#!/usr/bin/env bash
#
# git-data LUKS cutover body — epic #5274 Phase 3, Sub-PR 3.D / ADR-068.
#
# Migrates the live per-workspace bare repos from the Phase-2 plaintext ext4
# git-data volume onto a FRESH LUKS-at-rest volume, re-points the git-data host
# mount so /mnt/git-data (the path EVERY wrapper hardcodes) becomes LUKS-backed,
# then flips the `GIT_DATA_STORE_ENABLED` GA flag on BOTH web hosts in lockstep.
# This is the additive rsync-then-flag-flip cutover ADR-068 §1 is designed around
# — NOT an authority flip. Rollback safety rests on the RETAINED FRESH LUKS volume
# + each web host's LOCAL worktree clone; GitHub `origin` is only a SUBSET of
# git-data (see rollback()), so it is NOT a sufficient backstop on its own.
#
# MOUNT-TOPOLOGY (load-bearing — GAP-1 fix):
#   cloud-init mounts the LUKS volume ADDITIVELY at /mnt/git-data-luks, but every
#   host write path hardcodes /mnt/git-data/repositories (the PLAINTEXT volume):
#   git-data-transport-wrapper.sh, git-data-provision.sh, git-data-remove.sh,
#   git-data-bootstrap.sh (root + hooksPath + repositories symlink). The GA flag
#   only controls whether the WEB containers use git-data — it does NOT change the
#   git-data host's mount topology. So we MUST, during the freeze, re-point
#   /dev/mapper/git-data to /mnt/git-data itself (repoint_luks_mount). Then every
#   wrapper/symlink/hooksPath is LUKS-backed with ZERO path changes, and the DL-2
#   wipe is gated behind a canary proving that path is the LUKS mapper — so it can
#   NEVER rm live data on a stale mount.
#
# WRITE-FREEZE (load-bearing — DI-HIGH fix):
#   The real writers are per-turn replicateToGitData from the web hosts, and the
#   pre-receive fence enforces only the lease-gen CAS + namespace ownership — it has
#   NO freeze concept by default. So the AUTHORITATIVE freeze is: DRAIN both web
#   hosts (stop new turns; let in-flight finish) and run the delta-rsync + the
#   set-identity verify that GATE the flip AFTER that drain, against a genuinely
#   quiesced source. Belt-and-suspenders: a sentinel at $OLD_ROOT/.cutover-freeze
#   that git-data-pre-receive.sh now denies receive-pack on (rejects a straggler
#   push loud, rather than losing it on the stale source).
#
# INVOCATION BOUNDARY (load-bearing):
#   Invoked BY .github/workflows/git-data-cutover.yml, which holds the cloud-admin
#   creds OFF the app host (learning 2026-06-02). This script NEVER runs terraform
#   in-process and NEVER embeds cloud-admin creds. The LUKS passphrase stays
#   entirely host-side: prepare_luks_target reaches it ONLY via the host's
#   /etc/default/git-data-doppler + `doppler run` (env GIT_DATA_LUKS_KEY), piped on
#   stdin (`--key-file -`) — NEVER argv, NEVER this script's environment. All host
#   reach is over the private net via the workflow's CF Tunnel SSH bridge.
#
# ACCESS PATH (ADR-220, #6680): the bridge exports WEB_HOST_SSH (root on web-1). There
#   is no route and no authorized CI credential for git-data (10.0.1.20) on its own:
#   git-data is reached through web-1 (`ssh -W`, a direct-tcpip channel — no key and no
#   agent socket lands on web-1), and GIT_DATA_SSH is supplied only once #8189
#   provisions the root key. access_gate runs FIRST on the forward path and exits 3,
#   naming the missing piece, before any host-mutating step. There are no `ssh`
#   fallbacks: an unset invocation fails closed instead of dialing a bare `ssh`.
#
# FAIL-LOUD + AUTO-RECOVERY: every step logs and every guard aborts non-zero. An
# EXIT trap auto-rolls-back a mid-flip failure (flag off) and ALWAYS releases the
# write-freeze (un-drains both hosts) on abort — no stranded writers, no split-brain.
#
# Freeze-window order (GAP-3 + DI-HIGH):
#   prepare_luks_target -> preconditions -> bulk rsync (writers live)
#   -> acquire_freeze (DRAIN both hosts + sentinel) -> delta rsync (post-drain)
#   -> set-identity verify (post-drain — the ONLY verify that gates the flip)
#   -> repoint_luks_mount -> flag flip + reload -> release_freeze (un-drain)
#   -> canary -> (later, gated) old-volume wipe.
#
# Observability: verdict is read from Sentry (op:control_plane_route,
# worktree_lease) + the Better Stack git-data heartbeat, NEVER by SSH-eyeballing a
# host (hr-no-ssh-fallback-in-runbooks). See the runbook.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

log()  { echo "[git-data-cutover] $*"; }
step() { echo; echo "[git-data-cutover] ===== $* ====="; }
die()  { echo "[git-data-cutover] FATAL: $*" >&2; exit 1; }

# --- Configuration (all overridable by the workflow; documented defaults) -----
GIT_DATA_HOST="${GIT_DATA_HOST:-10.0.1.20}"
OLD_ROOT="${OLD_ROOT:-/mnt/git-data}"                 # plaintext source AND final LUKS mount
FRESH_ROOT="${FRESH_ROOT:-/mnt/git-data-luks}"        # LUKS staging mount (cloud-init/prepare)
LUKS_MAPPER="${LUKS_MAPPER:-/dev/mapper/git-data}"    # the opened LUKS device-mapper node
REPO_SUBDIR="${REPO_SUBDIR:-repositories}"
OLD_REPOS="${OLD_ROOT}/${REPO_SUBDIR}"
FRESH_REPOS="${FRESH_ROOT}/${REPO_SUBDIR}"
FREEZE_SENTINEL="${FREEZE_SENTINEL:-${OLD_ROOT}/.cutover-freeze}"
WEB_HOSTS="${WEB_HOSTS:-10.0.1.10}"   # web-2 (10.0.1.11) retired #6538; single-host roster
FLAG_NAME="${FLAG_NAME:-GIT_DATA_STORE_ENABLED}"
DRY_RUN="${DRY_RUN:-0}"
CONFIRM_WIPE="${CONFIRM_WIPE:-0}"
ROLLBACK="${ROLLBACK:-0}"

# --- Roster + invocations: parsed ONCE, used by the gate AND every later call ---
# One parse (`read -ra`: first line only, no glob expansion) so the addresses and argv the
# access gate proves are byte-for-byte the ones the mutating steps later dial. A value that
# is multi-line or not dotted-numeric is recorded, never dialed: an address starting with
# `-` would become an ssh option. Not an exit here — ROLLBACK must still write the flag off.
WEB_HOST_LIST=()
ROSTER_ERR_ROLE=""    # "" when valid; otherwise the role whose input is malformed
ROSTER_ERR_VERDICT=""
resolve_roster() {
  local h
  case "${WEB_HOSTS}${GIT_DATA_HOST}${WEB_HOST_SSH:-}${GIT_DATA_SSH:-}" in
    *$'\n'*) ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_multiline_input; return 0 ;;
  esac
  read -ra WEB_HOST_LIST <<< "$WEB_HOSTS"
  for h in "${WEB_HOST_LIST[@]}"; do
    if ! [[ "$h" =~ ^[0-9.]+$ ]]; then
      WEB_HOST_LIST=(); ROSTER_ERR_ROLE=web; ROSTER_ERR_VERDICT=invalid_host; return 0
    fi
  done
  if ! [[ "$GIT_DATA_HOST" =~ ^[0-9.]+$ ]]; then
    ROSTER_ERR_ROLE=git-data-jump; ROSTER_ERR_VERDICT=invalid_host
  fi
}

# ssh helpers (see ACCESS PATH above). This script holds NO key material inline. An unset
# or blank invocation returns 97 and a malformed git-data address 96 — never a bare `ssh`
# (a fallback is where a never-satisfied export contract hides, learning 2026-07-18).
gd_ssh() {  # gd_ssh <host> <remote-cmd>
  local -a inv
  read -ra inv <<< "${GIT_DATA_SSH:-}"
  [ "${#inv[@]}" -gt 0 ] || { echo "[git-data-cutover] GIT_DATA_SSH unset" >&2; return 97; }
  [ "$ROSTER_ERR_ROLE" != git-data-jump ] || { echo "[git-data-cutover] GIT_DATA_HOST malformed" >&2; return 96; }
  "${inv[@]}" "$1" "$2"
}
web_ssh() { # web_ssh <host> <remote-cmd>
  local -a inv
  read -ra inv <<< "${WEB_HOST_SSH:-}"
  [ "${#inv[@]}" -gt 0 ] || { echo "[git-data-cutover] WEB_HOST_SSH unset" >&2; return 97; }
  "${inv[@]}" "$1" "$2"
}

# --- Recovery state (read by the EXIT trap) ----------------------------------
FREEZE_HELD=0
FLIP_DONE=0
CANARY_OK=0
RECOVERY_FAILED=0   # recovery steps that could not run; ROLLBACK-only mode exits 4 on any
ACCESS_TMP=""       # probe capture dir of the access gate; removed on every exit

# Auto-recovery: on ANY non-zero exit, roll back a completed/partial flip (flag
# off + reload) and ALWAYS release the freeze (un-drain both hosts).
cleanup() {
  local rc=$?
  trap - EXIT
  _access_tmp_drop || true
  if [ "$rc" -eq 0 ]; then exit 0; fi
  if [ "$FLIP_DONE" != "1" ] && [ "$FREEZE_HELD" != "1" ]; then
    log "exit $rc — no flip and no freeze held, nothing to recover"
    exit "$rc"
  fi
  log "ABORT (rc=$rc) — auto-recovery: rollback (if flipped) + release freeze"
  [ "$FLIP_DONE" = "1" ]   && rollback
  [ "$FREEZE_HELD" = "1" ] && release_freeze
  exit "$rc"
}
trap cleanup EXIT

# Read/write the flag from Doppler prd (the workflow injects the token).
read_flag() { doppler secrets get "$FLAG_NAME" --plain -p soleur -c prd 2>/dev/null || echo ""; }
set_flag()  { doppler secrets set "$FLAG_NAME" "$1" --silent --no-interactive -p soleur -c prd; }

# A recovery step (rollback / freeze release) that could not run: logged AND annotated AND
# counted, so a partial recovery is visible in the annotations API and in the exit code.
recovery_warn() { # <step> <rc> <operator message>
  RECOVERY_FAILED=$((RECOVERY_FAILED + 1))
  log "WARNING: $3"
  echo "::warning title=git-data-cutover recovery::step=$1 rc=$2"
}

# ============================================================================
# access_gate — every host reachable and authorized BEFORE any mutation (ADR-220)
# ============================================================================
# Three probes, strictly ordered; each runs only after the previous one read ok:
#   web            every roster member runs `true` over WEB_HOST_SSH.
#   git-data-jump  `ssh -W <git-data>:22 <first roster member>` must return an `SSH-2.0-`
#                  line FIRST: web-1's sshd forwards and something answers as an sshd, with
#                  NO git-data credential (liveness, not authenticity — #7226). The verdict
#                  keys on that line, never the pipeline rc, which is ssh's own exit status.
#                  stdin is /dev/null: its EOF makes the remote close right after the banner;
#                  with stdin held open the probe waits out its timeout.
#   git-data-auth  root login over GIT_DATA_SSH; unset -> git_data_root_key_absent (#8189).
# Non-ok exits 3 from THIS body. Keep the call a plain statement: inside $(...) or a
# pipeline its `exit 3` would only leave a subshell and the mutating steps would run.
# Probe bytes are chosen by the edge or web-1 while host keys are unverified (#7226), and the
# runner parses workflow commands on stdout AND stderr. So every probe writes to a file, the
# -W line is only compared, and a failed probe's stderr is printed capped, printable-ASCII,
# behind a fixed prefix, inside a ::stop-commands:: span keyed on a per-run random token.
# A failure's reason= is a fixed word chosen by grep over that file, never probe bytes.
# ssh keeps the FIRST value of a repeated -o, so the appended options can add, never override.
_access_emit() { # <role> <host> <verdict> [rc] [reason]
  local detail="role=$1 host=$2 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  log "ACCESS ${detail}"
  if [ "$3" = ok ]; then
    echo "::notice title=git-data-cutover access::role=$1 verdict=ok"
  else
    echo "::error title=git-data-cutover access::role=$1 verdict=$3${4:+ rc=$4}${5:+ reason=$5}"
  fi
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- ACCESS %s\n' "$detail" >> "$GITHUB_STEP_SUMMARY" || true
  fi
}
_access_reason() { # <rc> <captured-stderr-file>
  if [ "$1" = 124 ]; then echo timeout
  elif grep -qF 'administratively prohibited' "$2"; then echo forward_refused
  elif grep -qF 'Connection refused' "$2"; then echo connect_refused
  elif grep -qF 'No route to host' "$2"; then echo no_route
  elif grep -qF 'Permission denied' "$2"; then echo auth_refused
  else echo unknown
  fi
}
_access_fail() { # <role> <host> <rc> <captured-stderr-file> — emit, dump, stop
  _access_emit "$1" "$2" failed "$3" "$(_access_reason "$3" "$4")"
  _access_stderr "$4"
  exit 3
}
_access_stderr() { # <captured-stderr-file>
  [ -s "$1" ] || return 0
  local tok l
  tok="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  echo "::stop-commands::${tok}"
  head -c 8192 "$1" | LC_ALL=C tr -cd '\12\40-\176' | while IFS= read -r l || [ -n "$l" ]; do
    printf '[git-data-cutover] probe-stderr: %s\n' "$l"
  done
  echo "::${tok}::"
}
# Removes ONLY the gate's three named captures, then the directory itself: the EXIT trap reads
# a global it did not bind, so nothing here may recurse into whatever that global holds.
_access_tmp_drop() {
  [ -n "$ACCESS_TMP" ] || return 0
  rm -f "$ACCESS_TMP/web.err" "$ACCESS_TMP/jump.err" "$ACCESS_TMP/auth.err"
  rmdir "$ACCESS_TMP" || return 1
  ACCESS_TMP=""
}
access_gate() {
  step "access gate (ADR-220): web -> git-data-jump -> git-data-auth, before any host mutation"
  local h rc first
  local -a inv gdinv
  if [ -n "$ROSTER_ERR_ROLE" ]; then _access_emit "$ROSTER_ERR_ROLE" "<invalid>" "$ROSTER_ERR_VERDICT"; exit 3; fi
  read -ra inv <<< "${WEB_HOST_SSH:-}"
  if [ "${#inv[@]}" -eq 0 ]; then _access_emit web "-" web_host_ssh_unset; exit 3; fi
  if [ "${#WEB_HOST_LIST[@]}" -eq 0 ]; then _access_emit web "-" web_roster_empty; exit 3; fi
  ACCESS_TMP="$(mktemp -d)" || die "access gate: mktemp failed"

  for h in "${WEB_HOST_LIST[@]}"; do
    rc=0
    timeout 30 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$h" true \
      </dev/null >/dev/null 2>"$ACCESS_TMP/web.err" || rc=$?
    [ "$rc" -eq 0 ] || _access_fail web "$h" "$rc" "$ACCESS_TMP/web.err"
    _access_emit web "$h" ok
  done

  rc=0
  first="$(timeout 25 "${inv[@]}" -o BatchMode=yes -o ConnectTimeout=20 -W "${GIT_DATA_HOST}:22" "${WEB_HOST_LIST[0]}" \
    </dev/null 2>"$ACCESS_TMP/jump.err" | head -n 1)" || rc=$?
  first="${first%$'\r'}"
  case "$first" in
    SSH-2.0-*) _access_emit git-data-jump "$GIT_DATA_HOST" ok ;;
    *) _access_fail git-data-jump "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/jump.err" ;;
  esac

  read -ra gdinv <<< "${GIT_DATA_SSH:-}"
  if [ "${#gdinv[@]}" -eq 0 ]; then
    _access_emit git-data-auth "$GIT_DATA_HOST" git_data_root_key_absent
    log "no credential is authorized for root on the git-data host yet — ADR-220; #8189 provisions it."
    exit 3
  fi
  rc=0
  timeout 30 "${gdinv[@]}" -o BatchMode=yes -o ConnectTimeout=20 "$GIT_DATA_HOST" true \
    </dev/null >/dev/null 2>"$ACCESS_TMP/auth.err" || rc=$?
  [ "$rc" -eq 0 ] || _access_fail git-data-auth "$GIT_DATA_HOST" "$rc" "$ACCESS_TMP/auth.err"
  _access_emit git-data-auth "$GIT_DATA_HOST" ok
  _access_tmp_drop
}

# ============================================================================
# prepare_luks_target — idempotent luksOpen + mount at FRESH_ROOT (GAP-2 fix)
# ============================================================================
# cloud-init runs ONLY on first boot, so the maintenance-window apply that ATTACHES
# the LUKS volume to the already-running git-data host does NOT luksFormat/luksOpen/
# mount it — /mnt/git-data-luks would be absent and precondition 0b would (correctly)
# fail loud. This step performs that idempotent unlock+mount itself, mirroring
# git-data-bootstrap.sh's LUKS re-assert. The passphrase is fetched ON the host via
# `doppler run` (env GIT_DATA_LUKS_KEY) and piped on stdin — never argv, never this
# script's env. Fail loud on an empty key — never an unencrypted fallback (NFR-026).
prepare_luks_target() {
  step "prepare LUKS target: idempotent luksOpen + mount at $FRESH_ROOT"
  local remote
  remote="FRESH_ROOT='${FRESH_ROOT}'; LUKS_MAPPER='${LUKS_MAPPER}'
$(cat <<'REMOTE'
set -euo pipefail
mkdir -p "$FRESH_ROOT"
if mountpoint -q "$FRESH_ROOT"; then
  echo "[prepare-luks] already mounted at $FRESH_ROOT (idempotent no-op)"; exit 0
fi
[ -f /etc/default/git-data-doppler ] || { echo "[prepare-luks] FATAL: /etc/default/git-data-doppler absent — cannot fetch GIT_DATA_LUKS_KEY"; exit 1; }
. /etc/default/git-data-doppler
FRESH_ROOT="$FRESH_ROOT" LUKS_MAPPER="$LUKS_MAPPER" \
  # --config prd_git_data (#6982 W0). This runs ON the git-data host under
  # doppler_service_token.git_data, which is scoped to prd_git_data — the CLI ERRORS on a
  # config it is not scoped to, so `--config prd` exits 1 and the cutover dies at step 0.
  # GIT_DATA_LUKS_KEY lives only in prd_git_data, so even a full-prd token resolves empty.
  doppler run --project soleur --config prd_git_data -- bash -s <<'LUKSEOF'
set -euo pipefail
[ -n "${GIT_DATA_LUKS_KEY:-}" ] || { echo "[prepare-luks] FATAL: GIT_DATA_LUKS_KEY empty — refusing an unencrypted unlock"; exit 1; }
if [ ! -e "$LUKS_MAPPER" ]; then
  luks_dev=""
  for dev in /dev/disk/by-id/scsi-0HC_Volume_*; do
    [ -e "$dev" ] || continue
    if cryptsetup isLuks "$dev"; then luks_dev="$dev"; break; fi
  done
  [ -n "$luks_dev" ] || { echo "[prepare-luks] FATAL: no LUKS-formatted volume among attached block volumes"; exit 1; }
  printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksOpen --key-file - "$luks_dev" git-data \
    || { echo "[prepare-luks] FATAL: luksOpen failed for $luks_dev"; exit 1; }
fi
mountpoint -q "$FRESH_ROOT" || mount "$LUKS_MAPPER" "$FRESH_ROOT"
mountpoint -q "$FRESH_ROOT" || { echo "[prepare-luks] FATAL: LUKS volume not mounted at $FRESH_ROOT"; exit 1; }
echo "[prepare-luks] LUKS cutover volume unlocked + mounted at $FRESH_ROOT"
LUKSEOF
REMOTE
)"
  gd_ssh "$GIT_DATA_HOST" "$remote" \
    || die "prepare_luks_target failed — the LUKS volume is not unlocked/mounted at $FRESH_ROOT"
  log "LUKS target ready at $FRESH_ROOT"
}

# ============================================================================
# STEP 0 — Preconditions (fail-closed before touching anything)
# ============================================================================
preconditions() {
  step "STEP 0: preconditions"
  # Host reachability + authorization were proven by access_gate seconds earlier.
  gd_ssh "$GIT_DATA_HOST" "mountpoint -q '$FRESH_ROOT'" \
    || die "fresh LUKS volume is NOT mounted at $FRESH_ROOT (prepare_luks_target should have mounted it)"
  gd_ssh "$GIT_DATA_HOST" "mountpoint -q '$OLD_ROOT'" \
    || die "old git-data volume is NOT mounted at $OLD_ROOT"
  log "old=$OLD_ROOT and fresh(LUKS)=$FRESH_ROOT both mounted"
  local cur
  cur="$(read_flag)" || die "could not read current $FLAG_NAME from Doppler prd"
  [ "$cur" != "true" ] || die "$FLAG_NAME is already 'true' — cutover appears already done; refusing to re-run"
  log "$FLAG_NAME is currently OFF ('${cur:-<unset>}') — clean starting state"
}

# ============================================================================
# STEP 1 — Pass-1 bulk rsync (writers LIVE)
# ============================================================================
bulk_rsync() {
  step "STEP 1: pass-1 bulk rsync (writers live) $OLD_REPOS -> $FRESH_REPOS"
  # Bulk copy with writers still serving prod turns so the post-drain freeze window
  # is short. -aHAX preserves hardlinks/perms/xattrs (object packs + fence sidecar).
  gd_ssh "$GIT_DATA_HOST" \
    "mkdir -p '$FRESH_REPOS' && rsync -aHAX --delete '$OLD_REPOS/' '$FRESH_REPOS/'" \
    || die "pass-1 bulk rsync failed"
  log "pass-1 bulk rsync complete"
}

# ============================================================================
# STEP 2 — Acquire the write-freeze: DRAIN both web hosts + git-data sentinel
# ============================================================================
# Draining BOTH web hosts (stop new turns; let in-flight finish) is the LOAD-BEARING
# freeze — the writers are the web hosts' per-turn replicateToGitData. The sentinel
# is defense-in-depth: git-data-pre-receive.sh denies receive-pack while it exists,
# so a straggler push during the drain-settle window is rejected loud (and retried
# after release), never silently lost on the stale source.
acquire_freeze() {
  step "STEP 2: acquire write-freeze (drain both web hosts + git-data sentinel)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping freeze acquire"; return 0; fi
  gd_ssh "$GIT_DATA_HOST" "touch '$FREEZE_SENTINEL'" \
    || die "could not create freeze sentinel $FREEZE_SENTINEL"
  gd_ssh "$GIT_DATA_HOST" "test -f '$FREEZE_SENTINEL'" \
    || die "freeze sentinel not present after touch — freeze NOT engaged"
  FREEZE_HELD=1   # set before draining so an abort mid-drain still releases it
  for h in "${WEB_HOST_LIST[@]}"; do
    web_ssh "$h" 'systemctl start soleur-drain.service' \
      || die "could not drain web host $h — aborting before delta"
    log "drained web host $h"
  done
  log "write-freeze ENGAGED (sentinel active + both hosts drained); pre-receive denies stragglers"
}

# --ignore-dry-run: ROLLBACK-only mode passes it. The dispatch input dry_run DEFAULTS to
# true, so without it a default rollback dispatch returned here and never released a
# freeze an earlier real run left held (#6680 review, wall 6).
release_freeze() { # [--ignore-dry-run]
  step "release write-freeze (remove sentinel + un-drain both web hosts)"
  if [ "$DRY_RUN" = "1" ] && [ "${1:-}" != "--ignore-dry-run" ]; then log "DRY_RUN: no freeze to release"; return 0; fi
  local h before="$RECOVERY_FAILED"
  gd_ssh "$GIT_DATA_HOST" "rm -f '$FREEZE_SENTINEL'" \
    || recovery_warn freeze_sentinel_rm "$?" "could not remove freeze sentinel $FREEZE_SENTINEL — remove it manually"
  for h in "${WEB_HOST_LIST[@]}"; do
    if web_ssh "$h" 'systemctl stop soleur-drain.service'; then
      log "un-drained web host $h"
    else
      recovery_warn web_undrain "$?" "could not un-drain web host $h — un-drain it manually"
    fi
  done
  if [ "$RECOVERY_FAILED" -eq "$before" ]; then
    FREEZE_HELD=0
    log "write-freeze RELEASED"
  else
    log "write-freeze release INCOMPLETE — FREEZE_HELD stays set so a later abort retries it"
  fi
}

# ============================================================================
# STEP 3 — Pass-2 delta rsync (UNDER freeze — the source is genuinely quiesced)
# ============================================================================
delta_rsync() {
  step "STEP 3: pass-2 delta rsync (post-drain, under freeze)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping delta rsync"; return 0; fi
  gd_ssh "$GIT_DATA_HOST" \
    "rsync -aHAX --delete '$OLD_REPOS/' '$FRESH_REPOS/'" \
    || die "pass-2 delta rsync failed"
  log "pass-2 delta rsync complete — FRESH is byte-current with the drained, quiesced source"
}

# ============================================================================
# STEP 4 — Set-identity verify (NOT count-match) — the gate for the flip
# ============================================================================
# Runs POST-drain so it is not racing live writers (a live write would race → spurious
# MISMATCH, and is exactly the write we must not lose). For EVERY bare repo:
# `git for-each-ref` output IDENTICAL (diff empty) AND `git rev-list --all | sort |
# sha256sum` EQUAL between old and fresh. A count-match would pass a corrupted copy.
# Any mismatch => abort (the EXIT trap releases the freeze; nothing has been flipped).
verify_set_identity() {
  step "STEP 4: set-identity verify (for-each-ref diff + rev-list sha256, per repo)"
  local remote
  remote="OLD_REPOS='${OLD_REPOS}'; FRESH_REPOS='${FRESH_REPOS}'
$(cat <<'REMOTE'
set -euo pipefail
mismatch=0
for oldrepo in "$OLD_REPOS"/*.git; do
  [ -d "$oldrepo" ] || continue
  name="$(basename "$oldrepo")"
  freshrepo="$FRESH_REPOS/$name"
  if [ ! -d "$freshrepo" ]; then
    echo "MISMATCH $name (absent on fresh volume)"; mismatch=1; continue
  fi
  old_refs="$(git --git-dir="$oldrepo" for-each-ref --sort=refname)"
  fresh_refs="$(git --git-dir="$freshrepo" for-each-ref --sort=refname)"
  if [ "$old_refs" != "$fresh_refs" ]; then
    echo "MISMATCH $name (for-each-ref diff)"; mismatch=1; continue
  fi
  old_sha="$(git --git-dir="$oldrepo" rev-list --all | sort | sha256sum | cut -d' ' -f1)"
  fresh_sha="$(git --git-dir="$freshrepo" rev-list --all | sort | sha256sum | cut -d' ' -f1)"
  if [ "$old_sha" != "$fresh_sha" ]; then
    echo "MISMATCH $name (rev-list sha256 $old_sha != $fresh_sha)"; mismatch=1; continue
  fi
  echo "OK $name"
done
[ "$mismatch" -eq 0 ] || exit 3
REMOTE
)"
  gd_ssh "$GIT_DATA_HOST" "$remote" \
    || die "set-identity verify FAILED — repos diverged (see MISMATCH lines). Freeze is auto-released; do NOT flip; re-run rsync"
  log "set-identity verify PASSED for all bare repos — fresh LUKS volume is an exact replica"
}

# ============================================================================
# STEP 5 — Re-point the LUKS mapper to /mnt/git-data (GAP-1 fix)
# ============================================================================
# Runs UNDER freeze, AFTER verify, BEFORE the flip. Makes /dev/mapper/git-data the
# OLD_ROOT (/mnt/git-data) mount so EVERY hardcoded wrapper/symlink/hooksPath
# becomes LUKS-backed with ZERO path changes. Rewrites /etc/fstab so the mapper is
# the durable OLD_ROOT entry and the old plaintext + FRESH_ROOT staging entries are
# gone. Asserts the resulting source device before returning.
repoint_luks_mount() {
  step "STEP 5: re-point $LUKS_MAPPER to $OLD_ROOT (LUKS-back the hardcoded path)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping mount re-point"; return 0; fi
  local remote
  remote="OLD_ROOT='${OLD_ROOT}'; FRESH_ROOT='${FRESH_ROOT}'; LUKS_MAPPER='${LUKS_MAPPER}'
$(cat <<'REMOTE'
set -euo pipefail
# 1. unmount the LUKS volume from its staging mount.
if mountpoint -q "$FRESH_ROOT"; then
  umount "$FRESH_ROOT" || { echo "[repoint-luks] FATAL: could not umount staging $FRESH_ROOT"; exit 1; }
fi
# 2. unmount the old PLAINTEXT volume from OLD_ROOT (writers are drained).
if mountpoint -q "$OLD_ROOT"; then
  umount "$OLD_ROOT" || { echo "[repoint-luks] FATAL: could not umount plaintext $OLD_ROOT (writers still draining?)"; exit 1; }
fi
# 3. mount the LUKS mapper AT OLD_ROOT.
mount "$LUKS_MAPPER" "$OLD_ROOT" || { echo "[repoint-luks] FATAL: could not mount $LUKS_MAPPER at $OLD_ROOT"; exit 1; }
# 4. rewrite /etc/fstab: drop any entry mounting at OLD_ROOT or FRESH_ROOT, add the
#    single durable mapper->OLD_ROOT entry. Idempotent.
cp /etc/fstab "/etc/fstab.cutover.bak.$(date -u +%Y%m%dT%H%M%SZ)"
grep -vE "[[:space:]](${OLD_ROOT}|${FRESH_ROOT})[[:space:]]" /etc/fstab > /etc/fstab.cutover.new || true
echo "$LUKS_MAPPER $OLD_ROOT ext4 defaults,nofail 0 2" >> /etc/fstab.cutover.new
mv /etc/fstab.cutover.new /etc/fstab
# 5. assert the source device of OLD_ROOT is now the mapper.
src="$(findmnt -no SOURCE "$OLD_ROOT" 2>/dev/null || echo "")"
[ "$src" = "$LUKS_MAPPER" ] || { echo "[repoint-luks] FATAL: $OLD_ROOT source is '$src', expected $LUKS_MAPPER"; exit 1; }
echo "[repoint-luks] $OLD_ROOT is now backed by $LUKS_MAPPER (LUKS-at-rest); fstab rewritten"
REMOTE
)"
  gd_ssh "$GIT_DATA_HOST" "$remote" \
    || die "repoint_luks_mount failed — $OLD_ROOT is NOT LUKS-backed; do NOT flip"
  log "$OLD_ROOT is now LUKS-backed via $LUKS_MAPPER"
}

# ============================================================================
# STEP 6 — Coordinated flag flip + reload (both hosts already drained)
# ============================================================================
# Both hosts are drained (freeze), so no turn straddles the non-atomic Doppler
# propagation. Set FLIP_DONE=1 BEFORE the write so a mid-flip failure (reload on the
# 2nd host) auto-rolls-back via the EXIT trap.
flip_flag_and_reload() {
  step "STEP 6: coordinated flag flip ($FLAG_NAME -> true) + reload both hosts"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping flip/reload"; return 0; fi
  FLIP_DONE=1
  set_flag "true" || die "flag write failed — hosts drained but flag not set"
  for h in "${WEB_HOST_LIST[@]}"; do
    web_ssh "$h" 'systemctl restart soleur-web.service' \
      || die "could not reload web host $h after flip — auto-rollback engaging"
    log "reloaded web host $h with $FLAG_NAME=true"
  done
  log "coordinated flip complete — both hosts now read from the LUKS git-data volume"
}

# ============================================================================
# ROLLBACK — flag off + reload (DI-MEDIUM: origin is a SUBSET, NOT the backstop)
# ============================================================================
# Rollback is SAFE, but NOT because "origin holds everything" — it does NOT.
# replicateToGitData force-pushes ALL refs to git-data, whereas the app's syncPush
# only auto-commits knowledge-base/** and reroutes protected pushes to a PR branch,
# so GitHub `origin` is a STRICT SUBSET of git-data. On rollback the flag is OFF, so
# replicateToGitData no-ops and the app reverts to its local-clone + origin baseline.
# The real backstops for any git-data-ONLY post-flip writes are (a) each web host's
# LOCAL worktree clone and (b) the FRESH LUKS volume, which PHYSICALLY RETAINS every
# post-flip write.
# WARNING: after a rollback, do NOT run the DL-2 wipe of the FRESH LUKS volume until
# those git-data-only post-flip writes are reconciled — origin does NOT hold them.
rollback() {
  step "ROLLBACK: $FLAG_NAME -> off + reload both hosts"
  local h
  set_flag "false" \
    || recovery_warn set_flag "$?" "could not write $FLAG_NAME=false — set it manually in Doppler prd NOW"
  [ "$ROSTER_ERR_ROLE" != web ] \
    || recovery_warn web_roster "3" "WEB_HOSTS/invocations malformed ($ROSTER_ERR_VERDICT) — no web host reloaded"
  for h in "${WEB_HOST_LIST[@]}"; do
    web_ssh "$h" 'systemctl restart soleur-web.service' \
      || recovery_warn web_restart "$?" "could not reload $h during rollback — reload it manually"
  done
  FLIP_DONE=0
  if [ "$RECOVERY_FAILED" -eq 0 ]; then
    log "ROLLBACK complete — both hosts back on the pre-cutover read path."
  else
    log "ROLLBACK attempted with $RECOVERY_FAILED failed step(s) — hosts may NOT be on the pre-cutover read path."
  fi
  log "git-data-only post-flip writes are RETAINED on the FRESH LUKS volume + host-local clones (NOT origin) — reconcile them before ANY FRESH-volume wipe."
}

# ============================================================================
# STEP 7 — Canary: a fresh write under /mnt/git-data lands on the LUKS device
# ============================================================================
# Proves the re-point took: OLD_ROOT's source device AND a fresh write's backing
# device are BOTH /dev/mapper/git-data. MUST pass before CONFIRM_WIPE is honored —
# so the DL-2 wipe can never destroy live data on a stale mount.
canary_luks_device() {
  step "STEP 7: canary — fresh write under $OLD_ROOT is LUKS-backed"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping canary"; return 0; fi
  local remote
  remote="OLD_ROOT='${OLD_ROOT}'; LUKS_MAPPER='${LUKS_MAPPER}'
$(cat <<'REMOTE'
set -euo pipefail
src="$(findmnt -no SOURCE "$OLD_ROOT" 2>/dev/null || echo "")"
[ "$src" = "$LUKS_MAPPER" ] || { echo "[canary] FAIL: $OLD_ROOT source '$src' != $LUKS_MAPPER"; exit 1; }
canary="$OLD_ROOT/.cutover-canary"
touch "$canary" || { echo "[canary] FAIL: cannot write under $OLD_ROOT"; exit 1; }
dev="$(df --output=source "$canary" | tail -n1 | tr -d '[:space:]')"
rm -f "$canary"
[ "$dev" = "$LUKS_MAPPER" ] || { echo "[canary] FAIL: fresh write backed by '$dev' != $LUKS_MAPPER"; exit 1; }
echo "[canary] OK: fresh write under $OLD_ROOT is LUKS-backed ($LUKS_MAPPER)"
REMOTE
)"
  gd_ssh "$GIT_DATA_HOST" "$remote" \
    || die "canary FAILED — $OLD_ROOT is NOT LUKS-backed; the wipe stays gated. Investigate the re-point"
  CANARY_OK=1
  log "canary PASSED — $OLD_ROOT is confirmed LUKS-at-rest; DL-2 wipe is now permissible"
}

# ============================================================================
# STEP 8 — Post-flip health confirmation (observability, NOT SSH eyeballing)
# ============================================================================
health_pointer() {
  step "STEP 8: post-flip health (read from observability layer)"
  cat <<'HEALTH'
[git-data-cutover] Confirm health from the observability layer (NO ssh):
  - Sentry: op:control_plane_route failures == 0, worktree_lease reject == 0.
  - Sentry: git-data member:false cross-tenant denials == 0.
  - Better Stack: soleur-git-data heartbeat GREEN (GIT_DATA_HEARTBEAT_URL).
  If any is unhealthy, run this script with ROLLBACK=1 and investigate.
HEALTH
}

# ============================================================================
# STEP 9 — Old-volume decommission / wipe (DL-2) — FINAL double-gated step
# ============================================================================
# Runs ONLY after the CANARY confirms /mnt/git-data is LUKS-backed AND CONFIRM_WIPE=1
# (never in dry-run). The canary gate is what makes this safe: without it a stale
# mount would leave OLD_REPOS pointing at the plaintext (LIVE) volume. After the
# re-point the old PLAINTEXT volume is UNMOUNTED, so the wipe is a terraform detach+
# destroy of that detached block volume — NOT an rm of OLD_REPOS (which now resolves
# to the LUKS-backed LIVE data). NB: never reach this step after a rollback (the
# forward path exits before it; rollback runs via the trap or ROLLBACK-only mode).
old_volume_wipe() {
  step "STEP 9: old-volume decommission/wipe (DL-2)"
  if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: skipping old-volume wipe"; return 0; fi
  if [ "$CANARY_OK" != "1" ]; then
    die "refusing wipe — canary did not confirm $OLD_ROOT is LUKS-backed (a stale mount could point at LIVE data)"
  fi
  if [ "$CONFIRM_WIPE" != "1" ]; then
    log "CONFIRM_WIPE!=1 — leaving the old plaintext volume intact (dual-existence)."
    log "Re-run with CONFIRM_WIPE=1 AFTER the soak confirms health to complete DL-2."
    return 0
  fi
  log "canary-gated: $OLD_ROOT is LUKS-backed; the old plaintext block volume is detached (unmounted by repoint)."
  log "NEXT (operator/terraform, NOT this script): secure-wipe + detach + destroy the old hcloud_volume so the decommissioned plaintext disk carries no user content (DL-2 complete)."
}

# ============================================================================
# Main
# ============================================================================
main() {
  # Rollback-only recovery mode (workflow_dispatch rollback=true). Reverts the flag
  # and ensures the freeze is released; ignores DRY_RUN. No access probe runs here:
  # the flag-off write needs no SSH and must never wait on one. Exit 4 when any
  # recovery step could not run, so a rollback that recovered nothing is never green.
  resolve_roster
  if [ "$ROLLBACK" = "1" ]; then
    step "ROLLBACK-ONLY mode (operator-invoked recovery)"
    rollback
    release_freeze --ignore-dry-run
    if [ "$RECOVERY_FAILED" -gt 0 ]; then
      log "rollback-only INCOMPLETE: $RECOVERY_FAILED recovery step(s) could not run — see the ::warning annotations"
      exit 4
    fi
    log "rollback-only complete"
    exit 0
  fi

  log "starting git-data LUKS cutover (DRY_RUN=$DRY_RUN, CONFIRM_WIPE=$CONFIRM_WIPE)"
  access_gate
  prepare_luks_target        # GAP-2: unlock+mount the LUKS volume (cloud-init won't on a running host)
  preconditions
  bulk_rsync                 # writers live
  acquire_freeze             # drain BOTH hosts (+ sentinel) — the authoritative freeze
  delta_rsync                # post-drain, quiesced source
  verify_set_identity        # post-drain gate; abort → trap releases freeze
  repoint_luks_mount         # GAP-1: /mnt/git-data now LUKS-backed
  flip_flag_and_reload       # abort → trap rolls back + releases freeze
  release_freeze             # un-drain both hosts
  canary_luks_device         # GAP-1 canary; gates the wipe
  health_pointer
  old_volume_wipe            # double-gated on CANARY_OK + CONFIRM_WIPE
  log "cutover body complete. GA verdict is soak-gated: scripts/followthroughs/phase3-ga-soak-5274.sh"
}

main "$@"
