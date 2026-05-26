---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_plan: knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
type: focused-refresh
---

# PR-F Inngest Trigger Layer — Brainstorm (Focused Refresh)

**Date:** 2026-05-17
**Worktree:** `.worktrees/feat-pr-f-inngest-trigger-layer` (commit `9095788f`)
**Draft PR:** [#3940](https://github.com/jikig-ai/soleur/pull/3940)
**Parent epic:** [#3244](https://github.com/jikig-ai/soleur/issues/3244) — *Command Center server-side agentic runtime*
**Parent plan:** `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` (Increment 3, lines 613–657)

## Scope of this brainstorm

The parent plan's **Increment 3** is **PR-F**. The plan was already deepened on 2026-05-05 with Inngest specifics (CEL concurrency, `event.v` schema-version envelope, signature-verification, `AbortSignal` for max-turn-duration, $75/mo pricing correction, 3-tier policy collapse, atomic SQL kill-switch). This is therefore a **focused refresh**, not a fresh design — it carves out Increment 3 as PR-F's scope, captures drift since 2026-05-05, and locks the one open architectural axis (deployment substrate).

## What We're Building

PR-F adds Inngest as the durable trigger substrate on top of merged PR-A→E (user-scoped Supabase JWT mint, BYOK lease + `audit_byok_use` writer sweep, JWT deny-list `is_jti_denied` consumer, RLS attachments). The slice ships:

- **Inngest substrate** — `inngest@^3` self-hosted alongside the existing Hetzner Node process. `/api/inngest/route.ts` + `server/inngest/client.ts` + `server/inngest/functions/*.ts`. Signature-verification mandatory at startup. Founder identity carried in `event.data.founderId` (v3 has no wildcard event names).
- **Stripe `invoice.payment_failed` → CFO** — replaces the existing no-op log at `apps/web-platform/app/api/webhooks/stripe/route.ts:415` with `inngest.send({ name: "finance.payment_failed", id: \`stripe-${event.id}\`, v: "1", data: { founderId, ... } })`. CFO function mints JWT inside each `step.run`, opens BYOK lease inside each step, drafts a customer response saved as `messages` row (`tier: external_brand_critical, status: draft`), logs the expense.
- **Today section on `/dashboard`** — single-source MVP (Stripe drafts only). Direct Supabase query in the existing `page.tsx`; one `today-card.tsx` client component for the action buttons. GitHub-source + KB-drift-source deferred to follow-up issues.
- **Trust-tier policy** — 3-tier MVP (`auto | draft_one_click | approve_every_time`) keyed in `server/tool-tiers.ts` `ACTION_CLASS_DEFAULTS` map. No new Postgres table. Verify-external-state contract: 2s timeout per source; block-and-alert on timeout; no silent proceed-on-error.
- **Per-tenant cost kill-switch** — 2 columns on `public.users` (`runtime_paused_at`, `runtime_cost_cap_cents` default 2000 = $20/hr). Atomic SQL function `record_byok_use_and_check_cap(...)` — single statement, no plpgsql, `SECURITY DEFINER` with `search_path = public, pg_temp`.
- **ADR** — `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` → `knowledge-base/engineering/adrs/<n>-inngest-as-durable-trigger-layer.md`. Records rejected alternatives (LangGraph, Bedrock AgentCore, Cloudflare DO + LISTEN/NOTIFY) AND the self-hosted-on-Hetzner decision with re-evaluation criteria.

## Why This Approach

PR-F merges the runtime that PR-A→E spent five increments hardening. The architectural choices were locked in the 2026-05-05 brainstorm + deepened plan; this refresh confirms they still hold post-PR-E and adds three deltas (substrate decision, ALS-inside-step-run refinement, drift on call sites + dashboard component shape).

The deployment substrate is now decided: **self-hosted Inngest dev server on Hetzner** (operator answered 2026-05-17). Rationale: PR-B→E spent five PRs keeping founder-tagged data off external substrates; routing Stripe customer email + draft text through Inngest Cloud for alpha velocity inverts that ladder. CTO + CLO concurred — no new sub-processor, no DPA, no Article 30 amendment cycle, no Privacy/DPD/GDPR sub-processor refresh. COO's operator-of-one bandwidth concern is real but smaller than the legal + tenant-isolation surface for an EU-only operator with a `single-user incident` brand-survival threshold.

## Key Decisions

### Carry-forward from parent plan (Increment 3)

| # | Decision | Source |
|---|----------|--------|
| K1 | Inngest substrate is `inngest@^3`. Each function names exactly one event; founder identity in `event.data.founderId` (v3 has no wildcard event names). | parent plan §3.1, line 622 |
| K2 | Concurrency primitive: CEL expression `event.data.founderId + ":finance.payment_failed"`, `scope: "fn"`, `limit: 1` + global `scope: "account"`, `limit: 50`. NOT a JS template string. | parent plan §3.1, lines 623–629 |
| K3 | Schema-version on **`event.v`** envelope field (NOT inside `data`). Worker reads `event.v`. Hand-rolled band-tolerance: `MIN_SUPPORTED = MAX_SUPPORTED = 1` at PR-F merge; `if v > MAX throw; if v < MIN deadletter; else upcast`. | parent plan §3.1, line 632 + `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary` |
| K4 | `cancelOn` does NOT interrupt in-flight `step.run`. Max-turn-duration enforced via cooperative `AbortSignal` plumbed into the Anthropic SDK call inside each step. | parent plan §3.1, line 637 |
| K5 | Idempotency key namespaced: `id: \`stripe-${stripe_event.id}\`` (24h global window) + DB-level `processed_stripe_events` uniqueness backstop past 24h. | parent plan §3.1, line 638 |
| K6 | Pricing reality: Inngest Pro is **$75/mo, NOT $25**. Free tier covers alpha; flip-trigger documented in expense ledger. (Moot for PR-F under self-hosted; carried for context.) | parent plan §3.1, line 639 |
| K7 | `step.sleepUntil` / `step.waitForEvent` are FREE; watchdog patterns cheap. | parent plan §3.1, line 640 |
| K8 | Inngest webhook signature-verification REQUIRED at startup. Missing key = throw at startup, NOT log-and-continue. Replay-window 5 min. | parent plan §3.1, lines 642–643 |
| K9 | Today section is **single-source MVP — Stripe only**. GitHub + KB-drift deferred. No new API route, no aggregator module. Direct Supabase query in `page.tsx`. | parent plan §3.3, line 662 |
| K10 | Trust-tier collapsed to **3 tiers** (`auto | draft_one_click | approve_every_time`). Verify-external-state contract: 2s timeout, block-and-alert, NO silent proceed. | parent plan §3.4, lines 671–688 |
| K11 | Cost kill-switch: 2 columns on `public.users`, NO new table. Atomic SQL function `record_byok_use_and_check_cap(...)` — single statement, `SECURITY DEFINER` with `search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`). $20/hr default cap. | parent plan §3.5, lines 692–728 |

### New decisions for PR-F (deltas this brainstorm introduces)

| # | Decision | Why |
|---|----------|-----|
| K12 | **Self-hosted Inngest dev server on Hetzner.** | Operator-confirmed 2026-05-17. Keeps EU-only tenant-isolation posture; no new sub-processor; no DPA/Article 30 cycle. ADR records re-evaluation criteria (concurrency cap pressure OR third hosted founder onboarded → reassess Cloud Hobby). |
| K13 | **Open `runWithByokLease` INSIDE each `step.run` that calls the Anthropic SDK**, NOT at the Inngest function entry. | `AsyncLocalStorage` at `byok-lease.ts:115` does NOT survive Inngest step-replay boundaries; the sync escape check at `byok-lease.ts:133–139` will throw `ByokLeaseError("escape")` and the only safe answer is fail-closed re-entry per step. Parent plan §3.1 line 644 said "each Inngest function runs under runWithByokLease" — this brainstorm refines that to per-step. |
| K14 | **Move ZERO cron workflows in PR-F.** | Parent plan TR9 says "cron lives in Inngest, not GH Actions" as a *destination*; CTO + COO converge that PR-F should not bundle the migration. 38 cron workflows classified: only ~14 group-(c) agent loops are eventual TR9 scope; even those move per-workflow in follow-up issues. PR-F's review surface stays bounded. |
| K15 | **Trust-tier gate ships IN PR-F.** | The Stripe→CFO E2E flow drafts a customer-class action (`external_brand_critical`); shipping without the gate normalizes "no send button = the gate," which is exactly the wrong-action vector the operator flagged. Parent plan §3.4 already specifies the 3-tier MVP — confirm in scope. |
| K16 | **`SOLEUR_FR5_ENABLED` env-flag, default `false`** until on-call rotation is wired through Better Stack Incidents and the FR5 trigger has been smoke-tested with synthetic Stripe events. COO addition; operator confirms by merging spec. |
| K17 | **Writer-sweep CI sentinel covers the new directory automatically** (`apps/web-platform/test/server/byok-audit-writer-sweep.test.ts:73`, glob `server/**/*.ts`) but **must be extended with a negative-case fixture** that asserts a refactored wrapper (e.g., `withByokSession`) is caught. Helper wrappers without literal `runWithByokLease(` bypass the regex (`/\brunWithByokLease\s*\(/`). | `hr-write-boundary-sentinel-sweep-all-write-sites` + `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose`. |
| K18 | **`disclaims warranty for runtime cost`** disclosure surfaces in any user-facing Today-card surfacing a CFO autonomous draft, per `hr-autonomous-loop-skill-api-budget-disclosure`. | The Stripe→CFO trigger consumes the founder's BYOK Anthropic budget unattended; disclosure is load-bearing, not cosmetic. |
| K19 | **ADR written BEFORE PR-F code lands** (status `proposed`), flipped to `accepted` on merge. | Rejected-alternatives lock holds the design; writing the ADR post-hoc invites self-justification. CTO recommendation. |

## Open Questions (for plan-time)

1. **Stripe event source for the merge.** Stub Stripe events from a fixture for the FR5 merge so PR-F doesn't entangle the founder's own billing system stability, then flip to operator's-own-Stripe behind `SOLEUR_FR5_ENABLED` the day after merge? Or wire operator's-own-Stripe (test mode) directly? Plan-time decision; CPO recommendation is stub-then-flip.
2. **Dashboard route component shape.** Repo research surfaced that `apps/web-platform/app/(dashboard)/dashboard/page.tsx` is currently a **client component** (`"use client"` at line 1) — parent plan §3.3 line 664 wrote "Page is a server component already." Plan-time: either convert to server component for the new Today fetch (incremental refactor; risk surface) or co-locate the Today fetch in a server-side data loader wrapper (smaller diff). The parent plan's direct-Supabase-in-page.tsx prescription assumes server-component; resolve at plan stage.
3. **PR-G scope.** CPO recommends PR-F is alpha-internal-only (operator + 1 dogfood founder); cohort exposure needs PR-G (scope-grant UX, audit-log viewer, onboarding for the runtime surface). PR-G is NOT in PR-F's scope, but should be filed as a follow-up issue at brainstorm close so the cohort-onboarding handoff doesn't drift.
4. **Article 30 + DPD + sub-processor list updates.** Self-hosted Inngest avoids the sub-processor disclosure cycle, BUT the runtime data-flow diagram still changes (Stripe webhook → outbox → Inngest scheduler → CFO leader). CLO indicated Article 30 amendment is "cheap to do now, expensive to retrofit under inquiry." Plan-time: minor amendment to Article 30 register + DPD covering the new processing activity, even though no new sub-processor is added.
5. **Stripe webhook outbox pattern.** COO recommended a `webhook_inbox` (`stripe_event_id` unique) + drainer pattern so Stripe's retry budget doesn't couple to Inngest uptime; parent plan §3.2 reuses the existing `processed_stripe_events` dedup. Plan-time: confirm the dedup pattern is sufficient OR adopt the outbox as a follow-up issue.

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from PR-A→E; operator re-affirmed 2026-05-17, selected ALL of cross-tenant + BYOK + wrong-action + billing-surprise).

**Vectors:**

| Vector | Worst-case user experience | Load-bearing invariant |
|--------|----------------------------|------------------------|
| Cross-tenant data leak | Inngest step runs as Founder A but reads Founder B's data (e.g., wrong `founderId` in event payload, JWT minted for wrong founder) | Mint JWT INSIDE each `step.run` via `getFreshTenantClient(event.data.founderId)`; never pass JWTs across step boundaries cached in `event.data`. The `is_jti_denied` consumer at `apps/web-platform/lib/supabase/tenant.ts:341` fires automatically on every fresh-client call. |
| BYOK credential leak | A worker re-entering a serialized `step.run` falls back to a global default key when the per-invocation lease is missing | Open `runWithByokLease` INSIDE each step (K13). ALS sync-escape check at `byok-lease.ts:133–139` is the fail-closed primitive. Plaintext NEVER via `process.env` (per `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`). |
| Wrong-action while founder sleeps | CFO function auto-sends a customer email/refund without operator review | Trust-tier gate enforced in PR-F (K15). `external_brand_critical` class = `draft_one_click` only; verify-external-state contract blocks on stale/mismatched Stripe state (K10). "Drafts everywhere, sends nowhere" recorded as ADR invariant. |
| Billing surprise / cost runaway | Inngest event loop or autonomous fan-out spends BYOK Anthropic tokens uncapped | Atomic SQL kill-switch `record_byok_use_and_check_cap(...)` (K11). $20/hr default per-tenant. `runtime_paused_at` flips on threshold breach. `disclaims warranty for runtime cost` disclosure on every Today-card surface (K18). |

**Plan-time gates:**

- `user-impact-reviewer` MUST sign off (operator confirmed `single-user incident` threshold).
- preflight Check 6 fires on `apps/web-platform/server/**`, `apps/web-platform/app/api/inngest/**`, `apps/web-platform/app/api/webhooks/stripe/**`, `apps/web-platform/supabase/migrations/**`, BYOK custody surfaces.
- `/soleur:gdpr-gate` invoked at plan Phase 2.7 and work Phase 2 exit (`hr-gdpr-gate-on-regulated-data-surfaces` — touches PII, auth, API routes, regulated data).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

Triad spawned mandatory (`USER_BRAND_CRITICAL=true`): CPO + CLO + CTO. COO added by lane=cross-domain (Inngest cost + cron migration + on-call axis). Sales, Finance, Marketing, Support not spawned (signal not orthogonal to scope — closed-alpha, no external surface, no pipeline impact, no support ops yet).

### Engineering (CTO)

**Summary:** Three production `runWithByokLease(` call sites (`agent-runner.ts:863`, `agent-runner.ts:2363`, `cc-dispatcher.ts:883`) plus the definition at `byok-lease.ts:213`. Inngest absent from `apps/web-platform/package.json` — greenfield install. ALS sync-escape check at `byok-lease.ts:133–139` is the load-bearing fail-closed primitive — every `step.run` must re-establish the lease (K13). Concurrency via Inngest singleton run keys (K2). ADR before code (K19). Sentinel sweep extends to `server/inngest/**` automatically; the regex narrowness is the residual risk (K17).

### Product (CPO)

**Summary:** Six prior slices shipped without external-user contact; PR-F is the seventh. Minimum shippable shape is **substrate + Stripe→CFO trigger + a `/dashboard` list view + a deny-by-default action-class table** — gated to operator + 1 dogfood founder. Cohort exposure requires PR-G (scope-grant UX, audit-log viewer, onboarding). The list-view-in-PR-F decision matches parent plan §3.3.

### Legal (CLO)

**Summary:** Self-hosted Inngest avoids the sub-processor disclosure cycle entirely. Article 30 register amendment is still recommended (cheap now, expensive under inquiry). PR-E audit-writer carry-forward holds via per-file CI sentinel; PR-F must add a negative-case fixture (K17). "Drafts everywhere, sends nowhere" must be recorded as an ADR invariant — the moment any class auto-sends, Art. 22(3) right-to-human-review notice obligations attach. Stripe webhook payload minimization rule documented at the adapter (hash customer_email; drop payment_method details; keep only what CFO needs).

### Operations (COO)

**Summary:** Critical pricing correction — Inngest Pro is **$75/mo, not $20** (umbrella spec wrong; carry to expense ledger). Hobby tier caps at 5 concurrent steps + 24h trace retention — concurrency cap throttles before execution cap at ~30 founders. **Move zero cron workflows in PR-F** (38 classified; ~14 group-(c) agent loops are eventual TR9 scope, migrated per-workflow in follow-ups). On-call MUST be live before FR5 goes hot — Better Stack Incidents free tier suffices for alpha. `SOLEUR_FR5_ENABLED` default false (K16). Doppler `dev` + `prd` Inngest signing/event keys distinct per env (`hr-dev-prd-distinct-supabase-projects` pattern carries to Inngest).

## Capability Gaps

None blocking PR-F. The `runtime-architect` agent named as a capability gap in the parent brainstorm (line 94 of `2026-05-05-command-center-runtime-brainstorm.md`) is NOT a PR-F prereq — the architectural decisions are captured in the parent plan + the PR-F ADR (K19). Defer agent creation to a follow-up; file as scope-out per `wg-when-deferring-a-capability-create-a`.

**Evidence (per skill rule on capability-gap evidence):**

- `grep -rEn 'runWithByokLease\s*\(' apps/web-platform/server/` → 3 production sites confirmed (file:line in Engineering section).
- `grep -l '"inngest"\|@inngest' apps/web-platform/package.json` → no match; Inngest is greenfield.
- `ls apps/web-platform/app/api/inngest/` → not present (Next.js route file does not exist; PR-F creates).
- `grep -n 'invoice.payment_failed' apps/web-platform/app/api/webhooks/stripe/route.ts` → handled as no-op log at line 415 today; PR-F replaces with `inngest.send`.
- `ls plugins/soleur/agents/engineering/research/ | grep -i runtime-architect` → not present (deferred, not blocking).

## Deferred to follow-up issues

- GitHub-source and KB-drift-source Today cards (parent plan §3.3 single-source MVP carve-out).
- Cron migration per workflow (group-(c) agent loops — ~14 workflows; one issue per migrating workflow or one umbrella).
- 5-tier trust policy refactor (PR-F ships 3-tier MVP per parent plan §3.4; 5-tier deferred until a second background trigger lands).
- `runtime-architect` agent (parent brainstorm capability gap; not a PR-F prereq).
- PR-G: scope-grant UX + audit-log viewer + cohort onboarding (CPO recommendation; alpha-cohort exposure prerequisite).
- Webhook outbox decoupling (COO recommendation; parent plan reuses `processed_stripe_events` dedup — re-evaluate post-PR-F if Stripe retry pressure surfaces).

## References

- Parent plan: `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md`, lines 613–728 (Increment 3 — Daily Priorities, Inngest, Stripe Trigger, Trust-Tier, Cost Kill-Switch, ADR).
- Parent spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md` (FR4–FR8, TR1, TR6, TR9).
- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-05-command-center-runtime-brainstorm.md`.
- Sibling shipped: PR-A #3240, PR-B #3395, PR-C #3854, PR-D #3883, PR-E #3887 (#3922 follow-up).
- AGENTS.md rules touched: `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-dev-prd-distinct-supabase-projects`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-weigh-every-decision-against-target-user-impact`, `hr-autonomous-loop-skill-api-budget-disclosure`, `hr-new-skills-agents-or-user-facing`, `cq-pg-security-definer-search-path-pin-pg-temp`, `cq-nextjs-route-files-http-only-exports`, `cq-union-widening-grep-three-patterns`.
- Learnings carried forward: `2026-03-13-ralph-loop-idle-detection-and-repetition`, `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs`, `2026-03-23-action-completion-workflow-gap`, `2026-03-20-claude-code-action-max-turns-budget`, `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`, `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose`, `2026-05-16-pr-e-autonomous-pipeline-cross-reconcile-and-concur-dissent`.
