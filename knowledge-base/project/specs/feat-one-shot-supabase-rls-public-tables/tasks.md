# Tasks — security: table-scoped RLS lockdown on the 14 dark-Inngest tables in soleur-dev

Plan: `knowledge-base/project/plans/2026-07-15-security-soleur-dev-inngest-rls-lockdown-plan.md` (v2, post 7-agent review)
Lane: `cross-domain` · Threshold: `single-user incident` (write-integrity) · `requires_cpo_signoff: true`

> ⚠️ **Read these three before touching anything:**
> 1. **This PR writes to Inngest prd** (`pigsfuxruiopinouvjwy`) — `apply-inngest-rls.yml` triggers on `paths: apps/web-platform/infra/inngest-rls/**`, which every file below matches. Task 2.1 narrows that filter; task 5.1 verifies it.
> 2. **`0001` and `0002` have INVERTED required shapes.** `inngest-rls.test.sh` *requires* `ALTER DEFAULT PRIVILEGES` for `0001`; `0002` must **never** contain it. Do not run both files through one assertion set — see 1.4.
> 3. **Never point `0001` at soleur-dev.** It is schema-wide and would revoke anon/authenticated across the app's 52 dev tables.

---

## Phase 0 — Preconditions (read-only; all against the live catalog, never migration grep)

- [ ] 0.1 Re-run the RLS-disabled catalog query on `mlwiodleouzwniehynfz`. **If ≠ the 14 named in the plan → STOP and re-scope** (the allowlist is static).
- [ ] 0.2 Re-run the GDPR row-count evidence query. If any payload table is non-zero → **escalate for a CLO determination IN PARALLEL and proceed with the lockdown anyway** (it is non-destructive and reduces exposure; halting burns the Art. 33 clock).
- [ ] 0.3 **Ownership check (load-bearing):** `pg_get_userbyid(relowner)` = `postgres` for all 14. If not, non-forced RLS locks Inngest out — STOP.
- [ ] 0.4 Dev app-table RLS census — confirm all 52 app tables are RLS-on.
- [ ] 0.5 **Record baselines** (T5 asserts against these, not literals): anon/authenticated grants over all non-allowlisted public tables; `pg_default_acl` contents.
- [ ] 0.6 **prd-Inngest precondition:** on `pigsfuxruiopinouvjwy`, `to_regclass` of every chosen negative-guard table is NULL. If not, pick different names.
- [ ] 0.7 **Goose re-run reachability:** confirm the pinned bootstrap image (`cloud-init-inngest.yml`, `soleur-inngest-bootstrap:v1.1.19`) means goose runs only on a deliberate in-PR pin bump. Gates DC-2.
- [ ] 0.8 DSN check → expect `postgres.mlwiodleouzwniehynfz`. **If already flipped: still apply the lockdown**, then go to Phase 5's trigger.

## Phase 1 — RED: artifacts + shape guards

- [ ] 1.1 Create `apps/web-platform/infra/inngest-rls/0002_dev_inngest_tables_lockdown.sql`: positive sentinel; **14-name allowlist-driven** loop (never `pg_tables`/`pg_class` schema-wide); `ENABLE ROW LEVEL SECURITY` (non-forced) + `REVOKE ALL FROM anon, authenticated`; zero policies; sequences owned by the 14 via `pg_get_serial_sequence`/`pg_depend` (**not** a hardcoded `goose_db_version_id_seq`); `lock_timeout='3s'`/`statement_timeout='30s'`; break-glass comment.
- [ ] 1.2 **NO `ALTER DEFAULT PRIVILEGES` in `0002`** — the single most important divergence from `0001` (it would break every future dev app migration).
- [ ] 1.3 Non-allowlisted RLS-disabled tables: **report, never abort** (an aborting assertion protects nothing and disables the self-heal).
- [ ] 1.4 Edit `0001_enable_rls_lockdown.sql`: add the in-DB negative guard using **app-distinctive** names (`kb_files`, `workspace_invitations`, `byok_delegation_acceptances`) — **never `users`/`conversations`** (Inngest ships generic nouns and could create `public.users`, which would permanently break the prd lockdown). Place it **before** the revoke loop, with an inline comment naming the invariant and its rename-degradation mode.
- [ ] 1.5 **Restructure** `inngest-rls.test.sh` into per-artifact profiles (path + per-file required/forbidden sets). Baseline `passed=16`; state the exact new expected count. All assertions run against the **comment-stripped** `SQL_CODE`.
- [ ] 1.6 `0002` positive guards: all 14 literal names present; revoke source is the allowlist array; break-glass present. Forbidden: `ALTER DEFAULT PRIVILEGES`, `FORCE ROW LEVEL SECURITY`, `CREATE POLICY`, postgres/service_role revoke, schema-wide catalog loop.
- [ ] 1.7 `0001` guard: assert byte-offset of the guard **precedes** the first `REVOKE`.

## Phase 2 — GREEN: apply path

- [ ] 2.1 **Narrow `apply-inngest-rls.yml`'s `paths:`** to `0001_enable_rls_lockdown.sql` + its own yml (closes finding 0). Add it to Files to Edit.
- [ ] 2.2 Add the project-name identity preflight to `apply-inngest-rls.yml`: `GET $API/v1/projects/$PROJECT_REF` → assert `.name == 'soleur-inngest-prd'`, fail-closed (precedent `cutover-inngest.yml:743-749`). This is the **primary** guard.
- [ ] 2.3 Create `.github/workflows/apply-inngest-rls-dev.yml` (~85 lines, **not** a 269-line verbatim mirror): `PROJECT_REF: mlwiodleouzwniehynfz` literal; applies only `0002`; identity preflight (`.name == 'soleur-dev'`); paths = `0002_*` + own yml + `cloud-init-inngest.yml`.
- [ ] 2.4 **Gate must check grants, not just RLS:** `relrowsecurity` + `pg_get_userbyid(relowner)='postgres'` + `has_table_privilege` × {anon, authenticated} × {SELECT, INSERT, UPDATE, DELETE, **TRUNCATE**}, scoped `AND c.relname = ANY(<14>)`. RLS never gates TRUNCATE, and PostgREST has no TRUNCATE verb — the catalog gate is the only place it can be asserted. A schema-wide gate can **never** reach `violations=0` on dev.
- [ ] 2.5 **Distinct** `ISSUE_TITLE`, label, and `concurrency: group` from the prd workflow (a verbatim copy would let a green prd run auto-close dev's failure issue).
- [ ] 2.6 Cut: `pg_default_acl` gate, 3-attempt 55P03 retry, advisor corroboration. Keep verbatim: anti-exfil helpers, pinned `API`, owner-liveness, `SET LOCAL ROLE anon` denial.
- [ ] 2.7 Hourly cron **only if** 0.7 shows goose can run without a pin bump (see DC-2).
- [ ] 2.8 Create `apply-inngest-rls-dev-workflow.test.sh` (shape guard; precedent `restart-inngest-workflow-guard.test.sh`) and add both workflows' paths to `infra-validation.yml`.
- [ ] 2.9 SHA-pin every `uses:`.

## Phase 3 — Verify

- [ ] 3.1 Create `apps/web-platform/infra/inngest-rls/anon-probe.sh` (T2/T3/T4.4) invoked by the dev workflow — Phase 3 must have an executor, not hand-run probes.
- [ ] 3.2 **T2:** anon `GET /rest/v1/apps` → expect **401/403 + `42501`**, NOT `200 []` (`200 []` is the *broken* state — RLS on but grant still present). Assert only on `apps` + `goose_db_version`; the other 12 are empty and prove nothing via body.
- [ ] 3.3 **T3 (204 trap):** anon DELETE may return 204 — assert by **service-role read-back of unchanged state**, against the Phase-0 baseline (not the literal 6).
- [ ] 3.4 **T4:** owner write intact via `BEGIN; SET LOCAL ROLE postgres; INSERT …; ROLLBACK;`; owner = `postgres`; `/hooks/inngest-liveness` healthy + `durability_state == durable` (**no SSH**); anon negative control → `42501`. Primary evidence is the prd precedent, not the idle dev host.
- [ ] 3.5 **T5:** grants over all 52 non-allowlisted tables unchanged vs. the 0.5 baseline (use `has_table_privilege`/`relacl`, not `information_schema.role_table_grants`); `pg_default_acl` unchanged; drive the dev app via `agent-browser`.
- [ ] 3.6 **T6/T7:** guard-ordering asserted statically; `ifsccnjhymdmidffkzhl` still 0/52. The at-risk project is `pigsfuxruiopinouvjwy` → task 5.1.

## Phase 4 — Docs, ADR, prevention

- [ ] 4.1 Amend `ADR-030-inngest-as-durable-trigger-layer.md`: I8 scope → every Inngest-hosting project; co-tenanted ⇒ table-scoped only; record the sentinel falsification; update `Enforced by` (`:121`) with `0002` + the dev workflow; changelog. Cite ADRs **by filename** (ADR-030 is an ambiguous ID).
- [ ] 4.2 Amend `ADR-100-…`: name soleur-dev as the dark backend (currently only in a Terraform comment); note the transient co-tenancy + Phase-5 cleanup. **Do not** put the web-platform `ensure_rls` decision in ADR-030 — wrong jurisdiction.
- [ ] 4.3 Fix `knowledge-base/operations/expenses.md:22`.
- [ ] 4.4 Escalate #3366 → `priority/p1-high`, remove `deferred-scope-out`, comment with this evidence. **No duplicate.** (See DC-1: CTO argues build it now.)
- [ ] 4.5 **File the cause-level prevention issue** (CPO condition 2): nothing detects *a non-`soleur` Doppler project's DSN resolving to the dev ref*; `preflight` Check 4 structurally cannot see it.
- [ ] 4.6 File the Phase-5 issue (below) + follow-ups: stale `SUPABASE_PAT` (401 in dev **and** prd); the 2 unpinned SECURITY DEFINER functions; anti-exfil helper triplication; §Drift adoption (own ADR+PR, `pg_temp` pinned in the same migration per DC-4); `ADR-030` ID collision; **`iac-plan-write-guard.sh` ack-bypass defect** (reproduced: 48 KB plan + valid ack → denied).
- [ ] 4.7 Supersede the stale premise in `session-state.md`.

## Phase 5 — Post-cutover orphan drop (tracking issue only — not this PR)

- [ ] 5.0 File with: **machine-checkable trigger** (`INNGEST_CUTOVER_FLIP == done` AND DSN ≠ `postgres.mlwiodleouzwniehynfz` AND `now − flip_ts > <soak>`); **CI annunciation from `op=arm`'s success path**; **named owner + 60-day calendar backstop**; **atomic retirement** of `0002` + the dev workflow with the drop.
  Rationale is *"the dark host is live against soleur-dev until `op=arm` writes the prod URI"* — **not** "preserve the rollback target" (falsified: G4 `:756` overwrites the DSN; `op=rollback` `:1061` never restores it).

## Phase 6 — Merge gates

- [ ] 5.1 **AC-P1 (highest priority):** after merge, `apply-inngest-rls.yml`'s auto-triggered run against **`pigsfuxruiopinouvjwy`** is green (`violations=0`, `pg_default_acl` clean, owner-liveness, anon-denied). *This PR mutates Inngest prd.*
- [ ] 5.2 AC-P2: dev workflow merge-apply green; `violations=0` over the allowlisted 14.
- [ ] 5.3 PR body: **`Ref #3366`** + the Phase-5 issue — **never `Closes`** (ops-remediation: the fix is verified post-merge by the apply workflow).
- [ ] 5.4 Confirm CPO sign-off on `decision-challenges.md` (DC-1…DC-4) before merge.
