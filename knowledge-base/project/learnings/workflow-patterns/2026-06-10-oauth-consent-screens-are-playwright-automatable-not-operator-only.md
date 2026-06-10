---
title: OAuth/app-install consent screens are Playwright-automatable, not operator-only
category: workflow-patterns
tags: [playwright-mcp, operator-steps, provisioning, slack, automation-claims]
pr: 5078
issue: 5079
date: 2026-06-10
---

# OAuth/app-install consent screens are Playwright-automatable, not operator-only

## Problem

The feat-slack-release-notify plan declared the Slack Incoming Webhook creation an
operator-only step: `Automation: not feasible because Slack Incoming Webhook creation
requires interactive OAuth app-install consent in the operator's Slack workspace.`
At execution time the agent inherited the claim verbatim, ended its turn with a
click-path checklist, and waited for the operator — violating the spirit of
`hr-exhaust-all-automated-options-before` (Playwright MCP is priority 5) and the
"never defer operator actions" feedback. The operator had to intervene to point out
the rule violation.

The root confusion: `hr-never-label-any-step-as-manual-without` listed "SSO consent"
as operator-only, and OAuth app-install consent pattern-matched to it. But the two
differ in what the human actually contributes:

- **Credential ENTRY** (typing a password, a 2FA code, a card number, solving a
  CAPTCHA) — genuinely human; the agent cannot and must not do it.
- **CONSENT clicks inside an already-authenticated session** (Slack "Allow", GitHub
  App install button, vendor dashboard toggle) — just DOM interactions; Playwright
  MCP performs them. Authorization comes from the session, not the click's muscle.

## What the autonomous run actually covered (PR #5078, 2026-06-10)

With one live Slack web session, Playwright MCP completed end-to-end with zero
operator clicks: app create ("Sol", From scratch, workspace picker) → icon upload via
`input[type=file] setInputFiles` → Incoming Webhooks toggle → **#releases channel
creation in the Slack web client** (right-click the sidebar "Channels" heading →
"Create a channel" wizard) → OAuth consent channel-picker + Allow → webhook URL
extraction → `gh secret set` → live webhook smoke test (`ok`).

## Techniques worth reusing

- **Secret never enters the conversation:** `browser_evaluate` has a `filename` param —
  extract the webhook URL straight to a file (saved at the Playwright MCP output dir,
  here repo root), shape-validate with `grep -qE`, pipe to `gh secret set` via stdin,
  `shred -u` both files. Shred AFTER the consumer succeeds (the first attempt shredded
  before a transient `gh` 401 resolved, forcing a re-extract).
- **Styled toggles:** Slack's checkbox is `.offscreen`; force-clicking the input does
  nothing — click the visible `.ts_toggle_button` (find via `data-qa` wrapper).
- **Suggestion popovers intercept pointer events** over the input they decorate
  (channel-name wizard): JS-`focus()` + `page.keyboard.type` + JS-dispatched click on
  the Next/Create button. Do NOT press Escape to close the popover — it closes the
  whole modal.
- **Mid-flow browser crashes** (`Target page ... has been closed`): `browser_close`
  then re-navigate; the session cookie survives the context recycle. Verify whether
  the interrupted mutation landed before redoing it (the crashed Allow had NOT landed:
  "No webhooks have been added yet").
- **Missing channel:** the OAuth channel picker only lists existing channels
  ("No channels found") — create the channel in the web client first.

## Rule changes

`hr-never-label-any-step-as-manual-without` (AGENTS.core.md) amended: operator-only is
now strictly credential ENTRY; consent screens in authenticated sessions route through
Playwright MCP; and a plan's "Automation: not feasible" claim MUST be re-verified by
attempting the browser path at execution time rather than inherited.
