# Tasks: fix(infra) deploy webhook disk full

## Phase 1: Immediate Recovery

- [x] 1.1 SSH to server and run `docker image prune -af` to free disk space (reclaimed 16.76GB)
- [x] 1.2 Verify root disk has >50% free space via `df -h /` (10% used, 66GB free)
- [ ] 1.3 Copy updated `ci-deploy.sh` to live server via SCP (after merge)
- [ ] 1.4 Re-run the web-platform release workflow or trigger a manual deploy
- [ ] 1.5 Verify production health endpoint reports correct version with low uptime
- [x] 1.6 Check telegram-bridge server disk usage and clean if needed (same host, no separate cleanup needed)

## Phase 2: Fix ci-deploy.sh Cleanup Logic

- [x] 2.1 Replace `docker system prune -f --filter "until=48h"` with `docker image prune -af` (no filter) in both web-platform and telegram-bridge deploy cases
- [x] 2.2 Add disk space pre-flight check (5GB minimum) before docker pull
- [x] 2.3 Run existing `ci-deploy.test.sh` tests to verify no regressions

## Phase 3: Fix Weekly Cron in cloud-init.yml

- [x] 3.1 Update weekly cron filter from `"until=168h"` to `"until=72h"` in `cloud-init.yml`

## Phase 4: Add Tests

- [x] 4.1 Add test case for disk space check rejection (mock `df` to return low space)
- [x] 4.2 Verify all tests pass including new test
- [x] 4.3 Run `npx markdownlint-cli2 --fix` on any changed `.md` files

## Phase 5: Ship

- [ ] 5.1 Run compound
- [ ] 5.2 Commit and push
- [ ] 5.3 Create PR with `Closes #1405`
- [ ] 5.4 Verify CI passes
- [ ] 5.5 Merge and verify deploy succeeds
