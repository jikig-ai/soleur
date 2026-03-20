# Tasks: Per-App Release Pipelines

**Plan:** `knowledge-base/project/plans/2026-03-19-feat-per-app-release-pipelines-plan.md`
**Issue:** #739
**Branch:** feat-app-versioning

## Phase 1: Prerequisites and Cleanup

- [x] 1.1 Normalize GHCR org in `apps/telegram-bridge/scripts/deploy.sh` and `apps/telegram-bridge/infra/variables.tf` to `jikig-ai` (lowercase)
- [x] 1.2 Fix `docker restart` bug in `apps/telegram-bridge/scripts/deploy.sh:16` — replace with stop/rm/run pattern
- [ ] 1.3 Create repository secrets via `gh secret set` — `TELEGRAM_BRIDGE_HOST` and `TELEGRAM_BRIDGE_SSH_KEY` (no Terraform state available; user must provide values manually)

## Phase 2: Reusable Release Workflow

- [x] 2.1 Create `.github/workflows/reusable-release.yml` with `workflow_call` inputs and outputs
  - [x] 2.1.1 `git fetch --tags` (shallow clone fix)
  - [x] 2.1.2 Path change detection step
  - [x] 2.1.3 PR extraction via `gh api commits/{sha}/pulls`
  - [x] 2.1.4 Bump type: `inputs.bump_type` override OR PR labels (semver:major > minor > patch, default patch)
  - [x] 2.1.5 Latest version via `git tag --list '<prefix>*' --sort=-version:refname | head -1`
  - [x] 2.1.6 Idempotency check (`gh release view "$TAG"`)
  - [x] 2.1.7 Changelog extraction from PR body
  - [x] 2.1.8 GitHub Release creation
  - [x] 2.1.9 Docker build+push (conditional on `docker_image` input)
  - [x] 2.1.10 Discord notification (truncate body to 1900 chars)
- [x] 2.2 Set `permissions: contents: write, packages: write`
- [x] 2.3 Pin all actions to commit SHAs
- [x] 2.4 Sanitize all `$GITHUB_OUTPUT` writes
- [x] 2.5 Set concurrency group `release-${{ inputs.component }}`

## Phase 3: Caller Workflows

- [x] 3.1 Create `.github/workflows/web-platform-release.yml` (caller + deploy job with health check)
- [x] 3.2 Create `.github/workflows/telegram-bridge-release.yml` (caller + deploy job with health check)

**Deferred:** Refactoring `version-bump-and-release.yml` to use the reusable workflow — follow-up PR after app workflows prove stable.

## Phase 4: `/ship` Skill Updates

- [x] 4.0 Create GitHub labels `app:web-platform` and `app:telegram-bridge`
- [x] 4.1 Update `plugins/soleur/skills/ship/SKILL.md` Phase 6 — add app path detection and `app:*` label application
- [x] 4.2 Update changelog generation to include app changes

## Phase 5: Seed Releases and Verification

- [ ] 5.1 Create seed releases: `web-v0.1.0` and `telegram-v0.1.0`
- [ ] 5.2 Trigger `workflow_dispatch` for each new workflow and verify
- [ ] 5.3 Verify Docker image tags on GHCR (3 tags: `v0.1.1`, `<sha>`, `latest`)
- [ ] 5.4 Verify Discord notifications

## Deferred to Separate Issues

- [ ] Refactor `version-bump-and-release.yml` to use reusable workflow (after stability proven)
- [ ] Add telegram-bridge Docker build test to CI (out of scope for #739)
- [x] Retire/repurpose `build-web-platform.yml` (feature-branch-only workflow) — deleted in #752

## Implementation Order

```
Phase 1 (prerequisites) → Phase 2 (reusable workflow) → Phase 3 (callers) → Phase 4 (/ship) → Phase 5 (verify)
```

Phases are sequential. Within Phase 1, tasks 1.1-1.2 can be parallelized. Phase 5 must run after merge to main.
