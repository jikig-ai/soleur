---
title: Stripe MCP OAuth plane vs product billing key for /soleur:invoice; credential boundary is defense-in-depth, not a tool sandbox
status: adopting
date: 2026-07-09
amends: none
supersedes: none
issue: 6260
related: [6259, 6264, 6268]
related_adrs: [ADR-083]
brand_survival_threshold: single-user incident
---

# ADR-107: Stripe MCP OAuth plane vs product billing key for `/soleur:invoice`

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
must **never** read or use the product-runtime `STRIPE_SECRET_KEY`, `.env`, or `lib/stripe.ts`.

**The credential-plane boundary is enforced by defense in depth, NOT by a tool sandbox.** Claude
Code's skill `allowed-tools` frontmatter is **pre-approval only**: per the official spec
(code.claude.com/docs/en/skills.md), *"it does not restrict which tools are available: every tool
remains callable, and your permission settings still govern tools that are not listed."* `Bash`,
`Read`, and `Write` therefore remain callable; a prompt-injection payload in a Stripe-returned field
(customer name, memo) could instruct a `Read('./.env')` or `Bash('cat lib/stripe.ts')`. No
skill-frontmatter mechanism removes a tool from the pool across the multi-turn interactive operator
exchange this skill requires — `disallowed-tools` restores the pool on the operator's next message,
and a `context: fork` subagent `tools:` allowlist (the only durable removal) cannot conduct the
typed-`yes` back-and-forth the approval gates depend on.

The boundary is therefore **three honest, partial layers**, each a reviewable/CI-gated repo artifact —
none a sandbox:

1. **Minimal declared scope** (`allowed-tools` = the 5 Stripe MCP tools): a defense-in-depth
   convention that suppresses prompts only for the intended surface; widening it is a reviewable
   frontmatter diff.
2. **Per-turn tool removal** (`disallowed-tools: Bash Read Write Edit`): removes the exfiltration
   tools for the duration of each operator turn, covering the intra-turn poisoned-read →
   same-turn-exfiltration chain; restores on the operator's next message.
3. **Cross-turn project deny** (committed `.claude/settings.json` → `permissions.deny`: `Read` on
   `**/.env`, `**/.env.*`, and `**/lib/stripe.ts`): durable across turns and mode-independent, but
   scoped to the `Read` vector only — a repo-wide `Bash` deny is infeasible because the workflow
   requires Bash.

The residual — a `Bash`-mediated secret read reachable only if the operator approves the permission
prompt — is accepted for v1 under the test-mode-only boundary (S2 livemode hard-STOP) and the
`single-user incident` threshold. The complete boundary (`context: fork` with a restricted subagent
`tools:` set) is deferred as incompatible with v1's interactive approval gates; it is the target
architecture if the interaction is re-modeled or a non-interactive send path is built (#6264 /
Stripe Connect territory).

## Alternatives Considered

### Credential plane

| Option | Verdict | Why |
|---|---|---|
| **(chosen) Per-user Stripe MCP OAuth plane** | Adopted | The OAuth account IS the token-agnostic mechanism; acts on the founder's own account; bundleable; the correct tenant. |
| **(a) Direct Stripe REST with `STRIPE_SECRET_KEY`** | Rejected | Couples to Soleur's own account (wrong tenant), not bundleable, and dispatches money-demands from the platform's billing credential. |
| **(b) Generic/both by token-plane rather than OAuth-account** | Rejected | The OAuth account is already the token-agnostic mechanism; a second credential plane doubles the failure modes this ADR exists to prevent. |
| **(c) Stripe Connect (connected accounts / restricted keys)** | Deferred to #6264 | The canonical multi-tenant "act on a third party's Stripe" pattern and the likely path for autonomous/cron sends (interactive browser OAuth cannot run headless) — but requires per-founder onboarding, out of the v1 interactive test-mode slice. |

### Credential-boundary enforcement mechanism

| Option | Verdict | Why |
|---|---|---|
| **(chosen) Three-layer defense-in-depth** (`allowed-tools` scope + `disallowed-tools` per-turn + committed `settings.json` `Read` deny) | Adopted for v1 | Each layer is a reviewable/CI-gated repo artifact; combined they close the `Read('.env')` vector intra- and cross-turn. Honest, self-contained, no operator step. |
| **`allowed-tools` as a sandbox ("physically cannot")** | Rejected — falsified | The plan/brainstorm asserted this; the official spec confirms `allowed-tools` is pre-approval only. Every tool stays callable. This was corrected at review time. |
| **`context: fork` + restricted subagent `tools:`** | Deferred | The ONLY mechanism that actually removes `Bash`/`Read` from the pool, and the correct target architecture — but incompatible with v1's interactive typed-`yes` / supply-line-items / "not a duplicate" gates. Revisit when a non-interactive send path exists. |
| **Descope / defer the skill** | Rejected | Disproportionate: with no blanket `Bash`/`Read` allow in committed `settings.json`, an injected `Read('.env')` hits a permission prompt today; test-mode-only bounds money/PII; the three committed layers close the `Read` vector. |

## Consequences

- The credential boundary is **defense-in-depth, not by construction.** Removing or renaming any
  layer breaches it; each is a reviewable diff, and layers 2–3 are additionally guarded by a
  `plugins/soleur/test/components.test.ts` assertion that the invoice SKILL.md retains
  `disallowed-tools: Bash Read Write Edit` and that `.claude/settings.json` retains the secret-file
  `Read` deny globs — a future edit dropping either fails CI.
- **Residual (accepted for v1):** injected Stripe data can still attempt `Bash('cat .env')`; the only
  backstop for the Bash vector is the interactive permission prompt. Soleur's committed
  `.claude/settings.json` grants no blanket `Bash`/`Read` allow (6 narrow git/gh entries), so such a
  call surfaces a prompt rather than executing silently — but the operator is non-technical and could
  approve it. Not merge-blocking: reachable only on approval, no live money/PII in test mode,
  threshold is single-user-incident. **Introducing a blanket `Bash` or `Read(**)` allow into
  `settings.json` re-opens this residual** — the CI guard protects the two committed layers, but
  nothing guards against a future over-broad allow-list entry.
- **`stripe_api_write` grants the founder's ENTIRE Stripe write surface** (refunds, payouts,
  account/bank-account updates, customer deletion — any `POST/PATCH/PUT/DELETE` by op-id), not just
  invoicing — inherent to the hosted MCP's generic dispatcher tool; the skill's binding table is a
  convention, not a limit. Bounded in v1 by the S2 test-mode hard-STOP and the typed-`yes` preview
  gate; not independently sandboxable. Documented, not blocking.
- **v1 is test-mode-only.** The first livemode send remains gated on the CG5 legal lockstep (#6264);
  no operator action is required to merge or run v1 (the durable hardening ships as committed repo
  artifacts, not a manual settings edit). The AC3a livemode hard-stop is the by-construction
  enforcement of the *mode* boundary (distinct from the credential boundary above).
- The anti-duplicate mechanism is metadata reconciliation (a **deterministic** hashed
  `metadata[soleur_invoice_key]` derived from stable invoice inputs, reused byte-for-byte across
  retries), because the generic MCP write tool cannot carry an `Idempotency-Key` header.
- The plan and this ADR's earlier draft asserted the boundary was "enforced by construction (the
  `allowed-tools` scope)" — that claim was falsified at review against the Claude Code skill spec and
  corrected here before merge. `status: adopting` flips to `accepted` once the skill is dogfooded
  end-to-end in a test-mode account and #6264's livemode lockstep is scoped.

## Diagram

**One C4 delta.** The Agent Runtime now transacts with Stripe using the operator's own credentials:
a `claude -> stripe` relationship is added to `model.c4` ("invoice skill: create/finalize/send/chase
via hosted Stripe MCP — OAuth, operator's OWN account; distinct credential plane from the
`webapp -> stripe` billing edge; ADR-107"). No new actor (the invoice recipient is reached by Stripe's
hosted invoice, never by Soleur directly), no new system (`stripe` already modeled), no new
container/data-store (no v1 founder ledger — that is #6264). The edge aggregates to `engine -> stripe`
in the context view, which already includes both elements, so no `views.c4` change is needed.
