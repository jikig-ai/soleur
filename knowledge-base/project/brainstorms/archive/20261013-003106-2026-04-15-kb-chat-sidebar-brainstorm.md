---
title: KB Chat Sidebar
date: 2026-04-15
status: complete
feature: kb-chat-sidebar
---

# KB Chat Sidebar — Brainstorm

## What We're Building

An in-context chat experience on the Knowledge Base document viewer. Today, the
"Chat about this" button navigates to a brand-new full-page chat conversation,
dropping the user out of the doc they were reading. Going forward, the button
opens a right-side chat panel on desktop (bottom sheet on mobile) that runs
alongside the doc. The user can select any passage in the rendered markdown and
send it into the chat as quoted context, so conversations can reference
specific parts of the document rather than the whole thing.

Value: preserves the "read and ask" loop without context-switching, enables
precision questions via selection-as-context, and resumes the same thread when
the user returns to a document later.

## Why This Approach

- `ConversationContext { path, type, content }` is already wired end-to-end
  through the WebSocket `start_session` flow (spec `feat-kb-conversation-context`
  shipped). Adding a sidebar reuses this plumbing; only a `selections` extension
  is new.
- A persistent panel in Next App Router must live in `layout.tsx` to survive
  file-to-file navigation (learning `ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md`).
  The sidebar goes in `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`,
  next to the existing file tree.
- Chat sub-components (`ChatInput`, `MessageBubble`, `AtMentionDropdown`,
  `ReviewGateCard`, `useWebSocket`) are already modular. The route shell
  (`chat/[conversationId]/page.tsx`, ~786 lines) is the only piece that's not
  embeddable. Extracting it into a `<ChatSurface variant="full" | "sidebar">`
  avoids forking chat into two surfaces that would drift forever.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Thread scope | One persistent thread per KB document (keyed on `context.path`) | Doc is the natural unit of context; reopening a file resumes its thread. |
| Reuse strategy | Extract `<ChatSurface variant>`; full chat page becomes a thin shell around it | Zero divergence between full-page and sidebar surfaces; review gates, @mentions, streaming all come for free. |
| Sidebar mount point | `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | App Router children swap on navigation; only the layout persists. |
| Default open state | Closed; opens on "Chat about this" click or selection pill; remembered per session | Viewer stays uncluttered for readers; discoverability preserved via the existing button. |
| Mobile behavior | Draggable bottom sheet (~60% viewport height) | No room for three panels on mobile; sheet lets user peek at the doc above. |
| Selection content types (v1) | Markdown only | PDF.js text-layer coords unstable after #2339 SSR fix; CSV/image selection has no clear UX pattern. PDF selection filed as follow-up. |
| Selection gesture | Floating "Add to chat" pill above the highlighted range | Matches Cursor/Notion AI; most discoverable; works equally well for desktop mouse and touch long-press. |
| Context protocol | Extend `ConversationContext` with `selections: Array<{text, startOffset?, endOffset?}>`; add WS message `type: "add_context"` for mid-conversation selection sends | URL params can't carry long selections; WS message fits the existing session model. |
| Legacy `?context=` URL | Keep supported; external/shared conversation links must keep working | Backwards-compat; no breaking change for anyone who bookmarked a link. |
| Conversation visibility | Same conversation records appear in `/dashboard/chat` inbox with a KB badge | One inbox, not two. |

## Open Questions

1. **Conversation continuity on nav.** When the user has the sidebar open on
   Doc A and navigates to Doc B, does the sidebar: (a) auto-switch to Doc B's
   thread, (b) show Doc A's thread with a "Now viewing Doc B — switch?" banner,
   or (c) close and re-open on Doc B closed? Default assumption: (a) auto-switch,
   same as the file tree's behavior. Confirm in UX gate.
2. **Selection during assistant streaming.** If the user selects text and hits
   the pill while an assistant response is mid-stream, do we queue the quote as
   the next user message, append to the current draft, or block the pill until
   streaming ends? Default: append to draft; don't send until user presses enter.
3. **Width.** Fixed 380px vs. resizable splitter. v1 = fixed; resizable is a
   follow-up.
4. **PDF selection.** Deferred. Track as a separate issue; revisit when
   PdfPreview's text-layer coords are stable (react-pdf upgrade or custom
   implementation).

## Domain Assessments

**Assessed:** Product, Marketing, Engineering

### Product (CPO)

**Summary:** Sidebar approach beats new-window for the KB "read-and-ask"
journey; doc-per-thread matches natural user mental model. Mobile, three-panel
cramping, and conversation-continuity-on-nav are the key UX risks. Scope is
~3–5 days; Phase A (sidebar + existing chat plumbing, no selection) alone
captures ~80% of the user value and is independently shippable. Recommend
filing as Phase 3 P3 (or Post-MVP) depending on Phase 3 close timing.

### Marketing (CMO)

**Summary:** Demoable "feel the difference" upgrade, not a headline feature.
Warrants a 20–30s screen recording + changelog entry + one social post. Maps to
"your knowledge, live" thread; framing should lead with the selection gesture,
not "AI chat." Instrument `kb.chat.opened` and `kb.chat.selection_sent` events
before ship for retention measurement.

### Engineering (CTO)

**Summary:** Refactor, don't iframe or rebuild. Extract `<ChatSurface variant>`
from the current chat page; KB sidebar embeds it. Extend `ConversationContext`
with `selections[]` and add a `"add_context"` WS message for mid-session sends.
Lazy-load via `next/dynamic({ ssr: false })` mirroring the PdfPreview pattern
(#2339) to keep the viewer bundle lean. Mobile, streaming-during-selection,
and the WS protocol extension are the sharp edges — none fatal, all spec-able.

## Capability Gaps

- **Reusable Drawer/Sheet primitive** — none exists in the codebase. Build as
  part of this feature (shadcn `Sheet` is the conventional choice) so future
  features (right-side panels elsewhere) can reuse it.
- **Inline/embeddable `<ChatSurface>`** — prerequisite extraction from the
  existing route-bound chat page. This is the biggest scope driver.
- **Floating selection-toolbar pattern** — no precedent in the repo. First
  implementation lands here; document the pattern for future reuse.
- **Per-doc conversation lookup API** — given a KB path, find-or-create a
  conversation. May or may not already exist in the chat inbox API; verify
  during spec phase.
