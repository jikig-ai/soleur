# Tag-Only Versioning Tasks

**Plan:** [2026-03-03-fix-tag-only-versioning-plan.md](../../plans/2026-03-03-fix-tag-only-versioning-plan.md)
**Issue:** #410
**PR:** #412

## Tasks

### Phase 1: Simplify release workflow and delete CHANGELOG.md

- [ ] T1: Rewrite "Compute next version" to use `gh release view` instead of `plugin.json`
- [ ] T2: Delete steps: "Configure git", "Compute component counts", "Update version files", "Verify version consistency", "Commit and push"
- [ ] T3: Remove explicit `gh workflow run deploy-docs.yml` trigger (redundant with `workflow_run`)
- [ ] T4: `git rm plugins/soleur/CHANGELOG.md`
- [ ] T5: Update `deploy-docs.yml`: remove CHANGELOG.md and plugin.json path triggers, add GITHUB_TOKEN env to build step

### Phase 2: Rewrite docs data files

- [ ] T6: Create `plugins/soleur/docs/_data/github.js` — single shared GitHub API fetch
- [ ] T7: Rewrite `changelog.js` to delegate to `github.js`
- [ ] T8: Rewrite `plugin.js` to overlay version from `github.js`
- [ ] T9: Add "View all releases" link to `changelog.njk`
- [ ] T10: Verify Eleventy builds with async data files (`npm install && npx @11ty/eleventy`)

### Phase 3: Update static files and documentation

- [ ] T11: Freeze `plugin.json` version to `"0.0.0-dev"`, remove counts from description
- [ ] T12: Freeze `marketplace.json` `plugins[0].version` to `"0.0.0-dev"`
- [ ] T13: Replace README.md version badge with dynamic shields.io
- [ ] T14: Rewrite "Versioning Requirements" in `plugins/soleur/AGENTS.md`
- [ ] T15: Update "Workflow Gates" in root `AGENTS.md`
- [ ] T16: Update `constitution.md` references to "6 files at merge time"
- [ ] T17: Delete 3 obsolete learnings files
- [ ] T18: Rewrite `2026-03-03-serialize-version-bumps-to-merge-time.md`
- [ ] T19: File GitHub issue for Discord webhook missing `username`/`avatar_url`
