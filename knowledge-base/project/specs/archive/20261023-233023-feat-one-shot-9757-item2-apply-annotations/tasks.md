# Tasks: fix apply workflow restore-step annotations for exits 2, 5 and 78

Plan: `knowledge-base/project/plans/2026-10-23-fix-apply-restore-exit-annotations-plan.md`
Branch: `feat-one-shot-9757-item2-apply-annotations` | Umbrella: #9757 (Ref only, stays open) | Follow-up: #10932

## Phase 0: Baseline measurements

- 0.1 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (489,845 at plan time) and `git rev-parse origin/main`.
- 0.2 Check sibling PRs/worktrees editing the same workflow (#10928, #10678, #7390, `fix-apply-infra-workflow-size`) for byte-baseline and comment-block collisions, and check no run holds the `terraform-apply-web-platform-host` concurrency group before arming the merge.
- 0.3 Re-locate the restore step by its name `Restore production's pinned image set from GHCR` and the gate arms by `case "$restore_rc"` (never by line number).

## Phase 1: Failing tests first

- 1.1 In `tests/scripts/test-registry-d10-workflow-wiring.sh` add W9 as one aggregate assertion (amended in review to a behavioural run of the step body, see decision-challenges.md): header-derived codes (pattern `^#[[:space:]]+[0-9]+[[:space:]]+[A-Za-z]` up to the first non-comment line, floor >= 7, code 0 included), explicit arm line per code before `*)`, tokens (`locally` in arms 2 and 5, `trace` in arm 78, no `unenumerated` in an explicit arm). Add the comment that exit 1 is outside the population (#10932). Bump `EXPECTED_ASSERTIONS` to the measured count (expected 24).
- 1.2 In `tests/scripts/test-registry-pull-path-health.sh` derive the A2 loop's codes from the shared header extractor plus 1 and assert the output contains `exit $code` and does not contain `unenumerated`.
- 1.3 Run both against the unmodified workflow and gate; capture the RED output (W9 names 78 missing; the loop fails for 78) for the PR body.

## Phase 2: Core implementation

- 2.1 Gate `scripts/registry-pull-path-health.sh`: rewrite the `2)` and `5)` arms (two causes; arm 5 says "either"), add the `78)` arm with a one-line defense-in-depth comment.
- 2.2 Workflow restore step: rewrite arms `2)` and `5)` (read the engine's `::error::` line first; keep the rotate guard and the measure-first command scoped to the rejected-credential cause), add one-line `78)` (no `BASH_XTRACEFD`), keep every arm a single `::error::restore FAILED exit N` echo line, reword the three stale count comments.
- 2.3 Byte funding: move the `DO NOT reinstate "rotate ZOT_PUSH_*"` comment to a `###` subsection under `## registry_store_restore` in `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`, leaving a one-line stub with the exact `DO NOT reinstate` text and NO `# Rationale:` prefix. If net bytes are still above the Phase 0 figure, move the DOPPLER_TOKEN history comment the same way; then shorten arms. Never raise the gate.
- 2.4 Runbook `registry-luks-recut-6929.md`: rewrite only the 78 row's last sentence.
- 2.5 Battery: add rows G26-G29 (renamed from the planned G18b; anchors `78) abort A2 "the rehearsal failed with exit 78`, replacement renumbering to 77) to `tests/scripts/test-registry-gate-mutation-battery.sh`.

## Phase 3: Verification

- 3.1 `bash tests/scripts/test-registry-d10-workflow-wiring.sh`, `bash tests/scripts/test-registry-pull-path-health.sh`, `bash tests/scripts/test-registry-gate-mutation-battery.sh` (G18b caught, anchor unique), `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- 3.2 Scratch-tree mutation runs: Guard 1 rows 1, 3, 6 and the reordered-arms must-PASS; Guard 2 rows 1 and 3. Copy the suite, workflow, `.github/actions/`, `scripts/derive-app-domain-base.sh` and the engine into a scratch tree.
- 3.3 Derived-state checks, each edited only if it reports: affected-selection for the wiring suite on a diff touching the workflow and engine paths (consumer: `scripts/test-all.sh --affected` reading `scripts/lib/test-affected-paths.sh`; measure before adding an edge); `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`; the fixture-relative-assert lint; `python3 scripts/lint-workflow-run-body-syntax.py` and `python3 scripts/lint-workflow-errexit-capture.py` as CI invokes them. Adding the workflow and engine paths to the wiring suite's affected-paths array is expected to be owed (verified missing).
- 3.4 `python3 scripts/lint-guard-contract.py` on the plan, markdownlint on plan and tasks, `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`.
- 3.5 Confirm `git diff --stat origin/main...HEAD` shows no `apps/**` path and no change to `scripts/registry-restore-from-ghcr.sh`; `grep -c "no arm for 78"` on the runbook is 0.

## Phase 4: Ship (operator gate)

- 4.1 PR body: first line answers "does merging THIS alone mutate production?" (yes, the production apply fires once, no Terraform diff expected); `Ref #9757` only; link #10932; RED-then-GREEN evidence and scratch-run results.
- 4.2 Ask the operator exactly ONE plain question before marking the PR ready or arming the merge: "Merging this PR runs the production infrastructure apply once, because it edits the apply workflow's own file. Should I go ahead and arm the merge?" If the operator prefers no apply but still wants the merge, the alternative is a `[skip-web-platform-apply]` line in the squash-commit body; never use it unasked. Record the answer in `decision-challenges.md`. No answer: stay draft.
- 4.3 After the go-ahead: `gh pr merge --squash --auto` (never `--admin`); watch the production apply run to conclusion; leave #9757 open.
