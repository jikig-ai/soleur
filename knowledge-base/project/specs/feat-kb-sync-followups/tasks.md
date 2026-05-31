---
feature: feat-kb-sync-followups
plan: knowledge-base/project/plans/2026-06-01-feat-kb-sync-reconnect-affordance-and-stale-heuristic-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4712
created: 2026-06-01
---

# Tasks — KB-sync #4706 follow-ups (#4712)

Two sequenced PRs on `feat-kb-sync-followups`, **item 1 first**. RED→GREEN per phase. Run `./node_modules/.bin/vitest run <file>` + `./node_modules/.bin/tsc --noEmit` (in `apps/web-platform`) at each GREEN.

## PR 1 — Reconnect affordance (user-facing)

### 1. Shared predicate
- [ ] 1.1 Add `lib/repo-status.ts` `repoNeedsReconnect(repoStatus, installationId)` (`== null`, with inline comment). RED test `test/lib/repo-status.test.ts` (node): true only for `ready ∧ null/undefined`; false for installed + non-ready states.

### 2. Server derivation (no `/api/repo/status` change)
- [ ] 2.1 `app/api/kb/tree/route.ts`: add `github_installation_id` to SELECT (`:13`); return `{ tree, lastSync, needsReconnect }` via `repoNeedsReconnect` (`:37`). RED `test/api/kb-tree.test.ts` (node).
- [ ] 2.2 Confirm `app/(dashboard)/dashboard/page.tsx:143` reads `.tree` only (additive-safe; no change).

### 3. Reconnect hook
- [ ] 3.1 `components/repo/use-reconnect.ts` `useReconnect(onReconnected)` → `{ reconnect, isPending }`: POST detect-installation; success → `onReconnected()` + confirmation; failure → **emit `client-observability` (`reportSilentFallback` on network error / `warnSilentFallback` on `installed:false`, `feature:"kb-reconnect"`, `op:"detect-installation-fallback"`), then** `sessionStorage.setItem("soleur_return_to", location.pathname)` then `assign("/connect-repo?return_to=…")`. No `.catch(noop)`.
- [ ] 3.2 RED `test/components/repo/use-reconnect.test.tsx` (happy-dom; mock `window.location` happy-dom way): detect→install fallback; `isPending` toggles; error routes to `/connect-repo`; **telemetry fires on the failure branch before redirect**.

### 4. Shared notice component
- [ ] 4.1 `components/repo/reconnect-notice.tsx` `<ReconnectNotice variant="card"|"banner" onReconnected>` — amber notice + Reconnect button (uses `useReconnect`); default/in-flight/cleared states per wireframes; single honest copy.
- [ ] 4.2 RED `test/components/repo/reconnect-notice.test.tsx` (happy-dom): both variants render + wire Reconnect; in-flight disables.

### 5. Settings card surface
- [ ] 5.1 `project-setup-card.tsx`: add `needsReconnect?` prop; gate `ready` branch with `&& !needsReconnect`; new branch → `<ReconnectNotice variant="card" onReconnected={() => router.refresh()} />`.
- [ ] 5.2 `settings-content.tsx` + `settings/page.tsx`: SELECT `github_installation_id`, derive via `repoNeedsReconnect`, thread prop.
- [ ] 5.3 Extend `test/project-setup-card.test.tsx`: variant only on `ready ∧ needsReconnect`; Connected view suppressed.

### 6. KB-view banner surface
- [ ] 6.1 `hooks/use-kb-layout-state.tsx`: add `needsReconnect` state, set in `fetchTree`, expose on **`ctxValue` (`:180`)**; add `needsReconnect` to `kb-context.tsx` `KbContextValue` type.
- [ ] 6.2 Mount `<ReconnectNotice variant="banner" onReconnected={refreshTree} />` above content in `kb-desktop-layout.tsx` + `kb-mobile-layout.tsx`, **reading `needsReconnect` + `refreshTree` from `useKb()`**, gated on `needsReconnect`. **`onReconnected` = `refreshTree`, NOT `router.refresh()`.**
- [ ] 6.3 RED `test/components/kb/kb-reconnect-banner.test.tsx` (happy-dom): renders only when `needsReconnect`; success uses `refreshTree`.

### 7. PR 1 ship
- [ ] 7.1 vitest + tsc green; no `repo_status` mutation; no migration. Open PR (Ref #4712).

## PR 2 — Failure-based stale heuristic (ops-only)

### 8. Cron extension
- [ ] 8.1 Widen the shared service mock in `test/server/inngest/cron-workspace-sync-health.test.ts` (`:26-47`) to branch on `table==="users"` (own `select/eq/not` chain + fixtures). RED.
- [ ] 8.2 `cron-workspace-sync-health.ts`: add `step.run("scan-stale-sync-failed")` before heartbeat — scan `users` (`ready` + installed via `.not("github_installation_id","is",null)`), take `historyArr.at(-1)`, keep iff `KbSyncRow` with `ok===false`; `reportSilentFallback(…, { op:"stale-sync-failed", extra:{ userId } })`. Report in-place, return `{ reported:n }`; do NOT widen `ScanResult` or top-level return. DB-error → report once (`op:"scan-stale"`), no findings.
- [ ] 8.3 GREEN tests: fires once on latest-`ok:false`; none on `ok:true`/legacy/empty/NULL-install; DB-error reports once; read-only.

### 9. PR 2 ship
- [ ] 9.1 vitest + tsc green; no new fn/registration/migration. Open PR (Ref #4712); after both merge, `gh issue close 4712`.
