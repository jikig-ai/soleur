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
#   LSOF_OUT / LSOF_OUT_FILE  stub lsof stdout (the header + the g4 read-fd line are ALWAYS emitted
#                             ahead of it, see the stub — the SUT asserts the header shape and drops
#                             row 1 with NR>1)
#   LSOF_ABSENT=1             `command -v lsof` fails AND the install fails (fail-closed probe)
#   LSOF_BLIND=1              lsof runs but never reports the probe fd (a scan that did not reach $MOUNT)
#   FINDMNT_MOUNT_OPTS        `findmnt -no OPTIONS $MOUNT` stdout, read by G4's _assert_mount_rw
#                             (#6733). Default `rw,relatime,errors=remount-ro` — a HEALTHY mount
#                             whose options nonetheless contain the substring "ro", so a case that
#                             passes cannot be passing via a broken substring comparison. Set to
#                             `ro,relatime` for the read-only refusal, or `` (empty, via the `-`
#                             form) for the unreadable-options refusal.
#   LSOF_RC=<n>               force the lsof exit status (rc>1 = an outright probe failure)
#   ACTIVE_UNITS              space-separated units for which `systemctl is-active` succeeds
#   CURL_CODE / READYZ_BODY   stub curl's /health code and /internal/readyz body (single-value,
#                             legacy form; still honoured when the sequenced knobs are unset)
#   CURL_CODES="521 521 200"  SEQUENCED /health codes consumed by call index, saturating on the
#                             LAST value — so "521" alone means a probe that NEVER recovers, while
#                             "521 521 200" recovers on the third attempt (#6807 retry arms).
#   READYZ_BODIES="a b c"     SEQUENCED readyz bodies, same saturation. Space-separated, so a body
#                             may not contain spaces — JSON.stringify output never does.
#   READYZ_CODES="200 503"    SEQUENCED readyz HTTP statuses. OPTIONAL: when unset the status is
#                             DERIVED from the body exactly as readiness.ts derives it (200 iff
#                             ready:true, else 503), so a fixture cannot model a 200+ready:false
#                             response the real server cannot produce. Pin it explicitly only to
#                             reach the gate-regression arm (403/404/405).
#                             All three use the `${X-default}` UNSET form, per the discipline at the
#                             DU_SRC/DF_AVAIL knobs: an EMPTY value must reach the SUT as empty and
#                             exercise its own arm, not be silently substituted into the happy path.
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
#   BLKID_RC=<n>              force `blkid`'s exit status (only 0 and 2 are acceptable to the SUT)
#   BLKID_ABSENT=1            `command -v blkid` fails (blkid not on PATH)
#   CRYPTSETUP_CLOSE_RC=<n>   force `cryptsetup close`'s exit status (rollback EBUSY)
#   READLINK_RC=<n>           force `readlink`'s exit status (the naive _same_dev fails OPEN here)
#   READLINK_EMPTY=1          readlink exits 0 but prints NOTHING (the other fail-open half)
run_case() {
  local script="$1" invocation="$2" require="$3"; shift 3
  CASE_N=$((CASE_N + 1))
  local d="$RUN_SCRATCH/case-$CASE_N"; mkdir -p "$d"
  CALLS="$d/calls"; MARKER_LOG="$d/marker"; STATE="$d/state.d"; MNT="$d/mnt"; STG="$d/staging"
  # $MNT/workspaces is created because the G4 probe READ-OPENS it (#6733) and dies
  # g4_workspaces_unopenable when it is absent — the wrong-device / empty-bind-source state. Cases
  # that want that refusal remove the directory themselves; every other case needs it present, or
  # the gate aborts before reaching whatever the case is actually about.
  mkdir -p "$STATE" "$MNT" "$MNT/workspaces" "$STG"
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
        # NOTE: no apostrophes in this block — it lives inside a single-quoted bash -c body.
        # The rollback path close previously swallowed its failure via `2>/dev/null || true`,
        # remounting plaintext and reporting SUCCESS while leaking the mapper open AND mounted at
        # $STAGING with a full divergent copy. This knob is what makes that EBUSY reproducible.
        if [ "${1:-}" = "close" ]; then return "${CRYPTSETUP_CLOSE_RC:-0}"; fi
        return 0
      }
      findmnt() {
        rec "findmnt $*"
        case "$*" in
          # `findmnt -rno TARGET` (no path operand) lists every mount target. clean_stray uses it
          # to refuse a mount nested BENEATH $STAGING, which rm -rf would otherwise descend
          # through into live data. Default empty = no nested mounts.
          *"-rno TARGET"*|*"TARGET"*) printf "%s" "${FINDMNT_TARGETS:-}" ;;
          # OPTIONS must be matched BEFORE the path arms below, which would otherwise answer an
          # options query with a SOURCE device. G4 asks `findmnt -no OPTIONS "$MOUNT"` to prove the
          # mount is not read-only (_assert_mount_rw, #6733); $MOUNT here is a scratch DIRECTORY and
          # not a real mountpoint, so the real findmnt returns EMPTY and the gate correctly refuses.
          # That refusal is right in production and useless as a fixture default, so the default is
          # a healthy read-write mount and FINDMNT_MOUNT_OPTS overrides it.
          #
          # The default deliberately carries `errors=remount-ro`: it is what the kernel really sets
          # on ext4 (measured on a live host), and it is the exact string a substring test for "ro"
          # trips over. A fixture whose default cannot express that trap would let a broken
          # substring comparison pass every case in both suites.
          *OPTIONS*) printf "%s\n" "${FINDMNT_MOUNT_OPTS-rw,relatime,errors=remount-ro}" ;;
          *"$WORKSPACES_STAGING"*) printf "%s\n" "${FINDMNT_STAGING_SRC:-}" ;;
          *"$WORKSPACES_MOUNT"*)   printf "%s\n" "${FINDMNT_MOUNT_SRC:-}" ;;
        esac
        return 0
      }
      # stat is the DEVICE-IDENTITY seam. clean_stray compares `stat -c %d` on $MOUNT vs $STAGING
      # to refuse deleting from the canonical filesystem. It cannot use the real stat here: the
      # harness creates MNT and STG as siblings under one scratch dir, so they genuinely ARE on
      # the same device and every case would refuse. The knobs default to DIFFERENT ids (the
      # production-normal case: a Hetzner data volume vs the root disk); STAT_DEV_SAME=1 collapses
      # them to exercise the refusal. STAT_RC forces the unreadable-device-id fail-closed arm.
      stat() {
        rec "stat $*"
        [ -n "${STAT_RC:-}" ] && return "$STAT_RC"
        local _sd="${STAT_DEV_STAGING:-2049}" _md="${STAT_DEV_MOUNT:-64513}"
        # STAT_DEV_SAME=1 collapses both to the staging id — the same-filesystem refusal case.
        [ "${STAT_DEV_SAME:-0}" = "1" ] && _md="$_sd"
        case "$*" in
          *"$WORKSPACES_STAGING"*) printf "%s\n" "$_sd" ;;
          *"$WORKSPACES_MOUNT"*)   printf "%s\n" "$_md" ;;
          *) command stat "$@"; return $? ;;
        esac
        return 0
      }
      # A FAILED PROBE IS NOT PROOF OF AN EMPTY DEVICE: the SUT accepts only rc 0 or rc 2
      # ("nothing detected") and refuses to mkfs on any other rc. The default models real blkid —
      # rc 2 when it reports no type — so the empty-fs happy path exercises the rc-2 arm, not a
      # rc-0 fiction. BLKID_RC forces any other rc (4 usage, 8 ambivalent, ENOENT, EIO...).
      blkid()   {
        rec "blkid $*"; printf "%s\n" "${BLKID_FS:-}"
        [ -n "${BLKID_RC:-}" ] && return "$BLKID_RC"
        [ -z "${BLKID_FS:-}" ] && return 2
        return 0
      }
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
      # RM_RC forces the removal to fail WITHOUT removing, making the rm-failure arm reachable.
      # It returns BEFORE `command rm`, so the fixture survives for the assertion.
      # NOTE: no apostrophes in this block — it lives inside a single-quoted bash -c body.
      rm()      { rec "rm $*"; [ -n "${RM_RC:-}" ] && return "$RM_RC"; command rm "$@"; return $?; }
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
      # RECORDING no-op sleep (#6807), modelled on nic-wait-gate.test.sh. It records the ARGUMENT,
      # not merely the call: that gives per-arm attribution AND covers the retry-INTERVAL seam for
      # free (`has "^sleep 3"`), so the interval knob does not need a separate observation channel.
      # A no-op is safe here ONLY because the retry loops are bounded by ATTEMPTS, never by wall
      # clock — a wall-clock deadline under a no-op sleep would spin hot for its whole duration.
      #
      # NOTE: no apostrophes in this block — it lives inside a single-quoted bash -c body.
      # Relationship to the MOCK_SLEEP_NOOP idiom in ci-deploy.test.sh (#6665): NOT a parallel
      # mechanism to be unified. That one is an opt-in gate on a PATH-mock binary, for a suite whose
      # sleeps are real wall clock it wants to skip; this is a shell-function stub inside an
      # already-stubbed subshell, and it RECORDS rather than merely skipping, because the recorded
      # argument is the only observation channel for the retry-interval seam. Unconditional here is
      # correct: this harness has no case that wants a real sleep. If #6665 broadens the
      # MOCK_SLEEP_NOOP gate, the thing to share is the opt-in convention, not this recorder.
      sleep() { rec "sleep $*"; return 0; }
      # _seq_pick <index> <space-separated list> — the MOUNTPOINT_RCS saturation semantics, reused.
      # Saturates on the LAST element, so a single-element list means "always this value"
      # (CURL_CODES="521" => ALWAYS 521, i.e. a never-recovering probe).
      _seq_pick() {
        local i="$1" list="$2"
        # shellcheck disable=SC2206  # deliberate word-splitting: the knob IS a space-separated list
        local -a seq=($list)
        [ "${#seq[@]}" -eq 0 ] && return 1
        [ "$i" -ge "${#seq[@]}" ] && i=$(( ${#seq[@]} - 1 ))
        printf "%s" "${seq[$i]}"
      }
      # SEPARATE INDEX PER ENDPOINT ARM. The single `case "$*"` below serves BOTH /health and
      # *readyz*, so ONE shared counter would let readyz retries advance the /health sequence and
      # silently desynchronise it — a /health assertion could then be satisfied by readyz traffic.
      # The same reasoning is why the sleep recorder records its argument rather than being counted
      # globally: sleeps must be attributed per arm, never summed.
      #
      # FILE-BACKED, not a shell variable. The SUT reads this stub through a command substitution
      # (`code="$(curl …)"`), which runs in a SUBSHELL — so a `CURL_I=$((CURL_I+1))` assignment is
      # discarded the moment curl returns, the index is forever 0, and every sequenced knob silently
      # degrades to "always the FIRST value". That failure is invisible in the happy direction: a
      # recovering sequence just never recovers, and the case looks like a real SUT bug. Keying the
      # counters off $CALLS (already per-case) also resets them per case for free.
      # NOTE: the legacy MOUNTPOINT_I above can stay a plain variable because `mountpoint -q` is
      # invoked DIRECTLY, never in a substitution.
      _seq_next() {
        local f="$CALLS.seq.$1" i=0
        [ -f "$f" ] && i="$(cat "$f")"
        printf "%s" "$((i + 1))" > "$f"
        printf "%s" "$i"
      }
      curl() {
        rec "curl $*"
        local outfile="" wfmt="" prev="" a body code
        for a in "$@"; do
          [ "$prev" = "-o" ] && outfile="$a"
          [ "$prev" = "-w" ] && wfmt="$a"
          prev="$a"
        done
        local i
        case "$*" in
          *readyz*)
            i="$(_seq_next readyz)"
            body="$(_seq_pick "$i" "${READYZ_BODIES-}")" \
              || body="${READYZ_BODY-{\"ready\":true\}}"
            # READYZ_CODES is optional: when a case does not pin a status, DERIVE it the way the
            # real endpoint does (readiness.ts: `res.writeHead(readiness.ready ? 200 : 503)`), so a
            # fixture cannot accidentally model a 200+ready:false response the server never sends.
            if ! code="$(_seq_pick "$i" "${READYZ_CODES-}")"; then
              case "$body" in
                *'"ready":true'*) code=200 ;;
                "")               code=000 ;;
                *)                code=503 ;;
              esac
            fi
            ;;
          *)
            i="$(_seq_next health)"
            body=""
            code="$(_seq_pick "$i" "${CURL_CODES-}")" || code="${CURL_CODE:-200}"
            ;;
        esac
        # Three real call shapes must be emulated, because the SUT uses all three:
        #   -o <file> -w %{http_code}   body to the file, status to stdout   (the /health probe)
        #   -w \n%{http_code}           body, newline, status, all to stdout (the readyz probe)
        #   (neither)                   body to stdout                       (legacy callers)
        if [ -n "$outfile" ]; then
          printf "%s" "$body" > "$outfile"
          printf "%s" "$code"
        elif [ -n "$wfmt" ]; then
          printf "%s\n%s" "$body" "$code"
        else
          case "$*" in
            *readyz*) printf "%s" "$body" ;;
            *)        printf "%s" "$code" ;;
          esac
        fi
        return 0
      }
      die()     { echo "DIE: $*"; exit 1; }
      emit_drift() { echo "EMIT_DRIFT: $1"; }
      lsof()    {
        rec "lsof $*"
        # The HEADER is always emitted: the SUT asserts its shape (`^COMMAND +PID +USER`) and drops
        # row 1 structurally with `NR>1`, so a headerless fixture would both fail the shape assert
        # and shift every holder count by one.
        printf "COMMAND     PID USER FD   TYPE DEVICE SIZE/OFF    NODE NAME\n"
        # Then the script own READ fd on workspaces/ (#6733), unless LSOF_BLIND. A real lsof
        # scanning $MOUNT cannot miss an fd this process holds open there, so the positive control
        # must model it — and it must carry THIS shell PID ($$, the same value the SUT keys its
        # positive control and holder filter on) and the workspaces/ path the SUT requires. A
        # hardcoded PID would make the fixture test itself rather than the gate.
        if [ "${LSOF_BLIND:-}" != "1" ]; then
          printf "bash    %s root 9r   DIR   0,50       40    1 %s\n" "$$" "$WORKSPACES_MOUNT/workspaces"
        fi
        if [ -n "${LSOF_OUT_FILE:-}" ]; then cat "$LSOF_OUT_FILE"; return "${LSOF_RC:-0}"; fi
        [ -n "${LSOF_OUT:-}" ] && printf "%s\n" "$LSOF_OUT"
        return "${LSOF_RC:-0}"
      }
      command() {
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "lsof" ] && [ "${LSOF_ABSENT:-}" = "1" ]; then return 1; fi
        # blkid lives in /usr/sbin, which this script has been bitten by before. An absent blkid
        # must refuse, never fall through to the DESTRUCTIVE mkfs arm.
        if [ "${1:-}" = "-v" ] && [ "${2:-}" = "blkid" ] && [ "${BLKID_ABSENT:-}" = "1" ]; then return 1; fi
        # TOOL_ABSENT=<name> makes exactly one probe binary unresolvable. clean_stray refuses to
        # run at all with a missing instrument, because `mountpoint -q` on an absent binary exits
        # 127 -> the `if` reads false -> the catastrophic-mode refusal silently does not fire.
        if [ "${1:-}" = "-v" ] && [ -n "${TOOL_ABSENT:-}" ] && [ "${2:-}" = "${TOOL_ABSENT}" ]; then return 1; fi
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

# run_monitor_case <luks-monitor.sh path> [env assignments...]        (#6807)
#
# The luks-monitor seam. Unlike run_case (which SOURCES the cutover to obtain functions), this must
# EXECUTE luks-monitor.sh: the behaviour under test — the readiness/inventory block — lives in the
# main body, and the sourced-detection guard deliberately returns before it. So the stubs are real
# executables on a mock PATH, in the shape ci-deploy.test.sh established, rather than shell
# functions.
#
# Sets: MON_RC, MON_OUT, CALLS (argv log), MNT, WSDIR (the workspaces root, pre-created empty).
#
# Knobs (all optional):
#   MON_MOUNT_SRC     findmnt -no SOURCE $MOUNT      (default: the fake mapper path — healthy)
#   MON_MOUNT_OPTS    findmnt -no OPTIONS $MOUNT     (default: rw,relatime,errors=remount-ro —
#                     a HEALTHY mount whose options nonetheless CONTAIN the substring "ro", so a
#                     capacity check that matched "ro" loosely cannot pass this fixture)
#   MON_MOUNTPOINT_RC mountpoint -q rc               (default 0)
#   MON_DEV_TYPE      blkid -s TYPE -o value         (default crypto_LUKS)
#   MON_KEY           doppler WORKSPACES_LUKS_KEY    (default "k"; empty = Doppler unreachable)
#   MON_ESCROW_RC     cryptsetup luksOpen --test-passphrase rc (default 0)
#   MON_UUID          cryptsetup luksUUID            (default a fixed uuid; empty = header unreadable)
#   MON_READYZ_CODE   readyz HTTP status             (default 200)
#   MON_READYZ_BODY   readyz body                    (default ready:true with both checks true)
#   MON_DF_USE        df -P use% column              (default 41%)
# Split into mon_prepare / mon_run so a case can BUILD A FIXTURE (workspace dirs, a seeded baseline)
# between the two. A single call that creates the case dir and immediately executes cannot express
# the inventory cases at all — the fixture has to exist in the same dir the run will read.
# run_monitor_case is the common prepare-then-run shorthand for cases that need no fixture.
run_monitor_case() { local p="$1"; shift; mon_prepare "$p"; mon_run "$@"; }

mon_prepare() {
  local probe="$1"
  MON_PROBE="$probe"
  CASE_N=$((CASE_N + 1))
  local d="$RUN_SCRATCH/mon-$CASE_N"; mkdir -p "$d/bin" "$d/state" "$d/mnt/workspaces"
  MON_DIR="$d"
  CALLS="$d/calls"; MARKER_LOG="$d/marker"; MNT="$d/mnt"; WSDIR="$d/mnt/workspaces"
  STATE="$d/state"
  : > "$CALLS"; : > "$MARKER_LOG"
  # A regular file standing in for the mapper device node: the SUT only ever tests it with `[ -e ]`
  # and passes it to stubbed binaries, so it never needs to be a real block device.
  printf '' > "$d/fake-mapper"

  # Every stub RECORDS to $CALLS and then answers from its knob. `exec` nothing, no PATH recursion:
  # each is a standalone script whose first act is the record, so an assertion can prove a probe
  # both DID and DID NOT happen (the flag-unset case needs the negative).
  cat > "$d/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf 'findmnt %s\n' "$*" >> "$CALLS"
case "$*" in
  *OPTIONS*) printf '%s\n' "${MON_MOUNT_OPTS-rw,relatime,errors=remount-ro}" ;;
  *)         printf '%s\n' "${MON_MOUNT_SRC-$FAKE_MAPPER}" ;;
esac
STUB
  cat > "$d/bin/mountpoint" <<'STUB'
#!/usr/bin/env bash
printf 'mountpoint %s\n' "$*" >> "$CALLS"
exit "${MON_MOUNTPOINT_RC:-0}"
STUB
  cat > "$d/bin/cryptsetup" <<'STUB'
#!/usr/bin/env bash
printf 'cryptsetup %s\n' "$*" >> "$CALLS"
case "$1" in
  status)  printf '  type:    LUKS2\n  device:  %s\n' "${MON_REAL_DEV-$FAKE_MAPPER}" ;;
  luksUUID) printf '%s\n' "${MON_UUID-3f07b655-31ab-48b9-b02d-013c6b08feba}" ;;
  luksOpen) exit "${MON_ESCROW_RC:-0}" ;;
esac
exit 0
STUB
  cat > "$d/bin/blkid" <<'STUB'
#!/usr/bin/env bash
printf 'blkid %s\n' "$*" >> "$CALLS"
case "$*" in
  *UUID*) printf '%s\n' "${MON_UUID-3f07b655-31ab-48b9-b02d-013c6b08feba}" ;;
  *)      printf '%s\n' "${MON_DEV_TYPE-crypto_LUKS}" ;;
esac
STUB
  cat > "$d/bin/doppler" <<'STUB'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$CALLS"
case "$*" in
  *WORKSPACES_LUKS_HEARTBEAT_URL*) printf '%s' "${MON_HB_URL-}" ;;
  *WORKSPACES_LUKS_KEY*)           printf '%s' "${MON_KEY-k}" ;;
esac
STUB
  # Emulates `-o <file> -w %{http_code}`: body to the file, status to stdout — the shape
  # wl_probe_readyz reads. The heartbeat push (no -o) just records and succeeds.
  cat > "$d/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALLS"
outfile=""; wfmt=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && outfile="$a"
  [ "$prev" = "-w" ] && wfmt="$a"
  prev="$a"
done
case "$*" in
  *readyz*)
    body="${MON_READYZ_BODY-{\"ready\":true,\"checks\":{\"workspaces_writable\":true,\"workspaces_populated\":true\}\}}"
    if [ -n "$outfile" ]; then
      printf '%s' "$body" > "$outfile"; printf '%s' "${MON_READYZ_CODE:-200}"
    elif [ -n "$wfmt" ]; then
      printf '%s\n%s' "$body" "${MON_READYZ_CODE:-200}"
    else
      printf '%s' "$body"
    fi ;;
  *) : ;;
esac
exit 0
STUB
  cat > "$d/bin/logger" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MARKER_LOG"
STUB
  cat > "$d/bin/df" <<'STUB'
#!/usr/bin/env bash
printf 'df %s\n' "$*" >> "$CALLS"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/x 100 41 59 %s /mnt\n' "${MON_DF_USE-41%}"
STUB
  chmod +x "$d"/bin/*
}

# mon_run [env assignments...] — execute the prepared probe. Re-runnable against the same fixture,
# so a case can assert on a baseline of 2 and then re-run with a baseline of 8 without rebuilding.
mon_run() {
  local d="$MON_DIR"
  MON_OUT="$(
    env "$@" \
      PATH="$d/bin:$PATH" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG" FAKE_MAPPER="$d/fake-mapper" \
      WORKSPACES_MOUNT="$MNT" WORKSPACES_MAPPER_PATH="$d/fake-mapper" LUKS_MONITOR_TEST_SEAM=1 \
      WORKSPACES_STATE_DIR="$STATE" LUKS_MONITOR_WORKSPACES_DIR="$WSDIR" \
    bash "$MON_PROBE" 2>&1
  )"
  MON_RC=$?
}

monOut()  { [[ "$MON_OUT" == *"$1"* ]]; }
monRan()  { [ "$MON_RC" -eq 0 ]; }

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
