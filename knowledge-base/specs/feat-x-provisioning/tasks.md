# Tasks: X/Twitter Account Provisioning via Ops-Provisioner

**Issue:** #474
**Plan:** [2026-03-09-feat-x-provisioning-plan.md](../../plans/2026-03-09-feat-x-provisioning-plan.md)

## Phase 1: Pre-provisioning Fixes

Fix SpecFlow-identified gaps before running the provisioning workflow.

### 1.1 Fix `x-setup.sh write-env` path resolution

- [ ] 1.1.1 Read `plugins/soleur/skills/community/scripts/x-setup.sh`
- [ ] 1.1.2 Change `local env_file=".env"` to resolve via `git rev-parse --show-toplevel` so `.env` is always at repo root regardless of cwd
- [ ] 1.1.3 Verify `.env` is in `.gitignore` at repo root (already confirmed, double-check)
- [ ] 1.1.4 Test: run `x-setup.sh write-env` from a worktree path, verify `.env` is created at repo root

### 1.2 Add `write-env-interactive` command to `x-setup.sh`

- [ ] 1.2.1 Add `cmd_write_env_interactive` function that prompts for each credential using `read -s` (silent input)
- [ ] 1.2.2 Prompt order: API Key, API Secret, Access Token, Access Token Secret
- [ ] 1.2.3 Validate each input is non-empty before proceeding
- [ ] 1.2.4 Call existing `cmd_write_env` logic after setting env vars internally
- [ ] 1.2.5 Add `write-env-interactive` to the usage/dispatch section
- [ ] 1.2.6 Test: run `write-env-interactive`, enter test values, verify `.env` contains them

### 1.3 Verify dependencies

- [ ] 1.3.1 Check `openssl`, `jq`, `curl` are available
- [ ] 1.3.2 Check `agent-browser` availability (note: optional, degraded mode is fine)

## Phase 2: Provisioning Execution

Run the ops-provisioner agent for X. This is the interactive phase with founder participation.

### 2.1 Handle availability check

- [ ] 2.1.1 Check `@soleur` availability on X (navigate to `x.com/soleur` or curl)
- [ ] 2.1.2 If taken, check `@soleur_ai`
- [ ] 2.1.3 Record chosen handle

### 2.2 Account registration

- [ ] 2.2.1 Invoke ops-provisioner with tool "X/Twitter", signup URL `https://x.com/i/flow/signup`
- [ ] 2.2.2 Founder completes registration (email, phone, CAPTCHA, password, DOB, handle)
- [ ] 2.2.3 Post-registration: set profile display name "Soleur", bio from brand guide
- [ ] 2.2.4 Verify account accessible at `x.com/<handle>`

### 2.3 Developer Portal setup

- [ ] 2.3.1 Navigate to `https://developer.x.com`
- [ ] 2.3.2 Founder applies for developer access (may require review wait)
- [ ] 2.3.3 Create project "Soleur"
- [ ] 2.3.4 Create app within project
- [ ] 2.3.5 Configure OAuth 1.0a: callback URL `https://soleur.ai`, website URL `https://soleur.ai`
- [ ] 2.3.6 Set app permissions to Read+Write

### 2.4 API key generation and validation

- [ ] 2.4.1 Generate Consumer Keys (API Key + API Secret)
- [ ] 2.4.2 Generate Access Token and Secret
- [ ] 2.4.3 Run `x-setup.sh write-env-interactive` -- founder pastes each credential
- [ ] 2.4.4 Run `x-setup.sh verify` -- confirm `GET /2/users/me` succeeds
- [ ] 2.4.5 If verify fails: diagnose (401 = bad credentials, 403 = wrong permissions, 429 = rate limit)

### 2.5 Expense recording

- [ ] 2.5.1 Update `knowledge-base/ops/expenses.md` with X API entry
- [ ] 2.5.2 Service: "X API", Provider: "X/Twitter", Category: "api", Amount: "0.00"
- [ ] 2.5.3 Notes: "Free tier (50 tweets/month, GET /2/users/me only)"
- [ ] 2.5.4 Update `last_updated` in frontmatter to today

## Phase 3: Post-provisioning Verification

### 3.1 Integration smoke test

- [ ] 3.1.1 Run `x-community.sh fetch-metrics` -- verify it returns follower/following/tweet counts
- [ ] 3.1.2 Run community skill `platforms` sub-command -- verify X is detected as enabled
- [ ] 3.1.3 Verify community agent can generate a multi-platform digest (X + existing platforms)

### 3.2 Commit and push

- [ ] 3.2.1 Run compound (`skill: soleur:compound`)
- [ ] 3.2.2 Commit code changes (x-setup.sh fixes) and knowledge-base updates (expenses.md)
- [ ] 3.2.3 Push to remote
