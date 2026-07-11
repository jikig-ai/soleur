---
issue: 6328
branch: feat-one-shot-6328-definer-grant-hygiene
type: security-hardening
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
adr: ADR-112 (new; amends ADR-101 + ADR-111)
status: draft
date: 2026-07-11
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO infrastructure (no server, systemd
     service, cron, vendor account, secret, DNS record, or firewall rule). Scope is a
     DB-free static test-lint (apps/web-platform/test/**), a new ADR, a learning doc,
     and one tracking issue. No .tf resource, cloud-init, or bootstrap script is
     applicable. The "operator"/"console" mentions are prose about failure visibility and
     the deferred option-(a) re-eval criteria, not provisioning steps. -->

# 🔒 security: repo-wide DEFINER grant-hygiene baseline — harden the static pre-filter, record the durable-guard re-eval (#6328)

## Enhancement Summary

**Deepened on:** 2026-07-11
**Agents used:** security-sentinel, data-integrity-guardian, architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer, Explore (verify-the-negative + repo-research). All six ran in parallel; findings folded below.

### Key changes from v1 (all agent-driven)

1. **P0 security fix (security-sentinel + data-integrity):** the net-grant assertion must forbid **`public` AND `anon` AND `authenticated`** — v1 dropped `public`, which would PASS a fn revoked from anon/authenticated but still executable by everyone via the residual `PUBLIC` grant (the exact false-GREEN this lint exists to kill; a regression from the current test which requires all three at `:146-151`).
2. **Model simplified (code-simplicity) + made faithful (data-integrity + spec-flow):** replace the "from-baseline ordered replay" engine with a **corpus-wide revoke-union of all three roles**, which catches no-grants-at-all and revoke-from-public-only *without* re-implementing Postgres `has_function_privilege()` (which the authoritative AC8 gate already computes exactly at runtime) and *without* depending on the unproven CREATE-time inheritance premise (see §sidestep below).
3. **Corpus glob excludes `*.down.sql` (data-integrity P0 + spec-flow P0-1):** `run-migrations.sh` skips them (`:125`,`:251`) and warns they sort lexically BEFORE the forward `.sql`; `128_...down.sql` re-GRANTs anon/authenticated. 85 down-files would poison the scan.
4. **`RETURNS TRIGGER` exclusion (spec-flow P0-2 — new, decisive):** ~33 forward `SECURITY DEFINER … RETURNS TRIGGER` functions exist; trigger functions have **no `GRANT EXECUTE` invocation path** (`authenticated` can't call them regardless of `proacl`), so the grant assertion must exclude them or it reds the whole corpus and forces a ~30-entry allowlist. Mirrors AC8's own `EXCLUDED` classification of trigger fns.
5. **Type-precise signatures (security P1 + data-integrity P0 + spec-flow P1-1):** strip param names AND `DEFAULT` clauses to a type-vector, or the 3-arg vs 4-arg `acquire_conversation_slot` overloads cross-cover. Model `DROP FUNCTION`-without-recreate as signature removal (the dropped 3-arg else false-VIOLATEs).
6. **Marker convention cut (code-simplicity + security P1 + spec-flow P1-3):** the `-- lint:authenticated-callable` comment conflicted with `stripLineComments` (stripped before read) and duplicated AC8's registry. Use an explicit `AUTHENTICATED_CALLABLE` allowlist constant (existing `LEGACY_SEARCH_PATH_NO_PG_TEMP` pattern), each entry citing its AC8 `EXCLUDED`/`ATTACK` classification.
7. **Authenticated-callable set is ~8-12, not "likely zero" (verify + data-integrity + spec-flow P1-2):** confirmed `set_current_organization_id`(060), `set_current_workspace_id`(079), `is_message_owner`(045/059), plus `is_workspace_member`(053), jti cluster(068), `append_kb_sync_row`(053), `resolve_workspace_installation_id`(079), `list_conversations_enriched`(125).
8. **`handle_new_user` is NOT a grandfather case (verify):** latest def (mig 112) pins `search_path` and revokes anon/authenticated — it PASSES.
9. **Comment/string hardening (spec-flow P1-5, P2-1, P2-3):** strip `/* */` block comments and dollar-quoted string literals before parsing (035/053/068 have block comments; 068 has real grants); balanced-paren signature capture (`numeric(10,2)`, `default now()`).
10. **Non-vacuity/live-catalog-parity guard (architecture-strategist P1):** assert the static detector's DEFINER-set ⊇ AC8's live-catalog enumeration, so the static tier cannot silently regress (otherwise AC "zero silent skips" inherits the detection blind spot).
11. **ADR: new ADR-112, not amend ADR-111 (architecture-strategist P1):** decision straddles ADR-101 (grant-convention) + ADR-111 (runtime guard) + a net-new lint; ADR-111 has no YAML frontmatter → an appended section is invisible to the `amends`/`amended_by` graph; ADR-084 precedent rejected amend for an orthogonal cross-cutting decision. ADR-112 carries `amends: [ADR-101, ADR-111]`.
12. **Phase 1/2 land atomically (spec-flow P2-5):** once detection is general, the old per-file REVOKE assertion immediately reds on lowercase fns whose revoke lives in a later file (037→128) — the resolver replaces it in the same landing; there is no "Phase 1 no-behavior-change" intermediate.

### Static-model sidesteps the deferred-ADP premise (spec-flow P1-4)

A from-baseline replay would bake in the *same* unproven assumption the plan defers option (a) for ("which role's default privileges do migrations inherit?"). The **revoke-union** model does not: it requires an *explicit* corpus REVOKE of `{public, anon, authenticated}` regardless of what the CREATE-time default actually is. So it neither assumes nor depends on the ADP inheritance premise — a strictly better basis for a pre-filter.

## Overview

Issue #6328 asks for a **repo-wide class-level guard** against the #6306 defect class: a service-role-only `SECURITY DEFINER` function that retains Supabase's CREATE-time `anon`/`authenticated` EXECUTE grant (an RLS-bypassing cross-tenant IDOR / disclosure surface). It proposes **(a)** an `ALTER DEFAULT PRIVILEGES` baseline migration or **(b)** a migration-lint CI gate, deferring the choice until **#6256 (the runtime RLS/authz-fuzz harness) merges**.

**That re-eval condition is now satisfied — #6256 has merged.** The durable class-level guard **already exists and runs per-migration-PR**: `.github/workflows/rls-authz-fuzz.yml` (triggered on `apps/web-platform/supabase/migrations/**`) spins up a disposable Supabase-CLI stack, applies all migrations, and runs `test/rls-fuzz/rls-rpc.integration.test.ts` **AC8**, which enumerates every DEFINER function `authenticated` may EXECUTE **from the live catalog** (`securityDefinerAuthenticatedFns()` → `has_function_privilege('authenticated', p.oid, 'EXECUTE')`, `catalog.ts:82-92`) and reds until each is classified and proven to deny. Being live-catalog-driven, it is **immune to source-form blind spots** and **already closes the "no-grants-at-all" blind spot** (`#6332`/`8efd1844b` un-baselined the #6306 `test.fails`, so AC8 enforces on main now).

The **residual gap** #6328 closes: the **static** sibling lint `apps/web-platform/test/migration-rpc-grants.test.ts` (PR #3634) is **case-sensitive and `AS $$`-body-form-only**, so it **silently misses the 5 files that use lowercase `security definer`** (incl. the exact #6306 functions and `handle_new_user`) — passing 524/524 vacuously over them. A green static lint dead for a whole authoring style is **false confidence**.

**Deliverable:** make the static lint a **trustworthy, no-stack, per-PR pre-filter** — case-insensitive body-form-agnostic detection + a corpus-wide revoke-union of `{public, anon, authenticated}` (forward-migrations only, type-precise, DROP-aware, `RETURNS TRIGGER`-excluded) + an explicit authenticated-callable allowlist cross-referencing AC8 + a **non-vacuity parity guard** tying the static detected-set to AC8's live enumeration. Record the two-tier guard decision in **ADR-112** (`amends: [ADR-101, ADR-111]`). **Defer option (a)** `ALTER DEFAULT PRIVILEGES` pending a live role-scope probe.

## Premise Validation

- **#6306** `CLOSED` by **PR #6318**. **#6318 / migration 128** on-branch; its comment defers "ALTER DEFAULT PRIVILEGES / migration lint … to a tracked #6306 follow-up and #6256" (= this issue). **#6256** `CLOSED`/merged; harness + ADR-111 + `rls-authz-fuzz.yml` on-branch. **#6332** (`8efd1844b`) un-baselined the #6306 `test.fails` — AC8 enforces on main.
- **Static audit** `migration-rpc-grants.test.ts` passes 524 tests but its regex (`:66`) is case-sensitive (no `i`) and requires `AS $$…$$;`. Verified: 5 lowercase-`security definer` files escape it; mixed-case files (029, 036, 087, 116…) also carry lowercase-defined DEFINER fns silently dropped per-function.
- **Mechanism-vs-ADR corpus:** neither `ALTER DEFAULT PRIVILEGES` nor `migration-lint` sits in any ADR's rejected-alternatives table. ADR-101 (client-callable `SECURITY INVOKER` RPC) is the grant-convention precedent for the authenticated-callable allowlist.
- **ADR ordinal:** freshly-fetched `origin/main` → highest is ADR-111, so **ADR-112** is the next free ordinal (provisional; `/ship`'s ADR-Ordinal Collision Gate re-verifies).

## Research Reconciliation — Issue Premise vs. Codebase Reality

| Issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "Future functions stay exposed by default." | AC8 reds on any new DEFINER fn `authenticated` may EXECUTE until classified + proven to deny — caught at PR time. | Keep AC8 authoritative (ADR-112). Defer option (a). |
| "Audit blind spot — can't detect a DEFINER fn managing no grants at all." | AC8 (live catalog) closes this. Static lint's real gap is **detection** (case/body-form), not the revoke criterion. | Harden detection + require a corpus-wide revoke of all 3 roles. |
| "Fix: (a) ALTER DEFAULT PRIVILEGES or (b) migration-lint." | (b) partially exists (buggy); (a) does not; runtime guard is stronger. | Hardened (b) as pre-filter + record AC8 as durable guard + defer (a). |
| v1 self-correction: "handle_new_user likely lacks pin / retains defaults." | FALSE — latest def (mig 112:49-53, :95) pins `search_path = public, pg_temp` and `REVOKE … FROM PUBLIC, anon, authenticated`. It PASSES. | Remove from grandfather framing. |
| v1: "authenticated-callable likely zero." | FALSE — ~8-12 confirmed DEFINER fns grant EXECUTE to authenticated. | Enumerate into `AUTHENTICATED_CALLABLE` allowlist. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this hardens a preventive CI **pre-filter** over migration source; it processes no user data and ships no schema change. Failure mode = "the static lint retains a residual detection gap," i.e. same coverage as today, backstopped by the authoritative runtime AC8 gate.

**If this leaks, the user's data is exposed via:** N/A — touches only test code, an ADR, and convention docs; no user-data path, secret, or live-grant mutation.

**Brand-survival threshold:** `aggregate pattern`. The *guarded* defect class is single-user-incident severity (cross-tenant IDOR/disclosure), but the load-bearing guard for that severity is the runtime AC8 gate, which already holds and is unaffected by this change. This plan strengthens a *second, defense-in-depth* static layer for a *class* of future functions; its own failure mode does not itself produce a single-user incident. `threshold: aggregate pattern, reason: preventive static pre-filter hardening; the single-user-incident-grade guard (rls-authz-fuzz AC8) is the authoritative backstop and is out of this change's blast radius.`

## Architecture Decision (ADR/C4)

### ADR-112 (new) — `knowledge-base/engineering/architecture/decisions/ADR-112-definer-grant-hygiene-two-tier-guard.md`

Author a new ADR (not an ADR-111 amendment — architecture-strategist P1): the decision straddles ADR-101 (grant-convention), ADR-111 (runtime harness), and a net-new static lint; ADR-111 has no YAML frontmatter, so an appended section produces no `amended_by` edge and is undiscoverable from ADR-101 where future client-callable-RPC authors look; ADR-084 set the precedent of rejecting amend for an orthogonal cross-cutting invariant. ADR-112 records:

- **Decision:** the runtime `rls-authz-fuzz` AC8 gate (live `pg_proc.proacl` introspection, per-migration-PR) is the **authoritative durable class-level guard** for DEFINER grant hygiene; the static lint is a **subordinate, no-stack, fast pre-filter that is advisory fast-feedback and NEVER coverage-bearing** (stated so a future PR cannot cite it to weaken AC8); a **non-vacuity parity guard** ties the static detected-set to AC8's live enumeration; `ALTER DEFAULT PRIVILEGES` is deferred as optional defense-in-depth pending a live role-scope probe.
- **Frontmatter:** `amends: [ADR-101, ADR-111]` (YAML). Add reciprocal `amended_by: ADR-112` where each target allows (ADR-101 has frontmatter; ADR-111 gets a one-line cross-ref).
- **Accepted residual (named):** a DEFINER function created **out-of-band** (SQL console/hotfix, not via a migration file) is invisible to BOTH the static lint (no migration file) AND AC8 (its stack is built from `migrations/**`). Compensating control: `AP-002` (no-SSH state mutation) + Terraform-only provisioning prohibits that path; ADP's re-eval fires if the policy is relaxed, and only a live-prod `has_function_privilege` sweep would then find such a function.
- **Convention cross-link:** the authenticated-callable allowlist extends ADR-101's `GRANT EXECUTE … TO authenticated` convention.
- **Principles register (advisory):** add an `AP-NNN` row in `principles-register.md` sourced to ADR-112.

### C4 views — no impact (enumerated per the completeness mandate)

/work MUST read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and confirm before writing "no C4 impact." Enumeration: **(a) external human actors** — none (internal CI tooling). **(b) external systems/vendors** — none (the disposable Supabase-CLI stack is ephemeral CI substrate in ADR-111's context, not a modeled container). **(c) containers/data-stores** — none (no schema/table/RPC added). **(d) actor↔surface access relationships** — none (no runtime grant mutated; the lint asserts source; option (a) is deferred). Standard C4 does not model CI gates/security controls as elements. Architecture-strategist confirmed this enumeration complete.

### Sequencing

True immediately on merge (AC8 already runs; the lint hardening + non-vacuity guard land together). No soak-gated status flip.

## Implementation Phases

### Phase 0 — Surface the newly-detected set (verification-first)

`wg-when-an-audit-identifies-pre-existing`.

1. Read `migration-rpc-grants.test.ts` in full and `test/rls-fuzz/{catalog.ts,rpc-cases.ts,rls-rpc.integration.test.ts}` (the AC8 classification registry to cross-reference).
2. Enumerate every DEFINER function across `supabase/migrations/*.sql` **case-insensitively, EXCLUDING `*.down.sql`**, capturing: file, name, **type-precise signature** (param names + `DEFAULT` stripped), `RETURNS TRIGGER` flag, body-quote form, `search_path` pin, and every same-signature `grant`/`revoke`/`DROP FUNCTION` across the corpus. Expected classes:
   - **Passes via revoke-union:** `find_stuck_active_conversations`(037→128), 4-arg `acquire_conversation_slot`(093→128), `release`/`touch_conversation_slot`(029→128), `handle_new_user`(latest 112 pins+revokes — NOT grandfather).
   - **`RETURNS TRIGGER` → excluded from grant assertion (~33 fns):** incl. `release_slot_on_archive`(036), and the trigger fns in 001/005/007/008/041/043/044/048/050-053/058/062-064/066/071/074/075/077/084/085/087/091/102/104/107/111/112/126. They keep the `search_path` pin check; they are NOT required to revoke anon/authenticated (no EXECUTE path).
   - **Authenticated-callable → `AUTHENTICATED_CALLABLE` allowlist (~8-12):** `set_current_organization_id`(060:218), `set_current_workspace_id`(079:303), `is_message_owner`(045:112,059:439), `is_workspace_member`(053:140), jti cluster(068:127,159,195), `append_kb_sync_row`(053:78), `resolve_workspace_installation_id`(079:127), `list_conversations_enriched`(125:179). Verify each fn's DEFINER status + its AC8 `EXCLUDED`/`ATTACK` classification before allowlisting.
   - **DROP-without-recreate → excluded:** 3-arg `acquire_conversation_slot(uuid,uuid,integer)` created 029:101, dropped 093:42, never recreated forward.
   - **Genuine grandfather gaps:** likely small after the above; each → allowlist entry + tracking issue.
3. Read the three C4 model files; confirm "no C4 impact."
4. Confirm no open code-review issue touches the target files beyond #3220/#3221.

### Phase 1 — Body-form-agnostic detector module (lands with Phase 2)

Create `apps/web-platform/test/migration-lint/definer-grants.ts` (pure, no DB). Detection generalization and the corpus resolver land **atomically** (spec-flow P2-5 — the old per-file assertion reds on 037-finder once detection generalizes):

- `stripSqlNoise(sql)` — strip `--` line comments, `/* */` **block comments**, AND **dollar-quoted string/body literals** before parsing (035/053/068 carry block comments and real grants; a `EXECUTE 'GRANT … TO authenticated'` inside a plpgsql body must not be counted as a top-level grant). Do NOT strip anything needed by the assertion.
- `extractSecurityDefinerFns(file, sql)` — **case-insensitive** (`i`). Match the `create [or replace] function <public.name>(<params>) …` **declaration header** (up to the body-start delimiter) and STOP — do NOT parse the body (drops the brittle `$$`/`$tag$`/`language sql`/`begin atomic` terminator problem; the check only needs the header for `security definer`, `returns trigger`, and `set search_path`). **Balanced-paren** signature capture. Tolerate clause ordering. Capture a `returnsTrigger` boolean from the header.
- `normalizeSignature(params)` — reduce to a **type vector** (strip param names, strip `DEFAULT`/`=` clauses, lowercase, collapse whitespace); apply to BOTH CREATE (`p_threshold_seconds integer default 120` → `integer`) and REVOKE/GRANT/DROP (`(integer)` → `integer`) sides.
- `parseGrantRevoke(sql)`, `parseDropFunction(sql)` — normalized via `normalizeSignature`.

Preserve the `search_path`/`pg_temp` pin assertion (+ `LEGACY_SEARCH_PATH_NO_PG_TEMP`) for ALL detected DEFINER fns (including triggers).

### Phase 2 — Corpus-wide revoke-union assertion (forward files only)

Do **not** re-implement `has_function_privilege()` (AC8 does that exactly at runtime — code-simplicity). Rule:

1. Build the corpus from `supabase/migrations/*.sql` **excluding `*.down.sql`** (mirror `run-migrations.sh:125,251`).
2. For each detected DEFINER fn `(name, type-signature)` that is (a) **NOT `RETURNS TRIGGER`** (no EXECUTE path — spec-flow P0-2), (b) NOT subsequently `DROP FUNCTION`ed-without-recreate, and (c) NOT in `AUTHENTICATED_CALLABLE`: assert the corpus contains same-signature `REVOKE` statements whose unioned role set covers **ALL of `{public, anon, authenticated}`** (security P0 — `public ⊇ {anon,authenticated}`). Absence → VIOLATION. Catches no-grants-at-all, revoke-from-public-only, AND revoke-anon/authenticated-only, without modeling the CREATE-time baseline.
3. **Documented residual (AC8 owns it):** the union does NOT model ACL-reset ordering; a `revoke` then later `DROP FUNCTION`+`CREATE` without re-revoke would false-PASS the static tier. AC8 catches that exactly via live `proacl`. Deliberate simplicity boundary.
4. **`AUTHENTICATED_CALLABLE` allowlist** (constant, mirror `LEGACY_SEARCH_PATH_NO_PG_TEMP`; NOT a comment marker). Each entry: `signature → rationale citing its AC8 EXCLUDED/ATTACK classification`. Populate with the Phase-0 set.
5. **Grandfather allowlist** for genuine pre-existing gaps: entry + rationale + tracking issue `#N`.

### Phase 3 — Synthesized regression fixtures (RED→GREEN)

`apps/web-platform/test/migration-lint/definer-grants.test.ts`, **synthesized** inline fixtures (`cq-test-fixtures-synthesized-only`). Assert:

- lowercase `create … security definer`, no revoke → **VIOLATION**.
- created A, `revoke … from public, anon, authenticated` in later forward B → **PASS**.
- revoke from anon, authenticated but NOT public → **VIOLATION** (security-P0 fixture).
- `RETURNS TRIGGER` DEFINER fn with no anon/auth revoke → **PASS** (excluded; spec-flow P0-2).
- `$tag$` / `language sql` / `begin atomic` body → **detected** (header-terminated).
- two overloads, only one revoked → the un-revoked one **VIOLATION** (type-precise, no cross-cover).
- `.down.sql` re-grant string → **ignored** (corpus excludes down files).
- create then later `drop function` (no recreate) → **excluded** (no false VIOLATION).
- block-commented / dollar-body-embedded grant string → **ignored** (spec-flow P1-5/P2-3).
- allowlisted authenticated-callable fn → **PASS**; same fn absent from allowlist → **VIOLATION**.

Write before finalizing Phase 2 (`cq-write-failing-tests-before`).

### Phase 4 — Non-vacuity parity guard + ADR-112 + docs

1. **Non-vacuity/live-catalog-parity guard (architecture P1):** in the `rls-authz-fuzz` job context (has the live catalog), assert every DEFINER fn the **live catalog** surfaces (a query over all `prosecdef` public fns, analogous to `securityDefinerAuthenticatedFns`) is also matched by `extractSecurityDefinerFns` over the same corpus — reds if the static tier under-detects. Weaker fallback: a corpus DEFINER-detection-count floor. Makes AC "zero silent skips" real, not self-referential.
2. Author **ADR-112** per the Architecture Decision section; reciprocal cross-refs to ADR-101/ADR-111; add the `AP-NNN` register row.
3. Update `migration-rpc-grants.test.ts` header: generalized invariant, `AUTHENTICATED_CALLABLE` + trigger-exclusion conventions, the AC8-owned residual, and the relationship to the authoritative runtime gate.
4. Capture the convention in `knowledge-base/project/learnings/best-practices/<topic>.md` (directory+topic only). Do **not** add a new `AGENTS.md` rule (`B_ALWAYS` at/near the 23000-byte cap; `cq-pg-security-definer-search-path-pin-pg-temp` already anchors the DEFINER convention).

### Phase 5 — Defer option (a) with a tracking issue

File a `type/security` + `deferred-scope-out` issue for `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated` as **optional defense-in-depth**, recording: (1) requires a **live role-scope probe** (Supabase sets ADP under `supabase_admin`; a mis-scoped ADP is a silent no-op — unverified it would create another false-confidence control) — `hr-verify-repo-capability-claim-before-assert`; (2) blast radius: new authenticated-callable RPCs would need explicit grants (fail-closed 403 direction); (3) the **one residual ADP alone closes** — out-of-band (console/hotfix) DEFINER creation, invisible to BOTH the static lint and AC8; accepted now because `AP-002` + Terraform-only provisioning prohibits that path. Milestone from `knowledge-base/product/roadmap.md`.

## Files to Edit

- `apps/web-platform/test/migration-rpc-grants.test.ts` — import the extracted detector; replace per-file grant logic with the corpus-wide revoke-union (`{public,anon,authenticated}`, forward files only, type-precise, DROP-aware, `RETURNS TRIGGER`-excluded); add `AUTHENTICATED_CALLABLE` + grandfather allowlists; document the invariant.
- `apps/web-platform/test/rls-fuzz/rls-rpc.integration.test.ts` (or `catalog.ts`) — add the non-vacuity/live-catalog-parity assertion (static detected-set ⊇ live DEFINER enumeration).
- `knowledge-base/engineering/architecture/decisions/ADR-101-client-callable-security-invoker-rpc.md` + `ADR-111-runtime-authz-rls-fuzz-harness.md` — reciprocal `amended_by: ADR-112` cross-refs.
- `knowledge-base/engineering/architecture/principles-register.md` — add the `AP-NNN` row (advisory).
- **No `*.sql` migration edits** — the authenticated-callable set is handled via the test-file allowlist, NOT per-migration comment markers. Zero net grant/revoke statements added to any migration.

## Files to Create

- `apps/web-platform/test/migration-lint/definer-grants.ts` — DB-free detector (case-insensitive, header-terminated, `/* */`+dollar-body stripping, balanced-paren + type-precise signatures, `returnsTrigger` flag) + parseGrantRevoke + parseDropFunction + revoke-union resolver.
- `apps/web-platform/test/migration-lint/definer-grants.test.ts` — synthesized-fixture unit tests for every blind-spot class (Phase 3).
- `knowledge-base/engineering/architecture/decisions/ADR-112-definer-grant-hygiene-two-tier-guard.md` — two-tier guard decision (`amends: [ADR-101, ADR-111]`).
- `knowledge-base/project/learnings/best-practices/<topic>.md` — the "static lint was false-confidence for lowercase functions; two-tier guard with AC8 authoritative" finding (author picks date).
- One GitHub tracking issue (Phase 5) for the deferred ADP option.

## Open Code-Review Overlap

2 open `code-review` issues mention `supabase/migrations` but neither touches the target files: **#3220** (postmerge verification of trigger-bearing migrations) and **#3221** (nightly cron for env-gated integration tests). **Disposition: Acknowledge both** — different concern (CI scheduling/postmerge infra), not the static-lint detection generalization. They remain open.

## Domain Review

**Domains relevant:** Engineering / Security.

### Security (Engineering)

**Status:** reviewed (deepen-plan security-sentinel + data-integrity-guardian + architecture-strategist + spec-flow-analyzer all ran; findings folded into v2/v3 above).
**Assessment:** static test-lint hardening — no live-grant mutation, no schema change, no user-data path. The single-user-incident-grade invariant is authoritatively enforced by AC8 (unchanged); this plan removes false confidence from the subordinate static tier and adds a non-vacuity guard so it cannot silently regress. Load-bearing corrections folded: forbid `public`; exclude `.down.sql`; exclude `RETURNS TRIGGER`; type-precise signatures + DROP tracking. Product/UX = NONE (no UI-surface file).

### Product/UX Gate

Not applicable — no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product tier = **NONE**.

## Acceptance Criteria

1. `test/migration-lint/definer-grants.ts` detects lowercase `create … security definer` (a unit assertion confirms the old regex returned zero, the new returns the fn).
2. **Revoke-union requires all three roles:** a fixture revoking `anon, authenticated` but NOT `public` yields **VIOLATION**; a fixture revoking `public, anon, authenticated` (cross-file) yields **PASS**. No fixture where a `public`-retaining function PASSES.
3. `RETURNS TRIGGER` DEFINER fn with no anon/auth revoke yields **PASS** (excluded); a unit assertion confirms the exclusion fires.
4. Type-precision: two overloads where only one is revoked flags the un-revoked overload as **VIOLATION**.
5. Corpus excludes `*.down.sql` (`git grep -n "down" apps/web-platform/test/migration-lint/definer-grants.ts` shows an explicit exclusion) and a `.down.sql` re-grant fixture does not satisfy the union.
6. DROP-without-recreate fixture is excluded (no VIOLATION); block-commented / dollar-body-embedded grant fixture is ignored.
7. `./node_modules/.bin/vitest run test/migration-rpc-grants.test.ts test/migration-lint/` is **green** over the real corpus — every detected DEFINER fn is PASS-by-union, `RETURNS TRIGGER`-excluded, in `AUTHENTICATED_CALLABLE`, dropped, or on the documented grandfather allowlist. Zero silent skips.
8. Every `AUTHENTICATED_CALLABLE` entry cites its AC8 `EXCLUDED`/`ATTACK` classification; grep confirms ≥8 entries (the Phase-0 set), not zero.
9. Every grandfather-allowlist entry carries a ≥1-sentence rationale AND a tracking issue `#N`.
10. The non-vacuity parity guard exists and reds when the static detector under-detects relative to the live catalog (a fabricated under-detection in a test proves it fires).
11. `ADR-112-...md` exists with YAML `amends: [ADR-101, ADR-111]`, names AC8 as authoritative + the static tier as non-coverage-bearing + the out-of-band accepted residual; ADR-101/ADR-111 carry reciprocal cross-refs.
12. A `type/security` + `deferred-scope-out` tracking issue for the ADP option exists (`gh issue view <N>`), with the live-role-scope-probe + out-of-band-residual criteria.
13. No `.sql` migration adds/changes a grant (`git diff --stat` shows no net grant/revoke added to any migration).
14. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
15. The three C4 model files are unchanged; the enumerated "no C4 impact" justification holds.

## Observability

CI test code only (no `server/`/`src/`/`infra/` surface), but deepen-plan 4.7 treats non-pure-docs `.ts` as in-scope, so the 5-field schema is declared for the CI-check surface:

```yaml
liveness_signal:
  what: the generalized migration-lint (migration-rpc-grants.test.ts + test/migration-lint/) runs in the ordinary web-platform vitest suite on every PR; the runtime AC8 backstop + the new non-vacuity parity guard run via .github/workflows/rls-authz-fuzz.yml on every migrations/** PR
  cadence: per-PR (both jobs)
  alert_target: GitHub Checks (a red check blocks merge — fail-closed)
  configured_in: apps/web-platform/vitest.config.ts (test/**/*.test.ts) + .github CI test job + .github/workflows/rls-authz-fuzz.yml
error_reporting:
  destination: GitHub Checks / PR status (a violation prints the offending function signature + migration file to the vitest failure output)
  fail_loud: true (a detected violation fails the test → red required check → merge blocked)
failure_modes:
  - mode: lint false-negative (residual detection gap lets a mis-granted DEFINER fn pass the static pre-filter)
    detection: the runtime AC8 gate (live pg_proc.proacl) still reds; the non-vacuity parity guard reds if the static detector under-detects relative to the live catalog
    alert_route: rls-authz-fuzz CI job red + PR review
  - mode: lint false-positive (a legit authenticated-callable fn not in AUTHENTICATED_CALLABLE, a trigger not excluded, or a dropped overload not excluded)
    detection: the vitest lint reds on the introducing PR, naming the function + file
    alert_route: GitHub Checks red
  - mode: AC8-owned residual (revoke-then-DROP+CREATE-without-re-revoke false-passes the static union)
    detection: AC8 live-catalog introspection catches it exactly at runtime
    alert_route: rls-authz-fuzz CI job red
logs:
  where: vitest stdout in the GitHub Actions CI job logs (ordinary test job + rls-authz-fuzz job)
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/migration-lint/ test/migration-rpc-grants.test.ts"
  expected_output: green on a clean corpus; a seeded violation fails and prints the offending function signature + migration filename (no SSH, no stack — pure static analysis)
```

## Test Scenarios

- Detector unit tests (synthesized fixtures) — all Phase-3 classes incl. public-not-revoked, trigger-exclusion, and overload-conflation.
- Real-corpus lint — green over all forward migration files; the 5 lowercase files participate; `.down.sql` excluded; ~33 triggers excluded from the grant assertion.
- Non-vacuity parity — a fabricated static under-detection reds the parity guard.
- Regression guard — reverting the `i` flag reds the lowercase-detection unit test.
- Runtime gate untouched — `rls-authz-fuzz.yml` / `test:rls-fuzz` behavior unchanged except the added parity assertion.

## Risks & Sharp Edges

- **Forbid `public`, not just anon/authenticated (P0).** `public ⊇ {anon,authenticated}`; the union MUST require all three (the current test at `:146-151` already does; v1 regressed it).
- **Exclude `*.down.sql`.** `run-migrations.sh:125,251` skips them and warns they sort BEFORE the forward `.sql`; `128_...down.sql:24-28` re-grants anon/authenticated.
- **Exclude `RETURNS TRIGGER` from the grant assertion.** ~33 trigger DEFINER fns have no `GRANT EXECUTE` path; asserting a revoke on them reds the corpus and forces a ~30-entry allowlist. Keep the `search_path` pin check for them; drop the grant requirement. Mirrors AC8's `EXCLUDED` trigger classification.
- **Type-precise signatures (strip names + DEFAULT) + model DROP-without-recreate.** The 3-arg vs 4-arg `acquire_conversation_slot` overloads cross-cover under name-blind matching; the dropped 3-arg false-VIOLATEs unless removed from the assertion set.
- **Strip `/* */` block comments AND dollar-quoted bodies before parsing grants.** 035/053/068 carry block comments; 068 has real grants; a plpgsql `EXECUTE 'GRANT …'` string must not count as a top-level grant. Balanced-paren signature capture (`numeric(10,2)`, `default now()`).
- **Do not re-implement `has_function_privilege` statically.** AC8 computes net grant state exactly at runtime; the static tier is a deliberately-approximate pre-filter. The revoke-then-DROP+CREATE residual is AC8's to own (code-simplicity).
- **Revoke-union sidesteps the unproven ADP-inheritance premise** — it requires an *explicit* revoke regardless of the CREATE-time default, so it does not depend on the same assumption option (a) is deferred for.
- **Phase 1 and Phase 2 land atomically** — once detection is general, the old per-file assertion reds on 037-finder (revoked only in 128); the resolver must replace it in the same landing (no "no-behavior-change" intermediate).
- **Authenticated-callable set is ~8-12, not zero** — several are security-sensitive JWT-hook functions (060/068); verify each against its AC8 classification before allowlisting.
- **`handle_new_user` is not a grandfather case** (mig 112 pins+revokes).
- **New ADR-112, not amend ADR-111** — ADR-111 lacks YAML frontmatter, so an appended section is invisible to the amendment graph. Use `amends: [ADR-101, ADR-111]`.
- **Static tier must be non-coverage-bearing** — without the parity guard, "zero silent skips" inherits the detection blind spot; state the non-coverage-bearing status in ADR-112.
- **Do not add a new `AGENTS.md` rule** (`B_ALWAYS` at/near the 23000-byte cap).
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — filled with a concrete threshold + reason.

## Non-Goals / Deferred

- **Option (a) `ALTER DEFAULT PRIVILEGES`** — deferred (Phase 5) pending a live role-scope probe; the one residual it uniquely closes (out-of-band creation) is accepted, compensated by AP-002 + Terraform-only provisioning.
- **Rebuilding/re-scoping the runtime AC8 gate** — out of scope; only the non-vacuity parity assertion is added.
- **Wiring the fuzz harness into the ordinary no-stack vitest suite** — impossible without a DB stack; `rls-authz-fuzz.yml` is the correct home.
- **Remediating grandfathered pre-existing gaps** — tracked separately; this PR ships the enforcement + allowlist, not historical cleanup.
