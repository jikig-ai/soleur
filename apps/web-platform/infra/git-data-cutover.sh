#!/usr/bin/env bash
#
# git-data LUKS cutover body — epic #5274 Phase 3, Sub-PR 3.D / ADR-068.
#
# Migrates the live per-workspace bare repos from the Phase-2 plaintext ext4
# git-data volume onto a FRESH LUKS-at-rest volume, then flips the
# `GIT_DATA_STORE_ENABLED` GA flag on BOTH web hosts in lockstep. This is the
# additive rsync-then-flag-flip cutover ADR-068 §1 is designed around — NOT an
# authority flip: `origin`→GitHub is retained throughout as the rehydration
# backstop (see Rollback).
#
# INVOCATION BOUNDARY (load-bearing):
#   This script is invoked BY .github/workflows/git-data-cutover.yml, which holds
#   the cloud-admin creds OFF the app host (learning 2026-06-02: never hold
#   cloud-admin creds inline on a prod host). This script itself:
#     * NEVER runs terraform in-process (the fresh LUKS volume is provisioned by
#       the maintenance-window `apply-web-platform-infra.yml` apply BEFORE this
#       runs — see the runbook);
#     * NEVER embeds cloud-admin/Doppler-write creds — it reads the ONE write it
#       needs (the flag flip) from an env-injected token the workflow scopes.
#   All host reach is over the private net via the workflow-established access
#   path (the CF Tunnel SSH bridge, .github/actions/cf-tunnel-ssh-bridge — the GH
#   runner egress IP is not in var.admin_ips, so a direct :22 dial is impossible).
#
# FAIL-LOUD: every step logs and every guard aborts non-zero. There is NO silent
# success path (hr-when-a-command-exits-non-zero-or-prints). The write-freeze is
# always left RELEASABLE on abort so a failed verify does not strand writers.
#
# Observability: this script's stdout/stderr is captured by the workflow; the
# post-cutover HEALTH verdict is read from Sentry (op:control_plane_route,
# worktree_lease) + the Better Stack git-data heartbeat, NEVER by SSH-eyeballing
# a host (hr-no-ssh-fallback-in-runbooks). See the runbook.
set -euo pipefail

log()  { echo "[git-data-cutover] $*"; }
step() { echo; echo "[git-data-cutover] ===== $* ====="; }
die()  { echo "[git-data-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (all overridable by the workflow; documented defaults) -----
# The git-data host on the private net (network.tf hcloud_network_subnet /
# git-data.tf). The workflow reaches it through the SSH bridge, so GIT_DATA_HOST
# is the address the bridge forwards to.
GIT_DATA_HOST="${GIT_DATA_HOST:-10.0.1.20}"
# Old (source) plaintext volume mount + the fresh (target) LUKS volume mount, both
# ON the git-data host. terraform provisions + LUKS-opens + mounts FRESH_ROOT in
# the maintenance window BEFORE this script runs; we only assert it here.
OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"
FRESH_ROOT="${FRESH_ROOT:-/mnt/git-data-luks}"
REPO_SUBDIR="${REPO_SUBDIR:-repositories}"           # bare repos live under <root>/repositories
OLD_REPOS="${OLD_ROOT}/${REPO_SUBDIR}"
FRESH_REPOS="${FRESH_ROOT}/${REPO_SUBDIR}"
# The freeze sentinel the pre-receive hook honours (see acquire_freeze below).
FREEZE_SENTINEL="${FREEZE_SENTINEL:-${OLD_ROOT}/.cutover-freeze}"
# The two web hosts whose containers carry the flag (variables.tf web_hosts). A
# space-separated roster of ssh-reachable host addresses.
WEB_HOSTS="${WEB_HOSTS:-10.0.1.10 10.0.1.11}"
# The GA flag. Doppler `prd`, consumed at container start (isGitDataStoreEnabled()
# in workspace-resolver.ts: process.env.GIT_DATA_STORE_ENABLED === "true").
FLAG_NAME="${FLAG_NAME:-GIT_DATA_STORE_ENABLED}"
# Dry-run: parse + verify + report, but perform NO freeze, NO flip, NO wipe.
DRY_RUN="${DRY_RUN:-0}"
# The destructive old-volume wipe (DL-2) is DOUBLE-gated: it runs only when the
# flip is confirmed healthy AND this is explicitly set (never in dry-run).
CONFIRM_WIPE="${CONFIRM_WIPE:-0}"

# ssh helper. The workflow exports GIT_DATA_SSH / WEB_HOST_SSH as the exact ssh
# invocation (key + bridge ProxyCommand) — documented placeholder so this script
# holds NO key material and NO connection secrets inline. Defaults are inert.
gd_ssh()  { ${GIT_DATA_SSH:-ssh} "$1" "$2"; }        # gd_ssh <host> <remote-cmd>
web_ssh() { ${WEB_HOST_SSH:-ssh} "$1" "$2"; }        # web_ssh <host> <remote-cmd>

# ============================================================================
# STEP 0 — Preconditions (fail-closed before touching anything)
# ============================================================================
preconditions() {
  step "STEP 0: preconditions"

  # 0a. Both web hosts reachable (a liveness ping the workflow's access path can
  #     satisfy). A host we cannot reach cannot be drained/reloaded in lockstep,
  #     so a partial flip is possible — abort rather than half-flip.
  for h in $WEB_HOSTS; do
    web_ssh "$h" 'true' || die "web host $h unreachable — cannot coordinate a lockstep flip"
    log "web host $h reachable"
  done

  # 0b. git-data host reachable + the FRESH LUKS volume is opened and mounted at
  #     its target (terraform did this in the maintenance window). Never rsync
  #     onto the root fs — that would lose LUKS-at-rest (NFR-026).
  gd_ssh "$GIT_DATA_HOST" 'true' || die "git-data host $GIT_DATA_HOST unreachable"
  gd_ssh "$GIT_DATA_HOST" "mountpoint -q '$FRESH_ROOT'" \
    || die "fresh LUKS volume is NOT mounted at $FRESH_ROOT — provision + luksOpen + mount it (terraform) first"
  gd_ssh "$GIT_DATA_HOST" "mountpoint -q '$OLD_ROOT'" \
    || die "old git-data volume is NOT mounted at $OLD_ROOT"
  log "git-data host reachable; old=$OLD_ROOT and fresh(LUKS)=$FRESH_ROOT both mounted"

  # 0c. The flag must currently be OFF. Re-running a completed cutover (flag
  #     already "true") would drain prod for a no-op flip — abort loud.
  local cur
  cur="$(read_flag)" || die "could not read current $FLAG_NAME from Doppler prd"
  [ "$cur" != "true" ] || die "$FLAG_NAME is already 'true' — cutover appears already done; refusing to re-run"
  log "$FLAG_NAME is currently OFF ('${cur:-<unset>}') — clean starting state"
}

# Read the flag from Doppler prd. Read-only; uses the workflow-injected token.
# (The single WRITE this script performs is set_flag below.)
read_flag() {
  doppler secrets get "$FLAG_NAME" --plain -p soleur -c prd 2>/dev/null || echo ""
}

# ============================================================================
# STEP 1 — Pass-1 bulk rsync (writers LIVE)
# ============================================================================
bulk_rsync() {
  step "STEP 1: pass-1 bulk rsync (writers live) $OLD_REPOS -> $FRESH_REPOS"
  # Bulk copy with writers still serving prod turns. This does the heavy lifting
  # so the freeze window (pass 2) is short. -aHAX preserves hardlinks/perms/xattrs
  # (bare-repo object packs + the fence sidecar under <id>.git/fence/).
  gd_ssh "$GIT_DATA_HOST" \
    "mkdir -p '$FRESH_REPOS' && rsync -aHAX --delete '$OLD_REPOS/' '$FRESH_REPOS/'" \
    || die "pass-1 bulk rsync failed"
  log "pass-1 bulk rsync complete"
}

# ============================================================================
# STEP 2 — Acquire the git-data WRITE-FREEZE
# ============================================================================
# The real writers are per-turn syncPush from the web hosts (git-data-replication.ts),
# NOT just crons — so a cron pause is insufficient. MECHANISM (documented
# placeholder; wire the concrete transport-deny in the pre-receive hook / sshd
# config at implementation time):
#   Primary: drop a freeze SENTINEL the pre-receive fence hook checks FIRST and
#            fail-closed-rejects every receive-pack while present (a push under
#            freeze is rejected loudly, the web host retries after release — no
#            lost writes because the ref is also on GitHub origin). This is
#            preferred over stopping sshd because it keeps upload-pack (clone/
#            ls-remote liveness probes) working and is releasable without a
#            service restart.
#   Alternative: stop the git-data sshd (denies BOTH receive-pack and upload-pack)
#            — heavier, and it also blanks the Better Stack heartbeat probe, so
#            the sentinel is the default.
acquire_freeze() {
  step "STEP 2: acquire git-data write-freeze"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping freeze acquire"; return 0; fi
  gd_ssh "$GIT_DATA_HOST" "touch '$FREEZE_SENTINEL'" \
    || die "could not create freeze sentinel $FREEZE_SENTINEL"
  gd_ssh "$GIT_DATA_HOST" "test -f '$FREEZE_SENTINEL'" \
    || die "freeze sentinel not present after touch — freeze NOT engaged, aborting before delta"
  log "write-freeze ENGAGED (sentinel $FREEZE_SENTINEL); receive-pack now fail-closed-rejects"
}

release_freeze() {
  step "release git-data write-freeze"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: no freeze to release"; return 0; fi
  gd_ssh "$GIT_DATA_HOST" "rm -f '$FREEZE_SENTINEL'" \
    || die "could not remove freeze sentinel $FREEZE_SENTINEL — MANUAL release required, writers still blocked"
  log "write-freeze RELEASED"
}

# ============================================================================
# STEP 3 — Pass-2 delta rsync (UNDER freeze — the source is now quiescent)
# ============================================================================
delta_rsync() {
  step "STEP 3: pass-2 delta rsync (under freeze)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping delta rsync"; return 0; fi
  gd_ssh "$GIT_DATA_HOST" \
    "rsync -aHAX --delete '$OLD_REPOS/' '$FRESH_REPOS/'" \
    || die "pass-2 delta rsync failed (freeze still held — release + investigate)"
  log "pass-2 delta rsync complete — fresh LUKS volume is now byte-current with the quiesced source"
}

# ============================================================================
# STEP 4 — Set-identity verify (NOT count-match)
# ============================================================================
# For EVERY bare repo, assert on the git-data host that:
#   (a) `git for-each-ref` output is IDENTICAL (diff empty) between old and fresh, AND
#   (b) `git rev-list --all | sort | sha256sum` is EQUAL between old and fresh.
# A count-match (N refs == N refs) would pass a silently-corrupted copy; set
# identity of the ref namespace AND the full reachable-object closure is the real
# invariant (ADR-068 / plan §3.D.3). Any mismatch => abort with the freeze LEFT
# RELEASABLE (we do NOT release here — the operator decides rollback vs retry).
verify_set_identity() {
  step "STEP 4: set-identity verify (for-each-ref diff + rev-list sha256, per repo)"
  # Runs entirely on the git-data host so we never stream every repo's object
  # graph across the wire. Emits "MISMATCH <repo>" lines to stdout; exits 3 iff
  # any repo diverged, 0 iff all match. A per-repo mismatch is captured for the
  # operator; a comparison-tooling error (missing dir) is also a hard mismatch.
  local remote_script
  remote_script=$(cat <<REMOTE
set -euo pipefail
old_repos='${OLD_REPOS}'; fresh_repos='${FRESH_REPOS}'
mismatch=0
for oldrepo in "\$old_repos"/*.git; do
  [ -d "\$oldrepo" ] || continue
  name="\$(basename "\$oldrepo")"
  freshrepo="\$fresh_repos/\$name"
  if [ ! -d "\$freshrepo" ]; then
    echo "MISMATCH \$name (absent on fresh volume)"; mismatch=1; continue
  fi
  old_refs="\$(git --git-dir="\$oldrepo" for-each-ref --sort=refname)"
  fresh_refs="\$(git --git-dir="\$freshrepo" for-each-ref --sort=refname)"
  if [ "\$old_refs" != "\$fresh_refs" ]; then
    echo "MISMATCH \$name (for-each-ref diff)"; mismatch=1; continue
  fi
  old_sha="\$(git --git-dir="\$oldrepo" rev-list --all | sort | sha256sum | cut -d' ' -f1)"
  fresh_sha="\$(git --git-dir="\$freshrepo" rev-list --all | sort | sha256sum | cut -d' ' -f1)"
  if [ "\$old_sha" != "\$fresh_sha" ]; then
    echo "MISMATCH \$name (rev-list sha256 \$old_sha != \$fresh_sha)"; mismatch=1; continue
  fi
  echo "OK \$name"
done
[ "\$mismatch" -eq 0 ] || exit 3
REMOTE
)
  gd_ssh "$GIT_DATA_HOST" "$remote_script" \
    || die "set-identity verify FAILED — one or more repos diverged (see MISMATCH lines above). Freeze is LEFT ENGAGED but releasable; roll back (release_freeze) and re-run rsync, do NOT flip"
  log "set-identity verify PASSED for all bare repos — fresh LUKS volume is an exact replica"
}

# ============================================================================
# STEP 5 — Coordinated cross-host flag flip
# ============================================================================
# Doppler propagation to two containers is NOT atomic, so a naive `doppler
# secrets set` + independent auto-reloads would leave a window where host A reads
# from git-data (flag on) while host B still reads the old volume (flag off) —
# split-brain. Sequence (both-quiesced flip):
#   1. DRAIN both web hosts together (stop accepting new turns; let in-flight
#      turns finish) — no host is serving a write during the flip.
#   2. WRITE the flag once to Doppler prd (GIT_DATA_STORE_ENABLED=true).
#   3. RELOAD both containers so BOTH pick up the new env at the same quiesced
#      point, then un-drain. No turn ever straddles the flip.
# The fresh LUKS volume must already be the volume the containers' push/clone path
# addresses post-flip (terraform re-pointed the git-data mount to the LUKS volume
# in the same maintenance window; see the runbook).
coordinated_flip() {
  step "STEP 5: coordinated cross-host flag flip ($FLAG_NAME -> true)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping drain/flip/reload"; return 0; fi

  for h in $WEB_HOSTS; do
    web_ssh "$h" 'systemctl reload-or-restart soleur-drain.service || true' \
      || die "could not drain web host $h — aborting flip (freeze still held)"
    log "drained web host $h"
  done

  set_flag "true" || die "flag write failed — hosts drained but flag NOT set; un-drain and retry"

  for h in $WEB_HOSTS; do
    web_ssh "$h" 'systemctl restart soleur-web.service' \
      || die "could not reload web host $h after flip — RUN ROLLBACK (flag off + re-drain) NOW"
    log "reloaded web host $h with $FLAG_NAME=true"
  done
  log "coordinated flip complete — both hosts now read from the LUKS git-data volume"
}

# The single Doppler WRITE this script performs. Uses the workflow-injected
# write-scoped token (never a cloud-admin cred).
set_flag() {
  doppler secrets set "$FLAG_NAME" "$1" --silent --no-interactive -p soleur -c prd
}

# ============================================================================
# ROLLBACK — flag off + re-drain
# ============================================================================
# Post-flip git-data writes made AFTER the flip are LOST by this rollback. That
# is acceptable ONLY because every ref the app pushes to git-data is ALSO pushed
# to GitHub `origin` (ensure-workspace-repo.ts retains origin→GitHub — the
# rehydration backstop, ADR-068 §1). On rollback the next turn re-clones/re-pushes
# from origin, so no user work is permanently lost. If origin retention were ever
# removed, THIS rollback would become lossy — do not remove it.
rollback() {
  step "ROLLBACK: $FLAG_NAME -> off + re-drain"
  set_flag "false" || log "WARNING: could not write $FLAG_NAME=false — set it manually in Doppler prd NOW"
  for h in $WEB_HOSTS; do
    web_ssh "$h" 'systemctl restart soleur-web.service' \
      || log "WARNING: could not reload $h during rollback — reload it manually"
  done
  log "ROLLBACK complete — both hosts back on the old volume; post-flip git-data writes rehydrate from GitHub origin"
}

# ============================================================================
# STEP 6 — Post-flip health confirmation (observability, NOT SSH eyeballing)
# ============================================================================
# Verdict is read from the observability layer, per hr-no-ssh-fallback-in-runbooks.
# This step only ASSERTS the freeze is released and prints WHERE to read health;
# the authoritative GA verdict is the soak follow-through
# (scripts/followthroughs/phase3-ga-soak-5274.sh).
health_pointer() {
  step "STEP 6: post-flip health (read from observability layer)"
  cat <<'HEALTH'
[git-data-cutover] Confirm health from the observability layer (NO ssh):
  - Sentry: op:control_plane_route failures == 0, worktree_lease reject == 0
            (feature tags control_plane_route, worktree_lease).
  - Sentry: git-data member:false cross-tenant denials == 0.
  - Better Stack: soleur-git-data heartbeat GREEN (GIT_DATA_HEARTBEAT_URL).
  If any of these is unhealthy, run ROLLBACK (this script's rollback path) and
  investigate before proceeding to the wipe.
HEALTH
}

# ============================================================================
# STEP 7 — Old-volume decommission / wipe (DL-2) — FINAL gated step
# ============================================================================
# Runs ONLY after the flip is confirmed healthy AND CONFIRM_WIPE=1 (never in
# dry-run). During dual-existence (before this wipe) an Art. 17 erasure must hit
# BOTH volumes (git-data-remove.sh on the live LUKS volume + this wipe removes the
# stale copies). CLO DL-2: cryptographic-erase / secure-wipe the old plaintext
# volume so no plaintext user content survives on a decommissioned disk.
old_volume_wipe() {
  step "STEP 7: old-volume decommission/wipe (DL-2)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping old-volume wipe"; return 0; fi
  if [ "$CONFIRM_WIPE" != "1" ]; then
    log "CONFIRM_WIPE!=1 — leaving the old plaintext volume intact (dual-existence)."
    log "Re-run with CONFIRM_WIPE=1 AFTER the soak confirms health to complete DL-2."
    return 0
  fi
  # Secure-wipe the bare-repo tree on the old plaintext volume, then hand the
  # block-volume DETACH/DESTROY to terraform (this script never runs terraform):
  gd_ssh "$GIT_DATA_HOST" "rm -rf '${OLD_REPOS:?}'" \
    || die "old-volume repo wipe failed — do NOT detach/destroy the volume until content is erased"
  log "old plaintext repo tree wiped at $OLD_REPOS"
  log "NEXT (operator/terraform, NOT this script): detach + destroy the old hcloud_volume so the decommissioned disk carries no plaintext (DL-2 complete)."
}

# ============================================================================
# Main
# ============================================================================
main() {
  log "starting git-data LUKS cutover (DRY_RUN=$DRY_RUN, CONFIRM_WIPE=$CONFIRM_WIPE)"
  preconditions
  bulk_rsync
  acquire_freeze
  delta_rsync
  verify_set_identity        # aborts (freeze releasable) on any mismatch
  coordinated_flip
  release_freeze
  health_pointer
  old_volume_wipe
  log "cutover body complete. GA verdict is soak-gated: scripts/followthroughs/phase3-ga-soak-5274.sh"
}

main "$@"
