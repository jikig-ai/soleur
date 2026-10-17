---
title: Exact production Node base offline compilation
date: 2026-10-06
source_sha: 696a76dfb04726b68dfaa4d9edd87c328270fa87
status: compilation-passed-runtime-unqualified
---

# Exact production Node base offline compilation

The tracked source at `696a76dfb04726b68dfaa4d9edd87c328270fa87` passed
offline Next/Webpack compilation, Next TypeScript and route validation,
custom-server compilation and Next-config compilation. All four recorded
steps, including the Node version probe, exited zero. The build started at
`2026-10-06T06:37:03Z` and finished at `2026-10-06T06:40:30Z`.

The locally cached linux/amd64 image was selected by full content ID:
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`.
Its repository digest matches the production Dockerfile's base pin. The
version probe returned **Node v22.22.1**. This resolves the base-image mismatch
in the [earlier compilation record](node22-build-6d67da6a.md); it does not
establish production runner, dependency-install or tool parity.

## Isolation and retained evidence

The wrapper exported only tracked application, plugin and script files from
the source commit. Three `.env*`/MCP members were excluded. Existing dependency
trees were mounted read-only; no install, image pull or package download ran.
Each disposable container used `--network none`, a read-only root filesystem,
dropped capabilities, no-new-privileges, the task user's UID/GID, two CPUs,
8 GiB memory and a bounded `/tmp` tmpfs. Next used a 4096 MiB Node heap.

An empty inherited environment was replaced with an explicit allowlist of
PATH/HOME, build identity, telemetry-off, heap size and synthetic Supabase
build placeholders. No application runtime, database, test suite, provider
request or authenticated account inspection ran. The export's Next-generated
TypeScript include change stayed inside the disposable source tree.

Local raw evidence is retained under
`.soleur/pinned-compiler-696a76df-20261006T063701Z-2342781/`: source archive,
source export, `build-record.json`, `node-version.log`, `next.log`, `server.log`
and `next-config.log`. The build wrapper is the task-specific
`/tmp/codex9051-pinned-696a76-build.py`. Raw build products are ignored and are
not committed; this document retains the source identity, controls and hashes.

## Artifact hashes

| Artifact in exported application | SHA-256 |
|---|---|
| `.next/BUILD_ID` | `0f4ed0c65c072ebc31e7776a22de7e69192f6be12e16f1c6c26155cfc258bbce` |
| `.next/build-manifest.json` | `8734876a1027693077fb3270fa28e94dbfaa5f4ff382ab15394da8df0f8ea911` |
| `.next/server/app-paths-manifest.json` | `92f8a661b1e0870606024c9dc6a082eb83897ddb13e1b86b5164ee3808b7f04a` |
| `dist/server/index.cjs` | `d6142674685fafaef3f9c1aa6a92b05ab012f265cb1f25a4579d707d3a558c0d` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

## Warnings and qualification limits

Next reported the existing Sentry `disableLogger` and client-config
deprecations, the middleware-to-proxy convention deprecation, dependency
dynamic-import warnings, the Claude Agent SDK ESM-import advisory, and
Edge-runtime `process.cwd`/`process.features` warnings.
Synthetic/missing build configuration advisories and esbuild bundle-size
output are not runtime observations. These warning classes also appeared in
the earlier compilation evidence; the successful exit is not a warning-free
claim.

The production base pin now matches, but this is **offline compilation only**.
The build uses cached dependencies and Webpack rather than claiming full
production image construction. No retained-schema recovery rehearsal,
authenticated preview/screenshots or routine-consumer execution is qualified.
The existing loopback database has no established task exclusivity or wholly
synthesized contents and was not used. Retained migrations and admission
evidence must be preserved for a separately authorized recovery rehearsal.

PR #9051 remains draft, Codex default-off and customer content blocked. Local
suites remain skipped at the user's direction. No live provider permission,
credential availability or execution deadline follows from compilation.
