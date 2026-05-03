---
date: 2026-05-03
problem_type: integration_pattern
component: vendor_signup_automation
symptoms:
  - "MCP/API tiers cannot do cold vendor signup because they assume an authenticated session"
  - "Playwright cold-signup blocked on roadmap pending CLO agency-liability legal framework"
root_cause: missing_tier_in_priority_chain
resolution_type: pattern_recognition
severity: medium
tags: [vendor-signup, ops-provisioner, service-automator, stripe-projects, cloudflare, automation-priority]
---

# Learning: Stripe Projects as a New Tier Above MCP in the Vendor-Signup Priority Chain

## Problem

The `hr-exhaust-all-automated-options` priority chain (MCP > CLI > API > Playwright > manual) has a structural gap: **every tier above Playwright assumes the user already has an account on the vendor**. MCPs authenticate via OAuth on an existing account. CLIs and REST APIs require an API token issued by an existing account. Playwright is the only path that creates a new account from scratch — and it is the most fragile, slowest, and now legally fenced (CLO deferred Playwright vendor signup pending an agency-liability framework, per `roadmap.md` Phase 5 note).

This left Soleur unable to programmatically subscribe a user to a vendor they had never signed up for, even when the vendor exposed every other API after the fact.

## Solution

Cloudflare and Stripe announced **Stripe Projects** on 2026-04-30 (https://blog.cloudflare.com/agents-stripe-projects/): a Stripe CLI plugin + REST surface where the user authenticates to Stripe once via OAuth/OIDC, the agent runs `stripe projects add <vendor>/<resource>`, Stripe attests the user's identity to the vendor, the vendor auto-provisions an account if one does not exist for the user's Stripe-attested email, Stripe issues a payment token (raw card never touches the agent), and the vendor returns scoped credentials.

This is **a new automation tier**, not just another MCP. It sits **above MCP** in the priority chain because it covers the cold-signup case MCPs structurally cannot. Generalize the pattern beyond Stripe Projects: any "third-party identity-attestation protocol that triggers vendor auto-provisioning + payment tokenization" forms this same tier.

Updated priority chain: **identity-attested provisioning > MCP > CLI > API > Playwright > manual.**

## Key Insight

**Cold signup and warm management are different automation problems.** The historical priority chain conflated them — MCPs were treated as the top tier for both. They are only the top tier for warm management. For cold signup, the chain starts one tier higher with identity-attestation protocols (Stripe Projects today; potentially others as the agent-native commerce category matures).

When evaluating a new vendor-signup capability, the routing question is no longer "does this vendor have an MCP?" but **"does this vendor participate in an identity-attestation protocol?"** — and only on a "no" do you fall back to MCP-or-Playwright reasoning.

This insight only became visible because (a) the CTO assessment surfaced "Stripe attests identity, not raw-card handoff" as the load-bearing distinction, and (b) the CLO assessment confirmed it's *materially* safer than Playwright but does not unblock the broader agency-framework — meaning the new tier solves the credential/payment problem cleanly while leaving the *intent* problem (did the user authorize THIS specific plan choice?) for per-action consent UX to handle.

## When to Apply

- Any future brainstorm or plan that mentions "agent provisions <vendor> for user," "subscribe user to <SaaS>," or "create new account on user's behalf."
- Reviewing prior automation choices for vendors that now appear in the Stripe Projects catalog (Cloudflare today; Vercel/Supabase/Resend likely candidates per COO assessment).
- Designing the `ops-provisioner` and `service-automator` agents' tier-selection logic.

## Counter-Indications

- **Stripe attests payment, not intent.** Even with Stripe Projects, the agent picking the *wrong* plan still leaves the user on the hook. Per-action consent UX (modal showing provider/plan/amount before invocation) remains required for the `single-user incident` user-brand threshold.
- **Beta-protocol churn risk.** Stripe Projects is open beta; pin CLI versions, version REST adapters, run nightly contract tests against the OpenAPI spec.
- **Vendor coverage is sparse.** Cloudflare is the launch partner. Most vendors (GitHub, Hetzner, smaller SaaS) are unlikely to participate within 6 months — so Playwright remains required, just no longer the first choice for catalog vendors.

## See Also

- `knowledge-base/project/learnings/2026-03-25-check-mcp-api-before-playwright.md` — the prior framing of the priority chain that this learning extends.
- `knowledge-base/project/learnings/2026-04-07-buttondown-onboarding-multi-account-playwright.md` — the multi-account Playwright pain that motivates a credential-tokenized alternative.
- `knowledge-base/project/brainstorms/2026-05-03-agent-native-cloudflare-signup-brainstorm.md` — the brainstorm where this insight surfaced.
- `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spec.md` — consumer-side spec.
- GH #3106 (consumer side, active), #3107 (provider side, deferred), #1287 (parent thematic: agent-native discovery & procurement).

## Tags

category: integration-issues
module: ops-provisioner
