---
title: "Tasks — fix follow-up composer gold focus highlight"
branch: feat-one-shot-fix-followup-input-gold-focus-highlight
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-04-fix-followup-composer-gold-focus-highlight-plan.md
status: planned
---

# Tasks — Remove double gold focus highlight on the follow-up chat composer

Derived from `2026-06-04-fix-followup-composer-gold-focus-highlight-plan.md` (post-review).

## Phase 1 — Setup & verification

- [ ] 1.1 Confirm working tree on branch `feat-one-shot-fix-followup-input-gold-focus-highlight`.
- [ ] 1.2 Backstop overlap check: `gh issue list --label code-review --state open --json number,title,body --limit 200` and grep for `chat-input.tsx` / `globals.css`. Record None or fold/ack/defer.
- [ ] 1.3 Re-read `apps/web-platform/components/chat/chat-input.tsx:604-647` and `apps/web-platform/app/globals.css:158-170` before editing (hr-always-read-a-file-before-editing-it).

## Phase 2 — Failing test first (RED)

- [ ] 2.1 Add a focus-styling test in `apps/web-platform/test/chat-input.test.tsx` (or `test/chat-input-focus.test.tsx` — must match `test/**/*.test.tsx`): render `<ChatInput>`, assert composer container className does NOT contain `border-soleur-border-emphasized` and DOES contain a neutral `focus-within:` utility. (AC6)
- [ ] 2.2 Run `vitest` for the file; confirm it fails (RED) against current code.

## Phase 3 — Core fix (GREEN)

- [ ] 3.1 Edit A: in `chat-input.tsx:606`, replace `focus-within:border-soleur-border-emphasized` with `focus-within:border-soleur-text-muted` (border-color shift only). Preserve the `flashQuote ? " ring-2 ring-amber-400"` branch verbatim. (AC1b, AC2, AC4)
- [ ] 3.2 Edit B (default B1): add `focus-visible:shadow-none` to the textarea className (`chat-input.tsx:646`) to suppress the inherited global gold box-shadow. Preserve `min-h-[36px]` / `max-h-[140px]`. (AC1a, AC5)
- [ ] 3.3 Verify B1 cascade win: confirm in the built output / browser that the textarea no longer shows the gold ring on focus. If the Tailwind utility loses to the `@layer base` rule, fall back to B2 (add `data-chat-composer-input` to the textarea + a scoped `box-shadow: none` reset in `globals.css` right after lines 164-169 — do NOT alter the global rule itself).
- [ ] 3.4 Confirm `globals.css:164-169` and all `--soleur-*` tokens are byte-unchanged (skip globals.css entirely if B1 works). (AC3)
- [ ] 3.5 Run the new test; confirm GREEN.

## Phase 4 — Full verification

- [ ] 4.1 `vitest` for `chat-input.test.tsx`, `chat-input-quote.test.tsx`, `chat-input-auto-grow.test.tsx`; all pass. (AC4, AC5, AC7)
- [ ] 4.2 `tsc --noEmit` clean; no new lint errors. (AC7)
- [ ] 4.3 Visual verification (Playwright MCP / `/soleur:qa`): screenshot focused composer in dark theme — single subtle non-gold focus state. Check empty vs. with-content states; confirm Send button amber fill (`bg-amber-600`) unaffected. (AC8)
- [ ] 4.4 `git diff globals.css` shows no change to the global focus-visible block (or no globals.css change at all). (AC3)

## Phase 5 — Ship

- [ ] 5.1 Run `/soleur:review` / QA before merge (rf-never-skip-qa-review-before-merging).
- [ ] 5.2 PR body uses `Closes #<issue>` if an issue exists; attach AC8 screenshot.
