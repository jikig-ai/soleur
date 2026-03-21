# Tasks: Monitor Cloudflare Access Service Token Expiration

## Phase 1: Terraform Notification Policy

- [ ] 1.1 Add `cf_notification_email` variable to `apps/web-platform/infra/variables.tf`
- [ ] 1.2 Add email value to Doppler `prd_terraform` config as `CF_NOTIFICATION_EMAIL`
- [ ] 1.3 Add `cloudflare_notification_policy.service_token_expiry` resource to `apps/web-platform/infra/tunnel.tf`
- [ ] 1.4 Run `terraform plan` and verify the notification policy resource appears as "will be created"
- [ ] 1.5 Run `terraform apply` to create the notification policy

## Phase 2: GitHub Actions Backup Workflow

- [ ] 2.1 Create `.github/workflows/scheduled-cf-token-expiry-check.yml`
  - [ ] 2.1.1 Add `workflow_dispatch` and `schedule` (weekly Monday 09:00 UTC) triggers
  - [ ] 2.1.2 Set `timeout-minutes: 5` on the job
  - [ ] 2.1.3 Implement Cloudflare API call to list service tokens (`GET /accounts/<id>/access/service_tokens`)
  - [ ] 2.1.4 Parse `expires_at` for the `github-actions-deploy` token
  - [ ] 2.1.5 Calculate days remaining from current date
  - [ ] 2.1.6 If <= 30 days: check for existing open issue (dedup), create or comment
  - [ ] 2.1.7 If > 30 days and stale issue exists: close with "token is valid" comment
  - [ ] 2.1.8 Handle API errors gracefully (warning annotation, not failure)
- [ ] 2.2 Verify required secrets exist: `CF_API_TOKEN` (or dedicated read-only token), `CF_ACCOUNT_ID`
- [ ] 2.3 Test workflow via `gh workflow run scheduled-cf-token-expiry-check.yml`
- [ ] 2.4 Poll run status and verify successful completion

## Phase 3: Rotation Runbook

- [ ] 3.1 Create `knowledge-base/learnings/2026-03-21-cloudflare-service-token-rotation.md`
  - [ ] 3.1.1 Document refresh procedure (extend expiry without credential change)
  - [ ] 3.1.2 Document rotation procedure (taint + apply + update GitHub secrets)
  - [ ] 3.1.3 Document verification procedure (trigger test deploy)
  - [ ] 3.1.4 Include YAML frontmatter (title, date, category, tags)

## Phase 4: Compound and Ship

- [ ] 4.1 Run `soleur:compound` before commit
- [ ] 4.2 Commit all changes
- [ ] 4.3 Push and create PR with `Closes #974` in body
- [ ] 4.4 Merge via `gh pr merge --squash --auto`
