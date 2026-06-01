# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-gsc-sitemap-redirect-leak/knowledge-base/project/plans/2026-06-01-fix-gsc-sitemap-redirect-leak-plan.md
- Status: complete

### Errors
- CWD/worktree resolution trap (recovered): first Write targeted bare-root path, blocked by worktree-write guard; re-issued to explicit worktree path. Eleventy build ran from bare-root cwd, wrote _site/ there (cleaned; no stray artifact in worktree).
- Content-guard false trigger (recovered): literal `doppler secrets set` phrase in prose tripped IaC-routing guard; rephrased to "no secret-store mutation".

### Decisions
- HEADLINE: REQUIRED Eleventy build proved the hypothesized leak does NOT reproduce on HEAD. Generated _site/sitemap.xml has 0 `.html` <loc>, 0 `/pages/`, 48 trailing-slash apex URLs. Redirect stubs carry `eleventyExcludeFromCollections: true` (since #1851) so never enter collections.all — the `.endsWith(".html")` clause is inert. The 23 GSC URLs are dominated by Google's historical www/index.html/?ref=/legacy memory that correctly 3xx (the benign class the brief said not to chase).
- Reframed scope fix -> regression-hardening. Three small edits: (1) drop inert `.html` clause in sitemap.njk (defense-in-depth; drops zero canonical pages), (2) add redirect-stub assertion to validate-seo.sh (today allows `.html` <loc>), (3) add Bun-test regression case. New gate rides inside script already invoked by deploy-docs.yml L75 + CI — no new workflow step.
- Disproved Explore agent's "content pages output at /pages/*.html" theory against the build: `permalink: agents/` -> /agents/index.html. Only bare-`.html` outputs are excluded-from-collections stubs + 404.html.
- Test suite is bun:test using Bun.spawn(["bash", SCRIPT, TMP_DIR]); setupSite() has no sitemap override, so leak fixture must overwrite ${TMP_DIR}/sitemap.xml directly.
- Threshold none, single-domain docs/SEO; deepen-plan gates 4.4/4.45/4.6/4.7/4.8 all passed.

### Components Invoked
- Eleventy build + sitemap/_site/pages inspection (REQUIRED verification)
- GSC drilldown report read (Table.csv, Metadata.csv, Chart.csv)
- Skill soleur:plan
- Skill soleur:deepen-plan
