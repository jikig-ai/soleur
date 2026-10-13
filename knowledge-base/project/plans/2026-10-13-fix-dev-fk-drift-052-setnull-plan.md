---
title: "fix: dev schema drift — audit_github_token_use.founder_id RESTRICT → SET NULL (mig 052, #10095)"
date: 2026-10-13
slug: fix-dev-fk-drift-052-setnull
branch: feat-one-shot-10095-dev-fk-drift-setnull
issue: 10095
closes: 10095
type: fix
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: dev schema drift — audit_github_token_use.founder_id RESTRICT → SET NULL (mig 052, #10095)

## Overview

Issue #10095 tracks a live dev-Supabase schema drift found while probing #9994
(deleteUser 500s on dev): `audit_github_token_use_founder_id_fkey` is
`confdeltype='r'` (ON DELETE RESTRICT) on dev, but
`apps/web-platform/supabase/migrations/052_multi_source_dedup.sql:68` declares
`ON DELETE SET NULL` and no later migration flips it.

Plan-time investigation upgraded the issue's hypothesis ("out-of-band
alteration, or dev was built from a pre-release 052") into an established causal
chain: this is the **A1 "edited after apply" arm** of the dev-ledger-parity
taxonomy — dev applied the pre-edit RESTRICT blob of 052 at `2026-05-19
21:13:16+00`; PR #4066's branch then fixed RESTRICT → SET NULL at 21:26:47Z
(commit `acb4d37493`, pre-squash) and squash-merged to main at 21:41:09Z
(`5bc14c7f95`). The ledger row carries `content_sha = NULL` (pre-054 row by
design), which is exactly the probe blind spot: `dev-migration-drift-probe`
skips NULL-sha rows (`.github/actions/dev-migration-drift-probe/action.yml`
"Old rows (pre-migration 054) have NULL content_sha — skip the content-drift
check"), so this drift was invisible to every automated surface.

Repair = the learning's §Content-drift **class C (targeted SQL)** procedure on
dev only: re-create the FK with SET NULL, replay the drifted function comment,
and compare-and-set the `_schema_migrations.content_sha` ledger row to main's
052 blob sha. Do NOT change main; never touch prd
(`hr-dev-prd-distinct-supabase-projects`).

## Research Insights

### Premise Validation (Phase 0.6) — all verified live at plan time

- `#10095` — OPEN, labels `priority/p2-medium`, `type/bug`, `domain/engineering`,
  `meta/machinery`, `ci/integration-suites`. Filed from #9994's planning
  evidence (2026-10-12 census).
- **Dev catalog (2026-10-13, read-only psql via `doppler run -p soleur -c dev`):**
  - `pg_constraint`: `audit_github_token_use_founder_id_fkey | r |
    audit_github_token_use | users` — still RESTRICT.
  - `pg_get_constraintdef`: `FOREIGN KEY (founder_id) REFERENCES users(id) ON
    DELETE RESTRICT`.
  - Ledger: `052_multi_source_dedup.sql | (content_sha NULL) | applied_at
    2026-05-19 21:13:16+00`.
  - `public.audit_github_token_use`: **0 rows** (0 with non-NULL founder_id) —
    RESTRICT has not bitten yet; the mu1 suite (#9995) would mint rows.
  - `pg_depend`: **0 non-internal dependents** on the constraint (4 rows with
    `deptype='i'` — the internal RI triggers the constraint itself owns on
    `audit_github_token_use` and `public.users`; `DROP CONSTRAINT` cascades
    them automatically). Safe to drop and re-create.
  - `founder_id` is **nullable** (`attnotnull=f`) — SET NULL-compatible; no
    column-nullability drift.
  - Sibling FK `audit_github_token_use_workspace_id_fkey` is `r` — that matches
    main's 059 (`ON DELETE RESTRICT` by design); untouched.
  - WORM trigger `audit_github_token_use_no_mutate`: `tgenabled='O'` (enabled),
    `prosrc` carries `app.worm_bypass` (087's body applied) and does **not**
    mention `founder_id` — identical to main's latest (see Findings, nuance).
  - `anonymise_audit_github_token_use` exists; `proacl =
    {postgres=X/postgres,service_role=X/postgres}` — matches main's grant
    intent.
  - **Dev comment drift found:** `obj_description` on
    `anonymise_audit_github_token_use` carries the RESTRICT-era text ("Art. 17
    cascade … the FK is ON DELETE RESTRICT and the auth-delete would abort
    without this"); main's 052-final text reads "Explicit Art. 17 anonymise
    path…". Only 052 ever comments this function (grep-verified), so main's
    latest definition is the 052-final text.
- **Git side (verified):**
  - `git rev-parse origin/main:apps/web-platform/supabase/migrations/052_multi_source_dedup.sql`
    = `048013204a426cf4a024d083a57b22367b436b7a` (main's blob).
  - `git log --follow` on the file: `5bc14c7f95` (squash merge of PR #4066) +
    `acb4d37493` "fix(pr-h): change audit_github_token_use FK RESTRICT → SET
    NULL". `git merge-base --is-ancestor acb4d37493 origin/main` = **false** —
    it is a pre-squash PR-branch commit, so the RESTRICT body **never existed
    on main** (the squashed `5bc14c7f95` blob already has SET NULL).
  - Applied-blob identification: `acb4d37493~1`'s blob for the file =
    `a14380522d48c1f56b03dcf3e940dd7ae82d082b` (RESTRICT) — the body dev
    applied at 21:13Z, 13 min before the fix commit.
  - Blob-to-blob diff (applied → main) touches exactly: the `founder_id` FK
    clause, the `anonymise_audit_github_token_use` comment text, the
    `audit_github_token_use_no_mutate` comment text (stale on BOTH sides
    post-087 — no migration re-commented), and an added `REVOKE ALL ON
    FUNCTION … no_mutate()` (already subsumed live by 087's wider
    `REVOKE … FROM PUBLIC, anon, authenticated, service_role`; dev proacl
    already matches). No objects exist only in the applied blob.
  - `git log --all -S audit_github_token_use_founder_id_fkey --
    apps/web-platform/supabase/migrations/` → **0 hits**: the constraint name
    is Postgres-autogenerated from the column-level `REFERENCES` clause; no
    migration names it, so no later migration touches it.
  - Later migrations mentioning `audit_github_token_use`: 059 (adds
    `workspace_id` + policy swap — applied on dev), 064/068 (pass-through
    references), 087 (redefines both functions — applied on dev, `app.worm_bypass`
    present). None touch `founder_id` or the constraint.
- **content_sha convention:** `apps/web-platform/scripts/run-migrations.sh:403`
  computes `git hash-object` (git blob SHA-1, `sha1sum` fallback). The drift
  probe compares against `git ls-tree` blob ids — same hash space as
  `git rev-parse origin/main:<path>`. A NULL-sha row is **skipped** by the
  probe (blind spot, confirmed at action.yml:197-199).
- `dev-ledger-reconcile.yml` is **not applicable**: it discards rows owned by
  *unmerged* PRs and refuses merged rows (`ledger-discard: refused
  reason=merged`); 052 is a merged row with content drift → manual class C per
  the learning is the only path. (The issue's "or record the reconcile path the
  dev-ledger-parity machinery prescribes" — recorded: machinery explicitly
  excludes this class.)
- Institutional learnings applied:
  `learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
  §Content drift (the repair procedure; takeaways 4/5 — pgrst reload scope,
  pooler :5432 for multi-statement DDL);
  `learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md`;
  `learnings/2026-05-15-one-shot-plan-subagent-cwd-divergence.md` (absolute
  paths throughout).

### Property List (Phase 0.6b)

1. Dev's `audit_github_token_use_founder_id_fkey` must match main's declared
   shape (`ON DELETE SET NULL`, `confdeltype='n'`).
2. The repair must follow the §Content-drift class C procedure: read-only
   triage first, one transaction per repair unit, ledger CAS, backup + mutex +
   fail-closed exits.
3. The ledger row must end with `content_sha` equal to main's 052 blob (or a
   recorded reason it cannot).
4. `tenant-isolation-teardown.ts`'s `set-null` fatality label for
   `anonymise_audit_github_token_use` must become true on dev again.
5. Main must not change; prd must not be touched.
6. `#9993` (standing tracker) stays open.

### Cut List (Phase 0.6b)

- *A new migration file on main* — main's schema is already correct (issue's
  own instruction); a new file would change main and renumber downstream.
- *Re-running 052 wholesale (class B)* — the file is not idempotent
  (`CREATE POLICY` without `IF NOT EXISTS`, bare `CREATE TRIGGER`,
  `CREATE INDEX IF NOT EXISTS` only partially so); re-running collides. Class C
  targeted SQL is the prescribed class.
- *Re-running the added `REVOKE` on the WORM function* — 087's wider revoke
  already produced the main-intended live ACL (`{postgres=X/postgres}`); the
  statement is a proven no-op on dev.
- *Adding a `founder_id→NULL` cascade carve-out to
  `audit_github_token_use_no_mutate` on dev* — would create NEW dev-vs-main
  drift; the carve-out gap is a main-side finding (follow-up issue, Phase 4).
- *`NOTIFY pgrst, 'reload schema'`* — constraint/comment changes alter no
  function signature or grant; PostgREST advertises nothing that changed
  (learning takeaway 4 scoped to RPC signature/grant changes).

### Findings

- **Root cause (established, not inferred):** dev applied 052's RESTRICT blob
  `a14380522d` at 21:13:16Z; the SET NULL edit landed on the PR branch at
  21:26:47Z (`acb4d37493`) and squash-merged at 21:41:09Z. A1 arm; NULL
  `content_sha` kept the probe blind. Pre-054 rows are the whole class of rows
  this blind spot covers.
- **The 'set-null' fatality label is additionally bounded by a main-side
  latent defect** (verified in source; same mechanism #9994 confirmed live for
  `dsar_export_audit_pii`): Postgres RI actions fire the referencing table's
  user triggers, and `audit_github_token_use_no_mutate` (087 body) has **no**
  `founder_id→NULL` carve-out — unlike `audit_byok_use` (066) and
  `dsar_export_audit_pii` (160). So on BOTH dev-today and a main-conformant
  dev, a deleteUser that reaches the cascade with rows still referencing the
  user fails (`23503` under RESTRICT; `P0001` WORM under SET NULL). The
  anonymise RPC is the load-bearing step and exists+is granted on both — the
  repair restores parity and makes the `set-null` label exactly as true on dev
  as on main, but does NOT by itself make an RPC-failure teardown path
  survivable. The carve-out gap is a main-side follow-up (Phase 4 files it);
  fixing it here would create new drift.
- **Grants/comments:** live ACLs already match main's latest; the only other
  live-object drift is the `anonymise_audit_github_token_use` function comment
  (replayed in the repair unit).

### Gate Decisions

- Phase 1.4 network-outage, 1.8 skill-description budget, 2.7 GDPR (synthetic
  audit rows only; `hr-gdpr-gate` — the table holds audit metadata, but the
  change is a constraint clause on dev, no new data surface), 2.8 IaC, 2.9
  Observability (no code-class file changed; the deliverable IS an
  observability-adjacent repair but no code gate fires), 2.10 ADR/C4, 2.11
  Encryption, 2.12 Guard Contract (no guard authored), 2.13 Founder check
  (headless) — all n/a or skipped per their predicates.
- `hr-dev-prd-distinct-supabase-projects`: dev-only write; no prd surface in
  scope. `hr-menu-option-ack-not-prod-write-auth`: n/a (dev write, and dev is
  explicitly outside the prd-ack class per the learning's own note).

## Root Cause

Timeline (all timestamps UTC, verified):

| t | Event | Evidence |
|---|-------|----------|
| 2026-05-19 ~21:0x | PR #4066 branch pushes 052 with `ON DELETE RESTRICT` (blob `a14380522d`) | `git rev-parse acb4d37493~1:<file>` |
| 21:13:16 | CI/apply path writes 052 to dev ledger; dev gets RESTRICT constraint | `_schema_migrations.applied_at` |
| 21:26:47 | `acb4d37493` "fix(pr-h): change audit_github_token_use FK RESTRICT → SET NULL" | `git show acb4d37493` |
| 21:41:09 | PR #4066 squash-merges as `5bc14c7f95`; main's blob `048013204a` is SET NULL from the start | `gh pr view 4066` + `git show` |

The runner never re-applies a ledgered filename; the pre-054 ledger row has
`content_sha NULL`, which every content-drift probe skips — so the drift
persisted invisibly for ~5 months until the #9994 census found it.

## Implementation Phases

All psql reads run via `doppler run -p soleur -c dev -- bash -c '…'` against
`"${DATABASE_URL_POOLER:-$DATABASE_URL}"`; the write step rewrites the pooler
URL to session mode (`${DATABASE_URL_POOLER/:6543\//:5432/}` — same idiom as
`apps/web-platform/scripts/email-route-status.sh:62`). Quoting note from the
sibling pipeline: `$VAR` must expand inside the *inner* `bash -c` string.

### Phase 0 — Work-time re-verification + honest-exit gates (read-only)

```bash
doppler run -p soleur -c dev -- bash -c 'psql "${DATABASE_URL_POOLER:-$DATABASE_URL}" \
  --no-psqlrc -tAq -c "select conname, confdeltype, pg_get_constraintdef(oid) \
    from pg_constraint where conname = '"'"'audit_github_token_use_founder_id_fkey'"'"';
  select filename, content_sha from public._schema_migrations \
    where filename = '"'"'052_multi_source_dedup.sql'"'"';
  select count(*) from public.audit_github_token_use;
  select count(*) from pg_depend d \
    where d.refobjid = (select oid from pg_constraint \
      where conname = '"'"'audit_github_token_use_founder_id_fkey'"'"') \
    and d.deptype <> '"'"'i'"'"'"'
```

Gates (checked in order; each failure is a STOP, not a proceed):

- **G1 — `confdeltype` already `n`:** drift already repaired out-of-band → skip
  Phases 1-2 entirely; run the Phase-3 read-only parity checks, comment the
  finding + whoever-fixed evidence on #10095, close. Do NOT write the ledger
  sha (the repair provenance is unknown; an unverified sha write asserts a
  parity that was not established).
- **G2 — `confdeltype` neither `r` nor `n`** (e.g. `a`/`c`/`d`), or the
  constraint is absent: the analyzed drift is stale → stop, post the census on
  #10095, no writes.
- **G3 — ledger row for `052_multi_source_dedup.sql` missing:** different
  drift class (schema-vs-ledger, `learnings/2026-05-22-*`) → stop, post on
  #10095, no writes.
- **G4 — `content_sha` non-NULL and ≠ `a14380522d48c1f56b03dcf3e940dd7ae82d082b`
  and ≠ `048013204a426cf4a024d083a57b22367b436b7a`:** a third applied body →
  stop and re-triage against the live catalog before any write.
- **G5 — non-internal `pg_depend` dependents ≠ 0** (`deptype <> 'i'`) → reassess
  the drop (order/cascade); stop if any dependent is unexpected. The 4
  `deptype='i'` RI triggers the constraint owns are expected and auto-cascade.

(0 rows expected in the table; a nonzero count does NOT gate — SET NULL works
with data — but record the count in the repair evidence.)

### Phase 1 — Mutex + backups (single `doppler run` invocation)

The mutex's local caveat (`scripts/dev-suite-mutex.sh` header):
`doppler run -- … acquire` and a separate `… release` get different caller pids
and thus different `DEV_SUITE_MUTEX_STATE_DIR`s — wrap acquire/release in ONE
invocation (or set the var explicitly). We wrap:

```bash
BK=/tmp/10095-dev-fk-drift-$(date -u +%Y%m%dT%H%M%SZ) && mkdir -p "$BK"
doppler run -p soleur -c dev -- bash -c '
  set -euo pipefail
  DEV_SUITE_MUTEX_IDENTITY="local-10095-reconcile" \
    bash scripts/dev-suite-mutex.sh acquire        # banner: DEV_SUITE_MUTEX_ACQUIRED|WAITING|CONTENDED_PROCEEDING
  trap "bash scripts/dev-suite-mutex.sh release" EXIT
  db_url="${DATABASE_URL_POOLER/:6543\//:5432/}"
  psql "$db_url" --no-psqlrc -v ON_ERROR_STOP=1 \
    -c "\copy (SELECT filename, content_sha, applied_at FROM public._schema_migrations ORDER BY filename) TO '"'"'$BK'"'"'/ledger.csv' csv header"
  pg_dump "$db_url" --schema-only -n public -f "$BK/dev-public-schema.sql"
  psql "$db_url" --no-psqlrc -tAq \
    -c "select conname, confdeltype, pg_get_constraintdef(oid) from pg_constraint where conrelid = '"'"'public.audit_github_token_use'"'"'::regclass" \
    > "$BK/constraints-pre.txt"
  …repair unit + post-verify from Phase 2/3…
'
```

`acquire`/`release` are fail-open by design (banners, not exit codes); if the
banner reads `CONTENDED_PROCEEDING` or `HOLDER_LOST`, note it in the evidence —
the procedure accepts fail-open but the close comment must record it. Backups
are LOCAL files (`$BK`) — never a `public` table (no RLS; exposed through
PostgREST) per the learning.

### Phase 2 — Repair unit (class C targeted SQL, one transaction)

Scratch file `$BK/repair-052.sql` (never committed; lives only in /tmp):

```sql
-- Lock risk: the re-ADD briefly takes SHARE ROW EXCLUSIVE on hot table
-- public.users to create/drop its RI triggers; lock_timeout bounds the wait
-- and fails the unit rather than queue behind other writers.
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '120s';

-- Object repair: dev's RESTRICT FK → main's SET NULL shape.
ALTER TABLE public.audit_github_token_use
  DROP CONSTRAINT audit_github_token_use_founder_id_fkey;

ALTER TABLE public.audit_github_token_use
  ADD CONSTRAINT audit_github_token_use_founder_id_fkey
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Comment parity: dev carries the RESTRICT-era comment text; replay main's.
COMMENT ON FUNCTION public.anonymise_audit_github_token_use(uuid) IS
  'PR-H (#3244) — Explicit Art. 17 anonymise path for audit_github_token_use. '
  'The FK has ON DELETE SET NULL so auth.admin.deleteUser cascades '
  'naturally; this RPC is the explicit path for account-suspend flows '
  'that scrub founder linkage WITHOUT deleting auth.users. Called by '
  'server/account-delete.ts for symmetry with 043/044/048 anonymise '
  'RPCs. Idempotent: re-running on already-anonymised rows is a no-op '
  '(UPDATE ... WHERE founder_id = p_founder_id matches zero rows). '
  'Bypasses the audit_github_token_use_no_mutate WORM trigger via '
  'SET LOCAL session_replication_role=replica (mig 037 + 044 pattern).';

-- Ledger compare-and-set: assert exactly one row transitions NULL → main blob.
DO $cas$
DECLARE n integer;
BEGIN
  UPDATE public._schema_migrations
     SET content_sha = '048013204a426cf4a024d083a57b22367b436b7a'
   WHERE filename = '052_multi_source_dedup.sql'
     AND content_sha IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'ledger CAS on 052_multi_source_dedup.sql matched % rows (expected 1)', n;
  END IF;
END
$cas$;
```

Apply (inside the same wrapped doppler invocation, still holding the mutex):

```bash
psql "$db_url" --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -f "$BK/repair-052.sql"
```

- Session-mode URL (`:5432`) is required — transaction-mode `:6543` rejects
  multi-statement DDL with 42601 (learning takeaway 5).
- `ADD CONSTRAINT` validates instantly (table has 0 rows; even with rows the
  validation is a normal FK scan — acceptable on dev).
- No `NOTIFY pgrst` — no signature/grant changed (see Cut List).
- The CAS predicate is `content_sha IS NULL` (the verified applied value); if
  anything populated it since Phase 0 the UPDATE matches 0 rows → exception →
  whole unit rolls back → re-triage. This IS the compare-and-set guard.

### Phase 3 — Post-repair verification (read-only)

Inside the same mutex window (before `release`):

```bash
psql "$db_url" --no-psqlrc -tAq \
  -c "select conname, confdeltype, pg_get_constraintdef(oid) from pg_constraint \
        where conname = 'audit_github_token_use_founder_id_fkey';
      select filename, content_sha from public._schema_migrations \
        where filename = '052_multi_source_dedup.sql';
      select substring(obj_description(p.oid) from 1 for 60) from pg_proc p \
        join pg_namespace n on n.oid=p.pronamespace \
        where n.nspname='public' and p.proname='anonymise_audit_github_token_use'"
```

Expected: `confdeltype=n` + `ON DELETE SET NULL`; `content_sha =
048013204a426cf4a024d083a57b22367b436b7a`; comment head `PR-H (#3244) —
Explicit Art. 17 anonymise path`. Then `release` (trap) fires.

### Phase 4 — Closeout

1. Comment on #10095 with: the verified causal chain (A1 arm —
   `acb4d37493`/`a14380522d` timeline table), the repair-unit contents, the
   pre/post catalog evidence, the mutex/backup record, and the bound on the
   "unblocks deleteUser" claim (WORM-trigger nuance → follow-up issue number).
2. `gh issue close 10095 --comment "<pointer to evidence comment>"`.
3. Comment on #9993 (standing tracker, stays open): the mig-052 FK drift leg
   reconciled under #10095 — dev now matches main for
   `audit_github_token_use_founder_id_fkey`.
4. File the follow-up issue (inferred scope): "`audit_github_token_use_no_mutate`
   lacks the founder_id→NULL cascade carve-out (audit_byok_use 066 /
   dsar_export_audit_pii 160 pattern) — 'set-null' teardown class inert for
   this table; Art.17 erasure gap when anonymise RPC fails pre-delete",
   labels `domain/engineering`, `type/bug`, `meta/machinery`. Mark it as a
   main-side defect — NOT fixed by this work.
5. Optional corroboration (non-blocking): next `scheduled-dev-migration-drift`
   cron run should stay green — no new findings expected from this row (sha
   now matches main's blob).

## Files to Edit

None — dev-database operational repair; no repo files change.

## Files to Create

None (pipeline planning artifacts + a `/tmp` scratch repair unit that is never
committed).

## Non-Goals

- Do NOT change main — schema, migrations, tests, or the teardown helper. Main
  is already correct (issue's own instruction). The `session_replication_role`
  wording in both function comments is stale relative to 087's `app.worm_bypass`
  body on MAIN too — a main-side doc defect, out of scope.
- Never touch prd (`hr-dev-prd-distinct-supabase-projects`). Every command is
  `-c dev` only; no prd credential is ever resolved.
- Do NOT re-apply 052 (non-idempotent — class C, not class B) and do NOT add a
  `founder_id` carve-out to the WORM trigger on dev (creates new drift; the gap
  is a main-side follow-up).
- Do NOT rewrite the ledger `filename`, `applied_at`, or any other row; the CAS
  touches only `content_sha` of the 052 row.
- Do NOT chase the remaining red legs: mu1 (#9995), raw-deleteUser carriers
  (#10096), umbrella #9993 stays open.
- No `NOTIFY pgrst` (no signature/grant change — documented, not omitted).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case a dev-database FK stays RESTRICT or the ledger row keeps a NULL sha;
  CI teardown on dev may keep failing on the same class it already fails on.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — a constraint clause change on a synthetic-only dev project
  + a ledger row's hash value. No user data touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** shared-dev schema parity repair on
  synthetic data; no prod mutation, no regulated-data surface, no user-facing
  artifact.

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` — the only hit (#8859,
PR #8858 debt-ledger review) is unrelated to migrations/teardown. No fold-ins.

## Domain Review

**Domains relevant:** none

No cross-domain implications — an internal dev-database parity repair plus
issue-tracker closeout. (Product/UX gate mechanical override: `Files to
Create`/`Files to Edit` are empty — no UI surface; tier NONE.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Apply the §Content-drift repair on dev (re-create the FK with `ON DELETE SET NULL` to match main)" [#10095] | Phases 1-2 (class C unit) | mapped |
| 2 | "or record the reconcile path the `dev-ledger-parity` machinery prescribes" [#10095] | Recorded in Premise Validation: machinery refuses merged rows (`dev-ledger-reconcile.yml` discards only unmerged-PR rows) → manual class C is the prescribed path | mapped |
| 3 | "compare-and-set the `_schema_migrations.content_sha` ledger row for 052 to main's blob sha" [issue repair spec] | Phase-2 CAS DO-block | mapped |
| 4 | "Do NOT change main — main's schema is already correct" [#10095] | Non-Goals + AC5 | mapped |
| 5 | "It makes `tenant-isolation-teardown.ts`'s `set-null` fatality class … wrong on dev" [#10095] | Phase-3 verify + AC4 (+ bound recorded: WORM carve-out gap → Phase-4 follow-up) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phases 0-3 verify + repair + re-verify | asks 1-3 quotes above | asked |
| Ledger backup + schema dump + mutex | learning's §Content-drift procedure (issue cites it as the repair spec) | asked |
| Phase 4 close #10095 with evidence | — | inferred — a verified-repaired tracker left open is stale tracking data; evidence-based close is the resolution the issue exists for |
| Phase 4 comment on #9993 | "Ref #9993" (issue footer) | inferred — keeps the standing tracker accurate without closing it |
| Phase 4 follow-up issue for the WORM carve-out gap | — | inferred — the plan-time triage surfaced a verified main-side latent defect of the #9994/160 class; `wg-when-an-audit-identifies-pre-existing` hygiene is to file, not to expand scope or to silently drop |
| Comment replay in the repair unit | — | inferred — the §Content-drift procedure requires every object in the drifted-file union to reach main's latest definition; dev's function comment is the applied blob's RESTRICT-era text |

### Split Assessment

- Subsystems touched: 0 repo subsystems (dev DB + issue tracker only)
- Planned files: 0 | Estimated changed lines: 0
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: On dev, `select confdeltype, pg_get_constraintdef(oid) from
  pg_constraint where conname='audit_github_token_use_founder_id_fkey'` returns
  `n` + `FOREIGN KEY (founder_id) REFERENCES users(id) ON DELETE SET NULL`.
- [ ] AC2: `select content_sha from public._schema_migrations where
  filename='052_multi_source_dedup.sql'` on dev returns
  `048013204a426cf4a024d083a57b22367b436b7a` — identical to
  `git rev-parse origin/main:apps/web-platform/supabase/migrations/052_multi_source_dedup.sql`
  (or a recorded reason in the issue comment if the value cannot be set).
- [ ] AC3: `gh issue view 10095 --json state` returns `CLOSED`, with a comment
  carrying the causal chain (`a14380522d` applied blob, `acb4d37493` edit,
  applied_at 21:13:16Z) and the post-repair census.
- [ ] AC4: Teardown-parity verified (read-only): `apps/web-platform/test/helpers/tenant-isolation-teardown.ts`
  labels `anonymise_audit_github_token_use` `set-null` (line ~119), and dev's
  FK now matches the migration the parity guard derives that class from — the
  label is as accurate on dev as on main. The residual main-side WORM
  carve-out gap is recorded in the follow-up issue (AC7), not silently folded.
- [ ] AC5: No code changes — `git diff --quiet origin/main...HEAD -- apps/
  plugins/ .github/ scripts/ supabase/` exits 0.
- [ ] AC6: `obj_description` on `public.anonymise_audit_github_token_use` on dev
  begins `PR-H (#3244) — Explicit Art. 17 anonymise path` (main's text);
  `proacl` census unchanged from pre-repair.
- [ ] AC7: The follow-up issue for the missing `founder_id→NULL` WORM
  carve-out exists (issue number recorded in the #10095 close comment), or a
  recorded reason it was not filed.
- [ ] AC8: Mutex released (`DEV_SUITE_MUTEX_RELEASED` banner or `HOLDER_LOST`
  recorded); backup artifacts (ledger `\copy`, `pg_dump --schema-only`)
  recorded as existing under a local `/tmp` path in the work log.

## Test Scenarios

- **integration (repair):** Given dev `confdeltype='r'` + NULL ledger sha, when
  the Phase-2 unit runs under the mutex, then `confdeltype='n'`, the
  constraint def reads `ON DELETE SET NULL`, the ledger sha equals main's
  blob, and the comment matches — all in one transaction (a mid-unit failure
  rolls the whole thing back, verified by ON_ERROR_STOP + --single-transaction).
- **integration (honest exit G1):** Given `confdeltype='n'` at Phase 0, then
  Phases 1-2 are skipped, no write occurs, and #10095 is commented + closed
  with the "already repaired" finding.
- **integration (honest exit G3/G4):** Given a missing ledger row or a
  non-NULL sha that matches neither known blob, when Phase 0 executes, then no
  write occurs and the anomaly is posted on #10095.
- **integration (CAS guard):** Given anything populated `content_sha` between
  Phase 0 and Phase 2, the DO-block matches 0 rows, raises, and the
  transaction rolls back — dev is unchanged.

## Context

- Issue: #10095 (`[ci/dev-ledger-reconcile] dev schema drift:
  audit_github_token_use.founder_id is ON DELETE RESTRICT on dev vs SET NULL
  on main (mig 052)`), labels `ci/integration-suites`, `meta/machinery`,
  `priority/p2-medium`.
- Repair procedure: `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
  §Content drift (classes A/B/C; one transaction per repair unit; ledger CAS;
  backup + mutex; pooler :5432 takeaway).
- Precedent for this exact work shape: #9994's closeout (2026-10-12) —
  dsar_export_jobs/dsar_export_audit_pii dev reconcile executed
  "operator-approved, mutex + ledger backup + single transaction".
- Key artifacts: `apps/web-platform/scripts/run-migrations.sh:403`
  (content_sha = `git hash-object`);
  `apps/web-platform/scripts/dev-ledger-parity.sh` (`check` /
  `classify-missing`; usage at :107-151);
  `scripts/dev-suite-mutex.sh` (`acquire|release|probe`; fail-open banners;
  state-dir caveat for separate local invocations);
  `.github/actions/dev-migration-drift-probe/action.yml` (NULL-sha skip);
  `apps/web-platform/test/helpers/tenant-isolation-teardown.ts:119`
  (`set-null` label); `test/server/teardown-anonymise-parity.test.ts`
  (re-derives the class from migrations).
- Verified dev census values at plan time (2026-10-13): confdeltype `r`;
  ledger row `052_multi_source_dedup.sql | NULL | 2026-05-19 21:13:16+00`;
  table rowcount 0; dependents 0; founder_id nullable; WORM trigger `O` +
  `app.worm_bypass` body, no founder_id carve-out; anonymise RPC proacl
  `{postgres,service_role}`.

## Notes

- `lane:` set to `cross-domain` — no `spec.md` exists for this branch, so the
  fail-closed default applied (TR2). No `spec.md` will be authored: this is an
  operational dev-DB repair plan, not a feature spec.
- **No Task/Agent tool exists in this harness (Devin CLI subagent), so every
  research/review fan-out the skills prescribe was executed inline by the
  planner instead** — every read-only command in this plan was run once at
  plan time and its output is recorded above (established Devin-CLI
  substitution convention).
- Advisor consult (Phase 4.5) skipped: the repair is a prescribed-procedure
  replay (learning §Content drift class C) with verified evidence; the two
  technical decision rows carry `pending - assumed` rulings for the
  technical-ruling gate's batched CTO consult per the one-shot contract.
- Doppler config used: `-p soleur -c dev` (the same database the nightly legs
  authenticate against via `-c dev_scheduled` — the sibling pipeline verified
  both configs resolve to identical user/host/db).
