---
title: Tasks — Dashboard ErrorCard dismiss button
date: 2026-05-11
plan: knowledge-base/project/plans/2026-05-11-feat-dashboard-error-card-dismiss-button-plan.md
branch: feat-one-shot-dashboard-error-close-button
---

# Tasks — Dashboard ErrorCard dismiss button

## Phase 1 — ErrorCard component

- [ ] 1.1 Write failing test: `renders dismiss button when onDismiss provided` in `apps/web-platform/test/error-states.test.tsx`.
- [ ] 1.2 Write failing test: `does not render dismiss button when onDismiss omitted` (backward compat).
- [ ] 1.3 Write failing test: `clicking dismiss invokes onDismiss exactly once`.
- [ ] 1.4 Add `onDismiss?: () => void` to `ErrorCardProps` in `apps/web-platform/components/ui/error-card.tsx`.
- [ ] 1.5 Render the `×` button using the SVG-line-X pattern from `apps/web-platform/components/chat/notification-prompt.tsx:159-173`. `aria-label="Dismiss"`, `type="button"`, color tokens `text-soleur-text-muted hover:text-soleur-text-secondary`. Decide between absolute positioning (`absolute top-3 right-3` with `pr-8` content padding) and flex layout — at implementation time.
- [ ] 1.6 Verify Phase 1 tests pass: `bun test apps/web-platform/test/error-states.test.tsx`.

## Phase 2 — chat-surface dismissal state

- [ ] 2.1 Write failing test in `apps/web-platform/test/error-states.test.tsx` (or sibling) covering the chat-surface integration: render `ChatSurface` with mocked `useWebSocket`, `lastError = {code: "key_invalid", ...}`; click dismiss; assert hidden; flip mock to `lastError = {code: "rate_limited", ...}`; assert new card visible.
- [ ] 2.2 In `apps/web-platform/components/chat/chat-surface.tsx`, add `const [dismissedErrorKey, setDismissedErrorKey] = useState<string | null>(null)`.
- [ ] 2.3 Add `const [sessionTimeoutDismissed, setSessionTimeoutDismissed] = useState(false)`.
- [ ] 2.4 Compute `activeKey = lastError ? \`${lastError.code}::${lastError.message}\` : null` (memoized).
- [ ] 2.5 Wrap the `lastError` `<ErrorCard>` render in `lastError && activeKey !== dismissedErrorKey && (...)`. Pass `onDismiss={() => setDismissedErrorKey(activeKey)}`.
- [ ] 2.6 Add edge-triggered reset for `sessionTimeoutDismissed`: `useRef<boolean>(false)` for previous `sessionStartTimeout`, `useEffect` that flips `sessionTimeoutDismissed` to `false` when previous was `false` and current is `true`.
- [ ] 2.7 Wrap the `sessionStartTimeout` `<ErrorCard>` render in `sessionStartTimeout && !sessionConfirmed && !sessionTimeoutDismissed && (...)`. Pass `onDismiss={() => setSessionTimeoutDismissed(true)}`.
- [ ] 2.8 Run grep: `rg "dismissedErrorKey|sessionTimeoutDismissed" apps/web-platform/components/chat/chat-surface.tsx` — confirm every reference is intentional (no orphans). Per `cq-ref-removal-sweep-cleanup-closures`.
- [ ] 2.9 Verify Phase 2 tests pass.

## Phase 3 — dashboard/page.tsx conversations card

- [ ] 3.1 Write failing test for `apps/web-platform/app/(dashboard)/dashboard/page.tsx` `Failed to load conversations` card dismissal (or extend the dashboard page test if one exists).
- [ ] 3.2 Add `const [conversationsErrorDismissed, setConversationsErrorDismissed] = useState(false)`.
- [ ] 3.3 Add edge-triggered reset on `error` value change via `useRef<string | null>`.
- [ ] 3.4 Wrap the `error && !conversationsErrorDismissed && (...)` render. Pass `onDismiss={() => setConversationsErrorDismissed(true)}`.
- [ ] 3.5 Verify Phase 3 tests pass.

## Phase 4 — Visual QA

- [ ] 4.1 Run `bun run dev` (or apps/web-platform start command). Navigate to `/dashboard`.
- [ ] 4.2 Force-render `lastError` (key_invalid) via React DevTools or test harness. Confirm X visible and clickable. Capture screenshot.
- [ ] 4.3 Force-render `sessionStartTimeout` simultaneously. Confirm both cards stack and each has its own X. Capture screenshot.
- [ ] 4.4 Dismiss each card independently. Confirm the other remains visible. Capture screenshot.
- [ ] 4.5 Trigger a NEW error (different `code`) after dismissing — confirm the new card shows.
- [ ] 4.6 Tab through the card with keyboard only — confirm dismiss button reachable and activates with Enter/Space.
- [ ] 4.7 Attach all screenshots to PR description.

## Phase 5 — Test sweep + ship

- [ ] 5.1 `bun test apps/web-platform/test/error-states.test.tsx`
- [ ] 5.2 `bun test apps/web-platform/test/` (full suite — confirm no regression).
- [ ] 5.3 `cd apps/web-platform && tsc --noEmit`
- [ ] 5.4 Run `/soleur:compound` to capture learnings.
- [ ] 5.5 Run `/soleur:ship`.
