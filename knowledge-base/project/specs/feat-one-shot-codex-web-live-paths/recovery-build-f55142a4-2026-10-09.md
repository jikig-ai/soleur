---
title: Approved offline application-image build at f55142a4
date: 2026-10-09
pr: 9051
status: offline-image-prepared-startup-and-recovery-unqualified
---

## Authorization and result

After the exact command was presented, the user replied `continue`, authorizing
one offline application-image build for source
`f55142a4cfc07e20fb2f6027184ab84819af29f2`. The approved selector was
`--authorized-one-offline-build-f55142a4`; the immutable runner SHA-256 was
`e60eb18639a7a31118338546668ff0d96f7b90e7661c718ca9f5c3ab71d7fcad`.
Its exclusive authorization marker is consumed. No retry is authorized.

The runner exited zero. All 15 recorded stages passed, from source export and
Node-version validation through dependency installs, Next/server/config
compilation, the dev-signin tripwire, runtime resolutions, plugin manifest,
unstarted image assembly and independent filesystem verification.
Execution ran from 21:21:22 to 21:35:22 UTC, about 14 minutes, within the
2,700-second work budget. The preflight found 79 GiB available disk and about
19 GiB available memory. Compilation used two CPUs, 6 GiB memory and a 4 GiB
Node heap, with network disabled and image pulls forbidden.

The local image is:

```text
tag: soleur-codex9051-recovery:f55142a4
ID: sha256:ff0253833e60b428fc9e6651ff664ea9316938f0ed5d59c2b8cef74429978e7f
source label: f55142a4cfc07e20fb2f6027184ab84819af29f2
size: 861881234 bytes
base: sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d
```

## Verification and cleanup

The assembly container remained created, never started. A read-only nested
plugin mount probe passed. A separate probe without app/plugin source mounts
matched all six runtime artifacts and the complete 1,578-file plugin manifest
inside the image. Its expected-manifest control file was mounted read-only.

| Artifact | SHA-256 |
| --- | --- |
| `package-lock.json` | `b6fb597acc1e8df40ac63390dd3b41e9376b0bd9ce4e1ec9ecd778983818536f` |
| `.next/BUILD_ID` | `4d6189db163fa4e35cb0f60eb1dc6ebc45638608870e65ab46fa4b7c407d9703` |
| `.next/build-manifest.json` | `c85403a230d2e534dbfe1134a9d043a5030e3bb9bafe8ae3dd73a0dd68588993` |
| `.next/server/app-paths-manifest.json` | `9b2a21cb16d2f9a6a579cdc34dc928a14989e1f25e642bc5420a75a6aa7f09f1` |
| `dist/server/index.cjs` | `29046dd6761c72d167a3bfaa8860dcb242647d6ab35df6ba042eaa014e3e9b49` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

The plugin manifest's canonical JSON SHA-256 is
`5fc097e207193d7196cd27f8cd78392b5fa035e2363153cf987b6cf422bce362`
(`sort_keys=True`, separators `(',', ':')`). The full local record is
`.soleur/current-source-recovery-proposal-20261009/candidate/build-record.json`,
SHA-256 `2e59bb6ad8f870c27e2b31d446b385c88b8ad64279d87ff8c5161b00852493a3`.
All 11 owned containers were removed or already removed; a final exact-prefix
inventory was empty. The source HEAD still matched the approved SHA at exit.

## Limits and warnings

This is a compiled application image. No Web app, database, SQL, provider/auth
call, customer content, browser session, recovery rehearsal, infrastructure
probe, image publication, deployment, account write or flag/cohort change ran.
The image inherits the base user configuration and has `/bin/true` as its
entrypoint; it does not supply the production runner's user/entrypoint/tool
and sandbox controls. Full production runner parity remains unqualified.

Installs used locked cached archives with `--ignore-scripts`; Next used
`--webpack` and synthetic build configuration. Production install scripts,
default build mode, global CLI/Vitest/browser/system dependencies, canary
payload, bwrap/shim/outer-wrap behavior, deploy ledgers, image scanning,
observability and the full historical Supabase/auth/storage substrate remain
outside this result. Successful compilation does not clear those gates.

Logs included existing dependency deprecations, middleware and Sentry config
deprecations, webpack cache-serialization performance warnings and a server
bundle-size annotation. The lockfile and affected configs were unchanged;
all stages exited zero. These warnings are recorded, not treated as production
dependency, future build-mode or performance qualification.

After build completion, main advanced through
`a859812e787be58aa3ee6ee3582beed1d506c0f9` with plugin merge-queue sync changes.
The application/compiler inputs were unchanged, but the full plugin manifest
changed. The image remains bound to `f55142a4`; no relabel, rebuild or startup
occurred. Current-source/full-production recovery remains unqualified.

Codex remains default-off, customer content blocked and PR #9051 draft with
auto-merge disarmed. Recovery execution and later screenshot/routine/Web/CLO/
review/promotion gates remain held. Subscription and OpenAI usage are separate
from local compute; Soleur disclaims warranty for runtime cost.
