---
feature: config-lock-wedge-fix
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 5912
branch: feat-config-lock-wedge-fix
pr: 5932
brainstorm: knowledge-base/project/brainstorms/2026-07-03-config-lock-wedge-fix-brainstorm.md
status: implemented
---

## Implementation note (2026-07-03)

Landed in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:
`_config_lock_wedged()` (per-file non-regular-lock gate) + `atomic_git_config()`
(read-first + gated lockless temp-copy/atomic-rename), with all five
`ensure_bare_config()` mutations routed through the helper and the old fail-loud
short-circuit replaced by a route-around (the sweep still runs for diagnostics +
stale-regular removal, `|| true`).

**Empirically validated (BLOCKING ASSUMPTION resolved for the create path):** with a
non-regular lock present at `.git/config.lock`, a native `git config` write fails
EEXIST, but after `atomic_git_config` sets `extensions.worktreeConfig=true` via the
lockless path, `git worktree add` (with a valid HEAD) succeeds and never touches the
wedged shared `config.lock` — it writes per-worktree config instead. So the
ensure_bare_config-scoped fix is sufficient to unwedge worktree creation; the
single-path-masking assumption (candidate 3 / #5934) governs only defense-in-depth,
not create-path correctness. Tests: `worktree-manager-atomic-config.test.sh` (new,
dir+symlink+char-device fixtures) and the updated Test 8 in
`worktree-manager-stale-lock-diag.test.sh` (behavior inverted: self-heal, not refuse).

# Spec: config.lock worktree-creation wedge — targeted fix

## Problem Statement

In the Concierge agent-sandbox, `.git/config.lock` is materialized as a non-regular
file (character device — sweep `type=other reason=non-regular-lock`), an artifact of
the sandbox filesystem/masking layer, write/remove-protected. `ensure_bare_config()`
in `worktree-manager.sh` writes shared `.git/config` (and per-worktree
`.git/config.worktree`) on every worktree-create path; each `git config` write tries
to create the corresponding `.lock` via `O_CREAT|O_EXCL` and hits `EEXIST` against the
pre-existing device node → permanent worktree-creation wedge with no in-sandbox
self-heal. Confirmed by a real wedged-session forensic captured on #5912.

## Goals

- Every autonomous Concierge session self-heals past the wedge in-session, with no
  operator SSH and no manual intervention.
- Preserve git-native INI correctness for config writes (no hand-rolled INI parser).
- Cover BOTH wedge surfaces: shared `.git/config` and per-worktree `.git/config.worktree`.

## Non-Goals

- The upstream platform/mount fix that stops the sandbox from materializing the
  char-device (candidate 3) — tracked as a separate companion issue; out of this repo.
- Removing the char-device node in-sandbox (impossible — protected; and wrong target).
- Any change to the sweep's diagnostic/instrumentation behavior (PR #5907) beyond
  consuming its existing non-regular-lock signal.

## Functional Requirements

- **FR1** — A `atomic_git_config <file> <args…>` helper applies a config mutation
  without acquiring the target's native `.lock` when that lock is wedged.
- **FR2** — Read-first: the helper skips the write entirely when `git config --get`
  already shows the desired value (zero-write fast path for the common re-run case).
- **FR3** — Gated lockless fallback: when a write is genuinely needed, branch on the
  sweep's existing non-regular-lock signal — clean lock → native `git config`
  (preserve flock serialization); wedged → temp-copy + same-dir atomic-rename.
- **FR4** — All `ensure_bare_config()` mutations route through the helper: shared
  `config` (repositoryformatversion, extensions.worktreeConfig, unset core.bare, unset
  core.worktree) AND per-worktree `config.worktree` (core.bare=true).

## Technical Requirements

- **TR1** — Lockless write: `cp -p` original → same-directory temp
  (`.git/config.soleur-tmp.$$`) → `git config --file <temp>` edits (creates a clean
  `<temp>.lock`, distinct from the masked `config.lock`) → `mv -f <temp>` over target.
- **TR2** — `cp -p` to preserve mode/owner/timestamps (plain `cp` perm-drifts config).
- **TR3** — Guard symlinked target: refuse/adjust so `mv -f` does not clobber a symlink
  with a regular file.
- **TR4** — CI fixture that forces a char-device (or bind-mount) at `config.lock` so the
  wedged-fallback branch is exercised (kills rare-branch bit-rot).
- **TR5** — GNU-only tooling consistent with the existing sweep (`stat`, `cp -p`).

## Risks / Assumptions

- **[BLOCKING ASSUMPTION]** Sandbox masking is single-path (`.git/config.lock` only),
  NOT a glob over `*.lock`. If globbed, the temp `.lock` is also masked and the fix
  fails identically. Evidence supports single-path (config.worktree.lock did not trip
  in the forensic); confirm against the next fuller forensic before/at plan phase.
- Parallel-session last-rename-wins is safe because all writers converge to the same
  idempotent target state; the wider copy→rename window is acceptable under the
  existing age-guard-not-flock posture.
