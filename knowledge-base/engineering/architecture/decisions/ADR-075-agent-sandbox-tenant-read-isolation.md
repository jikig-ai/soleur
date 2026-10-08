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

> **Superseded by the 2026-10-07 addendum** (#5862): the per-sibling enumeration this
> section describes was replaced by the constant parent deny once the vendored CLI 2.1.284
> builder's deny-then-restore ordering landed. Preserved below for history.

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

> **Addendum — 2026-10-06 (#9601):** this ADR covers filesystem read isolation between tenants. The owner's Anthropic
> credential in the agent's own environment is a separate property, recorded in [ADR-272](./ADR-272-agent-credential-isolation-via-sandbox-credentials-deny.md)
> (per-variable `sandbox.credentials` deny; the subprocess env scrub was rejected there).

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

## Addendum — 2026-10-06 (#8752): shared seccomp filter + inherited-fd hygiene landed

Two sandbox residuals tracked under #8752 are now closed at the shared layer — one artifact
(`apps/web-platform/infra/bwrap-userns-clone3-deny.bpf`, generated + parity-tested) serves both paths:

- The C4 render chain carries `--seccomp 9` (fd opened by its close-fds prelude).
- The Agent SDK spawn is wrapped by the `infra/bwrap-shim/bwrap` PATH shim (`/usr/local/bin/bwrap` in
  the runner image), which sweeps fds not referenced by the SDK's argv (the measured libuv/bwrap leak
  — `sandbox-selfprobe-fds` telemetry stays as the countermeasure witness) and injects the filter via
  `--add-seccomp-fd` before exec'ing the real `/usr/bin/bwrap`.
- The deny surface: `clone3` → `ENOSYS` (struct-hidden flags; preserves the `clone` fallback),
  `clone`/`unshare` with `CLONE_NEWUSER` → `EPERM`.

The per-sibling `denyRead` residual is **unchanged**: Option C (#5862) remains the exit criterion, and
the nested-userns/fd-hygiene closure does not affect the TOCTOU read-only window. Deploy-time
measurement of the new pair rides the faithful canary's four derived probes (`sandbox-canary.mjs`
`runHardeningProbes` + `runArgsFdTransportProbe` — the census carries a deliberate unreferenced fd so
the shim's sweep is observable, and the `--args` probe replays the SDK's real fd transport) and the
boot self-probe `op:"sandbox-hardening-selfprobe"`.

## Addendum — 2026-10-07 (#5862): Option C shipped via the vendored builder — residual closed

**Status: `accepted` (residual closed).** The exit criterion fired — and the trigger that fired it was
the *opposite* of what was predicted: dependency-patch infrastructure did not need to be introduced,
because the reorder was already vendored. Deny-then-restore has been in the native builder since CLI
2.1.197 — vendored since the SDK's move to the external native binary (SDK 0.3.197, #5849, which even
predates this ADR's merge); the era-pinned SDK 0.2.85 could never reach it because it spawned its
bundled `cli.js` (CLI 2.1.85) instead. The pinned `@anthropic-ai/claude-agent-sdk@0.3.284` / CLI
2.1.284 binary merely carries it forward. What the builder does: each `denyRead` landing emits
`--tmpfs` FIRST, then every covered `allowWrite` path is re-bound rw (`Re-bound write path wiped by
denyRead tmpfs`) and every covered `allowRead` path re-binds ro (`Re-allowed read access within
denied region`). Confirmed by reading the binary's embedded builder and by the in-image capture audit
(`infra/sandbox-canary-argv.json` regenerated via `SANDBOX_CANARY_MODE=capture` on `node:22-slim`,
`verify_ok`).

What changed:

- `buildAgentSandboxConfig` reverted to the structural shape — `denyRead: [workspacesRoot(),
  c4StagingRoot, "/proc", ...denyReadExtra]`, a constant list. `enumerateSiblingDenyPaths`, its
  `degraded` fail-closed arm, and the per-dispatch `readdirSync` are deleted. The `readOnly` support
  persona (ADR-113) carries `allowRead: [workspacePath]` — inert today (the support workspacePath is
  the plugin root, outside the deny parent) but forward-declared so a future root-resident read-only
  session gets the same builder's ro restore instead of a blanked workspace.
- The TOCTOU is structurally closed: a sibling workspace created after a session's namespace build
  lives under the parent `--tmpfs` — masked, not merely unlisted. The direct-bwrap TOCTOU regression
  case in `test/sandbox-isolation.test.ts` pins the property (create sibling mid-session → invisible).
- The intent-vs-effect gap flagged in Consequences is now covered: the committed-fixture ordering pin
  (`test/sandbox-canary.test.ts`, "every covering `--tmpfs` precedes an rw `--bind` restore of the
  workspace") reddens on any SDK drift that re-inverts the ordering, and the capture gate byte-diffs
  the argv on every capture-input change. The per-dispatch log renamed `op:sibling-deny` →
  `op:tenant-deny` (`degraded` field retired with the arm it described); prior `sibling-deny` events
  remain queryable in the log store.
- The residual-undetectability consequence retires: the ordering is now asserted pre-merge (ordering
  pin + capture gate), not merely hoped-for at runtime.

Option B (#5863 — per-tenant isolation so an agent cannot observe siblings *exist*) remains the
longer-term end-state; this amendment closes only the read-side residual.

## Addendum — 2026-10-08 (#5863): Option B adopted in arm-F form — mount-namespace-only outer wrap

**Status: `adopting`** (claim held until production measurement, per #9603 discipline).

Option B landed — but not in the shape this ADR projected. The earlier framing assumed
an outer `bwrap --unshare-*` namespace; the Phase-0 spike (docker + the production
`soleur-bwrap` seccomp profile, 2026-10-08) measured that **impossible in the current
container posture**:

- A scoped `/proc` requires an outer PID namespace; fresh `--proc` mounts EPERM under
  Docker's masked-paths (bubblewrap#284), and the masked mounts are init-userns-owned —
  unremovable from inside (`must be superuser to unmount`).
- The vendored inner sandbox unconditionally unshares user+pid+net; a child pidns/netns
  requires the outer userns to *own* both, so ANY outer userns is fatal to the inner
  sandbox unless it also owns a pidns — which has no mountable procfs. Bound procfs
  indexes the wrong pid space (`/proc/<outer-pid>/ns` ENOENT); tmpfs starves the inner
  shim's `/proc/self/fd` sweep.
- The only unblocking posture (`systempaths=unconfined`) unmasks host `/proc` for the
  whole container — a widening, not a fix.

**Adopted:** the outer wrap is a **mount namespace only** (zero `--unshare-*`), built by
a **file-capability `bwrap`** (`cap_sys_admin,cap_setuid,cap_setgid+ep` in the image;
`SYS_ADMIN` lives in the container bounding set via `--cap-add SYS_ADMIN` at
`docker run`; children of non-file-cap'd execs carry nothing, so the wrapped CLI and
its inner sandbox never hold it). Wired via `Options.spawnClaudeCodeProcess`
(`agent-outer-wrap.ts::makeSandboxedSpawn`) — the SDK's documented interpose for
container execution. Because the outer wrap creates no namespaces, the inner sandbox
runs at the same nesting level as today — verified with the captured inner argv shape
(`infra/sandbox-canary-argv.json`).

What this delivers: an agent session's filesystem contains **only its own tenant
workspace** — sibling workspaces are never mounted, so they are absent from `ls`,
`stat`, and `/proc/self/mounts` on **both** tool tiers (Bash's inner sandbox AND the
in-CLI file tools, which the inner bwrap never bounded). Sibling *existence*, the
mount-table leak, shared `/tmp`, and `#9725`'s deny-root divergence all close
structurally; the `/workspaces` `denyRead` simplifies to vestigial (kept unconditional
while the rollout flag exists — load-bearing on the flag-off arm).

**Open residuals (named, tracked):**

- `#9723` stays open: `/proc` remains the shared container procfs — sibling PIDs,
  `/proc/<pid>/environ`, **and `/proc/<pid>/{root,cwd,ns}` (a mount-namespace
  oracle into any same-uid process)** are still visible to a sandboxed session.
  The `root`/`cwd`/`ns` reach is acceptable only while `kernel.yama.ptrace_scope`
  stays `1` — the shared payload asserts the sysctl non-zero so a drift pages
  instead of silently voiding the wrap. The honest close is the pidns, which
  requires the topology work in #9773.
- Shared container loopback — including delegated-egress cross-use (a non-entitled
  session reaching a sibling's socat proxy allowlist is an authorization bypass of
  `allowedDomains`, not merely a covert channel) and other-tenant `127.0.0.1`
  listeners.
- **Shared mutable `$HOME` state**: `.credentials.json`/`settings.json`/
  `.claude.json`/`.gitconfig` are the same host files bound rw into every session —
  a same-uid cross-tenant corruption/config-poisoning channel (pre-existing
  behavior the wrap preserves, not a new surface; per-session copy-in/out is the
  candidate close — #9773 territory).
- The server process's own cross-tenant filesystem access and the shared in-process
  heap (BYOK leases, session state) — `#9773` territory.
- The bounded claim this supports publicly is *"per-session process-level filesystem
  isolation covering both agent tool tiers"* — never unqualified "tenant isolation".

**Privilege-hygiene notes:** file caps elevate only on `exec` of the bwrap binary
(ambient is empty for every other exec path); the image asserts `{bwrap}` is the only
file-cap'd binary at build time (`getcap -r /` audit in the Dockerfile); the wrapped
session's `CapEff`/`CapBnd` carry no `sys_admin` (test-pinned).

Verification posture: realized-state probe (`tenant-isolation-probe.sh`, founder-check
pinned) + committed argv fixture (`infra/agent-outer-wrap-argv.json`) + canary arm —
all dark-launched before gating, per `wg-dark-launch-deploy-gates`.
