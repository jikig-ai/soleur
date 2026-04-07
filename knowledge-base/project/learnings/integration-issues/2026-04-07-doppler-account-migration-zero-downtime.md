---
category: integration-issues
module: doppler
severity: low
tags: [doppler, secrets-management, account-migration, operations]
date: 2026-04-07
---

# Learning: Doppler Workspace Account Migration (Zero Downtime)

## Problem

The Doppler workspace was created under <jean@osmosis.team> (osmosis.team domain).
To fully decouple from the osmosis.team domain, ownership needed to transfer to
<ops@jikigai.com> with zero downtime -- no service token rotation, no CI disruption,
no production impact.

## Investigation

Checked the following before starting the migration:

- **Doppler API capabilities**: Tested invite, user removal, and workspace update
  endpoints. Found that team management (invites, user removal) is NOT supported
  via API -- only via the dashboard UI. Workspace metadata (billing_email,
  security_email) IS updatable via `POST /v3/workplace`.
- **Service token scope**: Confirmed that Doppler service tokens are scoped to
  workspace/project/config, not to the user who created them. This was the key
  finding that made zero-downtime migration possible.
- **Existing configs**: Verified all 6 configs (dev, dev_personal, ci, prd,
  prd_scheduled, prd_terraform) and ~80 secrets were accessible and intact
  before starting.

## Solution

Invite-and-transfer approach (no parallel workspace needed):

1. **Invited <ops@jikigai.com> as Owner** via Doppler dashboard Settings > Access >
   Invite Member. API does not support invites (`POST /v3/workplace/invites`
   returns "Invalid API endpoint").
2. **Updated billing_email and security_email** via API:
   `POST /v3/workplace` with `billing_email` and `security_email` fields. The API
   returns `success: true` with old values -- the change triggers a verification
   email and only takes effect after the recipient clicks the verification link.
3. **User accepted invite** and verified both email changes via the verification
   links sent to <ops@jikigai.com>.
4. **Removed <jean@osmosis.team>** via dashboard Settings > Access > Remove button
   next to the user. API does not support user removal (`DELETE /v3/workplace/users`
   returns "Invalid API endpoint").
5. **Re-authenticated local CLI** with `doppler login --scope /`. The `--scope /`
   flag bypasses the interactive TUI that fails in non-interactive shells (EOF on
   stdin). Scope `/` applies the token globally.
6. **Verified post-migration**: All 6 configs accessible, all ~80 secrets intact,
   all service tokens (GitHub Actions, production server) unchanged and functional.

## Key Insight

Doppler service tokens are scoped to workspace/project/config, NOT to the user
who created them. Changing workspace ownership does not invalidate any existing
tokens. This means account migrations are zero-downtime operations -- no token
rotation, no CI secret updates, no production restarts required.

This is unlike many SaaS platforms where API keys are tied to the creating user's
account and get revoked when that user is removed.

## Session Errors

1. **WebFetch 404s on Doppler docs** -- Tried 5 guessed URL paths
   (`/docs/api/workspaces`, `/docs/api/teams`, etc.) before finding the docs
   index. **Prevention:** Start with the docs index page
   (`https://docs.doppler.com/reference`) and navigate from there. Never guess
   documentation URL paths.

2. **Doppler invite API "Invalid API endpoint"** -- Tried 3 endpoint variations
   (`POST /v3/workplace/invites`, `/v3/workplace/users`, `/v3/invitations`).
   **Prevention:** Not all Doppler operations are API-accessible. Check API
   reference docs first; fall back to Playwright MCP for team management
   operations.

3. **Doppler user removal API "Invalid API endpoint"** -- Similar to above,
   tried `DELETE /v3/workplace/users/{email}`. **Prevention:** Same as above.
   Team management (invites, removals) requires the dashboard UI.

4. **`doppler login` failed with EOF** -- Running `doppler login` via Bash tool
   triggers an interactive TUI that reads stdin, which is unavailable in
   non-interactive shells. **Prevention:** Use `doppler login --scope /` to
   bypass the TUI. The `--scope` flag selects a non-interactive authentication
   flow.

5. **Worktree disappeared between operations** -- The worktree directory was not
   found after context resumed. **Prevention:** Check worktree existence
   (`test -d <path>`) before cd'ing into it. If missing, re-create with
   `worktree-manager.sh create`.

6. **Billing email API response misleading** -- `POST /v3/workplace` returned
   `success: true` with the old email values, suggesting the change did not
   take effect. **Prevention:** Know that Doppler email changes trigger a
   verification email. The API response shows current (pre-verification)
   values. Re-check after the user confirms they clicked the verification link.

## Tags

category: integration-issues
module: doppler
