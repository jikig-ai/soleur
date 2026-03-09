# X/Twitter Account Provisioning via Ops-Provisioner

**Date:** 2026-03-09
**Status:** decided
**Participants:** Founder, CMO, COO

## What We're Building

A guided provisioning workflow that uses the existing ops-provisioner agent to walk a founder through X/Twitter account registration, Developer Portal setup, API key generation, and expense recording — with agent-browser assisting on non-sensitive fields.

This is **not** automated account creation. The ops-provisioner navigates to the right pages, pre-fills safe fields (display name, bio from brand guide), and pauses for manual action on sensitive steps (credentials, verification, payment). X is the next tool to provision after Cloudflare and Plausible.

## Why This Approach

### Original Ask vs. Refined Scope

The original request was to automate X account registration via Playwright/agent-browser. Both CMO and COO independently rejected this:

- **ToS violation:** X prohibits automated account creation. Risk of immediate ban.
- **Negative ROI:** One-time 5-minute task. Automation would take hours with ongoing maintenance.
- **Human gates:** Developer Portal requires identity verification, app description review, and terms agreement.
- **Detection risk:** CAPTCHAs, phone verification, behavioral analysis designed to catch automation.

### Refined Scope

The actual need is a **guided provisioning flow** — the ops-provisioner pattern already used for Cloudflare and Plausible. The founder wants Soleur to:

1. Navigate to the right registration pages
2. Pre-fill non-sensitive fields from existing config (brand guide)
3. Pause for manual action on sensitive steps
4. Record the expense in the ops ledger

## Key Decisions

1. **Sequential single-session approach** — one run through all stages: account registration → Developer Portal → API keys → expense recording. Mirrors existing Cloudflare/Plausible pattern.

2. **Agent-browser assisted, not automated** — opens pages and pre-fills non-sensitive fields. Pauses for credentials, verification, payment. Follows ops-provisioner safety contract (never enters passwords, never clicks purchase buttons).

3. **General provisioning flow** — X is the use case, but any improvements benefit all future tool provisioning (the ops-provisioner is the reusable component).

4. **Existing infrastructure is sufficient** — `x-setup.sh` already handles credential validation (`validate-credentials`), env file writing (`write-env`), and round-trip verification (`verify`). No new scripts needed for the credential phase.

## Provisioning Steps

### Stage 1: X Account Registration
- **URL:** `https://x.com/i/flow/signup`
- **Pre-fill:** Display name "Soleur" from brand guide
- **Manual:** Email, phone verification, CAPTCHA, password
- **Validation:** Account accessible at `x.com/soleur` (or fallback handle)
- **Note:** Check handle availability first (`@soleur` preferred, `@soleur_ai` fallback)

### Stage 2: Developer Portal Setup
- **URL:** `https://developer.x.com`
- **Pre-fill:** App name "Soleur", app description from project description
- **Manual:** Developer terms agreement, identity verification, use case description
- **Validation:** Project and app visible in Developer Console

### Stage 3: API Key Generation + Validation
- **URL:** Developer Console → Keys and Tokens page
- **Manual:** Founder copies 4 credentials (API Key, API Secret, Access Token, Access Token Secret)
- **Automated:** `x-setup.sh write-env` stores credentials with `chmod 600`, `x-setup.sh verify` validates via API round-trip
- **Validation:** `GET /2/users/me` returns valid response

### Stage 4: Expense Recording
- **Automated:** ops-advisor updates `knowledge-base/ops/expenses.md` with X API tier costs
- **Decision needed:** Monthly budget ceiling for X API credits (CFO concern)
- **Note:** Free tier provides 50 tweets/month and `GET /2/users/me` only. Meaningful monitoring requires paid credits.

## Open Questions

1. **Handle availability** — Is `@soleur` available? Should check before starting provisioning.
2. **API budget ceiling** — How much to spend on X API credits monthly? Free tier is extremely limited. Basic-equivalent access is ~$100/mo.
3. **Secret storage for CI** — If community-manager runs on a schedule, env vars need to live in GitHub Actions secrets, not just local `.env`. This applies to all external API credentials (Discord has the same need).
4. **Current X API pricing model** — The brainstorm and spec from PR #466 have inconsistent pricing info. Need to verify current tier structure at developer.x.com before purchasing.

## Capability Gaps

- **COO:** The expense ledger is 15 days stale (last updated 2026-02-22). Should be reconciled before adding new line items. Plausible trial decision ($9/mo) due in 15 days is more urgent.
- **COO:** No credential rotation runbook exists. X would be the second external API (after Discord) — good trigger to create one.
- **CMO:** Zero follower cold-start problem. The marketing bottleneck is follower building, not account setup. Content strategy rates social as P2 (content marketing is Critical/P1).

## CMO Assessment Summary

The CMO recommends focusing automation on **post-registration** high-leverage activities:
- Automate profile branding (bio, avatar, header from brand guide) via API
- Automate first-post introduction thread via `social-distribute`
- Automate credential distribution via existing `x-setup.sh`
- Check handle availability with a simple curl before manual registration

## COO Assessment Summary

The COO recommends:
- P0: Check `@soleur` handle availability (zero cost, 30 seconds)
- P1: Decide Plausible trial conversion ($9/mo, 15 days until expiry)
- P1: Research current X API pricing model (brainstorm/spec are inconsistent)
- P2: Register X account manually, validate with ops-provisioner flow
- P3: Evaluate secret management for unattended agent use
- P3: Update expense ledger with X API costs once provisioned
