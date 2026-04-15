# Feature: KB Chat Sidebar

## Problem Statement

The "Chat about this" button on the KB document viewer navigates the user to a
full-page chat at `/dashboard/chat/new?msg=...&context=<path>`. This drops the
user out of the document they were reading — losing scroll position, breadcrumb
context, and the doc itself from sight. It also makes precise, passage-level
conversations impossible: there is no way to send a specific highlighted excerpt
as additional context to the chat.

Users want to read and ask without leaving the doc, and reference specific
passages in their questions.

## Goals

- Open chat as an in-context panel alongside the KB document (right sidebar on
  desktop, draggable bottom sheet on mobile).
- Enable text selection within the rendered markdown to be sent to chat as
  quoted context via a floating "Add to chat" pill.
- Preserve one thread per KB document, keyed on `context.path`; reopening a
  file resumes its thread.
- Ship without regressing the existing full-page chat route.

## Non-Goals

- Text selection inside PDF, image, CSV, or DOCX previews (markdown only for
  v1; PDF selection tracked as follow-up).
- Resizable sidebar splitter (fixed width in v1; resize as follow-up).
- Cross-document conversation threads (each doc is its own thread).
- Review-gate and attachment-upload parity cuts — sidebar ships with the same
  `<ChatSurface>` as the full page, so all affordances are automatically
  present.
- Changing the existing `?context=` URL contract for external/shared chat links.

## Functional Requirements

### FR1: In-context chat sidebar

- The KB viewer layout (`apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`)
  renders a right-side chat panel alongside the existing file tree and content
  area.
- The panel is closed by default and does not render its chat machinery until
  first opened.
- Clicking the existing "Chat about this" button opens the panel instead of
  navigating to `/dashboard/chat/new`.
- Open/closed state is remembered for the duration of the session.
- On desktop (≥ 768px): right-side panel, fixed width (380px).
- On mobile (< 768px): draggable bottom sheet at ~60% viewport height, with a
  handle to drag between collapsed/expanded/full-screen snap points.

### FR2: Per-document thread resolution

- On open, the panel resolves or creates a conversation keyed by the KB file's
  `context.path`.
- Switching to a different KB file auto-switches the open panel to that file's
  thread (no banner prompt, same behavior as file tree navigation).
- Closing and reopening the panel for the same doc resumes the existing thread.
- Threads appear in the `/dashboard/chat` inbox with a KB badge so users have
  one unified conversation list.

### FR3: Selection → quoted context

- While the rendered markdown article is visible and the user selects a
  non-empty text range, a floating "Add to chat" pill appears anchored above
  the selection range.
- Clicking the pill:
  - Opens the sidebar if closed.
  - Inserts the selected text into the sidebar's chat input as a quoted block
    (standard Markdown `>` blockquote prefix). The user can edit before
    sending.
- If the assistant is mid-stream when the pill is clicked, the quote is
  appended to the draft input (not auto-sent, not blocked).
- Selection handling is scoped to the markdown article element; it must not
  interfere with link clicks, anchor navigation, or text copy.

### FR4: Legacy URL compatibility

- The existing `/dashboard/chat/new?msg=...&context=<path>` flow continues to
  work for external or bookmarked links.
- No query-param shape changes to existing chat URLs.

## Technical Requirements

### TR1: Extract `<ChatSurface variant>`

- Refactor `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  into:
  - `components/chat/ChatSurface.tsx` — the embeddable component with a
    `variant: "full" | "sidebar"` prop that controls layout (full-height vs.
    sidebar-fit), header density, and any width-sensitive affordances.
  - `chat/[conversationId]/page.tsx` — thin route shell that renders
    `<ChatSurface variant="full" />` with `conversationId` from route params.
- Regressions in the full chat route are blockers; visual QA of the full chat
  route is required after extraction.

### TR2: Sidebar mount point in layout (not page)

- Sidebar renders in `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`,
  not `page.tsx`. Next.js App Router swaps `children` on every route change,
  which would unmount the panel on each KB file nav (see learning
  `ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md`).
- Layout passes the current document path to the sidebar via React context or
  a client-side URL hook; the panel uses this to resolve the correct thread on
  navigation.

### TR3: Extended `ConversationContext` wire protocol

- Extend `apps/web-platform/lib/types.ts`:

  ```ts
  interface ConversationContext {
    path: string;
    type: string; // "kb-viewer"
    content?: string;
    selections?: Array<{ text: string; startOffset?: number; endOffset?: number }>;
  }
  ```

- Add a new WebSocket client → server message for mid-conversation selection
  sends:

  ```ts
  type AddContextMessage = { type: "add_context"; selections: Array<{ text: string }> };
  ```

- WebSocket server (`ws-handler.ts`) accepts the new message and appends the
  selections to the active session's context, re-injecting into the subsequent
  LLM turn.
- The sidebar always passes `selections` through the chat input as a quoted
  block on send; the `add_context` message is only used for UI flows that
  attach context without an accompanying user message (v1.1 — not required for
  v1).

### TR4: Lazy-load the chat bundle

- Use `next/dynamic(() => import("@/components/chat/ChatSurface"), { ssr: false })`
  for the sidebar embedding, mirroring the PdfPreview pattern
  (`apps/web-platform/components/kb/PdfPreview.tsx`, introduced in #2339).
- Sidebar does not open the WebSocket connection until the panel is first
  opened by the user.

### TR5: Drawer/Sheet primitive

- Build a reusable `components/ui/Sheet.tsx` primitive (right-side on desktop,
  bottom-sheet on mobile) following the shadcn Sheet pattern, so future
  features can reuse it. Consumes viewport width via a media-query hook to
  pick its orientation.

### TR6: Selection-toolbar primitive

- Build `components/markdown/SelectionToolbar.tsx`:
  - Listens to `document.selectionchange`, scoped to a passed `articleRef`.
  - Portal-renders a floating button anchored at the top edge of the selection
    `Range.getBoundingClientRect()`.
  - Dismisses on selection collapse, click-outside, and Escape.
- Keep the implementation generic so other document viewers (future) can
  reuse it.

### TR7: Layout hardening for narrow column

- Apply `min-w-0` at every flex-item level inside the sidebar and wrap
  `<Markdown>` in `<div className="min-w-0 [overflow-wrap:anywhere]">` to
  prevent long URLs, code, or tables from expanding the panel beyond its
  fixed width (see learning
  `ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`).

### TR8: Analytics events

- Emit the following events via the existing analytics layer:
  - `kb.chat.opened` — panel opened (with `path` dimension)
  - `kb.chat.selection_sent` — user clicked "Add to chat" pill
  - `kb.chat.thread_resumed` — opening the sidebar resolved to an existing
    conversation rather than a new one
- Events are required for retention measurement (per CMO assessment) and must
  ship with the feature, not as a follow-up.

### TR9: Accessibility

- Panel is a `<aside>` with `aria-label="Chat about this document"`.
- Escape closes the panel when focused inside it.
- Focus moves to the chat input on open, and returns to the trigger button on
  close.
- Floating selection pill is keyboard-activatable via a shortcut (e.g.,
  `Cmd/Ctrl+Shift+L` sends the current selection to chat without requiring
  the pill click) so the feature is usable without a mouse.

### TR10: Feature flag

- Gate the sidebar behind a feature flag so the full-page flow remains the
  default until QA and founder sign-off. Flag name: `kb_chat_sidebar`. Remove
  the flag and the legacy "Chat about this" → new-window fallback in a
  follow-up PR after one week of soak.
