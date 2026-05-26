# Session State

## Plan Phase
- Plan file: /home/harry/Documents/Stage/Soleur/soleur/.worktrees/feat-one-shot-theme-selector-reload-persistence/knowledge-base/project/plans/2026-05-06-fix-theme-selector-reload-persistence-and-active-state-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause: React 18 production hydration does NOT patch className/attribute mismatches when state matches between SSR and post-hydration client. PR #3318's lazy-init-as-canonical change eliminated the prior effect-driven re-render. SSR paints System-active className; client lazy-init returns correct value (e.g., Dark); no re-render fires → SSR's active className persists on System; React sets aria-pressed correctly on Dark → "two pills highlighted" screenshot.
- Chosen fix: canonical mounted-gate pattern (per `next-themes`). SSR and first client paint render NO segment as active (`data-active="false"` on every button); first useEffect flips `mounted=true`, post-hydration re-render lights up the correct segment. ~1-frame blip with no segment highlighted accepted.
- Phase 1 demoted to lightweight confirmation; AC4 (no nested provider) demoted to regression-prevention test (only one `<ThemeProvider>` mount confirmed).
- Playwright wiring confirmed at `apps/web-platform/playwright.config.ts` + `apps/web-platform/playwright/*.e2e.ts`. AC5 reload-persistence implementable as sibling `.e2e.ts`.
- `data-active` attribute introduced as test/agent probe; `aria-pressed` retained for a11y; className becomes visual-only.
- Threshold `none` justified (no auth/data/payment surfaces); no CPO sign-off required.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
