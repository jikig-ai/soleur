# Brainstorm: LinkedIn API Scripts (linkedin-community.sh, linkedin-setup.sh)

**Date:** 2026-03-13
**Issue:** #589
**Parent:** #138 (LinkedIn Presence)
**Branch:** feat/linkedin-api-scripts
**Status:** Complete

## What We're Building

Two shell scripts following the established community platform pattern:

- **`linkedin-community.sh`**: Platform API wrapper with `post-content` (live, using `w_member_social` open permission), `fetch-metrics` (stub, gated on Marketing API), and `fetch-activity` (stub, gated on Marketing API).
- **`linkedin-setup.sh`**: Credential lifecycle management with `validate-credentials` (token introspection API), `generate-token` (Playwright-assisted OAuth flow), `check-expiry` (schedulable token TTL monitor with Discord alerts), and `write-env` (credential persistence).

## Why This Approach

### Posting is Unblocked

The original issue stated "Blocked on LinkedIn API App approval" — this is only partially true. LinkedIn's `w_member_social` permission is an **open/self-service permission** available to all developers without approval. Only the Marketing API (analytics, ad management) requires MDP partner approval. This means posting commands can ship immediately.

### 60-Day Token Lifecycle is a Design Constraint

Without Marketing Developer Platform (MDP) approval, LinkedIn provides **no programmatic refresh tokens**. Access tokens expire after 60 days and renewal requires re-running the browser OAuth flow. For a solo operator, this is a silent failure waiting to happen — posting and monitoring will break with no alert. The `check-expiry` command solves this by running on a schedule and sending Discord notifications at 14-day and 7-day thresholds.

### Bearer Token is the Simplest Auth Model

LinkedIn's OAuth 2.0 Bearer token is simpler than every other platform in the ecosystem:
- X/Twitter: OAuth 1.0a with HMAC-SHA1 signing (most complex)
- Bluesky: Session-based JWT with createSession step
- Discord: Bot token with `Authorization: Bot` prefix
- LinkedIn: Plain `Authorization: Bearer <token>` (simplest)

## Key Decisions

1. **Build posting now, stub analytics.** `post-content` uses `w_member_social` (self-service, available today). `fetch-metrics` and `fetch-activity` are stubs that check for Marketing API credentials and exit with a clear message. Avoids shipping dead code while following the established pattern of complete command sets.

2. **Playwright-assisted token generation.** `linkedin-setup.sh generate-token` invokes Playwright to drive the OAuth flow — creates the app, navigates to token generator, selects scopes. User only handles login credentials and the "Allow" consent click. Token gets auto-captured and written to `.env`.

3. **Scheduled token expiry monitoring.** `linkedin-setup.sh check-expiry` calls LinkedIn's `/introspectToken` endpoint, checks TTL, and sends Discord notifications at 14-day and 7-day thresholds. Designed for GitHub Actions cron scheduling. This is a net-new pattern — no other platform has expiring tokens that need monitoring.

4. **Three env vars minimum.** `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN`. Client credentials are required for token introspection. Optional: `LINKEDIN_REFRESH_TOKEN` (only available with MDP approval), `LINKEDIN_TOKEN_EXPIRES_AT` (cached TTL for local checks).

5. **Follow x-community.sh structure exactly.** Same 10-section layout (shebang, hardening, base URL, dependency checks, credential validation, auth, response handler, request helpers, command functions, main dispatch). Swap OAuth 1.0a signing for simple Bearer header. Apply 5-layer hardening pattern from learnings.

6. **Token introspection for validation.** `validate-credentials` calls `POST /oauth/v2/introspectToken` with client credentials and token. Returns active/expired status, days remaining, granted scopes. More reliable than local expiry caching since LinkedIn can revoke tokens at any time.

## Open Questions

1. **LinkedIn Company Page creation** — still requires manual browser action. Playwright could automate navigation to the creation form but the page itself may require admin verification steps.
2. **MDP approval timeline** — unknown. The hybrid approach means this doesn't block shipping.
3. **Token storage for CI** — GitHub Actions secrets for `LINKEDIN_ACCESS_TOKEN` expire every 60 days. The `check-expiry` cron job would itself need valid credentials to check validity. Bootstrap problem to address.

## Domain Leader Assessments

### CCO Assessment
- Community SKILL.md needs LinkedIn in 4 places: platform detection table, scripts list, `platforms` sub-command output, setup instructions
- No support runbooks directory exists (`knowledge-base/support/`) — gap for all platforms, not just LinkedIn
- 60-day token refresh is a net-new operational concern with no monitoring today (validates Approach 3 choice)
- Issue dependency chain: #589 blocks #590 (content-publisher) and #592 (workflow secrets)

## Scope Summary

### In Scope
- `linkedin-community.sh` with `post-content` (live), `fetch-metrics` (stub), `fetch-activity` (stub)
- `linkedin-setup.sh` with `validate-credentials`, `generate-token` (Playwright), `check-expiry`, `write-env`
- 5-layer shell hardening (input, transport, response parsing, error extraction, retry arithmetic)
- Token introspection integration (`/oauth/v2/introspectToken`)
- Discord notification for token expiry warnings
- SKILL.md updates for LinkedIn platform registration

### Out of Scope
- Marketing API analytics (requires MDP approval — separate PR)
- Programmatic refresh token flow (requires MDP approval)
- LinkedIn Company Page creation (manual browser action)
- Community adapter interface refactor (#470)
- Support runbooks directory (pre-existing gap, separate issue)
