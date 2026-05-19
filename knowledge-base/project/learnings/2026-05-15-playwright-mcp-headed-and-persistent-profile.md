---
name: playwright-mcp-headed-and-persistent-profile
description: The Soleur Playwright MCP server runs headed (visible browser window on the operator's display) with a persistent --user-data-dir profile, so a one-time interactive SSO login unlocks full Soleur-driven UI automation for subsequent sessions
metadata:
  type: reference
  date: 2026-05-15
  triggering_issue: "#3849"
---

# Playwright MCP runs headed with a persistent profile

## What the operator's `.mcp.json` actually configures

```json
{
  "command": "npx",
  "args": [
    "@playwright/mcp@latest",
    "--user-data-dir=/home/jean/.cache/playwright-mcp-profile"
  ]
}
```

Two consequences that are easy to miss:

1. **No `--headless` flag, no `--isolated` flag.** Default behaviour for
   `@playwright/mcp` is headed mode. Chrome launches with
   `--ozone-platform=wayland` and is visible on the operator's display
   (workspace permitting). The operator CAN see and interact with the
   browser.

2. **`--user-data-dir` is persistent.** Cookies, auth sessions, and
   service-worker storage survive across MCP server restarts. A single
   interactive SSO login durably unlocks future Soleur-driven
   navigation. The profile path under `~/.cache/playwright-mcp-profile`
   is operator-owned; do not delete it casually.

## Why this matters for the operator-only-step rule

The hard rule [[hr-never-label-any-step-as-manual-without]] lists
operator-only steps as CAPTCHAs, SSO/OAuth consent, credential mint
with no admin-scope bootstrap, and payment/billing entry. It is
tempting to read "SSO/OAuth consent" as "Soleur escalates and waits
for a pasted credential."

The headed-Playwright path is a third option that splits the work:

- **Operator** completes the SSO flow ONCE in the visible Playwright
  window (types password, clicks OAuth consent, satisfies any 2FA
  challenge).
- **Soleur** drives every UI step downstream — token mint, settings
  edits, environment-gate approvals, etc. — against the now-
  authenticated session.

For services with no SSO bypass (e.g. password-only login pages and
fresh-credential-mint flows that require an existing session), this
is strictly more automated than the "operator pastes the credential"
escape hatch.

## What I missed on 2026-05-15 / #3849

The 2026-05-15 Sentry token rotation session walked into the wrong
default twice:

1. The first `browser_navigate` call landed on `sentry.io/auth/login/jikigai/`. I treated "Sign In page = SSO wall = blocked" and reported case (c) without inspecting the form. The page actually offered username/password, Google OAuth, GitHub OAuth, and Azure DevOps — none of which were guaranteed-blocked.
2. Even after I learned the browser was headed, I asked the operator to *paste a credential into chat* instead of suggesting they log into the visible Playwright window.

The operator caught both mistakes. The resolution was to navigate
back to the login page, let the operator complete the SSO flow in
the visible window, and then drive Sentry's UI from token-mint
through every downstream settings change inside Soleur.

## How to apply

- Before declaring "this needs operator credentials", inspect the
  login page and enumerate the available auth methods. If any of
  them is a flow the operator can complete in the visible Playwright
  window, prefer that path over credential pasting.
- After a successful interactive login, future Soleur sessions can
  re-use the authenticated session as long as the persistent profile
  is intact. The session may expire on the service side; if
  `browser_navigate` lands on a login page mid-flow, re-prompt the
  operator to log in (don't ask for credentials by paste).
- Do NOT proactively close the Playwright browser with
  `browser_close` between operations — the headed window IS the
  operator's collaboration surface. Close only at end-of-task.

## Related

- [[hr-never-label-any-step-as-manual-without]] — operator-only set;
  this file is the implementation note for the Playwright fallback
- [[operator-only-step-canonical-list]] — the broader session
  summary
- `/home/jean/.cache/playwright-mcp-profile/` — operator-owned
  profile directory (gitignored)
