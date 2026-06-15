# Learning: flex-child min-width floor vs `min-w-0`, and an affordance label must live inside its own `<button>`

## Problem

Three presentational/interaction defects on the Concierge chat surface
(`apps/web-platform/components/chat/{message-bubble,debug-stream-panel}.tsx`):

1. The Concierge bubble's avatar sat as a row-level flex sibling **left of** the
   card, offsetting the card's left edge ~40px right of the wrapper — so it no
   longer aligned with the full-width Debug stream panel directly below it.
2. The bubble wrapped short content (`"Routing to the right experts..."`)
   onto two lines even when it fit on one.
3. (Regression from #5241) Clicking the word **"Show"** in the debug-panel
   header did nothing. Adding a Copy button had split the header into a toggle
   `<button>` (just "Debug stream" + count) and a sibling `<div>` whose
   `"Show/Hide · not saved"` `<span>` was now **outside any button**.

## Solution

1. **Avatar alignment:** move `LeaderAvatar` OUT of the row-level flex and INTO
   the existing in-card header row (`{leader && <div class="flex items-center gap-2">…}`),
   size `md`→`sm`. Card-left now equals wrapper-left equals Debug-panel-left,
   with zero negative margins → no off-screen clipping on any viewport.
   (Rejected the negative-margin/absolute-avatar variant: `-left-9`=36px clips
   past the `px-4`=16px gutter on narrow viewports.)
2. **Shrink-to-fit:** give the assistant card `w-fit min-w-[6rem] max-w-full`.
3. **Restore clickability:** move the `Show`/`Hide` label back INSIDE the toggle
   `<button>` (`ml-auto` keeps its right-side position); Copy stays a sibling
   `<button>`; the orphaned suffix becomes a static `not saved` caption.

## Key Insight

**(a) `min-w-0` and a `min-w-[Nrem]` floor are mutually exclusive on one flex
child — but you rarely need both.** A flex item with an absolutely-positioned,
right-anchored badge that can overhang the left edge when the card shrinks
needs a width *floor*. A flex item that must let wide `<pre>`/long tokens
shrink-and-scroll needs `min-w-0` (to override `min-width:auto` = min-content).
You can't carry both `min-w-0` and `min-w-[6rem]` (both set `min-width`; cascade
order is unpredictable). Resolution: **`min-w-[Nrem]` ALSO overrides
`min-width:auto`**, so it gives the overflow-shrink behaviour *and* a badge floor
in one class — drop `min-w-0` on that branch, keep it only where no floor is
needed (here: the user-side card). Pair with `w-fit` for content-sizing.

**(b) The word a user reads as a control must live inside that control's
`<button>`.** When you add a second button next to an existing toggle, it is
tempting to relocate the toggle's text label into a neutral sibling span — that
silently kills the affordance (the label looks clickable, does nothing). Keep
the label inside the original `<button>`; use `ml-auto` to preserve its visual
position. A test that clicks the *button by accessible name* (`getByRole`) will
NOT catch this regression — assert `within(toggle).getByText("Show")` and that
clicking that text flips `aria-expanded`. (code-quality-analyst mutation-verified
the guard: reverting the fix makes the test fail.)

## Session Errors

- **Bash CWD persisted across calls** — a `cd apps/web-platform` (and later a
  `cd <worktree-root>`) carried into the next call, so a follow-up relative
  `cd apps/web-platform` failed and a `./node_modules/.bin/vitest` exited 127.
  **Recovery:** chain `cd <worktree-abs-path> && <cmd>` in a single Bash call.
  **Prevention:** already documented in `work/SKILL.md` (worktree CWD-chaining
  rule) — one-off here, no new rule.
- **Monitor tool InputValidationError** — invoked with a guessed parameter
  shape; the tool schema was not loaded. **Recovery:** used a Bash `until` poll
  loop on the background log instead. **Prevention:** load deferred-tool schemas
  via ToolSearch before calling, or prefer a Bash poll for simple waits.

## Tags
category: ui-bugs
module: apps/web-platform/components/chat
