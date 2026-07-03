---
title: "feat(observability): assert live byok RPC bodies in the dev-migration-drift probe + self-diagnosing atomicity failure"
date: 2026-07-03
issue: 5920
ref: 5917
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(observability): assert live byok RPC bodies in the dev-migration-drift probe + self-diagnosing atomicity failure

> Spec lacks valid `lane:` (no `spec.md` for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

Follow-up hardening split out of the #5917 byok cap-boundary double-trip hotfix
(fixed by migration `121_byok_cap_trip_from_found.sql`, `v_tripped := FOUND`).
The #5917 root cause was a **dev-only RPC body drift**: a migration
`byok_cap_kill_tripped_while_paused` (supabase ledger version
`20260702195538`) applied directly to dev via MCP and **never committed**. It
was invisible to the existing `dev-migration-drift-probe`, which only
cross-references the `_schema_migrations` **ledger** (filename + content_sha)
against `origin/main` — it never inspects live **function bodies**. A
`CREATE OR REPLACE FUNCTION` that rewrites a body without a tracked
`_schema_migrations` row (direct `psql`/MCP apply) is a documented blind spot
of the ledger probe (`2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`).

Two hardening deliverables (they do not move any red check green, so they were
correctly deferred out of the #5917 P1 hotfix):

1. **Dev-RPC-body drift guard (observability).** Extend the
   `dev-migration-drift-probe` composite action to assert, for a small
   allowlist of security-critical byok RPCs, that the **live**
   `pg_get_functiondef` body contains the load-bearing markers. On drift, emit
   a `::error::` annotation naming the function + missing marker, plus a
   Sentry event (field-equivalent to `reportSilentFallback`) from the
   ephemeral runner. Add a source-side structural test guarding both body
   shapes.

2. **Self-diagnosing atomicity failure.** In
   `byok-kill-switch.atomicity.tenant-isolation.test.ts`, on an
   Invariant-C failure, fetch the live `pg_get_functiondef` body and embed it
   in the failure message. **Invariant C stays strict** (exactly-one-trip; no
   assertion relaxation) — the next drift-induced double-trip diagnoses itself
   in the CI log instead of requiring a manual `pg_get_functiondef` read.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "assert … the live body contains the load-bearing markers (`FOR UPDATE`, `v_tripped := FOUND`)" — reads as a **flat, shared** marker set for both RPCs | `v_tripped := FOUND` exists **only** in `record_byok_use_and_check_cap` (mig 121). The delegation RPC `check_and_record_byok_delegation_use` (current def = mig `084_byok_delegation_withdrawals.sql:344`) has **no** trip flag — it enforces caps via `RAISE EXCEPTION 'byok_delegations:hourly_cap_exceeded'` / `daily_cap_exceeded` and locks the delegation row with its own `FOR UPDATE` (084:27). | The allowlist is a **per-function marker map**, not a global set. `record_byok_use_and_check_cap` → `["FOR UPDATE", "v_tripped := FOUND"]`. `check_and_record_byok_delegation_use` → `["FOR UPDATE", "hourly_cap_exceeded", "daily_cap_exceeded"]`. This is the single most load-bearing correction in this plan. |
| "fetch `pg_get_functiondef` via the service client" (deliverable 2) | supabase-js exposes **no** raw-SQL path over PostgREST; there is **no** `pg`/`postgres` npm dep in `apps/web-platform`; the one existing test that names `pg_get_functiondef` (`byok-delegations-worm-column-enum.test.ts`) only *mentions* it in a comment and actually reads the migration **source** file. | Deliverable 2 needs a client-reachable introspection path. **Recommended (Option A):** a minimal service-role-only `SECURITY DEFINER` RPC `public.pg_functiondef(regprocedure) RETURNS text` (new migration 122), called via `service.rpc(...)`. **Fallback (Option B):** add `postgres` (porsager, zero-dep) as a devDependency and connect with `DATABASE_URL_POOLER` (already in the dev doppler env). Recommend A (faithful to "via the service client", convention-aligned); deepen-plan security-sentinel + data-integrity-guardian must ratify the grant scope. |
| "reportSilentFallback Sentry mirror" (deliverable 1) | `reportSilentFallback` is a **TypeScript server function** (`server/observability.ts:216`) needing the Sentry SDK + Next server context — it cannot run in the bash composite action. The credential must "stay in the ephemeral runner". | The mirror is a Sentry **event** emitted from bash via `curl` to the DSN's `store/` endpoint, carrying the same field vocabulary (`feature`/`op` as tags; `fn` + `missing_marker` in tags/extra). Canonical precedent: `web-platform-release.yml:893-933` (DSN parse → `/api/{project}/store/` → `X-Sentry-Auth` header → jq payload → 3-retry → warn-not-fail on Sentry outage). |
| existing ledger probe fails-loud (enforcement) | The composite action is **visibility-only** (`::warning::`, never non-zero) and is invoked by **two** workflows: `scheduled-dev-migration-drift.yml` **and** `tenant-integration.yml` (PR CI). | Body-marker drift emits `::error::` + Sentry event in **both** contexts, but the action never exits non-zero on its own. A new `fail-on-rpc-body-drift` input (default `false`) lets the **scheduled** workflow fail-loud (`true`) without reddening unrelated PRs (`tenant-integration.yml` keeps `false`). |

## User-Brand Impact

**If this lands broken, the user experiences:** a future dev-only body drift on
`record_byok_use_and_check_cap` or `check_and_record_byok_delegation_use` goes
undetected (probe false-greens, or the Sentry mirror silently fails to emit), OR
the self-diagnosis embeds a stale/empty body — so the next drift-induced
double-trip reddens the `tenant-integration-required` check (blocking every
founder's merges, as in #5917) with no fast-path root-cause in the CI log.

**If this leaks, the user's data is exposed via:** n/a for user data — the
probe reads function **definitions** (DDL introspection), never user rows. The
Option-A introspection RPC (`pg_functiondef`) returns function **source** to
`service_role` only (already omnipotent); no PII / user data / new grant to
`anon`/`authenticated`.

**Brand-survival threshold:** `aggregate pattern` — this change's own failure
mode is a *compounding observability gap* (the drift class recurs and stays
invisible), not a direct single-user incident. The invariant it guards (the
byok cost ceiling) is single-user-incident-class, but the guard's failure is
detection-absence. No per-PR CPO sign-off required.

## Premise Validation

Checked: issue **#5920** is `OPEN`, no closing PR. Referenced **#5917** was
fixed by migration `121_byok_cap_trip_from_found.sql` (present on disk;
`v_tripped := FOUND` at 121:112, `FOR UPDATE` at 121:72). All cited artifacts
exist: composite action `.github/actions/dev-migration-drift-probe/action.yml`;
workflow `.github/workflows/scheduled-dev-migration-drift.yml`; cron
`apps/web-platform/server/inngest/functions/cron-dev-migration-drift.ts`; test
`apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`;
learning `knowledge-base/project/learnings/2026-07-02-byok-cap-double-trip-was-dev-rpc-drift-not-contention.md`.
The delegation RPC's current definition is mig 084 (no later redefinition
found through mig 121). Nothing stale. No ADR corpus conflict (this hardens an
existing observability probe; it does not adopt a rejected mechanism).

## Research Insights

**Load-bearing files:**
- `.github/actions/dev-migration-drift-probe/action.yml` — the probe (bash + psql). Extend after the ledger-drift check. Filename-shape whitelist + `sh -c` DATABASE_URL_POOLER expansion pattern already established (lines 69-78).
- `.github/workflows/scheduled-dev-migration-drift.yml` (workflow_dispatch, dispatched by the Inngest cron) and `.github/workflows/tenant-integration.yml` — the **two** callers; both must forward the new `sentry-dsn` input.
- `apps/web-platform/supabase/migrations/121_byok_cap_trip_from_found.sql` — cap RPC current body (markers verified executable-only, not in comments).
- `apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.sql:344` — delegation RPC current body; markers `FOR UPDATE` (084:27), `hourly_cap_exceeded`/`daily_cap_exceeded` RAISE guards.
- `apps/web-platform/test/supabase-migrations/046-runtime-cost-state.test.ts` — structural-test convention: `readFileSync` + comment-strip `sql.replace(/--[^\n]*/g, "")` + `.toMatch`.
- `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts:206-241` — Invariant C (per-pair + `trippedCount === 1`).
- `.github/workflows/web-platform-release.yml:893-933` — canonical bash Sentry **event** emit; `.github/actions/sentry-heartbeat/action.yml` — DSN-secret-guard precedent.
- `server/observability.ts:149-164` — `SilentFallbackOptions` field vocabulary (`feature`, `op`, `extra`, `tags`) to mirror in the bash event.

**Institutional learnings applied (from learnings-researcher):**
- `2026-05-31-worm-bypass-migration-comment-literal-trips-comment-stripped-test.md` — comment-strip `/--[^\n]*/` removes line comments but **not** SQL string literals (`COMMENT ON FUNCTION '…'`). Our markers are verified executable-only, but comment-strip the body **before** marker match anyway (bash: `sed 's/--.*//'`; TS: `.replace(/--[^\n]*/g,"")`).
- `2026-06-19-sql-function-body-parser-must-anchor-to-create-not-bare-function.md` — anchor the structural test's "find defining migration" regex to `CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.<fn>` (bare `FUNCTION public.<fn>` also matches REVOKE/GRANT/COMMENT lines). Fail loud if no defining migration resolves.
- `security-issues/2026-04-17-log-injection-unicode-line-separators.md` — sanitize any DB-derived value echoed into `::error::` with `/[\x00-\x1f\x7f  ]/g`. Mitigation: the annotation echoes only **static allowlist literals** (fn name + marker); the DB-derived **body is never echoed** into an annotation (only into the vitest failure message, deliverable 2, which is not a runner annotation).
- `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md` — parse the DSN's own host/region substring for the POST target; never default a cluster.
- `2026-03-20-github-actions-error-annotations-require-runner.md` — `::error::` only parses on the runner (we run on the runner ✓).
- `2026-05-07-vitest-domock-factory-throw-wrapped-message.md` — assert on observable output, not inner error text (deliverable 2 embeds the body in the assertion **message**, which vitest preserves for a real `expect` failure).

**Verified CLI/config facts:** test runner = `vitest` (`package.json:15`, `test:ci = vitest run`); typecheck = `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces`); `unit` project include glob = `test/**/*.test.ts` (`vitest.config.ts:44`) — new structural test must live under `apps/web-platform/test/**`. `NEXT_PUBLIC_SENTRY_DSN` is an existing repo secret (used by 4 workflows).

## Implementation Phases

> TDD (`cq-write-failing-tests-before`): the structural test (Phase 2) and the
> atomicity self-diagnosis (Phase 4) are RED-first where a source assertion
> exists; the bash probe (Phase 1) is exercised via extracted-snippet
> `bash -c` + a fixture body.

### Phase 0 — Preconditions (verify, no code)
- `grep -nE 'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.check_and_record_byok_delegation_use' apps/web-platform/supabase/migrations/*.sql` — confirm 084 is the highest-numbered definer (through 121).
- Confirm markers are executable-only in both bodies (comment-strip then grep): `sed 's/--.*//' 121_*.sql | grep -c 'v_tripped := FOUND'` == 1; same for `FOR UPDATE`; delegation cap markers in 084.
- Confirm `pg_get_functiondef` returns a single overload for each proname on dev (via the probe query shape) — if >1, Phase 1 iterates all oids.

### Phase 1 — Probe extension (deliverable 1)
1. `action.yml`: add inputs `sentry-dsn` (required: false, default `''`) and `fail-on-rpc-body-drift` (default `'false'`); add output `rpc-body-drift-detected`.
2. New composite step `assert-byok-rpc-body-markers` (after the ledger probe). For each fn in the per-function marker map:
   - `body=$(doppler run … -- sh -c 'psql "$DATABASE_URL_POOLER" … -c "SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='"'"'public'"'"' AND p.proname='"'"'<fn>'"'"';"')` — reuse the existing `sh -c` env-expansion + psql-failure `::warning::`+`exit 0` pattern.
   - 0 rows → `::error::` "<fn> not found on dev" + Sentry event; >1 rows → assert markers across all bodies.
   - `stripped=$(printf '%s' "$body" | sed 's/--.*//')`; for each marker `grep -qF -- "$marker" <<<"$stripped"` else accumulate `<fn>::<marker>`.
   - On any miss: `echo "::error::dev-migration-drift: RPC public.<fn> is MISSING load-bearing marker \"<marker>\" — live dev body drifted from source (#5920; see mig 121/084)"` (static literals only), emit Sentry event, set `rpc-body-drift-detected=true`.
3. Sentry event helper (inline bash, per `web-platform-release.yml:893-933`): DSN-presence guard (`::warning::`+continue), parse `PUBLIC_KEY`/`HOST`/`PROJECT_ID`, `jq -nc` payload `{message, level:"error", platform:"other", tags:{feature:"dev-migration-drift", op:"rpc-body-marker-drift", fn:<fn>}, extra:{missing_marker:<marker>}}`, POST `store/` with `X-Sentry-Auth`, 3-retry, curl-fail → `::warning::` (observability degraded, does not change drift disposition).
4. If `fail-on-rpc-body-drift == 'true'` AND `rpc-body-drift-detected == 'true'` → `exit 1` (fail the step) at the end of the step.
5. `scheduled-dev-migration-drift.yml`: forward `sentry-dsn: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}` and `fail-on-rpc-body-drift: 'true'`.
6. `tenant-integration.yml`: forward `sentry-dsn: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}` (leave `fail-on-rpc-body-drift` default `false` — annotation + Sentry on PRs, non-blocking).

### Phase 2 — Structural source-side test (deliverable 1)
1. New file `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts`.
2. Define `RPC_BODY_MARKERS` (TS object) — the SAME map as the bash probe, with a cross-reference comment naming `action.yml` (single-source-of-truth Sharp Edge).
3. For each fn: glob `supabase/migrations/*.sql` (exclude `*.down.sql`), pick the **highest-numbered** file matching `/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.<fn>\b/`, `readFileSync`, comment-strip `/--[^\n]*/g`, assert each marker via `.toContain`. `throw` (fail loud) if no defining migration resolves.
4. This guards that committed source never regresses the markers (keeps the live-probe allowlist honest) and self-updates as the RPC is redefined in later migrations.

### Phase 3 — Introspection RPC (deliverable 2, Option A — recommended)
1. New migration `apps/web-platform/supabase/migrations/122_dev_pg_functiondef_introspection.sql`: `CREATE OR REPLACE FUNCTION public.pg_functiondef(p_fn regprocedure) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$ SELECT pg_get_functiondef(p_fn); $$;` + `REVOKE ALL … FROM PUBLIC, anon, authenticated;` + `GRANT EXECUTE … TO service_role;` + `COMMENT ON FUNCTION`. `.down.sql` drops it.
2. Wrap in `BEGIN;/COMMIT;` (no `CREATE INDEX CONCURRENTLY` — Supabase transaction-wraps migrations).
3. **deepen-plan gate:** security-sentinel + data-integrity-guardian must ratify the grant scope; if rejected, pivot to Option B (porsager `postgres` devDep + `DATABASE_URL_POOLER`, no prod DDL — obey `cq-before-pushing-package-json-changes`).

### Phase 4 — Self-diagnosing atomicity failure (deliverable 2)
1. In `byok-kill-switch.atomicity.tenant-isolation.test.ts`, before the strict Invariant-C assertions, compute `willFail = trippedCount !== 1 || pairs.some(p => p.kill_tripped !== (p.cumulative_cents === tripCumulative))`.
2. If `willFail`, `liveBody = (await service.rpc("pg_functiondef", { p_fn: "public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)" })).data ?? "<functiondef fetch failed>"`.
3. Pass `liveBody` into the **message** argument of the existing strict `expect(...)` calls (per-pair loop message + `trippedCount` message). **No assertion is relaxed** — Invariant C still requires exactly-one-trip; the body only enriches the failure message.
4. Guard the fetch so a `pg_functiondef` error never masks the real Invariant-C failure (fallback string, not a throw before the `expect`).

## Files to Create
- `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts` — structural source-side marker guard.
- `apps/web-platform/supabase/migrations/122_dev_pg_functiondef_introspection.sql` + `.down.sql` — Option-A introspection RPC (subject to Phase 3 security ratification).

## Files to Edit
- `.github/actions/dev-migration-drift-probe/action.yml` — body-marker probe step, `sentry-dsn`/`fail-on-rpc-body-drift` inputs, `rpc-body-drift-detected` output, bash Sentry emit.
- `.github/workflows/scheduled-dev-migration-drift.yml` — forward `sentry-dsn` + `fail-on-rpc-body-drift: 'true'`.
- `.github/workflows/tenant-integration.yml` — forward `sentry-dsn` (default fail flag).
- `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` — self-diagnosing Invariant-C failure message.

## Acceptance Criteria

### Pre-merge (PR)
1. `RPC_BODY_MARKERS` in `byok-rpc-body-markers.test.ts` maps `record_byok_use_and_check_cap → ["FOR UPDATE","v_tripped := FOUND"]` and `check_and_record_byok_delegation_use → ["FOR UPDATE","hourly_cap_exceeded","daily_cap_exceeded"]`; the structural test passes green against current sources (mig 121, 084).
2. The structural test picks the **highest-numbered** `CREATE OR REPLACE FUNCTION public.<fn>` migration (anchored regex) and comment-strips before asserting; it `throw`s if no definer resolves (verified by a negative fixture).
3. `action.yml` `assert-byok-rpc-body-markers` step, exercised via `bash -c` on an extracted snippet against (a) a fixture body containing all markers → no `::error::`, `rpc-body-drift-detected=false`; (b) a fixture body missing `v_tripped := FOUND` → `::error::` naming fn+marker, `rpc-body-drift-detected=true`.
4. DSN-unset path emits `::warning::` and continues (no `::error::`-swallowing; no non-zero exit from a Sentry outage).
5. `fail-on-rpc-body-drift='true'` + drift → step exits non-zero; default (`false`) → step exits 0 with the `::error::` annotation present.
6. Both caller workflows forward `sentry-dsn`; only `scheduled-dev-migration-drift.yml` sets `fail-on-rpc-body-drift: 'true'` (verified by `grep`).
7. `byok-kill-switch.atomicity.tenant-isolation.test.ts`: Invariant C assertions are byte-for-byte as strict (exactly-one-trip; per-pair; `trippedCount === 1`); only the `expect` **message** args gain the conditional live-body embed. (Diff shows no change to any `.toBe`/`.toEqual` target.)
8. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/supabase-migrations/byok-rpc-body-markers.test.ts` green.
9. `actionlint` on the two edited workflows; extracted `run:` snippets pass `bash -c` syntax check (composite `action.yml` is NOT linted with `actionlint` — it emits spurious schema errors; use `bash -c` for its embedded shell).

### Post-merge (operator/automated)
10. Migration 122 (Option A) applied to dev **and** prd via the existing `web-platform-release.yml#migrate` path (NOT operator SSH) — verified via `mcp__plugin_supabase_supabase__list_migrations` (dev + prd both show `122`).
11. Trigger the scheduled probe once (`gh workflow run scheduled-dev-migration-drift.yml`) and confirm a green run with "No … drift detected" (no false-positive body-marker `::error::`).
12. Live-DB self-diagnosis smoke: run the atomicity test against dev with `TENANT_INTEGRATION_TEST=1` — green (Invariant C passes on the correct mig-121 body; self-diagnosis path is dormant on green).

## Observability

```yaml
liveness_signal:
  what: dev byok-RPC body-marker probe runs inside dev-migration-drift-probe
  cadence: every 6h (Inngest cron cron-dev-migration-drift → workflow_dispatch)
  alert_target: Sentry (tags feature=dev-migration-drift, op=rpc-body-marker-drift) + red scheduled run
  configured_in: cron-dev-migration-drift.ts + scheduled-dev-migration-drift.yml + dev-migration-drift-probe/action.yml
error_reporting:
  destination: Sentry event via curl to NEXT_PUBLIC_SENTRY_DSN store/ endpoint (from the ephemeral runner)
  fail_loud: "::error:: annotation naming fn+missing_marker; scheduled job exits 1 (fail-on-rpc-body-drift=true)"
failure_modes:
  - mode: RPC live body missing a load-bearing marker (dev drift from source)
    detection: probe grep on pg_get_functiondef (comment-stripped) → Sentry event + ::error::
    alert_route: Sentry tag query feature=dev-migration-drift op=rpc-body-marker-drift (fn + missing_marker discriminate the exact function)
  - mode: allowlisted RPC missing entirely on dev
    detection: pg_proc returns 0 rows → ::error:: + Sentry event
    alert_route: same Sentry tag query
  - mode: Sentry DSN unset or curl fails
    detection: "::warning:: in step log; drift disposition unchanged"
    alert_route: scheduled-run step log + absence of expected Sentry event
  - mode: probe psql query fails
    detection: existing "::warning:: + drift-detected=false + exit 0" path
    alert_route: scheduled-run step log
logs:
  where: GitHub Actions step log (scheduled-dev-migration-drift run) + Sentry event
  retention: Actions ~90d; Sentry per project retention
discoverability_test:
  command: "gh run list --workflow scheduled-dev-migration-drift.yml --limit 5; Sentry search 'feature:dev-migration-drift op:rpc-body-marker-drift'"
  expected_output: "on drift, a red scheduled run + a Sentry event naming fn + missing_marker (NO ssh)"
```

**Blind-surface note (Phase 2.9.2):** the GHA runner is an ephemeral, operator-blind
execution surface. The in-surface probe emits the Sentry event **from the runner
itself**, with `fn` + `missing_marker` as discriminating structured fields that
identify the exact function and marker in one event — not a host-side-only signal.

## Architecture Decision (ADR/C4)

**No architectural decision.** This hardens an existing observability probe (no
new substrate, no tenancy/trust-boundary move, no ADR reversal). The Option-A
`pg_functiondef` helper is a read-only, `service_role`-only introspection
function — not a resolver/dispatch/trust boundary change (security-sentinel to
confirm the grant in deepen-plan).

**C4 completeness (all three model files read):** checked
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.
No new **external actor** (the GHA ephemeral runner is CI, not a modeled
container), no new **external system** (Sentry and the dev-Supabase project are
already modeled — `model.c4` Inngest/Supabase containers), no new **data store**
(read-only DDL introspection adds none), no changed **access relationship** (no
ownership/tenancy edge changes). → No C4 edit required.

## Domain Review

**Domains relevant:** none

Infrastructure / observability / tooling change. No user-facing surface (no
`components/**`, `app/**/page.tsx`), no financial/legal/marketing/sales/support
implication, no new vendor or pricing change. The invariant it guards (the byok
cost ceiling) is finance-adjacent, but this change touches only the *observability*
of an existing safety net, not billing or pricing logic. Engineering review is
covered by the plan + plan-review + deepen-plan (single-user-adjacent → deepen-plan
domain triad recommended).

## Infrastructure (IaC)

No new infrastructure. Reuses the **existing** `NEXT_PUBLIC_SENTRY_DSN` repo
secret (already consumed by `web-platform-release.yml`, `sentry-audit-gate.yml`,
`reusable-release.yml`, `apply-sentry-infra.yml`). No new server, service, cron
(the Inngest cron already exists), vendor, DNS, TLS, or firewall rule. The
Option-A migration is applied via the existing `web-platform-release.yml#migrate`
path (a PR merge is the apply mechanism), never operator SSH.

## GDPR / Compliance

Skip (advisory). Reads DDL **definitions** (`pg_get_functiondef`), not regulated
data; introduces no new processing activity. The atomicity test's synthetic
dev `auth.users` creation is pre-existing and unchanged. Option-A returns
function source to `service_role` only.

## Open Code-Review Overlap

None. Queried 61 open `code-review` issues against all six planned file paths
(`dev-migration-drift-probe`, `byok-kill-switch.atomicity`,
`scheduled-dev-migration-drift`, `tenant-integration.yml`, `supabase-migrations`)
— zero matches.

## Test Scenarios

- **Structural (unit):** markers present in current sources → green; a synthetic
  body missing a marker → red; no definer migration → fail-loud throw.
- **Probe (bash-c on extracted snippet):** all-markers fixture → clean; missing-marker
  fixture → `::error::` + `rpc-body-drift-detected=true`; DSN-unset → `::warning::`
  + continue; `fail-on-rpc-body-drift=true` + drift → non-zero exit.
- **Atomicity (live-DB, `TENANT_INTEGRATION_TEST=1`, dev):** green on mig-121 body;
  self-diagnosis path embeds the live body ONLY when `willFail` (verified by a
  temporary marker-break rehearsal, reverted).

## Risks & Sharp Edges

- **Per-function marker map, not a flat set** (Research Reconciliation row 1) —
  `v_tripped := FOUND` belongs only to the cap RPC. Encoding a shared set would
  false-`::error::` on the delegation RPC forever.
- **Marker map duplicated in bash (`action.yml`) and TS (structural test).** Drift
  between the two silently weakens the guard. Cross-reference comment in both;
  deepen-plan may hoist to a shared JSON read by both — evaluate cost vs. benefit.
- **Comment-strip does not remove SQL string literals** (`2026-05-31` learning).
  Markers are verified executable-only today; still comment-strip before match, and
  never pick a marker that also appears in a `COMMENT ON` literal.
- **Anchor the structural test's definer-finder to `CREATE OR REPLACE FUNCTION`**
  (`2026-06-19` learning), not bare `FUNCTION public.<fn>` (matches REVOKE/GRANT/COMMENT).
- **`pg_get_functiondef` overloads:** if a proname ever gains a second overload,
  the probe must iterate all oids (Phase 0 confirms single-overload today).
- **Do NOT echo the DB-derived body into a `::error::` annotation** (log-injection
  vector). Only static allowlist literals go into annotations; the body goes only
  into the vitest failure message (deliverable 2).
- **Sentry outage must never flip the drift disposition** — DSN-unset / curl-fail is
  `::warning::` only.
- **Option A adds prod DDL** for a test-only diagnostic; if security-sentinel rejects
  the introspection RPC, pivot to Option B (test-only pg connection).
- **A plan whose `## User-Brand Impact` section is empty, TBD, or omits the threshold
  will fail deepen-plan Phase 4.6.** This section is filled.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Flat shared marker set for both RPCs | Rejected — `v_tripped := FOUND` is cap-RPC-only; would false-fire on the delegation RPC. |
| Embed migration **source** in the atomicity failure (not live body) | Rejected — #5917 was a live-vs-source drift; source is clean, so source embedding defeats the diagnostic. |
| Option B (porsager `postgres` devDep) as primary | Fallback only — "via the service client" favors an `.rpc()` path; keep B if security rejects the introspection RPC. |
| Fail the composite action non-zero in all contexts | Rejected — would red unrelated PRs on pre-existing dev drift; gated behind `fail-on-rpc-body-drift` (scheduled only). |
