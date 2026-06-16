---
title: "feat(chat): New-conversation affordance in the rail + deterministic fresh-conversation appearance"
date: 2026-06-16
type: feature
branch: feat-one-shot-sidebar-new-conversation-rail
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
---

# ✨ feat(chat): "+ New conversation" in the rail + 🐛 deterministic fresh-conversation appearance

## Enhancement Summary

**Deepened on:** 2026-06-16
**Passes run:** ux-design-lead (wireframe producer — Phase 2.5 / 4.9 artifact), architecture-strategist,
code-simplicity-reviewer, user-impact-reviewer, verify-the-negative (8/8 claims confirmed against branch HEAD).

### Key Improvements (vs. v1 plan)
1. **Cut the timed-retry reconciliation — adopted the strictly simpler deterministic fix.**
   code-simplicity-reviewer AND architecture-strategist independently flagged the v1 bounded
   `setTimeout`-retry as a *clock racing a user-paced event* (the row is created lazily on first
   WS message, `apps/web-platform/server/ws-handler.ts:2191`). The corrected fix **drops the
   `pendingScopeRecoveryRef` gate** (`use-conversations.ts:456`) so the existing scope-resolve
   backfill fires **unconditionally** once on `null→id` — net-negative LOC, no timers, no
   `setTimeout` cleanup, no remount-leak risk, no bound-exhaustion Sentry slug. A /work-time
   falsification gate requires exhibiting one concrete failing event ordering before any timer is
   written; if none survives "unconditional scope-resolve backfill + SUBSCRIBED fetch +
   steady-state INSERT handler", no timer ships.
2. **Closed the `loading`-flicker interaction** (architecture-strategist P1): `fetchConversations`
   unconditionally `setLoading(true)`/`setError(null)` at `use-conversations.ts:157-158`; the
   unconditional backfill must use a **quiet-refetch** path (skip the loading/error toggle) so a
   background reconcile cannot blank or error-flash the rail. Added AC.
3. **Wireframe produced** (not deferred): `knowledge-base/product/design/chat/new-conversation-rail-affordance.pen`
   (committed) + screenshots `08-…-expanded.png`, `09-…-collapsed-absent.png` — documents the
   affordance in the expanded rail and its absence when collapsed.
4. **Fixed the `ws-handler.ts` path prefix** (was missing `apps/web-platform/`) and verified all
   file:line citations (architecture-strategist confirmed the rest correct).

### New Considerations Discovered
- The own-channel INSERT, once scope is resolved + channel SUBSCRIBED, **is** added by the
  steady-state fill-only reducer (`use-conversations.ts:370-381`) — so the only residual hole the
  v1 timer chased is the pre-`SUBSCRIBED`-buffered INSERT, which the `SUBSCRIBED` fetch (fired
  *after* the buffer window closes) and supabase-js's reconnect `SUBSCRIBED` re-fire already cover.
- The rail hook does NOT hold the freshly-created conversation id (verify-the-negative #5) — a
  cancel/observe predicate cannot match "the new id is present"; any retry that survives the
  falsification gate must key on "row count increased vs arm-time", not the id.

## Overview

Two related changes to the chat sidebar's **Recent Conversations** rail
(`apps/web-platform/components/chat/conversations-rail.tsx`, lifted into the single
nav rail's secondary slot per ADR-047):

1. **FEATURE — start a new conversation from the rail.** Today the rail's only
   new-conversation entry point is the *empty-state* CTA ("Start one →",
   `conversations-rail.tsx:133-139`), which disappears the moment one conversation
   exists. The dashboard page already has a persistent "+ New conversation" button
   (`app/(dashboard)/dashboard/page.tsx:739-744`), but the rail does not. Add a
   persistent "+ New conversation" affordance to the rail **header** so the user can
   start a new conversation directly from the sidebar regardless of list state. It is
   a plain navigation to `/dashboard/chat/new` — the canonical new-conversation entry
   (resolves to `chat/[conversationId]/page.tsx` with `conversationId="new"`, which
   `ChatSurface` treats as "start a fresh session", `chat-surface.tsx:349-358`).

2. **BUG — make the freshly-started conversation appear deterministically.** Commit
   `57fe0612a` (PR #5421, follow-up to #5391) added a transition-gated *scope-resolve
   backfill* to `apps/web-platform/hooks/use-conversations.ts` to recover an own-channel
   INSERT dropped during the fresh-mount connect window. It reduced but did **not**
   close the flakiness: the recovery is **conditional on a drop having been recorded**
   (`pendingScopeRecoveryRef`, `use-conversations.ts:456`). If no own-channel INSERT was
   dropped in the connect window — e.g. the row is created later, or the INSERT was buffered
   pre-`SUBSCRIBED` (supabase-js does **not** replay pre-subscribe INSERTs) so no drop is
   recorded — the ref is never armed and the refetch never fires. The conversation row is
   created **lazily server-side on the first WS message**
   (`apps/web-platform/server/ws-handler.ts:2191`), which can land before or after the two
   existing backfills (the `SUBSCRIBED` snapshot at `use-conversations.ts:403-404` and the
   gated scope-resolve refetch at `:451-460`). **The fix is to make the scope-resolve backfill
   UNCONDITIONAL** — drop the `pendingScopeRecoveryRef` gate so it always refetches exactly once
   when `workspaceId` transitions `null → id`, regardless of whether a drop was recorded. This
   is strictly simpler than the v1 timed-retry (net-negative LOC: deletes the ref, its arming
   branch, and the existing armed-drop Sentry mirror) and is **more** deterministic — it does not
   race a user-paced event. Walking the orderings: scope-resolves-before-subscribe is covered by
   the `SUBSCRIBED` fetch (fires after the buffer window closes, catching an already-committed
   row); subscribe-before-scope-resolves is covered by the now-unconditional `null→id` refetch;
   and a row created lazily *after* both is covered by the steady-state own-channel INSERT
   reducer (`:370-381`), which adds it once scope is resolved. **/work falsification gate:** before
   writing ANY timer/retry, exhibit one concrete event ordering that survives "unconditional
   scope-resolve backfill + `SUBSCRIBED` fetch + steady-state INSERT handler" and still drops the
   row. If none can be produced, no timer ships.

This is a **behavioral change on an existing surface** plus a **small UI addition** — not
a build. The rail, the hook, the realtime publication (`migrations/034`, `015` REPLICA
IDENTITY FULL), the `/dashboard/chat/new` route, and the lazy server INSERT all exist and
are wired.

## Research Reconciliation — Spec vs. Codebase

| Claim (from report / prior PIR #5421) | Reality on this branch HEAD | Plan response |
|---|---|---|
| "PR #5421 shows the freshly-started conversation in the rail immediately" | **Partly.** It recovers an own-channel INSERT *dropped because `workspaceId` was unresolved* (`use-conversations.ts:357-366` arms `pendingScopeRecoveryRef`; `:451-460` refetches once on `null→id` **only if armed**). It does NOT recover the case where no drop is recorded (row created later, or INSERT buffered pre-`SUBSCRIBED`). | Make the scope-resolve backfill UNCONDITIONAL (drop the `pendingScopeRecoveryRef` gate at `:456`). |
| "Recovery fires when `workspaceId` resolves" | True but **gated**: the `:456` condition is `prev===null && workspaceId!==null && pendingScopeRecoveryRef.current`. If no own-channel INSERT was dropped in the window, `pendingScopeRecoveryRef` is never set and the refetch never fires. | Drop the third clause: refetch unconditionally on the `null→id` transition. |
| "The `SUBSCRIBED` backfill closes the gap" | The `if (status === "SUBSCRIBED") fetchConversations()` (`:403-404`) fires once when the channel goes live; it can run before scope resolves (empty/stale set) and never re-runs. But it fires *after* the pre-subscribe buffer window closes, so it catches an already-committed row in the scope-resolves-first ordering. | Keep it; the unconditional `null→id` refetch covers the other ordering; the steady-state INSERT reducer (`:370-381`) covers a row that commits later. No timer needed. |
| Rail has a new-conversation entry point | Only the **empty-state** CTA (`:133-139`); it vanishes once any conversation exists. The persistent dashboard button (`page.tsx:739-744`) is NOT in the rail. | Add a persistent header affordance to the rail. |
| `/dashboard/chat/new` is the canonical new-conversation route | Confirmed: `chat/page.tsx` redirects to it; `chat/[conversationId]/page.tsx` mounts `ChatSurface` with id `"new"`; `chat-surface.tsx:349` branches to `startSession`. | A plain `<Link href="/dashboard/chat/new">` is the affordance — no new route, no server action. |
| Rail and dashboard are separate `useConversations` instances; chat surface holds none | Confirmed (`conversations-rail.tsx:88`, `page.tsx:117`; chat surface: no call site). A cross-instance optimistic insert remains out of scope (deferred in #5421). | Fix stays on the rail's own hook instance; no cross-instance writer. |

## User-Brand Impact

**If this lands broken, the user experiences:** they start a new conversation (the single
most common path), the Concierge begins working, but the left Recent Conversations rail
still does not show it — the exact reported defect, now twice-shipped, eroding trust in the
product's "memory-first" wedge. A regression in the new affordance (a button that 404s, or
that mis-routes) breaks the most prominent CTA in the sidebar.

**If this leaks, the user's workflow is exposed via:** any reconciliation/refetch path that
bypasses the `shouldDropForScope` (`repo_url` AND `workspace_id` AND channel-visibility AND
archive) guard could surface a conversation title in the **wrong repo's / wrong workspace's**
rail — a cross-tenant context exposure that exceeds the single-user threshold. Every insert
and refetch path MUST remain scope-equivalent to the list query
(`use-conversations.ts:222-228`, `.eq(repo_url).eq(workspace_id)`) — the #5391
guard-equals-fetch-scope invariant
(`knowledge-base/project/learnings/best-practices/2026-06-16-realtime-event-guard-must-equal-fetch-query-scope.md`).

**Brand-survival threshold:** single-user incident.
(CPO sign-off required at plan time before `/work` begins — `requires_cpo_signoff: true`.
`user-impact-reviewer` runs at review-time. Deepen-plan / domain-agent pass recommended at
this threshold — plan-review style agents are structurally blind to the realtime-timing and
scope-leak classes here.)

## Acceptance Criteria

> **Invariant, not proxy.** ACs that assert "a refetch call fired" are proxies — they can
> pass while the real rail (a separate, late-mounting instance) shows nothing. The row ACs
> below MUST render the **real `ConversationsRail`** and assert the **row appears**, or
> assert the resulting `conversations` array (drive the conversations mock so the
> reconciliation refetch returns a set that includes the new conversation).

### Pre-merge (PR)

- [ ] **AC1 — Persistent "+ New conversation" affordance renders in the rail header.** A
  vitest test renders the **real `ConversationsRail`** with a NON-empty conversation list and
  asserts a "+ New conversation" control is present in the rail header (queryable by role
  `link` with accessible name "New conversation", `href="/dashboard/chat/new"`), i.e. it is
  visible even when conversations exist (not only the empty-state CTA). File:
  `apps/web-platform/test/conversations-rail.test.tsx` (extend the existing suite — verify
  the existing rail-render harness there is the real component, not a mock).
- [ ] **AC2 — Affordance hidden in the collapsed rail.** When `useRailCollapsed()` is true the
  rail returns `null` (`conversations-rail.tsx:101-102`); assert the "+ New conversation"
  control is absent in the collapsed state (no icon-only form is added — the whole rail is
  DOM-removed when collapsed, matching the existing rich-row collapse behavior; do not
  manufacture a partial collapsed render). This is the both-toggle-states alignment check
  (`learnings/2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`): expanded shows
  it, collapsed removes it.
- [ ] **AC3 — Deterministic appearance via the now-unconditional scope-resolve backfill (no
  recorded drop required).** A vitest test renders the **real `ConversationsRail`**, drives the
  mock so (a) the rail mounts and subscribes, (b) the row does NOT exist at first fetch /
  `SUBSCRIBED` time, (c) `workspaceId` transitions `null → id`, and (d) the refetch triggered by
  that transition returns a set including the new conversation — and asserts the new conversation
  **row appears in the rail's rendered DOM before any completion UPDATE**. Critically, NO
  own-channel INSERT is dropped in this scenario (so `pendingScopeRecoveryRef` would never be
  armed) — proving the recovery is now **unconditional** on the `null→id` transition. File:
  `apps/web-platform/test/conversations-rail-connect-race.test.tsx` (extend; reuse the
  channel-mock-chain + deferred-`active-repo` harness already there).
- [ ] **AC4 — Backfill fires exactly once per `null→id` transition (bounded, no amplification).**
  A test asserts the unconditional scope-resolve refetch fires **once** when `workspaceId`
  transitions `null → id` and does NOT re-fire on subsequent re-renders (transition-gated via
  `prevWorkspaceIdRef`). Assert the `active-repo`/conversations call count after resolve is exactly
  the expected value (initial fetch + the one scope-resolve refetch; the mock omits the
  `SUBSCRIBED` callback as the existing AC2-bounded test does at
  `conversations-rail-connect-race.test.tsx:329-360`). **No `setTimeout`/retry loop is introduced**
  — if /work's falsification gate (Overview) cannot exhibit an ordering that survives the
  unconditional-backfill + `SUBSCRIBED` + steady-state-INSERT triad, this AC is the whole bound.
- [ ] **AC4b — Quiet refetch: the backfill never blanks or error-flashes the rail.** `fetchConversations`
  calls `setLoading(true)`/`setError(null)` at `use-conversations.ts:157-158`; the unconditional
  backfill MUST use a **quiet-refetch** path that skips that toggle (e.g. a `{ background: true }`
  arg to `fetchConversations`, or a dedicated background fetch) so a reconcile with last-known rows
  present cannot re-enter the `!loading`-gated empty/error branches (`conversations-rail.tsx:113,
  133`). Test: render the real rail with existing rows, fire the `null→id` backfill, assert the
  rail never renders the `conversations-rail-empty` or `conversations-rail-error` branch across the
  refetch (architecture-strategist P1).
- [ ] **AC5 — Scope-guard parity preserved (the cross-scope-leak containment).** Every insert
  AND refetch path (realtime INSERT, the now-unconditional scope-resolve backfill) remains gated by
  `shouldDropForScope` / the scoped list query — the rail never shows a row the list query
  (`.eq(repo_url).eq(workspace_id)`) would exclude. Tests: (a) an out-of-(repo|workspace)-scope
  INSERT is dropped; (b) a second workspace's rail does NOT show this workspace's new conversation
  under the unconditional backfill; (c) a non-`workspace`-visibility peer row is NOT surfaced by the
  backfill refetch (it leans on RLS 075, unchanged — confirm no regression; user-impact-reviewer
  FINDING 2). The backfill only ever calls the existing scoped `fetchConversations` after
  `workspaceId !== null`, so it can never run a `repo_url`-only-scoped query. This is the F3
  cross-tenant-context-exposure invariant — non-negotiable at the single-user threshold. The
  existing isolation case (`conversations-rail-connect-race.test.tsx:362-381`) stays green.
- [ ] **AC6 — UPDATE path unchanged; armed-drop path removed cleanly.** The completion UPDATE handler
  stays `map`-only (cannot resurrect an absent row — regression test stays green). Removing the
  `pendingScopeRecoveryRef` gate also removes its arming branch and the existing
  `own-insert-deferred-unresolved-workspace` Sentry mirror (`use-conversations.ts:357-366`); per
  `cq-ref-removal-sweep-cleanup-closures`, sweep the file for every reference to
  `pendingScopeRecoveryRef` and confirm it is fully removed (declaration `:154`, arming `:358`,
  gate `:456`) — no dangling reads. Update the existing connect-race test that asserted the armed
  drop + Sentry mirror to reflect the new unconditional behavior (the row now recovers via the
  unconditional refetch instead of the armed-drop path).
- [ ] **AC7 — No new silent-fallback surface (the v1 bound-exhaustion mirror is cut).** With no
  timer/bound there is nothing to exhaust; do NOT add a new Sentry slug. "The user-paced INSERT
  hasn't arrived yet" is normal latency, not a silent fallback (code-simplicity-reviewer). A
  genuine refetch FAILURE still surfaces via the existing `useConversations` error state
  (`use-conversations.ts:240-243, :288-291`) — unchanged. (If, and only if, the /work falsification
  gate proves a residual ordering requires a bounded retry, then re-introduce a one-shot
  bound-exhaustion mirror with a distinct `op` slug — NOT reusing
  `own-insert-deferred-unresolved-workspace` — preserving an explicit `message:` string per
  `learnings/2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`.)
- [ ] **AC8 — Hook-source-swap / real-renderer test sweep.** Per
  `learnings/best-practices/2026-06-15-hook-source-swap-sweep-all-real-hook-renderers-not-name-filtered.md`,
  derive the blast radius via
  `git grep -l 'useConversations' apps/web-platform/test/` **minus**
  `git grep -l 'vi.mock("@/hooks/use-conversations"' apps/web-platform/test/`; every real-hook
  renderer (and the channel-mock-chain renderers) still passes. Paste both grep outputs in the
  PR body.
- [ ] **AC9 — Typecheck + suite green.** `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit` exits 0 (NOT `npm run -w … typecheck` — the repo root declares no `workspaces`,
  per `learnings/2026-05-13-npm-workspaces-flag-fails-without-root-workspaces-declaration.md`),
  and `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/conversations-rail.test.tsx test/conversations-rail-connect-race.test.tsx
  test/conversations-rail-insert.test.tsx` is green; full `scripts/test-all.sh` exits 0.

### Post-merge (operator / automated)

- [ ] **AC10 — Live confirmation (Playwright MCP).** After the web-platform release, drive a
  real session **starting from `/dashboard`** (the reported path — the rail is NOT mounted on
  `/dashboard`, so this exercises the fresh-mount connect-race): open `/dashboard`, click into
  a new conversation (or use the new rail "+ New conversation" affordance once on
  `/dashboard/chat/*`), send the first message, and assert the new conversation row appears in
  the Recent Conversations rail **within seconds and before completion**, without a reload.
  Also click the new rail affordance and assert it lands on the new-conversation composer.
  Assert scope isolation (the row does not appear in a different workspace's rail). `Automation:
  feasible via mcp__playwright__* against the deployed app` — run it; do not punt to a manual
  operator step.

## Implementation Phases

> Scope is **two files** (rail component + hook) plus their tests. No new route, no server
> action, no migration. The cross-instance optimistic insert remains deferred (#5421).

1. **Phase 0 — Preconditions (verify, do not assume).**
   - Re-confirm the rail header structure and the empty-state-only entry point:
     `conversations-rail.tsx:104-110` (header `<div>` with the "Recent conversations" label),
     `:133-139` (empty-state "Start one →" CTA). Confirm the collapsed branch returns `null`
     (`:101-102`).
   - Re-confirm the canonical new-conversation route: `chat/page.tsx` → redirect
     `/dashboard/chat/new`; `chat/[conversationId]/page.tsx` mounts `ChatSurface` with the param;
     `chat-surface.tsx:349` branches `"new" → startSession`. A plain `<Link>` is sufficient
     (mirror `page.tsx:739-744`, but the rail's lighter context may prefer the
     `text-soleur-accent-gold-fg` token used by `rail-empty-state.tsx:28` rather than the full
     gradient button — choose at /work for visual fit; both are existing tokens).
   - Re-confirm the residual-gap shape in the hook: the `SUBSCRIBED` backfill
     (`use-conversations.ts:403-404`) is unconditional but single-shot; the scope-resolve
     backfill (`:451-460`) is **gated on `pendingScopeRecoveryRef`** (`:456`); the lazy row
     INSERT is `apps/web-platform/server/ws-handler.ts:2191` (created on first WS message,
     user-paced). Confirm these line shapes are unchanged from this plan's citations before coding.
   - **Falsification gate (BEFORE writing any timer/retry).** Walk every event ordering and
     confirm whether "unconditional scope-resolve backfill (the chosen fix) + the existing
     `SUBSCRIBED` fetch + the steady-state own-channel INSERT reducer (`:370-381`)" recovers the
     row. The three orderings: (i) scope-resolves-before-subscribe → `SUBSCRIBED` fetch fires after
     the pre-subscribe buffer window closes, catching the committed row; (ii)
     subscribe-before-scope-resolves → the unconditional `null→id` refetch fires when scope lands;
     (iii) row created lazily after both → the steady-state INSERT (scope now resolved) adds it via
     the fill-only reducer. If you cannot exhibit a concrete ordering that drops the row under this
     triad, **do NOT add a timer** — the unconditional backfill is the whole fix.
   - Confirm the two `useConversations` call sites (rail `:88`, dashboard `page.tsx:117`); chat
     surface holds none — so the fix stays hook-instance-local.
2. **Phase 1 (RED) — failing tests.**
   - **AC1/AC2 (rail UI):** in `test/conversations-rail.test.tsx`, add (a) a non-empty-list
     render asserting the "+ New conversation" link is present in the header, and (b) a
     collapsed-state render asserting it is absent. Verify the existing suite renders the real
     component.
   - **AC3/AC4/AC4b (deterministic appearance):** in `test/conversations-rail-connect-race.test.tsx`,
     add a case where the row does not exist at first fetch / `SUBSCRIBED`, `workspaceId` transitions
     `null→id`, NO INSERT is dropped (so `pendingScopeRecoveryRef` would stay false), and the row
     must still appear via the **unconditional** scope-resolve refetch. Add the once-per-transition
     call-count assertion (AC4) and the quiet-refetch no-flicker assertion (AC4b). Extend the
     existing deferred-`active-repo` / channel-mock harness (do not rebuild it).
3. **Phase 2 (GREEN) — the two changes.**
   - **Rail affordance (`conversations-rail.tsx`):** add a `<Link href="/dashboard/chat/new">`
     "+ New conversation" control into the existing header row (`:104-110`). Reuse the SAME href
     constant the empty-state CTA uses (`:138`) to prevent drift (user-impact-reviewer FINDING 5).
     Use existing tokens — the wireframe
     (`knowledge-base/product/design/chat/new-conversation-rail-affordance.pen`) shows the gradient
     `+ New` mirroring `page.tsx:743`; the lighter `text-soleur-accent-gold-fg` link is an
     acceptable alternative for the rail's density. Add an accessible name ("New conversation"). It
     renders only in the expanded branch (the collapsed branch returns `null` BEFORE the header at
     `:102` — AC2 holds for free; verify the early-return precedes the header JSX).
   - **Unconditional scope-resolve backfill (`use-conversations.ts`):** in the existing
     scope-resolve effect (`:451-460`), **drop the `pendingScopeRecoveryRef.current` clause** from
     the `:456` condition so it becomes `if (prev === null && workspaceId !== null)` — the refetch
     now fires exactly once on `null→id`, regardless of whether a drop was recorded. Then per
     `cq-ref-removal-sweep-cleanup-closures`, **delete `pendingScopeRecoveryRef` entirely** (the
     declaration `:154`, the arming branch + the `own-insert-deferred-unresolved-workspace` Sentry
     mirror at `:357-366`) and sweep the file for any remaining reference. The refetch MUST use a
     **quiet-refetch path** (skip `setLoading(true)`/`setError(null)` at `:157-158`) so a background
     reconcile with rows present cannot flash the empty/error branch (AC4b) — add a `{ background }`
     arg to `fetchConversations` (or a sibling quiet fetch).
     - **Do NOT** touch `shouldDropForScope`, the UPDATE handler (stays `map`-only), the
       `SUBSCRIBED` backfill, or the fill-only INSERT reducer. The change is a net-negative-LOC
       simplification: the backfill becomes unconditional and the armed-drop ref/mirror are removed.
       Every refetch still routes through the scoped list query, preserving F3 parity (AC5).
     - **Timer only if the falsification gate demands it.** If Phase 0's gate exhibited a surviving
       drop ordering, THEN (and only then) add a bounded, self-cancelling retry: transition-gated
       via a ref, cancel when the conversation **count increases vs. the arm-time count** (NOT
       `length > 0` — the rail may already have other conversations; NOT "new id present" — the hook
       does not hold the new id, verify-the-negative #5), `setTimeout` cleared in the effect cleanup
       so the ADR-047 remount cannot leak a timer, and re-introduce the AC7 one-shot bound-exhaustion
       Sentry mirror with a distinct slug.
4. **Phase 3 (REFACTOR).** Minimal. The change leaves two refetch triggers (`SUBSCRIBED` +
   unconditional scope-resolve) — both already exist; no new helper is warranted unless a timer was
   added. Keep `shouldDropForScope`/`deriveRailTitle` as the single guard/title source. Do NOT
   merge the triggers' gates/lifecycles (architecture-strategist P1 — merging gates risks
   reintroducing scope drift).
5. **Phase 4 — verify.** AC8 sweep, AC9 typecheck + suite, AC10 Playwright MCP post-deploy.

### Research Insights

- **Transition-gate precedent** (`apps/web-platform/hooks/use-kb-layout-state.tsx:232-240`,
  already reused by the existing backfill at `use-conversations.ts:451-460`):
  ```ts
  const prevRef = useRef<string | null>(null);
  useEffect(() => {
    if (prevRef.current === x) return;   // no transition
    prevRef.current = x;
    if (x !== null) { /* fire once on null → id */ }
  }, [x, ...]);
  ```
- **supabase-js Realtime:** INSERTs buffered before `SUBSCRIBED` are NOT replayed; the canonical
  pattern is subscribe → backfill → fill-only de-dup by id (`use-conversations.ts:370-381`) →
  route every insert through `shouldDropForScope`. The fix makes the existing scope-resolve backfill
  **unconditional**; it does not rewrite the pattern. supabase-js re-fires `SUBSCRIBED` on reconnect
  (a free recovery the v1 timer would have duplicated).
- **Lazy row creation:** the conversation row is created on the first WS message
  (`apps/web-platform/server/ws-handler.ts:2191`), not on navigation — so any recovery keyed only
  on subscribe time can run before the row exists. Once scope is resolved + channel SUBSCRIBED, the
  lazy INSERT arrives on the own channel and is added by the steady-state fill-only reducer
  (`:370-381`) — so the lazy-creation case needs no timer; it is covered by the existing INSERT
  handler the moment scope is resolved.
- **vitest discovery** (`apps/web-platform/vitest.config.ts:38-82`): component project glob is
  `test/**/*.test.tsx` (happy-dom); unit is `test/**/*.test.ts` + `lib/**/*.test.ts` (node). New
  tests extend existing files under `apps/web-platform/test/` — the runner discovers them.
- **typecheck form:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (root has no
  `workspaces` field).

## Files to Edit

- `apps/web-platform/components/chat/conversations-rail.tsx` — add the persistent
  "+ New conversation" header affordance (a `<Link href="/dashboard/chat/new">`); expanded
  branch only.
- `apps/web-platform/hooks/use-conversations.ts` — make the scope-resolve backfill unconditional
  (drop the `pendingScopeRecoveryRef` gate at `:456`); delete `pendingScopeRecoveryRef` + its arming
  branch + the `own-insert-deferred-unresolved-workspace` Sentry mirror (`:154, :357-366`); add a
  quiet-refetch path (skip `setLoading`/`setError` at `:157-158`). Do NOT modify `shouldDropForScope`,
  the `SUBSCRIBED` backfill, or the map-only UPDATE handler. (Net-negative LOC.)
- `apps/web-platform/test/conversations-rail.test.tsx` — AC1/AC2 (affordance present
  expanded, absent collapsed).
- `apps/web-platform/test/conversations-rail-connect-race.test.tsx` — AC3/AC4/AC4b/AC5/AC6 (row
  appears via the unconditional backfill with no recorded drop; once-per-transition; quiet refetch;
  scope+visibility isolation; armed-drop test updated to the new behavior; map-only UPDATE green).

## Files to Create

- (none expected) — all tests extend existing files. Create a new test file only if /work
  splits a focused reconciliation unit out; if so it lives under `apps/web-platform/test/` to
  satisfy the `test/**/*.test.tsx` (happy-dom) glob.

## Deferral Tracking

- **Zero-latency cross-instance optimistic insert.** A true zero-latency optimistic insert keyed
  on the `session_started` UUID (`lib/ws-client.ts:122-123`) is still **deferred** (it was
  deferred in #5421 and is unchanged here): the rail and dashboard are separate `useConversations`
  instances and the chat surface holds none, so it requires lifting the hook into a shared
  store/Context above both mount sites — disproportionate to a read-freshness fix. This plan's
  unconditional backfill makes the appearance *deterministic within Realtime latency* without it.
  **Re-evaluation criteria:** if AC10 shows perceptible latency (> a few seconds) in dogfooding,
  or a future feature already lifts `useConversations` into a shared store. **Action for /work:**
  verify whether #5421's deferral already filed a tracking issue (`gh issue list --search
  "optimistic insert conversations rail"`); if one exists, add a comment linking this plan; if
  not, file one (labels `domain/engineering`, `priority/p3-low`) — do NOT create a duplicate.

## Open Code-Review Overlap

None touching the planned files. `gh issue list --label code-review --state open` returns one
open scope-out, #4525 (PR #4518 `resolveCurrentOrganizationId` migration), which does not touch
`use-conversations.ts` / `conversations-rail.tsx`. Acknowledged, left open.

## Risks & Mitigations

- **R1 — Scope-guard drift / cross-scope leak (F3).** Any refetch/insert path that bypasses the
  scoped list query / `shouldDropForScope` can surface a conversation in the wrong workspace's
  rail — exceeding the single-user threshold. Mitigation: the unconditional backfill only ever
  calls the existing scoped `fetchConversations` AND only after `workspaceId !== null`, so it can
  never run a `repo_url`-only-scoped query; no new query, no guard change. AC5 (drop test +
  second-workspace isolation + visibility-scope assertion). **The most important invariant in this
  plan.**
- **R2 — `loading`/`error` flicker from a background refetch.** `fetchConversations` toggles
  `setLoading(true)`/`setError(null)` at `:157-158`; an unconditional backfill that re-enters that
  path could re-evaluate the `!loading`-gated empty/error branches (`conversations-rail.tsx:113,
  133`) and blank/flash the rail. Mitigation: quiet-refetch path (skip the toggle for the
  background reconcile); AC4b asserts no flicker (architecture-strategist P1).
- **R3 — Backfill amplification.** The unconditional backfill must fire once per `null→id`
  transition, not per render. Mitigation: it reuses the existing transition-gate ref
  (`prevWorkspaceIdRef`, `:451-460`); AC4 asserts exactly-once. (`workspaceId` starts `null` and
  resolves once per mount, so this is one extra refetch per fresh rail mount — and it *replaces* the
  speculative `pendingScopeRecoveryRef`-gated fetch, not adds to it.)
- **R4 — Affordance duplicates the dashboard button / inconsistent styling.** The dashboard page
  (`page.tsx:739-744`) already has a gradient "+ New conversation" button; the rail is a
  different, denser surface. Mitigation: the rail lives only on `/dashboard/chat/*` (the dashboard
  button is on `/dashboard`, a different route) so they never co-render; the wireframe shows the
  chosen token. Reuse the empty-state CTA's href constant (`:138`) to prevent route drift.
- **R5 — Timer leak (ONLY if the falsification gate forces a timer).** If Phase 0's gate exhibits a
  surviving drop ordering and a bounded retry is added, a `setTimeout` must be cleared on unmount
  (ADR-047 per-drill remount) or a stale timer fires into an unmounted hook / a different mount's
  scope. Mitigation: clear the pending timer id (chained-retry-aware, not just the first) in the
  effect cleanup; transition-gate so a fresh mount re-arms cleanly. If no timer is added (expected),
  this risk does not exist.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (It is filled.)
- ADR-047 keeps the **context band** mounted, NOT the conversations rail — the rail remounts per
  chat-drill, which is the source of the connect-race. Do not inherit the #5391 PIR's "rail stays
  mounted" framing.
- The conversation row is **lazily created** (on first WS message,
  `apps/web-platform/server/ws-handler.ts:2191`). The fix does NOT race it with a timer — once
  scope is resolved + channel SUBSCRIBED, the lazy own-channel INSERT is added by the steady-state
  fill-only reducer (`:370-381`). The unconditional backfill covers the orderings where the row
  exists before the steady-state subscription is live.
- **Do not add a timer without first running the Phase 0 falsification gate.** code-simplicity +
  architecture review both flagged the v1 timed-retry as a clock racing a user event; the
  unconditional backfill + `SUBSCRIBED` fetch + steady-state INSERT triad is believed to cover all
  orderings. A timer is dead weight unless a concrete surviving drop ordering is exhibited.
- Removing `pendingScopeRecoveryRef` is a ref-removal sweep
  (`cq-ref-removal-sweep-cleanup-closures`): delete the declaration (`:154`), the arming branch +
  Sentry mirror (`:357-366`), and the gate clause (`:456`), and grep for any dangling read.
- The collapsed rail returns `null` before the header (`:102`) — the early return must precede the
  new affordance JSX, or AC2 fails. Verify ordering.

## Observability

```yaml
liveness_signal:
  what: "Recent Conversations rail populates a freshly-started conversation before completion (deterministically, via the unconditional null→id scope-resolve backfill + steady-state INSERT)"
  cadence: "on every new-conversation start (user-interactive)"
  alert_target: "none (read-freshness UX; not an error-path event — PIR #5391 established read-freshness gaps do not fire Sentry/Better Stack in steady state)"
  configured_in: "n/a — verified by the AC10 Playwright MCP post-deploy check, not a monitor"
error_reporting:
  destination: "Sentry (browser SDK) — genuine refetch FAILURE only: a backfill refetch that errors surfaces via the existing useConversations error state (use-conversations.ts:240-243, :288-291). No NEW silent-fallback slug is added; the v1 bound-exhaustion mirror is cut (normal first-message latency is not a silent fallback — code-simplicity-reviewer). The existing own-insert-deferred-unresolved-workspace mirror is REMOVED with pendingScopeRecoveryRef."
  fail_loud: "existing rail error state (conversations-rail.tsx:113-132 'Couldn't load conversations / Retry') — unchanged"
failure_modes:
  - mode: "freshly-started conversation never surfaces via realtime (no recorded drop; row created before steady-state subscription)"
    detection: "AC3 vitest regression (row appears via the unconditional null→id backfill, no recorded drop) + AC10 Playwright MCP live check"
    alert_route: "CI (test failure) pre-merge; post-deploy Playwright run"
  - mode: "backfill fires more than once per null→id transition (amplification) or flashes loading/error"
    detection: "AC4 (exactly-once per transition) + AC4b (quiet refetch, no empty/error flicker)"
    alert_route: "CI (test failure)"
  - mode: "cross-scope leak (row in wrong workspace's / wrong visibility rail under the unconditional backfill)"
    detection: "AC5 scope+visibility isolation test (second workspace's rail does not show the row)"
    alert_route: "CI (test failure)"
logs:
  where: "browser console (dev only); no new server-side logging — the fix is client-hook-scoped"
  retention: "n/a (no new persistent log surface)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail-connect-race.test.tsx test/conversations-rail.test.tsx"
  expected_output: "all AC1-AC6 cases pass (exit 0); the unconditional-backfill no-recorded-drop case, exactly-once, quiet-refetch, scope/visibility isolation, and rail-affordance cases are green"
```

## Test Scenarios

1. Real `ConversationsRail` rendered with a non-empty list → "+ New conversation" link present
   in the header (`href="/dashboard/chat/new"`, accessible name "New conversation") (AC1).
2. Collapsed rail (`useRailCollapsed()` true) → rail returns `null`, affordance absent (AC2).
3. Real `ConversationsRail`; row absent at first fetch / `SUBSCRIBED`; `workspaceId` transitions
   `null→id`; NO own-channel INSERT dropped → row appears via the unconditional backfill before
   completion (AC3).
4. Backfill fires exactly once per `null→id` transition, not per render (AC4); the background
   refetch never flashes the empty/error branch when rows are present (AC4b).
5. Out-of-(repo|workspace)-scope INSERT dropped; second workspace's rail does NOT show this
   workspace's row; a non-`workspace`-visibility peer row is not surfaced by the backfill (AC5 — F3
   isolation).
6. Map-only UPDATE cannot resurrect an absent row; `pendingScopeRecoveryRef` fully removed with no
   dangling reads; the prior armed-drop test updated to the unconditional behavior (AC6).

## Domain Review

**Domains relevant:** Product (UI surface — adds a persistent affordance to an existing rail +
a behavioral change on the most common path)

### Product/UX Gate

**Tier:** advisory — the feature half adds ONE control (a Link) to an existing rail header,
mirroring the existing dashboard "+ New conversation" button (`page.tsx:739-744`); it creates no
new page, multi-step flow, or new component file. The bug half is a behavioral data-freshness fix.
**Decision:** reviewed — wireframe produced (Phase 4.9 artifact gate satisfied), and the
architecture / simplicity / user-impact deepen agents materially reshaped the bug-half.
**Agents invoked:** ux-design-lead (wireframe), architecture-strategist, code-simplicity-reviewer,
user-impact-reviewer (CONCUR); CPO sign-off carried by `requires_cpo_signoff`.
**Skipped specialists:** copywriter (no copy beyond the established "+ New conversation" label
already in `page.tsx:744`; no domain leader recommended one).
**Wireframe:** `knowledge-base/product/design/chat/new-conversation-rail-affordance.pen`
(committed) + screenshots `chat/screenshots/08-…-expanded.png`, `09-…-collapsed-absent.png`.
**Pencil available:** yes (Node v22.22.1, PENCIL_CLI_KEY present, MCP connected).

#### Findings

- The "+ New conversation" affordance reuses the exact label and route of the existing dashboard
  button; it is a parity addition, not a net-new surface. The rail and dashboard never co-render
  (different routes), so no duplication concern. Wireframe documents both toggle states (affordance
  in the expanded rail; absent in the collapsed 56px rail).
- The behavioral fix reinforces the brand's "memory-first / the AI that already knows your
  business" wedge by making the most common path (start a conversation) feel reliable.
- The one place blast radius could exceed the single-user tier is a cross-scope leak into the
  wrong workspace's rail — contained by AC5 (scope-guard parity, the F3 invariant).

No other cross-domain implications detected — single-domain web-platform UI + client-hook change.
