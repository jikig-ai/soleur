# Tasks: SEO & AEO for Docs Website

## Phase 1: Implementation

- [ ] 1.1 Update `plugins/soleur/docs/_includes/base.njk` -- add canonical URL, og:locale, Twitter/X card meta tags, enhanced OG tags (site_name, image dimensions, image alt)
- [ ] 1.2 Add JSON-LD structured data to `base.njk` -- WebSite + WebPage on all pages, SoftwareApplication on homepage only
- [ ] 1.3 Convert `plugins/soleur/docs/sitemap.njk` to collection-based with `<lastmod>` dates
- [ ] 1.4 Add `dateToRfc3339` Nunjucks filter to `eleventy.config.js`
- [ ] 1.5 Create `plugins/soleur/docs/llms.txt.njk` following llms-txt.org spec
- [ ] 1.6 Create `plugins/soleur/docs/_data/changelog.js` -- build-time changelog reader (ESM, resolve from CWD)
- [ ] 1.7 Update `plugins/soleur/docs/pages/changelog.njk` -- replace client-side JS with build-time rendered content
- [ ] 1.8 Create `plugins/soleur/agents/marketing/seo-aeo-analyst.md` with frontmatter, examples, analysis instructions
- [ ] 1.9 Create `plugins/soleur/skills/seo-aeo/SKILL.md` with audit/fix/validate sub-commands
- [ ] 1.10 Create `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` -- standalone CI validation script (chmod +x)
- [ ] 1.11 Update `plugins/soleur/docs/_data/skills.js` -- add seo-aeo to SKILL_CATEGORIES under "Content & Release"
- [ ] 1.12 Update `.github/workflows/deploy-docs.yml` -- add SEO validation step, add llms.txt to verify step, add skill path trigger
- [ ] 1.13 Create test file for `validate-seo.sh` -- mock _site/ with/without required elements, verify exit codes
- [ ] 1.14 Create test file for `changelog.js` -- verify returns content when CHANGELOG.md exists, empty when missing

## Phase 2: Ship

- [ ] 2.1 Build locally (`npx @11ty/eleventy`) and verify `_site/` output
- [ ] 2.2 Run `validate-seo.sh _site` locally -- must exit 0
- [ ] 2.3 Validate JSON-LD at schema.org validator
- [ ] 2.4 Verify `_site/llms.txt` content and `_site/pages/changelog.html` has rendered content
- [ ] 2.5 Run `bun test` -- all tests must pass
- [ ] 2.6 Version bump (MINOR) -- plugin.json, CHANGELOG.md, README.md (counts + tables)
- [ ] 2.7 Code review, /soleur:compound, commit, push, PR
