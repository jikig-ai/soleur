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
# --- (#8043 F8) REFUSE UNLESS THE STORE IS MOUNTED — before any path guard below.
#     `readlink -f` SUCCEEDS on a path that does not exist, so on a host whose volume never
#     mounted the guards below all pass and `git init --bare` wrote a REAL user repository
#     onto the root disk, where a later successful mount silently hides it. That is data
#     loss, not a false report. mountpoint(1) is the instrument; it is resolved from PATH
#     (sshd sets the server's PATH, and `AcceptEnv LANG LC_*` cannot reach it) and its
#     ABSENCE fails closed — a check that cannot run is not a check that passed. ---
mountpoint_bin="$(command -v mountpoint 2>/dev/null || true)"
[ -n "$mountpoint_bin" ] || reject "cannot verify the store is mounted: mountpoint(1) not on PATH (fail-closed)"
"$mountpoint_bin" -q "$MOUNT_ROOT" || reject "git-data store is not mounted at $MOUNT_ROOT — refusing to act on an unmounted store (fail-closed)"

repo_path="${REPO_ROOT}/${workspace_id}.git"
# The repo need not exist yet, so canonicalize the PARENT (REPO_ROOT, which must exist:
# git-data-bootstrap.sh creates it at boot, downstream of its own mountpoint FATAL). The
# `-d` is what makes this guard LIVE — `readlink -f` returns a path for an absent root.
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -n "$root_real" ] && [ -d "$root_real" ] || reject "repo root $REPO_ROOT is not present"
parent_real="$(readlink -f "$(dirname "$repo_path")" 2>/dev/null || echo "")"
[ "$parent_real" = "$root_real" ] || reject "resolved path escapes the repo root"

# --- Idempotent init under a per-workspace lock (concurrent first-init safe) ---
# (#8043 F8) NO mkdir OF THE REPO ROOT HERE. git-data-bootstrap.sh creates the root at boot,
# downstream of its own mountpoint FATAL, so on a healthy host this was dead code and on an
# unmounted one it was precisely the hazard: it created the store on the root disk. If the
# root is absent, `exec 9>` fails the redirection and `set -e` exits — the load-bearing
# control; the mount assertion above upgrades that raw bash error into a named refusal.
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
