# Tasks: CI Release Reliability Overhaul

## Phase 1: Docker Image Cleanup

- [x] 1.1 Add `docker system prune -f --filter "until=48h"` before `docker pull` in the `web-platform` case block of `apps/web-platform/infra/ci-deploy.sh:72`
- [x] 1.2 Add `docker system prune -f --filter "until=48h"` before `docker pull` in the `telegram-bridge` case block of `apps/web-platform/infra/ci-deploy.sh:98`
- [x] 1.3 Add test to `apps/web-platform/infra/ci-deploy.test.sh` verifying prune runs before pull for web-platform deploys
- [x] 1.4 Add test to `apps/web-platform/infra/ci-deploy.test.sh` verifying prune runs before pull for telegram-bridge deploys
- [x] 1.5 Run `bash apps/web-platform/infra/ci-deploy.test.sh` and verify all tests pass (existing + new)

## Phase 2: Deploy Concurrency Groups

- [x] 2.1 Add `concurrency: { group: deploy-production, cancel-in-progress: false }` to the deploy job in `.github/workflows/web-platform-release.yml:40`
- [x] 2.2 Add `concurrency: { group: deploy-production, cancel-in-progress: false }` to the deploy job in `.github/workflows/telegram-bridge-release.yml:35`

## Phase 3: Path Filters on Push Triggers

- [x] 3.1 Read `scripts/post-bot-statuses.sh` to understand synthetic status check behavior with path-filtered workflows
- [x] 3.2 Add `paths: ['apps/web-platform/**']` to `on.push` in `.github/workflows/web-platform-release.yml`
- [x] 3.3 Add `paths: ['apps/telegram-bridge/**']` to `on.push` in `.github/workflows/telegram-bridge-release.yml`
- [x] 3.4 Read `.github/workflows/version-bump-and-release.yml` to check existing `on.push` trigger structure
- [x] 3.5 Add `paths: ['plugins/soleur/**', 'plugin.json']` to `on.push` in `.github/workflows/version-bump-and-release.yml`
- [x] 3.6 Update `scripts/post-bot-statuses.sh` if needed to handle workflows that never start (vs start-and-skip) — NOT NEEDED: post-bot-statuses.sh only posts cla-check and test statuses, release workflows are not required status checks

## Phase 4: Deploy Retry

- [x] 4.1 Change deploy job `if` in `.github/workflows/web-platform-release.yml:42` from `needs.release.outputs.released == 'true'` to `needs.release.outputs.version != ''`
- [x] 4.2 Preserve the `skip_deploy` check: new condition should be `needs.release.outputs.version != '' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)`
- [x] 4.3 Change deploy job `if` in `.github/workflows/telegram-bridge-release.yml:37` from `needs.release.outputs.released == 'true'` to `needs.release.outputs.version != ''`

## Phase 5: Verification

- [x] 5.1 Run `bash apps/web-platform/infra/ci-deploy.test.sh` — all tests pass (22/22)
- [x] 5.2 Verify YAML syntax of all modified workflow files (check for indentation errors) — validated via python yaml.safe_load
- [ ] 5.3 Commit and push for CI validation
