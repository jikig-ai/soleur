---
name: operator-only-step-canonical-list
description: Canonical list of genuinely-manual operator steps that Soleur should not try to automate (SSO, OAuth consent, fresh credential mint, payment-method entry)
metadata:
  type: feedback
  date: 2026-05-15
  rule_touched: hr-never-label-any-step-as-manual-without
  triggering_issue: "#3849"
---

# Operator-only step canonical list

## Problem

Soleur kept proposing to automate steps that are intrinsically gated on
operator action. The pattern recurred enough across sessions that the operator
asked for it to be codified in AGENTS.md rather than re-litigated each time.

Concrete trigger: `/soleur:go 3849` for issue #3849 (Sentry IaC AC13-AC16
blocked on `SENTRY_AUTH_TOKEN` rotation). The issue body labels the token
mint as a "single operator action." On entry, Soleur tried to find a way
around this:

- **Sentry REST API path** — `POST /api/0/sentry-apps/<slug>/api-tokens/`
  requires a token with `org:admin` scope. The token under rotation IS the
  highest-scoped token Soleur has. Chicken-and-egg.
- **Playwright vs `de.sentry.io`** — Jikigai uses SSO. Soleur has no
  credential store for human SSO logins, and would not be a safe place
  to put one if it did.
- **Doppler / 1Password / local env** — empty for this auth boundary.

After the operator clarified the policy, Soleur stopped trying to eliminate
the mint step and instead codified the exemption.

## Solution

Single-line update to `AGENTS.core.md` rule body for
`hr-never-label-any-step-as-manual-without` to make the operator-only list
canonical:

> (a) CAPTCHAs, (b) SSO / OAuth consent flows, (c) fresh credential mint
> when no admin-scope bootstrap exists in Doppler (e.g., rotating a token
> whose own scope can't mint its successor — paste the new token into the
> chat and Soleur drives the rest), (d) payment-method / billing entry.
> Everything downstream of the operator handing over the credential is
> Soleur's responsibility.

The previous body listed only "CAPTCHAs and OAuth consent" which was
under-specified — OAuth ≠ SSO (broader; includes SAML), and rotation cases
were ambiguous.

## Key Insight

The policy is **not** "exhaust all automation attempts before deferring."
That framing (`hr-exhaust-all-automated-options-before`) is necessary but
insufficient — it produced false-positive automation attempts against
hard auth walls. The complementary positive rule needed is "here is the
small closed set of steps that ARE operator-only, regardless of tooling."

The boundary is **possession of credentials**, not **availability of
tooling**. Playwright MCP exists and works — it does not help here because
the missing input is a Sentry SSO password, not a way to drive a browser.

## How to apply

- When Soleur encounters a step that requires authenticating to a
  third-party SaaS that uses SSO/OAuth: ask the operator to mint the
  credential and paste it into chat. Then drive the rest.
- When Soleur encounters payment-method / billing entry: ask the
  operator. Do not propose Playwright + stored credit card numbers.
- When Soleur encounters token rotation: check Doppler for any
  higher-scoped bootstrap token first. If none exists with admin scope,
  this is case (c) — operator mints, Soleur drives.
- Do not propose `/soleur:one-shot` for issues whose body explicitly
  identifies the blocker as one of the (a)-(d) categories AND whose
  closing condition is operator workflow execution rather than a PR
  merge. Use `/soleur:brainstorm` or direct execution instead.

## Session Errors

1. **Misclassified #3849 as one-shot candidate** — Recovery: stopped at
   Step 0b, escalated to operator via AskUserQuestion. Prevention:
   tightened rule body now lists case (c) explicitly so the routing
   classifier can reject one-shot for "operator-only-closing-condition"
   issues. (No skill-level enforcement added — judgment call routing
   stays in `/soleur:go`.)
2. **AskUserQuestion options treated SSO as Playwright-automatable** —
   Recovery: operator corrected policy. Prevention: same rule edit.

## Related

- [[hr-exhaust-all-automated-options-before]] — necessary; sets the
  bar for attempting automation
- [[hr-never-label-any-step-as-manual-without]] — sufficient; this
  edit closes the loop by enumerating the exempt set
- [[hr-when-a-workflow-concludes-with-an]] — adjacent; mentioned
  "credentials/payment at the exact page" but vague
- Issue #3849 — original trigger; remains open pending operator
  token rotation
