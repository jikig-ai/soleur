---
title: "feat: Adopt Doppler as Secrets Manager"
type: feat
date: 2026-03-20
---

# feat: Adopt Doppler as Secrets Manager

## Overview

Migrate ~23 user-managed secrets from 3 surfaces (GitHub Actions secrets, local `.env`, server `/mnt/data/.env`) into Doppler as the single source of truth. Terraform integration deferred — run quarterly, `.tfvars` works fine. Zero added monthly cost (Doppler free tier).

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
  ┌──────────┐ ┌──────────┐ ┌──────────────────────┐
  │Local dev │ │GH Actions│ │Production servers    │
  │doppler   │ │  sync    │ │doppler secrets       │
  │run --    │ │(push to  │ │download --format     │
  │bun dev   │ │GH secrets│ │docker | docker run   │
  └──────────┘ │unchanged │ │--env-file /dev/stdin  │
               │workflow  │ │                      │
               │files)    │ │Fallback: /mnt/data/  │
               └──────────┘ │.env (cold-start)     │
                            └──────────────────────┘
```

**Key architectural decisions:**

1. **CI uses Doppler sync, not runtime injection.** Doppler pushes secrets to GitHub Actions' native secrets store. All 14 workflow files continue using `secrets.*` references unchanged. This eliminates the `with:` input problem (anthropic_api_key, SSH credentials) and the `secrets: inherit` problem entirely. [Updated 2026-03-20: Supersedes spec FR3 which proposed `dopplerhq/cli-action`.]

2. **Server uses `doppler secrets download` piped to `docker run --env-file /dev/stdin`.** Docker containers do NOT inherit the parent shell's environment — `doppler run -- docker run` would silently start containers with zero secrets. The correct pattern downloads secrets in Docker env format and pipes them via stdin. No plaintext file on disk.

3. **Both containers share one `prd` config.** Matches the current single `/mnt/data/.env` pattern. Each container ignores irrelevant vars (as it does today).

4. **`DOPPLER_TOKEN` is the one remaining manual secret.** Created in Doppler dashboard, injected into cloud-init via Terraform `templatefile()`. Stored in `/etc/environment` on the server so all processes (including SSH forced commands) can read it.

5. **Secret rotation happens AFTER all phases complete.** During migration, both old and new systems point to the same values. After migration, rotate all secrets in Doppler (auto-syncs to GH, available to server on next deploy).

6. **`/mnt/data/.env` stays as cold-start fallback.** On a freshly provisioned server, Doppler has no local cache. If Doppler is unreachable during first boot, the `.env` file provides a safety net. Remove only after confirming Doppler cache is populated.

7. **Terraform integration deferred.** Terraform is run quarterly. The `.tfvars` approach works. Doppler's `--name-transformer tf-var` introduces naming-mismatch complexity (`CF_API_TOKEN` vs `cloudflare_api_token`) and duplicate keys. Filed as follow-up.

### Doppler Environment Topology

| Config | Purpose | Secrets | Service Token | Consumer |
|--------|---------|---------|---------------|----------|
| `dev` | Local development | ~10 (CF, Discord, X, LinkedIn, Bluesky) | None (personal auth via `doppler login`) | Developer machine |
| `ci` | GitHub Actions | ~23 (all secrets currently in GH) | 1 (for sync integration) | GH Actions sync target |
| `prd` | Production servers | ~12 (Telegram, Supabase, Stripe, BYOK, Anthropic) | 1 per server (scoped to `prd` config) | Both Docker containers |

**Free tier usage:** 1 project (of 10), 3 configs (of 4), 3 service tokens (of 50), 1 sync (of 5).

### Secret Name Mapping

| Doppler Key | dev | ci | prd | Notes |
|-------------|-----|----|----|-------|
| `ANTHROPIC_API_KEY` | | x | x | Used by 10+ CI workflows and telegram-bridge |
| `DISCORD_WEBHOOK_URL` | x | x | | Used by 11 CI workflows |
| `DISCORD_RELEASES_WEBHOOK_URL` | | x | | reusable-release only |
| `DISCORD_BLOG_WEBHOOK_URL` | | x | | scheduled-content-publisher only |
| `DISCORD_BOT_TOKEN` | x | x | | Discord API auth |
| `DISCORD_GUILD_ID` | x | x | | Discord server ID |
| `X_API_KEY` | x | x | | X/Twitter API |
| `X_API_SECRET` | x | x | | X/Twitter API |
| `X_ACCESS_TOKEN` | x | x | | X/Twitter API |
| `X_ACCESS_TOKEN_SECRET` | x | x | | X/Twitter API |
| `LINKEDIN_ACCESS_TOKEN` | | x | | 60-day TTL, monitored by scheduled workflow |
| `LINKEDIN_PERSON_URN` | | x | | LinkedIn API |
| `LINKEDIN_ORG_ID` | | x | | LinkedIn API |
| `BSKY_HANDLE` | | x | | Bluesky API |
| `BSKY_APP_PASSWORD` | | x | | Bluesky API |
| `PLAUSIBLE_API_KEY` | | x | | Analytics |
| `PLAUSIBLE_SITE_ID` | | x | | Analytics |
| `NEXT_PUBLIC_SUPABASE_URL` | | x | x | Build-time arg + runtime |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | | x | x | Build-time arg + runtime |
| `SUPABASE_SERVICE_ROLE_KEY` | | | x | Server-only |
| `STRIPE_SECRET_KEY` | | | x | Server-only |
| `STRIPE_PRICE_ID` | | | x | Server-only |
| `STRIPE_WEBHOOK_SECRET` | | | x | Server-only |
| `BYOK_ENCRYPTION_KEY` | | | x | CRITICAL — loss = permanent data loss |
| `TELEGRAM_BOT_TOKEN` | | | x | telegram-bridge only |
| `TELEGRAM_ALLOWED_USER_ID` | | | x | telegram-bridge only |
| `WEB_PLATFORM_HOST` | | x | | Server IP for SSH deploy |
| `WEB_PLATFORM_SSH_KEY` | | x | | CI deploy SSH private key |
| `WEB_PLATFORM_HOST_FINGERPRINT` | | x | | Host key fingerprint |
| `CF_API_TOKEN` | x | | | Local scripts (Terraform stays on .tfvars for now) |
| `CF_ZONE_ID` | x | | | Local scripts |

**Excluded from Doppler:** `GITHUB_TOKEN` / `github.token` (auto-provided by GitHub), `deploy_ssh_public_key` (public key, not a secret), Terraform variables (`hcloud_token`, `cloudflare_api_token` — deferred).

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
- [ ] Create 3 service tokens:
  - `ci-sync` — scoped to `ci` config (for GitHub Actions sync)
  - `prd-web` — scoped to `prd` config (for web-platform server)
  - `prd-bridge` — scoped to `prd` config (for telegram-bridge server)

**0.4 Configure Doppler sync to GitHub Actions**

- [ ] In Doppler dashboard: Integrations → GitHub → Add sync
- [ ] Source: `ci` config
- [ ] Target: GitHub repository `jikig-ai/soleur` → Actions secrets
- [ ] Map all 23 CI secrets
- [ ] Verify sync pushes correctly: `gh secret list` should show all secrets

**Validation:** `gh secret list` shows all expected secrets. Existing CI workflows continue passing (no workflow changes needed).

**Rollback:** Delete Doppler account. GH Actions secrets remain intact.

### Phase 1: Local Dev Migration (Low Risk)

**1.1 Install Doppler CLI and authenticate**

```bash
curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | sh
doppler login
doppler setup  # Select project: soleur, config: dev
```

This creates `.doppler.yaml` in the repo root.

**1.2 Add `.doppler.yaml` to version control**

- [ ] Commit `.doppler.yaml` to repo root (contains project/config pointer, no secrets)
- [ ] `.doppler.yaml` is a tracked file — git worktrees will include it automatically (no worktree manager changes needed)

### .doppler.yaml

```yaml
setup:
  project: soleur
  config: dev
```

**Validation:**
- `doppler run -- env | grep DISCORD` shows expected vars
- `doppler run -- bun run dev` starts the dev server

**Rollback:** Keep `.env` file intact throughout. Delete `.doppler.yaml` to revert.

### Phase 2: CI Migration (Low Risk — Sync Approach)

**This phase requires zero workflow file changes.** Doppler sync (configured in Phase 0.4) pushes all secrets to GitHub Actions' native secrets store. All `secrets.*` references, `with:` inputs, `secrets: inherit`, and Docker build-args continue working exactly as before.

**2.1 Verify sync is active**

- [ ] `gh secret list` — all 23 secrets present
- [ ] Trigger a representative workflow manually (e.g., `scheduled-linkedin-token-check.yml`)
- [ ] Trigger `reusable-release.yml` workflow to validate Docker build-args still work

**Validation:** All 14 workflow files pass CI without any code changes. Secrets are sourced from Doppler via sync.

**Rollback:** Disable Doppler sync. GH Actions secrets remain with their current values.

### Phase 3: Server Runtime Migration (High Risk)

**This is the highest-risk phase.** Changes affect production container startup.

**CRITICAL: Docker env injection pattern.** Docker containers do NOT inherit the parent shell's environment. `doppler run -- docker run` would silently start containers with zero secrets. The correct pattern:

```bash
DOPPLER_TOKEN="$DOPPLER_TOKEN" \
  doppler secrets download --no-file --format docker --project soleur --config prd \
  | docker run --env-file /dev/stdin -d --name "$container" ...
```

This downloads secrets in Docker env format and pipes to `--env-file /dev/stdin`. Secrets never touch disk.

**3.1 Install Doppler CLI via cloud-init (pinned version)**

Modify both cloud-init files (`apps/telegram-bridge/infra/cloud-init.yml` and `apps/web-platform/infra/cloud-init.yml`):

### apps/web-platform/infra/cloud-init.yml (additions)

```yaml
runcmd:
  # Install Doppler CLI (pinned version for reproducibility)
  - curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh | DOPPLER_VERSION=3.x.x sh
  # Store Doppler service token in /etc/environment (accessible to all users including SSH forced commands)
  - echo "DOPPLER_TOKEN=${doppler_token}" >> /etc/environment
```

Note: Pin `DOPPLER_VERSION` to the latest stable version at implementation time, consistent with the repo's version-pinning convention (`check_deps.sh`).

**3.2 Add `doppler_token` as a Terraform variable**

Both Terraform stacks need the new variable:

### apps/web-platform/infra/variables.tf (addition)

```hcl
variable "doppler_token" {
  description = "Doppler service token for production secrets injection"
  type        = string
  sensitive   = true
}
```

Pass to cloud-init via `templatefile()` in both `server.tf` files:

```hcl
user_data = templatefile("cloud-init.yml", {
  image_name             = var.image_name
  deploy_ssh_public_key  = var.deploy_ssh_public_key
  ci_deploy_script_b64   = base64encode(file("ci-deploy.sh"))
  doppler_token          = var.doppler_token  # NEW
})
```

Apply same pattern to `apps/telegram-bridge/infra/variables.tf` and `server.tf`.

**3.3 Modify `ci-deploy.sh` to use Doppler**

Replace `--env-file /mnt/data/.env` with Doppler download piped to stdin:

### apps/web-platform/infra/ci-deploy.sh (key change)

```bash
# Before (line ~82):
docker run -d --name "$container" --env-file /mnt/data/.env ...

# After:
doppler secrets download --no-file --format docker --project soleur --config prd \
  | docker run --env-file /dev/stdin -d --name "$container" ...
```

`DOPPLER_TOKEN` is in `/etc/environment`, so it's available to the SSH forced command context without explicit `cat`.

Apply to all active `--env-file` locations:
- [ ] `apps/web-platform/infra/ci-deploy.sh:82` (web-platform container)
- [ ] `apps/web-platform/infra/ci-deploy.sh:109` (bridge container)
- [ ] `apps/web-platform/infra/cloud-init.yml:101` (initial web-platform start)
- [ ] `apps/telegram-bridge/infra/cloud-init.yml:90` (initial bridge start)

Note: `apps/telegram-bridge/scripts/deploy.sh` is a legacy manual deploy script that bypasses the CI pipeline's forced-command security. Do not modify — file a separate issue to remove it.

**3.4 Keep `/mnt/data/.env` as cold-start fallback**

- [ ] Do NOT remove `/mnt/data/.env` — it serves as fallback on freshly provisioned servers where Doppler has no local cache
- [ ] Cloud-init still creates the empty file (backward compat)
- [ ] `ci-deploy.sh` should fall back to `--env-file /mnt/data/.env` if `doppler secrets download` fails:

```bash
if ! doppler secrets download --no-file --format docker --project soleur --config prd \
     | docker run --env-file /dev/stdin -d --name "$container" ...; then
  echo "WARNING: Doppler download failed, falling back to /mnt/data/.env" >&2
  docker run -d --name "$container" --env-file /mnt/data/.env ...
fi
```

**Validation:**
- Deploy web-platform via CI: container starts, health check passes
- Deploy telegram-bridge via CI: container starts, bot responds
- Verify BYOK encryption/decryption still works

**Rollback:** Revert `ci-deploy.sh` to use `--env-file /mnt/data/.env`. The `.env` file is still on the server.

### Phase 4: Rotation & Cleanup

**4.1 Rotate all migrated secrets**

Per institutional learning (2026-02-10 API key leak): assume old values are compromised if they ever touched disk.

- [ ] Rotate each secret at its source (Discord dashboard, X developer portal, Stripe dashboard, etc.)
- [ ] Update new values in Doppler (single location)
- [ ] Doppler sync auto-pushes to GH Actions
- [ ] Deploy to pick up rotated production secrets

**4.2 Clean up old artifacts**

- [ ] Delete root `.env` file from developer machine
- [ ] Update `.env.example` files with comment: `# Secrets managed by Doppler. Run: doppler run -- <command>`

Note: `/mnt/data/.env` on the server stays as cold-start fallback. Update its values from Doppler periodically: `doppler secrets download --no-file --format docker --project soleur --config prd | ssh deploy@server 'cat > /mnt/data/.env && chmod 600 /mnt/data/.env'`

## Acceptance Criteria

- [ ] All 23 user-managed secrets stored in Doppler with correct config assignment
- [ ] `doppler run -- bun run dev` starts local dev with all secrets injected
- [ ] All 14 CI workflow files pass without modification (secrets via Doppler sync)
- [ ] Both production containers start via Doppler-injected env vars in `ci-deploy.sh`
- [ ] Credential rotation is `doppler secrets set KEY=newvalue` (single command, auto-propagates)
- [ ] Doppler failure falls back gracefully (cold-start: `/mnt/data/.env`; warm: cached secrets)
- [ ] BYOK_ENCRYPTION_KEY has offline backup independent of Doppler
- [ ] `web-platform/infra/.gitignore` includes `*.tfvars` and `.terraform.lock.hcl`

## Deferred Work

- **Terraform integration** — `doppler run --name-transformer tf-var -- terraform apply`. Deferred because Terraform runs quarterly and introduces naming-mismatch complexity (`CF_API_TOKEN` → `TF_VAR_cf_api_token` vs expected `cloudflare_api_token`). Track as follow-up issue.
- **Pre-commit secret scanning** — `git-secrets` or similar. Separate concern from Doppler migration. Track as follow-up issue.
- **Legacy deploy script removal** — `apps/telegram-bridge/scripts/deploy.sh` bypasses CI forced-command security. Track as follow-up issue.

## Institutional Learnings Applied

- **API key leak (2026-02-10):** Rotate all secrets after migration.
- **Env vars over CLI args (2026-02-18):** All Doppler injection via env vars. chmod 600 on token storage.
- **CI secrets gotcha (2026-02-12):** Sync approach avoids entirely — `secrets.*` references unchanged.
- **Bash operator precedence (2026-02-13):** Use `{ ...; }` grouping in ci-deploy.sh around fallback logic.
- **Cloud-init + Terraform separation (2026-02-10):** Terraform creates infra, cloud-init installs Doppler CLI.
- **Version pinning (commit 7e043fb):** Pin Doppler CLI version in cloud-init install.

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-03-20-secrets-manager-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-secrets-manager/spec.md`
- CI deploy script: `apps/web-platform/infra/ci-deploy.sh`
- Cloud-init (web): `apps/web-platform/infra/cloud-init.yml`
- Cloud-init (bridge): `apps/telegram-bridge/infra/cloud-init.yml`
- Web Dockerfile (build-args): `apps/web-platform/Dockerfile:12-14`
- Reusable release (secrets): `.github/workflows/reusable-release.yml:283-285`

### Related Issues

- #734 — This issue
- #678 — Discovery context (Playwright compensating for missing credentials)
