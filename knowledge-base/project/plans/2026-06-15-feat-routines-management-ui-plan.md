---
title: "feat: Inngest Routines management UI + Concierge delegation"
type: feat
date: 2026-06-15
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-routines-management
pr: "#5342"
issues: ["#5345", "#5346"]
brainstorm: knowledge-base/project/brainstorms/2026-06-15-routines-management-brainstorm.md
spec: knowledge-base/project/specs/feat-routines-management/spec.md
wireframes: knowledge-base/product/design/routines/routines-management.pen
---

# ✨ Plan: Inngest Routines Management UI + Concierge Delegation

## Overview

Give the operator a web surface to **see and operate** the 42 Inngest cron routines that run the
autonomous company (`server/inngest/cron-manifest.ts` → `EXPECTED_CRON_FUNCTIONS`), and a Concierge
chat to **author** routines. Today routines are visible only in code and triggerable only via the
`soleur:trigger-cron` CLI.

**Decomposition (two PRs behind one feature surface, CPO/CTO consensus):**

- **PR-1 (this plan, implementable now):** Routines tab (grouped by domain) + Recent Runs history +
  debug Run-now. Reuses existing backend primitives; adds a routine-metadata sidecar, a durable
  run-log, an Inngest run-log middleware, a shared run chokepoint, three session routes, and three
  agent MCP tools.
- **PR-2 (outlined, gated on #5346):** Concierge authoring chat (draft → dry-run test+verify →
  Open PR). Depends on a net-new agent capability — opening a `cron-*.ts` PR with all five lockstep
  registry edits — tracked in #5346. PR-2 gets its own plan once #5346 is scoped.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "show full execution history" | `lib/inngest/list-runs.ts:47-107` is hardwired to `finance.payment_failed` + founderId CEL; Inngest `/v1` is loopback-gated (`127.0.0.1:8288`) + retention-bounded | Durable Supabase run-log is the source of truth (FR6); `/v1` is at most enrichment (TR7). Do NOT reuse `list-runs.ts` for cron history. |
| "Run now" needs a new endpoint | `POST /api/internal/trigger-cron` (`route.ts:1-139`) + `manual-trigger-allowlist.ts` already exist (secret-gated) | Keep the secret-gated internal route for CLI/agent-secret use. Add a **session-gated** `/api/dashboard/routines/run` that calls a shared `runRoutine()` chokepoint (enforces protected-policy + attribution). No bypass route. |
| routine metadata (domain/owner) | `EXPECTED_CRON_FUNCTIONS` is a bare `string[]`, drift-guarded by `function-registry-count.test.ts:135` (`toBe(56)`) and the manifest==files set-equality | New **sidecar map** `ROUTINE_METADATA` in a separate client-free leaf + parity test `keys===EXPECTED_CRON_FUNCTIONS`. Do NOT change the array element type or add per-function exports (preserve the #4734 client-free leaf). |
| run-log written per routine | Inngest middleware `sentry-correlation.ts:55-156` already wraps every function run | Add a sibling middleware `run-log.ts` — central write, **zero** edits to the 42 `cron-*.ts` files, no registry-count impact. |
| WORM audit ledger | `037_audit_byok_use.sql` (no-mutate trigger + SECURITY DEFINER RPC) + `051_action_sends.sql` (owner-insert RLS + `session_replication_role='replica'` bypass) | Model `routine_runs` + `write_routine_run()` RPC on these. Migration `104` (latest is `103`). |

## User-Brand Impact

**If this lands broken, the user experiences:** the Routines tab shows stale/incorrect run status (a
failed `cfo-on-payment-failed` looks "completed"), or Run-now silently fires a production routine
twice — the operator can't trust what the autonomous company is doing.

**If this leaks, the user's data/workflow is exposed via:** the run-log stores `actor_id` (operator
UUID) and per-run metadata; an off-schedule or agent-initiated run of a production routine
(payment handling, content publishing, legal audit) takes a real action in the operator's name with
no human in the loop, or an audit record misattributes an agent action to the operator.

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true` (carried from the
brainstorm `## User-Brand Impact`; CPO reviewed at brainstorm Phase 0.5). `user-impact-reviewer` runs
at PR-review time.

---

## PR-1 — Routines visibility + debug Run-now

### Architecture

```
                       ┌─────────────────────────────────────────┐
  Operator (browser) ──┤ GET /api/dashboard/routines              │── sidecar metadata
                       │ GET /api/dashboard/routines/runs         │── routine_runs (paginated)
                       │ POST /api/dashboard/routines/run ────────┼──┐
                       └─────────────────────────────────────────┘  │
  Agent (MCP) ── routines_list / routine_runs_list / routine_run ───┤
                                                                     ▼
                                              server/routines/run-routine.ts  (chokepoint:
                                                policy check + attribution + dispatch)
                                                                     │ inngest.send(cron/X.manual-trigger)
                                                                     ▼
                                              Inngest runtime ── run-log middleware
                                                                     │ write_routine_run() RPC
                                                                     ▼
                                                          Supabase routine_runs (WORM)
```

### Phase 1 — Data model

**1.1 Routine metadata sidecar.** New client-free leaf `server/inngest/routine-metadata.ts`:

```ts
// Client-free leaf (mirrors cron-manifest.ts #4734 constraint — imports NOTHING from client).
export interface RoutineMeta {
  domain: string;          // "Onboarding" | "Engineering" | ...
  ownerRole: string;       // "COO" | "CTO" | "CMO" | "CLO" | "CFO" | ...
  cron: string;            // raw expr, e.g. "0 4 * * *" (single source for display)
  scheduleLabel: string;   // human, e.g. "Daily 04:00 UTC"
  manualTrigger: "allowed" | "confirm" | "denied"; // deny-by-default policy (CLO)
}
export const ROUTINE_METADATA: Record<string, RoutineMeta> = { /* 42 entries */ };
```

- `manualTrigger: "confirm"` for the protected subset (financial/egress/deletion): `cfo-on-payment-failed`,
  `cron-content-publisher`, `cron-legal-audit`, `cron-github-app-drift-guard`, plus any cron whose
  handler sends email / posts externally / deletes data. `"denied"` reserved for any routine that must
  never be manually fired (decide per-routine during implementation; default `"allowed"`).
- **Parity test** (`test/server/inngest/routine-metadata-parity.test.ts`): assert
  `Object.keys(ROUTINE_METADATA).sort()` deep-equals `[...EXPECTED_CRON_FUNCTIONS].sort()`. Adding/
  removing a cron forces a sidecar edit — same drift-guard discipline as the manifest.
- **Cron-drift test** (same file): for each fnId, assert `ROUTINE_METADATA[fnId].cron` equals the
  `{ cron: "..." }` literal in `server/inngest/functions/<fnId>.ts` (grep the literal). Keeps the
  displayed schedule honest. *(Flag for deepen-plan: confirm a robust extraction for the cron literal.)*

**1.2 Durable run-log.** Migration `104_routine_runs.sql` (model on `037`/`051`):

```sql
create table routine_runs (
  id uuid primary key default gen_random_uuid(),
  routine_id text not null,           -- fnId; immutable
  run_id text,                        -- Inngest run id (nullable; immutable)
  status text not null,               -- 'running' | 'completed' | 'failed'
  trigger_source text not null,       -- 'scheduled' | 'manual' | 'agent'; immutable
  actor_class text not null,          -- 'system' | 'human' | 'agent'; immutable
  actor_id uuid references users(id), -- operator (nullable for system); immutable
  delegating_principal uuid references users(id), -- for agent runs; immutable
  started_at timestamptz not null default now(),  -- immutable
  ended_at timestamptz,               -- lifecycle (settable once)
  duration_ms integer,                -- lifecycle
  error_summary text                  -- lifecycle (failed runs)
);
-- RLS: owner/operator-select only; NO direct insert/update/delete policies (writes via RPC).
-- WORM no-mutate trigger on UPDATE/DELETE (037 pattern), with the lifecycle-update RPC bypassing
-- via SET LOCAL session_replication_role='replica' (051:224 pattern), transitioning ONLY
-- status/ended_at/duration_ms/error_summary and ONLY WHERE status='running'.
```

- Two SECURITY DEFINER RPCs (service-role grant, `SET search_path = public, pg_temp` per `037:13`):
  `start_routine_run(...)` (insert, status='running') and `finish_routine_run(run_pk, status, ...)`
  (one-way lifecycle transition). **Recommended simpler alternative for deepen-plan / data-integrity
  review:** terminal-only append (one `write_routine_run()` at completion, pure 037/051 WORM-reject,
  no lifecycle UPDATE) — "running" then shown via optimistic client state + optional `/v1` enrichment.
  Pick the simpler one unless in-flight durability is judged load-bearing. **This is the
  deepen-plan Phase 4.4 precedent-diff + data-integrity-guardian decision** (atomicity, double-fire,
  the running→terminal transition).
- No `CREATE INDEX CONCURRENTLY` (Supabase wraps each migration in a txn — `037:18`). Add a plain
  index on `(routine_id, started_at desc)` for last-run + Recent Runs queries.

**1.2.1 GDPR-gate findings (Phase 2.7 — fold into the migration):**
- **Art-6:** annotate the migration `-- LAWFUL_BASIS: legitimate_interest (operational audit of
  operator-/agent-triggered routine runs; single-operator tenant)`.
- **Art-5(1)(e):** record a retention decision in the migration header (default: indefinite-as-audit-log
  with rationale; alternative sweep precedent `103_github_events_retention_7day.sql`).
- **Art-17:** FKs to `users` on a WORM table cannot use `ON DELETE CASCADE`. Add an
  `anonymise_routine_runs()` SECURITY DEFINER RPC bypassing the no-mutate trigger via
  `SET LOCAL session_replication_role='replica'` (precedent `051:194-243`), **wired into the DSAR/erasure
  path in the same PR** (`GDPR-Art-17-caller` — a mandated RPC must have a live call-site), OR
  `ON DELETE SET NULL` on `actor_id`/`delegating_principal`. Decide at deepen-plan with CLO.
- **Art-9 (Suggestion):** `error_summary` must be truncated + scrubbed in the run-log middleware — never
  store raw routine payload (a failing legal-audit/content/payment routine could embed PII).
- **Art-30:** add a register entry for the run-log (+ PR-2 Concierge) processing activity; confirm PR-2
  Anthropic LLM calls fall under the recorded Anthropic DPA (Chapter V).

### Phase 2 — Run-log middleware (central write, zero per-cron edits)

**2.1** New `server/inngest/middleware/run-log.ts` modeled on `sentry-correlation.ts:55-156`:
`init() → onFunctionRun({ ctx, fn }) → { transformInput, transformOutput }`. On run start record
fnId + run_id + trigger_source + actor (read from `event.name`/`event.data`: `cron/X` ⇒ scheduled;
`cron/X.manual-trigger` ⇒ read `trigger`/`actor_class`/`actor_id`/`delegating_principal` from the
route-controlled keys). On `transformOutput` (`:107-151`) record terminal status + duration +
error_summary via the RPC. Register in the middleware chain in `server/inngest/client.ts` alongside
`sentryCorrelation`.

**2.2** The middleware uses the Inngest-runtime Supabase **service-role** client (same client the crons
already use for persistence) to call the RPC. Fail-soft: a run-log write failure mirrors to Sentry
(`cq-silent-fallback-must-mirror-to-sentry`) but never fails the routine.

### Phase 3 — Shared run chokepoint + dispatch

**3.1** `server/routines/run-routine.ts` — `runRoutine({ fnId, actorClass, actorId, delegatingPrincipal, confirmed })`:
1. Validate `fnId ∈ EXPECTED_CRON_FUNCTIONS` (else 400).
2. Read `ROUTINE_METADATA[fnId].manualTrigger`: `denied` → 403; `confirm` && !confirmed → 409
   `confirmation_required`; `allowed`/confirmed → proceed.
3. `inngest.send({ name: manualTriggerEventFor(fnId), data: { ...route-controlled keys LAST } })` —
   `trigger: actorClass === 'agent' ? 'agent' : 'manual'`, `at`, `actor_class`, `actor_id`,
   `delegating_principal` (spread last per `trigger-cron/route.ts:115-122` audit-poison guard).

This is the single chokepoint for both the human (dashboard route) and agent (MCP tool) paths.

### Phase 4 — Session-gated dashboard routes

Server routes (Supabase cookie session like `audit/page.tsx` / `api/dashboard/runs/route.ts:14-21`).
**NOT** added to `PUBLIC_PATHS` (session-gated; only secret/HMAC routes go public per `lib/routes.ts`).

- **4.1** `GET /api/dashboard/routines/route.ts` → `ROUTINE_METADATA` joined with latest `routine_runs`
  row per `routine_id` (last-run status/date/duration). Auth: `supabase.auth.getUser()` → 401 if absent.
- **4.2** `GET /api/dashboard/routines/runs/route.ts?cursor=` → paginated `routine_runs`
  (reverse-chronological), keyset pagination on `(started_at, id)`. Returns empty-state-friendly shape.
- **4.3** `POST /api/dashboard/routines/run/route.ts` → body `{ fnId, confirmed? }`; calls
  `runRoutine({ fnId, actorClass: 'human', actorId: user.id, confirmed })`. Returns `accepted` or the
  `409 confirmation_required` so the UI shows the modal (wireframe 03).

**TR1:** `INNGEST_SIGNING_KEY` must not appear in these routes or components (these read `routine_runs`,
not `/v1`) — the existing `inngest-key-server-only.test.ts` grep stays green.

### Phase 5 — Agent MCP tools (parity, FR7)

**5.1** `server/routines-tools.ts` (pattern: `server/account-tools.ts` / `github-tools.ts`):
- `mcp__soleur_platform__routines_list` → read (same query as 4.1).
- `mcp__soleur_platform__routine_runs_list` → read (same as 4.2).
- `mcp__soleur_platform__routine_run` → calls `runRoutine({ actorClass: 'agent', actorId, delegatingPrincipal })`.

**5.2** `server/tool-tiers.ts` `TOOL_TIER_MAP`: `routines_list`/`routine_runs_list` = `auto-approve`
(read); `routine_run` = `gated` (write — review-gate confirmation, the agent's per-run ack).

### Phase 6 — UI

**6.1** `app/(dashboard)/dashboard/routines/page.tsx` (server component, template = `audit/page.tsx`) +
client components: tab bar (Routines / Recent Runs; Concierge added in PR-2), grouped-by-domain list,
row component, Recent Runs table, Run-now confirmation modal (wireframe 03). Reference
`knowledge-base/product/design/routines/routines-management.pen` screens 01-03.

**6.2** Nav rail: add a "Routines" entry (next/link `href="/dashboard/routines"`) in the dashboard
nav (per-page next/link pattern under `app/(dashboard)/layout.tsx`; locate the rail at implementation).

**6.3 Spec-flow states (must implement, not just happy path):**
- **P0-1:** After Run-now, show post-trigger acknowledgement and transition the row to "Running"
  (optimistic client state); guard against double-fire (disable the button while in-flight).
- **P1-4:** Recent Runs empty state ("No runs yet").
- **P1-5:** Failed-run drill-in — row expands/links to `error_summary` (and Sentry/Audit where available).
- **P1-6:** Recent Runs pagination (keyset load-more).
- **P2-10:** Run-now on an already-Running routine — define behavior (allow + new row, or disable).
- **P2-11:** Archived row — disabled Run-now with a tooltip; "Archived" = display state in v1 (NG2).

### PR-1 Acceptance Criteria

#### Pre-merge (PR)
- [ ] `routine-metadata.ts` sidecar exists; `routine-metadata-parity.test.ts` asserts
      `keys(ROUTINE_METADATA) === EXPECTED_CRON_FUNCTIONS` AND each `cron` matches the function source literal.
- [ ] `EXPECTED_CRON_FUNCTIONS` element type unchanged (still `string[]`); `function-registry-count.test.ts`
      (`toBe(56)`) + `inngest-key-server-only.test.ts` still green.
- [ ] Migration `104_routine_runs.sql` + `.down.sql`: WORM trigger rejects direct UPDATE/DELETE; RLS
      select-only; writes only via SECURITY DEFINER RPC(s) with service-role grant; no `CONCURRENTLY`.
- [ ] GDPR-gate folds (Phase 2.7): migration carries `-- LAWFUL_BASIS:` (Art-6) + retention header
      (Art-5e); Art-17 erasure handled (anonymise RPC wired to DSAR, or `ON DELETE SET NULL`);
      `error_summary` scrubbed/truncated in the middleware (Art-9); Art-30 register entry added.
- [ ] `run-log.ts` middleware registered in `client.ts`; a triggered run writes a `routine_runs` row with
      correct `trigger_source` + `actor_class` (verified by a middleware unit test driving a fake event).
- [ ] `runRoutine()` rejects `denied`, requires `confirmed` for `confirm`, dispatches with route-controlled
      keys spread LAST (actor cannot forge `trigger`/`at`); unit test for all three policy branches.
- [ ] Three `/api/dashboard/routines*` routes session-gated (401 without session), NOT in `PUBLIC_PATHS`.
- [ ] Three MCP tools registered with correct tiers (`routine_run` = gated); agent can list + run a
      non-protected routine; protected requires `confirmed`.
- [ ] UI renders 42 routines grouped by domain with accurate last-run; Recent Runs paginates; Run-now
      shows ack + Running transition; protected routine shows the confirm modal; empty + failed states render.
- [ ] `## Observability` discoverability_test passes (run-log queryable via Supabase MCP, no SSH).

#### Post-merge (operator)
- [ ] Migration `104` applied via `web-platform-release.yml#migrate` (auto on merge; no SSH). Verify
      `routine_runs` exists + RLS via Supabase MCP. `Automation: feasible` — fold the verify into `/soleur:ship`.

---

## PR-2 — Concierge authoring chat (OUTLINE — gated on #5346, separate plan)

**Hard dependency:** #5346 — a net-new agent capability that opens a `cron-*.ts` PR with all FIVE
lockstep registry edits (route handler + array, `cron-manifest` `EXPECTED_CRON_FUNCTIONS`,
`function-registry-count.test.ts` count, `infra/sentry/cron-monitors.tf`, `apply-sentry-infra.yml`
`-target=`). PR-2 cannot ship its "create" path until #5346 exists. **Do not start PR-2 until #5346 is
scoped; PR-2 gets its own `/soleur:plan`.**

**Flow (wireframe 04 + spec-flow states):** Concierge tab (3rd tab) → operator describes routine →
**generated-routine review card** (name, domain, owner, schedule+raw cron, target file, "what it will
do") → **dry-run test** → **verify** → confirmation → **Open PR**.

- **Create** dry-run: execute the drafted logic in the agent sandbox (bwrap) with egress/writes
  **stubbed** and a "DRY RUN — no external effects" marker (CLO; learning
  `2026-06-08-cron-sandbox-disable-needs-bypasspermissions-pairing.md` — disabling sandbox needs
  `bypassPermissions: true`; here we KEEP the sandbox and stub egress).
- **Edit** dry-run: re-run the existing deployed routine via `runRoutine` in a dry-run mode and read
  back the run-log output; verify against live.
- **Remove:** opens a PR deleting the cron + its 5 registry entries.
- Concierge actions recorded in `routine_runs` / audit ledger as `actor_class='agent'` +
  `delegating_principal` (operator-via-agent, never anonymous — CLO).

**Spec-flow gaps PR-2 MUST close (from analysis):** P0-2 verification-FAILED card + retry/edit/abandon
branch; P0-3 overflow `…` → pre-filled Concierge handoff (edit/remove parity from the Routines tab);
P1-7 PR-creation failure state; P1-8 PR link + "pending PR / not yet live" indicator on the Routines
tab; P1-9 revise-after-pass path.

**Naming open question:** "Concierge" already names the KB-chat agent surface (#3451/#3326) — confirm
the tab reuses that agent in a new mode (preferred) vs. a distinct surface.

---

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (brainstorm carry-forward + this plan's Research Reconciliation).
**Assessment:** Sidecar metadata (not array-type change / per-function export); run-log middleware (zero
per-cron edits, no registry-count impact); durable run-log is the history source (list-runs is
finance-specific, /v1 retention-bounded); debug trigger extends the allowlist via a shared chokepoint,
no bypass route. Highest residual risk: run-log lifecycle (running→terminal) atomicity → deepen-plan +
data-integrity-guardian.

### Legal (CLO)
**Status:** reviewed (carry-forward).
**Assessment:** WORM run-log with actor-class (HUMAN vs AGENT) + delegating principal + invocation mode
(Art. 5(2) accountability). Deny-by-default `manualTrigger` policy for financial/egress/deletion
routines. v2 Concierge test-runs dry-run/sandbox by default. No inbound legal threshold tripped
(founder-grade). `cfo-on-payment-failed` out-of-band run flagged for a financial-controls note.

### Product/UX Gate
**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer (this plan), cpo (brainstorm carry-forward)
**Skipped specialists:** none
**Pencil available:** yes — `.pen` committed (4 screens) at `knowledge-base/product/design/routines/routines-management.pen`, referenced in FR1/FR8.

#### Findings
spec-flow surfaced 13 journey gaps; v1 ACs cover P0-1 + P1-4/5/6 + P2-10/11; v2 outline carries P0-2,
P0-3, P1-7/8/9. CPO: lead with visibility, honest PR-scaffold framing, agent parity for every operator
action (delivered via the 3 MCP tools).

## Infrastructure (IaC)

PR-1 introduces **no** new server/vendor/secret/cron — only a Supabase migration (`104`) applied by the
existing `web-platform-release.yml#migrate` job (`run-migrations.sh`, not SSH). No `terraform-architect`
routing needed for PR-1. *(PR-2's Concierge "create" scaffolds a Sentry `cron-monitors.tf` resource +
`apply-sentry-infra.yml -target=` line — but that is the PR the Concierge OPENS, authored by the #5346
capability, not infra provisioned by this plan.)*

## Observability

```yaml
liveness_signal:
  what: routine_runs rows written by the run-log middleware on every cron execution; existing
        cron-inngest-cron-watchdog continues to assert cron liveness
  cadence: per-run (event-driven) + watchdog cron
  alert_target: Sentry (existing cron monitors) — no new monitor for PR-1
  configured_in: server/inngest/middleware/run-log.ts + existing infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (run-log write failures + new route errors, via captureException)
  fail_loud: run-log write failure mirrors to Sentry but never fails the routine (cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: run-log write fails (Supabase down)
    detection: Sentry event tagged surface=routine-run-log
    alert_route: existing Sentry alerting
  - mode: Run-now dispatch fails (Inngest send error)
    detection: 5xx from /api/dashboard/routines/run + Sentry
    alert_route: Sentry
  - mode: protected routine fired without confirmation
    detection: 409 confirmation_required (expected); abuse visible as repeated 403/409 in logs
    alert_route: n/a (by-design gate)
logs:
  where: Sentry + journald (Vector-shipped, per sentry-correlation.ts:24-26)
  retention: existing platform retention
discoverability_test:
  command: "supabase MCP: select routine_id,status,trigger_source,actor_class from routine_runs order by started_at desc limit 5"
  expected_output: recent run rows with correct trigger_source/actor_class attribution (NO ssh)
```

## Open Code-Review Overlap

None. Checked 64 open `code-review` issues (2026-06-15); no body references the planned files
(`client.ts`, `tool-tiers.ts`, `inngest/middleware`, `dashboard/routines`, `cron-manifest`,
`routine_runs`, `manual-trigger`).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Reuse `list-runs.ts` for cron history | Rejected — finance-specific (`finance.payment_failed`), can't list by fnId; /v1 retention-bounded. |
| Per-cron run-log writes (edit 42 files) | Rejected — huge diff, drift risk, registry-count entanglement. Middleware is central + zero per-cron edits. |
| Runtime routine creation | Rejected (NG1) — routines are deployed code behind the 5-registry lockstep + `toBe(56)` guard. Create = PR-scaffold (PR-2). |
| New bypass endpoint for Run-now | Rejected — reuse the allowlist via a session-gated route + shared chokepoint; no second trigger path. |
| Auto-derive protected subset from handler code | Deferred — explicit `manualTrigger` in the sidecar is auditable + reviewable; revisit if the list grows. |

## Risks & Mitigations

- **Run-log lifecycle atomicity (running→terminal).** Mitigation: deepen-plan Phase 4.4 precedent-diff
  vs `037`/`051`/`064` + data-integrity-guardian; default to the simpler terminal-only append unless
  in-flight durability is load-bearing.
- **Double-fire of a protected routine** (spec-flow P0-1). Mitigation: optimistic-disable Run-now while
  in-flight + the confirm modal + the `confirm` policy.
- **Agent runs a routine the operator wouldn't.** Mitigation: `routine_run` tier=gated (review-gate) +
  `denied`/`confirm` policy + actor_class='agent' attribution in the WORM log.
- **`INNGEST_SIGNING_KEY` leaking to client.** Mitigation: these routes read `routine_runs`, not /v1;
  `inngest-key-server-only.test.ts` stays green (TR1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — this one is
  filled (single-user incident).
- Pencil `open_document` is destructive on `routines-management.pen` (#3274) — any further wireframe
  edits go via temp-build + JSON-merge; commit the `.pen` after each edit.
- The `cron` literal extraction for the cron-drift test (FR1) must tolerate the actual
  `{ cron: "..." }` shape in each function file — verify the extraction at implementation, don't assume.
