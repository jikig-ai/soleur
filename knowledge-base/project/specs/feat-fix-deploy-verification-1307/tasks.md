# Tasks: fix(deploy) resolve Docker build ERESOLVE and deploy-on-build-failure

## Phase 1: Investigation and Lockfile Fix (this PR)

### 1.1 Verify vite compatibility matrix

- [ ] Check `@vitejs/plugin-react@6.0.1` peer dependency on vite
- [ ] Check `vitest@3.x` peer dependency range for vite
- [ ] Determine if `vite@6` satisfies both (likely yes based on lockfile data)

### 1.2 Regenerate lockfiles

- [ ] Run `npm install` in `apps/web-platform/` to regenerate `package-lock.json`
- [ ] Run `bun install` in `apps/web-platform/` to regenerate `bun.lock`
- [ ] Verify `npm ci` succeeds with the updated lockfile
- [ ] Verify `bun install --frozen-lockfile` succeeds

### 1.3 Verify tests pass with updated dependencies

- [ ] Run `bun test` in `apps/web-platform/` to verify vitest works with vite@6
- [ ] Run `npm run typecheck` to verify TypeScript compilation

### 1.4 After merge, verify release workflow (automated via ship Phase 7)

- [ ] Monitor the release workflow triggered by the merge to main
- [ ] Verify Docker build step succeeds
- [ ] Verify deploy step fires and returns HTTP 202
- [ ] Verify health endpoint reports new version
- [ ] If auto-trigger skipped, run `gh workflow run web-platform-release.yml -f bump_type=patch`

## Phase 2: Workflow Fix (follow-up issue)

### 2.1 Add `docker_pushed` output to reusable-release.yml

- [ ] Add `docker_pushed` to workflow outputs
- [ ] Set `docker_pushed: 'true'` after the Docker build+push step succeeds
- [ ] Fix Docker build step condition: change from `released == 'true'` to `version != ''` so it runs on retry
- [ ] Ensure output is NOT set when Docker build fails or is skipped

### 2.2 Gate deploy on `docker_pushed` in web-platform-release.yml

- [ ] Replace `needs.release.outputs.version != ''` with `needs.release.outputs.docker_pushed == 'true'`
- [ ] Preserve migrate and skip_deploy conditions unchanged
- [ ] Verify condition logic handles retry case (release exists, Docker rebuilds)

### 2.3 Apply same fix to telegram-bridge-release.yml

- [ ] Check if telegram-bridge-release.yml has the same `always()` + version condition
- [ ] Apply consistent gating if applicable

## Phase 3: Preventive CI Check (follow-up issue)

### 3.1 Add lockfile sync check to PR CI

- [ ] Add a CI job that runs `npm install --package-lock-only` in `apps/web-platform/`
- [ ] Check for uncommitted changes to `package-lock.json`
- [ ] Fail with a clear error message if changes are detected
- [ ] Scope to only trigger when `apps/web-platform/package.json` changes

### 3.2 File issue for dual-lockfile evaluation

- [ ] Create issue to evaluate removing the bun/npm dual-lockfile setup
