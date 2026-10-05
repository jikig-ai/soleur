---
title: "Codex Web offline compilation candidate"
date: 2026-10-05
source_sha: fa166b66d0695f5038d996613817ca686ce49d57
pr: 9051
status: compiled-runtime-and-recovery-unqualified
---

# Offline build observation

Completed at 2026-10-05T10:34:38Z from an isolated tracked-source export of
`apps/web-platform`, `plugins/soleur` and `scripts` at the exact source SHA
above. Runtime environment files and the plugin MCP registry were excluded.
Existing dependency directories were linked; Next 16.3.6, TypeScript 5.9.3 and
esbuild 0.28.1 matched the application lockfile. No dependency installation or
source modification was required.

The build subprocess environment was cleared, then supplied only PATH,
`NEXT_TELEMETRY_DISABLED=1`, synthetic Supabase URL/key placeholders,
`BUILD_SHA` and `BUILD_VERSION=9051-offline-candidate`. No application server
was started, test suite executed, credential inspected, or database used.

| Step | Observed result |
|---|---|
| `./node_modules/.bin/next build --webpack` | Exit 0; compilation, TypeScript check and route generation completed. |
| `npm run build:server` with local executable PATH | Exit 0; custom server bundle produced. |

The host compiler ran on Node 26.10.0 and used webpack. The production Docker
file pins Node 22, and CI's default Next build does not select this alternate
bundler. No Docker runner image, production-runtime dependency set, retained
schema compatibility or recovery behavior is qualified by this observation.
Synthetic build placeholders are not authenticated preview configuration.

## Retained artifacts

The local, ignored artifact directory is
`apps/web-platform/test-results/offline-candidate-fa166b66/`. It contains
exported source, build products, separate attempt logs and
`build-record-final.json`. These local files are not committed and their
continued availability is not assumed in a fresh clone. The committed record
below preserves the bounded observation; rebuild before relying on a missing
or changed artifact.

| Artifact, relative to exported application | SHA-256 |
|---|---|
| `.next/BUILD_ID` | `a8ff94fc30cee5f5d6a2610ad47926a4eed7a7cfa9f3e75391c385a00dfe57d8` |
| `.next/build-manifest.json` | `ff899a1acf3d26bc464a23f61f1788cb1de6ed47ac093982d5d20adf3bceeb3d` |
| `.next/server/app-paths-manifest.json` | `8514cfcff59eac6c527f739ed201611d47822354a42596b9d183ea15dd261c72` |
| `dist/server/index.cjs` | `ad5312491602078620cc19f9d1b896a2eefeb7fc1528acbe5cc891b14e4d896a` |

The first sandbox attempt could not capture its TypeScript child output;
the escalated app-only export then failed because repository helper imports
were missing. Adding those exact-head support modules resolved typecheck.
The server wrapper initially omitted npm's executable PATH; the corrected
compilation passed. Prior failures remain in their separate logs. Next/Sentry
deprecation notices, optional dependency warnings and webpack cache warnings
do not establish runtime compatibility or a clean production deployment.

## Remaining recovery gate

The [migration recovery review](migration-145-recovery-review-5cb81c9d.md)
still requires a nominated exact recovery application and an exclusive
disposable synthetic database retaining mode choices, admission evidence and
the migration ledger. The running loopback Supabase stack was not verified
as exclusive or wholly synthetic and was not used. No protected-value
comparison, application replacement, authenticated screenshot, routine
consumer or provider Web matrix was exercised. Keep PR #9051 draft and Codex
default-off.
