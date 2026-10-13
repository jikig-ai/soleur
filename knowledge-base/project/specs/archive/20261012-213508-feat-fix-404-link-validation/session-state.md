# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-03-24-fix-404-link-validation-plan.md
- Status: complete

### Errors

None

### Decisions

- Root cause identified: `social-distribute` skill constructs URLs by naively stripping the file path prefix, but Eleventy's `TemplateFileSlug._stripDateFromSlug` strips `YYYY-MM-DD-` date prefixes from `page.fileSlug`. The regex is `/\d{4}-\d{2}-\d{2}-(.*)/`.
- Fix 6 removed as overengineered: Running a full Eleventy build during `social-distribute` execution adds latency for no safety benefit. Root cause fix + CI validation provides same coverage.
- UTM campaign slugs also affected: The `utm_campaign` parameter in distribution content URLs also contains the date prefix and must be fixed alongside the URL path.
- 4 articles affected, 3 already published with broken links: `soleur-vs-anthropic-cowork`, `soleur-vs-notion-custom-agents`, `soleur-vs-cursor` (published), `vibe-coding-vs-agentic-engineering` (scheduled for today).
- Prevention strategy: New `validate-blog-links.sh` script (following `validate-seo.sh` patterns) added to both CI and content generator workflow.

### Components Invoked

- soleur:plan
- soleur:deepen-plan
- WebFetch (URL verification)
- Context7 (Eleventy docs)
- Eleventy build (output path confirmation)
- Eleventy source code analysis
