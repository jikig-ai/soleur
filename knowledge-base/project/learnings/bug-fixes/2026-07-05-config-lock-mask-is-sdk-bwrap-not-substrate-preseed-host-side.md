---
date: 2026-07-05
category: bug-fixes
module: workspace-provisioning
tags: [config-lock, sandbox, bubblewrap, git-worktree, concierge, root-cause, observability]
issue: 4826
related:
  - 2026-07-03-lockless-git-config-writer-bypasses-masked-config-lock.md
---

# Learning: the `.git/config.lock` wedge is an SDK bwrap per-path /dev/null mask, not a filesystem residual — fix it host-side before the mask exists

## Problem

Concierge worktree creation wedges because `.git/config.lock` is a **character
device** and every in-sandbox `git config` write fails against it. ADR-081 concluded
the root cause was a **container-filesystem residual inode** on the persistent volume
(candidate "c") and shipped a **host-side, deploy-time `-type c` sweep** (#5934) to
clear it. That sweep was verified *running* (Better Stack `SOLEUR_CHARDEV_SWEEP_DONE`
markers, zero FAILED) — yet a **fresh session still wedged**.

## Solution

Live probing from the wedged session (which we could not do from telemetry — the
in-sandbox `SOLEUR_GIT_LOCK_*` markers are **not mirrored to any queryable sink**)
was decisive:

- `ls -la .git/config.lock` → `crw-rw-rw- … 1, 3` (a `/dev/null` char device).
- `findmnt -T .git/config.lock` → `tmpfs[/null]  ro` — a **deliberate per-path bind
  mount** on the *literal* path, not a residual inode and not a mount over `.git`.
- `touch .git/config.soleur-probe.lock` → a **normal writable file** ⇒ the mask is
  **single-path**, not a `*.lock` glob.

So the node is the **Claude Agent SDK's bubblewrap file-mask (ADR-081 candidate "b"),
applied per-session INSIDE the sandbox** as a git-config-RCE guard — *not* a
host-volume residual. The deploy-time host sweep can never see a per-session
in-sandbox mount, which is why it ran clean while sessions still wedged.

The durable fix makes the in-sandbox path **need no config write at all**:
`seedWorktreeConfig()` in `apps/web-platform/server/workspace.ts` pre-applies the exact
transformation `ensure_bare_config` performs (`core.repositoryformatversion=1`,
`extensions.worktreeConfig=true`, clear `core.bare`/`core.worktree`) **host-side at
provision time, before the sandbox mask exists**. In-sandbox, `atomic_git_config`
then takes its read-first / absent-key **skip** for all four — zero writes, the masked
lock is never touched — and `git worktree add` reads `worktreeConfig` and writes only
per-worktree config (`config.worktree`, unmasked).

## Key Insight

1. **"The fix runs" is not "the fix works." Verify the USER-FACING symptom, not the
   mechanism.** The host sweep emitted DONE markers (mechanism verified) while the
   actual outcome (a session creating a worktree) stayed broken. A green internal
   signal conflated with the outcome produced two false "it's fixed" claims. For a
   blind execution surface, the only sound verification is reproducing the user's
   exact action — here, a fresh session — not a proxy telemetry marker.

2. **When a masked file is a `.lock` sidecar, the robust fix is to remove the NEED to
   write it, not to fight the mask.** #5912's in-sandbox temp-file bypass fights the
   mask (and is fail-closed correct for a genuine single-path mask). Pre-seeding the
   target state on the host, before the mask exists, makes the write idempotent-skip —
   strictly more robust, and independent of whether the in-session bypass fires.

3. **A root-cause ADR built on a ruled-out candidate must be re-probed against live
   ground truth.** ADR-081 ruled out the SDK bwrap mask (b) by *reading the sandbox
   config* (only directory paths passed to `denyRead`). One `findmnt` from a wedged
   session overturned it. Prefer a live mount/inode probe over config-reading when the
   artifact is a mount.

## Session Errors

- **Claimed "no Better Stack access"** from a bare-shell probe that needed
  `doppler run -p soleur -c prd_terraform`. Fixed in #6055 (the script now names the
  invocation). **Prevention:** a fail-safe TRANSIENT/auth error from an infra probe is
  inconclusive, never proof of a capability gap — re-run wrapped in `doppler run`.
- **Declared the wedge fixed end-to-end after verifying only the sweep ran.** See Key
  Insight 1. **Prevention:** for a blind surface, reproduce the user action; if you
  cannot (Concierge session), say so and gate the "fixed" claim on the user's retry.
- **Seed passed locally, failed in CI (`extensions.worktreeConfig` null).** The seed
  was placed INSIDE `provisionWorkspace`'s `git init → add → commit` try, after the
  commit. A CI runner (and a prod host) with no git identity throws at `git commit`,
  so the catch swallowed it and the seed never ran — invisible locally where a global
  identity exists. **Prevention:** a best-effort step that must run regardless of an
  earlier step's failure belongs OUTSIDE that step's try. Reproduce a "works locally,
  red in CI" gap by stripping the ambient state CI lacks
  (`env GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME= …`) — don't assume flake.

## Follow-ups

- **Observability (open):** mirror the in-sandbox `SOLEUR_GIT_LOCK_*` markers to a
  queryable sink so the next wedge is self-diagnosable without asking the operator to
  paste `findmnt`. This blindness forced two round-trips and is the meta-bug.

## Tags
category: bug-fixes
module: workspace-provisioning
