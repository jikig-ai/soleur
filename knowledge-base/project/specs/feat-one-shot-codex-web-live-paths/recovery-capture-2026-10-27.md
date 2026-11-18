# Approved recovery capture — 2026-10-27

## Authority and result

The operator approved exactly one metadata capture at source
`4225c68a3eb1e9bdb917f899ae85618848b2c691`, after a fresh no-action preview,
independent CTO source/binding review, and successful Doppler authentication
using the collector's restricted environment. The approval was consumed by
one successful invocation; it does not authorize a retry or a later capture.

The private receipt reports `captured-read-only-metadata`, captured at
`2026-10-27T10:27:19.021Z`. Its catalog SHA-256 is
`6b3f42ccba6a1f48d0f1a4aa1a0188fa8f5d52e3f24223f24c4e7866a49bd158`.
Both the lead and CTO independently verified that digest. Private evidence is
under `.soleur/dev-catalog-20261027-4225c68a3e/`; the directory is mode 0700
and both catalog/receipt files are mode 0600. The catalog is 312,430 bytes.
Raw catalog bytes and credentials are not committed.

| Section | Rows |
|---|---:|
| Ledger | 199 |
| Relations | 66 |
| Columns | 549 |
| Constraints | 311 |
| Indexes | 163 |
| Triggers | 50 |
| Policies | 88 |
| Selected functions | 14 |
| Sessions | 14 |
| Locks | 43 |

The collector reports zero application rows, zero mutations and
`writer_clearance:false`. It used verified TLS and a read-only repeatable-read
transaction, with a 60-second work bound and 4 MiB output bound. No dev-suite
mutex was observed in this snapshot. That observation is not writer exclusion.

## Reviewed bindings

| Input | Binding |
|---|---|
| Collector | SHA-256 `e05adb6c1042ab8bfc5cf357b0224368eeea7d047758298684be1f7a3ed8b683` |
| Supabase reference resolver | SHA-256 `fc94220469fe09b615e9e020daeac1a93edd359f64468ce5de94b4cf57a223d6` |
| App lockfile | SHA-256 `374f5b29a405e5afc159a964fc168dc7bef25c0beacd494f448170528fc10c92` |
| Supabase CA | SHA-256 `700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7` |
| Driver | `postgres` 3.4.9; archive verified against the app lockfile's SHA-512 integrity |
| Runtime | Node 26.12.1 |

The collector-equivalent authentication probes passed with only `PATH`,
`HOME` and optional existing `DOPPLER_TOKEN` passed to Doppler. Config metadata
identified project `soleur`, config `dev_scheduled`, environment `dev`.
Authentication probes did not fetch database secrets. The approved collector
then independently required distinct canonical dev/production refs before its
dev database connection.

## Filename and blob comparison

Each mapping below passed comparison against the original committed legacy
path, the current committed destination, and the captured ledger Git blob.
All destinations are absent from the captured ledger. Original `applied_at`
values, including microseconds, remain in the private capture; no timestamp,
hash or filename has been changed in the shared ledger.

| Legacy filename | Current filename | Identical Git blob |
|---|---|---|
| `143_agent_engine_attempts.sql` | `165_agent_engine_attempts.sql` | `213160dec9a98e69affd245dfacf7e3204d70954` |
| `144_codex_auth_mode_rebind.sql` | `166_codex_auth_mode_rebind.sql` | `be38bcb39d313de4e24ba44f02cdb47aebc3f00b` |
| `145_codex_auth_mode_rebind.sql` | `167_codex_auth_mode_rebind.sql` | `18282434482be03df053d014aa94ad0f153a631b` |
| `146_codex_terminal_lifecycle.sql` | `168_codex_terminal_lifecycle.sql` | `b006fb01c2544addd8035be4314273e14b7526ab` |
| `147_codex_lifecycle_state_sync.sql` | `169_codex_lifecycle_state_sync.sql` | `a8cef89ecdc303d3575dae712bd5181af5e0fd67` |
| `148_codex_lifecycle_lock_order.sql` | `170_codex_lifecycle_lock_order.sql` | `d5232094e55207676aa6c79cdff09f16509bec7e` |
| `149_codex_history_transfer_ack.sql` | `171_codex_history_transfer_ack.sql` | `6171d0949378f84bafdbb0a220cc3b1c80dd208f` |
| `150_codex_history_ack_owner_scope.sql` | `172_codex_history_ack_owner_scope.sql` | `253d27033d0c554385dc763092b6fe7430537603` |
| `151_agent_engine_event_attempt_index.sql` | `173_agent_engine_event_attempt_index.sql` | `3124f60f8c5b08a70abdc8a9c7d569883bd2cc45` |
| `152_agent_engine_erasure_lock_order.sql` | `174_agent_engine_erasure_lock_order.sql` | `bde20d998c1f06165f9bc0651351e5854421d8f7` |

Migration `175_codex_history_notice_issuance.sql` is genuinely unledgered and
is excluded from the map. All 21 SQL files in the retained renumber manifest
also match their pre-move committed bytes, Git blobs and SHA-256 values.
Among 187 same-named source/ledger entries, 119 non-null Git blob hashes match;
the other 68 hashes are null and remain unverifiable by a body hash.

Two other ledger-only records remain outside this map:

- `051_action_class_widening_and_action_sends.down.sql` has a null hash and
  original apply time `2026-05-19T19:38:41.737660Z`. Its destructive down body
  must not be replayed or its row deleted based on its filename.
- `164_git_data_erasure_pending.sql` carries blob
  `5ea5cc50b989947e2d540bef2b62b6cba5621273`, matching its original committed
  version at `29493ff592fb102ce59750ac2b6148bc028b8e7f`. Later versions on the
  independently owned branch differ. Its lifecycle and coordination are
  separate and untouched.

This proves filename/blob compatibility, not complete live-schema equivalence.
The collector does not enumerate column ACLs, role inheritance or effective
table/column privileges. Disposable registry parity and independent schema
comparison remain required.

## Writer coordination remains withheld

Ruled by CTO agent, 2026-10-27: the shared-dev mutating workflows are
`tenant-integration.yml`, `scheduled-integration-suites.yml` and
`dev-ledger-reconcile.yml`. The first two may proceed after failed advisory
lock acquisition. Per-ref workflow concurrency does not exclude other refs.
The reconciliation workflow requires actual acquisition, but cannot exclude
writers that bypass the lock. A GitHub Actions census at approximately
10:28 UTC showed tenant integration run `40488375309` in progress; this is a
dated observation, not current writer state.

Before a separately approved shared operation: prevent new starts of those
three mutators under exact authorized control-plane commands with restoration
defined; drain existing runs; account for known direct credential holders;
then require actual mutex acquisition, transactional ledger locking, fresh
tuple/schema verification and CAS. No freeze, cancellation, disable,
reconciliation or shared write was authorized or performed here.

`scheduled-realtime-probe.yml` subscribes without table mutation;
`web-platform-release.yml` applies production migrations; RLS authz fuzz
targets a disposable loopback stack with optional separate production-readonly
parity. They are distinct from the three shared-dev mutators. This workflow
inventory does not establish exclusion of direct CLI/API/database writers.

## Local checks and remaining work

The collector's 26 synthesized tests pass under Node 26.12.1 after the
sandboxed fixture-tar subprocess refusal was rerun with subprocess access.
The independent offline fake-Git/psql ledger suite passes 8/8. Six rehearsal
tests independent of the stale runner pin pass 6/6; two pin-dependent tests
are not represented as passing. Recipe preview reports 198 forward migrations,
eleven scenario artifacts, `runner-identity-review-required`,
`execute_available:false`, `independent_review_complete:false`, and zero
operational actions.

The complete runner hash is
`f71ba896687dafb34b760a754c47045a4eab1e5271d4662b1dd6e10a7f88ae3e`;
full replacement-runner review must precede repinning. Synthetic auth expired
October 26 and needs whole-contract renewal review. Owned executable
controllers, immutable-image/auth evidence, namespace/TLS isolation,
retained-file manifests, full-schema review and race observations remain
rehearsal prerequisites.

The CTO permits the grant/registry precursor on the planned Slice A branch,
before the full rights snapshot. It must pair actual forward column grants
with all three registry classifications and count column-only grants in the
non-vacuity assertion. A dedicated grant migration followed by a snapshot
migration and Slice B means three forward migrations across two PR slices.
The precursor does not complete Slice A or grant processing clearance.

PR #9051 remains draft with auto-merge off. Shared reconciliation, writer
clearance, provider requests, customer processing, full qualification, QA,
exact-head code review, preflight and readiness remain incomplete.

## Addendum — local grant precursor checkpoint

The companion branch `fix-codex-notice-rights-slice-a` now has local commit
`4f0c8407aba51fdd9c846c252e8d1edceb1cb3d1`. It contains the dedicated
179 grant migration, effective-privilege verifier, three registry entries,
column-aware non-vacuity assertion, regression tests and reusable disposable
test harness. Eight focused tests, scoped ESLint, full app TypeScript under
Node 26, and twenty actual PostgreSQL 17.6 checks pass. The owned synthetic
database was dropped; no shared application data was used. Migrations 165 and
175 remain unchanged. Full RLS-stack parity and recovery rehearsal are not
established by these focused checks.

Its report is
`knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/slice-a-grants-2026-10-27.md`
in worktree
`/data/git-repositories/jikig-ai/soleur/.worktrees/fix-codex-notice-rights-slice-a`.
The branch remains unpushed under the CTO's scoped local-only ruling because
the existing shared-dev CI exceeds current authority. This grant-only
checkpoint does not complete Slice A's rights snapshot, Slice B's retention
work, formal exact-head review, QA, preflight or final processing clearance.

Final GitHub reinspection still reports PR #9051 open/draft, auto-merge off,
and remote head `4225c68a3eb1e9bdb917f899ae85618848b2c691`. Neither this
evidence checkpoint nor the companion code was pushed. The shared writer
window and all independent readiness holds remain outstanding.
