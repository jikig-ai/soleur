---
title: "feat: KB-sync reconnect affordance + failure-based stale heuristic (#4712)"
type: feature
status: draft
created: 2026-06-01
issue: 4712
parent_issue: 4706
followup_issue: 4717
branch: feat-kb-sync-followups
pr: 4716
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ✨ feat: KB-sync #4706 follow-ups — reconnect affordance (PR 1) + failure-based stale heuristic (PR 2)

Two sequenced PRs on `feat-kb-sync-followups`, **item 1 first**. Closes #4712.

## Deepen-Plan Enhancement Summary (2026-06-01)

Substance triad (data-integrity-guardian, security-sentinel, architecture-strategist) + observability-coverage-reviewer. Gates 4.6/4.7/4.8 pass. **Security: clean** (return_to allowlist-safe, no cross-tenant leak, hashed userId confirmed, no new auth surface). Folded in:
1. **Client reconnect-failure telemetry** (observability P1) — emit `client-observability` `op:"detect-installation-fallback"` to Sentry before the `/connect-repo` redirect; the failure was previously loud-to-user but silent-to-ops (Phase 1.2).
2. **`useKb()` context seam** (arch P1-2) — `needsReconnect`/`refreshTree` flow through `KbContextValue`, not the `state` prop (Phase 1.5); `ProjectSetupCard` needs a `useRouter` import (P2-1).
3. **Latent-coupling + scope notes** (data-integrity P1) — `at(-1)` depends on the legacy writer staying write-blocked; item-2 is solo/owner-row detection (team-workspace gap → #4717); no PII in the cron `Error.message` (Sharp Edges).
4. **Doc fixes** — cron is 06:23 UTC (not 23:06); discoverability_test is the in-CI cron unit test (no false prod-Sentry e2e claim).

## Overview

The parent incident (#4706) froze a user's Knowledge Base for ~5 weeks: their workspace had `repo_status='ready'` but `github_installation_id IS NULL`, so the webhook reconcile (`workspace-reconcile-on-push.ts`, selects by `github_installation_id`) never selected it — silent staleness, zero `kb_sync_history` rows, no in-product signal. #4706 shipped a read-only Sentry detection cron (`cron-workspace-sync-health`) and the operator reconnected manually. This plan closes the two remaining gaps:

- **PR 1 (user-facing):** a deterministic `needsReconnect` flag + a **working** reconnect affordance (settings card variant + KB-view inline notice) that drives a real re-auth via the already-existing `/api/repo/detect-installation` → `/connect-repo` fallback.
- **PR 2 (ops-only):** extend the existing cron with a second deterministic scan — a `ready`+installed user whose **latest `kb_sync_history` row is `ok:false`** (persistent recorded failure) → Sentry via `reportSilentFallback`.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Reconnect UI lives in `RepoConnectionCard` | No such component. Real surface = `ProjectSetupCard` (`components/settings/project-setup-card.tsx:22`) + `DisconnectRepoDialog`; only reconnect path today is the `error`-state "Retry Setup" `<a>` (`:73`) | Add a `needsReconnect` variant to `ProjectSetupCard`; no `RepoConnectionCard` |
| `/api/kb/tree` 409s on `repo_status='error'` | It 404s on `not_connected`, 503s on `workspace_status!='ready'`, 500 on catch (`app/api/kb/tree/route.ts:17,21,38`). No 409. The 409s are in `/api/kb/sync` | Keep the "no `repo_status` mutation" rule (spirit holds); derive a new flag instead |
| Item 2 "scan workspaces … kb_sync_history" (spec FR6) | `kb_sync_history` is JSONB on **`users`** only (`session-sync.ts:327`). ADR-044 mirrored *repo* cols (`repo_url`/`repo_status`/`github_installation_id`) to `workspaces`, **not** history | Item-2 scan targets **`users`** (all three fields co-reside there), unlike item-1 which scans `workspaces` |
| Item 2 "log workspace UUID only" | `reportSilentFallback` auto-pseudonymizes `extra.userId → userIdHash` (`observability.ts`) | Item-2 logs `extra: { userId }` (hashed by the helper) — strictly more privacy-preserving than a raw UUID |
| `/api/repo/detect-installation` is the reconnect heal path | Confirmed: `POST`, returns `{installed:true, repos}` or `{installed:false, …}` (`route.ts:30,57,106`); auto-stores `github_installation_id` + mirrors to solo workspace | Reconnect button POSTs it first, falls through to `/connect-repo` only on `installed:false` |
| Spec FR1 derives `needsReconnect` in `/api/repo/status` too | **Dead code** — only `connect-repo/page.tsx` (`:119,207,366`) fetches `/api/repo/status`, and it reads `status`, not `needsReconnect`. The settings card is fed server-side by `settings/page.tsx`, not this route | **CUT** the `/api/repo/status` change; derive only in `/api/kb/tree` (KB notice) + `settings/page.tsx` (settings card) — both read `users` |
| KB-view notice assumes `/api/kb/tree` returns 200 for the frozen workspace | Load-bearing: the route 503s first if `workspace_status!=='ready'` (`:21`). Incident evidence (#4706: a **stale-but-visible** tree) proves the frozen class had `workspace_status='ready'` ⇒ route returned 200 | Assumption holds; the notice mounts above the still-rendered stale tree |

## User-Brand Impact

**If this lands broken, the user experiences:** a Knowledge Base that silently stops updating (stale file tree, no error) with no way to notice or fix it — the exact 5-week freeze of #4706 recurring; or, if the reconnect button is wired wrong, a button that looks actionable but doesn't re-authorize (dead-end).

**If this leaks, the user's data/workflow is exposed via:** no new exposure surface — both items read existing columns; item 2 logs only the helper-hashed `userId` to Sentry (already a disclosed sub-processor). The GitHub re-auth uses GitHub's own consent screen.

**Brand-survival threshold:** single-user incident (inherited from #4706). `requires_cpo_signoff: true` — CPO assessed this scope in the 2026-06-01 brainstorm (`## Domain Assessments`); `user-impact-reviewer` runs at PR-review time per review/SKILL.md.

## Implementation Phases

> Revised post plan-review (5-agent panel). Reconciliation table at `## Plan-Review Reconciliation`.

### PR 1 — Reconnect affordance (item 1, user-facing)

**Phase 1.0 — Shared `needsReconnect` predicate (kills selector-divergence, the incident's own bug class).**
- New pure helper `lib/repo-status.ts`: `export function repoNeedsReconnect(repoStatus: string | null, installationId: number | bigint | null | undefined): boolean { return repoStatus === "ready" && installationId == null; }` (`== null` is intentional — null OR undefined; add the inline comment since the codebase is mostly `===`). Single source of truth imported by both derivation sites below. **Do NOT** re-derive the predicate inline anywhere (DHH #1, simplicity).
- Test: `test/lib/repo-status.test.ts` (node) — true only for `ready ∧ null/undefined install`; false for `ready`+installed, and for `not_connected`/`error`/`cloning` regardless of install.

**Phase 1.1 — Server-derive `needsReconnect` (RED→GREEN). `/api/repo/status` is NOT touched (dead code — see reconciliation).**
- `app/api/kb/tree/route.ts`: add `github_installation_id` to the SELECT (`:13`); `const needsReconnect = repoNeedsReconnect(userData.repo_status, userData.github_installation_id);`; return `{ tree, lastSync, needsReconnect }` (`:37`). Assert non-breaking for the other consumer: `app/(dashboard)/dashboard/page.tsx:143` reads only `.tree` → additive-safe (Kieran P1-2).
- Tests: `test/api/kb-tree.test.ts` (node) — `needsReconnect` true only for `ready ∧ null install`; false for installed / `not_connected` (404 short-circuits) etc.

**Phase 1.2 — Shared reconnect action (RED→GREEN).**
- New `components/repo/use-reconnect.ts` (client hook), signature `useReconnect(onReconnected: () => void)` returning `{ reconnect, isPending }`:
  - exposes **`isPending`** (disables the button + shows "Reconnecting…"); guards against double-POST (spec-flow P0-3).
  - `POST /api/repo/detect-installation`; on `{installed:true}` → call `onReconnected()` (surface-specific refresh) + surface a success confirmation; on `{installed:false}` / non-200 / network → **(i) emit ops telemetry, (ii) persist return_to, (iii) redirect.**
    - **(i) Ops telemetry (deepen observability P1):** before redirecting, call from `@/lib/client-observability` — a thrown/network error → `reportSilentFallback(err, { feature: "kb-reconnect", op: "detect-installation-fallback" })` (error level); a clean `{installed:false}` → `warnSilentFallback(…, { feature: "kb-reconnect", op: "detect-installation-fallback" })` (warn level, expected re-auth) so the redirect rate is queryable in Sentry. "Loud to the user" (redirect) ≠ "loud to ops" — both are required. (`ClientExtra` brands `userId` as `never`, so no PII.)
    - **(ii)** `sessionStorage.setItem("soleur_return_to", window.location.pathname)` then **(iii)** `window.location.assign("/connect-repo?return_to=" + encodeURIComponent(window.location.pathname))` (spec-flow P0-1: the query param alone is dropped on the auto-detect path; persist to sessionStorage so the post-OAuth `consumeReturnTo` lands the user back where they froze). Pass `window.location.pathname` only (not `href`/`pathname+search`) so `safeReturnTo`'s allowlist (`/dashboard` prefix, rejects `..`/`//`) passes (Kieran P1-3).
  - No `.catch(noop)` — every branch is code-traced; errors fall loud to BOTH the user (`/connect-repo`) and ops (client-observability → Sentry).
- Test: `test/components/repo/use-reconnect.test.tsx` (**happy-dom** — mock `window.location` the happy-dom way, Kieran P1-1) — detect-first then install-fallback on `installed:false`; `isPending` toggles; `onReconnected` called on success; error path routes to `/connect-repo` (never swallowed) **AND fires `warnSilentFallback`/`reportSilentFallback` before redirect** (deepen observability P1).

**Phase 1.3 — Shared `<ReconnectNotice variant="card"|"banner">` (RED→GREEN). One component, both surfaces (DHH #3, simplicity).**
- New `components/repo/reconnect-notice.tsx`: amber notice (mirrors the existing `border-red-800 bg-red-950/50` treatment in amber) + Reconnect button wired to `useReconnect`. `variant="card"` for the settings card body, `variant="banner"` for the full-width KB banner. Default / in-flight (`isPending`) / success-cleared states per the wireframes (see Domain Review). Single honest copy string (no per-surface drift): "This project can't sync — reconnect to restore Knowledge Base updates. Reconnect re-authorizes GitHub access so syncing can resume."
- Test: `test/components/repo/reconnect-notice.test.tsx` (happy-dom) — both variants render the notice + wire Reconnect; in-flight disables.

**Phase 1.4 — Settings card surface (RED→GREEN).**
- `components/settings/project-setup-card.tsx`: add `needsReconnect?: boolean` prop (`:7`); **add `import { useRouter } from "next/navigation"` (the card has no router today — deepen arch P2-1)**; gate the existing `ready` branch with `&& !needsReconnect` (`:46`); add branch `repoStatus === "ready" && needsReconnect` → `<ReconnectNotice variant="card" onReconnected={() => router.refresh()} />` (server-rendered prop clears on refresh).
- `components/settings/settings-content.tsx` (`:10`,`:40`) + `app/(dashboard)/dashboard/settings/page.tsx` (`:29`,`:35`): add `github_installation_id` to the page SELECT, derive via `repoNeedsReconnect`, thread the prop through `SettingsContent → ProjectSetupCard`.
- Tests: extend `test/project-setup-card.test.tsx` — needs-reconnect variant renders only on `ready ∧ needsReconnect`; "Connected" view suppressed in that state.

**Phase 1.5 — KB-view banner surface (RED→GREEN). Correct refresh primitive (spec-flow P0-2).**
- `hooks/use-kb-layout-state.tsx`: add `needsReconnect` state (`:57`), set from `data.needsReconnect` in `fetchTree` (`:95`), and **expose it on `ctxValue` (`:180`) — the `KbContextValue` consumed via `useKb()`, where `refreshTree: fetchTree` already lives — NOT just the top-level `state` return** (deepen arch P1-2: `refreshTree` is read through the `useKb()` context, e.g. `file-tree.tsx:114`, not the `state` prop). Add `needsReconnect` to `kb-context.tsx`'s `KbContextValue` type.
- Mount `<ReconnectNotice variant="banner" onReconnected={refreshTree} />` above the content in `components/kb/kb-desktop-layout.tsx` and `components/kb/kb-mobile-layout.tsx`, **reading both `needsReconnect` and `refreshTree` from `useKb()`**, gated on `needsReconnect`. **`onReconnected` MUST be `refreshTree` (the hook's `fetchTree`), NOT `router.refresh()`** — the KB `needsReconnect` is client-fetched state; `router.refresh()` re-runs RSC but not the client `useEffect`, leaving the notice stuck (spec-flow P0-2). `refreshTree()` re-fetches `/api/kb/tree`, re-derives `needsReconnect=false`, and repaints the now-fresh tree. Judgment-relevance gate: renders only on the real signal, never ambient.
- Test: `test/components/kb/kb-reconnect-banner.test.tsx` (happy-dom) — banner renders only when `needsReconnect`; on success, `refreshTree` is the callback (assert the re-fetch path), not `router.refresh`.

### PR 2 — Failure-based stale heuristic (item 2, ops-only)

**Phase 2.1 — Extend the cron (RED→GREEN). Findings stay local; `ScanResult` unchanged (Kieran P0-2).**
- `server/inngest/functions/cron-workspace-sync-health.ts`: add a second `step.run("scan-stale-sync-failed")` BEFORE the heartbeat. Scan `users`: `.select("id, kb_sync_history").eq("repo_status","ready").not("github_installation_id","is",null)`; in JS, take the **latest** element (`historyArr.at(-1)`, NOT `.some()` — `.some()` false-positives on a since-recovered repo, Kieran P2-3) and keep the user iff that element is a rich `KbSyncRow` with `ok === false` (guard: `typeof r==='object' && r!==null && 'ok' in r && r.ok===false` — excludes legacy `{date,count}`, `ok:true`, and empty history → went-quiet/NULL-install class, deferred to #4717). For each finding: `reportSilentFallback(new Error("ready+installed workspace's latest KB sync failed"), { feature: "workspace-sync-health", op: "stale-sync-failed", extra: { userId }, message: "…persistent kb_sync_history ok:false; KB stale despite installed app" })` (the helper hashes `userId`). Read-only; DB-error path reports once via `op:"scan-stale"` and returns no findings. **Report in-place inside this step and return only `{ reported: n }` — do NOT widen `ScanResult` (`:31`) or the top-level return (`:97`), which the existing reporting test deep-equals against the item-1 findings (Kieran P0-2).** No new Inngest function, no registration change, no migration.
- Test: extend `test/server/inngest/cron-workspace-sync-health.test.ts` — **first widen the shared service mock (`:26-47`) to branch on `table==="users"`** with its own `select/eq/not` chain + rows/error fixture; the current mock hard-throws on any non-`workspaces` table and would red ALL existing describe blocks (Kieran P0-1). Then: latest-row `ok:false` ready+installed user reports exactly once (`op:"stale-sync-failed"`); ready+installed with latest `ok:true`, latest legacy `{date,count}`, empty history, and NULL-install all report none for this op; DB-error path reports once and returns `{findings:[]}`. Read-only (no `.update`/`.upsert`).

## Acceptance Criteria

### Pre-merge (PR 1)
- [ ] Single shared `repoNeedsReconnect()` predicate; derived ONLY in `/api/kb/tree` + `settings/page.tsx` (no inline copies; `/api/repo/status` untouched). True only for `ready ∧ install null`.
- [ ] `ProjectSetupCard` needs-reconnect variant renders only on `ready ∧ needsReconnect`; "Connected" view suppressed in that state.
- [ ] Shared `<ReconnectNotice>` used by BOTH surfaces; KB banner renders above the tree only when `needsReconnect`.
- [ ] Reconnect: `isPending` disables the button in-flight; detect-installation → on success `onReconnected` (settings `router.refresh()`, KB `refreshTree()` — NOT `router.refresh()`); on failure persists `soleur_return_to` then routes to `/connect-repo`; error path code-traced, no silent swallow.
- [ ] No `repo_status` mutation in the diff; no migration.
- [ ] `./node_modules/.bin/vitest run` green for changed test files; `./node_modules/.bin/tsc --noEmit` clean in `apps/web-platform`.

### Pre-merge (PR 2)
- [ ] Cron reports each `ready ∧ installed ∧ latest-row-ok:false` user via `reportSilentFallback` (`op:"stale-sync-failed"`, hashed userId); emits nothing for healthy / legacy-row / empty-history / NULL-install; DB-error path reports once. Read-only.
- [ ] No new Inngest function, no registration change, no migration.
- [ ] vitest + tsc green.

### Post-merge (operator)
- [ ] None automatable beyond CI. Item-1 affordance and item-2 Sentry signal are both verifiable via the discoverability tests below — no SSH, no dashboard eyeballing.

## Observability

```yaml
liveness_signal:    # cron-workspace-sync-health Sentry heartbeat (postSentryHeartbeat), daily 06:23 UTC (cron "23 6 * * *"), monitor slug "cron-workspace-sync-health"; unchanged by PR 2
error_reporting:    # server: reportSilentFallback → pino + Sentry (feature "workspace-sync-health"). PR1 client: reportSilentFallback/warnSilentFallback from lib/client-observability → Sentry (feature "kb-reconnect") BEFORE the /connect-repo redirect (deepen observability P1)
failure_modes:
  - mode: ready+NULL-install workspace silently unsyncable      # detection: existing op "ready-null-installation"               ; alert_route: Sentry
  - mode: ready+installed workspace persistently failing sync   # detection: NEW op "stale-sync-failed" (PR 2)                    ; alert_route: Sentry
  - mode: cron scan DB error                                    # detection: op "scan" / "scan-stale" reportSilentFallback       ; alert_route: Sentry
  - mode: reconnect detect-installation call fails              # detection: client-observability op "detect-installation-fallback" (warn on installed:false, error on network) ; alert_route: Sentry (client → Sentry) + user re-auth redirect
logs:               # where: Sentry + pino (reportSilentFallback mirrors both); retention: existing Sentry retention
discoverability_test:  # command (NO ssh): the cron unit test is the in-CI discoverability gate — `./node_modules/.bin/vitest run test/server/inngest/cron-workspace-sync-health.test.ts` asserts reportSilentFallback fires with op:"stale-sync-failed" on a seeded latest-row-ok:false user. (End-to-end prod-Sentry assertion has no keyboard-triggerable path from CI, so it is NOT claimed.) expected_output: test green = the op is wired
```

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from 2026-06-01 brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** Both items extend established patterns — no ADR, no new service/schema. Item 1 reuses `detect-installation`; item 2 extends the existing cron with a deterministic `latest-row-ok:false` signal that avoids the idle-repo false-positive trap. Ship item 1 first.

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** No statutory clock / DPA trigger. GitHub renders its own re-auth consent. Item 2 processes no new personal data; hashed-userId logging satisfies data-minimization. Honest reconnect CTA is the only soft requirement. **Satisfies Phase 2.7 GDPR gate** — see Compliance note below.

### Product/UX Gate
**Tier:** blocking (mechanical escalation: new component file `components/repo/reconnect-notice.tsx`).
**Decision:** reviewed.
**Agents invoked:** spec-flow-analyzer, ux-design-lead (CPO carried from brainstorm `## Domain Assessments`).
**Pencil available:** yes.
**Wireframes:** `knowledge-base/product/design/settings/kb-reconnect-affordance.pen` (+ screenshots `04-project-setup-card-needs-reconnect-variant.png`, `05-kb-reconnect-notice-inline-banner.png`). Three states per surface (default / Reconnecting… / cleared), Solar Forge tokens, amber notice family mirroring the existing red treatment.

#### Findings
spec-flow surfaced 5 journey gaps, all folded into the revised phases: P0-2 wrong refresh primitive (→ `refreshTree` on KB surface, Phase 1.5), P0-1 dropped `return_to` (→ persist `soleur_return_to`, Phase 1.2), P0-3 no in-flight state (→ `isPending`, Phase 1.2), P1-1 no success confirmation (→ confirmation in `<ReconnectNotice>`, Phase 1.3). **Deferred — P1-2 repo-scope mismatch:** `detect-installation` returns `{installed:true}` for ANY owned installation without verifying the install covers the *workspace's* repo, so reconnect can report success while the repo stays uncovered → silent re-freeze (a went-quiet case, no new `kb_sync_history` rows). Out of scope here; tracked by the went-quiet detector **#4717** (the failure-based heuristic in PR 2 only catches repos that DO sync-and-fail). Documented in Sharp Edges.

## Compliance (GDPR Gate — Phase 2.7)

Trigger (b) fires (single-user-incident threshold) and the diff touches API routes. The gate's intent is satisfied by the brainstorm CLO pass, which did article-level analysis on this exact scope (no Art. 33/34 event — stale-but-intact git-backed data is a product-quality defect, not a personal-data breach; no new processing activity; no Art. 30 amendment; hashed-userId Sentry logging within existing PA). No new schema/migration/external egress is introduced. `data-integrity-guardian` re-checks at deepen-plan as the secondary gate.

## Open Code-Review Overlap

None — checked all planned files against 74 open `code-review` issues (2026-06-01); zero overlap.

## Plan-Review Reconciliation (5-agent panel, 2026-06-01)

| Finding | Source | Disposition |
|---|---|---|
| `router.refresh()` won't clear the KB notice (client state) — the dead-end this feature exists to prevent | spec-flow P0-2, Kieran | **Fixed** — KB surface uses `refreshTree()` (Phase 1.5) |
| `return_to` query param dropped on OAuth round-trip | spec-flow P0-1 | **Fixed** — persist `soleur_return_to` before redirect (Phase 1.2) |
| No in-flight/loading state → dead-button feel + double-POST | spec-flow P0-3 | **Fixed** — `isPending` (Phase 1.2) |
| `needsReconnect` derived in 3 places = selector-divergence (the incident's bug class) | DHH #1, simplicity | **Fixed** — single `repoNeedsReconnect()` (Phase 1.0) |
| `/api/repo/status` derivation is dead code | simplicity, DHH | **Cut** — verified only `connect-repo` consumes it, reads `status` only |
| Two near-identical notices | DHH #3, simplicity | **Fixed** — one shared `<ReconnectNotice variant>` (Phase 1.3) |
| Cron test mock throws on non-`workspaces` table → PR2 reds whole file | Kieran P0-1 | **Fixed** — explicit mock-widen step (Phase 2.1) |
| Item-2 findings must not widen `ScanResult` (breaks reporting test) | Kieran P0-2 | **Fixed** — report-in-place, return count (Phase 2.1) |
| Guard must read `at(-1)`, not `.some()` | Kieran P2-3 | **Fixed** — `historyArr.at(-1)` (Phase 2.1) |
| Component env is happy-dom, not jsdom | Kieran P1-1 | **Fixed** — tests note happy-dom `window.location` mocking |
| `dashboard/page.tsx` 2nd `/api/kb/tree` consumer; `connect-repo` `/api/repo/status` fetches | Kieran P1-2 | **Asserted non-breaking** — both read `.tree`/`status` only; widening is additive |
| repo-scope mismatch re-freeze loophole | spec-flow P1-2 | **Deferred to #4717** — documented in Sharp Edges |
| `use-reconnect` hook + two-PR split are justified, keep | DHH #2/#5, simplicity | No change |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Flip `repo_status='error'` to reuse the existing Retry-Setup path | Rejected in #4706: would degrade the KB tree; use a new derived flag |
| Item-2 time-based "no `ok:true` in N days" (issue wording) | Highest false-positive (idle repos look frozen); deferred to **#4717** (went-quiet arm) |
| Dashboard ambient banner for item 1 | Learnings re-audit: small population → settings card + point-of-pain notice, not an ambient banner |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — it is filled above.
- Item-2 scans `users` (history lives there), item-1 scans `workspaces` — do not "unify" the scan table; the divergence is correct (ADR-044 did not mirror history).
- New component tests MUST live under `test/components/**` (the `component` project is **happy-dom**, not jsdom; `setupFiles: test/setup-dom.ts`), not co-located — `vitest.config.ts` only collects `test/**/*.test.tsx` (#4634). Mock `window.location` the happy-dom way (it is not trivially reassignable).
- **Item-2 `at(-1)` latest-row correctness has a latent coupling (deepen data-integrity P1).** Reading `historyArr.at(-1)` is the true latest only because the rich-row writer `appendKbSyncRow` routes through the atomic `append_kb_sync_row` RPC (migration 053, `jsonb_agg ORDER BY ord`) AND the legacy `recordKbSyncHistory`'s non-atomic `[...].slice(-14)` tenant UPDATE is **blocked** (migration 006 column grant + 017 RESTRICTIVE policy → silent no-op in prod). If a future migration re-grants `kb_sync_history` UPDATE to `authenticated`, the legacy writer could clobber/reorder rich rows and break the `at(-1)` assumption. Do not re-grant without revisiting this scan.
- **Item-2 is solo/owner-row detection (deepen data-integrity P1).** The `users`-scan reliably covers the #4706 incident class (solo workspaces, where repo state + history co-reside on `users`). For team workspaces (`workspace.id != owner.user.id`), `kb_sync_history` lives only on the **owner's** `users` row while repo-connection state is authoritative on `workspaces` (ADR-044/079) — so a failing team workspace can escape item-2 if reconcile didn't write history to the owner row. Treat team-workspace stale-detection as a known gap alongside the went-quiet #4717; do not try to close it here.
- **Do not interpolate PII into the item-2 cron `Error` message (deepen security).** `reportSilentFallback` hashes `extra.userId` but NOT the `Error.message` (`event.exception.values[].value`). Keep the message a static literal; pass identifiers only via `extra:{ userId }`.
- **Reconnect repo-scope mismatch (known limitation, deferred to #4717).** `detect-installation` returns `{installed:true}` for ANY owned GitHub-App installation; it does not verify the installation covers the *workspace's* specific repo. So a reconnect can store an install id (clearing `needsReconnect`) while the workspace repo stays uncovered → no webhook → no new `kb_sync_history` rows → silent re-freeze that neither item-1 (install now non-null) nor item-2 (no `ok:false` row is ever written) catches. This is the went-quiet class the #4717 follow-up targets; do NOT try to solve it here.
