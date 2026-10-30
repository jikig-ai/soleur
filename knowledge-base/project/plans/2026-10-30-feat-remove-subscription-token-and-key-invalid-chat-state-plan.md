---
title: "feat: remove a stored subscription token, and define chat state after a key_invalid card"
type: feat
date: 2026-10-30
slug: feat-remove-subscription-token-and-key-invalid-chat-state
branch: feat-one-shot-11524-11525-oauth-remove-key-invalid-chat
issue: 11524
closes: [11524, 11525]
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: remove a stored subscription token, and define chat state after a key_invalid card

## Enhancement Summary

**Deepened on:** 2026-10-30
**Passes:** premise/attribution re-verification (issue and PR states, rule ids, labels, migration ordinal on a fresh `origin/main`), halt gates 4.6-4.13 (all pass), precedent diff for the new SQL function, post-edit self-audit for dropped symbols, and a 4-agent plan review plus three CTO ruling rounds that preceded it.

### Key Improvements

1. DELETE goes through a service-role RPC (ADR-048 write boundary) instead of an app-level delete that could reach the user's `anthropic` fallback key; the precedent diff against migration 096 is recorded.
2. Three first-draft premises were corrected with code evidence: `errorOccurrence` is unreachable (dropped), the `ws-handler.ts` ladder edit is dead code (dropped), and the Reconnect rebind relies on the server answering `resume_session` with `session_started` (pinned by a reducer test, with a one-shot `start_session` fallback split between hook and surface).
3. Settings copy and control are keyed on "in effect" (`isCcOauthEnabled() && is_valid`) so an inert stored token stays removable without a false billing claim.

### New Considerations Discovered

- Removing the owner's token returns delegated leases to the owner's API key (baseline behavior): recorded in the ADR-048 addendum with a lease test.
- The hook cannot own the `start_session` fallback because it does not hold the start options; the surface does (`rebindRefused`).
- Existing `toEqual` pins on `lastError` forbid adding any field to `lastError` or `lastError.action`.

## Overview

Two deferred follow-ups from the #11086 Concierge sign-in work ship together in one PR.

1. **#11524 — remove a stored subscription token.** An account holding a stored subscription token
   (`api_keys.provider = 'anthropic_oauth'`) gets a Settings control that deletes it without a
   replacement. A new `DELETE /api/keys` write surface calls a new service-role-only RPC
   (`delete_oauth_credential`) that hard-deletes exactly that row. Settings learns whether the row exists
   and whether it is in effect, and asks for an explicit confirmation that names the consequence
   (subscription to API key, or no credential at all). Nothing is created, copied or converted by the
   removal, so the billing-basis change stays an explicit user decision.
2. **#11525 — chat state after a `key_invalid` card.** The composer is disabled while the credential is
   blocked, a message can no longer be shown optimistically and then silently dropped, the card gains an
   explicit **Reconnect** that re-binds the session so the next message is accepted, an always-visible
   helper line ("Saved your token in Settings? Select Reconnect to continue.") covers the fixed-in-Settings case, a repeated failure after Reconnect re-shows the card, and the
   multi-tab semantics are pinned by tests.

Both are the same defect family: after the lease fails closed, the user has no exit that does not involve
a replacement credential, and the chat gives no honest state about it.

Wireframes (committed, CPO condition): `knowledge-base/product/design/settings/subscription-token-removal-and-key-invalid-chat.pen`
(7 frames; PNG exports `08-…` to `14-…` in `knowledge-base/product/design/settings/screenshots/`).
The `.pen` and screenshots are the source of truth for layout; the copy tables below are the contract the
tests assert (where they differ, the tables win and the `.pen` note is updated).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief / first-pass review) | Reality (verified) | Plan response |
|---|---|---|
| "`POST /api/keys` is the only route; there is no DELETE" (#11524) | True: `app/api/keys/route.ts` exports only `POST`. `app/api/services/route.ts` has a DELETE, but it validates an allowlist of service providers that excludes `anthropic_oauth`. | New `DELETE` on `/api/keys`; do not widen the services route. |
| The oauth write boundary is "an app-level `.eq` chain is enough" (first draft) | ADR-048 and migration 096 route every `anthropic_oauth` write through a service-role-only `SECURITY DEFINER` RPC that hardcodes the provider, so a regressed caller cannot touch the `anthropic` row (the user's only fallback credential). | DELETE goes through a new RPC `delete_oauth_credential(p_user_id)` (CTO H4); migration 179 + down. |
| "composer is not disabled" (#11525) | True by code reading: `teardown()` never calls `setStatus`, so `status` stays `"connected"`; `ChatInput disabled={status !== "connected" \|\| firstRunBusy}` stays enabled; `sendMessage` dispatches `add_message` then `send()` no-ops on a closed socket. No existing test pins composer state after `key_invalid`. | Failing test first, then the derived `credentialBlocked` state. |
| "the error frame is user-scoped (every open conversation tab is torn down)" | The server keeps ONE live socket per user (`supersedeExistingUserSocket`, close 4002); the frame carries no `conversationId`. A blocked tab has no live socket (teardown nulls `onclose`), so a second tab cannot reach it. | Frame stays user-scoped (credential is account-global); behavior pinned by tests (G7); no cross-tab signal (#11597). |
| "`lastError` card has no defined lifecycle on a repeated failure" | A repeat blocked frame needs a live socket; `teardown()` makes `mountedRef` false so late frames are dropped; the only way back is `reconnect()` which calls `setLastError(null)`, and the existing effect in `chat-surface.tsx` resets `dismissedErrorKey` on null. The identical-key hide cannot occur through any reachable path except a late old-socket frame inside one React batch. | No new state field (CTO H1 dropped `errorOccurrence`); the lifecycle is pinned by a test: dismiss, Reconnect, second `key_invalid` shows the card. |
| "Settings … hasApiKey" can gate the new control | `settings/page.tsx` reads only `provider='anthropic'`; an oauth-only operator sees "No key configured" and cannot see the oauth row. The lease reads the oauth row only when `isCcOauthEnabled()` and with `is_valid=true`. | Second query selecting `provider, is_valid, updated_at`; remove control shown for ANY stored row (CTO H6), copy keyed on "in effect" = `isCcOauthEnabled() && is_valid`. |
| "returning from Settings gives no saved/resend hint" | `ErrorCard` action is a same-tab `NavLink`, so the chat unmounts on the way to Settings and remounts fresh (mount effect clears `lastError`). A hint is only reachable if the chat tab survives. | For `key_invalid`/`byok_key_missing` the action opens in a new tab, derived in `chat-surface.tsx` from `lastError.code` (no field in `lastError.action`, CTO H7); remount path resets (next send re-leases; card returns if still bad). |
| Reconnect "just calls `reconnect()`" (implicit) | After a key_invalid teardown, `reconnect()` goes connecting to connected without passing `reconnecting`, so `sessionStarted` is never reset and the new socket never gets `start_session`/`resume_session`; the server answers `chat` with "No active session" (`chat` case in `ws-handler.ts`). `teardown()` also nulls `realConversationId`. The server answers `resume_session` with `session_started`, so the client sets `sessionKind="fresh"` and does NOT refetch history; retained local messages are the on-screen transcript (CTO H3 restates G2). | `onCredentialReconnect` + `rebindConversationId` + one-shot `start_session` fallback when the resume is refused (H3). |
| `byok_key_missing` is handled client-side | Not handled client-side: the `error` case in `ws-client.ts` falls through to a generic "Error: …" bubble. The SERVER already emits the code on every path (`resolveSessionErrorCode` in `agent-runner.ts`, `sendUserMessage`, `cc-dispatcher`'s `MissingByokKeyError` arm); the `ws-handler.ts` deferred-creation `.catch` ladder never receives lease errors, so a ladder edit would be dead code. | G4 is client-only (CTO H2): no `ws-handler.ts` edit, no ladder test; a client test proves the frame produces the blocked state. |
| ADR-308 "open follow-ups: #11524, #11525" | Confirmed in `## Consequences`. ADR-048 addendum (2026-10-29) states the documented fallback when NO oauth row exists is the `anthropic` api_key. | ADR-308 amendment + ADR-048 addendum in this PR (no new ADR ordinal). |
| "billing-basis decision stays explicit" covers delegated leases | With an owner oauth row present, a delegated or owner-mismatched lease throws `OauthDelegationForbiddenError`; with the row gone it falls through to the owner's `anthropic` key (baseline pre-oauth delegation behavior). Operator-only feature (POST fence). | One sentence in the ADR-048 addendum + one lease test (CTO H5); no dialog copy. |

## Research Insights

**Premise Validation.** #11524 and #11525 are OPEN, no closing PR. Draft PR #11593 is this branch's own
PR (the collision pre-check hit is self). Parent #11086 is still OPEN (its fix merged as #11523). Cited
files/symbols all present on `origin/main`: `app/api/keys/route.ts` (POST only), `byok-lease.ts`
`fetchAgentCredentialIntoSlot` (oauth row preferred when `isCcOauthEnabled()`, fail-closed
`oauth_unusable`, else the `anthropic` row, else `MissingByokKeyError`), `ws-client.ts` `key_invalid`
branch + `teardown()`, `chat-surface.tsx` card and composer. ADR corpus grep (`anthropic_oauth`,
`oauth_unusable`): ADR-048 and ADR-308 only; neither rejects an explicit-delete mechanism, both defer
removal to #11524; ADR-048's RPC-only write boundary is honored (H4). Migration 178 narrowed `api_keys`
grants for `authenticated` to SELECT only (writes via service role). Latest migration on `origin/main`
is 178; the release workflow runs migrate + verify-migrations before deploy, so the RPC exists before
the route that calls it is live.

**Property List** (what the ask buys, one observable outcome each):

- P1. A user can erase their own stored subscription token with no replacement value.
- P2. The user is told, before confirming, which billing basis applies next (API key, none, or unchanged because the token is not in effect).
- P3. Nothing is created, copied or converted by the removal, and the `anthropic` row cannot be touched by it.
- P4. After a `key_invalid` card, a typed message is never shown as sent when it was not.
- P5. After fixing the credential, the user can resume the same conversation with an explicit action.
- P6. A repeated key_invalid after Reconnect is always visible, whatever the user dismissed before.
- P7. The multi-tab behavior is defined and pinned.

**Cut List** (mechanism, property, what already covers it):

- Audit table / migration for credential events: P1 needs only a durable record; a pino log line (Better Stack) + Sentry breadcrumb is the repo's pattern (POST has no audit table either). Cut. (The migration that IS added is the delete RPC, not an audit store.)
- Response `fallback` field + second post-delete read: the dialog already names the consequence from props; a duplicated `is_valid` predicate would drift from the lease. Cut (plan review).
- `errorOccurrence` counter: no reachable path needs it (H1). Cut.
- `ws-handler.ts` ladder edit and its test: dead code, the server already emits `byok_key_missing` (H2). Cut.
- Forced warm-Query eviction across hosts: not needed for P1-P3 (a new lease cannot see the row); state is process-local. Cut, deferred (#11596).
- BroadcastChannel cross-tab clear: Reconnect + hint cover P5. Cut, deferred (#11597).
- One-click Resend: would duplicate the user bubble; "send it again" copy covers P5. Cut, deferred (#11595).
- `conversationId` on the key_invalid frame: credential is account-global; P7 is a test, not a wire change. Cut.
- Persisting the blocked flag in sessionStorage: a stale flag could block a user who already fixed the credential. Cut (G1).
- A `newTab` field on `lastError.action`: breaks an existing `toEqual`; derived in the surface instead (H7). Cut.
- The first-run-send boolean test: `fr.started` stays latched and `runFirstRunSend`'s `send` callback is typed `=> void` (a boolean-returning function is assignable); nothing resends after Reconnect. Cut.

**Institutional learnings applied** (paths under `knowledge-base/project/learnings/`):

- `2026-06-02-two-row-by-provider-credential-and-lease-accessor-rename-sweep.md`: the two provider rows are independent; the RPC hardcodes `anthropic_oauth` and a test proves the `anthropic` row is untouched.
- `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md` (`hr-write-boundary-sentinel-sweep-all-write-sites`): every `api_keys` write site is enumerated below; no new sentinel (the RPC hardcodes provider).
- `2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md`: DELETE calls `validateOrigin`.
- `2026-03-27-websocket-close-code-routing-reconnect-loop.md`, `2026-04-02-defensive-state-clear-on-useeffect-remount.md`: teardown stays; the mount effect keeps clearing `lastError`.
- `2026-05-20-happy-dom-ws-fetch-blockade.md` and the existing `MockWebSocket` in `test/ws-client-key-invalid-teardown.test.tsx`: `close()` is a `vi.fn()` that does not change `readyState`, so refusal must key off the blocked state, not only off `readyState`.
- `2026-10-26-new-pen-needs-committed-skeleton-before-open-document.md`: followed (intent-to-add; see wireframes).
- `2026-09-30-a-layer-scoped-base-box-fixed-the-collapsed-icons…md`: `Button` padding beats caller `className`; happy-dom cannot see layout, so the new buttons get a real-browser bounding-box check in QA.
- `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`: ADR-308/048 amended in-PR.
- `cq-pg-security-definer-search-path-pin-pg-temp`: the RPC pins `search_path = public, pg_temp`.

## Problem Statement / Motivation

- An operator with a dead subscription token and no fresh `claude setup-token` value has exactly one exit
  today: save a valid token. The lease fails closed (`oauth_unusable`, no fallback), so the only way to run on
  the API key is `CC_OAUTH_ENABLED` off or a row removed outside the product (#11524).
- After the `key_invalid` card, a message typed in the same chat is shown and silently dropped, the composer
  looks live, no "saved, resend" cue exists, Reconnect is not offered (and would not rebind the session), and
  `byok_key_missing` renders as a generic assistant-style error (#11525).

## Proposed Solution

### A. `DELETE /api/keys` + `delete_oauth_credential` RPC (#11524) — rulings F6, F7, F8, F9, H4

- **Migration `apps/web-platform/supabase/migrations/179_delete_oauth_credential.sql`** (+ `.down.sql`; re-check the free ordinal
  against `origin/main` at implementation): `delete_oauth_credential(p_user_id uuid) RETURNS boolean`, `LANGUAGE sql`,
  `SECURITY DEFINER`, `SET search_path = public, pg_temp`; body is a `DELETE … WHERE user_id = p_user_id AND provider = 'anthropic_oauth' RETURNING`
  wrapped as `EXISTS`; `REVOKE EXECUTE … FROM PUBLIC, authenticated, anon; GRANT EXECUTE … TO service_role` (mirror migration 096's
  `store_oauth_credential` block); `COMMENT ON FUNCTION`. Down migration drops the function. Run the repo's migration/grants guard tests
  (`git grep -ln "migrations" apps/web-platform/test` plus `rls-authz-fuzz`) and the `.sql` lint.
- Route handler order: `validateOrigin` / `rejectCsrf` → `verifiedUserId` (401) → body must be exactly `{ credential_type: "oauth_token" }`, else 400
  `{ error, code: "unsupported_credential_type" }` (a bare or mistyped DELETE can never reach the RPC; the provider is never taken from input).
- **No operator / `CC_OAUTH_ENABLED` fence** (F6): a user can always erase their own stored secret, including after the kill-switch is flipped off.
  The route passes only `p_user_id` (the verified id) to the RPC through `createServiceClient()`.
- Response `200 { deleted: boolean }`. Idempotent: absent row → `deleted:false`, still 200. No soft delete / `is_valid=false` (CLO: "removed" must be true).
- RPC error → the route's existing pattern (`logger.error({ err }, …)` + `Sentry.captureException(err, { tags: { feature: "api-keys", op: "delete-oauth" }, extra: { userId, provider: "anthropic_oauth" } })`)
  and 500 `{ error: "Failed to remove token" }`; never a fallback to a direct table delete. (Staying on the route's own logging pattern keeps the module graph the existing
  `api-keys-*` tests mock: `@/server/logger` default export and `@sentry/nextjs` `addBreadcrumb`/`captureException`.)
- Audit = `logger.info({ feature: "api-keys", op: "oauth-credential-removed", userId, deleted }, …)` (top-level `userId`, pseudonymised by the pino
  formatter, ADR-029) + `Sentry.addBreadcrumb` (no user id, no value). Never the value, never the request body.

### B. Settings UI (#11524) — F9, H5, H6, CPO, CLO copy constraints

- Shared flag: new `apps/web-platform/server/cc-oauth-flag.ts` exports `isCcOauthEnabled()` (the exact predicate currently private at the top of
  `byok-lease.ts`, `"1"`/`"true"`); `byok-lease.ts` and `settings/page.tsx` import it so the page cannot drift from the lease (CTO H6).
- `settings/page.tsx`: add `service.from("api_keys").select("provider, is_valid, updated_at").eq("user_id", …).eq("provider","anthropic_oauth").maybeSingle()` in
  the existing `Promise.all`; pass `hasOauthToken={!!row}`, `oauthInEffect={isCcOauthEnabled() && row?.is_valid === true}`, `oauthTokenSavedAt`.
  `hasApiKey` keeps its existing meaning (`anthropic`, `is_valid=true` = what the lease reads).
- `settings-content.tsx`: thread `hasOauthToken`/`oauthInEffect` to `KeyRotationForm` (it currently forwards only `hasExistingKey` and
  `canUseOauthCredential`); status lines `Subscription token: saved <date>` and `Conversations use: …` from the pure helper `lib/credential-basis.ts`
  (`describeCredentialBasis({ hasOauthToken, oauthInEffect, hasApiKey })`). No token fragments.
- New `components/settings/remove-subscription-token-dialog.tsx` (inline expand-in-place confirm, mirroring `disconnect-repo-dialog.tsx`; `Button`
  primitives only, `usePendingAction`, `role="alert"` error). Rendered by `key-rotation-form.tsx` (fragment after the `<form>`) whenever `hasOauthToken`
  (any stored row, regardless of operator status, kill-switch or `is_valid`); the parent owns the post-removal notice (the dialog unmounts when
  `router.refresh()` flips `hasOauthToken`) and `onAddApiKey` (switch the credential radio to API key and focus `#api-key-input`).
- Copy contract (CPO + CLO + H6; one noun per surface, no "credential" in user copy; never claim Soleur revokes the token at Anthropic, never advertise subscription billing):

| Surface | Exact copy |
|---|---|
| Control | `Remove subscription token` (outlined, destructive-leaning) |
| Dialog title | `Remove subscription token?` |
| Body A (in effect, API key stored) | `Conversations will use your Anthropic API key, and its usage charges apply. Conversations already open keep using the token until they end. Removing it here does not revoke it with Anthropic - revoke it in your Claude account if it may be exposed.` |
| Body B (in effect, no API key) | `You will have no sign-in for Claude until you add an API key, and chat will stop working.` + the same revoke sentence |
| Body C (not in effect: kill-switch off or token invalid) | `Soleur is not using this token for conversations. Removing deletes the saved copy.` + the same revoke sentence; no billing claim, no "Add an API key first" |
| Buttons | `Keep token` (default focus) / `Remove token` (loading label `Removing`); variant B adds `Add an API key first` (ghost Button) |
| Post-removal notice | A: `Subscription token removed. New conversations will use your API key.` / B: `Subscription token removed. Add an API key to keep using chat.` / C: `Subscription token removed.` (`role="status"`, text chosen from the props the user confirmed against) |
| Errors | non-OK/5xx: `Failed to remove the token. Please try again.`; network: `Network error. Please try again.` |

  Focus after success: `#api-key-input` for B, otherwise the notice region (`tabIndex={-1}`). Typed text in the add-key input is untouched.

### C. Chat after `key_invalid` / `byok_key_missing` (#11525) — F1-F4, G1-G8, H1-H3, H7

Hook (`lib/ws-client.ts`):

- `send()` returns `boolean` (true only when `readyState === OPEN`). `sendMessage` returns `boolean`: it refuses BEFORE `reset_connection` and the
  optimistic `add_message` when blocked or the socket is not open. A refusal that is NOT the expected blocked state mirrors to
  `reportSilentFallback` from `lib/client-observability` (`feature: "send-message"`, `op: "refused-socket-not-open"`; `cq-silent-fallback-must-mirror-to-sentry`).
  Other callers of `send()` (`resumeSession`, review-gate responses) ignore the return value (unchanged).
- `credentialBlocked` is **derived** from `lastError?.code` being `key_invalid` or `byok_key_missing` (G7). A ref mirror gives `sendMessage` a synchronous
  read and is assigned **synchronously** in the error branch and in `reconnect()` (not in an effect), so there is no window where the ref and state disagree.
  `reconnect()` clears it through the existing `setLastError(null)`; the mount effect already does too.
- ONE shared handler for both codes (`key_invalid` keeps its pinned shape): bookkeeping BEFORE `teardown();` — capture `rebindConversationId` from
  `realConversationIdRef.current` only when the thread has ≥1 user message (the server persists the row before the lease), mark the last user message
  `unanswered`, set the blocked ref — then `setLastError` and `teardown()`. `key_invalid` lastError shape is unchanged (existing `toEqual` assertions stay valid);
  `byok_key_missing` sets `{ code: "byok_key_missing", message: "Add an API key in Settings to continue.", action: { label: "Add API key", href: "/dashboard/settings" } }`.
- Rebind (H3): the server answers `resume_session` with `session_started`, so the client sets `sessionKind="fresh"`, does NOT refetch history, and the retained
  local messages stay the transcript. A `rebindArmedRef` is set when the rebind resume is sent and cleared on `session_started`; if an `error` frame arrives while it is
  armed, drop `rebindConversationId`, show no extra error bubble, and fall back ONCE to `startSession` (never loop). The hook does not know the original start options
  (`leaderId`, context, `resumeByContextPath` live in the surface), so the fallback is split: the hook sets a returned `rebindRefused: boolean` (and clears
  `rebindConversationId`); the surface effect `if (rebindRefused) setSessionStarted(false)` re-fires the existing start/resume effect, which now has no rebind id and calls
  `startSession(...)` with the surface-held options. `rebindRefused` resets on `reconnect()` and mount. `rebindConversationId` is also cleared on mount.
- Reducer: `ChatMessage.unanswered?: boolean` (type in `lib/chat-state-machine.ts`) and action `mark_last_user_unanswered` — the reducer (`chatReducer`/`ChatAction`)
  lives in `lib/ws-client.ts` — a no-op when the last message is not a user message. Not persisted; history hydrate drops it (accepted, G5).

Surface (`components/chat/chat-surface.tsx` + `chat-input.tsx` + `error-card.tsx` + `message-bubble.tsx`):

- `ChatInput onSend` returns `boolean | void`; only an explicit `false` means not accepted. `handleSubmit` restructure (the current `finally` prunes staged
  attachments unconditionally and uploads happen BEFORE `onSend`): track `sent`; on `false` keep the draft, skip `onAtDismiss`, and prune attachments only when
  `sent` (uploaded refs stay marked `uploaded`; a later re-upload duplicating a storage object is harmless). `handleSubmit` also returns early when `disabled`
  (before any upload).
- `handleSend` returns `false` when `status !== "connected"` or blocked — **before** `onBeforeSend` (so analytics never counts a refused send) — which also fixes the
  existing silent draft drop on a non-connected status.
- The surface derives `blocked` locally from `lastError?.code` (not only from the hook's `credentialBlocked`, so tests that drive `wsReturn.lastError` directly work) and
  guards `rebindConversationId` by truthiness (`if (rebindConversationId)`), never `!== null`.
- Composer `disabled` adds `|| blocked`; placeholder per copy table; visible helper line under the composer (`role="status"`, `aria-live="polite"`) with an inline
  `Reconnect` ghost Button (the recovery path survives a dismissed card — wireframe 6a).
- `ErrorCard` gets an optional `newTab` prop; `chat-surface.tsx` passes `newTab` for the two blocked codes (derived from `lastError.code`, same site that derives
  title/retry/label), rendering a plain `<a target="_blank" rel="noopener noreferrer">` (precedent: `message-bubble.tsx` external link) instead of `NavLink`. For blocked
  codes `onRetry={onCredentialReconnect}` with `retryLabel="Reconnect"`. No field is added to `lastError.action`.
- Dismiss key stays `` `${lastError.code}::${lastError.message}` ``. Dismiss hides the card only; the composer stays disabled (F5). Lifecycle pinned by test
  (dismiss → Reconnect → second `key_invalid` shows the card; mutation: delete the null-reset effect → test reds).
- `onCredentialReconnect = () => { setSessionStarted(false); reconnect(); }`. The start/resume effect: `conversationId === "new"` and a truthy
  `rebindConversationId` → `resumeSession(rebindConversationId)` (no duplicate conversation); `startSession` only when absent; non-`new` ids unchanged. The `?msg=`
  first-run latch stays consumed; Reconnect never auto-resends.
- No tab-return hint (CTO ruling on plan-review cut, supersedes G8): the always-visible helper line carries the "saved" wording; no `visibilitychange` listener, hint state or close control exists. The `.pen` wireframe frame that draws a return hint is superseded by this line.
- Orphan bubble (G5): a user message flagged `unanswered` shows `Not answered` with sr-only `No reply was started` (`message-bubble.tsx`).

| Surface | Exact copy |
|---|---|
| Card titles | `Claude Sign-in Failed` (oauth scheme) / `Invalid API Key` (otherwise) / `API Key Required` (`byok_key_missing`) |
| Card action | `Update token` (oauth) / `Update key` / `Add API key` — new tab |
| Card retry | `Reconnect` |
| Composer placeholder | oauth: `Update your token in Settings, then reconnect` / otherwise `Update your key in Settings, then reconnect` |
| Helper line | oauth: `Saved your token in Settings? Select Reconnect to continue.` / otherwise `Saved your key in Settings? Select Reconnect to continue.` |
| Bubble flag | `Not answered` |

### Precedent diff — `delete_oauth_credential` vs `store_oauth_credential` (migration 096)

| Aspect | Precedent (`store_oauth_credential`, 096) | This plan (`delete_oauth_credential`, 179) | Note |
|---|---|---|---|
| Definer | `SECURITY DEFINER` | `SECURITY DEFINER` | same |
| `search_path` | `SET search_path = public, pg_temp` | `SET search_path = public, pg_temp` | same (`cq-pg-security-definer-search-path-pin-pg-temp`) |
| Language | `sql` | `sql` | body is a data-modifying CTE: `WITH d AS (DELETE FROM public.api_keys WHERE user_id = p_user_id AND provider = 'anthropic_oauth' RETURNING 1) SELECT EXISTS (SELECT 1 FROM d)` |
| Provider | hardcoded `'anthropic_oauth'` | hardcoded `'anthropic_oauth'` | never a parameter |
| Return | `void` | `boolean` (row existed) | lets the route report `deleted` without a second read |
| Grants | `REVOKE … FROM PUBLIC; … FROM authenticated; … FROM anon; GRANT … TO service_role` (4 statements) | identical four statements, new signature `(uuid)` | copy the block verbatim |
| Comment | `COMMENT ON FUNCTION` naming the route fence | `COMMENT ON FUNCTION` stating there is deliberately NO operator fence on erase | documents the F6 ruling at the DB layer |
| Down | `DROP FUNCTION IF EXISTS … (uuid, text, text, text)` first (then constraint work) | `DROP FUNCTION IF EXISTS public.delete_oauth_credential(uuid)` only | no schema change to reverse |

No test enumerates `SECURITY DEFINER` functions by name (`git grep store_oauth_credential` outside the migration hits only the route, its two tests and ADR-048), so no snapshot needs updating; still run the migration/grants guard tests in Phase 1.

### D. Docs

- ADR-308: replace the "Open follow-ups" bullet with an `## Amendment — 2026-10-30` recording both resolutions (explicit hard delete via RPC, no operator fence, no cross-host
  eviction; derived blocked state, Reconnect with rebind, user-scoped frame).
- ADR-048 `## Addendum — 2026-10-30 (#11524)`: removal is the user's explicit act through `delete_oauth_credential` (RPC-only write boundary kept); the documented no-oauth-row
  fallback to the `anthropic` row is what makes the dialog's billing sentence true; removing the owner's token returns delegated leases to the owner's API key (baseline
  pre-oauth delegation behavior, CTO H5).

## Technical Considerations

- **Architecture impact:** none structural. One new method on an existing route backed by one new RPC beside the existing one, one new client-only state, no new store, queue,
  edge or substrate. Teardown stays (pinned since #4642; it prevents a reconnect storm).
- **Security:** DELETE is CSRF-checked, session-authenticated, user-scoped by construction (`p_user_id` from the verified header, provider hardcoded inside the RPC). Attack surface
  enumeration for the write: (1) wrong-user delete — impossible, id never from input; (2) wrong-row delete — the RPC body names the provider, the route body must be exactly
  `oauth_token`, a test proves the `anthropic` row is untouched; (3) CSRF — `validateOrigin`; (4) value leakage — logs/breadcrumbs/Sentry carry no value and no body;
  (5) unauthenticated — 401; (6) double submit — idempotent 200; (7) direct client RPC call — EXECUTE revoked from `PUBLIC`/`authenticated`/`anon`.
- **Warm sessions (F8/G6):** a warm Query built with the removed token keeps it until its next cold start; the confirm copy says so, the lease fallback is unchanged,
  deferral #11596. A token the user suspects is exposed must be revoked at the provider (the copy says so).
- **Billing-basis explicitness (P2, P3):** the route never writes an `anthropic` row; the dialog names the consequence from props.
- **NFR:** no new availability/latency surface; one extra single-row `maybeSingle` read on the Settings page and one RPC call on DELETE.
- **Type-widening sweep (`hr-type-widening-cross-consumer-grep`, `cq-union-widening-grep-three-patterns`):** `UseWebSocketReturn` gains `credentialBlocked`,
  `rebindConversationId`, `rebindRefused` and `sendMessage: … => boolean`; sole consumer is `chat-surface.tsx` (the `useWebSocket(` call); the compile gate `test/mocks/use-websocket.ts`
  (`satisfies WebSocketState`) is updated. `ChatMessage.unanswered`, `ErrorCard.newTab` and `ChatInput.onSend` are additive/optional. `WSErrorCode` is NOT widened
  (`byok_key_missing` is already in `lib/types.ts` and `ws-zod-schemas.ts`).
- **`api_keys` write-site census (`hr-write-boundary-sentinel-sweep-all-write-sites`):** `git grep -n 'from("api_keys")'` → `app/api/keys/route.ts` (POST upsert + `store_oauth_credential`
  RPC; NEW `delete_oauth_credential` RPC), `app/api/services/route.ts` (DELETE, provider-allowlisted; unchanged), `server/*` (reads). No sentinel test enumerates these write sites;
  none is added because the new write site is an RPC with the provider hardcoded, and a behavior test asserts the route passes only `p_user_id`.

## Implementation Phases

Per `cq-write-failing-tests-before`, each phase starts with its RED tests and ends GREEN (no branch-long dead-red).

### Phase 1 — Server: migration, RPC, DELETE route

RED: `test/api-keys-delete.test.ts` (new; harness copied from `api-keys-oauth-gate.test.ts`: `vi.hoisted`, service-client mock with `rpc`), lease test in
`test/byok-lease-credential-type.test.ts` (delegated lease, no oauth row, owner API key → `scheme: "api_key"`; first confirm no equivalent exists).
GREEN: migration 179 + down, `app/api/keys/route.ts` DELETE.

### Phase 2 — Settings UI

RED: `test/credential-basis.test.ts` (2×2 of enabled × `is_valid` × `hasApiKey`), `test/remove-subscription-token-dialog.test.tsx`, additions to `test/settings-page.test.tsx`
(SettingsContent props, KeyRotationForm integration) and a server-page test with a service-client chain mock exposing `maybeSingle`.
GREEN: `server/cc-oauth-flag.ts` (+ `byok-lease.ts` import), `settings/page.tsx`, `settings-content.tsx`, `lib/credential-basis.ts`, `remove-subscription-token-dialog.tsx`, `key-rotation-form.tsx`.
Note: `settings-content-workspace-identity.test.tsx` mocks `key-rotation-form`, so the new child is covered by that mock.

### Phase 3 — Hook

RED: extend `test/ws-client-key-invalid-teardown.test.tsx` (same `MockWebSocket` harness): blocked derivation, refusal, rebind capture + fallback, supersede precedence, byok_key_missing → blocked,
rebind `session_started` leaves `messages` unchanged (reducer-level, exactly one `user-` bubble, no `filter_prepend`).
GREEN: `lib/ws-client.ts` (+ reducer action), `lib/chat-state-machine.ts` (field), `test/mocks/use-websocket.ts`.

### Phase 4 — Chat surface

RED: `test/chat-surface-credential-blocked.test.tsx` (new), flips in `test/error-states.test.tsx`, additions in `test/chat-input.test.tsx`.
GREEN: `chat-input.tsx`, `error-card.tsx`, `chat-surface.tsx`, `message-bubble.tsx`.

### Phase 5 — Docs and verification

ADR-308 amendment, ADR-048 addendum; run the scoped vitest set, `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, `bash apps/web-platform/scripts/check-button-primitive-sweep.sh`,
`bash plugins/soleur/test/c4-count-parity.test.sh`, the migration/grants guard tests; browser QA via `soleur:qa`.

## Files to Edit

- `apps/web-platform/app/api/keys/route.ts`
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- `apps/web-platform/components/settings/settings-content.tsx`
- `apps/web-platform/components/settings/key-rotation-form.tsx`
- `apps/web-platform/server/byok-lease.ts` (import `isCcOauthEnabled` from the new shared module; behavior unchanged)
- `apps/web-platform/lib/ws-client.ts`
- `apps/web-platform/lib/chat-state-machine.ts`
- `apps/web-platform/components/chat/chat-surface.tsx`
- `apps/web-platform/components/chat/chat-input.tsx`
- `apps/web-platform/components/chat/message-bubble.tsx`
- `apps/web-platform/components/ui/error-card.tsx`
- `apps/web-platform/test/mocks/use-websocket.ts`
- `apps/web-platform/test/ws-client-key-invalid-teardown.test.tsx`
- `apps/web-platform/test/error-states.test.tsx`
- `apps/web-platform/test/chat-input.test.tsx`
- `apps/web-platform/test/settings-page.test.tsx`
- `apps/web-platform/test/byok-lease-credential-type.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-308-server-authored-cli-auth-failure-copy-and-permanent-matcher.md`
- `knowledge-base/engineering/architecture/decisions/ADR-048-operator-cc-oauth-credential-selection-by-consumer-class.md`

## Files to Create

- `apps/web-platform/supabase/migrations/179_delete_oauth_credential.sql` and `179_delete_oauth_credential.down.sql`
- `apps/web-platform/server/cc-oauth-flag.ts`
- `apps/web-platform/components/settings/remove-subscription-token-dialog.tsx`
- `apps/web-platform/lib/credential-basis.ts`
- `apps/web-platform/test/api-keys-delete.test.ts`
- `apps/web-platform/test/chat-surface-credential-blocked.test.tsx`
- `apps/web-platform/test/remove-subscription-token-dialog.test.tsx`
- `apps/web-platform/test/credential-basis.test.ts`
- `knowledge-base/product/design/settings/subscription-token-removal-and-key-invalid-chat.pen` (+ `screenshots/08-…` to `14-…`; already on disk)
- `knowledge-base/project/specs/feat-one-shot-11524-11525-oauth-remove-key-invalid-chat/tasks.md`, `decision-challenges.md`

Glob verification: every path above resolves under `git ls-files` or is created by this PR; `components/**/*.tsx` matches the UI-surface glob (Product/UX gate ran at BLOCKING).

## Open Code-Review Overlap

2 open scope-outs touch `apps/web-platform/lib/ws-client.ts`:

- **#3374** (emit `slot_reclaimed` WS frame): **Acknowledge.** Different concern (server frame for ledger-divergence recovery); remains open.
- **#3280** (refactor `useWebSocket` history-fetch into a reducer-driven state machine): **Acknowledge.** This PR adds blocked/rebind state around, not inside, the history-fetch effects; folding the refactor in would triple the diff. Remains open.

No open code-review issue names any other file in the lists above.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled F1-F9, G1-G8 and (after a 4-agent plan review contradicted three premises with code evidence) H1-H7, all in `specs/<branch>/decision-challenges.md`. Keep teardown, derived blocked state, explicit Reconnect with rebind (server answers `session_started`; one-shot `start_session` fallback), `send()` boolean, user-scoped frame, no `errorOccurrence`, DELETE through a service-role RPC with no operator fence and hard delete, log-only audit, no cross-host eviction, explicit billing confirm with an in-effect-aware third variant, client-only `byok_key_missing`, `newTab` derived in the surface.

### Legal

**Status:** reviewed
**Assessment:** CLO: no legal blocker. Conditions folded in: hard DELETE scoped to the caller's own `anthropic_oauth` row; no token value in log/breadcrumb/Sentry; confirm copy must not say Soleur revokes the token at Anthropic or advertise subscription billing; honest "applies from your next conversation start" (no legal document promises immediate credential revocation); no policy-document edit required; optional note in `article-30-register.md` PA-1(f) left out of scope. Backups/PITR retain ciphertext until roll-off (existing generic caveat; do not promise "permanently").

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

CPO: threshold single-user incident, plan-time sign-off granted, conditional on the wireframe existing (done), the copy fixes (applied: one noun per surface, concrete billing line, "Keep token"/"Remove token", default focus on Keep, "Add an API key first" path, visible helper text plus `aria-live`, "Not answered" marker, status line naming the billing basis) and `soleur:engineering:review:user-impact-reviewer` at review. Deferred one-click Resend acceptable (tracked #11595). Spec-flow gaps resolved: remount resets (G1), `ChatInput` boolean contract (G3), `byok_key_missing` handled client-side (G4), session rebind on Reconnect (G2/H3), new-tab Settings link (G1/H7), orphan bubble flag (G5), hint folded into the helper line (G8 superseded), supersede precedence (G7), Remove-flow pending/error/focus/announce states (copy table), stale `hasApiKey` sentence handled by the confirm-time props. Wireframe open question (dismissed card has no Reconnect) resolved by the inline helper-line Reconnect Button. Plan-review taste items (cut the hint / `unanswered` flag / `Conversations use:` line / `Add an API key first`) are recorded as challenges in `decision-challenges.md`; the plan keeps the CPO-conditioned scope. Brainstorm-recommended specialists: none (no brainstorm). Content Review Gate: no domain leader recommended a copywriter; CPO copy fixes applied directly.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Remove control deleting or failing to delete the wrong thing (an operator left with no sign-in and a chat that errors, or a token that appears removed but still bills the subscription), or a composer that looks live while a typed message vanishes with no reply.
- **If this leaks, the user's money / workflow is exposed via:** a DELETE that reaches the `anthropic` API-key row (the user's only fallback) or another user's row, or a log/Sentry line carrying the token value or request body; neither is introduced because the user id and provider are never read from input (the RPC hardcodes the provider, EXECUTE is service-role only) and logs carry only `op`/`deleted`.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one account's money (billing basis) and ability to chat is affected by a single mistake, so the per-PR CPO sign-off and `user-impact-reviewer` apply; today's exposure is operator accounts only, which is why it is not `aggregate pattern`.

## Observability

```yaml
liveness_signal:
  what: pino info line op "oauth-credential-removed" (field deleted) emitted once per successful DELETE /api/keys; per-request, no heartbeat needed
  cadence: per-request
  alert_target: Better Stack logs (existing web-platform log drain); an RPC failure raises a Sentry issue
  configured_in: apps/web-platform/app/api/keys/route.ts
error_reporting:
  destination: Sentry via Sentry.captureException in the route (existing api-keys pattern), tags feature api-keys op delete-oauth
  fail_loud: HTTP 500 {"error":"Failed to remove token"} plus the Sentry event; a client send refused on a non-open, non-blocked socket mirrors to Sentry (feature send-message, op refused-socket-not-open)
failure_modes:
  - mode: the RPC errors (or the migration is missing) and the token is not removed
    detection: Sentry event tagged feature api-keys op delete-oauth; the route fails closed with 500, never a direct table delete
    alert_route: Sentry issue alert (existing project rules)
  - mode: removal succeeds but a warm Query keeps billing the subscription until it ends
    detection: documented limitation; a user report "old billing basis after removal" re-triggers #11596 (no automatic detector exists for a per-process Query env)
    alert_route: GitHub issue #11596 re-evaluation criteria
  - mode: client refuses sends silently because the blocked state never clears
    detection: blocked state is derived from lastError and cleared by reconnect and mount; vitest asserts the clear paths; send refusal outside the blocked state mirrors to Sentry
    alert_route: Sentry issue feature send-message
logs:
  where: Better Stack (pino stdout drain) for the audit line; Sentry for errors
  retention: per the existing Better Stack and Sentry retention plans (no new store)
discoverability_test:
  command: grep -o oauth-credential-removed apps/web-platform/app/api/keys/route.ts
  expected_output: oauth-credential-removed
```

## Encryption Posture

Not applicable: the only migration adds a `SECURITY DEFINER` function (no table, no column, no store) and there is no new cross-component connection; the function operates on the existing `api_keys` rows under their existing AES-GCM at-rest posture (ADR-004) and the existing TLS posture of the service-role client. The detection regex matches the `supabase/migrations/*.sql` path, so this paragraph records why the `at_rest`/`in_transit` schema has nothing to describe.

## Architecture Decision (ADR/C4)

### ADR

No new ordinal. The change extends two existing decisions, so both are amended in this PR (task in Phase 5): ADR-308 `## Amendment — 2026-10-30` replaces the "Open follow-ups" bullet (#11524 resolved by explicit hard delete through an RPC with no operator fence and no cross-host eviction; #11525 resolved by derived blocked state, Reconnect with rebind, user-scoped frame) and ADR-048 `## Addendum — 2026-10-30 (#11524)` (removal through `delete_oauth_credential`; the documented no-oauth-row fallback makes the dialog's billing sentence true; delegated leases return to the owner's API key). Both record the CTO ruling rationale in one line each.

### C4 views

No C4 change. Read in full: `knowledge-base/engineering/architecture/diagrams/spec.c4`, `views.c4`, `model.c4` (element census plus keyword greps). Checked and already modeled: (a) external human actor — `founder` ("Founder / Operator") is the only actor and is unchanged; (b) external system — `anthropic` (LLM calls with BYOK keys) and `sentry` are unchanged, no new vendor; (c) container/data store — the Supabase PostgreSQL element ("BYOK-encrypted API keys") is the store, already modeled; (d) actor-surface access — no new relationship (the operator already writes this row via POST). Derived-cardinality gate: `bash plugins/soleur/test/c4-count-parity.test.sh` returns `ALL TESTS PASSED` before the change and is re-run in Phase 5.

### Sequencing

The ADR text describes the shipped state; nothing is soak-gated.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "let the owner remove a stored subscription token (anthropic_oauth) without replacing it" [brief, issue #11524] | Proposed Solution A, Phase 1-2 | mapped |
| 2 | "new DELETE write surface (route, Settings UI affordance in components/settings/key-rotation-form.tsx, audit)" [brief] | A (route + RPC + audit), B (dialog rendered by `key-rotation-form.tsx`) | mapped |
| 3 | "billing-basis decision (subscription to API key) stays explicit, not automatic" [brief] | B copy table, route never writes `anthropic`, RPC cannot touch it | mapped |
| 4 | "composer state" [brief, issue #11525] | C `credentialBlocked`, disabled composer, helper line | mapped |
| 5 | "fixing the credential mid-conversation (saved/resend hint, no silently dropped optimistic message)" [brief] | C Reconnect + rebind, hint, `send()` boolean, `ChatInput` contract, `Not answered` flag | mapped |
| 6 | "multi-tab behavior (error frame is user-scoped; lastError card lifecycle on repeated failure)" [brief] | C user-scoped decision + tests (G7), lifecycle test (H1) | mapped |
| 7 | "Touches lib/ws-client.ts and components/chat/chat-surface.tsx" [brief] | Files to Edit | mapped |
| 8 | "Read both issue bodies for full context and re-evaluation criteria" [brief] | Research Reconciliation, deferral issues #11595-#11597 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| DELETE route, hard delete, no operator fence | "new DELETE write surface (route, … audit)" | asked |
| `delete_oauth_credential` RPC + migration 179 | "new DELETE write surface (route, … audit)" | inferred — justification: ADR-048's RPC-only write boundary for `anthropic_oauth`; an app-level delete could destroy the `anthropic` fallback key (CTO H4) |
| Settings dialog | "Settings UI affordance in components/settings/key-rotation-form.tsx" | asked |
| Second Settings query, `hasOauthToken`/`oauthInEffect`, shared `cc-oauth-flag.ts`, variant C | — | inferred — justification: the control must be discoverable and honest for an inert stored row; the page must not drift from the lease predicate (CTO H6) |
| `Conversations use: …` status line and `credential-basis.ts` | — | inferred — justification: CPO requires the billing basis be verifiable before the confirm (challenged in decision-challenges.md; kept) |
| `send()` boolean, `ChatInput` contract | "no silently dropped optimistic message" | asked |
| Derived blocked state + disabled composer | "composer state" | asked |
| Reconnect button + session rebind + fallback | "fixing the credential mid-conversation (saved/resend hint …)" | asked |
| Helper line carries the "saved" wording (no separate hint) | "saved/resend hint" | asked |
| Lifecycle test (dismiss → Reconnect → repeat) | "lastError card lifecycle on repeated failure" | asked |
| New-tab Settings link | — | inferred — justification: the hint and blocked UI are unreachable if the same-tab link unmounts the chat (spec-flow P2, CTO G1/H7) |
| `byok_key_missing` client branch | "billing-basis decision (subscription to API key) stays explicit" | inferred — justification: removing the token of an API-key-less account makes this the immediate next state, which today renders as a generic bubble (CTO G4/H2) |
| `Not answered` bubble flag | "no silently dropped optimistic message" | inferred — justification: the orphan bubble is the one message the user actually loses (CPO; challenged, kept) |
| ADR-308/048 amendments | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; ADR-308 names both issues as open follow-ups |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 29 | Estimated changed lines: ~600 source + ~600 test
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one app root; both issues are the same #11086 follow-up family and the operator asked for one PR. The file count includes 6 new/updated tests, 3 doc edits (2 ADRs + tasks) and 7 design artifacts already on disk; production files are 17.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Migration 179 defines `delete_oauth_credential(p_user_id uuid) RETURNS boolean` as `SECURITY DEFINER` with `search_path = public, pg_temp`, deleting only `provider='anthropic_oauth'` for `p_user_id`, EXECUTE revoked from `PUBLIC`/`authenticated`/`anon` and granted to `service_role`; a `.down.sql` drops it; the migration/grants guard tests pass.
- [ ] `DELETE /api/keys` with `{credential_type:"oauth_token"}` calls the RPC with ONLY `p_user_id` (the verified id), returns 200 `{deleted}`; absent row → `deleted:false`; any other body (missing, `{}`, `{credential_type:"api_key"}`, `{provider:"anthropic"}`, non-JSON) → 400 and the RPC is NOT called; 401 unauthenticated; `rejectCsrf` on bad origin; works for a non-operator and with `CC_OAUTH_ENABLED` unset; RPC error → 500 + `Sentry.captureException` and NO direct `from("api_keys").delete()` call (`test/api-keys-delete.test.ts`).
- [ ] Logger/Sentry mocks never receive the request body or any token-shaped string (`test/api-keys-delete.test.ts`).
- [ ] Settings shows `Subscription token: saved <date>` and the correct `Conversations use: …` line for the (enabled × `is_valid` × `hasApiKey`) matrix whenever a row exists, independent of `canUseOauthCredential`; no line when none; `isCcOauthEnabled` is imported from `server/cc-oauth-flag.ts` by both the page and `byok-lease.ts` (`test/credential-basis.test.ts`, `test/settings-page.test.tsx`).
- [ ] Remove dialog: variants A, B, C with the exact copy, default focus on `Keep token`, both buttons disabled while pending, error alert for non-OK and network failure, `Add an API key first` (variant B only) focuses `#api-key-input` and selects the API-key radio, success notice chosen from the confirmed props (`test/remove-subscription-token-dialog.test.tsx`).
- [ ] A delegated lease with no oauth row and an owner `anthropic` key resolves `scheme: "api_key"` (`test/byok-lease-credential-type.test.ts`).
- [ ] After a `key_invalid` or `byok_key_missing` frame: `credentialBlocked` is true; composer disabled with the scheme-specific placeholder; helper line + inline Reconnect visible even with the card dismissed; the last user message shows `Not answered`; `sendMessage` returns `false` and dispatches no `add_message`/`reset_connection` and no `chat` frame (with the `MockWebSocket` whose `readyState` stays OPEN) (`test/ws-client-key-invalid-teardown.test.tsx`, `test/chat-surface-credential-blocked.test.tsx`).
- [ ] `byok_key_missing` frame → "API Key Required" card, blocked state, NO generic "Error: …" assistant bubble (client test).
- [ ] `ChatInput` keeps draft and staged attachments when `onSend` returns `false` (attachment prune only when `sent`); `handleSubmit` does nothing (no upload) when `disabled`; a `void`-returning `onSend` still clears (`test/chat-input.test.tsx`). `handleSend` returns `false` before `onBeforeSend` when blocked/not connected.
- [ ] Reconnect from the blocked card re-binds: `setSessionStarted(false)` + `reconnect()`, then exactly one `resume_session` for the captured id (never `start_session` when an id was captured; `start_session` when none), exactly one `chat` frame in total after the user re-sends, blocked state cleared; a rebind `session_started` leaves `messages` unchanged (exactly one `user-` bubble, no `filter_prepend`, no history refetch); a refused rebind (`error` frame while armed) triggers exactly ONE `start_session` and no extra error bubble (`test/ws-client-key-invalid-teardown.test.tsx`, `test/chat-surface-credential-blocked.test.tsx`).
- [ ] Lifecycle: dismiss → Reconnect → second `key_invalid` re-shows the card; dismissing leaves the composer disabled; mutation: deleting the null-reset effect makes the test red; the existing "dismiss then re-fire after null" test stays green (`test/error-states.test.tsx`).
- [ ] Helper line shows the scheme-specific "Saved your token/key in Settings? Select Reconnect to continue." copy while blocked, including after the card is dismissed; no `visibilitychange` or `focus` listener is installed (`test/chat-surface-credential-blocked.test.tsx`).
- [ ] Supersede precedence: a 4002 close on the torn-down socket after `key_invalid` is a no-op (`lastError.code` stays `key_invalid`); a 4002 after Reconnect yields `lastError.code === "disconnected"` with `credentialBlocked === false` (`test/ws-client-key-invalid-teardown.test.tsx`).
- [ ] `ErrorCard` with `newTab` renders `<a target="_blank" rel="noopener noreferrer">` for the three blocked cards and `NavLink` otherwise; the two existing assertions that `Reconnect` is absent for `key_invalid` (`test/error-states.test.tsx`: "reconnect button not shown for key_invalid errors" and the oauth title test) are updated to the new contract (absence was a proxy for "no AUTO reconnect", asserted separately: `socket.onclose` stays null and no second `MockWebSocket` is constructed without a Reconnect click).
- [ ] `ws-client-key-invalid-teardown.test.tsx` existing cases and `ws-client-key-invalid-source-gate.test.ts` stay green in intent (the `lastError` `toEqual` shapes are unchanged: no field added to `lastError` or `lastError.action`; the branch still ends in `teardown();` and contains no `location.href`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (mock `satisfies` gate updated); `bash apps/web-platform/scripts/check-button-primitive-sweep.sh` passes with no new native `<button>`; `bash plugins/soleur/test/c4-count-parity.test.sh` passes.
- [ ] ADR-308 amendment and ADR-048 addendum committed; `decision-challenges.md` committed; `.pen` + screenshots committed (CPO condition; `wg-ui-feature-requires-pen-wireframe`).
- [ ] PR body: `Closes #11524`, `Closes #11525` (body, not title), `Ref #11086 #11595 #11596 #11597`; CPO sign-off recorded; `soleur:engineering:review:user-impact-reviewer` run at review.

### Post-merge (operator)

None. The release workflow applies migration 179 (migrate + verify-migrations precede deploy); if migration ordering ever fails to hold, the route fails closed with a 500 + Sentry event, never a direct delete.

## Test Scenarios

Layer labels: `unit` (vitest, jsdom/happy-dom), `integration` (route handler against mocked service client), `integration-db` (migration, only if the repo's migration test harness already runs SQL in CI — otherwise the migration is covered by the guard tests and a post-merge verification query is NOT required). No `e2e` (no Playwright spec touches these surfaces today; pyramid-justified: fully observable at unit/integration level, with the full-stack path covered by the QA pass below).

- Given an operator row exists, when DELETE `{credential_type:"oauth_token"}`, then `rpc("delete_oauth_credential", { p_user_id: U })` is the only service-client call and the response is `{deleted:true}` [integration].
- Given no row (RPC returns false), then `{deleted:false}` 200 [integration]. Given body `{}`/`{credential_type:"api_key"}`/`{provider:"anthropic"}`/non-JSON, then 400 and no RPC call [integration, property: for every body other than the exact one, the RPC is never called].
- Given a non-operator with `CC_OAUTH_ENABLED` unset, when DELETE, then NOT 403 [integration] (inverse of the POST fence, deliberate).
- Given the RPC errors, then 500, `Sentry.captureException` once, no `from()` call, and no token-shaped string anywhere in mock call args [integration].
- Given hasApiKey × enabled × `is_valid`, then `describeCredentialBasis` returns the expected strings [unit]; the dialog renders variant A/B/C accordingly [unit]. Given DELETE 200, then the parent notice matches the variant and focus lands as specified [unit]. Given a non-OK response / network failure, then the matching alert and buttons re-enabled [unit].
- Given `key_invalid` (oauth scheme) after one user message, then `credentialBlocked`, `rebindConversationId === realId`, last user message `unanswered`, `socket.onclose === null` [unit].
- Given blocked, when `sendMessage("x")`, then returns `false`, `messages` unchanged, `socket.send` not called with a chat frame [unit]. Given NOT blocked but `readyState` CLOSED, then returns `false` and a Sentry mirror fires [unit].
- Given blocked then Reconnect, then `resume_session` for the captured id; given the server replies `session_started`, then `messages` unchanged; given it replies `error` while armed, then exactly one `start_session` [unit, regression: "No active session"].
- Given dismiss → Reconnect → second `key_invalid`, then the card is visible again [unit].
- Given `byok_key_missing`, then the "API Key Required" card, composer disabled, no generic assistant bubble [unit].
- Given ChatInput `onSend → false` with staged attachments, then draft and attachments remain [unit].
- Mutation checks (so each new guard can be driven RED): remove the blocked check in `sendMessage` → refusal test fails; remove `setSessionStarted(false)` from the handler → rebind test fails; point the RPC call's argument at a body-supplied id → the "only `p_user_id`" assertion fails; delete the null-reset effect → lifecycle test fails.

**QA (browser, `soleur:qa`, deterministic):** Settings as an operator fixture with an `anthropic_oauth` row: click Remove → confirm A → status lines flip and focus lands as specified; repeat with no API key → variant B; with the kill-switch off → variant C; chat: inject a `key_invalid` frame through the existing WS injector (`e2e/cc-soleur-go-ws-injector.ts`) and verify composer disabled, Reconnect (one `resume_session`, no duplicated bubble against real persistence), new-tab link, hint on tab return, and 390px width has no clipped helper/placeholder text (real-browser bounding-box check for the new Buttons).

## Success Metrics

- Zero reports of "message disappeared after the sign-in card" (the #11525 re-evaluation trigger).
- An operator with a dead token can reach a working chat on their API key in Settings alone (the #11524 trigger).
- `oauth-credential-removed` lines appear with `deleted:true` only for rows that existed.

## Dependencies & Risks

- **Risk — Reconnect rebind semantics (highest).** The rebind id is the pending id from `session_started`; in the two-tab `context_path` race `createConversation` can resolve a different id, and `resume_session` answers "Conversation not found" (also on a repo mismatch). Mitigation: one-shot `start_session` fallback (H3); capture only when ≥1 user message was sent; tests for both branches; QA path.
- **Risk — duplicate bubble if the server reply type ever becomes `session_resumed`.** `filter_prepend` dedupes by id only and optimistic ids are `user-<uuid>`. Mitigation: the reducer-level test pins `session_started` handling.
- **Risk — happy-dom `MockWebSocket` hides closure.** `close()` does not change `readyState`; tests assert the blocked path, not just `readyState`.
- **Risk — migration ordering.** The route needs the RPC; the release workflow migrates before deploy. If it ever does not, the route fails closed (500 + Sentry).
- **Risk — copy drift between `.pen`, this plan and tests.** The copy tables are the single contract; tests assert literals.
- **Risk — existing tests pinning absence of Reconnect.** Updated explicitly (see Acceptance Criteria); the stronger invariant (no auto-reconnect) is asserted.
- **Dependency:** none external. The `.pen` is on disk (intent-to-add); commit with the plan.

## Deferrals (tracking issues)

- #11595 — one-click Resend after a key_invalid reconnect (re-eval: user reports retyping, or an id-keyed resend lands).
- #11596 — evict warm Queries on token removal via a per-user credential epoch (re-eval: "old billing basis after removal").
- #11597 — cross-tab credential-fixed signal (re-eval: blocked tab stays blocked after a valid save).
- Unverified, no issue yet: the `byok_key_missing` copy for a workspace MEMBER whose key owner has no key reads "Add an API key in Settings" (CTO G4 note). File if a team user reports it.

## GDPR / Compliance

`soleur:gdpr-gate` ran at plan time (advisory; trigger: `app/api/keys/route.ts` and a new `.sql` migration match the canonical regex). Disclaimer carried: this is not legal review,
findings are heuristic; CLO review is recorded under `## Domain Review` (Legal).

| check_id | Result |
|---|---|
| GDPR-Art-9 | No new column, no special-category data. No Critical finding; no `compliance-posture.md` write and no `compliance/critical` issue. |
| GDPR-Art-6 / Art-5e | No new schema column or table (the migration adds a function only), so no `LAWFUL_BASIS` annotation or retention metadata is needed. |
| GDPR-Art-17 / Art-17-caller | Positive: the change adds a self-service erase of the caller's own stored credential (hard delete). No new FK, no `anonymise_*` RPC. Backups/PITR retain ciphertext until roll-off (existing generic caveat). |
| GDPR-Chapter-V | No new vendor, SDK or env var; the audit line goes to the already-registered Better Stack and Sentry. |
| Suggestion | The audit line carries a pseudonymised `userId` only (ADR-029 formatter) and never the token value or request body; asserted by a test (Acceptance Criteria). |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan declares `single-user incident` and `requires_cpo_signoff: true`.
- Do not add a field to `lastError` or `lastError.action`: the existing `toEqual` assertions in `ws-client-key-invalid-teardown.test.tsx` break and the source-gate slice sees extra branch text. Presentation choices (new tab, labels) derive from `lastError.code` in the surface.
- The source-gate test slices `lib/ws-client.ts` from `msg.errorCode === "key_invalid"` to the FIRST `teardown();` after it: do not add a `teardown();` earlier in that branch, and keep new bookkeeping free of `location.href`.
- `credentialBlocked` must stay derived; the ref mirror is assigned synchronously where `lastError` is set/cleared, never in an effect.
- DELETE must not be gated on the operator fence or `CC_OAUTH_ENABLED`; copying the POST preamble verbatim is the likely mistake. It must also never fall back to a direct `from("api_keys").delete()` when the RPC errors.
- The route must not echo or log the request body. A `logger.info({ body })` convenience line would put user-controlled JSON in the log.
- `sendMessage` refusal must happen before `dispatch({ type: "reset_connection" })` — resetting the sticky unrecoverable state for a refused send would be a silent state change.
- The rebind relies on the server answering `resume_session` with `session_started`; if that ever changes to `session_resumed` the history refetch re-arms and duplicates the optimistic bubble.
- A new `Button` must be the primitive (`components/ui/button`); a native `<button>` raises the sweep baseline and fails `check-button-primitive-sweep.sh`.
- The `.pen` screenshots under `design/settings/screenshots/` are committed (existing convention); do not commit stray hash-named exports.
