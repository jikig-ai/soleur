# Tasks: X/Twitter Account Provisioning via Ops-Provisioner

**Issue:** #474
**Plan:** [2026-03-09-feat-x-provisioning-plan.md](../../plans/2026-03-09-feat-x-provisioning-plan.md)

## Phase 1: Fix `.env` Path Resolution

- [x] 1.1 Fix `x-setup.sh`: change relative `.env` path to use `git rev-parse --show-toplevel` in `cmd_write_env` and `cmd_verify`
- [x] 1.2 Fix `discord-setup.sh`: same `.env` path fix for consistency

## Phase 2: Provisioning

- [x] 2.1 Founder checks `@soleur` handle availability manually -- taken, using `@soleur_ai`
- [x] 2.2 Invoke ops-provisioner for X account registration (signup URL: `https://x.com/i/flow/signup`) -- @soleur_ai registered via Playwright MCP
- [x] 2.3 Invoke ops-provisioner for Developer Portal + API keys (configure OAuth 1.0a, Read+Write permissions) -- app created, OAuth 1.0a configured
- [x] 2.4 Run `x-setup.sh write-env` with credentials, then `x-setup.sh verify` -- verified: @soleur_ai (Soleur)
- [x] 2.5 Ops-provisioner records X API in expense ledger -- added to expenses.md

## Phase 3: Commit

- [x] 3.1 Run compound (`skill: soleur:compound`) -- learning captured, ops-provisioner updated
- [x] 3.2 Commit code changes (path fix) and knowledge-base updates (expenses.md)
- [x] 3.3 Push to remote
