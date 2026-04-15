---
title: Command Center row shift + chat markdown horizontal overflow (#2229)
category: ui-bugs
component: web-platform
date: 2026-04-15
tags: [tailwind, flexbox, min-w-0, overflow-wrap, tabular-nums, react-markdown]
related_issues: [2229, 2280]
---

# Command Center row shift + chat markdown horizontal overflow

## Problem

Two visual defects in the dashboard UI:

1. **Inbox row shift.** Desktop rows in `components/inbox/conversation-row.tsx`
   rendered the relative-time label (`"5m ago"` → `"10m ago"`) in a non-tabular
   proportional font inside a `<span className="shrink-0 text-xs ...">` with no
   reserved width. The 1-character delta when minutes rolled from single- to
   two-digit produced different total widths across rows, pulling the
   LeaderAvatar and ArchiveButton column positions left/right by a few px and
   breaking vertical alignment.
2. **Chat markdown overflow.** Long unbroken tokens (URLs, 200-char code
   blocks, wide GFM tables) pushed the chat bubble past its `max-w-[80%]`
   constraint, producing a horizontal scroll bar on the chat scroller. The
   bubble's flex row container lacked `min-w-0`, so the default
   `min-width: auto` let intrinsic content expand the bubble; the
   `MarkdownRenderer` also never opted into `overflow-wrap: anywhere`, so
   paragraphs with long tokens never broke.

## Root Cause

- **Inbox:** No `font-variant-numeric: tabular-nums` and no fixed-width slot on
  the time cell.
- **Chat:** Two-level `min-w-0` gap on the bubble flex containers + no
  container-level wrap rule on the Markdown output.

## Solution

Four small utility-class additions:

```tsx
// conversation-row.tsx (desktop time span)
<span className="w-16 shrink-0 truncate text-right text-xs tabular-nums text-neutral-500">
  {relativeTime(conversation.last_active)}
</span>

// markdown-renderer.tsx (wrap react-markdown output)
<div className="min-w-0 [overflow-wrap:anywhere]">
  <Markdown ...>...</Markdown>
</div>

// chat/[conversationId]/page.tsx (bubble flex containers)
<div className="flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%] ...">
  ...
  <div className="relative min-w-0 rounded-xl px-4 py-3 ...">
```

## Key Insights

1. **`min-w-0` must be applied at every flex-item level that has an
   `overflow-x-auto` descendant.** In this PR it was needed on *both* the
   bubble flex row AND the bubble body. A single `min-w-0` one level up does
   not propagate — the flex spec's default `min-width: auto` applies per-item.
   Without both, the existing `pre.overflow-x-auto` and `div.overflow-x-auto`
   (for tables) in `MarkdownRenderer` could not compute a stable containing
   block and still bled past `max-w-[80%]`.

2. **react-markdown v10 has no implicit wrapper element.** Applying
   container-level CSS (wrap rules, max-width, text color) requires wrapping
   the `<Markdown>` component in a styled `<div>`. Mutating every `p`/`h1`/`li`
   in the `components` prop is possible but produces more surface for drift
   than a single wrapper.

3. **`break-words` is redundant alongside `[overflow-wrap:anywhere]`.**
   `break-words` compiles to `overflow-wrap: break-word`; `anywhere` overrides
   it immediately. Initial commit included both; simplicity reviewer caught
   it. Keep only `[overflow-wrap:anywhere]`.

4. **`tabular-nums` + fixed width + `text-right` + `truncate` is the idiomatic
   recipe for a stable right-aligned numeric column in Tailwind v4.** Geist
   Sans supports the `tnum` OpenType feature so no font fallback is required.
   `truncate` catches the rare edge case (3-digit month count) safely.

5. **jsdom/happy-dom do not layout.** `offsetWidth` always returns 0, so any
   pixel-equality assertion on column stability passes trivially and proves
   nothing. Assert on the rendered class list instead, and reserve pixel
   verification for Playwright.

## Session Errors

1. **Test file placement collision.**
   - Recovery: Moved `test/conversation-row.test.tsx` to
     `test/components/conversation-row-alignment.test.tsx`. The codebase
     convention is `test/components/*.test.tsx` for component tests; plan
     prescribed flat placement.
   - Prevention: Plan skill should default component test paths to
     `test/components/<name>.test.tsx` when the target lives under
     `components/**`. Caught by `pattern-recognition-specialist` during
     review — no repeat cost, but plan-time prescription is the right fix.

2. **Wrong relative import path after moving file.**
   - Recovery: Updated `./mocks/use-team-names` → `../mocks/use-team-names`
     after moving the test into `test/components/`.
   - Prevention: Already covered by hard rule
     `hr-when-a-plan-specifies-relative-paths-e-g`. Re-running vitest caught
     it immediately. No workflow change needed.

## Prevention

- **Hook-enforceable?** No — this is a convention mismatch, not a mechanical
  violation.
- **Skill instruction edit (proposed):** In `plan` skill's "File creation"
  guidance, add: "When creating `.test.tsx` files for components under
  `components/**`, prescribe the path `test/components/<name>.test.tsx`.
  Never place component tests flat in `test/*.test.tsx` — this collides with
  the codebase convention."
- **Codebase rule:** The two patterns (`w-16 tabular-nums text-right` for
  stable numeric columns, `min-w-0 [overflow-wrap:anywhere]` wrapper for
  react-markdown) are idioms future UI fixes should reuse — worth surfacing
  in a component-level README or the frontend style section of the
  constitution if the pattern recurs.
