---
title: "Source-bound full-schema recipe and fresh-ledger preparation"
date: 2026-10-12
pr: 9051
baseline_source_sha: bc0f0d47c72369c26eac91308687a6a1fe9ea762
status: offline-prepared-current-source-binding-and-independent-review-pending
---

# Full-schema preparation

The new [recipe source](../../../../scripts/codex-qualification/rehearsal.py)
prepares the complete forward migration set from the requested committed Git
source, including every original SQL byte, Git blob and SHA-256. It derives
filenames and counts; the baseline contains 188 forward files. Paired down files
are excluded. It neither imports nor executes the historical withdrawn recovery
runner. It has an offline preview entrypoint and no execution entrypoint.

The recipe binds the canonical migration runner, its production Codex admission
guard, runtime/browser identities from `prepare.py`, and the new recipe/scenario
bytes. An uncommitted runtime edit or a source SHA different from HEAD refuses
preparation. The scenario component hashes explicitly include working preparation
bytes; these must be committed and independently reviewed before any operational
approval. Final current-source production fingerprints are owed after integration.

## Canonical fresh-schema correction

Source inspection found that the prior canonical runner emitted a hash-bearing
ledger INSERT after migration 001, although `content_sha` is added by migration
054. On a fresh `--bootstrap=skip` database that INSERT would fail and roll back
the first migration. This was a source finding; no database was contacted.

The [canonical runner](../../../../apps/web-platform/scripts/run-migrations.sh)
now checks `pg_attribute` **after the migration body, inside the same
`psql --single-transaction -f -` invocation**. Its DO block inserts only filename
while the column is absent, and filename plus original apply-time Git blob once
the migration body has added the column. Earlier rows remain NULL when 054 adds
it. The generated ledger assertion derives that transition from the actual
column-creation migration, compares the entire filename set, requires pre-column
NULL and subsequent exact hashes, and never writes the ledger.

No migration SQL body changes, fixture precreated column, pre-marking, retroactive
hash backfill or substitute schema are used. The canonical `--bootstrap=skip`
path, migration-145 production admission guard, unmerged-apply guard, schema
precondition probe, transaction refusal and schema-reload behavior are retained.
Future execution must use this reviewed current-source canonical fix; the prior
claim of an unchanged historical runner is superseded for this new proposal.
The routine canonical Git fetch and schema-reload hooks remain real execution
dependencies: an approved controller must admit their exact behavior or report
a blocking capability, rather than silently changing the runner.

## Source SQL scenarios

The [scenario directory](../../../../scripts/codex-qualification/scenarios/00_support.sql)
contains actual prepared SQL. No scenario has been executed. Its fresh fixture
namespace refuses reuse. All synthetic users are generated task fixtures;
genuine `auth.users` provisioning triggers create their profiles and workspaces.
Fixtures include owner/member/other-tenant users, Claude conversation controls,
a Codex conversation, and a synthetic routine control. This routine is a schema
fixture, not an eligible routine consumer or provider execution.

The owner-only snapshot helper discovers **every table in public, auth and
storage**, including empty tables, and records every complete row with duplicate
rows preserved and deterministic order. It also records relation and column
census. Before/after application replacement compares the full normalized JSON
state, including full rows; MD5 fields are diagnostic fingerprints, not the
authority for equality. Snapshots remain inside the owned synthetic database
and must never contain customer/account data or be published as row dumps.
This is table/column and row retention coverage, not a complete catalog dump of
all function/policy/grant/sequence definitions.

Further SQL prepares stale/admitted/current generation behavior, reciprocal
tenant RLS controls, member denial of owner settings changes, service-only native
state access, owner-only history-transfer acknowledgment, refusal of wrong
generation and cross-owner/tenant acknowledgments, membership-epoch invalidation
and later generation invalidation. It compares complete unrelated Claude,
routine, member and tenant rows during owner rebinding.

The checkpoint race uses separately owned interactive holder, waiter and observer
sessions. The holder performs the actual owner rebind and leaves its transaction
open. The observer must see that exact waiter in a lock wait and the exact holder
in `pg_blocking_pids`; the controller releases the holder only after observation
succeeds. The waiter then must report the stale-generation `55000` refusal, and
the assertion phase verifies that the stale checkpoint cannot reappear and a
current-generation checkpoint can still be saved. No elapsed sleep is accepted
as race evidence. Latest checkpoint code locks the run and then reads attempt
generation; lifecycle code locks run before attempt. Owner rebind and erasure
start with workspace locks. Controller timeouts, rollback and session cleanup
are required and unimplemented here.

Engine-scoped erasure verifies creator/updater anonymisation, checkpoint purge,
stale re-creation refusal, unchanged complete other-tenant/member rows, and
unchanged unrelated public/auth/storage rows plus ledger. Engine-only erasure
retains the auth account, membership and acknowledgment rows; account deletion
purges acknowledgments via the users FK and is a separate, unexecuted path.
This scenario does not attest full account deletion or legal clearance.

## Offline checks and remaining gates

The new emitted-SQL fixture suite first failed against the old runner, then
passed **4/4** after the fix. It runs only fake Git/psql, capturing emitted SQL
and arguments; no SQL is evaluated. It checks body-before-column-decision order,
same-transaction ledger assembly, failed apply stopping subsequent files,
guard/body/ledger order and outer transaction stripping. Its fourth case runs
all **9/9** existing schema-probe assertions from a temporary copy, planting a
fetch-intercepting Git shim alongside each fake psql. Only local Git read/hash
operations are delegated. The runner itself is not rewritten for those fixtures.

The recipe suite passed **7/7** using an isolated committed Git fixture with all
current migration bytes, the working canonical fix and the minimal recipe
dependencies. It tests exact forward bytes, derived ledger comparison,
inherited-runner refusal, runtime/approval boundaries, dirty-source refusal,
dynamic complete-row census and observed-lock race requirements. This fixture
is not a full production-source or image receipt. Referenced offline Vitest
suites passed 103 checks (guard ordering, UI spend resolver and SQL literal
lexer); ten opt-in live integration checks remained skipped, with no database
or authentication action. The inherited unmerged-gate suite passed 8/8 with Git
fetch intercepted and local reads delegated; fake-curl schema-reload checks
passed 24/24 and deprecated-endpoint fixtures passed 46/46. Further ratchet and independent review
results are recorded by the integrating lead.

This is a **recipe and SQL preparation**, not runnable runtime orchestration.
Actual storage/workspace file fixtures and before/after byte manifests remain
owed; table snapshots cannot stand in for retained object bytes. The owned
Docker internal-network controller/namespace bridge, per-role command and
environment admission, exact image/filesystem/local-auth receipt, session race
controller, schema-service quiescence for comparable snapshots and bounded
owned cleanup must all be completed and reviewed. No bwrap substitution is
proposed. Fresh exact current-source build/rehearsal approval is still required;
previous authorization remains consumed. No build, retry, recovery, Docker,
SQL, authentication, provider, credential, account/shared write, deployment,
flag or cohort operation occurred in this preparation.

Keep PR draft, auto-merge off, Codex default-off and customer content blocked.
Hosted App Server authentication remains blocked in both modes; the alternative
API route remains pending. SAST VOID, #10082 OPEN, full review incomplete,
#9791 OPEN/unverified and no current-source C.9 rerun remain separate facts.
Project sharing, retention/inheritance and configured regions remain unresolved.
