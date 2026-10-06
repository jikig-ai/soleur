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

## Prepared isolated rehearsal scope

Execution remains held pending clarification of the user's local-verification
hold. This is a concrete proposed scope, not an executed harness or successful
rehearsal. The agent would own execution and teardown after that scope is
authorized; no database or log-fetch task is handed to the operator.

1. Assemble and identify the candidate runner with locked dependencies and
   recorded tool versions. Use no inherited credentials, existing volumes or
   shared services; retain exact artifact hashes and the served build SHA.
2. Create one exclusively owned disposable database from the unchanged
   applicable migration chain and its filename/blob-hash ledger. The existing
   `migration-145-codex-backfill.integration.test.ts` must not run unchanged:
   its non-CI path selects `supabase_db_web-platform`, and its handcrafted
   fixture explicitly does not prove the complete chain.
3. Seed two wholly synthetic tenants, distinct owner mode choices, Claude and
   routine controls, admitted and unadmitted old-generation attempts, current
   attempts and bounded protected checkpoints. Capture exact before-state.
4. Replace/restart application artifacts only, retaining the database. Verify
   mode choices, attempt identities, original `accepted_at` values, ledger
   filenames/blob hashes and unrelated tenant controls survive. Verify admitted
   old-generation completion, refusal of stale retry/checkpoint writes, and
   refusal of unadmitted stale execution.
5. Exercise owner/tenant/member boundaries and erasure using synthetic local
   identities, with no real auth service, provider launcher or external egress.
   Keep Codex disabled. Verify erased checkpoints cannot be recreated.
6. Record bounded logs, before/after results, candidate/runtime hashes and
   teardown of only task-owned resources. Label direct RPC evidence separately
   from application startup and authenticated Web evidence.

A mock repository or direct SQL rehearsal alone cannot qualify deployed Web
compatibility. Authenticated screenshots, routine eligibility, separate
permitted Web matrices and attributable mode-specific CLO dispositions remain
distinct subsequent gates. API-key stays PENDING without live permission,
key or deadline; managed hosted-auth stays BLOCKED. PR #9051 remains draft,
Codex default-off and customer content blocked.
