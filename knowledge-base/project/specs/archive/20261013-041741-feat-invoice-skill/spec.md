---
feature: invoice-skill
branch: feat-invoice-skill
pr: 6259
issue: 6260
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-07-09-invoice-skill-brainstorm.md
---

# Spec: `/soleur:invoice` skill (v1 — read + guarded send)

## Problem Statement

The Soleur library covers engineering and marketing end-to-end but the Finance, Sales,
and Support domains have advisory agents and **zero executable skills**. A founder can get
revenue *advice* but has no verb to actually **get paid**. `/soleur:invoice` is the finance
domain's first executable skill: send an invoice, chase an overdue one, and see who owes you —
driven by the already-wired Stripe MCP, with no net-new product code.

## Goals

- G1. A founder (or operator) can create, preview, finalize, and send a Stripe invoice from the CLI.
- G2. A founder can see open/overdue invoices and resend/remind on them.
- G3. The skill is safe by construction for a non-technical user who trusts it: no wrong-account,
  no auto-send, no fabricated tax/numbering.
- G4. Token-agnostic — works against whichever Stripe account completed the MCP OAuth.

## Non-Goals

- NG1. Ledger record/reconcile (deferred v2 — no founder-side ledger exists yet).
- NG2. Any auto-send or unattended dunning cadence.
- NG3. Tax computation, currency FX, PDF rendering, credit notes/refunds.
- NG4. A new finance-write agent (evaluate at plan time).
- NG5. Reuse of `apps/web-platform/lib/stripe.ts` (product-runtime Node, not skill-callable).

## Functional Requirements

- **FR1 — Auth precondition.** Ensure the Stripe MCP (`mcp.stripe.com`) is authenticated;
  if not, run `__authenticate` / `__complete_authentication` and surface an error table
  (`MCP tool not found` → re-auth; `Token expired` → re-auth), copying the `linear-fetch/SKILL.md` idiom.
- **FR2 — Account safety gate.** Resolve and echo the connected Stripe **account id + livemode**
  (test vs live). Require a typed confirmation before ANY write operation. Never read or use the
  product `STRIPE_SECRET_KEY`.
- **FR3 — Read: who owes you.** `list_customers` and list open/overdue invoices; present a
  scannable "who owes you" view.
- **FR4 — Guarded create + send.** Create a draft invoice from operator-supplied line items →
  render a **human-approval preview** → on typed-yes, `finalize` (Stripe mints the sequential
  number) → send the hosted-invoice link. No un-gated send path exists.
- **FR5 — Chase.** Resend/remind on an existing overdue invoice using Stripe-native dunning.
  No custom scheduler.
- **FR6 — Refuse to fabricate.** On tax/VAT rate, currency, or legal-entity fields the skill
  must STOP and require an operator-supplied fact (or delegate to Stripe Tax if wired) — never guess.

## Technical Requirements

- **TR1.** Skill is a markdown workflow under `plugins/soleur/skills/invoice/SKILL.md`; it
  orchestrates `mcp__plugin_soleur_stripe__*` tools via `allowed-tools:` frontmatter. No imported code.
- **TR2.** Enumerate the exact post-OAuth Stripe MCP tool names at implementation time (run
  `__authenticate` then list tools) before finalizing the workflow steps.
- **TR3.** No plaintext customer PII (name/address/amount) written to logs or committed artifacts;
  hash where an identifier must be recorded (mirror the existing `recipient_hash` HMAC pattern).
- **TR4.** Register the skill per `plugins/soleur/AGENTS.md` (help/eval-harness registry,
  plugin.json description + README counts via `release-docs`).
- **TR5.** Author an ADR: "Stripe MCP OAuth plane vs product billing key for `/soleur:invoice`"
  (`/soleur:architecture create ...`).

## Compliance Gate (from CLO — PROCEED-WITH-GUARDRAILS)

- **CG1.** Human-approval preview before every send/dunning (FR4/FR5) — load-bearing, must ship.
- **CG2.** Stripe-owned sequential numbering (FR4) — never agent-minted.
- **CG3.** Refuse-to-fabricate (FR6).
- **CG4.** No plaintext PII in logs (TR3).
- **CG5.** Three-doc GDPR lockstep (Privacy Policy + Data Protection Disclosure + Art. 30 register)
  before first **livemode** send. Building + test-mode use is NOT gated on this. Delegate the
  lockstep verification to `legal-compliance-auditor` at implementation.

## Open Questions (carry to plan)

- OQ1. Standalone skill vs a new finance-write agent owner?
- OQ2. Founder-side ledger location (blocks v2 reconcile).
- OQ3. Should the legal threshold catalog gain an "invoice issuance" row?

## Acceptance Criteria

- AC1. `/soleur:invoice` lists customers and overdue invoices against the OAuth'd test account.
- AC2. Creating + sending an invoice requires an explicit typed confirm after an accurate preview;
  aborting the confirm sends nothing.
- AC3. The skill refuses to proceed when a tax rate or currency is unspecified rather than guessing.
- AC4. The account id + livemode are echoed and confirmed before any write.
- AC5. No plaintext customer PII appears in any log line or committed file.
