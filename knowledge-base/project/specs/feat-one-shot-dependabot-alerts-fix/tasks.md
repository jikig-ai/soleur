# Tasks: fix Dependabot alerts and prune stale .plugin/

Plan: `knowledge-base/project/plans/2026-05-09-fix-dependabot-alerts-and-prune-stale-plugin-dir-plan.md`
Branch: `feat-one-shot-dependabot-alerts-fix`
PR: #3488

## Phase 1: Delete orphaned `.plugin/`

- [ ] 1.1 `git rm -r .plugin/` (entire directory)
- [ ] 1.2 Verify `git ls-files .plugin/` returns empty
- [ ] 1.3 Confirm `.openhands/` (active integration) is intact: `ls .openhands/skills/ | wc -l` should be > 0

## Phase 2: Bump deps in `apps/web-platform/`

- [ ] 2.1 `cd apps/web-platform/ && npm update fast-uri` (scoped — NOT bare `npm update`)
- [ ] 2.2 Verify `fast-uri` resolves to `>= 3.1.2` in `package-lock.json`
- [ ] 2.3 `bun update fast-uri`
- [ ] 2.4 Verify `fast-uri` resolves to `>= 3.1.2` in `bun.lock`
- [ ] 2.5 `git diff --stat apps/web-platform/` shows ONLY `package-lock.json` + `bun.lock`

## Phase 3: Bump deps in `plugins/soleur/skills/pencil-setup/scripts/`

- [ ] 3.1 `cd plugins/soleur/skills/pencil-setup/scripts/ && npm update fast-uri hono ip-address`
- [ ] 3.2 Verify `fast-uri >= 3.1.2`, `hono >= 4.12.18`, `ip-address >= 10.1.1` in `package-lock.json`
- [ ] 3.3 Confirm no `bun.lock` exists in this directory (only `package-lock.json` regen needed)
- [ ] 3.4 `git diff --stat plugins/soleur/skills/pencil-setup/scripts/` shows ONLY `package-lock.json`

## Phase 4: Verify

- [ ] 4.1 `cd apps/web-platform && npm ci` exits 0 (lockfile integrity)
- [ ] 4.2 `cd apps/web-platform && npm run typecheck` exits 0
- [ ] 4.3 `git diff --stat` from repo root shows ONLY: `.plugin/**` deletions, three lockfiles modified, no `package.json` edits, no source edits

## Phase 5: Commit + ship

- [ ] 5.1 `git add .plugin apps/web-platform/package-lock.json apps/web-platform/bun.lock plugins/soleur/skills/pencil-setup/scripts/package-lock.json`
- [ ] 5.2 Commit: `fix(deps): resolve 18 Dependabot alerts; prune stale .plugin/ directory`
- [ ] 5.3 `git push`
- [ ] 5.4 Update PR #3488 body — use `Ref` (not `Closes`) for any alert numbers; Dependabot alerts auto-close from the lockfile diff
- [ ] 5.5 `gh pr ready 3488`

## Phase 6: Post-merge verify

- [ ] 6.1 Within ~24h of merge, confirm 0 open alerts: `gh api repos/jikig-ai/soleur/dependabot/alerts --paginate | jq '[.[] | select(.state=="open")] | length'` returns `0`
- [ ] 6.2 `dependency-review.yml` workflow on the PR shows zero new high/critical findings
