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

An additional source-head candidate build at `845d1455d55b76754c2cd4f3c9804a1f7d6888a1`
used the same pinned Node 22.22.1 base and installed the app's locked builder
and runtime dependencies offline from 1,220 integrity-checked cached archives.
`npm ci` used `--ignore-scripts`; six unavailable optional WASM archives were
not required by the successful Linux x64 build. Next/Webpack, TypeScript/routes,
the custom server, Next config, development-sign-in tripwire and native Sharp
resolution all passed. The [locked candidate build record](recovery-build-845d1455.md)
contains the image, lockfile and artifact hashes. This resolves the prior
current-cache version drift for this isolated app build only. Ignored install
scripts, global CLI/system/browser tools and full runner assembly remain
unqualified; no build artifact was published or started at this point.

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

The first run stopped before waiting for PostgREST or starting the application.
Its runner compared Docker's reported shared-network value with the requested
container-name string and rejected the normalized container ID. Both owned
containers were confirmed removed. This was a harness validation failure, not
a recovery pass; its logs and record remain under
`.soleur/isolated-recovery-845d1455-20261006T073743Z-510203/` and are excluded
from the commit.

After separate user authorization, one fresh attempt used the corrected
container-ID assertion, fresh disposable database/container names, and the
same pinned candidate runtime from source `845d1455d55b76754c2cd4f3c9804a1f7d6888a1`.
The repository head observed by the runner was `d1cc746218c1437b4b61a77fca155453774df6c0`;
the candidate artifact predates that head and does not qualify current-source
runtime. PostgreSQL ran with `--network=none`; its synthetic database creation,
13-migration setup and pre-replacement snapshot all exited zero. PostgREST and
the local REST proxy started in the isolated namespace. Candidate app startup
then failed before process launch because the read-only image had no
`/app/shared/plugins/soleur` mountpoint. The harness confirmed removal of the
app, proxy, PostgREST and PostgreSQL containers. No application health check,
post-state comparison, recovery scenario SQL or egress ran. The exact bounded
record and logs are task-owned under
`.soleur/isolated-recovery-9051-attempt2/` and excluded from the commit. This
authorized attempt is incomplete, not a recovery pass, and was not retried.

The prepared and partially applied closure contains 13 unchanged complete
migration bodies: 138, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151
and 152. Their full files and Git blob hashes were checked against HEAD before
setup. The remaining 170 of 183 forward migrations were not applied. Base
tables, auth claim helpers and membership functions are synthetic; this does
not execute the production runner or prove the full historical schema.

The remaining planned checks stay unqualified:

1. A further rehearsal requires new explicit authorization, a source-current
   candidate, and a writable mountpoint created in the disposable container
   image before applying the root-filesystem read-only setting.
2. Start an authorized candidate against the retained database and verify
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

## Source-current preparation — 2026-10-07

The [new local candidate record](recovery-build-66f424cb.md) supersedes the earlier
candidate identification for source `66f424cb0a592a54ea33d12cc64a1cbbd627e8c6`.
All eleven preparation stages passed, including locked offline dependencies,
full Next compilation, local image assembly, read-only nested plugin mounting
and independent image/runtime artifact checks. The image and parent runtime
bind source both contain the plugin mountpoint. Raw preparation failures and
deadline interruptions are preserved and described in that record.

This resolves candidate preparation only. No application startup, SQL setup,
snapshot comparison or recovery scenario ran for this source. The two historical
recovery attempts remain incomplete. A new one-use synthetic rehearsal still
requires fresh explicit authorization; all later qualification holds remain.

Main subsequently merged as `387e36f75d730c1b8283c245d76263241412dff3`.
App/compiler/dependency bytes are unchanged; the two changed plugin files were
refreshed in a local image layer. Fresh image/plugin hashes and read-only mounting
passed. The linked candidate record identifies the current image, provenance,
twelve required stages and updated one-use command. No rehearsal has run.

The next main sync merged as `27c04a95ca007813847a17e4c765dc37e2d0aeb6`.
The candidate record now identifies its current renderer/plugin image and
explicitly excludes the new deployment-guard shell changes from the synthetic
proof. Full production runner/infrastructure parity remains unqualified.
Fresh image/plugin checks and read-only binding passed; no rehearsal ran.

## Authorized scoped rehearsal result — 2026-10-07

The user subsequently authorized one synthetic rehearsal of the prepared
`27c04a95` renderer/plugin candidate. It ran once and passed fresh isolated
database setup with 13 unchanged migrations, connected initial/replacement
health and graceful shutdown, exact pre/post retained-state equality, and the
scoped generation, owner/member/tenant and erasure SQL cases. All five owned
containers were removed. The [attributable result and hashes](recovery-build-66f424cb.md#separately-authorized-rehearsal--2026-10-07)
bind this verdict to candidate source, observed head, image, script and raw record.
This discharges connected renderer startup/restart and this synthetic retained-
state/RPC proof only; the two historical attempts remain incomplete.

Production tool/infra/workspace/observability parity, full historical schema,
concurrency and live Codex-process recovery remain unqualified. No OpenAI call,
real credential, shared database/production write or customer content was used.
The one-use authorization is consumed; another rehearsal needs new explicit
authorization. Local suites and all later QA, routine, Web, legal, review and
promotion gates remain held. Keep draft/default-off/customer content blocked.
