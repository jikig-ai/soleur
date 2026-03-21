# Tasks: Monitor Cloudflare Access Service Token Expiration

## Phase 1: Terraform Notification Policy

- [ ] 1.1 Add `cf_notification_email` variable to `apps/web-platform/infra/variables.tf`
- [ ] 1.2 Add email value to Doppler `prd_terraform` config as `CF_NOTIFICATION_EMAIL`
- [ ] 1.3 Add `cloudflare_notification_policy.service_token_expiry` resource to `apps/web-platform/infra/tunnel.tf` (use v4 `email_integration` syntax, not v5 `mechanisms`)
- [ ] 1.4 Run `terraform validate` (catches attribute name mismatches without credentials)
- [ ] 1.5 Run `terraform plan` and verify the notification policy resource appears as "will be created"
- [ ] 1.6 Run `terraform apply` to create the notification policy

## Phase 2: GitHub Actions Backup Workflow

- [ ] 2.1 Create `.github/workflows/scheduled-cf-token-expiry-check.yml`
  - [ ] 2.1.1 Add `workflow_dispatch` trigger only (cron commented out until validated)
  - [ ] 2.1.2 Set `timeout-minutes: 5` on the job
  - [ ] 2.1.3 Set `permissions: { issues: write }`
  - [ ] 2.1.4 Add `concurrency` block to prevent parallel runs
  - [ ] 2.1.5 Implement Cloudflare API call: `GET /client/v4/accounts/<id>/access/service_tokens`
  - [ ] 2.1.6 Parse `expires_at` (ISO 8601) for the `github-actions-deploy` token via jq
  - [ ] 2.1.7 Calculate days remaining using GNU `date -d`
  - [ ] 2.1.8 If <= 30 days: pre-create `action-required` label (`gh label create ... || true`), check for existing open issue (dedup), create or comment
  - [ ] 2.1.9 If > 30 days and stale issue exists: close with "token is valid" comment
  - [ ] 2.1.10 Handle missing secrets and API errors gracefully (warning annotation, exit 0)
- [ ] 2.2 Add `CF_ACCOUNT_ID` as repository variable (`vars.CF_ACCOUNT_ID`) -- not a secret
- [ ] 2.3 Verify `CF_API_TOKEN` has Access:Read scope
- [ ] 2.4 Test workflow via `gh workflow run scheduled-cf-token-expiry-check.yml`
- [ ] 2.5 Poll run status and verify successful completion
- [ ] 2.6 After validation, uncomment cron schedule and push

## Phase 3: Rotation Runbook

- [ ] 3.1 Create `knowledge-base/project/learnings/2026-03-21-cloudflare-service-token-rotation.md`
  - [ ] 3.1.1 Document refresh procedure (extend expiry via `duration` attribute change)
  - [ ] 3.1.2 Document zero-downtime rotation (`client_secret_version` + `previous_client_secret_expires_at`)
  - [ ] 3.1.3 Document hard-cut rotation (`terraform apply -replace=` -- NOT deprecated `terraform taint`)
  - [ ] 3.1.4 Document verification procedure (trigger test deploy)
  - [ ] 3.1.5 Include YAML frontmatter (title, date, category, tags)

## Phase 4: Compound and Ship

- [ ] 4.1 Run `soleur:compound` before commit
- [ ] 4.2 Commit all changes
- [ ] 4.3 Push and create PR with `Closes #974` in body
- [ ] 4.4 Merge via `gh pr merge --squash --auto`
