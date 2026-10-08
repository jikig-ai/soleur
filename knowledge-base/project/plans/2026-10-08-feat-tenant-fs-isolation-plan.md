---
title: "agent-sandbox: per-session process-level filesystem isolation covering both agent tool tiers (ADR-075 Option B; not capacity #4891)"
date: 2026-10-08
slug: feat-tenant-fs-isolation
branch: feat-5863-tenant-fs-isolation
issue: 5863
closes: 5863
type: feat
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

## Overview

Give each Concierge agent session a filesystem view containing only that
session's own workspace. Instead of masking siblings with a `--tmpfs` deny over
a shared mount (the #5862 deny-then-restore baseline), wrap the **entire
`claude` CLI child process** in a self-authored outer bwrap namespace whose
mount table contains only what the session needs. The boundary covers both
agent tool tiers — sandboxed Bash and the file tools (Read/Write/Edit/Glob/
Grep/LS/Notebook*) that execute inside the otherwise-unsandboxed CLI child —
because the wrap happens at the process spawn, not inside the sandboxed
command surface.

Mechanism: the SDK's officially supported `Options.spawnClaudeCodeProcess`
interpose (`sdk.d.ts:2431`, added for "VMs, containers, or remote
environments"). The server receives `{command, args, cwd, env, signal}` and
returns `spawn("/usr/bin/bwrap", <outer argv> -- command ...args)` — no wrapper
script, no vendored-argv surgery, and the isolation property is authored by us
and therefore immune to SDK-bump argv drift (#5849 class).

Closes #5863; folds in #9725 (deny-root divergence) by construction. Leaves
open: #9723 (`/proc` cross-tenant environ channel — **measured unclosable in
the current container posture**, see Spike Results; needs a pidns, and a pidns
kills the vendored inner sandbox — named residual), #9724 (canary machinery
gaps on the *current* argv path), #9773 (per-tenant executor end-state).

**Claims & named residuals.** The bounded claim this design supports is
*process-level filesystem isolation covering both agent tool tiers* — it is
not unqualified "tenant isolation". Named residuals it does not close:
shared `/proc` (sibling PIDs and their `/proc/<pid>/environ` remain
visible — the #9723 credential channel stays open), container loopback
(including delegated-egress cross-use through a sibling session's socat proxy
allowlist — an authorization bypass, not merely a covert channel, and
other-tenant listeners on `127.0.0.1`), abstract unix sockets / `connect(2)`
to known paths, the server process's own cross-tenant fs access, and the
shared in-process heap (→ #9773).

## Research Insights

### Premise Validation (Phase 0.6)

All cited references verified live on 2026-10-08: #5863 OPEN; #5862 CLOSED via
PR #9709 (merged 2026-10-07, `web-platform-release` green since); #9723/#9724/
#9725 OPEN; ADR-075 `accepted` with Option B deferred to this issue; #4891
CLOSED (capacity, out of scope); `spawnClaudeCodeProcess` and
`SpawnedProcess`/`SpawnOptions` confirmed in installed SDK 0.3.284
(`sdk.d.ts:2431`, `:9328`, `:9380`); `getWorkspaceWorktreeRoot` at
`workspace-resolver.ts:69`. One stale reference corrected: "the #5849
split-unshare discriminator" resolves to the #5873 incident / #5941 probe gap
(#5849 is the Sonnet-5 toolchain PR that *caused* #5873).

### Property List (Phase 0.6b)

- P1: no sibling workspace present — content, existence, or mount entry — on
  any agent fs surface (Bash AND file tools).
- P2: ~~session `/proc` shows only session processes~~ — measured unclosable (spike); /proc stays shared, #9723 residual.
- P3: mount table derives from the workspace resolver root (survives the
  git-data cutover).
- P4: isolation argv authored by Soleur (SDK-drift-immune).
- P5: failure to construct the namespace fails the session loudly.
- P6: realized-state verification exists (in-sandbox probe, not argv diff).
- P7: per-session `/tmp` and config/`HOME` scope — no cross-tenant scratch or
  transcript visibility.

### Cut List (Phase 0.6b)

- Shim `--args` payload rewrite → P1 (Bash tier only) → cannot reach the
  file-tool tier; cut as primary, retained as contingency.
- Per-tenant subprocess/container executor → P1 + credential boundary →
  overshoots this issue's scope; filed as deferred #9773.
- Idmapped mounts / `setns` / new mount API → P1 → EPERM under the container
  seccomp profile (compile-time cap-gated); impossible without a profile
  change.
- `pathToClaudeCodeExecutable` wrapper script → P1+P4 → superseded by
  `spawnClaudeCodeProcess` (typed argv/env/cwd/signal, no shebang/`existsSync`/
  env-replacement pitfalls); cut in favor of the official interpose.

### Repo research (brainstorm + plan fan-out, consolidated)

- Spawn chain: `cc-dispatcher.ts`/`agent-runner.ts` → `buildAgentQueryOptions`
  (`agent-runner-query-options.ts:204`) → SDK `query()` → vendored CLI child
  (unsandboxed; file tools here) → per-Bash bwrap via `--args <fd>` (opaque to
  the `bwrap-shim` PATH interceptor).
- `buildAgentSandboxConfig` (`agent-runner-sandbox-config.ts:254`) emits
  constant `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...]` →
  vendored builder emits `--tmpfs <landing>` then rw restore binds.
- Sibling-observable surfaces today: `/proc` mount table + same-uid environ
  (#9723), shared `/tmp` (container tmpfs + `/tmp/claude-1001` rw),
  `~/.npm/_logs` + `~/.claude/debug` rw, `~/.claude` ro-visible incl.
  `projects/` transcripts, `denyRead` root divergence under
  `GIT_DATA_STORE_ENABLED` (#9725).
- Reuse inventory (functional-overlap agent): `c4-render.ts` ›
  `buildLikeC4SandboxArgv` is the argv-composition pattern to copy (not
  reusable — wrong mounts/env/net); `bwrap-shim` is the exec-interpose
  precedent (bypass it via absolute `/usr/bin/bwrap`); `classifySandboxStartupError`
  (`sandbox-startup-classifier.ts:136`) is reusable as-is for fail-closed
  classification; `test/helpers/sandbox-isolation-fixtures.ts` is the
  ready-made test harness; `sandbox-canary.mjs` capture/verify/replay
  machinery extends to an outer-wrap fixture.

### External research

- `spawnClaudeCodeProcess` (sdk.d.ts:2412-2431) is the documented interpose;
  `signal` fires only after the SDK's stdin-EOF + ~2 s grace. Caveats:
  custom spawners emit plain `exit` (no stderr drain), spawn ENOENT can hang
  `query()` (anthropics/claude-agent-sdk-typescript#255) — preflight the bwrap
  path.
- Minimal-mount argv composition (bwrap upstream + flatpak-run prior art):
  `--ro-bind /usr /usr` + merged-usr links, ld.so cache + `/etc` minimal set
  (resolv.conf/hosts/nsswitch/ssl/passwd/group), `--dev /dev`, terminfo +
  locale binds. **No `--clearenv`** — it wipes the spawn env wholesale, so
  secrets could only return via `--setenv` (argv → `/proc/.../cmdline` leak).
  Instead the spawner composes the child env server-side: `options.env` per
  the S0.2 measurement + derived overrides injected into the map.
- `/proc` — MEASURED (Phase 0, docker + soleur seccomp): fresh `--proc`
  EPERMs under Docker's masked-paths and the masked mounts cannot be
  umounted from inside a userns (`must be superuser to unmount` —
  init-userns-owned). A bound container procfs never scopes (pid-ns-keyed
  at mount). Worse, the vendored inner sandbox cannot nest under ANY outer
  userns: its unconditional `--unshare-pid`/`--unshare-net` require the
  outer to own both namespaces, and an outer pidns starves the inner's
  `/proc` reads. Arm F drops all `--unshare-*` and relies on a file-cap'd
  bwrap for a mountns-only wrap; `/proc` stays shared → #9723 residual.
- Signals: released bwrap has no `--forward-signals`; monitor does not relay
  SIGTERM. Teardown = `detached: true` at spawn + `process.kill(-pgid)` on the
  bwrap process group (asserts the *server's* pgid is untouched), plus
  `--die-with-parent` as belt. Killing bwrap's bare PID orphans the inner CLI.
- `SpawnedProcess` has **no stderr channel** (sdk.d.ts:9353) — the spawner
  must capture child stderr into a ring buffer and attach it to emitted
  errors and the `op:tenant-outer-wrap` log, or fail-closed loses its
  classification input.
- **Env:** never put secrets on argv (`--setenv GIT_INSTALLATION_TOKEN=…`
  lands on `/proc/<bwrap>/cmdline` — MORE readable than environ). Spawn env
  carries the credential set; `--setenv` is reserved for non-secret derived
  vars (HOME/CLAUDE_CONFIG_DIR/TMPDIR/XDG_*). `SpawnOptions.env` contents must
  be measured at spike — if the SDK merges ambient `process.env`, the spawn
  env is intersected with the known-key allowlist before use.
- Never `--ro-bind /run` or `$XDG_RUNTIME_DIR` — ro binds do NOT block
  `connect(2)` on socket inodes (delegated-authority escape).
- **Zero `--unshare-*` on the outer wrap** (arm F, measured): any outer
  userns breaks the vendored inner sandbox — its unconditional
  `--unshare-pid`/`--unshare-net` require the outer userns to *own* the
  pidns/netns, and an outer pidns has no mountable scoped procfs. The outer
  wrap is a pure mount namespace built by file-cap'd bwrap; loopback and
  `/proc` stay shared container-wide → named residuals.
- Bound mounts pin the *inode*: a workspace reprovision/re-clone that swaps
  the directory under the same path leaves the session bound to a deleted
  inode (split-brain). Canonicalize (`realpathSync`) once at dispatch — one
  value feeds bind source, bind dest, cwd, and the file-tool hook — and
  serialize reprovision before spawn binds (or post-spawn dev+ino compare).
- Mount-table strategy: broad ro-bind of the *system image* (`/usr`, merged-
  usr links, ld.so set, minimal `/etc` — identical container fs, no tenant
  data) + **strictly derived state roots** (workspace path, plugin root,
  per-tenant config dir, bpf artifact, socat socket dir) — each realpath'd +
  `accessSync`'d at spawn, fail-closed. Not a hand-enumerated literal list
  (the Check-10 `BWRAP_ARGS` lesson) and not build-time ldd/strace (misses
  PATH-resolved helpers and runtime sockets).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "`pathToClaudeCodeExecutable` wrapper" (spec FR1) | Works, but `spawnClaudeCodeProcess` is the documented interpose and strictly less fragile | Plan adopts `spawnClaudeCodeProcess`; FR1 mechanism updated |
| "exec the real bwrap by absolute path" (spec FR1) | Still correct at the spawn layer — spawn `/usr/bin/bwrap` directly, bypassing the PATH shim | Kept |
| "`--unshare-pid` scopes bound /proc to session processes" (spec FR3) | MEASURED dead: fresh `--proc` EPERMs (masked paths unremovable), bound procfs never scopes (pid-ns-keyed), tmpfs starves the inner shim — and an outer pidns is itself fatal because the inner's unconditional `--unshare-pid`/`--unshare-net` need an outer-owned pidns/netns + matching procfs | Arm F: mountns-only wrap via file-cap'd bwrap, zero `--unshare-*`; #9723 recorded as an open residual, spec FR3/G2/AC2 rewritten |
| Fresh per-session `$HOME`/`~/.claude` | `~/.claude/projects/` holds resume transcripts — a bare tmpfs breaks `resume`/`continue`; a new `.agent-home` root adds a state-root lifecycle + DSAR sweep obligations AND lands on ephemeral host NVMe under the `WORKTREE_ROOT` arm | Default: narrow-bind the existing `~/.claude/projects/<encoded-cwd>` (already cwd-keyed = already tenant-scoped) + enumerated config files onto a `--dir` `$HOME` — zero new state roots, resume continuity preserved both directions, tenant=workspace sharing model affirmed. `.agent-home` remains the contingency if S0.6 shows the narrow set insufficient |
| "`--clearenv` + `--setenv` allowlist" (spec FR4) | `--clearenv` wipes the spawn env wholesale — secrets could only return via `--setenv`, landing on `/proc/<bwrap>/cmdline` (worse than the environ channel #9723 closes) | No `--clearenv`; env composed server-side (options.env per S0.2 + derived overrides); argv carries no secrets |

## User-Brand Impact

- **Artifact:** the per-tenant agent filesystem boundary (what a tenant's
  agent can or cannot see, across both tool tiers).
- **If this lands broken, the user experiences:** either a silent isolation
  regression (sibling workspace reachable by another tenant's agent) or a
  hard session-startup outage (fail-closed spawn failure on every Concierge
  run).
- **If this leaks, the user's data is exposed via:** sibling workspace content
  and `/proc/<pid>/environ` credentials (GIT_INSTALLATION_TOKEN-class) readable
  by a co-tenant's agent.
- **Brand-survival threshold:** `single-user incident`.

CPO sign-off required at plan time (brainstorm carry-forward: CPO assessed
2026-10-08 — "gates the first hosted arms-length tenant"; claim ceiling is
"process-level filesystem isolation for sandboxed agent commands", never
unqualified "tenant isolation"). `soleur:engineering:review:user-impact-reviewer`
runs at review time per the review-skill conditional block.

## Implementation Phases

### Phase 0 — Spike results (measured, 2026-10-08, docker+soleur-seccomp)

Spike ran inside `docker run --security-opt seccomp=soleur-bwrap.json
ubuntu:24.04` (Docker's default masked `/proc`, same masking as prod —
cloud-init.yml:789 sets seccomp+apparmor, no `systempaths` override, so
masked paths apply).

| Probe | Result |
|---|---|
| `bwrap --unshare-user --unshare-pid --proc /proc` | **EPERM** `Can't mount proc` — bubblewrap#284 masked-paths |
| helper umounts masked `/proc/*` mounts then `mount -t proc` | **EPERM** — `must be superuser to unmount` (masked mounts are init-userns-owned; unremovable inside) |
| outer userns only + inner SDK argv | **dead** — inner unconditionally `unshare(pid,net)`; a child pidns/netns requires the outer userns to *own* the current pidns/netns |
| outer pidns + bound container `/proc` + inner | **dead** — `open /proc/<outer-pid>/ns/ns` ENOENT (bound procfs indexes container pids) |
| outer pidns + `--tmpfs /proc` + inner | **dead** — shim fd sweep needs `/proc/self/fd`; bwrap reads `/proc/sys/kernel/overflowuid` |
| **arm F**: `setcap cap_sys_admin,cap_setuid,cap_setgid+ep bwrap` + outer wrap with **zero `--unshare-*`** + inner captured-argv | **WORKS** — `stat`/`ls` deny sibling; inner `INNER-OK`; caps cleared on child |

Consequence (operator decision): the wrap is **mount-namespace only** —
no pidns, no netns, no userns. `#9723` cannot close here; it requires a
pidns, which requires `systempaths=unconfined` + netns egress plumbing —
a container-posture widening deferred to #9773's topology discussion.


Remaining Phase-0 items (still open under arm F):

- S0.2 Verify `spawnClaudeCodeProcess` round-trip against a stubbed API
  (`test/helpers/hermetic-cli-env.ts` pattern): SDK calls it once per session
  spawn including resume; stdin/stdout protocol flows through bwrap fds 0-2;
  `options.signal` arrives post-grace; **inspect what `SpawnOptions.env`
  actually contains** — if the SDK hands back the constructed child env,
  passthrough is correct; if it merges ambient `process.env`, intersect with
  `buildAgentEnv`'s emitted keyset + minimal ambient (never a hardcoded
  literal list). Also enumerate the child's inherited fd set
  (`/proc/<child>/fd`) against an allowlist — the #8752 fd-hygiene layer is
  shim-side and does NOT cover a hand-rolled spawn.
- S0.3 Kill-semantics probe: `detached: true` spawn → `kill(-pgid)` teardown;
  assert no orphaned `claude` survives AND the server's own process group is
  untouched (without `detached`, `kill(-pgid)` hits the runner). ESRCH on
  already-exited group is caught; the `options.signal` path must not
  double-kill.
- S0.5 Prove `tenant-isolation-probe.sh` executes under preflight Step 10.5's
  bwrap sandbox. NOTE: arm F's probe needs a **file-cap'd bwrap** inside the
  preflight sandbox — file caps are masked by the caller's bounding set, so
  this likely requires `bwrap` to also work via its non-privileged userns
  path there, OR the probe runs privileged on the host. Measure; if
  impossible under Step 10.5 the founder check is reshaped to `judgement`.
- S0.6 Config/transcript strategy: narrow-bind the existing `~/.claude`
  surface (`projects/<encoded-cwd>` rw for resume + the config files the CLI
  reads) onto a `--dir` `$HOME` vs a new per-tenant state root. Narrow-bind
  is the default (no new state root, no DSAR delta, preserves resume
  continuity across the flag flip); a new root is justified only if the
  spike shows the narrow set insufficient.
- S0.7 Arm-F privilege mechanics, end-to-end in a prod-posture container:
  `setcap cap_sys_admin,cap_setuid,cap_setgid+ep /usr/bin/bwrap` requires
  `cap_sys_admin` in the container **bounding set** (`--cap-add SYS_ADMIN`
  on `docker run`) — the app then drops it from effective/permitted/ambient
  (NOT bounding — a bounding drop is inherited and would permanently
  neuter the file cap) so the server process itself never carries it, and
  any exec of `bwrap` elevates transiently through the file cap alone.
  Verify: (a) the drop mechanism at entrypoint; (b) no OTHER binary in the
  image carries file caps (`getcap -r /` audit — every file-cap'd binary
  becomes an app-side SYS_ADMIN carrier); (c) the session process's cap
  sets post-exec contain no `sys_admin`; (d) the inner canary argv is
  byte-identical under file-cap bwrap (privileged path may alter flag
  semantics — `sandbox-canary` replay is the check).
- S0.8 `$HOME` dependents + socat/proxy socket ownership enumeration under
  the arm-F table (`~/.npm/_logs`, `gh` config, `~/.claude/*` reads; whether
  the CLI-created socket dir lands under the session `/tmp` or needs a
  host-side bind).

### Phase 1 — Failing tests (contract first)

- T1.1 Unit: `buildOuterWrapArgv({workspacePath, sessionId, cwd, command})`
  produces a table with NO mount **target** under the workspaces parent
  except the own workspace bind; **contains ZERO `--unshare-*` flags**
  (mountns-only — any userns breaks the inner sandbox, measured); `/proc`
  bound through as-is (shared — #9723 residual); **no `--clearenv`** (it
  would wipe the spawn env — env is composed server-side instead); no
  secret value appears anywhere in argv (credentials ride the spawn env;
  argv carries paths only); never binds `/run` or `$XDG_RUNTIME_DIR`;
  binds `realpath(options.command)` + its package dir; workspace path
  derived from the resolver root (both `WORKSPACES_ROOT` and
  `WORKTREE_ROOT` arms). A separate env-composition test pins: emitted
  child env == `options.env` (per S0.2) + derived overrides {HOME, TMPDIR,
  XDG_*} with `undefined` dropped — a drift test, not argv shape.
- T1.2 Integration (direct-bwrap, `sandbox-isolation-fixtures.ts` style):
  inside a spawned outer wrap, sibling dirs under a stub workspaces root are
  absent from `ls`, `stat`, and `/proc/self/mounts`. `/proc` is intentionally
  unscoped (arm F) — the suite asserts only fs surfaces, and documents #9723
  as the tracked residual. Requires the file-cap'd bwrap path; in the test
  env, cap grant via `setcap` on a copied fixture binary or `bwrap`'s
  userns path — pin whichever the fixture uses.
- T1.3 Mid-session sibling creation stays invisible (the TOCTOU regression
  shape from `sandbox-isolation.test.ts`, re-pointed at the outer wrap).
- T1.4 Fail-closed: missing bwrap/binary/mount-source → session refuses to
  spawn; stderr marker classifies via `classifySandboxStartupError`.
- T1.5 Fixture pin: committed outer-wrap argv fixture + ordering/shape
  assertions (mirroring `denyBeforeRestoreViolations` for the inner argv).

### Phase 2 — Implementation

- T2.1 New module `apps/web-platform/server/agent-outer-wrap.ts`:
  `buildOuterWrapArgv()` (pure — one optional-bag arg, the signature pinned
  to the shape `tenant-isolation-probe.sh` calls, `{workspacePath, sessionId,
  cwd, command}`) + `makeSandboxedSpawn()` returning a
  `spawnClaudeCodeProcess` implementation.
  - Spawn `/usr/bin/bwrap` by absolute path (never PATH — the #8752 shim's
    NEWUSER-deny filter must not inject into the outer namespace).
  - fd hygiene at our layer (the shim's sweep does not cover this spawn):
    `close_range`-equivalent sweep of inherited fds ≥3 beyond the pipes, or
    extract the shim's sweep logic; spike S0.2 asserts `/proc/<child>/fd`
    against an allowlist.
  - `spawn(..., { detached: true, env: <composed env> })`; `kill()` sends
    `process.kill(-child.pid, sig)` with ESRCH caught; `options.signal` wires
    the same teardown without double-kill; `--die-with-parent` stays as the
    belt.
  - `stdio: [pipe, pipe, pipe]` — stderr continuously drained into a ring
    buffer (a paused fd-2 blocks the child at ~64 kB) and attached to emitted
    `error`/`exit` payloads + the `op:tenant-outer-wrap` log.
  - Spawn-time preflight: `accessSync(X_OK)` on `/usr/bin/bwrap`,
    `accessSync` on `options.command` and every bind source; on miss return
    a synthetic failed process (error event + exit 127 + marker), never a
    hanging child (sdk#255).
  - `--chdir <realpath(options.cwd)>`; canonicalize once — `realpathSync`
    feeds bind source, bind dest, `--chdir`, and the hook input — and assert
    `options.cwd` sits under a bound root.
  - Workspace-inode discipline: reprovision must complete before the spawn
    binds (serialize on the dispatch path); a dev+ino parity log (not a
    blocking assert) records a lost race.
  - `AgentQueryOptionsArgs` gains the tenant/session identity fields the
    table needs (`workspaceId`/`sessionId`); `buildAgentQueryOptions` has
    TWO callers — wire both (`cc-dispatcher.ts` and the legacy
    `agent-runner.ts` `startAgentSession` — always `command_center` there).
  - Options drift: flag-off serialization stays byte-identical to today's
    `agent-runner-query-options` snapshot; flag-on adds the key in a second
    pinned shape.
- T2.2 Mount table (arm F — **mountns only, no `--unshare-*`**): privileged
  bwrap (`setcap` file caps — needs `SYS_ADMIN` in the container bounding
  set via `--cap-add SYS_ADMIN` on `docker run`, with the app dropping it
  from effective/permitted/ambient at entrypoint; bounding stays so the
  file cap can elevate). Broad ro-bind of the system image (`/usr`,
  merged-usr links, ld.so cache/conf); minimal `/etc` — regular files via
  `--file` (resolv.conf, hosts, nsswitch.conf, passwd/group), directories
  via `--ro-bind` (`/etc/ssl`, terminfo); `--dev /dev`; `--bind /proc /proc`
  (shared procfs — #9723 residual, accepted); `--tmpfs /tmp` + `TMPDIR`
  pointed there. Derived state roots (each realpath'd + `accessSync`'d,
  fail-closed): own workspace bind; plugin root; `realpath(options.command)`
  + its package dir (the vendored CLI tree — without it every flag-on spawn
  fails closed at exec); `$HOME` = `--dir /home/soleur` + narrow binds of
  `~/.claude/projects/<encoded-cwd>` (rw — resume transcripts, already
  cwd-keyed hence already tenant-scoped) and the CLI config files S0.6
  enumerates (no new state root by default);
  `/app/infra/bwrap-userns-clone3-deny.bpf` + the socat/proxy socket dir per
  S0.8; worktree `.git` gitfile targets under `WORKTREE_ROOT`. The spawn
  env carries the credential set per S0.2's measurement — never argv.
  **Privilege hygiene**: the CLI child post-exec carries only the caller's
  cap set (no `sys_admin`) — bwrap's privileged path clears file caps after
  setup; assert `CapEff`/`CapBnd` of the session process against the app's
  dropped baseline in a test.
- T2.3 Wire `spawnClaudeCodeProcess` into `buildAgentQueryOptions` — behind a
  rollout flag (env, read at dispatch not module load, default off in the
  same image; dark-launch per `wg-dark-launch-deploy-gates`). In-flight
  sessions keep their birth isolation. The flag is a soft one-way door only
  for the narrow-bind fallback contingency; with narrow binds, resume
  continuity survives the flip in both directions. File the
  flag+vestigial-deny deletion issue in this PR (the `denyRead` arm must not
  live forever untracked). A workspace-allowlist arm is worth the small cost
  for cohort-limited first rollout.
- T2.4 `buildAgentSandboxConfig`: **keep** `denyRead:[wsRoot]` unconditional
  while the flag exists — load-bearing on the flag-off arm, vestigial under
  the wrap (the vendored builder skips absent deny landings). This PR touches
  comments only — no per-arm config shape (the
  `agent-runner-helpers.test.ts` drift snapshot stays pinned). `/proc` +
  `c4StagingRoot` denies stay either way.
- T2.5 Personas: the wrap is universal — under the support persona
  `options.cwd` is `pluginPath`, so nothing under the workspaces resolver
  root is bound at all (the derived-root table contains no tenant workspace
  by construction); `knowledge-base/` is absent-by-construction (never
  broad-bind `/app`; the old `denyReadExtra` target is `/app/shared/
  knowledge-base`, now simply unmounted). Plugin root binds `--ro-bind`.
  One parity test for the `allowRead` arm.

### Phase 3 — Canary + observability

- T3.1 Extend `sandbox-canary.mjs` with an outer-wrap arm: capture the
  self-authored argv once (deterministic fixture), replay it at deploy inside
  the canary container, classify EPERM→`sandbox_broken`. **Non-blocking at
  first deploy** — report-only, promoted to gating only after a green soak
  (`wg-dark-launch-deploy-gates`).
- T3.2 In-sandbox realized-state probe (FR6), **dual vantage**: (a) inside the
  outer wrap via Bash — `/proc/self/mounts` carries no sibling-bearing path,
  `/proc` is unscoped under arm F — assert only the mount table; (b) **CLI-process vantage** — a file-tool
  Read attempt on a sibling path returns ENOENT (an inner-Bash probe alone
  cannot see the file-tool tier — it would stay green while siblings remain
  readable to Read/Edit). Emits `feature:agent-sandbox` structured event +
  Sentry mirror. `tenant-isolation-probe.sh` delegates to the same assertion
  set (it must not re-implement a copy that can drift green).
- T3.3 Structured log `op:"tenant-outer-wrap"` per session spawn:
  `{workspace, root, mounts, procMode, outcome}` — discriminating fields for
  the host-vs-sandbox-mount root-cause split (affected-surface rule, Phase
  2.9.2).
- T3.4 Interpose-installed assertion: the per-session `op:tenant-outer-wrap`
  log IS the proof the wrap ran; additionally `verifyAgentSandboxHardening`
  asserts the interpose is wired in `buildAgentQueryOptions` output (a
  boot-probe row would measure the same spawn at a worse vantage — fold any
  binary-reachability check into the T3.1 in-image replay instead).
- T3.5 Operator reproduction path: `op:tenant-outer-wrap` logs the full
  emitted argv per spawn (secrets-free by construction — T1.1 asserts it) +
  a committed debug entry `apps/web-platform/scripts/agent-outer-wrap-debug.sh`
  that replays `bwrap <logged argv> -- bash` for a given workspace path.
- T3.6 Dep-bump smoke: a wrapped-session smoke (or CLI-footprint diff) wired
  into the existing `sandbox-canary-capture-gate` trigger set, firing on
  `@anthropic-ai/claude-code`/SDK version changes — the vendored CLI's fs
  needs are empirical, not contractual, and every bump can add a path the
  derived table misses (repo precedent: `CLAUDE_CONFIG_DIR` does not govern
  `~/.claude/bridge-spawn`).
- T3.7 Follow-Through Enrollment (AC6's soak is time-gated):
  `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` exits 0 when the
  report-only canary verdict has stayed green for the soak window
  (`start=` pinned strictly after deploy, mirroring
  `reconcile-ff-only-sentry-4977.sh`); a tracker issue carries the
  `<!-- soleur:followthrough script=… earliest=<deploy+7d> -->` directive +
  `follow-through` label.

### Phase 4 — ADR-075 amendment + register

- T4.1 Amend ADR-075: Option B adopted in the outer-wrap form; move the
  deferred alternative into Decision consequences; record the loopback
  residual and the file-tool-tier coverage change explicitly.
- T4.2 Art. 30 register entry (honest tense, `adopting` status until
  prod-measured; names the loopback residual and the shared-heap residual
  class deferred to #9773). No public claim (per #9603 discipline).

## Files to Create

- `apps/web-platform/server/agent-outer-wrap.ts` — argv builder + spawn factory.
- `apps/web-platform/test/agent-outer-wrap.test.ts` — unit/integration contract.
- `apps/web-platform/infra/agent-outer-wrap-argv.json` — committed outer argv fixture.
- `apps/web-platform/scripts/agent-outer-wrap-debug.sh` — operator repro entry (`bwrap <logged argv> -- bash`).
- `knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh` — founder-check realized-state probe (pinned; frozen in this plan's freeze commit).
- `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` — soak follow-through probe for AC6.
- `knowledge-base/engineering/architecture/decisions/ADR-075-*.md` amendment (edit, not create).

## Files to Edit

- `apps/web-platform/server/agent-runner-query-options.ts` — wire
  `spawnClaudeCodeProcess` under the rollout flag.
- `apps/web-platform/server/agent-runner-sandbox-config.ts` — vestigial-deny
  simplification + comments.
- `apps/web-platform/server/cc-dispatcher.ts` — pass tenant/session identity
  (`workspaceId`/`sessionId`) through to the options builder.
- `apps/web-platform/server/agent-runner.ts` — second `buildAgentQueryOptions`
  caller (`startAgentSession`, always `command_center`) gets the same fields.
- `apps/web-platform/scripts/sandbox-canary.mjs` — outer-wrap capture/replay arm.
- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — in-image
  verify for the outer fixture.
- `apps/web-platform/test/sandbox-isolation.test.ts` — outer-wrap cases.
- `apps/web-platform/test/helpers/sandbox-isolation-fixtures.ts` — outer-wrap
  spawn helper.
- `apps/web-platform/test/sandbox-canary.test.ts` — fixture pin extension.
- `apps/web-platform/Dockerfile` — `setcap cap_sys_admin,cap_setuid,
  cap_setgid+ep /usr/bin/bwrap`; `getcap -r` audit asserting no other
  file-cap'd binary in the image; entrypoint drops `SYS_ADMIN` from
  effective/permitted/ambient (bounding retained — S0.7).
- `apps/web-platform/infra/cloud-init.yml` — `docker run` gains
  `--cap-add SYS_ADMIN` (bounding-set membership so the bwrap file cap can
  elevate; app itself runs capless after the entrypoint drop).
- `knowledge-base/legal/article-30-register.md` — new TOM row (adopting).

## Scope Check

### Ask Mapping

| # | User ask (verbatim, [issue #5863]) | Plan item | Status |
|---|-----------------------------------|-----------|--------|
| 1 | "Design per-tenant filesystem isolation for the in-process multi-tenant runner (mount-namespace-per-session, or per-agent workspace-only mount, or a topology change to per-tenant subprocess/container)." | Phases 0–3; `agent-outer-wrap.ts`; FR1–FR8 in spec | mapped |
| 2 | "Once shipped, the sandbox `denyRead` for `/workspaces` becomes unnecessary — simplify `buildAgentSandboxConfig`." | T2.4; AC7; flag-deletion issue filed in-PR | **partially mapped** — deny stays unconditional while the flag exists (regression guard); the simplification itself ships with flag deletion |
| 3 | [operator] "Tenants are coming" → full end-state bar (content, existence, mount table, /proc) | P1/P2; T1.2 assertions; FR2/FR3 | mapped |
| 4 | [operator] "Both tiers" — file tools covered | spawn-at-CLI-process design; AC1 covers both surfaces | mapped |
| 5 | [operator] "Fold into #5863" — #9723 + #9725 | #9725: resolver-root derivation (mapped). #9723: measured unclosable in this posture — residual + cross-ref to #9773 | **partially mapped** — re-scoped in the open, operator-approved arm F |
| 6 | [operator] "1 now, 3 tracked" | #9773 filed at brainstorm; ADR amendment records deferral | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| Outer-wrap module + spawn wiring | "mount-namespace-per-session, or per-agent workspace-only mount" | asked |
| Canary/probe extension (T3.1–T3.3) | — | inferred — dark-launch verification is mandated for new deploy-affecting surfaces (`wg-dark-launch-deploy-gates`) and the affected-surface observability rule (2.9.2) requires an in-surface probe |
| Per-tenant config dir | — | inferred — required for resume without re-leaking `~/.claude/projects` transcripts cross-tenant (P7) |
| ADR-075 amendment + Art.30 row | — | inferred — `wg-architecture-decision-is-a-plan-deliverable` + CLO gate requirement |
| `buildAgentSandboxConfig` simplification | "the sandbox denyRead for /workspaces becomes unnecessary — simplify" | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/server`, `apps/web-platform/{scripts,test}`, `knowledge-base` (ADR/legal)
- Planned files: ~10 | Estimated changed lines: ~600-900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (borderline on lines; splitting code from canary would strand the guard unvalidated)

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering

**Status:** reviewed
**Assessment:** (CTO, brainstorm carry-forward; amended by Phase-0 spike)
Outer-CLI bwrap wrap is the sweet spot — covers both tiers, dissolves #9725,
self-authored argv immune to SDK drift, failure scoped to session startup.
Spike corrected the #9723 expectation: a scoped `/proc` requires an outer
pidns, which the vendored inner sandbox cannot survive — the wrap ships
mountns-only (arm F, file-cap'd bwrap) and #9723 stays an open residual.
Plan uses `spawnClaudeCodeProcess` (the SDK's documented interpose —
strictly better than a wrapper script).

### Legal

**Status:** reviewed
**Assessment:** (CLO, brainstorm carry-forward; amended by Phase-0 spike)
No commitment breached; #9723 is a cross-tenant channel that must close or
be recorded as an open residual — the spike measured it **unclosable in the
current container posture**, so it is recorded as the open residual and the
bounded claim names it. Plan runs `soleur:gdpr-gate` (done — see
Compliance), writes the register entry in honest tense (`adopting` until
prod-measured), holds public claims, and ships the realized-state probe —
`/proc` reads leave no audit trail, so the residual's observability is the
canary + naming, not detection.

### Product

**Status:** reviewed
**Assessment:** (CPO, brainstorm carry-forward) Zero alpha-tester perception
today; value is claim-enabling. Under "tenants are coming" this gates the
first hosted tenant — sequencing agreed. Claim ceiling: "process-level
filesystem isolation for sandboxed agent commands".

**Brainstorm-recommended specialists:** none (no specialist named in the
brainstorm's Domain Assessments).

## Observability

```yaml
liveness_signal:
  what: "op=tenant-outer-wrap outcome=ok per-session spawn log + feature:agent-sandbox probe verdict"
  cadence: per session spawn; probe per deploy
  alert_target: "Sentry feature:agent-sandbox"
  configured_in: "apps/web-platform/server/agent-outer-wrap.ts; scripts/sandbox-canary.mjs"
error_reporting:
  destination: "pino + reportSilentFallback → Sentry"
  fail_loud: "spawn refusal throws; classifySandboxStartupError surfaces bwrap_eperm/launcher classes"
failure_modes:
  - mode: "outer wrap cannot build (bwrap missing/EPERM/masked-proc)"
    detection: "in-surface: wrapper stderr marker + op=tenant-outer-wrap outcome=fail {reason}"
    alert_route: "Sentry feature:agent-sandbox"
  - mode: "mount table under-binds (session breaks) vs over-binds (leak)"
    detection: "in-surface: realized-state probe asserts no sibling-bearing mount AND required binds present"
    alert_route: "Sentry feature:agent-sandbox + sdk-startup classifier"
  - mode: "SDK stops calling spawnClaudeCodeProcess (silent unwrapped spawn)"
    detection: "boot self-probe asserts the interpose is installed; per-session log proves the wrap ran"
    alert_route: "deploy-time verify + Sentry"
  - mode: "orphaned claude survives kill"
    detection: "process-group teardown assert in tests; session-reaper count metric"
    alert_route: "Sentry feature:agent-sandbox"
logs:
  where: "stdout pino → journald; Sentry mirrors"
  retention: "journald default"
discoverability_test:
  command: "bash knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh"
  expected_output: "isolation_ok"
```

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-075** (`ADR-075-agent-sandbox-tenant-read-isolation.md`): Option B
  adopted in the outer-wrap form — move Option B from deferred alternatives
  into the decision record; record the new residuals (container loopback
  sharing; shared in-process heap → #9773; inner-layer file masks unchanged);
  note Option C's machinery becomes vestigial for the workspaces root.

### C4 views

- Checked `model.c4`/`views.c4`/`spec.c4` during the C4 completeness pass: the
  change is an internal namespace boundary inside the existing web-platform
  container — no new external actor, external system, container, or data
  store. The tenant↔workspace relationship is already modeled; the isolation
  *mechanism* changes, not the graph. **No C4 impact** (actors/systems/
  relationships enumeration: tenant user, Concierge container, workspaces
  volume, Sentry — all already modeled; none added).

### Sequencing

The ADR amendment ships in the same PR, status `accepted` for the isolation
claim only after the deploy-time probe is green; interim `adopting` wording
per the register discipline.

## Guard Contract

### Guard 1 — outer-wrap realized-isolation probe

**Property.** A sandboxed agent session observes no filesystem entry under the
workspaces parent other than its own workspace. (`/proc` pid scope is out of
scope under arm F — #9723 residual.)

**Assembly.** The probe runs inside the outer wrap at **both** vantages the
property quantifies over: (a) a Bash-side check of `mountinfo` + `ls`/`stat`
of the parent + mountinfo, and (b) a CLI-process (file-tool) Read on a
sibling path — the file-tool tier shares the CLI process's view, so an
inner-bwrap Bash-only probe structurally cannot decide it. The guard sits in
the deploy canary replay plus an opt-in boot self-probe; the
`tenant-isolation-probe.sh` founder-check script exercises vantage (a) and
the session-level AC test exercises (b).

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a sibling bind to the outer argv | probe reports sibling-visible → RED |
| 2 | Add any `--unshare-*` flag to the outer argv (regresses into the dead userns arm) | T1.1 zero-unshare assertion + fixture pin → RED |
| 3 | Reorder own-ws bind before a later parent tmpfs | session ws unwritable/absent → RED |
| 4 | Probe body replaced by `exit 0` (vacuous harness row) | dispatch-count assertion: `mounts==0 && exit 0` is FAIL — the guard's own dispatch is floored |
| 5 | Valid but different table: extra `/usr/local` bind (non-parent, no sibling) | must-PASS — pins that the guard discriminates by *sibling-bearing* mounts, not by argv diff |

### Guard 2 — committed outer-argv fixture pin

**Property.** The outer argv emitted by `buildOuterWrapArgv` matches the
committed fixture under placeholder substitution — drift in the mount set is a
reviewable diff, never a silent one.

**Assembly.** `buildOuterWrapArgv` is the sole producer; the pin compares its
output to `infra/agent-outer-wrap-argv.json` (same canonical-projection idiom
as `sandbox-canary-argv.json`). No second producer exists.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a mount covering the workspaces parent | pin diff → RED |
| 2 | Reorder deny/restore pairs | ordering assertion → RED |
| 3 | Fixture regenerated from the mutated code and committed alongside (self-certify) | the guard's job is reviewability, not integrity — the regenerated diff lands in the same PR for review; this row verifies the test reports a real diff (non-empty mismatch text), not a bare exit code |
| 4 | Test that only diffs against the fixture (harness vacuity) | floor: fixture must contain ≥1 `{{WS}}` placeholder AND zero absolute sibling paths → RED if either absent |

## Acceptance Criteria

- AC1: In a spawned session, `ls`/stat/`findmnt` under the workspaces parent
  shows only the session's own workspace — via Bash AND via a file-tool read
  attempt on a sibling path (both denied by absence, not by hook).
- AC2: ~~`/proc` scoped to session~~ — replaced: `/proc` inside the session
  is the shared container procfs (#9723 residual); the AC suite must NOT
  assert pid scoping. (An outer pidns is measured-fatal to the inner
  sandbox; a host-proc bind never scopes.)
- AC3: A sibling workspace created mid-session remains invisible.
- AC4: No cross-tenant readable/writable scratch remains under `/tmp` or
  `HOME`; `resume`/`continue` keep working — narrow-bound
  `~/.claude/projects/<slug>` preserves transcript continuity across the
  flag flip in both directions (S0.6 default).
- AC5: Outer-wrap construction failure refuses the session with a classified
  startup error (`classifySandboxStartupError` vocabulary) — no degraded spawn.
- AC6: The outer-wrap canary arm ships report-only and records green on ≥1
  real deploy before any gating promotion (`wg-dark-launch-deploy-gates`).
- AC7: `denyRead:[wsRoot]` remains unconditional on the flag-off arm (no
  flag-off isolation regression); under the wrap it is vestigial and
  documented as such; removal is the flag-deletion follow-up.
- AC8: ADR-075 amended; Art. 30 register row written in `adopting` status.
- AC9: Rollout flag defaults off; enabling is an image+env change with no
  schema migration.
- AC10: No secret value appears on the outer argv or in the bwrap process's
  `/proc/<pid>/cmdline` (asserted by T1.1's env/argv drift test).
- AC11: A workspace reprovision (same path, new inode) is serialized before
  the spawn binds; a lost race is surfaced by the dev+ino parity log line.
- AC12: `options.resume` under flag-on reads transcripts through the narrow
  `~/.claude/projects/<slug>` bind — resume works, no stale-resume break.
- AC13: Support persona: the outer table binds nothing under the workspaces
  resolver root (cwd is `pluginPath`); `knowledge-base/` (`/app/shared/
  knowledge-base`) is absent-by-construction; `allowRead` arm unaffected.

```
founder_check:
  kind: command
  text: "Two-tenant realized probe — done = a runtime probe shows tenant A's session namespace cannot see tenant B's workspace on any filesystem surface (ls/stat of the parent, mountinfo)."
  command: bash knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh
  expected: isolation_ok
  pins:
      knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh: 409f1d0c9ab2dd4d4e4a00530fea7cb7d984021b
  approved_by: deruelle
  approved_at: 2026-10-08
```

## Test Scenarios

- Given a two-workspaces fixture root, when a session spawns for workspace A,
  then workspace B is absent from `ls <root>` and `/proc/self/mounts` inside.
- Given the outer wrap active, when `cat /proc/<sibling-agent-pid>/environ` is
  attempted (pid from the host's view), then the pid does not exist inside.
- Given `GIT_DATA_STORE_ENABLED=true` arm, when the resolver returns a
  `WORKTREE_ROOT` path, then the outer table binds under that root and no
  `/workspaces` assumption leaks.
- Given bwrap absent or EPERM (profile regression), when a session starts,
  then spawn refuses with `bwrap_eperm`-class error and a Sentry event fires.
- Given resume (`options.resume`), when the session spawns flag-on, then the
  same outer table applies and the pre-flip transcript dir is reachable via
  the narrow `~/.claude/projects/<slug>` bind — resume works both sides of
  the flip.
- Given a symlinked `WORKSPACES_ROOT`/`WORKTREE_ROOT` or workspace dir, when
  dispatch runs, then one `realpathSync` value feeds bind source, bind dest,
  cwd, and the hook — no hook/namespace divergence.
- Given the rollout flag OFF, when a session spawns, then `denyRead` still
  carries the workspaces root (no regression from today's baseline).
- Given a `GH_TOKEN`-bearing `options.env`, when the outer argv is emitted,
  then no secret value appears in argv; the child env carries it.

## Open Code-Review Overlap

- `#3243` arch: decompose cc-dispatcher.ts — **Acknowledge.** Our edit is a
  narrow pass-through (option field wiring); the decomposition scope-out is a
  different concern that stays open.
- `#3242` review: tool_use WS event lacks raw name field — **Acknowledge.**
  Unrelated surface in the same file; no interaction with spawn options.

## Risks / Sharp Edges

- **Nested bwrap on the deployed kernel/profile** — the #5873 split-unshare
  class lives here; Phase 0 spike is the gate, and the deploy canary replays
  the real argv before the flag flips.
- **Measured, not projected:** fresh `--proc` EPERMs under Docker masked
  paths and the masks are unremovable from inside a userns — arm F keeps
  `/proc` shared and records #9723 as an open residual (#9773 topology is
  the honest close). Never let a bound host procfs get described as scoped.
- **File-cap'd bwrap is new privilege surface** — `cap_sys_admin+ep` on the
  binary means any exec of it elevates transiently; mitigate by keeping the
  file cap on bwrap only (`getcap -r /` audit at image build), the app
  dropping SYS_ADMIN from effective/permitted/ambient (bounding retained so
  the file cap can elevate), and `--cap-add SYS_ADMIN` scoped to the deploy
  change in cloud-init.yml.
- **Under-binding breaks the CLI** — mitigated by derived-state-roots +
  broad-system-image strategy (not a literal list) plus S0.1's real-session
  spawn; the canary replays the argv in-image.
- **Kill propagation** — `detached:true` + `kill(-pgid)` + `--die-with-parent`;
  orphan check in S0.3; a bare-PID kill would orphan the CLI.
- **Env/cmdline leak** — secrets must never reach argv (`/proc/.../cmdline` is
  same-uid readable); spawn env composition measured at S0.2.
- **Loopback residual (graded as egress-bypass, not covert channel)** —
  shared `127.0.0.1` lets a non-entitled session egress *through a sibling
  session's socat proxy* (its `allowedDomains` entitlement), plus any
  tenant-bound listener or server-internal admin endpoint. Named residual;
  S0.1 checks whether proxies can move to per-session sockets; full closure
  belongs to #9773's topology work or per-session netns design.
- **Other named residuals the wrap does NOT close:** abstract unix sockets and
  `connect(2)` to known-path sockets (fs-invisibility ≠ connect-block);
  nested-userns creation inside the outer wrap (deliberately unfiltered for
  the inner shim); the server process's own cross-tenant fs access (hooks,
  dispatcher git ops); shared in-process heap (BYOK leases, session state →
  #9773).
- **Resume continuity** — narrow-binding `~/.claude/projects/<slug>` keeps
  the same host dir, so the flag flip preserves resume in both directions.
  If S0.6 shows the narrow set insufficient and a new per-tenant root is
  adopted instead, the flip becomes a one-time transcript-continuity break —
  named in rollout notes then.
- **Workspace-inode pinning** — reprovision swaps the inode under the same
  path; bind happens at spawn, so reprovision must serialize before spawn
  (or the post-spawn dev+ino assert catches a lost race).
- **Flag mechanics** — rollout env flag read at dispatch, not module load;
  cutover mid-flight is not supported (in-flight sessions keep their birth
  isolation).

## Session Summary (evidence notes)

- Premise probes: `gh issue view` on 5863/5862/9723/9724/9725/4891/5733/6641;
  `gh pr view 9709`; release runs green post-merge.
- SDK surface: `sdk.d.ts:2431` `spawnClaudeCodeProcess`, `:9328` SpawnedProcess,
  `:9380` SpawnOptions.
- Overlap check: `gh issue list --label code-review --state open` scanned
  against the Files lists.
