---
title: Codex Web recovery candidate and rehearsal boundary
date: 2026-10-06
reviewed_sha: 8ad1754705e76153fd6f8a91698157305f89581c
pr: 9051
status: candidate-identified-runtime-and-retained-schema-unqualified
---

# Recovery candidate and rehearsal boundary

The candidate is a **current-source forward recovery**, using the artifact set
compiled from `9304505dbd263a5ccf1059300d7acdffc3df7336`. It is not a verified
earlier rollback release or a qualified runner image. The
[compilation record](node22-pinned-build-9304505d.md#resynced-source-compilation)
owns the exact base, compiler controls and artifact hashes.

At the reviewed head, a Git comparison found no application, plugin, script or
workflow differences from that compiled source. All five recorded artifact
SHA-256 values were independently recalculated and matched. The exported
`.next`, server bundle and compiled config remain under the task-owned
`.soleur/pinned-compiler-resync-9304505d-20261006T065308Z-3785833/source/apps/web-platform/`.
These local artifacts are not published or deployed.

## Dependency boundary

The compiler mounted cached dependencies read-only; it did not run `npm ci`.
A current package-version inventory found these mismatches against the
reviewed app lockfile:

| Package | Lockfile | Current cached package |
|---|---|---|
| `@anthropic-ai/claude-agent-sdk` | `0.3.284` | `0.3.197` |
| `@anthropic-ai/claude-agent-sdk-linux-x64` | `0.3.284` | `0.3.197` |
| `@anthropic-ai/claude-code` | `2.1.284` | `2.1.280` |
| `@anthropic-ai/claude-code-linux-x64` | `2.1.284` | `2.1.280` |
| `fast-uri` | `3.1.8` | `3.1.5` |
| `ip-address` | `10.7.2` | `10.5.0` |

This is a present-cache observation, not a captured build-time dependency
manifest. Package versions alone establish neither tarball integrity nor
production dependency/tool parity. Absent package paths were not classified
as required missing packages: platform-optional entries and installation
layout require separate analysis. The Dockerfile's production dependency
installation, global CLI tools, browser/system dependencies and runner
assembly remain unqualified. Do not reuse this cache as a lockfile-parity
attestation or start the existing bundle as a qualified recovery application.

## Static retained-schema coverage

The scoped `data-migration-expert` assessment found no new implementation
defect at the reviewed head. It inspected unchanged migration/RPC definitions
and existing regression definitions; no SQL or application runtime executed.

- Migration 145's `assert_agent_engine_attempt_generation()` validates
  admission generation and records `accepted_at` once.
- Migration 148's `transition_agent_engine_attempt()` and
  `append_agent_engine_lifecycle_event()` permit an already admitted old
  generation to finish while fencing unaccepted stale execution, with
  run-before-attempt locking.
- Migration 152's `save_agent_engine_recovery_checkpoint()` rejects stale
  generations and anonymized runs.
- `codexConversationRuntime()` still supplies no launcher or qualification
  and accepts no customer data class.

The [static migration recovery review](migration-145-recovery-review-5cb81c9d.md#recovery-verdict-and-remaining-gate)
and [supported recovery runbook](../../../../apps/web-platform/docs/migration-rollback.md)
require retained settings, attempts, protected fields and ledger. Candidate
identification and static invariant inspection do not establish application
startup, retained-state compatibility, concurrency behavior or Web parity.

## Isolated rehearsal attempt: incomplete

The user authorized one disposable, wholly synthetic recovery rehearsal. A fresh
PostgreSQL container ran with `--network=none`; its disposable database applied
the 13 unchanged migration bodies listed below on the declared synthetic base,
seeded two synthetic tenants and captured the pre-replacement state. Database
creation, scoped migration setup and the initial snapshot each exited zero.

The run stopped before waiting for PostgREST or starting the application.
Starting the local PostgREST container reached a runner assertion that compared
Docker's reported shared network value with the requested container-name string.
The assertion did not accept the value Docker returned. The runner then removed both owned containers;
the bounded record at the worktree scratch path reports both removals confirmed.
No application runtime, before/after comparison, recovery scenario SQL or
external egress ran. This is a harness validation failure, not a recovery pass.
The run was not retried; exact logs and the failed record remain task-owned under
`.soleur/isolated-recovery-845d1455-20261006T073743Z-510203/` and are excluded
from the commit.

The prepared and partially applied closure contains 13 unchanged complete
migration bodies: 138, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151
and 152. Their full files and Git blob hashes were checked against HEAD before
setup. The remaining 170 of 183 forward migrations were not applied. Base
tables, auth claim helpers and membership functions are synthetic; this does
not execute the production runner or prove the full historical schema.

The remaining planned checks stay unqualified:

1. Correct the container-network assertion, then prepare a new one-shot
   rehearsal with a fresh task-owned database and container names.
2. Start the candidate application against the retained database and verify
   connected startup and graceful stop for both application instances.
3. Compare exact pre/post application state, then run the stale-generation,
   owner/member/tenant and erasure SQL cases.
4. Record bounded logs, artifact hashes, scenario results and confirmed teardown.

The existing `migration-145-codex-backfill.integration.test.ts` must not run
unchanged: its non-CI path selects `supabase_db_web-platform`, and its
handcrafted fixture does not prove the complete chain.

A mock repository or direct SQL rehearsal alone cannot qualify deployed Web
compatibility. Authenticated screenshots, routine eligibility, separate
permitted Web matrices and attributable mode-specific CLO dispositions remain
distinct subsequent gates. API-key stays PENDING without live permission,
key or deadline; managed hosted-auth stays BLOCKED. PR #9051 remains draft,
Codex default-off and customer content blocked.
