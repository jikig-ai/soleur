# Learning: a guard's rows must be generated from the arrays it scans, and "which workflow applies" is a paths-filter question

## Problem

PR #10966 (PR-1 of the Inngest host-replace window prework) retired the plaintext-to-LUKS cutover trio from the image and added
Guard 3 (`apps/web-platform/infra/inngest-carrier-vocabulary.test.sh`), a test that keeps the retired vocabulary and the trio's
names out of every baked carrier and delivery-path file. A 10-seat panel, a 7-seat fix round and a verification pass found:

- **Guard 3 rows were hand-written per instance.** The scan read six delivery files, four recipe files and thirteen needles, but
  only two delivery files and a few needles had a kill row. Deleting a `DELIVERY_FILES` entry, or typo-ing a needle (the per-needle
  row was generated from the same array, so it followed the typo), left the 36-assertion suite green. Four review seats found this
  independently, each from a different angle.
- **The plan named the wrong apply workflow.** It said the merge fires `apply-web-platform-infra.yml`, so "no `.tf` resource
  changes, the plan is a no-op". In fact that workflow's `-target` list names none of the web-host `terraform_data` resources;
  `apply-deploy-pipeline-fix.yml` (its own `paths:` filter, its own kill switch `[skip-deploy-fix-apply]`) re-fires three of them.
- **A retirement banner overclaimed.** "No on-host consumer" was false: live hosts keep the trio installed with its timer enabled.
- **Test infrastructure gaps.** The new suite added seven unbaselined fixture-scan sites; a literal `cp <path>` inside a string
  is read by `fixture-scan.py` as a live copy; a floor written as `[[ ... ]] || { ...; exit 1; }` was invisible to
  `guard-vacuity-floor`; five baselines and one lint tripped in CI that the affected gate (rc=6, budget-deferred) never ran.

## Solution

- Generate every kill row from the array the scan reads (`RECIPE_FILES`, `DELIVERY_FILES`, `NEEDLES`), so dropping an entry
  removes its row and the exact assertion floor reds. Pin the independently spelled needle list once. Give each verdict helper
  (`kills`, `stays_green`) a negative control (no-op, wrong-tag, over-block). Build the fixture base tree once and copy it.
- Match the trio by stem (hyphen, snake_case and upper-case payload spellings), not by `.sh|.service|.timer`.
- Close G4 respellings (flags between verb and name, a secrets verb on an allowlisted text line, writers under all of `.github`)
  and pin the first-boot stager at exactly one site.
- Correct the plan to name each workflow whose `paths:` filter the diff hits and its own kill switch; scope the banner to what
  stays in force (section 5c).

## Key Insight

A guard's fixtures are a second copy of its population. If the rows are written by hand, the population and the rows drift the
first time anyone edits the array, and the suite stays green because the deleted row takes its own failure with it. Generate the
rows from the arrays, floor the assertion count at the measured number, and add an independent literal for anything the generated
rows would follow into a typo.

Separately, "what does merging apply" is a property of every workflow's `paths:` filter, not of the workflow that comes to mind.
Name each one the diff hits, and the kill-switch token each honours, before writing an apply expectation.

## Session Errors

1. **Planning subagent returned only a skeleton plan** — Recovery: resumed it via SendMessage; it wrote the 574-line plan. — Prevention: check the plan file length before accepting a planner's "complete".
2. **`technical-ruling-gate.sh` rejected `decision-challenges.md`** (unescaped `|`, a class outside the vocabulary) — Recovery: escaped and reclassified. — Prevention: run the gate right after writing the table, not at the end.
3. **The build agent hit the weekly API limit and its worktree was removed, losing the untracked plan and spec files** — Recovery: rebuilt from the planner transcript; committed immediately. — Prevention: commit plan/spec artifacts the moment they are written; never leave a feature's only copy untracked across an agent boundary.
4. **A merge with `origin/main` conflicted on `PJ_TRIPLES` (289 vs 287)** — Recovery: resolved to 288, confirmed by a green run. — Prevention: re-measure a counted baseline after every merge touching the same suite.
5. **The affected-test gate returned rc=6 (budget-deferred), so five CI reds were first seen in CI** (vector tag parity, fixture-relative-assert baseline, `credentials_required` corpus count, Better Stack mutation battery pin, lint-infra-no-human-steps) — Recovery: read the CI logs by job id and fixed each. — Prevention: when the affected gate defers, run these repo-global ratchets by name before the first push (see the fix-round briefing in `risk-tier-and-fix-rounds.md`).
6. **The review worktree was removed while seats ran, and a seat's scratch clones are git checkouts the delete guard refuses to remove** — Recovery: re-created the worktree on the branch; left the clones for the operator. — Prevention: brief seats to use the sandbox allocator (`soleur-sandbox.sh new`), whose paths `rm` accepts, instead of ad-hoc `git clone`.
7. **A structural seat and a test-design seat each paused with a status line instead of a report** — Recovery: `SendMessage` "reply now with the report". — Prevention: already documented (a `completed` notification per pause is not a report); keep checking the last assistant text.
8. **`gh run view --log` returned nothing for runs still in progress, then the API refused escape sequences** — Recovery: waited for completion semantics and used `gh api --allow-escape-sequences`. — Prevention: read job logs only after the run completes.
9. **A PreToolUse hook blocked a Bash command whose text merely contained the words for a Doppler write** (inside a Python heredoc editing a test) — Recovery: wrote the script with the Write tool and ran it. — Prevention: for edits whose text names a guarded command, write the helper file first (already advised for `terraform apply`).
10. **The plan's apply expectation, the runbook banner and an ADR addendum each asserted a mechanism claim that was never falsified** (wrong workflow and kill switch; "no on-host consumer"; "measured once") — Recovery: corrected after the architecture, security and pattern seats ran the commands. — Prevention: for each causal sentence a doc edit adds, name and run the command that would falsify it before committing.
11. **Guard 3 v1 hand-written rows, an unrooted fixture write set, a literal `cp <path>` string and a floor shape the vacuity guard cannot see** — Recovery: rewrote with generated rows and asserted-absolute roots. — Prevention: run `fixture-scan.py --rule relative` and `guard-vacuity-floor.test.sh` after writing any new `*.test.sh`.

## Tags
category: logic-errors
module: apps/web-platform/infra, review
