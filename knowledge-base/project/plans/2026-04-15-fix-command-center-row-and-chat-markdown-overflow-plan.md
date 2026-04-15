---
title: "fix: command center row shift and chat markdown horizontal overflow"
type: fix
date: 2026-04-15
issue: 2229
branch: feat-one-shot-2229-alignment-fix
---

# fix: Command Center row shift and chat markdown horizontal overflow

## Problem

Issue [#2229](https://github.com/jikig-ai/soleur/issues/2229) reports two related alignment
defects in the dashboard UI:

1. **Command Center inbox row shift.** On the desktop conversation list, the "relative
   time" text (`relative-time.ts`) grows from 7 characters ("5m ago") to 8 characters
   ("10m ago") as the minute/hour count rolls into two digits. Because the time cell is
   a plain flex child with no fixed width, every such row renders a different total
   width for the trailing cluster, which pulls the adjacent LeaderAvatar (the "domain
   leader badge") a few pixels to the left relative to neighbouring rows. The columns
   no longer line up vertically, producing a visibly ragged right edge.

2. **Chat markdown horizontal overflow.** In a conversation, when the assistant
   returns a large code block, a wide GFM table, or an unbreakable string (a long URL
   or shell one-liner), the message bubble grows past its `max-w-[80%]` constraint and
   the whole chat scroller develops a horizontal scroll bar. This happens because the
   bubble's ancestor flex container does not set `min-width: 0`, so the default
   `min-width: auto` of a flex item lets inline content expand the bubble beyond the
   declared max. The markdown paragraph/heading/list components also do not opt into
   `overflow-wrap: anywhere`, so long tokens (URLs, identifiers) never break.

Both defects are visual-only — no data is lost — but they degrade the feel of the two
highest-traffic surfaces in the product (the inbox and the conversation view).

## Root Cause Analysis

### 1. Inbox row shift — `components/inbox/conversation-row.tsx`

Desktop row layout (line 207-237):

```tsx
// Desktop: horizontal row
<div className="hidden w-full items-center gap-4 md:flex">
  <StatusBadge />
  {isArchived && <span>Archived</span>}
  <div className="flex min-w-0 flex-1 flex-col gap-0.5">
    {/* title + preview */}
  </div>
  {conversation.domain_leader && (
    <LeaderAvatar leaderId={conversation.domain_leader} size="md" ... />
  )}
  <span className="shrink-0 text-xs text-neutral-500">
    {relativeTime(conversation.last_active)}
  </span>
  {(onArchive || onUnarchive) && <ArchiveButton />}
</div>
```

`relativeTime()` outputs:

- `"just now"` (8 chars)
- `"${N}m ago"` -- 7 chars when `N` is single-digit, 8 when two-digit
- `"${N}h ago"` -- 7 / 8 chars
- `"${N}d ago"` -- 7 / 8 chars
- `"${N}mo ago"` -- 8 / 9 chars

The `<span>` wrapping the time has no min-width and uses the default (proportional)
text rendering. Digits in the default sans-serif font (`var(--font-geist-sans)`
per `app/layout.tsx`) are **not** tabular-width, so "1" ≠ "5" ≠ "10" ≠ "15" in
horizontal advance. The result: every row in the inbox renders a slightly
different-width time cell, which translates into a slightly different position for
the LeaderAvatar and ArchiveButton to its left. The user perceives this as
"the badge jumps left when a two-digit number is shown."

Fix: (a) force tabular digits on the time cell with `tabular-nums`, and (b) give
the time cell a deterministic min-width wide enough to hold all common relative-time
strings so the trailing cluster does not translate when the value grows. A
fixed-width approach (`w-16` ≈ 4rem ≈ 64px) matches the longest expected label
(`"99mo ago"` = 9 characters) comfortably at `text-xs`. Combined with
`text-right`, this both prevents shift **and** right-aligns the column across
rows.

### 2. Chat markdown overflow — `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` + `components/ui/markdown-renderer.tsx`

Bubble wrapper (line 519-533):

```tsx
<div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
  <div className={`flex max-w-[90%] gap-3 md:max-w-[80%] ${isUser ? "flex-row-reverse" : ""}`}>
    {leader && <LeaderAvatar ... />}
    <div className={`relative rounded-xl px-4 py-3 text-sm leading-relaxed ...`}>
      {/* bubble content */}
    </div>
  </div>
</div>
```

Two issues compound:

1. The **inner flex container** (`flex max-w-[90%] gap-3 md:max-w-[80%]`) has its
   `max-width` set but its children do not have `min-width: 0`. CSS spec default for a
   flex item's `min-width` is `auto`, which resolves to the intrinsic content size.
   If the markdown bubble contains, say, a 300-character single-line code block, the
   inner bubble's intrinsic min-width is ~300 characters; flexbox will honour that over
   the ancestor's max-width, and the whole row pushes past the viewport.
2. The **MarkdownRenderer** custom components do not apply any word-break rules.
   Paragraphs (`mb-2 leading-relaxed`), headings, and list items default to
   `overflow-wrap: normal`, which does **not** break unbreakable strings (URLs,
   file paths, snake_case identifiers). Even if the bubble is sized correctly, long
   words inside a `<p>` stretch their line box horizontally.

The existing `pre` and `table` components already use `overflow-x-auto` (line 36, 49
of `markdown-renderer.tsx`), which is the correct treatment for code and tables
when the bubble itself has a stable width. The fix is to give the bubble a stable
width and make text content wrap aggressively, so the bubble never grows past its
`max-w-[80%]` envelope.

Fix:

- Add `min-w-0` to the bubble's flex row container so the max-width constraint is
  respected.
- Add `min-w-0` to the inner bubble `<div>` so its width is capped by the parent.
- In `MarkdownRenderer`, default to `break-words` / `[overflow-wrap:anywhere]` on
  the root markdown wrapper (or on block-level components), matching the pattern
  already used on the streaming state (`page.tsx:607`:
  `whitespace-pre-wrap [overflow-wrap:anywhere]`).

## Scope & Non-Goals

**In scope:**

- Stabilize the time column width in `conversation-row.tsx` (desktop view).
- Prevent markdown content from expanding the chat bubble past its max-width.
- Apply wrapping rules to text content in `MarkdownRenderer`.

**Out of scope:**

- Mobile inbox layout changes (the two-column desktop alignment issue does not apply
  to the vertical mobile stack).
- Replacing `react-markdown` or adding new markdown features.
- Visual redesign of the conversation row (status badge, avatar size, spacing).
- Fixing long-word wrapping in the conversation preview (`ConversationRow` already
  uses `truncate`).

## Acceptance Criteria

- [ ] In a Command Center inbox with rows displaying times spanning single-digit and
      two-digit values (e.g., "5m ago", "12m ago", "3h ago", "10h ago", "1d ago"),
      the LeaderAvatar column and the ArchiveButton column are vertically aligned
      across every row (pixel-perfect equality of the avatar centre and the button
      centre).
- [ ] Rendering a chat message containing a 300-character single-line code snippet,
      a wide GFM table, and a bare 200-character URL does **not** introduce a
      horizontal scroll bar on the chat scroller (`.flex-1.overflow-y-auto` parent).
- [ ] The message bubble never exceeds its declared `max-w-[80%]` on desktop
      (`md:` breakpoint) regardless of content length.
- [ ] Existing vitest suites for `command-center` and markdown rendering continue to
      pass; new tests cover both defects.
- [ ] Playwright E2E run for the dashboard and chat routes shows no regression in
      screenshots beyond the fixed alignment.

## Files to Change

- `apps/web-platform/components/inbox/conversation-row.tsx`
  - Line 227: widen the time span class from
    `"shrink-0 text-xs text-neutral-500"` to
    `"shrink-0 w-16 text-right text-xs text-neutral-500 tabular-nums"`.
  - Consider applying the same treatment to the mobile variant (line 178) for
    consistency, though the mobile layout is a vertical stack and does not
    suffer the same shift.
- `apps/web-platform/components/ui/markdown-renderer.tsx`
  - Add `break-words [overflow-wrap:anywhere]` to the `p`, `li`, `h1`, `h2`, `h3`
    component definitions, OR wrap the root `<Markdown>` output in a `<div>`
    that applies these classes once.
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
  - Line 521: add `min-w-0` to the inner bubble flex container:
    `"flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%] ..."`.
  - Line 527-533: add `min-w-0` to the bubble body `<div>` so its width is capped
    by the parent.

## Files to Create

- `apps/web-platform/test/conversation-row.test.tsx` — unit tests for the time
  column width behaviour (assert the time span has `w-16`, `text-right`,
  `tabular-nums`; assert LeaderAvatar receives a stable flex position by
  checking the rendered DOM class list).
- `apps/web-platform/test/markdown-renderer.test.tsx` — unit tests that the
  markdown wrapper applies wrap rules and that pre/table children retain their
  `overflow-x-auto` behaviour.

No new files are required in `knowledge-base/` or `components/` beyond the tests.

## Test Scenarios

### Unit — `conversation-row.test.tsx`

1. Renders a row with `last_active = "5 minutes ago"` and a row with
   `last_active = "12 minutes ago"`. Assert both rendered time `<span>` elements have
   the same `offsetWidth` (using jsdom layout approximation — fall back to asserting
   the exact class list if layout is not available).
2. Assert the time span includes the classes `w-16`, `text-right`, `tabular-nums`.
3. Assert the LeaderAvatar is rendered immediately before the time span in DOM order
   (no reordering).

### Unit — `markdown-renderer.test.tsx`

1. Render `content = "a".repeat(500)` and assert the rendered `<p>` includes a class
   that applies `overflow-wrap: anywhere` or equivalent (`break-words`).
2. Render a markdown table and assert the wrapping `<div>` still carries
   `overflow-x-auto`.
3. Render a fenced code block and assert the `<pre>` still carries `overflow-x-auto`.

### Integration — existing `command-center.test.tsx`

1. Extend the existing mock list to include a conversation with
   `last_active = Date.now() - 12 * 60000` (12m ago, two-digit) alongside the current
   2m ago / 15m ago / 1d ago fixtures.
2. Assert the `role="button"` rows render without console warnings and that all
   `data-testid`-decorated cells produce the same bounding-rect X-coordinate for the
   avatar position (if testable in jsdom; otherwise assert the time span class list).

### E2E — Playwright (optional, gated on `e2e/` convention)

1. Visit `/dashboard` with a seeded conversation list containing times from 5m ago
   to 23h ago. Take a screenshot and visually compare against a baseline once a
   baseline is captured.
2. Visit `/dashboard/chat/<id>` with a fixture message containing a long URL, a
   wide table, and a long code block. Assert `document.documentElement.scrollWidth
   === window.innerWidth` (no horizontal scroll).

## Implementation Plan

### Step 1 — RED: write failing unit tests

1. Create `apps/web-platform/test/conversation-row.test.tsx` with the three
   assertions above. Expect failures because `w-16`/`tabular-nums` are not yet
   applied.
2. Create `apps/web-platform/test/markdown-renderer.test.tsx` with the wrap rule
   assertion. Expect failure because `break-words` is not yet applied.
3. Extend `command-center.test.tsx` fixture set to include a two-digit time entry.
4. Run `cd apps/web-platform && node node_modules/vitest/vitest.mjs run
   test/conversation-row.test.tsx test/markdown-renderer.test.tsx test/command-center.test.tsx`
   (honour the worktree vitest rule `cq-in-worktrees-run-vitest-via-node-node`).

### Step 2 — GREEN: minimal fixes

1. `conversation-row.tsx`: update the desktop time span class.
2. `markdown-renderer.tsx`: apply wrapping classes to text components (prefer
   modifying the root `<Markdown>` wrapper with a wrapping `<div>` so individual
   component overrides stay minimal).
3. `page.tsx` (chat): add `min-w-0` on the two relevant bubble containers.

### Step 3 — Verify

1. Re-run the vitest suites — all green.
2. Run the broader web-platform vitest suite to ensure no regressions in other
   command-center or chat tests.
3. Spawn a local dev server (`bun run dev` inside `apps/web-platform`) and open
   `/dashboard` + a chat with a fixture message to visually verify.
4. Use Playwright MCP if available for a screenshot-based confirmation.

### Step 4 — Commit

1. Run `skill: soleur:compound` (AGENTS.md workflow gate).
2. Commit with a conventional message:
   `fix(ui): stabilize inbox row width and chat markdown overflow (#2229)`.
3. Use `/ship` for the PR flow.

## Risks & Mitigations

- **Risk:** The `w-16` (4rem) value may be too narrow for the longest possible
  relative-time string (e.g., `"123mo ago"` after a multi-year dormant conversation).
  - **Mitigation:** `99mo ago` is 8 chars; at `text-xs` (~12px font), 4rem ≈ 64px
    comfortably fits 8 monospace-metric digits. For 3-digit months the label wraps or
    truncates safely. If users complain, raise to `w-20`.

- **Risk:** Adding `overflow-wrap: anywhere` to all markdown `<p>` elements may
  break words mid-character in a way that degrades readability of normal prose.
  - **Mitigation:** `anywhere` breaks **only** when the line would otherwise
    overflow. Short paragraphs render identically to `normal`. If testing shows
    readability regressions, downgrade to `break-words` (which is less aggressive
    and only breaks at explicit word boundaries when the overflow cannot be avoided).

- **Risk:** `min-w-0` on the bubble flex container interacts with the leader
  avatar's `shrink-0` class and could allow the avatar to overlap with the bubble
  body on extreme narrow viewports.
  - **Mitigation:** The avatar already has fixed dimensions (`size="md"`,
    approximately 32px) and sits outside the bubble body in the flex row. `min-w-0`
    applies to the bubble body only, not the avatar. Verify on a 320px viewport in
    the test suite.

- **Risk:** The existing `command-center.test.tsx` snapshots or DOM queries may
  fail when class strings change.
  - **Mitigation:** Update the test file in the same commit. The existing test uses
    `screen.getByRole(...)` queries, not class-based assertions, so the risk is low.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Reserve a fixed pixel width via inline style on each row | Exact pixel control | Bypasses Tailwind system, hard to theme | **Rejected** — prefer utility classes |
| Drop the relative time from the row entirely, show only on hover | Eliminates width variation | Loses at-a-glance information value | **Rejected** — regresses UX |
| Move the time to the left of the avatar | Time is still visible, avatar stays rightmost | Reorders established layout, touches mobile | **Rejected** — unnecessary churn |
| Use `table` layout instead of flex for the inbox row | Natural column alignment | Large refactor, accessibility concerns | **Rejected** — disproportionate to the fix |
| Wrap all markdown output in `overflow-x-auto` container | Simple, single class | Causes per-bubble scroll bars, ugly on mobile | **Rejected** — we want content to wrap, not scroll |
| Apply CSS `word-break: break-all` globally | Breaks all long strings | Degrades normal prose (breaks inside words) | **Rejected** — `anywhere` / `break-words` is gentler |

No deferrals: both fixes are small, bounded, and shippable together.

## Domain Review

**Domains relevant:** Product (ADVISORY)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** ux-design-lead (ADVISORY tier — modifies existing UI, no
new surface), copywriter (no copy changes)
**Pencil available:** N/A

#### Findings

This plan modifies existing user-facing components (the conversation inbox row and
the chat message bubble) without introducing any new screens, modals, flows, or
copy. The mechanical escalation rule does not fire: no new files in
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Per the skill
procedure, running in pipeline mode, the ADVISORY tier auto-accepts.

No new user flows, error states, or drop-off points are introduced — the fix is
purely a layout/CSS correction.

## References

- Issue: [#2229](https://github.com/jikig-ai/soleur/issues/2229)
- Current conversation row: `apps/web-platform/components/inbox/conversation-row.tsx`
- Relative time helper: `apps/web-platform/lib/relative-time.ts`
- Markdown renderer: `apps/web-platform/components/ui/markdown-renderer.tsx`
- Chat page (bubble): `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Prior related plan: `knowledge-base/project/plans/2026-04-12-fix-chat-input-alignment-plan.md`
- Tailwind `tabular-nums`: <https://tailwindcss.com/docs/font-variant-numeric>
- CSS `overflow-wrap: anywhere`: <https://developer.mozilla.org/docs/Web/CSS/overflow-wrap>
- Flexbox `min-width: 0` pattern: <https://developer.mozilla.org/docs/Web/CSS/min-width#flex_items>
