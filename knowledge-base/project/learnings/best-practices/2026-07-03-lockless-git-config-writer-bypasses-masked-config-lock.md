---
date: 2026-07-03
category: best-practices
module: git-worktree
tags: [git, worktree, config-lock, blind-surface, lockless-write, atomic-rename, concierge-sandbox]
issue: 5912
pr: 5932
related:
  - 2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md
  - 2026-07-02-fail-loud-guard-must-not-nest-under-a-different-state-class-gate.md
---

# Learning: self-heal past a masked `.git/config.lock` with a lockless temp-copy + atomic rename

## Problem

The Concierge agent-sandbox materialises `.git/config.lock` as a **non-regular file
— a character device** (an artifact of the sandbox filesystem/masking layer,
write/remove-protected). git creates config locks via `open(O_CREAT|O_EXCL)`, so the
pre-existing node makes **every** `git config` write fail `EEXIST` ("could not lock
config file … : File exists"). `ensure_bare_config()` in `worktree-manager.sh` runs on
every worktree-create path, so worktree creation wedged **permanently**, with no
in-sandbox self-heal — the surface every autonomous `/soleur:go` / `/soleur:one-shot`
session depends on. The instrumented sweep from #5907 captured the forensic
(`SOLEUR_GIT_LOCK_UNREMOVABLE … type=other reason=non-regular-lock`), unblocking #5912.

## Solution

A generalized `atomic_git_config <file> <git-config-args…>` helper (in
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`) that all five
`ensure_bare_config()` mutations route through:

- **Read-first idempotence** — a `key value` set already at the desired value, or an
  `--unset` of an absent key, is a zero-write fast path. **Reads never take the lock**,
  so this works even while wedged.
- **Gated lockless writer** — `_config_lock_wedged()` returns true only when
  `<file>.lock` is present AND non-regular. Clean/absent lock → native `git config`
  (keeps git's flock serialization). Wedged → `cp -p <file> <file>.soleur-tmp.$$` →
  `git config --file <temp>` (git creates a **clean** `<temp>.lock`, a distinct path) →
  `mv -f <temp> <file>` (same-dir atomic rename). Never touches the masked lock.

The old `ensure_bare_config` **failed loud** on any unremovable lock; the fix
**routes around** the non-regular case and demotes the sweep to
`sweep_stale_git_locks … || true` (diagnostics + stale-REGULAR removal only).

## Key Insight

1. **To write a file whose sibling `.lock` path is hijacked, redirect the tool's own
   writer to a temp in the same directory, then atomic-rename.** git (and any
   lock-file-based writer) locks `<target>.lock`; pointing it at `<temp>` gives it a
   fresh, unmasked lock path while preserving the tool's native format correctness (no
   hand-rolled INI parser). Same-dir is load-bearing: a cross-fs `/tmp` temp makes the
   rename a non-atomic copy+unlink.

2. **Fixing the ONE chokepoint that sets the enabling config can unwedge a whole
   pipeline — verify empirically.** Setting `extensions.worktreeConfig=true` via the
   lockless path steers the subsequent `git worktree add` onto **per-worktree** config,
   so it never needs the masked shared `config.lock`. Reproduced on git 2.53: with a
   dir at `config.lock`, native `git config` fails, but after the lockless write
   `git worktree add` (valid HEAD) returns 0 and leaves `config.lock` untouched. The
   scoped fix (only `ensure_bare_config`'s mutations) is therefore sufficient for
   create-path correctness — don't assume you must patch every git call.

3. **On a blind execution surface, a fail-CLOSED fallback still needs a DISTINCT
   sentinel for its variant failure.** The fix's BLOCKING ASSUMPTION is that masking is
   single-path (`config.lock` only). If it's a glob over `*.lock`, the temp's own
   `.lock` is also masked and the write fails — safely (fail-closed, config untouched),
   but a generic error is indistinguishable from the original single-path wedge. Emit a
   distinct `SOLEUR_GIT_LOCK_TEMP_WEDGED` on the temp-write-failure branch so the next
   blind-surface session can tell glob-masking apart and resolve the assumption from a
   real forensic (feeds the platform companion #5934). Multi-agent review's
   `user-impact-reviewer` (single-user-incident threshold) surfaced this; the
   implementation-side checks could not.

## Session Errors

- **`TaskCreate` called with Agent-tool params** (`prompt`/`description` instead of the
  required `subject`) — 4 `InputValidationError` rejections. Recovery: dropped the
  optional task list and proceeded. **Prevention:** `TaskCreate` is a deferred tool
  whose schema was not loaded; load a deferred tool's schema (`ToolSearch
  select:<tool>`) before the first call rather than guessing its params from a
  sibling tool. One-off (harness-usage, no project recurrence vector).
- **Foreground `sleep 20` blocked** by the harness ("Bash completed with no output").
  Recovery: switched to the background-task completion notification / `ScheduleWakeup`
  model. **Prevention:** never foreground-`sleep` to poll; rely on task-notifications.
  One-off (known harness constraint).

## Tags
category: best-practices
module: git-worktree
