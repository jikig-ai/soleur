---
title: Codex Web locked-dependency recovery candidate build
date: 2026-10-06
source_sha: 845d1455d55b76754c2cd4f3c9804a1f7d6888a1
pr: 9051
status: isolated-app-build-passed-runner-unqualified
---

# Locked-dependency recovery candidate build

The isolated build compiled the application and production runtime dependencies
at source `845d1455d55b76754c2cd4f3c9804a1f7d6888a1`. The Node 22.22.1 image
matched the app Dockerfile's pinned base digest:
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`.
Build and runtime dependency installation used the committed lockfile and
offline npm cache. No credential files were copied, no network was available,
and no image was published or deployed.

The builder copied 1,220 eligible npm tarballs after verifying their lockfile
integrity hashes. `npm ci` ran with `--offline --ignore-scripts --no-audit
--no-fund`; six unavailable optional WASM packages were not needed by the
successful Linux x64 build. The same controls installed production runtime
dependencies separately with `--omit=dev --ignore-scripts`. Consequently this
does not validate install scripts or production global CLI, browser, system
dependency and runner-image assembly.

All eight bounded build steps exited zero: Node version, locked builder
dependencies, Next/Webpack build, development-sign-in tripwire, custom server
compile, Next config compile, locked production runtime dependencies, and
runtime resolution. The runtime check resolved `pdfjs-dist`, loaded native
Sharp, and reported SDK `0.3.284` from the lockfile. No local test suite ran.

| Artifact | SHA-256 |
|---|---|
| `package-lock.json` | `1e553e0b02f50bab07613dc9a9789e570b08da503fb576a19518f7be524099a9` |
| `.next/BUILD_ID` | `ebc2db9a13b3381634c7f3b8ffab569878c5caf38edc77ac4802b5ba728aa3e3` |
| `.next/build-manifest.json` | `a99b6fc91c8efd62e9cf4c8e38f1a81a421dde8130a5bdd0abc55f4025b67b2d` |
| `.next/server/app-paths-manifest.json` | `0014345616bde7dbb0f188c2b60a3b53e1ff59eb4097a41c98b24ac7b0052783` |
| `dist/server/index.cjs` | `2b5e5982a2f77732e0b16456be2baeb1444436fa5018d619f106a86c3f30a03f` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

The subsequent [isolated recovery attempt](recovery-readiness-2026-10-06.md#isolated-rehearsal-attempt-incomplete)
applied the scoped SQL closure but stopped at a container-network metadata
assertion before application startup. This record proves compilation only;
it does not qualify retained-schema recovery, runtime behavior, authenticated
Web paths or production runner parity. The source export, build logs and
machine-readable record remain in the task-owned ignored `.soleur/` scratch
directory and are not required to verify the hashes above.
