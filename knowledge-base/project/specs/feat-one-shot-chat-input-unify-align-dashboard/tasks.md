---
title: "Tasks: align unified chat input + apply to dashboard landing prompt"
plan: knowledge-base/project/plans/2026-06-02-fix-chat-input-unify-align-dashboard-plan.md
lane: single-domain
---

# Tasks — fix chat input alignment + dashboard unification

## 1. Setup / verification

- 1.1 Confirm `min-h-[40px]` appears in exactly 3 places (1 source + 2 tests) via
  `grep -rn "min-h-\[40px\]" apps/web-platform` and `grep -rn "40px" apps/web-platform/test/chat-input*.tsx`.
- 1.2 Confirm `apps/web-platform` test runner + discovery globs (`vitest.config.ts` `include:`,
  `package.json scripts.test`, `bunfig.toml` pathIgnorePatterns) before running tests.
- 1.3 Capture BEFORE Playwright screenshots at 1280 / 768 / 375 px for: chat bottom bar, KB doc
  ask panel, dashboard first-run prompt.

## 2. Core implementation — Part A (shared ChatInput alignment)

- 2.1 In `components/chat/chat-input.tsx:646`, change textarea `min-h-[40px]` → `min-h-[36px]`.
- 2.2 Re-balance textarea vertical padding (`py-2` → hypothesis `py-1.5`); FINAL value chosen
  from the visual pass (2.5), not asserted blind.
- 2.3 Keep container `items-end` (do NOT switch to `items-center`).
- 2.4 Verify the auto-grow effect (`:186-187`) still rests at the 36px floor and caps at 140px.
- 2.5 Visual-verify single-line alignment, multi-line button pinning, Send-vs-Stop parity, and
  mobile @ button position across breakpoints; lock the padding value.

## 3. Core implementation — Part B (dashboard unified box)

- 3.1 In `app/(dashboard)/dashboard/page.tsx:505-553`, replace the `flex items-center gap-3` row
  with ONE bordered container mirroring `chat-input.tsx:606`
  (`flex items-end gap-1.5 rounded-xl border ... px-2 py-1.5 ... focus-within:border-...`).
- 3.2 Make the paperclip button borderless (mirror `chat-input.tsx:615`); keep onClick/aria/SVG.
- 3.3 Make the `<input name="idea">` borderless + transparent inside the box; wrap in
  `<div className="flex-1">`; keep placeholder/autoFocus/onPaste; keep it single-line `<input>`.
- 3.4 Make the send button borderless solid-amber (mirror `chat-input.tsx:682`); keep
  type="submit"/aria/SVG.
- 3.5 Leave form/drag wrapper, attachment preview strip, error msg, hidden file input, and all
  handlers UNCHANGED.

## 4. Testing

- 4.1 Update `test/chat-input.test.tsx:136` `toContain("min-h-[40px]")` → new floor.
- 4.2 Update `test/chat-input-auto-grow.test.tsx:46` `toMatch(/min-h-\[40px\]/)` → new floor regex
  (leave `:44` negative `h-[\d+px]` guard and `:47` `max-h-[140px]` untouched).
- 4.3 `grep -rn "min-h-\[40px\]" apps/web-platform` returns zero.
- 4.4 Run web-platform vitest suite + `tsc --noEmit`; both green.
- 4.5 Capture AFTER screenshots; confirm all Acceptance Criteria visual gates.

## 5. Ship

- 5.1 Commit Part A + Part B + both test edits in ONE commit (the class change and its
  assertions must land atomically).
- 5.2 Open PR; attach before/after screenshots for the three surfaces.
