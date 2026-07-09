---
name: invoice
description: "This skill should be used when the founder wants to get paid through their own Stripe account: list who owes them, create and send an invoice behind a human-approval preview, or chase an overdue one. Test-mode only in v1."
allowed-tools:
  - mcp__plugin_soleur_stripe__get_stripe_account_info
  - mcp__plugin_soleur_stripe__stripe_api_read
  - mcp__plugin_soleur_stripe__stripe_api_write
  - mcp__plugin_soleur_stripe__stripe_api_search
  - mcp__plugin_soleur_stripe__stripe_api_details
preconditions:
  - Stripe MCP server is authenticated (mcp__plugin_soleur_stripe__authenticate has been run for this session)
  - The authenticated account is in TEST mode (v1 hard-refuses livemode — see S2)
---

# Invoice — get paid via your own Stripe

This skill is the Finance domain's get-paid workflow. It drives the **hosted Stripe MCP**
(`mcp.stripe.com`, OAuth) to see who owes the founder money, create + send an invoice behind a
human-approval preview, and chase overdue ones. It acts on the founder's **own** Stripe account —
whichever account completed the OAuth — and **never** touches Soleur's product billing credential
(`STRIPE_SECRET_KEY`). See [ADR-106](../../../../knowledge-base/engineering/architecture/decisions/ADR-106-stripe-mcp-oauth-plane-vs-product-billing-key.md)
for the credential-plane boundary.

**Credential isolation is mechanical, not prose.** The `allowed-tools` frontmatter contains **only**
Stripe MCP tools — no `Bash`, no secret-file `Read`, no Doppler tool — so the skill physically cannot
read `STRIPE_SECRET_KEY`, `.env`, or `lib/stripe.ts`, regardless of any instruction to the contrary.

**v1 scope: TEST mode only.** Livemode invoicing is blocked in v1 (S2 hard-stop) pending the legal
lockstep tracked in [#6264](https://github.com/jikig-ai/soleur/issues/6264). Building and test-mode
use are **not** gated on that.

## Tool surface (generic, runtime-discovered)

The hosted MCP exposes **generic** tools, not named ones (`create_invoice` does not exist). Bind each
verb to a generic call (op-ids confirmed via `stripe_api_details` / `stripe_api_search` at run time):

| Verb | MCP tool | Stripe op-id |
|---|---|---|
| account info | `get_stripe_account_info` | — |
| list customers | `stripe_api_read` | `GetCustomers` |
| list invoices (open/overdue) | `stripe_api_read` | `GetInvoices` (filter `status=open`) |
| retrieve invoice | `stripe_api_read` | `GetInvoicesInvoice` |
| create draft | `stripe_api_write` | `PostInvoices` (body: `customer`, `collection_method=send_invoice`, `days_until_due`, `automatic_tax`, `currency`, `metadata`) |
| add line item | `stripe_api_write` | `PostInvoiceitems` |
| finalize | `stripe_api_write` | `PostInvoicesInvoiceFinalize` |
| send | `stripe_api_write` | `PostInvoicesInvoiceSend` |
| void | `stripe_api_write` | `PostInvoicesInvoiceVoid` |

**Anti-duplicate mechanism = metadata reconciliation, NOT idempotency keys.** The generic
`stripe_api_write` tool accepts path/query/body params only — it has **no HTTP header slot**, and
Stripe's `Idempotency-Key` is a header, so it cannot be passed through. Instead, stamp a
client-generated marker in the invoice `metadata` on every create (`metadata[soleur_invoice_key]`),
and **list-and-check that marker before every create/finalize** to prevent duplicates. This is the
primary path, not a fallback.

**Two confirmation gates layer — do not confuse them.** `stripe_api_write` may itself return a
Stripe-side `human_confirmation` request (an approval id + URL; re-call with `approval_token`). That
is a technical vendor gate and is **not founder-legible**. It layers **under** this skill's own
founder-legible preview + typed-`yes` gate (S2/S4/S5), which stays load-bearing. If the Stripe URL
approval appears, surface it plainly alongside the skill's own preview so the operator is not confused
by two prompts.

## Re-entrant MCP error table

This table applies at **every** MCP call, not just S1. The skill holds **no checkpoint state**, so
there is never a false "resume" — on a mid-flow failure, re-run from the last **un-sent** step.

| Condition | Meaning | Action |
|---|---|---|
| `MCP tool not found` | Stripe MCP not registered this session | Emit: run `mcp__plugin_soleur_stripe__authenticate`; **fail-closed** (stop). |
| `Token expired` (can fire mid-flow) | OAuth token rotated | Re-authenticate, then **re-run from the last un-sent step** (no checkpoint — re-read state from Stripe). |
| `403 Forbidden` | Token lacks access to this account/object | Confirm the OAuth account is the intended one; stop. |
| `429 rate-limit` | Too many requests | Retry **only** a read, or a write whose metadata marker was already reconciled (S4). **Never** a naive write retry — reconcile the marker first. |
| `finalize-ok / send-failed` | Invoice finalized but `send` failed | Go to **S4.8 recovery**: surface the finalized id + `hosted_invoice_url`; offer resend-same-id or `void`. Never re-create. |
| `already-finalized` | Finalize called on a finalized invoice | Go to S4.8 recovery (treat as finalized; do not re-create). |
| Network error | Transient connectivity | Retry a read; for a write, reconcile the metadata marker first, else abort. |
| `requires_location_inputs` (tax) | Customer address missing | **STOP** at S4.4 — do not preview an incomplete total; route to a customer-address fix (S6). |
| Finalize rejected (tax/currency/entity) | Missing invoice fact | Route to **S6** (refuse-to-fabricate). "Customer has no email" routes to a customer-fix step. |

## Workflow

### S1 — Auth precondition
If the Stripe MCP is not authenticated, emit the instruction to run
`mcp__plugin_soleur_stripe__authenticate` and **fail-closed** (stop). Do not proceed to any read or
write. The error table above is re-entrant: a `Token expired` later in the flow returns here.

### S2 — Account + mode gate (runs BEFORE any read)
This gate runs **before S3**, so a live account is refused before any customer PII is surfaced. It is
a **hard precondition for S3, S4, and S5**; the ack is **session-scoped** (once per session).

1. Call `get_stripe_account_info` to get the account id + display name. It returns **no `livemode`
   field**, so determine mode from the `livemode` boolean on any object a read returns (every Stripe
   object carries it); a Stripe **sandbox** account is inherently test.
2. Echo the **account id** and a **founder-legible plain-language mode line** — NOT the raw `livemode`
   field:
   - TEST: *"TEST mode — nothing real is sent; no customer is emailed and no money moves."*
   - LIVE: *"LIVE mode — real invoices to real customers."*
3. **If the account is livemode (`livemode == true`): STOP.** Emit a plain message that live invoicing
   is **not enabled yet** and point to [#6264](https://github.com/jikig-ai/soleur/issues/6264) (the
   legal lockstep). Offer **no** proceed path — there is no `understood`/`--force`/`--yes` live-send
   branch in v1.
4. In **TEST** mode, proceed only after the operator types a single literal `yes`. **Any non-exact
   token** (e.g. `y`, `Yes`, `yes please`) → re-echo the mode line **once**, then abort. No
   `--force`/`--yes` flags.

### S3 — Read "who owes you" (test mode only)
List customers and open/overdue invoices (`stripe_api_read` → `GetCustomers`, `GetInvoices` with
`status=open`). Present a scannable table (customer, amount, due date, invoice id).
**Empty-state:** if no customers exist, say so plainly and route to S4's create-customer path rather
than dead-ending.

### S4 — Guarded create + send
Ordered to avoid the orphaned-invoice window. **S2 must have passed this session.**

1. **Resolve customer.** If none supplied or not found: offer a guarded create-customer step, or emit
   "no customer resolved — create one in Stripe first." **Never finalize with no target.**
2. **Duplicate guard.** List the customer's existing open/draft invoices. If a same-amount or recent
   match exists, surface it and require an explicit **"not a duplicate"** confirm before continuing.
   Also list-and-check the `metadata[soleur_invoice_key]` marker.
3. **Build draft** (`PostInvoices` + `PostInvoiceitems` for operator-supplied line items). Stamp
   `metadata[soleur_invoice_key]` with a client-generated marker on the create write (the
   metadata-reconciliation anti-duplicate mechanism — Idempotency-Key headers are unavailable here).
4. **Compute-then-preview (pre-finalize).** If `automatic_tax` is enabled, **re-read the DRAFT**
   (`GetInvoicesInvoice`) to get Stripe's computed total **before** finalizing, so the founder-legible
   preview reflects the real total. **If tax status is `requires_location_inputs` (missing address):
   STOP** and route to a customer-address fix (S6) — do not preview an incomplete total.
5. **Typed-`yes`** on that preview. Decline → **abort** (nothing is finalized).
6. **`finalize`** (`PostInvoicesInvoiceFinalize`) — Stripe mints the invoice `number` (never
   agent-minted). Reconcile the metadata marker first if retrying.
7. **`send`** (`PostInvoicesInvoiceSend`). The **guaranteed deliverable is the `hosted_invoice_url`**
   minted at finalize — always surface it to the operator. In **test mode Stripe does not email the
   customer**, so `send` is **best-effort**; the hosted link is the honest v1 output.
8. **Recovery.** Finalize mints `hosted_invoice_url` immediately, so a failed `send` is **not** an
   orphan. Surface the finalized invoice id + hosted link and offer **resend the same id** or
   **`void`** (`PostInvoicesInvoiceVoid`) to retire it. **Never re-run create as recovery** — it mints
   a duplicate.

### S5 — Chase an overdue invoice
For an existing open/overdue invoice, re-trigger `send` (`PostInvoicesInvoiceSend`).
**S5 MUST run the S2 mode gate + a per-send preview + literal-`yes`** — including when the operator
opens directly with "chase my overdue." It **inherits the S2 livemode hard-stop**: no dunning against
a live account in v1.

### S6 — Refuse to fabricate
If tax rate, currency, or legal entity is unspecified, **STOP** and require an operator fact or
`automatic_tax` (Stripe Tax) — never guess. **Never mint an invoice number** (finalize does that).
A finalize rejected for a tax/currency/entity cause routes here; "customer has no email" routes to a
customer-fix step.

### S7 — PII discipline
Never write plaintext customer PII (name, address, email, amount tied to an identity) to any emitted
log line or committed file. Surface only what the operator needs **in-session** (which is not
persisted). This mirrors the `recipient_hash` HMAC discipline used elsewhere in the codebase.

## Sharp edges

- **Do not hardcode Stripe MCP tool names from memory** beyond the binding table above — the hosted
  MCP is runtime-discovered. Confirm op-ids with `stripe_api_details` / `stripe_api_search` at run time.
- **Never touch `STRIPE_SECRET_KEY`** — it is Soleur's own account; this skill lives on the MCP OAuth
  plane ([ADR-106](../../../../knowledge-base/engineering/architecture/decisions/ADR-106-stripe-mcp-oauth-plane-vs-product-billing-key.md)).
- The anti-duplicate mechanism is **metadata reconciliation**, not idempotency keys — the generic
  write tool cannot pass an `Idempotency-Key` header.
- Autonomous/cron sending is **out of v1 scope** — interactive browser OAuth cannot run headless. The
  multi-tenant path (Stripe Connect) is deferred to #6264.
