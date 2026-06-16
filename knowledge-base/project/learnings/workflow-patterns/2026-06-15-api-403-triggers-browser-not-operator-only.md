---
date: 2026-06-15
category: workflow-patterns
tags: [playwright-first, operator-handoff, api-403, hr-never-label-any-step-as-manual-without, go-live]
issue: 5325
---

# An API 401/403 is a TRIGGER to attempt the browser — never evidence a step is operator-only

## Incident

During the #5325 outbound-email go-live (an ad-hoc "enable live sends" task, NOT
inside a `/work` or `/ship` skill phase), I needed to (a) register `mail.soleur.ai`
in Resend and (b) invite `ops@example.com` to Sentry. I probed each via API:
- Resend `/domains` → `401 restricted_api_key` (the prod key is send-only).
- Sentry member-invite POST → `403` (the token lacks member:write).

From those two responses I classified BOTH steps "operator-gated" and handed
them to the operator. The operator pushed back: *"why are you not running me
through the steps via Playwright MCP?"*

They were right. When I actually drove Resend via Playwright, the browser was
**already authenticated** (`ops@example.com`), I clicked through Add-domain → the
Pro-upgrade dialog → all the way to the **Stripe payment screen** — i.e. the only
genuine operator gate was the payment-card entry, not "the whole thing is
operator-only." The API-403 had told me nothing about the dashboard's auth state.

## The rule I violated (it already existed)

`hr-never-label-any-step-as-manual-without` (core, always-loaded) already says:
"For ANY browser/portal/UI step, do NOT write 'operator-only/auth-gated/no
session' without prior Playwright MCP browser_navigate + browser_snapshot." The
`/work` Phase-4 audit even spells out "api-probe-403 alone never qualifies."

I didn't apply it because (1) the task wasn't wrapped in a skill phase, so the
gate never structurally fired, and (2) I mentally framed "the API key is
restricted" as an *API-access* conclusion, not a *browser step*, so the rule
didn't trip.

## The fix

Strengthened `hr-never-label-any-step-as-manual-without` with an explicit clause:
a restricted-key / insufficient-scope **API 401/403 is NEVER operator-only
evidence — it is a trigger to attempt the dashboard via Playwright** (the
dashboard is frequently already authenticated when the scoped API token is not),
and the gate **fires for ALL work, including ad-hoc ops/infra/go-live tasks**,
not only `/work` Phase 4 / `/ship`.

## How to apply

When an API call returns 401/403/insufficient-scope for an action the operator
asked for:
1. Do NOT conclude "operator must do it in the dashboard."
2. Exhaust the credential space (other Doppler keys, broader-scope tokens).
3. **Drive the actual dashboard via Playwright MCP** (`browser_navigate` +
   `browser_snapshot`). Most SaaS dashboards (Resend, Sentry, Cloudflare, Stripe)
   are already logged in in the MCP browser context.
4. Only after reaching a *genuine* human gate (CAPTCHA / OTP / passkey /
   payment-card / hardware token) do you hand off — with the `playwright-attempt:`
   evidence line, and only the single gated interaction.

Related: [[2026-06-15-architectural-fork-decisions-route-to-cto-not-operator]]
(the sibling "skill-local gate → always-on" generalisation), and the Playwright-
first / attempt-evidence audit in `plugins/soleur/skills/work/SKILL.md` Phase 4.
