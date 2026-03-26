# Tasks: SEO Bug Batch (#1121 #1122 #1123 #1124)

## Phase 1: Triage and Close False Positives

- [ ] 1.1 Close #1121 with explanation (false positive -- audit curl missing -L flag)
- [ ] 1.2 Close #1123 with explanation (false positive -- case studies already in feed)
- [ ] 1.3 File new issue: fix SEO audit agent curl usage (add -L flag to follow redirects)

## Phase 2: Fix #1122 -- Exclude feed.xml from sitemap

- [ ] 2.1 Edit `plugins/soleur/docs/sitemap.njk` to filter out `.xml` entries from `collections.all`
- [ ] 2.2 Run `npx @11ty/eleventy` and verify `_site/sitemap.xml` does not contain `feed.xml`
- [ ] 2.3 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and verify all checks pass

## Phase 3: Fix #1124 -- Update author URL to /about/

- [ ] 3.1 Edit `plugins/soleur/docs/_data/site.json` to change `site.author.url` from `"https://soleur.ai"` to `"https://soleur.ai/about/"`
- [ ] 3.2 Run `npx @11ty/eleventy` and verify blog post HTML shows author link to `/about/`
- [ ] 3.3 Verify JSON-LD `BlogPosting.author.url` renders as `https://soleur.ai/about/`
- [ ] 3.4 Run `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` and verify all checks pass

## Phase 4: Validate and Ship

- [ ] 4.1 Full local build passes (`npx @11ty/eleventy`)
- [ ] 4.2 SEO validation passes
- [ ] 4.3 Run compound
- [ ] 4.4 Commit and push
- [ ] 4.5 Create PR (Closes #1122, Closes #1124; references #1121, #1123 as false positives)
