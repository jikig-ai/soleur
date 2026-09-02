---
title: "I committed the defect class I was closing, eleven times"
date: 2026-08-27
category: test-failures
module: test-all / fixture-guards
issue: 7652
pr: 7702
tags: [guards, vacuity, mutation-testing, false-red, false-green, shared-state]
---

# I committed the defect class I was closing, eleven times

## Problem

#7652 is one sentence: **a claim outran its check.** `scripts/test-all.sh` printed
`[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` while inspecting only `git rev-parse HEAD` and
`git status --porcelain` — blind to the shared-config write that actually happened. Separately,
`git -C ""` does not error; it silently operates on the current directory, so a fixture helper
called with an empty argument writes into the caller's repo.

Both halves were fixed. Then seven review agents found **eleven fresh instances of the same class
inside the fix**, four of them merge blockers. That is the finding worth keeping — not the fix.

## What recurred, and why the fix is where it recurs

| Instance | Shape |
|---|---|
| Config dimension unconditionally FATAL | The claim ("a suite wrote") outran the check (a SHARED store changed) |
| Manifest carried, never consulted | The mechanism existed; nothing read it |
| Both-boundaries-unmeasured stayed silent | A clean signal emitted over a check that never ran |
| REPORT header named a ref event for config REPORTs | Message named a cause the code did not measure |
| Attribution pointed at a preamble that reads 0 when it matters | The plan **warned about this exact number** |
| "every suite before it completed without changing the tree" | A universal claim over entities never measured |
| Scanner guard matched comments | A guard satisfied by prose about the guard |
| Guard C compliance = `grep 'cp .*repo-write-boundary'` | Same, one token over — in the fix for the first one |
| Six copies each called themselves "the CANONICAL copy" | Six of seven were false |
| Recovery steps cited SHAs no longer printed | Instruction outran the output |
| First stale-claim sweep marked 1 block, left 7 twins | Correction outran its own reach |

The mechanism is not carelessness. **A fix is written while holding the defect in mind, so its
verification inherits the defect's framing.** The author is thinking about the thing being closed,
not about the new prose, the new anchor, or the new fixture — and those are written fast, because
they feel like bookkeeping rather than authorship.

## Key insight — batteries are armed against deletion and unarmed against shrinkage

The single most useful sentence from the review: *"this battery is well armed against deletion and
neutering, and unarmed against SHRINKAGE."*

A shrink-only baseline detects **growth** only. Measured green before the fix round:

- cutting the write-verb list to the five verbs the fixtures exercised (−18 live sites)
- reverting the scanner corpus from `*.sh` to `*.test.sh` (−525 files)
- blinding the corpus walk to 1 of 901 files, while `FILES=901` still printed
- making a whole boundary dimension a constant
- dropping `--tags` from the refs dimension
- permuting the per-dimension next-action map

Every one is a **narrowing**, and narrowing is the direction a real edit takes. The fix is a
positive floor (`SITES >= N`), a **named member at its exact count** (a total cannot see one file
going to zero while another grows), and **one fixture per member** of any set the guard quantifies
over — never a sample.

## Three probes that were themselves vacuous

Caught only by running them, never by reading:

1. **`_repo_boundary_digest` ends in `| cut`.** A pipeline reports its *last* command's status, so a
   failing `sha256sum` returned 0 with empty output — and the up-front probe added to catch exactly
   that was vacuous. Before the fix: the manifest claimed `measured`, every digest was blank, and
   the classifier reported **every key in the shared config as DELETED**. A false-RED storm under a
   full-coverage claim.
2. **`strip_log_injection` is a stdin filter** (`tr | sed`), not a function taking an argument.
   Called with one inside a `while read` loop, it inherited the loop's herestring and consumed the
   entire remaining list — the first config key printed as the whole projection. A helper eating its
   caller's stdin, inside the redactor written to make the output safe.
3. **`$(git config --local --list -z)` strips NUL bytes.** The `-z` framing was destroyed, every
   entry collapsed into one blob, and the dimension reported a constant while blind to its own
   subject.

## The plan's primary mechanism was measured out — and the measurement is the deliverable

The plan pre-committed a rule *before* measuring: CWD isolation is primary if the breakage set is
≤40 suites **and** each break is a path-resolution fix. Measured: 170 of 177 `run_suite` call sites
pass relative paths, and **64 suites read the live repo on purpose** — including the guard this
issue's first half shipped. The rule fired against its own preferred mechanism.

Two things made that work: the rule was written down *before* the number existed, and the rejection
reason is **fail-open risk**, not cost (per-suite opt-in isolation needs 374 judgement calls whose
wrong answer is silent). A pre-committed rule is what lets a measurement overrule a plan without
re-litigating it.

## Validated in production conditions, unprompted

The final shard run produced the exact event the harm partition was written for. Four sibling
worktrees moved their branches mid-run:

```
=== 342 suites: 340 passed, 0 failed, 0 killed, 2 skipped,
    4 repo observation(s) (REPORT — not a verdict, exit code unchanged) ===
```

`rc=0`, zero FATAL. **Before the partition, each of those four would have printed
`A SUITE WROTE TO THE LIVE REPOSITORY` and incremented `failed`** — the gate would have gone red
four times on a completely healthy run, on a 22-worktree machine. Not a projection from a probe:
what the shipped code did, on a real run, without being staged.

## Prevention

- **On a fix PR, review the new ASSERTIONS before the new code.** They are written after the tests
  and nothing forces coverage for them. Litmus per assertion: *name an implementation a reasonable
  engineer might write next that satisfies this while violating the property.*
- **Enumerate a guard's AXES, not its mutation count.** N mutations of one shape is one mutation.
  The axes that get missed: fixture DIRECTION, member CARDINALITY (1-of-1 cannot be told from
  all-of-1), population GROWTH (add a member, don't only edit one), corpus SELECTION, and the
  assertion-count FLOOR itself.
- **Floors exact, never with slack.** 17 against 21 arms left four must-trip arms deletable.
- **Sweep by CLAIM, not by file.** The first sweep marked one block and left seven twins — including
  a Files-to-Edit row promising a change the PR does not make.
- **A guard that measures a SHARED store needs a harm partition on every axis it reads.** Fixing the
  ADD axis and leaving DELETE and ref-creation collapsed is fixing an instance, not a class.
- **Run the cheap deterministic gate before the panel.** `shellcheck -S warning` found a
  captured-but-never-asserted verdict variable that no agent flagged, in seconds.

## Session Errors

*24 inventory items, consolidated into 15 entries: entry 9 enumerates the nine boundary/scanner
defects introduced by the fix rather than listing them separately, because they share one cause and
one prevention. Nothing from the inventory is dropped.*


1. **Closed #7652 on a truncated comment read.** `gh issue view --jq` piped through `head -60` cut
   3 of 5 comments; the newest filed two further in-scope instances. — *Recovery:* reopened with a
   correction comment. — **Prevention:** when a decision turns on an issue's discussion, read the
   comment COUNT first and assert you have all of them; never let a pager silently truncate input to
   a close/abort decision.
2. **Heredoc wrote to a non-existent scratchpad dir**, so `gh issue close --comment "$(cat …)"` ran
   with an empty body. — *Recovery:* `mkdir -p`, posted separately. — **Prevention:** `mkdir -p`
   before any heredoc into a scratch path, and never nest a file-producing heredoc in the same
   command as the consumer that would be denied without it.
3. **`local name="${1:?}" d="$TMP_ROOT/$name"`** — bash expands every word of a `local` before
   assigning any. — *Recovery:* split into two statements. — **Prevention:** one variable per
   `local` whenever a later one references an earlier.
4. **`$(git config --list -z)` strips NUL bytes.** — *Recovery:* stream from a process substitution.
   — **Prevention:** never capture NUL-framed output in a command substitution; bash warns and the
   warning is easy to skim past.
5. **manifest/body namespace collision** — `refs\tmeasured` parsed as a ref named `measured`,
   producing a phantom DELETED+created FATAL pair. — **Prevention:** give metadata rows their own
   prefix when they share a stream with data rows.
6. **The manifest global was lost through command substitution.** Every real caller does
   `before="$(_repo_state)"`. — **Prevention:** if a function's output is consumed via `$( )`, it
   cannot also communicate through globals — return everything in the payload.
7. **An arm anchored on the bare token `REPORT`** matched unrelated prose in the same file and
   passed vacuously. — **Prevention:** `cq-assert-anchor-not-bare-token`; anchor on a phrase a
   comment cannot produce.
8. **Fixed 2 of 3 sandbox relocators.** The third failed all 36 of its arms with `rc=2` — my own
   refusal code, which looks nothing like a missing file. — **Prevention:** when a finding names an
   instance, enumerate the population from the tree and put the enumeration in a test.
9. **Nine boundary/scanner defects introduced by the fix** (config partition, manifest pairing,
   fail-open `elsewhere`, `awk -v` escapes, credential-in-key, comment-matching guard, over-widened
   verbs, over-widened Guard C, three-way-broken parity extraction). — **Prevention:** the
   review-the-assertions-first rule above; all nine were in verification code, not in the fix.
10. **Fixed the scanner's comment-blindness with no arm.** Re-narrowing it left the suite green. —
    **Prevention:** every review-driven fix needs its fixture in the same commit, mutation-proven.
11. **`worktree\s+\w+` matched the READ `worktree list`.** — **Prevention:** when widening a
    matcher, ask what it now accepts that it did not; the error lands where no fixture covers.
12. **The tag fixture broke on the operator's global signed-tag config.** It went RED rather than
    passing vacuously. — **Prevention:** pin fixture-relevant git config explicitly and assert the
    precondition, so a break reads as a fixture error, not a phantom regression.
13. **The first AC11 claim over-stated.** "All four dimensions unchanged" holds only on a quiet
    machine; the boundary measures a SHARED store. — **Prevention:** state acceptance criteria over
    what the system can guarantee (no FATAL; every delta classified) rather than over equality.
14. **The first stale-claim sweep marked one block and left seven twins.** — **Prevention:** index
    corrections by the CLAIM and grep its paraphrases; a residual-zero count over the new text is
    structurally blind to the sites still carrying the old.
15. **`gh issue create` denied for a missing `--milestone`** (hook). — **Prevention:** already
    hook-enforced; no change needed.
16. **I built the harm partition for `config` and never swept it to `refs`, its sibling dimension
    in the same function.** The ship-gate battery then passed all 342 suites and still exited 1:
    six sibling ref moves — a `git push -u`, a `cleanup-merged` deletion, a `git fetch` advancing
    `main` — were each unconditionally FATAL. The proof was sitting in my own log, one screen
    apart: `[config] branch.feat-next16-7591.merge was ADDED` classified REPORT, and
    `[refs] refs/heads/feat-next16-7591 was created or moved` classified FATAL — **the same event,
    two dimensions, opposite verdicts.** I had even written the rationale into arm 30's comment
    ("the config dimension carries the SAME sibling side effect") without asking which other
    dimension carried it too. — **Prevention:** when a fix introduces a CLASS distinction (harm
    partition, severity tier, attribution rule), enumerate every dimension the enclosing function
    already iterates and state the verdict for each, including "unchanged, because X". A partition
    added to one member of an enumerable set is a sweep, not a local edit — the same shape as
    `hr-write-boundary-sentinel-sweep-all-write-sites`, one level up from write SITES to verdict
    CLASSES. The tell that it was a sweep was visible at authoring time: the function's own
    `for dim in head worktree` loop names the set.
17. **A false RED is the same defect as a false GREEN, and I nearly shipped one into the gate whose
    subject is not over-claiming.** The refs dimension asserted an attribution — "a suite wrote to
    the live repository" — that the run could not support, because non-own refs live in the SHARED
    bare repo that 21 sibling worktrees write to concurrently. That is AP-021/ADR-166 (never name a
    cause the run measured) pointed at severity instead of at prose. — **Prevention:** for any
    dimension read from a store this process does not exclusively own, ask "who else can write
    here, and can this run tell them apart?" before choosing FATAL. Where attribution is impossible
    the honest class is the reported-but-not-counted one; where it is possible (single-worktree
    checkout — every CI runner) the strong class stays. Gate the softening on the measured
    condition, never on a blanket widening: arms 42-43 exist so that sibling presence can never
    launder HEAD, our own branch, or a tag.
