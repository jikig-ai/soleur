---
title: "Migration 145 static recovery review"
date: 2026-10-04
reviewed_sha: 5cb81c9d97196b7e29e4c4436edb26e77785a75e
pr: 9051
status: static-review-complete-recovery-qualification-pending
---

# Migration 145 static recovery review

The scoped static code review is complete at the exact SHA above. No additional
implementation defect was found in migration admission or reconciliation
protection. This verdict does not approve promotion: the compatible application
recovery build and recovery rehearsal remain unqualified.

The review followed the canonical `data-migration-expert` role. Its scope was
migration 145's forward/down SQL, the production migration runner, its injected
admission guard, shared-dev reconciliation, their regression definitions, the
rollback runbook, and the live-handler wiring plan. Tests were inspected, not
executed. Local suites, runtime/database probes, provider calls, credential
reads, shared/prod database writes and remote mutations were forbidden for this
review. No such operations occurred. No live database measurements are asserted.

## Admission and protected data

Migration 145 adds `workspace_engine_settings.codex_auth_mode`, the owner's
separate Codex mode choice, and `agent_engine_attempts.accepted_at`, evidence
that a turn admitted before a mode switch may finish. It backfills settings
from a Codex workspace default or the latest supported Codex conversation mode.
Its historical down drops both fields; forward reapplication cannot reliably
reconstruct their values.

`.github/workflows/web-platform-release.yml` calls
`apps/web-platform/scripts/run-migrations.sh`. The production runner skips
`.down.sql` files. For migration 145, it injects
`scripts/sql/codex-auth-mode-pre-migration.sql` before the unchanged migration
body and ledger insertion, inside one `psql --single-transaction -f -`
invocation. The runner strips the migration's exact outer transaction wrapper
so the ledger insert remains inside that transaction. A missing guard asset
refuses the apply.

The guard acquires `ACCESS EXCLUSIVE` on
`public.workspace_engine_settings`, with a 30-second lock timeout and
five-minute statement timeout. It rejects Codex defaults whose source mode is
NULL or outside `managed`/`api-key`. Holding the lock through the constrained
backfill excludes concurrent owner RPC and direct settings writes. A separate
zero-count observation cannot replace this guard. Refusal does not normalize
the value or choose a credential mode for the owner.

## Down and reconciliation paths

1. **Production forward runner:** down files are skipped; deployment migration
   application does not perform schema rollback.
2. **Direct historical down or ancestor down:** unsupported. Migration 145's
   down destroys both protected fields; table-owning ancestor downs can erase
   them indirectly. A sufficiently privileged direct SQL caller can still run
   historical SQL. The protections reviewed here govern supported automation,
   rather than claiming to prevent arbitrary privileged SQL.
3. **145 selected for reconciliation:**
   `dev-ledger-reconcile.sh`'s refusal stage independently refuses removal of
   145's row, including ledger-only selection. `--allow-later-rows` cannot
   waive this refusal.
4. **Any other paired down while 145 is retained:** every eligible paired down
   is refused when 145 appears anywhere in the retained ledger, independently
   of ledger age, advisory SQL classification or the later-row override. This
   covers ancestor table drops, nested dollar-quoted SQL and apparently benign
   downs. Protection precedes the advisory classifier, which cannot establish
   the safety of executable dollar-quoted bodies.
5. **Unrelated ledger-only cleanup:** permitted because it executes no down
   body. The writer uses a ledger lock, snapshot comparison, per-row
   compare-and-set deletion and closing ledger comparison. The positive-control
   regression asserts that 145's ledger row remains.
6. **Read-only `--scan-down`:** classifies 145's down as `codex-forward-only`;
   this classification is not evidence that snapshot or restoration ran.

## Static regression evidence

`test/scripts/run-migrations-codex-guard.test.ts` defines checks for guard
ordering before the body and ledger write, bounded timeouts, removed outer
transaction wrappers, missing-asset refusal and unrelated-migration behavior.

`test/migration-145-codex-backfill.integration.test.ts` defines disposable
PostgreSQL cases for unsupported, NULL and supported source modes. Its lock
fixture waits for a post-guard readiness marker, checks that the exclusive lock
is granted, then holds the transaction until the competing unsupported writer
returns. Parent-controlled release and bounded teardown replace the earlier
fixed-sleep race. These definitions were inspected; no execution result is
claimed by this review.

`scripts/dev-ledger-parity.test.sh` defines refusal checks for 145 itself, the
later-row override, actual table-owning ancestor downs, shared-object
redefinition, nested dollar-quoted DROP and benign paired SQL. Its ledger-only
positive control verifies one cleanup unit without removal of 145.

`test/migration-145-codex-auth-mode-rebind.test.ts` statically covers the field
definitions and admission/generation semantics. `accepted_at` distinguishes an
already admitted turn from stale retries and preserves its ability to finish
after a mode change; the protected field cannot be discarded as incidental
metadata.

## Recovery verdict and remaining gate

`apps/web-platform/docs/migration-rollback.md` and the live-handler wiring plan
now describe a concrete supported strategy: retain settings, attempt rows,
both protected fields and the migration ledger; keep Codex disabled; revert
application code only to a verified compatible build, or ship a forward
correction. If a compatible build is not verified, execution remains disabled.

The remaining recovery qualification must identify the exact compatible
application build or correction and demonstrate that recovery against the
retained schema preserves the owner's mode choice and admitted-turn semantics.
This scoped static review establishes neither an exact qualified recovery
build nor a completed recovery rehearsal.

Snapshot/restoration is not implemented or claimed. It is required before
permitting a schema downgrade, rather than an unconditional requirement for
schema-preserving recovery. Any future downgrade must capture both fields with
their workspace/attempt identities under bounded write exclusion, establish
durable recoverability, and restore exact values before execution while
preserving isolation, erasure, retention and admission semantics.

The runbook contains content-free pre/post migration SQL for source-mode
validation, target-mode validation, ledger presence/blob comparison and
admission-column presence. Those probes were not executed here. Exact-head CI
and recovery qualification remain separate gates; this artifact does not
substitute for either.
