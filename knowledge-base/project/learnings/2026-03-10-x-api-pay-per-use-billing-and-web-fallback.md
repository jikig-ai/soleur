# Learning: X API pay-per-use billing and web UI fallback

## Problem

During blog post distribution to X/Twitter (#502), the X API returned HTTP 402 (Payment Required) when attempting to post a tweet via `POST /2/tweets`. The account was on X's pay-per-use plan with a $0.00 balance. Even Free tier actions like posting require purchased credits under the consumption-based billing model.

Secondary issues compounded the distribution attempt:

1. **X API credentials missing from `.env`** -- required regenerating Consumer Key and Access Token via the X Developer Console (Playwright MCP automation).
2. **`x-setup.sh write-env` requires credentials already exported** -- the script reads from environment variables, not interactively. Cannot bootstrap credentials from nothing.
3. **`source .env` does not persist across Bash tool calls** -- each Claude Code Bash invocation is a fresh shell. Environment variables set in one call are invisible in the next.
4. **Playwright click timeout on tweet 5 Reply button** -- a link preview overlay intercepted clicks on the Reply button, requiring Escape to dismiss the overlay first.

## Solution

### API billing workaround

When the X API returns 402, fall back to posting via the X web UI using Playwright MCP browser automation. The web UI does not require API credits.

### Credential regeneration

Regenerated credentials via X Developer Console using Playwright MCP. Critical ordering: regenerate Consumer Key first, then Access Token. Reversing this order produces a mismatched pair (the Access Token is signed against the old Consumer Key).

### .env loading in non-interactive shells

Use the `export` + `grep` + `xargs` pattern to load `.env` into the current shell:

```bash
export $(grep -v '^#' .env | grep -v '^$' | xargs)
```

This works in Claude Code's non-interactive Bash tool where `source .env` variables do not persist between calls.

### X web UI thread posting via Playwright

Posted a 5-tweet thread as connected replies:

1. Navigate to `https://x.com/compose/post`
2. Fill tweet text and click Post
3. Navigate to the posted tweet's URL
4. Click Reply, fill next tweet, post
5. Repeat for each tweet in thread

When link preview overlays block the Reply button, press Escape before clicking Reply.

## Key Insight

X's pay-per-use billing means the API can authenticate successfully but refuse to perform actions (HTTP 402) when the account has zero credits. This is different from a rate limit (429) or auth failure (401/403). The web UI remains functional regardless of API credit balance, making Playwright MCP browser automation a viable fallback for posting when the API is financially gated. Any social distribution pipeline should detect 402 specifically and offer the web UI path rather than failing outright.

## Session Errors

1. X API credentials not in `.env` -- required regeneration via Developer Console
2. `x-setup.sh write-env` failed -- script requires credentials already exported, cannot interactively set them
3. `source .env` does not persist across Bash tool calls -- each invocation is a fresh shell, needed `export $(grep ...)` pattern
4. X API HTTP 402: no credits -- pay-per-use account had $0.00, required web UI fallback
5. Playwright click timeout on tweet 5 Reply button -- link preview overlay intercepted clicks, required Escape to dismiss

## Related

- `2026-03-09-x-provisioning-playwright-automation.md` -- credential pairing order (Consumer Key before Access Token)
- `2026-03-09-external-api-scope-calibration.md` -- X API Free tier limitations and scope assumptions
- `2026-03-10-x-api-oauth-get-query-params-in-signature.md` -- OAuth signature requirements for GET requests
- `2026-02-19-discord-bot-identity-and-webhook-behavior.md` -- Discord webhook posting (succeeded in same session)

## Tags

category: integration-issues
module: community
