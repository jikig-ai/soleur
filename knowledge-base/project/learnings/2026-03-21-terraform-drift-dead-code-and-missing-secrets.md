# Learning: Terraform drift from dead code and missing Doppler secrets

## Problem

Two infra-drift issues (#987, #988) were auto-created by the scheduled drift workflow. Investigation revealed three distinct root causes:

1. **telegram-bridge** defined Hetzner resources (server, firewall, volume, SSH key) that were never needed — the bridge runs on the web-platform server. Terraform planned to "create" 6 resources that shouldn't exist.
2. **web-platform** had a missing Doppler secret (`CF_NOTIFICATION_EMAIL`) added in #983 code but never provisioned. This caused `terraform plan` to exit with code 1 (error), masking the real drift (firewall SSH restriction).
3. The CF API token lacked `Notifications:Edit` permission, causing partial `terraform apply` failure (firewall updated, notification policy creation failed with auth error 10000).

## Solution

### telegram-bridge: Remove dead Hetzner code

- Deleted `server.tf`, `firewall.tf`, `outputs.tf`, `cloud-init.yml`
- Removed hcloud provider from `main.tf` and 8 unused variables from `variables.tf`
- Result: `terraform plan` returns exit code 0 (no changes)

### web-platform: Provision secret and apply

- Added `CF_NOTIFICATION_EMAIL=ops@jikigai.com` to Doppler `prd_terraform` config
- Ran `terraform apply` — firewall SSH restriction applied (0.0.0.0/0 → 82.67.29.121/32)
- Filed #992 for the CF API token permission gap (notification policy still pending)

### Verification approach

- Ran `hcloud server list` to confirm no telegram-bridge resources exist in Hetzner
- Ran fresh `terraform plan` on both stacks after changes to confirm clean state

## Key Insight

Drift detection exit codes have three meanings that require different responses:

- **Exit 0:** No drift — everything matches
- **Exit 1:** Plan error — usually missing secrets or permissions, not drift
- **Exit 2:** Actual drift — resources differ from code

Exit code 1 is the most dangerous because it silently masks real drift. When a required variable is missing from Doppler, ALL resources become invisible to the plan, hiding genuine drift underneath. Always check Doppler provisioning when a drift workflow reports exit 1.

## Session Errors

1. Ran telegram-bridge `terraform plan` from wrong CWD (web-platform dir) — got misleading error
2. `hcloud server list` with invalid column name cancelled parallel calls
3. Cloudflare API calls for email lookup returned unauthorized (scoped token)

## Prevention

1. **Pre-merge secret validation:** When `variables.tf` adds a variable without a default, verify the corresponding Doppler key exists before merging
2. **Drift workflow error distinction:** Enhance the workflow to report exit code 1 differently from exit code 2 — exit 1 means "plan broken" not "drift detected"
3. **Resource ownership audits:** Each app's `infra/` dir should only define resources that app actually uses. If an app shares another's server, it should not duplicate server/firewall/volume resources.

## Tags

category: infrastructure-issues
module: apps/telegram-bridge/infra, apps/web-platform/infra
