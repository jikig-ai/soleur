# Tasks: fix docs build dateToShort filter

## Phase 1: Setup

- [ ] 1.1 Verify current build failure: run `npx @11ty/eleventy` from `plugins/soleur/docs/` and confirm filter error
- [ ] 1.2 Verify current build success: run `npx @11ty/eleventy` from repo root and confirm clean build

## Phase 2: Core Implementation

- [ ] 2.1 Create `plugins/soleur/docs/package.json` with `"type": "module"` and scripts using `cd ../../../ && npx @11ty/eleventy`
- [ ] 2.2 Verify `npm run docs:build` from `plugins/soleur/docs/` succeeds with full output (templates + passthrough copies)

## Phase 3: Testing

- [ ] 3.1 Run `npx @11ty/eleventy` from repo root -- build succeeds, `_site/sitemap.xml` has `YYYY-MM-DD` dates, passthrough copies present
- [ ] 3.2 Run `npm run docs:build` from `plugins/soleur/docs/` -- build succeeds with identical output
- [ ] 3.3 Verify bare `npx @11ty/eleventy` from docs dir still fails (expected -- the fix is the npm script)
- [ ] 3.4 Run markdown lint on any changed `.md` files
