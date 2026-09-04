---
title: "Every defect this session was in the verification, not the fix — and each round's fix introduced the next round's"
date: 2026-09-04
category: workflow-patterns
tags: [review, guards, mutation-testing, verification, observability, compliance]
issue: 7710
pr: 7841
---

# Every defect was in the verification, not the fix

## Problem

`#7710`: the gdpr-gate refused before scanning anything, printing `rules 117 days
stale` and `POSTURE_FAIL` with no evidence a scan had occurred. The fix was
small in principle — restore the writer that advances `last-verified`, and give
the path scan an output of its own.

The implementation was straightforward. **Twenty-one defects were found in it,
and the overwhelming majority were in the machinery built to verify it rather
than in the thing being verified.**

## The dominant pattern

Round one's fix introduced round two's defect, three times over:

| Round one shipped | Round two found |
|---|---|
| Heartbeat keyed on `res.merged`, to fix "green with no artifact" | The direct merge normally FAILS and auto-merge lands the PR ~60s later — measured on three sibling-cron PRs — so it would page on **every healthy run**. A monitor that pages on the healthy path is muted within two cycles: the exact condition that let #7710 run 117 days |
| A 21-day write suppression, to cut needless bot PRs | It made the follow-through probe's 14-day window **shorter than the producer's own write interval**, so a healthy pipeline would report "the writer is not advancing the field" |
| `registryCount` from declared records, to close a tautology | The declared view shares its record-opener predicate with the emitted view, so deleting an *opener* shrank both together and the conjunct held at 7 == 7 with a record lost |

Each fix was correct about the defect it named and wrong about the one it
created. The generalisable form: **a fix is written while holding the old bug in
mind, so its verification inherits that framing and pins the shape of the old
bug rather than the property.**

## What actually caught things

Instrument yields were **disjoint**, and no instrument found more than a third:

- **`shellcheck`** — 1 finding, and it was the highest-value cheap one: a bare
  `SC2034` unused-variable warning on a parity check declared in #3541 and never
  written. A captured-but-never-asserted verdict.
- **`semgrep`** — 0 findings, verified non-vacuous (79 rules, 2 files, 100% parsed).
- **Repo lints** — `lint-orphan-test-suites` correctly refused a double
  registration I had just created.
- **The agent panel** — the two P1s that mattered most (the inverted heartbeat,
  the branch-prefix collision), each found independently by two agents.
- **Mutation testing** — found what the panel did not: three guards that could
  not fail, and one of my own new assertions that survived its own mutation.

Running the cheap deterministic gates BEFORE the panel is worth it: they cost
seconds and their findings do not overlap with the panel's.

## Specific traps worth carrying forward

**A grep assertion is satisfied by the comment explaining it.** Five instances
in one session, three of them written *after* I had fixed an earlier one. The
moment a task requires both "assert X" and "document X", they collide. Anchor on
something a comment cannot produce — a line-anchored assignment, a call shape —
never a bare literal.

**An assertion's window must be wider than the prose inside it.** A
`catch[\s\S]{0,200}` proximity window was shorter than the explanatory comment I
had just added to the same block, so it never reached the mutated line. Anchor on
the block, not on proximity.

**A slice that runs to EOF can be satisfied by the wrong call site.** A
`mergeMode: "direct"` assertion sliced from the attest step to end-of-file also
swallowed the drift route's identical option.

**Count live, not from the source of truth you happen to have open.** The ruleset
count was wrong twice in opposite directions — once by counting a ruleset that
governs a *different repository*, once by counting Terraform instead of the repo.
The live API returned three, including one with no Terraform file at all.

**A claim inherited from the plan is a claim to verify.** "ADR-121 and ADR-186
each place that substitution in a rejected-alternatives table" was fabricated;
both have zero hits for identity or checksum. It shipped because the plan said
it and the reasoning around it was sound.

**A guard that asserts absence needs its own floor.** The glob-liveness suite's
skip branch called `print_results` with no floor, so in CI — where lefthook is on
no runner's PATH — it exited 0 having asserted nothing. Guard 2's second
chokepoint had never run.

**A single fixture cannot see a set shrink.** Deleting 10 of 15 lefthook globs —
every API-route and SQL-migration entry — left the suite green, because the one
staged fixture still matched a surviving glob.

**The honest number is the one that blocks you.** `net-issue-flow` initially
PASSED at +0 because a filed issue cited the originating issue rather than the
PR, which is #7759's exact blind spot. Correcting the body made the gate see two
filings and block at +1. The under-count was the comfortable answer and it was
wrong.

## Prevention

- On a fix-shaped PR, **review the new assertions before the new code.**
- For every guard, ask: *name an implementation a reasonable engineer might
  write next that satisfies this while violating the property.*
- Mutate each review-driven fix back out and confirm the suite reds — a
  review-driven fix is exactly as unpinned as the blind spot it closed.
- Run `shellcheck`, `semgrep` and the repo lints before the panel.
- Never read a verdict through a pipe: `cmd > log; rc=$?` — `EXIT=$?` after
  `| tail` reports `tail`'s status, which reported a **failed commit as
  successful** twice in this session.

## Session Errors

**Pipe-masked exit codes (twice).** `EXIT=$?` after `| tail` reported `0` for a
commit that markdown-lint had blocked, and again for a rejected `git push`. —
Recovery: re-ran with an explicit `rc` capture. — Prevention: never place `$?`
after a pipeline whose last stage is a formatter.

**A backgrounded command's output swallowed by `| tail`.** The pipe buffers to
EOF, so the worktree-create log read 0 bytes until it exited. — Prevention:
redirect to a file, then read the file.

**A docstring orphaned onto the wrong function** by my own insertion; `tsc`
cannot see comment placement. — Prevention: when inserting before a symbol,
check whether the anchor has a docstring above it.

**Five grep-assertion/comment collisions.** — Prevention: anchor on syntax.

**A fabricated ADR cross-reference carried from the plan.** — Prevention: run the
falsifying command for every causal claim the prose adds.

**A ruleset count wrong twice, in opposite directions.** — Prevention: count live.

**A gobwas double-star learning generalised to single-star.** Shipped a no-op glob, a false
comment, and a customer-shipped false claim. — Prevention: measure the matcher.

**An inverted heartbeat.** My own round-one fix keyed the health signal on
`res.merged`, which is `false` on every healthy run of this repo's direct-merge
path. — Recovery: redesigned onto observed artifact age. — Prevention: for every
new gate, state in one sentence what it reports on the HEALTHY path.

**A probe window shorter than its producer's write interval.** My 21-day write
suppression made the 14-day follow-through probe report a healthy pipeline as
broken. — Recovery: widened to 30 days and added a second PASS arm. —
Prevention: when adding a suppression, re-read every consumer's window.

**A CI hard-fail keyed on a binary no runner has.** `SOLEUR_REQUIRE_LEFTHOOK`
would have redded every PR. — Recovery: caught pre-push; moved to a dedicated
path-filtered job that installs lefthook. — Prevention: name the environment a
new gate ships into before making it blocking.

**An assertion window narrower than the comment inside it.** A
`catch[\s\S]{0,200}` proximity slice could not reach the line it was meant to
pin, and survived its own mutation. — Recovery: re-anchored on the block. —
Prevention: mutate every new assertion before trusting it.

**A gate that passed because my own filing cited the wrong number.** The
`net-issue-flow` check read zero filings because the issue body cited the
originating issue rather than the PR — a live instance of #7759. — Recovery:
corrected the body; the gate then correctly blocked at +1. — Prevention: when a
gate returns the comfortable answer, reproduce its selector by hand.

**CWD drift mid-command** left a mutation restore unexecuted. — Prevention:
`cd <abs> && cmd` in one call; verify the file after any mutation loop.

**`git stash list` tripped the guardrail hook** (it is read-only, but the hook
matches the verb). — Prevention: use `git show <ref>:<path>`.

**`SC2066`** introduced by my own single-pattern loop. — Prevention: shellcheck
after every shell edit, not at the end.

**Forwarded from the planning phase (4):** a PreToolUse guard matching a token
inside a cited *filename*; MD038 on nested backticks; a grep *pattern* tripping a
Bash safety hook; and a `^  *field:` self-check that false-reported five missing
fields against a zero-indent YAML fence.
 — Prevention: run each phase's own linters against the artifact it just produced, and never put a search pattern inside a command a safety hook scans.

**A mistyped `bun test` path exits 0 and silently drops the file.** Verifying the
final counts before ship, `bun test <a> <b> <c>` reported `Ran 65 tests across 2
files` and exit 0 — the third path matched no test file, and bun reported that
only in a line above the summary. The dropped file was the largest suite in the
diff (91 tests), and `apps/web-platform` runs under **vitest**, not bun, so that
argument could never have matched. — Recovery: ran it under vitest (91 passed). —
Prevention: assert the FILE count, not just the pass count — `Ran N tests across
K files` where K is the number of paths you passed.

**Every suite count in the PR body was stale.** They were written mid-session;
seven of nine had since changed (39→37, 32→42, 38→43, 19→20, 5→6, 67→91,
239→112). Nothing compared them to reality until the pre-ship re-run. — Recovery:
re-ran all ten suites at the tip and replaced the prose with a table. —
Prevention: a count in a PR body is a measurement with a timestamp; re-derive
every one immediately before marking ready. Writing this into the body of a PR
whose subject is *a gate reporting a number nobody re-derived* is the session's
tidiest instance of its own thesis.
