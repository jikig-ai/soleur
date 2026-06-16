---
title: "fix(chat): Recent Conversations rail — optimistic insert for freshly-started conversations"
date: 2026-06-16
type: bug
branch: feat-one-shot-recent-conversations-sidebar-optimistic-insert
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
---

# 🐛 fix(chat): Recent Conversations rail does not show a freshly-started conversation immediately

## Overview

When a user starts a new conversation in the web platform, it does **not** appear in the
left **Recent Conversations** rail until it completes. The word "still" in the report is
literal: this is the **second** attempt. PR #5391 (merged 2026-06-16) added a Supabase
Realtime INSERT subscription + a one-shot `SUBSCRIBED`-status backfill to
`apps/web-platform/hooks/use-conversations.ts`, but the gap persists in the reported
scenario — the rail shows the *previous* "Fix issue 4826" (Done, 3h ago) yet the freshly
started "Fix Issue 4826" (Concierge "Working / Routing to the right experts") never lands.

### Root cause (traced read-only against `origin/main` HEAD)

The conversation row is created **lazily, server-side, on the first WS message**
(`apps/web-platform/server/ws-handler.ts:2165 → :2191 → :897`), NOT on navigation. The
client already knows the final UUID from the `session_started` WS frame
(`apps/web-platform/lib/ws-client.ts:122-123, :1133`; surfaced via `ChatSurface`'s
`onRealConversationId`, `components/chat/chat-surface.tsx:156, :373-376`). Per **ADR-047**
the conversations rail is **portaled per-drill** (it mounts fresh on entry to
`/dashboard/chat/*`, it is NOT permanently mounted — only the context *band* is). So the
"start a new conversation" path frequently does this:

1. User clicks "New conversation" on `/dashboard` → `router.push("/dashboard/chat/new")`
   (`app/(dashboard)/dashboard/page.tsx:622, :741`). The conversations rail is mounted by
   `chat/layout.tsx:71` (it wraps `/dashboard/chat/*` ONLY — it is **not present on
   `/dashboard`**), so it **mounts fresh on this entry**. Within `/dashboard/chat/*` it then
   stays mounted; the fresh mount + connect-race happens **once**, on entry from `/dashboard`.
2. `useConversations` runs `fetchConversations()` (`hooks/use-conversations.ts:288-290`):
   `auth.getUser()` → `/api/workspace/active-repo` round-trip → sets `userId`, then
   `workspaceId`, then `repoUrl`, then the list query. The realtime effect subscribes only
   **after** `userId` resolves (`use-conversations.ts:297-298, :404`).
3. The user's first message lands the server INSERT during this connect window.
   - **Race A — pre-`SUBSCRIBED` INSERT:** Realtime does **not** replay INSERTs buffered
     before `SUBSCRIBED` (`use-conversations.ts:354-360`), and the only recovery — the
     single-shot `if (status === "SUBSCRIBED") fetchConversations()`
     (`use-conversations.ts:373-375`) — can land *just before* the row exists and never
     re-runs. The own-channel INSERT falls in the gap.
   - **Race B — null `workspaceId` in the closure:** The realtime effect can subscribe
     while `workspaceId` is still `null` (it is set inside the same async
     `fetchConversations`). An own-channel INSERT arriving then is **dropped** by
     `shouldDropForScope` at `use-conversations.ts:112` (`conv.workspace_id !== null`), as
     the code itself documents at `:98-99` — relying on the same single-shot backfill that
     Race A defeats.
4. When the conversation later **completes**, an UPDATE fires, but
   `handleConversationUpdate` is `prev.map(...)` (`use-conversations.ts:318-324`) — it
   **patches existing rows only and cannot add a missing one**. The row finally surfaces
   only on the next full refetch (navigation away/back, section switch, or reconnect).
   This is exactly the "appears only after it completes" symptom.

This is a **behavioral fix**, not a build — the rail, the hook, the Realtime publication
(`migrations/034`, `015` REPLICA IDENTITY FULL), and the INSERT path all exist and are
wired. The defect is that the optimistic-insert path depends on a single pre-INSERT
backfill snapshot and a possibly-`null` `workspaceId`.

### Chosen approach (hook-scoped Realtime + backfill hardening — the viable path)

**Spec-flow analysis (2026-06-16) ruled out a naive client-optimistic insert as the
primary fix.** The rail (`conversations-rail.tsx:88`) and the dashboard page
(`app/(dashboard)/dashboard/page.tsx:117`) are **two SEPARATE `useConversations`
instances**, and the **chat surface holds NO instance** of the hook. The full-route chat
page (`app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:56-61`) does **not** even
pass `onRealConversationId`. So a client-side optimistic insert invoked from the chat
surface has **no in-process path to the rail's React state** — it would require lifting the
hook into a shared store/Context above both mount sites, or a cross-instance broadcast the
rail subscribes to. That cross-instance refactor is disproportionate to a read-freshness
fix and is the wrong altitude. **The fix is therefore Realtime + backfill hardening on the
rail's own hook instance** — which is exactly where the bug lives:

1. **Re-run the backfill when `workspaceId` resolves** (not only on the first
   `SUBSCRIBED`). This closes Race B at its root: the row INSERTed with a real
   `workspace_id` is recovered by a refetch once the rail's own `workspaceId` is known.
2. **Make the own-channel INSERT tolerant of an unresolved-scope window**: if `repoUrl`
   or `workspaceId` is still `null` at INSERT time, do **not** silently drop the event with
   no recovery — schedule a bounded recovery refetch once scope resolves (the refetch is
   authoritative; the dropped payload need not be buffered). Keep shared-channel drop
   semantics unchanged. Per `cq-silent-fallback-must-mirror-to-sentry`, if an own-channel
   INSERT is dropped for unresolved scope with no recovery scheduled, mirror it to Sentry
   so the no-op is observable.

These two land on the rail's own instance and **always** apply. They make the new
conversation appear within Realtime/backfill latency (sub-second to a few seconds) — not
"only after it completes". The honest framing: this delivers **"appears within Realtime
latency before completion"**, not a zero-latency client-optimistic insert.

**Deferred (cross-instance optimistic insert — separate follow-up).** A true zero-latency
optimistic insert keyed on the `session_started` UUID (`ws-client.ts:122-123`) requires the
shared-store/Context refactor above. It is filed as a tracking issue (see Deferral Tracking
below), NOT attempted here — the deterministic-race fixes (1)+(2) resolve the reported
symptom without it.

## Research Reconciliation — Spec vs. Codebase

| Claim (from report / prior PIR) | Reality on `origin/main` | Plan response |
|---|---|---|
| "Newly-created conversations appear only after they complete" | Confirmed — completion UPDATE is `map`-only (`use-conversations.ts:318-324`), cannot add a missing row | Fix the insert path, not the update path |
| PIR #5391: "the rail stays mounted (ADR-047) and never re-runs its mount fetch" | **Partly wrong.** ADR-047 keeps the context *band* mounted; the conversations rail **portals per-drill** and remounts on chat entry (`ADR-047-nav-context-band-outside-swap.md` Decision §2; `components/dashboard/rail-slot.tsx:53-62`) | Fix must handle the **fresh-mount connect-race**, which the "always-mounted" framing missed — this is why #5391 was insufficient |
| "INSERT subscription closes the gap" (#5391) | INSERT subscription depends on a single pre-INSERT `SUBSCRIBED` backfill AND a non-null `workspaceId`; both can fail in the fresh-mount window | Re-backfill on `workspaceId` resolve + tolerate null-scope INSERT + client-side optimistic insert on known UUID |
| Conversation row exists at navigation time | **No** — created lazily on first WS message (`ws-handler.ts:2165→2191→897`); URL stays `/dashboard/chat/new` (no remount) | Optimistic insert must key on the `session_started` UUID the client already holds, not assume a DB row |
| `conversations.visibility` blocks the own rail | **No** — default `'private'` (`migrations/075:23-29`); own channel does NOT check visibility (`use-conversations.ts:113` is shared-only). Not the cause | Leave own-channel visibility semantics unchanged |

## User-Brand Impact

**If this lands broken, the user experiences:** they start a new conversation, the
Concierge begins working, but the left Recent Conversations rail does not show it — so they
cannot navigate back to their in-progress work from the rail and the product looks broken
on the single most common path. A regression here (e.g. an optimistic row that never
reconciles, or a row inserted into the wrong workspace's rail) would surface a *phantom* or
*cross-scope* conversation — worse than the current omission.

**If this leaks, the user's workflow is exposed via:** an insert path that bypasses the
`shouldDropForScope` repo_url + workspace_id guard could surface a conversation title in the
wrong repo's / wrong workspace's rail. The fix MUST route every insert path (realtime INSERT
AND the recovery backfill) through the same scope-equivalent guard so the rail never shows a
row the list query would not (the #5391 workspace_id-guard-parity invariant —
`knowledge-base/project/learnings/best-practices/2026-06-16-realtime-event-guard-must-equal-fetch-query-scope.md`).

**Brand-survival threshold:** single-user incident.
(CPO sign-off required at plan time before `/work` begins — `requires_cpo_signoff: true`.
`user-impact-reviewer` runs at review-time.)

## Acceptance Criteria

> **Invariant, not proxy (spec-flow correction):** ACs that render a bare `renderHook`
> instance and assert a *refetch call fired* are proxies — they can pass while the real
> rail (a separate, late-mounting instance) shows nothing. AC1 (vitest) and AC8 (Playwright)
> MUST render/drive the real `ConversationsRail` and assert the **row appears**; AC2/AC3 MUST
> assert the **resulting `conversations` array contains the row**, not merely that
> `fetchConversations` was called (drive the mock so the refetch returns a row set that
> includes the new conversation).

- [ ] **AC1 — Row renders in the real rail on the reported path.** A vitest test renders the
  **real `ConversationsRail`** component (not a bare `renderHook`), drives the mock so the
  rail mounts during the connect window (the reported `/dashboard` → `/dashboard/chat/new`
  entry: `active-repo` resolves AFTER an own-channel INSERT fires, and `workspaceId` starts
  `null` then transitions), and asserts the new conversation **row is present in the rail's
  rendered DOM before any completion UPDATE** (assert on the row title / rail rows under
  `data-testid="conversations-rail"`). Covers both sub-races (pre-`SUBSCRIBED` INSERT and
  null-`workspaceId` INSERT). File: `apps/web-platform/test/conversations-rail-insert.test.tsx`.
- [ ] **AC2 — Backfill on `workspaceId` resolve lands the row.** A test asserts that when
  `workspaceId` transitions `null → <id>` after subscribe, the recovery refetch fires AND
  the refetched row set (mock returns the new conversation) lands in
  `result.current.conversations` (or the rendered rail) — assert the **row**, not just the
  refetch call. The backfill is **bounded**: fires once on the scope-resolve transition, not
  per-render (guard-ref / transition-gate).
- [ ] **AC3 — Null-scope INSERT recovers (not silently lost).** A test asserts an own-channel
  INSERT arriving while `repoUrl`/`workspaceId` are `null` results in the row appearing once
  scope resolves (via the bounded recovery refetch), rather than being dropped with no
  recovery. (May be folded into AC2 if the recovery mechanism is the same scope-resolve
  refetch — keep one test that asserts the **row**.) If a drop with no recovery is ever
  taken, it is mirrored to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
- [ ] **AC4 — Scope-guard parity preserved (the cross-scope-leak containment).** Every insert
  path (realtime INSERT, backfill) is gated by `shouldDropForScope` (repo_url **AND**
  workspace_id **AND** channel-visibility **AND** archive) — the rail never shows a row the
  list query (`use-conversations.ts:215-239`, `.eq(repo_url).eq(workspace_id)`) would
  exclude. Tests: (a) an out-of-(repo|workspace)-scope INSERT is dropped; (b) a second
  workspace's rail does NOT show this workspace's new conversation. This is the F3
  cross-tenant-context-exposure containment invariant — non-negotiable at the single-user
  threshold.
- [ ] **AC5 — UPDATE path unchanged for membership.** The completion UPDATE still only
  patches existing rows; the fix does not add an "UPDATE can resurrect a row" path (the
  insert/backfill path owns membership). Regression test for `handleConversationUpdate`
  map-only semantics (`use-conversations.ts:318-324`) stays green.
- [ ] **AC6 — Hook-source-swap test sweep.** Per
  `learnings/best-practices/2026-06-15-hook-source-swap-sweep-all-real-hook-renderers-not-name-filtered.md`,
  derive the blast radius via
  `git grep -l 'useConversations' apps/web-platform/test/` **minus**
  `git grep -l 'vi.mock("@/hooks/use-conversations"' apps/web-platform/test/`; every
  real-hook renderer (and every channel-mock-chain mock) still passes. Paste the two grep
  outputs in the PR body.
- [ ] **AC7 — Typecheck + suite green.** `cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit` exits 0, and `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/conversations-rail-insert.test.tsx test/conversations-rail.test.tsx
  test/use-conversations-limit.test.tsx` is green; full `scripts/test-all.sh` exits 0.

### Post-merge (operator / automated)

- [ ] **AC8 — Live confirmation (Playwright MCP).** After the web-platform release, drive a
  real session **starting from `/dashboard`** (the reported path — the rail is NOT mounted
  on `/dashboard`, so this exercises the fresh-mount connect-race): open `/dashboard`,
  navigate into a new conversation, send the first message, and assert the new conversation
  row appears in the Recent Conversations rail **within seconds and before completion**,
  without a reload. Also assert **scope isolation** (the row does not appear in a different
  workspace's rail — the F3 containment). `Automation: feasible via mcp__playwright__*
  against the deployed app` — run it; do not punt to a manual operator step.

## Implementation Phases

> Scope is **hook-only**: the rail's own `useConversations` instance. No chat-surface
> wiring (the optimistic cross-instance path is deferred — see Deferral Tracking).

1. **Phase 0 — Preconditions (verify, do not assume).**
   - Re-confirm the two-instance reality: `git grep -n "useConversations(" apps/web-platform`
     — exactly the rail (`conversations-rail.tsx:88`) + dashboard page
     (`app/(dashboard)/dashboard/page.tsx:117`); chat surface holds none. (Verified at plan
     time by spec-flow-analyzer.) This is why the fix is hook-only.
   - Confirm the rail mount boundary: `chat/layout.tsx:71` mounts the rail for
     `/dashboard/chat/*` only (not `/dashboard`) — the fresh-mount connect-race fires on
     entry.
   - Re-read `use-conversations.ts:288-404` (fetch + realtime effect) and confirm the
     `SUBSCRIBED` backfill (`:373-375`) + `shouldDropForScope` (`:102-118`) shapes are
     unchanged from this plan's citations.
   - Confirm the active-repo route self-heal divergence (PIR Race C, latent edge):
     `app/api/workspace/active-repo/route.ts:48-65` self-heals a removed-from-workspace user
     to solo, but `createConversation` (`ws-handler.ts:865, :892`) does not — note as a
     latent out-of-scope edge unless deepen-plan elevates it.
2. **Phase 1 (RED) — failing tests.** Add AC1–AC5 cases to
   `test/conversations-rail-insert.test.tsx`. AC1 must render the **real `ConversationsRail`**
   and drive the mock so `active-repo` resolves AFTER the INSERT and `workspaceId` starts
   `null` (the existing harness resolves scope synchronously — extend it to defer/reorder so
   the connect-race actually arises). Reuse the channel-mock-chain harness.
3. **Phase 2 (GREEN) — hook fix.** In `hooks/use-conversations.ts`:
   - Re-run the bounded backfill when `workspaceId` resolves (Race B). Transition-gate it
     (fire once on `null → id`), not per-render; add a guard ref.
   - On an own-channel INSERT with unresolved scope, schedule a bounded recovery refetch
     instead of a silent drop with no recovery (Race A/B residue). If a drop with no recovery
     is ever taken, mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
4. **Phase 3 (REFACTOR).** Collapse the backfill triggers (SUBSCRIBED + scope-resolve +
   null-scope-recovery) behind one bounded helper; keep `shouldDropForScope`/`deriveRailTitle`
   as the single guard/title source so INSERT/UPDATE/backfill cannot drift.
5. **Phase 4 — verify.** AC6 sweep, AC7 typecheck + suite, AC8 Playwright MCP post-deploy.

## Files to Edit

- `apps/web-platform/hooks/use-conversations.ts` — backfill-on-`workspaceId`-resolve +
  bounded null-scope INSERT recovery + (if a drop is unavoidable) Sentry mirror.
- `apps/web-platform/test/conversations-rail-insert.test.tsx` — AC1–AC5 tests; extend the
  harness so the connect-race (deferred `active-repo`, null→id `workspaceId`) is reproducible,
  and add a real-`ConversationsRail` render case.

## Files to Create

- (none expected) — new tests land in the existing
  `test/conversations-rail-insert.test.tsx`. A new test file is created only if deepen-plan
  splits a focused backfill unit out; if so it lives under `apps/web-platform/test/` to
  satisfy the vitest `test/**/*.test.tsx` happy-dom glob (`vitest.config.ts:63-64`).

## Deferral Tracking

- **Zero-latency client-optimistic insert (cross-instance).** A true optimistic insert keyed
  on the `session_started` UUID (`ws-client.ts:122-123`) is **deferred**. Why: the rail and
  chat surface are separate `useConversations` instances (the chat surface holds none), so it
  requires lifting the hook into a shared store/Context above both mount sites — a refactor
  disproportionate to a read-freshness fix. Re-evaluation criteria: if Realtime+backfill
  latency proves perceptibly slow in dogfooding (AC8 shows > a few seconds), or if a future
  feature already lifts `useConversations` into a shared store. **Action for /work:** file a
  GitHub issue (label `domain/engineering`, `priority/p3-low`) capturing this with the
  re-evaluation criteria and a roadmap pointer; do NOT leave the deferral untracked.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` returns no scope-outs touching
`use-conversations.ts` or `conversations-rail.tsx`. Open issues #3026
cursor-pagination/virtualization and #3027 pin-conversations are feature follow-ups on the
rail, not this bug, and touch different concerns — acknowledged, left open.)

## Risks & Mitigations

- **R1 — Two `useConversations` instances (confirmed).** The rail
  (`conversations-rail.tsx:88`) and dashboard page (`page.tsx:117`) are separate hook
  instances; the chat surface holds none. This is why a client-optimistic insert is NOT the
  fix here. Mitigation: scope to the rail's own instance (Realtime + backfill hardening),
  which is where the bug lives; defer the cross-instance optimistic insert (Deferral
  Tracking). No mitigation needed for the chosen approach — the risk is what *ruled out* the
  naive approach.
- **R2 — Backfill amplification.** Re-running the backfill on `workspaceId` resolve must not
  create a refetch loop. Mitigation: transition-gate it (fire once when `null → id`), keep
  the existing `[userId, workspaceId, archiveFilter, limit, fetchConversations]` dep shape
  and a guard ref (AC2 asserts bounded).
- **R3 — Scope-guard drift / cross-scope leak (F3).** Any insert path (INSERT, backfill)
  that bypasses `shouldDropForScope` reintroduces the #5391 workspace_id-parity bug and can
  surface a conversation in the wrong workspace's rail — a cross-tenant context exposure that
  exceeds the single-user threshold. Mitigation: AC4 (both the drop test AND the
  second-workspace-rail isolation test) + the realtime-guard-equals-fetch-scope learning;
  route every insert through the one guard. The most important invariant in this plan.
- **R4 — Latency framing.** The chosen approach delivers "appears within Realtime/backfill
  latency", not zero-latency. Mitigation: AC8 measures the live latency post-deploy; if it is
  perceptibly slow, the Deferral Tracking item's re-evaluation criterion fires.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (It is filled.)
- ADR-047 keeps the **context band** mounted, NOT the conversations rail — do not inherit
  the #5391 PIR's "rail stays mounted" framing; the rail remounts per chat-drill, which is
  the source of the connect-race.
- The conversation row is **deferred** (created on first WS message), so any optimistic
  insert keyed on the `session_started` UUID precedes the DB row — the row is not yet
  fetchable by a backfill until the first message lands.

## Observability

```yaml
liveness_signal:
  what: "Recent Conversations rail populates a freshly-started conversation before completion"
  cadence: "on every new-conversation start (user-interactive)"
  alert_target: "none (read-freshness UX; not an error-path event — PIR #5391 established read-freshness gaps do not fire Sentry/Better Stack)"
  configured_in: "n/a — verified by the AC8 Playwright MCP post-deploy check, not a monitor"
error_reporting:
  destination: "Sentry (browser SDK) — genuine error paths only: a backfill refetch that fails surfaces via the existing useConversations error state (use-conversations.ts:240-243, :281-283); plus a NEW mirror if an own-channel INSERT is dropped for unresolved scope with no recovery scheduled (cq-silent-fallback-must-mirror-to-sentry)"
  fail_loud: "existing rail error state (conversations-rail.tsx:113-132 'Couldn't load conversations / Retry') — unchanged"
failure_modes:
  - mode: "own-channel INSERT dropped by stale-null scope with no recovery"
    detection: "AC1-AC3 vitest regression + AC8 Playwright MCP live check + Sentry mirror on the drop"
    alert_route: "CI (test failure) pre-merge; post-deploy Playwright run; Sentry on live drop"
  - mode: "backfill refetch loop (amplification)"
    detection: "AC2 transition-gate test asserts backfill fires once on null→id, not per-render"
    alert_route: "CI (test failure)"
  - mode: "cross-scope leak (row in wrong workspace's rail)"
    detection: "AC4 scope-isolation test (second workspace's rail does not show the row)"
    alert_route: "CI (test failure)"
logs:
  where: "browser console (dev only); no new server-side logging — the fix is client-hook-scoped"
  retention: "n/a (no new persistent log surface)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail-insert.test.tsx"
  expected_output: "all AC1-AC5 cases pass (exit 0); the connect-race + backfill-on-resolve + scope-guard/isolation cases are green"
```

## Test Scenarios

1. Real `ConversationsRail` rendered; `active-repo` resolves AFTER an own-channel INSERT;
   `workspaceId` starts `null` → row renders in the rail before completion (AC1).
2. `workspaceId` transitions `null → id` after subscribe → recovery backfill returns the row,
   row lands in `conversations` (AC2/AC3).
3. Out-of-(repo|workspace)-scope INSERT → dropped; second workspace's rail does NOT show this
   workspace's row (AC4 — the F3 isolation invariant).
4. Completion UPDATE for a row NOT present → does not resurrect it (AC5, map-only preserved).

## Domain Review

**Domains relevant:** Product (UI surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed (CPO signed off on the single-user-incident framing; spec-flow-analyzer
ran with the UI-flow-aware proxy-vs-invariant lens and materially reshaped the plan)
**Agents invoked:** cpo, spec-flow-analyzer
**Skipped specialists:** ux-design-lead (N/A — no new/changed visual surface; this is a
data-freshness behavioral fix on the existing rail, creates no new page/component/flow);
copywriter (no domain leader recommended one — no copy change)
**Pencil available:** N/A (no UI surface to wireframe)

#### Findings

- **CPO:** Signed off on the `single-user incident` threshold (correct tier — most common
  path on the operator's daily surface; the one place blast radius could exceed the tier is a
  cross-scope leak into the wrong workspace's rail, contained by AC4). Confirmed the fix
  reinforces the brand's "memory-first / the AI that already knows your business" wedge.
  `wg-ui-feature-requires-pen-wireframe` does NOT fire (no new page/component/form). Conditions
  (all in-plan): AC4 scope-parity holds; AC8 Playwright not punted to manual; phantom/reconcile
  handled (now moot — optimistic path deferred).
- **spec-flow-analyzer:** Found AC1–AC4 (v1) were hook-instance **proxies** that could pass
  while the real rail (separate, late-mounting instance, no writer wired) showed nothing;
  confirmed the rail/chat-surface are separate `useConversations` instances and the full-route
  chat page passes no `onRealConversationId` (so a client-optimistic insert has no writer path
  to the rail). Plan revised: optimistic path **deferred**, fix re-scoped to Realtime+backfill
  hardening on the rail's own instance, AC1/AC8 re-anchored to render the **real**
  `ConversationsRail` and assert the **row** (not a refetch call), AC4 adds the cross-workspace
  isolation case, AC1 premise corrected (rail not mounted on `/dashboard`).
