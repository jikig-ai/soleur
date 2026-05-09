# Session State

## Plan Phase
- Plan file: /home/harry/Documents/Stage/Soleur/soleur/.worktrees/feat-one-shot-theme-selector-gap-and-fouc-fixes/knowledge-base/project/plans/2026-05-06-fix-theme-selector-gap-and-fouc-plan.md
- Status: complete

### Errors
None.

### Decisions
- Issue 1 (gap): Single CSS-class change in `app/(dashboard)/layout.tsx:327` — `px-3 pt-3` → `p-3` so vertical rhythm matches the footer's `p-3` and the gap above and below the toggle are equal.
- Issue 2 (animation mismatch): Hand-port `next-themes`' `disableTransitionOnChange` pattern into `theme-provider.tsx` as `disableTransitionsForOneFrame()` called from `setTheme`, the data-theme `useEffect`, the cross-tab `storage` handler, AND the `prefers-color-scheme` listener. Add `animation-duration: 0s !important` to defend against the `pulse-border` keyframe.
- Issue 3 (FOUC): Augment `<NoFoucScript>` to write `documentElement.style.colorScheme` and `documentElement.style.backgroundColor` synchronously, and inject a transient `* { transition: none }` style at boot to prevent first-paint transitions on hydration. Hex literals duplicated from `globals.css` are guarded by a Phase 4.2 drift-guard test.
- TDD ordering: Tests land in commit 1 (RED), then implementation in commits 2–4. New test file `apps/web-platform/test/components/theme-no-fouc-script.test.tsx` plus an extension to `theme-provider.test.tsx`.
- Scope discipline: No tokenization changes, no `dark:`-prefix additions, no Eleventy-site fixes. User-Brand threshold: none. No CPO sign-off needed.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- mcp__plugin_soleur_context7__resolve-library-id + query-docs against /pacocoursey/next-themes
- WebSearch for Tailwind v4 + transition-colors + theme-switch flicker (Discussion #15598, Issue #16639)
- Read of adjacent learning 2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md
