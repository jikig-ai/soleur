---
title: "feat: X/Twitter account provisioning via ops-provisioner"
type: feat
date: 2026-03-09
semver: patch
---

# feat: X/Twitter Account Provisioning via Ops-Provisioner

## Overview

Provision the X/Twitter account, Developer Portal, and API keys using the ops-provisioner agent's guided workflow. The X integration code (PR #466) is complete but inert -- all scripts exist, no credentials do. This is the third use of ops-provisioner (after Cloudflare and Plausible) and the first multi-stage provisioning.

Closes #474.

## Problem Statement / Motivation

The community-manager agent has X/Twitter code (`x-community.sh`, `x-setup.sh`) that cannot be tested or used because no X account exists. Two verification tasks in `knowledge-base/specs/feat-community-agent-x/tasks.md` are explicitly blocked on account registration. The ops-provisioner exists to handle exactly this workflow but has only been tested with single-stage provisioning (Plausible).

## Proposed Solution

Invoke the ops-provisioner with X as the target tool, walking through 4 stages sequentially. Fix gaps discovered by SpecFlow analysis before executing.

### SpecFlow-Identified Fixes (Pre-provisioning)

SpecFlow found 3 issues that must be fixed before provisioning can succeed:

1. **`x-setup.sh write-env` uses relative `.env` path** -- When run from a worktree, credentials land in the wrong directory. Fix: use `git rev-parse --show-toplevel` to resolve the repo root, or accept an `--env-file` flag.

2. **No interactive credential input mechanism** -- `write-env` reads from env vars, but the agent cannot set env vars for the user's shell. The founder would need to manually export 4 variables. Fix: add a `write-env-interactive` command that uses `read -s` (silent input) to prompt for each credential.

3. **Display name pre-fill targets wrong step** -- X's signup page shows email/phone entry, not display name. Display name is set in profile settings after account creation. Fix: move display name pre-fill to a post-registration profile setup step.

### Provisioning Stages (Corrected)

**Stage 1: Handle Availability Check**
- Navigate to `https://x.com/soleur` via agent-browser (or provide URL in degraded mode)
- Check page content for "This account doesn't exist" indicator
- If taken, check `https://x.com/soleur_ai`
- If both taken, ask founder to choose a handle manually
- Degraded mode: print URLs for manual browser check

**Stage 2: Account Registration**
- agent-browser opens `https://x.com/i/flow/signup`
- Founder completes entire signup flow manually (email, phone, CAPTCHA, password, DOB, handle)
- Post-registration: agent-browser navigates to profile settings, pre-fills display name "Soleur" and bio from brand guide
- Validation: navigate to `https://x.com/<handle>` and verify profile loads

**Stage 3: Developer Portal + API Keys** (3 sub-stages with pause points)
- **3a: Developer Account Application** -- Navigate to `https://developer.x.com`, founder applies for developer access. If approval requires review, pause and tell founder to re-invoke when approved.
- **3b: Project/App Creation + OAuth Config** -- Create project and app. Configure OAuth 1.0a: callback URL `https://soleur.ai`, website URL `https://soleur.ai`, permissions Read+Write.
- **3c: Token Generation + Validation** -- Navigate to Keys and Tokens page. Founder generates and copies 4 credentials. Run `x-setup.sh write-env-interactive` (prompts for each credential with silent input). Run `x-setup.sh verify` to validate via `GET /2/users/me`.

**Stage 4: Expense Recording**
- ops-provisioner updates `knowledge-base/ops/expenses.md` directly (following ops-advisor conventions)
- Record: Service "X API", Provider "X/Twitter", Category "api", Amount "0.00", Notes "Free tier (50 tweets/month, GET /2/users/me only)"
- Update `last_updated` to today
- Note: ledger reconciliation (Plausible trial, Hetzner renewal) is out of scope -- tracked separately

## Technical Considerations

- **Security:** `write-env-interactive` uses `read -s` to suppress credential echo. Credentials never appear in terminal output, CLI args, or agent logs. `.env` file gets `chmod 600` before writing (existing behavior).
- **Worktree path:** `x-setup.sh` must resolve `.env` to repo root via `git rev-parse --show-toplevel`, not relative cwd. This fix benefits all worktree contexts, not just this provisioning.
- **agent-browser availability:** The ops-provisioner already degrades gracefully if agent-browser is missing. All stages have a degraded path (print URLs + manual instructions).
- **Developer Portal approval delay:** If developer account approval is not instant, the provisioner pauses at Stage 3a. The founder re-invokes when approved. No checkpoint file needed -- the provisioner detects completed stages (existing account, existing app) and skips them.
- **Dependencies:** `openssl`, `jq`, `curl` must be present for OAuth 1.0a signing in `x-setup.sh`. Already documented in learnings.

## Acceptance Criteria

- [ ] `x-setup.sh` `write-env` uses absolute `.env` path (repo root)
- [ ] `x-setup.sh` has `write-env-interactive` command for secure credential input
- [ ] X account registered with preferred handle
- [ ] Developer Portal project and app created with OAuth 1.0a + Read+Write permissions
- [ ] All 4 env vars validated via `x-setup.sh verify`
- [ ] Expense ledger updated with X API entry
- [ ] `bun test` passes (if x-setup.sh has tests)

## Test Scenarios

- Given agent-browser is available, when ops-provisioner is invoked for X, then it navigates to x.com/i/flow/signup and pauses for manual registration
- Given agent-browser is unavailable, when ops-provisioner is invoked for X, then it prints URLs and step-by-step manual instructions for each stage
- Given credentials are copied from Developer Portal, when `write-env-interactive` is run, then it prompts for each credential without echoing input and writes to repo root `.env`
- Given valid credentials in `.env`, when `x-setup.sh verify` is run from a worktree, then it finds `.env` at repo root and validates successfully
- Given `x-setup.sh verify` returns 401, when the error is displayed, then it suggests re-copying credentials from the portal
- Given both @soleur and @soleur_ai are taken, when handle check runs, then it asks the founder to choose a handle manually

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| Developer Portal approval takes days | Provisioner pauses at 3a; founder re-invokes when approved |
| @soleur handle already taken | Fallback to @soleur_ai; if both taken, manual choice |
| agent-browser not installed | Graceful degradation to manual URLs + instructions |
| X changes signup flow | Agent-browser snapshots adapt to DOM; manual instructions still work |
| Free tier insufficient for community features | Document limitation; paid tier decision deferred to CFO (#471) |

## References & Research

### Internal References

- ops-provisioner agent: `plugins/soleur/agents/operations/ops-provisioner.md`
- x-setup.sh: `plugins/soleur/skills/community/scripts/x-setup.sh`
- x-community.sh: `plugins/soleur/skills/community/scripts/x-community.sh`
- Community SKILL.md: `plugins/soleur/skills/community/SKILL.md`
- Expense ledger: `knowledge-base/ops/expenses.md`
- Brand guide X notes: `knowledge-base/overview/brand-guide.md:150-163`
- Brainstorm: `knowledge-base/brainstorms/2026-03-09-x-provisioning-brainstorm.md`
- Spec: `knowledge-base/specs/feat-x-provisioning/spec.md`

### Learnings Applied

- `2026-03-09-external-api-scope-calibration.md` -- verify X API tier live before assuming scope
- `2026-02-18-token-env-var-not-cli-arg.md` -- secrets via env vars, never CLI args
- `2026-02-10-api-key-leaked-in-git-history-cleanup.md` -- .gitignore before credentials
- `2026-02-22-ops-provisioner-worktree-gap.md` -- always run from worktree, not main
- `2026-02-17-playwright-screenshots-land-in-main-repo.md` -- absolute paths for MCP tools

### Related Issues

- #474 -- this feature
- #127 -- X/Twitter community agent (merged, PR #466)
- #469 -- engage sub-command for X (blocked on account)
- #471 -- X monitoring commands requiring paid tier
