---
title: "Tasks — fix deploy-pipeline-fix false-success (#4804)"
plan: knowledge-base/project/plans/2026-06-02-fix-deploy-pipeline-fix-false-success-plan.md
issue: "#4804"
lane: cross-domain
---

# Tasks — deploy-pipeline-fix false-success (#4804)

## Phase 0 — Preconditions (no writes)

- [ ] 0.1 Re-read `infra-config-apply.sh:52-60` (upfront gate) + `70-116` (per-file loop); confirm loop already supports `continue`/`FAIL_COUNT`/`FILES_JSON`.
- [ ] 0.2 Confirm state JSON keys: `files_written`, `files_failed`, per-file `sha256`/`status`/`reason`.
- [ ] 0.3 Confirm `TOTAL = ${#FILE_MAP[@]}` is currently 8.
- [ ] 0.4 Confirm `grep -c infra-config-apply.test.sh .github/workflows/infra-validation.yml` returns 0.

## Phase 1 — RED (failing test first)

- [ ] 1.1 Add case to `infra-config-apply.test.sh`: one env var unset → assert exit 1, 7 files written with correct content, state `files_written==7`/`files_failed==1`, missing file `status:"failed", reason:"missing_env"`.
- [ ] 1.2 (Optional) Add happy-path-unchanged case (8/0/exit 0).
- [ ] 1.3 Run test → confirm new case RED-fails against current upfront-gate behavior.

## Phase 2 — GREEN: handler contract change

- [ ] 2.1 Delete upfront validation loop (`infra-config-apply.sh:52-60`).
- [ ] 2.2 Add per-file `missing_env` arm at top of write-loop body (before `mktemp`): record failed file, `continue`, increment `FAIL_COUNT`.
- [ ] 2.3 Confirm `EXIT_CODE=1` when `FAIL_COUNT>0` (existing logic unchanged).
- [ ] 2.4 Run handler test → all cases pass (GREEN).

## Phase 3 — GREEN: CI verify-step strengthening

- [ ] 3.1 In `apply-deploy-pipeline-fix.yml` "Verify infra-config apply succeeded": parse `.files_failed`/`.files_written`/`.exit_code`; fail when `files_failed != 0`.
- [ ] 3.2 Replace unconditional 404-pass with bounded first-bootstrap tolerance (explicit `workflow_dispatch`/input signal); persistent 404 on `push` fails. Route untrusted input via `env:`.
- [ ] 3.3 Add final post-apply assertion: `GET /hooks/deploy-status` → `jq -e '.journald_storage.persistent == true'` (HMAC + CF-Access headers), gated `if: success()`.
- [ ] 3.4 Add `gh issue close 4804 --reason completed` step `if: success()` after 3.3 (or document `/soleur:ship` handles it).
- [ ] 3.5 `actionlint .github/workflows/apply-deploy-pipeline-fix.yml`; validate embedded shell via `bash -c`.

## Phase 4 — Register handler test in CI

- [ ] 4.1 Add `run: bash apps/web-platform/infra/infra-config-apply.test.sh` step to `infra-validation.yml` (near `ci-deploy.test.sh`, matching naming/indentation).

## Phase 5 — Learning

- [ ] 5.1 Write `knowledge-base/project/learnings/bug-fixes/<topic>.md`: 202-trigger-and-forget vs script-completion; chicken-and-egg freeze on atomic FILE_MAP + hooks.json additions; assert-files-landed verification principle. Cross-ref the two deploy-pipeline-fix learnings.

## Acceptance (gate before PR-ready)

- [ ] AC1-AC9 pre-merge satisfied (see plan).
- [ ] AC10 PR body uses `Ref #4804` (not `Closes`).
- [ ] AC11-AC13 post-merge automation wired in workflow.
