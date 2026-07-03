# ADR-081: Char-device residual at `.git/config.lock` — substrate root cause and privileged non-blind sweep remediation

**Status:** adopting (→ accepted once the 7-day AC10 soak confirms non-recurrence; #5934)
**Date:** 2026-07-03
**Deciders:** Engineering (CTO carry-forward from the 2026-07-03 config.lock-wedge-fix brainstorm)
**Related:** #5934 (this durable fix), #5912 / PR #5932 (in-session `atomic_git_config` self-heal), PR #5907 (instrument), ADR-068 (multi-host git-data), ADR-075 (agent-sandbox tenant read isolation), ADR-079 (faithful sandbox canary)

## Context

The confirmed root cause of the Concierge worktree-creation wedge (tracker #5912) is
that `.git/config.lock` in the agent sandbox is sometimes a **non-regular file — a
character device**, write/remove-protected. git creates its config lock via
`open(O_CREAT|O_EXCL)`, which fails `EEXIST` against **any** pre-existing inode
(POSIX open(2): "fail if the file exists" — not "if a regular file exists"), so every
`git config` write in `ensure_bare_config()` fails and worktree creation is permanently
wedged with no in-sandbox recourse (the blind agent has neither the privilege to remove
the node nor a non-`rm` path to it).

**The decisive question was WHERE the char device originates.** Three candidates:

- **(a) An explicit `.lock` / `*.lock` mask in this repo's sandbox config** — **RULED OUT.**
  `apps/web-platform/server/agent-runner-sandbox-config.ts` passes only **directory**
  paths to the Claude Agent SDK's `filesystem.denyRead` (sibling tenant workspaces +
  `/proc`) and only the agent's own workspace to `allowWrite`. There is no `.lock`, no
  glob, and no file-level `/dev/null` mask anywhere in the repo sandbox config. This
  **answers #5934's re-evaluation criterion (1): the masking is single-path, not glob**
  — a character-device wedge is a per-path substrate artifact, which **de-risks #5912**
  (its atomic temp file's `.lock` sibling is a fresh, never-before-masked path).
- **(b) SDK-internal bubblewrap behavior driven by our config** — **RULED OUT as the cause.**
  The SDK's file-level `/dev/null` mask fires only for a **file path** in `denyRead`; the
  repo passes only directory paths, so the SDK never receives `.git/config.lock` to mask.
  (The mechanism exists in the SDK; our config never exercises it. This ruling is
  SDK-pin-dependent — installed SDK v0.3.197; a future bump should re-verify — but the
  conclusion holds regardless because the file-mask path is never reached.)
- **(c) The container filesystem / mount substrate** — **THE ORIGIN.** The node is a
  **residual** char-special inode at one historical path on the **persistent host block
  volume** that holds the bare repos. Confirmed topology (`ci-deploy.sh:899`): the
  Concierge container runs `-v /mnt/data/workspaces:/workspaces`, so the bare repos live
  on a **bind-mounted persistent volume, NOT the container overlay2 upper layer**. The
  SDK/bwrap base `--ro-bind / /` faithfully re-exposes any pre-existing char-special
  inode into the sandbox.

## Decision

The durable remediation is a **root-privileged, non-blind, character-device-scoped
sweep** that clears any residual `config.lock` / `config.worktree.lock` **before** an
agent session uses the repo — NOT an in-sandbox mask change (there is no mask to narrow)
and NOT an unconditional in-sandbox `rm -rf` (blind surface + no privilege).

- **Layer:** the persistent host volume `/mnt/data/workspaces`, host-side. overlay2 does
  not overlay the bind mount, so a `Dockerfile`-layer sweep would never see the node.
  ADR-068's `/mnt/git-data` (not-yet-GA multi-host, `replicas=1`) is deliberately **not**
  swept.
- **Timing:** a **quiescent window** — `ci-deploy.sh`'s pre-`docker run` slot (old
  container stopped, canary not yet running). **Ordering is the concurrency-safety
  mechanism**: never a periodic timer against a live volume (under a future ADR-068
  shared-git-data topology the volume is not quiescent and a periodic sweep would race a
  live writer). Delivered via the webhook infra-config chain
  (`git-lock-chardevice-sweep.sh`), so existing hosts get it on the next deploy.
- **rdev-aware removal (kernel-grounded discriminators):** a **plain** char-special
  inode is cleared with `rm -f`; a **bind-mounted** device node (e.g. a bound `/dev/null`,
  `rdev 1:3`) returns `EBUSY` on unlink and MUST be `umount`ed first, else the sweep
  silently "succeeds" while the wedge persists. `rdev 0:0` ⇒ an overlay whiteout;
  other non-zero ⇒ a real `mknod` device.
- **Forensic sharpening (ships regardless):** `worktree-manager.sh`'s
  `sweep_stale_git_locks` now types a char-device lock as `type=chardevice`, emits its
  `rdev` (the substrate discriminator) and mount-visibility on the blind-surface
  `SOLEUR_GIT_LOCK_DIAG`/`UNREMOVABLE` line, and probes `trusted.overlay.whiteout` on a
  regular lock — so the next real wedge (or a forced fixture) proves the exact mechanism
  in one event.

The **"#5912 becomes dead-code insurance" claim holds ONLY** under the assumption that the
node is a one-time persistent-volume artifact (created once, cleared at the next quiescent
boot/entrypoint, never re-appearing mid-container-lifetime). This is plausible — a
char-device `config.lock` is not what a git-killed-mid-write leaves (that is a *regular*
stale lock the in-sandbox age-guard already handles) — but it is an assumption, and the
AC10 7-day soak is its empirical test. If the node can appear mid-lifetime, entrypoint/boot
granularity cannot preempt it and #5912 stays load-bearing.

## Alternatives Considered

- **(i) In-repo mask allow-list of git's lock acquisition** — rejected: no mask exists to
  narrow (criterion 1 answer). Not applicable.
- **(ii) Unconditional in-sandbox `rm -rf` of the char-device lock** — rejected:
  blind surface + no privilege; auto-`rm -rf` on a blind surface is out of scope.
- **(iii) #5912 lockless writer alone** — accepted as the PRIMARY in-session fix, but
  rejected as the DURABLE fix: the device node persists on the substrate; #5934 is
  explicitly the "remove the node" tracker.
- **(iv) Vendored-SDK bwrap-arg reorder** — non-goal here; tracked separately under
  ADR-075's "durable TOCTOU closer", unrelated to the residual node.

## Observability (no-SSH)

- **Liveness:** `git-lock-chardevice-sweep.sh` writes a JSON state file
  (`/var/lock/git-lock-chardevice-sweep.state`) and emits one `SOLEUR_CHARDEV_SWEEP_*`
  marker per node to the host journal (routed by `vector.toml`); readable via the
  `cat-*-state.sh` pattern.
- **Fail-loud:** a failure to remove a detected node emits a loud
  `SOLEUR_CHARDEV_SWEEP_FAILED` marker; never silent.
- **Regression signal:** the in-sandbox `SOLEUR_GIT_LOCK_UNREMOVABLE … type=chardevice
  rdev=…` line — a wedge that reached a live session despite the sweep. Its `rdev` field
  discriminates all competing substrate hypotheses in ONE event.
- **Soak (AC10):** `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` asserts
  zero char-device UNREMOVABLE events for 7 days post-deploy; PASS closes #5934.

## C4 impact

**None.** All three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) were
read. This is an internal filesystem-substrate maintenance step within already-modeled
containers (Agent Runtime `claude`, the `/workspaces` compute cluster `hetzner`); it adds
no element, edge, or actor, so no `.c4` edit is in scope.

## Consequences

- Positive: the wedge is removed at the substrate before it can reach a live session; the
  in-sandbox forensic now proves the mechanism deterministically; the fix is
  repo-expressible IaC, not a pure upstream ask.
- Negative / watch: the sweep runs per deploy (a fast no-op when clean); the
  "dead-code insurance" reclassification of #5912 is conditional on the AC10 soak; a
  future ADR-068 shared-git-data topology would require re-validating the quiescence
  assumption before any periodic variant.
