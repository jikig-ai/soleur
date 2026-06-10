# A step may be classified "operator-only" ONLY with evidence of a real Playwright attempt that reached a true human gate

## Problem

PR #5082 (GSC legal redirects) required widening a Cloudflare API token to add account-level `Account Rulesets:Edit` + `Account Filter Lists:Edit` before the merge-triggered Terraform apply could create the Bulk Redirects resources. The agent classified this as "BLOCKING operator-only, MFA-gated, no Terraform path" and filed it as a `deferred-automation` backlog item (#5092) — **without ever opening a browser.**

The justification was two `api-probe-403`s (`GET /accounts/{id}/tokens` and `GET /user/tokens` both returned 9109) plus an assumption that the dashboard is "MFA-gated." Both are predictions, not observations:

- The 403s came from the **narrowly-scoped rulesets token itself**, which of course lacks token-management permission — they say nothing about whether the dashboard path is automatable.
- "MFA-gated" was never observed. When the operator pushed back and a Playwright attempt was actually made, the flow logged in (the genuine gate was a **one-time SSO login + passkey**, cleared once with operator help), navigated to the token, and **reached the fully-editable token permission form** — added the Account row, selected "Account Rulesets." The dashboard edit itself is mechanically automatable; nothing about it is MFA-gated per-action.

This is the second bypass of the same rule class (`hr-never-label-any-step-as-manual-without`): PR #4227 deferred inline-automatable steps; this PR deferred a *browser-automatable* step by asserting a gate instead of attempting one.

## Solution

**Attempt-evidence is now a hard precondition for any "operator-only" / "manual" / "not automatable" classification of a browser step.** The classification must carry a `playwright-attempt:` line:

```
playwright-attempt: navigated <URL>; reached <specific gate observed>; <why it blocks autonomy>
```

`<specific gate observed>` must be a concrete gate the run actually hit (CAPTCHA/Turnstile, email-OTP, SMS-OTP, authenticator-TOTP, WebAuthn/passkey/Touch-ID, push-MFA, payment-card iframe, hardware-token tap), or `tool-instability: <symptom>`. An a-priori assertion ("MFA-gated", "dashboard-only", "no API path") or an `api-probe-403` from a narrow token never qualifies — and the credential space must be exhausted first (a Global API Key or a write-scoped token may exist in Doppler).

Two distinct dispositions once evidence exists:

- **`operator-only`** — a true human gate (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card/hardware-token). Drive Playwright up to that single interaction, hand off only that, resume. File `deferred-automation` (with the evidence line).
- **`attempted-blocked-on-tool`** — the gate is automatable but the tool failed (browser-context crashes, MCP down, headless-absent MCP). NOT operator-only. File a `tooling`/`flaky` issue (NOT `deferred-automation`) with the exact resume recipe (URL, remaining clicks, partial form state), and retry in a stable session.

Enforced in: `work` Phase 4 Playwright-First Audit + Post-Merge Self-Audit table; `ship` Phase 5.5 Undeferred Operator-Step Gate option 1.

## Key Insight

"No API path" justifies a browser attempt; it never justifies skipping straight to operator handoff. The only evidence that a browser step is operator-only is a browser attempt that hit a named human gate. Until you've watched the gate appear, "operator-only" is a guess — and the guess is usually wrong (the real gate is almost always a one-time login, not a per-action MFA challenge).

## Session Errors

1. **Classified the CF token widen "operator-only / MFA-gated" with zero browser attempts** — Recovery: operator pushback → ran the Playwright attempt → reached the editable token form. **Prevention:** the `playwright-attempt:` evidence gate added by this PR.
2. **Cited `api-probe-403` from the narrow rulesets token as proof "no API path exists"** — Recovery: re-checked Doppler for a Global API Key / write-scoped token (none existed, so the API path genuinely was unavailable — but that had to be *verified*, not assumed). **Prevention:** the gate's explicit "exhaust the credential space; api-probe-403 from a narrow token never qualifies" clause.
3. **Playwright MCP browser crashed every ~2-3 actions; the SPA edit-form state did not survive a reconnect** — Recovery: switched from `browser_evaluate`+deep-snapshots (crash-prone) to native `browser_click`/`browser_type` with minimal snapshots, which reached the form; full completion still blocked by the crash cadence. **Prevention:** documented as the `attempted-blocked-on-tool` disposition (distinct from operator-only); native clicks + minimal snapshots are the lower-crash path for SPA dashboards in this environment.

## Tags

category: workflow-patterns
module: skills/work, skills/ship
