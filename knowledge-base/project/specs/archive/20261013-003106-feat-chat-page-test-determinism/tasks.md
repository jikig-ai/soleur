# Tasks: Chat Page Test Determinism (#1485)

## Phase 1: Fix Determinism (setTimeout Replacement)

### 1.1 Replace setTimeout in "does NOT send msg when sessionConfirmed is false" test

- [ ] Replace `await new Promise((r) => setTimeout(r, 50))` with `await waitFor(() => { ... })` at line 73
- **File:** `apps/web-platform/test/chat-page.test.tsx`

### 1.2 Replace setTimeout in "does not re-send msg after reconnection" test

- [ ] Replace `await new Promise((r) => setTimeout(r, 50))` with `await waitFor(() => { ... })` at line 103
- **File:** `apps/web-platform/test/chat-page.test.tsx`

### 1.3 Verify existing tests still pass

- [ ] Run `cd apps/web-platform && bun test test/chat-page.test.tsx`

## Phase 2: Add Missing Test Scenarios

### 2.1 Add handleSend independence test

- [ ] **Pre-task:** Read `components/chat/chat-input.tsx` to determine submit mechanism and input placeholder
- [ ] Check if `@testing-library/user-event` is a devDependency; install if not
- [ ] Add test: `handleSend works when sessionConfirmed is false and status is connected`
- **File:** `apps/web-platform/test/chat-page.test.tsx`

### 2.2 Add no-msg-param baseline test

- [ ] Add test: `does not send any message when no ?msg= param is present even after sessionConfirmed`
- **File:** `apps/web-platform/test/chat-page.test.tsx`

### 2.3 Add server error path test

- [ ] Add test: `shows error card and does not send msg when server errors before session_started`
- **File:** `apps/web-platform/test/chat-page.test.tsx`

## Phase 3: Verification

### 3.1 Run full test suite

- [ ] Run `cd apps/web-platform && bun test test/chat-page.test.tsx` -- all tests pass
- [ ] Verify no `setTimeout` patterns remain in negative assertions: `grep -n "setTimeout" test/chat-page.test.tsx` returns nothing
