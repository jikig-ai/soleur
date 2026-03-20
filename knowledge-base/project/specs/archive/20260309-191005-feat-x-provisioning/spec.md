# Spec: X/Twitter Account Provisioning via Ops-Provisioner

**Branch:** feat-x-provisioning
**Brainstorm:** [2026-03-09-x-provisioning-brainstorm.md](../../brainstorms/2026-03-09-x-provisioning-brainstorm.md)

## Problem Statement

The X/Twitter integration (PR #466) is code-complete but inert — all scripts and agent config exist, but no X account or API credentials have been provisioned. The ops-provisioner agent handles SaaS tool provisioning (tested with Cloudflare and Plausible) but hasn't been used for X. The provisioning workflow needs to be executed for X and any gaps in the ops-provisioner surfaced and fixed.

## Goals

1. Provision an X/Twitter account using the ops-provisioner's guided workflow
2. Set up the X Developer Portal and generate API keys
3. Validate credentials via existing `x-setup.sh verify`
4. Record X API costs in the ops expense ledger
5. Identify and fix any ops-provisioner gaps encountered during the X provisioning

## Non-Goals

- Automated account creation (ToS violation, rejected by CMO/COO)
- Building X-specific provisioning scripts (ops-provisioner is the general tool)
- X API feature expansion (covered by issues #469, #471)
- Credential rotation runbook (separate follow-up)
- Paid API tier purchase (decision deferred to CFO)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Ops-provisioner navigates to `x.com/i/flow/signup` via agent-browser, pre-fills display name from brand guide |
| FR2 | Ops-provisioner pauses for manual action on sensitive steps (email, phone verification, CAPTCHA, password) |
| FR3 | Ops-provisioner navigates to `developer.x.com` for Developer Portal setup, pre-fills app name and description |
| FR4 | Ops-provisioner pauses for developer terms agreement and identity verification |
| FR5 | After founder copies API credentials, `x-setup.sh write-env` stores them with `chmod 600` |
| FR6 | `x-setup.sh verify` validates credentials via `GET /2/users/me` round-trip |
| FR7 | Ops-advisor updates `knowledge-base/ops/expenses.md` with X API tier and costs |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Agent-browser used for page navigation and non-sensitive field pre-filling only |
| TR2 | All credential handling follows env var pattern (never CLI arguments, per learnings) |
| TR3 | `.env` file has `.gitignore` coverage before any credentials are written (already verified) |
| TR4 | Playwright/agent-browser paths must be absolute (worktree path resolution issue, per learnings) |

## Provisioning Stages

### Stage 1: Handle Availability Check
- Verify `@soleur` availability on X (fallback: `@soleur_ai`)

### Stage 2: Account Registration
- Agent-browser opens signup page
- Pre-fills: display name "Soleur"
- Manual: email, phone, CAPTCHA, password

### Stage 3: Developer Portal + API Keys
- Agent-browser opens developer.x.com
- Pre-fills: app name, description
- Manual: terms, identity verification, credential copy
- Automated: `x-setup.sh write-env` + `verify`

### Stage 4: Expense Recording
- Ops-advisor records tier and costs in expense ledger
- Reconcile stale ledger entries (15 days overdue)

## Success Criteria

1. Active X account with handle registered
2. Developer Portal project and app created
3. All 4 env vars (`X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`) set and validated
4. `x-setup.sh verify` returns success
5. Expense ledger updated with X API entry
6. Community agent integration tests unblocked
