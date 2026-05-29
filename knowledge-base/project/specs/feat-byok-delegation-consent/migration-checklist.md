# Migration checklist — feat-byok-delegation-consent (#4625)

Migrations apply post-merge via `web-platform-release.yml#migrate` (the
canonical `run-migrations.sh` path, filename-keyed, writes
`_schema_migrations.content_sha` in the same transaction). Order:

- `083_byok_delegation_consent_gate.sql` — `current_byok_side_letter_version()`
  + `resolve_byok_key_owner` acceptance gate.
- `084_byok_delegation_withdrawals.sql` — `byok_delegation_withdrawals`
  WORM table, `withdraw_byok_delegation_consent` RPC, resolver withdrawal
  clause, `check_and_record_byok_delegation_use` per-turn re-gate,
  `audit_byok_use.attribution_shift_reason` += `consent_withdrawn`,
  `anonymise_byok_delegation_withdrawals` RPC.

Both run **before** any dependency on the schema (the gate is in SQL; the
TS lease path already calls `resolve_byok_key_owner`). 083 before 084
(084's `to_regclass`/`pg_proc` precondition asserts 083's function exists).

## dev apply — pending (post-merge via release pipeline)
## prd apply — pending (post-merge via release pipeline)

## 074 content_sha reconciliation (post-apply, dev + prd)

This PR edits the **header comment** of the already-applied
`074_byok_delegation_acceptances.sql` (AC9 — correct the Art. 6(1)(b)/
consent conflation to state Art. 6(1)(a) consent + Art. 26 coherently).
The runner is filename-keyed, so 074 is **not re-applied** (no DDL change;
the body is byte-identical — only the leading `--` comment block changed).
But the `dev-migration-drift-probe` composite action compares
`_schema_migrations.content_sha` against `git ls-tree origin/main`'s blob
sha, so after merge it will emit a **`::warning::`** (not a merge-blocking
gate) for 074 until the ledger sha is reconciled on dev + prd.

Reconcile once 074's new content lands on origin/main (automatable via
Doppler `DATABASE_URL_POOLER`, per AGENTS.md §"Tracking row in the SAME
transaction"; same recovery shape as PR #4225):

```sh
NEW_SHA=$(git hash-object apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.sql)
# dev:
doppler run -p soleur -c dev -- sh -c 'psql "$DATABASE_URL_POOLER" -c "UPDATE public._schema_migrations SET content_sha = '"'"'"'"'$NEW_SHA'"'"'"'"' WHERE filename = '"'"'074_byok_delegation_acceptances.sql'"'"';"'
# prd: same with -c prd
```

(Verify: the drift probe annotation for 074 disappears on the next
scheduled run, or run `apps/web-platform/scripts/preflight-schema-vs-ledger.sh`.)
