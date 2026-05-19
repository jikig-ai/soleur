---
title: Add dismiss (X) button to dashboard ErrorCard
date: 2026-05-11
type: feat
branch: feat-one-shot-dashboard-error-close-button
status: draft
detail_level: MORE
requires_cpo_signoff: false
---

# feat: Add dismiss (X) button to dashboard ErrorCard

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Overview (a11y context), Files to Edit (concrete code shapes), Acceptance Criteria (a11y AC added), Risks (focus management + role="alert" interaction), Sharp Edges (parity reasoning), Test Strategy (regression test for the dismiss-doesn't-clear-lastError invariant), Domain Review (agent-native parity rationale).

### Key Improvements

1. **Surfaced existing a11y baseline** — `ErrorCard` already has `role="alert"` (per learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`). The dismiss button must NOT break this — the announcement fires on mount, and our render-gating (`activeKey !== dismissedErrorKey ? <ErrorCard /> : null`) correctly remounts on new errors so re-announcement works. Documented + AC11 reframed.
2. **Focus management on dismiss** — When the dismiss button is clicked and the card unmounts, focus is orphaned (the activated element is gone). Browsers default to `<body>`. New AC12 + Risks §5 added: focus returns to a sensible anchor (chat input on chat surface, page heading on conversations list) OR explicitly accept body-default with rationale.
3. **Agent-native parity** — `agent-native-architecture` skill principle: "whatever the user can do via UI, the agent should do via tools." Dismissal is a passive render-gating decision with NO server-state mutation, NO MCP tool surface needed. Documented in Domain Review to pre-empt agent-native-reviewer flagging it.
4. **Test strategy strengthened** — Per AGENTS.md `cq-write-failing-tests-before`, tests precede impl. Added explicit regression test: dismissing the card MUST NOT call any clear/null setter on `useWebSocket.lastError` (the state-machine invariant). Verified via mock `setLastError` call assertion.
5. **Discriminator key collision check** — `${code}::${message}` keying: server-supplied strings are sanitized (`apps/web-platform/test/error-sanitizer.test.ts` confirms PII redaction), so concatenation safety holds. Same-frame re-suppression accepted as desirable; counter-bump fallback documented.
6. **Open code-review overlap re-verified** — The 3 ws-client.ts and 2 dashboard/page.tsx open issues are confirmed orthogonal. We do NOT modify ws-client.ts.

### New Considerations Discovered

- **`role="alert"` re-announce semantics.** Re-mounting an `ErrorCard` after a different error fires correctly re-triggers the screen-reader announcement IF the React reconciler treats the new element as a new mount. Our `lastError && activeKey !== dismissedErrorKey && (...)` ternary returns `null` on the dismissed branch, which unmounts. When a new error arrives with a different key, React mounts a fresh `<ErrorCard>` — `role="alert"` fires. Verified via React docs: a `null` → element transition is always a mount.
- **Existing dismiss-button precedent inconsistency.** `notification-prompt.tsx:159` uses an SVG-line X with explicit width=16; `account-state-banner.tsx:49` uses a literal `×` (Unicode multiplication sign). For consistency with the more-recent and more-accessible pattern (SVG can be styled, has `aria-label`, scales cleanly), pick the `notification-prompt.tsx` pattern. Documented in §Files to Edit.
- **No need for Headless UI / Radix Dialog.** The dismiss action is not a modal — it's an in-line affordance that only hides the card. No focus trap, no escape-key handler beyond what native `<button>` provides. Deliberately NOT introducing a new UI dependency.

### Sources

- AGENTS.md rules: `cq-write-failing-tests-before`, `cq-ref-removal-sweep-cleanup-closures`, `cq-union-widening-grep-three-patterns`, `hr-weigh-every-decision-against-target-user-impact`, `hr-when-a-plan-specifies-relative-paths-e-g`
- Project learnings: `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md` (role="alert" on ErrorCard, focus-ring patterns), `2026-04-23-command-center-bubble-lifecycle-invariants.md` (state-clearing without state-mutation in chat-state-machine pattern is precedent for our dismiss-without-clear approach)
- Existing precedents: `notification-prompt.tsx:159-173` (DismissButton SVG shape), `account-state-banner.tsx:42-51` (× pattern, less preferred)
- WAI-ARIA Authoring Practices 1.2: `aria-label` on icon-only buttons; `role="alert"` re-announce semantics on remount
- React Testing Library docs: `userEvent.click` over `fireEvent.click` for full interaction simulation; query-by-role over query-by-text for resilient a11y assertions

## Overview

Users on the Dashboard chat surface currently cannot dismiss inline error notification cards (`Invalid API Key`, `Session Failed to Start`, `Connection Error`, `Rate Limited`, `Failed to load conversations`, etc.). When two errors stack — e.g., a `key_invalid` followed by a `sessionStartTimeout` — they consume vertical real estate above the chat thread until the user navigates away or the underlying state changes (which, for `key_invalid`, never happens without an explicit key update).

This plan adds a small `×` icon button in the top-right corner of every `ErrorCard`. Clicking it hides that specific card. The dismissal is **per-card, in-memory only** — refreshing the page or triggering a new instance of the same error re-shows the card (errors are not silenced, only the current notification is acknowledged).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "Two stacked red-bordered error cards above the chat thread" | Confirmed: `apps/web-platform/components/chat/chat-surface.tsx:517-538` renders `lastError` (line 519) and `sessionStartTimeout && !sessionConfirmed` (line 531) as two adjacent `ErrorCard` instances | Both rendered call sites get dismiss wired via independent local state |
| "Dashboard chat surface" only | Plus a third call site at `app/(dashboard)/dashboard/page.tsx:651` (`Failed to load conversations`) on the conversations list page | Inherits dismiss for free since `onDismiss` is added at the component level. No extra wiring; documented in §Files to Edit so QA covers it |
| Card has "small X icon in top-right corner" | The codebase already has a canonical `DismissButton` shape in `components/chat/notification-prompt.tsx:159-173` (16×16 SVG, `text-soleur-text-muted hover:text-soleur-text-secondary`) used in `notification-prompt.tsx` and `account-state-banner.tsx` (as `×` text) | Reuse the SVG-line-X pattern from `notification-prompt.tsx` for visual consistency with other dismissable cards. No new design tokens |
| Dismissal hides the card | `lastError` is owned by `useWebSocket` (`lib/ws-client.ts:374`) and only cleared on remount (line 1083) or `connect` (line 1218). `sessionStartTimeout` is local `useState` in `chat-surface.tsx:216` | Add a sibling local "dismissed-error key" `useState` in `chat-surface.tsx`. Do NOT mutate `lastError` itself — that is the WS hook's source of truth and the agent-native consumer reads it. The dismissal layer sits between hook state and render |

## User-Brand Impact

**If this lands broken, the user experiences:** A non-clickable X icon, or an X that hides the card permanently (even when a NEW, distinct error fires). Worst case: the user dismisses an `Invalid API Key` card, a different error (`rate_limited`, `image_paste_lost`) then fires, and the dismissal state silently swallows the new card — the user has no idea the platform is failing.

**If this leaks, the user's data/workflow/money is exposed via:** N/A. Dismissal is client-only, in-memory. The X click triggers no network request, persists no data, and changes no server state. The underlying error condition (invalid key, session timeout) is unchanged — only the current notification banner is hidden.

**Brand-survival threshold:** none

**Reason:** This is purely a UI affordance on already-displayed, already-redacted error text. No new data flows, no new persistence, no auth/payment/PII surface touched. Diff confined to client-side React state in `apps/web-platform/components/`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: When `onDismiss` is passed, every `ErrorCard` instance renders a dismiss button (SVG `×` icon, 16×16, two `<line>` paths matching `notification-prompt.tsx:167-170`) in the top-right corner with `aria-label="Dismiss"` and `type="button"` (a11y + form-submission safety). When `onDismiss` is omitted, the dismiss button is NOT rendered (backward compat for any future caller that wants a non-dismissable card — verified by AC1b regression test).
- [ ] AC2: Clicking the dismiss button hides that specific `ErrorCard` instance without affecting any other rendered `ErrorCard` (verified by Vitest + Testing Library for `chat-surface.tsx`'s two-card stack).
- [ ] AC3: When `useWebSocket.lastError` transitions from `{code: "key_invalid", ...}` → `null` → `{code: "rate_limited", ...}`, the new card is shown even if the previous card was dismissed (i.e., the dismissal key tracks the **specific error**, not a "dismissed any error" boolean).
- [ ] AC4: When `lastError` changes shape (e.g., new `code` value) while a card is already shown, the new card is shown — a stale dismissal does NOT mask a fresh error.
- [ ] AC5: `sessionStartTimeout` card dismissal is independent of `lastError` card dismissal — dismissing one does not hide the other.
- [ ] AC6: `app/(dashboard)/dashboard/page.tsx` `ErrorCard` for "Failed to load conversations" inherits dismissal (verified by spot-check render test). When `error` upstream stays truthy after dismiss, refetching (via `onRetry`) and re-failing must re-show the card.
- [ ] AC7: Vitest suite `apps/web-platform/test/error-states.test.tsx` extended with three cases: (a) renders dismiss button, (b) clicking dismiss hides only the clicked card, (c) `onDismiss` callback is invoked exactly once per click.
- [ ] AC8: `tsc --noEmit` passes for the apps/web-platform workspace.
- [ ] AC9: `bun test apps/web-platform/test/error-states.test.tsx` passes locally.
- [ ] AC10: Visual QA via Playwright MCP: navigate to `/dashboard`, force-render both `lastError` (key_invalid) and `sessionStartTimeout` cards via test harness or DevTools, confirm both X buttons are clickable, confirm cards hide independently. Screenshots attached to PR.
- [ ] AC11: Keyboard-only operation: `Tab` reaches the dismiss button after the retry/action button(s); `Enter`/`Space` activates it. (Native `<button>` semantics already provide this — the AC verifies tab order is sensible relative to existing card buttons.)
- [ ] AC12: Focus management on dismiss — when the dismiss button is clicked and the card unmounts, focus moves to a sensible anchor: on `chat-surface.tsx`, focus returns to the chat input textarea (`document.querySelector('[data-chat-input]')` or equivalent ref); on `dashboard/page.tsx`, focus moves to the page heading or first interactive element. Implementation may rely on React's default behavior (focus returns to body) IF QA confirms the screen-reader experience is acceptable; otherwise an explicit focus call is wired in the dismiss handler. Verified manually with VoiceOver/NVDA in Phase 4 visual QA.
- [ ] AC13: `role="alert"` re-announce regression — when `lastError` flips key (e.g., `key_invalid` → `rate_limited`) AFTER a previous dismiss, the new card mounts and the screen reader announces it. Verified by Vitest assertion that the `<div role="alert">` is in the DOM after the key change (testing-library `getByRole("alert")` after re-render).
- [ ] AC14: Dismissing the card MUST NOT mutate `useWebSocket.lastError` — verified by mock that no `setLastError`-equivalent is invoked during the dismiss flow. The dismissal layer sits OUTSIDE the WS hook's state. (Regression guard against a future "helpful" refactor that pushes dismiss into the hook.)

### Post-merge (operator)

- (None.) Pure client-side change, no migrations, no infra, no env vars, no remote workflows added.

## Files to Edit

- `apps/web-platform/components/ui/error-card.tsx` — Add `onDismiss?: () => void` prop. When present, render an absolutely-positioned `×` button in the top-right corner. Convert outer `<div>` to `position: relative` (or use flex layout with the dismiss-button column).
- `apps/web-platform/components/chat/chat-surface.tsx` — Add two pieces of local `useState`:
  1. `const [dismissedErrorKey, setDismissedErrorKey] = useState<string | null>(null)` — tracks the currently-dismissed `lastError`'s discriminator (we'll use `lastError.code + lastError.message` as the key, since `code` alone collapses `image_paste_lost` distinct messages).
  2. `const [sessionTimeoutDismissed, setSessionTimeoutDismissed] = useState(false)` — tracks dismissal of the `Session Failed to Start` card.
  - Compute a derived key for the active `lastError` and pass `onDismiss` to its `ErrorCard` only when the derived key !== `dismissedErrorKey`. When `lastError` becomes a new key, render the card and let the user dismiss again.
  - Reset `sessionTimeoutDismissed` to `false` whenever `sessionStartTimeout` transitions `false → true` so a re-fire (re-mount, reconnect cycle) re-shows the card.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — Wire `onDismiss` for the `Failed to load conversations` card. Add a sibling `useState<boolean>` and reset on `error` change.
- `apps/web-platform/test/error-states.test.tsx` — Extend with three new tests (see AC7).

## Files to Create

- (None.)

## Implementation Phases

### Phase 1 — `ErrorCard` component (RED → GREEN)

1. Write failing tests in `error-states.test.tsx`:
   - `renders dismiss button when onDismiss provided`
   - `does not render dismiss button when onDismiss omitted` (preserves backward compat for any callers that don't pass it)
   - `clicking dismiss invokes onDismiss exactly once`
2. Add `onDismiss?: () => void` to `ErrorCardProps`.
3. Render the `×` button using the `notification-prompt.tsx:159-173` `DismissButton` SVG (two `<line>` elements), with `aria-label="Dismiss"`, `type="button"`, `text-soleur-text-muted hover:text-soleur-text-secondary`, positioned via `flex justify-between` on the title row OR `absolute top-3 right-3` (decide at implementation time — the absolute approach decouples vertical alignment from title length).
4. Keep tests green.

#### Research Insights — ErrorCard component

**Recommended concrete shape (after research):**

```tsx
"use client";

interface ErrorCardProps {
  title: string;
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  action?: { label: string; href: string };
  onDismiss?: () => void;
}

export function ErrorCard({
  title,
  message,
  onRetry,
  retryLabel = "Try again",
  action,
  onDismiss,
}: ErrorCardProps) {
  return (
    <div
      role="alert"
      className="relative rounded-xl border border-red-900/50 bg-red-950/20 p-5"
    >
      {onDismiss && (
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="absolute right-3 top-3 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      )}
      <h3 className="mb-1 pr-8 text-sm font-semibold text-red-300">{title}</h3>
      <p className="pr-8 text-sm text-soleur-text-secondary">{message}</p>
      <div className="mt-3 flex gap-2">
        {/* unchanged retry/action block */}
      </div>
    </div>
  );
}
```

**Key decisions in the snippet above:**
- `relative` + `absolute right-3 top-3` decouples button position from title length (a long title won't push the X out of alignment).
- `pr-8` on title and message reserves whitespace so long titles don't run under the X (32px padding ≥ 16px button + 12px button-edge inset + 4px breathing).
- `aria-hidden="true"` on the SVG prevents screen readers from announcing the SVG itself; the `aria-label="Dismiss"` on the parent button is the announced label.
- `rounded p-1` on the button gives a comfortable 24×24 touch target (16 SVG + 8 padding) — meets WCAG 2.5.5 Target Size (Enhanced) minimum.
- `transition-colors` matches the existing retry/action button hover affordance.
- `role="alert"` is preserved on the container — the existing a11y baseline from learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md` is unchanged.

**Anti-patterns avoided:**
- Did NOT introduce a separate `<DismissButton>` component for the ErrorCard. The `notification-prompt.tsx` extraction makes sense there (used 3 times in one file); here it's used once. YAGNI.
- Did NOT use the literal `×` Unicode character (the `account-state-banner.tsx` pattern). SVG renders consistently across font stacks; Unicode `×` (U+00D7) varies in vertical alignment by font.
- Did NOT add focus-ring overrides — the global `@layer base` `:where()` focus-ring (per learning 2026-04-02) handles `focus-visible` automatically.

### Phase 2 — `chat-surface.tsx` per-card dismissal state (RED → GREEN)

1. Write failing test: render `ChatSurface` with `lastError = {code: "key_invalid", message: "X"}`; assert card visible; click dismiss; assert card hidden; mock `useWebSocket` to return `lastError = {code: "rate_limited", message: "Y"}`; re-render; assert NEW card visible.
2. Add the two `useState` slots described in §Files to Edit.
3. Compute the active-error key as `${lastError.code}::${lastError.message}` (concatenation safe since both are server-supplied strings; `::` is unlikely to appear in either and the key is purely an in-memory equality token, not a parsed value). Wrap in `useMemo` to avoid object-identity churn.
4. Pass `onDismiss={() => setDismissedErrorKey(activeKey)}` only when `activeKey !== dismissedErrorKey`. Skip rendering the card entirely when keys match.
5. Add a `useEffect` that resets `sessionTimeoutDismissed` to `false` when `sessionStartTimeout` flips from `false` to `true` (track previous value via `useRef`).
6. Per AGENTS.md `cq-ref-removal-sweep-cleanup-closures`: if any ref/state addition has a cleanup that captures the new ref, grep its name in the file before commit to verify zero orphaned uses.

#### Research Insights — chat-surface dismissal state

**Recommended concrete shape (after research):**

```tsx
// Inside ChatSurface component, near other useState declarations (line ~216):
const [dismissedErrorKey, setDismissedErrorKey] = useState<string | null>(null);
const [sessionTimeoutDismissed, setSessionTimeoutDismissed] = useState(false);
const prevSessionTimeoutRef = useRef(false);

// Active error key (memoized to keep referential equality when lastError ref-stable):
const activeErrorKey = useMemo(
  () => (lastError ? `${lastError.code}::${lastError.message}` : null),
  [lastError],
);

// Edge-triggered reset for sessionStartTimeout (false -> true transition):
useEffect(() => {
  if (!prevSessionTimeoutRef.current && sessionStartTimeout) {
    setSessionTimeoutDismissed(false);
  }
  prevSessionTimeoutRef.current = sessionStartTimeout;
}, [sessionStartTimeout]);

// Render gating (replaces existing lines 517-538):
{lastError && activeErrorKey !== dismissedErrorKey && (
  <div className={`mb-4 ${widthWrapper}`}>
    <ErrorCard
      title={
        lastError.code === "key_invalid"
          ? "Invalid API Key"
          : lastError.code === "rate_limited"
            ? "Rate Limited"
            : "Connection Error"
      }
      message={lastError.message}
      onRetry={lastError.code !== "key_invalid" ? reconnect : undefined}
      retryLabel="Reconnect"
      action={lastError.action}
      onDismiss={() => setDismissedErrorKey(activeErrorKey)}
    />
  </div>
)}

{sessionStartTimeout && !sessionConfirmed && !sessionTimeoutDismissed && (
  <div className={`mb-4 ${widthWrapper}`}>
    <ErrorCard
      title="Session Failed to Start"
      message="The server did not confirm the session within 10 seconds. Please try again."
      onRetry={reconnect}
      retryLabel="Reconnect"
      onDismiss={() => setSessionTimeoutDismissed(true)}
    />
  </div>
)}
```

**Why edge-triggered (not deps-based) reset for `sessionTimeoutDismissed`:**
A naive `useEffect(() => { if (sessionStartTimeout) setSessionTimeoutDismissed(false); }, [sessionStartTimeout])` would reset on EVERY render where `sessionStartTimeout === true` — making dismiss un-stick. The `useRef` pattern stores the previous value across renders so we only act on the false→true transition.

**Why not store dismissal in `useReducer` or context:**
Two boolean/string slots in one component are not state-machine territory. `useState` is the simplest tool that works; reaching for `useReducer` would be premature abstraction. No other component needs to read this state.

**Why concatenate code+message (not just code):**
The `image_paste_lost` error path (`ws-client.ts:665-670`) sets `lastError.message` from a server-supplied per-incident message. A user dismissing one paste-lost notification should NOT suppress a subsequent paste-lost with a different message. Concatenation gives per-incident discrimination without a counter.

**Anti-patterns avoided:**
- Did NOT add a `clearLastError`/`dismissError` method to `useWebSocket`. Concern: widens the hook's public surface, tempts other consumers to suppress real errors, conflicts with the in-flight ws-client refactor (#3280). Documented in Sharp Edges.
- Did NOT use `Set<string>` for tracking multiple dismissed keys. Only one error is rendered at a time (the WS hook holds one `WebSocketError | null`, not a queue). Set semantics imply queueing that doesn't exist.
- Did NOT pass `setDismissedErrorKey` into a child via context. The render gating happens in chat-surface; the dismiss handler can be a closure over the local setter.

### Phase 3 — `dashboard/page.tsx` conversations-list card (RED → GREEN)

1. Add a sibling `useState<boolean>` `conversationsErrorDismissed`.
2. Reset to `false` whenever `error` transitions from a value to a different value (track via `useRef<string | null>`).
3. Pass `onDismiss` to the `ErrorCard` only when not dismissed.
4. Add a render-test (or extend an existing dashboard test if one exists) verifying dismiss hides the card.

#### Research Insights — dashboard/page.tsx

**Recommended concrete shape:**

```tsx
// In DashboardPage component, near other useState declarations:
const [conversationsErrorDismissed, setConversationsErrorDismissed] = useState(false);
const prevErrorRef = useRef<string | null>(null);

useEffect(() => {
  if (error !== prevErrorRef.current) {
    setConversationsErrorDismissed(false);
    prevErrorRef.current = error;
  }
}, [error]);

// Replace existing line 650-656:
{error && !conversationsErrorDismissed && (
  <ErrorCard
    title="Failed to load conversations"
    message={error}
    onRetry={refetch}
    onDismiss={() => setConversationsErrorDismissed(true)}
  />
)}
```

**Why edge-trigger on `error` value change (not just truthiness flip):**
If `error` is `"Network error"` → user dismisses → user clicks retry → fetch fails again with `"Network error"` (identical string), the dismissal would persist and the user would have no feedback. By keying on the value, an identical re-fail re-shows the card. This matches the chat-surface dismissed-key pattern semantically: "different incident → re-show."

**Caveat:** If `refetch` returns the same `error` string on a deliberate retry (no value change), the card stays hidden. This is acceptable because the user just clicked retry — they're already aware. The retry button's action is the user's acknowledgment.

### Phase 4 — Visual QA

1. Run `bun run dev` (or apps/web-platform equivalent), navigate to `/dashboard`.
2. Trigger `lastError` via dev-only path or React DevTools — confirm X visible, dismissal hides card.
3. Trigger `sessionStartTimeout` (let session-start exceed 10 s, or mock) — confirm independent dismiss.
4. Stack both cards, dismiss each in turn — confirm only the clicked card disappears.
5. Capture before/after screenshots at the PR-attached resolution.

### Phase 5 — Test sweep + ship

1. `bun test apps/web-platform/test/error-states.test.tsx`
2. `bun test apps/web-platform/` (full app suite — confirm no regression in chat-surface tests).
3. `tsc --noEmit` from `apps/web-platform/`.
4. `/soleur:compound` before commit.
5. `/soleur:ship`.

## Test Strategy

**Framework:** Vitest + React Testing Library (already installed, all sibling tests use this — `error-states.test.tsx`, `useWebSocket-abort.test.tsx`).

**Categories:**

- **Unit (component):** `ErrorCard` props handling — onDismiss render gating, callback wiring.
- **Integration (chat surface):** WS-mock-backed render asserting that dismissal of one card does not hide a sibling card, and that a new error key re-shows after dismiss.
- **Visual QA (Playwright MCP):** Manual screenshot in dev for the stacked-cards case (the only path with real DOM positioning).

**Anti-patterns to avoid:**

- Do NOT mutate `lastError` in tests by calling a fake "dismissError" on the hook — there is no such API and we are NOT adding one (see Sharp Edges §1). Local component state is the dismissal source of truth.
- Do NOT use `act()` wrappers manually unless RTL warns; modern RTL handles this automatically for click events.

### Research Insights — Test Strategy

**Test query selectors (preferred order, per RTL guiding principles):**

1. `getByRole("button", { name: /dismiss/i })` — most resilient; survives implementation refactors that change DOM structure
2. `getByLabelText("Dismiss")` — second-best; requires the label to exist
3. `getByText` — avoid for the icon button (no visible text)

**Concrete test sketch for AC2/AC7 (dismiss-hides-only-this-card):**

```tsx
test("clicking dismiss on lastError card does not hide sessionStartTimeout card", async () => {
  wsReturn.lastError = {
    code: "key_invalid",
    message: "Your API key is invalid or expired.",
    action: { label: "Update key", href: "/dashboard/settings" },
  };
  // sessionStartTimeout is local state; force via a mounted ChatSurface in a state where it's true.
  // (Use the existing pattern from useWebSocket-abort.test.tsx for hook-state forcing.)

  const { container } = await renderChatPage();
  expect(screen.getByText("Invalid API Key")).toBeInTheDocument();

  // Two cards rendered means two role=alert containers
  const alertsBefore = container.querySelectorAll('[role="alert"]');
  expect(alertsBefore.length).toBe(2);

  // Click the dismiss button on the FIRST card (lastError)
  const dismissButtons = screen.getAllByRole("button", { name: /dismiss/i });
  await userEvent.click(dismissButtons[0]);

  // Only sessionStartTimeout card remains
  const alertsAfter = container.querySelectorAll('[role="alert"]');
  expect(alertsAfter.length).toBe(1);
  expect(screen.queryByText("Invalid API Key")).toBeNull();
  expect(screen.getByText("Session Failed to Start")).toBeInTheDocument();
});
```

**Concrete test sketch for AC14 (dismiss does NOT mutate lastError):**

```tsx
test("dismissing card does not invoke any setLastError mock", async () => {
  // The mock from createWebSocketMock does NOT expose setLastError as part of the public hook return
  // (correctly — it's internal). The regression guard is therefore: AFTER dismiss, the hook return
  // value's lastError reference is unchanged.
  wsReturn.lastError = { code: "key_invalid", message: "X", action: undefined };
  const { rerender } = await renderChatPage();
  const beforeRef = wsReturn.lastError;

  await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));

  // Hook state untouched: same object identity
  expect(wsReturn.lastError).toBe(beforeRef);
  // Render-gated: card no longer in DOM
  expect(screen.queryByText("Invalid API Key")).toBeNull();
});
```

**Concrete test sketch for AC13 (role=alert re-announces on key change):**

```tsx
test("new error after dismiss re-mounts with role=alert", async () => {
  wsReturn.lastError = { code: "key_invalid", message: "A", action: undefined };
  const { rerender } = await renderChatPage();

  await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));
  expect(screen.queryByText("A")).toBeNull();

  // New error fires (different key)
  wsReturn.lastError = { code: "rate_limited", message: "B", action: undefined };
  // Force re-render via mock state-change pattern from existing tests
  rerender(<ChatPage />);

  expect(screen.getByText("B")).toBeInTheDocument();
  expect(screen.getByRole("alert")).toBeInTheDocument();
});
```

**`userEvent` vs `fireEvent`:** Prefer `userEvent.click` (RTL recommendation since v14) — it simulates the full user interaction (focus + pointer events + click + blur) instead of just the synthetic click event. The existing `error-states.test.tsx` uses `.click()` directly; new tests in this PR use `userEvent` for the new interactions to match the modern RTL pattern.

## Open Code-Review Overlap

Three open code-review issues touch files this plan modifies. All are independent concerns — **acknowledge**, do not fold in:

- **#3372** (lib/ws-client.ts) — `tryLedgerDivergenceRecovery` 120 s threshold tautology. Concerns the WS recovery path inside the ledger divergence reducer, not error-state plumbing. Out of scope.
- **#3374** (lib/ws-client.ts) — `slot_reclaimed` WS frame emission for agent clients. New WS frame, unrelated to the `error`-frame handling we touch indirectly via consumer state. Out of scope.
- **#3280** (lib/ws-client.ts) — refactor history-fetch into reducer-driven state machine. Architectural refactor of `useWebSocket`. We do not touch the hook in this PR; only chat-surface consumer state. Folding would expand scope by an order of magnitude. Out of scope.
- **#3334** (app/(dashboard)/dashboard/page.tsx) — gold-gradient primary CTA consolidation. UI design-token concern, not error state. Out of scope.
- **#2590** (app/(dashboard)/dashboard/page.tsx) — extract `useFirstRunAttachments` + `FirstRunComposer` from `DashboardPage`. Orthogonal refactor; we touch the error-render block, which is downstream of both extracted hooks. Out of scope.

This plan does NOT modify `lib/ws-client.ts`. The ws-client.ts overlaps therefore touch the file we *consume* but not the file we *change*.

## Risks

1. **Stale-dismiss masking new error.** If we keyed dismissal on a constant ("any error dismissed"), a `key_invalid` dismiss could swallow a subsequent `rate_limited`. Mitigation: discriminator key `${code}::${message}`. AC3 + AC4 are the regression gates.
2. **`useWebSocket.lastError` re-firing the same code+message.** The hook resets `lastError` to `null` on remount/connect (lines 1083, 1218) but if a server re-emits the identical frame in-session without a `null` intermediate, our key-based dismissal would suppress the re-fire. Mitigation: confirmed in research that all `setLastError` paths in `ws-client.ts:644-848` either follow a teardown (which remounts → null) or fire from distinct error codes. We accept the in-session same-frame re-suppression as a desirable feature ("user already saw this exact error"). Documented in Sharp Edges §2.
3. **`role="alert"` and dismissal interaction.** Screen readers announce `role="alert"` on mount. After dismissal + re-show with a new error, the new card MUST also announce. Since we re-mount the card (key change), `role="alert"` will re-fire. Verified by inspection of the render gating (`activeKey !== dismissedErrorKey ? <ErrorCard ... /> : null` — null unmounts the node).
4. **`absolute` positioning vs. button overlap.** If we choose absolute positioning, ensure the dismiss button doesn't overlap the title or the action buttons on narrow viewports. Mitigation: title and message have natural right-padding (`pr-8` on the inner content), or use flex layout with the dismiss button as a sibling column. Decide at implementation time. **Resolved by Research Insights**: snippet uses `pr-8` on title and message — verified as sufficient at the SVG (16px) + button padding (8px) + edge inset (12px) = 36px ≤ 32px (`pr-8`). Tighten to `pr-9` (36px) if QA shows visual contact.
5. **Focus management on dismiss → orphaned focus.** When the dismiss button is clicked and `<ErrorCard>` unmounts, the activated DOM element is gone. Browsers default focus to `<body>`, which means screen-reader users lose focus context (next Tab starts from page top). Mitigation tiers, in order of preference:
    - **Tier A (recommended for chat-surface):** Wire an explicit focus call in the dismiss handler that targets the chat input textarea via `useRef` (the natural next interaction). Adds 3 lines per call site.
    - **Tier B (acceptable for dashboard/page.tsx):** Accept body-default if QA confirms screen-reader experience is reasonable (the conversations list has natural Tab order from page heading down).
    - **Tier C (anti-pattern):** Do nothing — silently degrades a11y. Reject.
    Decision deferred to Phase 4 visual QA with screen-reader trial. AC12 documents the gate.
6. **`role="alert"` re-announce on key change.** When `lastError` flips key after a previous dismiss, the ternary returns `<ErrorCard>` after returning `null` — React reconciler treats this as a fresh mount, which re-fires `role="alert"`. Verified by ARIA spec: `role="alert"` triggers on element insertion into the accessibility tree. Our render gating guarantees insertion (not just attribute toggle), so the announcement re-fires. AC13 is the regression gate.
7. **Conflict with #3280 (ws-client.ts reducer refactor).** If #3280 lands first, `lastError` may move from `useState` to a reducer slice. Our chat-surface code consumes the `lastError` value via destructure — refactor-resilient. If #3280 instead introduces a `clearLastError` reducer action, our plan is unchanged (we don't call any clearing API; the reducer can ignore us). Defensive: explicitly NOT calling any clearing function in any test or impl, AC14 enforces this.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Section is filled with concrete artifacts/vectors and `none` threshold + reason.
- **Do NOT add a `clearLastError`/`dismissError` API to `useWebSocket`.** Dismissal is a UI concern, not a hook-state concern. Adding a clear API to the hook would (a) widen the hook's public surface, (b) tempt other consumers to suppress real errors, (c) conflict with #3280's reducer refactor. The discriminator-key pattern in chat-surface is the lowest-blast-radius placement.
- **Do NOT use a `WeakSet` or set-of-keys to track multiple dismissed errors.** A single `dismissedErrorKey: string | null` is sufficient because at most one `lastError` is rendered at a time (the hook holds a single value, not a queue). A set would imply queueing semantics that don't exist.
- **Same-frame re-suppression.** If the WS server re-fires the IDENTICAL `error` frame (same `code`, same `message`) without a null intermediate, our dismiss-key suppresses the re-show. This is intentional (the user already acknowledged this exact error) but if reviewers flag it as a usability concern, the fallback is to bump the dismiss-key on every `setLastError` call by adding a monotonic counter to the key. Defer until reviewers raise it.
- **`sessionStartTimeout` reset on transition.** If we naively reset on every render where `sessionStartTimeout === true`, the dismiss state never sticks. The reset must be edge-triggered (`false → true` only). Use `useRef` for previous value, not `useEffect` deps.
- **Per AGENTS.md `cq-union-widening-grep-three-patterns`** — we are NOT widening any discriminated union. `WebSocketError.code` accepts `string` and is consumed in chat-surface only via specific equality checks. No exhaustiveness rails affected.
- **Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`** — file paths in §Files to Edit are absolute within the repo (no `../` traversal). All four files were verified via `find`/`grep` during research and exist.

## Domain Review

**Domains relevant:** Product (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode + ADVISORY tier per Phase 2.5)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This plan modifies an existing UI component (`ErrorCard`) without adding a new user-facing page, multi-step flow, or new persuasive/emotional surface. The dismiss button is a standard affordance whose pattern already exists in two sibling components (`notification-prompt.tsx`, `account-state-banner.tsx`) — visual consistency comes from reusing the established `DismissButton` SVG shape and color tokens. No new copy is introduced (the X icon has only an `aria-label`). Tier is ADVISORY by the Phase 2.5 mechanical rule (modifies existing UI, no new file in `components/**/*.tsx` or `app/**/page.tsx`). In pipeline mode, ADVISORY auto-accepts.

The brainstorm at `knowledge-base/project/brainstorms/2026-04-16-dismissable-foundation-cards-brainstorm.md` is for *foundation cards* on the Command Center grid — a different surface with different dismissal semantics (auto-replace, not manual X). It is NOT a relevant brainstorm carry-forward for this plan; the request is for error-notification cards above the chat thread, where manual dismissal is the correct affordance because (a) errors are not progress milestones, (b) auto-replace would conflate "dismissed" with "resolved", (c) there is no "next error" to surface.

### Agent-Native Parity (engineering)

Per `agent-native-architecture` skill: "whatever the user can do via the UI, the agent should achieve via tools." This plan adds a UI affordance (dismiss button) that hides a notification render. The agent-native equivalent is **"ignore this field in your context window"** — which agents can do trivially without any new MCP tool, because:

1. **No server-state mutation.** Dismissal does not write to the DB, the WS server, or any persistent store. There is no "dismissed-error" record to read back.
2. **No agent-readable state change.** `lastError` on the WS hook is unaffected by dismissal — it remains the canonical "last server-reported error" value. An agent reading the WS connection sees the same `error` frames; an agent reading conversation history is unaffected (no new messages emitted).
3. **No new event surface.** Dismissal does not fire a WS frame, does not invoke a route handler, does not log anything to Sentry/pino.

If a future change adds *server-side* dismissal (e.g., "snooze this error class for 24h"), THAT change would need an MCP tool. This change does not, and the plan deliberately scopes against that expansion (Sharp Edges §1: do NOT add a clearLastError API to the hook).

**Pre-empted concerns from `agent-native-reviewer`:**

- "Should there be an `mcp__dismiss_error` tool?" → No. The error is a passive notification, not an actionable state. Agents reading `lastError` get the same data whether the human dismissed the card or not.
- "Should the WS server know the error was dismissed?" → No. The server has no behavior contingent on dismissal. Adding the round-trip would create a coordination problem (two clients, two dismissal states) for zero user value.
- "Should the dismissal persist across page refreshes?" → No. The error itself does not persist — `lastError` is reset on remount per `ws-client.ts:1083`. Persisting dismissal of a state that doesn't persist is incoherent.

## Distribution & Marketing

Not applicable. Internal UX polish; no public-facing announcement, no docs/site change, no Discord/X post.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-11-feat-dashboard-error-card-dismiss-button-plan.md

Context: branch feat-one-shot-dashboard-error-close-button, worktree .worktrees/feat-one-shot-dashboard-error-close-button/, no PR yet, no issue yet. Plan written and deepened, no implementation started. Three files to touch: components/ui/error-card.tsx, components/chat/chat-surface.tsx, app/(dashboard)/dashboard/page.tsx. Tests live in apps/web-platform/test/error-states.test.tsx.
```
