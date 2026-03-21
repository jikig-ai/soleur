---
title: "feat: Migrate Terraform State to Cloudflare R2"
type: feat
date: 2026-03-21
---

# feat: Migrate Terraform State to Cloudflare R2

## Overview

Migrate both Terraform stacks (`telegram-bridge` and `web-platform`) from implicit local backend to Cloudflare R2 remote state. Import all 24 existing resources. Add AGENTS.md hard rule requiring remote backend for all future Terraform roots.

CI `terraform plan` workflow and Lefthook pre-commit hooks are deferred to follow-up issues — ship the state migration first to unblock #967.

## Problem Statement

Both stacks use the default local backend — state has been lost (confirmed in #967). Live infrastructure (Hetzner servers, Cloudflare DNS/tunnels) exists but Terraform cannot track it. This blocks #967 (Cloudflare Tunnel server provisioning) and creates ongoing operational risk.

## Proposed Solution

### Phase 1: Bootstrap R2 Backend

Create the R2 bucket and credentials. This is a chicken-and-egg bootstrap step — the bucket must exist before Terraform can use it as a backend. This is an explicit exception to the AGENTS.md "Terraform for provisioning" rule: the state backend itself cannot be managed by the Terraform that depends on it.

**1.1 Fix wrangler auth** — The current `CF_API_TOKEN` is expired/broken (401 errors). Either:
- Source a valid token from Doppler: `eval $(doppler secrets get CLOUDFLARE_API_TOKEN --plain)` and export as `CLOUDFLARE_API_TOKEN`
- Or run `wrangler login` via Playwright MCP (browser OAuth)

**1.2 Create R2 bucket:**
```bash
wrangler r2 bucket create soleur-terraform-state
```

**1.3 Enable bucket versioning** (for state recovery) via S3-compatible API:
```bash
# R2 versioning uses the S3-compatible API, not the Cloudflare v4 REST API
aws s3api put-bucket-versioning \
  --bucket soleur-terraform-state \
  --versioning-configuration Status=Enabled \
  --endpoint-url "https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
```

**1.4 Create R2 API token** scoped to `soleur-terraform-state` bucket with Object Read & Write.
- Via Cloudflare dashboard or API
- Produces: Access Key ID + Secret Access Key

**1.5 Store credentials in Doppler:**
- Doppler project: `soleur`, config: `prd_terraform` (same config used by `doppler run --` for Terraform operations)
- Key names (S3 convention — Terraform S3 backend reads these automatically):
  - `AWS_ACCESS_KEY_ID` = R2 access key
  - `AWS_SECRET_ACCESS_KEY` = R2 secret key

**Files created/modified:** None (bucket is external infrastructure)

### Phase 2: Backend Configuration + Hygiene

Add the `backend "s3"` block to both stacks, initialize remote state, update gitignore, commit lock files, and add the AGENTS.md guardrail. All in one commit.

**2.1 `apps/telegram-bridge/infra/main.tf`** — Add backend block:
```hcl
terraform {
  backend "s3" {
    bucket                      = "soleur-terraform-state"
    key                         = "telegram-bridge/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false  # R2 does not support S3 conditional writes
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
  required_version = ">= 1.6"
}
```

**2.2 `apps/web-platform/infra/main.tf`** — Same backend block with `key = "web-platform/terraform.tfstate"`. Also bump `required_version` to `>= 1.6` (the `endpoints` syntax requires it).

**2.3 Add `lifecycle { ignore_changes = [user_data] }` to both server resources:**
- `apps/telegram-bridge/infra/server.tf` — `hcloud_server.bridge`
- `apps/web-platform/infra/server.tf` — `hcloud_server.web`

After import, `templatefile()` in `user_data` produces a different hash than the live server's stored value. Without `ignore_changes`, Terraform marks the server for replacement (destructive — wipes running workload). This is safe because `user_data` only runs at server creation time.

**2.4 Remove `.terraform.lock.hcl` from per-directory `.gitignore` files:**
- `apps/telegram-bridge/infra/.gitignore`
- `apps/web-platform/infra/.gitignore`

**2.5 Initialize remote backend** (per stack):
```bash
cd apps/<stack>/infra
doppler run --project soleur --config prd_terraform -- terraform init
```
Since local state is lost, Terraform creates an empty remote state in R2. No migration prompt. This also generates the `.terraform.lock.hcl` file — commit it.

**2.6 Add AGENTS.md hard rule:**
```markdown
- Every new Terraform root must include an R2 remote backend block. Use the `soleur-terraform-state` bucket with a unique key path matching the app name (e.g., `key = "<app-name>/terraform.tfstate"`). Copy the backend block from `apps/telegram-bridge/infra/main.tf` as the template. Local state is never acceptable.
```

**Files modified:**
- `apps/telegram-bridge/infra/main.tf`
- `apps/web-platform/infra/main.tf`
- `apps/telegram-bridge/infra/server.tf` (lifecycle block)
- `apps/web-platform/infra/server.tf` (lifecycle block)
- `apps/telegram-bridge/infra/.gitignore`
- `apps/web-platform/infra/.gitignore`
- `apps/telegram-bridge/infra/.terraform.lock.hcl` (committed)
- `apps/web-platform/infra/.terraform.lock.hcl` (committed)
- `AGENTS.md`

### Phase 3: Import Existing Resources

Import all 24 live resources into the new remote state.

**3.0 Discover resource IDs** — Before importing, retrieve IDs via CLI/API:
```bash
# Hetzner (both stacks) — install hcloud if needed
which hcloud || (curl -sL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz | tar xz -C ~/.local/bin hcloud)

hcloud server list -o columns=id,name
hcloud volume list -o columns=id,name
hcloud firewall list -o columns=id,name
hcloud ssh-key list -o columns=id,name

# Cloudflare (web-platform only)
# DNS records, tunnels, access apps via Cloudflare API
```

**3.1 telegram-bridge (6 resources):**
```bash
cd apps/telegram-bridge/infra
doppler run --project soleur --config prd_terraform -- bash -c '
  terraform import hcloud_ssh_key.default <SSH_KEY_ID>
  terraform import hcloud_server.bridge <SERVER_ID>
  terraform import hcloud_volume.data <VOLUME_ID>
  terraform import hcloud_volume_attachment.data <VOLUME_ID>
  terraform import hcloud_firewall.bridge <FIREWALL_ID>
  terraform import hcloud_firewall_attachment.bridge <FIREWALL_ID>
'
```

Note: `hcloud_firewall_attachment` imports by firewall ID only (not `<FIREWALL_ID>-<SERVER_ID>`).

**3.2 web-platform (17 resources, excluding `random_id`):**

Hetzner resources (6):
```bash
terraform import hcloud_ssh_key.default <SSH_KEY_ID>
terraform import hcloud_server.web <SERVER_ID>
terraform import hcloud_volume.workspaces <VOLUME_ID>
terraform import hcloud_volume_attachment.workspaces <VOLUME_ID>
terraform import hcloud_firewall.web <FIREWALL_ID>
terraform import hcloud_firewall_attachment.web <FIREWALL_ID>
```

Cloudflare DNS (6):
```bash
terraform import cloudflare_record.app <ZONE_ID>/<RECORD_ID>
terraform import cloudflare_record.deploy <ZONE_ID>/<RECORD_ID>
terraform import cloudflare_record.dkim_resend <ZONE_ID>/<RECORD_ID>
terraform import cloudflare_record.spf_send <ZONE_ID>/<RECORD_ID>
terraform import cloudflare_record.mx_send <ZONE_ID>/<RECORD_ID>
terraform import cloudflare_record.dmarc <ZONE_ID>/<RECORD_ID>
```

Cloudflare Zero Trust (5):
```bash
terraform import cloudflare_zero_trust_tunnel_cloudflared.web <ACCOUNT_ID>/<TUNNEL_ID>
terraform import cloudflare_zero_trust_tunnel_cloudflared_config.web <ACCOUNT_ID>/<TUNNEL_ID>
terraform import cloudflare_zero_trust_access_application.deploy <ACCOUNT_ID>/<APP_ID>
terraform import cloudflare_zero_trust_access_service_token.deploy <ACCOUNT_ID>/<TOKEN_ID>
terraform import cloudflare_zero_trust_access_policy.deploy_service_token <ACCOUNT_ID>/<APP_ID>/<POLICY_ID>
```

**3.3 Handle `random_id.tunnel_secret` (DANGEROUS — highest-risk import):**

The `random_id` resource generated a 32-byte tunnel secret stored only in lost state. The live value exists inside the Cloudflare tunnel configuration.

**Pre-import verification:**
```bash
# Retrieve tunnel token via Cloudflare API
curl -s "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" | jq .result
```

The tunnel token is a JWT-like payload containing the secret. Extract the 32-byte secret and convert to **base64url encoding** (no padding, `-` instead of `+`, `_` instead of `/`). This is the format `terraform import random_id` expects:
```bash
terraform import random_id.tunnel_secret <BASE64URL_NO_PADDING>
```

**If import succeeds but plan shows a diff on `cloudflare_zero_trust_tunnel_cloudflared.web.secret`:** The value mismatch will trigger tunnel recreation. **BLOCK — do not apply.** Recovery: `terraform state rm random_id.tunnel_secret` and retry with the correct value.

**If the value cannot be recovered:** Stop and reassess. Options include restructuring `tunnel.tf` to use a Doppler-stored secret instead of `random_id`, but that design should be done deliberately, not as a panic fix.

**3.4 Handle `cloudflare_zero_trust_access_service_token.deploy`:**
The `client_secret` is only available at creation time. After import, the secret output will be empty. If CI deploy relies on this value, it must be re-created or stored separately in Doppler.

**3.5 Known post-import plan diffs:**
- `user_data` — handled by `lifecycle { ignore_changes = [user_data] }` added in Phase 2.3
- `config_src = "cloudflare"` on the tunnel may conflict with the `cloudflare_zero_trust_tunnel_cloudflared_config` resource managing config via Terraform. If plan shows a diff here, investigate whether `config_src` should be `"local"` instead.

**3.6 Verify — zero diff:**
```bash
doppler run --project soleur --config prd_terraform -- terraform plan
# Expected: "No changes. Your infrastructure matches the configuration."
```

**Files modified:** None (state changes only)

### Phase 4: Follow-Up Issues

File separate issues for deferred work. These are valuable guardrails but not prerequisites for recovering state.

- [ ] **CI `terraform plan` on PRs** — new workflow or extension of `infra-validation.yml`, Doppler-first credentials, fork PR handling, PR comment posting
- [ ] **Lefthook pre-commit hooks** — `terraform fmt -check` and optionally `tflint` for infra file changes
- [ ] **Drift detection** — scheduled `terraform plan -detailed-exitcode` workflow (brainstorm open question 1)

## Technical Considerations

### Architecture
- R2 backend is a thin storage layer — no compute, no locking, no vendor lock-in beyond Cloudflare
- Per-app state key paths provide blast radius isolation
- Backend block is static (no variables) — endpoint hardcodes the Cloudflare account ID
- `use_lockfile = false` explicitly disables S3 conditional writes (R2 doesn't support them). Future-proofs against Terraform 1.11+ defaulting to `true`

### Security
- State files contain sensitive values (API tokens, IPs). R2 encrypts at rest by default. Access restricted to the scoped R2 API token.
- R2 credentials flow: Doppler → env vars → Terraform S3 backend (no CLI args, no committed files)

### Risks
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `random_id.tunnel_secret` import fails | Medium | High (tunnel recreation = downtime) | Verify value via CF API before import. If wrong, `state rm` and retry. If unrecoverable, stop and redesign. |
| Wrangler auth broken | Known | Blocks Phase 1 | Source token from Doppler or `wrangler login` via Playwright |
| `config_src` conflict on tunnel | Medium | Low (plan drift, not destructive) | Investigate during Phase 3.5, adjust `config_src` value if needed |

## Acceptance Criteria

- [ ] `terraform plan` in both stacks shows "No changes" after import
- [ ] State files exist in R2 at `telegram-bridge/terraform.tfstate` and `web-platform/terraform.tfstate`
- [ ] R2 bucket has versioning enabled
- [ ] AGENTS.md contains remote backend hard rule with template
- [ ] `.terraform.lock.hcl` committed for both stacks
- [ ] No `.tfstate` files in the repository
- [ ] #967 is unblocked
- [ ] Follow-up issues filed for CI plan workflow and Lefthook hooks

## Test Scenarios

- Given both stacks have remote state, when `terraform plan` runs, then output is "No changes"
- Given a new Terraform root at `apps/new-app/infra/` without a backend block, when an agent reads AGENTS.md, then it adds the R2 backend template

## Dependencies & Risks

- **Blocks:** #967 (Cloudflare Tunnel provisioning) — unblocked once state is imported
- **Related:** #969 (Doppler + Terraform integration) — R2 credentials use Doppler
- **Depends on:** Valid Cloudflare API token (wrangler auth currently broken)
- **In-flight worktrees:** `doppler-terraform` touches variables.tf files — merge before or after, not during

## References

### Internal
- Brainstorm: `knowledge-base/brainstorms/2026-03-21-terraform-state-mgmt-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-terraform-state-mgmt/spec.md`
- Best practices: `knowledge-base/learnings/2026-02-13-terraform-best-practices-research.md`
- Import IDs reference: `.worktrees/cf-tunnel-server-provisioning/knowledge-base/plans/2026-03-21-infra-cf-tunnel-server-provisioning-plan.md` (lines 107-125)

### External
- [Cloudflare R2 as Terraform Backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [Terraform S3 Backend Docs](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Hetzner S3 Backend Tutorial](https://community.hetzner.com/tutorials/howto-hcloud-s3-terraform-backend/)
