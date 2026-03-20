---
title: "feat: Adopt Doppler as Secrets Manager"
type: feat
date: 2026-03-20
---

# feat: Adopt Doppler as Secrets Manager

## Overview

Migrate ~23 user-managed secrets from 4 scattered surfaces (GitHub Actions secrets, local `.env`, server `/mnt/data/.env`, Terraform variables) into Doppler as the single source of truth. Incremental migration by surface with rollback capability at each phase. Zero added monthly cost (Doppler free tier).

**Issue:** #734
**Brainstorm:** `knowledge-base/brainstorms/2026-03-20-secrets-manager-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-secrets-manager/spec.md`

## Problem Statement

Credentials are scattered across 4 surfaces with no single source of truth. This causes:
- **Disaster recovery risk** — Rebuilding `/mnt/data/.env` requires recalling ~12 secrets from memory. BYOK_ENCRYPTION_KEY has no backup.
- **Secret drift** — Same secret in 3 places; no sync mechanism after rotation.
- **Dev machine exposure** — Live API tokens in plaintext at root `.env`. Past API key leak required full git history rewrite across 10 branches.
- **Rotation friction** — Updating a credential means manual edits in 2-3 locations.

## Proposed Solution

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    DOPPLER                           │
│  Project: soleur                                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐            │
│  │   dev   │  │   ci    │  │   prd   │            │
│  │ ~10 keys│  │ ~23 keys│  │ ~12 keys│            │
│  └────┬────┘  └────┬────┘  └────┬────┘            │
│       │            │            │                   │
└───────┼────────────┼────────────┼───────────────────┘
        │            │            │
        ▼            ▼            ▼
  ┌──────────┐ ┌──────────┐ ┌──────────────────┐
  │Local dev │ │GH Actions│ │Production server │
  │doppler   │ │  sync    │ │doppler run --    │
  │run --    │ │(push to  │ │docker run ...    │
  │bun dev   │ │GH secrets│ │                  │
  └──────────┘ │unchanged │ │Fallback: cached  │
               │workflow  │ │secrets on disk   │
               │files)    │ └──────────────────┘
               └──────────┘
```

**Key architectural decisions:**

1. **CI uses Doppler sync, not runtime injection.** Doppler pushes secrets to GitHub Actions' native secrets store. All 14 workflow files continue using `secrets.*` references unchanged. This eliminates the `with:` input problem (anthropic_api_key, SSH credentials) and the `secrets: inherit` problem entirely.

2. **Server uses `doppler run` wrapper in `ci-deploy.sh`.** Doppler CLI is installed via cloud-init. The forced SSH command wraps `docker run` with `doppler run --fallback passthrough --`. Cached secrets provide resilience against Doppler outages.

3. **Both containers share one `prd` config.** Matches the current single `/mnt/data/.env` pattern. Each container ignores irrelevant vars (as it does today).

4. **`DOPPLER_TOKEN` is the one remaining manual secret.** Created in Doppler dashboard, injected into cloud-init via Terraform `templatefile()`. Passed to Terraform itself via the operator's personal `doppler run` wrapper. This is the accepted "turtles all the way down" bootstrap.

5. **Secret rotation happens AFTER all 4 phases complete.** During migration, both old and new systems point to the same values. After migration, rotate all secrets in Doppler (auto-syncs to GH, available to server on next restart).

### Doppler Environment Topology

| Config | Purpose | Secrets | Service Token | Consumer |
|--------|---------|---------|---------------|----------|
| `dev` | Local development | ~10 (CF, Discord, X, LinkedIn, Bluesky) | None (personal auth via `doppler login`) | Developer machine |
| `ci` | GitHub Actions | ~23 (all secrets currently in GH) | 1 (for sync integration) | GH Actions sync target |
| `prd` | Production server | ~12 (Telegram, Supabase, Stripe, BYOK, Anthropic) | 1 (for server bootstrap) | Both Docker containers |

**Free tier usage:** 1 project (of 10), 3 configs (of 4), 2 service tokens (of 50), 1 sync (of 5).

### Secret Name Mapping

| Doppler Key | dev | ci | prd | Terraform Variable | Notes |
|-------------|-----|----|----|-------------------|-------|
| `ANTHROPIC_API_KEY` | | x | x | | Used by 10+ CI workflows and telegram-bridge |
| `DISCORD_WEBHOOK_URL` | x | x | | | Used by 11 CI workflows |
| `DISCORD_RELEASES_WEBHOOK_URL` | | x | | | reusable-release only |
| `DISCORD_BLOG_WEBHOOK_URL` | | x | | | scheduled-content-publisher only |
| `DISCORD_BOT_TOKEN` | x | x | | | Discord API auth |
| `DISCORD_GUILD_ID` | x | x | | | Discord server ID |
| `X_API_KEY` | x | x | | | X/Twitter API |
| `X_API_SECRET` | x | x | | | X/Twitter API |
| `X_ACCESS_TOKEN` | x | x | | | X/Twitter API |
| `X_ACCESS_TOKEN_SECRET` | x | x | | | X/Twitter API |
| `LINKEDIN_ACCESS_TOKEN` | | x | | | 60-day TTL, monitored by scheduled workflow |
| `LINKEDIN_PERSON_URN` | | x | | | LinkedIn API |
| `LINKEDIN_ORG_ID` | | x | | | LinkedIn API |
| `BSKY_HANDLE` | | x | | | Bluesky API |
| `BSKY_APP_PASSWORD` | | x | | | Bluesky API |
| `PLAUSIBLE_API_KEY` | | x | | | Analytics |
| `PLAUSIBLE_SITE_ID` | | x | | | Analytics |
| `NEXT_PUBLIC_SUPABASE_URL` | | x | x | | Build-time arg + runtime |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | | x | x | | Build-time arg + runtime |
| `SUPABASE_SERVICE_ROLE_KEY` | | | x | | Server-only |
| `STRIPE_SECRET_KEY` | | | x | | Server-only |
| `STRIPE_PRICE_ID` | | | x | | Server-only |
| `STRIPE_WEBHOOK_SECRET` | | | x | | Server-only |
| `BYOK_ENCRYPTION_KEY` | | | x | | CRITICAL — loss = permanent data loss |
| `TELEGRAM_BOT_TOKEN` | | | x | | telegram-bridge only |
| `TELEGRAM_ALLOWED_USER_ID` | | | x | | telegram-bridge only |
| `WEB_PLATFORM_HOST` | | x | | | Server IP for SSH deploy |
| `WEB_PLATFORM_SSH_KEY` | | x | | | CI deploy SSH private key |
| `WEB_PLATFORM_HOST_FINGERPRINT` | | x | | | Host key fingerprint |
| `CF_API_TOKEN` | x | | | `cloudflare_api_token` | Terraform + local scripts |
| `CF_ZONE_ID` | x | | | `cloudflare_zone_id` | Terraform + local scripts |
| `HCLOUD_TOKEN` | | | | `hcloud_token` | Terraform only |
| `DOPPLER_TOKEN_PRD` | | | | | Bootstrap for prod server (Terraform injects) |

**Excluded from Doppler:** `GITHUB_TOKEN` / `github.token` (auto-provided by GitHub), `deploy_ssh_public_key` (public key, not a secret — stays as Terraform variable).

## Implementation Phases

### Phase 0: Prerequisites (Low Risk)

**0.1 Back up BYOK_ENCRYPTION_KEY**

This is urgent and independent of Doppler. The key is at `/mnt/data/.env` on the production server.

- [ ] SSH to server, extract `BYOK_ENCRYPTION_KEY` value
- [ ] Store in a password manager or encrypted offline note (NOT in Doppler — this is a backup against Doppler failure)
- [ ] Document the backup location in `apps/web-platform/README.md`

**0.2 Fix `web-platform/infra/.gitignore`**

Pre-existing security gap: missing `*.tfvars` and `.terraform.lock.hcl`.

- [ ] Edit `apps/web-platform/infra/.gitignore` to match telegram-bridge pattern:

### apps/web-platform/infra/.gitignore

```gitignore
.terraform/
terraform.tfstate
terraform.tfstate.backup
terraform.tfvars
*.tfvars
.terraform.lock.hcl
```

**0.3 Create Doppler account and project**

- [ ] Sign up at doppler.com via Playwright (email + password, no OAuth consent needed)
- [ ] Create project "soleur"
- [ ] Verify 3 default configs exist: dev, stg, prd
- [ ] Rename `stg` to `ci` (Settings → Environments)
- [ ] Populate all secrets from existing sources (see mapping table)
- [ ] Create 2 service tokens:
  - `ci-sync` — scoped to `ci` config (for GitHub Actions sync)
  - `prd-server` — scoped to `prd` config (for production server)

**0.4 Configure Doppler sync to GitHub Actions**

- [ ] In Doppler dashboard: Integrations → GitHub → Add sync
- [ ] Source: `ci` config
- [ ] Target: GitHub repository `jikig-ai/soleur` → Actions secrets
- [ ] Map all 23 CI secrets
- [ ] Verify sync pushes correctly: `gh secret list` should show all secrets

**Validation:** `gh secret list` shows all expected secrets. Existing CI workflows continue passing (no workflow changes needed).

**Rollback:** Delete Doppler account. GH Actions secrets remain intact.

### Phase 1: Local Dev Migration (Low Risk)

**1.1 Install Doppler CLI**

```bash
curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh
doppler login
doppler setup  # Select project: soleur, config: dev
```

This creates `.doppler.yaml` in the repo root.

**1.2 Add `.doppler.yaml` to version control**

- [ ] Add `.doppler.yaml` to repo root (contains project/config pointer, no secrets)
- [ ] Verify `.env` remains in `.gitignore`

### .doppler.yaml

```yaml
setup:
  project: soleur
  config: dev
```

**1.3 Update worktree manager**

Modify `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:

- [ ] In `copy_env_files()` (lines 96-134): add `.doppler.yaml` to the copy glob alongside `.env*` files
- [ ] Keep `.env` copying as fallback for non-Doppler users (the function already handles missing files gracefully)

**1.4 Migrate community setup scripts**

All 4 scripts need a `write-doppler` command alongside existing `write-env`. The `write-env` command stays for backward compatibility.

For each script (`discord-setup.sh`, `x-setup.sh`, `bsky-setup.sh`, `linkedin-setup.sh`):

- [ ] Add `cmd_write_doppler()` function that calls `doppler secrets set KEY=value` for each credential
- [ ] Add `write-doppler` to the command dispatch case statement
- [ ] Update `cmd_verify()` to check Doppler if `doppler` CLI is available, falling back to `.env` source
- [ ] Fix `linkedin-setup.sh` line 282: replace `git rev-parse --show-toplevel` with `$GIT_ROOT` (pre-existing bare-repo hardening gap)

### plugins/soleur/skills/community/scripts/discord-setup.sh (new function)

```bash
cmd_write_doppler() {
  if ! command -v doppler &>/dev/null; then
    echo "Error: doppler CLI not installed. Run: curl -Ls https://cli.doppler.com/install.sh | sh" >&2
    return 1
  fi

  doppler secrets set \
    DISCORD_BOT_TOKEN="$DISCORD_BOT_TOKEN_INPUT" \
    DISCORD_GUILD_ID="$1" \
    DISCORD_WEBHOOK_URL="$2" \
    ${3:+DISCORD_RELEASES_WEBHOOK_URL="$3"} \
    ${4:+DISCORD_BLOG_WEBHOOK_URL="$4"}
}
```

**1.5 Create `doppler-run` wrapper script (optional convenience)**

A thin wrapper at `scripts/doppler-run.sh` that checks for Doppler CLI, falls back to `.env` sourcing:

### scripts/doppler-run.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

if command -v doppler &>/dev/null && [[ -f ".doppler.yaml" ]]; then
  exec doppler run -- "$@"
else
  if [[ -f ".env" ]]; then
    set -a; source .env; set +a
  fi
  exec "$@"
fi
```

**Validation:**
- `doppler run -- env | grep DISCORD` shows expected vars
- `doppler run -- bun run dev` starts the dev server
- Setup scripts' `write-doppler` + `verify` commands work end-to-end
- Worktree creation copies `.doppler.yaml`

**Rollback:** Keep `.env` file intact throughout Phase 1. Remove `.doppler.yaml`, revert script changes.

### Phase 2: CI Migration (Low Risk — Sync Approach)

**This phase requires zero workflow file changes.** Doppler sync (configured in Phase 0.4) pushes all secrets to GitHub Actions' native secrets store. All `secrets.*` references, `with:` inputs, `secrets: inherit`, and Docker build-args continue working exactly as before.

**2.1 Verify sync is active**

- [ ] `gh secret list` — all 23 secrets present
- [ ] Trigger a representative workflow manually to validate (e.g., `scheduled-linkedin-token-check.yml` — uses 1 secret)
- [ ] Trigger `reusable-release.yml` workflow to validate Docker build-args still work

**2.2 Document the new management workflow**

- [ ] Add comment to `.github/README.md` or similar: "Secrets are managed via Doppler. Do not use `gh secret set` directly — changes will be overwritten by Doppler sync."
- [ ] Remove any scripts/docs that reference manual `gh secret set` for these secrets

**2.3 Add `DOPPLER_TOKEN` as the one remaining GitHub Secret**

- [ ] `gh secret set DOPPLER_TOKEN < <(doppler configs tokens create ci-sync --config ci --plain)`
- [ ] This is ONLY needed if future workflows want to use `dopplerhq/cli-action` directly (e.g., for `doppler run` wrapping). Not required for the sync approach.

**Validation:** All 14 workflow files pass CI without any code changes. Secrets are sourced from Doppler via sync.

**Rollback:** Disable Doppler sync. GH Actions secrets remain with their current values. Re-enable manual `gh secret set` management.

### Phase 3: Server Runtime Migration (High Risk)

**This is the highest-risk phase.** Changes affect production container startup. Test thoroughly in a staging-like setup before deploying.

**3.1 Install Doppler CLI via cloud-init**

Modify both cloud-init files (`apps/telegram-bridge/infra/cloud-init.yml` and `apps/web-platform/infra/cloud-init.yml`):

- [ ] Add Doppler CLI installation before the Docker setup section
- [ ] Add `DOPPLER_TOKEN` to the deploy user's environment

### apps/web-platform/infra/cloud-init.yml (additions)

```yaml
runcmd:
  # Install Doppler CLI (pinned version for reproducibility)
  - curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh
  # Store Doppler service token for deploy user
  - mkdir -p /home/deploy/.config/doppler
  - echo "${doppler_token}" > /home/deploy/.config/doppler/.token
  - chmod 600 /home/deploy/.config/doppler/.token
  - chown -R deploy:deploy /home/deploy/.config/doppler
```

**3.2 Add `doppler_token` as a Terraform variable**

### apps/web-platform/infra/variables.tf (addition)

```hcl
variable "doppler_token" {
  description = "Doppler service token for production secrets injection"
  type        = string
  sensitive   = true
}
```

Pass to cloud-init via `templatefile()`:

### apps/web-platform/infra/server.tf (modification)

```hcl
user_data = templatefile("cloud-init.yml", {
  image_name             = var.image_name
  deploy_ssh_public_key  = var.deploy_ssh_public_key
  ci_deploy_script_b64   = base64encode(file("ci-deploy.sh"))
  doppler_token          = var.doppler_token  # NEW
})
```

**3.3 Modify `ci-deploy.sh` to use Doppler**

Replace `--env-file /mnt/data/.env` with `doppler run --fallback passthrough --`:

### apps/web-platform/infra/ci-deploy.sh (key change)

```bash
# Before (line ~82):
docker run -d --name "$container" --env-file /mnt/data/.env ...

# After:
DOPPLER_TOKEN="$(cat /home/deploy/.config/doppler/.token)" \
  doppler run --fallback passthrough --project soleur --config prd -- \
  docker run -d --name "$container" ...
```

The `--fallback passthrough` flag uses cached secrets if Doppler is unreachable. On first run, Doppler caches secrets locally (encrypted). Subsequent runs work offline.

- [ ] Apply same pattern to all 5 `--env-file` locations:
  - `apps/web-platform/infra/ci-deploy.sh:82` (web-platform container)
  - `apps/web-platform/infra/ci-deploy.sh:109` (bridge container)
  - `apps/web-platform/infra/cloud-init.yml:101` (initial web-platform start)
  - `apps/telegram-bridge/infra/cloud-init.yml:90` (initial bridge start)
  - `apps/telegram-bridge/scripts/deploy.sh:16` (legacy script)

**3.4 Keep `/mnt/data/.env` as fallback during transition**

- [ ] Do NOT remove `/mnt/data/.env` yet — keep as rollback
- [ ] Cloud-init still creates the empty file (backward compat)
- [ ] After validating Doppler works in production, the `.env` file becomes unused

**Validation:**
- Deploy web-platform via CI: container starts, health check passes
- Deploy telegram-bridge via CI: container starts, bot responds
- Simulate Doppler outage: restart container with `--fallback passthrough` — should use cached secrets
- Verify BYOK encryption/decryption still works

**Rollback:** Revert `ci-deploy.sh` to use `--env-file /mnt/data/.env`. SCP the current secrets to `/mnt/data/.env` via `doppler secrets download --no-file --format docker | ssh deploy@server 'cat > /mnt/data/.env && chmod 600 /mnt/data/.env'`.

### Phase 4: Terraform Migration (Medium Risk)

**4.1 Use `doppler run` for Terraform commands**

No changes to Terraform files needed. The operator wraps commands:

```bash
# Plan
doppler run --name-transformer tf-var -- terraform plan

# Apply
doppler run --name-transformer tf-var -- terraform apply
```

Doppler transforms `HCLOUD_TOKEN` → `TF_VAR_hcloud_token`, `CF_API_TOKEN` → `TF_VAR_cf_api_token`, etc.

**4.2 Verify name mapping**

The `--name-transformer tf-var` lowercases and prepends `TF_VAR_`. Verify the mapping matches Terraform variable names:

| Doppler Key | Transformed | Expected TF Variable | Match? |
|-------------|-------------|---------------------|--------|
| `HCLOUD_TOKEN` | `TF_VAR_hcloud_token` | `hcloud_token` | Yes |
| `CF_API_TOKEN` | `TF_VAR_cf_api_token` | `cloudflare_api_token` | **NO** |
| `CF_ZONE_ID` | `TF_VAR_cf_zone_id` | `cloudflare_zone_id` | **NO** |

**Naming mismatch!** Terraform variables are `cloudflare_api_token` and `cloudflare_zone_id`, but Doppler keys would transform to `cf_api_token` and `cf_zone_id`.

**Resolution:** Name the Doppler keys to match the Terraform variable names:

| Doppler Key (for Terraform) | Transformed | TF Variable | Match? |
|----------------------------|-------------|-------------|--------|
| `CLOUDFLARE_API_TOKEN` | `TF_VAR_cloudflare_api_token` | `cloudflare_api_token` | Yes |
| `CLOUDFLARE_ZONE_ID` | `TF_VAR_cloudflare_zone_id` | `cloudflare_zone_id` | Yes |

The `dev` config uses `CF_API_TOKEN` (for local scripts). The Terraform-consumed versions live in `dev` with the full names. Both can coexist in the same Doppler config — the `--name-transformer` only affects the TF_VAR_ prefix.

**4.3 Remove `.tfvars` files**

- [ ] Delete any local `.tfvars` files (already gitignored, but remove from disk)
- [ ] Document the new workflow: `doppler run --name-transformer tf-var -- terraform apply`
- [ ] Update `apps/telegram-bridge/README.md` and `apps/web-platform/README.md`

**4.4 Add convenience alias to `scripts/doppler-run.sh`**

```bash
# Usage: ./scripts/doppler-run.sh tf plan
# Usage: ./scripts/doppler-run.sh tf apply
if [[ "${1:-}" == "tf" ]]; then
  shift
  exec doppler run --name-transformer tf-var -- terraform "$@"
fi
```

**Validation:** `doppler run --name-transformer tf-var -- terraform plan` succeeds without `.tfvars` files. All variables resolve correctly.

**Rollback:** Re-create `.tfvars` files with values from `doppler secrets download --format env`.

### Phase 5: Rotation & Cleanup

**5.1 Rotate all migrated secrets**

Per institutional learning (2026-02-10 API key leak): assume old values are compromised if they ever touched disk.

- [ ] Rotate each secret at its source (Discord dashboard, X developer portal, Stripe dashboard, etc.)
- [ ] Update new values in Doppler (single location)
- [ ] Doppler sync auto-pushes to GH Actions
- [ ] Production containers pick up new values on next restart/deploy
- [ ] Terraform picks up new values on next apply

**5.2 Clean up old artifacts**

- [ ] Delete root `.env` file from developer machine
- [ ] Remove `/mnt/data/.env` from production server (after confirming Doppler fallback cache is populated)
- [ ] Remove `gh secret set` references from documentation
- [ ] Update `.env.example` files with Doppler reference comment

**5.3 Add pre-commit secret scanning**

- [ ] Add `git-secrets` or equivalent pre-commit hook to prevent accidental secret commits
- [ ] Document in CLAUDE.md or constitution.md

## Acceptance Criteria

### Functional Requirements

- [ ] All 23 user-managed secrets stored in Doppler with correct config assignment
- [ ] `doppler run -- bun run dev` starts local dev with all secrets injected (no `.env` file needed)
- [ ] All 14 CI workflow files pass without modification (secrets delivered via Doppler sync)
- [ ] Both production containers start via `doppler run` wrapper in `ci-deploy.sh`
- [ ] `doppler run --name-transformer tf-var -- terraform plan` resolves all variables
- [ ] Credential rotation is `doppler secrets set KEY=newvalue` (single command, auto-propagates)

### Non-Functional Requirements

- [ ] Doppler outage does not prevent production container restarts (fallback cache)
- [ ] BYOK_ENCRYPTION_KEY has offline backup independent of Doppler
- [ ] No plaintext `.env` files on developer machine or production server after Phase 5
- [ ] `web-platform/infra/.gitignore` includes `*.tfvars` and `.terraform.lock.hcl`
- [ ] Pre-commit hook prevents accidental secret commits

## Test Scenarios

### Phase 1 — Local Dev

- Given Doppler CLI installed and authenticated, when `doppler run -- env | grep DISCORD`, then all Discord vars are present
- Given a new worktree created, when checking for `.doppler.yaml`, then it exists and points to project `soleur`
- Given `discord-setup.sh write-doppler` executed with valid credentials, when `doppler secrets get DISCORD_BOT_TOKEN`, then value matches
- Given Doppler CLI not installed, when running `scripts/doppler-run.sh bun dev` with `.env` present, then falls back to `.env` sourcing

### Phase 2 — CI

- Given Doppler sync active, when triggering `scheduled-linkedin-token-check` workflow, then LinkedIn token check succeeds using synced secret
- Given Doppler sync active, when triggering `reusable-release` workflow, then Docker build-args resolve and image builds successfully
- Given Doppler sync active, when running `claude-code-review` workflow, then `anthropic_api_key` input receives the synced secret value

### Phase 3 — Server Runtime

- Given Doppler CLI installed on server with valid token, when deploying via CI, then container starts with all env vars present
- Given Doppler unreachable, when restarting a container that previously ran successfully, then `--fallback passthrough` uses cached secrets and container starts
- Given both containers running with Doppler injection, when checking BYOK encryption, then encrypt/decrypt roundtrip succeeds
- Given `ci-deploy.sh` receives an invalid image name, when deploy is attempted, then the validation rejects it (existing forced-command security preserved)

### Phase 4 — Terraform

- Given Doppler dev config has `HCLOUD_TOKEN` and `CLOUDFLARE_API_TOKEN`, when running `doppler run --name-transformer tf-var -- terraform plan`, then plan succeeds with no missing variable errors
- Given no `.tfvars` files on disk, when running terraform plan via Doppler, then all sensitive variables resolve from environment

## Dependencies & Prerequisites

| Dependency | Required By | Status |
|------------|-------------|--------|
| Doppler account (free tier) | Phase 0 | Not started |
| Doppler CLI on dev machine | Phase 1 | Not started |
| Doppler CLI on production server | Phase 3 | Not started (cloud-init change) |
| BYOK backup | Phase 0 (urgent) | Not started |
| `.gitignore` fix for web-platform infra | Phase 0 | Not started |

## Risk Analysis & Mitigation

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Doppler outage blocks container startup | HIGH | LOW | `--fallback passthrough` uses encrypted local cache |
| CI sync delivers stale secrets | MEDIUM | LOW | Sync is near-instant; verify with `gh secret list` after rotation |
| `ci-deploy.sh` Doppler wrapper fails | HIGH | MEDIUM | Test in staging first; keep `/mnt/data/.env` as rollback |
| Free tier limits exceeded | LOW | LOW | Currently using 1/10 projects, 3/4 envs, 2/50 tokens |
| Bootstrap `DOPPLER_TOKEN` leaked | HIGH | LOW | Scoped to `prd` config only; rotate via dashboard; store with chmod 600 |
| Name transformer produces wrong TF_VAR_ | MEDIUM | MEDIUM | Mapping table verified above; test with `terraform plan` before `apply` |

## Institutional Learnings Applied

- **API key leak (2026-02-10):** Rotate all secrets after migration. Add pre-commit scanning.
- **Env vars over CLI args (2026-02-18):** All Doppler injection is via env vars. chmod 600 on token files.
- **CI secrets gotcha (2026-02-12):** Sync approach avoids this entirely — `secrets.*` references unchanged.
- **Bash operator precedence (2026-02-13):** Use `{ ...; }` grouping in ci-deploy.sh around `|| true` fallbacks.
- **Token lifecycle (2026-03-02):** claude-code-action token revocation is irrelevant — Doppler sync handles API key delivery, not runtime injection.
- **GH Actions security (2026-02-21):** Pin `dopplerhq/cli-action` to commit SHA if used directly.
- **Cloud-init + Terraform separation (2026-02-10):** Terraform creates infra, cloud-init installs Doppler CLI — no secret injection overlap.

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-03-20-secrets-manager-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-secrets-manager/spec.md`
- CI deploy script: `apps/web-platform/infra/ci-deploy.sh`
- Cloud-init (web): `apps/web-platform/infra/cloud-init.yml`
- Cloud-init (bridge): `apps/telegram-bridge/infra/cloud-init.yml`
- Worktree manager: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:96-134`
- Discord setup: `plugins/soleur/skills/community/scripts/discord-setup.sh:209-253`
- Web Dockerfile (build-args): `apps/web-platform/Dockerfile:12-14`
- Reusable release (secrets): `.github/workflows/reusable-release.yml:283-285`

### External

- Doppler CLI docs: https://docs.doppler.com/docs/cli
- Doppler GitHub sync: https://docs.doppler.com/docs/github-actions
- Doppler Terraform: https://docs.doppler.com/docs/terraform
- `dopplerhq/cli-action`: https://github.com/DopplerHQ/cli-action

### Related Issues

- #734 — This issue
- #678 — Discovery context (Playwright automation compensating for missing credentials)
