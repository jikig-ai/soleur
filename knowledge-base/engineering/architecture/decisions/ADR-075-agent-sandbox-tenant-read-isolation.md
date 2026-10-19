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

## Addendum — 2026-10-08 (#9723 / #9725): the deny is realized, not declared — shim tail mask + dual root

**Status: `accepted`.** Two audit findings showed the read-isolation this ADR asserts was weaker in
effect than in intent on the post-ADR-068 tree:

- **#9723 — the `/proc` deny was dead code.** `denyRead` carries `/proc`, which the vendored builder
  projects to `--tmpfs /proc` — but the same vendored argv *ends* with `--bind /proc /proc` (the
  sandbox-runtime bootstrap bind), restoring the host procfs AFTER the deny landing. Host
  `/proc/<pid>/environ` was readable in-sandbox again. The fix lands in `infra/bwrap-shim/bwrap`
  (the PATH shim the SDK's spawn already resolves in the runner image): after arity-aware argv
  parsing, the shim appends a final `--proc /proc` after the vendor tail — a fresh pidns-scoped
  procfs, deliberately NOT `--tmpfs` (a bare tmpfs deletes `/proc/self/fd`, which the vendored
  `apply-seccomp` inner command execs through; verified live). The mask is realized at spawn, so no
  fixture or SDK source is edited; `infra/sandbox-canary-argv.json` keeps the vendor's authentic tail.
  The canary `proc_mask` probe now discriminates on host-PID visibility (the canary's own host pid
  must be absent), not on an empty procfs — `/proc/self/environ` legitimately exists under `--proc`.
- **#9725 — the workspace deny covered only the pre-cutover root.** `workspacePathForWorkspaceId`
  resolves under `WORKTREE_ROOT` (`/var/lib/soleur/worktrees`) once `GIT_DATA_STORE_ENABLED` flips,
  but the deny list carried only `WORKSPACES_ROOT`. The deny set is now produced by
  `workspaceTenantDenyRoots()` (exported from `workspace-resolver.ts`, the single owner of the
  root pair): `[WORKSPACES_ROOT, WORKTREE_ROOT]`, deduplicated, flag-independent — both roots are
  denied on every dispatch, so the cutover flag state cannot change the isolation guarantee.
  `getWorkspaceWorktreeRoot` stays private. The builder's deny-then-restore ordering re-binds the
  own workspace rw regardless of which root it resolves under; a catastrophic workspace path equal
  to (or containing) a deny root still throws rather than silently restoring a whole tenant tree.

Supporting gates (same PR): `infra/git-data-flag-precheck.sh` carries a `SANDBOX_DENY_ROOTS`
source-coverage probe — informational under proof, blocking under `FLAG_MODE=flip` — and
`.github/workflows/git-data-cutover.yml` gates the flip on a `GIT_DATA_DENY_FLOOR` live-image semver
(same `/health` + `ver_le` pattern as `GIT_DATA_EMITTER_FLOOR`), so the flag cannot be flipped onto a
running image that predates the dual-root deny. The canary fixture was re-captured on `node:22-slim`
with `WORKTREE_ROOT=/tmp/soleur-sandbox-canary-worktrees` pinned — it now carries both deny landings
and still ends `--bind /proc /proc`.

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

- `#9723` stays open **for the wrapped-CLI tier specifically**: the #9768
  addendum below scoped the *inner* sandbox's procfs (the shim tail mask), but
  the file tools run in the CLI process itself — one level OUTSIDE the inner
  shim — so for them `/proc` is still the shared container procfs: sibling
  PIDs, `/proc/<pid>/environ`, **and `/proc/<pid>/{root,cwd,ns}` (a mount-
  namespace oracle into any same-uid process)** remain visible there. The
  `root`/`cwd`/`ns` reach is acceptable only while `kernel.yama.ptrace_scope`
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

## Addendum — 2026-10-09 (#9873 disposition): arm-F elevation dropped; Option B exits via #9773 only

The file-capability elevation arm recorded in the 2026-10-08 addendum was
**reverted** (#9874, `d7dfd05aac`) after the v0.333.1 deploy rolled back on
`canary_sandbox_failed`: released bwrap 0.8–0.12 aborts on
`real_uid != 0 && has_caps()` ("Unexpected capabilities but not setuid"), and a
capped binary outside the container bounding set fails `execve` outright
(EPERM, rc 126 — incident #9871). #9873 tracked the replacement elevation arm.

**Disposition (operator-ratified 2026-10-09, brainstorm
`knowledge-base/project/brainstorms/2026-10-09-outer-wrap-elevation-disposition-brainstorm.md`
and spec `feat-outer-wrap-elevation-disposition/spec.md`): Option 3 — drop the
privileged arm.** The remaining non-userns elevation paths were all dead ends or
net-negative:

- **setuid bwrap** is a dead mechanism: upstream deprecated it at 0.11.2
  (CVE-2026-41163) and removed it at 0.12.0 — it could only ever run on prod's
  pinned 0.8.0 and cannot even be tested on the dev host's 0.12.
- **Any** non-userns elevation needs `CAP_SYS_ADMIN` in the container bounding
  set at `docker run`, which flips `seccomp-bwrap.json` onto its permissive
  CAP_SYS_ADMIN shape for every process and makes every setuid binary already
  in the image (`su`, `mount`, `newgrp`) a root-capable escalation carrier.
  A setuid bwrap reachable by agent-executed code is also the primitive that
  unmounts the deny tmpfs in force today — self-defeating.
- The executor topology (#9773, epic #9842) was operator-approved the same week
  and subsumes the wrap's entire purpose; the challenge review dropped the
  "arm-F uid envelope" premise, so any in-container elevation would be strictly
  interim spend against a funded replacement that closes the superset.

`AGENT_OUTER_WRAP` stays flag-off on the shared prod container (the
implicit-userns fallback still serves hosts that permit it); sibling workspace
**content** stays masked by the #5862 `denyRead` + realpath hook, which is now
indefinitely load-bearing (#9798's post-promotion cleanup premise is void).
The open residual — sibling filesystem *existence*/mount-table presence, plus
the shared-`$HOME` **read** surface (`.claude/projects/<cwd-slug>/` transcripts
are same-uid readable cross-session — the wrap's narrow `$HOME` binds were the
mechanism that would have closed it; ADR-075's existing bullet records only
the write side) — exits only with **#9773 Stage 1**. **Revisit trigger:** if Stage-1 GA slips materially
(~8 weeks) or a realized sibling-filesystem incident lands, the interim arm is
re-opened as a bespoke minimal setuid launcher (fixed-argv
mount+bind+drop-uid+exec), never setuid bwrap.

## Addendum — 2026-10-11 (#10032): the /proc mask realization changes from fresh procfs to neutralize + fd re-home

**Context.** The #9723 fix made the bwrap PATH shim splice a pidns-scoped
`--proc /proc` after the vendored builder's `enableWeakerNestedSandbox` tail
bind (`--bind /proc /proc`), re-masking the real procfs that tail re-exposed.
Post-#9768 the shim required that splice on every SDK argv — and under
production's Docker default masked `/proc`, `mount("proc", ...)` inside the
user namespace fails EPERM (`mount_too_revealing` class; bwrap 0.8.0 prints
`Can't mount proc on /newroot/proc: Operation not permitted`). Every
sandboxed spawn failed closed from 2026-10-09T04:52Z (canary #9860, root
cause class H6 — reproduced in-image during Phase 0: same image digest,
same bwrap 0.8.0, `sdk_probe` EPERMs while the procfs-free `sdk_noproc`
passes).

**Decision.** The mask realization changed shape; the isolation guarantee
did not. The shim now:

- **Drops** every procfs-mount-at-`/proc` token from the merged setup
  stream — outer argv and `--args` payload transport alike (selective
  re-emit, never verbatim) — so the vendored `denyRead: ["/proc"]` →
  `--tmpfs /proc` lands as the realized mask: an empty, mountless `/proc`.
  Dropping (not covering) is load-bearing: a covered bind remains a live
  host-procfs mount object beneath the tmpfs, re-exposable by any inner
  process holding `CAP_SYS_ADMIN` over the mount namespace via `umount(2)`
  — the vendored `apply-seccomp` multicall class attempts exactly such
  namespace work on permissive postures. Removal makes the deny
  mount-independent, not merely order-correct.
- **Appends** `--tmpfs /proc` at the last setup position when a rewritten
  stream carries no mask of its own (otherwise the `--ro-bind / /` root
  bind would re-expose host procfs).
- **Re-homes** every unique command-side `/proc/self/fd/N` reference with a
  literal-path `--ro-bind <resolved-source> /proc/self/fd/N` mount at the
  outer setup tail — token-preserving, so the vendored `apply-seccomp`
  multicall exec path stays resolvable without any procfs.
- **Refuses** (exit 65, `bwrap-shim:`) when a referenced fd cannot be
  re-homed — not open, unreadable, deleted, or a pipe/socket/anon inode —
  and keeps the existing pidns/userns gates and `--opt=` limitation.

**Why not `systempaths=unconfined`.** Measured during Phase 0, it lets
`--proc /proc` mount — but it widens `/proc` and `/sys` for every process
in the shared container, not just the sandbox, as an interim for a defect
the shim can fix without widening anything. Rejected on least-privilege.

> **Addendum — 2026-10-12 (#10065):** the "Dropping (not covering) is load-bearing" rationale above holds for a mount
> NAMESPACE that carries no other procfs. The vendored argv for the agent runner begins with a recursive `--ro-bind / /`,
> so the container's own procfs already sits beneath the vendor `--tmpfs /proc` after a drop as well; a drop and a cover
> therefore differ only for a process that could `umount` the tmpfs, i.e. one holding `CAP_SYS_ADMIN` over the mount
> namespace. **Observed** 2026-10-12 (`knowledge-base/project/specs/feat-one-shot-10065-sandbox-proc-suite-parity/measurements.md`,
> M3; run under `apparmor=unconfined`, so the AppArmor half is CI's): in the unprivileged suite image every
> `umount2("/proc")` from inside the sandbox is EPERM for drop and cover alike, with and without `--cap-add CAP_SYS_ADMIN`,
> so no behavioral probe separates them. **Inferred, not measured:** that attribution (unprivileged bwrap drops every
> capability after setup, and the vendored tail carries `--cap-drop ALL`) is the reading consistent with those
> observations; locked inherited mounts would also produce EPERM, and no positive control (a sandbox that CAN umount)
> exists in that image. The shim still drops, because "no argv-requested procfs mount at `/proc`" is the property it can
> state and the suite can assert (the recorder arm of `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`).
> **Conditional on three things:** (1) an UNELEVATED bwrap: the production bwrap is neither setuid nor file-capability'd
> (the 2026-10-09 addendum reverted that arm; the suite's static `ELEVATION` arm is a best-effort scan of the common
> Dockerfile spellings, backed by a live `stat` of the suite container's `/usr/bin/bwrap`, so it is not a proof); (2) the
> vendored tail keeps `--cap-drop ALL`, which `test/sandbox-vendored-argv-tail.test.ts` pins in both vendored binaries;
> (3) the three app-container `docker run` tuples keep their posture (no added capability, no host pid mode, no
> `systempaths` override), which the closed-world tuple check `infra/lib/docker-run-tuple.py` enforces in the required
> lane through `test/docker-run-tuple-posture.test.ts`. If any stops holding, drop versus cover
> becomes load-bearing again and this addendum must be re-decided, not carried forward. The hook sandbox builder in the CLI
> platform binary has no root bind, so the original sentence holds there.
>
> In effect this supersedes the sentences of the **Isolation effect** paragraph below that read "no procfs is mounted" and
> "no-procfs-at-all": the realized mask is an empty `/proc` tmpfs with the container's procfs beneath it, and the paragraph's
> conclusion (cross-tenant `/proc/<pid>/environ` reads are unreachable) rests on the unelevated-bwrap condition above.

**Why the single-rung re-home.** The plan's rung-2 (`--bind-data` /
`--ro-bind-data` / `--bind-fd` content binds for deleted or memfd sources)
is dead on production's bwrap 0.8.0: `--bind-data` EBADFs at write,
`--bind-fd` parses but cannot resolve its fd source, and binding
`/proc/self/fd/N` itself fails because real bwrap never holds that fd.
Rung-1 `--ro-bind` covers the real surface — the vendored multicall fd is
an `/proc/self/exe` handle on the CLI binary, a live readable path —
verified end-to-end in-image (the re-homed binary executes through
`/proc/self/fd/5`). Anything else refuses rather than shipping a silently
broken multicall.

**Isolation effect.** *(Read with the 2026-10-12 (#10065) addendum above: the realized mask is an empty `/proc` tmpfs with
the container's procfs beneath it, so "no procfs is mounted" and "no-procfs-at-all" below describe the argv, not the
kernel mount set.)* Preserved and, strictly, strengthened: the realized
mask is now no-procfs-at-all (previously a pidns-scoped procfs that still
exposed the sandbox's own `/proc/<pid>` surface). `/proc/<pid>/environ`
cross-tenant reads are unreachable because no procfs is mounted; the
fd-re-home mounts land only under `/proc/self/fd/` at the literal paths the
command names. A real `--proc` or procfs bind anywhere in the merged stream
is dropped, not shadowed — mount ordering can no longer defeat the deny.

**Probe re-spec.** The canary `proc_mask` probe asserted the pidns-procfs
shape (host pid absent AND `/proc/self/environ` present). Under tmpfs that
second half inverts into a false defeat, so the probe now asserts **no
`/proc/<pid>` directory entries** — a bound host procfs, a fresh `--proc`,
or a leaked root bind all land as `proc_mask_defeated`; the legitimate
empty tmpfs (optionally carrying `self/fd/` re-home mounts, which the
`/proc/[0-9]*` glob cannot match) passes.

**Invariance caveat.** Under the injected clone3-deny filter the vendored
`apply-seccomp` multicall cannot reach its `/proc`-dependent steps at all
(it dies at `unshare(CLONE_NEWUSER)` on every kernel posture measured), so
the mask realization shape cannot change the multicall's outcome. The
re-home is therefore **semantic preservation of the vendored contract** —
the shim rewrites the vendored argv and a dangling `/proc/self/fd/N` would
be a silent degrade, forbidden by the shim's own fail-closed doctrine — not
a second isolation layer, and it decouples this decision from the deferred
prod-posture question (a future posture where the multicall runs keeps the
exec path resolvable). The multicall-success check in the in-image verify
path is retained against posture drift.

**Deferred.** Per-tenant executor topology remains **#9773** (epic #9842) —
this is an interim realization change, not the architecture. The
least-privilege kernel-stream read for `kdeny` (`src=none`) was **#10045** —
resolved 2026-10-11: the `KDENY_KERNEL_STREAM` fixed-argv sudoers grant plus a
`sudo:`-signature denial fallback in `_canary_kdeny_read` give the row the host
kernel stream it needed.

**Basis.** `knowledge-base/project/specs/archive/20261013-062704-feat-one-shot-10032-sandbox-shim-procfs/measurements.md`
(in-image repro + rewritten-argv spawn, rung-2 EBADF measurement,
`systempaths=unconfined` contrast); `infra/bwrap-shim/bwrap`;
`test/bwrap-shim.test.ts`; `scripts/sandbox-canary.mjs`.

## Addendum — 2026-10-16 (#10445): AF_UNIX blocking inside the inner sandbox is deliberately not enforced

> **Partly superseded by the 2026-10-19 addendum below (#10455 a):** the "single `socket(AF_UNIX)` deny in the one filter" follow-up and the "proxy auth is the only remaining AF_UNIX control" assumption no longer hold as written; read that addendum first.

**Context.** The #8752 plan recorded the vendored `apply-seccomp` helper as "inert today (our config sets no
`allowUnixSockets`)", and the 2026-10-11 addendum above (its "Invariance caveat") recorded that the multicall "dies at
`unshare(CLONE_NEWUSER)` on every kernel posture measured". The first was false, and the second was measured on a host
that denies unprivileged `NEWUSER` in the container, not on production's posture. The vendored builder wraps **every**
sandboxed command in that helper (its job is to block `socket(AF_UNIX)` for the command), so under the shim's `--add-seccomp-fd` filter every hosted Bash call failed with
`apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` from the first production deploy of
`web-v0.324.3` (2026-10-06) until this change. The incident record is the PIR
`knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`.

**Decision (CTO-ruled, 2026-10-16).** `buildAgentSandboxConfig` sets `network.allowAllUnixSockets: true`. The
vendored builder then skips the helper ("Skipping seccomp filter - allowAllUnixSockets is enabled"). The
nested-userns / `clone3` filter injected by the shim is **unchanged**. Rejected: a `CLONE_NEWUSER` exception in
the filter, because a seccomp filter cannot key on the caller and the exception would re-open nested user
namespaces for every sandboxed process.

**Residual and its bounds.** The SDK helper was the per-command AF_UNIX block until 2026-10-06 (when #9595 made it
fail). This change returns to a state with no AF_UNIX block, which is weaker than the pre-incident baseline in this
dimension: a tenant's Bash can create and connect AF_UNIX sockets inside its sandbox, and bwrap's `--ro-bind / /`
leaves sibling sessions' pathname sockets in the shared temp dir visible. The exposure is bounded by:

1. Per-session proxy-credential auth on the sibling bridge sockets. `test/sandbox-wrapped-command-runtime.test.ts` (G2)
   runs two real SDK sessions and requires that, through every visible socket, a request with no credential and a
   request with a wrong credential both get `407`, while the caller's own credential is accepted by its own socket (the
   negative control). This is proven for HTTP CONNECT; SOCKS auth was established by reading the vendored binary and is
   not yet tested (#10455).
2. Masks over the CLI peer-messaging socket directories (`peerMessagingSocketDirs()`: the union of `cc-socks` under
   `XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR` and `/tmp`, plus `/tmp/cc-socks-<uid>`). The peer-messaging
   protocol's own auth was not characterised, so the mask, not auth, is the control there.
3. A mask over the session-transcript directory (`$HOME/.claude/projects`, and `$CLAUDE_CONFIG_DIR/projects` when set),
   because a sibling's proxy credential printed by `env` and persisted in a shared-HOME transcript would otherwise be
   usable against that sibling's bridge socket; G2 asserts the sandbox sees none.
4. Per-command `--unshare-net`, which bounds abstract-namespace sockets (asserted in the runtime test's spawn argv).
5. A per-tenant CLI temp base. The CLI persists every Bash command's output (a sibling's `env` included, with its
   per-session proxy credential) under `<CLAUDE_CODE_TMPDIR or tmpdir>/claude-<uid>/...`, and the vendored builder binds
   that whole per-uid dir writable into every sandbox, so no `denyRead` can hide it (the covered allowWrite path is
   re-bound after the tmpfs). Found by the fix-round security seat: with AF_UNIX allowed, session B could read A's
   persisted `env` output and replay A's credential against A's bridge sockets (accepted: 502, not 407). Each tenant
   (workspace) therefore gets its own CLI temp base (`agentSessionTmpDir`, `/tmp/.cs/<sha256(workspace)[0:16]>`, injected as
   `CLAUDE_CODE_TMPDIR`) and the sandbox config denies the shared root `/tmp/.cs`; G2 runs A with `env; sleep 60` and
   requires B to find none of A's credential under `/tmp`, `$TMPDIR` or `$HOME`, with a control arm (no per-tenant base)
   that must find it. This, not socket authentication, is now the primary control for the credential; proxy auth stays
   as the backstop. Other persisted CLI output locations (`<cfg>/tasks`, `debug`, `history.jsonl`, `cc-daemon-<uid>`)
   are tracked in #10455.

Load-bearing assumption: SDK proxy auth is the only remaining AF_UNIX control for the bridge sockets. Sockets of the
host runtime (docker, dbus) are a property of the run tuple and are checked by the pathname-socket census in
`infra/sandbox-masked-proc-docker.test.sh`. The census has limits: one idle session in the suite image
(which has none of production's `/workspaces` or plugin mounts), and no abstract sockets. The egress forwarder is a TCP loopback listener, outside the
per-command network namespace, so it is not covered by these socket controls.

**Follow-up.** If the SDK changes how the proxy sockets authenticate, or a decision is made to enforce AF_UNIX
blocking again, the replacement is a single `socket(AF_UNIX)` deny in the one bwrap-level filter (`socketpair` stays
allowed: libuv child processes need it), tracked in #10455. The vendored-binary pins in
`test/sandbox-vendored-argv-tail.test.ts` (helper-selection literals and the settings mapping) turn red on an SDK bump
that changes how the helper is selected, so the premise is re-proved rather than inherited.

## Addendum — 2026-10-19 (#10455 a): AF_UNIX is denied for no-egress sessions by a second seccomp artifact, behind a runtime flag

**This addendum SUPERSEDES two statements of the 2026-10-16 addendum above.** (1) The "Follow-up" paragraph said the
replacement for the lost per-command AF_UNIX block is "a single `socket(AF_UNIX)` deny in the one bwrap-level filter". That is not
buildable: the vendored builder starts in-sandbox `socat TCP-LISTEN:3128/1080 ... UNIX-CONNECT:<sock>` bridges before every user
command (measured 2026-10-19 from the bwrap argv the real SDK emits, with `allowedDomains: []`, and pinned in
`test/sandbox-vendored-argv-tail.test.ts`), so a blanket deny breaks the proxy bridge of every egress session. (2) The
"Load-bearing assumption" said SDK proxy auth is the only remaining AF_UNIX control. For **no-egress sessions with the runtime flag
on** it is no longer the only control: they cannot create an AF_UNIX socket at all.

**Decision (CTO-ruled, 2026-10-19; the flag architecture-reviewed).** A second generated artifact,
`infra/bwrap-userns-clone3-unixdeny.bpf` (`gen-bwrap-userns-seccomp.mjs --variant unixdeny`): the base rules plus
`socket(AF_UNIX)` (nr 41 and its x32 twin, the LOW 32 bits of arg0 equal to 1) returning `EPERM`; `socketpair` is untouched (libuv
and Node IPC); the arch gate is kept; `--check` verifies both artifacts. The base artifact is byte-identical to today's (golden
bytes pinned by sha256 and compared with `origin/main`), so egress sessions and the C4 render path are provably unchanged.

- **Selection.** `usesUnixDenyArtifact` (`server/agent-sandbox-seccomp.ts`) is the single predicate and `seccompArtifactFor` the single path resolver.
  `buildAgentEnv` sets `SOLEUR_BWRAP_SECCOMP_BPF` to the variant only for a session with **no egress of any kind** (no GitHub
  installation token, no web-egress handle) while the runtime flag `agent-sandbox-unix-deny` is ON; otherwise it passes the ambient value
  through unchanged (the #8752 incident-time override is preserved; the CTO's "always set" is amended because the flag defaults OFF).
  `buildAgentSandboxConfig` records the same posture, and `buildAgentQueryOptions` checks at spawn time that env and config agree
  (CTO-ruled fail-safe, 2026-10-19: a disagreement mirrors to Sentry (`op=seccomp-agreement`) and corrects to base; it never throws, because a
  throw at query start would turn defense-in-depth into a total tenant outage. The only correction is toward the base artifact: an unixdeny
  selector on a session that is not variant-eligible, e.g. an ambient `SOLEUR_BWRAP_SECCOMP_BPF` incident override equal to the unixdeny path
  on an egress session, is reset to the base artifact). Both runners resolve the flag once per query.
- **Kill switch.** The flag defaults OFF and fails closed to OFF (a throw, a 2 s timeout, an absent flag service or a missing flag all
  resolve OFF with one debounced warning). Turning it ON is a production write, taken only after the deploy SDK Bash smoke has been
  green on a real deploy and with the operator's explicit authorization at that time (tracker #10548). The deploy smoke runs the
  no-egress tuple **with the variant selected**, so a variant that breaks Bash start is reported on the deploy that carries it before
  the flag is ever on. The variant is a strict superset of the base program, so the same run also covers a broken base.
- **Verified both ways.** `probeAgentSandboxHardening` (boot) and the canary hardening probes (deploy) verify both artifacts: under the
  variant `socket(AF_UNIX)` must be `EPERM`, under the base it must still work. Real-SDK arms
  (`test/sandbox-wrapped-command-runtime.test.ts`): no-egress + flag on, Bash starts, AF_UNIX is `EPERM`, `socketpair` and `AF_INET`
  sockets work and `curl` fails fast ("Proxy CONNECT aborted"); egress session, base artifact, the bridge reaches the proxy ("CONNECT
  tunnel failed, response 502"); flag off, today's posture.
- **io_uring.** `IORING_OP_SOCKET` (kernel 5.19+) would bypass a `socket()` filter, but the production run-tuple profile
  (`infra/seccomp-bwrap.json`, a default-deny allowlist) names no `io_uring_*` syscall, so a ring cannot be created: measured live on
  2026-10-19 (`io_uring_setup` returns EPERM under the committed profile and docker's built-in default, rc 3 unconfined as the positive
  control). The variant therefore needs no ENOSYS rule; a static test fails if the profile ever allowlists an `io_uring_*` name.

**What stays as it was.** Egress sessions (any GitHub installation token or web egress) remain at "per-session proxy auth + masks"
(the five bounds of the 2026-10-16 addendum) with the base artifact; **proxy auth is still the load-bearing control for them**. Covering
them needs a per-command wrapper, tracked in #10549. Pre-existing weaker-than-baseline posture for egress sessions is unchanged by this
addendum.

**Tenant-visible effect (flag on).** A no-egress session can no longer create AF_UNIX sockets: a local Postgres or Redis socket path,
Python `multiprocessing` Manager/Listener and D-Bus clients fail with "Operation not permitted". Node IPC and libuv child processes
(`socketpair`) are unaffected. Release-notes and support lines: `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
("Tenant-visible: no-egress AF_UNIX deny").

**Residuals.** The deny is by `socket()` family: AF_UNIX use through `socketpair` and fd passing between two processes of the same
sandbox is allowed by design. The flag is global (anonymous identity), not per organisation. The Flagsmith outage fallback is the
`FLAG_AGENT_SANDBOX_UNIX_DENY` env mirror (default `0`, so an outage resolves OFF unless an operator set the mirror to `1`).
