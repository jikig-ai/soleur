#!/usr/bin/env bash
#
# git-data per-workspace bare-repo provisioner — FIXED SSH forced command
# (epic #5274 Phase 2 PR B part 2, ADR-068 amendment 2026-07-01 "PR B bare-repo
# provisioning").
#
# `git-receive-pack` never auto-creates its target, so the per-workspace bare repo
# MUST exist before the first replication push. The git-shell TRANSPORT key cannot
# `git init --bare` (git-shell -c permits only receive-pack/upload-pack). This
# wrapper is bound to a SECOND, dedicated provision key's forced command
# (`command="/usr/local/bin/git-data-provision.sh"` in cloud-init authorized_keys),
# so provisioning authority and ref-write authority are SEPARATE credentials with
# separate blast radii (ADR-068 §6 — never a cluster-wide cred). The transport
# git-shell key is untouched.
#
# Contract: read `workspace_id` from SSH_ORIGINAL_COMMAND as a SINGLE OPAQUE
# argument (validated, NEVER eval'd — no shell-injection surface regardless of what
# the client sends), validate it (CWE-22, same posture as git-data-pre-receive.sh),
# then run an idempotent `git init --bare` of /mnt/git-data/repositories/<id>.git
# under a per-workspace flock. Re-provision is a safe no-op. Runs as the `git` user.
#
# A freshly inited repo needs NO fence-sidecar seeding: it inherits
# `core.hooksPath` (the fail-closed placeholder → the real CAS fence) from the
# system git config the bootstrap set, and the fence defaults stored_max=0 on the
# absent fence/ dir, so the first push at gen=N advances 0→N. The repo is inited ON
# THE BLOCK VOLUME (the mounted repo root), preserving the reboot-durable fence max.
set -euo pipefail

# The bare-repo root on the block volume. Overridable ONLY for tests via
# GIT_DATA_REPO_ROOT — sshd passes NO client env to a forced command by default
# (AcceptEnv is empty), so in production this is always the server default and the
# client cannot influence it (the workspace_id in SSH_ORIGINAL_COMMAND is the only
# client input, and it is validated below).
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"

reject() {
  echo "remote: git-data provision: $1" >&2
  exit 1
}

# --- Read the requested workspace_id (opaque; the forced command ignores the
#     command word). Trim surrounding whitespace only; never eval. ---
workspace_id="${SSH_ORIGINAL_COMMAND:-}"
# Strip leading/trailing whitespace without a subshell eval.
workspace_id="${workspace_id#"${workspace_id%%[![:space:]]*}"}"
workspace_id="${workspace_id%"${workspace_id##*[![:space:]]}"}"

# --- Fail-closed validation (mirrors git-data-pre-receive.sh worktree-id checks) ---
[ -n "$workspace_id" ] || reject "missing workspace_id (fail-closed)"
case "$workspace_id" in
  (.|..) reject "workspace_id is a dot path: '$workspace_id'" ;;
  (*/*) reject "workspace_id contains a slash: '$workspace_id'" ;;
  (*[!A-Za-z0-9._-]*) reject "workspace_id has unsafe characters: '$workspace_id'" ;;
esac

# --- Build the target path and refuse if it does not canonicalize under the root ---
repo_path="${REPO_ROOT}/${workspace_id}.git"
# The repo need not exist yet, so canonicalize the PARENT (REPO_ROOT, which does).
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -n "$root_real" ] || reject "repo root $REPO_ROOT is not present"
parent_real="$(readlink -f "$(dirname "$repo_path")" 2>/dev/null || echo "")"
[ "$parent_real" = "$root_real" ] || reject "resolved path escapes the repo root"

# --- Idempotent init under a per-workspace lock (concurrent first-init safe) ---
mkdir -p "$REPO_ROOT"
lock_file="${REPO_ROOT}/.${workspace_id}.init.lock"
exec 9>"$lock_file"
flock 9 || reject "could not acquire init lock for '$workspace_id'"

if [ -d "$repo_path" ]; then
  # Already provisioned — a re-provision is a safe no-op (the app calls this
  # unconditionally before every push).
  echo "remote: git-data provision: '$workspace_id' already provisioned (no-op)" >&2
  exit 0
fi

# `git init --bare` inherits system core.hooksPath (the fence) automatically.
git init --bare --quiet "$repo_path" || reject "git init --bare failed for '$workspace_id'"
echo "remote: git-data provision: initialized bare repo for '$workspace_id'" >&2
exit 0
