# Tasks: SEO Bug Batch (#1121 #1122 #1123 #1124)

## Phase 1: Triage and Close False Positives

- [ ] 1.1 Close #1121 with explanation (false positive -- audit curl missing -L flag; Cloudflare Bot Fight Mode 301)
- [ ] 1.2 Close #1123 with explanation (false positive -- all 5 case studies already in feed via blog.json data cascade)
- [ ] 1.3 File new issue: fix SEO audit agent curl usage (add -L flag guidance to `plugins/soleur/agents/marketing/seo-aeo-analyst.md`)

## Phase 2: Fix #1122 -- Exclude feed.xml from sitemap

- [ ] 2.1 Edit `plugins/soleur/docs/sitemap.njk` to add `endsWith(".xml")` filter in the collections.all loop
- [ ] 2.2 Add non-HTML sitemap entry check to `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` (regression guard)
- [ ] 2.3 Run `npx @11ty/eleventy` and verify `_site/sitemap.xml` does not contain `feed.xml`
- [ ] 2.4 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and verify all checks pass (including new check)

## Phase 3: Fix #1124 -- Update author URL to /about/

- [ ] 3.1 Edit `plugins/soleur/docs/_data/site.json` to change `site.author.url` from `"https://soleur.ai"` to `"https://soleur.ai/about/"`
- [ ] 3.2 Run `npx @11ty/eleventy` and verify blog post HTML shows author link to `https://soleur.ai/about/`
- [ ] 3.3 Verify JSON-LD `BlogPosting.author.url` renders as `https://soleur.ai/about/` in blog posts
- [ ] 3.4 Verify JSON-LD `SoftwareApplication.author.url` renders as `https://soleur.ai/about/` on homepage
- [ ] 3.5 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and verify all checks pass

## Phase 4: Validate and Ship

- [ ] 4.1 Full local build passes (`npx @11ty/eleventy`)
- [ ] 4.2 Full SEO validation passes (`validate-seo.sh`)
- [ ] 4.3 Run compound
- [ ] 4.4 Commit and push
- [ ] 4.5 Create PR (Closes #1122, Closes #1124; references #1121, #1123 as false positives)
