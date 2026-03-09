# Tasks: X/Twitter Account Provisioning via Ops-Provisioner

**Issue:** #474
**Plan:** [2026-03-09-feat-x-provisioning-plan.md](../../plans/2026-03-09-feat-x-provisioning-plan.md)

## Phase 1: Fix `.env` Path Resolution

- [ ] 1.1 Fix `x-setup.sh`: change relative `.env` path to use `git rev-parse --show-toplevel` in `cmd_write_env` and `cmd_verify`
- [ ] 1.2 Fix `discord-setup.sh`: same `.env` path fix for consistency

## Phase 2: Provisioning

- [ ] 2.1 Founder checks `@soleur` handle availability manually (visit `x.com/soleur`)
- [ ] 2.2 Invoke ops-provisioner for X account registration (signup URL: `https://x.com/i/flow/signup`)
- [ ] 2.3 Invoke ops-provisioner for Developer Portal + API keys (configure OAuth 1.0a, Read+Write permissions)
- [ ] 2.4 Run `x-setup.sh write-env` with credentials, then `x-setup.sh verify`
- [ ] 2.5 Ops-provisioner records X API in expense ledger

## Phase 3: Commit

- [ ] 3.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2 Commit code changes (path fix) and knowledge-base updates (expenses.md)
- [ ] 3.3 Push to remote
