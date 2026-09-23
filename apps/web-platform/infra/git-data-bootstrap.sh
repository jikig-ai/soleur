#!/usr/bin/env bash
#
# git-data host bootstrap — epic #5274 Phase 2 PR B / ADR-068 §3.
#
# Idempotent. Installs the DURABLE SUBSTRATE for the multi-host /workspaces
# split's git-data store: the block-volume mount, git + flock, the dedicated
# `git` transport user's .ssh perms, the bare-repo root, and a FAIL-CLOSED
# PLACEHOLDER pre-receive hook. The REAL CAS fence (git-data-pre-receive.sh) is
# delivered by a host replace (cloud-init) or the operator root path the cutover
# uses — NEVER by a git-uid channel: $HOOKS_DIR is root:git 0750 and the hook root:root
# (#8043 F9), and the "web-platform deploy pipeline" this header once named was never
# built (ADR-149, F9 disposition). CI cannot SSH either host.
#
# DELIVERY: embedded into cloud-init-git-data.yml via base64encode(file()) and
# run once from runcmd on first boot (mirrors inngest-redis-bootstrap.sh).
#
# The bare repos AND the per-(workspace,worktree) fence sidecar/lock MUST live on
# the persistent block volume, never tmpfs — a reboot resetting the fence max to 0
# would let a stale gen=5 writer beat a fresh 0 (git-data-pre-receive.sh header).
set -euo pipefail
# (#7797) xtrace would print the Doppler-injected LUKS passphrase; refuse before anything reads it.
case "$-" in
  *x*)
    if [ -n "${GIT_DATA_LUKS_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# (#6982, W1) Teach the EXISTING log() to speak off-box. Step 7 already asserts every
# invariant the boot signal needs, fail-loud; the only defect was that `log` went NOWHERE
# off-box on a host with no SSH and no console. Routing on the FATAL prefix (rather than a
# die() at 12 sites) makes it impossible to add a future FATAL without an emit. Fail-open.
GIT_DATA_EMIT="${GIT_DATA_EMIT:-/usr/local/bin/git-data-emit}"
log() {
  # (#7227) fd 2, NOT stdout. The parent runcmd redirects this script's STDERR into the
  # per-stage scoped detail file, so on stdout every one of the FATAL sentences below was
  # invisible to on_err and the bootstrap stage's fatal shipped a detail that knew nothing
  # about the invariant that actually failed. Comments and content in this file are
  # render-stripped (ADR-152), so this costs zero stored user_data bytes.
  echo "[git-data-bootstrap] $*" >&2
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

# 1. THE STORE IS THE LUKS MAPPER, AT /mnt/git-data (#8211, ADR-239). One section, where there
#    used to be two: §1 mounted the PLAINTEXT volume here by a raw `scsi-0HC_Volume_*` glob and
#    §1b re-asserted the LUKS mapper at /mnt/git-data-luks, so the served root was plaintext while
#    every artifact attested encryption. cloud-init's luks_open heredoc now mounts the mapper at
#    /mnt/git-data and nothing mounts the plaintext volume after boot. This section re-asserts that
#    IDEMPOTENTLY: if a boot race left the mapper closed, luksOpen it (the LUKS device is the
#    attached volume `cryptsetup isLuks` recognizes; the passphrase arrives ONLY as the
#    Doppler-injected GIT_DATA_LUKS_KEY env, piped via stdin, never argv) and mount it. Then the
#    SOURCE — not mountedness — must EQUAL the mapper. There is NO plaintext fallback (NFR-026).
#    STORE_DEVICE/STORE_VERIFIED are the test seams every store script shares (contract C1/C2).
STORE_DEVICE="${GIT_DATA_STORE_DEVICE:-/dev/mapper/git-data}"
STORE_VERIFIED="${GIT_DATA_STORE_VERIFIED:-/etc/git-data/store-verified}"
mkdir -p "$GIT_DATA_ROOT"
if ! mountpoint -q "$GIT_DATA_ROOT"; then
  if [[ ! -e "$STORE_DEVICE" ]]; then
    [[ -n "${GIT_DATA_LUKS_KEY:-}" ]] || {
      log "FATAL: GIT_DATA_LUKS_KEY empty — refusing to unlock the LUKS store unencrypted"
      exit 1
    }
    # #6604 note: this glob is SAFE by construction — the loop selects the LUKS device by an
    # explicit `cryptsetup isLuks` discriminator, so the plaintext volume in the set is skipped,
    # not mis-bound. The web-1 ambiguity #6604 fixes is the INVERSE (a raw-glob mount with no
    # discriminator), which is exactly the form this section no longer has.
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
  mount "$STORE_DEVICE" "$GIT_DATA_ROOT" || true
fi
# (#7204 review) MOUNTEDNESS IS NOT IDENTITY: `mountpoint -q` is satisfied by ANY device. Compared
# by EQUALITY, never prefix or glob, and by --mountpoint (the mount AT the root, not the one
# containing it). This is the single serving assertion; the post-bootstrap duplicate is gone.
_served_src="$(findmnt -n -o SOURCE --mountpoint "$GIT_DATA_ROOT" 2>/dev/null || true)"
if [ "$_served_src" != "$STORE_DEVICE" ]; then
  log "FATAL: $GIT_DATA_ROOT is served by '${_served_src:-nothing}', expected '$STORE_DEVICE' — refusing to continue on a non-LUKS device"
  exit 1
fi

# 2. git + flock (util-linux), and the git account's LOGIN SHELL (not git-shell — see the
#    assertion below). cloud-init `packages:` installs git;
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
# 3. The dedicated `git` transport user (created by cloud-init `users:`). (#8043 F7) THE
#    ACCOUNT MUST NOT OWN ITS OWN AUTHORIZATION MAP, nor the directory holding it, nor the
#    home that directory sits in — owning any one of the three lets `git` rewrite the map
#    (in place, or by replacing .ssh, or by replacing the home). This block is the LAST
#    WRITER of those paths: it runs in runcmd, AFTER write_files declared `owner:` on the
#    map, so what it sets is what boots. It used to `chown -R git:git .ssh`, which reverted
#    cloud-init's declaration on every boot (learning 2026-03-20: a recursive chown placed
#    after a targeted one silently reverts it, and cloud-init exits 0). There is NO correct
#    position for a `-R` over .ssh once the map is root-owned, so it is deleted, not moved.
#    Three targeted, non-recursive calls, ordered home -> .ssh -> file. Modes are chosen so
#    the account can still WORK: sshd chdir()s into the home for the forced command and
#    traverses .ssh to read the map, so both are `root:git 0750` (`root:root 0750` would be
#    untraversable — the trap step 4 avoids for $HOOKS_DIR). The map itself is `root:root
#    0644`, NOT 0600: sshd opens it under the target user's uid (measured in the pinned
#    ubuntu-24.04 image — 0600 is "Permission denied" and every push is refused).
id "$GIT_USER" >/dev/null 2>&1 || {
  log "FATAL: $GIT_USER user absent (cloud-init users: stage did not run)"
  exit 1
}
# (#8043) THE TRANSPORT USER'S LOGIN SHELL MUST BE A REAL SHELL. sshd runs a forced
# `command=` as `<login shell> -c "<command>"`; git-shell refuses anything but its four
# built-ins (measured in the pinned image: rc=128 "fatal: unrecognized command"), so a
# git-shell login would kill transport, provision and the Art. 17 erasure alike. The
# confinement is the forced-command map, not the shell. Read the shell back from the
# account rather than trusting the template's declaration. AFTER the `id` guard above: under
# `set -eo pipefail` a `getent` on an absent account fails the pipeline and exits here with
# no message, hiding the named "user absent" FATAL written for exactly that case.
_git_shell="$(getent passwd "$GIT_USER" | cut -d: -f7)"
case "$_git_shell" in
  /bin/sh|/bin/bash|/usr/bin/sh|/usr/bin/bash) : ;;
  *)
    log "FATAL: $GIT_USER login shell is '$_git_shell' — must be a real shell, or every forced command dies at '<shell> -c'"
    exit 1 ;;
esac

mkdir -p "$GIT_HOME/.ssh"
chown "root:$GIT_USER" "$GIT_HOME"
chmod 0750 "$GIT_HOME"
chown "root:$GIT_USER" "$GIT_HOME/.ssh"
chmod 0750 "$GIT_HOME/.ssh"
if [[ -f "$GIT_HOME/.ssh/authorized_keys" ]]; then
  chown root:root "$GIT_HOME/.ssh/authorized_keys"
  chmod 0644 "$GIT_HOME/.ssh/authorized_keys"
fi

# 4. Bare-repo root + hooks dir on the volume. chown immediately after mkdir (the
#    five-bug-cascade learning, inngest-redis-bootstrap). (#8043 F9) TWO OWNERS, NOT ONE:
#    $REPO_ROOT stays git-owned (git-data-provision.sh inits repos there as `git`), but
#    $HOOKS_DIR is `root:git 0750` — not writable by the account whose pushes the hook in it
#    fences, still traversable because `git` runs receive-pack, which execs the hook.
mkdir -p "$REPO_ROOT" "$HOOKS_DIR"
chown "$GIT_USER:$GIT_USER" "$REPO_ROOT"
chmod 0750 "$REPO_ROOT"
chown "root:$GIT_USER" "$HOOKS_DIR"
chmod 0750 "$HOOKS_DIR"

# 4b. Repo-root reconcile (ADR-068 amendment 2026-07-01 "PR B bare-repo
#     provisioning"). The TRANSPORT forced command resolves push URL paths relative to
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
#    so a push is rejected until the real fence hook lands by host replace (see header).
#    Re-runnable: skip the staged install only when the hook is already in place.
#    (#8043 F9) ROOT-OWNED, not git-owned. A root-owned $HOOKS_DIR alone does not close the
#    property: truncating an existing file needs write permission on the FILE, so a git-owned
#    0755 pre-receive inside a root-owned directory is still a fence the fenced account can
#    overwrite. `git` needs only x (other) to exec it from receive-pack.
#    The staged copy must be ROOT'S: /tmp is sticky and world-writable, so on any re-run after
#    /tmp was cleared a git-uid file at this path would be installed root:root 0755 as the
#    fence. cloud-init writes it root-owned at first boot; anything else is refused.
if [[ -f "$PLACEHOLDER_STAGED" ]]; then
  assert_not_symlink "$PLACEHOLDER_STAGED"
  [[ "$(stat -c %U "$PLACEHOLDER_STAGED")" == root ]] || {
    log "FATAL: staged placeholder $PLACEHOLDER_STAGED is owned by $(stat -c %U "$PLACEHOLDER_STAGED"), not root — refusing to install it as the fence"
    exit 1
  }
  install -o root -g root -m 0755 "$PLACEHOLDER_STAGED" "$PRE_RECEIVE"
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
# (#8043 review) THIS LINE ALONE IS NOT ENOUGH on the pinned image: the trailing `/*` form
# needs git >= 2.46 and ubuntu-24.04 ships 2.43.0, where it matches nothing (measured, rc 128
# per repo). git-data-gc.sh therefore passes `-c safe.directory="$repo"` per command; this
# system value is kept as the documented intent and becomes effective on a newer git.
git config --system safe.directory "$REPO_ROOT/*"

# 7. Liveness assert — fail LOUD if any invariant is unmet (the post-merge
#    readiness/cutover gate surfaces it; never leave a half-provisioned host
#    silently "green" — hr-fresh-host-provisioning-reachable-from-terraform-apply).
[[ -x "$PRE_RECEIVE" ]] || {
  log "FATAL: pre-receive hook missing/not executable"
  exit 1
}
# (#8043 F7/F9) OWNERSHIP IS READ BACK, NOT ASSUMED. Each path is compared as a literal
# `user:group mode` so this proves the ABSENCE of the reverted state (a later recursive
# chown, a re-added `-o git` install), not merely that a chown line exists above.
# The table IS the contract: one row per path, `path expected-owner expected-mode why`.
# The model these literals were chosen against (git is in group git and no other; a path is
# traversable iff owner-x/group-x/other-x reaches git, writable iff the same with w) only
# holds if the group membership holds, so that is asserted first.
_own() { stat -c '%U:%G %a' "$1"; }
[[ "$(id -Gn "$GIT_USER")" == "$GIT_USER" ]] || {
  log "FATAL: $GIT_USER is in groups '$(id -Gn "$GIT_USER")', expected only '$GIT_USER' — a supplementary group makes the root:git 0750 model wrong"
  exit 1
}
while read -r _p _o _m _why; do
  [[ "$(_own "$_p" 2>/dev/null || echo absent)" == "$_o $_m" ]] || {
    log "FATAL: $_p is $(_own "$_p" 2>/dev/null || echo absent), expected $_o $_m ($_why)"
    exit 1
  }
done <<EOF
$GIT_HOME root:$GIT_USER 750 git could replace .ssh, or sshd cannot chdir
$GIT_HOME/.ssh root:$GIT_USER 750 git could create authorized_keys2, or sshd cannot traverse
$GIT_HOME/.ssh/authorized_keys root:root 644 git could rewrite the map, or sshd cannot read it
$HOOKS_DIR root:$GIT_USER 750 git could write the hook dir, or cannot traverse it
$PRE_RECEIVE root:root 755 git could overwrite the fence it is fenced by
EOF
[[ "$(git config --system core.hooksPath)" == "$HOOKS_DIR" ]] || {
  log "FATAL: core.hooksPath not set to $HOOKS_DIR"
  exit 1
}
[[ "$(git config --system receive.advertisePushOptions)" == "true" ]] || {
  # MEASURED-BY: the `git config --system receive.advertisePushOptions` read in this test's
  # own condition. The appendix states the CONSEQUENCE that follows from that measured fact,
  # not a hypothesis about why it holds.
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
log "bootstrap substrate ready: LUKS store served at $GIT_DATA_ROOT, git+flock present, bare-repo root $REPO_ROOT, repositories symlink reconciled, provision wrapper present, fail-closed placeholder hook active, push-options advertised"

# 7b. STORE VERIFICATION (#8211, ADR-239; Guard 2). The store scripts refuse until the marker
# written below exists and names this mapper's filesystem UUID (contract C1/C2), so NO store action
# is possible until every step here has passed — the wrappers and authorized_keys land in
# write_files, before runcmd, and a Delete Account arriving mid-bootstrap is refused, never
# reported `erased`. Each step passes or ends in a named `log "FATAL: …"` (stage=bootstrap).
# The sentinel lines delimit ONE unit that git-data-bootstrap-store-verify.test.sh extracts and
# drives without root; keep every step-2..5 line between them.
# ---- BEGIN store-verify unit ----
_plaintext_volume=absent _plaintext_empty=no _served_repos=unknown _fence_on_mapper=no _erasure_probe=no
# A re-run must not inherit a marker a previous run wrote: the marker means "THIS run passed".
rm -f "$STORE_VERIFIED"
# Every entry under <root>/repositories — not only *.git (a partial `x/` is still user data) —
# except the provision/remove lock dotfiles and lost+found. Fails (pipefail) if find cannot read.
_repo_count() {
  [ -d "$1/repositories" ] || { echo 0; return 0; }
  find "$1/repositories" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name lost+found -printf x | wc -c
}
# 2. THE PLAINTEXT VOLUME HOLDS NO REPOSITORY. Only when a plaintext volume id was rendered.
#    Mounted read-only and briefly: `noload` because plain `ro` on ext4 can still replay the
#    journal; under a private `mktemp -d` parent (0700) so the volume's own root mode never
#    exposes it; nosuid/nodev/noexec because nothing on it may run. The SOURCE is verified, not
#    only the count: a failed or no-op mount leaves an empty directory that counts as 0.
#    A dirty journal means the on-disk tree is not the whole truth, so nothing is counted.
#    The data is safe on every FATAL: the volume is retained and was never written.
_pt_id="${GIT_DATA_PLAINTEXT_VOLUME_ID:-}"
if [ -n "$_pt_id" ]; then
  _plaintext_volume=present
  [[ "$_pt_id" =~ ^[0-9]+$ ]] || { log "FATAL: plaintext_unverified reason=source — volume id '$_pt_id' is not numeric"; exit 1; }
  _pt_dev="${GIT_DATA_PLAINTEXT_DEV:-/dev/disk/by-id/scsi-0HC_Volume_$_pt_id}"
  _pt_dir="$(mktemp -d)"
  _pt_mnt="$_pt_dir/mnt"
  _pt_mounted=0
  mkdir "$_pt_mnt"
  _pt_release() {
    if [ "$_pt_mounted" = 1 ]; then
      _pt_mounted=0
      umount "$_pt_mnt" || { log "FATAL: plaintext_unverified reason=umount — $_pt_dev is still mounted read-only at $_pt_mnt"; exit 1; }
    fi
    rmdir "$_pt_mnt" "$_pt_dir" 2>/dev/null || true
  }
  trap _pt_release EXIT
  mount -o ro,noload,nosuid,nodev,noexec "$_pt_dev" "$_pt_mnt" || { log "FATAL: plaintext_unverified reason=mount — could not mount $_pt_dev read-only"; exit 1; }
  _pt_mounted=1
  _pt_src="$(findmnt -n -o SOURCE --mountpoint "$_pt_mnt" 2>/dev/null || true)"
  _pt_got="$(realpath -e "$_pt_src" 2>/dev/null || true)"
  _pt_want="$(realpath -e "$_pt_dev" 2>/dev/null || true)"
  if [ -z "$_pt_got" ] || [ "$_pt_got" != "$_pt_want" ]; then
    log "FATAL: plaintext_unverified reason=source — $_pt_mnt is served by '${_pt_src:-nothing}', not $_pt_dev"
    exit 1
  fi
  _pt_sb="$(dumpe2fs -h "$_pt_dev" 2>/dev/null)" || { log "FATAL: plaintext_unverified reason=journal — dumpe2fs could not read the $_pt_dev superblock"; exit 1; }
  if printf '%s\n' "$_pt_sb" | awk '/^Filesystem features:/ && / needs_recovery( |$)/{f=1} END{exit !f}'; then
    log "FATAL: plaintext_unverified reason=journal — $_pt_dev has needs_recovery set; its tree was not counted"
    exit 1
  fi
  _pt_n="$(_repo_count "$_pt_mnt")" || { log "FATAL: plaintext_unverified reason=mount — $_pt_dev repositories/ is unreadable"; exit 1; }
  _pt_release
  trap - EXIT
  [ "$_pt_n" -eq 0 ] || { log "FATAL: plaintext_residue count=$_pt_n — the plaintext volume still holds repositories/ entries"; exit 1; }
fi
_plaintext_empty=yes
# 3. THE SERVED STORE HOLDS NOTHING UNKNOWN (luks_residue). Counted with the same exclusions,
#    BEFORE the probe writes its lock dotfile. Unknown content on an adopted volume blocks the
#    host rather than being served.
_served_repos="$(_repo_count "$GIT_DATA_ROOT")" || _served_repos=unreadable
[ "$_served_repos" = 0 ] || { log "FATAL: luks_residue count=$_served_repos — $REPO_ROOT on the served store is not empty"; exit 1; }
# 4. THE FENCE SITS ON THE MAPPER. The hook was installed at step 5 above; -T resolves the mount
#    that CONTAINS it, so a hook on the root disk (an unmounted store) reads as not-the-mapper.
_fence_src="$(findmnt -n -o SOURCE -T "$PRE_RECEIVE" 2>/dev/null || true)"
[ "$_fence_src" = "$STORE_DEVICE" ] || { log "FATAL: fence_on_mapper=no — $PRE_RECEIVE is on '${_fence_src:-nothing}', not $STORE_DEVICE"; exit 1; }
_fence_on_mapper=yes
# 5a. THE MARKER — the ONLY writer. One line: the mapper's filesystem UUID, so a mapper reopened
#     on a different volume refuses. Atomic (same-directory temp + mv), 0644, root-owned because
#     root creates it. In /etc: it survives a reboot, and nothing mounts the plaintext volume
#     after boot, so the verification stays true.
_store_uuid="$(findmnt -n -o UUID --mountpoint "$GIT_DATA_ROOT" 2>/dev/null || true)"
[ -n "$_store_uuid" ] || { log "FATAL: store marker not written — $GIT_DATA_ROOT reports no filesystem UUID"; exit 1; }
install -d -m0755 -o root -g root "$(dirname "$STORE_VERIFIED")"
_marker_tmp="$(mktemp "$STORE_VERIFIED.XXXXXX")"
printf '%s\n' "$_store_uuid" > "$_marker_tmp"
chmod 0644 "$_marker_tmp"
mv -f "$_marker_tmp" "$STORE_VERIFIED"
# 5b. THE ERASURE PROBE — a real no-op erasure through the real wrapper, as `git`, which needs
#     the marker. `env -i` comes BEFORE runuser: `runuser -u` without -l keeps its caller's env,
#     so `runuser … env -i` would briefly run a git-uid process holding GIT_DATA_LUKS_KEY in
#     /proc/<pid>/environ. runuser by absolute path: env -i's PATH does not include /usr/sbin.
#     boot-probe-0 passes the id validation; its 0-byte lock dotfile is invisible to gc (*.git
#     only) and to every count above. A failure REMOVES the marker before the FATAL.
_probe_rc=0
_probe_err="$(env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 /usr/sbin/runuser -u git -- "${GIT_DATA_REMOVE_BIN:-/usr/local/bin/git-data-remove.sh}" 2>&1 >/dev/null)" || _probe_rc=$?
if [ "$_probe_rc" -ne 0 ] || [[ "$_probe_err" != *"not present (no-op)"* ]]; then
  rm -f "$STORE_VERIFIED"
  log "FATAL: erasure_probe=no rc=$_probe_rc — a no-op erasure as git did not succeed: ${_probe_err:-no stderr}"
  exit 1
fi
_erasure_probe=yes
# ---- END store-verify unit ----

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
# WORDING PINNED (AC30): `luks_mounted` is about the DEVICE: $GIT_DATA_ROOT is served by the
# mapper (§1). Since #8211 REPO_ROOT is on that device; the booleans from 7b (fence_on_mapper,
# erasure_probe, plaintext_empty) are what attest the rest, and each is reached only on pass.
# Values are exactly yes/no: the readers grep `"<field>":"yes"`, so a third value would pass
# unchecked. df% is GIT_DATA_ROOT (the volume that fills). No repo paths, no UUIDs: booleans,
# present/absent and integers carry no identifier by construction.
# ipcent too: inodes exhaust ahead of bytes (see 6c), so bytes-only reads healthy to ENOSPC.
# `|| true` because read returns 1 on an empty df and this script is `set -e`.
read -r _disk_pct _inode_pct < <(df --output=pcent,ipcent "$GIT_DATA_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9 \n') || true
# (#7772 item 2) The fifth boolean, and unlike its four siblings it is MEASURED rather than
# `yes` by construction. It reads the live ruleset, so it covers the one case the runcmd's
# warning-on-arm-failure structurally cannot: the ruleset DISAPPEARING after a successful load.
# That is not hypothetical here — installing `nftables` also installs nftables.service, whose
# ExecStop runs `nft flush ruleset`, and /etc/nftables.conf whose third line is `flush ruleset`.
# It ships disabled and we never enable it, but RemainAfterExit=yes means systemd would keep
# reporting our oneshot "active" over an emptied ruleset indefinitely, and git-data never
# reboots to re-assert (ADR-115 bars it from the reboot primitive). Without this boolean the
# control's only signal is the ABSENCE of a warning, which notifies nobody.
# Anchored on the daddr, not the table name: a table that exists with its rule flushed is
# exactly the state being tested for, and a name-only grep would report it healthy.
_nft_drop=no
if command -v nft >/dev/null 2>&1 &&
   nft list chain inet soleur_git_data output 2>/dev/null | grep -q '169\.254\.169\.254'; then
  _nft_drop=yes
fi
# (#8210) The sixth boolean (the fifth TERMINAL one), MEASURED like nft_metadata_drop and — unlike it — TERMINAL for
# the rung-2 capture and the boot-signal poll: the runcmd arm item ran `enable --now --no-block`
# before this script, so at birth the reopen unit must be enabled AND have CONVERGED to
# active(exited) — the only terminal-success state a Type=oneshot RemainAfterExit=yes unit has.
#
# WHY ActiveState=active AND NOT Result=success. An earlier revision read `Result`, and its own
# comment claimed "a genuinely wedged unit still reports no". MEASURED on systemd 261 (review):
# Result is RESET to `success` the moment a retry attempt STARTS —
#   activating auto-restart exit-code NRestarts=0
#   activating start        success   NRestarts=1   <- attempt 2 running, Result already "success"
# — so a first attempt that hung on Doppler (killed at TimeoutStartSec=300, retried at ~360 s)
# read `yes` at the 420 s mark on a unit that could still fail terminally twenty minutes later,
# and a never-started oneshot reads `inactive success` too. ActiveState=active is reached only
# when an attempt EXITED 0 (RemainAfterExit then holds it there); `activating` covers the whole
# ladder under RestartMode=direct; `failed` is terminal failure. `is-enabled` alone would pass
# a unit armed for next boot that died today.
#
# WAIT FOR A TERMINAL STATE FIRST, and this is the difference between a measurement and a
# coin flip: sampling the instant the arm item returns reads a TRANSIENT state, not the unit's
# verdict, and this boolean is TERMINAL — a `no` makes the boot-signal poll tell the operator
# to treat the birth or replace as FAILED, whose remediation is another destroy/recreate of the
# host holding every user's source. So a 30-second Doppler or DNS blip at birth must not order
# a destructive remediation of a healthy host.
#
# THE BOUND IS DELIBERATELY BELOW THE LADDER. 420 s = one full attempt (300) + one RestartSec
# (60) + margin; the unit's worst case is 5x300 + 4x60 = 1740 s, and waiting that long here
# would blow the ~610 s birth poll on the apply side. So the boolean is FAIL-CLOSED WITH A
# BOUNDED FALSE-NEGATIVE WINDOW: a ladder still running at 420 s reads `no`. The runbook's
# instruction for `luks_reopen_unit=no` is therefore a Sentry read (a luks_reopen fatal, or a
# LATER luks_reopen_ok row in the same boot) BEFORE any replace — never a replace first.
_reopen_unit=no
_reopen_wait=0
while [ "$(systemctl show -p ActiveState --value git-data-luks-reopen.service 2>/dev/null)" = activating ] \
      && [ "$_reopen_wait" -lt 420 ]; do
  sleep 5
  _reopen_wait=$((_reopen_wait + 5))
done
if systemctl is-enabled --quiet git-data-luks-reopen.service 2>/dev/null &&
   [ "$(systemctl show -p ActiveState --value git-data-luks-reopen.service 2>/dev/null)" = active ]; then
  _reopen_unit=yes
fi
if [[ -x "$GIT_DATA_EMIT" ]]; then
  "$GIT_DATA_EMIT" "git-data bootstrap complete" boot_complete info "" \
    "luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" \
    "nft_metadata_drop=${_nft_drop}" "luks_reopen_unit=${_reopen_unit}" \
    "fence_on_mapper=${_fence_on_mapper}" "erasure_probe=${_erasure_probe}" \
    "plaintext_empty=${_plaintext_empty}" "plaintext_volume=${_plaintext_volume}" \
    "served_repos=${_served_repos}" \
    "disk_pct=${_disk_pct:-unknown}" "inode_pct=${_inode_pct:-unknown}" || true
fi
