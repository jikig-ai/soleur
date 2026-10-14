---
plan: knowledge-base/project/plans/2026-07-18-fix-model-c4-cron-monitor-count-plan.md
issue: 6644
branch: feat-one-shot-6644-model-c4-cron-count
lane: single-domain
---

# Tasks — fix(observability): model.c4 cron-monitor count 49 → 50

## Phase 1 — Correct the C4 source

- [ ] 1.1 Edit `knowledge-base/engineering/architecture/diagrams/model.c4` line 451
  (`github -> sentry` edge description): replace the unique clause
  `Of 49 cron monitors, 6 check in from here and 43 from webapp`
  with `Of 50 cron monitors, 7 check in from here and 43 from webapp`.
  Change nothing else — leave `from 6 workflows`, the `3 GHA-schedule + 3 workflow_dispatch`
  enumeration, `-supabase-advisor-scan`, and `43 from webapp` verbatim.

## Phase 2 — Regenerate the compiled artifact

- [ ] 2.1 Run `bash scripts/regenerate-c4-model.sh` from the repo root (uses pinned
  `likec4@1.50.0`; idempotent; validates off-tree before publishing).
- [ ] 2.2 Confirm the regenerated `knowledge-base/engineering/architecture/diagrams/model.likec4.json`
  diff is minimal (the two changed characters in the `github -> sentry` edge description;
  element/relation counts unchanged). Do NOT hand-edit the JSON.

## Phase 3 — Verify

- [ ] 3.1 `bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` exits 0
  (primary VERIFY — cross-file `c4_count == tf_count == 50`).
- [ ] 3.2 `bash plugins/soleur/test/c4-model-freshness.test.sh` exits 0 (JSON in sync, no drift).
- [ ] 3.3 `grep -c '7 check in from here and 43 from webapp' …/model.c4` == 1 and
  `grep -c '6 check in from here' …/model.c4` == 0.
- [ ] 3.4 `git diff --stat` shows exactly two files changed: `model.c4` + `model.likec4.json`.
