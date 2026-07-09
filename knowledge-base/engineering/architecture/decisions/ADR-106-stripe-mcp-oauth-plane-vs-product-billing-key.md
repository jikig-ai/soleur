---
adr: 106
title: Stripe MCP OAuth plane vs product billing key for /soleur:invoice
status: adopting
date: 2026-07-09
amends: none
supersedes: none
issue: 6260
related: [6259, 6264, 6268]
related_adrs: [ADR-083]
brand_survival_threshold: single-user incident
---

# ADR-106: Stripe MCP OAuth plane vs product billing key for `/soleur:invoice`

## Context

The new `/soleur:invoice` skill (`plugins/soleur/skills/invoice/SKILL.md`, #6260) is a get-paid
workflow: it lets the founder see who owes them, create + send an invoice behind a human-approval
gate, and chase overdue ones. Stripe appears in this codebase on **two disjoint credential planes**,
and the sharpest failure mode of this feature is acting on the wrong one:

1. **Product-runtime plane** — `apps/web-platform/lib/stripe.ts` + the billing webhook route use
   `STRIPE_SECRET_KEY`, which is **Soleur's own** account (the platform's subscription billing:
   `billing/page.tsx`, roadmap 3.14 #1079 / 4.10 #1444, both Done). This charges Soleur's customers
   for Soleur.
2. **Per-user OAuth plane** — the already-registered hosted Stripe MCP (`mcp.stripe.com`,
   `plugin.json`) is authenticated per-session via browser OAuth against **whichever Stripe account
   the founder connects** (their own). This is the founder invoicing *their* customers.

Acting on the wrong plane is a `single-user incident`: a founder either fails to get paid, or a
malformed money-demand is dispatched from the wrong account (test-vs-live, Soleur's-vs-founder's).

Phase-0 runtime grounding (`knowledge-base/project/specs/feat-invoice-skill/phase0-stripe-mcp-findings.md`)
established that the hosted MCP exposes **generic** tools (`stripe_api_read`/`stripe_api_write` + an
op-id, `get_stripe_account_info`), not named ones, and that the write tool has **no HTTP header slot**
— so Stripe's `Idempotency-Key` header cannot be passed, and the skill uses metadata reconciliation
for anti-duplicate instead.

## Decision

The invoice skill acts **exclusively** on the per-user Stripe MCP OAuth plane (`mcp.stripe.com`). It
**never** reads or uses the product-runtime `STRIPE_SECRET_KEY`, and never reads `.env` or
`lib/stripe.ts`.

**The boundary is capability-scoped, not prose.** The SKILL.md `allowed-tools` frontmatter contains
**only** Stripe MCP tools — `get_stripe_account_info`, `stripe_api_read`, `stripe_api_write`,
`stripe_api_search`, `stripe_api_details` — and **explicitly excludes** `Bash`, secret-file `Read`,
and any Doppler tool. The skill therefore **physically cannot** read `STRIPE_SECRET_KEY`/`.env`/
`lib/stripe.ts`, regardless of any prose instruction. A grep over a prohibition sentence is not the
guard; the tool scope is.

**Livemode is blocked in v1 (temporal access boundary).** The account-mode gate (S2) hard-STOPs when
`livemode == true` and points to #6264 — there is **no** live proceed-path in v1. Live invoicing is
gated on the CG5 legal lockstep (three-doc → up-to-6-location GDPR lockstep + full legal-doc audit)
tracked in #6264. v1 ships usable in **test mode only**. This temporal boundary lives here alongside
the credential boundary deliberately: an engineer reading only ADR-106 must learn both "MCP OAuth
plane, never the product key" **and** "test-mode until #6264."

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **(chosen) Per-user Stripe MCP OAuth plane** | Adopted | The OAuth account IS the token-agnostic mechanism; acts on the founder's own account; bundleable; the correct tenant. |
| **(a) Direct Stripe REST with `STRIPE_SECRET_KEY`** | Rejected | Couples to Soleur's own account (wrong tenant), not bundleable, and dispatches money-demands from the platform's billing credential. |
| **(b) Generic/both by token-plane rather than OAuth-account** | Rejected | The OAuth account is already the token-agnostic mechanism; a second credential plane doubles the failure modes this ADR exists to prevent. |
| **(c) Stripe Connect (connected accounts / restricted keys)** | Deferred to #6264 | The canonical multi-tenant "act on a third party's Stripe" pattern and the likely path for autonomous/cron sends (interactive browser OAuth cannot run headless) — but requires per-founder onboarding, out of the v1 interactive test-mode slice. |

## Consequences

- The skill's credential surface is enforced by construction (the `allowed-tools` scope), not by a
  prose prohibition — a future edit that adds `Bash`/`Read`/Doppler to `allowed-tools` is the only way
  to breach it, and that is a reviewable frontmatter diff.
- **v1 is test-mode-only.** The first livemode send remains gated on the CG5 legal lockstep (#6264);
  no operator action is required to merge v1 (the test-mode build is self-contained). The AC3a livemode
  hard-stop is the by-construction enforcement.
- The anti-duplicate mechanism is metadata reconciliation (`metadata[soleur_invoice_key]` +
  list-and-check), because the generic MCP write tool cannot carry an `Idempotency-Key` header.
- `status: adopting` flips to `accepted` once the skill has been dogfooded end-to-end in a test-mode
  account (create → finalize → hosted link) and #6264's livemode lockstep is scoped.

## Diagram

**One C4 delta.** The Agent Runtime now transacts with Stripe using the operator's own credentials:
a `claude -> stripe` relationship is added to `model.c4` ("invoice skill: create/finalize/send/chase
via hosted Stripe MCP — OAuth, operator's OWN account; distinct credential plane from the
`webapp -> stripe` billing edge; ADR-106"). No new actor (the invoice recipient is reached by Stripe's
hosted invoice, never by Soleur directly), no new system (`stripe` already modeled), no new
container/data-store (no v1 founder ledger — that is #6264). The edge aggregates to `engine -> stripe`
in the context view, which already includes both elements, so no `views.c4` change is needed.
