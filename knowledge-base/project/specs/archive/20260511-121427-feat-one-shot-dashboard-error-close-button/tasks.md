---
title: Tasks — Dashboard ErrorCard dismiss button
date: 2026-05-11
plan: knowledge-base/project/plans/2026-05-11-feat-dashboard-error-card-dismiss-button-plan.md
branch: feat-one-shot-dashboard-error-close-button
---

# Tasks — Dashboard ErrorCard dismiss button

## Phase 1 — ErrorCard component

- [x] 1.1 Write failing test: `renders dismiss button when onDismiss provided` in `apps/web-platform/test/error-states.test.tsx`.
- [x] 1.2 Write failing test: `does not render dismiss button when onDismiss omitted` (backward compat).
- [x] 1.3 Write failing test: `clicking dismiss invokes onDismiss exactly once`.
- [x] 1.4 Add `onDismiss?: () => void` to `ErrorCardProps` in `apps/web-platform/components/ui/error-card.tsx`.
- [x] 1.5 Render the `×` button using the SVG-line-X pattern from `apps/web-platform/components/chat/notification-prompt.tsx:159-173`. `aria-label="Dismiss"`, `type="button"`, color tokens `text-soleur-text-muted hover:text-soleur-text-secondary`. Decide between absolute positioning (`absolute top-3 right-3` with `pr-8` content padding) and flex layout — at implementation time.
- [x] 1.6 Verify Phase 1 tests pass: `bun test apps/web-platform/test/error-states.test.tsx`.

## Phase 2 — chat-surface dismissal state

- [x] 2.1 Write failing test in `apps/web-platform/test/error-states.test.tsx` (or sibling) covering the chat-surface integration: render `ChatSurface` with mocked `useWebSocket`, `lastError = {code: "key_invalid", ...}`; click dismiss; assert hidden; flip mock to `lastError = {code: "rate_limited", ...}`; assert new card visible.
- [x] 2.2 In `apps/web-platform/components/chat/chat-surface.tsx`, add `const [dismissedErrorKey, setDismissedErrorKey] = useState<string | null>(null)`.
- [x] 2.3 Add `const [sessionTimeoutDismissed, setSessionTimeoutDismissed] = useState(false)`.
- [x] 2.4 Compute `activeKey = lastError ? \`${lastError.code}::${lastError.message}\` : null` (memoized).
- [x] 2.5 Wrap the `lastError` `<ErrorCard>` render in `lastError && activeKey !== dismissedErrorKey && (...)`. Pass `onDismiss={() => setDismissedErrorKey(activeKey)}`.
- [x] 2.6 Add edge-triggered reset for `sessionTimeoutDismissed`: `useRef<boolean>(false)` for previous `sessionStartTimeout`, `useEffect` that flips `sessionTimeoutDismissed` to `false` when previous was `false` and current is `true`.
- [x] 2.7 Wrap the `sessionStartTimeout` `<ErrorCard>` render in `sessionStartTimeout && !sessionConfirmed && !sessionTimeoutDismissed && (...)`. Pass `onDismiss={() => setSessionTimeoutDismissed(true)}`.
- [x] 2.8 Run grep: `rg "dismissedErrorKey|sessionTimeoutDismissed" apps/web-platform/components/chat/chat-surface.tsx` — confirm every reference is intentional (no orphans). Per `cq-ref-removal-sweep-cleanup-closures`.
- [x] 2.9 Verify Phase 2 tests pass.

## Phase 3 — dashboard/page.tsx conversations card

- [x] 3.1 Write failing test for `apps/web-platform/app/(dashboard)/dashboard/page.tsx` `Failed to load conversations` card dismissal (or extend the dashboard page test if one exists).
- [x] 3.2 Add `const [conversationsErrorDismissed, setConversationsErrorDismissed] = useState(false)`.
- [x] 3.3 Add edge-triggered reset on `error` value change via `useRef<string | null>`.
- [x] 3.4 Wrap the `error && !conversationsErrorDismissed && (...)` render. Pass `onDismiss={() => setConversationsErrorDismissed(true)}`.
- [x] 3.5 Verify Phase 3 tests pass.

## Phase 4 — Visual QA

- [x] 4.1 Run `bun run dev` (or apps/web-platform start command). Navigate to `/dashboard`.
- [x] 4.2 Force-render `lastError` (key_invalid) via React DevTools or test harness. Confirm X visible and clickable. Capture screenshot.
- [x] 4.3 Force-render `sessionStartTimeout` simultaneously. Confirm both cards stack and each has its own X. Capture screenshot.
- [x] 4.4 Dismiss each card independently. Confirm the other remains visible. Capture screenshot.
- [x] 4.5 Trigger a NEW error (different `code`) after dismissing — confirm the new card shows.
- [x] 4.6 Tab through the card with keyboard only — confirm dismiss button reachable and activates with Enter/Space.
- [x] 4.7 Attach all screenshots to PR description.

## Phase 5 — Test sweep + ship

- [x] 5.1 `bun test apps/web-platform/test/error-states.test.tsx`
- [x] 5.2 `bun test apps/web-platform/test/` (full suite — confirm no regression).
- [x] 5.3 `cd apps/web-platform && tsc --noEmit`
- [x] 5.4 Run `/soleur:compound` to capture learnings.
- [x] 5.5 Run `/soleur:ship`.
