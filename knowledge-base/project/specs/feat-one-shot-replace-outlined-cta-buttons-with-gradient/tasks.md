# Tasks — feat: KB chat trigger gold-gradient CTA

Derived from `knowledge-base/project/plans/2026-05-06-feat-kb-chat-trigger-gold-gradient-cta-plan.md`.

## Phase 1 — Setup

1.1. Re-read `apps/web-platform/components/kb/kb-chat-trigger.tsx` (Edit tool requires a fresh read).
1.2. Re-read `apps/web-platform/app/(dashboard)/dashboard/page.tsx` lines 520-530 to confirm the source-of-truth gradient classes verbatim.

## Phase 2 — Core Implementation

2.1. Replace the `baseClass` constant in `kb-chat-trigger.tsx` (lines 36-37):
   - Remove: `border border-amber-500/50`, `text-amber-400`, `transition-colors`, `hover:border-amber-400`, `hover:text-amber-300`, and `font-medium`.
   - Add: `bg-gradient-to-r from-[#D4B36A] to-[#B8923E]`, `text-soleur-text-on-accent`, `font-semibold`, `transition-opacity`, `hover:opacity-90`.
   - Keep: `inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs`.
2.2. Recolor the thread-indicator dot (line 76):
   - Change `bg-amber-400` → `bg-soleur-text-on-accent`.
   - Keep `data-testid="kb-trigger-thread-indicator"`, `aria-hidden="true"`, `ml-1 inline-block h-1.5 w-1.5 rounded-full`.
2.3. Confirm the `<Link>` fallback at line 47 still consumes `baseClass` (no separate class string).

## Phase 3 — Testing & Verification

3.1. Run `bun test apps/web-platform/test/kb-chat-trigger.test.tsx`. Expect all 5 specs green (label switching, dot presence, fallback Link).
3.2. Run `bun test apps/web-platform/test/kb-content-header.test.tsx`. Expect green (no diff to header).
3.3. Run `bun test apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx`. Expect green.
3.4. Run `tsc --noEmit` from `apps/web-platform/`. Expect zero new errors.
3.5. Visual screenshot: load `/dashboard/knowledge-base/<any-doc>` in dev. Capture both states:
   - Empty thread → "Ask about this document" pill with no dot.
   - With messages → "Continue thread" pill with white dot.
   Compare side-by-side against `/dashboard` empty-state "New conversation".
3.6. Verify neighbors unchanged: `git diff main -- apps/web-platform/components/kb/kb-content-header.tsx apps/web-platform/components/kb/share-popover.tsx` returns empty.

## Phase 4 — Ship

4.1. Run `skill: soleur:compound` to capture any learnings.
4.2. Run `skill: soleur:ship` for review + QA + PR.

## Acceptance Criteria Mapping

- AC1 → 2.1
- AC2 → 2.2
- AC3 → 2.3
- AC4 → 3.6
- AC5 → 3.1, 3.2, 3.3
- AC6 → 3.5
- AC7 → 3.4
