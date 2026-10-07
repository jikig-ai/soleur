---
title: Source-current offline recovery image preparation
date: 2026-10-07
compiled_source_sha: 66f424cb0a592a54ea33d12cc64a1cbbd627e8c6
candidate_source_sha: 27c04a95ca007813847a17e4c765dc37e2d0aeb6
pr: 9051
status: scoped-synthetic-startup-restart-and-retained-state-passed
---

# Source-current offline recovery image preparation

This is preparation for a possible newly authorized synthetic rehearsal.
It grants no permission to repeat either historical recovery attempt. No Web
application process, database, OpenAI auth service or provider request has run during
this preparation. Local application test suites remain held.

## Build boundary

The initial app and plugin export used the compiled source revision above. The
resync section below records the refreshed plugin source. The
root helper imported by a test included in Next's typecheck was subsequently
exported unchanged from the same revision. The
[preparation learning](../../learnings/workflow-patterns/2026-10-07-isolated-build-export-must-include-root-typecheck-imports.md)
records the missing-helper failure and corrected export. The failed record
was preserved separately; it was not a repository build failure.

The cached Node 22.22.1 base image is
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`.
Builder containers use network `none`, a read-only root, no added capabilities,
no new privileges, the host's non-root user, two CPUs, a 6 GiB memory limit,
a 4 GiB Node heap and a 512 MiB temporary filesystem. An empty environment
receives only local build paths, disabled Next telemetry and dummy synthetic
public Supabase values. No credential files are mounted or read.

Locked builder installation uses `npm ci --offline --ignore-scripts --no-audit
--no-fund`; runtime installation adds `--omit=dev`. The cache contains 1,357
integrity-verified eligible archives. Six unavailable optional WASM archives
remain excluded for this Linux x64 candidate. Install scripts, global CLI tools,
browser/system dependencies and full production runner assembly are unqualified.

The corrected build passed compilation, TypeScript and 92-page generation but
its 480-second wrapper deadline expired during trace collection. Its owned
container was removed. That incomplete record is preserved. The subsequent
preparation run used a 1,200-second compile deadline and passed the complete
Next build, development-sign-in tripwire, server/config compilation, locked
runtime installation and native module resolution. No deadline interruption
is treated as a runner crash or successful build.

Required stages are Node version, locked builder dependencies, full Next
Webpack build/typecheck/routes, development-sign-in tripwire, custom server,
Next config, locked runtime dependencies, native runtime module resolution,
local image assembly, read-only nested plugin mount preflight and independent
image-artifact verification. All eleven stages passed. The image source label
matches the exported revision; all six hashes match both the runtime bind source
and the image's own files.

| Artifact | SHA-256 |
|---|---|
| `package-lock.json` | `c5dc6a055b2c1d69c37212d5d3f100542adf058e79080bc8cc9709e8da1e813e` |
| `.next/BUILD_ID` | `e91148bb2edc8655cd873edc669a89b9773c83e24f7903407b6cbcc91a695bfc` |
| `.next/build-manifest.json` | `30c460adf2673eb22d3b569ac9504a903ac8aa57ed369afabad4fd416f0a3730` |
| `.next/server/app-paths-manifest.json` | `8084b26193db34226eaffead245d64a7aa939369fef020563be4fd8a1d417bfd` |
| `dist/server/index.cjs` | `2fb26fbecd008c20ead3c0e55de733e6883b1829ba700af6960a1d608339d21b` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

## Local image assembly correction

The first image assembly failed: BuildKit interpreted the raw image ID in
`FROM sha256:<ID>` as a registry tag and attempted host-side registry metadata
resolution. Container/build-step network isolation and `--pull=false` did not
prevent that lookup. It failed before image assembly; no OpenAI auth/provider
call or application startup occurred. The failed record is retained separately.

The corrected method uses `docker create --pull never` with the verified local
base ID, copies the payload, and commits the container locally. Before commit,
its state must be `created`, not running, with a zero start timestamp. The
assembly container is never started. The read-only mount probe is separate
and uses `--pull never` with network `none`. This distinguishes offline app
compilation and corrected local assembly from the failed builder's lookup.

The first local commit exceeded its 180-second client deadline for the 3.5 GiB
payload. No candidate image was visible on readback, and the unstarted container
was removed. Its incomplete record is preserved. The subsequent local assembly
revalidates the same payload, uses a fresh owned container and allows 600 seconds
for copy and 900 seconds for commit. No application or recovery retry is involved.

The corrected local commit completed on 2026-10-07. Its local image ID is
`sha256:87a268fc5a223e294e926c5b41f5f80eb778096bda0744bc8a7c12f6635fbcf9`.
The assembly state proved it had never been started. Both filesystem probes
passed, and a task-prefix container inventory was empty after teardown.

Existing Next/Sentry deprecation and Edge-import warnings, npm dependency
deprecation notices, Webpack cache advice and the synthetic missing-pepper
sentinel were inspected. They remain qualification limitations; the synthetic
build intentionally has no real observability credential or user data.

## Mountpoint and rehearsal admission

The local image and runtime bind source both contain `/app/shared/plugins/soleur`.
A filesystem-only Node probe verified the nested read-only plugin mount and
server artifact. A second probe checked image contents without runtime binds.
Neither probe starts a Web app or database. The candidate is local only; it is
neither pushed nor deployed. These probes resolve the previous mountpoint
preparation failure; they do not establish connected application startup.

The prepared rehearsal refuses missing or failed build stages, incomplete
image results, missing artifact names, image/source-label mismatches and changes
to app/plugin/build source after compilation. A static admission check accepted
a complete synthetic record and rejected 21 incomplete variants, including
each omitted build step and artifact. This executed only the admission
statements; it did not execute the rehearsal runner or an application suite.

The synthetic SQL fixture manifest identifies all 185 forward migration files.
The 13 selected bodies (138, 141, 142, 143 and Codex/engine 144–152) were checked
byte-for-byte against this source; the other 172 are not applied. Base tables,
auth claims and membership helpers remain synthetic. Static generation and
hash checking executed no SQL and establish no full-history or real-auth parity.

If separately authorized, the one-use command is:

```bash
python3 .soleur/current-source-recovery-66f424cb/recovery-run.py --authorized-one-synthetic-rehearsal-27c04a95
```

The script and raw records are task-owned ignored scratch, not committed
tooling or evidence of execution. Its proposed scope is an exclusively owned,
network-disabled synthetic PostgreSQL database, local PostgREST/proxy, connected
candidate startup and graceful stop, same-candidate replacement/restart,
exact pre/post retained-state comparison, stale-generation/tenant/erasure
scenarios and removal of every task-owned container. No shared database,
published port, provider/auth call, real credential, flag or cohort is involved.
It stops on the first failure and has no automatic retry permission.

The prepared rehearsal script's SHA-256 is
`1847a52487434481101985595774c59169a697fe64b89352613b5189679a972e`.
No `recovery-record.json` exists for this source-current candidate; the command
above has not run. Authorization for offline preparation does not authorize it.

## Main resync and current candidate

Main advanced to `db99f2a261a3517879012955bebd4c0e719f34f7` during preparation.
It merged cleanly as `387e36f75d730c1b8283c245d76263241412dff3`. Git comparisons
prove app, root scripts/compiler helper, workflows and dependency files are
byte-identical to compiled source `66f424cb`. The only plugin changes are
`commands/go.md` and `test/go-session-gates.test.sh`. Recompiling unchanged app
source is unnecessary; the compiled source SHA remains distinct from the
candidate's refreshed plugin source SHA.

Both plugin files were exported from the merged revision and copied into a
small local layer over the initial prepared image. Its assembly container was
never started. That first resynced image ID is
`sha256:a3b7c93d6500b48967b8d71e8d2087de64a849cff455a6e589745d519df92ae2`;
its source label is the merged revision. A fresh read-only plugin mount passed.
Independent image verification matched all six unchanged app hashes and both
plugin hashes. All task-owned overlay/probe containers were removed. The
original build record is preserved separately from this resync.

| Updated plugin file | SHA-256 |
|---|---|
| `commands/go.md` | `46afb1627816f99af67d24b86a89ee68d2c12c9b2c9aa83540ccbd0bcf081e1a` |
| `test/go-session-gates.test.sh` | `78784f5d1bbce5678a4321b6ed11ea3f52c9e243a9695105dfc82ea264cef2c8` |

The current admission guard requires twelve successful named stages, including
the plugin overlay and fresh image verification. Its 21 incomplete variants
were refused. The 13-body/185-file SQL manifest was regenerated statically for
the merged revision; no SQL ran. The scratch directory retains the original
compiled SHA in its name, while the command's authorization selector identifies
the current candidate revision. No prior recovery authorization transfers to it.

### Current renderer/plugin candidate after infrastructure main sync

Main advanced again to `a0359450dddb6640144c712c231fab3e4aaceff4` and merged as
`27c04a95ca007813847a17e4c765dc37e2d0aeb6`. Its four app changes are the
`cron-egress-enforce-probe` and `web-private-nic-guard` shell scripts and their
shell tests. Git proves every other app file, the root compiler helper,
dependency files and workflows unchanged from compiled `66f424cb`. These four
files are not inputs to this isolated Node renderer build. The two production
guard scripts are re-included by the production Docker context; this rehearsal
image does not include or qualify them. Root lint-fixture/baseline changes also
remain outside the compiler-input proof. Full runner/infrastructure parity is
still unqualified.

The changed `skills/work/SKILL.md` was exported from merged `27c04a95` into a
small local layer. The latest candidate image is
`sha256:09a90a42a30f5d4f6c7fe335e027da6dbe6e773cf6bd41e922a0e2b6c564ba17`,
with source label `27c04a95ca007813847a17e4c765dc37e2d0aeb6`. Its new skill hash
is `8db881c6f52888e1d943db11dcd8db33d5c50d7fcc3992ba57de19dff721fcfa`.
All six renderer artifact hashes and all three refreshed plugin hashes matched
in a fresh image probe, and read-only plugin binding passed. The assembly
container never started; all preparation containers were removed. All twelve
required stages pass. Static SQL generation now identifies merged `27c04a95`;
no SQL, app startup or recovery scenario ran. The command above is the current
one-use proposal and still requires explicit new authorization.

## Remaining qualification

Local image preparation passed. Connected startup, application recovery and
post-state scenarios have not run. Full
production runner parity, concurrency, authenticated screenshots, an eligible
routine consumer, separate permitted Web matrices, attributable mode-specific
CLO dispositions, full-branch review and promotion remain unqualified.
Keep PR #9051 draft, Codex default-off and customer content blocked.

## Separately authorized rehearsal — 2026-10-07

After reviewing this candidate, the user explicitly answered “Authorize one
synthetic rehearsal.” The exact one-use command above ran once with script
SHA-256 `1847a52487434481101985595774c59169a697fe64b89352613b5189679a972e`.
Candidate source was `27c04a95ca007813847a17e4c765dc37e2d0aeb6`, observed repository
head `aeedc0ced9dfdf2d40e0fd312a3c3d85ffd05efa`, and renderer/plugin image
`sha256:09a90a42a30f5d4f6c7fe335e027da6dbe6e773cf6bd41e922a0e2b6c564ba17`.
Runtime/build source comparison and the six recorded artifact hashes passed
admission. The preceding preparation and proposal sections remain historical;
their statements that no rehearsal had run precede this authorization.

The rehearsal ran from 11:11:34 to 11:12:03 UTC. Every recorded step exited zero:
fresh synthetic database creation, the 13-body scoped migration/setup assertions,
initial snapshot, connected health for both initial and replacement instances,
both graceful stops and process exits, exact retained-state comparison, final
snapshot, scenario SQL and result ledger. Neither process was OOM-killed.
Both health responses identified this candidate SHA and `supabase: connected`.
The replacement uses identical hard-linked renderer artifacts; no earlier
release, provider turn or restoration of a live Codex process was exercised.

The pre/post snapshots have identical SHA-256
`78c923b0f9930ff03ab09ed757da836a62b2e3eee042bb0f09aa1fdc4d535cc6`.
The SQL equality assertion covers the fixture's settings, attempt IDs,
accepted timestamps, checkpoints, memberships and migration ledger. Subsequent
SQL proved stale admission/checkpoint/lifecycle refusal, completion of an already
admitted old generation, current-generation positive controls, duplicate-attempt
refusal, owner/member and cross-tenant fences, and erasure with the other tenant
and migration ledger retained. Synthetic claim helpers and sequential SQL do not
qualify real authentication, the full 185-file migration history or concurrency.

Four traced application fetches used only `127.0.0.1:3001/rest/v1/`: startup
conversation housekeeping and database health reads. No prohibited fetch was
observed. PostgreSQL used network `none`; the other four containers shared its
isolated namespace, with no published ports, read-only roots, dropped
capabilities and no new privileges. All five owned containers were confirmed
removed in the record and by an empty exact-prefix Docker inventory. No real
credential, OpenAI provider/auth call, shared database/production write, flag
change, customer content or browser-auth copy was involved. The one-use
authorization is consumed; the runner now refuses another invocation.

The raw record and bounded logs remain in ignored task scratch
`.soleur/current-source-recovery-66f424cb/`. The final record's SHA-256 is
`d95068fdeed30e1cdecb443010fde7187eee4a8fec29019cf3214b77922e17c3`.
This tracked result does not publish synthetic JWTs, raw account screenshots
or credential-bearing environment values.

Application warnings/errors were inspected: the empty synthetic workspace
fails its populated-workspace check; absent host identity disarms watchdog
dispatch; git replication, proxy TLS and Sentry are unconfigured; agent sandbox
shim/BPF and LikeC4 self-probes fail because those tools are absent from this
renderer image. The missing-pepper sentinel and Sentry configuration deprecation
also remain visible. These intentionally incomplete synthetic fixtures do not
establish production readiness or a production incident. Connected renderer
startup and scoped retained-state/RPC recovery passed; full runner/tool/infra,
workspace readiness and observability parity remain unqualified. Local suites,
authenticated screenshots, routine eligibility, permitted Web matrices,
attributable mode-specific CLO dispositions, full review and promotion stay held.

## Post-rehearsal main sync

Main `8bcbe0379aeddaec86d51e084276e643d1d84bd8` merged cleanly after the
rehearsal, including API provider validation, cost-accounting source and Cursor
adapter/plugin changes. This changes application and plugin bytes from the
rehearsed `27c04a95` candidate. Its successful result remains source-bound;
the local image does not qualify the subsequently merged runtime. No rebuild
or second rehearsal ran, and the consumed authorization does not permit one.
All later qualification holds remain. The 13 selected migration bodies are
unchanged by this sync; that does not extend the renderer startup verdict.
