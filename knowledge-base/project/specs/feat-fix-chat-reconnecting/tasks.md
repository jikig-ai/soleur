# Tasks: fix chat reconnecting loop

## Phase 1: Core Fix

- [ ] 1.1 Add `NON_TRANSIENT_CLOSE_CODES` constant map to `apps/web-platform/lib/ws-client.ts`
  - [ ] 1.1.1 Define close code routing: `Record<number, { action: "redirect" | "disconnect"; target?: string; reason: string }>`
  - [ ] 1.1.2 Map codes 4001 (redirect /login), 4002 (disconnect), 4003 (redirect /login), 4004 (redirect /accept-terms), 4005 (disconnect)
- [ ] 1.2 Extract `teardown()` helper from existing `key_invalid` pattern (lines 184-192)
  - [ ] 1.2.1 Helper sets `mountedRef.current = false`, clears reconnect timer, nullifies `onclose`, closes socket
  - [ ] 1.2.2 Refactor existing `key_invalid` handler to use `teardown()` (deduplication)
- [ ] 1.3 Update `ws.onclose` handler to accept `CloseEvent` and branch on close codes
  - [ ] 1.3.1 Change handler signature from `() => {}` to `(event: CloseEvent) => {}`
  - [ ] 1.3.2 Look up `event.code` in `NON_TRANSIENT_CLOSE_CODES`
  - [ ] 1.3.3 If found with action `"redirect"`: call `teardown()`, set status to `"disconnected"`, redirect to target
  - [ ] 1.3.4 If found with action `"disconnect"`: call `teardown()`, set status to `"disconnected"` (no redirect)
  - [ ] 1.3.5 Default (no match): preserve existing exponential backoff reconnect behavior

## Phase 2: UI Feedback

- [ ] 2.1 Add `disconnectReason` state to `useWebSocket` hook
  - [ ] 2.1.1 Add `useState<string | undefined>(undefined)` for `disconnectReason`
  - [ ] 2.1.2 Set reason string from `NON_TRANSIENT_CLOSE_CODES` entry in `onclose` handler
  - [ ] 2.1.3 Add `disconnectReason` to `UseWebSocketReturn` interface
  - [ ] 2.1.4 Return `disconnectReason` from the hook
- [ ] 2.2 Update `StatusIndicator` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - [ ] 2.2.1 Accept optional `disconnectReason` prop
  - [ ] 2.2.2 When status is `"disconnected"` and reason is present, display the reason text instead of generic label
  - [ ] 2.2.3 Pass `disconnectReason` from `ChatPage` to `StatusIndicator`

## Phase 3: Testing

- [ ] 3.1 Verify with Playwright: open chat with expired/invalid session token, confirm redirect to `/login` (not reconnect loop)
- [ ] 3.2 Verify with Playwright: open chat without T&C acceptance, confirm redirect to `/accept-terms`
- [ ] 3.3 Verify normal disconnect (network drop, code 1006) still triggers exponential backoff reconnect
- [ ] 3.4 Verify existing `key_invalid` error code redirect to `/setup-key` still works (regression guard)
- [ ] 3.5 Verify concurrent tab scenario: open two tabs, confirm first tab shows "Superseded" reason without reconnect loop
- [ ] 3.6 Verify teardown pattern consistency: confirm `key_invalid` handler and new close code handler both use the same `teardown()` function
