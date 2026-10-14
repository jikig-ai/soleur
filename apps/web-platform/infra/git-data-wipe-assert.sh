#!/usr/bin/env bash
#
# git-data-wipe-assert.sh — the HOST-SIDE evidence read for the wipe of the retired plaintext volume
# (#10138, ADR-239 amendment 2026-10-09, ADR-241; design-wipe-body-pr.md 3.2, 3.3).
#
# HOW IT RUNS. git-data-cutover.sh MODE=wipe_assert sends this file on STDIN to `bash -s` on the
# git-data host, as root, over the single ssh site (gd_capture), with the inputs as %q-quoted
# VAR=value words in front of `bash -s`. It is NOT file()-bound into the host's user_data (the
# rung-2 evidence hash is unaffected) and it is NOT a test double: the suite drives THIS file, and
# the host-side commands it calls are replaced only by PATH shims.
#
# WHAT IT PROVES, in ONE session so no fact can change between two reads:
#   WIPE_PHASE=pre          H1-H10 of the design. The store is still served by the LUKS mapper and
#                           its marker is bound; the plaintext device (found by its Hetzner by-id
#                           link, for the TYPED volume id) is a block device that is not the mapper's
#                           backing device (checked in BOTH directions against the LUKS volume's id),
#                           not LUKS, not mounted, no holders, no leftover snapshot, no open handle,
#                           quiescent (sectors written/discarded ABSOLUTELY 0 0 and stable over 2 s),
#                           kernel read-only, the host is the instance Hetzner names, and the host
#                           booted before, and within a bounded window of, the boot_complete row.
#                           With WIPE_LISTING=run it also takes the layout-independent listing below.
#   WIPE_PHASE=post_detach  After the Hetzner detach: the store facts again, the by-id link of the
#   WIPE_PHASE=finish       typed id is GONE, an uncached direct-I/O read of the mapper and a listing
#                           of the store root succeed (the store is still served).
#
# THE LAYOUT-INDEPENDENT LISTING (CTO option A; the measured journal of the live volume is dirty, so a
# debugfs read is not trustworthy). The unit below is a PORT of the bootstrap's `plaintext-count unit`
# (git-data-bootstrap.sh, between its BEGIN/END plaintext-count unit sentinels; that file is read, not
# edited): a non-persistent device-mapper `snapshot` stacked on the kernel-read-only device, its
# copy-on-write store a sparse file on /dev/shm (RAM), the SNAPSHOT mounted read-only WITHOUT noload so
# the journal replays into the COW. The retained device is never mounted and never written; afterwards
# its sysfs sector counters must still read 0 0, it must have no holders and the snapshot must be gone.
# What it reads is `find -mindepth 1 -maxdepth 1 -printf '%y\t%f\0'` over the snapshot (no -L, nothing
# dereferenced), against a PATH-TYPED allowlist: `repositories` and `lost+found` must be real
# directories, `.gc-cursor` and the lock dotfiles must be regular files. Anything else is off the list.
#
# NO NAME LEAVES THE HOST. The output is one fixed-shape line of per-type COUNTS (no digest, no name,
# no per-name hash, nothing from inside repositories/ but a count). Names are read into shell variables
# for classification only: stdout is held back until the final line, stderr of every command is
# discarded, and the only stderr this file writes is a fixed reason word and digits (gd_capture prints
# a failed session's stderr, so nothing else may reach it).
#
# EXIT CODES (the session's rc IS the verdict; git-data-cutover.sh maps each to a word). Anything not
# in this table, and every transport rc (124 timeout, 255 ssh), is `probe_failed rc=<n>` there:
#    0  ok: the one line is printed
#   11 store_not_on_mapper        12 cutover_frozen           13 store_unverified no_fs_uuid
#   14 store_unverified marker_absent                         15 store_unverified marker_mismatch
#   16 probe_failed (an input, a read or an instrument failed; never a host verdict)
#   20 wipe_device_absent         21 wipe_device_not_block    22 wipe_device_is_luks_backing
#   23 wipe_device_luks_or_unknown                            24 wipe_device_mounted
#   25 wipe_device_has_holders    26 wipe_snapshot_present    27 wipe_device_open
#   28 wipe_device_active         29 wipe_device_written      30 wipe_ro_flag_lost
#   31 wipe_instance_mismatch     32 wipe_boot_generation_mismatch
#   33 wipe_boot_layout_signal_absent     34 wipe_boot_layout_signal_offlist
#   35 wipe_boot_layout_signal_unparseable                    36 wipe_snapshot_teardown_failed
#   37 wipe_plaintext_not_empty   38 wipe_luks_identity_mismatch
#   40 wipe_device_still_attached 41 wipe_mapper_read_failed  42 wipe_store_root_unreadable
# (git-data-cutover.sh itself refuses wipe_target_is_luks, before any call, when the two ids are equal.)
# Keep the table, the `die` calls below and the case in git-data-cutover.sh equal (the suite derives
# the set from all three).
#
# Inputs (all validated before anything is read): WIPE_PHASE, WIPE_TYPED_ID, WIPE_LUKS_ID,
# WIPE_SERVER_ID, WIPE_OLD_ROOT, WIPE_LUKS_MAPPER, WIPE_STORE_VERIFIED, and for `pre` WIPE_ROW_DT (the
# boot_complete row's dt, epoch seconds) and WIPE_LISTING (run|skip).
#
# Every read of the system goes through an EXTERNAL command (cat, stat, realpath, ls, find, date): the
# suite replaces those by PATH shims, so this file carries no test seam (ADR-214).
#
# WHY ONE FUNCTION. `bash -s` reads its script from stdin as it executes it, and this file redirects
# stdin to /dev/null (so no command can eat the rest of the script). The whole body therefore lives in
# one function that is parsed completely before it runs.
set -uo pipefail
export LC_ALL=C

wa_main() {
  case "$-" in
    *x*) printf 'wipe-assert: refusing to run under xtrace (the listing holds names)\n' >&2; exit 16 ;;
  esac
  # fd 3 = the original stderr, fd 4 = the original stdout; from here on every command's own stdout and
  # stderr are discarded, so nothing read from the volume can reach either stream by accident.
  exec 3>&2 4>&1 1>/dev/null 2>/dev/null </dev/null

  # ---- BEGIN wipe-core ----
  readonly WA_SNAP=git-data-pt-snap
  readonly WA_ROW_WINDOW_S=3600      # max seconds from host boot to the boot_complete row (UNMEASURED: wipe_check prints boot_to_row_s)
  readonly WA_BUDGET_S=240           # self-imposed ceiling; the ssh bound in git-data-cutover.sh is longer
  readonly WA_SETTLE_TRIES=20        # post-detach: wait up to 20 s for udev to drop the by-id link

  say() { printf '%s\n' "$*" >&3; }
  # die <rc> <fixed-reason-word> [key=digits...] — fixed words and digits are the only text this file ever
  # writes to stderr.
  die() { local rc="$1"; shift; say "wipe-assert: rc=$rc reason=$*"; exit "$rc"; }

  # State the EXIT trap releases.
  WA_DIR="" WA_MNT="" WA_LOOP="" WA_SNAP_UP=0 WA_MOUNTED=0
  # Collect-then-continue (never `rm -rf`, never stop at the first failure): every step is attempted.
  wa_release() {
    local first=""
    if [ "$WA_MOUNTED" = 1 ]; then
      if timeout 30 umount "$WA_MNT"; then WA_MOUNTED=0; else first="umount"; fi
    fi
    timeout 20 udevadm settle --timeout=15 || true
    if [ "$WA_SNAP_UP" = 1 ]; then
      if timeout 45 dmsetup remove --retry "$WA_SNAP"; then WA_SNAP_UP=0; else first="${first:-dmsetup}"; fi
    fi
    if [ -n "$WA_LOOP" ]; then
      if timeout 10 losetup -d "$WA_LOOP"; then WA_LOOP=""; else first="${first:-losetup}"; fi
    fi
    if [ "$WA_MOUNTED" != 1 ] && [ -n "$WA_DIR" ]; then
      if rm -f -- "$WA_DIR/cow"; then
        rmdir -- "$WA_MNT" "$WA_DIR" || true
        WA_DIR=""
      else
        first="${first:-cow}"
      fi
    fi
    [ -z "$first" ] || return 1
    return 0
  }
  # A teardown failure outranks every other verdict: a live snapshot of the retained device is the one
  # state this file must never leave unreported.
  wa_exit() {
    local rc=$?
    trap - EXIT
    if [ -n "$WA_DIR$WA_LOOP" ] || [ "$WA_SNAP_UP" = 1 ] || [ "$WA_MOUNTED" = 1 ]; then
      wa_release || { say "wipe-assert: rc=36 reason=teardown_failed"; exit 36; }
    fi
    exit "$rc"
  }
  trap wa_exit EXIT
  trap 'exit 16' HUP INT TERM PIPE

  # devnum_hex <node> — "maj:min" as lowercase hex from stat; fails on anything else.
  devnum_hex() {
    local mm
    mm="$(stat -L -c '%t:%T' -- "$1")" || return 1
    [[ "$mm" =~ ^[0-9a-f]+:[0-9a-f]+$ ]] || return 1
    printf '%s' "$mm"
  }
  # hex "maj:min" -> decimal "maj:min"
  devno_dec() { printf '%s:%s' "$((16#${1%:*}))" "$((16#${1#*:}))"; }
  # wstat — "<sectors written> <sectors discarded>" (sysfs stat fields 7 and 14) of the pinned device.
  wstat() {
    local raw f
    raw="$(cat -- "$SYS/stat")" || return 1
    read -r -a f <<< "$raw"
    [ "${#f[@]}" -ge 14 ] || return 1
    [[ "${f[6]}" =~ ^[0-9]+$ && "${f[13]}" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s' "${f[6]}" "${f[13]}"
  }
  # wl_same — the by-id link still names the device pinned at resolution (a path is not an identity).
  wl_same() {
    local mm
    mm="$(devnum_hex "$BYID")" || die 20 device_vanished
    [ "$mm" = "$MM" ] || die 20 device_changed
  }
  # ---- END wipe-core ----

  # --- inputs ------------------------------------------------------------------------------------------
  local PHASE="${WIPE_PHASE-}" TYPED="${WIPE_TYPED_ID-}" LUKSID="${WIPE_LUKS_ID-}" SERVERID="${WIPE_SERVER_ID-}"
  local OLD_ROOT="${WIPE_OLD_ROOT-}" MAPPER="${WIPE_LUKS_MAPPER-}" MARKER="${WIPE_STORE_VERIFIED-}"
  local ROW_DT="${WIPE_ROW_DT-}" LISTING="${WIPE_LISTING-}"
  [[ "$PHASE" =~ ^(pre|finish|post_detach)$ ]] || die 16 arg_phase
  [[ "$TYPED" =~ ^[0-9]{1,12}$ && "$LUKSID" =~ ^[0-9]{1,12}$ && "$SERVERID" =~ ^[0-9]{1,12}$ ]] || die 16 arg_ids
  [ "$TYPED" != "$LUKSID" ] || die 16 arg_ids_equal
  [[ "$OLD_ROOT" =~ ^/[A-Za-z0-9/_.-]+$ && "$MARKER" =~ ^/[A-Za-z0-9/_.-]+$ && "$MAPPER" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || die 16 arg_paths
  if [ "$PHASE" = pre ]; then
    [[ "$ROW_DT" =~ ^[0-9]{9,11}$ ]] || die 16 arg_row_dt
    [[ "$LISTING" =~ ^(run|skip)$ ]] || die 16 arg_listing
  else
    [ -z "$ROW_DT" ] && [ -z "$LISTING" ] || die 16 arg_pre_only
  fi
  BYID="/dev/disk/by-id/scsi-0HC_Volume_$TYPED"
  local BYID_LUKS="/dev/disk/by-id/scsi-0HC_Volume_$LUKSID"
  local MAPPER_NAME="${MAPPER##*/}"
  local START=$SECONDS
  DEV="" MM="" SYS="" W0="" BOOT_TO_ROW=""
  budget() { [ $((SECONDS - START)) -le "$WA_BUDGET_S" ] || die 16 budget_exceeded; }

  # --- H1/H2: the store is still served by the mapper, not frozen, its marker bound ------------------------
  store_facts() {
    local s fu m
    s="$(findmnt -n -o SOURCE --mountpoint "$OLD_ROOT")" || die 16 findmnt_source
    [ "$s" = "$MAPPER" ] || die 11 store_not_on_mapper
    [ ! -e "$OLD_ROOT/.cutover-freeze" ] || die 12 cutover_frozen
    fu="$(findmnt -n -o UUID --mountpoint "$OLD_ROOT")" || die 16 findmnt_uuid
    [ -n "$fu" ] || die 13 no_fs_uuid
    [ -f "$MARKER" ] && [ -s "$MARKER" ] || die 14 marker_absent
    m="$(head -n 1 -- "$MARKER")" || die 16 marker_read
    [ "$m" = "$fu" ] || die 15 marker_mismatch
  }

  # --- H3-H5: the device, found by its Hetzner by-id link, is neither the mapper's backing nor LUKS ----------
  h3_to_h5() {
    local t st backline back bmm lmm rc
    DEV="$(realpath -e -- "$BYID")" || die 20 byid_unresolved
    [[ "$DEV" =~ ^/dev/[A-Za-z0-9/_.-]+$ ]] || die 20 byid_unresolved
    t="$(stat -L -c %F -- "$DEV")" || die 21 stat_failed
    [ "$t" = "block special file" ] || die 21 not_block
    MM="$(devnum_hex "$DEV")" || die 16 devno_unreadable
    SYS="/sys/dev/block/$(devno_dec "$MM")"
    # H4 — in BOTH directions: the mapper's backing device is not the typed one, and it is the LUKS volume's.
    st="$(cryptsetup status "$MAPPER_NAME")" || die 16 cryptsetup_status
    backline="$(printf '%s\n' "$st" | sed -n 's/^[[:space:]]*device:[[:space:]]*\(\/dev\/[A-Za-z0-9\/_.-]*\)$/\1/p')"
    case "$backline" in "" | *$'\n'*) die 16 backing_unreadable ;; esac
    back="$(realpath -e -- "$backline")" || die 16 backing_unresolved
    bmm="$(devnum_hex "$back")" || die 16 backing_devno
    [ "$bmm" != "$MM" ] || die 22 typed_is_backing
    lmm="$(devnum_hex "$BYID_LUKS")" || die 38 luks_byid_unresolved
    [ "$lmm" = "$bmm" ] || die 38 luks_not_backing
    # H5 — only exit 1 is "not LUKS"; 0 is LUKS, anything else is unknown, never "plaintext".
    rc=0
    cryptsetup isLuks -- "$DEV" || rc=$?
    [ "$rc" -eq 1 ] || die 23 luks_or_unknown
  }

  # --- H6/H7: not mounted, no holders, no leftover snapshot, no open handle -----------------------------------
  h6_to_h7() {
    local mi hits hold names rc try
    mi="$(cat -- /proc/self/mountinfo)" || die 16 mountinfo
    if printf '%s\n' "$mi" | awk -v d="$(devno_dec "$MM")" '$3 == d { f = 1 } END { exit !f }'; then die 24 in_mountinfo; fi
    rc=0
    hits="$(findmnt -n -S "$DEV")" || rc=$?
    { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } || die 16 findmnt_source_lookup
    [ -z "$hits" ] || die 24 findmnt_source
    hold="$(ls -A -- "$SYS/holders")" || die 25 holders_unreadable
    [ -z "$hold" ] || die 25 holders
    names="$(dmsetup ls)" || die 16 dmsetup_ls
    if printf '%s\n' "$names" | awk -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 26 snapshot_present; fi
    # One find over /proc (a fork per descriptor would not finish on a busy host). A vanished process
    # makes find exit non-zero, so a second look decides, and a doubt refuses.
    for try in 1 2; do
      rc=0
      hits="$(timeout 20 find /proc -ignore_readdir_race -maxdepth 3 -type l -regex '/proc/[0-9]+/fd/[0-9]+' -lname "$DEV" -print -quit)" || rc=$?
      [ -z "$hits" ] || die 27 handle_open
      [ "$rc" -eq 0 ] && return 0
      [ "$try" = 2 ] || sleep 1
    done
    die 27 handle_unknown
  }

  # --- H8: quiescent AND untouched since enumeration; kernel read-only -----------------------------------------
  h8() {
    local w1 ro
    W0="$(wstat)" || die 16 stat_unreadable
    sleep 2
    w1="$(wstat)" || die 16 stat_unreadable
    [ "$W0" = "$w1" ] || die 28 counters_moved
    [ "$W0" = "0 0" ] || die 29 sectors_written
    ro="$(blockdev --getro "$DEV")" || die 16 getro_failed
    [ "$ro" = 1 ] || die 30 ro_flag_lost
  }

  # --- H9/H10: the instance Hetzner names, and the boot generation the row belongs to --------------------------
  h9_h10() {
    local iid up upi now boot delta
    iid="$(cat -- /var/lib/cloud/data/instance-id)" || die 16 instance_id_unreadable
    [[ "$iid" =~ ^[0-9]+$ ]] || die 31 instance_id_nonnumeric
    [ "$iid" = "$SERVERID" ] || die 31 instance_id_differs
    up="$(cat -- /proc/uptime)" || die 16 uptime_unreadable
    upi="${up%%.*}"
    [[ "$upi" =~ ^[0-9]+$ ]] || die 16 uptime_unparseable
    now="$(date +%s)" || die 16 date_failed
    [[ "$now" =~ ^[0-9]+$ ]] || die 16 date_unparseable
    boot=$((now - upi))
    [ "$boot" -le "$ROW_DT" ] || die 32 host_booted_after_row
    delta=$((ROW_DT - boot))
    [ "$delta" -le "$WA_ROW_WINDOW_S" ] || die 32 row_outside_window "boot_to_row_s=$delta"
    BOOT_TO_ROW="$delta"
  }

  # ---- BEGIN wipe-listing unit ----
  # Inputs: DEV MM SYS BYID W0 (set by the identity stages). Outputs: J (dirty|clean), TOP_D TOP_F TOP_L
  # TOP_O REPOS. The loopback suite extracts this unit (and the core above) by their sentinels and drives
  # them on real loop devices.
  wl_has_nr() { printf '%s\n' "$1" | awk '/^Filesystem features:/ && / needs_recovery( |$)/ { f = 1 } END { exit !f }'; }
  wl_valid() {
    local st
    st="$(dmsetup status "$WA_SNAP")" || die 33 snapshot_status_unreadable
    case "$st" in *Invalid*) die 33 snapshot_invalid ;; esac
  }
  wl_errs() { local v; v="$(cat -- "/sys/fs/ext4/$1/errors_count")" || return 1; [[ "$v" =~ ^[0-9]+$ ]] || return 1; printf '%s' "$v"; }
  # wl_classify — reads NUL-terminated "<type>\t<name>" records on fd 0, ended by an "E\tEND" record that
  # exists only if find itself exited 0. Names are classified and counted, never stored beyond the loop
  # body and never written anywhere. A name that cannot be classified is "unparseable", not skipped.
  wl_classify() {
    local rec t n saw_end=0
    TOP_D=0 TOP_F=0 TOP_L=0 TOP_O=0 HAS_REPOS=no OFFLIST=0
    while IFS= read -r -d '' rec; do
      t="${rec%%$'\t'*}"
      n="${rec#*$'\t'}"
      [ "$t" != "$rec" ] || die 35 record_shape
      if [ "$t" = E ]; then saw_end=1; break; fi
      [[ "$t" =~ ^[dflcbpsDU]$ ]] || die 35 record_type
      [ -n "$n" ] || die 35 record_empty
      case "$n" in *[[:cntrl:]]*) die 35 record_control ;; esac
      case "$t" in d) TOP_D=$((TOP_D + 1)) ;; f) TOP_F=$((TOP_F + 1)) ;; l) TOP_L=$((TOP_L + 1)) ;; *) TOP_O=$((TOP_O + 1)) ;; esac
      case "$n:$t" in
        repositories:d) HAS_REPOS=yes ;;
        lost+found:d) : ;;
        .gc-cursor:f | .init.lock:f | .*.init.lock:f) : ;;
        *) OFFLIST=1 ;;
      esac
    done
    [ "$saw_end" = 1 ] || die 33 listing_failed
  }
  wipe_listing() {
    local sb jb bs cow_bytes eh sz deps src got want ssb dm e0 e1 rn names_after hold_after
    wl_same
    sb="$(timeout 20 dumpe2fs -h "$DEV")" || die 33 dumpe2fs_failed
    if wl_has_nr "$sb"; then J=dirty; else J=clean; fi
    jb="$(printf '%s\n' "$sb" | sed -n 's/^Total journal blocks:[[:space:]]*\([0-9][0-9]*\)$/\1/p')"
    bs="$(printf '%s\n' "$sb" | sed -n 's/^Block size:[[:space:]]*\([0-9][0-9]*\)$/\1/p')"
    [[ "$jb" =~ ^[1-9][0-9]*$ && "$bs" =~ ^[1-9][0-9]*$ ]] || die 33 geometry_unreadable
    [ "$bs" -ge 4096 ] || bs=4096
    cow_bytes=$((jb * bs + 67108864))
    eh="$(printf '%s\n' "$sb" | sed -n 's/^FS Error count:[[:space:]]*//p')"
    eh="${eh:-0}"
    [[ "$eh" =~ ^[0-9]+$ ]] || die 33 error_count_unreadable
    WA_DIR="$(mktemp -d -p /dev/shm)" || { WA_DIR=""; die 33 mktemp_failed; }
    WA_MNT="$WA_DIR/mnt"
    mkdir -- "$WA_MNT" || die 33 mkdir_failed
    truncate -s "$cow_bytes" -- "$WA_DIR/cow" || die 33 cow_failed
    WA_LOOP="$(losetup --find --show -- "$WA_DIR/cow")" || { WA_LOOP=""; die 33 losetup_failed; }
    sz="$(blockdev --getsz "$DEV")" || die 33 getsz_failed
    [[ "$sz" =~ ^[1-9][0-9]*$ ]] || die 33 getsz_unparseable
    wl_same
    if ! timeout 30 dmsetup create "$WA_SNAP" --table "0 $sz snapshot $DEV $WA_LOOP N 8"; then
      if dmsetup info "$WA_SNAP"; then WA_SNAP_UP=1; fi
      die 33 snapshot_create_failed
    fi
    WA_SNAP_UP=1
    deps="$(dmsetup deps "$WA_SNAP")" || die 33 deps_unreadable
    [[ "$deps" == *" ($((16#${MM%:*})), $((16#${MM#*:})))"* ]] || die 33 snapshot_origin_mismatch
    timeout 45 mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$WA_SNAP" "$WA_MNT" || die 33 snapshot_mount_failed
    WA_MOUNTED=1
    wl_valid
    src="$(findmnt -n -o SOURCE --mountpoint "$WA_MNT")" || die 33 mount_source_unreadable
    got="$(realpath -e -- "$src")" || die 33 mount_source_unresolved
    want="$(realpath -e -- "/dev/mapper/$WA_SNAP")" || die 33 snapshot_node_unresolved
    [ "$got" = "$want" ] || die 33 mount_source_not_snapshot
    ssb="$(timeout 20 dumpe2fs -h "/dev/mapper/$WA_SNAP")" || die 33 snapshot_superblock_unreadable
    if wl_has_nr "$ssb"; then die 33 journal_not_replayed; fi
    if printf '%s\n' "$ssb" | awk '/^Filesystem state:/ && /with errors/ { f = 1 } END { exit !f }'; then die 33 snapshot_with_errors; fi
    dm="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 33 blkdevname_unreadable
    e0="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e0" = "$eh" ] || die 33 errors_count_changed_by_replay
    # The listing. A find that fails never reads as an empty listing: the terminator record is only
    # printed when find exits 0, and wl_classify refuses a stream without it.
    wl_classify < <(timeout 30 find "$WA_MNT" -mindepth 1 -maxdepth 1 -printf '%y\t%f\0' && printf 'E\tEND\0')
    # Counts under repositories/ — only if it is a real directory (find never follows); the bootstrap's
    # exclusions, so a lock dotfile or lost+found is not a repository. Nothing but the count is kept.
    REPOS=0
    if [ "$HAS_REPOS" = yes ]; then
      rn="$(timeout 30 find "$WA_MNT/repositories" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name '.init.lock' ! -name lost+found -printf x | wc -c)" || die 33 repos_count_failed
      [[ "$rn" =~ ^[0-9]+$ ]] || die 33 repos_count_unparseable
      REPOS="$rn"
    fi
    e1="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing
    wl_valid
    # Teardown BEFORE any verdict is spoken, then the origin must be as untouched as before.
    wa_release || die 36 teardown_failed
    names_after="$(dmsetup ls)" || die 36 snapshot_ls_failed
    if printf '%s\n' "$names_after" | awk -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 36 snapshot_remains; fi
    [ "$(wstat)" = "$W0" ] || die 29 origin_written_during_listing
    hold_after="$(ls -A -- "$SYS/holders")" || die 25 holders_unreadable_after
    [ -z "$hold_after" ] || die 25 holders_after
    [ "$(blockdev --getro "$DEV")" = 1 ] || die 30 ro_flag_lost_after
    # Verdicts: off-list beats not-empty (the counts on stderr are digits only).
    if [ "$OFFLIST" = 1 ]; then
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D top_f=$TOP_F top_l=$TOP_L top_o=$TOP_O repos=$REPOS"
      exit 34
    fi
    [ "$REPOS" -eq 0 ] || die 37 repositories_not_empty "repos=$REPOS"
  }
  # ---- END wipe-listing unit ----

  line_pre() {
    local lsig journal d f l o r
    if [ "$LISTING" = run ]; then
      lsig=ok journal="$J" d="$TOP_D" f="$TOP_F" l="$TOP_L" o="$TOP_O" r="$REPOS"
    else
      lsig=not_run journal=na d=na f=na l=na o=na r=na
    fi
    printf 'wipe_assert pre ok layout_signal=%s journal=%s top_d=%s top_f=%s top_l=%s top_o=%s repos=%s boot_to_row_s=%s\n' \
      "$lsig" "$journal" "$d" "$f" "$l" "$o" "$r" "$BOOT_TO_ROW" >&4
  }

  phase_post() {
    local t=0
    store_facts
    # The by-id link of the typed id must be GONE (udev drops it a moment after the detach).
    while stat -- "$BYID"; do
      t=$((t + 1))
      [ "$t" -le "$WA_SETTLE_TRIES" ] || die 40 byid_still_present
      sleep 1
    done
    # An uncached read through the mapper (the page cache cannot answer for the device) and a root listing.
    timeout 30 dd if="$MAPPER" of=/dev/null bs=4096 count=1 iflag=direct || die 41 mapper_read_failed
    ls -A -- "$OLD_ROOT" || die 42 store_root_unreadable
    store_facts
    printf 'wipe_assert %s ok byid=gone mapper_read=ok store_root=ok\n' "$PHASE" >&4
  }

  if [ "$PHASE" != pre ]; then phase_post; return 0; fi
  store_facts
  h3_to_h5
  budget
  h6_to_h7
  budget
  h8
  h9_h10
  budget
  if [ "$LISTING" = run ]; then wipe_listing; fi
  budget
  # Re-pin the identity and the counters once more at the end: nothing changed under the read.
  wl_same
  [ "$(wstat)" = "$W0" ] || die 29 sectors_written_late
  store_facts
  line_pre
  return 0
}
wa_main
exit $?
