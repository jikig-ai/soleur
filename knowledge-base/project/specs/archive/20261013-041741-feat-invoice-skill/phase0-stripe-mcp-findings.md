---
feature: invoice-skill
phase: 0 (runtime grounding)
date: 2026-07-09
stripe_account: acct_1TBdK3CuJjszePq3 (Jikig AI sandbox — TEST mode)
mcp: mcp.stripe.com (OAuth, connected this session)
---

# Phase 0 findings — Stripe hosted MCP grounding

Completed live against the connected sandbox account. These bind the SKILL.md's `allowed-tools`
and step calls (the plan authored the workflow abstractly precisely so this could fill it in).

## Tool surface (generic, NOT named — Research Reconciliation confirmed)

The hosted MCP does **not** expose `create_invoice`/`list_customers`. It exposes generic tools:

| MCP tool | Use |
|---|---|
| `mcp__plugin_soleur_stripe__get_stripe_account_info` | account id + display_name (NO livemode — see below) |
| `mcp__plugin_soleur_stripe__stripe_api_read` | any GET (op-id + params) |
| `mcp__plugin_soleur_stripe__stripe_api_write` | any POST/PATCH/PUT/DELETE (op-id + flat params); **has native `human_confirmation`** |
| `mcp__plugin_soleur_stripe__stripe_api_search` / `stripe_api_details` | discover op-ids + inspect params |
| `mcp__plugin_soleur_stripe__fetch_stripe_resources` / `search_stripe_resources` | resource fetch/search |
| `mcp__plugin_soleur_stripe__create_refund` | refunds (out of v1 scope) |

## Capability → operation binding table (the 6+ verbs S4/S5 need)

| Verb | MCP tool | Stripe op-id | Notes |
|---|---|---|---|
| account-info | `get_stripe_account_info` | — | returns account_id, display_name |
| list customers | `stripe_api_read` | `GetCustomers` | S3 |
| list invoices (overdue) | `stripe_api_read` | `GetInvoices` | filter `status=open` |
| retrieve invoice | `stripe_api_read` | `GetInvoicesInvoice` | S4 draft re-read / recovery |
| create draft | `stripe_api_write` | `PostInvoices` | body has `customer`, `auto_advance`, `automatic_tax.enabled`, `collection_method` (send_invoice), `days_until_due`, `default_tax_rates`, `currency`, **`metadata`** |
| add line item | `stripe_api_write` | `PostInvoiceitems` | pre-finalize |
| finalize | `stripe_api_write` | `PostInvoicesInvoiceFinalize` | mints `number` (CG2 ✓) |
| send | `stripe_api_write` | `PostInvoicesInvoiceSend` | best-effort in test mode |
| void | `stripe_api_write` | `PostInvoicesInvoiceVoid` | recovery |

(Confirm exact op-ids via `stripe_api_search` at author time — `PostInvoices` verified via `stripe_api_details`.)

## Idempotency-support probe (fable advisor's load-bearing bet) → **NO**

`stripe_api_write.parameters` accepts **path/query/body only — no HTTP header slot**. Stripe's
`Idempotency-Key` is a *header*, so it **cannot** be passed through the generic MCP write tool.
→ **S4 uses the metadata-reconciliation fallback as the PRIMARY anti-duplicate path**, not a fallback:
stamp a client marker in the invoice `metadata` on create (the `metadata` field is confirmed present on
`PostInvoices`), and list-and-check that marker before every create/finalize. AC5a's "idempotency key OR
metadata marker" resolves to the metadata branch.

## Livemode determination (new finding)

`get_stripe_account_info` returns **no `livemode` field**. The account here is a **Stripe sandbox**
(inherently test-only). For the generic S2 gate, determine mode by reading the `livemode` boolean off
any object a read returns (every Stripe object carries it), OR treat a sandbox account as test.
The SKILL.md's S2 must not rely on `get_stripe_account_info` alone for the livemode hard-stop.

## Native human-confirmation (defense-in-depth)

`stripe_api_write` may itself require human confirmation: first call returns an approval-request id + URL;
the human approves at the URL; re-call with `approval_token`. This is a Stripe-side technical gate that
LAYERS UNDER our founder-legible S2/S4 preview + typed-`yes` (which stays load-bearing — the Stripe URL is
not founder-legible). Note both in the SKILL.md so the two gates don't confuse the operator.

## Phase 0 status
- [x] Tools enumerated · [x] binding table · [x] idempotency probe (NO → metadata) · [x] account+mode confirmed (sandbox/test) · [x] budget re-check (components.test.ts 1249/0 pass, headroom intact)
- Next: Phase 1 — author `plugins/soleur/skills/invoice/SKILL.md` from this table.
