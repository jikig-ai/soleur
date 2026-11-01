# Learning: a step conclusion is not a measurement — record the verdict explicitly

## Problem

PR #11784 (#10111 Part 1, a scheduled real-SDK ask probe) let a push-triggered run skip the paid probe when
only package files changed and neither SDK version moved "since the last run that measured". Three review
rounds each narrowed what counted as "measured", and each narrowing still inferred it from something the
platform reports for its own reasons:

1. empty `outcome` output (a deliberate skip, a billing skip and a crashed run all read empty);
2. any completed, non-cancelled run (a billing-skipped run measured nothing);
3. the probe step's conclusion `success` or `failure` (round 2). `cmd_run` returns 1 for every non-pass
   outcome, so a CANT-RUN, a crash, a step timeout and a budget stop all concluded `failure` and counted as a
   baseline. After an SDK bump produced a blind run, a later package-only push diffed against it and skipped
   the bumped SDK entirely until the weekly cron.

Four of six fix-round seats and the architecture seat reported the same defect from different angles.

## Solution

Make "measured" a recorded fact instead of an inference. A dedicated final workflow step,
`Record that the probe measured` (`if: always() && (steps.probe.outputs.outcome == 'pass' || ... == 'fail')`),
succeeds only after an explicit verdict; the runner trusts a baseline run only when that step is `success`.
The workflow suite pins the step name against the runner constant, the exact `if:` string, its position after
the probe, and that it sets no `continue-on-error` and calls no `exit` (four mutants).

## Key Insight

A platform-reported status (step conclusion, job result, "completed") answers "did the machinery finish", not
"did the thing we care about get measured". When a later decision (skip the paid run) depends on the latter,
write the latter down as its own artifact, at the point where it is known, and select on that artifact. Every
inference tier costs a review round; the structural fix is a recorded state with three values at minimum
(measured-ok, measured-bad, not-measured).

Corollaries recorded in this PR:
- A guard that reads a string out of a file can be satisfied by a comment containing it: strip comments and
  anchor on the statement form. `sed ... | grep -q` under `set -o pipefail` is itself a flake (grep exits early,
  sed takes SIGPIPE, the pipeline returns 141): capture first, match second.
- A guard that restates a constant (`TWO_PASS_MIN = 2 * 8 * 180`) goes stale silently: read the case count and
  timer out of the source it protects (`RSAP_PROBE_TS`).
- A regex mask for a token family needs a left boundary only where benign prose can collide (`risk-ant-colony`
  contains `sk-ant-`); keep an unbounded form for the live-shaped variant (`sk-ant-api03-`).

## Session Errors

1. **Launched the full-battery gate (`scripts/test-all.sh`) by accident** — it refused rc 4 (sibling runs); the
   cause was `INDEX-UNBOUND` from flat-array registry entries. Recovery: removed the 8 flat entries, kept the
   per-suite block, ran a hand-derived consumer set. **Prevention:** use the per-suite `AFFECTED_*_PATHS` block, not flat entries, for a new suite; run named suites only.
2. **`fixture-relative-assert` ratchet red (7 unguarded scratch writes)** — Recovery: added the canonical
   `assert_fixture_dir` guard. **Prevention:** copy the guard when a runner writes under a `mktemp` dir.
3. **`pr-fanout-ledger` A5 red: note lacked `no cancel: <reason>`** — Recovery: reworded. **Prevention:** a ledger row for a non-cancelling workflow states the reason in that form.
4. **`guard-vacuity-floor` red twice** — a case counter bumped inside `ok()`/`no()` (tautological conservation),
   then the deferral ledger grew to 48. Recovery: moved the counter off the helpers; promoted the runner suite
   into all four `PROMOTED_FILES` regexes. **Prevention:** never count assertions inside the verdict helpers; promote a new suite in the same edit.
5. **`git commit` in a compound Bash call was blocked by a hook** (needs a literal absolute `cd`). Recovery: separate calls. **Prevention:** already hook-enforced; issue commits in their own call.
6. **Workflow `timeout-minutes` 30/40 below the in-step rerun worst case** — Recovery: restored 50/65 with the measured-run comment. **Prevention:** the workflow suite now derives the two-pass floor from the probe source.
7. **The baseline fix itself was wrong twice before the recorded-verdict design** (see Problem). **Prevention:** when a review finding says "X is inferred", fix by recording X, not by narrowing the inference.
8. **My new `sed | grep -q` guard under pipefail failed intermittently** (306/1 on one run, 305/0 on the previous). Recovery: capture then match. **Prevention:** run a new suite twice before committing, and never pipe into `grep -q` under pipefail.
9. **A mutant regex pinned the old step name** ("mutation did NOT land", rc=2) after I renamed the step. Recovery: updated the pattern. **Prevention:** grep the mutation table for the renamed literal in the same edit.
10. **A review seat sat idle about 4.5 hours "waiting on its monitor"** and reported only an interim. Recovery: `SendMessage` asked for the final report. **Prevention:** routed into `review/references/risk-tier-and-fix-rounds.md` ("Tell every seat to RETURN its report").
11. **Tool-output quota error (EDQUOT) on `/tmp/claude-1000`**, and a failed write into a log directory that did not exist (`/var/tmp/soleur-10111-final`). Recovery: retried; created the directory. **Prevention:** `mkdir -p` the log dir before use; keep tool output small (a repo-wide `git grep` printed 56 KB).
12. **The verification seat's report said "one P2" and "P2 – none"** — Recovery: treated as no P2 after reading the body. **Prevention:** none beyond reading the body; one-off.

## Tags

category: logic-errors
module: ci-workflows, real-sdk-ask-probe
