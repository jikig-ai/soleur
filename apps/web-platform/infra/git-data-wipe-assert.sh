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
#                           With WIPE_LISTING=run it also takes the layout-independent listing below, and the pre line
#                           ends in `lock_residue=<n|na> store_root_repos=<n>` (counts only; store_root_repos counts the
#                           entries of the LUKS store's repositories/ directory and refuses rc 42 if it cannot be read).
#   WIPE_PHASE=clear        (A1) Remove a LEFTOVER throwaway snapshot a killed listing left behind, after proving it has the
#                           shape the listing makes (rc 43 and nothing removed otherwise). No volume operation.
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
# directories (`lost+found` also EMPTY), `.gc-cursor` and the lock dotfiles must be regular files (under
# repositories/ the lock-name exclusion applies to regular files only). Anything else is off the list.
#
# NO NAME LEAVES THE HOST. The output is one fixed-shape line of per-type COUNTS (no digest, no name,
# no per-name hash, nothing from inside repositories/ but a count). The off-list refusal adds one bit,
# whether a top-level directory is named hooks (the name git-data-bootstrap.sh uses for its hooks
# directory; the bit proves the name only, not who made the directory or what it holds), and two counts,
# and, when that bit is 1, the group below; the compared names are constants in this file, and no listed
# name is printed, hashed or stored.
# When that bit is 1 the line carries ONE further group of four fields, in this order, describing the depth-1
# shape of that directory by TYPE and SIZE metadata at one moment (a printed 0 is "zero at that moment", never
# "unread"):
#   hk_entries    entries directly inside it, dotfiles included (a count, never a name)
#   hk_nonfile    how many of them are not regular files, from the same walk (never above hk_entries)
#   hk_pr_f       1 if an entry named exactly pre-receive (case-sensitive) is a regular file directly inside it,
#                 no link followed; 0 otherwise
#   hk_pr_small   1 if that same file is at most 4096 bytes (WA_HK_PR_MAX; a zero-byte file reads 1, there is no lower
#                 bound); never above hk_pr_f
# The group is absent when the bit is 0: an absent group reads "not measured", and a printed 0 never stands in for
# it. The size comes from inode metadata, the file's content is never opened, and no size, letter or listing name
# is printed. A read that fails or answers off-shape is rc 33 (hooks_shape_failed, hooks_shape_unparseable,
# hooks_pr_failed, hooks_pr_unparseable), never a default 0 and never a partial line.
# Names are read into shell variables for classification only: stdout is held back until the final
# line, stderr of every command is
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
#   43 wipe_snapshot_not_ours (phase=clear only: a leftover snapshot this file did not make)
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
  # Beyond the allowlist arms on the retired volume's snapshot, the hooks directory and the pre-receive file are the two names
  # probed by the hk_ reads, both constants (a third name, a list or a configurable name needs a new ruling): the top-level
  # directory WA_HK_DIR and, as a regular file directly inside it, WA_HK_PR. They are the names git-data-bootstrap.sh uses
  # for its hooks directory and fence hook (a suite row compares them).
  readonly WA_HK_DIR=hooks
  readonly WA_HK_PR=pre-receive
  # WA_HK_PR_MAX is a coarse plausibility bound on the size of that file, not an identity test. It is read off the pre-receive
  # file Terraform delivered to a host: the placeholder file (base64-delivered at first; decoded size 997 bytes unstripped from
  # 2026-07-01, 197 bytes stripped once the comment strip was added, 34654d7ab1, 2026-07-29, until 2026-09-29), then the real
  # script, stripped, 2784 bytes from 2026-09-30 (a96d123938). Only 2784 (the real script) and 197 (the placeholder) were ever
  # rendered to a host. The real script's six source commits strip to 1870 to 2784 bytes. 4096 clears all of these. A size at or
  # under it says nothing about provenance or content (a zero-byte file reads 1; there is no lower bound); a size over it is not
  # evidence of foreign content (an unstripped copy of the real script, raw 6170 to 9325 bytes, reads over it). Which of these
  # renders the retired volume's pre-receive file came from (the era of that file) is not established in the repo. A change of
  # the value returns to the CLO.
  readonly WA_HK_PR_MAX=4096
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
  # awk_hit <input> <awk args...> — a membership gate over a read. awk exits 0 on a hit and 1 on none (the
  # programs below end `exit !f`); any other status means the INSTRUMENT failed, never "no hit": a missing or
  # crashing awk must not read as "not mounted / no snapshot / journal replayed" (rc 16, never a verdict).
  awk_hit() {
    local in="$1" arc=0
    shift
    printf '%s\n' "$in" | awk "$@" || arc=$?
    case "$arc" in 0) return 0 ;; 1) return 1 ;; *) die 16 awk_failed ;; esac
  }
  # wl_same — the by-id link still names the device pinned at resolution (a path is not an identity).
  # byid_present — is the typed volume's by-id link still there? 0 = listed, 1 = ABSENT. "Absent" is only ever
  # a positive reading: the by-id directory listed successfully AND still names the retained LUKS volume's link
  # (so the listing is a real, complete one) AND does not name the typed link. A stat that fails (EACCES, EIO,
  # ELOOP, a missing binary) is not "the link is gone", so nothing here asks stat; any doubt is rc 16.
  byid_present() {
    local names
    names="$(ls -A -- /dev/disk/by-id)" || die 16 byid_dir_unreadable
    case $'\n'"$names"$'\n' in *$'\n'"${BYID_LUKS##*/}"$'\n'*) : ;; *) die 16 byid_listing_incomplete ;; esac
    case $'\n'"$names"$'\n' in *$'\n'"${BYID##*/}"$'\n'*) return 0 ;; esac
    return 1
  }
  wl_same() {
    local mm
    mm="$(devnum_hex "$BYID")" || die 20 device_vanished
    [ "$mm" = "$MM" ] || die 20 device_changed
  }
  # ---- END wipe-core ----

  # --- inputs ------------------------------------------------------------------------------------------
  local PHASE="${WIPE_PHASE-}" TYPED="${WIPE_TYPED_ID-}" LUKSID="${WIPE_LUKS_ID-}" SERVERID="${WIPE_SERVER_ID-}"
  local OLD_ROOT="${WIPE_OLD_ROOT-}" MAPPER="${WIPE_LUKS_MAPPER-}" MARKER="${WIPE_STORE_VERIFIED-}"
  local ROW_DT="${WIPE_ROW_DT-}" LISTING="${WIPE_LISTING-}" w_late
  [[ "$PHASE" =~ ^(pre|finish|post_detach|clear)$ ]] || die 16 arg_phase
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
    local s fu m fz
    s="$(findmnt -n -o SOURCE --mountpoint "$OLD_ROOT")" || die 16 findmnt_source
    [ "$s" = "$MAPPER" ] || die 11 store_not_on_mapper
    # The sentinel is ABSENT only if the store root was read successfully and the name is not in it: `[ ! -e ]`
    # is also true for EACCES / EIO / ELOOP, which would read an unreadable root as "not frozen". find exits
    # non-zero on any such error (rc 16, never a verdict) and exits 0 with no output only for a real absence.
    fz="$(find -H "$OLD_ROOT" -mindepth 1 -maxdepth 1 -name .cutover-freeze -print)" || die 16 freeze_probe
    [ -z "$fz" ] || die 12 cutover_frozen
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
    if awk_hit "$mi" -v d="$(devno_dec "$MM")" '$3 == d { f = 1 } END { exit !f }'; then die 24 in_mountinfo; fi
    rc=0
    hits="$(findmnt -n -S "$DEV")" || rc=$?
    { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } || die 16 findmnt_source_lookup
    [ -z "$hits" ] || die 24 findmnt_source
    hold="$(ls -A -- "$SYS/holders")" || die 25 holders_unreadable
    [ -z "$hold" ] || die 25 holders
    names="$(dmsetup ls)" || die 16 dmsetup_ls
    if awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 26 snapshot_present; fi
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
    boot=$((10#$now - 10#$upi))
    [ "$boot" -le "$ROW_DT" ] || die 32 host_booted_after_row
    delta=$((10#$ROW_DT - boot))
    [ "$delta" -le "$WA_ROW_WINDOW_S" ] || die 32 row_outside_window "boot_to_row_s=$delta"
    BOOT_TO_ROW="$delta"
  }

  # ---- BEGIN wipe-listing unit ----
  # Inputs: DEV MM SYS BYID W0 (set by the identity stages) and the function budget (defined by wa_main, outside this
  # unit; a driver that extracts the unit supplies its own). Outputs: J (dirty|clean), TOP_D TOP_F TOP_L
  # TOP_O REPOS, and for the off-list refusal HAS_HOOKS (0|1), LF_ENTRIES and OFFLIST_N (counts) and HK_TAIL (the
  # hk_ group text, empty unless HAS_HOOKS=1). The
  # loopback suite extracts this unit (and the core above) by their sentinels and drives them on real
  # loop devices.
  wl_has_nr() { awk_hit "$1" '/^Filesystem features:/ && / needs_recovery( |$)/ { f = 1 } END { exit !f }'; }
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
    TOP_D=0 TOP_F=0 TOP_L=0 TOP_O=0 HAS_REPOS=no HAS_LF=no OFFLIST=0 LOCKS_TOP=0 HAS_HOOKS=0 OFFLIST_N=0 LF_ENTRIES=0
    while IFS= read -r -d '' rec; do
      t="${rec%%$'\t'*}"
      n="${rec#*$'\t'}"
      [ "$t" != "$rec" ] || die 35 record_shape
      if [ "$t" = E ]; then saw_end=1; break; fi
      [[ "$t" =~ ^[dflcbpsDU]$ ]] || die 35 record_type
      [ -n "$n" ] || die 35 record_empty
      case "$n" in *[[:cntrl:]]*) die 35 record_control ;; esac
      case "$t" in d) TOP_D=$((TOP_D + 1)) ;; f) TOP_F=$((TOP_F + 1)) ;; l) TOP_L=$((TOP_L + 1)) ;; *) TOP_O=$((TOP_O + 1)) ;; esac
      # One constant name, a directory only, an exact match: the bit is not an allowlist entry, so a
      # directory named hooks still falls into the off-list arm below.
      if [ "$n" = hooks ] && [ "$t" = d ]; then HAS_HOOKS=1; fi
      case "$n:$t" in
        repositories:d) HAS_REPOS=yes ;;
        lost+found:d) HAS_LF=yes ;;
        .*.init.lock:f) LOCKS_TOP=$((LOCKS_TOP + 1)) ;;
        .gc-cursor:f | .init.lock:f) : ;;
        *) OFFLIST=1; OFFLIST_N=$((OFFLIST_N + 1)) ;;
      esac
    done
    [ "$saw_end" = 1 ] || die 33 listing_failed
  }
  wipe_listing() {
    local sb jb bs cow_bytes eh sz deps src got want ssb dm e0 e1 rn ln lk names_after hold_after w_after ro_after
    # HK_PR_F and HK_PR_SMALL are upper-case locals on purpose: the emitted fields are written from exactly these names,
    # a spelling the suite's rows HK7 (the one say line) and HK8 (the closed set, which holds the literal hk_pr_small=$HK_PR_SMALL) pin.
    local ht nf al pr HK_PR_F HK_PR_SMALL
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
    if awk_hit "$ssb" '/^Filesystem state:/ && /with errors/ { f = 1 } END { exit !f }'; then die 33 snapshot_with_errors; fi
    dm="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 33 blkdevname_unreadable
    e0="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e0" = "$eh" ] || die 33 errors_count_changed_by_replay
    # The listing. A find that fails never reads as an empty listing: the terminator record is only
    # printed when find exits 0, and wl_classify refuses a stream without it.
    wl_classify < <(timeout 30 find "$WA_MNT" -mindepth 1 -maxdepth 1 -printf '%y\t%f\0' && printf 'E\tEND\0')
    # Counts under repositories/ — only if it is a real directory (find never follows); the bootstrap's
    # exclusions, narrowed to the TYPE they stand for: a lock is a REGULAR FILE and lost+found an EMPTY
    # DIRECTORY, so a directory, symlink or other entry carrying a lock name (or a lost+found that holds
    # anything) is counted, not excluded. Nothing but the count is kept.
    REPOS=0
    if [ "$HAS_REPOS" = yes ]; then
      rn="$(timeout 30 find "$WA_MNT/repositories" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '.*.init.lock' -o -name '.init.lock' \) \) ! \( -type d -name lost+found -empty \) -printf x | wc -c)" || die 33 repos_count_failed
      [[ "$rn" =~ ^[0-9]+$ ]] || die 33 repos_count_unparseable
      REPOS="$rn"
    fi
    # id-bearing lock residue (A1, 2026-10-15): regular files named .<id>.init.lock at the top level (counted by the
    # classifier) and under repositories/. A COUNT only, never a name; the bare .init.lock carries no id.
    LOCKS="$LOCKS_TOP"
    if [ "$HAS_REPOS" = yes ]; then
      lk="$(timeout 30 find "$WA_MNT/repositories" -mindepth 1 -maxdepth 1 -type f -name '.?*.init.lock' -printf x | wc -c)" || die 33 lock_count_failed
      [[ "$lk" =~ ^[0-9]+$ ]] || die 33 lock_count_unparseable
      LOCKS=$((LOCKS + lk))
    fi
    # The allowlisted top-level lost+found is a directory whose CONTENTS the classifier never opens: it must be
    # empty (any entry inside is off the list; only the count is read, never a name).
    if [ "$HAS_LF" = yes ]; then
      ln="$(timeout 30 find "$WA_MNT/lost+found" -mindepth 1 -maxdepth 1 -printf x | wc -c)" || die 33 lostfound_count_failed
      [[ "$ln" =~ ^[0-9]+$ ]] || die 33 lostfound_count_unparseable
      LF_ENTRIES="$ln"   # keep after the digit check above: only a validated count is ever printed
      [ "$ln" -eq 0 ] || OFFLIST=1
    fi
    # The shape of a top-level hooks DIRECTORY (HAS_HOOKS=1 implies OFFLIST=1: no allowlist arm names it), read here, before
    # the errors_count re-read below, so a filesystem error these reads induce is caught by it. TYPE and SIZE metadata only:
    # one find prints a type letter per depth-1 entry (nothing else, no name), one find prints a fixed letter for the file
    # named WA_HK_PR when it is a regular file (s: at most WA_HK_PR_MAX bytes, b: larger). No link is followed, the path has
    # no trailing slash, and the file is never opened. The count is the string length (linear; bash pattern substitution on
    # a long string is quadratic). Every failure or off-shape answer is rc 33 with a fixed word: never a default 0.
    # ---- BEGIN wipe-hooks reads ----
    HK_TAIL=""
    if [ "$HAS_HOOKS" = 1 ]; then
      budget
      ht="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -printf '%y')" || die 33 hooks_shape_failed
      nf="$(printf '%s' "$ht" | tr -d f | wc -c)" || die 33 hooks_shape_failed
      al="$(printf '%s' "$ht" | tr -d 'dflcbpsDU' | wc -c)" || die 33 hooks_shape_failed
      [[ "$nf" =~ ^[0-9]+$ && "$al" =~ ^[0-9]+$ ]] || die 33 hooks_shape_unparseable
      [ "$((10#$al))" -eq 0 ] || die 33 hooks_shape_unparseable
      pr="$(timeout 30 find "$WA_MNT/$WA_HK_DIR" -mindepth 1 -maxdepth 1 -name "$WA_HK_PR" -type f \( -size -$((WA_HK_PR_MAX + 1))c -printf s -o -printf b \))" || die 33 hooks_pr_failed
      [[ "$pr" =~ ^[sb]?$ ]] || die 33 hooks_pr_unparseable
      HK_PR_F=0
      if [ -n "$pr" ]; then HK_PR_F=1; fi
      HK_PR_SMALL=0
      if [ "$pr" = s ]; then HK_PR_SMALL=1; fi
      HK_TAIL=" hk_entries=${#ht} hk_nonfile=$((10#$nf)) hk_pr_f=$HK_PR_F hk_pr_small=$HK_PR_SMALL"
    fi
    # ---- END wipe-hooks reads ----
    e1="$(wl_errs "$dm")" || die 33 errors_count_unreadable
    [ "$e1" = "$e0" ] || die 33 errors_count_changed_by_listing
    wl_valid
    # Teardown BEFORE any verdict is spoken, then the origin must be as untouched as before.
    wa_release || die 36 teardown_failed
    names_after="$(dmsetup ls)" || die 36 snapshot_ls_failed
    if awk_hit "$names_after" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 36 snapshot_remains; fi
    w_after="$(wstat)" || die 16 stat_unreadable_after
    [ "$w_after" = "$W0" ] || die 29 origin_written_during_listing
    hold_after="$(ls -A -- "$SYS/holders")" || die 25 holders_unreadable_after
    [ -z "$hold_after" ] || die 25 holders_after
    ro_after="$(blockdev --getro "$DEV")" || die 16 getro_failed_after
    [ "$ro_after" = 1 ] || die 30 ro_flag_lost_after
    # Verdicts: off-list beats not-empty (the counts on stderr are digits only; has_hooks_d is a single 0 or 1).
    if [ "$OFFLIST" = 1 ]; then
      say "wipe-assert: rc=34 reason=offlist top_d=$TOP_D top_f=$TOP_F top_l=$TOP_L top_o=$TOP_O repos=$REPOS has_hooks_d=$HAS_HOOKS lf_entries=$LF_ENTRIES offlist_n=$OFFLIST_N$HK_TAIL"
      exit 34
    fi
    [ "$REPOS" -eq 0 ] || die 37 repositories_not_empty "repos=$REPOS"
  }
  # ---- END wipe-listing unit ----

  # store_root_repos (A1, 2026-10-15): a read-only COUNT of the entries under the LUKS store root's repositories/
  # directory, with the bootstrap's exclusions (id-bearing and bare lock files, an EMPTY lost+found). It is an
  # independent barrier for the separated wipe (ADR-239 Amendment 2026-10-15): the runner refuses when it is not
  # 0. The host is not told which variant is running, so no input can steer it. A repositories entry that is not a
  # directory (a symlink or a file) is unreadable, never "empty". Only the integer leaves the host.
  store_root_repos() {
    local rt n
    rt="$(find -H "$OLD_ROOT" -mindepth 1 -maxdepth 1 -name repositories -printf 'T:%y')" || die 42 store_root_unreadable
    case "$rt" in
      "") SRR=0 ;;
      T:d)
        n="$(timeout 30 find -H "$OLD_ROOT/repositories" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '.*.init.lock' -o -name '.init.lock' \) \) ! \( -type d -name lost+found -empty \) -printf x | wc -c)" || die 42 store_root_unreadable
        [[ "$n" =~ ^[0-9]+$ ]] || die 42 store_root_unreadable
        SRR="$n" ;;
      *) die 42 store_root_unreadable ;;
    esac
  }

  # clear_origin_ok — the retained device is untouched and kernel read-only (before AND after a clear).
  clear_origin_ok() {
    local ro
    W0="$(wstat)" || die 16 stat_unreadable
    case "$W0" in "0 0") : ;; *) die 29 sectors_written ;; esac
    ro="$(blockdev --getro "$DEV")" || die 16 getro_unreadable
    case "$ro" in 1) : ;; *) die 30 ro_flag_lost ;; esac
  }
  # clear_snapshot (phase=clear; A1 2026-10-15, CTO follow-up ruling) — remove a LEFTOVER git-data-pt-snap that a run
  # killed with SIGKILL (which no trap can catch) left behind. It touches nothing that does not match the shape this file's
  # own listing makes (a SHAPE proof, not authorship: git-data-bootstrap.sh makes the same name and shape, and only a held
  # handle or a busy device stops a removal there): the
  # snapshot's origin must be the typed device and it must be non-persistent (N); its COW must be a loop device whose
  # backing file lives in a /dev/shm/tmp.<id> directory, and a mount of the snapshot, if any, must be that directory's
  # mnt. Anything else is rc 43 and NOTHING is removed. The removal is wa_release, the one function that also tears
  # down this file's own listing (its single `dmsetup remove` names the pinned constant; no name is an input).
  clear_snapshot() {
    local names tbl tbl2 c d e f h dmn rc try hits tgt mntdir lo lk lf cowdir
    names="$(dmsetup ls)" || die 16 dmsetup_ls
    if ! awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then CLEAR_RESULT=absent; return 0; fi
    tbl="$(dmsetup table "$WA_SNAP")" || die 16 table_unreadable
    case "$tbl" in *$'\n'*) die 43 snapshot_not_ours ;; esac  # one segment only: the first line alone is never trusted for a multi-target table
    read -r _ _ c d e f _ h <<< "$tbl"
    [ "$c" = snapshot ] && [ "$d" = "$(devno_dec "$MM")" ] && [ "$f" = N ] && [ -z "$h" ] || die 43 snapshot_not_ours
    dmn="$(dmsetup info -c --noheadings -o blkdevname "$WA_SNAP")" || die 16 blkdevname_unreadable
    [[ "$dmn" =~ ^dm-[0-9]+$ ]] || die 16 blkdevname_unparseable
    for try in 1 2; do
      rc=0
      hits="$(timeout 20 find /proc -ignore_readdir_race -maxdepth 3 -type l -regex '/proc/[[:digit:]]+/fd/[[:digit:]]+' -lname "/dev/$dmn" -print -quit)" || rc=$?
      [ -z "$hits" ] || die 27 handle_open
      [ "$rc" -eq 0 ] && break
      [ "$try" = 2 ] && die 27 handle_unknown
      sleep 1
    done
    rc=0
    tgt="$(findmnt -n -o TARGET -S "/dev/mapper/$WA_SNAP")" || rc=$?
    { [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; } || die 16 findmnt_snapshot_lookup
    mntdir=""
    if [ -n "$tgt" ]; then
      case "$tgt" in *$'\n'*) die 43 snapshot_not_ours ;; esac
      [[ "$tgt" =~ ^(/dev/shm/tmp\.[A-Za-z0-9]{6,12})/mnt$ ]] || die 43 snapshot_not_ours
      mntdir="${BASH_REMATCH[1]}"
    fi
    lo="$(losetup -l -n -O NAME,BACK-FILE)" || die 16 losetup_list
    # The COW must be a LOOP device: major 7 is the loop driver. The name /dev/loop<minor> below assumes loop.max_part=0 (the
    # kernel default); with partitions the minor differs and every leftover is refused (rc 43, nothing removed), which is safe.
    [[ "$e" =~ ^7:[0-9]+$ ]] || die 43 snapshot_not_ours
    lk="/dev/loop${e#*:}"
    lf="$(printf '%s\n' "$lo" | sed -n "s#^${lk}[[:space:]][[:space:]]*\(.*\)\$#\1#p")"
    case "$lf" in "" | *$'\n'*) die 43 snapshot_not_ours ;; esac
    [[ "$lf" =~ ^(/dev/shm/tmp\.[A-Za-z0-9]{6,12})/cow(\ \(deleted\))?$ ]] || die 43 snapshot_not_ours
    cowdir="${BASH_REMATCH[1]}"
    if [ -n "$mntdir" ] && [ "$mntdir" != "$cowdir" ]; then die 43 snapshot_not_ours; fi
    clear_origin_ok
    # Removal is by name, so re-read the table once more right before it: a snapshot swapped in during the proof is refused.
    tbl2="$(dmsetup table "$WA_SNAP")" || die 16 table_unreadable
    [ "$tbl2" = "$tbl" ] || die 43 snapshot_not_ours
    WA_DIR="$cowdir"; WA_MNT="$cowdir/mnt"; WA_LOOP="$lk"; WA_SNAP_UP=1
    if [ -n "$mntdir" ]; then WA_MOUNTED=1; fi
    if ! wa_release; then die 36 teardown_failed; fi
    names="$(dmsetup ls)" || die 16 dmsetup_ls
    if awk_hit "$names" -v n="$WA_SNAP" '$1 == n { f = 1 } END { exit !f }'; then die 36 snapshot_remains; fi
    clear_origin_ok
    CLEAR_RESULT=cleared
  }

  line_pre() {
    local lsig journal d f l o r k
    if [ "$LISTING" = run ]; then
      lsig=ok journal="$J" d="$TOP_D" f="$TOP_F" l="$TOP_L" o="$TOP_O" r="$REPOS" k="$LOCKS"
    else
      lsig=not_run journal=na d=na f=na l=na o=na r=na k=na
    fi
    printf 'wipe_assert pre ok layout_signal=%s journal=%s top_d=%s top_f=%s top_l=%s top_o=%s repos=%s boot_to_row_s=%s lock_residue=%s store_root_repos=%s\n' \
      "$lsig" "$journal" "$d" "$f" "$l" "$o" "$r" "$BOOT_TO_ROW" "$k" "$SRR" >&4
  }

  phase_post() {
    local t=0
    store_facts
    # The by-id link of the typed id must be GONE (udev drops it a moment after the detach).
    while byid_present; do
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

  if [ "$PHASE" = clear ]; then
    store_facts
    h3_to_h5
    budget
    clear_snapshot
    printf 'wipe_assert clear ok snapshot=%s\n' "$CLEAR_RESULT" >&4
    return 0
  fi
  if [ "$PHASE" != pre ]; then phase_post; return 0; fi
  store_facts
  h3_to_h5
  budget
  h6_to_h7
  budget
  h8
  h9_h10
  budget
  store_root_repos
  budget
  if [ "$LISTING" = run ]; then wipe_listing; fi
  budget
  # Re-pin the identity and the counters once more at the end: nothing changed under the read.
  wl_same
  w_late="$(wstat)" || die 16 stat_unreadable_late
  [ "$w_late" = "$W0" ] || die 29 sectors_written_late
  store_facts
  line_pre
  return 0
}
wa_main
exit $?
