# Tasks: CI Release Reliability Overhaul

## Phase 1: Docker Image Cleanup

- [ ] 1.1 Add `docker system prune -f --filter "until=48h"` before `docker pull` in the `web-platform` case block of `apps/web-platform/infra/ci-deploy.sh:72`
- [ ] 1.2 Add `docker system prune -f --filter "until=48h"` before `docker pull` in the `telegram-bridge` case block of `apps/web-platform/infra/ci-deploy.sh:98`
- [ ] 1.3 Add test to `apps/web-platform/infra/ci-deploy.test.sh` verifying prune runs before pull for web-platform deploys
- [ ] 1.4 Add test to `apps/web-platform/infra/ci-deploy.test.sh` verifying prune runs before pull for telegram-bridge deploys
- [ ] 1.5 Run `bash apps/web-platform/infra/ci-deploy.test.sh` and verify all tests pass (existing + new)

## Phase 2: Deploy Concurrency Groups

- [ ] 2.1 Add `concurrency: { group: deploy-production, cancel-in-progress: false }` to the deploy job in `.github/workflows/web-platform-release.yml:40`
- [ ] 2.2 Add `concurrency: { group: deploy-production, cancel-in-progress: false }` to the deploy job in `.github/workflows/telegram-bridge-release.yml:35`

## Phase 3: Path Filters on Push Triggers

- [ ] 3.1 Read `scripts/post-bot-statuses.sh` to understand synthetic status check behavior with path-filtered workflows
- [ ] 3.2 Add `paths: ['apps/web-platform/**']` to `on.push` in `.github/workflows/web-platform-release.yml`
- [ ] 3.3 Add `paths: ['apps/telegram-bridge/**']` to `on.push` in `.github/workflows/telegram-bridge-release.yml`
- [ ] 3.4 Read `.github/workflows/version-bump-and-release.yml` to check existing `on.push` trigger structure
- [ ] 3.5 Add `paths: ['plugins/soleur/**', 'plugin.json']` to `on.push` in `.github/workflows/version-bump-and-release.yml`
- [ ] 3.6 Update `scripts/post-bot-statuses.sh` if needed to handle workflows that never start (vs start-and-skip)

## Phase 4: Deploy Retry

- [ ] 4.1 Change deploy job `if` in `.github/workflows/web-platform-release.yml:42` from `needs.release.outputs.released == 'true'` to `needs.release.outputs.version != ''`
- [ ] 4.2 Preserve the `skip_deploy` check: new condition should be `needs.release.outputs.version != '' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)`
- [ ] 4.3 Change deploy job `if` in `.github/workflows/telegram-bridge-release.yml:37` from `needs.release.outputs.released == 'true'` to `needs.release.outputs.version != ''`

## Phase 5: Verification

- [ ] 5.1 Run `bash apps/web-platform/infra/ci-deploy.test.sh` — all tests pass
- [ ] 5.2 Verify YAML syntax of all modified workflow files (check for indentation errors)
- [ ] 5.3 Commit and push for CI validation
