#!/usr/bin/env bash
# tmpfs-guard.sh — keeps the shared /tmp tmpfs from filling.
#
# Two reapers, both scoped to files owned by the current user (no sudo):
#
#   1. reap_output_files    — oversized Claude Code task .output files.
#   2. reap_scratch_entries — stale, large, own-uid scratch entries at the top
#                             level of /tmp (added #6789).
#
# WHY (2) EXISTS. /tmp is a 4 GiB tmpfs — Layer 3 of the 2026-03-28 tmpfs guard,
# deliberately capped so a runaway file cannot consume all system memory. The
# cap is correct; what was missing was a reaper for the class of artifact now
# filling it. Measured 2026-07-22: /tmp at 86% with THREE abandoned scratch
# trees holding 3.1 GiB (88% of occupancy), while 4294 small entries held only
# 160 MB (4.5%). Because tmpfs is RAM-backed, that 3.5 GiB was memory withheld
# from a machine with ~6 GiB available and swap exhausted — precisely the
# condition under which concurrent test runs hit the timeout-flake class that
# reads as a false regression (#6726, #4096, #3817).
#
# This script had run every five minutes throughout, warning and cleaning
# nothing outside its .output scope. A guard that only warns is not a guard.
#
# SAFETY (plan R3). Reaping on a SINGLE dimension deletes live work: age alone
# removes a long-running session's scratch dir, size alone removes a small but
# active one. Every candidate must clear ALL of:
#   - ownership : owned by the invoking uid
#   - age       : NOTHING in the tree modified within the age floor
#   - size      : at least the size floor
#   - liveness  : no process cwd inside it, no open file handle
#   - not protected: /tmp/claude-<uid> belongs to worktree-manager.sh's
#     cleanup_claude_tmp, and the session-state root belongs to session-state.sh
#
# Designed to run as a user cron job every 5 minutes.
#
# COUNT-SHAPED LEAKS (#6991). The size floor above cannot see the failure mode
# that actually occurred on 2026-07-27: ~15,000 files of a few hundred bytes
# each. The largest leaked artifact was 372 bytes and 0 of 11,172 `tmp.*`
# entries reached 1 MB, so not one of them could EVER have been reaped.
#
# This script DETECTS that shape and reports it; it does not reclaim it. The
# reasoning is measured and is written up at the count check in
# reap_scratch_entries: any tier that reclaims sub-MB entries must drop the size
# floor to ~zero, and a dry run against this operator's real /tmp showed 12,240
# entries clearing every remaining gate — only ~10,700 of them the leak, the
# rest authored work — in a pass that had not finished after 10 minutes against
# a 5-minute cron interval. Age and size cannot separate a leaked artifact from
# an old-but-precious one in a SHARED /tmp. The sound fix is per-run private
# scratch roots reaped by their owner, which needs a migration this script
# cannot perform; it is tracked separately.
#
# Two constraints on any future attempt, both measured, so they are not
# rediscovered:
#   - NOT `df -i`. On a host carrying the leak, /tmp was 29% blocks but only 7%
#     inodes (268,438 of 3,992,059) — tmpfs charges a full page per file, so
#     blocks exhaust long before inodes can. An inode trigger would sit
#     disengaged through exactly the scenario it exists for.
#   - NOT a `tmp.` prefix signature. `tmp.` is GNU mktemp's DEFAULT template:
#     856 of 1013 command-position mktemp call sites in this repo are bare. It
#     is a default name, not a leak signature.
#   - And note `du -sm` rounds UP, so a nominal "1 MB floor" admits every
#     non-empty entry. A floor cannot be "reduced" into safety here.
#
# Test seams (default to the real system; overridden only by tmpfs-guard.test.sh):
#   TMPFS_GUARD_TMP, TMPFS_GUARD_PROC, TMPFS_GUARD_DRY_RUN,
#   TMPFS_GUARD_THRESHOLD_MB, TMPFS_GUARD_USAGE_WARN_PCT,
#   TMPFS_GUARD_SCRATCH_MIN_MB, TMPFS_GUARD_SCRATCH_AGE_MIN,
#   TMPFS_GUARD_LOG_SINK, TMPFS_GUARD_ALARM_FILE,
#   TMPFS_GUARD_COUNT_TRIGGER, TMPFS_GUARD_UNIX_SOCKETS,
#   TMPFS_GUARD_HEARTBEAT_FILE, TMPFS_GUARD_LOCKFILE, TMPFS_GUARD_NO_FLOCK
#
# Every name above is read by the code below. Keep this list exact: a seam that
# is documented but unimplemented produces a test that sets it, observes no
# effect, and passes for the wrong reason — the same silent-pass class this
# script's sibling fix (#6992) exists to remove.

set -euo pipefail

THRESHOLD_MB="${TMPFS_GUARD_THRESHOLD_MB:-200}"   # delete .output files larger than this
USAGE_WARN_PCT="${TMPFS_GUARD_USAGE_WARN_PCT:-70}"
TMP_ROOT="${TMPFS_GUARD_TMP:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"   # a trailing slash breaks the _FRESH_TOP prefix strip
PROC_ROOT="${TMPFS_GUARD_PROC:-/proc}"
DRY_RUN="${TMPFS_GUARD_DRY_RUN:-0}"

# Scratch-reaper floors. 24h and 100MB are deliberately conservative: they
# clear the measured 3.1 GiB of abandoned trees without touching anything a
# session plausibly still wants.
SCRATCH_MIN_MB="${TMPFS_GUARD_SCRATCH_MIN_MB:-100}"
SCRATCH_AGE_MIN="${TMPFS_GUARD_SCRATCH_AGE_MIN:-1440}"

# Count-pressure ALARM threshold. 5000 sits far above the ~600 entries a
# healthy /tmp carries here and far below the 17,898 measured while the leak
# was present, so it is provably reachable rather than notional. It arms a
# report, never a delete — see reap_scratch_entries.
COUNT_TRIGGER="${TMPFS_GUARD_COUNT_TRIGGER:-5000}"
# Where /proc exposes unix-domain socket paths. See _build_inuse_top.
UNIX_SOCKETS="${TMPFS_GUARD_UNIX_SOCKETS:-/proc/net/unix}"

# Durable alarm store. Deliberately NOT under $TMP_ROOT — an alarm log on the
# filesystem being reaped is self-defeating.
ALARM_FILE="${TMPFS_GUARD_ALARM_FILE:-${HOME:-/nonexistent}/.local/state/soleur/tmpfs-guard-alarms.log}"
ALARM_MAX_LINES=200

# Overwritten every completed run; SessionStart reads its mtime. Kept beside the
# alarm file so both live or die together.
HEARTBEAT_FILE="${TMPFS_GUARD_HEARTBEAT_FILE:-${HOME:-/nonexistent}/.local/state/soleur/tmpfs-guard-last-run}"

CLAUDE_TMP="$TMP_ROOT/claude-$(id -u)"

# --- Logging seam ----------------------------------------------------------
# Every log line goes through here. The default sink is the journal, exactly as
# before; the test suite points TMPFS_GUARD_LOG_SINK at a fixture-scoped file so
# it stops polluting the operator's journal.
#
# That pollution was not cosmetic: of 346 `Reaped` lines in the journal over 14
# days, 344 came from this suite's fixture roots and ONE came from the real
# /tmp. Anyone reading the journal to judge whether the guard works saw a busy,
# healthy-looking reaper that had in fact reaped once in a fortnight.
#
# `notify-send` is deliberately absent. It is a silent no-op under cron (no DBUS
# session) and was additionally swallowed by `2>/dev/null || true` — keeping it
# as a best-effort extra is exactly how the current dead channel came to exist.
guard_log() {
  local msg="$1"
  if [[ -n "${TMPFS_GUARD_LOG_SINK:-}" ]]; then
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$TMPFS_GUARD_LOG_SINK" 2>/dev/null || true
  else
    logger -t tmpfs-guard "$msg" 2>/dev/null || true
  fi
}

# Append an alarm record the operator will actually see. The SessionStart hook
# renders this file at the top of the next agent session; there is no network
# path from this host's cron to Better Stack or Sentry (Vector is not installed,
# `tmpfs-guard` is not in the vector tag allowlist, no local Sentry DSN exists,
# `doppler` is off cron's PATH, and `gh` authenticates via an OS keyring that
# cron cannot reach). Inventing one would create an egress surface where none
# exists; surfacing at SessionStart needs no credential at all.
alarm_record() {
  local msg="$1" dir
  dir="$(dirname "$ALARM_FILE")"
  # Both failure paths log rather than returning silently. This is the ONLY
  # channel that reaches the operator, and its failure mode (unwritable $HOME,
  # a full home filesystem) is plausibly correlated with the condition being
  # alarmed — so a silent drop turns "no alarm" from ambiguous into wrong.
  if ! mkdir -p "$dir" 2>/dev/null; then
    guard_log "ALARM-DROP: cannot create $dir — alarm not persisted: $msg"
    return 0
  fi
  if ! printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$ALARM_FILE" 2>/dev/null; then
    guard_log "ALARM-DROP: cannot append to $ALARM_FILE — alarm not persisted: $msg"
    return 0
  fi
  # Size cap: keep the most recent ALARM_MAX_LINES.
  local n
  n=$(wc -l < "$ALARM_FILE" 2>/dev/null || echo 0)
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > ALARM_MAX_LINES )); then
    tail -n "$ALARM_MAX_LINES" "$ALARM_FILE" > "$ALARM_FILE.tmp" 2>/dev/null \
      && mv -f "$ALARM_FILE.tmp" "$ALARM_FILE" 2>/dev/null || true
  fi
}

# Overwrite-in-place heartbeat, written on EVERY completed run. This is what
# makes "the cron entry stopped firing" detectable: the alarm file cannot show
# it (a dead guard writes no alarms, so an absent alarm reads as health), and
# the journal liveness line has no consumer. SessionStart compares this file's
# mtime against the 5-minute cadence.
heartbeat_write() {
  local dir
  dir="$(dirname "$HEARTBEAT_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" > "$HEARTBEAT_FILE" 2>/dev/null || true
}

# Clear the alarm file once the machine is demonstrably healthy. Without this
# the operator must hand-delete it: the guard appends every 5 minutes while the
# condition holds (288/day against a 200-line cap), so the count saturates
# within hours and then every future session shows a long-resolved incident as
# active. That is alarm fatigue on the one channel that works, and a manual
# clear step is exactly the kind of operator homework this repo refuses to ship.
alarm_clear_if_healthy() {
  [[ -f "$ALARM_FILE" ]] || return 0
  guard_log "alarm cleared — $TMP_ROOT healthy again"
  rm -f "$ALARM_FILE" 2>/dev/null || true
}

tmpfs_usage_pct() {
  local p
  p=$(df "$TMP_ROOT" --output=pcent 2>/dev/null | tail -1 | tr -d ' %') || p=""
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  printf '%s\n' "$p"
}

# Populate _INUSE_TOP with the top-level $TMP_ROOT entry of every live process
# that has EITHER its cwd OR an open file descriptor under $TMP_ROOT, in a
# SINGLE /proc pass. A cwd or fd target of /tmp/tmp.ABC/repo/x marks
# /tmp/tmp.ABC in use. Built once per run rather than rescanned per candidate —
# the naive per-candidate scan is O(candidates × pids) and on a full /tmp
# (6000+ stale entries, 600+ pids) that is millions of readlinks, far too slow
# for a 5-minute cron.
#
# BOTH cwd AND fds are load-bearing (the SAFETY header's "no open file handle"
# claim): a process can hold an OPEN FD to a file inside a scratch tree — an
# mmap'd dataset, a held-open DB, a downloaded artifact being served — while
# its cwd is elsewhere and nothing in the tree has a recent mtime. cwd alone
# would miss it and `rm` the live data out from under the reader. `fuser` below
# covers only top-level *file* candidates; this fd scan is what covers the
# common *directory* case (a scratch tree with a live open handle inside).
declare -A _INUSE_TOP
declare -A _FRESH_TOP

# Populate _FRESH_TOP with every top-level $TMP_ROOT entry whose tree contains
# ANYTHING modified inside the age floor, in a SINGLE walk. This replaces a
# per-candidate recursive `find`; see the AGE gate in reap_scratch_entries for
# the measurement that motivated it.
_build_fresh_top() {
  _FRESH_TOP=()
  local age_min="$1" top
  # Sentinel. The walk below runs inside a process substitution, so its exit
  # status is unreachable to `pipefail` and a failure — awk without NUL-in-RS,
  # find aborting, a full $TMPDIR (which is the very filesystem under pressure)
  # — yields an EMPTY map. An empty map reads as "nothing is fresh", which
  # silently removes the recursive-age gate for every candidate in the run.
  # The failure direction of this function is deletion, so it must fail closed:
  # the caller aborts the reap if the sentinel is missing afterwards.
  _FRESH_TOP["__built__"]=1
  # awk dedupes; the consumer is an associative-array write, so a `sort -zu`
  # stage would only buffer the whole set to do work the array does for free.
  # On the measured leak host that is ~268,000 records saved.
  while IFS= read -r -d '' top; do
    [[ -n "$top" ]] && _FRESH_TOP["$TMP_ROOT/$top"]=1
  done < <(
    find "$TMP_ROOT" -mindepth 1 -mmin "-${age_min}" -print0 2>/dev/null \
      | awk -v RS='\0' -v ORS='\0' -v root="$TMP_ROOT/" '
          {
            s = substr($0, length(root) + 1)
            i = index(s, "/")
            t = (i ? substr(s, 1, i - 1) : s)
            if (!seen[t]++) print t
          }'
  )
}
# Map an absolute path to its top-level $TMP_ROOT entry and mark it in use.
_mark_inuse() {
  local target="$1" rest top
  case "$target" in
    "$TMP_ROOT"/*)
      rest="${target#"$TMP_ROOT"/}"
      top="${rest%%/*}"
      [[ -n "$top" ]] && _INUSE_TOP["$TMP_ROOT/$top"]=1
      ;;
  esac
}
_build_inuse_top() {
  _INUSE_TOP=()
  local p fd target
  for p in "$PROC_ROOT"/[0-9]*; do
    if [[ -e "$p/cwd" ]]; then
      target=$(readlink "$p/cwd" 2>/dev/null) && _mark_inuse "$target"
    fi
    # Open file descriptors (skips a process whose /proc/<pid>/fd we cannot read
    # — a foreign-owned process; those never hold OUR uid-scoped candidates).
    if [[ -d "$p/fd" ]]; then
      for fd in "$p"/fd/*; do
        [[ -e "$fd" || -L "$fd" ]] || continue
        target=$(readlink "$fd" 2>/dev/null) && _mark_inuse "$target"
      done
    fi

    # MEMORY MAPPINGS. A file can be open()'d, mmap'd MAP_SHARED, and its fd
    # CLOSED — the mapping stays live and writable while no fd references it,
    # so the walk above cannot see it. /proc/<pid>/map_files carries the path.
    #
    # The canonical instance is the JVM: HotSpot creates
    # /tmp/hsperfdata_<user>/<pid> with exactly open+mmap+close, and on tmpfs
    # the mtime is stamped at the first write fault and never advances, so a
    # JVM running longer than the age floor has a directory that is stale,
    # own-uid, un-denylisted, fd-less and socket-less. It clears every other
    # gate. Deleting it makes jps/jstat lose a running process while the JVM
    # keeps writing into an unlinked inode.
    if [[ -d "$p/map_files" ]]; then
      for fd in "$p"/map_files/*; do
        [[ -e "$fd" || -L "$fd" ]] || continue
        target=$(readlink "$fd" 2>/dev/null) && _mark_inuse "$target"
      done
    fi
  done

  # UNIX-DOMAIN SOCKETS. The fd walk above is architecturally BLIND to these: a
  # socket fd readlinks to `socket:[12345]`, never to its filesystem path, so a
  # directory held open only by a live socket looks completely idle. /proc/net/unix
  # is the only place the kernel exposes the path, and it is one file read —
  # cheaper than the fd walk it completes.
  #
  # This is not theoretical. /tmp/com.google.Chrome.* holds `SingletonSocket`
  # for a LIVE browser; measured 2026-07-27, it cleared ownership, top-level
  # age, recursive age, the denylist as it then stood, and the fd-based liveness
  # scan — every gate except the 100 MB size floor. The pressure tier drops that
  # floor, so this pass and the widened denylist are the ONLY things standing
  # between the pressure tier and a killed browser. That is why it had to land
  # before the pressure tier existed, and why the suite asserts it
  # non-vacuously: blinding TMPFS_GUARD_UNIX_SOCKETS deletes the same fixture.
  if [[ -r "$UNIX_SOCKETS" ]]; then
    # Strip the SEVEN fixed columns (Num RefCount Protocol Flags Type St Inode)
    # and take the whole remainder as the path. `$NF` would be wrong: it is the
    # last WHITESPACE-SEPARATED field, so a socket at "/tmp/sock dir/live.sock"
    # yields "dir/live.sock", which fails the ^/ test and is silently dropped —
    # leaving a live socket-held directory invisible to liveness and therefore
    # deletable under the pressure tier. Measured: that path is exactly how a
    # live browser's IPC directory gets reaped.
    while read -r sock_path; do
      [[ -n "$sock_path" ]] && _mark_inuse "$sock_path"
    done < <(
      awk '{ line = $0
             if (sub(/^([^ ]+[ ]+){7}/, "", line) && substr(line, 1, 1) == "/") print line }' \
        "$UNIX_SOCKETS" 2>/dev/null || true
    )
  fi
}

# --- Reaper 1: oversized .output files (pre-existing behaviour) -------------
reap_output_files() {
  local usage_pct="$1"
  # Initialise BEFORE the early return, so a sourced caller that reads the
  # global after a no-op call gets 0 rather than an unbound-variable abort
  # under `set -u` (or a stale value from a previous call).
  CLEANED_COUNT=0
  # Scoped to the Claude temp dir; absent on a machine with no active session.
  [[ -d "$CLAUDE_TMP" ]] || return 0

  local cleaned=0 cleaned_mb=0 file size_bytes size_mb
  while IFS= read -r file; do
    size_bytes=$(stat --format=%s "$file" 2>/dev/null) || continue
    size_mb=$(( size_bytes / 1048576 ))
    # Skip files still being written by an active process.
    if fuser "$file" >/dev/null 2>&1; then
      if [[ "$usage_pct" -lt 90 ]]; then
        continue
      fi
      # At 90%+ usage, killing it is justified — the system is about to lock up.
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
      guard_log "would remove $file (${size_mb} MB)"
      continue
    fi
    rm -f "$file"
    cleaned=$(( cleaned + 1 ))
    cleaned_mb=$(( cleaned_mb + size_mb ))
  done < <(find "$CLAUDE_TMP" -name "*.output" -size "+${THRESHOLD_MB}M" -type f 2>/dev/null)

  if [[ "$cleaned" -gt 0 ]]; then
    guard_log "Removed $cleaned .output files (${cleaned_mb} MB). $TMP_ROOT at ${usage_pct}%."
  fi
  # Return via a global, never stdout — see the REAP_COUNT note on
  # reap_scratch_entries.
  CLEANED_COUNT="$cleaned"
  return 0
}

# --- Reaper 2: stale, large, own-uid scratch entries (#6789) ---------------
reap_scratch_entries() {
  local usage_pct="${1:-0}"
  # All four globals initialised before the early return — see reap_output_files.
  REAP_COUNT=0
  REAP_MB=0
  COUNT_PRESSURE_SEEN=0
  [[ -d "$TMP_ROOT" ]] || return 0
  local uid; uid="$(id -u)"
  local reaped=0 reaped_mb=0
  local e base size_mb

  # Which tier are we in? The count signal is one `find | wc -l`.
  local entry_count min_mb age_min max_reap
  entry_count=$(find "$TMP_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  [[ "$entry_count" =~ ^[0-9]+$ ]] || entry_count=0
  [[ "$usage_pct" =~ ^[0-9]+$ ]] || usage_pct=0

  # BOTH signals must hold. Entry count alone is not pressure: this repo's
  # documented workflow runs parallel worktrees, which inflates /tmp's entry
  # count without filling it, and the pressure tier drops the size floor to zero
  # and the age floor to 6h. Engaging it on a /tmp at 10% would take real risk
  # to reclaim space nobody needs. Usage is already computed by main; requiring
  # it makes the tier's name true.
  # COUNT PRESSURE IS AN ALARM, NOT A REAP TRIGGER.
  #
  # #6991 asks for a reaper that can act on a count signal. This detects the
  # signal and reports it; it deliberately does NOT widen what gets deleted.
  # The reason is measured, not cautious-by-default.
  #
  # A count-shaped leak is by definition made of sub-MB entries, so any tier
  # that reclaims it must drop the size floor to approximately zero — and
  # `du -sm` rounds UP, so even a nominal "1 MB floor" admits every non-empty
  # entry. Dry-run against this operator's real /tmp (18,832 entries) with such
  # a floor: 12,240 entries cleared every remaining gate, of which only ~10,700
  # were the leak. The other ~1,500 were authored work — PR bodies, review
  # backups, a downloaded CLI binary and its config — and `find -delete` on a
  # RAM-backed tmpfs is terminal. The same run had not finished after 10
  # minutes, against a 5-minute cron interval.
  #
  # Age and size are the only value proxies available in a SHARED /tmp, and
  # neither separates a leaked artifact from an old-but-precious one. The issue
  # itself names the sound fix — per-run private scratch roots reaped by their
  # owner — and rejects prefix signatures, because `tmp.` is mktemp's default
  # at 856 of 1013 call sites. That fix needs the scratch-root migration, which
  # has zero adopters today. Filed separately rather than approximated here.
  if (( entry_count >= COUNT_TRIGGER )); then
    COUNT_PRESSURE_SEEN=1
    guard_log "count pressure: $entry_count top-level entries in $TMP_ROOT at ${usage_pct}% (trigger $COUNT_TRIGGER) — reporting, not reaping"
    alarm_record "$TMP_ROOT holds $entry_count top-level entries (trigger $COUNT_TRIGGER) at ${usage_pct}% usage — a count-shaped leak the size-based reaper cannot reclaim. Inspect the oldest: find $TMP_ROOT -mindepth 1 -maxdepth 1 -printf '%T@ %p\n' | sort -n | head -40"
  fi

  # One tier. The floors below are the pre-existing, conservative ones.
  min_mb="$SCRATCH_MIN_MB"
  age_min="$SCRATCH_AGE_MIN"
  max_reap=0   # 0 = uncapped; the floors already bound the candidate set

  _build_inuse_top

  # SIZE FIRST, via a SINGLE batched `du`. Size is the most selective gate — a
  # measured 3 of thousands of entries qualify — but it is also the only gate
  # that must walk a tree. Running it per-candidate (a fresh `du`/recursive
  # `find` for each of 6000+ stale entries) does not finish inside a 5-minute
  # cron window. One `du --files0-from` over the whole stale set walks every
  # tree exactly once (~2s on the measured /tmp) and hands back a tiny survivor
  # list, on which the expensive recursive-age + liveness gates then run.
  #
  # `--files0-from` (not an argv list) so a large candidate set cannot hit the
  # kernel's per-arg E2BIG ceiling (the ARGV lesson from work/SKILL.md). The
  # top-level `-mmin` prefilter is cheap and only ever more conservative; the
  # recursive age check below is the real R6 safety gate.
  local cand_file; cand_file="$(mktemp -t tmpfs-guard-cand.XXXXXX)" || return 0
  local sized_file; sized_file="$(mktemp -t tmpfs-guard-sized.XXXXXX)" || { rm -f "$cand_file"; return 0; }
  # shellcheck disable=SC2064
  trap "rm -f '$cand_file' '$sized_file'" RETURN

  # Candidates are NUL-delimited end to end EXCEPT across `du`, which emits
  # newline-terminated "<size>\t<path>" records with no NUL option. An entry
  # whose NAME contains a newline therefore splits into two records, and the
  # read loop below attributes the second half's size to the first half's path
  # — measured: a 14-byte directory was deleted because a 20 MB sibling named
  # "<same-name>\nx" existed, with neither the size nor the age gate ever
  # evaluated against it. Excluding such names is fail-safe (they are simply
  # never reaped) and costs nothing: no legitimate scratch entry has one.
  local skipped_odd=0
  while IFS= read -r -d '' e; do
    if [[ "$e" == *$'\n'* ]]; then
      skipped_odd=$((skipped_odd + 1))
      continue
    fi
    printf '%s\0' "$e"
  done < <(
    find "$TMP_ROOT" -mindepth 1 -maxdepth 1 -user "$uid" -mmin "+${age_min}" -print0 2>/dev/null || true
  ) > "$cand_file"
  if (( skipped_odd > 0 )); then
    guard_log "skipped $skipped_odd candidate(s) whose name contains a newline — not reapable safely"
  fi
  # `du -sm` emits ONE "<size>\t<path>" summary line per candidate. `-s` is
  # load-bearing — without it du descends and prints every subdirectory, which
  # would enqueue non-top-level paths for reaping. `du` exits non-zero on a
  # vanished entry (a concurrent reap elsewhere) — tolerate it, the survivors it
  # did size are still valid. Keep only rows at or above the floor; the size↔path
  # tab is preserved verbatim for the read loop below.
  du -sm --files0-from="$cand_file" 2>/dev/null \
    | awk -F'\t' -v floor="$min_mb" '$1 ~ /^[0-9]+$/ && $1 >= floor' \
    > "$sized_file" || true

  # Recursive-age set, built AFTER the size filter and only when something
  # survived it. On a healthy /tmp the sized set is empty every five minutes
  # forever, and an unconditional build would pay a full recursive walk of the
  # whole tree for a map nothing then reads. Safe to skip: an empty
  # "$sized_file" means the loop below never runs, so _FRESH_TOP is unreachable.
  [[ -s "$sized_file" ]] && _build_fresh_top "$age_min"

  while IFS=$'\t' read -r size_mb e; do
    [[ -n "$e" ]] || continue
    [[ "$size_mb" =~ ^[0-9]+$ ]] || continue
    base="${e##*/}"

    # Protected paths. These have other owners or are deliberately reused; reaping
    # them here would race a different cleanup path or destroy a live cache.
    # `node-compile-cache` is a reusable Node V8 cache, not a leak — spared here
    # for the same reason worktree-manager.sh's cleanup_stale_sandbox_tmp spares
    # it (that function owns the signature-gated sandbox-copy class; this reaper
    # additionally covers the dotted `tmp.XXXXXX` mkdtemp trees its 15+-char
    # regex excludes, so the two cooperate — see the delete-idiom note below).
    # The pressure tier drops the size floor to ~1 MB, which exposes the entire
    # small-entry population for the first time — and that population is where
    # IPC directories, sockets and lockfiles live. The names below were taken
    # from a live /tmp listing on 2026-07-27 rather than assumed; the previous
    # 9-entry list predates the pressure tier and was never audited against one.
    case "$base" in
      claude-*|soleur-session-state*|node-compile-cache|.X11-unix|.ICE-unix|.font-unix|.XIM-unix|.Test-unix|systemd-*|snap*)
        continue ;;
      com.google.Chrome.*|.org.chromium.*|.com.google.Chrome.*|chromium-*|firefox-*|\
      dbus-*|pulse-*|.mount_*|tmux-*|ssh-*|.X*-lock|gpg-*|wayland-*|at-spi2-*)
        continue ;;
    esac

    # Never follow a symlink out of the scratch root.
    [[ -L "$e" ]] && continue

    # LIVENESS (O(1) set lookup — the map now covers cwd, open fds, AND
    # unix-socket paths from /proc/net/unix).
    #
    # `fuser` stays scoped to FILES. Running it on directories as well was
    # measured at 66 ms per call — 19.9 s for 300 candidates, which alone
    # blows the 5-minute cron interval at leak scale — and it is redundant:
    # _INUSE_TOP already covers the directory cases (cwd, open fd, and socket
    # path). Verified non-vacuous: blinding the /proc/net/unix seam lets a
    # socket-held directory be deleted, so the map is what protects it, not
    # fuser.
    [[ -n "${_INUSE_TOP[$e]:-}" ]] && continue
    if [[ ! -d "$e" ]]; then
      fuser "$e" >/dev/null 2>&1 && continue
    fi

    # AGE (recursive) — the R6 safety gate. A directory's own mtime does NOT
    # change when a nested file is written, so a top-level test alone would
    # delete a tree that is actively in use.
    #
    # Answered from the _FRESH_TOP set built in ONE pass before the loop.
    # Per-candidate `find` was 18 ms a call (5.3 s for 300); the single batched
    # walk that replaces it measured 0.024 s for the same fixture — ~220x
    # cheaper, and the gap widens with the candidate count. At leak scale the
    # per-candidate form does not finish inside the cron interval.
    [[ -n "${_FRESH_TOP[$e]:-}" ]] && continue

    # Per-run cap on the pressure tier. Bounds both blast radius and wall clock.
    if (( max_reap > 0 && reaped >= max_reap )); then
      guard_log "pressure cap reached ($max_reap entries) — stopping this run"
      # Hitting the cap means an automated mass-delete ran on the operator's
      # machine AND did not finish. That is higher-signal than the usage alarm
      # below and must not depend on it.
      alarm_record "pressure reap hit the per-run cap ($max_reap entries) in $TMP_ROOT — the leak is producing faster than one run can reclaim"
      break
    fi

    # guard_log, not echo. These lines used to go to stdout, which the caller
    # captured and discarded, so the journal carried 0 `reaping` lines against
    # 346 `Reaped` summaries — every doc claim keyed on per-entry reap detail
    # was unverifiable.
    if [[ "$DRY_RUN" == "1" ]]; then
      guard_log "would reap $e (${size_mb} MB)"
      continue
    fi
    guard_log "reaping $e (${size_mb} MB)"
    # `find … -delete`, NEVER `rm -rf` — a size-survivor can be an abandoned repo
    # clone (a `.git`-bearing checkout), and the constitution's
    # guardrails:block-recursive-delete rule forbids `rm -rf` on such a target.
    # worktree-manager.sh's cleanup_stale_sandbox_tmp uses the same find-delete
    # idiom for the same reason; the cron context here means the PreToolUse hook
    # would not fire, so honouring the idiom (not relying on the hook) is what
    # keeps this inside the guardrail. `-delete` implies depth-first and never
    # follows symlinks. Tolerate partial failure (a vanished/permission entry).
    find "$e" -delete 2>/dev/null || true
    reaped=$(( reaped + 1 ))
    reaped_mb=$(( reaped_mb + size_mb ))
  done < "$sized_file"

  if [[ "$reaped" -gt 0 ]]; then
    guard_log "Reaped $reaped stale scratch entries (${reaped_mb} MB) from $TMP_ROOT."
  fi

  # RETURN VIA GLOBALS, never stdout. The previous contract was
  # `reaped="$(reap_scratch_entries)"`, which captured the per-entry `echo`
  # lines AND the trailing count into one multi-line string. `main` then ran
  # `[[ "${reaped:-0}" -eq 0 ]]` on it: bash arithmetic parses the leading word
  # `tmpfs` as a variable name and `set -u` makes that FATAL. main exited 1 and
  # the high-usage alarm branch never ran — on precisely the runs that had
  # reaped something while /tmp was full. Reproduced: `tmpfs: unbound variable`,
  # exit 1.
  #
  # With globals there is no command substitution, no subshell, and no parsing,
  # so a stray write to stdout can never break the arithmetic again.
  REAP_COUNT="$reaped"
  REAP_MB="$reaped_mb"
  return 0
}

main() {
  local usage_pct
  usage_pct="$(tmpfs_usage_pct)"

  # NOTE: the .output reaper self-guards on CLAUDE_TMP. This used to be a
  # top-of-script `exit 0`, which would now silently disable the scratch reaper
  # on any machine without an active Claude session — the reaper would never
  # run precisely where abandoned scratch accumulates unattended.
  CLEANED_COUNT=0
  REAP_COUNT=0
  REAP_MB=0
  COUNT_PRESSURE_SEEN=0

  reap_output_files "$usage_pct"
  reap_scratch_entries "$usage_pct"

  # Per-run liveness line, emitted on EVERY run including a healthy one. Without
  # it "the guard is silent because nothing needed doing" and "the guard is not
  # running at all" are indistinguishable, and the cron entry stopping is a
  # failure mode with no detector.
  local summary="run complete: $TMP_ROOT at ${usage_pct}%, cleaned=${CLEANED_COUNT}, reaped=${REAP_COUNT} (${REAP_MB} MB), count_pressure=${COUNT_PRESSURE_SEEN}"
  guard_log "$summary"
  # The journal line above has no consumer. The heartbeat does: SessionStart
  # compares its mtime against the 5-minute cadence, which is what makes "the
  # cron entry was removed" detectable at all. An absent alarm file cannot
  # carry that signal — a dead guard writes no alarms, so silence reads as
  # health, which is the exact failure this PR exists to remove.
  heartbeat_write "$summary"

  # Warn on high usage when neither reaper found anything — something else is
  # filling /tmp and no automated path will reclaim it.
  #
  # This branch fired 94 times in 14 days and reached nobody: it went only to
  # the journal (unwatched) and notify-send (a no-op under cron). It now also
  # writes the durable alarm file that the SessionStart hook surfaces, so the
  # next agent session shows it to the operator.
  if [[ "$usage_pct" -ge "$USAGE_WARN_PCT" ]] \
     && [[ "${CLEANED_COUNT:-0}" -eq 0 ]] && [[ "${REAP_COUNT:-0}" -eq 0 ]]; then
    guard_log "$TMP_ROOT at ${usage_pct}% — nothing reapable found."
    alarm_record "$TMP_ROOT at ${usage_pct}% — nothing reapable found. Investigate: du -sh $TMP_ROOT/* | sort -h | tail"
  fi

  # Healthy run: usage below the warn threshold AND no count pressure. Clear the
  # alarm file so a resolved incident stops being reported as active.
  if [[ "$usage_pct" -lt "$USAGE_WARN_PCT" ]] && [[ "${COUNT_PRESSURE_SEEN:-0}" -eq 0 ]]; then
    alarm_clear_if_healthy
  fi
}

# CLI vs. sourced (test harness). Mirrors the session-state.sh idiom.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Serialise runs. A pressure-tier pass over a large /tmp can outlast the
  # 5-minute cron interval, and two overlapping runs would race each other's
  # deletes — one stat-ing an entry the other has already removed. There was no
  # lock at all before. Non-blocking: if a run is already in flight, this one
  # exits rather than queueing up behind it (a queue of guards is its own leak).
  if [[ "${TMPFS_GUARD_NO_FLOCK:-0}" != "1" ]] && command -v flock >/dev/null 2>&1; then
    _lockfile="${TMPFS_GUARD_LOCKFILE:-${TMPDIR:-/tmp}/.tmpfs-guard-$(id -u).lock}"
    # If the lockfile cannot be created, run UNSERIALISED and say so — do not
    # fall back to `exec 9>/dev/null`. That path locks the /dev/null inode,
    # which is shared with every process on the box, so an unrelated flocker
    # would block this guard indefinitely and it would then log "another
    # tmpfs-guard run is in flight", which is false. The trigger for the
    # fallback is ENOSPC creating a file in a full /tmp — i.e. the emergency
    # itself — so lying about the cause there is the worst possible moment.
    if exec 9>"$_lockfile" 2>/dev/null; then
      if ! flock -n 9; then
        guard_log "another tmpfs-guard run is in flight — skipping"
        exit 0
      fi
    else
      guard_log "lockfile unavailable ($_lockfile) — running unserialised"
    fi
  fi
  main
fi
