# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-website-visual-regressions/knowledge-base/project/plans/2026-04-27-fix-website-visual-regressions-and-add-pre-deploy-screenshot-gate-plan.md
- Status: complete

### Errors
None. Context7 quota was exhausted, so framework docs came from `WebFetch` (Playwright + web.dev) and direct file inspection instead.

### Decisions
- Root cause is PR #2904 (commit 5e74b560), not a recent SEO fix. The hand-extracted critical CSS only covers `/` and `/blog/<post>/`. Every other page (pricing, blog index, agents, skills, about, getting-started, community, changelog, vision, company-as-a-service, plus 9 legal sub-pages) renders in FOUC during the async stylesheet swap window. This is the second iteration of the same class within 8 hours; the existing learning didn't prevent recurrence per AGENTS.md `wg-when-a-workflow-gap-causes-a-mistake-fix`.
- Honeypot bug is site-wide, not pricing-only. `_includes/newsletter-form.njk` is included in `base.njk` on every page. The home page only "looks structurally okay" because its honeypot is below the fold.
- Fix strategy is option (A): widen the inline CSS + Playwright screenshot gate at `deploy-docs.yml`. Rejected (B) revert (loses LCP win), (C) build-time extractor (overkill for ~10 templates), (D) per-page conditional (maintenance burden). Option (C) filed as Post-MVP follow-up if inline block grows past 9KB.
- Playwright `waitUntil: 'domcontentloaded'` (not `'load'`) is the correct gate point per Playwright docs — `'load'` waits for the swapped stylesheet and would silently mask the FOUC. Verbatim CSS values copied from cited `style.css` line ranges.
- Prevention: Playwright screenshot gate in `deploy-docs.yml` + new AGENTS.md rule `cq-eleventy-critical-css-screenshot-gate`. Byte budget verified (AGENTS.md ~38360 pre-rule; rule ~580 bytes lands at ~38940, under 40000 critical threshold).

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- WebFetch (Playwright `page.goto` waitUntil docs; web.dev critical-CSS sizing)
- Bash, Read, Edit, Write
- ToolSearch (Playwright MCP, Context7)
