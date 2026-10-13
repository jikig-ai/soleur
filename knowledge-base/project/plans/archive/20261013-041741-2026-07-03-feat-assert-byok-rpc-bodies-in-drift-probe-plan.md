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

## Enhancement Summary

**Deepened on:** 2026-07-03
**Research agents used:** learnings-researcher, security-sentinel, architecture-strategist (+ local repo research)

### Key improvements from deepen-plan review
1. **Option B (test-only porsager `postgres` connection) is now primary; Option A (prod introspection RPC) demoted to fallback** — both reviewers ruled a permanent prod `SECURITY DEFINER` function unjustified for a dev-only test diagnostic (least-privilege / blast-radius). Removes all prod DDL from the default path.
2. **Severity + Sentry emission now track `fail-on-rpc-body-drift`** — scheduled surface is the sole `::error::` + Sentry + fail authority; PR CI stays `::warning::`-only with no Sentry (kills signal erosion, Sentry misattribution to unrelated PRs, and N-duplicate events). Restores the composite action's documented `::warning::`-for-visibility convention.
3. **Marker map promoted to a shared `byok-rpc-markers.json`** read by both the bash probe (`jq`, already required) and the TS structural test — true single source of truth (a comment was ruled insufficient for a security guard).
4. **Explicit tripwire framing** — the marker probe is necessary-not-sufficient (a rewrite can keep both markers and still double-trip); Invariant C stays the strict semantic authority. Flagged the delegation RPC's lack of a live semantic backstop as a follow-up.

### New considerations discovered
- Supabase default-privileges gotcha: Option-A `REVOKE` must name `PUBLIC, anon, authenticated` explicitly (learning `2026-05-06-...`).
- Markers must live inside the `$$…$$` body (`pg_get_functiondef` omits `COMMENT ON`/`REVOKE`/`GRANT`); anchor the definer-finder to `CREATE OR REPLACE FUNCTION`; `grep -qF` is reformat-brittle.
- Sentry `message` pinned to a static literal so the DB body never reaches the Sentry surface; a "fn allowlist is static" comment guards the no-SQLi assumption.
- Security review: all three surfaces (introspection RPC, bash Sentry emit, psql query) are sound; no Critical/High/Medium.

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
   shapes. **This probe is a drift *tripwire* (necessary, not sufficient):**
   it catches the #5917 drift signature and any accidental marker deletion,
   but marker-presence does not *prove* the exactly-one-trip semantics — a
   rewrite could keep both markers and still double-trip. The semantic
   authority remains Invariant C in the atomicity test (deliverable 2), which
   stays strict. A future maintainer MUST NOT relax Invariant C on the belief
   that the marker probe covers it. The delegation RPC has **no** companion
   live atomicity test, so for it the marker probe is the only live guard (its
   `hourly_cap_exceeded`/`daily_cap_exceeded` markers prove the RAISE strings
   exist, not that the `>` comparison logic is intact) — a delegation-RPC
   semantic test is filed as a follow-up.

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
| "fetch `pg_get_functiondef` via the service client" (deliverable 2) | supabase-js exposes **no** raw-SQL path over PostgREST; there is **no** `pg`/`postgres` npm dep in `apps/web-platform`; the one existing test that names `pg_get_functiondef` (`byok-delegations-worm-column-enum.test.ts`) only *mentions* it in a comment and actually reads the migration **source** file. | Deliverable 2 needs a client-reachable introspection path. **Recommended (Option B, revised per deepen-plan security + architecture review):** add `postgres` (porsager, zero-dep) as a **devDependency** and connect with `DATABASE_URL_POOLER` (already in the dev doppler env; same credential class the test already uses under `TENANT_INTEGRATION_TEST=1`) — **no prod DDL**, blast radius confined to the test process. **Fallback (Option A):** a minimal service-role-only `SECURITY DEFINER` RPC `public.pg_functiondef(regprocedure) RETURNS text` (new migration 122), called via `service.rpc(...)`. Both reviewers recommend B over A on least-privilege grounds ("via the service client" is a mechanism suggestion, not a contract — it does not justify a permanent prod introspection function for a dev-only diagnostic). Obey `cq-before-pushing-package-json-changes` for the devDep. |
| "reportSilentFallback Sentry mirror" (deliverable 1) | `reportSilentFallback` is a **TypeScript server function** (`server/observability.ts:216`) needing the Sentry SDK + Next server context — it cannot run in the bash composite action. The credential must "stay in the ephemeral runner". | The mirror is a Sentry **event** emitted from bash via `curl` to the DSN's `store/` endpoint, carrying the same field vocabulary (`feature`/`op` as tags; `fn` + `missing_marker` in tags/extra); `message` is a **static** string (never the DB body). Canonical precedent: `web-platform-release.yml:893-933` (DSN parse → `/api/{project}/store/` → `X-Sentry-Auth` header → jq payload → 3-retry → warn-not-fail on Sentry outage). The Sentry emit is gated to the **scheduled** surface only (see next row). |
| existing ledger probe fails-loud (enforcement) | The composite action is **visibility-only** (`::warning::`, never non-zero) and is invoked by **two** workflows: `scheduled-dev-migration-drift.yml` **and** `tenant-integration.yml` (PR CI). Its own header (action.yml:11-15) documents `::warning::`-for-visibility as the design invariant. | **Severity + Sentry track the `fail-on-rpc-body-drift` input** (revised per architecture review Q1 — restores the action's documented visibility/enforcement split). Scheduled workflow (`fail-on-rpc-body-drift: 'true'`) → `::error::` + Sentry event + `exit 1`. PR CI (`tenant-integration.yml`, default `false`) → `::warning::` only, **no Sentry** (a pre-existing dev-infra drift must not red-annotate or misattribute a Sentry event to an unrelated PR, and must not emit N duplicate events across every migration-touching PR run). Only the scheduled surface forwards `sentry-dsn`. |

## User-Brand Impact

**If this lands broken, the user experiences:** a future dev-only body drift on
`record_byok_use_and_check_cap` or `check_and_record_byok_delegation_use` goes
undetected (probe false-greens, or the Sentry mirror silently fails to emit), OR
the self-diagnosis embeds a stale/empty body — so the next drift-induced
double-trip reddens the `tenant-integration-required` check (blocking every
founder's merges, as in #5917) with no fast-path root-cause in the CI log.

**If this leaks, the user's data is exposed via:** n/a for user data — the
probe reads function **definitions** (DDL introspection), never user rows.
Under **Option B (primary)** the introspection path is entirely test-process /
dev-only (porsager over `DATABASE_URL_POOLER`) — **no prod runtime surface**.
Under the Option-A fallback, the `dev_functiondef` RPC returns function
**source** to `service_role` only (already omnipotent); no PII / user data /
new grant to `anon`/`authenticated` (the explicit three-name `REVOKE` is
load-bearing — Supabase default-privileges gotcha).

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
1. `action.yml`: add inputs `sentry-dsn` (required: false, default `''`) and `fail-on-rpc-body-drift` (default `'false'`); add output `rpc-body-drift-detected`. Load the marker map by reading the shared `byok-rpc-markers.json` via `jq` (single source of truth — see Phase 2). Add a comment asserting the fn allowlist / marker map is compile-time static (no DB-derived / `github.event.*` interpolation into SQL) — mirrors the existing filename-shape-whitelist comment at `action.yml:79-82`.
2. New composite step `assert-byok-rpc-body-markers` (after the ledger probe). For each fn in the map:
   - `body=$(doppler run … -- sh -c 'psql "$DATABASE_URL_POOLER" … -c "SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='"'"'public'"'"' AND p.proname='"'"'<fn>'"'"';"')` — reuse the existing `sh -c` env-expansion + psql-failure `::warning::`+`exit 0` pattern.
   - 0 rows → drift ("<fn> not found on dev"); >1 rows → assert markers across all bodies.
   - `stripped=$(printf '%s' "$body" | sed 's/--.*//')`; for each marker `grep -qF -- "$marker" <<<"$stripped"` else accumulate `<fn>::<marker>`. (Markers are exact fixed-strings; a semantically-identical reformat, e.g. `:=` spacing, fails loud — see Sharp Edges.)
   - On any miss: set `rpc-body-drift-detected=true`; **severity tracks `fail-on-rpc-body-drift`**: `true` → `::error::dev-migration-drift: RPC public.<fn> is MISSING load-bearing marker "<marker>" — live dev body drifted from source (#5920; see mig 121/084)` (static literals only) + Sentry event; `false` → `::warning::` (same text), **no Sentry**.
3. Sentry event helper (inline bash, per `web-platform-release.yml:893-933`), invoked ONLY when `fail-on-rpc-body-drift == 'true'` AND `sentry-dsn` non-empty: DSN-presence guard (`::warning::`+continue), parse `PUBLIC_KEY`/`HOST`/`PROJECT_ID`, `jq -nc` payload `{message:"byok RPC body-marker drift", level:"error", platform:"other", tags:{feature:"dev-migration-drift", op:"rpc-body-marker-drift", fn:<fn>}, extra:{missing_marker:<marker>}}` (`message` is a **static** string — the DB body is never placed on the Sentry surface), POST `store/` with `X-Sentry-Auth`, 3-retry, curl-fail → `::warning::` (observability degraded, does not change drift disposition).
4. If `fail-on-rpc-body-drift == 'true'` AND `rpc-body-drift-detected == 'true'` → `exit 1` (fail the step) at the end of the step.
5. `scheduled-dev-migration-drift.yml`: forward `sentry-dsn: ${{ secrets.NEXT_PUBLIC_SENTRY_DSN }}` and `fail-on-rpc-body-drift: 'true'`. (Scheduled = sole Sentry emitter + sole fail authority.)
6. `tenant-integration.yml`: leave `fail-on-rpc-body-drift` default `false` and do **not** forward `sentry-dsn` — PR CI shows a `::warning::` (visibility, consistent with the ledger probe's `::warning::`-in-PR convention at action.yml:11-15), never `::error::` / Sentry / a red check on pre-existing dev drift. Timing note: `tenant-integration.yml` runs the probe pre-apply (before the migration apply), so the live body is dev's pre-apply state; a PR that legitimately changes a marker is caught at PR time by the **structural test** (Phase 2), not the live probe.

### Phase 2 — Marker map + structural source-side test (deliverable 1)
1. New file `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` — the **single source of truth** for the per-function marker map, consumed by BOTH the bash probe (`jq`, Phase 1) and the TS structural test. `jq` is already required by the Sentry-emit path, so the shared-file marginal cost is ~zero (architecture review Q3: a comment is insufficient for a duplicated security guard). Shape: `{ "record_byok_use_and_check_cap": ["FOR UPDATE", "v_tripped := FOUND"], "check_and_record_byok_delegation_use": ["FOR UPDATE", "hourly_cap_exceeded", "daily_cap_exceeded"] }`.
2. New file `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts` — `import` (or `JSON.parse(readFileSync)`) the shared JSON.
3. For each fn: glob `supabase/migrations/*.sql` (exclude `*.down.sql`), pick the **highest-numbered** file matching `/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.<fn>\b/` (anchored to `CREATE OR REPLACE FUNCTION`, per `2026-06-19` learning — bare `FUNCTION public.<fn>` matches REVOKE/GRANT/COMMENT), `readFileSync`, comment-strip `/--[^\n]*/g`, assert each marker via `.toContain`. `throw` (fail loud) if no defining migration resolves.
4. Assert each marker lives inside the function **body** (all five are executable-only today; `pg_get_functiondef` emits only the `$$…$$` body — never `COMMENT ON`/`REVOKE`/`GRANT` — so a marker outside the body would be invisible to the live probe).
5. This guards that committed source never regresses the markers (keeps the live-probe map honest) and self-updates as the RPC is redefined in later migrations.

### Phase 3 — Introspection mechanism (deliverable 2, Option B — recommended)
**Option B (primary; test-only, no prod DDL):** add `postgres` (porsager, zero-dep) to `apps/web-platform/package.json` `devDependencies` (obey `cq-before-pushing-package-json-changes`: `bun install` + commit the lockfile). The atomicity test opens a direct connection with `process.env.DATABASE_URL_POOLER` (present in the dev doppler env the test already runs under) to `SELECT pg_get_functiondef(...)` on failure. Same credential class as the test's existing `service_role` usage — no escalation, no prod runtime surface.

**Option A (fallback — only if the devDep is rejected):** new migration `apps/web-platform/supabase/migrations/122_dev_functiondef_introspection.sql` (do NOT name it `pg_functiondef` — the `pg_` prefix squats on Postgres's reserved catalog convention; use e.g. `dev_functiondef`): `CREATE OR REPLACE FUNCTION public.dev_functiondef(p_fn regprocedure) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$ SELECT pg_get_functiondef(p_fn); $$;` + `REVOKE ALL … FROM PUBLIC, anon, authenticated;` (**all three names explicit** — Supabase `ALTER DEFAULT PRIVILEGES` auto-grants EXECUTE to `anon`/`authenticated`; `FROM PUBLIC` alone leaves those live — learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`, precedent `084:39-46`) + `GRANT EXECUTE … TO service_role;` + `COMMENT ON FUNCTION`; `.down.sql` drops it; wrap `BEGIN;/COMMIT;`; no `CREATE INDEX CONCURRENTLY`. Called via `service.rpc("dev_functiondef", …)`.

### Phase 4 — Self-diagnosing atomicity failure (deliverable 2)
1. In `byok-kill-switch.atomicity.tenant-isolation.test.ts`, before the strict Invariant-C assertions, compute `willFail = trippedCount !== 1 || pairs.some(p => p.kill_tripped !== (p.cumulative_cents === tripCumulative))`.
2. If `willFail`, fetch the live body: Option B → `sql\`SELECT pg_get_functiondef('public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure)\`` via the porsager connection; Option A → `service.rpc("dev_functiondef", { p_fn: "public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)" })`. Fallback string on error.
3. Pass the live body into the **message** argument of the existing strict `expect(...)` calls (per-pair loop message + `trippedCount` message). **No assertion is relaxed** — Invariant C still requires exactly-one-trip; the body only enriches the failure message.
4. Guard the fetch so a fetch error never masks the real Invariant-C failure (fallback string, not a throw before the `expect`).

## Files to Create
- `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` — shared per-function marker map (single source of truth for bash probe + TS test).
- `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts` — structural source-side marker guard.
- (Option A fallback only) `apps/web-platform/supabase/migrations/122_dev_functiondef_introspection.sql` + `.down.sql`.

## Files to Edit
- `.github/actions/dev-migration-drift-probe/action.yml` — body-marker probe step (reads shared JSON via jq), `sentry-dsn`/`fail-on-rpc-body-drift` inputs, `rpc-body-drift-detected` output, gated bash Sentry emit, static-allowlist comment.
- `.github/workflows/scheduled-dev-migration-drift.yml` — forward `sentry-dsn` + `fail-on-rpc-body-drift: 'true'` (sole Sentry + fail authority).
- `.github/workflows/tenant-integration.yml` — no change to fail flag; do NOT forward `sentry-dsn` (PR CI stays `::warning::`-only). *(If the composite action's default input handling already yields the warning-only path with no forwarding, this file may need no edit — verify at /work.)*
- `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` — self-diagnosing Invariant-C failure message.
- (Option B primary) `apps/web-platform/package.json` + lockfile — add `postgres` devDependency.

## Acceptance Criteria

### Pre-merge (PR)
1. The shared `byok-rpc-markers.json` maps `record_byok_use_and_check_cap → ["FOR UPDATE","v_tripped := FOUND"]` and `check_and_record_byok_delegation_use → ["FOR UPDATE","hourly_cap_exceeded","daily_cap_exceeded"]`; the structural test (reading that JSON) passes green against current sources (mig 121, 084).
2. The structural test picks the **highest-numbered** `CREATE OR REPLACE FUNCTION public.<fn>` migration (anchored regex) and comment-strips before asserting; it `throw`s if no definer resolves (verified by a negative fixture).
3. `action.yml` `assert-byok-rpc-body-markers` step, exercised via `bash -c` on an extracted snippet against (a) all-markers fixture body → no drift, `rpc-body-drift-detected=false`; (b) body missing `v_tripped := FOUND` with `fail-on-rpc-body-drift=false` → `::warning::` naming fn+marker, no Sentry, exit 0; (c) same drift with `fail-on-rpc-body-drift=true` → `::error::` + Sentry payload + exit 1.
4. DSN-unset path (with `fail-on-rpc-body-drift=true`) emits `::warning::` and continues (Sentry outage never flips the drift disposition / never swallows the `::error::`).
5. Only `scheduled-dev-migration-drift.yml` sets `fail-on-rpc-body-drift: 'true'` and forwards `sentry-dsn` (verified by `grep`); `tenant-integration.yml` forwards neither.
6. The Sentry `message` is a fixed literal string; the DB-derived body never appears in any `::error::`/`::warning::` annotation or Sentry payload (grep the diff — the body flows only into `grep -qF` and the vitest failure message).
7. `byok-kill-switch.atomicity.tenant-isolation.test.ts`: Invariant C assertions are byte-for-byte as strict (exactly-one-trip; per-pair; `trippedCount === 1`); only the `expect` **message** args gain the conditional live-body embed. (Diff shows no change to any `.toBe`/`.toEqual` target.)
8. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run test/supabase-migrations/byok-rpc-body-markers.test.ts` green.
9. `actionlint` on the edited workflow(s); extracted `run:` snippets pass `bash -c` syntax check (composite `action.yml` is NOT linted with `actionlint` — it emits spurious schema errors; use `bash -c` for its embedded shell).
10. (Option B) `postgres` added to `devDependencies` with the lockfile committed (`cq-before-pushing-package-json-changes`); the atomicity test's failure-path fetch is dev-only (`DATABASE_URL_POOLER`, gated by `TENANT_INTEGRATION_TEST=1`).

### Post-merge (operator/automated)
11. (Option A fallback only) Migration 122 applied to dev **and** prd via the existing `web-platform-release.yml#migrate` path (NOT operator SSH) — verified via `mcp__plugin_supabase_supabase__list_migrations`. **Under Option B (primary) there is no migration to apply.**
12. Trigger the scheduled probe once (`gh workflow run scheduled-dev-migration-drift.yml`) and confirm a green run with "No … drift detected" (no false-positive body-marker `::error::`).
13. Live-DB self-diagnosis smoke: run the atomicity test against dev with `TENANT_INTEGRATION_TEST=1` — green (Invariant C passes on the correct mig-121 body; self-diagnosis path is dormant on green).

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
itself** (scheduled surface only), with `fn` + `missing_marker` as discriminating
structured fields that identify the exact function and marker in one event — not a
host-side-only signal.

**Tripwire, not semantic proof:** the marker probe is a *necessary-not-sufficient*
drift tripwire (catches the #5917 signature + accidental marker deletion). It does
NOT prove exactly-one-trip semantics — that authority stays with Invariant C in the
atomicity test (kept strict). The delegation RPC has no live semantic backstop
(follow-up filed).

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
- **Marker probe is necessary-not-sufficient** (architecture review Q4). A rewrite
  can keep `FOR UPDATE` + `v_tripped := FOUND` and still double-trip; the probe
  catches the #5917 signature + accidental marker deletion, not the full semantic.
  Invariant C (atomicity test) is the semantic authority and stays strict.
- **Delegation RPC has no live semantic backstop.** Its markers prove the RAISE
  strings exist, not that the `> v_row.<cap>_cap_cents` comparison is intact — and
  it has no companion atomicity test. Follow-up: a delegation-RPC semantic/atomicity
  test (file a tracking issue at /work with label `observability`).
- **Marker map is a shared JSON** (`byok-rpc-markers.json`), read by both bash (`jq`)
  and TS — single source of truth, resolves the bash/TS duplication-drift edge
  (architecture review Q3; `jq` is already required by the Sentry path).
- **`grep -qF` exact-string brittleness:** a semantically-identical reformat (e.g.
  `v_tripped:=FOUND` spacing) fails the fixed-string match. The structural test
  asserts the same literal against source, so a reformat fails loud at PR time
  (acceptable); the shared JSON then needs a manual marker bump.
- **Comment-strip does not remove SQL string literals** (`2026-05-31` learning).
  Markers are verified executable-only today; still comment-strip before match, and
  never pick a marker that also appears in a `COMMENT ON` literal.
- **Markers must live inside the `$$…$$` body** — `pg_get_functiondef` emits only the
  body, never `COMMENT ON`/`REVOKE`/`GRANT`; a marker outside the body is invisible
  to the live probe (all five are body-resident today).
- **Anchor the structural test's definer-finder to `CREATE OR REPLACE FUNCTION`**
  (`2026-06-19` learning), not bare `FUNCTION public.<fn>` (matches REVOKE/GRANT/COMMENT).
- **`pg_get_functiondef` overloads:** if a proname ever gains a second overload,
  the probe must iterate all oids (Phase 0 confirms single-overload today).
- **Do NOT echo the DB-derived body into any annotation or Sentry payload**
  (log-injection vector; Sentry `message` is a static literal). Only static allowlist
  literals go into annotations; the body goes only into the vitest failure message.
- **Severity + Sentry track `fail-on-rpc-body-drift`** — PR CI stays `::warning::`-only,
  no Sentry (avoids signal erosion + misattribution + N-duplicate events); scheduled is
  the sole `::error::`+Sentry+fail authority (architecture review Q1).
- **Option B (primary) keeps introspection out of prod;** Option A fallback (if the
  devDep is rejected) must name `REVOKE … FROM PUBLIC, anon, authenticated` (Supabase
  default-privileges gotcha) and avoid the reserved `pg_` name prefix.
- **A plan whose `## User-Brand Impact` section is empty, TBD, or omits the threshold
  will fail deepen-plan Phase 4.6.** This section is filled.

## Precedent Diff (deepen-plan Phase 4.4)

Pattern-bound behaviors and their in-repo precedents:

- **SECURITY DEFINER RPC + search_path pin + REVOKE/GRANT** (Option-A migration 122):
  precedent = `121_byok_cap_trip_from_found.sql:54-56,121-124` (`LANGUAGE plpgsql
  SECURITY DEFINER SET search_path = public, pg_temp`; `REVOKE ALL … FROM PUBLIC,
  anon, authenticated; GRANT EXECUTE … TO service_role`). Migration 122 follows
  this shape verbatim, differing only in `LANGUAGE sql STABLE` (a one-line wrapper
  around `pg_get_functiondef`) — a `regprocedure`-arg introspection helper also has
  precedent in `048_precheck_jwt_mint_sqlstate.sql`. `cq-pg-security-definer-search-path-pin-pg-temp`
  satisfied.
- **Bash Sentry event emit from a CI runner:** precedent = `web-platform-release.yml:893-933`
  (DSN parse → `store/` POST → `X-Sentry-Auth` → 3-retry → warn-not-fail). Adopted
  verbatim in shape; only the tags/extra vocabulary differs.
- **Composite-action psql with `sh -c` env expansion + filename-shape whitelist:**
  precedent = the existing `dev-migration-drift-probe/action.yml:69-91`. The new
  body-marker step reuses both patterns; fn names are a static allowlist (no
  DB-derived interpolation into SQL).
- **Structural migration-shape test:** precedent = `046-runtime-cost-state.test.ts`
  (`readFileSync` + `/--[^\n]*/g` comment-strip + `.toMatch`). No novel pattern.

No novel pattern is introduced; every shape has an established sibling.

## Deepen-Plan Gate Status

- **4.6 User-Brand Impact:** PASS (threshold `aggregate pattern`, concrete artifact + vector).
- **4.7 Observability:** PASS (5 fields present, no placeholders, `discoverability_test.command` is ssh-free).
- **4.8 PAT-shaped variable:** PASS (no PAT-shaped var/env/literal).
- **4.9 UI-wireframe:** N/A (no UI-surface file in Files-to-Edit/Create).
- **4.55 Downtime & Cutover:** N/A (migration 122 is a new `CREATE FUNCTION`, no hot-table rewrite/reboot/router change).
- **4.5 Network-outage:** N/A (no SSH/network-connectivity symptom).

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Flat shared marker set for both RPCs | Rejected — `v_tripped := FOUND` is cap-RPC-only; would false-fire on the delegation RPC. |
| Embed migration **source** in the atomicity failure (not live body) | Rejected — #5917 was a live-vs-source drift; source is clean, so source embedding defeats the diagnostic. |
| Option A (prod `SECURITY DEFINER` introspection RPC) as primary | Demoted to fallback (security + architecture review) — permanent prod DDL + widened PostgREST surface for a dev-only test diagnostic; "via the service client" is a mechanism suggestion, not a contract. Option B (test-only pg connection) is primary. |
| Fail the composite action non-zero in all contexts | Rejected — would red unrelated PRs on pre-existing dev drift; gated behind `fail-on-rpc-body-drift` (scheduled only). |
| `::error::` + Sentry in both callers | Rejected (architecture review Q1) — severity/Sentry now track `fail-on-rpc-body-drift`; PR CI is `::warning::`-only to avoid signal erosion + Sentry misattribution + duplicate events. |
| Cross-reference comment for the duplicated marker map | Rejected (architecture review Q3) — comments rot on a security-relevant guard; promoted to a shared `byok-rpc-markers.json` (jq already required). |
