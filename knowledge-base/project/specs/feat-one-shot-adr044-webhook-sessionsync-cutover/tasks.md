---
feature: ADR-044 PR-2b precondition — webhook founder attribution + session-sync write cutover
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-17-feat-adr-044-webhook-sessionsync-cutover-plan.md
issue: "#5437 (umbrella — Ref, NOT Closes)"
brand_survival_threshold: single-user incident
---

# Tasks — ADR-044 webhook + session-sync cutover

> Two logical units (CTO split): PR-A = webhook attribution (security), PR-B = session-sync write. Both land on this branch; reviewable as two commits.

## Phase 0 — Preconditions (verify before coding)
- [ ] 0.1 Re-confirm origin/main state: issue #5437 OPEN; PR 5481 + 5466 MERGED (done at plan time — re-verify on resume).
- [ ] 0.2 DUAL-shape reader sweep: `git grep -nE "\.(eq|in|match|or|filter)\([\"']?github_installation_id|select\([^)]*\bgithub_installation_id\b" -- apps/web-platform/`. Enumerate every `users.github_installation_id` reader; confirm only the webhook reverse-lookup + the `detect-installation/route.ts` self-read (`.eq("id", user.id)`) remain (the two Inngest readers already cut over). Note `detect-installation` disposition.
- [ ] 0.3 Confirm `workspaces` has NO UPDATE RLS policy / NO `GRANT UPDATE` to authenticated (mig grep) — locks in the service-role-injection design for SURFACE 2.
- [ ] 0.4 Read `writeRepoColsToWorkspace` + `appendKbSyncRowForWorkspace` + `resolveActiveWorkspace` bodies to confirm the injected-service + resolved-workspace pattern.
- [ ] 0.5 Open Code-Review Overlap query (plan §Open Code-Review Overlap) — record matches + disposition or None.

## Phase 1 — SURFACE 1: webhook founder attribution (PR-A) [TDD: RED first]
- [ ] 1.1 Write failing tests `test/github-webhook-founder-attribution.test.ts` for the 6 scenarios (single-solo / zero / >1-ambiguous / team-not-mistaken / push-no-users-read / db-error-500). Mirror `test/webhook-subscription.test.ts`.
- [ ] 1.2 Add the non-push solo-founder resolver (`server/resolve-founder-for-installation.ts` or fold into `resolve-installation-id-for-workspace.ts`): injected service client, solo self-join (`m.user_id = w.id AND m.role='owner' WHERE w.github_installation_id = $1`), discriminated-union return {found/none/ambiguous/db-error}. No allowlist entry.
- [ ] 1.3 Webhook route: replace Step 5 `users` reverse-lookup. Non-push branch → resolver; map 0→404+release, 1→proceed, >1→Sentry op:founder-ambiguous + 404 + release (zero send/isGranted), db-error→500+release. Reword the comment so `users` + `github_installation_id` don't co-occur on one line.
- [ ] 1.4 Push branch: stop sourcing `founderId` from a `users` read; drop `founderId` from the `inngest.send` reconcile payload.
- [ ] 1.5 Bump `WORKSPACE_RECONCILE_SCHEMA_V` (2→3) in session-sync.ts; drop `founderId` from the reconcile event payload type.
- [ ] 1.6 `workspace-reconcile-on-push.ts`: drop `founderId` from consumed payload type; confirm no `event.data.founderId` read remains.
- [ ] 1.7 GREEN: all Phase 1 tests pass.

## Phase 2 — SURFACE 2: session-sync write relocation (PR-B) [TDD: RED first]
- [ ] 2.1 Write failing test `test/server/session-sync-workspace-last-synced.test.ts` (or extend `session-sync.tenant-isolation.test.ts`): write lands on `workspaces.repo_last_synced_at` keyed on resolved workspace id; no `users` write; read-back parity via repo/status; 0-row Sentry-mirror.
- [ ] 2.2 `updateLastSynced(service, workspaceId)`: write via `writeRepoColsToWorkspace(service, workspaceId, { repo_last_synced_at })`; remove the `users` UPDATE. Service client injected — session-sync.ts does NOT acquire service-role.
- [ ] 2.3 Thread the injected service client + resolved active-workspace id from `agent-runner.ts` (lines 1166, 2262) through `syncPull`/`syncPush` into `updateLastSynced`. Reuse agent-runner's existing active-workspace resolution (no second divergent resolver).
- [ ] 2.4 Confirm session-sync.ts NOT added to `.service-role-allowlist`; `service-role-allowlist-gate.sh` passes.
- [ ] 2.5 GREEN: all Phase 2 tests pass.

## Phase 3 — ADR / C4 (plan deliverable)
- [ ] 3.1 Amend ADR-044: "Amendment 2026-06-17b — webhook founder attribution + session-sync write" transcribing the CTO ruling; mark §"Remaining #5470 set" CLOSED.
- [ ] 3.2 Update the ADR-044 C4 connection-owner edge note (read=Workspace / write=Workspace for the webhook + session-sync edges). Edit `.c4` model file directly if a view exists; else prose in the amendment.

## Phase 4 — Verify + ship
- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-webhook-founder-attribution.test.ts test/server/session-sync*.test.ts`.
- [ ] 4.3 Run all Pre-merge ACs (plan §Acceptance Criteria 1-13), incl. the literal greps.
- [ ] 4.4 Review: security-sentinel + data-integrity-guardian + user-impact-reviewer (single-user-incident threshold) + observability-coverage-reviewer.
- [ ] 4.5 gdpr-gate (auth/API-route surface).
- [ ] 4.6 PR body uses `Ref #5437` (NOT Closes). Verify KB path citations resolve.
