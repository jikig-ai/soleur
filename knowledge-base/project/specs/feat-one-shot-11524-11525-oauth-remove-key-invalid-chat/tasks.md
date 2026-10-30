# Tasks: remove a stored subscription token + chat state after a key_invalid card

Plan: `knowledge-base/project/plans/2026-10-30-feat-remove-subscription-token-and-key-invalid-chat-state-plan.md`
Closes #11524, Closes #11525. Rulings: `decision-challenges.md` (same directory). All paths under `apps/web-platform/` unless noted.

## Phase 1: Server — migration, RPC, DELETE route

- 1.1 RED: `test/api-keys-delete.test.ts` (harness from `test/api-keys-oauth-gate.test.ts`; service client mock exposes `rpc`).
  - 1.1.1 exact-body gate: only `{credential_type:"oauth_token"}` reaches the RPC; `{}`, `{credential_type:"api_key"}`, `{provider:"anthropic"}`, non-JSON -> 400.
  - 1.1.2 RPC called with ONLY `p_user_id` (verified id); 200 `{deleted}`; absent row -> `deleted:false`.
  - 1.1.3 401 / `rejectCsrf`; non-operator and `CC_OAUTH_ENABLED` unset are NOT 403.
  - 1.1.4 RPC error -> 500 + `Sentry.captureException`, no direct `from()` delete; no body/token-shaped string in any logger/Sentry mock arg.
- 1.2 RED: delegated-lease test in `test/byok-lease-credential-type.test.ts` (confirm no equivalent exists first).
- 1.3 GREEN: `supabase/migrations/179_delete_oauth_credential.sql` + `.down.sql` (recheck the free ordinal on `origin/main`; mirror migration 096's REVOKE/GRANT block; `search_path = public, pg_temp`).
- 1.4 GREEN: `DELETE` in `app/api/keys/route.ts` (validateOrigin -> verifiedUserId -> exact body -> RPC -> `logger.info` op `oauth-credential-removed` + breadcrumb).
- 1.5 Run migration/grants guard tests and `.sql` lint.

## Phase 2: Settings UI

- 2.1 RED: `test/credential-basis.test.ts`, `test/remove-subscription-token-dialog.test.tsx`, additions to `test/settings-page.test.tsx` (+ server-page test with a `maybeSingle` chain mock).
- 2.2 GREEN: `server/cc-oauth-flag.ts` (`isCcOauthEnabled`), import it in `server/byok-lease.ts` (behavior unchanged) and the settings page.
- 2.3 GREEN: `app/(dashboard)/dashboard/settings/page.tsx` — oauth query `provider, is_valid, updated_at`; props `hasOauthToken`, `oauthInEffect`, `oauthTokenSavedAt`.
- 2.4 GREEN: `components/settings/settings-content.tsx` — thread props to `KeyRotationForm`; status lines via `lib/credential-basis.ts`.
- 2.5 GREEN: `components/settings/remove-subscription-token-dialog.tsx` (variants A/B/C, `Button` primitives, `usePendingAction`).
- 2.6 GREEN: `components/settings/key-rotation-form.tsx` — render dialog after the form when `hasOauthToken`; own the post-removal notice, `onAddApiKey`, focus.

## Phase 3: Hook (`lib/ws-client.ts`)

- 3.1 RED: extend `test/ws-client-key-invalid-teardown.test.tsx` — blocked derivation, `sendMessage` refusal (MockWebSocket `readyState` stays OPEN), rebind capture + armed-ref fallback (exactly one `start_session`), `session_started` after rebind leaves `messages` unchanged, supersede precedence, `byok_key_missing` -> blocked.
- 3.2 GREEN: `send()` returns boolean; `sendMessage` returns boolean and refuses BEFORE `reset_connection`/`add_message`; non-blocked refusal mirrors to Sentry.
- 3.3 GREEN: shared key_invalid/byok_key_missing handler (bookkeeping before the first `teardown();`, no `location.href`, no field added to `lastError`/`action`); ref set synchronously (also in `reconnect()`).
- 3.4 GREEN: `rebindConversationId` + armed ref + one-shot `startSession` fallback; reducer action `mark_last_user_unanswered` (reducer lives in `ws-client.ts`); `ChatMessage.unanswered` in `lib/chat-state-machine.ts`.
- 3.5 GREEN: `test/mocks/use-websocket.ts` (`credentialBlocked: false`, `rebindConversationId: null`).

## Phase 4: Chat surface

- 4.1 RED: `test/chat-surface-credential-blocked.test.tsx`; flip the two Reconnect-absent assertions in `test/error-states.test.tsx`; add lifecycle test (dismiss -> Reconnect -> repeat shows card); `test/chat-input.test.tsx` additions.
- 4.2 GREEN: `components/chat/chat-input.tsx` — `onSend` returns `boolean | void`; `handleSubmit` restructure (early return when `disabled`; prune attachments only when `sent`; `false` keeps draft and `onAtDismiss` state).
- 4.3 GREEN: `components/ui/error-card.tsx` — `newTab` prop (plain `<a target="_blank" rel="noopener noreferrer">`).
- 4.4 GREEN: `components/chat/chat-surface.tsx` — `handleSend` returns false before `onBeforeSend`; derive `blocked` from `lastError.code`; composer disabled + placeholder + helper line with inline Reconnect; `onCredentialReconnect` (`setSessionStarted(false)` + `reconnect()`); rebind effect (truthy guard); `visibilitychange` hint; `newTab` for blocked codes.
- 4.5 GREEN: `components/chat/message-bubble.tsx` — `Not answered` flag.
- 4.6 Verify no settings-route layout mounts `useWebSocket` (a new tab would supersede the chat socket).

## Phase 5: Docs and verification

- 5.1 ADR-308 `## Amendment — 2026-10-30`; ADR-048 `## Addendum — 2026-10-30 (#11524)` (RPC, fallback, delegated leases).
- 5.2 Run scoped vitest, `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, `bash apps/web-platform/scripts/check-button-primitive-sweep.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 5.3 Browser QA via `soleur:qa` (Settings variants A/B/C; injected key_invalid frame; Reconnect rebind against real persistence; 390px bounding-box check).
- 5.4 PR body: `Closes #11524`, `Closes #11525`, `Ref #11086 #11595 #11596 #11597`; record CPO sign-off; request `user-impact-reviewer` at review.
