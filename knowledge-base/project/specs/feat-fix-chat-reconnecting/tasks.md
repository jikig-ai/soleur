# Tasks: fix chat reconnecting loop

## Phase 1: Core Fix

- [ ] 1.1 Update `ws.onclose` handler in `apps/web-platform/lib/ws-client.ts` to accept `CloseEvent` and branch on close codes
  - [ ] 1.1.1 Add close code constants map (4001-4005 with their semantic meanings)
  - [ ] 1.1.2 For codes 4001/4003: set `mountedRef.current = false`, clear reconnect timer, redirect to `/login`
  - [ ] 1.1.3 For code 4004: set `mountedRef.current = false`, clear reconnect timer, redirect to `/accept-terms`
  - [ ] 1.1.4 For code 4002: set status to `"disconnected"`, do not schedule reconnect
  - [ ] 1.1.5 For code 4005: set status to `"disconnected"`, do not schedule reconnect
  - [ ] 1.1.6 For all other codes: preserve existing exponential backoff reconnect behavior

## Phase 2: UI Feedback

- [ ] 2.1 Add optional `disconnectReason` to `useWebSocket` return type
  - [ ] 2.1.1 Add `disconnectReason` state (`useState<string | undefined>`)
  - [ ] 2.1.2 Set reason string in each non-transient close code branch
  - [ ] 2.1.3 Return `disconnectReason` from the hook
- [ ] 2.2 Update `StatusIndicator` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - [ ] 2.2.1 Accept `disconnectReason` prop
  - [ ] 2.2.2 When status is `"disconnected"` and reason is present, display the reason text

## Phase 3: Testing

- [ ] 3.1 Manually verify with Playwright: simulate 4001 close and confirm redirect to `/login`
- [ ] 3.2 Manually verify with Playwright: simulate 4004 close and confirm redirect to `/accept-terms`
- [ ] 3.3 Verify normal disconnect (network drop) still triggers exponential backoff reconnect
- [ ] 3.4 Verify existing `key_invalid` error code redirect still works
