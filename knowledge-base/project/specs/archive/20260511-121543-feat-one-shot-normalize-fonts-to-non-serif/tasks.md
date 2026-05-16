# Tasks — fix: normalize web-platform fonts to non-serif

Plan: `knowledge-base/project/plans/2026-05-11-fix-normalize-fonts-to-non-serif-plan.md`

## 1. Setup

- 1.1 Verify branch is `feat-one-shot-normalize-fonts-to-non-serif` and worktree is clean.
- 1.2 Run `rg "font-serif|Cormorant|Garamond|\\\${serif\\." apps/web-platform/` and snapshot the before-state count. Acceptance is "post-PR count = 0".
- 1.3 Confirm `bun test` passes on the worktree baseline before any edits.

## 2. Failing tests (TDD)

- 2.1 Add an assertion (or update an existing one) in `apps/web-platform/test/ready-state.test.tsx` that the rendered heading element does NOT carry the `mock-serif` className. This test fails today.
- 2.2 Same for `apps/web-platform/test/connect-repo-page.test.tsx` (assert no `mock-serif` on any rendered heading).
- 2.3 Same for `apps/web-platform/test/connect-repo-failed-state.test.tsx`.
- 2.4 Run `bun test` and confirm the three new assertions fail RED.

## 3. Core implementation

- 3.1 In `apps/web-platform/components/connect-repo/fonts.ts`:
    - Remove the `Cormorant_Garamond` import and the `serif` export.
    - Rename the Inter `variable` option from `"--font-sans"` to `"--font-inter"` (canonical Vercel + Tailwind v4 pattern).
- 3.2 (Recommended) Move `apps/web-platform/components/connect-repo/fonts.ts` → `apps/web-platform/app/fonts.ts`. Update import paths in `app/(auth)/connect-repo/page.tsx` and (new) `app/layout.tsx`.
- 3.3 In `apps/web-platform/app/layout.tsx`:
    - Import `sans` from `@/app/fonts` (or current location).
    - Apply `${sans.variable}` to the `<html>` element's className. Keep existing `lang="en" suppressHydrationWarning`. Do NOT add `${sans.className}` anywhere.
    - Leave `<body>` className unchanged (`bg-soleur-bg-base text-soleur-text-primary antialiased`).
- 3.4 In `apps/web-platform/app/globals.css`:
    - Add a new `@theme inline` block (alongside the existing `@theme` color block):

        ```css
        @theme inline {
          --font-sans: var(--font-inter), system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }
        ```

    - Inside the existing `@layer base { body { ... } }` rule, add `font-family: var(--font-sans);` so descendants without explicit `font-*` utilities inherit Inter.
- 3.5 In each of the four KB components, strip the `font-serif` Tailwind utility:
    - `components/kb/kb-sidebar-shell.tsx:18`
    - `components/kb/no-project-state.tsx:12`
    - `components/kb/empty-state.tsx:10`
    - `components/kb/workspace-not-ready.tsx:11`
- 3.6 In each of the ten connect-repo components, remove the `serif` import line and strip `${serif.className}` from heading classNames:
    - `components/connect-repo/create-project-state.tsx`
    - `components/connect-repo/ready-state.tsx`
    - `components/connect-repo/select-project-state.tsx`
    - `components/connect-repo/setting-up-state.tsx`
    - `components/connect-repo/choose-state.tsx`
    - `components/connect-repo/no-projects-state.tsx`
    - `components/connect-repo/github-redirect-state.tsx`
    - `components/connect-repo/github-resolve-state.tsx`
    - `components/connect-repo/failed-state.tsx`
    - `components/connect-repo/interrupted-state.tsx`
- 3.7 In `app/(auth)/connect-repo/page.tsx`:
    - Remove the entire `import { serif, sans } from ...` line (no longer needed — layout-level wiring covers it).
    - Strip `${serif.variable} ${sans.variable}` from the wrapper className (line 612).
    - Delete the entire `style={{ fontFamily: "var(--font-sans), system-ui, sans-serif" }}` attribute (line 613) — redundant with `@layer base` body rule.
- 3.8 In each of the three test files, remove the `Cormorant_Garamond: () => ({ ... })` entry from the `next/font/google` mock object:
    - `test/ready-state.test.tsx:9-11`
    - `test/connect-repo-page.test.tsx:20-22`
    - `test/connect-repo-failed-state.test.tsx:5-7`

## 4. Verification

- 4.1 Re-run the three failing tests from Phase 2; they pass GREEN.
- 4.2 Run `bun test` end-to-end in `apps/web-platform`; full suite passes.
- 4.3 Run `cd apps/web-platform && bun run build`; build is clean with no font-related warnings.
- 4.4 Run all three Acceptance Criteria greps and confirm zero matches:
    - `rg "font-serif" apps/web-platform/components apps/web-platform/app`
    - `rg "Cormorant|Garamond" apps/web-platform/`
    - `rg "\\\${serif\\." apps/web-platform/components apps/web-platform/app`
- 4.5 Start dev server (`bun run dev`), capture Playwright screenshots of the eight surfaces in Acceptance Criteria, confirm consistent Inter sans typeface across all.
- 4.6 Attach two before/after screenshot pairs to the PR body.

## 5. Ship prep

- 5.1 Run `skill: soleur:compound` to capture any learnings from the implementation session.
- 5.2 Run `skill: soleur:preflight` to clear the pre-ship gates.
- 5.3 Open PR with `Ref #<issue-if-filed>` in body (no `Closes` / `Fixes` keywords unless an issue is tracking).
- 5.4 In PR body, link to `knowledge-base/marketing/brand-guide.md` lines 249-257 and explicitly call out the brand-guide deviation. Request CMO review (label `domain/marketing` or assign per repo conventions).
- 5.5 File a follow-up issue: "Brand-guide reconciliation: dashboard sans-only vs Cormorant Garamond" — milestoned to current marketing phase. Include rationale and the chosen path from this PR.

## 6. Post-merge

- 6.1 CMO sign-off on the brand-guide deviation OR a follow-up PR updates lines 249-257 of the brand guide.
- 6.2 Verify production deployment renders sans on the eight surfaces (Playwright MCP smoke).
