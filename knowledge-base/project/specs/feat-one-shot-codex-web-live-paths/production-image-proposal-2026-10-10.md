---
title: Fresh production-Dockerfile candidate build proposal
date: 2026-10-10
pr: 9051
status: executed-once-candidate-prepared-startup-and-recovery-unqualified
---

## Current source and admission

The user approved the exact source/digest-bound command with `continue`.
After all 25 required checks passed at `a2ff13ca8d`, the build ran once and
passed. The exclusive authorization marker is consumed; no retry is authorized.
See [the executed build result](production-image-build-a2ff13ca-2026-10-10.md)
for immutable provenance, admission checks, cleanup and qualification limits.
The proposal below records the scope admitted before execution.

Main through `df1891cbbb7cb32a20e1c5c0bf2403b4b2a2f6cf` merged cleanly at
`dc506ba2e0f8344317ac59c46928dac154f58674`. Application implementation,
compiler/dependency inputs, normal Vitest configuration and the previously
authorized 30-file fixture set are unchanged. Their 321-test result remains
source-bound to `c15572e48`; no expanded local suite ran.

Main changes the standalone canary configuration, adds bounded canary failure
diagnostics, and records arm-F elevation as indefinitely dropped with the
outer-wrap flag off. Source inspection is not deployed isolation qualification.
The existing `f55142a4` offline prototype does not contain these updated plugin
and canary contracts. Its build and the historical `27c04a95` rehearsal are
both consumed one-use actions; neither runner may be repinned or retried.

A fresh execution artifact is prepared at
`.soleur/production-image-proposal-20261010/prepare.py`. Its preview passed:
4,928 tracked app/plugin inputs, contained fixture symlinks admitted by bounded
Git target traversal, no private-key-shaped files, and only the public numeric
release-age npm setting. No source export, download, container action,
application startup, SQL or authorization consumption occurred.

The reviewed original Dockerfile SHA-256 is
`29f77331e70fcab879ad4352d98209feb4fae542a7f7874bc9b061ead0a9607c`.
The controlled Dockerfile SHA-256 is
`75d7f4206e3bb1ae27cfc37f9a8300ed6a5e8565ee896344663f7e7da08b58a0`.
Four controlled RUN lines disable networking for Next, the development-sign-in
tripwire, the server compiler and the config compiler. Next also disables
telemetry and uses a 4 GiB Node heap. These controls preserve the default Next
build mode, ordinary npm install scripts and all production runner stages.

## Exact proposed action

One fresh local production-Dockerfile candidate build, with full source SHA and
runner SHA-256 supplied in the reviewed approval command. The runner verifies
both, refuses a dirty tracked tree or changed head, and consumes an exclusive
marker before staging or Docker/network actions. A failed or interrupted run
does not authorize retry. Documentation evidence is committed first; the final
approval command binds the resulting exact head.
Exact owned container/volume names and the candidate image tag must be absent;
the builder configuration is fresh and private to this attempt.

The action exports pinned tracked app/plugin source into fresh disk-backed
scratch, reproduces the release vendor step including removal of plugin-root
`.mcp.json`, and uses a dedicated BuildKit builder without changing the selected
default builder. It loads a local image and never pushes it or exports a shared
cache. Its source label and build SHA identify the approved source.

Unlike the previous offline compile, this needs **new explicit authorization
for public image/package/browser downloads and ordinary install scripts**.
The production stages install Claude Code, LikeC4, Vitest, apt/system tools,
GitHub CLI and Chromium. The engine-managed BuildKit container is privileged;
its network has no enforced destination allowlist. There are no provider
credentials or private Docker/npm configuration. The compiler and filesystem
probes use network none; synthetic public build values and an empty Docker
configuration replace actual account settings. No provider session, browser
session or customer content is supplied.

The BuildKit resource controls are two CPUs and 6 GiB memory/swap total,
with a 75-minute work deadline, shorter stage limits and separately bounded
cleanup. Preflight requires at least 40 GiB free disk; installs and image/cache
assembly can write several GiB. These driver options are documented in
[Docker's container-driver reference](https://docs.docker.com/build/builders/drivers/docker-container/).
Local compute is separate from Soleur subscription and OpenAI assistant usage;
Soleur disclaims warranty for runtime cost.

## Verification and cleanup

After a successful build, admission checks the production `soleur` user,
default server command, source label and image ID. Network-none read-only
filesystem probes inventory runtime hashes, baked canary/shim/filter artifacts,
global package versions, contained plugin hashes/symlinks and browser payload
directories. The plugin file set must equal the source set admitted by the
pinned Dockerignore policy, including the required manifests and go entrypoints.
Root metadata access does not qualify non-root browser execution.
A separate Node identity probe verifies default UID 1001. Neither probe invokes
the server, provider CLI, browser, sandbox replay or deployment scripts.

Both named probes, the dedicated builder and its cache volume are removed and
their exact owned inventory checked. Logs, source/input manifests, immutable
image/tool provenance and a final record remain in task-owned scratch. The
local candidate image remains available for a separately authorized admission.
No global cache prune or removal of unrelated containers/images is proposed.

## Gates that remain held

This would prepare a fuller candidate, not establish current-source recovery
or full production parity. Synthetic build values, the compiler controls,
rolling GitHub CLI fallback and downloaded transitive/tool artifacts must remain
attributable in the result. Full retained Supabase/auth/storage/cron substrate,
startup/replacement, sandbox/isolation/observability/deploy behavior and recovery
scenario execution are separate unqualified gates. The old 13-migration
synthetic closure cannot establish the full historical schema.

App/database/recovery startup needs separate explicit authorization after a
verified candidate exists. Authenticated screenshots, eligible routine
consumer, permitted mode-specific Web matrices and attributable CLO, full
review and promotion remain held. Codex stays default-off/customer content
blocked, PR #9051 draft and auto-merge disarmed. API-key mode remains PENDING;
managed hosted-auth remains BLOCKED. Account-read authorization persists;
Cloudflare challenge retries remain stopped, admin alternatives unexecuted
and the support request unsent. No custom override or hosted-integration
approval is inferred from this proposal.
