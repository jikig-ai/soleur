# Tasks: fix Dependabot alerts and prune stale .plugin/

Plan: `knowledge-base/project/plans/2026-05-09-fix-dependabot-alerts-and-prune-stale-plugin-dir-plan.md`
Branch: `feat-one-shot-dependabot-alerts-fix`
PR: #3488

## Phase 1: Delete orphaned `.plugin/`

- [x] 1.1 `git rm -r .plugin/` (entire directory)
- [x] 1.2 Verify `git ls-files .plugin/` returns empty
- [x] 1.3 Confirm `.openhands/` (active integration) is intact: `ls .openhands/skills/ | wc -l` should be > 0

## Phase 2: Bump deps in `apps/web-platform/`

- [x] 2.1 `cd apps/web-platform/ && npm update fast-uri` (scoped — NOT bare `npm update`)
- [x] 2.2 Verify `fast-uri` resolves to `>= 3.1.2` in `package-lock.json`
- [x] 2.3 `bun update fast-uri` — **DEFERRED in initial commit, then resolved during review.**
       `bun update <pkg>` injects the package as a direct `package.json` dependency (no
       `--no-save` for transitives), which the plan forbids. Initial commit shipped only
       the npm-side bump; review identified bun.lock divergence as a hygiene issue. The
       review-time fix surgically edited `bun.lock` to swap `fast-uri@3.1.0` → `3.1.2` with
       the registry sha, then validated via `bun install --frozen-lockfile`.
- [x] 2.4 Verify `fast-uri` resolves to `>= 3.1.2` in `bun.lock`
- [x] 2.5 `git diff --stat apps/web-platform/` shows ONLY `package-lock.json` + `bun.lock`

## Phase 3: Bump deps in `plugins/soleur/skills/pencil-setup/scripts/`

- [x] 3.1 `cd plugins/soleur/skills/pencil-setup/scripts/ && npm update fast-uri hono express-rate-limit`
       **NOTE:** Use `express-rate-limit` not `ip-address`. `express-rate-limit@8.3.1`
       pins `ip-address` at exact `"10.1.0"`, so `npm update ip-address` is a no-op.
       Bumping `express-rate-limit` to 8.5.1 pulls `ip-address: "^10.2.0"` transitively.
- [x] 3.2 Verify `fast-uri >= 3.1.2`, `hono >= 4.12.18`, `ip-address >= 10.1.1`,
       and `express-rate-limit >= 8.5.1` in `package-lock.json`
- [x] 3.3 Verify the express-rate-limit pin for ip-address changed from `"10.1.0"` (exact)
       to a caret/tilde range:
       `grep -A6 '"node_modules/express-rate-limit"' package-lock.json | grep ip-address`
       should show e.g. `"ip-address": "^10.2.0"`.
- [x] 3.4 Confirm no `bun.lock` exists in this directory (only `package-lock.json` regen needed)
- [x] 3.5 `git diff --stat plugins/soleur/skills/pencil-setup/scripts/` shows ONLY `package-lock.json`

## Phase 4: Verify

- [x] 4.1 `cd apps/web-platform && npm ci` exits 0 (lockfile integrity)
- [x] 4.2 `cd apps/web-platform && npm run typecheck` exits 0
- [x] 4.3 `git diff --stat` from repo root shows ONLY: `.plugin/**` deletions, three lockfiles modified, no `package.json` edits, no source edits

## Phase 5: Commit + ship

- [x] 5.1 `git add .plugin apps/web-platform/package-lock.json apps/web-platform/bun.lock plugins/soleur/skills/pencil-setup/scripts/package-lock.json`
- [x] 5.2 Commit: `fix(deps): resolve 18 Dependabot alerts; prune stale .plugin/ directory` (commit `0b7a2ae1`; review fixes in follow-up commit)
- [x] 5.3 `git push`
- [ ] 5.4 Update PR #3488 body — use `Ref` (not `Closes`) for any alert numbers; Dependabot alerts auto-close from the lockfile diff (handled by /ship)
- [ ] 5.5 `gh pr ready 3488` (handled by /ship)

## Phase 6: Post-merge verify

- [ ] 6.1 Within ~24h of merge, confirm 0 open alerts: `gh api repos/jikig-ai/soleur/dependabot/alerts --paginate | jq '[.[] | select(.state=="open")] | length'` returns `0`
- [ ] 6.2 `dependency-review.yml` workflow on the PR shows zero new high/critical findings
