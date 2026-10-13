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

Give the operator a web surface to **see and operate** the cron routines that run the autonomous
company (`server/inngest/cron-manifest.ts` → `EXPECTED_CRON_FUNCTIONS`, **43 entries** as of
2026-06-15 — bind to `.length`, never a literal), and a Concierge chat to **author** routines. Today
routines are visible only in code and triggerable only via the `soleur:trigger-cron` CLI.

**Scope (v1).** Exactly the `EXPECTED_CRON_FUNCTIONS` **crons**. Event-driven functions
(`cfo-on-payment-failed` — `{ event: "finance.payment_failed" }`, requires a `PaymentFailedPayload`)
and one-shot functions are **out of scope**: the `runRoutine()` chokepoint validates
`fnId ∈ EXPECTED_CRON_FUNCTIONS`, which structurally excludes them (firing them with empty/forged
`event.data` would be unsafe). [Plan-review correction: an earlier draft wrongly used
`cfo-on-payment-failed` as the flagship protected routine — it is not a cron.]

**Decomposition (two PRs behind one feature surface, CPO/CTO consensus):**

- **PR-1 (this plan, implementable now):** Routines tab (grouped by domain) + Recent Runs history +
  debug Run-now. Reuses existing primitives; adds a routine-metadata sidecar, a durable run-log, an
  Inngest run-log middleware, a shared run chokepoint, three session routes, three agent MCP tools, UI.
- **PR-2 (outlined, gated on #5346):** Concierge authoring chat (draft → dry-run test+verify →
  Open PR). Depends on a net-new agent capability — opening a `cron-*.ts` PR with all five lockstep
  registry edits — tracked in #5346. PR-2 gets its own plan once #5346 is scoped.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "full execution history" | `lib/inngest/list-runs.ts:47-107` hardwired to `finance.payment_failed` + founderId CEL; `/v1` loopback-gated + retention-bounded | Durable Supabase run-log is the source of truth (FR6); `/v1` at most enrichment (TR7). Do NOT reuse `list-runs.ts`. |
| "Run now" needs a new endpoint | `POST /api/internal/trigger-cron` (`route.ts:1-139`, secret-gated) + `manual-trigger-allowlist.ts` exist | Route **both** the session path AND the legacy secret route through one `runRoutine()` chokepoint (policy + attribution + single `inngest.send`). No second dispatch site. |
| routine metadata (domain/owner) | `EXPECTED_CRON_FUNCTIONS` is a bare `string[]` (43); `function-registry-count.test.ts:135` `toBe(56)` counts the **route array (cron + event fns)**, NOT the cron set | New **sidecar map** `ROUTINE_METADATA` (client-free leaf) + parity test `keys === EXPECTED_CRON_FUNCTIONS`. `toBe(56)` is unaffected and is NOT the metadata guard. Do NOT change the array element type or add per-function exports (#4734). |
| run-log written per routine | Inngest middleware `sentry-correlation.ts:55-156` wraps every run; `client.ts:68` `middleware:[...]`; service-role client at `lib/supabase/service.ts` (already `.rpc()`-used by crons) | Add a sibling `run-log.ts` — central write, zero edits to the 43 `cron-*.ts`, no registry-count impact. **Gate the terminal write on the final attempt** (`ctx.attempt`). |
| WORM audit ledger | `037_audit_byok_use.sql` (FOR-EACH-STATEMENT no-mutate trigger + SECURITY DEFINER RPC + `REVOKE … FROM anon, authenticated`) + `051:224` `session_replication_role='replica'` | `routine_runs` + a single `write_routine_run()` RPC (terminal-only append — no lifecycle UPDATE). Migration `104`. |

## User-Brand Impact

**If this lands broken, the user experiences:** the Routines tab shows stale/incorrect run status (a
failed `cron-legal-audit` or `cron-content-publisher` looks "completed"), or Run-now silently fires a
production routine twice — the operator can't trust what the autonomous company is doing.

**If this leaks, the user's data/workflow is exposed via:** the run-log stores `actor_id` (operator
UUID) + per-run metadata; an off-schedule or agent-initiated run of a production routine (content
publishing, legal audit, external egress) takes a real action in the operator's name with no human in
the loop, or an audit record misattributes an agent action to the operator.

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true` (carried from
brainstorm; CPO reviewed at brainstorm Phase 0.5). `user-impact-reviewer` runs at PR-review time.

---

## PR-1 — Routines visibility + debug Run-now

### Architecture

```
  Operator (browser) ── GET /api/dashboard/routines        ─┐ (shared read fn)
                        GET /api/dashboard/routines/runs    ─┤
                        POST /api/dashboard/routines/run ────┤
  Agent (MCP, gated) ── routines_list / routine_runs_list ──┤
                        routine_run ────────────────────────┤
  CLI (secret route) ── POST /api/internal/trigger-cron ────┤   ← now routes through chokepoint too
                                                             ▼
                              server/routines/run-routine.ts  (THE single dispatch site:
                                policy check + attribution-set-route-last + inngest.send)
                                                             │ inngest.send(cron/X.manual-trigger)
                                                             ▼
                              Inngest runtime ── run-log middleware (final-attempt-gated write)
                                                             │ write_routine_run() RPC (terminal append)
                                                             ▼
                                                  Supabase routine_runs (WORM, append-only)
```

### Phase 1 — Data model

**1.1 Routine metadata sidecar.** New client-free leaf `server/inngest/routine-metadata.ts` (imports
NOTHING from client, mirroring `cron-manifest.ts` #4734):

```ts
export interface RoutineMeta {
  domain: string;       // "Onboarding" | "Engineering" | ...
  ownerRole: string;    // "COO" | "CTO" | "CMO" | "CLO" | "CFO" | ...
  scheduleLabel: string;// human, e.g. "Daily 04:00 UTC" (display only — NO raw cron field;
                        //   the cron literal stays single-sourced in each cron-*.ts)
  manualTrigger: "allowed" | "confirm"; // confirm = protected subset (financial/egress/deletion)
}
export const ROUTINE_METADATA: Record<string, RoutineMeta> = { /* one entry per EXPECTED_CRON_FUNCTIONS id */ };
```

- `manualTrigger: "confirm"` for the protected crons: `cron-content-publisher`, `cron-legal-audit`,
  `cron-github-app-drift-guard`, `cron-content-vendor-drift`, plus any cron whose handler sends email /
  posts externally / deletes data (enumerate during implementation). Default `"allowed"`.
  *(No `"denied"` level in v1 — event functions that must never be fired are already excluded by the
  `fnId ∈ EXPECTED_CRON_FUNCTIONS` membership check. Add `denied` only if a never-fire cron appears.)*
- **Parity test** `test/server/inngest/routine-metadata-parity.test.ts` (the metadata drift guard — a
  hard CI gate): `Object.keys(ROUTINE_METADATA).sort()` deep-equals `[...EXPECTED_CRON_FUNCTIONS].sort()`.
  This (NOT `toBe(56)`) is what prevents a cron being added without metadata. No cron-drift/source-grep
  test (we dropped the raw `cron` field, so there is no second source to drift).

**1.2 Durable run-log.** Migration `107_routine_runs.sql` (model on `037`/`051`), **terminal-only
append** (no `running` row, no lifecycle UPDATE):

```sql
-- LAWFUL_BASIS: legitimate_interest (operational audit of operator-/agent-triggered routine runs; single-operator tenant)
-- RETENTION: indefinite (operational audit log; low row volume — one row per routine run). Revisit if volume grows (cf. 103_github_events_retention_7day).
create table routine_runs (
  id uuid primary key default gen_random_uuid(),
  routine_id text not null,            -- fnId ∈ EXPECTED_CRON_FUNCTIONS
  run_id text,                         -- Inngest run id
  status text not null,                -- 'completed' | 'failed' (terminal; no 'running' in the log)
  trigger_source text not null,        -- 'scheduled' | 'manual' | 'agent'
  actor_class text not null,           -- 'system' | 'human' | 'agent'
  actor_id uuid references users(id) on delete set null,            -- operator (nullable)
  delegating_principal uuid references users(id) on delete set null,-- for agent runs
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_ms integer not null,
  error_summary text                   -- failed runs: scrubbed + truncated (≤ N chars), never raw payload
);
-- RLS: operator-select only; NO insert/update/delete policies (writes only via the RPC).
-- WORM: BEFORE UPDATE/DELETE no-mutate trigger (037 FOR-EACH-STATEMENT pattern); REVOKE the trigger fn
--   from anon, authenticated. Pure append — there is no allowed UPDATE, so no replica-role bypass.
-- write_routine_run(...) SECURITY DEFINER, SET search_path = public, pg_temp, service-role grant only (037:79-104 pattern).
-- Index (NOT CONCURRENTLY — 037:18): (routine_id, started_at desc) for last-run + Recent Runs.
```

- **Art-17 erasure:** `ON DELETE SET NULL` on the two FKs (single-operator tenant — no DSAR-RPC needed;
  DHH/code-simplicity). The WORM rows survive operator-account deletion with the actor anonymised.
- **Art-9:** `error_summary` truncated + scrubbed in the middleware — never raw routine payload.

### Phase 2 — Run-log middleware (central write, zero per-cron edits)

**2.1** New `server/inngest/middleware/run-log.ts` modeled on `sentry-correlation.ts:55-156`; register
in `client.ts:68` `middleware:[...]` after `sentryCorrelation`. On `transformOutput` (`:107-151`,
function-final) compute terminal `status`/`duration_ms`/`error_summary` and the attribution from
`ctx.event` and call `write_routine_run()` via the `lib/supabase/service.ts` service-role client.

**2.2 Final-attempt gate (P0 — `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`).**
`transformOutput` fires on **every** attempt's final result. The terminal write MUST be gated on
`ctx.attempt >= (ctx.maxAttempts ?? 1) - 1`, **fail-safe to write when attempt data is absent** — else
a fail-then-succeed sequence appends two rows (`failed` then `completed`). Do NOT wrap the write in a
memoized `step.run` (a recovered status would be lost). **AC + test:** a fail-then-succeed run writes
exactly one `completed` row.

**2.3 Attribution integrity (P1).** The middleware DERIVES `trigger_source` from `event.name`
(`cron/X` ⇒ `scheduled`; `cron/X.manual-trigger` ⇒ `manual`/`agent` from the `trigger` key) and reads
`actor_class`/`actor_id`/`delegating_principal` ONLY from keys set by `runRoutine` (route-controlled,
spread last). It MUST ignore any caller-supplied actor fields. **AC + test:** an event with
caller-forged `data.actor_class:"system"` is recorded with the chokepoint-derived value, not the forgery.

**2.4** Fail-soft: a run-log write failure mirrors to Sentry (`cq-silent-fallback-must-mirror-to-sentry`)
and MUST NOT throw into the handler (no retry-poisoning). **AC + test:** a throwing RPC does not
propagate to the routine.

### Phase 3 — Shared run chokepoint (THE single dispatch site)

**3.1** `server/routines/run-routine.ts` — `runRoutine({ fnId, actorClass, actorId, delegatingPrincipal, confirmed })`:
1. Validate `fnId ∈ EXPECTED_CRON_FUNCTIONS` (else 400 — excludes event/oneshot fns).
2. `ROUTINE_METADATA[fnId].manualTrigger`: `confirm` && !confirmed → `409 confirmation_required`;
   `allowed`/confirmed → proceed.
3. `inngest.send({ name: manualTriggerEventFor(fnId), data: { ...callerData, /* route-controlled LAST */
   trigger: actorClass === 'agent' ? 'agent' : 'manual', at, actor_class, actor_id, delegating_principal } })`
   (spread-last guard per `trigger-cron/route.ts:115-122`).

**3.2** The legacy `POST /api/internal/trigger-cron` route's dispatch is **refactored to call
`runRoutine`** with `actorClass:'system'`, `confirmed:true` (the secret is a higher trust tier —
the `confirmed:true` is the explicit, documented exemption from the confirm gate, and it normalizes
attribution to `system`/`manual`). This makes `runRoutine` the literal single `inngest.send` site and
closes the actor-forgery + protected-bypass gap the legacy direct-send had. Existing
`manual-trigger-allowlist` behavior preserved.

### Phase 4 — Session-gated dashboard routes (thin adapters)

Server routes (Supabase cookie session like `audit/page.tsx` / `api/dashboard/runs/route.ts:14-21`).
**NOT** in `PUBLIC_PATHS` (session-gated). Route handlers are pure adapters: auth + shape body → call a
shared fn; they do NOT re-implement policy.

- **4.1** `GET /api/dashboard/routines` → shared `listRoutinesWithLastRun()` (`ROUTINE_METADATA` ⋈
  latest `routine_runs` per `routine_id`; null-guards a missing metadata row). **Same fn** backs the
  `routines_list` MCP tool (no copy).
- **4.2** `GET /api/dashboard/routines/runs?cursor=` → shared paginated reader (keyset on
  `(started_at, id)`); empty-state-friendly shape. Same fn backs `routine_runs_list`.
- **4.3** `POST /api/dashboard/routines/run` → `{ fnId, confirmed? }` → `runRoutine({ actorClass:'human',
  actorId: user.id, confirmed })`. Returns `accepted` or `409 confirmation_required` (UI modal, wireframe 03).

**TR1:** these read `routine_runs`, not `/v1` — `inngest-key-server-only.test.ts` stays green.

### Phase 5 — Agent MCP tools (parity, FR7)

**5.1** `server/routines-tools.ts` (pattern: `server/account-tools.ts`):
`mcp__soleur_platform__routines_list` + `mcp__soleur_platform__routine_runs_list` (call the shared read
fns) + `mcp__soleur_platform__routine_run` (calls `runRoutine({ actorClass:'agent', actorId, delegatingPrincipal })`).

**5.2** `server/tool-tiers.ts` `TOOL_TIER_MAP` (FQ keys): `…routines_list`/`…routine_runs_list` =
`auto-approve`; `…routine_run` = `gated`.

**5.3 Agent confirmation = host review-gate (no double-gate) (P0, spec-flow).** For the agent path the
`gated` tier's host `review-gate` ("Agent wants to run routine X — Allow?") IS the single confirmation.
Add a `routine_run` case to `buildGateMessage` (`tool-tiers.ts:141`) showing the routine name + its
`manualTrigger` policy. When the operator approves the review-gate, the tool calls
`runRoutine(..., confirmed: true)` — so a `confirm` routine is NOT additionally blocked by the in-band
409. The in-band 409 is the **session/UI** mechanism; the review-gate is the **agent** mechanism. Pick
one per path; never both.

### Phase 6 — UI

**6.1** `app/(dashboard)/dashboard/routines/page.tsx` (server component, template `audit/page.tsx`) +
client components: tab bar (Routines / Recent Runs; Concierge in PR-2), grouped-by-domain list, row,
Recent Runs table, Run-now confirm modal (wireframe 03). Reference the `.pen` screens 01-03.

**6.2** Nav rail: add "Routines" (`next/link href="/dashboard/routines"`) in the dashboard nav.

**6.3 Spec-flow states (implement, not just happy path):**
- **P0-1:** after Run-now, post-trigger acknowledgement + optimistic "Running" client state; disable the
  button while in-flight (this also answers **P2-10** — no concurrent double-fire).
- **P1-4:** Recent Runs empty state.
- **P1-5:** failed-run drill-in — row expands to the (scrubbed, non-empty) `error_summary`; the
  middleware MUST populate `error_summary` on failure so the drill-in has actionable content.
- **P1-6:** Recent Runs keyset pagination (load-more).
- *(P2-11 archived-row state CUT from v1 — no archive mechanism exists in v1 (NG2); a disabled state
  for a row that cannot be produced is dead UI. Revisit with the durable archive toggle.)*

### PR-1 Acceptance Criteria

#### Pre-merge (PR)
- [ ] `routine-metadata.ts` sidecar exists; `routine-metadata-parity.test.ts` asserts
      `keys(ROUTINE_METADATA) === EXPECTED_CRON_FUNCTIONS` (bound to the array, not a literal count).
      No raw `cron` field; no source-grep cron-drift test.
- [ ] `EXPECTED_CRON_FUNCTIONS` element type unchanged (`string[]`); `function-registry-count.test.ts`
      (`toBe(56)`, route array) + `inngest-key-server-only.test.ts` still green. (56 ≠ the cron count;
      they are distinct sets — do not conflate.)
- [ ] Migration `107_routine_runs.sql` + `.down.sql`: terminal-only append; WORM no-mutate trigger
      rejects UPDATE/DELETE; RLS select-only; write only via `write_routine_run()` SECURITY DEFINER RPC
      (service-role grant, `search_path` pinned); `ON DELETE SET NULL` FKs; `-- LAWFUL_BASIS:` +
      `-- RETENTION:` headers; no `CONCURRENTLY`.
- [ ] `run-log.ts` registered at `client.ts:68`; **final-attempt-gated** terminal write — test: a
      fail-then-succeed run writes exactly one `completed` row (not two).
- [ ] Middleware ignores caller-supplied actor fields — test: forged `data.actor_class` is overridden by
      the chokepoint-derived value.
- [ ] Run-log write failure does not propagate to the routine — test: throwing RPC → routine still ok,
      Sentry mirrored.
- [ ] `runRoutine()` is the single `inngest.send` dispatch site; the legacy `/api/internal/trigger-cron`
      route calls it (`actorClass:'system'`, `confirmed:true`); test: legacy path records `system`
      attribution; `confirm` policy enforced for the session/agent path (409 / review-gate).
- [ ] Three `/api/dashboard/routines*` routes session-gated (401 without session), NOT in `PUBLIC_PATHS`;
      route + MCP read paths call the **same** shared fns (no duplicated query).
- [ ] Three MCP tools registered with FQ names + correct tiers (`mcp__soleur_platform__routine_run` =
      gated); `buildGateMessage` has a `routine_run` case; agent can list + run a non-protected routine;
      a `confirm` routine is gated once (review-gate), not double-gated.
- [ ] UI renders all `EXPECTED_CRON_FUNCTIONS` routines grouped by domain with accurate last-run; Recent
      Runs paginates + empty state; Run-now shows ack + Running + disables while in-flight; protected →
      confirm modal; failed-run drill-in shows non-empty scrubbed `error_summary`.
- [ ] `## Observability` discoverability_test passes (run-log queryable via Supabase MCP, no SSH).

#### Post-merge (operator)
- [ ] Migration `104` applied via `web-platform-release.yml#migrate` (auto on merge; no SSH). Fold the
      `routine_runs`-exists + RLS verify into `/soleur:ship` post-merge (Supabase MCP). `Automation: feasible`.

---

## PR-2 — Concierge authoring chat (OUTLINE — gated on #5346, separate plan)

**Hard dependency:** #5346 — a net-new agent capability that opens a `cron-*.ts` PR with all FIVE
lockstep registry edits (route handler + array, `cron-manifest` `EXPECTED_CRON_FUNCTIONS`,
`function-registry-count.test.ts` count, `infra/sentry/cron-monitors.tf`, `apply-sentry-infra.yml`
`-target=`). PR-2's "create" path cannot ship until #5346 exists. **PR-2 gets its own `/soleur:plan`.**

**Flow (wireframe 04 + spec-flow):** Concierge tab → describe → **review card** (name, domain, owner,
schedule, target file, "what it will do") → **dry-run test** → **verify** → confirm → **Open PR**.

- **Create** dry-run: drafted logic in the agent sandbox (bwrap KEPT) with egress/writes **stubbed** +
  a "DRY RUN — no external effects" marker (CLO).
- **Edit** dry-run: re-run the existing deployed routine via `runRoutine` dry-run; verify against live.
- **Remove:** PR deleting the cron + its 5 registry entries.
- Concierge actions recorded as `actor_class='agent'` + `delegating_principal` (operator-via-agent).

**Spec-flow gaps PR-2 MUST close:** P0-2 verification-FAILED card + retry/edit/abandon; P0-3 overflow
`…` → pre-filled Concierge handoff (edit/remove parity from the Routines tab); P1-7 PR-creation failure
state; P1-8 PR link + "pending PR / not yet live" indicator on the Routines tab; P1-9 revise-after-pass.

**Naming open question:** "Concierge" already names the KB-chat agent surface (#3451/#3326) — confirm
the tab reuses that agent in a new mode (preferred) vs. a distinct surface.

---

## Domain Review

**Domains relevant:** Engineering, Product, Legal (brainstorm carry-forward + 5-agent plan-review panel).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review panel).
**Assessment:** Sidecar metadata (not array-type change / per-function export); run-log middleware
(zero per-cron edits, final-attempt-gated, fail-soft); durable run-log is the history source; single
`runRoutine` chokepoint for ALL dispatch (session + agent + legacy secret route), no bypass; v1 scope =
crons only (event fns excluded by membership). Residual: confirm the cron `scheduleLabel` set is accurate.

### Legal (CLO)
**Status:** reviewed (carry-forward + GDPR-gate Phase 2.7).
**Assessment:** WORM run-log with actor-class (HUMAN/AGENT/SYSTEM) + delegating principal + invocation
mode (Art. 5(2)). `-- LAWFUL_BASIS:` (Art-6) + retention header (Art-5e) + `ON DELETE SET NULL`
(Art-17, single-operator) + scrubbed `error_summary` (Art-9) + Art-30 register entry. Deny-by-default
for protected crons via `confirm`. No inbound legal threshold tripped (founder-grade).

### Product/UX Gate
**Tier:** blocking · **Decision:** reviewed · **Agents invoked:** spec-flow-analyzer (×2: wireframe +
plan), cpo (brainstorm carry-forward) · **Skipped specialists:** none · **Pencil available:** yes —
`.pen` (4 screens) committed at `knowledge-base/product/design/routines/routines-management.pen`.

#### Findings
spec-flow surfaced 13 journey gaps; v1 ACs cover P0-1 + P1-4/5/6 (+ P2-10 folded into P0-1 disable);
P2-11 cut (dead UI); P0-2/P0-3/P1-7/8/9 carried to PR-2. Plan-level spec-flow flagged the agent
confirm-path double-gate (fixed: §5.3) and the metadata null-guard (fixed: §4.1). CPO: lead with
visibility, honest PR-scaffold framing, agent parity via the 3 MCP tools.

## Infrastructure (IaC)

PR-1 introduces no new server/vendor/secret/cron — only Supabase migration `104`, applied by the
existing `web-platform-release.yml#migrate` job (`run-migrations.sh`, not SSH). No `terraform-architect`
routing needed. *(PR-2's Concierge "create" scaffolds a Sentry `cron-monitors.tf` resource +
`apply-sentry-infra.yml -target=` line — authored by the #5346 capability in the PR it opens, not infra
provisioned here.)*

## Observability

```yaml
liveness_signal:
  what: routine_runs rows written by the (final-attempt-gated) run-log middleware on every cron run; existing cron-inngest-cron-watchdog continues to assert cron liveness
  cadence: per-run (event-driven) + watchdog cron
  alert_target: Sentry (existing cron monitors) — no new monitor for PR-1
  configured_in: server/inngest/middleware/run-log.ts + existing infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (run-log write failures + new route errors, via captureException)
  fail_loud: run-log write failure mirrors to Sentry, never fails the routine (cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: run-log write fails (Supabase down)
    detection: Sentry event tagged surface=routine-run-log
    alert_route: existing Sentry alerting
  - mode: Run-now dispatch fails (Inngest send error)
    detection: 5xx from /api/dashboard/routines/run + Sentry
    alert_route: Sentry
  - mode: duplicate run-log row from retry (final-attempt gate regression)
    detection: routine-metadata-parity + a unit test on the attempt gate; runtime dup visible as 2 rows same run_id
    alert_route: caught in CI test; runtime would surface in Recent Runs
logs:
  where: Sentry + journald (Vector-shipped, per sentry-correlation.ts:24-26)
  retention: existing platform retention
discoverability_test:
  command: "supabase MCP: select routine_id,status,trigger_source,actor_class,run_id from routine_runs order by started_at desc limit 5"
  expected_output: recent run rows with correct trigger_source/actor_class attribution, one row per run_id (NO ssh)
```

## Open Code-Review Overlap

None. Checked 64 open `code-review` issues (2026-06-15); no body references the planned files
(`client.ts`, `tool-tiers.ts`, `inngest/middleware`, `dashboard/routines`, `cron-manifest`,
`routine_runs`, `manual-trigger`).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Reuse `list-runs.ts` for cron history | Rejected — finance-specific; /v1 retention-bounded. |
| Per-cron run-log writes (edit 43 files) | Rejected — huge diff, drift risk. Middleware is central, zero per-cron edits. |
| Insert-at-start + terminal-update (two RPCs, replica-role bypass) | Rejected (DHH + code-simplicity) — "running" is UI state, not a DB fact; terminal-only append is pure WORM + one RPC. |
| `manualTrigger: denied` level | Rejected for v1 — no cron member; event fns excluded by membership. Add when a never-fire cron appears. |
| Art-17 anonymise RPC + DSAR wiring | Rejected for single-operator tenant — `ON DELETE SET NULL` closes Art-17 in one line. |
| `cfo-on-payment-failed` as protected routine | **Rejected — it is an event function, not a cron; out of scope.** |
| Legacy secret route keeps direct `inngest.send` | Rejected — left a protected-policy bypass + actor-forgery hole; route it through `runRoutine`. |
| Runtime routine creation | Rejected (NG1) — routines are deployed code; create = PR-scaffold (PR-2). |

## Risks & Mitigations

- **Retry double-write to the run-log** (architecture P0). Mitigation: final-attempt gate (§2.2) +
  hard AC/test; terminal-only append alone does NOT solve it.
- **Actor-forgery / protected-policy bypass via the secret route** (architecture P1). Mitigation: single
  `runRoutine` dispatch site (§3.2) + middleware ignores caller actor fields (§2.3) + tested invariants.
- **Double-fire of a protected routine** (spec-flow P0-1). Mitigation: optimistic-disable + confirm
  modal + `confirm` policy.
- **Agent runs a routine the operator wouldn't.** Mitigation: `routine_run` tier=gated (review-gate
  with routine-named message) + `confirm` policy + `actor_class='agent'` WORM attribution.
- **`INNGEST_SIGNING_KEY` leaking to client.** Mitigation: routes read `routine_runs`, not /v1;
  `inngest-key-server-only.test.ts` stays green (TR1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — filled here.
- Pencil `open_document` is destructive on `routines-management.pen` (#3274) — further wireframe edits
  via temp-build + JSON-merge; commit the `.pen` after each edit.
- `EXPECTED_CRON_FUNCTIONS` is **43**; `function-registry-count.test.ts` `toBe(56)` counts the route
  array (cron + event fns) — distinct sets, never conflate. Bind ACs to `.length`, never a literal.
- Event-driven functions (`cfo-on-payment-failed`) require `event.data` payloads and are NOT firable via
  Run-now — the `fnId ∈ EXPECTED_CRON_FUNCTIONS` membership check is what excludes them.

## Plan Review — applied (5-agent panel, single-user threshold)

DHH + code-simplicity (simplification) and Kieran + architecture-strategist + spec-flow (correctness).
Applied: terminal-only append + final-attempt gate (P0); single `runRoutine` dispatch incl. legacy
route (P1 forgery/bypass); agent confirm = review-gate, no double-gate (P0); cfo-is-not-a-cron
correction + 43-not-42 + 56-is-route-array (P0 facts); dropped sidecar `cron` field + drift test;
`allowed|confirm` only; `ON DELETE SET NULL`; cut P2-11, folded P2-10 into P0-1; shared read fn;
scrubbed-but-present `error_summary`; FQ tool names.
