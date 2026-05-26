# Tasks — Remove redundant blinking orange dot from tool-use chip

Source plan: `knowledge-base/project/plans/2026-05-06-fix-tool-use-blinking-dot-removal-plan.md` (deepened 2026-05-06).

## 1. RED — Write failing tests (uses data-testid hooks per learning 2026-04-18 Pattern 4)

- 1.1 Create `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx` with one test that:
  - 1.1.1 Mocks `@/lib/client-observability` per the existing pattern in `message-bubble-retry.test.tsx` (lines 7-10) — required to keep `formatAssistantText`'s fallthrough path from initializing Sentry in the bundle under test.
  - 1.1.2 Renders `<MessageBubble role="assistant" messageState="tool_use" toolLabel="Reading knowledge-base/overview/foo.pdf" />`.
  - 1.1.3 Asserts `getByTestId("tool-status-chip")` resolves (chip is rendered with the data-testid hook added in Phase 2).
  - 1.1.4 Asserts `getByTestId("tool-status-chip").querySelector("span.animate-pulse")` is `null` (dot is gone, scoped to the chip subtree to avoid false-positive matches against the streaming-state caret which lives elsewhere in the bubble).
  - 1.1.5 Asserts `container.textContent` contains the toolLabel verbatim.
  - 1.1.6 Asserts `container.textContent` contains the `Working` badge text.
  - 1.1.7 Asserts `container.querySelector(".message-bubble-active")` is non-null (animated border preserved).
- 1.2 Edit `apps/web-platform/test/tool-use-chip.test.tsx` — append one test:
  - 1.2.1 `test("does not render a pulsing dot indicator", ...)` rendering `<ToolUseChip toolName="Skill" toolLabel="Routing" leaderId="cc_router" />`, locating the chip via the existing `[data-tool-chip-id]` attribute (line 42 of `tool-use-chip.tsx`), and asserting `chip.querySelector("span.animate-pulse")` is `null`.
  - 1.2.2 Verify the 5 existing tests (lines 13, 21, 29, 37, 47) still pass by reading them first; the edit appends a 6th test rather than modifying any.
- 1.3 Run `bun test apps/web-platform/test/message-bubble-tool-status-chip.test.tsx apps/web-platform/test/tool-use-chip.test.tsx` — the new test in 1.1 MUST fail because `data-testid="tool-status-chip"` doesn't exist yet (Phase 2 adds it). The new test in 1.2 MUST fail because the dot is still in the DOM.

## 2. GREEN — Remove the dots, add data-testid

- 2.1 Edit `apps/web-platform/components/chat/message-bubble.tsx` `ToolStatusChip` (lines 24-31):
  - 2.1.1 Add `data-testid="tool-status-chip"` to the wrapping `<div>` (line 26). This mirrors `data-testid="thinking-dots"` (line 16) and `data-testid="retrying-chip"` (line 45) precedent in the same file.
  - 2.1.2 Delete line 27: `<span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />`.
  - 2.1.3 Leave the wrapping `<div>`'s `gap-2` class in place — `gap` on a single-child flex container is a no-op and minimizes the diff (see plan Risks).
- 2.2 Edit `apps/web-platform/components/chat/tool-use-chip.tsx`:
  - 2.2.1 Delete lines 45-48 (the `<span ... bg-amber-500 ...>` dot inside the chip body).
  - 2.2.2 Leave the chip's outer container className unchanged (`gap-2` is a no-op on a single child here too) and the existing `data-tool-chip-id` attribute (line 42) — the existing attribute already serves as the structural test hook.
- 2.3 Run `bun test apps/web-platform/test/message-bubble-tool-status-chip.test.tsx apps/web-platform/test/tool-use-chip.test.tsx apps/web-platform/test/message-bubble-retry.test.tsx` — all green.
- 2.4 Run the full chat-related test slice: `bun test apps/web-platform/test/` and confirm no new failures vs. the main-branch baseline.
- 2.5 Optional sanity grep: `grep -n "bg-amber-500" apps/web-platform/components/chat/message-bubble.tsx apps/web-platform/components/chat/tool-use-chip.tsx` — expected to return ZERO `bg-amber-500` matches in either file. Note: the `RetryingChip` retains a `bg-amber-400` dot at `message-bubble.tsx:48` (intentionally kept; different shade, different surface — the retry chip stands alone with no surrounding `Working` badge).

## 3. QA

- 3.1 Run the dev server (`bun dev` in `apps/web-platform/`) and trigger a Concierge `tool_use` event (e.g., a `/soleur:go` flow that reads a knowledge-base file).
- 3.2 Capture a screenshot of the Concierge bubble while a tool_use is in flight. Expected: animated border + top-right `Working` badge + toolLabel text WITHOUT an inner pulsing dot.
- 3.3 Capture a screenshot of the cc_router pre-bubble chip during routing. Expected: yellow-bordered pill with toolLabel text WITHOUT an inner pulsing dot.
- 3.4 (Optional) Verify the `RetryingChip` is still rendered with its dot when retry is triggered — this is the regression-canary for the out-of-scope chip.

## 4. Ship

- 4.1 Run `skill: soleur:compound` to capture any session learnings.
- 4.2 Commit with a `fix(chat): ...` prefix and the screenshot from step 3.2 attached to the PR.
- 4.3 Use `Closes #<issue-number>` in the PR body if a tracking issue is filed (this plan does not require one — it is a one-shot UI cleanup, not a deferral).
- 4.4 Apply semver label `patch` (visual-only, no behavior change).
