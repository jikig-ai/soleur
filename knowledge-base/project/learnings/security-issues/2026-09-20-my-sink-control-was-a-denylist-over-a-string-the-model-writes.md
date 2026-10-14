---
title: "My sink control was a denylist over a string the model writes"
date: 2026-09-20
category: security-issues
issue: 8427
pr: 8428
tags: [sink-controls, denylist, telemetry, redaction, mutation-testing, review-panel, adr-211]
---

# My sink control was a denylist over a string the model writes

## Problem

`cron-compound-promote`'s `checkDiffPaths` had SIX conditions all returning the
literal `underivable`, so a weekly refusal told an operator that path derivation
failed and nothing about why. Splitting the enum was correct and easy. Carrying
git's `detail` string to the outcome marker alongside it was neither, and I did
not find that out — a ten-seat review panel did.

## Key Insight

**A control over attacker-chosen text is a denylist no matter how it is
spelled, and its bound is whatever shape you failed to imagine.**

`classifyPaths` collapsed path-shaped tokens to a fixed vocabulary, and its doc
comment claimed it reduced "a model-controlled 200-character write into a
third-party processor to a few bits". `PATH_TOKEN_RE` required a `/`.

A file created at the repository **root** has no `/`. `git diff-index` emits
paths unquoted, spaces included. So a proposal creating

```
ALERT soleur cron compromised contact ops at evil-host now.md
```

yields `detail = "A ALERT soleur cron compromised contact ops at evil-host now.md"`
and the classifier is the **identity function** on it. Verified end to end
against git 2.55.0: `git apply --cached` rc 0, status `A`, path relayed
byte-for-byte into the marker. At ~198 characters per refused cluster and 20
entries, ~3,960 model-chosen characters per weekly run into Better Stack — a
processor for which the Vendor Mapping records no executed Art. 28(3)
instrument.

Every fixture in my suite used a slash-bearing path. The suite was structurally
blind, so it was green, and its green meant nothing.

**The repair was not a better regex.** ADR-211 already says it: at the producer
the STRUCTURE still exists, so an allowlist is available and is strictly better.
`reason` is chosen by our code. `diff_*` are numbers and booleans. Those are
decidable by construction. `detail` was the one field that was not, so it is
gone — and the full diagnostic still reaches Sentry, redacted and capped.

Dropping it dissolved four findings at once, which is the tell that the field
was the problem rather than its transform:

| dissolved | was |
|---|---|
| the classifier hole | above |
| a ReDoS | `X*/X*` backtracks quadratically — 13.5 s at 64 KB × 20 entries ≈ 60 s of event-loop stall |
| Vector's 10,000 B slice | 5,515 B now; 9,755 B (+245 headroom) with ASCII `detail`; **21,755 B** with 200 astral code points, because the cap counted code points |
| ~1.28 MB of Inngest step state | `detail` rode on a `step.run` return value |

## Solution

Delete the field. Keep the enum split and `diffShape`, which are what actually
close #8427. Revert the stderr bound. Fix the three predicates and the census.

## Second insight: a justification can be right about one mechanism and still unreachable

I raised the stderr bound 4096 → 64,000 so that "redaction's `MAX_INPUT_LEN` is
the only cut before redaction". Two independent errors in one sentence:

1. `MAX_INPUT_LEN` **is** 64,000 and its guard is `s.length > MAX_INPUT_LEN`.
   A string cut to exactly 64,000 never truncates, so the `[…]` marker it
   appends is unreachable — **the raise made my slice the silent cut it claimed
   to remove.**
2. It bought nothing anyway. Every consumer head-anchors at 200 characters, so
   the straddling credential could not have reached a sink at either bound.

I reasoned about the redactor's window without checking what its consumers keep.
The gate is one line: for a claim about a boundary, read BOTH sides of the
comparison and BOTH ends of the pipe.

## Third insight: a count in a legal register is a falsifiable claim

The Article 30 cell said "six mutants, all killed" against a guard with **ten**
rows, two of which the plan declared and I never implemented. The corpus already
records that *claims about people* fail because nothing greps them; this is one
step over — a claim about a COUNT **does** have a file to grep, and nobody
grepped it. The mechanism claims in the same cell were cross-checked against
code and survived. The arithmetic did not.

## Fourth insight: a predicate can be wrong in the way its own field name denies

All three `diffShape` predicates passed a green suite because every fixture was
the shape I was thinking of:

- `diff_fenced` anchored at index 0 skipped whitespace but **not a prose line**,
  so `"Here is the patch:\n```diff"` returned `false` — the dominant LLM failure,
  and the field's entire reason to exist.
- `diff_header_pair` fired on diff CONTENT (a removed line beginning `-- `
  renders `--- `). Adjacency does not separate those, because content lines sit
  adjacent too. **Position does**: a header pair precedes the first hunk.
- `diff_hunk` required a space in the third character, so a combined `@@@` hunk
  read as hunk-less.

## Fifth insight: a census can claim a multiset and be a set

My header said "site-keyed multiset, because a plain set tolerates changing ONE
of two shared-literal sites". The assertions were a set comparison plus one
hardcoded count for one literal — leaving `structural-op`'s THREE sites
unpinned. The header was right about the hazard; the code did not implement it.
Read what a guard ASSERTS, not what its comment claims it asserts.

## Prevention

- For any control over model- or user-chosen text, write the **complement** of
  the match set and ask what lives there. If the answer is "arbitrary bytes",
  it is a denylist — move the decision to the producer where the structure is.
- Before claiming a boundary interacts with another, read both comparison
  operators and both consumers. `>` vs `>=` decided this one.
- Any count written into a durable record (a legal register, an ADR, a runbook)
  gets re-derived at write time. It is greppable, so grep it.
- Sweep fixture SHAPE, not fixture count: for each predicate, name an input the
  producer can emit that no fixture instantiates.
- Run the deterministic lints and the cheap mechanical gates BEFORE the panel —
  they have disjoint yields and the panel costs ~1.1M tokens.

## Session Errors

1. **Shipped a security control that did not hold.** `classifyPaths` was the
   identity function on any path without a `/`. **Prevention:** see Key Insight —
   write the complement of the match set before writing the control.
2. **Made a ReDoS reachable by my own bound raise.** **Prevention:** a bound
   raise on attacker-influenced input is a performance change; measure the
   regex at the new bound.
3. **Declared the Vector slice in the plan as AC18/guard 23 and never
   implemented it.** The plan's own #1 finding shipped as prose.
   **Prevention:** a plan AC that names a numeric budget must land as an
   assertion in the same PR, or be struck from the plan explicitly.
4. **Three `diffShape` predicates wrong in ways their field names denied.**
   **Prevention:** per predicate, name an input where its answer differs from
   what the field name would make an operator conclude.
5. **Census claimed a multiset and was a set.** **Prevention:** mutate a
   shared-literal site and confirm RED before believing a multiset claim.
6. **Wrote "six mutants, all killed" into the Article 30 register against a
   ten-row guard.** **Prevention:** re-derive every count at write time,
   especially in records a regulator reads.
7. **My git shim recursed.** It `exec`'d `git` by name through the still-shimmed
   PATH; four unrelated must-PASS rows timed out at 16 s each, and vitest's
   timeout cut the promise before `.finally()` restored PATH, so the pollution
   outlived the row. **Prevention:** resolve the real binary to an ABSOLUTE path
   before mutating PATH, and use try/finally inside an async IIFE rather than
   `promise.finally()` so a timeout still unwinds.
8. **Wrote `.diff_fenced // "-"` in a jq projection.** jq's `//` fires on
   `false` as well as `null`, so every `false` rendered identically to absent —
   and `false` is meaningful for all three booleans. **Prevention:** never `//`
   a boolean in jq; use an explicit `== null` test. Now written into the runbook.
9. **My jq extractor grabbed the wrong fenced block.** It took the FIRST
   `jq -R -r` in the runbook (an unrelated recipe), exited 0, and printed
   nothing — the instrument answered instead of erroring. **Prevention:** assert
   the extraction matched exactly one candidate before running it.
10. **Read Better Stack silence as absence.** A raw-SQL probe hits only the hot
    window (~3.4 h when measured); the run was 6 h old. The runbook already says
    mode 2 UNIONs the S3 archive and I did not read it first. **Prevention:**
    before reading an empty telemetry result as evidence, check the table's
    oldest row.
11. **Left the SUT mutated after a battery.** The restore used a relative path
    after a `cd ..` that landed in `apps/`, so `cp` failed and the mutated file
    survived. Caught only because I verified against the committed state rather
    than against my own pristine copy. **Prevention:** echo the backup path,
    restore with absolute paths, and verify with `git diff --stat` against HEAD.
12. **Scored a bad mutation as a survivor.** My first discriminator-shadowing
    mutant inserted the keys before the spread while LEAVING the after-spread
    copies, so the property still held and the row read as an equivalent mutant.
    **Prevention:** a mutation that ADDS must also REMOVE; assert the mutated
    file differs in the way intended, not merely that it differs.
13. **Ran one combined panel instead of the design-validity pass first.** I
    noted the deviation and it still cost: three seats spent their whole budget
    analysing machinery deleted an hour later — the exact waste the design-risk
    gate exists to prevent. **Prevention:** on a `design-risk` PR the serial
    pass is cheaper than it feels; take it.

## Related

- ADR-211 (producer/sink posture — the rule this PR relearned the hard way)
- #8441 (the gdpr-gate canonical regex has no egress surface, so it never fired
  on a change about egress)
- #8281 / #8293 (the tracker this unblocks; G-b adjudicated MET 2026-09-20)
- `knowledge-base/project/learnings/2026-09-04-every-fix-reintroduced-the-class-it-was-fixing.md`
