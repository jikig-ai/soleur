# Tasks: Command Center UI Bugs

## Phase 1: Fix Multi-Leader Session Key Collision (Bug 4)

- [x] 1.1 Update `sessionKey` in `apps/web-platform/server/agent-runner.ts` to accept optional `leaderId` parameter
- [x] 1.2 Update `startAgentSession` to pass `leaderId` to `sessionKey` and use leader-scoped key for `activeSessions`
- [x] 1.3 Update `abortSession` to iterate `activeSessions` entries matching `userId:conversationId:*` prefix when no `leaderId` is provided
- [x] 1.4 Update `abortAllUserSessions` to work with new key format (prefix still `userId:`)
- [x] 1.5 Update `activeSessions.delete` in `startAgentSession` finally block to use the correct leader-scoped key
- [x] 1.6 Add test: parallel `startAgentSession` calls for 3 leaders on same conversation produce 3 separate `activeSessions` entries
- [x] 1.7 Add test: `abortSession` without `leaderId` aborts all leader sessions for a conversation

## Phase 2: Remove Default CPO Boot (Bug 1)

- [x] 2.1 In `apps/web-platform/server/ws-handler.ts` `start_session` handler, skip `startAgentSession` call when `msg.leaderId` is falsy
- [x] 2.2 Verify `session_started` message is still sent to client (conversation creation + session_started reply must remain)
- [x] 2.3 For directed sessions (msg.leaderId is truthy), keep existing `startAgentSession` call
- [x] 2.4 Add test: auto-route session start does NOT trigger `stream_start` before first chat message
- [x] 2.5 Add test: directed @CPO session start still triggers agent boot with greeting

## Phase 3: Add Thinking Indicators (Bug 2)

- [ ] 3.1 Update `MessageBubble` in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` to detect empty-content assistant messages
- [ ] 3.2 Add pulsing dots animation component (3 dots with staggered animation, matching existing amber-500 color scheme)
- [ ] 3.3 Render thinking indicator inside the message bubble when `role === "assistant"` and `content === ""`
- [ ] 3.4 Verify indicator disappears naturally when first `stream` token sets content to non-empty string
- [ ] 3.5 Add test: `MessageBubble` with empty content and `role="assistant"` renders thinking indicator

## Phase 4: Markdown Rendering (Bug 3)

- [ ] 4.1 Install `react-markdown` AND `remark-gfm` in `apps/web-platform` (`bun add react-markdown remark-gfm`)
- [ ] 4.2 Regenerate `apps/web-platform/package-lock.json` via `npm install` (Dockerfile uses `npm ci`)
- [ ] 4.3 Create `MarkdownContent` component with `react-markdown`, `remark-gfm`, and custom `components` prop for Tailwind styling
  - [ ] 4.3.1 Style headings (h1-h3) with appropriate font sizes and margins
  - [ ] 4.3.2 Style tables with borders, padding, and neutral background for header row (requires `remark-gfm`)
  - [ ] 4.3.3 Style code blocks: detect `language-*` className for block vs inline code
  - [ ] 4.3.4 Style inline code with subtle background (amber-300 text on neutral-800 bg)
  - [ ] 4.3.5 Style lists (ul/ol) with proper indentation and markers
  - [ ] 4.3.6 Style bold/italic/links (links open in new tab with `target="_blank" rel="noopener noreferrer"`)
  - [ ] 4.3.7 Style blockquotes with left border and italic text
- [ ] 4.4 Configure security: `disallowedElements={["script", "iframe", "form", "object", "embed"]}` + `unwrapDisallowed` -- do NOT enable `rehype-raw`
- [ ] 4.5 Add `isStreaming` prop to `MessageBubble`, derived from `activeStreamsRef.current.has(msg.leaderId)` in the parent render
- [ ] 4.6 Implement three-state rendering in `MessageBubble`: thinking dots (empty content) -> plain text (streaming) -> markdown (complete)
- [ ] 4.7 Add test: markdown headings render as HTML heading elements
- [ ] 4.8 Add test: GFM table renders as HTML `<table>` with `<th>` and `<td>`
- [ ] 4.9 Add test: dangerous elements (script tags) are stripped but text content preserved (`unwrapDisallowed`)
- [ ] 4.10 Verify both lockfiles are committed (`bun.lock` + `package-lock.json`)
