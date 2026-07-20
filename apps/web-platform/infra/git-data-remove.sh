#!/usr/bin/env bash
#
# git-data per-workspace bare-repo ERASURE — FIXED SSH forced command
# (epic #5274 Phase 3, ADR-068 — GDPR Article 17 / CLO DL-1).
#
# The Art. 17 counterpart to git-data-provision.sh. Account/workspace deletion
# (account-delete.ts, wired in 3.D) must remove the per-workspace bare repo — and
# its per-(workspace,worktree) fence sidecar at `<id>.git/fence/` — from the
# git-data host. `rm` over the transport git-shell key is impossible (git-shell -c
# permits only receive-pack/upload-pack), so erasure is bound to a THIRD, dedicated
# REMOVE key's forced command (`command="/usr/local/bin/git-data-remove.sh"` in
# cloud-init authorized_keys). Provisioning, ref-write, and erasure authority are
# THREE separate credentials with separate blast radii (ADR-068 §6 — never a
# cluster-wide cred): a leaked transport key cannot fabricate or delete repos, a
# leaked provision key cannot delete, and a leaked remove key cannot write refs.
# Same OS `git` user (per-key command= overrides the login shell). Ships via
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
# GIT_DATA_REPO_ROOT — sshd passes NO client env to a forced command (AcceptEnv
# empty), so in production this is always the server default and the client cannot
# influence it (the workspace_id in SSH_ORIGINAL_COMMAND is the only client input,
# validated below).
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"

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

# --- Build the target path and refuse if the PARENT does not canonicalize under
#     the root (identical to provision's guard). ---
repo_path="${REPO_ROOT}/${workspace_id}.git"
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -n "$root_real" ] || reject "repo root $REPO_ROOT is not present"
parent_real="$(readlink -f "$(dirname "$repo_path")" 2>/dev/null || echo "")"
[ "$parent_real" = "$root_real" ] || reject "resolved path escapes the repo root"

# --- Idempotent erasure under a per-workspace lock (mirrors provision's lock) ---
mkdir -p "$REPO_ROOT"
lock_file="${REPO_ROOT}/.${workspace_id}.init.lock"
exec 9>"$lock_file"
flock 9 || reject "could not acquire init lock for '$workspace_id'"

if [ ! -e "$repo_path" ]; then
  # Nothing to erase — a deleted/never-provisioned workspace. Art. 17 satisfied.
  echo "remote: git-data remove: '$workspace_id' not present (no-op)" >&2
  rm -f "$lock_file"
  exit 0
fi

# The repo exists — canonicalize the FULL target (not just its parent) and assert
# it is EXACTLY <root>/<id>.git before the destructive rm, so a symlink planted at
# the repo path cannot redirect the rm outside the root (defense-in-depth beyond
# the charset/parent guards; a create path never needs this, a delete path does).
repo_real="$(readlink -f "$repo_path" 2>/dev/null || echo "")"
[ "$repo_real" = "${root_real}/${workspace_id}.git" ] || reject "repo path is not a direct child of the root (symlink?)"

rm -rf "$repo_real" || reject "rm -rf failed for '$workspace_id'"
# Clean up the per-workspace lock file itself (leftover from provision/remove).
rm -f "$lock_file"
echo "remote: git-data remove: erased bare repo for '$workspace_id'" >&2
exit 0
