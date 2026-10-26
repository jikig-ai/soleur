---
title: "feat: Explicit Data API grants for public-schema relations ahead of Supabase 2026-10-30 default change"
type: feat
date: 2026-10-26
slug: supabase-public-schema-grants
branch: feat-one-shot-supabase-public-grants
issue: none-yet
lane: cross-domain
requires_cpo_signoff: true
---

# feat: Explicit Data API grants for public-schema relations ahead of Supabase 2026-10-30 default change

> Spec lacks valid lane: — no `spec.md` exists for this branch; defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-26
**Sections enhanced:** Technical Considerations, Research Insights, Guard Contract, Alternatives
**Research agents used:** none spawnable in this harness — all deepen-plan mechanical halt gates and quality checks were applied directly by the planning agent (recorded below); the per-section/review-agent fan-out (skill phases 2–6) could not run and is flagged in `decision-challenges.md` + the session summary.

### Deepen halt-gate results

| Gate | Result |
|---|---|
| 4.4 precedent-diff | PASS — precedent locations cited (049/079/084/107 grant shapes, `definer-grants.ts:100` noise-stripper, `lint-migration-fk-preconditions.sh`, `rpc-cases.ts` registry); no novel pattern introduced |
| 4.5 network-outage | N/A — no trigger patterns |
| 4.55 downtime/cutover | Evaluated — no downtime class (grants-only DDL; note added to Technical Considerations) |
| 4.6 user-brand impact | PASS — section present, `single-user incident`, concrete content |
| 4.7 observability | PASS — 5 fields, probe `grep` allowlisted, literal `expected_output`, no ssh, <15s |
| 4.8 PAT-shaped variable | PASS — regex sweep zero hits |
| 4.9 UI-wireframe | N/A — no UI-surface files |
| 4.10 encryption posture | PASS — fields non-boilerplate, `does_not_defend` non-empty, no exception needed |
| 4.11 guard contract | PASS — `lint-guard-contract.py` green (2 entries, matrices ≥3 rows, structural assemblies) |
| 4.12 scope check | PASS — 1 unfenced section, all asks mapped, `Recommendation:` present |
| 4.13 task-design | N/A — no new autonomous-task surface (existing workflows edited only) |

### Key Improvements from the deepen pass

1. **Stale citation corrected** — #6340 auto-closed stale 2026-10-10 (NOT_PLANNED); the ADP live-probe never ran, so "pending probe" claims now read "no validated ADP path exists" (strengthens the per-table-grants choice).
2. **Lexer requirement folded into the lint spec** — the detector must noise-strip comments/dollar-bodies/strings per `definer-grants.ts:100` (a line-scanner would false-positive/negative); the `EXECUTE`-dynamic blind spot is explicitly assigned to the runtime tier.
3. **Snapshot scope pinned to the three api roles** — non-API-role grants (e.g., `supabase_auth_admin` in 049) replay verbatim and are outside the flip; grantee-set widening ruled out.
4. **ADR ordinal re-verified against freshly-fetched `origin/main`** — 303 confirmed next free; labels `domain/engineering` + `type/chore` verified live via `gh label list`; #4027/#4647 states verified live.

## Overview

On 2026-10-30 Supabase applies the post-May new-project default to all existing projects: tables created in `public` stop receiving automatic `SELECT,INSERT,UPDATE,DELETE` grants to `anon`/`authenticated`/`service_role` ([changelog 45329](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)). Existing tables keep their grants; only tables *created after* the flip are affected on an existing project — but every *fresh* environment (new project, preview branch, `supabase db reset`, a post-flip local `supabase start` per supabase/cli#5524) replays all 182 up-migrations into a world with no default table grants, so every relation the repo expects to be API-reachable needs explicit `GRANT`s.

This plan (1) lands a generated backfill migration that materializes today's effective per-relation api-role privileges as explicit grants — preserving deliberately-narrowed column-level and role-scoped postures verbatim — (2) flips the local `supabase` stack to the post-change default so CI exercises the real target state, (3) extends the rls-authz-fuzz harness with a live-catalog grant-coverage gate (authoritative tier per the ADR-112 precedent) and adds a static PR-diff migration lint (subordinate tier), and (4) records the convention in a new ADR.

## Problem Statement / Motivation

- **Deadline is 2026-10-30, today is 2026-10-26.** Any `create table` migration merged after the flip produces a table the Data API cannot see (`permission denied`, SQLSTATE 42501) on prd — silent breakage of whatever client reads it. Prior art for the failure shape: #4647 (onboarding dismissal writes silently failing on missing `GRANT UPDATE`) and `knowledge-base/project/learnings/2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`.
- **Fresh-environment replay is already broken-shaped.** 42 up-migrations create ~70 `public` relations; 28 of the 42 carry no api-role `GRANT` at all, and the 14 that do carry only partial grants. A new Supabase project, preview branch, or post-flip local stack built today would serve `permission denied` for nearly every table.
- **The rls-authz-fuzz harness has a false-green hole for this class.** AC-verdict logic discriminates `42501` as "denied" — a table denied by *missing grant* reads identically to a table denied by *RLS*. The fix needs a grant-*state* assertion, not another behavior probe.
- **A blanket backfill is a security regression.** Migrations 006 and 079 deliberately replaced table-level grants with column-level grants (`users`/`repos`); 049/`runtime_mint_intent` deliberately narrowed service_role (#4027, open). `GRANT ALL ON ALL TABLES` would silently re-open those surfaces. Postgres privilege resolution: a table-level grant subsumes all column-level grants (`2026-03-20-supabase-column-level-grant-override.md`).

## Proposed Solution

**Do not widen, do not hand-guess — snapshot.** Generate the backfill from the live prd catalog so the declared grant set IS today's audited effective state:

1. **Audit + generate.** A read-only catalog extraction (run via the existing `doppler run -c prd` run-verify path) dumps, per `public` relation (relkind `r`,`v`,`m`,`S`), the effective privileges for `anon`/`authenticated`/`service_role` from `information_schema.role_table_grants`, `information_schema.column_privileges`, and `information_schema.role_usage_grants`. Output = explicit `GRANT`/`REVOKE`-free DDL reproducing that state verbatim (table-level where held, per-column where table-level was deliberately revoked). The same extraction emits the per-relation classification (client-exposed / service-role-only / internal) that seeds the fuzz registry and the narrowing follow-up list.
2. **Backfill migration** `164_api_data_grants_snapshot.sql` (number provisional — next free at plan time; renumber per convention if a sibling lands first): the generated grants, idempotent (`GRANT` is idempotent; `IF EXISTS` guards not needed for grants but relation-existence `to_regclass` preconditions keep the file self-describing per the FK-lint convention). On prd this is a no-op (the privileges are already effective); on fresh builds it restores the exact prd posture.
3. **Flip the local stack to the new world (Ruled by CTO agent, 2026-10-26).** A post-start normalize step in `apps/web-platform/scripts/supabase-local.sh` applies Supabase's documented "Revoke default privileges" SQL after stack start — the PRIMARY path, not a fallback. The `[api] auto_expose_new_tables` config key does NOT exist on pinned CLI 2.84.2 (it was added by `supabase/cli#5239`, merged 2026-05-26; 2.84.2 released 2026-03-25) — writing it is dead config at best, a parse failure at worst. All local+CI starts funnel through the wrapper (`package.json` `db:start`; fuzz job `rls-authz-fuzz.yml:60-62`), so one normalize step covers both. With defaults off, the fuzz stack's grant state = explicit migration grants only, i.e., exactly the post-10-30 world. On any future CLI bump to >=v2.116.0 the swap to the declarative key is REQUIRED (unset re-enables auto-expose there) — recorded in ADR-303.
4. **Runtime authoritative gate.** Extend `test/rls-fuzz/catalog.ts` with a public-relation + sequence enumerator; new registry `test/rls-fuzz/table-grants.ts` (mirroring `rpc-cases.ts`) recording each relation's intended api-role privilege set; new gate `test/rls-fuzz/rls-grants.integration.test.ts` asserting `has_table_privilege`/`has_column_privilege`/`has_sequence_privilege` per registry on the applied stack, with catalog⇔registry parity so an unclassified new relation reds.
5. **Static subordinate lint.** `apps/web-platform/scripts/lint-migration-api-grants.sh` (+`.test.sh`), `--from-pr-diff`, wired into `tenant-integration.yml` beside `lint-migration-fk-preconditions.sh`: every diff-touched migration creating a `public` relation (table/view/materialized view, `temp` excluded) must carry an api-role `GRANT` for it in-file, or a `-- soleur:no-data-api: <relation> — <reason>` sentinel; serial/identity/sequence-using tables additionally require a sequence `GRANT USAGE` presence or the sentinel.
6. **Deploy-time sentinel.** `apps/web-platform/supabase/verify/164_*.sql` asserting expected-vs-effective grants on prd post-apply (runs automatically in the release `verify-migrations` job via `run-verify.sh`), plus the existing `rls-parity-check.ts` `role_table_grants` local-vs-prod diff as a continuous drift detector.

## Research Insights

**Relevant files:**

- `apps/web-platform/supabase/migrations/` — 294 files (182 up + `.down.sql` siblings + helpers). 42 up-files contain `create table`; 28/42 have zero api-role grant; 14/42 have partial grants.
- `apps/web-platform/scripts/run-migrations.sh` — canonical filename-tracked applier (ADR-111), `--single-transaction` per file; `migrate` job in `web-platform-release.yml` invokes it on prd (`web-platform-release.yml:1021`).
- `apps/web-platform/scripts/run-verify.sh` + `supabase/verify/NNN_*.sql` — post-apply sentinel convention; `verify-migrations` job runs it (`web-platform-release.yml:1023-1076`) including idempotence probes.
- `apps/web-platform/scripts/lint-migration-fk-preconditions.sh` (+`.test.sh`) and `lint-migration-immutability.sh` — the established bash migration-lint shape; wired into `tenant-integration.yml` (`:388`, `--from-pr-diff`, no-DB, early).
- `apps/web-platform/test/migration-lint/definer-grants.ts` — ADR-112's vitest static-tier sibling (for EXECUTE grants on definer functions; table grants are a different object class).
- `apps/web-platform/test/rls-fuzz/{catalog.ts,rpc-cases.ts,targets.ts}` — the live-catalog enumerator + classification-registry pattern to mirror; `bun run test:rls-fuzz` globs the whole dir (`package.json:18`), so a new gate file runs in the existing `rls-authz-fuzz` job.
- `apps/web-platform/scripts/rls-parity-check.ts` — already diffs `information_schema.role_table_grants` and `pg_roles` local-vs-prod (`:53,:59`); becomes a continuous proof that the snapshot matches prd once the local stack runs defaults-off.
- `apps/web-platform/scripts/supabase-local.sh` — the loopback-bound stack wrapper (ADR-153); home of the post-start normalize step (PRIMARY local-parity mechanism per CTO ruling — the config key does not exist on pinned CLI 2.84.2).
- `apps/web-platform/supabase/config.toml` — `[api]` section exists (`:21`), no `auto_expose_new_tables` key — and NOT added by this plan: the key first shipped in `supabase/cli#5239` (merged 2026-05-26), after pinned CLI 2.84.2 (2026-03-25). Dead config at best, parse failure at worst. Deferred until the deliberate CLI bump, where unset ≡ auto-expose again so `= false` becomes mandatory (>=v2.116.0 note per 6337; recorded in ADR-303).
- `.github/workflows/rls-authz-fuzz.yml` — local CLI stack, CLI pinned 2.84.2 (`:54`; the pin is deliberate — `:50-51` ties CLI/GoTrue to prod for ADR-111 parity, so no CLI bump under a 4-day deadline), applies migrations via run-migrations.sh (`[db.migrations] enabled = false`).
- `apps/web-platform/docs/migration-rollback.md` — forward-only convention; `.down.sql` files are manual aids, not automation.
- Learnings: `2026-03-20-supabase-column-level-grant-override.md` (table grant subsumes column grants — the 006/079 trap), `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md` (missing grant = silent write failure, #4224), `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` (`to_regclass` precondition convention).

**ADRs read (Phase 0.6 corpus grep):** ADR-111 (fuzz harness; `supabase db reset` structurally incompatible — 29 duplicate numeric prefixes; faithfulness contract includes `role_table_grants` parity), ADR-112 (two-tier guard precedent; `ALTER DEFAULT PRIVILEGES` deferred to #6340 pending a live role-scope probe — a mis-scoped ADP is a silent no-op under `supabase_admin`; **#6340 auto-closed stale 2026-10-10, NOT_PLANNED — the probe never ran**, so no validated ADP path exists either way), ADR-153 (loopback binding), ADR-044/ADR-101 (workspace tenancy + client-RPC conventions). No ADR decided the *table-grant* question — this plan's mechanism is not a rejected alternative; ADR-112's ADP-deferral reasoning (mis-scope = silent no-op) is the load-bearing precedent applied here.

**External docs:** Supabase changelog 45329 (the breaking change; existing tables keep grants), `supabase.com/docs/guides/api/securing-your-api` (default-privilege table: the flip removes `select,insert,update,delete` but tables KEEP `truncate,references,trigger,maintain` and sequences keep only `update` — **sequence `USAGE` is lost**, so serial/identity inserts via Data API would fail even with a table grant), `supabase/cli#5239` (`[api].auto_expose_new_tables` — added 2026-05-26, AFTER pinned CLI 2.84.2's 2026-03-25 release, so the key cannot be used here; per 6337, on CLI >=v2.116.0 unset re-enables auto-expose, so a future bump must set `false` explicitly).

**Premise Validation (Phase 0.6):** triage claims verified — migrations dir, 294 files, canonical applier, rls-authz-fuzz arm, and #4027 (OPEN, p3 tech-debt) all confirmed. One correction: "ZERO table-level grants" is inaccurate — 14 of 42 create-table files DO carry api-role table/column grants (e.g., 049 service_role-scoped, 079 column-scoped, 084, 107 view grant); the accurate claim is *partial, inconsistent coverage*. Substance stands. `#4647` surfaced as prior-art evidence. Serial/identity correction (Ruled by CTO agent, 2026-10-26): the claimed "≥11 migrations with serial/identity" matched only on comment words — the corpus has exactly ONE identity column (`138_agent_engine_runs.sql:66`), zero serials, zero `CREATE SEQUENCE`. Sequence privileges remain in scope (that column needs USAGE, and the guard arm is forward-looking for future serial/identity tables) — on corrected grounds, not the inflated count.

**Property List (Phase 0.6b):** P1 prd keeps serving the Data API exactly as today after 10-30 (no widening, no narrowing). P2 every fresh environment built by replaying the migration corpus reproduces prd's effective api-role privilege state. P3 deliberate narrowings (column-level splits 006/079, role-scoped 049) are preserved verbatim — never widened by the backfill. P4 a future create-table/view migration without required grants fails before merge. P5 drift between intended and effective grant state is detected continuously, on prd and on the local stack. P6 the local fuzz stack models the post-change default so the guards measure migration-grants, not platform-defaults.

**Cut List (Phase 0.6b):** `ALTER DEFAULT PRIVILEGES … GRANT` to restore auto-expose — buys P2 but re-opens the exact over-exposure Supabase is closing, contradicts #4027's narrowing direction, and ADR-112 already established a mis-scoped ADP under `supabase_admin` is a silent no-op pending the #6340 live probe → cut. Hand-editing the 42 historical migrations — buys P2 but violates `lint-migration-immutability.sh` and rewrites applied history → cut. Migration-file template — the lint's error text + sentinel already carry the convention; a template duplicates what ADR + lint enforce → cut.

## Research Reconciliation — Spec vs. Codebase

| Spec/triage claim | Codebase reality | Plan response |
|---|---|---|
| "ZERO migrations contain table-level GRANT to anon/authenticated/service_role" | 14 of 42 create-table files carry api-role table/column grants (049, 064, 079, 084, 107, 110, 138 partial via view); 28 carry none | Backfill generated from live catalog — both populations land in the same snapshot; no enumeration needed from source text |
| "rls-authz-fuzz CI arm gets permission-denied after 10-30" | The arm runs a LOCAL `supabase start` (CLI 2.84.2); breakage depends on the CLI's auto-expose behavior, not the hosted flip — and the `auto_expose_new_tables` key does not exist on the pinned CLI (supabase/cli#5239 landed 2026-05-26, after 2.84.2's 2026-03-25 release) | Normalize default privileges in `supabase-local.sh` post-start so the stack models the target world deterministically (Ruled by CTO agent, 2026-10-26 — the config-key form was rejected) |
| "supabase db reset recreates schema and loses grants" | `supabase db reset` is structurally incompatible with this repo — 29 duplicate numeric prefixes PK the CLI tracker (ADR-111) | Plan uses the repo's canonical `run-migrations.sh` replay; no `db reset` dependency |

## Open Code-Review Overlap

- #3220 (`ci: postmerge verification of trigger-bearing migrations in prd`) — **Acknowledge.** Same directory but a different property (trigger presence vs relation grant state). This plan's `verify/164_*.sql` asserts grant state only; it does not close #3220 and #3220 does not cover grants.
- No other open `code-review` issue bodies reference the planned file paths (queried 2026-10-26: catalog.ts, rpc-cases.ts, tenant-integration.yml, lint-migration paths, migrations/, rls-authz-fuzz.yml).

## Implementation Phases

### Phase A — Audit + snapshot generation

1. Write `apps/web-platform/scripts/dump-api-grants.sh` (or `.ts` next to `rls-parity-check.ts`): read-only extraction emitting (a) the GRANT DDL for migration 164 — table-level `GRANT <verbs> ON public.<r> TO <roles>` where held at table level, per-column `GRANT <verb> (<cols>)` where table-level was deliberately revoked (006/079 shape), `GRANT USAGE,SELECT ON SEQUENCE` per role_usage_grants — and (b) a per-relation classification block (RLS enabled? permissive policies per role? serial/identity columns?) used to seed `table-grants.ts` and the narrowing follow-up issue. <!-- verified: 2026-10-26 source: https://supabase.com/docs/guides/troubleshooting/database-api-42501-errors (role_table_grants), https://supabase.com/docs/guides/api/securing-your-api (default-privilege table) -->
2. Run it via `doppler run -c prd` against prd (read-only catalog introspection — the same access class `run-verify.sh` already uses).
3. Hand-review the generated grant matrix against the classification: flag any relation where the audit shows a *narrower* intended set than the snapshot (internal tables that hold default-era anon/auth grants they never use) — that list goes into the follow-up issue, NOT into this migration (P1: zero prd behavior change).

### Phase B — Backfill migration + sentinel

4. Write `apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.sql` — header documenting provenance (generated from prd catalog on <date>; generation command), `to_regclass` preconditions per convention, then the generated GRANT DDL grouped by relation with the classification annotation per relation. Covers tables, views, materialized views, sequences.
5. Write `164_api_data_grants_snapshot.down.sql` — **documented no-op** (comment-only body): the up adds grants already effective on prd; a `REVOKE` down would strip pre-existing default-era access and break prd — strictly worse than the forward state (see Down-migration analysis below).
6. Write `apps/web-platform/supabase/verify/164_api_data_grants_snapshot.sql` — per-relation `has_table_privilege`/`has_column_privilege`/`has_sequence_privilege` assertions for the full registered set, idempotent and re-runnable (the verify-migrations job re-runs it for the idempotence probe).

### Phase C — Flip the local stack to post-change defaults

7. Add a post-start normalize step to `apps/web-platform/scripts/supabase-local.sh` applying Supabase's documented "Revoke default privileges" SQL (`supabase.com/docs/guides/api/securing-your-api`) after stack start. This is the PRIMARY mechanism (Ruled by CTO agent, 2026-10-26): `auto_expose_new_tables` does not exist on pinned CLI 2.84.2 — do NOT write it to `config.toml`. All local+CI starts funnel through this wrapper (`package.json` `db:start`; fuzz job `rls-authz-fuzz.yml:60-62`), so one step covers both surfaces.
8. Assert the resulting `pg_default_acl` state after normalize — the fuzz stack must carry no api-role default table privileges. Annotate `<!-- verified: <date> source: <url> -->` at implementation per the CLI-verification gate.
9. Record in ADR-303 that on any future CLI bump to >=v2.116.0 the swap to `[api] auto_expose_new_tables = false` becomes REQUIRED (per 6337, unset re-enables auto-expose on newer CLIs) — the declarative key replaces the normalize step then, not now.

### Phase D — Guards (runtime authoritative + static subordinate)

10. `apps/web-platform/test/rls-fuzz/table-grants.ts` — registry mirroring `rpc-cases.ts`: per public relation + sequence, `EXPOSED: { role: Set<verb> }` (matching the 164 snapshot) or `INTERNAL` with a reason citing the classification audit.
11. `apps/web-platform/test/rls-fuzz/catalog.ts` — add `publicApiRelations()` + `publicApiSequences()` enumerators from `pg_class`.
12. `apps/web-platform/test/rls-fuzz/rls-grants.integration.test.ts` — the gate: for every catalog member, assert effective privileges equal the registered set (`has_table_privilege` per verb per role; column-privilege assertions for the 006/079 shapes; `has_sequence_privilege` for sequences); catalog⇔registry parity assertion (unclassified member red; registry entry for a nonexistent relation red).
13. `apps/web-platform/scripts/lint-migration-api-grants.sh` + `.test.sh` — PR-diff static lint per the FK-lint shape: detector for `create (unlogged )?table|view|materialized view` on `public` relations (case-insensitive, `if not exists`, `partition of` excluded if inherited — decide at implementation; `temp` excluded), per-relation requirement of an in-file `GRANT … TO (anon|authenticated|service_role)` or a `soleur:no-data-api:` sentinel; serial/identity tables additionally require a sequence-grant presence or sentinel. **Lexer requirement:** the detector MUST strip SQL noise first — `--`/`/* */` comments, dollar-quoted bodies, single-quoted strings — mirroring `test/migration-lint/definer-grants.ts:100` (the noise-stripper precedent; port or reuse it, do not line-scan raw text). Documented blind spot, owned by the runtime tier: a relation created via dynamic `EXECUTE format(...)` inside a `DO` block is invisible to source-form detection — the fuzz gate's live-catalog enumeration is the backstop, exactly the ADR-112 two-tier split.
14. Wire `bash scripts/lint-migration-api-grants.sh --from-pr-diff` into `.github/workflows/tenant-integration.yml` next to the FK-precondition step (`:386`) — early, no DB.

### Phase E — Decision record + deferral

15. Author `ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md` (ordinal provisional; next free is 303 — sweep on collision per the ordinal gate) recording: explicit per-relation grants as the convention, the two-tier authority split (fuzz gate authoritative, lint subordinate — mirroring ADR-112), the ADP-restore rejection (with the ADR-112/#6340 mis-scope reasoning), and the local-parity mechanism — `supabase-local.sh` post-start normalize under pinned CLI 2.84.2, with the recorded swap to `[api] auto_expose_new_tables = false` becoming REQUIRED at any CLI bump to >=v2.116.0 (6337: unset re-enables auto-expose there).
16. File the narrowing follow-up issue (grant-hygiene audit list from Phase A; relates #4027) and mark it blocked-by nothing — it has no deadline; label `domain/engineering`, `type/chore`, `code-review`-adjacent wording avoided.
17. File a tracking issue for THIS change if the pipeline wants a `#N` (changelog/PR body link; optional — the PR can stand on the changelog citation alone).

## Technical Considerations

- **Immutability.** The 42 historical create-table migrations are applied history — `lint-migration-immutability.sh` forbids editing them. All grant materialization lives in the forward migration only.
- **Postgres privilege resolution.** A table-level grant subsumes all column-level grants/revokes on the same table (`2026-03-20` learning). The snapshot MUST emit per-column grants where table-level was deliberately revoked — verified against `column_privileges`, not guessed.
- **Sequences.** Post-change, new sequences keep only `update` — `USAGE` (needed for `nextval`/identity inserts via Data API) is lost. The snapshot and lint both cover `public` sequences.
- **Down-migration semantics.** Convention ships a `.down.sql` sibling, but this migration's honest down is a no-op: `GRANT`s that duplicate already-effective privileges cannot be "un-added" — `REVOKE` removes the ACL entry regardless of whether it came from defaults or the explicit grant, so a revoke-down on prd would *reduce* access below the pre-164 state. The `.down.sql` documents this; a real rollback is the manual procedure in `docs/migration-rollback.md`.
- **False-green kill.** The fuzz gate asserts grant *state* (`has_table_privilege`), not access *behavior* — a missing grant can no longer masquerade as an RLS denial (both are 42501 at the SQL layer).
- **Availability during apply (deepen 4.55 evaluated — no downtime class).** The migration is grants-only DDL: `GRANT` takes a brief metadata lock per relation, no table rewrite, no `CONCURRENTLY`-forbidden constructs, one `--single-transaction` apply. Zero-downtime by construction; the offline-inducing trigger list (rewrite DDL, hot-table locks, deploy/router changes) does not match.
- **Scope of the snapshot: the three api roles only.** `anon`/`authenticated`/`service_role` are the roles the flip affects. Non-API-role grants already explicit in migrations (e.g., 049's `supabase_auth_admin`) replay verbatim on fresh builds and are unaffected — do NOT widen the snapshot's grantee set.
- **Migration role grant-authority.** `run-migrations.sh` applies files as the connecting role, which owns the tables it created — `GRANT` needs no extra privilege. Assumes the same DSN role used on every apply path (prd migrate job + fuzz stack both use it; the fuzz run is itself the proof).
- **Attack surface enumeration (grant surface):** every `public`-schema relation is reachable through (a) PostgREST/supabase-js as `anon`/`authenticated` (RLS-bounded), (b) `service_role` (RLS-bypassing — server-only), (c) SECURITY DEFINER RPCs (owner rights, grant-independent — governed by ADR-112's AC8, out of scope), (d) direct SQL as the migration/postgres owner (grant-independent). The snapshot only materializes (a)/(b)'s existing state; (c)/(d) are unaffected by definition.
- **NFR:** no performance impact (ACL metadata); security posture preserved exactly; compliance posture preserved exactly (no new processing — see GDPR note).
- **GDPR advisory (Phase 2.7 gate fires — `.sql` surfaces).** The change alters no data flow: it re-states privileges already effective on prd. PII-bearing relations (`dsar_export_audit_pii`, `beta_contacts`, `email_*`, `messages`, `conversations`) receive exactly their current grants; the narrowing follow-up is where any Art. 5(1)(c) minimization of the API surface would land. No Critical findings anticipated; no `compliance-posture.md` write.

## Files to Create

- `apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.sql`
- `apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.down.sql` (documented no-op)
- `apps/web-platform/supabase/verify/164_api_data_grants_snapshot.sql`
- `apps/web-platform/scripts/dump-api-grants.sh` (or `.ts` — implementer picks the file shape that matches `rls-parity-check.ts` conventions)
- `apps/web-platform/scripts/lint-migration-api-grants.sh`
- `apps/web-platform/scripts/lint-migration-api-grants.test.sh`
- `apps/web-platform/test/rls-fuzz/table-grants.ts`
- `apps/web-platform/test/rls-fuzz/rls-grants.integration.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md`

## Files to Edit

- `apps/web-platform/scripts/supabase-local.sh` — post-start normalize step (PRIMARY local-parity mechanism per CTO ruling)
- `apps/web-platform/test/rls-fuzz/catalog.ts` — add `publicApiRelations()`/`publicApiSequences()`
- `.github/workflows/tenant-integration.yml` — add the lint step beside the FK lint

## User-Brand Impact

- **If this lands broken, the user experiences:** on any environment provisioned after 2026-10-30 (preview, new project, fresh local stack), every screen backed by an un-granted table fails with `permission denied` — login-adjacent data (conversations, workspaces, kb_files) included; on prd, a *mis-scoped* grant could expose a table the RLS layer assumed unreachable.
- **If this leaks, the user's data is exposed via:** an over-broad `GRANT` on a PII-bearing relation (`dsar_export_audit_pii`, `messages`, `conversations`, `beta_contacts`) reaching `anon`/`authenticated` through the Data API — bounded by RLS where policies exist, unbounded for `service_role` and for relations relying on grant-absence as part of their posture (006/079 column splits, 049).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** a one-verbatim-verb mistake in the generated snapshot on a PII table exposes one founder's data — a single-user breach class identical to the RLS-leak class ADR-111 scoped `single-user incident`; `none` is untenable because the migration touches grant ACLs on PII-adjacent tables.

`requires_cpo_signoff: true` set in frontmatter. CPO sign-off is required at plan time before `soleur:work` begins — **discharged 2026-10-26**: `soleur:product:cpo` and `soleur:engineering:review:user-impact-reviewer` both returned GRANTED (rationale in `decision-challenges.md`).

## Observability

```yaml
liveness_signal:
  what: "release pipeline `migrate` job applies 164 via run-migrations.sh; `verify-migrations` job then runs supabase/verify/164 sentinel against prd (plus idempotence re-run)"
  cadence: per-release (on merge to main)
  alert_target: GitHub required-check red on the release workflow; post-merge monitor arm
  configured_in: .github/workflows/web-platform-release.yml (migrate :1021, verify-migrations :1023)
error_reporting:
  destination: GitHub Actions job logs + workflow conclusion (no Sentry surface — CI/deploy artifact)
  fail_loud: "nonzero exit from run-migrations.sh (migrate red, deploy blocked) or run-verify.sh (verify-migrations red)"
failure_modes:
  - mode: migration 164 fails to apply on prd
    detection: `migrate` job exits nonzero; deploy arm stops before deploy
    alert_route: workflow red on the merge; operator sees failed required check
  - mode: effective grants on prd drift from the registered set
    detection: `verify/164` sentinel red in verify-migrations; rls-parity-check.ts role_table_grants diff red in rls-authz-fuzz
    alert_route: workflow red
  - mode: future migration creates a public relation without grants
    detection: lint-migration-api-grants.sh --from-pr-diff red in tenant-integration; fuzz rls-grants gate red
    alert_route: PR check red (merge blocked)
logs:
  where: GitHub Actions job logs (web-platform-release.yml, tenant-integration.yml, rls-authz-fuzz.yml)
  retention: GitHub Actions default retention
discoverability_test:
  command: grep -m1 'GRANT ' apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.sql
  expected_output: GRANT
```

## Encryption Posture

```yaml
at_rest:
  - store: supabase.prd (existing Postgres — no new store introduced; grants-only DDL)
    mechanism: provider-managed:Supabase disk encryption at rest
    evidence: "Supabase security docs — https://supabase.com/security (retrieved 2026-10-26); unchanged by this change"
    defends_against: nothing new — ACL metadata only; storage posture identical to pre-change
    does_not_defend: "an over-broad GRANT itself — bounded by snapshot-exact generation + verify/164 + fuzz gate, not by storage encryption"
    disclosed_as: not-publicly-claimed
    live_verification: available:verify/164 role_table_grants sentinel post-apply
in_transit:
  - connection: release-runner -> supabase.prd (existing migrate path)
    enforced_at: apps/web-platform/scripts/run-migrations.sh (DATABASE_URL/DATABASE_URL_POOLER)
    tls: postgres TLS per existing DSN — unchanged by this change
    cert_verification: on
    does_not_defend: "credential leakage of the migration role — unchanged by this change"
    disclosed_as: not-publicly-claimed
# no exception block: no plaintext-exception, cert_verification on
```

## Guard Contract

### Guard 1 — lint-migration-api-grants.sh (static PR-diff lint)

**Property.** Every migration file touched by a PR that creates a `public`-schema Data-API-visible relation (table, view, materialized view — temp and partition-child excluded) carries an in-file api-role `GRANT` for that relation (plus a sequence `GRANT USAGE` when the table has serial/identity columns), or an explicit `soleur:no-data-api:` sentinel recording intent.

**Assembly.** All `apps/web-platform/supabase/migrations/*.sql` files (forward files only — `.down.sql` is a manual-aid sibling never applied by run-migrations.sh) that appear in the `git diff origin/main...HEAD` name list. The chokepoint is the `--from-pr-diff` step in `tenant-integration.yml` — the single CI path migration PRs flow through; direct file-arg invocation is the local path. The corpus is deliberately NOT asserted (the 28 pre-existing ungranted create-table files are covered by migration 164, not by self-grants; the lint's window is new/modified files).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture migration with `CREATE TABLE public.t` and no GRANT → run lint | RED (exit 1, names `t`) |
| 2 | Same fixture plus `GRANT SELECT ON public.t TO anon` (lowercase, single-role — a non-canonical permitted form) | PASS (must-PASS row) |
| 3 | Fixture creates `public.t1` AND `public.t2`; grant covers only `t1` | RED — a check stopping at the first member is the defect itself |
| 4 | Delete/rename the create-relation detector branch so no relation is ever found on a fixture that creates one | RED — `.test.sh` fixture suite asserts detection; a lint reporting "0 checked" is vacuous |
| 5 | Fixture with `.down.sql` suffix containing `create table` | PASS (permitted difference — down files are never applied) |
| 6 | Fixture table with `GENERATED ALWAYS AS IDENTITY`, table grant present, no sequence grant, no sentinel | RED (sequence arm) |
| 7 | Fixture with `-- soleur:no-data-api: audit_x — internal-only, definer-RPC access` sentinel | PASS (permitted difference — the classification escape hatch) |
| 8 | `create table` inside a `--` comment or dollar-quoted string in a diffed migration | PASS (permitted difference — the noise-stripper must not false-positive on non-DDL text) |
| 9 | Mutate the `.test.sh` harness: flip T1's expected exit code | RED (harness row — suite must not be satisfiable by a stub) |

### Guard 2 — rls-fuzz grant-coverage gate (runtime, authoritative)

**Property.** On the applied stack, every `public`-schema relation's and sequence's effective privileges for `{anon, authenticated, service_role}` exactly equal its registered classification — no missing grants (P2) and no unregistered exposure (P3).

**Assembly.** Live `pg_class` enumeration of `public` relkind `r`,`v`,`m`,`S` on the fuzz stack — every member flows through `test/rls-fuzz/table-grants.ts` (the single classification registry; unregistered member reds via the catalog⇔registry parity assertion). Chokepoint: the `rls-authz-fuzz` job (`test:rls-fuzz` globs the dir), a required check. With the `supabase-local.sh` normalize applied, effective state = explicit migration grants only — the gate measures what migrations declared, not platform defaults (P6).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Registry marks `public.t` `INTERNAL` but a fixture migration grants `SELECT` on it to `anon` | RED (over-grant detection) |
| 2 | Fixture migration creates `public.new_t` with no `table-grants.ts` entry | RED (own-dispatch — catalog enumerates a member the registry cannot classify) |
| 3 | Registry expects `{authenticated: {SELECT}}` on `t`; migration grants only `anon` | RED (role-set mismatch) |
| 4 | Reorder/short-circuit: gate returns after the FIRST catalog member; second member is mis-granted | RED (order/lifetime row — assertion must live inside the enumeration, not after it) |
| 5 | Remove one registered relation's GRANT lines from the generated migration 164 on the defaults-off stack | RED (remediation's own output tested against the guard — the post-change tree, not the pre-change tree) |
| 6 | Registry marks relation `INTERNAL`, it carries zero api-role grants on the stack | PASS (must-PASS non-canonical — the unexposed member path) |
| 7 | Mutate the harness: stub `has_table_privilege` to always-true while a fixture mis-grants | RED via the parity/vacuity assertion (a satisfied-by-nothing gate cannot pass) |

## Architecture Decision (ADR/C4)

This plan establishes a cross-cutting invariant — *every `public` relation declares its Data API privilege surface explicitly* — and a two-tier authority split mirroring ADR-112. Both are decision records a future engineer must find.

### ADR

Create `ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md` (ordinal provisional — 303 is next free at plan time; on collision renumber and sweep `grep -rn 'ADR-303' knowledge-base/project/{plans,specs}/feat-one-shot-supabase-public-grants/` + the file in the same edit). One-line decision: *explicit per-relation api-role GRANTs are required for every public-schema relation, enforced by a live-catalog gate (authoritative) + a PR-diff static lint (subordinate); `ALTER DEFAULT PRIVILEGES` auto-expose is rejected.* Carries `related_adrs: [ADR-111, ADR-112]` and reciprocal cross-refs into ADR-112's header (its two-tier pattern extended to relation grants).

### C4 views

No C4 impact — checked against `model.c4`/`views.c4`/`spec.c4` on 2026-10-26: (a) external human actors — none added (no new data sender/recipient); (b) external systems/vendors — none added (Supabase is already modeled: `model.c4` `supabase = database`, edges `webapp -> supabase` :579, `engine -> supabase` :585); (c) containers/data-stores — no new store; the grant change is intra-database ACL metadata on the existing `supabase` container; (d) actor↔surface access relationships — the effective access relationships are unchanged by design (snapshot-exact = P1). CI gates and DB ACLs are not modeled elements (precedent: ADR-112 §C4 impact).

### Sequencing

The ADR ships in this PR describing the landed state (`status: accepted`); the grant-narrowing follow-up is an audit output, not an architecture decision, and needs no ADR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "A backfill migration (or equivalent) that explicitly grants the correct Data API privileges on ALL existing public-schema tables to anon/authenticated/service_role, matching whatever access each table is actually meant to have — audit how each table is accessed" | Phase A audit+generate; Phase B migration 164; snapshot-exact preserves "actually meant to have" as the audited effective state; per-table classification seeds the fuzz registry + narrowing follow-up | mapped |
| 2 | "Consider ALTER DEFAULT PRIVILEGES for the migration role vs per-table grants — weigh over-exposure risk for internal-only tables" | Cut List + Alternatives: ADP rejected (over-exposure + ADR-112 mis-scope precedent); per-table explicit grants chosen | mapped |
| 3 | "A durable guard so a future create table migration without the required grants fails before merge" | Phase D: fuzz grant gate (authoritative) + lint-migration-api-grants.sh (subordinate) + tenant-integration wiring | mapped |
| 4 | "match how this repo already lints migrations; check apps/web-platform/supabase/scripts/ and verify/ and existing lefthook/CI gates" | Lint mirrors `lint-migration-fk-preconditions.sh` shape + `--from-pr-diff` in tenant-integration.yml; `verify/164` sentinel mirrors the verify/ convention | mapped |
| 5 | "Down-migration implications" | `.down.sql` documented no-op + Technical Considerations analysis | mapped |
| 6 | "whether tests/CI (rls-authz-fuzz) can prove the fix" | `supabase-local.sh` post-start normalize (defaults-off stack) + catalog grant-state gate + `rls-parity-check.ts` role_table_grants diff | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `supabase-local.sh` post-start normalize (defaults-off local stack) | inferred — ask said "make this repo safe" + "rls-authz-fuzz … gets permission-denied"; defaults-off is what makes the CI arm prove the fix deterministically (ask 6); mechanism set by CTO ruling 2026-10-26 (config key absent on pinned CLI 2.84.2) | inferred (justified) |
| fuzz `table-grants.ts` registry + gate | "durable guard" (ask 3) + "tests/CI (rls-authz-fuzz) can prove the fix" (ask 6) | asked |
| lint script + workflow step | "durable guard … fails before merge (lint script / CI check)" (ask 3) | asked |
| ADR-303 + narrowing follow-up issue | inferred — cross-cutting convention change requires an ADR (plan Phase 2.10 gate); deferral-tracking checklist requires filing deferred items | inferred (justified) |
| sequence USAGE coverage | inferred — "Data API privileges … matching whatever access each table is actually meant to have"; inserts via API fail without sequence usage post-flip (Supabase docs) | inferred (justified) |
| `verify/164` sentinel | "check … verify/ and existing … gates for migrations" (ask 4) | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/supabase/` (migration), `apps/web-platform/scripts` + `apps/web-platform/test/rls-fuzz` (local-stack normalize + guards), `.github/workflows/` (lint wiring)
- Planned files: 9 create + 3 edit (12) | Estimated changed lines: ~700 (dominated by generated grant DDL, ~70 relations)
- Thresholds: >= 4 subsystem roots OR > 25 files OR > 800 lines — under all three
- Recommendation: single PR — the lint and gate are what make the migration verifiable; splitting them from it ships the invariant unguarded.

## Domain Review

**Domains relevant:** none (cross-domain)

Engineering-domain infrastructure change executed inside the engineering pipeline itself: DB ACL metadata, a CI lint, a test-harness gate, an ADR. No user-facing surface (Product NONE — no UI-surface file in Files lists; the mechanical override does not fire), no marketing/legal/finance/operations/sales/support implication beyond the GDPR advisory folded into Technical Considerations and the CPO-signoff requirement carried by `## User-Brand Impact`.

## Acceptance Criteria

- [ ] **AC1.** `apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.sql` exists, is generated from a prd catalog extraction (provenance comment names the command + date), applies cleanly via `run-migrations.sh` on a fresh defaults-off stack, and its grant set covers EVERY `public` relation (relkind r,v,m) and sequence that holds api-role privileges on prd — completeness proven by the verify sentinel, not by file inspection.
- [ ] **AC2.** Post-apply on prd, effective api-role privileges for every public relation are IDENTICAL to pre-apply (snapshot-exact): `verify/164` per-relation `has_*_privilege` assertions pass and the `rls-parity-check.ts` `role_table_grants` diff shows no drift. No table-level grant is added where column-level postures exist (`users` UPDATE-email-only, `repos` column-split, `runtime_mint_intent` service_role-scoped — the 006/079/049 shapes asserted verbatim).
- [ ] **AC3.** `apps/web-platform/scripts/supabase-local.sh` normalizes default privileges post-start (Supabase's documented revoke-default-privileges SQL), the fuzz job asserts the local stack's `pg_default_acl` carries no api-role default table grants, and `config.toml` carries NO `auto_expose_new_tables` key (absent on pinned CLI 2.84.2).
- [ ] **AC4.** `bash apps/web-platform/scripts/lint-migration-api-grants.sh --from-pr-diff` exits 1 on a create-table-without-grant diff, 0 on granted/sentinel fixtures, and runs as a step in `tenant-integration.yml`; `lint-migration-api-grants.test.sh` covers the mutation-matrix rows (table, view, second-member, serial/identity-sequence arm, down-file skip, sentinel, case-insensitivity).
- [ ] **AC5.** `test/rls-fuzz/rls-grants.integration.test.ts` enumerates live `pg_class` and asserts registered grant state with catalog⇔registry parity; `bun run test:rls-fuzz` is green including the new gate; a new unclassified public relation demonstrably reds it (fixture run or test case).
- [ ] **AC6.** `verify/164_api_data_grants_snapshot.sql` passes under `run-verify.sh` post-apply on prd and is idempotent (verify-migrations re-runs it).
- [ ] **AC7.** `ADR-303-*.md` exists with the decision, alternatives (incl. ADP-restore rejection), `related_adrs` cross-refs; ADR-112's header gains the reciprocal pointer.
- [ ] **AC8.** The grant-narrowing follow-up issue is filed carrying the Phase-A per-relation audit list, relates #4027, and carries re-evaluation criteria.
- [ ] **AC9.** `164_api_data_grants_snapshot.down.sql` exists and is a documented no-op explaining why REVOKE-down is unsafe on prd.
- [ ] **AC10.** Every new migration-creating relation on the defaults-off local stack is API-reachable exactly per its registered classification — the P2 property proven end-to-end by the fuzz job on this PR's own migrations.

## Test Scenarios

- Given a fixture migration `CREATE TABLE public.lint_probe` with no GRANT, when `lint-migration-api-grants.sh --from-pr-diff` runs, then exit 1 naming `lint_probe` — `unit` (bash fixture, `.test.sh`).
- Given a fixture with `GRANT SELECT ON public.lint_probe TO authenticated` (lowercase), when the lint runs, then exit 0 — `unit`.
- Given a fixture creating two tables granting only the first, when the lint runs, then exit 1 — `unit`.
- Given a fixture `.down.sql` containing `create table`, when the lint runs, then exit 0 — `unit`.
- Given a fixture with `GENERATED ALWAYS AS IDENTITY` + table grant + no sequence grant, when the lint runs, then exit 1 — `unit`.
- Given the full corpus applied on the defaults-off stack, when `rls-grants.integration.test.ts` runs, then every registered relation matches its classification and parity holds — `integration`.
- Given a scratch migration adding `public.unregistered_probe` on the fuzz stack, when the gate runs, then RED via the catalog⇔registry parity assertion — `integration`.
- Given 164 applied on prd, when `run-verify.sh` executes `verify/164`, then all privilege assertions pass; re-run → still pass (idempotent) — `integration`.
- Given `users` and `repos` post-164, when `column_privileges` is read, then `authenticated` holds UPDATE(email)-only on users and the 079 column split on repos — never a table-level grant — `integration` (verify/164 arm).
- Given the release merges, when `verify-migrations` runs, then the sentinel passes and `rls-parity-check.ts` shows zero `role_table_grants` drift — `e2e`, `pyramid-justified: the property is prod-vs-local catalog equality; only exercisable in the release path`.

## Success Metrics

- `bun run test:rls-fuzz` green including the new grant gate on this PR.
- Post-release `verify-migrations` green with `verify/164` passing on prd.
- `rls-parity-check.ts` `role_table_grants` local-vs-prod diff clean on the PR's own fuzz run.
- A deliberately-ungranted create-table fixture reds both the lint and the fuzz gate (mutation-matrix proof).
- Zero `permission denied` regressions: tenant-integration + ordinary suites green.

## Dependencies & Risks

- **Deadline pressure:** 4 days to the flip. Mitigation: the lint alone prevents the acute prd risk (new table post-flip without grants); prd's existing tables are never affected by the flip, so the backfill is not on the prod-critical path — it is on the fresh-environment path.
- **Race:** a `create table` migration merged before this PR would need manual grants post-flip — flag in PR body; consider landing the lint first if the PR grows.
- **`auto_expose_new_tables` on CLI 2.84.2:** resolved by CTO ruling 2026-10-26 — the key was added by `supabase/cli#5239` (merged 2026-05-26) and does NOT exist on the pinned CLI; the `supabase-local.sh` normalize is the primary path, not a fallback. On any future bump to >=v2.116.0 the config key becomes required (unset re-enables auto-expose per 6337) — recorded in ADR-303.
- **prd catalog read:** `doppler run -c prd` read-only path is the established `run-verify.sh` mechanism — no new credential surface.
- **Generated-file drift:** the snapshot is a point-in-time prd state; relations created between generation and merge must be re-swept — the fuzz gate (registry parity) catches the miss if the author forgets.
- **#4027 interaction:** runtime_mint_intent's deliberately narrow service_role grants are preserved by snapshot-exact; the narrowing follow-up must not conflict with #4027's scope.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| `ALTER DEFAULT PRIVILEGES FOR ROLE <migration-role> IN SCHEMA public GRANT …` to keep auto-expose | Rejected — re-opens the exact over-exposure Supabase is closing (every internal table becomes API-granted under RLS), contradicts #4027's narrowing direction, and ADR-112 established that a mis-scoped ADP under `supabase_admin` is a silent no-op (the #6340 probe meant to validate ADP auto-closed stale 2026-10-10 and never ran — no validated ADP path exists) |
| Hand-audit each of ~70 relations and hand-write grants | Rejected as the grant source — snapshot-from-catalog IS the audit materialized; the hand audit still runs to produce the classification registry + narrowing list, but not the DDL |
| Tighten internal-table grants during the backfill | **Deferred** — any narrowing changes prd behavior (P1 forbids) and needs per-relation consumer proof; filed as follow-up issue paired with #4027 |
| Edit the 42 historical migrations to carry grants | Rejected — `lint-migration-immutability.sh` forbids mutating applied history; a single forward backfill covers the corpus |
| Vitest static tier (`test/migration-lint/table-grants.ts`) instead of bash lint | Rejected — the FK-lint bash `--from-pr-diff` shape is where migration PR-diff checks already live (fails fast, pre-DB); the authoritative tier is the fuzz gate either way |
| No `.down.sql` | Rejected — convention ships a sibling per migration; the honest down is a documented no-op (REVOKE-down would reduce prd below pre-164 state) |

## References & Research

- Supabase changelog 45329 — <https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically>
- Supabase "Securing your API" default-privilege table — <https://supabase.com/docs/guides/api/securing-your-api>
- `supabase/cli#5239` — `auto_expose_new_tables` (added 2026-05-26; absent on pinned CLI 2.84.2)
- `supabase.com/docs/guides/troubleshooting/database-api-42501-errors` — `role_table_grants` introspection + recommended `GRANT` remediation
- ADR-111, ADR-112, ADR-153 (this repo)
- Issues: #4027 (narrow service_role grants), #4647 (missing-grant silent failure), #6306/#6328 (definer EXECUTE grant class), #6340 (ADP live-probe), #3220 (overlap — acknowledged)
- Learnings: `2026-03-20-supabase-column-level-grant-override.md`, `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`, `2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`

## Sharp Edges

- Do NOT hand-write the grant DDL — generate it from `role_table_grants` + `column_privileges` + `role_usage_grants`; hand lists of ~70 relations rot before review.
- Do NOT emit table-level grants for the 006/079 column-split relations — a table grant silently re-grants every column (Postgres subsumption), re-opening `github_installation_id` and `tc_accepted_at`.
- Do NOT rely on the fuzz harness's RLS-denial verdicts to prove grant coverage — 42501 conflates "denied by grant" with "denied by RLS"; assert `has_table_privilege` state.
- Do NOT skip the sequence arm — post-change sequences lose `USAGE`; serial/identity inserts via Data API fail even with the table granted.
- Do NOT write a REVOKE-bearing `.down.sql` — it strips default-era effective access on prd, strictly worse than the forward state.
- Do NOT leave the local stack on implicit defaults — without the `supabase-local.sh` normalize the gate measures platform defaults, not migration grants, and the whole proof is circular. Do NOT write `auto_expose_new_tables` to `config.toml` — the key does not exist on pinned CLI 2.84.2 (added 2026-05-26, post-2.84.2); dead config at best, parse failure at worst.
- Do NOT forget the migration number is provisional (164 at plan time) — a sibling `16x` can land first; renumber the up/down/verify trio together.
- The lint's `soleur:no-data-api:` sentinel requires a reason — an uncommented sentinel is an allowlist entry with no rationale (the ADR-112 EXCLUDED-class escape-hatch lesson).
- CPO sign-off was required before `soleur:work` (threshold `single-user incident`) — discharged 2026-10-26: CPO agent + user-impact-reviewer both GRANTED (`decision-challenges.md`).
