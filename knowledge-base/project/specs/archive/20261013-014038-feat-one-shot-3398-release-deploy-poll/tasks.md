# Tasks — fix(ci): web-platform-release deploy poll timeout + lock contention

Plan: `knowledge-base/project/plans/2026-05-07-fix-3398-release-deploy-poll-timeout-lock-contention-plan.md`

## Phase 1 — Workflow ceiling bump

- [x] Bump `STATUS_POLL_MAX_ATTEMPTS` 60 → 180 in `.github/workflows/web-platform-release.yml`.
- [x] Bump `HEALTH_POLL_MAX_ATTEMPTS` 30 → 90 in same file.
- [x] Update comment block above `STATUS_POLL_*` (rerun-unsafety + 900s rationale + #3398 reference).
- [x] Add per-attempt elapsed-time annotation parsing `.start_ts` via `jq`.

## Phase 2 — `ci-deploy.sh` lock comment

- [x] Add 9-line lock-semantics comment above the `flock -n 200` block.
- [x] Add `START_TS` schema-stability breadcrumb at line 43 (and at `write_state`'s printf).

## Phase 3 — Documentation

- [x] Append `## Rerun Safety` section to `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`.
- [x] Append `## 2026-05-07 update` to `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md`.
- [x] Create `knowledge-base/project/learnings/best-practices/2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`.

## Phase 4 — Follow-up issues (filed at PR time, before merge)

- [x] File issue: #3408 — "Pre-rerun lock probe in web-platform-release deploy job".
- [x] File issue: #3409 — "Build-version verification on /health endpoint after deploy".
- [ ] Record both issue numbers in the PR body (handled at /ship time).

## Verification

- [x] No test changes required (infra-only carve-out per `cq-write-failing-tests-before`).
- [ ] `bash apps/web-platform/infra/ci-deploy.test.sh` still green after lock comment.
- [ ] Plan checkboxes synced.
