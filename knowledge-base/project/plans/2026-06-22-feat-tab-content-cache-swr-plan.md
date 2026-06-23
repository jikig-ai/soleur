---
feature: tab-content-cache
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVED 2026-06-22 (conditions C1 in-memory-only, C2 sign-out clear+test)
issue: 5640
pr: 5639
brainstorm: knowledge-base/project/brainstorms/2026-06-22-tab-content-cache-brainstorm.md
spec: knowledge-base/project/specs/feat-tab-content-cache/spec.md
---

# ✨ feat: cache tab content for instant view switching (SWR)

## Overview

Switching between the web-platform dashboard views (Dashboard, Inbox, Knowledge Base, Routines)
re-fetches all content every time because each view fetches via plain `fetch()`/Supabase-query +
`useEffect` + `useState`, and unmounts on navigation — discarding state and re-fetching on remount.
There is no client-side cache.

Adopt **SWR** (Vercel's stale-while-revalidate library): migrate the affected fetch hooks to
`useSWR` so a returning view renders cached content **instantly** (no spinner) and revalidates
**quietly in the background**, updating in place if data changed. **In-memory / session-only** — no
content persisted to disk. The single load-bearing risk is cache **scoping/invalidation**: the cache
MUST clear on sign-out and workspace switch so one user/workspace never sees another's content
(brand-survival threshold = single-user incident).

Decisions carried from brainstorm + plan-phase gates:
- Library: **SWR**. Freshness: **stale-while-revalidate**. Persistence: **in-memory only** (CPO C1).
- Scope: **all four main views in one PR** (operator choice).
- Refresh affordance: **Option A — ambient thin gold top shimmer** during background revalidation
  (operator choice). **Do NOT surface any "from cache" status** to the user — the cache is invisible;
  only the shimmer appears while revalidating.
- Conversation/agent **live-status is realtime-backed** (Supabase realtime → SWR `mutate()`), never
  served stale-then-revalidate (CPO freshness flag).

## Research Reconciliation — Spec vs. Codebase

| Spec / assumption | Reality (verified) | Plan response |
|---|---|---|
| "all views fetch via plain `fetch()`" | True for Inbox/KB/Routines/Dashboard; **`use-conversations.ts` uses a Supabase client query**, not HTTP `fetch` (`hooks/use-conversations.ts:229`) | SWR fetcher wraps the Supabase query; same `useSWR(key, fetcher)` shape |
| "clear cache on workspace switch" | Workspace switch does a **hard** `window.location.assign("/dashboard")` (`org-switcher-container.tsx:126`) → clears in-memory cache *by accident*; NOT reached in the offline post-RPC "park" window | Add explicit clear at RPC-commit + disable `revalidateOnReconnect` for content keys (GAP B) |
| "clear cache on sign-out" | Sign-out is a **soft** `router.push("/login")` (`use-sign-out.ts:64`) — SWR's module-singleton cache **survives**; confirmed cross-user leak vector | Explicit awaited cache clear before navigation + regression test (GAP A, CPO C2) |
| "filter-aware caching" | Inbox `?status=archived` (`inbox-surface.tsx:42`); Dashboard has **5 independent fetches**; Routines Recent-Runs is keyset-paginated | Per-filter cache keys; Recent Runs uses `useSWRInfinite` (or documented scope-cut) |
| Dashboard skeleton gate | `if (kbLoading) return <skeleton>` (`dashboard/page.tsx`) | Gate on `!data`, never `isValidating` (GAP F regression trap) |

## User-Brand Impact

**If this lands broken, the user experiences:** dashboard views that show another user's or another
workspace's cached content (inbox subjects, conversation titles, KB contents) after a sign-out +
different-user login on the same tab, or after a workspace switch.

**If this leaks, the user's data is exposed via:** the in-memory SWR cache surviving an auth/workspace
change and being rendered instantly to the next principal before background revalidation replaces it.

**Brand-survival threshold:** single-user incident.

CPO sign-off obtained at plan time (frontmatter). `user-impact-reviewer` runs at review time
(review/SKILL.md conditional-agent block).

## Open Code-Review Overlap

2 open code-review issues touch files this plan edits:
- **#2590** — `refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer from DashboardPage` (`dashboard/page.tsx`). **Acknowledge** — orthogonal (component extraction, not data-fetching). SWR migration of the 5 fetches does not conflict; issue stays open.
- **#2193** — `refactor(billing): unify past_due/unpaid banners ... in layout` (`(dashboard)/layout.tsx`). **Acknowledge** — orthogonal (banner unification). Mounting `<SWRConfig>` does not conflict; issue stays open.

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-067 — Adopt SWR for client-side data caching (stale-while-revalidate)** via
`/soleur:architecture` as an in-scope task of this feature (not a follow-up). Decision: client data
fetching in the dashboard standardizes on SWR with an **in-memory, session-only** cache; the cache is
**cleared on sign-out and workspace switch** to preserve single-(user,workspace) isolation;
realtime-backed surfaces (conversations) drive the cache via `mutate()`. Record alternatives
considered (TanStack Query; custom in-memory cache) per the brainstorm.

### C4 views
**No C4 impact.** Verified against all three model files (`model.c4`, `views.c4`, `spec.c4`):
- **External human actors** (`founder`, `emailSender`): SWR adds none.
- **External systems/vendors** (anthropic, github, cloudflare, doppler, discord, stripe, plausible,
  resend): SWR is an in-process npm library, not a networked third party — no new edge.
- **Containers/data-stores**: the `dashboard` (React) container is a model leaf (no L3 webapp
  component view); an in-memory client cache is internal to it — no element to add.
- **Access relationships** (`founder→dashboard→api→supabase`): caching changes fetch *timing*, not
  access topology.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Net simplification — SWR replaces hand-rolled fetch/effect/state plumbing with a proven
primitive. Main risks: Supabase realtime → `mutate()` wiring for conversations, per-filter cache keys,
and the skeleton-gate regression trap. All addressed in Implementation Phases.

### Legal / Data-handling (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** In-memory/session-only caching keeps no user content at rest → no new retention/DSAR
surface. The only data-handling requirement is cache invalidation on workspace switch / sign-out (FR4),
which is the load-bearing safeguard. See GDPR note below (trigger (b) fired).

### Product/UX Gate
**Tier:** blocking (mechanical UI-surface override — edits `app/(dashboard)/dashboard/page.tsx`,
`components/inbox/inbox-surface.tsx`, `components/routines/routines-surface.tsx`)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes (`.pen` committed: `knowledge-base/product/design/tab-content-cache/swr-loading-states.pen`)

#### Findings
- **CPO:** APPROVE with binding conditions **C1** (in-memory only) and **C2** (explicit sign-out clear +
  test). Freshness flag: conversation/agent live-status must not be served stale → realtime→`mutate()`.
- **spec-flow-analyzer:** GAP A (sign-out soft-nav leak — CRITICAL), GAP B (workspace-switch offline-park
  + `revalidateOnReconnect` cross-workspace write — CRITICAL), GAP #4 (stale-revalidation-failure UI —
  per-view decision), GAP D (Routines optimistic-run vs `revalidateOnFocus`), GAP E (Recent Runs
  pagination), GAP F (skeleton must gate on `!data`). All folded into phases/ACs below.
- **ux-design-lead:** wireframes committed + operator-approved. Operator decisions: ship Option A
  (ambient gold shimmer); **do not show any cache-status indicator**; keep the stale-failure retry bar.

## Implementation Phases

> **Phase order is load-bearing:** the safety foundation (cache provider + clear wiring) ships in
> Phase 1 BEFORE any consumer migration, so no view can be cached without the clear in place.

### Phase 0 — Preconditions
- `cd apps/web-platform && grep '"swr"' package.json` → confirm absent.
- Confirm SWR is mature (published ≫ 3 days ago) so the `minimumReleaseAge = 259200` gate
  (`bunfig.toml`, #1174) does NOT fire — no temporary override needed.
- Re-read `dashboard/page.tsx`, `use-conversations.ts`, `org-switcher-container.tsx`, `use-sign-out.ts`
  before editing (`hr-always-read-a-file-before-editing-it`).

### Phase 1 — Safety foundation (provider + cache-clear wiring)
**Files to create:**
- `apps/web-platform/lib/swr-config.ts` — exported global SWR config object + a `clearSwrCache(mutate)`
  helper (`mutate(() => true, undefined, { revalidate: false })`) + typed cache-key builders. Global
  config: `revalidateOnFocus: true`, **`revalidateOnReconnect: false`** for content keys (GAP B),
  `dedupingInterval` sane default.

**Files to edit:**
- `apps/web-platform/app/(dashboard)/layout.tsx` — mount `<SWRConfig value={swrConfig}>` wrapping the
  provider stack (above `<TeamNamesProvider>`, ~line 254). It is already `"use client"`. Keep the
  provider at a **structurally stable position** (provider-tree stability — cf. #5632 remount fix).
- `apps/web-platform/components/auth/use-sign-out.ts` — **await `clearSwrCache(mutate)` before**
  `router.push("/login")` (between `removeAllChannels()` @31 and the push @64). Defense-in-depth:
  also clear on Supabase `onAuthStateChange("SIGNED_OUT")`. (FR4, CPO C2, GAP A.)
- `apps/web-platform/components/dashboard/org-switcher-container.tsx` — call `clearSwrCache(mutate)`
  immediately AFTER the `set_current_workspace_id` RPC commits (~line 190), before the hard reload, so
  the offline post-RPC park window cannot revalidate stale workspace-A keys (GAP B). Keep the hard
  `window.location.assign` as defense-in-depth.

### Phase 2 — Migrate simple GET views to `useSWR`
- `apps/web-platform/components/inbox/inbox-surface.tsx` — `useSWR(["/api/inbox/emails", status], fetcher)`;
  key includes `status` filter (FR5). Gate loading on `!data` (GAP F). Add stale-failure retry bar (below).
- `apps/web-platform/hooks/use-kb-layout-state.tsx` — `/api/kb/tree` and `/api/chat/thread-info` (keyed by
  `contextPath`) via `useSWR`.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — migrate all **5** fetches to distinct `useSWR`
  keys (`/api/kb/tree`, `/api/dashboard/today`, `/api/inbox/emails`, `/api/workspace/active-repo`, orphan
  count). The KB-tree gate `if (kbLoading) return <skeleton>` must become `if (!kbData) return <skeleton>`
  — never gate on `isValidating` (GAP F). Note `/api/inbox/emails` is shared with Inbox → free dedup.
- `apps/web-platform/components/routines/routines-surface.tsx` — main Routines list via `useSWR`.

### Phase 3 — Conversations (Supabase query + realtime → mutate)
- `apps/web-platform/hooks/use-conversations.ts` — `useSWR(["conversations", {statusFilter, domainFilter,
  archiveFilter, limit}], supabaseFetcher)`. Convert the realtime **INSERT** (@359-390) and **UPDATE**
  (@328-351) handlers from `setConversations(...)` to `mutate(key, updater, { revalidate: false })`,
  preserving `shouldDropForScope()` (@109-125). `archiveConversation`/`unarchiveConversation`/`updateStatus`
  → optimistic `mutate`. This keeps live agent-status push-fresh (CPO freshness flag, TR3).

### Phase 4 — Refresh affordance + stale-failure UI
**Files to create:**
- `apps/web-platform/components/ui/refresh-shimmer.tsx` — Option A: a ~2px gold (`--accent-gold-fg` /
  `#C9A962`) top progress shimmer shown when `isValidating && data` (background revalidation of a cache
  hit). No layout shift, no input block, brand palette tokens (no raw hex). **No cache-status indicator.**
- Stale-failure affordance: in Inbox and Routines, when `error && data` (revalidation failed while stale
  data is shown), render a subtle dismissible "Couldn't refresh — Retry" bar alongside the stale content
  (GAP #4). KB/Dashboard foundation cards: silent + SWR auto-retry (default backoff).

### Phase 5 — Recent Runs pagination (Routines sub-tab)
- `apps/web-platform/components/routines/routines-surface.tsx` (RunLogView ~line 550) — migrate keyset
  pagination to `useSWRInfinite` to preserve accumulated pages across remount (GAP E). Suppress
  `revalidateOnFocus` for the in-flight optimistic "Run now" key until the 5s reconcile lands (GAP D).
  **Permitted scope-cut:** if `useSWRInfinite` proves disproportionate, leave Recent Runs on its current
  fetch (it is a secondary client-state sub-tab, not a top-level nav view) and record the deferral.

### Phase 6 — Tests + ADR + verification
- Create tests (all under `test/**` per vitest globs; `.test.tsx` → happy-dom project).
- Author **ADR-067** via `/soleur:architecture`.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`; root has no workspaces).
- Run targeted tests: `./node_modules/.bin/vitest run <path>`.

## Files to Edit (summary)
- `apps/web-platform/package.json` (add `swr`)
- `apps/web-platform/app/(dashboard)/layout.tsx`
- `apps/web-platform/components/auth/use-sign-out.ts`
- `apps/web-platform/components/dashboard/org-switcher-container.tsx`
- `apps/web-platform/components/inbox/inbox-surface.tsx`
- `apps/web-platform/hooks/use-kb-layout-state.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- `apps/web-platform/components/routines/routines-surface.tsx`
- `apps/web-platform/hooks/use-conversations.ts`

## Files to Create
- `apps/web-platform/lib/swr-config.ts`
- `apps/web-platform/components/ui/refresh-shimmer.tsx`
- `apps/web-platform/test/swr-cache-clear-on-signout.test.tsx`
- `apps/web-platform/test/inbox-surface-cache.test.tsx`
- `apps/web-platform/test/use-conversations-realtime-mutate.test.tsx`
- `knowledge-base/engineering/architecture/decisions/ADR-067-adopt-swr-client-cache.md`

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (FR1):** Returning to a previously-visited view renders cached content with no loading
      spinner — test asserts `fetch`/fetcher is NOT called on remount when cache is warm (invariant:
      zero refetch on cache-hit remount; spy on call count, not DOM presence).
- [ ] **AC2 (FR2/GAP F):** Background revalidation never re-shows the first-load skeleton — dashboard
      gates skeleton on `!data`, not `isValidating`; test asserts skeleton absent on warm remount.
- [ ] **AC3 (FR4/C2/GAP A — load-bearing):** After sign-out, the SWR cache is empty. Test: populate
      cache as user A → `useSignOut` → assert no user-A key survives (cleared before navigation).
- [ ] **AC4 (FR4/GAP B):** Workspace switch clears the cache at RPC-commit; `revalidateOnReconnect` is
      OFF for content keys. Test asserts content keys are not revalidated in the offline-park window.
- [ ] **AC5 (FR5):** Inbox active vs archived cache under distinct keys — switching filter shows
      cached-instant if previously loaded; no key collision.
- [ ] **AC6 (TR3):** Conversations realtime INSERT/UPDATE drive `mutate()` (not `setState`); test fires a
      mock realtime event and asserts the cache key updated and `shouldDropForScope` honored.
- [ ] **AC7 (refresh UI):** The ambient gold shimmer renders only when `isValidating && data`; no
      "from cache" status indicator exists anywhere.
- [ ] **AC8 (stale-failure):** Inbox/Routines render the "Couldn't refresh — Retry" bar when `error &&
      data`; stale content stays visible (no full error screen).
- [ ] **AC9:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; new tests pass.
- [ ] **AC10 (C1):** No content persisted to disk — no `localStorage`/`sessionStorage`/persistent SWR
      provider for content (grep confirms cache provider is in-memory only).
- [ ] **AC11 (ADR/C4):** ADR-067 committed in this PR; C4 "no impact" rationale recorded (this plan).

### Post-merge (operator)
- [ ] **AC12:** None required — pure client-side code change against already-provisioned surfaces; PR
      merge restarts the container via `web-platform-release.yml`. Use `Ref #5640` in the PR body and
      close on verify (not `Closes` — though this is a normal feature, no post-merge prod write).

## Test Scenarios
1. Warm-cache remount → zero refetch, instant render (AC1).
2. Sign-out as A → sign-in as B same tab → B never sees A's cached inbox/conversations (AC3).
3. Workspace switch → cache cleared, no cross-workspace key write (AC4).
4. Inbox active↔archived filter → separate caches, instant on return (AC5).
5. Realtime conversation UPDATE while mounted → in-place mutate, no full refetch (AC6).
6. Revalidation network failure while stale data shown → retry bar appears, stale data retained (AC8).

## Risks & Mitigations
- **Cross-user leak via surviving cache (single-user incident):** explicit awaited clear on sign-out +
  onAuthStateChange; regression test (AC3). Highest-severity risk; mitigated in Phase 1.
- **Cross-workspace key write in offline-park window:** clear at RPC-commit + `revalidateOnReconnect:
  false` for content keys (AC4).
- **Skeleton flash regression:** gate on `!data` (AC2).
- **Optimistic "Run now" reverted by focus revalidation:** suppress `revalidateOnFocus` for that key
  until reconcile (Phase 5).
- **New dependency supply-chain:** SWR is mature; `minimumReleaseAge` gate won't fire; `bun add swr`
  normally. Follow `cq-before-pushing-package-json-changes`.
- **Provider-tree instability** re-introducing remounts: keep `<SWRConfig>` at a stable tree position
  (cf. #5632).

## Observability
Gate does not fire — all edited code is client-side (`app/`, `components/`, `hooks/`), none under
`apps/*/server/`, `apps/*/src/`, or `apps/*/infra/`, and no new infra surface. Error surfacing is
client-only: SWR `onError` flows into the existing error states + the new stale-failure retry bar; no
new server error paths are introduced.

## GDPR Note
`gdpr-gate` trigger (b) fired (brand_survival_threshold = single-user incident). Disposition: the
in-memory-only design (no content at rest) + clear-on-sign-out/workspace-switch (FR4) IS the
data-minimization/retention control. No schema, migration, auth-flow, `.sql`, or API-route surface is
touched and no new processing activity is created (the cache holds data the user already accesses). The
diff-level `/soleur:gdpr-gate` scan runs at `/work`/review where a diff exists (advisory).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6 — this section is filled above.
- Test `.test.tsx` files MUST live under `test/**` (happy-dom vitest project); a co-located
  `components/**/*.test.tsx` is silently never run.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — `npm run -w` fails (no root
  `workspaces`).
- `bunfig.toml` `[test] pathIgnorePatterns = ["**"]` blocks `bun test` — use vitest only.
- `use-conversations.ts` fetches via Supabase client query, not HTTP `fetch` — SWR fetcher wraps the
  query; tests mock the Supabase client, not `fetch`.
