---
issue: 6328
branch: feat-one-shot-6328-definer-grant-hygiene
lane: single-domain
plan: knowledge-base/project/plans/2026-07-11-security-definer-grant-hygiene-baseline-plan.md
adr: ADR-112 (new; amends ADR-101 + ADR-111)
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- No infrastructure in scope: DB-free static test-lint + ADR + learning + one tracking
     issue. No .tf/cloud-init/bootstrap applicable. -->

# Tasks — DEFINER grant-hygiene static pre-filter hardening (#6328)

Derived from the finalized (deepen-plan v3) plan. The runtime `rls-authz-fuzz` AC8 gate
is the authoritative durable guard; this work hardens the subordinate static pre-filter
so it stops passing vacuously, and records the two-tier decision in ADR-112.

## Phase 0 — Surface the newly-detected set (verification-first)

- [x] 0.1 Read `apps/web-platform/test/migration-rpc-grants.test.ts` in full, plus `apps/web-platform/test/rls-fuzz/{catalog.ts,rpc-cases.ts,rls-rpc.integration.test.ts}` (AC8 classification registry).
- [x] 0.2 Enumerate every DEFINER function across `apps/web-platform/supabase/migrations/*.sql` **case-insensitively, excluding `*.down.sql`**. For each capture: file, name, type-precise signature (strip param names + DEFAULT), `RETURNS TRIGGER` flag, `search_path` pin, and every same-signature grant/revoke/DROP across the corpus.
- [x] 0.3 Classify each: passes-via-union / `RETURNS TRIGGER`-excluded (~33) / authenticated-callable (~8-12: 060,079,045,059,053,068,125) / DROP-without-recreate-excluded (3-arg acquire) / genuine grandfather gap. Confirm `handle_new_user` passes (mig 112 pins+revokes — not grandfather).
- [x] 0.4 Read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`; confirm "no C4 impact".
- [x] 0.5 Confirm no open code-review issue touches target files beyond #3220/#3221.

## Phase 1 — Body-form-agnostic detector module (lands atomically with Phase 2)

- [x] 1.1 Create `apps/web-platform/test/migration-lint/definer-grants.ts`.
- [x] 1.2 `stripSqlNoise(sql)` — strip `--` line comments, `/* */` block comments, AND dollar-quoted string/body literals before parsing.
- [x] 1.3 `extractSecurityDefinerFns(file, sql)` — case-insensitive (`i`), match the CREATE FUNCTION **declaration header up to the body-start delimiter** and stop (no body parse); balanced-paren signature capture; tolerate clause ordering; capture a `returnsTrigger` boolean.
- [x] 1.4 `normalizeSignature(params)` — type-vector (strip names + DEFAULT clauses); apply to CREATE and grant/revoke/DROP sides.
- [x] 1.5 `parseGrantRevoke(sql)` + `parseDropFunction(sql)` — normalized signatures.
- [x] 1.6 Refactor `migration-rpc-grants.test.ts` to import these; preserve the `search_path`/`pg_temp` pin assertion (+ `LEGACY_SEARCH_PATH_NO_PG_TEMP`) for ALL detected DEFINER fns (incl. triggers).

## Phase 2 — Corpus-wide revoke-union assertion (forward files only)

- [x] 2.1 Build the corpus from `supabase/migrations/*.sql` **excluding `*.down.sql`** (mirror `run-migrations.sh:125,251`).
- [x] 2.2 For each detected DEFINER fn that is NOT `RETURNS TRIGGER`, NOT DROP'd-without-recreate, and NOT in `AUTHENTICATED_CALLABLE`: assert corpus REVOKEs cover **all of `{public, anon, authenticated}`** for its type-signature; absence → VIOLATION.
- [x] 2.3 Add `AUTHENTICATED_CALLABLE` allowlist constant (mirror `LEGACY_SEARCH_PATH_NO_PG_TEMP`; NOT a comment marker). Each entry cites its AC8 `EXCLUDED`/`ATTACK` classification. Populate with the Phase-0 set (~8-12).
- [x] 2.4 Add grandfather allowlist for genuine pre-existing gaps: entry + ≥1-sentence rationale + tracking issue `#N`.
- [x] 2.5 Document (header comment) the AC8-owned residual: revoke-then-DROP+CREATE-without-re-revoke false-passes the static union; AC8 catches it at runtime.

## Phase 3 — Synthesized regression fixtures (RED→GREEN)

- [x] 3.1 Create `apps/web-platform/test/migration-lint/definer-grants.test.ts` with synthesized inline fixtures (`cq-test-fixtures-synthesized-only`).
- [x] 3.2 Cover: lowercase-no-revoke→VIOLATION; created-A/revoked-all-3-in-B→PASS; revoke-anon+auth-but-NOT-public→VIOLATION; RETURNS TRIGGER-no-revoke→PASS; `$tag$`/`language sql`/`begin atomic` body→detected; two-overloads-one-revoked→un-revoked VIOLATION; `.down.sql` re-grant→ignored; drop-without-recreate→excluded; block-commented/dollar-body grant→ignored; allowlisted→PASS, un-allowlisted-grant-to-authenticated→VIOLATION.
- [x] 3.3 Write tests before finalizing Phase 2 logic (`cq-write-failing-tests-before`).

## Phase 4 — Non-vacuity parity guard + ADR-112 + docs

- [x] 4.1 Add the non-vacuity/live-catalog-parity assertion in `apps/web-platform/test/rls-fuzz/rls-rpc.integration.test.ts` (or `catalog.ts`): every DEFINER fn the live catalog surfaces is also matched by `extractSecurityDefinerFns` over the same corpus; reds on static under-detection. Fallback: corpus detection-count floor.
- [x] 4.2 Author `knowledge-base/engineering/architecture/decisions/ADR-112-definer-grant-hygiene-two-tier-guard.md` with YAML `amends: [ADR-101, ADR-111]`, recording: AC8 authoritative, static tier non-coverage-bearing, out-of-band accepted residual + AP-002 compensating control, ADP deferral. Re-verify ordinal 112 vs `origin/main` at write time.
- [x] 4.3 Add reciprocal `amended_by: ADR-112` cross-refs to `ADR-101-client-callable-security-invoker-rpc.md` and `ADR-111-runtime-authz-rls-fuzz-harness.md`.
- [x] 4.4 Add an `AP-NNN` row to `knowledge-base/engineering/architecture/principles-register.md` sourced to ADR-112 (advisory).
- [x] 4.5 Update `migration-rpc-grants.test.ts` header: generalized invariant, `AUTHENTICATED_CALLABLE` + trigger-exclusion conventions, AC8-owned residual, relationship to the authoritative runtime gate.
- [x] 4.6 Write `knowledge-base/project/learnings/best-practices/<topic>.md` (directory+topic only, author picks date). Do NOT add a new `AGENTS.md` rule.

## Phase 5 — Defer option (a)

- [x] 5.1 File a `type/security` + `deferred-scope-out` GitHub issue for the `ALTER DEFAULT PRIVILEGES` baseline, recording the live-role-scope-probe requirement, the fail-closed blast radius, and the out-of-band-creation residual (the one thing only ADP closes). Milestone from `knowledge-base/product/roadmap.md`.

## Verification (pre-merge)

- [x] V1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/migration-rpc-grants.test.ts test/migration-lint/` — green over the real corpus, zero silent skips.
- [x] V2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [x] V3 `git diff --stat` — no net grant/revoke statement added to any `*.sql` migration.
- [x] V4 All 15 Acceptance Criteria in the plan satisfied.
