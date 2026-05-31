---
title: "Tasks — Sentry issue RW token + postmerge auto-resolve (#4681)"
plan: knowledge-base/project/plans/2026-05-31-chore-sentry-issue-rw-token-postmerge-autoresolve-plan.md
issue: 4681
lane: cross-domain
---

# Tasks — #4681 write-scoped Sentry token + postmerge auto-resolve

## Phase 1 — Docs (in-PR)
- [x] 1.1 Add `SENTRY_ISSUE_RW_TOKEN=` block (with documenting comment) to `apps/web-platform/.env.example` after the `SENTRY_API_TOKEN=` line.

## Phase 2 — Skill change (in-PR)
- [x] 2.1 In `plugins/soleur/skills/postmerge/SKILL.md` Phase 3.6, add the write-token resolution line (`SENTRY_ISSUE_RW_TOKEN` via doppler, fallback to empty/skip — NOT to a read token).
- [x] 2.2 Add the `PUT {"status":"resolved"}` curl inside the "expected good outcome" branch only (gated on non-empty RW token AND issue not already resolved). Reuse the existing `API_HOST`/`SENTRY_ORG` resolution.
- [x] 2.3 Add `AUTO-RESOLVED` to the Phase 3.6 / Phase 6 / Phase 7 outcome vocabulary; on PUT non-200 emit a WARN and continue (never block).
- [x] 2.4 Add `No SENTRY_ISSUE_RW_TOKEN | Skip auto-resolve …` row to the Graceful Degradation table.

## Phase 3 — Verify (in-PR)
- [x] 3.1 `grep -c '^SENTRY_ISSUE_RW_TOKEN=' apps/web-platform/.env.example` == 1.
- [x] 3.2 `grep -c '"status":"resolved"' plugins/soleur/skills/postmerge/SKILL.md` >= 1; PUT precedes/follows the RW-token line; STILL-FIRING branch unchanged.
- [x] 3.3 `bun test plugins/soleur/test/components.test.ts` passes (no description budget impact).

## Phase 4 — Operator (post-merge)
- [ ] 4.1 Mint `postmerge-issue-rw` Internal Integration token on `jikigai-eu` (`event:admin`, `org:read`, `project:read`).
- [ ] 4.2 Write the value to `SENTRY_ISSUE_RW_TOKEN` on Doppler `soleur`/`prd`; confirm discoverability_test returns `200`.
- [ ] 4.3 Confirm next postmerge run on a stopped Sentry issue prints `AUTO-RESOLVED`; then `gh issue close 4681`.
