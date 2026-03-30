# Tasks: Triage Dependabot Alerts

## Phase 1: Runtime Upgrades

- [ ] 1.1 Upgrade Next.js to >=15.5.14 in `apps/web-platform/package.json`
  - [ ] 1.1.1 Run `npm install next@latest` in `apps/web-platform/`
  - [ ] 1.1.2 Regenerate `apps/web-platform/bun.lock` with `bun install`
  - [ ] 1.1.3 Regenerate `apps/web-platform/package-lock.json` with `npm install`
  - [ ] 1.1.4 Verify build: `cd apps/web-platform && npm run build`
- [ ] 1.2 Upgrade Pillow to 12.1.1 in `plugins/soleur/skills/gemini-imagegen/requirements.txt`
  - [ ] 1.2.1 Update pin from `Pillow==11.3.0` to `Pillow==12.1.1`
  - [ ] 1.2.2 Verify install: `pip install -r plugins/soleur/skills/gemini-imagegen/requirements.txt`
- [ ] 1.3 Upgrade path-to-regexp to 8.4.0 in `plugins/soleur/skills/pencil-setup/scripts/`
  - [ ] 1.3.1 Run `npm update` in `plugins/soleur/skills/pencil-setup/scripts/`
  - [ ] 1.3.2 Verify: `npm ls path-to-regexp` shows 8.4.0

## Phase 2: Dev-Only Upgrades

- [ ] 2.1 Attempt liquidjs upgrade via Eleventy update
  - [ ] 2.1.1 Check latest `@11ty/eleventy` version and whether it pulls liquidjs >=10.25.0
  - [ ] 2.1.2 If yes, update `package.json` and regenerate lockfile
  - [ ] 2.1.3 If no, note that alerts #15, #16 have no patch available
  - [ ] 2.1.4 Verify docs build: `npm run docs:build`
- [ ] 2.2 Regenerate root `package-lock.json` to pull minimatch 3.1.3, picomatch patches
  - [ ] 2.2.1 Run `npm update minimatch picomatch` at root
  - [ ] 2.2.2 Verify lockfile has minimatch >=3.1.3 and picomatch >=2.3.2
- [ ] 2.3 Regenerate `apps/web-platform/` lockfiles for flatted 3.4.2, picomatch patches
  - [ ] 2.3.1 Run `npm update flatted picomatch` in `apps/web-platform/`
  - [ ] 2.3.2 Regenerate bun.lock
  - [ ] 2.3.3 Verify flatted >=3.4.2 in lockfile

## Phase 3: Dismissals

- [ ] 3.1 Dismiss esbuild alert #1 via GitHub API with justification
- [ ] 3.2 Dismiss liquidjs alerts #15, #16 if no patch available (after Phase 2.1)
- [ ] 3.3 Consider adding `allow-ghsas` entries to `dependency-review.yml` for dismissed advisories

## Phase 4: Verification

- [ ] 4.1 Run `gh api repos/jikig-ai/soleur/dependabot/alerts --jq '[.[] | select(.state == "open")] | length'` -- confirm 0 open or only dismissed
- [ ] 4.2 Full build verification for `apps/web-platform/`
- [ ] 4.3 Docs build verification
- [ ] 4.4 Commit all changes with clear message referencing #1309
