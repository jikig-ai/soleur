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

# (#6982, W1) Teach the EXISTING log() to speak off-box. Step 7 already asserts every
# invariant the boot signal needs, fail-loud; the only defect was that `log` went NOWHERE
# off-box on a host with no SSH and no console. Routing on the FATAL prefix (rather than a
# die() at 12 sites) makes it impossible to add a future FATAL without an emit. Fail-open.
GIT_DATA_EMIT="${GIT_DATA_EMIT:-/usr/local/bin/git-data-emit}"
log() {
  echo "[git-data-bootstrap] $*"
  case "$*" in
    FATAL:*) [ -x "$GIT_DATA_EMIT" ] && "$GIT_DATA_EMIT" "git-data bootstrap FATAL" bootstrap fatal "$*" || true ;;
  esac
}

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

# 1. The substrate MUST be on the block volume. cloud-init mounts it by STABLE by-id device
#    (cloud-init-git-data.yml:117 pins scsi-0HC_Volume_${git_data_volume_id}); this glob is only
#    a degraded-remount FALLBACK reached iff that pinned mount was lost. #6604 note: the
#    glob-ambiguity #6604 fixes ("once a LUKS volume attaches beside the LIVE plaintext /mnt/data,
#    the glob binds the wrong device") is a WEB-1 condition — it does NOT bite here. On the
#    git-data host the plaintext mount is already by-id-pinned at boot, and if this fallback runs
#    on the 2-volume set it FAILS LOUD (a multi-device `mount` errors → the mountpoint check below
#    exits 1), never silently mounting the wrong volume. The LUKS store is selected by an explicit
#    `cryptsetup isLuks` discriminator below (§1b), not a positional glob.
mkdir -p "$GIT_DATA_ROOT"
if ! mountpoint -q "$GIT_DATA_ROOT"; then
  log "volume not mounted at $GIT_DATA_ROOT — attempting mount"
  mount /dev/disk/by-id/scsi-0HC_Volume_* "$GIT_DATA_ROOT" || true
fi
if ! mountpoint -q "$GIT_DATA_ROOT"; then
  log "FATAL: git-data block volume is not mounted at $GIT_DATA_ROOT"
  exit 1
fi

# 1b. Fresh LUKS-at-rest volume (Sub-PR 3.D cutover target). cloud-init already
#     luksOpened + mounted it at /mnt/git-data-luks under `doppler run`; re-assert
#     IDEMPOTENTLY here — if a boot race left the mapper closed, luksOpen it (the
#     LUKS device is the attached volume that `cryptsetup isLuks` recognizes; the
#     passphrase arrives ONLY as the Doppler-injected GIT_DATA_LUKS_KEY env, piped
#     via stdin, never argv). FAIL LOUD if the key env is absent or the volume is
#     not mounted — the LUKS volume is git-data-cutover.sh's FRESH_ROOT (rsync
#     target); NEVER fall back to an unencrypted mount (NFR-026).
LUKS_ROOT="/mnt/git-data-luks"
LUKS_MAPPER="/dev/mapper/git-data"
mkdir -p "$LUKS_ROOT"
if ! mountpoint -q "$LUKS_ROOT"; then
  if [[ ! -e "$LUKS_MAPPER" ]]; then
    [[ -n "${GIT_DATA_LUKS_KEY:-}" ]] || {
      log "FATAL: GIT_DATA_LUKS_KEY empty — refusing to unlock the LUKS cutover volume unencrypted"
      exit 1
    }
    # #6604 note: this glob is SAFE by construction — the loop selects the LUKS device by an
    # explicit `cryptsetup isLuks` discriminator, so a second (plaintext) volume in the set is
    # skipped, not mis-bound. This is the CORRECT form of the "which device is LUKS" predicate;
    # the web-1 ambiguity #6604 fixes is the INVERSE (a raw-glob mount with no discriminator).
    luks_dev=""
    for dev in /dev/disk/by-id/scsi-0HC_Volume_*; do
      [[ -e "$dev" ]] || continue
      if cryptsetup isLuks "$dev"; then
        luks_dev="$dev"
        break
      fi
    done
    [[ -n "$luks_dev" ]] || {
      log "FATAL: no LUKS-formatted volume found among attached block volumes"
      exit 1
    }
    printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksOpen --key-file - "$luks_dev" git-data || {
      log "FATAL: luksOpen failed for $luks_dev"
      exit 1
    }
  fi
  mount "$LUKS_MAPPER" "$LUKS_ROOT" || true
fi
if ! mountpoint -q "$LUKS_ROOT"; then
  log "FATAL: fresh LUKS cutover volume is not mounted at $LUKS_ROOT — refusing to continue"
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

# 4b. Repo-root reconcile (ADR-068 amendment 2026-07-01 "PR B bare-repo
#     provisioning"). The git-shell TRANSPORT resolves push URL paths relative to
#     the git user's HOME ($GIT_HOME), while the PROVISION wrapper writes absolute
#     paths under $REPO_ROOT (/mnt/git-data/repositories). Symlink so a push URL of
#     `.../repositories/<id>.git` and the provisioned `/mnt/git-data/repositories/
#     <id>.git` resolve to the IDENTICAL $GIT_DIR the fence keys on — otherwise the
#     transport would push to a different repo than the one provisioned/fenced.
#     `ln -sfn` is idempotent (re-point, never nest a link inside an existing dir).
ln -sfn "$REPO_ROOT" "$GIT_HOME/repositories"
chown -h "$GIT_USER:$GIT_USER" "$GIT_HOME/repositories"

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

# 6b. Advertise push-options so the app-server's fence-guarded replication push
#     can deliver `--push-option=lease-gen=<N> --push-option=worktree-id=<id>`
#     (worktree-id is PER-USER since Phase 3 / ADR-068 D0, no longer "primary")
#     to the pre-receive CAS fence (ADR-068 amendment, PR B). WITHOUT this, git
#     silently drops the options and the hook never sees the gen — the fence then
#     fail-closed-rejects every push. Forward-compat: the Phase-2 replication push
#     is app-server-side; the in-sandbox GIT_PUSH_OPTION_* path lands in Phase 3.
git config --system receive.advertisePushOptions true

# 6c. (#6982, W4) Move maintenance OFF the push path and BOUND its peak. This is what makes
# ADR-068 D1's "neither CPU- nor RAM-bound" true rather than asserted: git's DEFAULTS make a
# 2 vCPU/4 GB/no-swap box burst-bound (receive.autogc ON = every push can trigger an inline
# server-side repack; pack.windowMemory UNLIMITED; gc.autoDetach hides the OOM from the
# pushing client). The burst is a CONFIG artifact, not a property of the store. Maintenance
# still runs, daily, under systemd caps — `gc.auto 0` means "never as a side effect of
# someone else's push". See ADR-068 D-SIZE.
git config --system receive.autogc false
git config --system gc.auto 0
git config --system gc.autoDetach false
# unpackLimit=1 — KEEP EVERY PUSH PACKED. Unset it inherits transfer.unpackLimit (100), so a
# push under 100 objects explodes to loose — and the modal session push is under 100. Measured:
# 79,411 objects = 700 MB/79,411 inodes loose vs 123 MiB/2 packed; mkfs gives this 10 GB volume
# 655,360 inodes, so inodes exhaust at ~55-60% of BYTES — ENOSPC while df-bytes reads healthy.
# gc.auto=0 means nothing packs it until the timer.
git config --system receive.unpackLimit 1
# receive.maxInputSize bounds a SINGLE push. Unset, one client can fill the shared 10 GB
# volume for every other workspace -- a blast radius, not a per-user quota. 512 MiB, not the
# 2 GiB first shipped: index-pack writes the incoming stream to disk WHILE validating, so the
# limit is only enforced after the bytes have landed. At 2 GiB one push transiently takes 20%
# of the shared store and five concurrent ones ENOSPC it for everyone -- which is the very
# failure the bound exists to prevent, so the sizing had to survive its own argument.
git config --system receive.maxInputSize 536870912
# 64m window / 128m pack / single thread: sized to leave headroom on a 4 GB box that also
# serves receive-pack. threads=1 because parallel delta search multiplies the window
# budget by the thread count, which is the actual OOM path.
git config --system pack.windowMemory 64m
git config --system pack.packSizeLimit 128m
git config --system pack.threads 1
git config --system pack.deltaCacheSize 64m
# Above this, store blobs undeltified rather than spending window memory on them.
git config --system core.bigFileThreshold 32m
# safe.directory — WITHOUT THIS THE MAINTENANCE TIMER IS A NO-OP THAT REPORTS SUCCESS.
# The repos are created by git-data-provision.sh as the `git` user and REPO_ROOT is chowned
# to git above; git-data-gc.service runs as ROOT. Since git 2.35 that combination is
# refused: "fatal: detected dubious ownership in repository" (reproduced, rc=128) — so
# reflog-expire, repack and prune ALL fail per repo, and because the script exits 0 on
# per-repo failures systemd reports the unit successful. ADR-068's D-SIZE sizing argument
# rests on this maintenance path actually running.
git config --system safe.directory "$REPO_ROOT/*"

# 7. Liveness assert — fail LOUD if any invariant is unmet (the post-merge
#    readiness/cutover gate surfaces it; never leave a half-provisioned host
#    silently "green" — hr-fresh-host-provisioning-reachable-from-terraform-apply).
mountpoint -q "$GIT_DATA_ROOT" || {
  log "FATAL: volume unmounted post-bootstrap"
  exit 1
}
mountpoint -q "$LUKS_ROOT" || {
  log "FATAL: LUKS cutover volume unmounted post-bootstrap"
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
[[ "$(git config --system receive.advertisePushOptions)" == "true" ]] || {
  log "FATAL: receive.advertisePushOptions not advertised — push-option fence unreachable"
  exit 1
}
# (#6982, W4) RE-ASSERT every maintenance setting. A `git config` that silently failed to
# take is indistinguishable from one that was never written, and the failure mode is not
# an error — it is an OOM-killed repack weeks later, on the push path, invisible to the
# client. Asserting the read-back is what makes the D1 claim an enforced invariant.
for _kv in "receive.autogc=false" "gc.auto=0" "gc.autoDetach=false" \
           "receive.unpackLimit=1" "receive.maxInputSize=536870912" \
           "pack.windowMemory=64m" "pack.packSizeLimit=128m" "pack.threads=1" \
           "pack.deltaCacheSize=64m" "core.bigFileThreshold=32m" \
           "safe.directory=$REPO_ROOT/*"; do
  _k="${_kv%%=*}"
  _want="${_kv#*=}"
  _got="$(git config --system "$_k" 2>/dev/null || true)"
  [[ "$_got" == "$_want" ]] || {
    log "FATAL: git config --system $_k is '$_got', expected '$_want' — maintenance would run unbounded on the push path"
    exit 1
  }
done
[[ "$(readlink -f "$GIT_HOME/repositories" 2>/dev/null)" == "$(readlink -f "$REPO_ROOT")" ]] || {
  log "FATAL: $GIT_HOME/repositories does not resolve to $REPO_ROOT — transport push URL and provisioned/fenced repo would diverge"
  exit 1
}
[[ -x /usr/local/bin/git-data-provision.sh ]] || {
  log "FATAL: git-data-provision.sh missing/not executable — bare repos cannot be provisioned before first push"
  exit 1
}
log "bootstrap complete: plaintext volume mounted, LUKS cutover volume mounted at $LUKS_ROOT, git+flock present, bare-repo root $REPO_ROOT, repositories symlink reconciled, provision wrapper present, fail-closed placeholder hook active, push-options advertised"

# 8. (#6982, W1 / ADR-149 item 4) THE BOOT-COMPLETION SIGNAL — the post-apply signal this
# host never had, emitted only here so its mere ARRIVAL means every assertion above passed.
# The birth job POLLS for it rather than treating a green apply as a green boot.
#
# Chosen over arming the heartbeat: a TCP connect-and-close to :22 proves the port is OPEN,
# not that git transport SERVES, and sshd is up before runcmd — so a host whose LUKS never
# mounted answers on :22 and BEATS GREEN. The booleans are all `yes` by construction here;
# they are emitted because the CONSUMER asserts on them, so a weakened assert shows up as a
# false rather than a missing event.
#
# WORDING PINNED (AC30): `luks_mounted` is about the DEVICE. It says NOTHING about the
# repositories being encrypted at rest — they are NOT, REPO_ROOT is the PLAINTEXT volume
# until the cutover, and duplicating that false claim into telemetry would be the Art. 30
# defect in a second artifact. df% is GIT_DATA_ROOT (the volume that fills). No repo paths,
# no UUIDs: four booleans and an integer carry no identifier by construction.
# ipcent too: inodes exhaust ahead of bytes (see 6c), so bytes-only reads healthy to ENOSPC.
# `|| true` because read returns 1 on an empty df and this script is `set -e`.
read -r _disk_pct _inode_pct < <(df --output=pcent,ipcent "$GIT_DATA_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9 \n') || true
if [[ -x "$GIT_DATA_EMIT" ]]; then
  "$GIT_DATA_EMIT" "git-data bootstrap complete" boot_complete info "" \
    "luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" \
    "disk_pct=${_disk_pct:-unknown}" "inode_pct=${_inode_pct:-unknown}" || true
fi
