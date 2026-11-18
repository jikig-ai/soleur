---
title: Withdrawn old-candidate historical recovery proposal
date: 2026-10-11
updated: 2026-10-12
pr: 9051
status: withdrawn-source-stale-auth-incompatible-admission-defects
source_sha: 2b826822c086d4348ada891e15fde2aa7b62eac3
---

## Withdrawal — 2026-10-12

Ruled by CTO agent: withdraw this proposal as the next acceptance action. The image is
source-stale after the application fixes and has unusable build-only anonymous
browser authentication. Review also found two concrete admission defects:
reserved container names were accepted as ownership before successful creation,
and exec payloads did not reject privilege elevation or credential overrides.
Passing the preparation fixtures did not establish those missing boundaries.

No build, rehearsal, image pull, application/database startup, SQL or provider
action was authorized by this proposal. Its original executable is archived at
`.soleur/recovery-proposal-20261011/withdrawn/rehearse.py`, retaining the historical
prepared digest below. The old entrypoint now refuses unconditionally before
operational imports, metadata probes, marker creation or any mutation. The
historical command is withdrawn and must not be offered for approval or run.

A separate draft-only safety prototype lives at
`.soleur/recovery-proposal-20261012/`. It repairs registered-ID/name-alias admission
and exec privilege/environment validation using offline fixtures. It is not a
replacement orchestration or an execution-ready candidate; fresh fixed-source,
auth-capable image preparation and full reviewed source/image-bound orchestration
remain necessary. The proposed hosted App Server authentication route is BLOCKED
for both modes under the October 12 CLO supplement; a different concrete
API-funded route remains PENDING. No exception or credential workaround is granted.

### Draft-only safety repair evidence

The October 12 prototype binds policy SHA-256
`67d0b0ffd3470b106c9e100bb7545f63492a1fe5637bbb652ab2325fefb64250`,
proxy SHA-256
`36e73746240aa239cf07402131508cd61284bcd6b1b0365af7be8f9ea4b23370`,
and bundle SHA-256
`772e22346df8b8b9d29edc5b4a810eb302e98ff1679cab3a78baf04fd1e7c26a`.
It passed 51 ownership/exec regressions, 12 foreign-name collision transport
checks and seven HTTP upgrade/hijack checks. The root independently reread the
admission/transport implementation and repeated those three fixture groups,
with exits zero. Only task-owned fake Unix backends were contacted; zero Docker,
database, SQL or provider calls were made. Existing creation and namespace
fixtures are separately recorded in the prototype's ignored safety record.

The withdrawn entrypoint SHA-256 is
`5ec4591eae9de713059346acbdaed77e6f0464d96145c5e1daede121b2e65d86`.
Its unconditional refusal is preparation evidence, not authorization. Network/
volume admission, complete orchestration and per-item cleanup provenance must
still be reviewed in a fresh source/image-bound proposal.

## Historical prepared action and immutable scope

The sections below preserve the old draft's intended design and preparation
evidence. Its ownership/exec claims were not established and are superseded by
the withdrawal above. They do not describe an available approval or execution.

One fresh isolated rehearsal was prepared at
`.soleur/recovery-proposal-20261011/rehearse.py`. It binds the approved build
source `2b826822c086d4348ada891e15fde2aa7b62eac3` and immutable image
`sha256:0914d1f1a6ec00fe79129531eac7d6e7aeb9507548e8f6207649d5915fa25420`.
The production build passed filesystem, default UID and owned cleanup admission.
Application fixes prepared afterward differ from this image; its rehearsal
**cannot qualify current application source**. The migration/tooling guards
remain unchanged. This is retained-schema compatibility evidence for that
specific image, not promotion or authenticated Web qualification.

Runner SHA-256:
`d8f096eaea61a1d58ca30485e359b663a7a04c761b06b6bb74c3ed9b0a9ca5ff`.

Complete runtime bundle SHA-256:
`989174e557b038c95e7f2dc23c5edbcb982bb3b046badf1b1076c0e03c87aeb9`.

The bundle binds admission policy, proxy transport, namespace bridge, immutable
image manifest, synthetic seed/scenario SQL and the pinned CLI executable.
Any changed component refuses execution. The preview passed at the source above,
explicitly returning `source_is_current_runtime: false`, 187 forward migrations,
six fixed public image pulls, eight GiB total admitted container memory and an
1800-second work deadline. No recovery marker or attempt directory exists.

The proposed one-use command was never authorized or executed and is withdrawn.
Its original design required an exclusive marker before downloads/export/startup
or database mutations. No recovery marker was consumed. Old consumed build and
historical rehearsal artifacts remain intact; they cannot be repinned or retried.

## Preparation and image closure evidence

The read-only intake bound all 187 complete forward SQL files by filename,
Git blob, SHA-256 and byte count. Its manifest digest is
`a3caa50e351fd838c5411c53a1577d587ee1bd3b2023c410d0c174d59ffa7ee2`.
The handwritten thirteen-migration closure is not reused as the database schema.

Supabase CLI 2.84.2 was subsequently prepared through reversible public tool
preparation. Its official archive SHA-256 is
`620a5f6ea7b60f9b4fe112a5d72464ea0e53d04022035641674a2e6d121e0eb5`;
the extracted executable SHA-256 is
`3132b218461bf90d4cd5983b27b44031cd9b6c797c259a431b2e2520b5f7bdce`.
Version output verified 2.84.2. Version/help preparation made an observed public
release-update metadata request; the attempted skip-update environment setting
is unsupported and is not an offline guarantee. No stack or SQL ran.

The tagged upstream CLI image definitions require older versions than the
existing shared stack cache. Anonymous ECR metadata encountered its normal bearer
challenge and then HTTP 429. Sequential read-only DockerHub metadata resolved the
original upstream repositories into six immutable linux/amd64 manifests,
without downloading image layers or substituting another version:

| Original repository | Version |
| --- | --- |
| `docker.io/supabase/postgres` | `17.6.1.095` |
| `docker.io/supabase/gotrue` | `v2.188.1` |
| `docker.io/postgrest/postgrest` | `v14.7` |
| `docker.io/supabase/storage-api` | `v1.44.11` |
| `docker.io/library/kong` | `2.8.1` |
| `docker.io/axllent/mailpit` | `v1.22.3` |

Full index/platform/config digests and layer sizes are in
`.soleur/recovery-proposal-20261011/image-manifest.json`, SHA-256
`e48e6011aef57ddb47b0f575c6eb9ee86f0c73cf02a7544fef249fbff6b888f4`.
The proposed six explicit pulls use platform digests, never rolling tags, and
total 665,199,944 compressed layer bytes before Docker cache reuse. Unpacked
images and the exported source write additional task/cache disk data. The runner
records verified immutable RepoDigests and observed local Docker image IDs;
it does not assume a registry config digest equals Docker 29's image ID.

## Isolation, resource and failure controls

The CLI and unchanged canonical migration runner execute inside a fresh bwrap
user/network namespace with no external route. A task-owned Unix socket bridges
only to the newly created, positively identified PostgreSQL on host loopback
59052. Another private Unix socket supplies a task-local Docker API proxy.
The default Docker socket and host credentials are absent from this namespace;
the selected global Docker context is unchanged.

The proxy admits only the fresh project
`codex9051-historical-oct11-6df89c21`, its exact volumes/network and inventoried
container/exec IDs. It binds creations to admitted immutable images, stamps
ownership, forces the internal bridge and loopback publication, and sets memory,
CPU, PID and no-new-privileges controls before creation. CLI's default
`host.docker.internal:host-gateway` escape is stripped. Privileged/device/added
capability/host-namespace access, foreign resources, automatic pulls, builds and
global pruning are refused. Unsupported API contracts stop the attempt.

The internal bridge has no external route; published services use only the
reviewed loopback ports 59051–59060. PostgreSQL gets one CPU/one GiB, auxiliary
services and temporary migration jobs one CPU/512 MiB each, and renderers two
CPUs/two GiB each, with an eight GiB total admitted memory budget. Work is bounded
to 30 minutes with shorter stage limits; cleanup has a separate five-minute
budget. Source export, config, CLI home, Git snapshot, plugin seed, workspace
fixture, sockets and logs belong to the fresh attempt directory. The canonical
migration runner's temporary files/fetch are confined there/in its private tmpfs;
its detached Git snapshot has no credentialed remote or live worktree refs.

Sanitized environments exclude pooler, hosted Supabase, Doppler, Flagsmith,
Sentry, Inngest, provider and browser-account credentials. Only newly generated
local synthetic Supabase keys enter the renderer/storage flow. Original plugin
MCP configuration is omitted. Realtime, Studio, analytics, edge, image transforms
and pooler services are not started; genuine local auth/storage/API schemas are
retained, but production cron/realtime/infrastructure parity is not inferred.

Offline verification passed 18 admission-policy fixtures and seven fake-Unix
transport fixtures, including HTTP 101 exec hijack and bidirectional stdin/output,
ID registration, project-filtered reads and pull refusal, with zero Docker calls.
A separate kernel fixture proved distinct network namespace, successful synthetic
Unix/loopback echo bridge and absence of an external route; it ran no application,
database or SQL. These are harness controls, not recovery execution evidence.

## Exact proposed scenarios and attribution

The CLI initializes genuine local auth/storage service schemas. The unchanged
canonical filename-tracked migration runner then applies all 187 complete source
bodies with `--bootstrap=skip` and a content-SHA tracking bootstrap. The resulting
ledger must exactly equal every admitted filename/blob hash. No migration is
pre-marked, omitted, rewritten or downgraded; migration 145's production guard
remains active. The hosted schema-refresh helper sees no account token; schema
reload uses only the owned local PostgreSQL.

Synthetic auth users provision genuine personal workspaces through the historical
trigger. Fixture SQL supplies owner/co-member/other-tenant conversations, messages,
Codex/Claude/routine control bindings, turn attempts and protected checkpoints;
it does not replace auth helpers, application tables or production RPC definitions.
The API uploads and rereads one fixed synthetic storage object; one fixed workspace
file is retained. No routine consumer, provider process or customer traffic runs.

The initial and replacement renderers use the admitted production image/default
user, verify exact build SHA plus connected Supabase health, and stop gracefully.
Public/auth/storage table contents are compared by complete row-set fingerprints
before scenario mutations, alongside exact storage/file hashes and the retained
migration ledger. Then the original generation, owner/member/cross-tenant,
history acknowledgment and scoped engine-erasure scenarios run against the
complete schema.

A concurrent owner transaction holds the mode-change lock while an old-generation
checkpoint write waits. The controller observes the owned local
`pg_stat_activity` lock-holder before issuing the stale write; it must be rejected
after the switch commits. Two explicit synthetic switches restore API-key choice
at generation three before erasure assertions. Local WAL delta and retained row
counts are recorded. This measures isolated SQL behavior, not provider-request
admission or mode-specific live Web write counts.

On any failure, the runner stops and performs per-item positive ownership
verification before removing only its containers, volumes and network.
Final inventory must show their absence. Explicitly downloaded immutable images,
source/manifests and bounded raw logs remain; no global cache prune occurs.
Local compute and OpenAI assistant usage are separate from Soleur subscription;
Soleur disclaims runtime cost warranty.

## Acceptance criteria that this action cannot release

The frontend still has the build-only
`NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:3001` and
`NEXT_PUBLIC_SUPABASE_ANON_KEY=synthetic-build-only-not-authentication` baked in.
Runtime local JWTs and renderer health do not repair those browser assets.
Authenticated screenshots require a separately qualified auth-capable build
configuration and genuine isolated auth flow; no proxy is labeled production
authenticated evidence.

The old image has no installed Codex App Server payload or approved live
qualification/egress composition. New application fixes are not in this image.
Current-source recovery, real Codex-process recovery, full production host/
sandbox/firewall/deployment/observability parity, eligible routine execution,
permitted API-key/managed Web matrices, attributable CLO and review/promotion
therefore remain open after any passing scoped result.

No rehearsal authorization is consumed. PR remains draft and auto-merge disarmed;
Codex default-off and customer content blocked. Existing credential/provider/
browser-auth, account/shared-write, deployment and cohort restrictions persist.
Project sharing, retention/inheritance and configured regions remain unknown.
