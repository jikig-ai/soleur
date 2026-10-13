# Tasks — feat-one-shot-10095-dev-fk-drift-setnull

Plan: `knowledge-base/project/plans/2026-10-13-fix-dev-fk-drift-052-setnull-plan.md`
Issue: #10095 (closes) · tracker: #9993 (stays open) · follow-up: WORM
carve-out gap issue (new)

## 0. Work-time re-verification (read-only) + honest-exit gates

- [ ] 0.1 Re-run the Phase-0 census (`pg_constraint.confdeltype`,
  `_schema_migrations` 052 row, `audit_github_token_use` count, `pg_depend`
  dependents) via `doppler run -p soleur -c dev` on the pooler URL.
- [ ] 0.2 Gate G1: if `confdeltype='n'` → skip §1-§2, run §3 parity checks,
  comment "already repaired" evidence on #10095, close. No writes.
- [ ] 0.3 Gate G2: if `confdeltype` ∉ {`r`,`n`} or constraint absent → STOP,
  post census on #10095, no writes.
- [ ] 0.4 Gate G3: if the `052_multi_source_dedup.sql` ledger row is missing →
  STOP (different drift class), post on #10095, no writes.
- [ ] 0.5 Gate G4: if `content_sha` is non-NULL and matches neither
  `a14380522d48c1f56b03dcf3e940dd7ae82d082b` nor
  `048013204a426cf4a024d083a57b22367b436b7a` → STOP, re-triage, no writes.
- [ ] 0.6 Gate G5: if `pg_depend` shows dependents → reassess; STOP on any
  unexpected dependent. Record the table rowcount in the evidence either way.

## 1. Mutex + backups (single `doppler run` invocation)

- [ ] 1.1 `mkdir /tmp/10095-dev-fk-drift-<ts>`; inside ONE
  `doppler run -p soleur -c dev -- bash -c '…'` invocation (shared
  `DEV_SUITE_MUTEX_STATE_DIR` via same caller pid), run
  `scripts/dev-suite-mutex.sh acquire` with
  `DEV_SUITE_MUTEX_IDENTITY=local-10095-reconcile`; grep the banner
  (`ACQUIRED|WAITING|CONTENDED_PROCEEDING`). Arm `trap … release EXIT`.
- [ ] 1.2 `\copy` the full `_schema_migrations` table to a LOCAL csv under the
  backup dir (never a `public` table).
- [ ] 1.3 `pg_dump --schema-only -n public` to a LOCAL file under the backup
  dir.
- [ ] 1.4 Snapshot the pre-repair constraint defs to a LOCAL file.
  (Session-mode URL `${DATABASE_URL_POOLER/:6543\//:5432/}` for all of these.)

## 2. Repair unit (class C targeted SQL, one transaction)

- [ ] 2.1 Write the scratch `$BK/repair-052.sql`: `SET LOCAL` timeout pins;
  `DROP CONSTRAINT audit_github_token_use_founder_id_fkey`; `ADD CONSTRAINT …
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE SET NULL`;
  `COMMENT ON FUNCTION public.anonymise_audit_github_token_use` replay of
  main's text; the CAS `DO` block (`UPDATE _schema_migrations SET
  content_sha='048013204a426cf4a024d083a57b22367b436b7a' WHERE filename=…
  AND content_sha IS NULL`, assert ROW_COUNT=1).
- [ ] 2.2 Apply via `psql "$db_url" --no-psqlrc --single-transaction
  -v ON_ERROR_STOP=1 -f "$BK/repair-052.sql"` on the session-mode URL, inside
  the mutex window.
- [ ] 2.3 Confirm no `NOTIFY pgrst` needed (constraint/comment change only —
  no signature/grant) and record that reasoning in the work log.

## 3. Post-repair verification (read-only, same mutex window)

- [ ] 3.1 Re-run the census: `confdeltype='n'` + `ON DELETE SET NULL` in
  `pg_get_constraintdef`. (AC1)
- [ ] 3.2 Ledger row: `content_sha = 048013204a426cf4a024d083a57b22367b436b7a`
  — identical to `git rev-parse origin/main:apps/web-platform/supabase/migrations/052_multi_source_dedup.sql`.
  (AC2)
- [ ] 3.3 Comment head on `anonymise_audit_github_token_use` begins `PR-H
  (#3244) — Explicit Art. 17 anonymise path`; `proacl` census unchanged.
  (AC6)
- [ ] 3.4 Verify teardown-parity read-only: `set-null` label at
  `apps/web-platform/test/helpers/tenant-isolation-teardown.ts:119` now
  matches dev's FK; note the parity guard
  (`test/server/teardown-anonymise-parity.test.ts`) re-derives the class from
  main's migrations. (AC4)
- [ ] 3.5 Mutex release banner observed (`DEV_SUITE_MUTEX_RELEASED` or
  `HOLDER_LOST` recorded); backup paths recorded in the work log. (AC8)

## 4. Closeout

- [ ] 4.1 Comment on #10095: causal chain (A1 arm — `a14380522d` applied at
  21:13:16Z, `acb4d37493` fix at 21:26:47Z, squash-merge `5bc14c7f95` at
  21:41:09Z), repair-unit contents, pre/post census, mutex/backup record,
  bound on the "unblocks deleteUser" claim + follow-up issue number.
- [ ] 4.2 `gh issue close 10095 --comment "<evidence pointer>"`; verify
  `CLOSED`. (AC3)
- [ ] 4.3 Comment on #9993: mig-052 FK drift reconciled under #10095; tracker
  stays open. Verify still `OPEN`.
- [ ] 4.4 File the follow-up issue: `audit_github_token_use_no_mutate` lacks
  the `founder_id→NULL` cascade carve-out (audit_byok_use 066 /
  dsar_export_audit_pii 160 pattern) — 'set-null' teardown class inert for
  this table; Art.17 erasure gap when the anonymise RPC fails pre-delete.
  Labels `domain/engineering`, `type/bug`, `meta/machinery`. Record its number
  in the #10095 comment (edit or follow-up comment). (AC7)

## 5. PR hygiene

- [ ] 5.1 `git diff --quiet origin/main...HEAD -- apps/ plugins/ .github/
  scripts/ supabase/` exits 0 — no code/migration changes. (AC5)
- [ ] 5.2 PR body carries `Closes #10095` and notes the dev-only operational
  nature of the change + the follow-up issue.
