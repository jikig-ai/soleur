#!/usr/bin/env bash
#
# git-data per-workspace bare-repo ERASURE — FIXED SSH forced command
# (epic #5274 Phase 3, ADR-068 — GDPR Article 17 / CLO DL-1).
#
# The Art. 17 counterpart to git-data-provision.sh. Account/workspace deletion
# (account-delete.ts, wired in 3.D) must remove the per-workspace bare repo — and
# its per-(workspace,worktree) fence sidecar at `<id>.git/fence/` — from the
# git-data host. `rm` over the transport key is impossible (its forced command,
# git-data-transport-wrapper.sh, allowlists only receive-pack/upload-pack; the login
# shell is /bin/sh, #8043, so the forced-command map is the whole confinement), so
# erasure is bound to a THIRD, dedicated
# REMOVE key's forced command (`command="/usr/local/bin/git-data-remove.sh"` in
# cloud-init authorized_keys). Provisioning, ref-write, and erasure authority are
# THREE separate credentials with separate blast radii (ADR-068 §6 — never a
# cluster-wide cred): a leaked transport key cannot fabricate or delete repos, a
# leaked provision key cannot delete, and a leaked remove key cannot write refs.
# Same OS `git` user (sshd runs each key's command= BY the login shell as `<shell> -c`;
# the confinement is the forced-command map, not the shell — #8043). Ships via
# cloud-init ONLY (the fixed low-churn security-boundary wrapper's correct home,
# mirroring git-data-provision.sh); the app-side call lands in 3.D.
#
# Contract: read `workspace_id` from SSH_ORIGINAL_COMMAND as a SINGLE OPAQUE
# argument (validated, NEVER eval'd), validate it (CWE-22, same posture as
# git-data-provision.sh / git-data-pre-receive.sh), then idempotently `rm -rf` the
# VALIDATED /mnt/git-data/repositories/<id>.git under a per-workspace flock. Absent
# repo ⇒ erasure already satisfied ⇒ no-op success (the app may retry; a deleted
# workspace has no repo to remove). The fence sidecar lives inside the bare repo
# (`$GIT_DIR/fence/`, git-data-pre-receive.sh:100), so the single `rm -rf` erases
# both the objects/refs AND the fence generation state — complete erasure.
set -euo pipefail

# The bare-repo root on the block volume. Overridable ONLY for tests via
# GIT_DATA_REPO_ROOT. In production this is always the server default: sshd forwards
# client environment only for names matched by AcceptEnv, and Ubuntu's stock
# sshd_config ships `AcceptEnv LANG LC_*` (#8043 F10 — an earlier comment here claimed
# AcceptEnv was empty; the premise was wrong, the conclusion holds), which cannot match
# GIT_DATA_REPO_ROOT or GIT_DATA_MOUNT_ROOT. The client's only input is the workspace_id
# in SSH_ORIGINAL_COMMAND, validated below.
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"
# (#8043 F8) The MOUNT the store lives on — a SECOND, independently-defaulted seam, asserted
# below with mountpoint(1). It is deliberately not derived from REPO_ROOT: `mountpoint -q` on
# the repositories SUBDIRECTORY returns 1 on a correctly mounted host, so an assertion on
# REPO_ROOT would refuse every erasure/provision (measured, ubuntu-24.04). The suites point
# this at a real mount (`stat -c %m` of their temp root) rather than stubbing the instrument.
MOUNT_ROOT="${GIT_DATA_MOUNT_ROOT:-/mnt/git-data}"

reject() {
  echo "remote: git-data remove: $1" >&2
  exit 1
}

# --- Read the requested workspace_id (opaque; the forced command ignores the
#     command word). Trim surrounding whitespace only; never eval. ---
workspace_id="${SSH_ORIGINAL_COMMAND:-}"
workspace_id="${workspace_id#"${workspace_id%%[![:space:]]*}"}"
workspace_id="${workspace_id%"${workspace_id##*[![:space:]]}"}"

# --- Fail-closed validation (identical to git-data-provision.sh) ---
[ -n "$workspace_id" ] || reject "missing workspace_id (fail-closed)"
case "$workspace_id" in
  (.|..) reject "workspace_id is a dot path: '$workspace_id'" ;;
  (*/*) reject "workspace_id contains a slash: '$workspace_id'" ;;
  (*[!A-Za-z0-9._-]*) reject "workspace_id has unsafe characters: '$workspace_id'" ;;
esac

# --- (#8043 F8) REFUSE UNLESS THE STORE IS MOUNTED — before any path guard below.
#     `readlink -f` SUCCEEDS on a path that does not exist, so on a host whose volume never
#     mounted the guards below all pass, the repo is "not present", and this script used to
#     print a no-op SUCCESS over a store nobody looked at: an Article 17 erasure that erased
#     nothing. mountpoint(1) is the instrument; it is resolved from PATH (sshd sets the
#     server's PATH, and `AcceptEnv LANG LC_*` cannot reach it) and its ABSENCE fails
#     closed — a check that cannot run is not a check that passed. ---
command -v mountpoint >/dev/null 2>&1 || reject "cannot verify the store is mounted: mountpoint(1) not on PATH (fail-closed)"
mountpoint -q "$MOUNT_ROOT" || reject "git-data store is not mounted at $MOUNT_ROOT — refusing to act on an unmounted store (fail-closed)"

# --- (#8043 review) HONOUR THE CUTOVER FREEZE. git-data-cutover.sh plants
#     `$MOUNT_ROOT/.cutover-freeze` between its post-drain delta rsync and the mount repoint;
#     the pre-receive fence already denies pushes on it, but an erasure/provision landing in
#     that window would act on the plaintext volume only while the LUKS copy — already
#     `--delete`-synced — keeps the repo, and the outcome would be reported success. The
#     sentinel is root-owned on a root-owned mount root: the git uid cannot forge or remove it.
#     The path seam is the one git-data-pre-receive.sh already carries (test-only; AcceptEnv
#     cannot reach it), so a suite can plant the sentinel without owning a mount root. ---
cutover_freeze="${GIT_DATA_CUTOVER_FREEZE:-${MOUNT_ROOT}/.cutover-freeze}"
[ ! -e "$cutover_freeze" ] || reject "store is frozen for cutover ($cutover_freeze present) — retry after the cutover (fail-closed)"


# --- Build the target path and refuse if the PARENT does not canonicalize under
#     the root (identical to provision's guard). The `-d` is what makes this guard LIVE:
#     `readlink -f` returns a path for an absent root, so `-n` alone never fired. ---
repo_path="${REPO_ROOT}/${workspace_id}.git"
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -d "$root_real" ] || reject "repo root $REPO_ROOT is not present"
# (#8043 review) THE ROOT MUST BE ON THE STORE, not merely "a store is mounted and a root
# exists" — those are two facts about two paths, and nothing else binds them. A repo root
# that resolves onto the root disk while /mnt/git-data is mounted would satisfy both
# checks above and put the erasure/provision on the wrong disk. `stat -c %m` names the
# mount a path sits on; the store's mount is the mount root itself.
[ "$(stat -c %m "$root_real")" = "$(readlink -f "$MOUNT_ROOT")" ] || reject "repo root $root_real is not on the store mounted at $MOUNT_ROOT (fail-closed)"
parent_real="$(readlink -f "$(dirname "$repo_path")" 2>/dev/null || echo "")"
[ "$parent_real" = "$root_real" ] || reject "resolved path escapes the repo root"

# --- Idempotent erasure under a per-workspace lock (mirrors provision's lock).
#     (#8043 F8) NO mkdir OF THE REPO ROOT HERE: an erasure path must never CREATE the
#     store. The bootstrap creates the root at boot; if it is absent, `exec 9>` below fails
#     the redirection and `set -e` exits — that deletion is the load-bearing control, the
#     mount assertion above is the message upgrade that names why.
#     (#8043 review) The lock file is a git-owned dotfile in a git-owned root, so a symlink can be
#     planted at its path by the same uid: `exec 9>` would then O_TRUNC whatever it points at.
#     Refuse a symlink before opening. It is NEVER unlinked afterwards: unlinking a lock file
#     while a sibling holds fd 9 on it lets the next opener create a new inode and hold "the
#     lock" concurrently (measured — provision and remove then race on one path). 0-byte
#     dotfiles are invisible to git-data-gc.sh, which iterates `*.git` only. ---
lock_file="${REPO_ROOT}/.${workspace_id}.init.lock"
[ ! -L "$lock_file" ] || reject "lock path is a symlink: '$lock_file' (fail-closed)"
exec 9>"$lock_file"
flock 9 || reject "could not acquire init lock for '$workspace_id'"

if [ ! -e "$repo_path" ]; then
  # Nothing to erase — a deleted/never-provisioned workspace. Art. 17 satisfied.
  echo "remote: git-data remove: '$workspace_id' not present (no-op)" >&2
  exit 0
fi

# The repo exists — canonicalize the FULL target (not just its parent) and assert
# it is EXACTLY <root>/<id>.git before the destructive rm, so a symlink planted at
# the repo path cannot redirect the rm outside the root (defense-in-depth beyond
# the charset/parent guards; a create path never needs this, a delete path does).
repo_real="$(readlink -f "$repo_path" 2>/dev/null || echo "")"
[ "$repo_real" = "${root_real}/${workspace_id}.git" ] || reject "repo path is not a direct child of the root (symlink?)"

# (#8043 review) `--one-file-system`: a bind mount planted INSIDE <id>.git (root can; the
# exact-child check above cannot see one, since `readlink -f` returns the same path) would
# otherwise have its SOURCE's contents erased before rm fails EBUSY on the mount itself —
# the damage done, the exit code honest. Measured: with the flag rm skips the foreign
# device and the source is intact.
rm -rf --one-file-system "$repo_real" || reject "rm -rf failed for '$workspace_id'"
echo "remote: git-data remove: erased bare repo for '$workspace_id'" >&2
exit 0
