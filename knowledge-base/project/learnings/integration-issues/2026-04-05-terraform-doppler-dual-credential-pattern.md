---
module: Web Platform Infrastructure
date: 2026-04-05
problem_type: integration_issue
component: tooling
symptoms:
  - "terraform plan fails with 'No value for required variable' when using bare doppler run"
  - "terraform init fails with 'No valid credential sources found' when using --name-transformer tf-var"
  - "Discord bot API returns 403 Missing Permissions for channel creation"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [terraform, doppler, name-transformer, tf-var, r2-backend, discord-bot, oauth2]
synced_to: []
---

# Terraform + Doppler Dual Credential Pattern and Discord Bot Re-Authorization

## Problem

Deploying `terraform_data.disk_monitor_install` to the production server required three credential layers that interact in non-obvious ways: (1) R2 backend credentials for Terraform state, (2) Doppler secrets mapped to `TF_VAR_` env vars for Terraform variables, and (3) a Discord bot token with sufficient permissions to create channels and webhooks.

## Environment

- Module: Web Platform Infrastructure
- Terraform: with R2 remote backend (Cloudflare)
- Doppler: `prd_terraform` config
- Discord Bot: `soleur-community` role
- Date: 2026-04-05

## Symptoms

- `doppler run -p soleur -c prd_terraform -- terraform plan` failed with "No value for required variable" for `webhook_deploy_secret`, `doppler_token`, `cf_notification_email`, `discord_ops_webhook_url`
- `doppler run --name-transformer tf-var -- terraform init` failed with "No valid credential sources found" for S3/R2 backend
- `POST /guilds/{guild_id}/channels` returned `{"message": "Missing Permissions", "code": 50013}`

## What Didn't Work

**Attempted Solution 1:** Bare `doppler run` without `--name-transformer tf-var`

- **Why it failed:** Doppler injects secrets with their original names (e.g., `WEBHOOK_DEPLOY_SECRET`). Terraform expects `TF_VAR_webhook_deploy_secret`. Without the name transformer, Terraform variables are not populated.

**Attempted Solution 2:** `doppler run --name-transformer tf-var` for everything

- **Why it failed:** The `--name-transformer tf-var` converts ALL secrets to `TF_VAR_` prefix, including `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. The R2 backend needs these as raw `AWS_*` env vars, not `TF_VAR_aws_*`.

## Session Errors

**Discord bot missing MANAGE_CHANNELS permission**

- **Recovery:** Generated OAuth2 re-authorization URL with updated permissions bitmap (`536939536 = current | MANAGE_CHANNELS`), user clicked Authorize
- **Prevention:** When adding Discord bot API calls to a plan, verify the bot's current permission bitmap against required permissions. Use `GET /guilds/{guild_id}/members/{bot_id}` to check roles and `GET /guilds/{guild_id}/roles` to decode permissions.

**Terraform SSH key passphrase incompatibility (repeat occurrence)**

- **Recovery:** Generated temporary unencrypted ed25519 key, same pattern as 2026-04-03
- **Prevention:** Already documented. Use `connection { agent = true }` in provisioner blocks. See `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`.

## Solution

The correct pattern requires two-step credential injection:

```bash
# Step 1: Extract R2 backend creds as raw AWS env vars
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

# Step 2: Use name-transformer for TF vars only
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -target=terraform_data.disk_monitor_install \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" \
    -var="ssh_private_key_path=/tmp/tf_temp_key" \
    -input=false
```

For Discord bot re-authorization, construct the OAuth2 URL with the updated permissions bitmap:

```text
https://discord.com/oauth2/authorize?client_id=<bot_id>&permissions=<new_bitmap>&scope=bot&guild_id=<guild_id>
```

Where `new_bitmap = current_permissions | required_permission_flags`.

## Why This Works

1. **R2 backend** reads `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` directly from env vars — these must NOT be transformed to `TF_VAR_` prefix
2. **Terraform variables** read from `TF_VAR_*` env vars — the `--name-transformer tf-var` converts Doppler secret names (e.g., `DISCORD_OPS_WEBHOOK_URL`) to Terraform var names (e.g., `TF_VAR_discord_ops_webhook_url`)
3. **SSH key path vars** must be passed explicitly via `-var` because they reference local paths not stored in Doppler
4. **Discord bot permissions** are encoded as a bitmap in the managed role. Re-authorizing with a new permissions value updates the role.

## Prevention

- When running Terraform locally with Doppler + R2 backend: always extract AWS creds separately before using `--name-transformer tf-var`
- The CI drift workflow (`scheduled-terraform-drift.yml`) already implements this pattern correctly — reference it as the canonical example
- When adding Discord API calls to deployment plans, include a permission verification step (check current permissions bitmap vs required)
- For the SSH key issue: migrate provisioner blocks to `connection { agent = true }` — tracked in existing learning

## Related Issues

- See also: [2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md](../2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md) (identical SSH key workaround)
- See also: [2026-03-21-doppler-tf-var-naming-alignment.md](../2026-03-21-doppler-tf-var-naming-alignment.md) (Doppler naming patterns)
- See also: [2026-03-29-doppler-service-token-config-scope-mismatch.md](../2026-03-29-doppler-service-token-config-scope-mismatch.md) (Doppler config scoping)
- Follow-through issue: #1538
- Source PR: #1525
