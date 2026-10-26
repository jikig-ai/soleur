# CTO Rulings — feat-one-shot-supabase-public-grants

Six binding technical rulings on the forks in
`knowledge-base/project/plans/2026-10-26-feat-supabase-public-schema-grants-plan.md`.
Evidence verified against the worktree on 2026-10-26; external claims verified against
supabase/cli release and PR metadata.

---

## Item 1: Per-table explicit GRANTs vs ALTER DEFAULT PRIVILEGES

Ruled by CTO agent, 2026-10-26: Per-table explicit GRANTs in each creating/backfill migration — ADP-restore rejected - ADP re-opens the exact over-exposure Supabase is closing, contradicts #4027's narrowing direction, and ADR-112 already established that a mis-scoped ADP under `supabase_admin` is a silent no-op (ADR-112:83; the #6340 validation probe auto-closed stale 2026-10-10 and never ran, so no validated ADP path exists). Explicit GRANTs are idempotent, diff-reviewable, lintable, and snapshot-exact.

**Decision:** Per-table explicit GRANTs. The backfill migration materializes the audited per-relation privilege set; the two-tier guard (lint + fuzz gate) covers future creates. No `ALTER DEFAULT PRIVILEGES` restore.

**Rationale:** Default privileges are per-creator-role (`FOR ROLE <creator>`): the applier role differs between the local stack (`postgres`, per `RLS_FUZZ_DATABASE_URL` in `.github/workflows/rls-authz-fuzz.yml:40`) and hosted prd, so a single ADP statement cannot provably scope to both — and a mis-scoped ADP fails *silently*, the precise failure shape ADR-112 documented. Worse, a correctly-scoped ADP still restores auto-expose for every future relation: the next internal table created gets `anon`/`authenticated`/`service_role` grants under RLS, re-opening the attack surface the 2026-10-30 flip exists to close and cutting against #4027. Explicit grants make every relation's API surface a reviewable, asserted artifact (P4 via the lint/fuzz pair) rather than ambient platform state — and they survive an operator toggling Studio's default-privileges setting.

**Rejected alternatives:** `ALTER DEFAULT PRIVILEGES FOR ROLE <migration-role> IN SCHEMA public GRANT …` — silent-mis-scope risk on hosted prd, re-opens over-exposure, contradicts #4027, and fights the platform's own flip mechanism (Supabase manipulates `pg_default_acl` server-side at the flip; an ADP restore may conflict or be overwritten).

**Dissent:** If a future requirement ever legitimately wants auto-expose for *new* tables (none does today — P4 demands the opposite), ADP `FOR ROLE` scoping would need the live probe #6340 never ran. Nothing in the current corpus requires it.

---

## Item 2: Generated prd-catalog snapshot vs hand-audited narrowing during backfill

Ruled by CTO agent, 2026-10-26: Generated snapshot from the live prd catalog, replayed verbatim; zero prd behavior change; narrowing deferred to a follow-up paired with #4027 - effective privileges compose defaults + explicit grants + revokes and cannot be read from source text; the catalog is the only ground truth, and mid-backfill narrowing without per-relation consumer proof is the #4647 silent-failure class.

**Decision:** Generate the backfill from a read-only prd catalog extraction (`role_table_grants` + `column_privileges` + `role_usage_grants`), emitting table-level GRANTs where held and per-column GRANTs where table-level was deliberately revoked. No narrowing inside migration 174.

**Rationale:** Verified repo evidence shows effective state is not derivable from migration text: `006_restrict_tc_accepted_at_update.sql:7-11` (`REVOKE UPDATE` then `GRANT UPDATE (email)` on `users`), `079_workspace_repo_ownership_schema.sql:88-89` (`REVOKE SELECT` then column-list re-grant on `workspaces`), `049_runtime_mint_intent.sql:66-78` (`REVOKE ALL … FROM PUBLIC, anon, authenticated` then `GRANT INSERT`/`GRANT UPDATE(created_at)` to `service_role` and `GRANT SELECT, DELETE` to `supabase_auth_admin`). A table-level GRANT would silently subsume the 006/079 column splits (the `2026-03-20` learning) — hand-guessing that boundary across ~70 relations is exactly where a snapshot-error becomes a PII exposure. The hand-audit still runs: it produces the per-relation classification that seeds `table-grants.ts` and the narrowing list — but as analysis, not as DDL.

**Rejected alternatives:** Hand-write the grant DDL per relation (rots before review, cannot see effective state); narrow during backfill (violates P1 — any effective-state change on prd is behavior change; each narrowing needs a consumer-access proof that belongs in the follow-up issue with #4027, not in a 4-day remediation).

**Dissent:** The snapshot's correctness rests on the generator actually reading `column_privileges` — a generator that reads only `role_table_grants` and emits `GRANT … ON TABLE` would re-open `github_installation_id`/`tc_accepted_at`. The verify/174 column-privilege assertions and the fuzz gate's column checks are the containment; AC2 names the three shapes explicitly.

---

## Item 3: Bash lint at the PR-diff chokepoint vs a vitest module under test/migration-lint/

Ruled by CTO agent, 2026-10-26: Bash `lint-migration-api-grants.sh --from-pr-diff` wired into `tenant-integration.yml` beside the FK lint - the established migration PR-diff chokepoint is bash-shaped, fails fast pre-DB, and the authoritative tier is the live-catalog fuzz gate either way; a vitest module would sit on the wrong tier boundary for a per-PR tripwire.

**Decision:** `apps/web-platform/scripts/lint-migration-api-grants.sh` (+`.test.sh`), `--from-pr-diff`, added as a step in `tenant-integration.yml` adjacent to `lint-migration-fk-preconditions.sh` (verified at `.github/workflows/tenant-integration.yml:388`).

**Rationale:** The chokepoint already exists and is bash: `lint-migration-fk-preconditions.sh` implements the exact pattern to mirror — `--from-pr-diff` at :100, `git diff origin/main...HEAD --diff-filter=AM -- 'apps/web-platform/supabase/migrations/*.sql'` at :114, repo-root resolution guard at :51-66. Running at that step means the check fires early, needs no DB, and lives on the single CI path migration PRs flow through. The ADR-112 two-tier precedent applies cleanly: the authoritative tier is the rls-fuzz live-catalog gate; the lint is the subordinate fast tripwire. `test/migration-lint/definer-grants.ts` is not counter-precedent — it covers a different object class (definer EXECUTE grants) where source-form analysis was the *primary* mechanism; here the runtime gate exists, so the static tier only needs to trip, not to prove.

**Rejected alternatives:** A vitest module under `test/migration-lint/` — would run on a different schedule (test-job, post-install) instead of the pre-DB diff step, duplicates a tier that already has an authoritative runtime sibling, and contradicts ask 4 ("match how this repo already lints migrations").

**Dissent:** The plan's lexer mandate is the real cost: the noise-stripper (`test/migration-lint/definer-grants.ts:99-110` — comments, nested block comments, `'…'` literals, `$$…$$`/`$tag$` bodies) must be *reused or faithfully ported*, not approximated with `grep -v`. Cheapest correct path: have the bash script shell out to `bun`/node on the existing TS stripper rather than re-implementing a state machine in awk. Guard-contract mutation row 8 (commented/dollar-quoted `create table` must not fire) is the test that catches a lazy port. If the implementer cannot get a faithful stripper inside the bash shape, the vitest tier becomes acceptable — but that evidence does not exist at ruling time.

---

## Item 4: Relation scope of backfill + guards — tables only vs r,v,m,S

Ruled by CTO agent, 2026-10-26: All four relkinds (tables, views, materialized views, sequences) in both the backfill snapshot and the guards - `138_agent_engine_runs.sql:66` holds a real `GENERATED ALWAYS AS IDENTITY` column whose owned sequence needs `USAGE` for Data-API inserts post-flip, and the guard's sequence arm must exist for every *future* serial/identity table regardless of today's count.

**Decision:** Scope = relkinds `r`, `v`, `m`, `S`. Snapshot emits `GRANT USAGE[,SELECT] ON SEQUENCE` per `role_usage_grants`; the lint requires a sequence-grant presence or sentinel on serial/identity tables; the fuzz registry enumerates `S` alongside `r`,`v`,`m`.

**Rationale:** Correcting the plan's evidence first: the claim "serial/identity columns exist in ≥11 migrations (029, 033, 046, 053, 061, 064, 084, 093, 121, 126…)" (plan :90) is **wrong** — verified by grep: exactly ONE migration carries an identity column (`138_agent_engine_runs.sql:66`, `id bigint GENERATED ALWAYS AS IDENTITY`); zero `serial`/`bigserial` columns, zero `CREATE SEQUENCE`, zero `nextval` in the corpus; the cited files match only on comment words ("serializes", "identity"). The decision survives on corrected grounds: (a) that one identity column alone makes sequence `USAGE` non-optional — post-change sequences keep only `update`, so Data-API inserts into `agent_engine_runs` fail without it; (b) the guards are forward-looking — omitting `S` leaves a permanent hole where any future `GENERATED … AS IDENTITY` table passes the lint with a table grant yet silently breaks inserts (the exact false-green class this change exists to kill); (c) `role_usage_grants` extraction is free in the same catalog pass; (d) views/matviews are independently required — 4 migrations contain view DDL and PostgREST exposes views through the same grant mechanism.

**Rejected alternatives:** Tables-only — leaves the one existing identity column broken on fresh post-flip stacks and leaves every future serial/identity table unguarded.

**Dissent:** None on scope. The plan should fix the "≥11 migrations" line at :90 (and any derived sizing) to "1 identity column (138) plus the forward-looking guard arm" — a documentation correction, not a design change.

---

## Item 5: `174_api_data_grants_snapshot.down.sql` — REVOKE-down vs documented no-op

Ruled by CTO agent, 2026-10-26: Documented no-op - REVOKE cannot distinguish grant provenance: on prd the privileges are already effective pre-174, so a revoke strips the ACL entry regardless of source and reduces access *below* the pre-174 state — strictly worse than the forward state.

**Decision:** Ship `174_api_data_grants_snapshot.down.sql` as a comment-only documented no-op explaining why REVOKE-down is unsafe on prd, per the forward-only convention (`docs/migration-rollback.md`).

**Rationale:** Privileges are additive ACL entries with no provenance tag. Pre-174 on prd, every targeted privilege is already effective (via the default-era grants); the up-migration's GRANTs are idempotent re-declarations. A REVOKE-down therefore cannot "un-add" them — it removes the underlying privilege and leaves prd *less* privileged than before the migration ran: a guaranteed regression on the `users`/`workspaces` column-split postures and every default-era table grant. The repo's own precedent agrees: `079_workspace_repo_ownership_schema.down.sql:70-72` documents "Restore the Supabase default table-level SELECT grant" — i.e., a correct down restores the *prior* grant posture, and for 174 prior == post. On a fresh post-flip replay, a REVOKE-down would instead reintroduce the precise broken state the backfill fixes. The convention (112 `.down.sql` siblings, manual aids under a forward-only strategy) requires the file to exist and be honest; a no-op with the reasoning written down is both.

**Rejected alternatives:** REVOKE-down mirroring the up file (provably regressive on prd); no `.down.sql` at all (breaks the sibling convention the corpus follows — 112 down files).

**Dissent:** None. If a genuine rollback of 174 is ever needed it is a forward migration revoking a named, audited set — the manual procedure in `docs/migration-rollback.md` — not a `.down.sql` replay.

---

## Item 6: Local-stack parity — `auto_expose_new_tables = false` vs post-start normalize

Ruled by CTO agent, 2026-10-26: Post-start normalize step in `supabase-local.sh` is the PRIMARY mechanism under pinned CLI 2.84.2; the config key is deferred pending a CLI bump - verified release/PR metadata proves the key does not exist on 2.84.2: v2.84.2 was released 2026-03-25 (`gh api repos/supabase/cli/releases/tags/v2.84.2`), and `auto_expose_new_tables` was added by supabase/cli#5239 merged 2026-05-26 (merge commit bbc5523 — v2.100.0 is `behind` it, v2.110.0 `ahead`), so the "primary" the plan assumed cannot fire.

**Decision:** Make the normalize step primary now: after `supabase-local.sh start`, run Supabase's documented revoke-default-privileges SQL for `public` against the api roles, then assert `pg_default_acl` carries no api-role table privileges (the planned step-9 assertion). Do **not** write `auto_expose_new_tables` into `config.toml` while the pinned CLI predates the key. Record in ADR-303: a CLI bump to ≥v2.116.0 swaps the normalize step for `auto_expose_new_tables = false`.

**Rationale:** The flag's absence on 2.84.2 makes it either dead config (silently ignored → the stack keeps bootstrap auto-expose grants and the fuzz gate measures platform defaults, not migration grants — the circular-proof failure P6 exists to prevent) or a config-parse hazard breaking `supabase start`; both are worse than an explicit normalize. Current-flag semantics strengthen this: supabase/cli#6337 (merged 2026-08-26, first in v2.116.0) reverted the unset default — unset ≡ auto-expose to match the platform, only explicit `false` revokes — so on a future bump the key must be set explicitly anyway, and the normalize keeps working regardless of which flip-era the CLI is from. The pin is deliberate, not incidental: `rls-authz-fuzz.yml:50-51` ties CLI/GoTrue to prod's version for the ADR-111 parity contract, so bumping 2.84.2→2.116+ under a 4-day deadline is an unscoped toolchain change — rejected. Coverage is total: every stack start funnels through the wrapper (`package.json:24` `db:start` → `./scripts/supabase-local.sh start`; the fuzz job itself runs `./scripts/supabase-local.sh start` at `rls-authz-fuzz.yml:60-62`), so one normalize step reaches local dev and CI. Note for implementation: the revoke must target the role(s) that own the defacl entries the bootstrap installed (`postgres` on the local stack); the `pg_default_acl` assertion is the catch-all if the owner set is broader.

**Rejected alternatives:** `auto_expose_new_tables = false` as primary — cannot exist on the pinned CLI (verified); bumping the pinned CLI to gain the flag — breaks the prod-version-parity intent of the pin and couples an unscoped toolchain regression to a deadline remediation.

**Dissent:** If the implementer verifies that 2.84.2 *ignores* unknown config keys (unverified either way at ruling time), writing the flag now as forward-compat is permissible but not required — the normalize + `pg_default_acl` assertion is still the mechanism that must exist and be asserted. The ruling that changes is only "may also write the key", never "key instead of normalize". What would flip this ruling entirely: a decision to repin the CLI ≥v2.116.0 on parity grounds (prod GoTrue bump) — then config-key-primary becomes correct and the normalize step is removed in the same change.
