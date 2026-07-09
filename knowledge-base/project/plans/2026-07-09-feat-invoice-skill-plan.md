---
title: "feat: /soleur:invoice skill v1 (read + guarded send)"
date: 2026-07-09
type: feat
issue: 6260
pr: 6259
branch: feat-invoice-skill
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-09-invoice-skill-brainstorm.md
spec: knowledge-base/project/specs/feat-invoice-skill/spec.md
---

# feat: `/soleur:invoice` skill v1 — read + guarded send ✨

## Overview

Add `plugins/soleur/skills/invoice/SKILL.md` — the Finance domain's **first executable
skill** (4 advisory finance agents exist today, zero skills). It's a get-paid workflow that
orchestrates the already-wired **Stripe hosted MCP** (`mcp.stripe.com`, OAuth-gated) to see
who owes you, create + send an invoice behind a human-approval gate, and chase overdue ones.

**No net-new product code.** The skill is a markdown workflow living entirely on the MCP plane;
`apps/web-platform/lib/stripe.ts` + the webhook route are product-runtime/inbound-only and are
**not** reused. Token-agnostic: acts on whichever Stripe account completed the OAuth (per the
operator's "generic/both" choice) — the account-safety gate (FR2) makes "which account" explicit.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (verified this session) | Plan response |
|---|---|---|
| Post-OAuth Stripe MCP exposes **named** tools (`create_invoice`, `list_customers`, `finalize_invoice`) | Hosted `mcp.stripe.com` exposes **generic** tools: `stripe_api_read` (GET), `stripe_api_write` (POST/PATCH/DELETE) with the Stripe API path as a param, plus `get_stripe_account_info`, `stripe_api_search`. **No static manifest — runtime-discovered.** ([Stripe MCP docs](https://docs.stripe.com/mcp)) | `allowed-tools:` frontmatter + step calls are **bound at /work Phase 0** after `__authenticate` + live tool enumeration. Workflow authored abstractly (draft→finalize→send→chase), mapped to whatever tools the runtime surfaces (named or generic). OQ resolved at build. |
| Skill description budget cap ~1800, "zero headroom" (learning 2026-04-21) | Live `components.test.ts:15` cap = **2,327 words**, current **2,257**, **70 free** (cap raised since that learning) | Invoice description ≤ ~40 words; re-measure at Step 2. No sibling-trim needed (70 > 10). |
| Stripe billing / invoice-history "not built" (implied gap) | Soleur's **own** subscription billing IS built (`billing/page.tsx`, webhook, roadmap 3.14 #1079 + 4.10 #1444 Done) — a **different** Stripe account than this skill targets | Skill targets the founder's *own* customers via the MCP OAuth plane; never touches product `STRIPE_SECRET_KEY`. |
| Registration = ~5 files | Count propagates to `plugin.json`, `plugins/soleur/README.md`, **root `README.md`**, **`knowledge-base/overview/brand-guide.md` (2×)**, `docs/_data/skills.js` (learning 2026-02-22) | `Files to Edit` greps the old count repo-wide + runs `sync-readme-counts.sh` + re-greps for zero stale. |

## User-Brand Impact

**If this lands broken, the user experiences:** an invoice that fails to send (no money in) or,
worse, sends against the **wrong Stripe account** (test-vs-live confusion) — a founder trusting
the skill either doesn't get paid or dispatches a malformed money-demand.

**If this leaks, the user's customer data / money is exposed via:** plaintext customer
name/address/amount written to a log or committed artifact (US-Stripe → EU-pinned-estate residency
drift), or an autonomous send of a wrong-amount/duplicate invoice to a real person.

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true`.
`user-impact-reviewer` runs at PR-review time. (CPO plan-time sign-off: see Domain Review.)

## Implementation Phases

### Phase 0 — Runtime grounding (before writing SKILL.md)
1. Authenticate the Stripe MCP (`mcp__…stripe__authenticate`) in a **test-mode** account, then
   **enumerate the actual post-OAuth tools**. Produce a **capability→tool binding table** for the six
   verbs S4/S5 need: *account-info, list (customers/invoices), create-draft, retrieve-invoice,
   finalize, send, void* — recording each tool's exact name + call shape (named tools vs generic
   `stripe_api_read`/`stripe_api_write` + path).
2. **Idempotency-support probe (load-bearing — fable advisor).** Determine whether the discovered
   write tool **accepts an `Idempotency-Key`**. If YES → S4 uses idempotency keys. If NO → S4 branches
   to the **metadata-reconciliation fallback**: stamp a client-generated marker in the invoice
   `metadata` on create, and list-and-check for that marker before every create/finalize to prevent
   duplicates. The binding table records this yes/no; S4 must not assume key support.
3. Confirm `get_stripe_account_info` (or `GET /v1/account`) returns account id + `livemode`.
4. Run the budget one-liner (`bun test plugins/soleur/test/components.test.ts`) to re-confirm headroom.

### Phase 1 — Author `plugins/soleur/skills/invoice/SKILL.md`
Mirror the `linear-fetch` / `xcode-test` MCP idiom (frontmatter `allowed-tools` + `preconditions`,
error table, step-by-step MCP calls) and the `flag-delete` / `admin-ip-refresh` / `user-set-role`
typed-`yes` guard shape (`hr-menu-option-ack-not-prod-write-auth`).

Workflow steps:
- **S1 Auth precondition** — if Stripe MCP not authenticated, emit the instruction to run
  `authenticate`; fail-closed. The **error table is re-entrant** (I1): it applies at every MCP call,
  not just S1. Rows: `MCP tool not found`→re-auth; `Token expired` (can fire mid-flow)→re-auth then
  **re-run from the last un-sent step** (the skill holds no checkpoint state — no false "resume");
  `403`→confirm account access; `429 rate-limit`→retry **only** idempotency-key-gated (or
  metadata-reconciled per Phase 0), never a naive write retry; `finalize-ok / send-failed`→S4
  recovery; `already-finalized`→S4 recovery; network→idempotency-gated retry or abort.
- **S2 Account + mode gate (FR2) — runs BEFORE S3** (so a live account is refused before any customer
  PII is surfaced — arch P1) — call `get_stripe_account_info`; **echo account id + a founder-legible
  mode line** (CPO): plain-language *"TEST mode — nothing real is sent"* vs a LIVE line, NOT the raw
  `livemode` field. **v1 hard-refuses livemode (arch P0 / simplicity):** if `livemode == true`, **STOP**
  with a plain message that live invoicing is not enabled yet and points to #6264 (the CG5 legal
  lockstep) — do NOT offer any proceed path. In **test** mode, proceed after a single literal `yes`
  (**any non-exact token → re-echo once, then abort**, I3; no `--force`/`--yes`). S2 is a **hard
  precondition for S3, S4, and S5** (C2/arch P1); the ack is session-scoped.
- **S3 Read "who owes you" (FR3)** — (only reached in test mode) list customers + open/overdue
  invoices; scannable table. **Empty-state (C3):** if no customers exist, say so plainly and route to
  S4's create-customer path rather than dead-ending.
- **S4 Guarded create + send (FR4)** — the sharp part; ordered to **avoid the orphaned-invoice window**
  (C1):
  1. **Resolve customer.** If none supplied / not found (C3, I2): offer a guarded create-customer step
     or emit "no customer resolved — create one in Stripe first"; never finalize with no target.
  2. **Duplicate guard (CPO):** list the customer's existing open/draft invoices; if a same-amount or
     recent match exists, surface it and require an explicit "not a duplicate" confirm before continuing.
  3. **Build draft** (operator-supplied line items) with a **Stripe idempotency key** on the create write.
  4. **Compute-then-preview (pre-finalize):** if `automatic_tax` is enabled, **re-read the DRAFT** to
     get Stripe's computed total *before* finalizing — the founder-legible preview reflects the real
     total, moving the divergence check **ahead of** finalize (so no redundant post-finalize abort is
     needed). **If tax status is `requires_location_inputs`, STOP** (missing customer address) rather
     than previewing an incomplete total (advisor).
  5. **Typed-`yes`** on that preview. Decline → abort (nothing finalized).
  6. **`finalize`** (idempotency/metadata-guarded; Stripe mints the number).
  7. **`send`** — the guaranteed deliverable is the **`hosted_invoice_url` minted at finalize**, always
     surfaced to the operator. In **test mode Stripe does not email the customer**, so `send` is
     best-effort; the hosted link is the honest v1 output (advisor).
  8. **Recovery (C1, simplified):** finalize mints `hosted_invoice_url` immediately, so a failed `send`
     is **not** an orphan — surface the finalized invoice id + hosted link and offer **resend the same
     id** (or `void_invoice` to retire it). **Never re-run create as recovery** (it mints a duplicate).
- **S5 Chase (FR5)** — for an existing open/overdue invoice, re-trigger `send`. **S5 MUST run the S2
  mode gate + a per-send preview + literal-`yes`** (C2/CG1) — including when the operator opens directly
  with "chase my overdue"; and it inherits the S2 livemode hard-stop (no dunning against a live account in v1).
- **S6 Refuse-to-fabricate (FR6)** — if tax rate / currency / legal-entity is unspecified, STOP and
  require an operator fact or `automatic_tax` (Stripe Tax); never guess. Never mint an invoice number.
  **Finalize-rejected (I2)** routes here for tax/currency/entity causes, and to a customer-fix step for
  "customer has no email".
- **S7 PII discipline (CG4)** — no plaintext customer PII in any emitted log line or file; surface only
  what the operator needs in-session (which is not persisted).

### Phase 2 — Register the skill
Edit the count/listing surfaces (see Files to Edit), run `scripts/sync-readme-counts.sh`, re-grep for
stale counts. Add the `SKILL_CATEGORIES` entry (category: finance/operations).

### Phase 3 — ADR + C4 (see Architecture Decision section) + tests
Author ADR-103 (`status: adopting`), add the `claude → stripe` C4 edge, run component + C4 tests.

## Files to Create
- `plugins/soleur/skills/invoice/SKILL.md`
- `knowledge-base/engineering/architecture/decisions/ADR-103-stripe-mcp-oauth-plane-vs-product-billing-key.md`

## Files to Edit
- `plugins/soleur/.claude-plugin/plugin.json` — `description` component counts
- `plugins/soleur/README.md` — counts table + skill listing (finance/ops category)
- `README.md` (root) — skill count
- `knowledge-base/overview/brand-guide.md` — skill count (2 occurrences)
- `plugins/soleur/docs/_data/skills.js` — `SKILL_CATEGORIES` entry for `invoice`
- `knowledge-base/engineering/architecture/diagrams/model.c4` — add `claude → stripe` edge
- (no `views.c4` edit — `stripe` + `engine`/`claude` already in the context + containers `include` lists; the new edge renders and aggregates to `engine → stripe` in the context view)

**Count-propagation gate:** `git grep -n "<old-skill-count>"` repo-wide before AND after
`sync-readme-counts.sh`; the after-grep must return zero stale counts.

## Architecture Decision (ADR/C4)

> **Correction to brainstorm:** the ADR was tentatively filed under the deferred v2 issue (#6264).
> The `wg-architecture-decision-is-a-plan-deliverable` gate requires it ship **with** v1 — v1 is what
> establishes the credential-plane boundary. Moving ADR-103 into v1 scope; #6264 updated to drop it.

### ADR
- **Create ADR-103** — "Stripe MCP OAuth plane vs product billing key for `/soleur:invoice`",
  `status: adopting`. Decision: the invoice skill acts **exclusively** on the per-user Stripe MCP
  OAuth plane (`mcp.stripe.com`); it **never** reads or uses the product-runtime `STRIPE_SECRET_KEY`
  (Soleur's own subscription-billing credential). Rationale: two disjoint credential planes; acting on
  the wrong one (test-vs-live, Soleur's-vs-founder's) is the feature's sharpest failure. Alternatives
  considered: (a) direct Stripe REST with `STRIPE_SECRET_KEY` — rejected (couples to Soleur's account,
  not bundleable, wrong tenant); (b) generic/both by *token-plane* rather than OAuth-account — rejected
  (the OAuth account IS the token-agnostic mechanism; a second plane doubles failure modes);
  (c) **Stripe Connect** (connected accounts / restricted keys) — the canonical multi-tenant "act on a
  third party's Stripe" pattern and the likely path for autonomous/cron sends (interactive browser OAuth
  can't run headless) — **considered and deferred to #6264** (requires per-founder onboarding; out of
  the v1 interactive test-mode slice). ADR-083.
  - **Mechanical enforcement (arch P1) — the boundary is capability-scoped, not prose.** ADR-103 records
    that the skill's `allowed-tools` frontmatter contains **only** the Stripe MCP tools (plus, if strictly
    needed, a narrowly-scoped read) and **explicitly excludes** `Bash`, secret-file `Read`, and any
    Doppler tool — so the skill physically **cannot** read `STRIPE_SECRET_KEY`/`.env`/`lib/stripe.ts`,
    regardless of any prose prohibition. A grep on a sentence (old AC4) is not the guard; the tool scope is.
  - **`## Consequences` (arch P2) — the temporal access boundary lives with the credential boundary.**
    Record that livemode writes are **blocked in v1** pending the CG5 legal lockstep (#6264); an engineer
    reading only ADR-103 must learn both "MCP OAuth plane, never the product key" AND "test-mode until #6264".
  **Ordinal is provisional** — `/ship`'s ordinal-collision gate re-verifies ADR-103 against `origin/main`.
- **C4 completeness check (all three `.c4` files read):**
  - External human actors — the invoice **recipient** (founder's customer) is reached by **Stripe**
    (hosted invoice), never by Soleur directly → **no new actor** (a Soleur→customer edge would be false).
  - External systems — `stripe` already modeled (`model.c4:242`). No new system.
  - Containers/data-stores — none new (no v1 ledger; that's #6264).
  - **Changed access relationship** — the Agent Runtime now transacts with Stripe using the operator's
    own credentials: **add `claude → stripe`** ("invoice skill: create/finalize/send/chase via hosted
    Stripe MCP — OAuth, operator's OWN account; distinct credential plane from the `webapp → stripe`
    billing edge; ADR-103"). This is the only C4 delta.
  - Pre-existing stale "61 workflow skills" count in the `skills` container description is independent
    drift (real ≈93) — **not** corrected here (bumping to 62 would be equally wrong; a full recount is a
    separate hygiene task).
- Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edge edit.

## Domain Review

**Domains relevant:** Finance, Legal, Engineering, Product (sign-off). Carried forward from the
brainstorm `## Domain Assessments` (CFO/CLO/CTO); Product added for the single-user-incident sign-off.

### Finance (CFO) — carry-forward
**Status:** reviewed. Smallest valuable slice = create→send→list-overdue→resend; do NOT stub
reconcile (deferred #6264 — no founder ledger yet). Delegate rev-rec/reporting *analysis* to
`revenue-analyst`/`financial-reporter`; the Stripe *action* is net-new skill logic.

### Legal (CLO) — carry-forward — PROCEED-WITH-GUARDRAILS
**Status:** reviewed. See Compliance Gate. Invoice issuance is a new outbound money-demand surface
absent from the legal threshold catalog (`recommended-tools.md`) — tracked for #6264.

### Engineering (CTO) — carry-forward
**Status:** reviewed. Skill-shaped, no net-new product code; copy `linear-fetch` idiom; credential
plane is the sharp edge (ADR-103). Runtime tool enumeration required (Phase 0).

### Product/UX Gate
**Tier:** none. Files to Create/Edit are markdown/JSON/`.c4`/`.js`-data — **no** UI-surface path
(`components/**/*.tsx`, `app/**/page.tsx`). No wireframes required (`wg-ui-feature-requires-pen-wireframe`
does not fire). **CPO plan-time sign-off** still required per `requires_cpo_signoff: true` — obtained via
CPO domain-leader spawn (Phase 2.5) since the brainstorm assessed CFO/CLO/CTO, not CPO.

## Compliance Gate (Phase 2.7 — GDPR trigger fired: new external-API processing + single-user threshold)

The CLO assessment IS the compliance review; the gate's output is the CG list below. A full
`/soleur:gdpr-gate` run happens at /work against the **drafted SKILL.md** (the regulated surface is the
skill's runtime PII handling, which does not exist as text until Phase 1).

- **CG1** — human-approval preview before every send/dunning (S4/S5); **no auto-send path**. Load-bearing.
- **CG2** — Stripe-owned sequential numbering (finalize mints it); never agent-minted.
- **CG3** — refuse-to-fabricate tax/currency/legal-entity (S6).
- **CG4** — no plaintext customer PII in logs/artifacts (S7); mirror the `recipient_hash` HMAC discipline.
- **CG5** — three-doc (→ up to **6-location**, learning 2026-03-10) GDPR lockstep + full legal-doc audit
  (`grep "does not collect"/"no personal data"/"email address"` across `**/legal/*.md`) before the first
  **livemode** send. **Building + test-mode use is NOT gated on this.** Delegate to
  `legal-compliance-auditor` at implementation; the livemode enablement lives in #6264.

## Observability

**Skip — with reason.** The skill is an interactive CLI markdown workflow (not code under
`apps/*/server`, `apps/*/src`, `apps/*/infra`, or `plugins/*/scripts/`; no new infra). Its failure
modes (auth failure, wrong account, send failure, tax-unspecified) surface **in the operator's live
session** via the SKILL.md error table — there is no blind/server-side execution surface to instrument
with Sentry/Better Stack. The error table IS the observability for this surface. If a future v2 adds a
server-side/cron send path, the Phase 2.9 gate re-applies.

## Infrastructure (IaC)

**None.** The Stripe MCP is already registered (`plugin.json:38`, `mcp.stripe.com`); auth is per-user
browser OAuth (not an IaC-provisionable secret). No new server, cron, vendor account, secret, or DNS.
Phase 2.8 skipped. The skill must **never** introduce a `STRIPE_SECRET_KEY` dependency (ADR-103).

## Open Questions (carry to /work)
- OQ1 — standalone skill vs a new finance-write agent owner (no agent owns live Stripe writes today).
- OQ2 — exact post-OAuth Stripe MCP tool names + call shape (resolved at Phase 0 enumeration).
- OQ3 — founder-side ledger location (blocks #6264 reconcile; out of v1 scope).

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** — `plugins/soleur/skills/invoice/SKILL.md` exists with `name: invoice`, third-person
  `description` ("This skill should be used when…") ≤ 1024 chars, `allowed-tools`, `preconditions`.
- **AC2** — `bun test plugins/soleur/test/components.test.ts` passes (frontmatter, cumulative budget
  ≤ 2327 words, per-skill ≤ 1024 chars, "This skill" voice, kebab-case, no-backtick refs).
- **AC3** — the SKILL.md contains a **literal-`yes` confirmation** step before any send/finalize on
  **both the S4 create AND the S5 chase path** (C2), preceded by a **founder-legible plain-language mode
  line** (not a raw `livemode` field — CPO) and the account id.
- **AC3a (livemode refusal — arch P0 / simplicity)** — grep asserts the SKILL.md **hard-STOPs** on
  `livemode == true` and routes to #6264, with **no** live proceed-path (no `understood` live-send branch).
  This is the by-construction enforcement of AC11.
- **AC4 (mechanical credential isolation — arch P1)** — the SKILL.md `allowed-tools` frontmatter contains
  **only** Stripe MCP tools (no `Bash`, no secret-file `Read`, no Doppler tool); grep both that
  `STRIPE_SECRET_KEY` is never referenced AND that `allowed-tools` is Stripe-MCP-scoped. Never mint an
  invoice number (grep prohibition present).
- **AC5** — the SKILL.md contains a re-entrant MCP error table with rows for `MCP tool not found`/
  `Token expired`→re-auth, **`429`→idempotency-keyed retry only**, and **`finalize-ok / send-failed`→
  recovery block** (C1/I1).
- **AC5a** — the create/finalize writes carry a **Stripe idempotency key OR the Phase-0
  metadata-reconciliation marker** (grep present, per the binding-table probe); the recovery block offers
  only resend-same-id or `void_invoice` and **explicitly forbids re-create** as recovery (C1).
- **AC5b** — a **duplicate guard** step lists the customer's existing open/draft invoices and requires a
  "not a duplicate" confirm before create (CPO); an **empty-account / customer-not-found** path is
  specified rather than dead-ending (C3).
- **AC6** — count-propagation: `git grep -n "<old-count>"` returns **zero** stale skill counts after
  `sync-readme-counts.sh` (plugin.json, both READMEs, brand-guide.md ×2, skills.js all consistent).
- **AC7** — ADR-103 file exists with `status: adopting`, a `## Decision`, a `## Alternatives Considered`
  table naming the three rejected options (STRIPE_SECRET_KEY / token-plane / Stripe Connect), and a
  `## Consequences` entry recording the test-mode-until-CG5 (#6264) livemode gate.
- **AC8** — `model.c4` contains exactly one new `claude -> stripe` relationship citing ADR-103;
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC9** — `docs/_data/skills.js` has an `invoice` → finance/ops `SKILL_CATEGORIES` entry.
- **AC10 (hosted-link is the deliverable — advisor)** — the SKILL.md always surfaces the
  `hosted_invoice_url` after finalize and specs `send` as best-effort in test mode (grep present). The
  tax divergence check is **pre-finalize** (S4.4); there is **no** post-finalize re-fetch-and-abort
  (the redundant draft-echo guard was removed — it recreated the orphan window).

### Post-merge (operator)
- **AC11** — first **livemode** send remains gated on the CG5 legal lockstep (#6264); v1 ships usable in
  **test mode only** — enforced by construction via the AC3a livemode hard-stop. No operator action is
  required to merge v1 (test-mode build is self-contained).

## Test Scenarios
- **Happy path (test mode):** authenticate → echo shows plain "TEST mode" → single `yes` → list overdue
  → resolve customer → duplicate guard clears → draft → compute-then-preview → `yes` → finalize → the
  `hosted_invoice_url` is returned (send is best-effort; no customer email in test mode).
- **Livemode refusal (arch P0):** authenticated account is `livemode: true` → skill **STOPS before any
  read**, shows the plain message + #6264, offers no proceed path.
- **Refuse-to-fabricate:** customer with no tax config + no operator-supplied rate → skill STOPS at S6;
  `requires_location_inputs` (no address) also STOPS at S4.4.
- **Send-fails-after-finalize (C1):** `send` fails after `finalize` → skill surfaces the finalized id +
  hosted link and offers resend-same-id or void — re-running create is refused; **no duplicate minted**.
- **Duplicate guard (CPO):** a same-amount recent open invoice exists → skill surfaces it and requires
  "not a duplicate" confirm before continuing.
- **Empty account (C3):** no customers exist → skill says so and routes to create-customer, not a dead-end.
- **Chase gate (C2):** operator opens with "chase my overdue" → S2 mode gate + per-send `yes` fire, and
  a live account is refused, before any dunning send.
- **Abort:** operator declines the `yes` → nothing is finalized or sent.

## Plan Review

**Panel (relevance-substituted).** The default `/plan_review` eng-panel is Rails-reviewer-heavy
(DHH/Kieran) — a poor fit for a markdown-skill + ADR/C4 plan with no Rails code. Substituted the
genuinely-fitting lenses: **CFO/CLO/CTO** (brainstorm carry-forward), **CPO** (single-user-incident
sign-off → APPROVE-WITH-CHANGES), **spec-flow-analyzer** (workflow-completeness), **architecture-strategist**
(ADR/C4/credential-plane — confirmed C4+ADR correct), **code-simplicity-reviewer** (YAGNI), and a scoped
**`fable` advisor** consult (Phase 4.5). All findings were **applied**, not deferred:

- CPO → duplicate guard (S4.2/AC5b) + founder-legible mode line (S2/AC3).
- spec-flow → orphan-invoice/duplicate recovery (S4.8), idempotency keys, S5 chase-gate (C2), empty-account/finalize-reject states (C3/I2), re-entrant error table (I1).
- fable advisor → Phase-0 idempotency-support probe + metadata-reconciliation fallback; hosted-link as guaranteed deliverable; `requires_location_inputs` stop.
- architecture-strategist + code-simplicity (consensus P0) → **livemode hard-stop in v1** (S2/AC3a), which *removed* the live double-ack machinery (net simplification + safety); mechanical `allowed-tools` credential isolation (AC4); ADR-103 Connect alternative + Consequences; cut redundant post-finalize draft-echo (old AC10); filed C4 count-hygiene issue #6268.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (This plan's section is filled.)
- **Do not hardcode Stripe MCP tool names from memory** — the hosted MCP is runtime-discovered and may
  expose generic `stripe_api_read`/`stripe_api_write` rather than named tools. Bind at Phase 0.
- **`!` code-fence permission flow fails silently** (learning 2026-02-22): keep any permission-sensitive
  Bash surfaced in the skill narrative or pre-allowlisted, not buried in a `!` fence.
- **Never touch `STRIPE_SECRET_KEY`** — it is Soleur's own account; the skill lives on the MCP OAuth plane (ADR-103).
- If v2 adds Stripe **webhook** listeners, apply the insert-first dedup pattern (learning 2026-04-22) — out of v1 scope.
