---
title: Approved production-Dockerfile candidate at a2ff13ca
date: 2026-10-10
pr: 9051
status: candidate-prepared-startup-and-recovery-unqualified
---

## Authorization and result

The user replied `continue` after the exact command and its download/install,
privileged builder, resource and filesystem-only scope were presented. This
authorized one build at `a2ff13ca8d567b30db1afd261c0ad31d51442a9a`, with runner
SHA-256 `bc240a5ebcaa1d3179d4d036eb0223e54e9c2e7ece98d4f5b74557030d39e9c3`.
The exclusive marker is consumed. No retry, rebuild or startup is authorized.
The [proposal](production-image-proposal-2026-10-10.md) preserves admitted scope.

The prerequisite exact-source CI passed: CI `38084153918` and its required
test aggregate, tenant `38084153892` and its required aggregate, RLS
`38084153889`, and final description guards `38084195005` all succeeded.
All 25 required checks were actual SUCCESS. The watch exited zero with
85 passes, seven skips and zero failures, effective cancellations or pending.
RLS applied 186 migrations with zero skipped and passed 11 files / 153 tests;
production catalog parity was skipped.

The runner exited zero after eight recorded stages, including cleanup.
Execution ran from 21:20:52 to 21:31:32 UTC, 10 minutes 40 seconds, within the
75-minute work budget. Two CPUs and 6 GiB builder memory were verified;
Next used a 4 GiB heap. All four compiler/tripwire stages used network none.
Public install/download stages used the admitted network and ordinary scripts,
synthetic build configuration, sanitized environment and empty Docker config.

```text
tag: soleur-codex9051-production-candidate:a2ff13ca8d56
image ID: sha256:a725576ec0b909cc8815f097bf61fa0261b93fa0dfed65511088bef6ff3ff3ef
size: 2465036946 bytes
source label: a2ff13ca8d567b30db1afd261c0ad31d51442a9a
base: node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d
BuildKit image ID: sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea
```

## Admission and cleanup

The production image configuration retains user `soleur` and default command
`node dist/server/index.cjs`. A network-none, read-only root filesystem
inventory verified all 1,345 expected filtered plugin files, their hashes and
four contained fixture symlinks against the pinned export. Plugin-root MCP
configuration is absent. Required manifests and go entrypoints are present.
A separate network-none Node probe verified default UID 1001.

Global package metadata matched Claude Code 2.1.293, LikeC4 1.50.0 and Vitest
4.1.11. GitHub CLI's requested 2.96.0 was unavailable; the existing Dockerfile
fallback installed 2.102.0. Browser payload directories include Chromium 1224,
headless shell 1224 and FFmpeg 1011. Root metadata inspection does not qualify
browser execution as the default user. The production Dockerfile's final
zero-file-capability audit passed; no sandbox/isolation replay ran.

| Runtime artifact | SHA-256 |
| --- | --- |
| `package-lock.json` | `b6fb597acc1e8df40ac63390dd3b41e9376b0bd9ce4e1ec9ecd778983818536f` |
| `.next/BUILD_ID` | `8d74f3e20625834e1bf9face530b3fdfda8ec49d018f1014ad1586c36ba5f555` |
| `.next/build-manifest.json` | `6e87075778608eb4cb485b79433a113e75670caa8ab51622be8c87c5ba80380c` |
| `.next/server/app-paths-manifest.json` | `7049998711263a0e8b1073c4dfad0def1ed1036a7cf5308b03b6ec71dcb81da9` |
| `dist/server/index.cjs` | `29046dd6761c72d167a3bfaa8860dcb242647d6ab35df6ba042eaa014e3e9b49` |
| `next.config.mjs` | `4193cf79644c87e3c17bf0687d2a2e5c4908141052621bb60e190a310c442429` |

Seven additional canary/config/shim/filter source artifacts also matched the
export. The complete inventory is in the local record below. The canonical
plugin hash manifest SHA-256 is
`adad1c0fab5241034d53c9ebac8c73c75f054caade179b7f3ec39bf4849a1b67`
(`sort_keys=True`, separators `(',', ':')`). The 4,928-entry Git input manifest
SHA-256 is `27acdea2ad3347571f05766b68ce45fd100ed6f0f8a4466b8b2f7e5013a7e432`.

Both named probes, dedicated builder `codex9051-prod-a2ff13ca8d56-1139998`
and its exact cache volume were removed. Independent read-only inventory
confirmed their absence and the retained image ID/user/command/source label.
No global prune or unrelated resource removal ran. The final local record is
`.soleur/production-image-proposal-20261010/candidate-a2ff13ca8d56/build-record.json`,
SHA-256 `3bdc192922f611c36147e9c6e2c5ec7f5defd1a5830516f112442f8cc59b5ca9`.
Its inherited `container_actions: 0` is a preview field, not an execution
counter; recorded stages show the builder and two probe container actions.

## Warnings, source binding and held gates

Next 16.3.6's default Turbopack build passed with 28 warnings: the ESM Claude
Agent SDK could not be externalized, a dynamic subprocess path in
`_cron-claude-eval-substrate.ts` could not be statically resolved, and 26
dynamic-filesystem calls required whole-project tracing. Sentry `disableLogger`
and middleware convention deprecations also appeared. These are recorded
runtime/tracing limits, not resolved by successful compilation. Next adjusted
the exported scratch tsconfig include list; the tracked worktree stayed clean.

npm reported 17 audit entries for the full install (1 low, 5 moderate, 11 high)
and 11 for the runtime install (1 low, 4 moderate, 6 high), plus existing package
deprecations. The app lockfile is unchanged from the prior offline build.
Read-only GitHub inspection confirmed existing open Dependabot alerts for that
manifest, including [Next](https://github.com/jikig-ai/soleur/security/dependabot/278),
[MCP SDK](https://github.com/jikig-ai/soleur/security/dependabot/276) and
[sharp](https://github.com/jikig-ai/soleur/security/dependabot/275).
Those alerts and npm's summaries use different counting units; their totals
are not asserted equivalent. No audit fix, dependency update or vulnerability
qualification occurred.

Main advanced during execution through `3ef5aa6e12c3f3c35db84d828441907cb6358646`,
adding GitHub webhook draft-CI handling and changing baked plugin inputs.
The image remains bound to `a2ff13ca8d`; it is not current-source parity after
that sync. No relabel, rebuild or consumed runner repinning is permitted.

A further main advance through `149a5d3b4e10c1b62232004035185fd8ce66a87c`
adds open-web-egress runtime/gateway wiring, Dockerfile payload changes,
compiler configuration and migration 158. This changes app, image and retained
schema inputs again. At that sync, the 30 selected fixture files were unchanged,
but imported implementations and tsconfig changed; their earlier 321 passes
could not qualify the resulting source. The subsequent corrected selected
suite passed at `ce2be17417`, recorded in the session artifact. Legal conflicts
were resolved by keeping
both the Codex and web-access disclosures and regenerating canonical hashes.
Source-only inspection found a forwarder payload/default-path mismatch in
main, tracked by [Ref #9952](https://github.com/jikig-ai/soleur/issues/9952).
No runtime failure was observed, and no payload correction or rebuild ran.

Main through `5da9ad060e1c12037f17785971184c0630b98c93` also bakes the
soleur-owned `node_modules/.vite-temp` target for Vitest's ESM config loader.
The approved image predates that ownership contract and cannot qualify the
current canary. No selected test or its normal imported source changed in
this last delta; no further selected-suite rerun was warranted for it.

No application startup, database/SQL, provider/auth/customer call, browser
session, recovery rehearsal, deploy script, shared infrastructure write, image
publication or flag/cohort change ran. Current-source/full-production recovery,
retained Supabase/auth/storage/cron substrate, replacement and observability
qualification remain incomplete. Authenticated screenshots, eligible routine
consumer, permitted mode-specific Web matrices and attributable CLO, full
review and promotion remain held. Codex stays default-off/customer content
blocked, PR #9051 draft, and auto-merge disarmed. API-key mode remains PENDING;
managed hosted-auth remains BLOCKED. Soleur subscription and OpenAI usage are
separate from local compute; Soleur disclaims warranty for runtime cost.
