# ADR-050: LikeC4 diagram re-render at runtime via out-of-process CLI spawn

- **Status:** Accepted
- **Date:** 2026-06-05
- **Deciders:** Jean (operator), CTO (architecture review)
- **Relates to:** PR #4963 (Layer 1 honesty), PR #4965 / #4964 (this change), ADR-033 (Inngest child-process-spawn precedent)

## Context

The LikeC4 C4-model visualizer renders from a **precomputed, layouted**
`model.likec4.json`. Until now that artifact was regenerated **only out-of-band**
via `/soleur:architecture render` (which runs `npx likec4 export json`). A
Code-tab Save (or the Concierge `edit_c4_diagram` tool) committed the `.c4`
source but left the rendered diagram stale.

The original posture, documented in `lib/c4-constants.ts` and
`app/api/kb/c4/project/route.ts`, was an explicit **"never render at runtime"**:
the `likec4`/`@likec4/language-services`/`@likec4/layouts` toolchain drags
vite/esbuild/bundle-require into prod deps and breaks the npm10/npm11
lockfile-sync parity that prod `npm ci` requires. Only `@likec4/core` +
`@likec4/diagram` (the client renderer) are installed.

PR #4963 (Layer 1) made the staleness honest (a banner). This change (Layer 2,
#4964) reverses the "never render at runtime" posture for the **write path
specifically**, so the diagram actually updates after a save.

## Decision

After `writeC4Diagram` commits a `.c4` source and syncs the workspace clone,
regenerate `model.likec4.json` by **spawning the `likec4` CLI out-of-process**
(`server/c4-render.ts`, modeled on `server/pdf-linearize.ts`), commit the
regenerated JSON via the same GitHub Contents API path, and re-sync. The
existing client `reload()` then surfaces the fresh `dump`.

Key constraints that make this NOT a reversal of the lockfile-parity rule:

1. **The CLI is spawned, never imported.** It is preinstalled as a Dockerfile
   global (`npm install -g likec4@1.50.0`, the `@anthropic-ai/claude-code`
   precedent), NOT a `package.json` dependency. vite/esbuild never enter prod
   deps; lockfile parity is untouched. The "never render at runtime" rule
   becomes, more precisely, "never *import* the toolchain into the bundle."
2. **The CLI lays out via bundled graphviz-wasm** — no native `dot` binary
   needed (verified: `likec4@1.50.0 export json` exits 0 with no `dot` on PATH).
3. **In-process, synchronous, failure-isolated.** `writeC4Diagram` runs in the
   Next/custom-server process (not the bwrap agent sandbox), where
   `child_process.spawn` is established precedent (`pdf-linearize.ts` → qpdf,
   `push-branch`/`git-auth` → git). The re-render is best-effort: a render /
   commit / sync failure is reported via `reportSilentFallback` and returns
   `rerendered:false`, degrading to the Layer-1 honest-stale banner. The `.c4`
   commit is load-bearing and is NEVER rolled back.

### Alternative rejected: Inngest out-of-process job (ADR-033 pattern)

The deferred fallback was an Inngest function shelling out to the CLI, with the
UI polling for the refreshed dump. Rejected because the synchronous in-request
path (bounded 25s, dev-cohort-gated, human-paced saves) delivers the
"Saved — diagram updated" UX directly, whereas the async job would force the
stale banner on every save (eventual consistency) for no benefit at this scale.
If a future constraint forbids spawning on the request path, the Inngest
function remains the template.

## Consequences

- **Positive:** the diagram visibly updates after a save with no manual
  `/soleur:architecture render`; both write surfaces (UI + Concierge) benefit
  from the single `writeC4Diagram` funnel.
- **Cost — double commit:** each save yields a paired `.c4` + `model.likec4.json`
  commit (acceptable; mirrors the manual render workflow). Could be folded into a
  single Git Trees write later (Non-Goal).
- **Cost — version dual-pin coupling:** the Dockerfile `likec4@X` pin must track
  the `package.json` `@likec4/core`/`@likec4/diagram` version so the exported
  schema matches `LikeC4Model.create`. Drift-guarded by
  `test/c4-likec4-version-pin.test.ts` (fails CI if the pins diverge).
- **Cost — latency on the save path:** multi-second worst case, bounded by
  `RENDER_TIMEOUT_MS=25s` + a concurrency gate (default 2, env
  `C4_RENDER_CONCURRENCY`). `maxDuration=60` on the PUT route is a forward-compat
  platform hint; the in-code timeout is the real bound under the custom server.

## Amendment — 2026-09-22 (#8542)

`renderC4Model` no longer returns the CLI's bytes verbatim. After the elements gate, it returns
them in the canonical format from `lib/c4-canonical.mjs`: one value per line, with view hashes
blanked. It does this so the app and the repo/plugin writers emit identical files (ADR-235
amendment of the same date). A canonicalize failure maps to `io_error`, and nothing is committed.

## Amendment — 2026-09-24 (#8623): the render input is the committed source set, fetched from GitHub; never the tenant workspace

**Invariant.** Tenant workspace content — the worktree **and** its `.git` — is untrusted input to
any server-side tool. A sandboxed agent can write it (`allowWrite: [workspacePath]`; the Agent SDK's
built-in deny list covers `.git/hooks` and `.git/config` but not `.git/objects`, refs or `HEAD`).
GitHub is trusted only for the **modes and bytes at a fixed commit sha**, never for the content
itself: the tenant can push anything.

**Correction.** The Decision's SECURITY framing ("no command-injection or scope-escape surface
here") held for the argv and was false for the input directory. likec4 1.50.0 executes a
`likec4.config.{js,cjs,mjs,ts,cts,mts}` anywhere under its cwd, honours `.likec4rc` /
`likec4.config.json` `include.paths`, and follows symlinks. Measured with the pinned binary and the
server's argv/env: a tracked config in the diagrams folder or a subfolder ran (sentinel written);
a symlinked directory's and an `include.paths` directory's elements reached the exported model.
The acceptance suite was RED on `renderC4Model(workspacePath)` as it stood at `main` `ca83c8edf0`.

**Decision.** `renderC4Model(stage)` takes no workspace path. It creates a `mkdtemp` directory
under a server-private staging root (`server/c4-staging-root.ts`, default
`~/.cache/soleur-c4-render`, never `os.tmpdir()`; the root must be a real directory owned by the
server's uid), lets `stage` fill `<dir>/src` **before** taking a render slot and under a 10 s
deadline that aborts in-flight requests, re-verifies after taking the slot that `<dir>/src` holds
exactly the staged files, then spawns likec4 with `cwd = <dir>/src`, `-o <dir>/model.likec4.json`
and `HOME = <dir>` (node's module fallback would otherwise execute `$HOME/.node_modules`
packages, measured). In production `stage` is
`stageCommittedC4Sources` (`server/c4-stage-sources.ts`): it lists the diagrams subtree of the
commit GitHub returned for the `.c4` write (Contents API for the folder's type and tree sha, then
the recursive Trees API for true modes), refuses likec4 configs (all nine names), symlinks,
submodules, a truncated listing, more than 50 sources or more than 4 MiB of sources as
`unsafe_source` **before any blob is fetched**, then fetches only regular-file
`.c4`/`.likec4`/`.like-c4` blobs (at most 8 in flight, each verified against its git blob sha and
cached by sha; the bytes just committed are not re-downloaded) and writes them `wx`/`0600`. The extension
allowlist is the security control; the refusals exist so the user is told (a warning-level Sentry
event and a class-specific `rerenderDiagnostic`) instead of getting a model that differs from what
the repo declares. The staging root is created and added to the agent sandbox's `denyRead`, so a
tenant's agent (every session built by `buildAgentSandboxConfig`) can neither write a config into a
stage between staging and spawn nor read another tenant's staged sources; the sandbox canary
placeholders it (ADR-079 amendment of the same date).

The model commit is conditioned on the SOURCE SET: before the PUT the writer re-reads HEAD's
diagrams listing and requires its source set (path + blob sha pairs) to equal the rendered one;
otherwise a newer source change is on HEAD and this render is superseded (`logger.warn
event=c4_rerender_superseded`, no Sentry, no diagnostic — a newer save through the editor or
Concierge renders its own; a change pushed from outside Soleur is picked up by the next save). The
PUT carries HEAD's model sha from that same listing, so a model committed in between fails it
(409/422) and the check runs once more. Comparing sources, not model bytes, is what stops an older
render landing after an undo: an undo restores the old model bytes, never the old source set.

**Alternatives rejected.** Rendering inside the bwrap agent sandbox (contains execution instead of
removing the config from the input; sandbox orchestration on a synchronous save path). Reading the
local object store with per-object hash verification (the agent can write `.git/objects`, refs,
`HEAD` and `objects/info/alternates`; correctness would need Merkle verification, git env
hardening and alternates/gitfile/promisor handling, against ~3 API calls). Staging from the
worktree with `lstat`/`O_NOFOLLOW` (includes untracked agent-written files; TOCTOU against a
writing agent). Silently skipping configs (commits a model different from the repo's).

**Residuals.** The likec4 child still runs as the app's uid; with no config it only parses DSL,
bounded by the spawn timeout. Wrapping it in bwrap is defence in depth, tracked as #8696. A `.c4`
with a relative `icon` path bakes the random staging path into the model (it already baked the
workspace path). A `file://` icon URI under the stage is rewritten to a stable `/c4-sources` root so the committed
model does not change on every save. The editor's staleness banner copy is tracked as #8695. `syncWorkspace`'s
`git pull` in the tenant workspace is a separate surface, measured separately.

> **Superseded 2026-09-24 (#8696, #8695):** the first two sentences of the Residuals paragraph above
> (the child runs as the app's uid; bwrap tracked as #8696) and the banner-copy sentence (#8695) are
> resolved by the amendment below. The icon and `syncWorkspace` sentences still stand.

## Amendment — 2026-09-24 (#8696, #8695): render child sandboxed; wasm layout pinned

**Decision.** The likec4 child runs as
`/usr/bin/choom -n 1000 -- /usr/bin/bwrap <argv> -- /usr/bin/prlimit --nproc=64 -- node likec4 export json --no-use-dot -o /c4-out/model.likec4.json .`
(`server/c4-render.ts`, `buildLikeC4SandboxArgv` + `renderCommand`; one `spawn(` site). The argv:

- `--die-with-parent --new-session`; `--unshare-user/pid/net/ipc/uts` (user/pid/net are the set the
  deploy canary proves for the Agent SDK argv, ADR-079; ipc/uts are admitted by the same seccomp
  `CLONE_NEWUSER` rule and proved by the boot self-probe).
- An **allowlisted root**: `--ro-bind /usr /usr`, merged-usr symlinks for `/bin /lib /lib64 /sbin`,
  and `--ro-bind` of `/etc/ld.so.cache`, `/etc/passwd`, `/etc/group` (likec4 calls `os.userInfo()`
  at import and crashes without passwd). An allowlist rather than `--ro-bind / /` plus masks: the
  next mount added to the container is excluded by construction.
- **No `/proc`.** `--proc /proc` is EPERM in this Docker setup, and binding the parent's `/proc`
  (as the SDK argv does) would expose `/proc/<server-pid>/environ` — the exposure this removes.
- `--dev /dev`; `--size 64MiB --tmpfs` for `/dev/shm`, `/tmp` and `/c4-home`; the staged sources
  `--ro-bind`ed at `/c4-sources` (the cwd); `<stage>/out` `--bind`ed at `/c4-out` (the only
  writable bind from the host); then `--remount-ro /dev` and `--remount-ro /` after every mount.
- `--clearenv` plus exactly `PATH`, `HOME=/c4-home`, `TMPDIR=/tmp`, `LANG=C.UTF-8`
  (bwrap adds `PWD`). bwrap's own environment is the existing allow-list, so it never sees a secret.
- `--json-status-fd 3`: bwrap writes `{"exit-code": N}` only after the child it set up has run.
  A non-zero exit with no such record is `sandbox_error` (setup failed); with one it is
  `non_zero_exit`. The child cannot reach fd 3 (measured), so it cannot forge the distinction.
- Outside the sandbox, `choom -n 1000` makes the render the OOM killer's first choice over the
  server; inside, `prlimit --nproc=64` caps its process count (likec4 peaks at 13 tasks; the limit
  is per user namespace, so a concurrent server spawn still succeeds — measured).
- Outside production only, the install prefixes of node and likec4 are added as `--ro-bind p p`
  (after the tmpfs mounts) so CI's `/opt/hostedtoolcache` node runs. **Production pin:** with
  `NODE_ENV=production`, bwrap, node and the likec4 entry must all resolve under `/usr` and no extra
  bind may exist, else the render returns `sandbox_error` without spawning.

**Fail closed.** Every sandbox failure (launcher missing, setup failure, binaries unresolvable or
outside `/usr`, a sandbox that does not exit) is `sandbox_error` → the internal diagnostic; the
`.c4` is still committed. `C4_RENDER_SANDBOX=off` selects a direct spawn (still `--no-use-dot`) only
when `NODE_ENV !== "production"`; there is no other unsandboxed path.

**The host does not trust the child's output (Guard 5).** This extends the spirit of AP-020 from
the hook stdin envelope (the register's scope) to child-written files: the model is read through
one fd opened `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, `fstat`-checked as a regular file of at most 20 MiB,
and read from that fd — a planted symlink, FIFO or oversize file is `io_error`, never followed or
waited on (measured with real bwrap: the child can plant the symlink; the host refuses it). After a
timeout the host waits up to 5 s for the child's `close` (every sandbox process gone) before
settling, and if it never comes the stage is left for the stale sweep rather than removed while a
sandbox process can still write into it.

**Wasm layout pinned; zero-view models refused.** likec4 1.50.0 defaults `--use-dot` to true when
it detects a container (`/.dockerenv`). The runner image has no graphviz, so every production
render since #4964 laid out with a missing binary: exit 0, all elements, **zero views**, which the
elements-only gate committed. `--no-use-dot` pins wasm layout (the same engine the plugin's
regenerator uses outside containers), and a views gate returns `layout_failed` (internal diagnostic,
previous model kept) for any export without a non-empty `views` object. A successful layout always
emits at least `index`, so this never blames the user's source.

**Render pool.** This module is bundled twice into one process (the custom server via the
Concierge tool, the Next route), so the concurrency counter lives on
`globalThis[Symbol.for("soleur.c4RenderPool")]`: one `POOL_SIZE` (default 2) per process. A render
waits at most 10 s for a slot, then returns `timeout` / `render slot wait` (Sentry warning: load,
not a defect). Worst case before the model commit: stage 10 s + slot 10 s + spawn 25 s + kill
grace 5 s + `rm` ≈ 50 s.

**Observability.** Failures reach Sentry via `reportSilentFallback(null, …)` (a real `Error` loses
its tags to the pino mirror, #8629) with message `c4 re-render failed: <reason>` and tags
`reason`, `phase`, `detail_class` (`bwrap-setup`, `bwrap-enoent`, `outside-usr`, `not-resolvable`,
`sandbox-no-exit`, `output-rejected`, `zero-views`, `slot-wait`, `likec4-exit`, `other`), so each
failure class opens its own issue and fires the default first-seen alert. **Boot self-probe:**
`verifyC4RenderSandboxOnce()` runs inside the server's `listen` callback in production, never
awaited, and renders a 2-element fixture through the same spawn site and argv — in the real
container, under the real seccomp and AppArmor profiles, on every start including the canary
container. Success emits a Sentry info event `event_type:c4-sandbox-probe` (info pino lines never
reach Better Stack); failure emits `op=sandbox-selfprobe`. It is report-only: it never gates a
deploy (learning 2026-06-04: dark-launch a new probe report-only first). It also reports, by count
only, any file/dir fd ≥ 3 the server holds without close-on-exec.

**Banner (#8695).** The save's `rerenderDiagnostic` now reaches the staleness banner, whose second
line states it; with no reason (only a supersede by a newer source change) it says so and promises
no refresh. A resync failure after a committed model now carries the retry diagnostic.

**Measurements** (replica of the runner stage: `node:22-slim@sha256:4f77a690…` + `likec4@1.50.0` +
apt `bubblewrap` **0.8.0**, `--security-opt seccomp=infra/seccomp-bwrap.json`, `--cpus 2 --memory
2g`, this repo's 82-view model; AppArmor not loaded on the measuring host — the boot probe closes
that gap in the real container). CI runs a newer bwrap from `ubuntu-latest`; every option used
exists in 0.8.0.

| Measurement | Result |
|---|---|
| final argv, repo model | rc 0, 82 views, 4.5 s; **byte-identical** to the unsandboxed render |
| peak tmpfs use (`du -sb`) | `/tmp` 60 B, `/c4-home` 160 B, `/dev/shm` 40 B → 64 MiB cap |
| unsandboxed, no flag (today's prod) | rc 0, **0 views**, ~20k stderr lines (`dot` not found) |
| two concurrent renders | 12.5 s wall, cgroup `memory.peak` 366 MiB |
| `--json-status-fd` | `child-pid` is written even when setup fails; `exit-code` only after the child ran; a payload printing `bwrap: forged` and exiting 7 records `exit-code: 7`; fd not inheritable |
| `prlimit --nproc=64` inside | a fork loop capped at 61; a concurrent host spawn succeeded; likec4 renders down to `--nproc=12` |
| `choom -n 1000` outside | sandboxed process `oom_score_adj=1000` |
| `setpriv -d` inside | `no_new_privs: 1` |
| writes | `/`, `/dev`, `/c4-sources` read-only; `/tmp`, `/c4-home`, `/dev/shm` writable; `/workspaces`, `/app`, `/proc` absent |
| `--disable-userns` | fails: `/proc/sys/user/max_user_namespaces: Read-only file system` → not used |

**Alternatives rejected.** Deny-list root (`--ro-bind / /` + masks); `--proc /proc` (EPERM); the
parent `/proc` (exposes environ); `--disable-userns` (fails here); `RLIMIT_AS` (V8/wasm reserve large
virtual ranges); a container `--pids-limit` (host-wide change for one render); stdout output instead
of `/c4-out` (`/dev/stdout` needs `/proc`); a deploy-canary row as a gate (couples rollback to an
unproven probe; promote once the boot probe has a clean record); a dedicated IaC Sentry alert (the
first-seen route plus `detail_class` covers it and would move `c4-count-parity`'s rule counts);
falling back to an unsandboxed spawn (a silent downgrade); installing graphviz instead of
`--no-use-dot` (a second layout engine diverging from the plugin regenerator's).

**Residuals.** The disk-backed `/c4-out` is unsized: a compromised child can fill disk for at most
25 s. Memory is bounded by the container `--memory` cap, not per render. The child can create
nested user namespaces (seccomp allows `CLONE_NEWUSER`; `--disable-userns` fails), so kernel
privilege-escalation bugs stay in scope — equally true of the agent sandbox. A Concierge
`edit_c4_diagram` completing while the editor is open does not reload it (tracked separately).
