#!/usr/bin/env bash
#
# Shared stubbed-subshell harness for the workspaces-cutover.sh behavioral suites.
#
# WHY THIS FILE EXISTS: `run_case` was born inline in workspaces-luks-freeze.test.sh and lived
# there alone. #6588's staging-target guards (prepare_staging_target / emit_staging_target /
# _same_dev) need the SAME source-the-script-and-stub-the-world subshell plus THREE stub
# capabilities the freeze harness never had (a SEQUENCED `mountpoint`, a `readlink` seam, and a
# per-case `$WORKSPACES_STAGING`). Copying run_case into a second suite would have forked the
# harness — and the fork would silently drift from the rule set documented below, which is exactly
# how this repo previously shipped a harness that violated the very rule it enforces. One
# definition, two consumers: workspaces-luks-freeze.test.sh and workspaces-luks-staging.test.sh.
#
# HARNESS RULE — NEVER pipe into the assertion predicate.
#   `calls | grep -q PAT` under `set -o pipefail` returns 141 when grep matches EARLY and the
#   producer takes SIGPIPE. On a NEGATIVE assertion (`if ! ...`) that fails OPEN: the violation is
#   present and the test reports green. Both suites exist to forbid exactly that shape in the SUT,
#   so committing it in the harness made the vacuity guard itself vacuous. Every predicate below
#   therefore greps a FILE directly, or uses bash `[[ == ]]`. No pipes.
#
# HARNESS RULE — `[^\n]` in a POSIX ERE excludes the BACKSLASH and the LETTER n, not newlines.
#   Use `.*` in any ERE written against $CALLS.
#
# HARNESS RULE — a stub must end in `return $?` (or an explicit rc), never a bare `return 0` after
#   a command whose status the case is trying to observe: a trailing `return 0` swallows the very
#   SIGPIPE/failure the mutation exists to reproduce.
#
# HARNESS RULE — pass large fixtures by FILE (LSOF_OUT_FILE), never through `env`: the argv limit
#   makes the subshell die E2BIG before any precondition runs.
#
# This file is sourced, never executed; it defines functions and two counters and does nothing else.

# --- counters + reporters ----------------------------------------------------
pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

RUN_SCRATCH="$(mktemp -d -t wl-harness.XXXXXXXX)"
CASE_N=0
cleanup_scratch() { rm -rf "$RUN_SCRATCH"; }
trap cleanup_scratch EXIT INT TERM HUP

# harness_blockdev — a REAL block device path on this host, discovered not assumed.
#
# `_same_dev` ends in `[ -b "$b" ]`, and `[` is a shell BUILTIN: it cannot be stubbed. So any case
# that needs _same_dev to return TRUE (the already-cutover refusal, the mapper->device anchor, the
# mount-source positive control) must be handed a path that really is a block device. Nothing is
# ever written to it — mkfs.ext4, mount, blkid, cryptsetup, df and du are all stubbed — it is used
# only as an argument to `[ -b ]` and `readlink -f`.
#
# NOT hardcoded to /dev/loop0: a CI image without the loop module would make every case that
# depends on it fail for a reason unrelated to the code under test. /sys/block is the enumeration.
harness_blockdev() {
  local p n
  for p in /dev/loop0 /dev/sda /dev/vda /dev/nvme0n1 /dev/sr0; do
    [ -b "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  for n in /sys/block/*; do
    p="/dev/$(basename "$n")"
    [ -b "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# harness_blockdev_other <exclude> — a SECOND, DISTINCT real block device.
#
# Needed by the staging mount-source positive control: "mounted, but from the WRONG device" is the
# 2026-07-19 incident itself, and modelling it faithfully needs two paths that are BOTH real block
# devices and NOT each other. Returns non-zero when the host has only one, so the caller can say so
# plainly rather than faking the second operand with a non-block path.
harness_blockdev_other() {
  local ex="${1:-}" p n
  for p in /dev/loop1 /dev/loop2 /dev/loop0 /dev/sdb /dev/sda /dev/vdb /dev/vda /dev/nvme0n1 /dev/sr0; do
    [ -b "$p" ] && [ "$p" != "$ex" ] && { printf '%s\n' "$p"; return 0; }
  done
  for n in /sys/block/*; do
    p="/dev/$(basename "$n")"
    [ -b "$p" ] && [ "$p" != "$ex" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# run_case <script> <invocation> <required-fns> [env assignments...]
#
# <required-fns>: asserted DECLARED before the invocation runs; otherwise the subshell exits 97 with
# HARNESS_UNDEFINED. Without it, a case asserting "exits non-zero" passes vacuously against a script
# where the function does not exist — the subshell fails for the wrong reason.
#
# Sets: CASE_RC, CASE_OUT, CALLS (argv log), MARKER_LOG (logger sink), MNT (the stub $MOUNT),
#       STG (the stub $WORKSPACES_STAGING, pre-created and EMPTY).
#
# Stub knobs:
#   LSOF_OUT / LSOF_OUT_FILE  stub lsof stdout (the g4 probe line is ALWAYS emitted, see the stub)
#   LSOF_ABSENT=1             `command -v lsof` fails AND the install fails (fail-closed probe)
#   LSOF_BLIND=1              lsof runs but never reports the probe fd (a scan that did not reach $MOUNT)
#   LSOF_RC=<n>               force the lsof exit status (rc>1 = an outright probe failure)
#   ACTIVE_UNITS              space-separated units for which `systemctl is-active` succeeds
#   CURL_CODE / READYZ_BODY   stub curl's /health code and /internal/readyz body
#   MOUNTPOINT_RC=<n>         single global rc for every `mountpoint` call (legacy knob)
#   MOUNTPOINT_RCS="1 1 0"    SEQUENCED rcs consumed by call index; saturates on the LAST value.
#                             prepare_staging_target calls `mountpoint -q "$STAGING"` TWICE with
#                             different required answers (the stray probe, then the mount guard),
#                             and the repoint block needs a not-mounted -> mounted TRANSITION. One
#                             global rc cannot express either, which makes half the matrix
#                             unwritable. Takes precedence over MOUNTPOINT_RC when non-empty.
#   MOUNT_RC=<n>              force `mount`'s exit status
#   UMOUNT_RC=<n>             force `umount`'s exit status for every target
#   UMOUNT_FAIL_MATCH=<glob-fragment>  umount returns 1 only when its argv contains this fragment
#                             (paths are per-case temp dirs, so cases match on "/staging" or "/mnt")
#   MKDIR_RC=<n>              force `mkdir`'s exit status (the stub otherwise really creates)
#   FINDMNT_MOUNT_SRC         `findmnt -no SOURCE $MOUNT` stdout   (default: empty)
#   FINDMNT_STAGING_SRC       `findmnt -no SOURCE $STAGING` stdout (default: empty)
#   BLKID_FS                  `blkid -p -s TYPE -o value` stdout   (default: empty = "no filesystem")
#   MKFS_RC=<n>               force `mkfs.ext4`'s exit status
#   CRYPTSETUP_DEV            the `device:` line `cryptsetup status` reports (default: empty)
#   DU_SRC / DF_AVAIL         the capacity-probe byte counts (verbatim, so a case can feed garbage)
#   READLINK_RC=<n>           force `readlink`'s exit status (the naive _same_dev fails OPEN here)
#   READLINK_EMPTY=1          readlink exits 0 but prints NOTHING (the other fail-open half)
run_case() {
  local script="$1" invocation="$2" require="$3"; shift 3
  CASE_N=$((CASE_N + 1))
  local d="$RUN_SCRATCH/case-$CASE_N"; mkdir -p "$d"
  CALLS="$d/calls"; MARKER_LOG="$d/marker"; STATE="$d/state.d"; MNT="$d/mnt"; STG="$d/staging"
  mkdir -p "$STATE" "$MNT" "$STG"
  : > "$CALLS"; : > "$MARKER_LOG"
  CASE_OUT="$(
    env "$@" \
      CUTOVER="$script" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG" \
      WORKSPACES_STATE_DIR="$STATE" WORKSPACES_MOUNT="$MNT" WORKSPACES_STAGING="$STG" \
      INVOCATION="$invocation" REQUIRE_FNS="$require" \
    bash -c '
      source "$CUTOVER"                                   # guard => functions only, no main body
      rec() { printf "%s\n" "$*" >> "$CALLS"; }
      systemctl() {
        rec "systemctl $*"
        if [ "${1:-}" = "is-active" ]; then
          local u="${@: -1}"
          case " ${ACTIVE_UNITS:-} " in *" $u "*) return 0;; *) return 1;; esac
        fi
        if [ "${1:-}" = "show" ]; then printf "%s\n" "${STOP_RESULT:-success}"; fi
        return 0
      }
      docker()  { rec "docker $*"; return 0; }
      mount()   { rec "mount $*"; return "${MOUNT_RC:-0}"; }
      umount()  {
        rec "umount $*"
        if [ -n "${UMOUNT_FAIL_MATCH:-}" ]; then
          case "$*" in *"$UMOUNT_FAIL_MATCH"*) return 1;; esac
        fi
        return "${UMOUNT_RC:-0}"
      }
      # SEQUENCED mountpoint. MOUNTPOINT_I is shell state in THIS subshell, so the index advances
      # across calls within one case and resets with the next run_case (a fresh subshell).
      MOUNTPOINT_I=0
      mountpoint() {
        rec "mountpoint $*"
        if [ -n "${MOUNTPOINT_RCS:-}" ]; then
          # shellcheck disable=SC2206  # deliberate word-splitting: the knob IS a space-separated list
          local -a seq=(${MOUNTPOINT_RCS})
          local i="$MOUNTPOINT_I"
          MOUNTPOINT_I=$((i + 1))
          [ "$i" -ge "${#seq[@]}" ] && i=$(( ${#seq[@]} - 1 ))   # saturate on the last value
          return "${seq[$i]}"
        fi
        return "${MOUNTPOINT_RC:-0}"
      }
      cryptsetup() {
        rec "cryptsetup $*"
        if [ "${1:-}" = "status" ] && [ -n "${CRYPTSETUP_DEV:-}" ]; then
          printf "  type:    LUKS2\n  device:  %s\n" "$CRYPTSETUP_DEV"
        fi
        return 0
      }
      findmnt() {
        rec "findmnt $*"
        case "$*" in
          *"$WORKSPACES_STAGING"*) printf "%s\n" "${FINDMNT_STAGING_SRC:-}" ;;
          *"$WORKSPACES_MOUNT"*)   printf "%s\n" "${FINDMNT_MOUNT_SRC:-}" ;;
        esac
        return 0
      }
      blkid()   { rec "blkid $*"; printf "%s\n" "${BLKID_FS:-}"; return 0; }
      mkfs.ext4() { rec "mkfs.ext4 $*"; return "${MKFS_RC:-0}"; }
      # `du --apparent-size -sb X | cut -f1` and `df --output=avail -B1 X | tail -1 | tr -dc 0-9`:
      # emit the SHAPE each consumer parses so a case can feed non-numeric garbage verbatim.
      # `${X-default}`, NOT `${X:-default}`: a case that feeds an EMPTY probe result (the shape df
      # produces once `tr -dc 0-9` has stripped non-numeric output) must reach the SUT as empty. The
      # `:-` form substitutes the default for empty too, which silently converts that case into the
      # happy path and makes it pass vacuously.
      du()      { rec "du $*"; printf "%s\t%s\n" "${DU_SRC-1024}" "${@: -1}"; return 0; }
      df()      { rec "df $*"; printf "Avail\n%s\n" "${DF_AVAIL-999999999}"; return 0; }
      mkdir()   { rec "mkdir $*"; [ -n "${MKDIR_RC:-}" ] && return "$MKDIR_RC"; command mkdir "$@"; return $?; }
      # rm is a PASSTHROUGH recorder: the stray-guard case asserts "no rm ANYWHERE in the recorded
      # calls" (detect-and-refuse, never delete — the staged copy is user data, AP-009), and other
      # suites rely on rm actually removing their temp files.
      rm()      { rec "rm $*"; command rm "$@"; return $?; }
      cp()      { rec "cp $*"; return 0; }
      rsync()   { rec "rsync $*"; return 0; }
      # readlink is load-bearing for _same_dev: the naive canonicalizer fails OPEN when readlink
      # errors or prints nothing (both substitutions yield "" and "" = "" is TRUE). Default is a
      # real passthrough so _same_dev can be exercised for real against harness_blockdev.
      readlink() {
        [ -n "${READLINK_RC:-}" ] && return "$READLINK_RC"
        [ "${READLINK_EMPTY:-}" = "1" ] && { printf ""; return 0; }
        command readlink "$@"; return $?
      }
      systemd-run() { rec "systemd-run $*"; return 0; }
      logger()  { printf "%s\n" "$*" >> "$MARKER_LOG"; }
      hostname() { echo "test-host"; }
      apt-get() { rec "apt-get $*"; return 1; }
      timeout() { shift; "$@"; }
      curl() {
        rec "curl $*"
        case "$*" in
          *readyz*) printf "%s" "${READYZ_BODY-{\"ready\":true\}}" ;;
          *)        printf "%s" "${CURL_CODE:-200}" ;;
        esac
        return 0
      }
      die()     { echo "DIE: $*"; exit 1; }
      emit_drift() { echo "EMIT_DRIFT: $1"; }
      lsof()    {
        rec "lsof $*"
        # Always report the script own probe fd unless LSOF_BLIND — a real lsof scanning $MOUNT
        # cannot miss an fd this process holds open there, so the positive control must model it.
        if [ "${LSOF_BLIND:-}" != "1" ]; then
          local p
          for p in "$WORKSPACES_MOUNT"/.luks-g4-probe.*; do
            [ -e "$p" ] && printf "COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME\nbash    111 root    9w   REG   0,1        0    1 %s\n" "$p"
          done
        fi
        if [ -n "${LSOF_OUT_FILE:-}" ]; then cat "$LSOF_OUT_FILE"; return "${LSOF_RC:-0}"; fi
        [ -n "${LSOF_OUT:-}" ] && printf "%s\n" "$LSOF_OUT"
        return "${LSOF_RC:-0}"
      }
      command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "lsof" ] && [ "${LSOF_ABSENT:-}" = "1" ]; then return 1; fi
        builtin command "$@"
      }
      for f in ${REQUIRE_FNS:-}; do
        declare -F "$f" >/dev/null || { echo "HARNESS_UNDEFINED:$f"; exit 97; }
      done
      eval "$INVOCATION"
    ' 2>&1
  )"
  CASE_RC=$?
}

# --- predicates: file-direct greps and bash matching ONLY, never a pipe ---
has()     { grep -qE -- "$1" "$CALLS"; }            # a recorded call matches
hasF()    { grep -qF -- "$1" "$CALLS"; }            # literal
nhas()    { ! grep -qE -- "$1" "$CALLS"; }
cnt()     { grep -cE -- "$1" "$CALLS" || true; }
idx()     { grep -nE -- "$1" "$CALLS" | head -1 | cut -d: -f1; }   # value only; rc unused
markerF() { grep -qF -- "$1" "$MARKER_LOG"; }
outF()    { [[ "$CASE_OUT" == *"$1"* ]]; }
undef()   { [[ "$CASE_OUT" == *"HARNESS_UNDEFINED:"* ]]; }
died()    { [ "$CASE_RC" -ne 0 ] && ! undef; }
# ran — positive control: the case completed successfully. Without this a case can assert on the
# calls file (populated before an unrelated die) while the function never actually succeeded.
ran()     { [ "$CASE_RC" -eq 0 ] && ! undef; }
