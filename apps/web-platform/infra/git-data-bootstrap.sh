#!/usr/bin/env bash
#
# git-data host bootstrap — epic #5274 Phase 2 PR B / ADR-068 §3.
#
# Idempotent. Installs the DURABLE SUBSTRATE for the multi-host /workspaces
# split's git-data store: the block-volume mount, git + flock, the dedicated
# `git` transport user's .ssh perms, the bare-repo root, and a FAIL-CLOSED
# PLACEHOLDER pre-receive hook. The REAL CAS fence (git-data-pre-receive.sh)
# ships later via the web-platform deploy pipeline — the most-likely-to-iterate,
# safety-critical artifact stays pipeline-iterable (CI cannot SSH either host).
#
# DELIVERY: embedded into cloud-init-git-data.yml via base64encode(file()) and
# run once from runcmd on first boot (mirrors inngest-redis-bootstrap.sh).
#
# The bare repos AND the per-(workspace,worktree) fence sidecar/lock MUST live on
# the persistent block volume, never tmpfs — a reboot resetting the fence max to 0
# would let a stale gen=5 writer beat a fresh 0 (git-data-pre-receive.sh header).
set -euo pipefail

log() { echo "[git-data-bootstrap] $*"; }

GIT_DATA_ROOT="/mnt/git-data"
REPO_ROOT="$GIT_DATA_ROOT/repositories" # per-workspace bare repos land here
HOOKS_DIR="$GIT_DATA_ROOT/hooks"        # core.hooksPath target (on the volume)
PLACEHOLDER_STAGED="/tmp/git-data-pre-receive-placeholder.sh"
PRE_RECEIVE="$HOOKS_DIR/pre-receive"
GIT_USER="git"
GIT_HOME="/home/$GIT_USER"

# Defense-in-depth (CWE-367, mirrors inngest-redis-bootstrap.sh): refuse to
# install from a symlinked /tmp staging path.
assert_not_symlink() {
  if [[ -L "$1" ]]; then
    log "ERROR: refusing to install from symlinked staging path $1"
    exit 1
  fi
}

# 1. The substrate MUST be on the block volume. cloud-init's runcmd mounts it by
#    id; re-assert idempotently here (glob — this host has exactly one volume) and
#    FAIL LOUD if it is not mounted (never write the bare repos to the root fs —
#    that loses the reboot-durable fence guarantee).
mkdir -p "$GIT_DATA_ROOT"
if ! mountpoint -q "$GIT_DATA_ROOT"; then
  log "volume not mounted at $GIT_DATA_ROOT — attempting mount"
  mount /dev/disk/by-id/scsi-0HC_Volume_* "$GIT_DATA_ROOT" || true
fi
if ! mountpoint -q "$GIT_DATA_ROOT"; then
  log "FATAL: git-data block volume is not mounted at $GIT_DATA_ROOT"
  exit 1
fi

# 2. git + flock (util-linux) + git-shell. cloud-init `packages:` installs git;
#    assert + self-heal idempotently so a transient apt drop on first boot fails
#    LOUD, not silent.
if ! command -v git >/dev/null 2>&1; then
  log "git missing — installing"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq git
fi
command -v git >/dev/null 2>&1 || {
  log "FATAL: git still not installed"
  exit 1
}
command -v flock >/dev/null 2>&1 || {
  log "FATAL: flock (util-linux) missing — fence lock would be unenforceable"
  exit 1
}
command -v git-shell >/dev/null 2>&1 || {
  log "FATAL: git-shell missing — transport user shell unenforceable"
  exit 1
}

# 3. The dedicated `git` transport user (created by cloud-init `users:`). Lock down
#    its .ssh so sshd accepts the forced-command authorized_keys cloud-init wrote.
id "$GIT_USER" >/dev/null 2>&1 || {
  log "FATAL: $GIT_USER user absent (cloud-init users: stage did not run)"
  exit 1
}
mkdir -p "$GIT_HOME/.ssh"
chmod 700 "$GIT_HOME/.ssh"
[[ -f "$GIT_HOME/.ssh/authorized_keys" ]] && chmod 600 "$GIT_HOME/.ssh/authorized_keys"
chown -R "$GIT_USER:$GIT_USER" "$GIT_HOME/.ssh"

# 4. Bare-repo root + hooks dir on the volume, owned by the transport user. chown
#    immediately after mkdir (the five-bug-cascade learning, inngest-redis-bootstrap).
mkdir -p "$REPO_ROOT" "$HOOKS_DIR"
chown "$GIT_USER:$GIT_USER" "$REPO_ROOT" "$HOOKS_DIR"
chmod 0750 "$REPO_ROOT" "$HOOKS_DIR"

# 5. Install the FAIL-CLOSED placeholder pre-receive. Staged to /tmp by cloud-init
#    (base64). core.hooksPath (step 6) points every per-workspace bare repo at it,
#    so a push is rejected until the real fence hook lands via the deploy pipeline.
#    Re-runnable: skip the staged install only when the hook is already in place.
if [[ -f "$PLACEHOLDER_STAGED" ]]; then
  assert_not_symlink "$PLACEHOLDER_STAGED"
  install -o "$GIT_USER" -g "$GIT_USER" -m 0755 "$PLACEHOLDER_STAGED" "$PRE_RECEIVE"
elif [[ ! -f "$PRE_RECEIVE" ]]; then
  log "FATAL: placeholder hook not staged at $PLACEHOLDER_STAGED and $PRE_RECEIVE absent"
  exit 1
fi

# 6. System-wide hooksPath so every bare repo (created on demand by the app) gets
#    the fence WITHOUT per-repo hook installation. pre-receive fires only on push;
#    server-side `git init --bare` is unaffected.
git config --system core.hooksPath "$HOOKS_DIR"

# 7. Liveness assert — fail LOUD if any invariant is unmet (the post-merge
#    readiness/cutover gate surfaces it; never leave a half-provisioned host
#    silently "green" — hr-fresh-host-provisioning-reachable-from-terraform-apply).
mountpoint -q "$GIT_DATA_ROOT" || {
  log "FATAL: volume unmounted post-bootstrap"
  exit 1
}
[[ -x "$PRE_RECEIVE" ]] || {
  log "FATAL: pre-receive hook missing/not executable"
  exit 1
}
[[ "$(git config --system core.hooksPath)" == "$HOOKS_DIR" ]] || {
  log "FATAL: core.hooksPath not set to $HOOKS_DIR"
  exit 1
}
log "bootstrap complete: volume mounted, git+flock present, bare-repo root $REPO_ROOT, fail-closed placeholder hook active"
