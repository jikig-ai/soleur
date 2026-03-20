---
title: "chore: document .env provisioning after removing CI env setup step"
type: feat
date: 2026-03-20
issue: "#844"
---

# chore: document .env provisioning after removing CI env setup step

## Overview

PR #825 removed the "Ensure telegram env vars on server" SSH step from `telegram-bridge-release.yml`. The env vars (`TELEGRAM_BOT_TOKEN`, etc.) are now assumed to exist in `/mnt/data/.env` from initial provisioning. Both cloud-init configs create an empty `/mnt/data/.env` placeholder (mode 600, owned by `deploy`), but nothing populates it with actual values. A fresh server rebuild from cloud-init would have an empty `.env`, causing containers to fail on startup.

The telegram-bridge README (`apps/telegram-bridge/README.md`) already documents the `scp .env` step (line 62-66), but:
1. The web-platform has no README or `.env.example` -- its required env vars are scattered across source files
2. Neither cloud-init file documents what `.env` keys are expected
3. There is no single "operations runbook" covering the post-provisioning manual step for either component

## Problem Statement / Motivation

**Gap:** After `terraform apply` creates a new server, the operator must manually populate `/mnt/data/.env` with secrets before containers will function. This step is undocumented for web-platform and only partially documented for telegram-bridge (in its README, not in the infra docs). If the server is ever rebuilt (disaster recovery, migration, or Terraform recreate), the operator must know exactly which env vars to set and in what format.

**Introduced by:** #825 -- the removal is correct (env vars should be provisioned once, not on every deploy), but the documentation gap needs closing.

## Proposed Solution

**Option A (recommended): Documentation-only approach**

1. Create `apps/web-platform/.env.example` listing all required env vars with descriptions
2. Add a "Server Provisioning" section to `apps/telegram-bridge/README.md` infra notes (the existing Quick Start step 6 covers initial setup, but a dedicated section for disaster recovery is clearer)
3. Add inline comments in both `cloud-init.yml` files next to the `.env` placeholder explaining what keys must be populated and pointing to `.env.example`

**Option B (future, out of scope): Terraform `sensitive_file` provisioning**

Use Terraform to write the `.env` file from variables. This is more automated but introduces sensitive values into Terraform state, requires `terraform.tfvars` to contain secrets, and conflicts with the single-provisioning design (env vars are set once, not on every apply). This option is documented for awareness but deferred -- the operational overhead of managing secrets in Terraform state outweighs the benefit for a single-server setup with infrequent reprovisioning.

## Technical Considerations

### Required env vars per component

**telegram-bridge** (from `apps/telegram-bridge/.env.example`):

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Bot API token from @BotFather |
| `TELEGRAM_ALLOWED_USER_ID` | Yes | Numeric Telegram user ID |
| `SOLEUR_PLUGIN_DIR` | No | Path to Soleur plugin directory |
| `CLAUDE_MODEL` | No | Claude model (default: claude-opus-4-6) |
| `SKIP_PERMISSIONS` | No | Set `false` to disable `--dangerously-skip-permissions` |

**web-platform** (from source code grep of `process.env.*`):

| Variable | Required | Description |
|----------|----------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Yes | Supabase anonymous key |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Supabase service role key |
| `STRIPE_SECRET_KEY` | Yes | Stripe API secret key |
| `STRIPE_PRICE_ID` | Yes | Stripe price ID for checkout |
| `STRIPE_WEBHOOK_SECRET` | Yes | Stripe webhook signing secret |
| `BYOK_ENCRYPTION_KEY` | Yes (prod) | 32-byte hex key for BYOK encryption |
| `PORT` | No | Server port (default: 3000) |
| `NODE_ENV` | No | Set by Dockerfile (`production`) |
| `WORKSPACES_ROOT` | No | Workspace directory (default: `/workspaces`) |
| `SOLEUR_PLUGIN_PATH` | No | Plugin path (default: `/app/shared/plugins/soleur`) |

### Shared `.env` file

Both components on the same server use `--env-file /mnt/data/.env` (visible in `ci-deploy.sh` lines 122 and 147). This means a single `.env` file must contain vars for both components. Non-applicable vars are simply ignored by each container.

### Cloud-init creates the placeholder

Both cloud-init files already handle:
- `touch /mnt/data/.env` -- creates empty file
- `chmod 600 /mnt/data/.env` -- restricts to owner-only
- `chown -R deploy:deploy /mnt/data` -- grants deploy user ownership

The gap is: no documentation tells the operator what to put in this file.

### SpecFlow edge cases

- **Edge case: partial .env** -- If only telegram-bridge vars are set but not web-platform vars, the web-platform container will start but crash on first Supabase/Stripe call. The `.env.example` should group vars by component to make this clear.
- **Edge case: BYOK_ENCRYPTION_KEY** -- Must be generated once and preserved across server rebuilds (it encrypts stored API keys). If lost, all BYOK keys become unrecoverable. The docs must flag this as critical.
- **Edge case: NEXT_PUBLIC_ vars at build time** -- `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` are baked into the Docker image at build time (Dockerfile ARG). The `.env` file provides them at runtime for server-side code only. This is not a provisioning concern but should be noted to avoid confusion.

## Acceptance Criteria

- [ ] `apps/web-platform/.env.example` exists with all required env vars, descriptions, and grouping
- [ ] Both `cloud-init.yml` files have inline comments next to the `.env` placeholder referencing the `.env.example` files
- [ ] `apps/telegram-bridge/README.md` has a "Disaster Recovery" or "Reprovisioning" section that covers `.env` restoration
- [ ] The shared nature of `/mnt/data/.env` (both components read it) is documented

## Test Scenarios

- Given a fresh server provisioned via `terraform apply`, when the operator follows the documentation to populate `/mnt/data/.env`, then both containers start and pass health checks
- Given the operator rebuilds the server (Terraform destroy + apply), when they follow the reprovisioning docs, then they can restore service without guessing which env vars are needed
- Given `BYOK_ENCRYPTION_KEY` is not documented, when the operator reprovisions, then existing BYOK-encrypted API keys are lost -- **prevented by documenting this key as critical**

## Files to Modify

1. **`apps/web-platform/.env.example`** (new) -- All web-platform env vars with descriptions
2. **`apps/telegram-bridge/infra/cloud-init.yml`** -- Add comments at `.env` placeholder referencing `.env.example`
3. **`apps/web-platform/infra/cloud-init.yml`** -- Add comments at `.env` placeholder referencing `.env.example`
4. **`apps/telegram-bridge/README.md`** -- Add reprovisioning section covering `.env` restoration

## Dependencies & Risks

- **Low risk:** Documentation-only changes, no behavioral impact
- **Dependency on #843:** The `ci-deploy.sh` deduplication is separate work; this plan does not touch deploy logic
- **Future consideration:** If the project moves to multi-server (separate telegram-bridge host), the `.env` files will split. The documentation should note this is currently a shared file on a single server.

## References & Research

### Internal References

- Issue: #844
- Related PR: #825 (removed CI env setup step)
- Related issue: #843 (deduplicate ci-deploy.sh)
- Related plan: `knowledge-base/plans/2026-03-20-security-deploy-ssh-user-privilege-boundary-plan.md` (#832)
- Existing `.env.example`: `apps/telegram-bridge/.env.example`
- Cloud-init (telegram-bridge): `apps/telegram-bridge/infra/cloud-init.yml:200-204`
- Cloud-init (web-platform): `apps/web-platform/infra/cloud-init.yml:205-209`
- ci-deploy.sh (both components use `--env-file /mnt/data/.env`): lines 122, 147
- Learning: `knowledge-base/project/learnings/2026-03-20-cloud-init-chown-ordering-recursive-before-specific.md`
