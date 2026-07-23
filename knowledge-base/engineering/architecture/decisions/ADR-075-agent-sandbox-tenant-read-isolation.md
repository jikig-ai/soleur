---
title: "Agent bwrap tenant read-isolation: per-sibling deny now, SDK bwrap-arg reorder as durable fix"
status: accepted
date: 2026-07-01
supersedes_pr: 5848
---

# ADR-075: Agent bwrap tenant read-isolation

## Context

The Concierge `/soleur:go` agent runs **in-process inside a single, multi-tenant web-platform
container**. `apps/web-platform/infra/ci-deploy.sh:655` bind-mounts one shared host directory
`-v /mnt/data/workspaces:/workspaces`, so every tenant's `/workspaces/<uuid>` sits side-by-side in
the same container filesystem, and `buildAgentSandboxConfig` is invoked by the SDK `query()` in the
same node process that serves every tenant (`cc-dispatcher.ts`, `agent-runner-query-options.ts`).
There is no per-tenant container or subprocess. **bwrap is the only filesystem isolation between
tenants.** The runtime `createSandboxHook` realpath-containment covers file-tools
(Read/Write/Edit/Glob/Grep/LS/Notebook) but **not Bash** — so `cat /workspaces/<other>/...` via Bash
is guarded by nothing but the sandbox `denyRead`.

The original strand (#5733) was that the agent could not read its own repo. PR #5848 added
`allowRead:[workspacePath]`. But the `@anthropic-ai/claude-agent-sdk` (v0.2.85) bwrap builder emits
the **write-plane binds first, then the read-plane last** (`--tmpfs <denyRead-dir>`, then
`--ro-bind` for each `allowRead` child). So a broad `denyRead:["/workspaces"]` `--tmpfs`-obscures the
whole tree *after* the `allowWrite --bind`, and the only post-tmpfs re-allow the SDK offers
(`allowRead`) is **read-only** — it re-binds the workspace read-only, shadowing the rw bind and
making the workspace read-only. #5848 thereby converted "not a git repository" into "read-only file
system" (verified deterministically with bwrap 0.11.1). `SandboxSettings.filesystem` exposes only
`{allowWrite, denyWrite, denyRead, allowRead}` — no bind-remap, no raw-args, no
"allowWrite-within-deny" — so a writable child under a `denyRead` parent is **not expressible**
through the SDK config.

## Decision

**Ship per-sibling `denyRead` now** (this PR): at dispatch, enumerate the entries under
`WORKSPACES_ROOT`, deny each sibling individually (plus `/proc`), and leave the agent's OWN
workspace out of the deny set — so it is never `--tmpfs`-shadowed and keeps read+write via the base
`--ro-bind / /` + `allowWrite`. `allowRead` is removed (it re-creates the EROFS). Enumeration
fails **closed** to the broad parent deny on any non-ENOENT error (strand-over-leak), mirrored to
Sentry.

**Status: accepted-with-residual.** Per-sibling deny hides every *existing* sibling but carries a
bounded TOCTOU: a sibling workspace created *after* this session's bwrap namespace is built becomes
read-only-visible via the base bind, exploitable only via Bash and only under adversarial steering.
The **exit criterion** for this residual is Option C.

## Rejected / deferred alternatives

- **B — per-tenant volume/container isolation** (each agent sees only its own `/workspaces/<uuid>`):
  the correct end-state, but it is unbuilt infra (single shared mount + in-process multi-tenant
  runner). `ci-deploy.sh:617` defers volume isolation to #4891, but that issue is **capacity**
  isolation, not tenant read-isolation — B needs its own issue. Deferred (tracked in #5863).
- **C — vendor/patch the SDK bwrap builder** to emit the write-bind *after* the parent tmpfs (the
  EXP2 ordering: `--tmpfs /workspaces` first, then `--bind own` rw — writable-own AND future-sibling
  safe, no enumeration, no TOCTOU). This is the durable closer, but the repo has **no dependency-patch
  infrastructure** (no `patch-package` / pnpm `patchedDependencies`; SDK pinned `0.2.85`), so landing
  it under prod pressure adds supply-chain + per-bump maintenance surface and needs its own review.
  **Adopted as the tracked follow-up (#5862) and the exit criterion for this ADR's residual.**
- **D — path remap** (bind own to a sandbox-private mountpoint outside `/workspaces`): needs
  src≠dest bind, absent from the SDK. Dead.

## Consequences

- The agent regains read+write of its own workspace; every existing sibling stays hidden.
- `buildAgentSandboxConfig` now performs a `readdirSync(WORKSPACES_ROOT)` per dispatch (was pure).
- A structured `feature=agent-sandbox op=sibling-deny {workspace, deniedCount, degraded}` log makes
  the isolation decision observable without SSH (`observability-coverage-reviewer` §Step 4.6); the
  `workspace` UUID is the join key that attributes a degraded broad-deny to the session it stranded.
- The log/Sentry signal reflects the COMPUTED deny decision, not the REALIZED bwrap mount state: if a
  future SDK bump re-orders the binds and shadows the write plane (the #5848 class), the signal still
  reads healthy while the agent strands. Closing that intent-vs-effect gap needs an in-sandbox
  writability probe (assert the `.git/` ASKPASS write succeeds, emit `op=writability-probe {ok}`) —
  tracked as a follow-up, not shipped here.
- Residual TOCTOU remains until Option C (#5862) lands; this ADR is accepted with C as the exit
  criterion, and the residual read-only window is currently **undetectable** (no telemetry fires if
  it is ever exploited). Option B (#5863) is the longer-term end-state.
