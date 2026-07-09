---
name: invoice
description: "This skill should be used when the founder wants to get paid through their own Stripe account: list who owes them, create and send an invoice behind a human-approval preview, or chase an overdue one. Test-mode only in v1."
allowed-tools:
  - mcp__plugin_soleur_stripe__get_stripe_account_info
  - mcp__plugin_soleur_stripe__stripe_api_read
  - mcp__plugin_soleur_stripe__stripe_api_write
  - mcp__plugin_soleur_stripe__stripe_api_search
  - mcp__plugin_soleur_stripe__stripe_api_details
disallowed-tools: Bash Read Write Edit
preconditions:
  - Stripe MCP server is authenticated (mcp__plugin_soleur_stripe__authenticate has been run for this session)
  - The authenticated account is in TEST mode (v1 hard-refuses livemode — see S2)
---

# Invoice — get paid via your own Stripe

This skill is the Finance domain's get-paid workflow. It drives the **hosted Stripe MCP**
(`mcp.stripe.com`, OAuth) to see who owes the founder money, create + send an invoice behind a
human-approval preview, and chase overdue ones. It acts on the founder's **own** Stripe account —
whichever account completed the OAuth — and **must never** touch Soleur's product billing credential
(`STRIPE_SECRET_KEY`). See [ADR-107](../../../../knowledge-base/engineering/architecture/decisions/ADR-107-stripe-mcp-oauth-plane-vs-product-billing-key.md)
for the credential-plane boundary and its enforcement model.

**Credential isolation is defense-in-depth, NOT a tool sandbox.** A skill's `allowed-tools` is
*pre-approval only* — per the Claude Code spec it does **not** remove `Bash`/`Read`/`Write` from the
pool, so a prompt-injection payload in a Stripe-returned field (a customer name/memo) could try to
`Read('.env')` or `Bash('cat lib/stripe.ts')`. The boundary is three partial layers: (1) `allowed-tools`
lists only the 5 Stripe MCP tools (minimal declared scope); (2) `disallowed-tools: Bash Read Write Edit`
removes the exfiltration tools for the duration of each operator turn (the injection window); (3) a
committed `.claude/settings.json` `Read` deny on `**/.env*` + `**/lib/stripe.ts` covers the cross-turn
`Read` vector. Residual: a `Bash`-mediated secret read, reachable only if the operator approves a
permission prompt. Full model + rejected alternatives (`context: fork`) in ADR-107.

**v1 scope: TEST mode only.** Livemode invoicing is blocked in v1 (S2 hard-stop) pending the legal
lockstep tracked in [#6264](https://github.com/jikig-ai/soleur/issues/6264). Building and test-mode
use are **not** gated on that.

## Tool surface (generic, runtime-discovered)

The hosted MCP exposes **generic** tools, not named ones (`create_invoice` does not exist). Bind each
verb to a generic call (op-ids confirmed via `stripe_api_details` / `stripe_api_search` at run time):

| Verb | MCP tool | Stripe op-id |
|---|---|---|
| account info | `get_stripe_account_info` | — |
| mode probe (livemode, zero-PII) | `stripe_api_read` | `GetBalance` |
| list customers | `stripe_api_read` | `GetCustomers` |
| list invoices (open/overdue) | `stripe_api_read` | `GetInvoices` (filter `status=open`) |
| retrieve invoice | `stripe_api_read` | `GetInvoicesInvoice` |
| create draft | `stripe_api_write` | `PostInvoices` (body: `customer`, `collection_method=send_invoice`, `days_until_due`, `automatic_tax`, `currency`, `metadata`) |
| add line item | `stripe_api_write` | `PostInvoiceitems` |
| finalize | `stripe_api_write` | `PostInvoicesInvoiceFinalize` |
| send | `stripe_api_write` | `PostInvoicesInvoiceSend` |
| void | `stripe_api_write` | `PostInvoicesInvoiceVoid` |

**Anti-duplicate mechanism = DETERMINISTIC metadata reconciliation, NOT idempotency keys.** The generic
`stripe_api_write` tool accepts path/query/body params only — it has **no HTTP header slot**, and
Stripe's `Idempotency-Key` is a header, so it cannot be passed through. Instead, stamp a **deterministic**
marker in the invoice `metadata` on every create: `metadata[soleur_invoice_key]` = a hash of the invoice's
**stable inputs** (customer id + currency + total amount + line-item descriptions/amounts + a coarse
date/period bucket), computed the SAME way on every attempt so a retry regenerates the **byte-identical**
value. **Never put raw customer PII in the marker — hash it.** Then **list-and-check that exact marker
before every create/finalize**: if a prior attempt's marker already exists, reconcile to that invoice
instead of minting a second one. A non-deterministic (per-attempt-random) marker would defeat this — a
lost-response create followed by a retry would generate a new marker, match nothing, and mint a duplicate.

**Two confirmation gates layer — by AUTHORITY (do not conflate them).** `stripe_api_write` may return a
Stripe-side `human_confirmation` request (an approval id + URL; the human approves at the URL; re-call
with `approval_token`, which the agent **cannot** self-satisfy). When it fires, **the Stripe URL approval
is the final authorization that actually executes the write.** State this plainly to the operator and
**re-display the skill's own computed total inside that instruction**, so the founder approves the Stripe
page against the same number the skill previewed. The skill's founder-legible preview + typed-`yes`
(S2/S4/S5) runs first and remains required; do **not** describe the native Stripe gate as subordinate —
surface both without conflating them, and make explicit which action actually sends.

## Re-entrant MCP error table

This table applies at **every** MCP call, not just S1. The skill holds **no checkpoint state**, so
there is never a false "resume" — on a mid-flow failure, re-run from the last **un-sent** step (the
deterministic `soleur_invoice_key` marker is what makes that re-run safe against duplicates).

| Condition | Meaning | Action |
|---|---|---|
| `MCP tool not found` | Stripe MCP not registered this session | Emit: run `mcp__plugin_soleur_stripe__authenticate`; **fail-closed** (stop). |
| `Token expired` (can fire mid-flow) | OAuth token rotated | Re-authenticate, then **re-run from the last un-sent step** (re-read state from Stripe; reconcile the marker before any re-create). |
| `403 Forbidden` | Token lacks access to this account/object | Confirm the OAuth account is the intended one; stop. |
| `429 rate-limit` | Too many requests | Retry a read, or a write **only after** re-checking the `soleur_invoice_key` marker (reconcile-then-retry). **Never** a naive write retry. |
| Mode indeterminate | The `GetBalance` probe returned no usable `livemode` boolean | **STOP** — never assume test mode (S2 fail-closed). |
| `finalize-ok / send-failed` | Invoice finalized but `send` failed | Go to **S4.8 recovery**: surface the finalized id + `hosted_invoice_url`; offer resend-same-id or `void`. Never re-create. |
| `already-finalized` | Finalize called on a finalized invoice | Go to S4.8 recovery (treat as finalized; do not re-create). |
| Network error | Transient connectivity | Retry a read; for a write, reconcile the `soleur_invoice_key` marker first, else abort. |
| `requires_location_inputs` (tax) | Customer address missing | **STOP** at S4.4 — do not preview an incomplete total; route to a customer-address fix (S6). |
| Finalize rejected (tax/currency/entity) | Missing invoice fact | Route to **S6** (refuse-to-fabricate). "Customer has no email" routes to a customer-fix step. |

## Workflow

### S1 — Auth precondition
If the Stripe MCP is not authenticated, emit the instruction to run
`mcp__plugin_soleur_stripe__authenticate` and **fail-closed** (stop). Do not proceed to any read or
write. The error table above is re-entrant: a `Token expired` later in the flow returns here.

### S2 — Account + mode gate (runs BEFORE any customer read)
This gate runs **before S3**, so a live account is refused before any customer PII is surfaced. It is
a **hard precondition for S3, S4, and S5**; the ack is **session-scoped** (once per session).

1. Call `get_stripe_account_info` for the account id + display name (the account echo).
2. **Determine `livemode` deterministically from a ZERO-PII read**, not from customer data: call
   `stripe_api_read` op-id `GetBalance`. The Balance object carries a `livemode` boolean and contains
   **no customer PII**, so mode can be established before any `GetCustomers`/`GetInvoices` read. **Fail
   closed:** if the probe returns no usable `livemode` boolean (error, empty, unexpected shape), **STOP**
   — never assume test mode.
3. Echo the **account id** and a **founder-legible plain-language mode line** — NOT the raw `livemode`
   field:
   - TEST: *"TEST mode — nothing real is sent; no customer is emailed and no money moves."*
   - LIVE: *"LIVE mode — real invoices to real customers."*
4. **If `livemode == true`: STOP.** Emit a plain message that live invoicing is **not enabled yet** and
   point to [#6264](https://github.com/jikig-ai/soleur/issues/6264) (the legal lockstep). Offer **no**
   proceed path — there is no `understood`/`--force`/`--yes` live-send branch in v1.
5. In **TEST** mode, proceed only after the operator types a single literal `yes`. **Any non-exact
   token** (e.g. `y`, `Yes`, `yes please`) → re-echo the mode line **once**, then abort. No
   `--force`/`--yes` flags.

### S3 — Read "who owes you" (test mode only)
List customers and open/overdue invoices (`stripe_api_read` → `GetCustomers`, `GetInvoices` with
`status=open`). Present a scannable table with the minimum the operator needs to act — customer name,
amount, due date, invoice id (per S7, do not dump full email/address here).
**Empty-state:** if no customers exist, say so plainly and route to S4's create-customer path rather
than dead-ending.

### S4 — Guarded create + send
Ordered to avoid the orphaned-invoice window. **S2 must have passed this session.**

1. **Resolve customer.** If none supplied or not found: offer a guarded create-customer step, or emit
   "no customer resolved — create one in Stripe first." **Never finalize with no target.**
2. **Duplicate guard.** List the customer's existing open/draft invoices AND list-and-check the
   deterministic `metadata[soleur_invoice_key]` marker. If a same-amount / recent match or an existing
   marker match exists, surface it and require an explicit **"not a duplicate"** confirm (or reconcile
   to the existing invoice) before continuing.
3. **Build draft** (`PostInvoices` + `PostInvoiceitems` for operator-supplied line items). Stamp
   `metadata[soleur_invoice_key]` with the **deterministic** marker (hash of customer id + currency +
   total + line-items + coarse date bucket — byte-identical across retries so a lost-response retry
   reconciles instead of minting a duplicate). Do **not** put raw customer PII in metadata.
4. **Compute-then-preview (pre-finalize) — ALWAYS.** Re-read the DRAFT (`GetInvoicesInvoice`) to get
   Stripe's authoritative totals, and present a founder-legible preview of the **real total** (line-item
   sum + tax + currency) before finalizing. This applies to **both** the `automatic_tax` path (Stripe
   computes tax) **and** the manual-tax path (operator-supplied rate) — the founder always sees the
   actual total feeding the money-demand before the irreversible finalize. **If `automatic_tax` is
   enabled and tax status is `requires_location_inputs` (missing address): STOP** and route to a
   customer-address fix (S6) — do not preview an incomplete total.
5. **Typed-`yes`** on that preview. Decline → **abort** (nothing is finalized).
6. **`finalize`** (`PostInvoicesInvoiceFinalize`) — Stripe mints the invoice `number` (never
   agent-minted). Reconcile the `soleur_invoice_key` marker first if retrying.
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
Never write plaintext customer PII (name, address, email, amount tied to an identity) to any committed
repo artifact or application log. **Note:** the Claude Code conversation transcript persists to local
disk (`~/.claude/projects/…`), so anything surfaced in-session **is** written to that local file — the
plan's earlier "not persisted" framing is inaccurate. Therefore surface only the **minimum** the
operator needs to act: customer name + amount + due date + invoice id for the "who owes you" table;
email/address only at the moment they are needed to resolve or create a customer, never a full PII dump.
This mirrors the `recipient_hash` HMAC discipline. The `allowed-tools`/`disallowed-tools` scope prevents
the skill from itself authoring a committed artifact, but does not change transcript persistence.

## Sharp edges

- **The credential boundary is defense-in-depth, not a sandbox.** Do NOT re-describe `allowed-tools` as
  isolation, and never introduce `Bash`/secret-`Read`/Doppler into this skill's frontmatter or a blanket
  `Bash`/`Read` allow into `.claude/settings.json` — either re-opens the exfiltration residual (ADR-107).
- **Do not hardcode Stripe MCP tool names from memory** beyond the binding table — the hosted MCP is
  runtime-discovered; confirm op-ids with `stripe_api_details` / `stripe_api_search` at run time.
- `stripe_api_write` is a **generic dispatcher for the founder's entire Stripe write surface** (refunds,
  payouts, account updates — not just invoicing). The binding table is a convention, not a limit; bounded
  in v1 only by the S2 test-mode hard-STOP + the typed-`yes` gate (ADR-107 §Consequences).
- Autonomous/cron sending is **out of v1 scope** — interactive browser OAuth cannot run headless. The
  multi-tenant path (Stripe Connect) and a `context: fork` by-construction tool boundary are deferred to #6264.
