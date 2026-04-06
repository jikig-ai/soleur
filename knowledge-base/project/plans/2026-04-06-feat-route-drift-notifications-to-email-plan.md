---
title: "feat: route drift detection notifications to email instead of Discord"
type: feat
date: 2026-04-06
---

# feat: route drift detection notifications to email instead of Discord

## Overview

The Terraform drift detection workflow (`scheduled-terraform-drift.yml`) currently sends notifications via `DISCORD_WEBHOOK_URL` when drift or errors are detected. This webhook posts to a community-facing Discord channel, leaking internal infrastructure concerns to users. Drift alerts must be routed to a private operational channel instead.

Ref #1420. Triggered by #1412 (drift detected in web-platform DNS record).

## Problem Statement

When `terraform plan -detailed-exitcode` returns a non-zero exit code (2 = drift, 1 = plan error), the workflow's "Discord notification" step posts a message to whichever channel `DISCORD_WEBHOOK_URL` targets. This is the same webhook used by 13+ other workflows for failure notifications. The community Discord should only contain community-relevant content -- infrastructure drift is an internal operational concern.

### Scope of the Problem

13+ workflows share the same `DISCORD_WEBHOOK_URL` secret for failure/operational notifications (e.g., `scheduled-content-publisher.yml`, `rule-audit.yml`, `scheduled-weekly-analytics.yml`). The discord channel reorg plan (`2026-03-12-feat-discord-channel-reorg-plan.md`) already established the `DISCORD_<PURPOSE>_WEBHOOK_URL` naming pattern for channel-specific webhooks. This PR addresses only the drift workflow; the broader migration is deferred (see Deferral Tracking).

## Proposed Solution

Replace the Discord notification in `scheduled-terraform-drift.yml` with email notification via GitHub Actions. Two options were evaluated:

### Option A: Email via Resend HTTP API (Recommended)

Send email directly from the workflow using the Resend HTTP API (one `curl` call, no third-party action dependency). Resend is already provisioned for the project (Supabase auth emails). This:

- Routes to `ops@jikigai.com` (already in Doppler as `CF_NOTIFICATION_EMAIL`)
- Requires no new service subscriptions (Resend SMTP is already provisioned)
- Provides a clear audit trail in email
- Works independently of Discord availability

### Option B: Private `#ops-alerts` Discord channel

Create a new Discord channel and webhook (`DISCORD_OPS_WEBHOOK_URL`). This follows the existing channel reorg pattern but:

- Still requires Discord availability for ops alerts
- Adds another webhook secret to manage
- Does not solve the fundamental issue of relying on a community platform for ops alerting

### Option C: Better Stack alerting

Route to Better Stack for unified incident management. However:

- Better Stack is on free tier (email alerts only, no integrations)
- Would require upgrading for webhook ingestion
- Over-engineering for the current scale (solo operator)

### Option D: GitHub native notifications

Rely on GitHub's built-in email notifications for issue creation. However:

- Already works if watching the repo -- but depends on personal notification settings
- No control over formatting or urgency
- Easily lost in GitHub notification noise

### Option E: Remove Discord, add nothing (zero-code)

The drift workflow already creates/updates a GitHub issue with the `infra-drift` label. If the repo owner watches the repo, GitHub sends an email on issue creation. However:

- Depends on personal notification settings being correctly configured
- No subject line control (GitHub uses its own format)
- No guaranteed delivery -- if notifications are off or filtered, drift goes unnoticed
- Does not distinguish drift (exit 2) from plan error (exit 1) in the notification channel

**Decision: Option A (email via Resend HTTP API).** It reuses existing infrastructure (Resend API key works for both SMTP and HTTP API), routes to the established ops email (`ops@jikigai.com`), provides subject line control for filtering/urgency, and guarantees delivery regardless of GitHub notification settings. Option E was considered but rejected because ops alerting should not depend on personal notification configuration.

## Technical Approach

### Phase 1: Add email notification to drift workflow

Replace the "Discord notification" step in `scheduled-terraform-drift.yml` with an email step.

#### Implementation

1. **Add Resend API key to GitHub secrets.** Resend provides both SMTP and HTTP API. The HTTP API is simpler for GitHub Actions (one `curl` call, no SMTP action dependency). Store `RESEND_API_KEY` in Doppler (`prd` config) for canonical secret management, then set it as a GitHub Actions secret via `gh secret set RESEND_API_KEY`. The same API key works for both the HTTP API (used here) and SMTP (used by Supabase auth emails).

2. **Replace Discord step with email step** in `scheduled-terraform-drift.yml`:
   - Remove the existing "Discord notification" step (lines 188-227)
   - Add a new "Email notification" step that sends via Resend HTTP API
   - Send to `ops@jikigai.com`
   - From `noreply@soleur.ai` (already verified domain in Resend)
   - Subject includes stack name and alert type (drift vs error)
   - Body includes plan output summary and workflow run link

3. **Preserve exit code handling:** The email step fires on `steps.plan.outputs.exit_code != '0'` (same condition as the current Discord step), distinguishing drift (exit 2) from plan errors (exit 1).

#### Files Changed

| File | Change |
|------|--------|
| `.github/workflows/scheduled-terraform-drift.yml` | Replace Discord notification step with Resend email step |

### Phase 2: Audit other workflows (deferred)

The 12+ other workflows using `DISCORD_WEBHOOK_URL` for failure notifications have the same routing problem. However, those are lower priority:

- Content/growth workflows failing is less sensitive than infrastructure drift
- A broader migration should follow the channel reorg pattern already planned

This phase is tracked separately -- see Deferral Tracking below.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Private `#ops-alerts` Discord channel | Deferred | Still Discord-dependent; good complement but not primary |
| Better Stack webhook | Rejected | Requires paid upgrade for current scale |
| GitHub native notifications | Insufficient | No formatting control, lost in noise |
| `dawidd6/action-send-mail` GitHub Action | Considered | Adds a third-party action dependency; Resend HTTP API is simpler (one `curl` call) |
| Remove Discord, add nothing (rely on GitHub issue notifications) | Rejected | Depends on personal notification settings; no subject line control; no guaranteed delivery |

## Acceptance Criteria

- [ ] `scheduled-terraform-drift.yml` sends email to `ops@jikigai.com` when drift is detected (exit code 2)
- [ ] `scheduled-terraform-drift.yml` sends email to `ops@jikigai.com` when plan fails (exit code 1)
- [ ] Email includes stack name, alert type (drift vs error), workflow run link, and truncated plan output
- [ ] Email comes from `noreply@soleur.ai` (Resend verified domain)
- [ ] Discord notification step is removed from the drift workflow
- [ ] `RESEND_API_KEY` GitHub Actions secret is provisioned
- [ ] Workflow continues to function when `RESEND_API_KEY` is not set (graceful skip)
- [ ] Other workflows using `DISCORD_WEBHOOK_URL` are not affected by this change

## Test Scenarios

- Given drift is detected (exit code 2), when the email step runs, then an email is sent to `ops@jikigai.com` with subject containing "DRIFT" and the stack name
- Given plan fails (exit code 1), when the email step runs, then an email is sent to `ops@jikigai.com` with subject containing "ERROR" and the stack name
- Given `RESEND_API_KEY` is not set, when the email step runs, then it skips gracefully with a warning message
- Given the workflow runs with no drift (exit code 0), then no email is sent
- Given the email API returns a non-2xx status, then a workflow warning is emitted but the job does not fail

## Domain Review

**Domains relevant:** Operations

### Operations

**Status:** reviewed
**Assessment:** This is a pure operational routing change. The only cost implication is that Resend's free tier (100 emails/day) is more than sufficient for twice-daily drift checks across 2 stacks (max 4 emails/day worst case). No new vendor subscription required -- Resend is already provisioned for Supabase auth emails. The `ops@jikigai.com` address is already established as the operational contact.

### Product/UX Gate

Not applicable -- no user-facing changes. Infrastructure/tooling change only.

## Deferral Tracking

**Deferred: Migrate all workflow failure notifications from Discord to email/ops channel.** 12+ workflows use `DISCORD_WEBHOOK_URL` for failure notifications that are also operational (not community content). A broader migration should evaluate whether to:

1. Route all failure notifications to email (like this PR does for drift)
2. Create a private `#ops-alerts` Discord channel (per the channel reorg plan)
3. Both (email as primary, Discord as secondary)

**Re-evaluation criteria:** After this PR validates the Resend email pattern for drift, apply the same pattern to other operational workflows.

## References

- #1420 -- Parent issue
- #1412 -- Triggering drift alert (web-platform DNS record)
- `.github/workflows/scheduled-terraform-drift.yml` -- Workflow being modified
- `knowledge-base/project/plans/2026-03-12-feat-discord-channel-reorg-plan.md` -- Established `DISCORD_<PURPOSE>_WEBHOOK_URL` pattern
- `knowledge-base/project/learnings/2026-03-18-supabase-resend-email-configuration.md` -- Resend SMTP setup for Supabase auth
- `knowledge-base/project/learnings/2026-03-21-terraform-drift-dead-code-and-missing-secrets.md` -- Exit code semantics
- `knowledge-base/operations/expenses.md` -- Resend not listed (bundled with Supabase, free tier)
