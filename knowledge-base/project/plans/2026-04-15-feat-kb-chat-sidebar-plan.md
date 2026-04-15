---
title: KB Chat Sidebar — Implementation Plan
date: 2026-04-15
status: draft
feature: feat-kb-chat-sidebar
issue: 2345
branch: kb-chat-sidebar
worktree: .worktrees/kb-chat-sidebar/
pr: 2347
brainstorm: knowledge-base/project/brainstorms/2026-04-15-kb-chat-sidebar-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-chat-sidebar/spec.md
wireframes: knowledge-base/project/specs/feat-kb-chat-sidebar/wireframes.pen
---

# Plan: KB Chat Sidebar (#2345)

## Overview

Ship an in-context chat panel on the KB document viewer. On desktop it mounts
as a fixed 380px right-side panel inside `dashboard/kb/layout.tsx`; on mobile
it mounts as a draggable bottom sheet. Text selected inside the rendered
markdown article surfaces a floating **"Quote in chat"** pill that quotes the
selection into the chat input. Each KB document gets one persistent thread
keyed on its path; re-opening the file resumes the thread with a
"Continuing from [date]" banner.

The feature is a composition-and-refactor job, not a greenfield chat build:
the existing `[conversationId]/page.tsx` chat route is extracted into a
`<ChatSurface variant="full" | "sidebar">` component that both the full-page
route and the new sidebar embed. The WebSocket `ConversationContext` protocol
gains a `selections[]` field plus two new message variants
(`resume_or_create_by_context`, `add_context`). Legacy `?context=` URLs keep
working.

## Known Blockers

1. **Milestone conflict — RESOLVED 2026-04-15.** Issue #2345 promoted from
   `Post-MVP / Later` to `Phase 3: Make it Sticky` (row 3.23 in roadmap,
   P3 priority). `gh issue edit 2345 --milestone "Phase 3: Make it Sticky"`
   + roadmap update committed in same action (commit `4561b1f4`) per
   AGENTS.md `wg-when-moving-github-issues-between`.

## Research Reconciliation — Spec vs. Codebase

Three spec claims diverge from the codebase state and require plan-level
additions beyond "implement the spec":

| Spec claim | Reality | Plan response |
|---|---|---|
| TR8: "emit via the existing analytics layer" | No frontend analytics abstraction exists. Plausible is server-side-only (`server/service-tools.ts`). | Build `lib/analytics-client.ts` + `/api/analytics/track` route that forwards to Plausible. Provision goals via Plausible API before ship. Graceful skip on 402 (free tier). |
| TR10: "gate behind feature flag `kb_chat_sidebar`" | No FF system exists. | Use `NEXT_PUBLIC_KB_CHAT_SIDEBAR` env var set via Doppler (`dev`, `prd` configs). Matches existing `NEXT_PUBLIC_*` precedent. |
| FR2: "resolves or creates a conversation keyed by `context.path`" | No lookup API. `conversations` table has no `context_path` column. | Add `context_path TEXT` column + UNIQUE partial index on `(user_id, context_path) WHERE context_path IS NOT NULL`. Extend `start_session` with optional `resumeByContextPath` parameter — server looks up existing row or creates pending. No new WS message type (simpler than a dedicated `resume_or_create_by_context`; one code path for abort/validate/rate-limit). Backfill pre-migration rows as a separate follow-up migration if legacy shape matches. |

Other delta notes:

+ `MessageBubble` + `ReviewGateCard` are inlined in `chat/[conversationId]/page.tsx` (L476, L654), not already in `components/chat/`. Extraction of `ChatSurface` lifts them into `components/chat/message-bubble.tsx` and `components/chat/review-gate-card.tsx`.
+ `useWebSocket` lives in `apps/web-platform/lib/ws-client.ts`, not `hooks/`.
+ No `/dashboard/chat` inbox route exists — the inbox is on `/dashboard` home via `useConversations`. The "KB badge" per FR2 is a rendering change in `components/inbox/conversation-row.tsx`.
+ No `useMediaQuery` / `useBreakpoint` hook exists. Build alongside `Sheet`, mirroring `app/(dashboard)/layout.tsx:158-165`.
+ KB viewer renders in both markdown and non-markdown branches of `kb/[...path]/page.tsx` (L120–128, L157–165). Sidebar opener must land in **both** branches; selection is markdown-only.

## Research Findings (short form)

### Institutional learnings that shape the plan

+ `ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md` → sidebar mounts directly inside `kb/layout.tsx`, never through `children`.
+ `ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md` → apply `min-w-0` at every flex level in the sidebar; wrap chat markdown in `[overflow-wrap:anywhere]`.
+ `2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md` → `selections[]` MUST be validated in `server/context-validation.ts` in `start_session` before side effects.
+ `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` → `resume_or_create_by_context` must respect the "pending conversation" state (no DB row until first message). Audit `resume_session` + `close_conversation` for `selections[]` clearing.
+ `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` → adding `WSMessage` variants requires running `tsc --noEmit` to update every exhaustive switch.
+ `2026-03-27-ws-session-race-abort-before-replace.md` → new handler that changes session state calls `abortActiveSession(userId, session, "superseded")` **before** any `await`.
+ `2026-03-28-csp-connect-src-websocket-scheme-mismatch.md` → same WS host as current chat = no CSP change. Verify during QA.
+ `2026-04-14-next-dynamic-testing-pattern-vitest.md` → mock `next/dynamic` via `React.lazy` + `Suspense` in tests.
+ `2026-04-06-chat-page-test-determinism-and-coverage.md` → RTL negative assertions use `waitFor`, not `setTimeout`.
+ `2026-02-17-backdrop-filter-breaks-fixed-positioning.md` → dashboard header may create a containing-block trap. Verify floating pill and bottom-sheet are not trapped.
+ `2026-04-15-kb-share-binary-files-lifecycle.md` → sidebar opener lands in BOTH markdown and non-markdown branches of `kb/[...path]/page.tsx`.

### Community / functional discovery

No overlap — build as planned. No community skill generates
selection-anchored toolbars, mobile-adaptive sheet primitives, or WebSocket
`add_context` scaffolding at trust tier 1/2.

## Implementation Phases

**Phase A (1–3)** = ship-viable Phase-A slice per brainstorm (sidebar + existing
chat plumbing, no selection). Includes feature flag plumbing and
`kb.chat.opened` emit so it's actually demoable to users, not an
under-the-hood primitive dump (per CPO review). **Phase B (4)** adds
selection → quote. **Phase C (5–7)** wires remaining analytics, a11y, and
hardens for ship. Phase 5 (the earlier empty-scope placeholder for standalone
`add_context` UI) has been collapsed; the WS handler stays but UI surface
lands as a tracked follow-up issue.

### Phase 1 — Primitives

Goal: land reusable pieces with zero visible behavior change.

1.1 `apps/web-platform/hooks/use-media-query.ts` — new hook. Template: mirror
    `app/(dashboard)/layout.tsx:158-165`. Subscribe on mount, cleanup on
    unmount, return boolean. SSR-safe (return `false` when `window` undefined).

1.2 `apps/web-platform/components/ui/sheet.tsx` — new primitive. Consumes
    `useMediaQuery("(min-width: 768px)")`.

    - **Desktop:** right-side fixed-width panel (`position: fixed`, `right: 0`,
      `top: <header-height>`, `width: 380px`).
    - **Mobile:** bottom-sheet with **three snap points with explicit
      semantics:**
      - `collapsed` (~20vh, handle visible) — peek state user can expand
        back from
      - `default` (~60vh) — primary reading state
      - `full` (100dvh) — immersive chat
    - **Drag-to-close semantics:** if the user drags below `collapsed`'s
      snap threshold (i.e., `<10vh`), the sheet dismisses via `onClose`.
      0vh does NOT mean "collapsed with handle" — sheet always has either
      one of three snap points visible OR is closed. (Resolves SpecFlow
      gap #3.)
    - Props: `open`, `onClose`, `side?: "right" | "bottom"` (auto from
      breakpoint if omitted), `aria-label`, `onSnapChange?`.
    - Uses a portal rooted at `document.body`. Verify no `backdrop-filter`
      ancestor traps `position: fixed` (per learning).

1.3 Extract `<ChatSurface variant="full" | "sidebar">` from
    `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`:

    - New file: `apps/web-platform/components/chat/chat-surface.tsx` —
      embeddable. Owns `useWebSocket`, message list, input, review-gate, all
      hooks and state. Accepts `{ conversationId, variant, onClose?,
      initialContext?, onThreadResumed?: (conversationId, createdAt) => void }`.
    - New file: `apps/web-platform/components/chat/message-bubble.tsx` —
      lifted from page.tsx:476–577 (plus `renderBubbleContent` L582–643,
      `ThinkingDots` L461–469, `ToolStatusChip` L645–652). **User bubble's
      markdown rendering policy:** enable `react-markdown` on user bubbles
      so sent blockquotes render as blockquotes (not raw `>` text). Today
      user bubbles are plain text — this changes to parsed markdown with
      the same `min-w-0 [overflow-wrap:anywhere]` wrapper. (Resolves
      SpecFlow gap #6.)
    - New file: `apps/web-platform/components/chat/review-gate-card.tsx` —
      lifted from page.tsx:654–760.
    - New file: `apps/web-platform/components/chat/status-indicator.tsx` —
      lifted from page.tsx:762–786.
    - Updated `chat/[conversationId]/page.tsx` — becomes a ~30-line shell
      that reads `conversationId` from route params and renders
      `<ChatSurface variant="full" conversationId={id} />`.
    - `variant` branches:
      - Root wrapper: `variant === "full" ? "h-[100dvh] md:h-full" : "h-full"`.
      - Header block (L225–254): rendered only when `variant === "full"`; sidebar has its own compact header (see 2.7 — filename-as-title, `JetBrains Mono`, close button, "↗ Open full" link when thread ≥ 10 messages).
      - Width wrappers (L328, L406, L439): `variant === "full" ? "max-w-3xl mx-auto" : "max-w-none"`.
      - Mobile back arrow (L228–236) and `safe-bottom` padding (L405): `variant === "full"` only.
      - Desktop-only status bar (L387–402): `variant === "full"` only.
      - **Code-block treatment in sidebar:** wrap (not scroll) — combined
        with `[overflow-wrap:anywhere]`. Horizontal scroll inside a 380px
        panel is unreadable. (Resolves UX concern #1.)

1.4 Test the extraction:
    - Update `apps/web-platform/test/chat-page.test.tsx` to mount
      `<ChatSurface variant="full" />` under the same mock setup.
    - Add `apps/web-platform/test/chat-surface-sidebar.test.tsx` — renders
      `<ChatSurface variant="sidebar" />`, asserts header is compact, no
      `max-w-3xl`, no `safe-bottom`, user bubbles render blockquotes as
      blockquotes.
    - Run: `cd apps/web-platform && node node_modules/vitest/vitest.mjs run`.

**Exit criterion:** full-page chat route (`/dashboard/chat/<id>`) is visually
and functionally identical to main. `<ChatSurface variant="sidebar">` renders
in isolation without crashing.

### Phase 2 — KB sidebar shell + feature flag + first analytics emit

Goal: sidebar mounts, opens via "Ask about this document" button, survives KB
navigation, resumes per-doc thread. Flag-gated and demoable.

2.1 Database migration (Supabase) — **split into two files** so backfill
    failure doesn't roll back the schema change:

    - **Schema migration:** `supabase/migrations/20260415a_add_context_path_to_conversations.sql`:

      ```sql
      ALTER TABLE public.conversations
        ADD COLUMN context_path TEXT;

      -- UNIQUE partial index enforces one conversation per (user, doc path).
      -- Combined with ON CONFLICT handling in start_session's
      -- resumeByContextPath lookup, this resolves the two-tab race:
      -- the second tab's create attempt sees the first tab's row.
      CREATE UNIQUE INDEX conversations_context_path_user_uniq
        ON public.conversations (user_id, context_path)
        WHERE context_path IS NOT NULL;
      ```

    - **Backfill migration (separate, conditional):**
      `supabase/migrations/20260415b_backfill_context_path.sql`. Only
      applied if staging verification shows `messages.metadata->context->>'path'`
      is populated for legacy `?context=` threads. Otherwise, accept that
      pre-migration KB threads are un-badged and skip this file entirely
      (noted in rollout checklist step 3). The backfill SQL:

      ```sql
      UPDATE public.conversations c
      SET context_path = (
        SELECT (m.metadata->'context'->>'path')
        FROM public.messages m
        WHERE m.conversation_id = c.id
          AND m.role = 'user'
          AND m.metadata->'context'->>'path' IS NOT NULL
        ORDER BY m.created_at ASC
        LIMIT 1
      )
      WHERE c.context_path IS NULL;
      ```

      **If the UNIQUE index already exists and backfill would violate it**
      (multiple legacy conversations sharing a path for one user), wrap
      the UPDATE with a DISTINCT-aware subquery that picks the most recent
      row only. Verify before running.

    - Update `apps/web-platform/lib/types.ts` `Conversation` interface to
      add `context_path?: string | null`.

2.2 `apps/web-platform/lib/types.ts` — extend `start_session` to accept an
    optional `resumeByContextPath`:

    ```ts
    | { type: "start_session"; leaderId?: DomainLeaderId; context?: ConversationContext; resumeByContextPath?: string }
    ```

    No new message types in v1. `add_context` and `ConversationContext.selections[]`
    are deferred to v1.1 — v1 delivers selections as quoted blockquotes in
    the user message text (per spec TR3: "The sidebar always passes
    `selections` through the chat input as a quoted block on send"). Server
    has no v1 work to do with `selections[]` as a separate field; all the
    content arrives inline in the user message.

    Add `startSession({ leaderId?, context?, resumeByContextPath? })` entry
    point on `UseWebSocketReturn` (or extend the existing `startSession`
    signature).

2.3 `apps/web-platform/server/context-validation.ts` — no v1 change. The
    existing path/type/content validation already applies to `start_session`
    context. Defer `selections[]` schema to v1.1 when `add_context` ships.

2.4 `apps/web-platform/server/ws-handler.ts` — extend the existing
    `case "start_session":` at L284 (not a new case) to handle the
    `resumeByContextPath` parameter:

    - If `msg.resumeByContextPath` is set AND no explicit `conversationId`
      in context: validate path (same regex), query `conversations WHERE
      user_id = ? AND context_path = ? LIMIT 1` (UNIQUE index guarantees
      at most one row). If found, emit `session_resumed { conversationId,
      resumedFromTimestamp: updated_at, messageCount }` and skip pending
      creation. If not found, fall through to the existing pending-creation
      path with `contextPath` stored on the pending record — on first
      message send, the `context_path` column is written with `ON CONFLICT
      DO NOTHING` on the UNIQUE index to handle two-tab races gracefully.
    - The existing `start_session` abort-active + validate-context
      invariants (ws-handler.ts:302) apply unchanged. No new abort/validate
      code path. (Resolves architecture finding #2 + simplicity finding #3:
      one code path, not three.)

2.5 `apps/web-platform/server/agent-runner.ts` — no v1 change required
    (selections arrive in user message text; system-prompt builder sees
    them there without special handling). Defer selections-specific
    prompt-building to v1.1 when `add_context` ships.

2.6 `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — mount the
    sidebar. Insert a third flex child inside the root `<div className="flex
    h-full">` at L136:

    ```tsx
    const KbChatSidebar = dynamic(
      () => import("@/components/chat/kb-chat-sidebar").then(m => m.KbChatSidebar),
      { ssr: false, loading: () => null }
    );

    // …inside KbLayout:
    const [sidebarOpen, setSidebarOpen] = useState(false);
    const pathname = usePathname();
    const contextPath = deriveContextPathFromPathname(pathname);
    const flagEnabled = process.env.NEXT_PUBLIC_KB_CHAT_SIDEBAR === "1";

    return (
      <KbContext value={ctxValue}>
        <KbChatContext value={{ open: sidebarOpen, openSidebar: () => setSidebarOpen(true), closeSidebar: () => setSidebarOpen(false) }}>
          <div className="flex h-full">
            <aside>…file tree…</aside>
            <div className="min-w-0 flex-1 …">{children}</div>
            {flagEnabled && (
              <KbChatSidebar
                open={sidebarOpen}
                onClose={() => setSidebarOpen(false)}
                contextPath={contextPath}
              />
            )}
          </div>
        </KbChatContext>
      </KbContext>
    );
    ```

    `KbChatContext` is separate from `KbContext` to keep existing tree
    traversal consumers unaffected. (Feature flag plumbing moved into
    Phase 2 per CPO blocking finding.)

2.7 New component:
    `apps/web-platform/components/chat/kb-chat-sidebar.tsx` — wraps
    `<Sheet>` around `<ChatSurface variant="sidebar">`.

    **Internal state:** current `conversationId` (null until resolved),
    `resumedFrom: null | { timestamp, messageCount }`, `resolving: boolean`,
    `resolveError: null | string`.

    **Lifecycle:**

    - On open OR on `contextPath` change while open, sets `resolving = true`,
      calls `startSession({ resumeByContextPath: contextPath })`. On the
      resulting `session_resumed` or `session_started` event:
      `conversationId` swaps, `resumedFrom` populated if `resumedFromTimestamp`
      present, `resolving = false`.
    - **Loading state:** while `resolving`, render a compact skeleton
      (header with filename, placeholder "Resolving thread…" text, no
      input). (Resolves SpecFlow gap #1.)
    - **Timeout:** if no response in 10s, render error state with "Couldn't
      connect. Retry?" button. Retry re-sends. (Resolves SpecFlow gap #1.)
    - **Close-mid-stream behavior:** closing the panel while
      `isStreaming` aborts the active WS session via
      `abortActiveSession(userId, session, "user_closed")`. Reopening the
      panel on the same doc resumes the existing conversation (the
      user-authored messages already persist; partial assistant response
      is discarded). (Resolves SpecFlow gap #2.)
    - **Doc-switch-while-open:** when `contextPath` changes, preserve the
      current draft in a `sessionStorage`-backed `drafts[contextPath]` map.
      Re-entering Doc A restores Doc A's draft. (Resolves CPO finding #3
      + SpecFlow gap #8 follow-on.)

    **Header:** filename in `JetBrains Mono` at 380px (truncate with
    ellipsis if overflow); "↗ Open full" link to `/dashboard/chat/<id>`
    when `messageCount ≥ 10`; close button with
    `aria-label="Close panel"`. (Per copywriter + ux-design-lead.)

    **Thread-resumed banner:** if `resumedFrom` is populated, render a
    subtle banner "Continuing from <formatted date>" at top of message
    list. **Auto-dismisses on the first new user message sent.** (Per
    copywriter + UX lead.)

    **Empty state:** when `messages.length === 0` and not resolving,
    render:

    - Heading: "Ask about this document."
    - Subtext: "Select any passage to quote it, or type a question below."

    (Per copywriter.)

    **Analytics emits:**

    - On successful resolve with no resumedFrom → `track("kb.chat.opened",
      { path: contextPath })` (first analytics emit — enables demoability;
      moved from former Phase C per CPO).
    - On successful resolve with resumedFrom → `track("kb.chat.opened",
      { path })` + `track("kb.chat.thread_resumed", { path })`.

    Lazy-loaded via `next/dynamic` per TR4 (mirrors
    `components/kb/file-preview.tsx:1-16`).

2.8 `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` —
    both "Chat about this" buttons (L120–128 and L157–165) are replaced
    with a **stateful trigger** that reads `KbChatContext`:

    - If `conversationId` has been resolved and `messageCount > 0`: label
      = "Continue thread" with a subtle unread dot.
    - Otherwise: label = "Ask about this document".
    - `onClick` calls `kbChatContext.openSidebar()` **when
      `NEXT_PUBLIC_KB_CHAT_SIDEBAR === "1"`**, otherwise keeps the legacy
      link to `/dashboard/chat/new?msg=...&context=...`.

    (Copy per copywriter; stateful behavior per UX + copywriter.)

2.9 Inbox badge: `apps/web-platform/components/inbox/conversation-row.tsx`
    — when `conversation.context_path` is non-null, render a "KB" badge
    alongside the leader avatar. Uses existing `Badge` component
    (`components/ui/badge.tsx`).

2.10 Session state persistence: `sidebarOpen` and `drafts[contextPath]`
     stored in `sessionStorage` so panel state and in-flight drafts
     survive within a tab session (per FR1 "remembered per session"
     + CPO draft-preservation finding).

**Exit criterion:** With flag on, clicking the trigger on any KB doc
opens the sidebar, resolves or creates a thread, persists across
doc-to-doc nav with draft preservation, and emits `kb.chat.opened` +
`kb.chat.thread_resumed` to Plausible. With flag off, legacy
`/dashboard/chat/new` flow works unchanged. Full-page chat route
unchanged.

### Phase 3 — Narrow-column hardening + inbox/visual QA

3.1 Apply `min-w-0` at every flex-item level inside the sidebar
    (per TR7 + learning). Verify with long-URL and code-block test
    fixtures. **Done.** `variant` threaded through `ChatSurface` →
    `MessageBubble` → `MarkdownRenderer`; sidebar variant swaps
    `<pre>` from `overflow-x-auto` to
    `whitespace-pre-wrap break-words [overflow-wrap:anywhere]`. Every
    flex ancestor of message content now has `min-w-0`. Contract
    tested in `test/chat-surface-sidebar-wrap.test.tsx`
    (long URL + long code-block fixtures, plus a flex-ancestor audit
    walker). Full-variant scroll behavior preserved.

3.2 Verify `next/dynamic` bundle-split: inspect
    `.next/server/app/(dashboard)/dashboard/kb/layout.js` chunk after
    build; ChatSurface must not be in the synchronous layout bundle.
    **Done.** `next build` succeeded; `/dashboard/kb/[...path]` route
    = 5.79 kB / 276 kB First Load JS. KB layout chunk
    (`.next/static/chunks/app/(dashboard)/dashboard/kb/layout-*.js`,
    32 kB) contains zero references to `ChatSurface` / `MessageBubble`
    / `MarkdownRenderer`. Chunk `3786-*.js` (47 kB) holds ChatSurface
    and is loaded via `Promise.all([r.e(...), ...]).then(r.bind(r,787))`
    — the canonical webpack lazy pattern emitted by `next/dynamic`.

3.3 **Attach flow verification at 380px** — the chat input has an attach
    button (imported `AttachmentDisplay`). Verify file-picker + attachment
    preview card fits and is usable in the narrow sidebar. If not, scope
    a follow-up to tune the attach UX for sidebar width. (Per UX concern
    #6.) **Done (code review).** Paperclip button is `h-[44px] w-[44px]
    shrink-0`; textarea is `flex-1`; preview strip is `flex flex-wrap
    gap-2`; filename is `max-w-[120px] truncate`; progress bar is `w-16`.
    At 380px sidebar with `px-4` input padding, usable width = 348px →
    44px (attach) + 8px (gap) + 296px (textarea). Two attachment chips
    fit per row. No follow-up needed.

3.4 Visual QA checklist (Playwright screenshot pass):
    sidebar opens at 1440px, 1024px, 768px, 375px; markdown with long
    code block wraps (not scrolls) without overflow; file-tree + content
    + sidebar all visible at ≥1024px; mobile bottom-sheet snap points
    work; thread-resumed banner renders and auto-dismisses. **Deferred
    to /qa phase.** Running a real-browser pass requires Doppler-scoped
    dev server + Supabase OAuth login, which the `/qa` skill handles
    once for the full pipeline. Contract-level wrap/min-w-0 behavior is
    covered by vitest (see 3.1); bundle-split is empirically verified
    (see 3.2); Rollout Plan step 5 ("Manual QA on staging with flag on")
    covers the real-device sweep before the prd flag flip.

**Exit criterion:** Phase A value ships. The brainstorm's "80% value"
slice is independently demoable with flag flip. **Met.** All contract
tests pass (1419/1419 relevant; 1 skipped unchanged); tsc clean;
bundle-split verified; narrow-column wrap verified.

### Phase 4 — Text selection → quoted context

Goal: selected markdown text becomes a quoted input in the sidebar.

4.1 `apps/web-platform/components/kb/selection-toolbar.tsx` — new
    component (placed under `kb/` because the `articleRef` scoping and
    iOS-Safari share-menu suppression are KB-article-specific; moving it
    to a generic `components/markdown/` dir would fragment the layout for
    a single file):

    - Props: `{ articleRef: RefObject<HTMLElement>, onAddToChat: (text:
      string) => void, maxBytes?: number }`.
    - Subscribes to `document.selectionchange`.
    - Checks `selection.anchorNode` / `focusNode` are both descendants
      of `articleRef.current` (ignore selections elsewhere).
    - **Client-side preflight:** selection text is measured
      (`new Blob([text]).size`). If `> maxBytes` (default 8KB matching
      server cap), pill renders in disabled state with tooltip "Selection
      too long — shorten to under 8KB". (Resolves SpecFlow gap #4.)
    - Renders a floating button via `createPortal(…, document.body)`
      anchored at `range.getBoundingClientRect().top - buttonHeight - 8px`.
      Label: **"Quote in chat"** with `⌘⇧L` shortcut hint badge (per
      copywriter).
    - Dismisses on selection collapse, click-outside, and `Escape`.
      **Escape priority:** pill's Escape handler calls
      `event.stopPropagation()` so sidebar's Escape doesn't also close
      the panel. Escape thus dismisses the pill only; a second Escape
      (if focus inside panel) closes the panel. (Resolves SpecFlow gap
      #10.)
    - **iOS Safari handling:** apply `user-select: text` to
      `articleRef.current`, suppress `contextmenu` event on selection
      when pill is visible (to avoid the native share menu competing
      with the pill). Test manually on iOS Safari. (Resolves UX
      concern #3.)
    - Does NOT interfere with link clicks (use `pointerdown` handler with
      delay/click-distinction; do not `preventDefault`). Does NOT interfere
      with text copy (never modify the selection).

4.2 `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` —
    wrap the markdown `<article>` (L170) with a ref, render
    `<SelectionToolbar articleRef={ref} onAddToChat={kbChatContext.submitQuote}>`
    conditionally when `isMarkdown === true` and feature flag is on.
    The `submitQuote(text)` handler **lives on `KbChatContext`**, not in
    `ChatInput`. It calls `openSidebar()` and forwards the text to the
    sidebar's chat-input ref. This keeps `ChatInput` free of KB-domain
    knowledge — it stays reusable by the full-page route where
    `KbChatContext` doesn't exist.

4.3 `apps/web-platform/components/chat/chat-input.tsx` — accept an
    optional imperative handle (via `forwardRef` + `useImperativeHandle`)
    exposing `insertQuote(text: string)` that:

    - Prepends `> <text>\n\n` to the current draft (or replaces cursor
      position if there's an active selection in the textarea).
    - Does NOT auto-send; user edits and presses Enter.
    - If assistant is mid-stream: appends to draft (per brainstorm Open
      Question #2 default).
    - **Post-quote confirmation (mobile + desktop):** after insert, scroll
      textarea into view (`scrollIntoView({ block: "nearest" })`) and
      apply a 400ms `ring-2 ring-amber-400` flash on the inserted
      blockquote line. Guarantees the user sees the quote landed,
      especially on mobile bottom-sheet where input may be below the
      fold. (Resolves SpecFlow gap #9.)
    - **Mobile bottom-sheet: referenced passage handling.** On mobile,
      if the sheet opens from `collapsed → default` due to pill click,
      and the selected passage would be hidden under the sheet, render
      a "Referenced passage" chip at the top of the sheet (first 60
      chars of selection + ellipsis) so the user has context of what
      they quoted. Chip dismisses on scroll or first new message. (Per
      UX concern #8.) **The chip lives in `KbChatSidebar`, not
      `ChatInput`** — sidebar-specific UX doesn't leak into the reusable
      input component.
    - `track("kb.chat.selection_sent", { path })` emits from
      `KbChatSidebar`'s submit hook (not from ChatInput — same domain
      leakage concern), when a message containing a blockquote is sent.

    `ChatInput` is not aware of `KbChatContext`. The flow is:
    `SelectionToolbar → KbChatContext.submitQuote(text) →
    KbChatSidebar.handleQuote(text) { openSidebar();
    chatInputRef.current?.insertQuote(text); }`.

4.4 Keyboard shortcut: `Cmd/Ctrl+Shift+L` while focus is anywhere inside
    the markdown article triggers `addQuoteToChat(window.getSelection()
    .toString())` (per TR9 a11y requirement).

4.5 Chat input placeholder (sidebar variant): "Ask about this
    document — ⌘⇧L to quote selection" (⌘⇧L / Ctrl+Shift+L detected at
    render). Per copywriter.

**Exit criterion:** select text in a KB markdown file → "Quote in chat"
pill appears → click pill → sidebar opens → input contains `> <quoted text>`
as a blockquote with flash confirmation → editable → Enter sends with
the quote as the first block. iOS Safari works.

### Phase 5 — Analytics hardening

(Former Phase 6; former Phase 5 collapsed into Phase 2 per CPO.)

5.1 `apps/web-platform/lib/analytics-client.ts` — new module:

    ```ts
    export async function track(goal: string, props?: Record<string, unknown>) {
      try {
        await fetch("/api/analytics/track", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ goal, props }),
        });
      } catch { /* fail-soft */ }
    }
    ```

5.2 `apps/web-platform/app/api/analytics/track/route.ts` — new route.
    Forwards to Plausible custom goal endpoint. Per learnings
    (`2026-04-02-plausible-api-response-validation`, `2026-03-30-plausible-http-402`),
    validate JSON response shape and treat HTTP 402 as graceful skip.

    **Auth: same-origin check + IP rate-limit, not session cookie.** The
    route forwards to a third-party goal API with no PII. Session-cookie
    auth would over-constrain the route (future anon surfaces would need
    to fork or loosen it). Enforce `Origin` header ∈ allow-list (self-host
    + Vercel preview URLs) and a per-IP rate cap (e.g., 120 req/min).

    **Omit user_id entirely** from props — do not hash. Hashing without a
    documented salt rotation strategy produces a stable identifier in a
    third-party tool that's hard to roll back. v1 ships with no user
    dimension; add hashed-with-rotating-salt in a future iteration if
    funnel analysis demands it.

5.3 Provision three Plausible goals via API before first emit
    (per `2026-03-13-plausible-goals-api-provisioning-hardening`):
    `kb.chat.opened`, `kb.chat.selection_sent`, `kb.chat.thread_resumed`.
    Provisioning is a one-time ops step; record in
    `knowledge-base/marketing/analytics/plausible-goals.md` (or existing
    equivalent) so it's discoverable.

5.4 Confirm all three emits wired from Phase 2 (kb.chat.opened,
    kb.chat.thread_resumed — 2.7) and Phase 4 (kb.chat.selection_sent —
    4.3) actually reach the `/api/analytics/track` route. End-to-end
    test: open panel in staging → check Plausible dashboard → selection
    sent → check dashboard → resumed thread → check dashboard.

### Phase 6 — Accessibility + feature flag rollout

6.1 Panel accessibility (TR9, enhanced per copywriter + UX):

    - `<aside aria-label="Document conversation">` (or
      `aria-label={`Conversation about ${filename}`}` if filename known).
    - `Escape` key closes panel when focus is inside it (after pill has a
      chance to consume it first — see 4.1 Escape priority).
    - Focus moves to `ChatInput`'s textarea on open, placeholder shows
      shortcut hint.
    - Focus returns to trigger on close.
    - Floating selection pill: `role="button"`, keyboard-focusable,
      `Enter`/`Space` activates.
    - `Cmd/Ctrl+Shift+L` shortcut documented in input placeholder +
      pill tooltip.
    - Mobile sheet drag-handle: `aria-label="Resize panel"`, tooltip
      "Drag to expand".
    - Close-button `aria-label="Close panel"`.

6.2 Feature flag flip path (already plumbed in Phase 2):

    - Doppler `dev` config: `NEXT_PUBLIC_KB_CHAT_SIDEBAR=1` from day one so
      QA can use the sidebar.
    - Doppler `prd` config: `NEXT_PUBLIC_KB_CHAT_SIDEBAR=0` at merge time.
    - Flip prd to `1` after manual QA + founder sign-off.
    - Follow-up issue: remove the flag and the legacy "Ask about this
      document" → new-window fallback one week after prd flip.

### Phase 7 — Tests + QA

7.1 Unit/component tests (vitest, happy-dom) — see Test Scenarios below.

7.2 Playwright browser QA — run existing `skill: soleur:test-browser`
    against the KB viewer routes. Screenshots at 1440, 1024, 768, 375
    viewport widths. **Test BOTH flag states** — flag off must fall back
    to legacy `/dashboard/chat/new` navigation. (Per UX concern #5.)

7.3 Cross-browser selection QA (Chrome, Safari, iOS Safari). **Budget
    explicit QA time — no prior learnings on selection behavior in this
    codebase.** Verify iOS share-menu suppression works.

7.4 Full-chat-route regression: `/dashboard/chat/<existing-id>` must look
    and behave identical to main. Screenshot-diff or manual visual
    comparison.

7.5 Concurrent-tab scenario: open Doc X in two tabs, both open sidebar,
    send messages in both. Verify last-writer-wins on `resume_or_create_
    by_context` (`ORDER BY updated_at DESC LIMIT 1`); verify no duplicate
    conversations created; verify Tab A streaming aborts gracefully when
    Tab B supersedes.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/hooks/use-media-query.ts` | breakpoint hook |
| `apps/web-platform/components/ui/sheet.tsx` | drawer/sheet primitive |
| `apps/web-platform/components/chat/chat-surface.tsx` | extracted embeddable chat |
| `apps/web-platform/components/chat/message-bubble.tsx` | lifted from page.tsx |
| `apps/web-platform/components/chat/review-gate-card.tsx` | lifted from page.tsx |
| `apps/web-platform/components/chat/status-indicator.tsx` | lifted from page.tsx |
| `apps/web-platform/components/chat/kb-chat-sidebar.tsx` | sidebar wrapper |
| `apps/web-platform/components/kb/selection-toolbar.tsx` | floating pill (KB-article-scoped) |
| `apps/web-platform/lib/analytics-client.ts` | thin client for Plausible |
| `apps/web-platform/app/api/analytics/track/route.ts` | server route to Plausible |
| `supabase/migrations/20260415a_add_context_path_to_conversations.sql` | schema migration (column + UNIQUE partial index) |
| `supabase/migrations/20260415b_backfill_context_path.sql` | backfill migration (conditional; skip if legacy shape doesn't match) |
| `apps/web-platform/test/chat-surface-sidebar.test.tsx` | sidebar variant tests |
| `apps/web-platform/test/kb-chat-sidebar.test.tsx` | panel lifecycle tests |
| `apps/web-platform/test/selection-toolbar.test.tsx` | selection primitive tests |
| `apps/web-platform/test/sheet.test.tsx` | primitive tests (desktop/mobile) |
| `apps/web-platform/test/use-media-query.test.ts` | hook tests |
| `apps/web-platform/test/api/analytics-track.test.ts` | route tests |
| `knowledge-base/marketing/analytics/plausible-goals.md` | ops doc for provisioned goals (if file doesn't already exist) |

## Files to Modify

| Path | Change |
|---|---|
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | reduce to thin shell around `<ChatSurface variant="full">` |
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | mount sidebar + `KbChatContext` + flag gate |
| `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` | stateful trigger button; mount `SelectionToolbar` in markdown branch |
| `apps/web-platform/lib/types.ts` | extend `start_session` WSMessage with optional `resumeByContextPath`; extend `Conversation` with `context_path` |
| `apps/web-platform/lib/ws-client.ts` | extend `startSession()` signature with optional `resumeByContextPath` |
| `apps/web-platform/server/ws-handler.ts` | extend existing `start_session` case to handle `resumeByContextPath` lookup + fall-through to pending-creation |
| `apps/web-platform/components/chat/chat-input.tsx` | expose `insertQuote` imperative handle; placeholder with shortcut hint |
| `apps/web-platform/components/inbox/conversation-row.tsx` | render "KB" badge when `context_path` present |
| `apps/web-platform/test/chat-page.test.tsx` | update mounts to `<ChatSurface variant="full">` |
| `knowledge-base/product/roadmap.md` | update L8 row if milestone moves (Phase 3 P3 per CPO recommendation) |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Fork chat into two surfaces (full vs sidebar) | Drifts forever; review gates / @mentions / streaming would diverge. |
| Iframe full chat route inside a Sheet | Breaks React context, PostHog session, auth cookies edge cases; scroll conflicts; blocks selection quote wiring. |
| Sidebar mounted in `kb/[...path]/page.tsx` | `children` unmounts on every KB nav (per `kb-nav-tree-disappears` learning). Fatal. |
| URL param for selection (`?quote=...`) | URL length limits; breaks the "add another quote" v1.1 flow. WS message is the right abstraction. |
| Store selections on the `messages` table | Complicates schema for a feature that's stateless-per-turn. Keep in `ConversationContext` in-memory. |
| Use a runtime FF system (GrowthBook, LaunchDarkly) | No existing primitive; introducing one is its own brainstorm. `NEXT_PUBLIC_*` env flag is enough for v1 rollout. |
| Client-side Plausible script tag instead of server route | PII risk + CSP implications + ad-blocker bypass. Server-side forward is the canonical pattern per existing Plausible integration. |
| New REST route `/api/conversations/by-context` instead of WS message | WS-first matches existing chat flow; avoids dual-channel session state. |
| Show banner on doc-switch ("Switch to Doc B?") instead of auto-switch | Brainstorm Open Q #1 resolved: auto-switch matches file-tree behavior; banner adds friction without value. |
| Preserve in-flight stream when panel closes | Complicates WS session lifecycle; aborting is simpler and matches user intent (close = stop). |

## Test Scenarios

**Unit / component (vitest + happy-dom):**

1. `use-media-query.test.ts` — returns `false` in SSR; subscribes to matchMedia; cleans up on unmount.
2. `sheet.test.tsx` — renders right-side on desktop, bottom on mobile; `Escape` invokes `onClose`; focus-trap when open; dismisses on backdrop click; dragging below collapsed threshold calls `onClose`.
3. `chat-surface-sidebar.test.tsx` — variant="sidebar" omits full-mode header, width constraints, mobile back arrow, safe-bottom padding; user bubbles render blockquotes as blockquotes.
4. `chat-page.test.tsx` (updated) — existing full-chat-route assertions continue to pass after extraction.
5. `chat-input.test.tsx` (augmented) — `insertQuote` prepends `> <text>\n\n`; does not auto-send; works while streaming; flash animation applied; scroll-into-view called.
6. `selection-toolbar.test.tsx` — pill appears for in-article selections; does not appear outside; dismisses on collapse, click-outside, Escape (and stops propagation); keyboard shortcut fires `onAddToChat`; oversized selection renders disabled pill with tooltip.
7. `kb-chat-sidebar.test.tsx` — opens, sends `resume_or_create_by_context` on open and on path change, passes `conversationId` to ChatSurface; resolving state renders skeleton; timeout renders retry; `resumedFrom` renders banner that dismisses on first new message; draft persists across doc nav.
8. `api/analytics-track.test.ts` — forwards to Plausible; 402 → 204 (graceful skip); invalid body → 400; unauthenticated → 401.
9. WS-handler tests for `start_session` with `resumeByContextPath` — find existing row emits `session_resumed`; miss falls through to pending-creation; abort-before-await invariant preserved; `ON CONFLICT DO NOTHING` on two-tab race.
10. ~~WS-handler tests for `add_context`~~ — deferred to v1.1.
11. ~~`context-validation.test.ts` `selections[]` schema~~ — deferred to v1.1.
12. Migration test (if Supabase test harness exists) — UNIQUE partial index enforced; duplicate insert fails with expected PG error; new NULL-context_path inserts work; conditional backfill runs correctly in staging.

**Integration / browser (Playwright):**

13. "Ask about this document" on markdown KB doc opens sidebar, auto-resumes prior thread (banner "Continuing from [date]" shown).
14. Navigating Doc A → Doc B with panel open auto-switches thread; Doc A's draft preserved; returning to Doc A restores its draft.
15. Selecting markdown text → "Quote in chat" pill appears → click → sidebar opens (if closed) → input contains `> <text>` → flash animation visible → Enter sends.
16. Selection while assistant streaming: quote appends to draft, does not auto-send.
17. Keyboard shortcut `Cmd/Ctrl+Shift+L` inserts quote without mouse.
18. Mobile (iPhone 14 Pro size): tap trigger → bottom sheet at ~60vh, draggable to full + collapsed; dragging below 10vh closes sheet.
19. Mobile: pill click on a selection near the fold opens sheet; "Referenced passage" chip visible at top of sheet.
20. Selection does NOT interfere with link clicks or text copy (Cmd/Ctrl+C).
21. Full-page `/dashboard/chat/<id>` regression: visually/functionally identical to main.
22. Long URLs / wide code blocks in sidebar chat bubbles wrap (no horizontal overflow of 380px panel).
23. Flag off: trigger falls back to legacy `/dashboard/chat/new?msg=...&context=...` navigation.
24. Resumed-thread banner auto-dismisses on first new user message.
25. Close panel while streaming → assistant response aborts; reopening on same doc shows user messages only (no partial assistant output).
26. Two-tab scenario: Tab A streaming, Tab B opens sidebar on same doc → Tab A gracefully aborts, Tab B resumes.
27. iOS Safari: pill replaces/suppresses native share menu when selection is in article.
28. Oversized selection (>8KB): pill is disabled with tooltip; no quote can be inserted.

## Acceptance Criteria

+ [x] AC1: "Ask about this document" trigger opens sidebar (flag on) or legacy route (flag off).
+ [x] AC2: Sidebar auto-resolves thread by `context.path`; resumed threads show "Continuing from [date]" banner that auto-dismisses on first new message.
+ [x] AC3: "Quote in chat" pill surfaces on markdown selection; inserts `> <text>` with flash confirmation.
+ [x] AC4: Keyboard shortcut `⌘⇧L` / `Ctrl+Shift+L` inserts quote without mouse; input placeholder surfaces the shortcut.
+ [x] AC5: Sidebar survives KB file-to-file navigation; drafts preserved per-path.
+ [x] AC6: Full-page `/dashboard/chat/<id>` route unchanged after ChatSurface extraction.
+ [x] AC7: Mobile renders draggable bottom sheet at ~60vh with three snap points; dragging below 10vh closes.
+ [x] AC8: Three Plausible goals fire: `kb.chat.opened`, `kb.chat.selection_sent`, `kb.chat.thread_resumed`.
+ [x] AC9: Panel a11y contract met: `aria-label`, `Escape` close, focus move on open, focus return on close.
+ [x] AC10: Long URLs and code blocks wrap (not scroll) inside 380px sidebar.
+ [ ] AC11: DB migration applied to prod (verified via Supabase REST API); backfill ran or explicitly skipped with rationale. *(Rollout step 3 — verified post-merge, not pre-merge.)*
+ [x] AC12: Legacy `?context=` URL shape unchanged.
+ [x] AC13: All vitest scenarios pass.
+ [x] AC14: Flag off-path tested — `NEXT_PUBLIC_KB_CHAT_SIDEBAR=0` falls back to legacy navigation.
+ [x] AC15: Closing panel mid-stream aborts session; reopening shows user messages only.
+ [x] AC16: Selection > 8KB renders disabled pill; no oversize payload reaches server.
+ [ ] AC17: iOS Safari: native share menu suppressed on markdown selection when pill visible. *(Implemented via `contextmenu` preventDefault on articleRef in SelectionToolbar; real-device verification deferred to Rollout step 5 / `/qa`.)*
+ [x] AC18: Inbox row shows "KB" badge for conversations with `context_path`.
+ [x] AC19: Trigger label is stateful: "Ask about this document" (no thread) / "Continue thread" (thread exists).
+ [x] AC20: Two-tab scenario doesn't create duplicate conversations; supersede abort is graceful. *(Implemented via UNIQUE partial index on `(user_id, context_path)` + `23505 unique_violation` catch in `server/ws-handler.ts:createConversation` that falls back to the existing row. Two-tab real-browser verification deferred to Rollout step 5.)*

## Domain Review

**Domains relevant:** Product, Marketing, Engineering

### Product (CPO)

**Status:** reviewed
**Assessment:**

+ Carry-forward (brainstorm): Sidebar approach beats new-window; doc-per-thread matches mental model; mobile/cramping/nav-continuity are sharp edges.
+ Plan-level (fresh): Phase A rework to include flag plumbing + one analytics emit (CPO blocking finding #1 — resolved). Phase 5 collapsed (CPO finding #2 — resolved). Doc-switch draft preservation added (CPO finding #3 + SpecFlow gap #8 — resolved). Milestone conflict surfaced in Known Blockers section for user decision (CPO finding #4).
+ Empty-state copy spec added. External feature name: plan prose + UI copy uses "Ask this document" framing throughout (not "KB chat sidebar").

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** Demoable "feel the difference" upgrade. Warrants a 20–30s
screen recording + changelog entry + one social post. Framing leads with
the selection gesture ("Quote in chat") per CMO direction — copywriter
replaced "Add to chat" and "Chat about this" framing throughout. Ship-phase
artifacts (recording, changelog, social) tracked at `/ship` time.

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Refactor over iframe/rebuild. Extract `<ChatSurface variant>`,
extend `ConversationContext` with `selections[]`, add `add_context` WS
message, lazy-load via `next/dynamic`. Plan honors all four directives; the
WS protocol adds `resume_or_create_by_context` to handle per-doc thread
resolution that has no existing API. Session-state audit for
`selections[]` on abort/close paths added to 2.4 per
`deferred-ws-conversation-creation` learning.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead, copywriter
**Skipped specialists:** none
**Pencil available:** yes (wireframes produced)

#### Findings

**spec-flow-analyzer (10 gaps identified, all integrated into plan):**

1. Panel-resolving state → added to 2.7 (skeleton + 10s timeout + retry)
2. Close-mid-stream abort behavior → added to 2.7 (`user_closed` abort)
3. Mobile 0vh snap semantics → clarified in 1.2 (drag < 10vh = close)
4. Client-side selection preflight → added to 4.1 (disabled pill + tooltip on >8KB)
5. Resumed-thread visual cue → added to 2.7 (banner "Continuing from [date]")
6. User-bubble markdown rendering for blockquotes → added to 1.3 (`MessageBubble` policy change)
7. Draft persistence when creation fails → covered by 2.10 `sessionStorage` drafts
8. Legacy `?context=` URL dedup → migration backfill added to 2.1
9. Post-quote confirmation on mobile → added to 4.3 (scroll + flash + "Referenced passage" chip)
10. Pill vs. panel Escape priority → clarified in 4.1 (`stopPropagation`)

**CPO plan-level review:**

+ Finding #1 (BLOCKING): flag + `kb.chat.opened` emit moved into Phase A — resolved.
+ Finding #2 (HIGH): Phase 5 collapsed into Phase 2 — resolved.
+ Finding #3 (HIGH): draft preservation on doc-switch — added to 2.7 + 2.10 + test 14.
+ Finding #4 (MEDIUM): milestone conflict — surfaced in Known Blockers section; user decision required.
+ Concurrent-tabs race: test scenario 26 added.
+ KB badge backfill: added to migration 2.1.
+ External feature name: plan now uses "Ask this document" framing per copywriter.

**ux-design-lead (wireframes at `knowledge-base/project/specs/feat-kb-chat-sidebar/wireframes.pen`, 9 screens + 3x PNG exports):**

+ Code-block treatment in sidebar: wrap (not scroll) — resolved in 1.3.
+ Mid-stream file switch: covered by 2.7 `user_closed` abort + draft preservation.
+ iOS Safari pill/native-menu collision: `user-select` + `contextmenu` suppression added to 4.1.
+ Resumed-thread banner auto-dismiss: added to 2.7.
+ Flag state QA: both states tested in 7.2.
+ Attach flow at 380px: verification added to 3.3.
+ Empty-state prompts: NOT added as a feature in v1 (out of spec scope; separate follow-up if validated).
+ Mobile sheet covering selection: "Referenced passage" chip added to 4.3.

**copywriter (7 surfaces + 6 plan-copy edits integrated):**

+ Pill label → "Quote in chat" (replaced "Add to chat" throughout plan).
+ Sidebar header → filename in `JetBrains Mono`.
+ Empty state → "Ask about this document." / "Select any passage to quote it, or type a question below."
+ Thread-resumed banner → "Continuing from [date]".
+ Mobile drag-handle aria → "Resize panel" / tooltip "Drag to expand".
+ Input placeholder → "Ask about this document — ⌘⇧L to quote selection".
+ Close aria → "Close panel".
+ Stateful trigger label → "Ask about this document" / "Continue thread".
+ `<aside aria-label>` → "Document conversation".

**Brainstorm-recommended specialists:**

+ ux-design-lead — invoked (covered by UX Gate pipeline).
+ copywriter — invoked (covered by UX Gate Content Review Gate).

## Rollout Plan

1. **Resolve milestone conflict** (Known Blockers #1) — promote #2345 to Phase 3 P3 milestone OR pause build.
2. Merge with `NEXT_PUBLIC_KB_CHAT_SIDEBAR=0` in prd Doppler config.

        # dev config — flag on from day one so QA can exercise the sidebar
        doppler secrets set NEXT_PUBLIC_KB_CHAT_SIDEBAR=1 -p soleur -c dev
        # prd config — flag off at merge time
        doppler secrets set NEXT_PUBLIC_KB_CHAT_SIDEBAR=0 -p soleur -c prd

3. Apply Supabase migration to prod; verify via REST API (per AGENTS.md `wg-when-a-pr-includes-database-migrations`). Verify backfill worked in staging before applying to prod.
4. Provision three Plausible goals via API — `bash scripts/provision-plausible-goals.sh` (idempotent PUT upsert; see `knowledge-base/marketing/analytics/plausible-goals.md`).
5. Manual QA on staging with flag on (desktop, mobile, iOS Safari). See QA checklist below.
6. Founder sign-off.
7. Flip prd flag to `1`:

        doppler secrets set NEXT_PUBLIC_KB_CHAT_SIDEBAR=1 -p soleur -c prd
        # Redeploy web-platform so the new env var reaches Next.js build output.

8. One-week soak; monitor `kb.chat.opened` / `kb.chat.selection_sent` / `kb.chat.thread_resumed` in Plausible.
9. Follow-up PR: remove flag + legacy "Ask about this document" → new-window fallback. Tracked in the flag-removal follow-up issue (Deferrals table).

### Staging QA checklist (step 5)

Run against staging with `NEXT_PUBLIC_KB_CHAT_SIDEBAR=1`:

+ [ ] Trigger label on a fresh doc reads "Ask about this document".
+ [ ] After sending one message, label updates to "Continue thread" with the dot indicator.
+ [ ] Closing + reopening the sidebar on the same doc resumes the thread (banner "Continuing from …") and fires `kb.chat.thread_resumed` in Plausible.
+ [ ] Selecting a passage shows the "Quote in chat" pill with ⌘⇧L hint.
+ [ ] Clicking the pill opens the sidebar (if closed), inserts `> text\n\n`, flashes amber, does not auto-send.
+ [ ] ⌘⇧L / Ctrl+Shift+L with selection in article fires the same flow without clicking.
+ [ ] Selection > 8KB renders the pill disabled with tooltip.
+ [ ] Navigating between KB files preserves per-path drafts.
+ [ ] Resize to 375px mobile width: bottom sheet drags between snap points; drag below 10vh closes.
+ [ ] iOS Safari: native share menu does not appear while pill is visible on selected text.
+ [ ] Flip flag to 0 on staging and re-verify the legacy `/dashboard/chat/new?context=...` link works.

### Flag-off regression check (step 2 + 7 rollback)

`NEXT_PUBLIC_KB_CHAT_SIDEBAR=0` must render the legacy link in both markdown and non-markdown KB branches. `KbChatTrigger` falls back to `<Link href={fallbackHref}>Chat about this</Link>` when the context value's `enabled` is false or the provider is absent entirely — covered by the existing `test/kb-chat-trigger.test.tsx`-style mounts inside the a11y + quote tests. Redeploy is required after a flip either direction because `NEXT_PUBLIC_*` vars are baked into the Next build.

## Deferrals (tracked as follow-up issues)

Per AGENTS.md `wg-when-deferring-a-capability-create-a`, each deferral
below must be filed as a GitHub issue before this plan is marked ready.

| Deferral | Re-evaluation criterion | Target milestone | Issue |
|---|---|---|---|
| PDF text selection → chat | When react-pdf text-layer coords are stable | Post-MVP / Later | — |
| Resizable sidebar splitter | First user complaint about fixed 380px | Post-MVP / Later | — |
| `add_context` WS message + selections[] schema + UI flow (v1.1 — entire mid-session attach path) | User research shows demand for "attach without message" flow | Post-MVP / Later | — |
| Runtime feature-flag primitive (replace env-var pattern) | Second feature needs FF rollout | Post-MVP / Later | — |
| Remove `NEXT_PUBLIC_KB_CHAT_SIDEBAR` flag + legacy fallback | One-week prd soak clean (goals ≥ 25 unique / no Sentry spike / no regressions) | Post-MVP / Later | #2377 |
| In-app keyboard-shortcuts help surface | 3+ shortcuts exist | Post-MVP / Later |
| Empty-state suggested prompts | Validated via UX research | Post-MVP / Later |
| Attach UX tuning for 380px sidebar | If 3.3 verification finds issues | Phase 3 or Post-MVP |

## Open Questions (from brainstorm, resolved here)

1. **Conversation continuity on nav.** Auto-switch to Doc B's thread (option a); preserve Doc A's draft in `sessionStorage`. **Resolved in 2.7 / 2.10.**
2. **Selection during assistant streaming.** Append to draft, don't send. **Resolved in 4.3.**
3. **Width.** Fixed 380px. **Resolved — resizable tracked as deferral.**
4. **PDF selection.** Deferred. **Tracked as follow-up.**

## Risks + Mitigations

| Risk | Mitigation |
|---|---|
| Extraction regresses full-page chat | Screenshot-diff + `chat-page.test.tsx` lock |
| Long selections blow up WS payload / LLM cost | Server caps (8KB/selection, 32KB total, 20 max) + client preflight (4.1) |
| Pending conversation state mismanaged when nav-switching | Unit test `resume_or_create_by_context` against `deferred-ws-conversation-creation` contract (test 9) |
| Floating pill trapped by ancestor `backdrop-filter` | Portal to `document.body`; verify no containing-block trap (test 22) |
| iOS Safari selection behavior differs | Explicit cross-browser QA budget (7.3) + `user-select`/`contextmenu` suppression (4.1) |
| Plausible 402 on free tier breaks user flow | `/api/analytics/track` returns 204 on 402; client fail-soft |
| Migration not applied to prod at ship time | Rollout step 3; verified via Supabase REST API |
| Backfill misses pre-migration legacy `?context=` threads | Rollout step 3 tests backfill in staging first; accept discontinuity if SELECT shape wrong (noted in migration file) |
| Concurrent tabs create duplicate conversations | `context_path` index + `ORDER BY updated_at DESC LIMIT 1` find-first logic; test 26 |
| Trigger label state out of sync between `kb/layout.tsx` and trigger | Source label state from `KbChatContext.messageCount` (single source); re-render on update |

## Resume Prompt

For resuming this feature from a fresh session:

    /soleur:work knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md

    Context: branch kb-chat-sidebar, worktree .worktrees/kb-chat-sidebar/,
    PR #2347, issue #2345. Plan reviewed by spec-flow-analyzer, CPO,
    ux-design-lead, copywriter; wireframes at
    knowledge-base/project/specs/feat-kb-chat-sidebar/wireframes.pen.
    Known Blocker #1: resolve #2345 milestone (Phase 3 P3 vs Post-MVP)
    before starting Phase 1.
