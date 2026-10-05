---
title: "Codex Web cumulative text and offline Node 22 build"
date: 2026-10-05
source_sha: 6d67da6a9177f2fa14d5fe7222d3ce87d10f117c
pr: 9051
status: compiled-runtime-and-recovery-unqualified
---

# Current-main compilation and streaming repair

This source incorporates main
`c35116046b2542eaec70d19d18a39b7e05ac59ea` as its second parent. The merge
preserves Codex delivery/resend controls and adopts main's scoped OTP banner
helper and regression case, reasoning trail changes and vendored Inter.

## Streaming repair

Scoped integrity review traced raw `item/agentMessage/delta` fragments through
the translator, dispatch and mapper into a reducer expecting cumulative text.
Earlier source `034fabb804de2b871b2c520bff0f947941af8a1d` could replace the
answer with its latest fragment. Main's new reasoning fold would additionally
turn fragments into misleading activity entries. The audit defect was filed
as [issue 9553](https://github.com/jikig-ai/soleur/issues/9553) before repair.

`createCodexWebEventMapper()` now converts translated item deltas into
cumulative text at the Web boundary. It replaces persisted-message snapshots
without appending them and retains separate items, including identifiers with
colons. Dispatch creates one mapper per admitted turn. Native routine output
semantics are preserved. Retention is capped at 32 items and 256 KiB aggregate
UTF-8; overflow throws a content-free error before modifying retained state.
Dispatch records a failed attempt and the WebSocket handler captures the
error in Sentry. Terminal/error events clear retained text. Iterator closure
reaches adapter disposal.

Synthetic regression definitions were written before implementation. They
exercise translator → mapper → reducer, cumulative dispatch frames, replay
replacement, item/turn isolation, terminal cleanup and exact UTF-8/item
limits. Local suites were not executed at the user's direction; local TDD
red/green is not asserted. TypeScript and scoped ESLint passed. Soleur's
five custom Semgrep rules scanned four source files with zero findings and
approximately 99.9% parsed lines.

Independent integrity and user-impact reviews of pushed source found no
remaining scoped defect. The plan names lost text, false activity and visible
retention failure. This is not full-branch review, authenticated screenshot
QA or promotion approval.

## Isolated build controls

Tracked source was exported under `.soleur/`, excluding environment files
and MCP configuration. Existing dependencies were mounted read-only. The
cached compiler image reports Node `v22.23.3` and repository digest
`node@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c`.
That differs from the production Dockerfile pin
`sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d`.
Production image/dependency parity is not established.

Compiler containers use cached images only, network disabled, a read-only
root, dropped capabilities, non-root identity and `no-new-privileges`.
The environment is cleared before supplying disposable HOME, executable
PATH, telemetry disablement, synthetic Supabase placeholders and source
build identifiers. The retry additionally sets
`NODE_OPTIONS=--max-old-space-size=4096`, with two CPUs and an 8 GiB
container cap. No image/dependency installation, server startup, test suite,
database, provider/auth call or credential-value inspection was performed.

The first attempt retained under `.soleur/node22-candidate-6d67da6a-retry/`
compiled Webpack successfully, then Node's default heap failed during the
Next TypeScript phase. The retry uses a new export under
`.soleur/node22-candidate-6d67da6a-heap4096/`; the failed log remains intact.

The retry completed at `2026-10-05T18:10:50Z`. Node-version, full
`next build --webpack` (including TypeScript and route generation),
`npm run build:server` and Next-config compilation all exited zero. No font
stub or egress relaxation was used. The larger heap resolved the measured
compiler crash. Next modified only the disposable export's TypeScript
include to add `.next/dev/types/**/*.ts`.

| Product, relative to exported application | SHA-256 |
|---|---|
| `.next/BUILD_ID` | `0aff45351dd024a4caca7e6676f2daf9fabe69d51a3c3ce9edcf264e2dc08fac` |
| `.next/build-manifest.json` | `e63dc1308de46db435e618f9ee1e4bcb0a9f0a97e0433b4866cedae58d1b3d30` |
| `.next/server/app-paths-manifest.json` | `42e5dddd1451d8682be0ee34c5443686c8eaeb25efd2ebebe938640a53e7331e` |
| `dist/server/index.cjs` | `d6142674685fafaef3f9c1aa6a92b05ab012f265cb1f25a4579d707d3a558c0d` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

Next emitted existing middleware/Sentry configuration deprecations, Webpack
dynamic-import/ESM external warnings in unchanged modules and cache-size
advisories. Missing observability pepper notices reflect the deliberate
synthetic environment and fail-closed pseudonymization. Esbuild emitted its
server-bundle-size advisory. These warnings do not establish runtime parity.

## Scoped advisory data gate

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

The installed advisory path scanner examined five repair source/test paths
and matched zero regulated paths. Its corpus was last verified on
2026-09-14, 21 days before this invocation. The five mandatory v1 checks
(lawful basis, retention, erasure including caller wiring, vendor transfer
and special-category columns) found no new trigger: this repair adds no
schema, foreign key, vendor, credential or persistent storage. Text is
transient, bounded and cleared at turn termination. This narrow observation
does not resolve the branch's mode-specific legal or data-transfer gates.

## Exact-source remote checks

[CI 37352290494](https://github.com/jikig-ai/soleur/actions/runs/37352290494)
and [tenant integration 37352290431](https://github.com/jikig-ai/soleur/actions/runs/37352290431)
passed on `6d67da6a9177f2fa14d5fe7222d3ce87d10f117c`. Both Web test shards,
browser tests and the Web build passed. The PR monitor settled with 84
passing checks and six skips, including passing CLA, secret scan and quality
guards. These results attest this source SHA; the evidence commit requires
its own exact-head checks.

The retained Web shard log explicitly reports
`test/codex-ws-events.test.ts` (10 tests) and
`test/codex-conversation-dispatch.test.ts` (19 tests) passing. This is remote
regression execution, including the newly added definitions; it does not
establish a local TDD red run or an authenticated provider path.

## Qualification limits

Any successful compilation here establishes compiler output only.
Retained-schema recovery, protected-value preservation, admitted-turn
behavior, a served preview and authenticated screenshots remain unqualified.
The existing loopback database was not used because exclusivity and wholly
synthetic contents are not established. Startup would perform orphan cleanup.

API-key disposition remains PENDING without live authorization. Managed
hosted-auth remains BLOCKED pending provider-permitted integration. No real
key or deadline is recorded. Compatible recovery rehearsal, authenticated
screenshots, an eligible routine consumer, separate permitted Web matrices
and attributable mode-specific CLO dispositions remain open. Keep PR #9051
draft, Codex default-off and customer content blocked. Existing restrictions
on provider/auth calls, credential inspection, shared database/production
writes, flag/cohort changes and browser authentication reuse remain in force.
