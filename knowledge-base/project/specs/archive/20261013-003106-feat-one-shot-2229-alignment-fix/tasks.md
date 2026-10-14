---
feature: feat-one-shot-2229-alignment-fix
plan: knowledge-base/project/plans/2026-04-15-fix-command-center-row-and-chat-markdown-overflow-plan.md
issue: 2229
---

# Tasks — #2229 UI alignment fix

## Phase 1 — Setup

1.1. Confirm `apps/web-platform` dev dependencies installed (`bun install` at repo
root is sufficient — deps live in the top-level lockfile).
1.2. Verify vitest runs in worktree via
`cd apps/web-platform && node node_modules/vitest/vitest.mjs run`.
1.3. Read the plan file end-to-end.

## Phase 2 — RED: failing tests

2.1. Create `apps/web-platform/test/conversation-row.test.tsx` with assertions:

- 2.1.1. Time span has classes `w-16`, `text-right`, `tabular-nums`.
- 2.1.2. Time spans for single-digit and two-digit minutes have equal `offsetWidth`
  (or identical class list if jsdom layout is unavailable).
- 2.1.3. LeaderAvatar renders in expected DOM position relative to time span.

2.2. Create `apps/web-platform/test/markdown-renderer.test.tsx` with assertions:

- 2.2.1. A long unbroken 500-character string renders inside a `<p>` with
  `break-words` / `overflow-wrap: anywhere`.
- 2.2.2. Markdown tables retain their `overflow-x-auto` wrapper.
- 2.2.3. Fenced code blocks retain their `overflow-x-auto` `<pre>` class.

2.3. Extend `apps/web-platform/test/command-center.test.tsx` to include a
`12m ago` conversation alongside the existing `2m ago` / `15m ago` / `1d ago`
fixtures. Ensure no console warnings; existing assertions still pass.

2.4. Run the vitest suite — confirm the NEW tests fail (RED).

## Phase 3 — GREEN: minimal implementation

3.1. Update `apps/web-platform/components/inbox/conversation-row.tsx`:

- 3.1.1. Line 227 desktop time span: change class to
  `"shrink-0 w-16 text-right text-xs text-neutral-500 tabular-nums"`.
- 3.1.2. Optionally apply the same treatment to the mobile variant (line 178)
  for consistency — evaluate visually.

3.2. Update `apps/web-platform/components/ui/markdown-renderer.tsx`:

- 3.2.1. Wrap the `<Markdown>` output in a root `<div className="break-words
  [overflow-wrap:anywhere]">` so wrap rules apply once, not per component.
- 3.2.2. Verify `pre` and `table` components still render with their existing
  `overflow-x-auto` wrappers (no change expected).

3.3. Update `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`:

- 3.3.1. Line 521 bubble flex row: add `min-w-0` to the className string.
- 3.3.2. Line 527 bubble body `<div>`: add `min-w-0` to the className string.

3.4. Run the vitest suite — confirm the NEW tests pass (GREEN) and no
regressions in the broader suite.

## Phase 4 — Visual verification

4.1. Start `cd apps/web-platform && bun run dev` and visit `/dashboard` with a
seeded or staged set of conversations spanning single-digit and two-digit
relative times. Screenshot the before/after.

4.2. Visit a chat with a fixture message containing:

- A 200+ character bare URL.
- A wide GFM table.
- A 300-character single-line code block.
Confirm no horizontal scroll bar appears on the chat scroller.

4.3. Shut down the dev server.

## Phase 5 — Ship

5.1. Run `skill: soleur:compound` to capture learnings.

5.2. `git add` the changed component files, the plan, and the test files.

5.3. Commit with message
`fix(ui): stabilize inbox row width and chat markdown overflow (#2229)`.

5.4. Run `/ship` to push, open the PR with `Closes #2229` in the body, and
queue auto-merge.

5.5. After merge, run `skill: soleur:postmerge` to verify deployment.
