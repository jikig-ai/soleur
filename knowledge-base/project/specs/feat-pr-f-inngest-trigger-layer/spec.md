---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_plan: knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
parent_spec: knowledge-base/project/specs/feat-agent-runtime-platform/spec.md
type: sub-increment
---

# Feature: PR-F Inngest Trigger Layer

**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
**Parent epic:** [#3244](https://github.com/jikig-ai/soleur/issues/3244) — *Command Center server-side agentic runtime*
**Parent plan:** `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` (Increment 3, lines 613–728)
**Parent spec:** `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md` (FR4–FR8, TR1, TR6, TR9)
**Predecessors merged:** PR-A [#3240], PR-B [#3395], PR-C [#3854], PR-D [#3883], PR-E [#3887/#3922]
**Worktree:** `.worktrees/feat-pr-f-inngest-trigger-layer` (commit `9095788f`)
**Branch:** `feat-pr-f-inngest-trigger-layer`
**Draft PR:** [#3940](https://github.com/jikig-ai/soleur/pull/3940)
**Brand-survival threshold:** `single-user incident`

## Problem Statement

PR-A→E shipped the security/isolation hardening required to safely run autonomous agents on behalf of multiple founders: user-scoped Supabase JWT minting (PR-B), `audit_byok_use` writer at every BYOK SDK call path (PR-E), `is_jti_denied` JWT-mint consumer (PR-E), and RLS-bound attachments (PR-D). The runtime is now safe to run *synchronous* workloads on behalf of a logged-in founder — but the parent epic's promise is *autonomous* leaders that react to inbound events while the founder sleeps.

Without a durable trigger substrate, three roadmap goals stay unbuilt:

1. **Inbound-event-to-leader pipelines.** Stripe failed-payment, GitHub issue created, KB drift detected, etc. have no executor.
2. **Cross-domain priority arbitration moat.** The Daily Priorities "Today" surface has no producer of cards to surface.
3. **The architectural decision lock.** Inngest was named in the parent plan but never ADR'd; any future "should we use X instead" conversation lacks a rejected-alternatives record.

PR-F is the slice that closes those gaps for the alpha-internal cohort (operator + 1 dogfood founder). Cohort exposure is gated to a follow-up PR-G (scope-grant UX, audit-log viewer, onboarding).

## Goals

- Land Inngest as the durable trigger substrate, **self-hosted alongside the existing Hetzner Node process** (no new sub-processor; no DPA/Article 30 disclosure cycle for the alpha).
- Ship one end-to-end inbound-event-to-leader trigger: Stripe `invoice.payment_failed` → `inngest.send({ name: "finance.payment_failed", ... })` → CFO leader → draft customer response + expense log → Today card on `/dashboard`.
- Ship a single-source MVP of the Daily Priorities Today section (Stripe drafts only; GitHub + KB-drift deferred to follow-up issues).
- Ship the 3-tier trust policy gate (`auto | draft_one_click | approve_every_time`) so external-class actions cannot auto-send without operator review.
- Ship per-tenant cost attribution + atomic kill-switch ($20/hr default, atomic SQL function on `audit_byok_use`).
- Capture the architectural decision as an ADR with rejected alternatives.
- Maintain the PR-E `audit_byok_use` writer-sweep CI invariant — every new SDK call site inside an Inngest function is automatically swept; helper-wrapper bypass risk is closed by adding a negative-case fixture.

## Non-Goals

- **Not** Inngest Cloud. Self-hosted dev server on Hetzner only; Cloud re-evaluated at concurrency-cap pressure OR third hosted founder onboarded (criteria recorded in ADR).
- **Not** a cron migration. Zero GH Actions cron workflows move in PR-F; the parent plan's TR9 statement is a *destination*, not a PR-F deliverable. Per-workflow migration filed as follow-up issues.
- **Not** the 5-tier trust policy. 3-tier MVP only. 5-tier refactor deferred until a second background trigger lands.
- **Not** GitHub-source or KB-drift-source Today cards. Stripe-only MVP per parent plan §3.3 single-source carve-out.
- **Not** alpha-cohort exposure. PR-F ships with `SOLEUR_FR5_ENABLED=false` by default until on-call rotation is wired through Better Stack Incidents. Cohort onboarding is PR-G's scope.
- **Not** the `runtime-architect` agent. Capability gap noted in parent brainstorm; not a PR-F prereq.
- **Not** a per-tenant Grafana board. Inngest's own dashboard suffices for alpha; OTEL + Grafana Pro is a beta-gate, not PR-F-gate.
- **Not** WORM-grade audit storage hardening beyond what `audit_byok_use` already provides via Postgres append-only with hash-chain. CLO accepts pino for transport telemetry; decision/action events stay on `audit_byok_use`.

## Functional Requirements

### FR1 — Inngest substrate, self-hosted

Install `inngest@^3` as a dependency in `apps/web-platform/package.json` (regenerate both `bun.lock` and `package-lock.json` per `cq-before-pushing-package-json-changes`). Boot the Inngest dev server alongside the existing Node process on the Hetzner host. Add Next.js App Router route at `apps/web-platform/app/api/inngest/route.ts` exporting ONLY HTTP handlers from `serve()` per `cq-nextjs-route-files-http-only-exports`; function definitions live under `apps/web-platform/server/inngest/functions/`. Inngest client initialized at `apps/web-platform/server/inngest/client.ts`. Signature-verification is REQUIRED at startup — missing `INNGEST_SIGNING_KEY` throws at process boot (NOT log-and-continue); replay-window enforced at 5 minutes.

### FR2 — Stripe `invoice.payment_failed` → CFO E2E

Replace the no-op log at `apps/web-platform/app/api/webhooks/stripe/route.ts:415` with an `inngest.send` emit. The emit fires AFTER the existing `processed_stripe_events` dedup-insert (preserves 2026-04-22 idempotency contract). Event envelope:

```ts
{
  id: `stripe-${stripe_event.id}`,          // 24h global window
  name: "finance.payment_failed",            // canonical; founder identity NOT in event name
  v: "1",                                    // envelope-level schema version
  data: { founderId, domain: "finance", event: "finance.payment_failed", payload: { ... minimized ... } }
}
```

The CFO function `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`:

1. Reads `event.v`; if `v > MAX_SUPPORTED` throw `SchemaVersionError`; if `v < MIN_SUPPORTED` route to `step.run("deadletter", ...)`.
2. **Inside each `step.run` that touches tenant data or the SDK**: mints fresh founder JWT via `getFreshTenantClient(event.data.founderId)` (deny-list `is_jti_denied` consumer fires automatically at `apps/web-platform/lib/supabase/tenant.ts:341`), opens `runWithByokLease(event.data.founderId, ...)`.
3. Before drafting: re-fetches the live Stripe charge state (per `domain-leader-false-status-assertions-20260323`) with a 2s timeout. On timeout or state-mismatch: block-and-alert, no draft fires.
4. Drafts customer response (saved as `messages` row, `tier: external_brand_critical, status: draft`). Writes the expense log row.
5. Surfaces result as a Today card via the existing `messages` query (FR3).

Stripe webhook payload is **minimized at the adapter** before emit: hash `customer_email` for routing; drop `payment_method` details; retain only `amount`, `currency`, `failure_code`, `invoice_id` per Art. 5(1)(c) data minimization.

### FR3 — Today section on `/dashboard` (single-source MVP)

Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx` to add a "Today" section above the existing surfaces. **Plan-time decision required** — `page.tsx` is currently a client component (`"use client"` at line 1), but parent plan §3.3 prescribes a server-component fetch. Resolve at plan stage: either (a) convert to server component for the new Today fetch, or (b) co-locate the Today fetch in a server-side data loader. Direct query under `tenantClient`:

```ts
tenantClient.from('messages')
  .select('id, draft_preview, source, urgency, created_at')
  .eq('user_id', auth.uid())
  .eq('status', 'draft')
  .eq('tier', 'external_brand_critical')
  .order('created_at', { ascending: false })
  .limit(20)
```

RLS handles tenant isolation. New component `apps/web-platform/components/dashboard/today-card.tsx` (client component) renders one card with action buttons: **Send / Edit / Discard**. "Send" routes through the FR4 trust-tier gate. Today card surface MUST display the `disclaims warranty for runtime cost` disclosure per `hr-autonomous-loop-skill-api-budget-disclosure`.

### FR4 — Trust-tier policy (3-tier MVP)

Extend `apps/web-platform/server/tool-tiers.ts` with an `ACTION_CLASS_DEFAULTS` map keyed independently from the existing per-tool tier. New type in `apps/web-platform/lib/types.ts`:

```ts
type TrustTier = "auto" | "draft_one_click" | "approve_every_time";
```

Action-class taxonomy:

| Class | Examples | Default tier |
|-------|----------|--------------|
| Read/research/draft | KB writes, plan writes, internal artifacts | `auto` |
| External-facing draft | Draft email, draft customer reply, draft tweet | `draft_one_click` |
| External-facing brand-critical / money / credentials | Publish blog, send customer message, charge, BYOK rotation, prod migration, lift-pause | `approve_every_time` (reuses `permission-callback.ts:599-700` review-gate UX) |

Storage in code (no Postgres table for MVP); per-founder override deferred. **Verify-external-state contract** (per Kieran K3 / parent plan §3.4 lines 683–688):

- Timeout: **2s per source**.
- On timeout: action does NOT fire; UI shows "Verifying [source] — try again shortly"; `reportSilentFallback(err, { feature: "trust-tier-verify", op: "<source>" })` mirrors to Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
- On state mismatch: action does NOT fire; UI shows "Stripe state has changed since this draft — review and re-issue"; stale draft auto-archived; new draft re-queued.
- NO silent proceed-on-error. NO silent proceed-on-stale.

### FR5 — Per-tenant cost attribution + kill-switch

Migration `apps/web-platform/supabase/migrations/0NN_runtime_cost_state.sql`:

```sql
alter table public.users
  add column if not exists runtime_paused_at timestamptz,
  add column if not exists runtime_cost_cap_cents int default 2000;  -- $20/hr default

create or replace function public.record_byok_use_and_check_cap(
  p_invocation_id uuid, p_founder_id uuid, p_agent_role text,
  p_token_count int, p_unit_cost_cents int
) returns table(cumulative_cents int, kill_tripped bool)
language sql security definer set search_path = public, pg_temp as $$
  -- atomic single-statement CTE chain; INSERT + SUM + conditional UPDATE on users
  -- (full body in parent plan §3.5 lines 704-728)
$$;
```

Atomic primitive: single SQL statement, NOT plpgsql, per `cq-pg-security-definer-search-path-pin-pg-temp`. Inngest function preamble calls `record_byok_use_and_check_cap` after each SDK turn; if `kill_tripped=true`, function aborts at next `step.run` boundary; `runtime_paused_at` blocks subsequent Inngest dispatches for that founder.

### FR6 — ADR capture (before code lands)

Run `/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` BEFORE PR-F's first non-scaffolding commit. Status: `proposed` until merge; flipped to `accepted` on merge. ADR records:

- **Chosen substrate:** Inngest self-hosted dev server on Hetzner.
- **Rejected alternatives:** LangGraph + custom (operationally heavy), Bedrock AgentCore (AWS lock, no EU residency parity), Cloudflare Durable Objects + LISTEN/NOTIFY (cannot host the Agent SDK long-running process), Inngest Cloud Hobby (5th sub-processor disclosure cycle conflicts with EU-only posture; re-evaluation criteria recorded).
- **Load-bearing invariants:** per-invocation user-scoped JWT minted INSIDE each `step.run`; per-`step.run` `runWithByokLease` (NOT once-at-function-entry — ALS does not survive step boundaries); singleton concurrency per `(founderId, domain, eventKey)`; signature-verification required at startup; "drafts everywhere, sends nowhere" — no auto-send class.
- **Closes:** the parent plan's reference to the runtime ADR. (Note: parent plan cites `Closes #2955`; #2955 is CLOSED already — ADR records the historical link for traceability without creating a new closing chain.)

### FR7 — Feature flag for FR2 trigger

Add `SOLEUR_FR5_ENABLED` env var (Doppler `dev` + `prd`), default `false`. The Stripe `invoice.payment_failed` branch reads this flag BEFORE `inngest.send`; when false, retains the existing log-and-continue behavior. Flips to `true` only after on-call rotation is wired (Better Stack Incidents, free tier) and synthetic Stripe events have smoke-tested the full E2E path on `prd`.

## Technical Requirements

### TR1 — Lease re-entry inside each `step.run`

Every `step.run("name", async () => { ... })` that calls the Anthropic SDK or touches tenant data MUST open its own `runWithByokLease(event.data.founderId, async (lease) => { ... })` scope. NEVER close over a `lease` from an outer step. NEVER pass a minted JWT or lease across step boundaries via `event.data` or step return values. The `AsyncLocalStorage` instance at `apps/web-platform/server/byok-lease.ts:115` does not survive across Inngest step replay; the sync escape check at `byok-lease.ts:133–139` will throw `ByokLeaseError("escape")` and fail-closed if drift occurs.

### TR2 — Concurrency CEL key

Each Inngest function declares:

```ts
concurrency: [
  { scope: "fn", key: 'event.data.founderId + ":" + "<event-name>"', limit: 1 },
  { scope: "account", key: '"agent-runtime"', limit: 50 },
]
```

CEL expression (NOT JS template string). Prevents ralph-loop pathology per `2026-03-13-ralph-loop-idle-detection-and-repetition`.

### TR3 — `AbortSignal` cooperative timeout

Per-`step.run`, the Anthropic SDK call receives an `AbortController.signal` whose timeout is `MAX_TURN_DURATION_MS` (default 90s). `cancelOn` declarations on the Inngest function are the outer envelope (cancellation propagates at step boundaries only); the inner `AbortSignal` is the cooperative inner-timeout primitive per parent plan §3.1 line 637 + `2026-03-20-claude-code-action-max-turns-budget`.

### TR4 — Writer-sweep CI invariant

`apps/web-platform/test/server/byok-audit-writer-sweep.test.ts:73` matches glob `server/**/*.ts` against regex `/\brunWithByokLease\s*\(/`. PR-F adds files under `server/inngest/functions/`; the existing sweep covers them automatically. **PR-F MUST add a negative-case fixture** asserting that a deliberately-stubbed wrapper without the literal `runWithByokLease(` call is caught at PR review (the regex narrowness is the residual risk per `2026-05-15-ci-sentinel-paren-safety-substring-match-against-canonical-prose`).

### TR5 — Doppler env shape

Add to Doppler `dev` AND `prd` configs (distinct keys per env, per `hr-dev-prd-distinct-supabase-projects` pattern):

- `INNGEST_SIGNING_KEY` — webhook signature verification key. Inngest dev server generates per-env.
- `INNGEST_EVENT_KEY` — event-send key.
- `SOLEUR_FR5_ENABLED` — feature flag, default `false` in both envs.
- `MAX_TURN_DURATION_MS` — optional override; default 90000.

Missing `INNGEST_SIGNING_KEY` MUST throw at startup, not log-and-continue.

### TR6 — `is_jti_denied` consumer parity

The Inngest function MUST NOT bypass `getFreshTenantClient` by caching JWTs across step boundaries. Each step that touches tenant data calls `getFreshTenantClient(event.data.founderId)` fresh; the `denyProbe` at `apps/web-platform/lib/supabase/tenant.ts:341` fires automatically. Tested via deny-list-fixture integration test that injects a deny-listed `jti` and asserts the step throws `RuntimeAuthError` before any data access.

### TR7 — Stripe webhook contract preservation

The existing `processed_stripe_events` dedup pattern at `apps/web-platform/app/api/webhooks/stripe/route.ts` (per migration 030 + learning `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern`) is RETAINED as the past-24h idempotency backstop. PR-F's `id: \`stripe-${stripe_event.id}\`` is the in-flight 24h Inngest-level dedup; both must hold.

### TR8 — Schema-version envelope discipline

`event.v` lives at the Inngest envelope, NOT inside `data`. Worker reads `event.v` first; band-tolerance check (`MIN_SUPPORTED = MAX_SUPPORTED = 1` at PR-F merge); upcast-or-deadletter discipline per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary`. Adding a v2 field later requires bumping `MAX_SUPPORTED` in a follow-up.

### TR9 — Outbox / decoupling (deferred decision)

Parent plan reuses `processed_stripe_events` dedup; COO recommended a `webhook_inbox` + drainer to decouple Stripe's retry budget from Inngest uptime. **Plan-time decision** — defer to a follow-up issue unless smoke-testing surfaces Stripe-retry pressure during alpha.

## Out of MVP scope

- GitHub-source and KB-drift-source Today cards (parent plan §3.3 single-source carve-out).
- Per-workflow cron migration to Inngest (~14 group-(c) agent loops; one issue per migrating workflow).
- 5-tier trust policy refactor (`auto_with_digest`, `per_command_ack`).
- `runtime-architect` agent.
- PR-G: scope-grant UX, audit-log viewer, cohort onboarding.
- Webhook outbox pattern (TR9 deferred — revisit post-alpha if Stripe retry pressure appears).
- Per-tenant Grafana board + OTEL.
- WORM audit storage hardening beyond append-only Postgres + hash-chain.

## User-Brand Impact

Threshold: `single-user incident`. Operator re-affirmed 2026-05-17 with ALL of cross-tenant + BYOK + wrong-action + billing-surprise.

**Vectors and load-bearing invariants:**

| Vector | Invariant |
|--------|-----------|
| Cross-tenant data leak | JWT minted INSIDE each `step.run` via `getFreshTenantClient(event.data.founderId)`; never passed across step boundaries cached in `event.data`. |
| BYOK credential leak | `runWithByokLease` opened INSIDE each `step.run` (TR1); ALS sync-escape check fails closed; plaintext never via `process.env`. |
| Wrong-action while founder sleeps | Trust-tier gate enforced (FR4); `external_brand_critical` = `draft_one_click` only; verify-external-state contract blocks on stale/mismatched Stripe state. "Drafts everywhere, sends nowhere" ADR invariant. |
| Billing surprise / cost runaway | Atomic SQL kill-switch (FR5); `$20/hr` default cap; `runtime_paused_at` blocks subsequent dispatch; `disclaims warranty for runtime cost` disclosure on every Today-card. |

**Plan-time gates:**

- `user-impact-reviewer` MUST sign off.
- preflight Check 6 fires on `apps/web-platform/server/**`, `apps/web-platform/app/api/inngest/**`, `apps/web-platform/app/api/webhooks/stripe/**`, `apps/web-platform/supabase/migrations/**`.
- `/soleur:gdpr-gate` invoked at plan Phase 2.7 and work Phase 2 exit.
- Article 30 register + DPD light-touch amendment for the new processing activity (no new sub-processor under self-hosted).

## Acceptance Criteria (high-level)

- [ ] `inngest@^3` added to `apps/web-platform/package.json`; both lockfiles regenerated.
- [ ] `/api/inngest/route.ts` exists; throws at startup if `INNGEST_SIGNING_KEY` unset.
- [ ] `cfo-on-payment-failed.ts` Inngest function exists; opens `runWithByokLease` INSIDE each `step.run`.
- [ ] Stripe `invoice.payment_failed` branch emits `inngest.send` AFTER dedup-insert, gated on `SOLEUR_FR5_ENABLED`.
- [ ] Stripe webhook payload minimized at the adapter (no `customer_email` cleartext beyond hash; no `payment_method` details).
- [ ] `/dashboard` Today section renders Stripe-source draft cards via direct `tenantClient` query.
- [ ] `today-card.tsx` displays the `disclaims warranty for runtime cost` disclosure.
- [ ] `TrustTier` type added; `ACTION_CLASS_DEFAULTS` map seeded; verify-external-state 2s-timeout contract enforced.
- [ ] Migration `0NN_runtime_cost_state.sql` shipped; `record_byok_use_and_check_cap` atomic; `cq-pg-security-definer-search-path-pin-pg-temp` honored.
- [ ] ADR written at `proposed`, flipped to `accepted` on merge.
- [ ] Writer-sweep negative-case fixture added.
- [ ] Article 30 register + DPD amendments shipped (no new sub-processor, but processing activity added).
- [ ] `user-impact-reviewer` sign-off captured at review time.

## References

See brainstorm `## References` section for the full list of AGENTS.md rules and learnings carried forward.
