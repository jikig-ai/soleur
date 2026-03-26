# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-seo-bug-fixes-1121-1122-1123-1124/knowledge-base/project/plans/2026-03-26-fix-seo-bug-batch-1121-1122-1123-1124-plan.md
- Status: complete

### Errors

None

### Decisions

- **#1121 (meta tags missing in production): FALSE POSITIVE.** The SEO audit agent used `curl -s` without `-L`, getting a Cloudflare 301 redirect page instead of actual content. All meta tags are present in both local build and live production (when following redirects).
- **#1122 (feed.xml in sitemap): REAL BUG.** Fix by adding `endsWith(".xml")` filter in `sitemap.njk`. The Eleventy RSS plugin sets `eleventyExcludeFromCollections: ["blog"]` (array, not `true`), so feed.xml remains in `collections.all`. Template-level filtering is the correct approach since the plugin's exclusion config is not externally configurable.
- **#1123 (case studies missing from feed): FALSE POSITIVE.** All 5 case studies inherit the `blog` tag from `blog/blog.json` via Eleventy's directory data cascade. Verified in both local build (12 entries) and live production feed.
- **#1124 (author URL points to homepage): REAL BUG, implement partial fix now.** Update `site.author.url` to `https://soleur.ai/about/` ahead of the About page creation (scheduled Apr 10-16). The 404 experience is acceptable and the URL will auto-resolve when the About page is created.
- **Added regression guard:** New `validate-seo.sh` check to catch non-HTML sitemap entries in CI, preventing future regressions from Eleventy plugins that add non-HTML outputs to `collections.all`.

### Components Invoked

- `skill: soleur:plan` (plan creation)
- `skill: soleur:deepen-plan` (plan enhancement with research)
- Context7 MCP for Eleventy v3 documentation
- Local Eleventy build for reproduction testing
- Live production verification for all 4 issues
- Learnings archive scan (5 relevant learnings)
- SEO audit agent source analysis
- Eleventy RSS plugin source analysis
