---
title: Resynced Codex Web exact-base offline compilation
date: 2026-10-06
source_sha: 9304505dbd263a5ccf1059300d7acdffc3df7336
status: compilation-passed-runtime-unqualified
---

# Resynced source compilation

The main sync at `9304505dbd263a5ccf1059300d7acdffc3df7336` passed all four
offline steps: Node-version probe, full Next/Webpack build with TypeScript and
route validation, custom-server compilation and Next-config compilation.
The build ran from `2026-10-06T06:53:12Z` to `2026-10-06T06:58:24Z`.
The exact cached production base remains
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`,
linux/amd64, **Node v22.22.1**.

The [initial exact-base record](node22-pinned-build-696a76df.md#isolation-and-retained-evidence)
describes the unchanged isolation controls: tracked-source export without
`.env*`/MCP members, read-only cached dependencies, no network/pull/download,
empty inherited environment with synthetic build configuration, non-root
containers with dropped capabilities and a read-only filesystem, two CPUs,
4096 MiB Node heap and 8 GiB container memory. No suite, runtime, database,
credential inspection or provider/auth request ran.

Raw local evidence is retained in
`.soleur/pinned-compiler-resync-9304505d-20261006T065308Z-3785833/`, including
`build-record.json`, exported source and four step logs. The new wrapper is
`/tmp/codex9051-pinned-930450-build.py`; prior evidence is preserved. A filtered
post-build Docker listing confirmed no task compiler containers remain.

| Artifact | SHA-256 |
|---|---|
| `.next/BUILD_ID` | `67435c25f79acd53683f0aa6dd1b0b92853ff353ede18cb22072b5a088635b10` |
| `.next/build-manifest.json` | `d9134bb5960e9623c1612c41f877a7d30f2d9efb16861a4beb2cec73f4d8455a` |
| `.next/server/app-paths-manifest.json` | `4cc82ff916dc47144588803c340a8d5989cb18a0e1eff7f126a7bb442cc2c508` |
| `dist/server/index.cjs` | `6cd5c64f3a7d0bbf59671173639a7b732f16de63831d6560fa684fc385e1ba95` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

Existing Sentry/middleware deprecations, Webpack cache-size and dependency
ESM/Edge API advisories, deliberate synthetic missing-pepper notices and the
server bundle-size advisory remain. Next modified only the disposable export's
TypeScript include. Config compilation emitted no warning.

Exact base parity and compilation are established; production runner dependency
and global-tool parity, retained-schema application recovery, authenticated
preview/screenshots and routine execution remain unqualified. The subsequent
main documentation merge and evidence/plan edits do not change the compiled
application/plugin/script sources. This is not whole-tree build reproducibility
or runtime qualification. PR #9051 remains draft, Codex default-off and customer
content blocked; local suites remain skipped at the user's direction.
