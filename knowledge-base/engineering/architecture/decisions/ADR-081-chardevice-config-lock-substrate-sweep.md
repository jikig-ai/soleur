# ADR-081: Char-device residual at `.git/config.lock` — substrate root cause and privileged non-blind sweep remediation

**Status:** adopting (→ accepted once the 7-day AC10 soak confirms non-recurrence; #5934)
**Date:** 2026-07-03
**Deciders:** Engineering (CTO carry-forward from the 2026-07-03 config.lock-wedge-fix brainstorm)
**Related:** #5934 (this durable fix), #5912 / PR #5932 (in-session `atomic_git_config` self-heal), PR #5907 (instrument), ADR-068 (multi-host git-data), ADR-075 (agent-sandbox tenant read isolation), ADR-079 (faithful sandbox canary)

> **CORRECTION (2026-07-05, #4826 — the root cause below is WRONG).** A fresh Concierge
> session still wedged after this ADR's host sweep shipped and ran clean (DONE markers,
> zero FAILED). Live probing from the wedged session (`findmnt -T .git/config.lock`)
> proved the node is **`tmpfs[/null]` — a deliberate, per-path, read-only `/dev/null`
> bind-mount on the literal `.git/config.lock`**, with an arbitrary `config.soleur-probe.lock`
> beside it left a normal writable file (⇒ **single-path, not glob**). That is the Claude
> Agent SDK's **bubblewrap file-mask (candidate "b" below), applied per-session INSIDE the
> sandbox** as a git-config-RCE guard — **NOT** a container-filesystem residual inode on the
> persistent volume (candidate "c", which this ADR adopted). Candidate (b) was ruled out
> here on the assumption the repo passes only directory paths to `denyRead`; the live mount
> evidence overturns that. **Consequences:** (1) the host-side `-type c` sweep (#5934) clears
> a real but effectively non-occurring case — it can never see a per-session in-sandbox bwrap
> mount; keep it as cheap insurance but it does NOT unblock live sessions. (2) The durable fix
> is to make the in-sandbox worktree path **need no config write at all**: pre-seed
> `core.repositoryformatversion=1` + `extensions.worktreeConfig=true` (and clear `core.bare`/
> `core.worktree`) **host-side at workspace provision time, before the mask exists**
> (`apps/web-platform/server/workspace.ts` `seedWorktreeConfig`), so the in-sandbox
> `ensure_bare_config` takes `atomic_git_config`'s read-first/absent-key skip and never
> touches the masked lock. See the #4826 PR. (3) #5912's in-session temp-file bypass remains
> correct for a genuine single-path mask but is defence-in-depth, not the primary path.

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
  glob, and no file-level `/dev/null` mask anywhere in the repo sandbox config.
  **#5934 re-evaluation criterion (1) is CLOSED: mask scope = single-path, not glob**
  — but the *authoritative* source of that conclusion is the live `findmnt`/`touch`
  evidence in the 2026-07-05 CORRECTION at the top of this ADR (a per-path `tmpfs[/null]`
  bind-mount on the literal `.git/config.lock`, with a sibling `.lock` path left writable),
  NOT this bullet's repo-config inference — the CORRECTION overturns the premise that the
  repo passes only directory paths to `denyRead`. Either way the scope is single-path,
  which **de-risks #5912** (its atomic temp file's `.lock` sibling is a fresh,
  never-before-masked path). *(Consolidated 2026-07-08, #6191 — single-path stated once,
  authoritatively; ADR-081 status unchanged.)*
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
- **Timing + the real safety invariant (corrected after review):** the sweep runs at
  `ci-deploy.sh`'s pre-canary-`docker run` slot, but the OLD production container is
  **still live** there (it is not stopped until the blue-green cutover later), so the
  volume is **NOT quiescent** — its uid-1001 agents are actively writing git config.
  The load-bearing safety invariant is therefore the **`-type c` filter**, NOT ordering:
  a live git writer's lock is ALWAYS a *regular* file (`open(O_CREAT|O_EXCL)`, held
  single-digit-ms), never a character device, so `find -type c` can never match an
  in-flight legitimate lock — it matches only the wedge artifact, whose removal is the
  desired unwedge. `remediate_node` additionally re-asserts `-type c` + resolved-path-
  under-root immediately before the destructive op (TOCTOU defense-in-depth on the live
  volume). Keep it a deploy-time (not periodic-timer) invocation: under a future ADR-068
  shared-git-data topology the same `-type c` invariant is what holds, and a timer adds
  churn without new safety. Delivered via the webhook infra-config chain, so existing
  hosts get it on the next deploy.
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

**Identity-authority amendment (2026-07-07, #6184).** A fresh Concierge session still
wedged after the host sweep + host-side seed shipped — but the failing write was NOT a
`config.lock` acquisition inside `ensure_bare_config` (which the non-bare guard skips on
the agent workspace; see ADR-099). It was `ensure_worktree_identity` issuing a raw
`git config --local` write to overwrite the host-seeded per-workspace **owner** identity
with the sandbox image's `github-actions[bot]` **global** — a write that EEXISTs on the
masked `config.lock` (RC=255), and which, had it "succeeded", would have misattributed the
operator's commits to the bot. **Resolution:** on the non-bare agent workspace the
host-seeded **local** identity is authoritative in-sandbox; `ensure_worktree_identity` must
not override it. It now discriminates on **bot-shape**, not presence: it returns without
writing when a present local is non-bot (the Concierge owner), overrides a bot-shaped local
from a human `--global` (the bare-dev #2815 case), and refuses to ever write a bot-shaped
`--global`. Only the correcting paths route through `atomic_git_config`. This
confirms the ADR's durable direction — **make the in-sandbox path need no config write at
all** — extends from `ensure_bare_config` to the identity write.

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
- **(v) Route the identity write through `atomic_git_config` (Layer A, #6184)** — rejected
  as the primary fix. Routing the raw `git config --local` identity write around the masked
  lock would "succeed" — at overwriting the authoritative host-seeded **owner** with the
  sandbox `github-actions[bot]` **global**, silently misattributing the operator's commits.
  A loud wedge is preferable to a quiet wrong-author write. The correct fix is to **not
  write at all** when a valid local identity is present (see the identity-authority
  amendment above); `atomic_git_config` is kept only for the genuine set-when-absent case.

## Observability (no-SSH)

Corrected after review — this host's `vector.toml` has **no Sentry sink**; all
telemetry ships to **Better Stack** (journald → `host_scripts_journald` → HTTP sink).

- **Liveness + fail-loud (the wired no-SSH layer):** each `SOLEUR_CHARDEV_SWEEP_*`
  marker is emitted to stdout AND `logger -t git-lock-chardevice-sweep`, whose
  SYSLOG_IDENTIFIER `vector.toml` routes to Better Stack. `SOLEUR_CHARDEV_SWEEP_DONE`
  (one per run) is liveness; `SOLEUR_CHARDEV_SWEEP_FAILED` (a detected node it could
  not clear) is the loud failure signal. The JSON state file at `/var/lock` is
  host-local inspection only — **no `cat-*-state.sh` reader is wired** (unlike the
  inngest precedent); the Better Stack marker path is the authoritative no-SSH signal.
- **Regression signal (the AC10 soak):**
  `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` queries Better Stack
  (`scripts/betterstack-query.sh`) and PASSes only when the sweep ran ≥1× (a `DONE`
  marker) AND zero `SOLEUR_CHARDEV_SWEEP_FAILED` in the window — fail-safe TRANSIENT
  (never a false close) on any query/auth failure. The earlier draft queried Sentry for
  the **in-sandbox** `SOLEUR_GIT_LOCK_UNREMOVABLE type=chardevice` line, but that line is
  emitted only to blind agent-sandbox stdout and is **not mirrored to any queryable
  sink**, so the query would PASS vacuously. Mirroring the in-sandbox line to a queryable
  sink (a Concierge dispatch-path stdout→telemetry capture) is a separate observability
  follow-up; until then the host `FAILED` marker is the sound, wired regression signal.

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
  future ADR-068 shared-git-data topology would require re-validating the `-type c`
  safety invariant before any periodic variant.
- **Coverage assumption (`GIT_LOCK_SWEEP_MAXDEPTH=3`):** the sweep is depth-bounded to
  3, which covers the two observed wedge paths — a bare repo (`<workspace>/config.lock`,
  depth 2) and a working tree (`<workspace>/.git/config.lock`, depth 3). A hypothetical
  nested workspace layout one level deeper (`<workspace>/<repo>/.git/config.lock`) would
  be silently missed (a no-op-that-looks-clean, `removed=0`). This is correct for
  today's single-level workspace layout; a future nested-workspace change must revisit
  `GIT_LOCK_SWEEP_MAXDEPTH`.

## Amendment (2026-07-07, #5934 round 6) — masked config TARGET + telemetry-blindness + non-bare-guard misfire

An operator-confirmed verbatim error from a sandbox on **current main** refined the model:

```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=chardevice ... reason=non-regular-lock
mv: cannot move '.git/config.soleur-tmp.4' to '.git/config': Device or resource busy
[error] worktree wedge: could not apply shared-config prerequisites in .git
```

1. **The masked node is the config TARGET, not only the lock.** The `mv … .git/config:
   Device or resource busy` shows the bwrap mask covers `.git/config` itself (the rename
   target of `atomic_git_config`'s lockless writer), so the same-dir rename EBUSYs. Fix
   (in-sandbox, defense-in-depth): `_config_target_masked` (`[[ -c ]]` + `stat -c%m`-self
   mountpoint idiom, reused from the sweep) pre-checks the target BEFORE the write and emits a
   VISIBLE `SOLEUR_GIT_CONFIG_TARGET_MASKED` sentinel instead of attempting the doomed rename.

2. **The fatal path was telemetry-blind (the meta-bug).** The `worktree wedge:` give-up was
   emitted ONLY via `headless_or_stderr` → a per-PID logfile the PostToolUse
   `git-lock-marker-telemetry` scanner never reads, AND its `[error] ` prefix failed
   `MARKER_RE`'s `^worktree wedge:` anchor. So the wedge fired every run yet showed **zero
   events/30d** — which is why four prior fixes (07-01 → 07-07) never converged. Fix: a bare
   stdout `echo` at every give-up + `MARKER_RE`/`WEDGE_RE` now tolerate the `[error] ` prefix
   and allowlist `SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_GIT_CONFIG_MASK_SKIP`,
   `SOLEUR_FEATURE_PUSH_FAILED`, `NO_GIT_REPOSITORY`.

3. **The operator workspace is CONFIRMED NON-BARE, and the round-5 non-bare guard MISFIRED.**
   Under the mask, `git rev-parse --show-toplevel` returns empty (→ `GIT_ROOT=""`) and
   `--is-bare-repository` degrades (both must read the masked config), so the guard fell
   through to the bare surgery on a normal clone and wedged. **This is the operator-facing
   root cause.** Fix (round 6): detect non-bare by the PURE FILESYSTEM fact that `git_dir` is a
   `.git` **directory** (plus a `$PWD/.git` fallback when `GIT_ROOT` is empty) and SKIP the
   surgery — never trusting the mask-degraded `git rev-parse` first. Native `git worktree add`
   then proceeds in-sandbox with no host dependency. Only a GENUINELY bare repo (gitdir IS the
   root) consults git and can hit the rare fail-loud `branch=bare-fail` path.

**Cut:** a self-heal of a stale `extensions.worktreeConfig` was scoped then removed — the flag
is confirmed UNSET on the affected workspace and its write targets the masked path (adds risk,
no benefit).

**Durable locus unchanged:** the permanent prevention remains **host-side** — pre-seed
`.git/config` before the bwrap mask (coordinated with the open #6191; #5934 stays OPEN). This
amendment adds the in-sandbox visibility + graceful-degrade layer; it does not supersede the
host-side seed. **C4 impact:** none (internal shell + telemetry hardening on already-modeled
containers; no new element/edge/actor).
