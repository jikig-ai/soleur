# Learning: retiring a gate arm trips the parser, the plan_only path and four CI ratchets

## Problem

PR #11432 (Ref #11194) retired the plaintext-volume arms from the git-data host replace/birth gates and added a fail-closed interlock (`git_data_plaintext_id_interlock`) that refuses unless `git_data_volume_id` in the module call is `""`. Review and CI found a chain of defects, each in a place the diff's own suites did not look.

## Root cause

1. **The interlock parser failed open.** A brace inside a quoted string, and a `${...}` / `%{...}` interpolation inside the module call, shifted its brace depth so a nested `git_data_volume_id = ""` passed as the top-level one (reproduced PASS; `terraform validate` confirmed the effective value was non-empty). Fix: blank quoted strings first, then ABORT on any `${` or `%{` inside the module block.
2. **`plan_only` cannot reach a verdict past a stale rung-2 hold.** The `Rung-2 rehearsal interlock` step in `git_data_host_replace` / `git_data_host_create` runs before the new interlock and has no `plan_only` handling, so the documented owner step "run `plan_only` first" is unreachable until a fresh paid rehearsal lands. Tracked in #11460; documented, not changed (CTO ruling).
3. **Prose carried stale or wrong claims**: "both volumes / 5-target / three interlocks" survived the retirement; the owner sequence said `infra-privileged` needs reviewer approval (it has no reviewers; the reviewer-gated step is the rehearsal on `web-platform-infra-apply`); a floor compare said 103 while the message said 111.
4. **A draft PR's aggregate `test` check is RED by design** (ADR-276 Option R: heavy legs are skipped on a light draft), so "CI green" requires marking the PR ready.
5. **Four ratchets the selected suites could not see**: `workflow-file-size` (494,166 B vs the 490,000 gate; fixed by relocating comments verbatim to the job-rationale runbook), `lint-infra-no-human-steps` (ADR/plan/tasks lines), `affected-index-ratchet` (the readiness suite reads `apps/web-platform/infra/git-data.tf` but did not declare it in `scripts/lib/test-affected-paths.sh`), and `markdown-lint` (editing an old file made its five pre-existing MD046 indented blocks and one MD012 blank this PR's findings).

## Solution

- Interlock: strings blanked, interpolation aborts, rows added for each shape, and a mutant row proving deleting the check reds the suite.
- Declared `git-data.tf` for the readiness suite; disabled MD046 for the relocated-comments file and dropped the blank line.
- One identical owner-sequence text in ADR-239, the birth runbook and the cutover runbook; dated records restored under a Superseded banner rather than edited.

## Key insight

A fail-closed check is only as closed as its parser: enumerate the constructs the language lets a value hide in (strings, interpolation, heredocs) and make the parser ABORT on any it does not model. Separately, retiring an arm moves counts, byte sizes, declared read-paths and lint scope: run the ratchets that count the whole tree, not only the suites that reference the changed files.

## Session Errors

1. **Workflow over the 490,000-byte gate (494,166).** Recovery: relocated comments verbatim to the rationale runbook. Prevention: check `wc -c` on `.github/workflows/apply-web-platform-infra.yml` before adding any workflow text; keep new text under 100 bytes net.
2. **`lint-infra-no-human-steps` flagged ADR/plan/tasks lines.** Recovery: wrapped them in `lint-infra-ignore` regions. Prevention: run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` before the first push.
3. **Interlock parser fail-open on brace-in-string and on `${`/`%{`.** Recovery: blank strings, abort on interpolation. Prevention: fixture the hiding constructs for every HCL parser row.
4. **Owner sequence named the wrong approval gate for the replace job.** Recovery: read the environments' reviewer config and rewrote all copies. Prevention: verify an approval claim against `gh api repos/.../environments/<name>` before writing it.
5. **Floor compare and message disagreed (103 vs 111).** Recovery: both set to 111. Prevention: derive the message from the compare variable.
6. **`affected-index-ratchet` new-pair on `git-data.tf`.** Recovery: declared the path in `scripts/lib/test-affected-paths.sh`. Prevention: when a suite feeds a tracked file to the SUT, declare it in the same commit (the gate's failure text prescribes this).
7. **`markdown-lint` on a file with pre-existing violations.** Recovery: file-level MD046 disable plus one blank line removed. Prevention: run `markdownlint-cli2` on every changed `.md`, including old ones.
8. **Editing the PR body re-triggered `pull_request` runs and cancelled 11 in-flight checks.** Recovery: waited for the new run. Prevention: write the PR body once, before the last push, not between pushes.
9. **`gh pr edit` ran from the scratchpad directory ("not a git repository").** Recovery: re-ran from the worktree. Prevention: never `cd` out of the worktree in a compound command.
10. **GitHub API rate limit (5,000/hr, shared with agents) hit while polling job logs.** Recovery: backed off with a single snapshot monitor. Prevention: one monitor per PR, 45 s+ interval, fetch job logs once.
11. **Stop hook blocked a closing line that promised an action.** Recovery: ended with an explicit `Paused:` sentence. Prevention: end every waiting turn with `Paused:`/`Blocked:`.

## Tags

category: workflow-issues
module: git-data-host-replace, ci-ratchets
