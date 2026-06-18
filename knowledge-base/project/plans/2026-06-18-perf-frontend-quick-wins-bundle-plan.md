---
title: "perf: frontend performance quick-wins bundle (2026-06-18 audit)"
type: perf
branch: feat-one-shot-perf-quick-wins
date: 2026-06-18
lane: single-domain
brand_survival_threshold: none
status: draft
related_issues: ["#5531", "#5532", "#5533", "#5534", "#5535", "#5536"]
---

# perf: Frontend performance quick-wins bundle (2026-06-18 audit)

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Implementation Phases (H3 precedent, M4 field-completeness, M1 call-site enumeration), Risks, Domain Review (4.9 determination)
**Passes run:** hard gates 4.6/4.7/4.8/4.9; verify-the-negative pass (5 claims, all `confirms`); precedent-diff (H3 `Promise.all`, M4 explicit-select).

### Key Improvements
1. **H3 precedent confirmed:** the codebase already parallelizes independent Supabase awaits with `Promise.all` in async server components — `app/(dashboard)/dashboard/settings/page.tsx:31` and `app/(dashboard)/dashboard/admin/analytics/page.tsx:27`. The chat layout fix follows an established in-repo pattern. (Caveat: `chat/layout.tsx` is structured so only the invites fetch is independent — the delegation chain is sequential — so the canonical fix is "start invites early, await both," a partial `Promise.all`, not a full one.)
2. **M4 field-completeness verified:** the 17-column explicit list is EXACTLY the `Conversation` interface field set (types.ts:580-603) — no field missing, none extra. Confirmed the rows are spread (`...conv` at use-conversations.ts:286), so the full set is required.
3. **M1 call-site enumeration:** `startSession` has exactly two call sites (chat-surface.tsx:352, :358), both inside the single guarded session-start effect (:347-365). Adding `contextPending` to that effect's guard is the complete and only change needed to preserve the once-only `initialContext` delivery.
4. **R3 downgraded:** no existing test pins the literal `.select("*")` argument (all test mocks are `select: vi.fn(() => chain)` ignoring the arg), so the M4 refactor cannot break a mock on the arg string.

### New Considerations Discovered
- The 4.9 UI-Wireframe gate's glob superset matches `components/**/*.tsx` (the M1 `chat-surface.tsx` edit). Determination: the edit adds only a boolean prop + an effect-guard clause (no new JSX surface, layout, or flow) → UI-surface tier NONE, no `.pen` required (see Domain Review). Documented explicitly so the gate's mechanical match does not surprise a reviewer.

## Overview

Four independent, low-risk frontend performance fixes in `apps/web-platform`, drawn from the 2026-06-18 frontend performance audit. Each is mechanical and behavior-preserving (modulo the one deliberate UX improvement: a skeleton instead of a blank screen). They ship in **one PR**.

| Tag | Fix | File(s) | Risk |
|-----|-----|---------|------|
| H4 | Add `loading.tsx` streaming skeletons to 5 hot dashboard segments | `app/(dashboard)/dashboard/{,chat/,chat/[conversationId]/,kb/,settings/}loading.tsx` (NEW) | low |
| H3 | Parallelize `getPendingInvitesForUser` with the delegation branch via `Promise.all` | `app/(dashboard)/dashboard/chat/layout.tsx` | low |
| M4 | Replace `.select("*")` with an explicit column list on the conversations query | `hooks/use-conversations.ts` | low |
| M1 | Render `ChatSurface` with a context-pane loading state instead of `return null` | `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (+ `components/chat/chat-surface.tsx`) | low-med |

**NO behavior changes beyond these four.** The audit's larger structural items (H1 root-layout dynamic rendering, H2 dashboard-chrome client→server conversion, M3 dashboard-home triple-fetch, M2 list virtualization, plus the cache-audit reliability/security items) are tracked as dedicated follow-up issues **#5531–#5536** and are **out of scope** for this PR (contextual links only — this PR does **not** close them).

## Research Reconciliation — Spec vs. Codebase

The feature description ("ARGUMENTS") makes a few claims that the codebase contradicts or refines. Resolved as follows:

| Claim (from arguments) | Reality in codebase | Plan response |
|---|---|---|
| "reuse existing Mantine skeleton components" for `loading.tsx` | There are **no Mantine `Skeleton` usages** anywhere in `apps/web-platform`. Every existing skeleton is hand-rolled Tailwind `animate-pulse` over `bg-soleur-bg-surface-2` — the analytics `loading.tsx`, `components/kb/loading-skeleton.tsx`, `components/kb/kb-content-skeleton.tsx`. (`@mantine/core` 8.3.15 IS a dependency, but `Skeleton` is unused.) | **Mirror the actual pattern** (hand-rolled `animate-pulse`, per the analytics `loading.tsx` and KB skeletons) — this is what "mirror the existing pattern at `…/admin/analytics/loading.tsx`" literally instructs. Do NOT introduce the first Mantine `Skeleton`; it would be a net-new convention, contradicting the "mirror existing" instruction. |
| H4 goal: "stream a skeleton during the server data-fetch" for all 5 segments | Only `settings/page.tsx` is an async **server** component (awaits Supabase). `dashboard/page.tsx`, `chat/[conversationId]/page.tsx`, and `kb/layout.tsx` are `"use client"`; `chat/page.tsx` is a `redirect()` stub and the chat segment's async work lives in `chat/layout.tsx`. | `loading.tsx` is still useful for **all 5** segments: for `settings` it streams during the server data-fetch (the stated goal); for the client segments + the chat layout it renders during the App-Router segment-navigation RSC fetch/render window. Capture the mechanism difference in the FRs; do NOT overstate "server data-fetch" uniformly. |
| M1: "it returns `null` … while a client fetch of `/api/kb/content` resolves" | Confirmed at `chat/[conversationId]/page.tsx:54` (`if (contextLoading) return null;`). BUT the inline comment (lines 51-53) documents the gate as **load-bearing**: it ensures `ChatSurface`'s one-shot session-start effect receives `initialContext` in the same WS bootstrap rather than racing. | M1 is **not** a one-line delete. The fix must render `ChatSurface` immediately yet still defer the *session-start* until context resolves (or fails) — by threading a `contextPending` flag into `ChatSurface` so its session-start `useEffect` (chat-surface.tsx:347-365) waits, not by gating the whole mount. See M1 phase for detail. |
| M4: `.select("*")` "at ~line 231" | Confirmed at `hooks/use-conversations.ts:231`. Rows are cast `as Conversation` and **spread** (`...conv`) into `ConversationWithPreview` (line 285), so any consumer of the rail rows can read any `Conversation` field. | The explicit column list MUST be the **complete** `Conversation` interface field set (types.ts:580-603), not a guessed subset — see M4 phase. Wire-size win comes from excluding columns NOT in the `Conversation` type (e.g. server-only/uncast DB columns), not from dropping typed fields. |
| Issues #5531–#5536 are follow-ups | All six are **OPEN** (verified via `gh issue view`) and each references the same 2026-06-18 audit. | Reference them in the PR body as contextual follow-ups; use `Ref #N` phrasing, never `Closes #N`. |

## User-Brand Impact

**If this lands broken, the user experiences:** a blank chat conversation pane that never loads its KB context (M1 regression if the session-start race is reintroduced), an empty conversations rail (M4 regression if a consumed column is dropped from the explicit select), or a stuck/flashing skeleton during navigation (H4). All are recoverable by reload; none corrupts or exposes data.

**If this leaks, the user's data is exposed via:** N/A — no new data is read, written, transmitted, or logged. M4 *narrows* the columns fetched (strictly less data on the wire); H3 only reorders existing awaits; H4 renders static placeholder markup; M1 renders the same `ChatSurface` it already renders.

**Brand-survival threshold:** none — pure client/route refactor on an already-provisioned surface, no new data movement, no schema/auth/migration/regulated-data surface touched. Threshold-none scope-out reason: this PR touches only `app/(dashboard)/**` route/render files and one client hook's query column list; it adds, reads, writes, and transmits no personal data and crosses no auth or trust boundary.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (H4):** Five new files exist and each `export default` a component: `app/(dashboard)/dashboard/loading.tsx`, `app/(dashboard)/dashboard/chat/loading.tsx`, `app/(dashboard)/dashboard/chat/[conversationId]/loading.tsx`, `app/(dashboard)/dashboard/kb/loading.tsx`, `app/(dashboard)/dashboard/settings/loading.tsx`.
  Verify: `for f in dashboard dashboard/chat "dashboard/chat/[conversationId]" dashboard/kb dashboard/settings; do test -f "apps/web-platform/app/(dashboard)/$f/loading.tsx" && echo "OK $f" || echo "MISSING $f"; done` → 5 `OK`.
- [ ] **AC2 (H4):** Each new `loading.tsx` uses the hand-rolled `animate-pulse` + `bg-soleur-bg-surface-2` skeleton idiom (no `@mantine` `Skeleton` import). Verify: `grep -L "animate-pulse" <each new file>` returns nothing (all contain it); `grep -rl "from \"@mantine.*Skeleton\|Skeleton }" apps/web-platform/app/(dashboard)/dashboard/*/loading.tsx` returns nothing.
- [ ] **AC3 (H3):** In `chat/layout.tsx`, `getPendingInvitesForUser` is awaited inside a `Promise.all` (or `await`ed on a promise started before the delegation branch), NOT serially after it. Verify by reading the diff: the `getPendingInvitesForUser(...)` call no longer sits below the closed delegation `if`-block as a standalone `await`; instead its promise is created at the top of the `if (user)` block and resolved via `Promise.all([...])`. The delegation chain's internal awaits (`resolveCurrentOrganizationId` → `isByokDelegationsEnabled` → `resolveCurrentWorkspaceId` → `resolveGranteeDelegation` → `resolveGranteeAcceptanceStatus`) keep their original sequential ordering.
- [ ] **AC4 (M4):** `hooks/use-conversations.ts:~231` no longer contains `.select("*")` on the `conversations` query; it contains an explicit comma-separated column list. Verify: `awk 'NR>=225 && NR<=240' apps/web-platform/hooks/use-conversations.ts | grep -c '\.select("\*")'` → `0`. The column list equals the full `Conversation` interface field set: `id, user_id, domain_leader, session_id, status, total_cost_usd, input_tokens, output_tokens, last_active, created_at, archived_at, context_path, repo_url, active_workflow, workflow_ended_at, workspace_id, visibility` (verified against `lib/types.ts:580-603`).
- [ ] **AC5 (M1):** `chat/[conversationId]/page.tsx` no longer has `if (contextLoading) return null;`. It renders `<ChatSurface variant="full" … />` unconditionally, passing a flag (e.g. `contextPending={contextLoading}`) so `ChatSurface` defers its session-start until context resolves. Verify: `grep -c "return null" apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` → `0` (or only inside the `useEffect` early-return `if (!contextParam) return;`, which is a different statement — confirm no bare `return null` remains at the component body).
- [ ] **AC6 (M1):** The WS session-start invariant is preserved — for a `conversationId === "new"` session with `?context=`, `startSession` still receives `initialContext` (the KB content), not `undefined`. Verify via the existing chat-surface session-start tests staying green AND a new/extended test asserting `startSession` is called with the resolved `initialContext` only after `contextPending` flips false. (See Test Strategy.)
- [ ] **AC7 (gate):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC8 (gate):** `cd apps/web-platform && npm run lint` exits 0 (or reports no new errors on touched files).
- [ ] **AC9 (gate):** `cd apps/web-platform && npm run test:ci` — full suite green (no regressions in the existing `use-conversations-*`, `conversations-rail-*`, `chat-surface-*`, `chat-page*` suites).
- [ ] **AC10 (scope):** PR body references the 2026-06-18 audit and links #5531–#5536 as follow-ups with `Ref` (not `Closes`).

### Post-merge (operator)

- [ ] **AC11:** None. This is a pure code change deployed by the standard `web-platform-release.yml` pipeline on merge to main; no migration, no Terraform, no Doppler, no manual step. The merge IS the deploy.

## Implementation Phases

### Phase 1 — H4: `loading.tsx` skeletons (5 files, NEW)

Mirror `app/(dashboard)/dashboard/admin/analytics/loading.tsx` (hand-rolled `animate-pulse` divs over `bg-soleur-bg-surface-2`, wrapped in the segment's layout container classes). Each skeleton should roughly echo the *shape* of the real segment so the swap-in is not jarring, but exactness is not required (skeletons are deliberately coarse). Suggested shapes:

1. `dashboard/loading.tsx` — home: a banner strip + a vertical list of ~6 conversation-row skeletons (`h-16` cards). Mirror the `max-w` container the home page uses.
2. `dashboard/chat/loading.tsx` — chat composer chrome: a centered composer card skeleton (this segment's async work is the layout's delegation/invite resolution; the skeleton streams while that resolves).
3. `dashboard/chat/[conversationId]/loading.tsx` — a conversation transcript skeleton: alternating left/right message bubbles (~5) + a composer bar at the bottom.
4. `dashboard/kb/loading.tsx` — KB shell: a sidebar tree skeleton (reuse the *shape* of `components/kb/loading-skeleton.tsx`) beside a content-area skeleton. **Do not import** the client `LoadingSkeleton` into a route `loading.tsx` blindly — `LoadingSkeleton` lives in a `"use client"` module; importing it from a server `loading.tsx` is allowed (client components render fine inside server components) but simplest is to inline equivalent `animate-pulse` markup to keep `loading.tsx` a pure server component with zero client boundary. Inline is the chosen approach.
5. `dashboard/settings/loading.tsx` — settings cards: ~3 stacked card skeletons (`rounded-xl border border-soleur-border-default` shells with `animate-pulse` inner rows). This is the one true "stream during server data-fetch" win (settings page is async server).

Each file:
```tsx
export default function <Seg>Loading() {
  return (
    <div className="<segment container classes>">
      {/* animate-pulse bg-soleur-bg-surface-2 placeholder blocks */}
    </div>
  );
}
```
No props, no hooks, no client directive. These are App-Router Suspense fallbacks.

### Phase 2 — H3: parallelize the pending-invites fetch

In `app/(dashboard)/dashboard/chat/layout.tsx` (inside `if (user) { … }`), `getPendingInvitesForUser(user.id, user.email ?? "")` depends only on `user` — it does NOT depend on `orgId`, the delegation flag, or any delegation-chain result. Start its promise **before** entering the delegation branch and resolve both together so the invite round-trip overlaps the delegation chain instead of running serially after it.

**Precedent (deepen-plan precedent-diff):** `Promise.all` over independent Supabase awaits in an async server component is the established in-repo pattern — see `app/(dashboard)/dashboard/settings/page.tsx:31` and `app/(dashboard)/dashboard/admin/analytics/page.tsx:27`. The difference here: in `chat/layout.tsx` only the invites fetch is independent; the five delegation awaits form a genuine dependency chain. So the canonical shape is "start the independent fetch early, await it late" (a degenerate `Promise.all` of one in-flight promise + the sequential chain) rather than a full `Promise.all` of two independent branches. Both shapes are acceptable; prefer the simpler "start early, await late" unless the linter forces the explicit `Promise.all`.

Target shape (preserve the delegation chain's internal sequential awaits exactly — those are genuinely dependent):
```ts
if (user) {
  // Start the independent invites fetch immediately; it overlaps the
  // delegation resolution below instead of adding a serial round-trip.
  const invitesPromise = getPendingInvitesForUser(user.id, user.email ?? "");

  // Delegation branch — awaits stay sequential (each depends on the prior).
  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
  let bannerResult: DelegationBannerProps | null = null;
  if (orgId) {
    const identity: Identity = { userId: user.id, role: "prd", orgId };
    if (await isByokDelegationsEnabled(orgId, identity)) {
      const workspaceId = await resolveCurrentWorkspaceId(user.id, supabase);
      const delegation = await resolveGranteeDelegation(user.id, workspaceId, orgId, identity);
      if (delegation) {
        const acceptance = await resolveGranteeAcceptanceStatus(user.id, delegation.id);
        bannerResult = { /* …unchanged… */ };
      }
    }
  }

  const invites = await invitesPromise; // already in-flight; no added latency
  bannerProps = bannerResult;
  if (invites.length > 0) {
    pendingInvite = { invitationId: invites[0].id, inviterName: invites[0].inviter_name, workspaceName: invites[0].workspace_name };
  }
}
```
Note: assign `bannerProps` from a local at the end (or keep assigning it inline as today) — either is fine; the outer `let bannerProps`/`let pendingInvite` stay. The whole block remains inside the existing `try/catch`. **Floating-promise lint guard:** an un-awaited promise created and later awaited in the same scope is fine, but if `next lint`/biome flags `invitesPromise` as a floating promise before its `await`, that is a false positive for this pattern — the `await invitesPromise` below satisfies it. Confirm AC8 stays green; if the linter is unhappy, the `Promise.all([invitesPromise, <delegation-as-async-iife>])` form (arguments' suggested shape) is the fallback. Prefer the simpler "start early, await late" form above unless lint forces `Promise.all`.

### Phase 3 — M4: explicit column list

In `hooks/use-conversations.ts:~231`, replace:
```ts
.select("*")
```
with the explicit list matching the `Conversation` interface (mirror how the messages query at :269 names its columns):
```ts
.select(
  "id, user_id, domain_leader, session_id, status, total_cost_usd, input_tokens, output_tokens, last_active, created_at, archived_at, context_path, repo_url, active_workflow, workflow_ended_at, workspace_id, visibility",
)
```
**Why the full set, not a subset:** rows are cast `as Conversation` and **spread** (`...conv`) into `ConversationWithPreview` at :285, then handed to the rail and every downstream consumer. Dropping any typed field would silently `undefined` it for a consumer. The wire-size win comes from `*` having returned any *future/server-only* columns added to the table that are NOT in the `Conversation` type; the explicit list pins the payload to exactly the typed shape. Keep the existing `try/catch` around the `await query.limit(limit)` (the PostgrestBuilder is a thenable, not a Promise — do not switch to `.catch()`; per learning `2026-05-16-postgrest-builder-thenable-not-promise-catch-method-absent.md`). No other change. The sibling `.update(...)` calls at :538/:551/:570 are mutations, not selects — leave them.

### Phase 4 — M1: render `ChatSurface` with a context-pending state

Two coordinated edits. The session-start race is the load-bearing constraint (see Research Reconciliation).

**4a. `chat/[conversationId]/page.tsx`** — remove the mount gate, pass a pending flag:
```tsx
  // (drop:  if (contextLoading) return null;)
  return (
    <ChatSurface
      variant="full"
      conversationId={params.conversationId}
      initialContext={initialContext}
      contextPending={contextLoading}
    />
  );
```

**4b. `components/chat/chat-surface.tsx`** — accept `contextPending` and defer session start until it is false:
- Add `contextPending?: boolean` to the props interface (default `false`).
- In the session-start effect (chat-surface.tsx:347-365), add `contextPending` to the early-return guard and the dep array:
  ```ts
  useEffect(() => {
    if (status !== "connected" || sessionStarted || contextPending) return;
    // …unchanged body (startSession with initialContext / resumeSession)…
  }, [status, conversationId, leaderId, sessionStarted, startSession, resumeSession, initialContext, resumeByContextPath, contextPending]);
  ```
  This preserves the original invariant: for a `new` conversation with `?context=`, `startSession` still fires exactly once, with the *resolved* `initialContext`, only after `contextPending` flips false. The non-context path (`contextPending` defaults `false`) is unaffected — every other `ChatSurface` call site keeps today's behavior.
- **Optional context-pane affordance:** if `ChatSurface`'s full variant renders a context pane region, show a small `animate-pulse` placeholder there while `contextPending` is true, so the chat shell is visible immediately (the audit's intent) instead of a blank route. If the context pane is not a distinct region, simply rendering the chat shell (composer + empty transcript) while the session is deferred already satisfies "no blank screen." Keep this minimal; do not redesign `ChatSurface`.

**Verification of no behavior change:** the only observable difference vs. today is that the chat shell paints immediately instead of staying blank for the duration of the `/api/kb/content` fetch. The WS session still starts with the same `initialContext`. Confirm via AC6 test.

## Test Strategy

- **H4 loading.tsx:** No unit tests — repo convention is that `loading.tsx` route fallbacks are untested (the analytics `loading.tsx` has none; covered by e2e/manual). `tsc --noEmit` is the only gate (catches malformed JSX/exports). Do NOT author a co-located component test — vitest only collects `test/**/*.test.tsx` (see `vitest.config.ts` `include`), so a co-located test would silently never run anyway.
- **H3 chat/layout.tsx:** No direct test (layout files are untested in this repo; indirect coverage via `test/chat-page.test.tsx`). Gate is `tsc --noEmit` + the existing chat-page suites staying green. The change is await-ordering only — no behavioral assertion to add.
- **M4 use-conversations.ts:** Existing `test/use-conversations-limit.test.tsx` + `test/conversations-rail-*.test.tsx` must stay green. If those tests stub the Supabase `.select()` chain with a `*`-shaped mock, the mock must accept the new explicit-column string (it is a chained builder; the arg string is typically ignored by the mock). Run the full suite (AC9) and fix any mock that asserts on the literal `"*"` argument.
- **M1 chat-surface.tsx / page.tsx:** Extend or add a test under `apps/web-platform/test/` (e.g. `test/chat-page-context-pending.test.tsx`, NOT co-located) that: (1) mounts the page with `?context=<path>`, mocks `/api/kb/content/<path>`, asserts `ChatSurface` renders immediately (shell visible) while the fetch is pending; (2) asserts the WS `startSession` is invoked with the resolved `initialContext` only after the fetch resolves, never with `undefined`. The existing `test/chat-surface-context-reset.test.tsx` and `test/chat-page*.test.tsx` are the closest precedents for the mock setup.

**Commands (canonical for apps/web-platform — do NOT use `npm run -w`, the repo root has no `workspaces` field):**
```
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit      # typecheck (AC7)
cd apps/web-platform && npm run lint                          # lint (AC8)
cd apps/web-platform && npm run test:ci                       # full suite (AC9)
cd apps/web-platform && npx vitest run test/chat-page-context-pending.test.tsx   # the new M1 test
```

## Files to Edit

- `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` (H3)
- `apps/web-platform/hooks/use-conversations.ts` (M4)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (M1)
- `apps/web-platform/components/chat/chat-surface.tsx` (M1 — add `contextPending` prop + session-start guard)

## Files to Create

- `apps/web-platform/app/(dashboard)/dashboard/loading.tsx` (H4)
- `apps/web-platform/app/(dashboard)/dashboard/chat/loading.tsx` (H4)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/loading.tsx` (H4)
- `apps/web-platform/app/(dashboard)/dashboard/kb/loading.tsx` (H4)
- `apps/web-platform/app/(dashboard)/dashboard/settings/loading.tsx` (H4)
- `apps/web-platform/test/chat-page-context-pending.test.tsx` (M1 test — under `test/`, not co-located)

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open`; no open scope-out references any of the files in `## Files to Edit` / `## Files to Create`. (The six audit follow-ups #5531–#5536 are `perf`/`reliability`/`security`-labeled audit items, not `code-review` scope-outs, and target different structural surfaces — root layout, dashboard chrome, list virtualization, cache TTL — not these four files.)

## Observability

No new failure modes, error paths, log calls, or server surfaces are introduced:
- H4 renders static placeholder markup (no I/O, no failure mode).
- H3 reorders existing awaits inside the existing `try/catch` (same catch behavior; on error → no banner, identical to today).
- M4 narrows the column list on an existing query inside the existing `try/catch`; existing `convError` handling (`setError`) is unchanged.
- M1 renders the same `ChatSurface`; the `/api/kb/content` fetch already logs failures via `console.error` (chat-surface page lines 41-43), unchanged.

Discoverability test (no ssh): `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit && npm run test:ci` — green suite is the signal that the refactor preserved behavior. No new alert routes required.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure frontend performance refactor on an already-provisioned surface.

**Product/UX Gate — Tier: NONE. No wireframes required.** Two surfaces to account for:

1. **New `loading.tsx` files** — `loading.tsx` is NOT in the mechanical escalation glob set (`app/**/page.tsx`, `app/**/layout.tsx`, `app/**/template.tsx`, `components/**/*.{tsx,jsx,vue,svelte}`), so the mechanical override does not fire on them. They are non-interactive Suspense fallbacks that mirror already-designed chrome (no new flows, no interactive surface, no new visual-design decisions) — Excluded per `ui-surface-terms.md` ("Pure copy or style tweaks with no structural/layout change").
2. **`components/chat/chat-surface.tsx` edit (M1)** — this path DOES match the glob superset `components/**/*.tsx`, so the deepen-plan Phase 4.9 mechanical net flags it. **Determination: NONE.** The edit is purely additive plumbing — one optional boolean prop (`contextPending`) on the props interface plus one guard clause in an existing `useEffect` (verified: no JSX/layout/markup change, chat-surface.tsx:347-365). It introduces no new component, no new visual surface, no new flow, and makes no design decision. Per `ui-surface-terms.md` Excluded ("Pure copy or style tweaks with no structural/layout change") and the gate's own "discusses UI but implements orchestration → NONE" rule, no `.pen` is required. Recorded explicitly so the glob match does not read as a missed wireframe.

## Infrastructure (IaC)

N/A — skipped. No new server, service, cron, secret, vendor, DNS, cert, or runtime process. Pure code change against the already-provisioned `apps/web-platform/**` surface, deployed by the existing `web-platform-release.yml` pipeline on merge.

## Architecture Decision (ADR/C4)

N/A — skipped. No architectural decision: no ownership/tenancy boundary move, no new substrate/integration pattern, no resolver/dispatch/trust-boundary change, no ADR reversal/extension. A competent engineer reading the existing ADRs + C4 would not be misled by these four mechanical fixes.

## Hypotheses

N/A — no network-outage / SSH / connectivity keywords in scope.

## Risks & Mitigations

- **R1 (M1 session-start race regression):** the highest-risk item. Mitigated by threading `contextPending` into `ChatSurface`'s session-start guard (not deleting the gate) + AC6 test asserting `startSession` receives the resolved `initialContext`. Reviewers: confirm the dep array includes `contextPending` and the `new`-conversation path is exercised.
- **R2 (M4 dropped-column regression):** mitigated by using the *complete* `Conversation` field set (verified against `types.ts:580-603`) and the full-suite gate (AC9). If a future column is added to `Conversation`, the explicit select must be updated too — note this in the diff comment above the `.select(...)`.
- **R3 (M4 test mock asserts literal `"*"`):** ~~if any existing test mock pattern-matches the `.select("*")` arg, AC9 will fail~~ — **DOWNGRADED by deepen-plan verify-pass**: no existing test pins the `.select()` argument (all mocks are `select: vi.fn(() => chain)`, ignoring the arg). The refactor cannot break a mock on the arg string. Retained only as a watch-item if a new test is added.
- **R4 (H3 floating-promise lint):** if `next lint` flags the early-started promise, fall back to the `Promise.all` form (arguments' suggested shape). AC8 catches this.
- **R5 (H4 skeleton shape mismatch / flash):** coarse skeletons are acceptable; a brief flash on fast loads is strictly better than today's blank screen. No mitigation needed beyond mirroring the analytics pattern.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — this plan's section is filled (threshold: none, with scope-out reason).
- **M1 is NOT a one-line delete** of `if (contextLoading) return null;`. The gate is load-bearing for the WS session-start (`initialContext` delivery). Removing it without the `contextPending` guard in `chat-surface.tsx` reintroduces the race the gate prevents — a `new` conversation with `?context=` would start its WS session without the KB content. This is the only fix in the bundle that touches two files.
- **No Mantine `Skeleton`** despite the arguments saying "Mantine skeleton components" — the repo convention is hand-rolled `animate-pulse`. Following the arguments literally would introduce a net-new dependency-usage and contradict "mirror the existing pattern."
- **Typecheck command** is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, never `npm run -w apps/web-platform typecheck` (the repo root has no `workspaces` field — the `-w` form aborts with "No workspaces found").
- **Test file paths** must live under `apps/web-platform/test/` (vitest `include` is `test/**/*.test.tsx` / `test/**/*.test.ts`) — a co-located `*.test.tsx` is silently never collected. The new M1 test goes in `test/`.
