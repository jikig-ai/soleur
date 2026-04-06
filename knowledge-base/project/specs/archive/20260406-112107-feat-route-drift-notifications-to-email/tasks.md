# Tasks: Route drift notifications to email

Ref: `knowledge-base/project/plans/2026-04-06-feat-route-drift-notifications-to-email-plan.md`

## Phase 1: Setup

- [ ] 1.1 Provision `RESEND_API_KEY` as GitHub Actions repository secret
  - Check Doppler for existing Resend API key (`doppler secrets --only-names -p soleur -c dev`, `-c prd`)
  - If not in Doppler, generate via Resend dashboard (Playwright MCP)
  - Store in Doppler, then set as GitHub Actions secret via `gh secret set`

## Phase 2: Core Implementation

- [ ] 2.1 Replace Discord notification step with email notification in `.github/workflows/scheduled-terraform-drift.yml`
  - Remove "Discord notification" step (lines 188-227)
  - Add "Email notification" step using Resend HTTP API (`curl`)
  - Condition: `steps.plan.outputs.exit_code != '0'`
  - Send to: `ops@jikigai.com`
  - From: `noreply@soleur.ai`
  - Subject: `[DRIFT] Infrastructure drift detected in <stack_name>` or `[ERROR] Terraform plan failed for <stack_name>`
  - Body: Stack name, timestamp, workflow run link, truncated plan output
  - Graceful skip: If `RESEND_API_KEY` is empty, echo warning and exit 0

## Phase 3: Testing

- [ ] 3.1 Trigger manual workflow run: `gh workflow run scheduled-terraform-drift.yml`
- [ ] 3.2 Verify email received at `ops@jikigai.com` with correct subject and body
- [ ] 3.3 Verify no Discord message was sent (confirm Discord step is removed)
- [ ] 3.4 Verify workflow succeeds when `RESEND_API_KEY` is unset (test graceful skip)

## Phase 4: Deferral Issue

- [ ] 4.1 Create GitHub issue to track migrating remaining workflow failure notifications from Discord to email
  - Include: list of 12+ affected workflows, evaluation criteria, link to this PR
  - Milestone: "Post-MVP / Later"
