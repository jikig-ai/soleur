# Tasks — feat-one-shot-10932-restore-exit-1

Plan: `knowledge-base/project/plans/2026-10-28-chore-enumerate-restore-engine-exit-1-in-apply-restore-step-plan.md`
Issue: #10932 (`Ref` only; umbrella #9757 stays open). Draft PR: #11438. Pipeline STOPS at the pushed draft PR.

## Phase 0 — Preflight (no edits)

- 0.1 Confirm `git diff --stat origin/main...HEAD -- apps scripts/registry-restore-from-ghcr.sh` is empty.
- 0.2 Baseline: `bash tests/scripts/test-registry-d10-workflow-wiring.sh` ends `39 passed, 0 failed`; workflow is 489,888 bytes.
- 0.3 Record the STOP for item (a): the engine header is a comment block but any edit changes the file; do not edit it.

## Phase 1 — RED tests first (`tests/scripts/test-registry-d10-workflow-wiring.sh`)

- 1.0 Start from the measured prototype: `git apply knowledge-base/project/specs/feat-one-shot-10932-restore-exit-1/w9-prototype.diff`, then review it.
- 1.1 Re-key the `*)` fall-through flag from `$hdr` to `$tested`.
- 1.2 Add the exit-1 content pin (`manifest`) to the per-code `case`.
- 1.3 Extend `W9_PY`: `drop1`, `envswap`, `jobif`, `jobcoe` mutations; `env` and `job` read modes.
- 1.4 Extend `w9_check`: credential-env pin (message "credential env"); job-level pin (message "job-level").
- 1.5 Add the four controls to the control list; refresh the W9 header comment.
- 1.6 Run the suite; capture the expected RED ("exit 1 fell to the *) arm").
- 1.7 Set `EXPECTED_ASSERTIONS` from the green run (expected 43) after Phase 2.

## Phase 2 — Workflow (`.github/workflows/apply-web-platform-infra.yml`)

- 2.1 Add the `1)` arm (text in the plan).
- 2.2 Reword the `*)` arm (drop the #10932 exception; name 126/127/137/143 as shell or runner codes; keep "unenumerated exit").
- 2.3 Move the 11-line `# EXPLICIT, not inherited` block above the job `if:` to the rationale doc verbatim; leave a one-line stub.
- 2.4 `wc -c` target <= 489,950; hard gate 490,000.

## Phase 3 — Docs

- 3.1 Rationale doc: `### Why the restore job's if: is explicit` and `### Why exit 1 has its own restore-step arm (#10932)` under `## registry_store_restore`.
- 3.2 Runbook: add the `1` row; fix the lead sentence; qualify "then re-run that job" for exit 1.
- 3.3 `python3 -I scripts/lint-infra-no-human-steps.py --changed --base origin/main`.

## Phase 4 — Verify and stop

- 4.1 Suites: d10-workflow-wiring (43 passed), pull-path-health, restore-from-ghcr, `bun test plugins/soleur/test/workflow-file-size.test.ts`.
- 4.2 Manual once: delete the `1)` arm and confirm the suite fails with "exit 1 fell"; restore it.
- 4.3 `git diff --stat origin/main...HEAD` for `apps`, the engine, the pull-path-health script and suite, and the header lib: all empty.
- 4.4 Pre-ready gates: `python3 -I scripts/ci-pr-affected-replay.py ratchet`; `bunx vitest run --project repo-wide test/plugin-root-anchoring.test.ts` (from `apps/web-platform`); `plugins/soleur/scripts/scan-ancestor-signal-helpers.test.sh`.
- 4.5 Commit, push, update PR #11438 body (`Ref #9757`, `Ref #10932`, no closing keyword; state (a) not done and the residual classification). STOP: no `gh pr ready`, no auto-merge.
