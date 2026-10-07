---
title: Source-current offline recovery image preparation
date: 2026-10-07
source_sha: 66f424cb0a592a54ea33d12cc64a1cbbd627e8c6
pr: 9051
status: local-image-prepared-startup-and-recovery-unqualified
---

# Source-current offline recovery image preparation

This is preparation for a possible newly authorized synthetic rehearsal.
It grants no permission to repeat either historical recovery attempt. No Web
application process, database, OpenAI auth service or provider request has run during
this preparation. Local application test suites remain held.

## Build boundary

The app and plugin were exported from the exact source revision above. The
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
a complete synthetic record and rejected 20 incomplete variants, including
each omitted build step and artifact. This executed only the admission
statements; it did not execute the rehearsal runner or an application suite.

The synthetic SQL fixture manifest identifies all 185 forward migration files.
The 13 selected bodies (138, 141, 142, 143 and Codex/engine 144–152) were checked
byte-for-byte against this source; the other 172 are not applied. Base tables,
auth claims and membership helpers remain synthetic. Static generation and
hash checking executed no SQL and establish no full-history or real-auth parity.

If separately authorized, the one-use command is:

```bash
python3 .soleur/current-source-recovery-66f424cb/recovery-run.py --authorized-one-synthetic-rehearsal-66f424cb
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
`e2eb8fa33505bde385c2a1f8157dd08cb0d0db6c810fbde63878f3c45f3b0488`.
No `recovery-record.json` exists for this source-current candidate; the command
above has not run. Authorization for offline preparation does not authorize it.

## Remaining qualification

Local image preparation passed. Connected startup, application recovery and
post-state scenarios have not run. Full
production runner parity, concurrency, authenticated screenshots, an eligible
routine consumer, separate permitted Web matrices, attributable mode-specific
CLO dispositions, full-branch review and promotion remain unqualified.
Keep PR #9051 draft, Codex default-off and customer content blocked.
