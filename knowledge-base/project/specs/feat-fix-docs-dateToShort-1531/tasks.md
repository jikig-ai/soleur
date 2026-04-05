# Tasks: fix docs build dateToShort filter

## Phase 1: Setup

- [ ] 1.1 Verify current build failure: run `npx @11ty/eleventy` from `plugins/soleur/docs/` and confirm filter error
- [ ] 1.2 Verify current build success: run `npx @11ty/eleventy` from repo root and confirm clean build

## Phase 2: Core Implementation

- [ ] 2.1 Create `plugins/soleur/docs/eleventy.config.js` with `dateToShort` filter registration
- [ ] 2.2 Ensure the local config sets correct `dir.input` (`.` since CWD is already the docs dir) and `dir.output` to match expected output location
- [ ] 2.3 Verify no duplicate filter warnings when running from repo root (root config is what Eleventy uses from root -- the docs-local config is only loaded when CWD is docs)

## Phase 3: Testing

- [ ] 3.1 Run `npx @11ty/eleventy` from repo root -- build succeeds, `_site/sitemap.xml` has `YYYY-MM-DD` dates
- [ ] 3.2 Run `npx @11ty/eleventy` from `plugins/soleur/docs/` -- build succeeds, `_site/sitemap.xml` has `YYYY-MM-DD` dates
- [ ] 3.3 Verify `sitemap.xml` content is identical in both scenarios (same entries, same dates)
- [ ] 3.4 Run markdown lint on any changed `.md` files
