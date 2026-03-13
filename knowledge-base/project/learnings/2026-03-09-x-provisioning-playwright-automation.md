# Learning: X/Twitter Account Provisioning via Playwright MCP

## Problem

Setup scripts (`x-setup.sh`, `discord-setup.sh`) used relative `.env` paths, breaking when invoked from worktrees or subdirectories. Additionally, provisioning a new X account and Developer Portal app required extensive manual browser interaction.

## Solution

**Path fix:** Replaced hardcoded `.env` with `git rev-parse --show-toplevel` to resolve the repo root dynamically in both `cmd_write_env` and `cmd_verify` for both scripts.

**Provisioning:** Used Playwright MCP browser automation to:
1. Navigate X signup flow, filling non-sensitive fields (name, birthday, username)
2. Pause for manual entry on sensitive steps (verification codes, passwords)
3. Complete profile setup (logo upload, bio, location, website) via /settings/profile
4. Register Developer Portal app with instant pay-per-use approval
5. Configure OAuth 1.0a with Read+Write permissions
6. Generate and pair Consumer Key + Access Token credentials

**Credential pairing gotcha:** Regenerating Consumer Key invalidates existing Access Tokens. Must regenerate Access Token *after* Consumer Key to get a matching pair.

**Verification:** `x-setup.sh verify` confirmed round-trip API call to `GET /2/users/me` succeeds.

## Key Insight

Playwright MCP works well for semi-automated provisioning — automate the mechanical steps (navigation, form filling, file uploads) while pausing for human input on security-sensitive steps (passwords, verification codes). The ops-provisioner pattern of "never enter credentials into web forms" is a good safety boundary. Always resolve `.env` paths from the repo root in scripts that may be called from worktrees.

## Tags
category: integration-issues
module: community/x-setup
