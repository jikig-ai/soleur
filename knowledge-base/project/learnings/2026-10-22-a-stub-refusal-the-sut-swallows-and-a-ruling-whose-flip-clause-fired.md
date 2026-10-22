# Learning: a stub refusal the SUT swallows, and a ruling whose own flip clause had fired

## Problem

PR #10652 (Inngest LUKS arc items 6, 8b, C1; tracker #9927) shipped a green CI and a green self-run mutation battery, and an
11-seat review still found no P1 but about forty P2/P3 defects, nearly all in the PR's own verification and prose.

Four shapes, each reproduced by running it:

1. **A refusing stub is invisible when the SUT swallows the refusal.** The loader suite's `doppler` stub exits 64 on any
   unmodelled argv, to fail closed. The SUT reads with `legacy_hcloud="$(doppler ...)" || legacy_hcloud=""`, which turns that
   exit into an empty value. Adding a hidden second read (`doppler run -- printenv HCLOUD_TOKEN`) to the legacy arm left the
   suite at 117/117 green.
2. **A ruling carried a flip clause the PR's own measurement fired.** F6 said "flips if O10 lands first". The same PR measured
   O10 done (names-only listing), yet the code comment, ADR-241 amendment, runbook and test comments still described a
   "residual until O10". Five artifacts agreed with each other and contradicted the measurement.
3. **A no-op edit justified by a false causal claim, then pinned by a guard.** Ten guards were rewritten to `${HCLOUD_TOKEN:-}`
   "because an unset variable aborts under `set -u`", and fence rows R7a-c pinned the spelling. Every one of the ten steps already
   ran `HCLOUD_TOKEN="${HCLOUD_TOKEN:-}"` a few lines earlier. One grep refuted it.
4. **An instrument outlived its purpose.** The C1 probe carried a `SOLEUR-DEBT` deletion criterion ("delete once the finding is
   recorded") that its own PR satisfied, while keeping a committed path to an account-wide Supabase management token that
   reaches the production app project.

## Solution

- Log the stub's refusals where the SUT cannot swallow them (`MISS:` line appended to the calls file) and assert no `MISS` in the
  rows that matter. Re-ran the mutation: now red.
- Re-read every ruling's flip clause against the PR's own measurements before writing docs that cite the ruling. Rewrote the five
  artifacts to the measured fact; behaviour unchanged. Recorded in `decision-challenges.md` (CTO, 2026-10-22).
- Reverted the ten edits and R7a-c; `grep` for the pre-bind before adding an "unbound variable" guard.
- Deleted the probe, its suite and registrations on the CTO's ruling; the method lives in `measurements.md` and git history.
- Added a late dispatch re-validation (both helpers re-driven after every row) to the fence and luks suites, whose opening
  self-test alone let a mid-file `fail() { PASS++ }` print `N passed, 0 failed`.

## Key Insight

A verification artifact fails open exactly where the thing it checks is made quiet by something the author wrote for another
reason: the SUT's own `||` swallows the stub's refusal; a ruling's flip clause is quiet until a measurement elsewhere in the PR
fires it; a deletion criterion is quiet until the PR itself meets it. For each guard, stub or ruling the PR adds, ask what
would make it go silent, and run that.

## Session Errors

1. **`deploy-script-tests (1/4)` failed five attempts on an apt outage in a suite the PR does not touch.** Recovery: stopped
   rerunning, posted evidence on #9394, retried at the owner's request, attempt 6 passed. Prevention: after a leg fails the same way
   twice, read the failing step and stop; do not burn reruns.
2. **Three `gh issue create` calls were denied by the filing hook** (missing `--milestone`; then a `--body-file` that did not
   exist because the heredoc creating it sat in the same denied command). Recovery: write the body with the Write tool, then run
   `gh issue create` as its own call with a literal absolute path. Prevention: never create a `--body-file` in the same Bash call
   as the `gh issue create` that reads it.
3. **A `markdown-lint` CI failure (MD037) from nested bold markers I put in an Article 30 table cell.** Recovery: rewrote the
   marker, relinted. Prevention: run `markdownlint-cli2` over `git diff --name-only origin/main...HEAD -- '*.md'` before pushing,
   not over the files I remember editing.
4. **A DIRTY merge ref suppressed every `pull_request` workflow** (6 of about 80 checks ran, all green). Recovery: merged
   `origin/main`, resolved two doc conflicts. Prevention: read `mergeStateStatus` before reading a check set as a verdict (already in
   the review skill).
5. **A conflict-resolution script used an off-by-one index; a revert assertion expected 10 occurrences and found 11.** Both
   aborted on their own assertions with no damage. Prevention: keep assertions on counts and on marker positions in any one-shot edit.
6. **I wrote "failed six attempts" in the PR body before counting (five).** Recovery: corrected before merge. Prevention: derive
   every count in a PR body from a command run in the same turn.
7. **My launder-mutant for the luks suite tripped the opening self-test, so it did not exercise the new late check.** Prevention:
   place the mutation where only the new guard can see it.
8. **The Stop hook caught me ending a turn on an unkept first-person promise.** Recovery: ended with a `Paused:` sentence naming
   the wait. Prevention: if the next action is waiting on a monitor or a seat, say `Paused: <what>` rather than "I'll ...".
9. **The ten no-op guards and the F6 docs contradicting the PR's own O10 measurement** (shapes 2 and 3 above). Recovery: reverted
   and rewritten. Prevention: this learning (a review-skill bullet was tried and removed: it pushed `review/SKILL.md` 1,011 bytes over its body-budget ceiling, `lint-skill-body-budget.py`).

## Tags

category: workflow-issues
module: infra-credentials, review
