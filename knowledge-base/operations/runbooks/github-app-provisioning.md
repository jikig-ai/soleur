---
title: GitHub App provisioning — Soleur-Concierge (PR-H)
status: active
date: 2026-05-19
related: [3244, 4066]
brand_survival_threshold: single-user incident
---

# GitHub App provisioning — Soleur-Concierge

Operator runbook for the single manual gate in PR-H (#3244) Phase 2. The GitHub App is created once at `https://github.com/settings/apps/new`; thereafter the secrets land in Doppler `prd` via `terraform apply` and the webhook lives.

The manual gate is tracked for future automation (per `hr-never-label-any-step-as-manual-without`) — the `integrations/github` Terraform provider does not yet support App creation. See deferred-automation issue filed at PR-H Phase 2 start.

## Prerequisites

- Operator authenticated to github.com as a user with administrative access to jikig-ai/soleur.
- Operator has `prd_terraform` Doppler config access for the post-apply secret writes.
- AWS/R2 backend creds available in the same Doppler config (already there from inngest.tf bootstrap).

## Step 1 — Create the GitHub App

1. Navigate to `https://github.com/settings/apps/new`.
2. **App name:** `Soleur-Concierge`
3. **Homepage URL:** `https://soleur.ai`
4. **Webhook URL:** `https://soleur.ai/api/webhooks/github` (also output by terraform after step 3 as `github_app_webhook_url`).
5. **Webhook secret:** leave blank for now — Soleur generates this via `random_id` in Step 3 and you paste it back in Step 4.
6. **Repository permissions:**
   - `pull_requests:read`
   - `issues:read`
   - `metadata:read` (auto-required)
   - `actions:read`
   - `repository_advisories:read`
   - `secret_scanning_alerts:read`
7. **Subscribe to events:**
   - `pull_request`
   - `workflow_run`
   - `issues`
   - `repository_advisory`
   - `secret_scanning_alert`
8. **Where can this App be installed?** Only on this account (founder's own account/orgs only — per ADR-036 multi-org install is out-of-scope at MVP).
9. **Click "Create GitHub App."**

## Step 2 — Capture the App identity material

After creation, you land on the App settings page.

- **App ID:** copy the numeric value shown at the top.
- **Client ID:** copy the `Iv1.<hex>` value.
- **Client Secret:** click "Generate a new client secret." Copy the one-shot value.
- **PEM:** scroll to "Private keys" and click "Generate a private key." A `.pem` file downloads automatically. This is one-shot — keep it.

## Step 3 — Export TF_VAR_*

In your terminal (one shell session for the apply):

    export TF_VAR_github_app_id="<APP_ID>"
    export TF_VAR_github_app_private_key="$(cat ~/Downloads/soleur-concierge.<date>.private-key.pem)"

Post-#4150: `TF_VAR_github_app_client_id` and `TF_VAR_github_app_client_secret` are no longer required — the OAuth client credentials had no runtime consumer and were removed. If a future feature needs the OAuth client flow, re-add the variables and the matching `doppler_secret` resources in `github-app.tf`.

For the GitHub Actions secret publishing path, the `integrations/github` provider now authenticates via App-installation auth (`main.tf` `app_auth { id, installation_id, pem_file }`) using the same `TF_VAR_github_app_id` + `TF_VAR_github_app_private_key` already exported above. The App's `Secrets: Read & Write` repository permission is the load-bearing scope. The Doppler service token for the kb-drift cron is now minted in-band by the `doppler_service_token.kb_drift` resource (`kb-drift.tf`) — no operator-mint required.

NOTE: the `prd_kb_drift_walker` Doppler config must exist BEFORE first apply. Create it once via the Doppler dashboard (Project → soleur → New config under `prd` environment, name = `prd_kb_drift_walker`). Future Terraform automation tracked separately.

## Step 4 — Canonical Terraform apply

Per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan`:

    export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
    export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
    cd apps/web-platform/infra
    terraform init -input=false
    doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -out=plan.tfplan
    # Review the plan: expect 3 doppler_secret in `prd` (github_app_id, pem,
    #   webhook_secret) + 1 random_id (webhook secret) + 1 random_id
    #   (kb-drift signing key) + 1 doppler_secret (kb-drift signing key)
    #   + 1 doppler_secret (kb-drift ingest URL) + 1 doppler_service_token
    #   (kb-drift Actions secret source) + 1 github_actions_secret
    #   + 3 betteruptime_* resources (only when betterstack_paid_tier=true).
    doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply plan.tfplan

## Step 5 — Paste the webhook secret back into the GitHub App

After apply succeeds:

    terraform output -raw github_app_webhook_url
    doppler secrets get GITHUB_APP_WEBHOOK_SECRET -p soleur -c prd --plain | pbcopy

Go back to the GitHub App settings page → **Webhook → Secret** → paste the value, **Save changes**.

## Step 6 — Install the App on the founder's test repo

1. Go to the App's "Install App" page.
2. Choose the founder's own account.
3. Pick "Only select repositories" → choose the test repo(s).
4. Approve the install.

Capture the resulting `installation_id` (visible in the URL of the install page: `/installations/<INSTALLATION_ID>`). It will be used as `users.github_installation_id` in a future onboarding step.

## Rotation

- **Webhook secret rotation:** `terraform apply -replace=random_id.github_webhook_secret` — then re-paste per Step 5.
- **App PEM rotation:** generate a new PEM in the GitHub App settings (the old PEM stays valid until revoked). Update `TF_VAR_github_app_private_key` and `terraform apply` — the `ignore_changes = [value]` on the doppler_secret means you must use `terraform taint doppler_secret.github_app_private_key` first.
- **kb-drift Doppler token rotation:** `terraform apply -replace=doppler_service_token.kb_drift`. The new token value propagates to the published `DOPPLER_TOKEN_KB_DRIFT` Actions secret in the same apply (no `ignore_changes` on `github_actions_secret.doppler_token_kb_drift.plaintext_value` — Post-#4150 deliberate change).

## Failure modes

- **Apply fails on the `github` provider auth (401/403):** Post-#4150 the provider uses App-installation auth. Verify (a) `TF_VAR_github_app_id` + `TF_VAR_github_app_private_key` are set, (b) the App is installed on the org with installation_id `122213433` (`gh api /orgs/jikig-ai/installations`), (c) the App declares `secrets:write` at the App-permissions level AND the installation has accepted that permission.
- **Apply fails on `doppler_service_token.kb_drift`:** verify (a) `prd_kb_drift_walker` config exists, (b) `DOPPLER_TOKEN_TF` (workplace personal token) has scope to mint config-scoped service tokens.
- **Apply fails on `prd_kb_drift_walker` config not found:** the Doppler config must exist before first apply. Create it in the Doppler dashboard.
- **Webhook 401 in production:** signature verification failing. Confirm Step 5 (you pasted the new secret into the App). The route fails closed and Sentry mirrors the event at `level: error`.

## Cross-references

- ADR-036 — GitHub App webhook as second multi-source ingress
- ADR-037 — messages.source_ref composite-unique for multi-source dedup
- Migration 051 — audit_github_token_use + processed_github_events + messages.source_ref
