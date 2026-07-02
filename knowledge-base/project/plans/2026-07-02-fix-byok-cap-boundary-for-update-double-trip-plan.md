---
title: "fix(ci): byok cap-boundary FOR UPDATE double-trip — make the kill-switch trip signal authoritative + guard dev-RPC drift"
date: 2026-07-02
type: bug
issue: 5917
branch: feat-one-shot-5917-byok-cap-boundary-flake
lane: cross-domain  # no spec.md present — defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels: [priority/p1-high, type/bug, domain/engineering]
milestone: "Post-MVP / Later"
---

# 🐛 fix(ci): byok cap-boundary `FOR UPDATE` double-trip on shared dev-Supabase

## Overview

The **required** `tenant-integration-required` check went red on `main`
(2026-07-02 ~20:26 UTC) on the live dev-Supabase concurrency test
`apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`
› *"N concurrent RPC calls at cap-boundary serialize via FOR UPDATE"*.

The issue (#5917) hypothesised a **shared-dev-DB cross-run contention flake**
and proposed test-side fixes (per-run row namespace / serialize the test).
**Both halves of that premise are wrong** and the CI log proves it:

- **The failing assertion is Invariant C, not a load/clock/error invariant.**
  Log (run `28619386206`, line 235): `at cumulative=700: expected true to
  be false`. `kill_tripped` was **true on TWO calls** (cumulative 600 **and**
  700), where the contract is *exactly one* trip (the call landing at
  `CAP_CENTS + COST_CENTS = 600`).
- **Invariant B passed cleanly** (`cumulatives === [100,200,…,1000]`, no gaps
  or duplicates) — so the audit accounting *did* serialise. Only the
  kill-switch trip signal double-fired.
- **Per-run founder isolation already exists** (the test's `afterAll`:
  *"Per-run isolation is guaranteed by the per-run randomBytes-derived
  email"*). The `FOR UPDATE` lock and the `SUM … WHERE founder_id =
  p_founder_id` are both scoped to a **per-run-unique** founder row, so
  concurrent *other* CI runs cannot contend on this row. The issue's
  "dedicated row namespace" fix is already implemented.

### Why a double-trip is the smoking gun

Under a correctly-held `SELECT … FOR UPDATE` on the founder's `users` row,
a double-trip is **impossible**: callers execute their critical sections one
at a time in lock-acquisition order; the call that lands at cumulative 700
acquires the lock strictly *after* the 600-call commits its
`runtime_paused_at` stamp, so it re-reads a non-NULL `runtime_paused_at`
(READ COMMITTED + EvalPlanQual re-read on lock release) and does **not**
trip. Invariant B being clean *confirms* lock-acquisition order == cumulative
order for this run. Therefore the observed double-trip means the trip
decision did **not** observe the prior committed stamp.

Two root-cause branches remain (Phase 0 disambiguates — see `## Hypotheses`):

- **H1 (leading) — dev-DB RPC drift.** dev-Supabase is running a
  `record_byok_use_and_check_cap` body that is **not** migration 061's
  `FOR UPDATE` version (a stale/older/hand-patched definition, or a dev reset
  that left `_schema_migrations` intact but the function body wrong). Fits the
  **persistence** signal (failed on two consecutive main commits + a full
  re-run also failed → not a random race; a persistent wrong definition).
- **H2 — genuine trip-signal fragility.** Even with the lock, the current
  RPC derives `v_tripped` from a **pre-read snapshot** (`v_paused_at IS NULL`
  captured at the top of the function) rather than from the guarded
  `UPDATE`'s actual effect. Any serialization anomaly (pooler edge, future RV
  rewrite) that staled that snapshot re-produces the double-trip.

### The fix — one migration that is correct under BOTH branches

Derive the trip signal from the guarded `UPDATE`'s **actual row-change**, not
the pre-read snapshot:

```sql
-- BEFORE (mig 061:136-141): trip decided by a stale top-of-function read
IF v_paused_at IS NULL AND v_total > v_cap THEN
  UPDATE public.users SET runtime_paused_at = now()
   WHERE id = p_founder_id AND runtime_paused_at IS NULL;
  v_tripped := true;
END IF;

-- AFTER (new migration 121): trip decided by whether THIS statement flipped it
IF v_total > v_cap THEN
  UPDATE public.users SET runtime_paused_at = now()
   WHERE id = p_founder_id AND runtime_paused_at IS NULL;
  v_tripped := FOUND;   -- true iff this UPDATE changed the row
END IF;
```

The `AND runtime_paused_at IS NULL` predicate in the `UPDATE`'s `WHERE` clause
is evaluated **atomically against the current row**: only one concurrent
caller can flip NULL → non-NULL; every other caller's `WHERE` fails to match,
so `FOUND` is false for them. This yields **exactly one trip** and is a
*strict improvement* — it preserves the safety property (fail-safe: the
switch still trips on cap breach) while removing the reliance on a pre-read
snapshot. `FOR UPDATE` is **retained** (it still serialises the audit
INSERT↔SUM against the TOCTOU race Invariant B guards).

Applying this migration to dev **also reconciles any H1 drift** (it is an
idempotent `CREATE OR REPLACE`), so the single deliverable both unblocks the
required check and hardens production.

Two supporting deliverables close the recurrence loop:

1. **Dev-RPC-body drift assertion** — the existing `dev-migration-drift-probe`
   only checks the `_schema_migrations` **ledger**, so a function body that
   drifted while the ledger stayed intact is invisible. Add a live-body
   assertion (`pg_get_functiondef`) for security-critical byok RPCs so THIS
   drift class pages loudly next time.
2. **Self-diagnosing test failure** — on a double-trip, dump the live
   `pg_get_functiondef` into the assertion message so the next occurrence is
   root-caused from the CI log alone (blind-surface structured probe,
   plan-gate §2.9.2). Invariant C is **not** weakened.

## Premise Validation

Checked at plan time (Phase 0.6): (a) **CI log** for the cited red run
(`28619386206`) — decisive: failing assertion is Invariant C
(`at cumulative=700: expected true to be false`), a double kill-switch trip,
**not** the load/clock/contention flake the issue body hypothesised.
(b) **RPC source drift** — `record_byok_use_and_check_cap` is redefined across
migrations 046 → **061** (6-arg `p_workspace_id`); 073 touches only RLS, 093 is
a different RPC (`acquire_slot`). The **latest** body (mig 061:81-146) **still
contains `FOR UPDATE`** and the `v_paused_at IS NULL AND v_total > v_cap`
guard — so this is **not** a source regression that dropped the lock.
(c) **Own capability claim** — verified `cron-dev-migration-drift.ts` checks
`_schema_migrations` ledger drift only and does **not** assert live RPC bodies
(grep for `pg_get_functiondef` → zero). What held: per-run isolation, source
FOR-UPDATE. What was stale: the issue's cross-run-contention premise and its
test-side fix direction.

## Research Reconciliation — Issue Premise vs. Codebase Reality

| Issue #5917 claim | Reality (verified) | Plan response |
|---|---|---|
| "Concurrent CI runs contend on the same `FOR UPDATE` row / controlled-N serialization" | Founder row is **per-run unique** (random email → unique `users.id`); lock + SUM are `founder_id`-scoped. No cross-run row contention. | Reject the contention premise; do not add a "row namespace" (already exists). |
| Fix = "isolate the fixture per-run / dedicated row namespace" | Already implemented (`randomBytes`-derived per-run founder). | Do not touch fixture isolation. |
| "No byok/RPC/migration code changed in the window → environmental" | True for the merge window, but the **live dev RPC body** may still differ from source (drift ≠ git delta). | Phase 0 pulls the live dev `pg_get_functiondef` to decide drift vs genuine. |
| Failing invariant = concurrency/serialization (implied load flake) | Failing invariant is **atomicity double-trip** (Invariant C), Invariant B (serialization) **passed**. | Fix the trip-signal source (`v_tripped := FOUND`); keep Invariant C strict — it is the safety net. |
| "the fix is test-side (serialize / tolerate)" | Tolerating a double-trip would **mask a real cost-ceiling atomicity regression**. | Do NOT weaken the test; fix the RPC + add drift observability. |

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) the required
`tenant-integration-required` check stays red and **every founder's PR merge
is blocked**, or (b) the byok kill-switch (the per-founder LLM cost ceiling)
mis-fires under concurrency — double-pausing, or, if the lock is genuinely
broken on dev/prod, failing to trip and letting a founder's spend slip past
their cap.

**If this leaks, the user's money/cost-control is exposed via:** a
non-atomic `record_byok_use_and_check_cap` that fails to stamp
`runtime_paused_at` on the winning call → runaway BYOK spend on the founder's
own API key past the cap they set.

**Brand-survival threshold:** `single-user incident` — the byok kill-switch
is the cost-containment safety net; one founder's broken ceiling is a
brand-survival event. `requires_cpo_signoff: true` (frontmatter);
`user-impact-reviewer` runs at review-time.

## Hypotheses

Phase 0 is diagnosis-first (per the "recurring production symptom → verify
which code path actually executes on the affected surface" discipline). The
decisive read is the **live dev RPC body**, not code-reading.

- **H1 — dev-DB RPC drift (leading).** `pg_get_functiondef` on dev returns a
  `record_byok_use_and_check_cap` body lacking the mig-061 `FOR UPDATE` /
  guard. Evidence for: **persistence** (2 consecutive reds + re-run red).
  Fix: apply migration 121 (idempotent `CREATE OR REPLACE`) to dev →
  reconciles + hardens.
- **H2 — genuine trip-signal fragility.** dev body **matches** mig 061 (FOR
  UPDATE present) yet still double-tripped → the pre-read-snapshot trip signal
  is the fault. Fix: the same migration 121 (`v_tripped := FOUND`) is the
  primary fix, not defense-in-depth.
- **H3 — leftover/global state (rejected at plan time).** Founder is per-run
  unique and SUM/lock are founder-scoped; leftover rows from a crashed run
  land under a different `founder_id` and cannot affect this founder's trip.
  Phase 0 confirms by checking the founder row is fresh — but this is not the
  cause.

Because migration 121 is correct and idempotent under H1 **and** H2, the plan
does **not** block on the branch verdict — it records the verdict for the
learning and proceeds with the same deliverable either way.

## Implementation Phases

### Phase 0 — Live evidence (read-only, decisive)

0.1 Pull the live dev definition via Supabase MCP (`execute_sql`, dev project
    per `hr-dev-prd-distinct-supabase-projects`):
    `SELECT pg_get_functiondef('public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure);`
    Record whether it contains `FOR UPDATE` and how it derives `v_tripped`.
0.2 `mcp__…__list_migrations` on dev — confirm 061/064/093 are recorded;
    correlate against any dev-migration apply near 2026-07-02 20:00 UTC.
0.3 Re-run `tenant-integration` on current `main` HEAD in a quiet CI window
    (`gh workflow run tenant-integration.yml --ref main`); capture green
    (transient) vs red (persistent). Persistent red ⇒ H1.
0.4 Record the H1/H2 verdict in the plan/learning. Proceed with Phase 1
    regardless (migration 121 is correct under both).

### Phase 1 — Authoritative trip-signal migration (RED→GREEN)

1.1 **Write failing structural test first** (`cq-write-failing-tests-before`):
    extend `apps/web-platform/test/supabase-migrations/046-runtime-cost-state.test.ts`
    (or add `121-byok-cap-trip-from-found.test.ts`) with a statement-order
    assertion that the new body derives the trip from `FOUND` after the
    guarded `UPDATE` (regex over the migration SQL), and that `FOR UPDATE` is
    retained. RED against current source.
1.2 Add migration `apps/web-platform/supabase/migrations/121_byok_cap_trip_from_found.sql`
    (verify `121` is the next free number at /work — highest is 120):
    `CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)`
    with the mig-061 body **except** the trip block becomes
    `IF v_total > v_cap THEN UPDATE … WHERE … AND runtime_paused_at IS NULL; v_tripped := FOUND; END IF;`.
    Retain `FOR UPDATE`, the audit-INSERT-first ordering, the strict `>`
    predicate, `SECURITY DEFINER`, and `SET search_path = public, pg_temp`
    (`cq-pg-security-definer-search-path-pin-pg-temp`). Re-issue the same
    `REVOKE`/`GRANT` grants as mig 061. Read migrations 118-120 first for the
    in-transaction DDL constraint convention (no `CONCURRENTLY`).
1.3 Add `121_byok_cap_trip_from_found.down.sql` restoring the mig-061 body
    verbatim (documented knowingly-prior state in the down header).
1.4 GREEN the structural test.

### Phase 2 — Reconcile dev + confirm the required check green

2.1 Apply migration 121 to dev via Supabase MCP `apply_migration` (dev
    project). This reconciles any H1 drift AND installs the hardened body.
2.2 Re-run `tenant-integration` against the PR branch head; confirm
    `byok-kill-switch.atomicity.tenant-isolation.test.ts` and
    `tenant-integration-required` are **green**. (Note: dev migration apply
    is a Supabase-MCP path, NOT operator SSH — `hr-all-infrastructure…`.)

### Phase 3 — Dev-RPC-body drift guard (observability)

3.1 Extend the `dev-migration-drift-probe` composite action (invoked by
    `.github/workflows/scheduled-dev-migration-drift.yml`; scheduled by
    `apps/web-platform/server/inngest/functions/cron-dev-migration-drift.ts`)
    to assert, for a small allowlist of security-critical byok RPCs
    (`record_byok_use_and_check_cap`, `check_and_record_byok_delegation_use`),
    that the live `pg_get_functiondef` body contains the load-bearing markers
    (`FOR UPDATE`, `v_tripped := FOUND`). Emit a `::error::` (fail the probe)
    + `reportSilentFallback` mirror when a marker is missing — a **structured,
    discriminating** signal naming the function + missing marker (blind-surface
    probe, §2.9.2). Keep the credential in the ephemeral runner (no prod-host
    parking — matches the cron's HARD NON-GOAL).
3.2 Structural test for the new probe assertion (mock the two body shapes:
    present-marker → pass, missing-marker → fail).

### Phase 4 — Self-diagnosing test failure (no invariant weakening)

4.1 In `byok-kill-switch.atomicity.tenant-isolation.test.ts`, wrap the
    Invariant C block so that on a double-trip it fetches
    `pg_get_functiondef('public.record_byok_use_and_check_cap…')` via the
    service client and includes the live body (or a `FOR UPDATE`/`FOUND`
    presence summary) in the assertion message. Invariant C stays strict
    (exactly one trip). This turns the next occurrence into a
    self-root-causing CI log.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-dev-migration-drift.ts` — (Phase 3, if the body assertion is threaded through the scheduler; otherwise the composite action only). Grep the composite action path first.
- `.github/workflows/scheduled-dev-migration-drift.yml` / its `dev-migration-drift-probe` composite action — add the RPC-body assertion (Phase 3.1).
- `apps/web-platform/test/supabase-migrations/046-runtime-cost-state.test.ts` — statement-order assertion for the FOUND-based trip (Phase 1.1) OR a new sibling test file.
- `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` — self-diagnosing failure dump only; **Invariant C unchanged** (Phase 4).

## Files to Create

- `apps/web-platform/supabase/migrations/121_byok_cap_trip_from_found.sql` (verify next number at /work).
- `apps/web-platform/supabase/migrations/121_byok_cap_trip_from_found.down.sql`.
- (optional) `apps/web-platform/test/supabase-migrations/121-byok-cap-trip-from-found.test.ts` if not folding into the 046 test.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — Live dev `pg_get_functiondef('public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure)` returns a body containing both `FOR UPDATE` and `v_tripped := FOUND` (post-apply). Paste the query output in the PR body.
- [ ] **AC2** — Migration 121's SQL contains, in order: `FOR UPDATE`, `INSERT INTO public.audit_byok_use`, the `SUM(token_count * unit_cost_cents)` prior-hour rollup, `IF v_total > v_cap THEN`, `UPDATE public.users … WHERE id = p_founder_id AND runtime_paused_at IS NULL`, `v_tripped := FOUND` — verified by the structural test (Phase 1.1), which is RED before the migration and GREEN after.
- [ ] **AC3** — Migration 121 retains `SECURITY DEFINER` + `SET search_path = public, pg_temp` and re-issues the mig-061 `REVOKE`/`GRANT` grants (grep the migration; `cq-pg-security-definer-search-path-pin-pg-temp`).
- [ ] **AC4** — `byok-kill-switch.atomicity.tenant-isolation.test.ts` Invariant C is unchanged (exactly-one-trip; `git diff` shows only an added failure-diagnostic branch, no assertion relaxation).
- [ ] **AC5** — Dev-migration-drift probe asserts the byok RPC-body markers and FAILs (with a `::error::` naming the function + missing marker) when a marker is absent — verified by the Phase 3.2 structural test (both body shapes).
- [ ] **AC6** — Typecheck green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`). Structural migration tests green via the package's actual runner (check `package.json scripts` + `vitest.config.ts` `include` globs — path must satisfy the runner's discovery glob).
- [ ] **AC7** — `tenant-integration` run on the PR branch is green: the byok atomicity test passes and `tenant-integration-required` reports success. Link the run.
- [ ] **AC8** — Down migration `121_*.down.sql` restores the mig-061 body verbatim (diff against mig 061 lines 81-146).

### Post-merge (operator/automated)

- [ ] **AC9** — Migration 121 applied to dev via Supabase MCP `apply_migration` (Phase 2.1); `list_migrations` shows 121 recorded. Automatable — NOT operator SSH.
- [ ] **AC10** — Post-merge `tenant-integration` on `main` HEAD green (confirms `main`'s required check unblocked).
- [ ] **AC11** — Record the H1/H2 verdict (drift vs genuine) in a `knowledge-base/project/learnings/` file (directory + topic only, no hardcoded date filename).

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering (CTO)

**Status:** carried to deepen-plan / review (pipeline)
**Assessment:** A concurrency-atomicity change to a `SECURITY DEFINER`
cost-ceiling RPC on the founder-money path. Core risk is the plpgsql trip
semantics (`FOUND` after a guarded `UPDATE`) and migration safety
(in-transaction DDL, grants, down-migration). `data-integrity-guardian` +
`architecture-strategist` at deepen-plan/review are the load-bearing lenses
(single-user-incident threshold — see plan-review-vs-deepen-plan learning).
No Product/UX surface.

### Product/UX Gate

Not applicable — no file under `components/**`, `app/**/page.tsx`, or
`app/**/layout.tsx`. Mechanical UI-surface override did not fire.
**Tier:** NONE.

## Architecture Decision (ADR/C4)

**No new architectural decision.** Deriving `v_tripped := FOUND` is a
*refinement* of the existing PR-F #3940 / migration-046 `FOR UPDATE`
atomicity invariant (Kieran P1.1), not a new tenancy/ownership/substrate/
resolver boundary. No existing ADR's `## Decision` is reversed.

**C4 views:** no impact. Checked all three model files
(`model.c4`, `views.c4`, `spec.c4`): the change is internal DB logic inside the
already-modeled `supabase = database "Supabase PostgreSQL"` store (model.c4:156).
Enumerated for this change — (a) external human actors: none new (founder/
agent already modeled); (b) external systems/vendors: none new (the
`engine -> anthropic "LLM calls with BYOK keys"` edge, model.c4:249, is
unchanged); (c) containers/data-stores: `users` + `audit_byok_use` live inside
the already-modeled `supabase` store; (d) access relationships: unchanged
(service-role-only RPC, no new caller edge). No `.c4` edit required.

## Observability

```yaml
liveness_signal:
  what: "dev-migration-drift-probe asserts live byok RPC bodies contain FOR UPDATE + v_tripped:=FOUND"
  cadence: "every 6h (scheduled-dev-migration-drift.yml, dispatched by cron-dev-migration-drift)"
  alert_target: "GHA ::error:: (fails the probe run) + Sentry issues stream via reportSilentFallback"
  configured_in: ".github/workflows/scheduled-dev-migration-drift.yml + apps/web-platform/server/observability"
error_reporting:
  destination: "Sentry (reportSilentFallback) for dispatch/probe failure; GHA annotation for body-marker miss"
  fail_loud: true
failure_modes:
  - mode: "dev RPC body drifts (loses FOR UPDATE or the FOUND-based trip)"
    detection: "probe pg_get_functiondef marker check FAILs, naming the function + missing marker (in-surface, discriminating)"
    alert_route: "GHA ::error:: + Sentry"
  - mode: "byok atomicity test double-trips again in CI"
    detection: "Invariant C failure message now embeds the live pg_get_functiondef body (self-diagnosing)"
    alert_route: "tenant-integration CI log + tenant-integration-required red"
  - mode: "migration 121 not applied to dev"
    detection: "list_migrations missing 121; drift probe ledger check"
    alert_route: "drift probe ::warning:: + AC9"
logs:
  where: "GitHub Actions run logs (tenant-integration, scheduled-dev-migration-drift) + Sentry"
  retention: "GHA default (90d) / Sentry retention"
discoverability_test:
  command: "gh run view <run-id> --log-failed | grep 'record_byok_use_and_check_cap' ; mcp execute_sql \"SELECT pg_get_functiondef('public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure)\""
  expected_output: "body contains 'FOR UPDATE' and 'v_tripped := FOUND'; probe error names the function on drift"
```

## Open Code-Review Overlap

None — no open `code-review`-labelled issue references the byok RPC, the
atomicity test, or the dev-migration-drift probe (checked at plan time).

## GDPR / Compliance

Migration + `audit_byok_use` are `.sql`/regulated-data-adjacent surfaces, so
`gdpr-gate` nominally applies and runs advisory at deepen-plan/review. **No new
processing activity**: the change alters only the trip-signal derivation, not
what data is collected, retained, or disclosed (`audit_byok_use` WORM rows,
`founder_id`, cost — all pre-existing). Expected verdict: no Critical fold-in.

## Test Scenarios

1. **Structural (unit, migration):** migration 121 SQL derives the trip from
   `FOUND`, retains `FOR UPDATE`, strict `>`, audit-INSERT-first, grants.
2. **Live atomicity (tenant-integration, opt-in):** existing Invariant C now
   passes on dev post-apply; on a hypothetical regression the failure message
   embeds the live body.
3. **Drift probe (unit):** present-marker body → pass; missing-marker body →
   `::error::` naming the function.
4. **Down migration:** restores mig-061 body verbatim.

## Sharp Edges

- **Do NOT weaken Invariant C** to "tolerate" the double-trip — it is the
  safety net for a real cost-ceiling atomicity regression. The whole test
  exists (#3981) to catch a lost `FOR UPDATE` / weakened predicate. Fix the
  RPC, not the assertion.
- **A plan whose `## User-Brand Impact` is empty/`TBD` fails deepen-plan
  Phase 4.6.** It is filled (threshold `single-user incident`).
- **`v_tripped := FOUND` semantics:** `FOUND` after `UPDATE` is true iff ≥1
  row changed. Only one concurrent caller matches `runtime_paused_at IS NULL`
  → exactly one trip. Verify with a rolled-back live repro
  (`BEGIN; SELECT record_byok_use_and_check_cap(…); ROLLBACK;`) at /work
  before trusting the semantics.
- **Migration number:** highest is currently 120 — confirm `121` is free at
  /work (`ls apps/web-platform/supabase/migrations/`); a colliding number
  silently shadows.
- **Runner discovery globs:** the migration test path must satisfy
  `apps/web-platform/vitest.config.ts` `include:` (grep it) — a co-located or
  mis-globbed test is silently never run.
- **Dev apply is Supabase-MCP, not SSH.** Reconciling dev goes through
  `apply_migration` / the existing dev-apply path, never
  `ssh … && psql` (`hr-all-infrastructure-provisioning-servers`).
- **`Ref #5917`, not `Closes #5917`, if any step is post-merge/ops** — but
  here the required check unblocks pre-merge once dev is reconciled, so
  `Closes #5917` is correct provided AC7/AC10 are green before merge.
