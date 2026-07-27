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
# entries reached 1 MB, so not one of them could EVER have been reaped. The
# single entry over the floor was 14h old against a 24h age gate, so that was
# excluded too.
#
# The reaper now has a second, pressure-gated tier keyed on the TOP-LEVEL ENTRY
# COUNT. Three constraints shaped it, each measured rather than assumed:
#
#   - NOT `df -i`. On a host carrying the leak, /tmp was 29% blocks but only 7%
#     inodes (268,438 of 3,992,059) — tmpfs charges a full page per file, so
#     blocks exhaust long before inodes can. An inode trigger would sit
#     disengaged through exactly the scenario it exists for.
#   - NOT a `tmp.` prefix signature. `tmp.` is GNU mktemp's DEFAULT template:
#     856 of 1013 command-position mktemp call sites in this repo are bare. It
#     is a default name, not a leak signature.
#   - The size floor is REDUCED under pressure, never removed. Removing it
#     would expose the entire small-entry population, which is where unix
#     sockets, lockfiles and IPC directories live — see the liveness note on
#     _build_inuse_top.
#
# Test seams (default to the real system; overridden only by tmpfs-guard.test.sh):
#   TMPFS_GUARD_TMP, TMPFS_GUARD_PROC, TMPFS_GUARD_DRY_RUN,
#   TMPFS_GUARD_SCRATCH_MIN_MB, TMPFS_GUARD_SCRATCH_AGE_MIN,
#   TMPFS_GUARD_LOG_SINK, TMPFS_GUARD_USAGE_PCT, TMPFS_GUARD_ALARM_FILE,
#   TMPFS_GUARD_COUNT_TRIGGER, TMPFS_GUARD_PRESSURE_MIN_MB,
#   TMPFS_GUARD_PRESSURE_AGE_MIN, TMPFS_GUARD_PRESSURE_MAX_REAP,
#   TMPFS_GUARD_UNIX_SOCKETS, TMPFS_GUARD_NO_FLOCK

set -euo pipefail

THRESHOLD_MB="${TMPFS_GUARD_THRESHOLD_MB:-200}"   # delete .output files larger than this
USAGE_WARN_PCT="${TMPFS_GUARD_USAGE_WARN_PCT:-70}"
TMP_ROOT="${TMPFS_GUARD_TMP:-/tmp}"
PROC_ROOT="${TMPFS_GUARD_PROC:-/proc}"
DRY_RUN="${TMPFS_GUARD_DRY_RUN:-0}"

# Scratch-reaper floors. 24h and 100MB are deliberately conservative: they
# clear the measured 3.1 GiB of abandoned trees without touching anything a
# session plausibly still wants.
SCRATCH_MIN_MB="${TMPFS_GUARD_SCRATCH_MIN_MB:-100}"
SCRATCH_AGE_MIN="${TMPFS_GUARD_SCRATCH_AGE_MIN:-1440}"

# Pressure tier. Engages only when the top-level entry count crosses the
# trigger. 5000 sits far above the ~600 entries a healthy /tmp carries here and
# far below the 17,898 measured while the leak was present, so it is provably
# reachable rather than notionally reachable.
COUNT_TRIGGER="${TMPFS_GUARD_COUNT_TRIGGER:-5000}"
PRESSURE_MIN_MB="${TMPFS_GUARD_PRESSURE_MIN_MB:-1}"
PRESSURE_AGE_MIN="${TMPFS_GUARD_PRESSURE_AGE_MIN:-360}"
PRESSURE_MAX_REAP="${TMPFS_GUARD_PRESSURE_MAX_REAP:-4000}"

# Where /proc exposes unix-domain socket paths. See _build_inuse_top.
UNIX_SOCKETS="${TMPFS_GUARD_UNIX_SOCKETS:-/proc/net/unix}"

# Durable alarm store. Deliberately NOT under $TMP_ROOT — an alarm log on the
# filesystem being reaped is self-defeating.
ALARM_FILE="${TMPFS_GUARD_ALARM_FILE:-$HOME/.local/state/soleur/tmpfs-guard-alarms.log}"
ALARM_MAX_LINES=200

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
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$ALARM_FILE" 2>/dev/null || return 0
  # Size cap: keep the most recent ALARM_MAX_LINES.
  local n
  n=$(wc -l < "$ALARM_FILE" 2>/dev/null || echo 0)
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > ALARM_MAX_LINES )); then
    tail -n "$ALARM_MAX_LINES" "$ALARM_FILE" > "$ALARM_FILE.tmp" 2>/dev/null \
      && mv -f "$ALARM_FILE.tmp" "$ALARM_FILE" 2>/dev/null || true
  fi
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
  while IFS= read -r -d '' top; do
    [[ -n "$top" ]] && _FRESH_TOP["$TMP_ROOT/$top"]=1
  done < <(
    find "$TMP_ROOT" -mindepth 1 -mmin "-${age_min}" -print0 2>/dev/null \
      | awk -v RS='\0' -v ORS='\0' -v root="$TMP_ROOT/" '
          {
            s = substr($0, length(root) + 1)
            i = index(s, "/")
            print (i ? substr(s, 1, i - 1) : s)
          }' \
      | sort -zu
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
    [[ -d "$p/fd" ]] || continue
    for fd in "$p"/fd/*; do
      [[ -e "$fd" || -L "$fd" ]] || continue
      target=$(readlink "$fd" 2>/dev/null) && _mark_inuse "$target"
    done
  done

  # UNIX-DOMAIN SOCKETS. The fd walk above is architecturally BLIND to these: a
  # socket fd readlinks to `socket:[12345]`, never to its filesystem path, so a
  # directory held open only by a live socket looks completely idle. /proc/net/unix
  # is the only place the kernel exposes the path, and it is one file read —
  # cheaper than the fd walk it completes.
  #
  # This is not theoretical. /tmp/com.google.Chrome.* holds `SingletonSocket`
  # for a LIVE browser; measured 2026-07-27, it cleared ownership, top-level
  # age, recursive age, the denylist, and the fd-based liveness scan — all five
  # gates. The ONLY thing standing between it and deletion was the 100 MB size
  # floor, which is why the pressure tier reduces that floor instead of removing
  # it, and why this pass had to land before the pressure tier existed at all.
  if [[ -r "$UNIX_SOCKETS" ]]; then
    while read -r sock_path; do
      [[ -n "$sock_path" ]] && _mark_inuse "$sock_path"
    done < <(awk 'NF > 7 && $NF ~ /^\// { print $NF }' "$UNIX_SOCKETS" 2>/dev/null || true)
  fi
}

# --- Reaper 1: oversized .output files (pre-existing behaviour) -------------
reap_output_files() {
  local usage_pct="$1"
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
  REAP_COUNT=0
  REAP_MB=0
  [[ -d "$TMP_ROOT" ]] || return 0
  local uid; uid="$(id -u)"
  local reaped=0 reaped_mb=0
  local e base fresh size_mb

  # Which tier are we in? The count signal is one `find | wc -l`.
  local entry_count min_mb age_min max_reap
  entry_count=$(find "$TMP_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  [[ "$entry_count" =~ ^[0-9]+$ ]] || entry_count=0

  if (( entry_count >= COUNT_TRIGGER )); then
    PRESSURE_ACTIVE=1
    min_mb="$PRESSURE_MIN_MB"
    age_min="$PRESSURE_AGE_MIN"
    max_reap="$PRESSURE_MAX_REAP"
    guard_log "count pressure: $entry_count top-level entries in $TMP_ROOT (trigger $COUNT_TRIGGER) — floor ${min_mb}MB, age ${age_min}min, cap ${max_reap}"
  else
    PRESSURE_ACTIVE=0
    min_mb="$SCRATCH_MIN_MB"
    age_min="$SCRATCH_AGE_MIN"
    max_reap=0   # 0 = uncapped; the normal tier's floors already bound it
  fi

  _build_inuse_top
  _build_fresh_top "$age_min"

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

  find "$TMP_ROOT" -mindepth 1 -maxdepth 1 -user "$uid" -mmin "+${age_min}" -print0 \
    2>/dev/null > "$cand_file" || true
  # `du -sm` emits ONE "<size>\t<path>" summary line per candidate. `-s` is
  # load-bearing — without it du descends and prints every subdirectory, which
  # would enqueue non-top-level paths for reaping. `du` exits non-zero on a
  # vanished entry (a concurrent reap elsewhere) — tolerate it, the survivors it
  # did size are still valid. Keep only rows at or above the floor; the size↔path
  # tab is preserved verbatim for the read loop below.
  du -sm --files0-from="$cand_file" 2>/dev/null \
    | awk -F'\t' -v floor="$min_mb" '$1 ~ /^[0-9]+$/ && $1 >= floor' \
    > "$sized_file" || true

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
  PRESSURE_ACTIVE=0

  reap_output_files "$usage_pct"
  reap_scratch_entries

  # Per-run liveness line, emitted on EVERY run including a healthy one. Without
  # it "the guard is silent because nothing needed doing" and "the guard is not
  # running at all" are indistinguishable, and the cron entry stopping is a
  # failure mode with no detector.
  guard_log "run complete: $TMP_ROOT at ${usage_pct}%, cleaned=${CLEANED_COUNT}, reaped=${REAP_COUNT} (${REAP_MB} MB), pressure=${PRESSURE_ACTIVE}"

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
}

# CLI vs. sourced (test harness). Mirrors the session-state.sh idiom.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Serialise runs. A pressure-tier pass over a large /tmp can outlast the
  # 5-minute cron interval, and two overlapping runs would race each other's
  # deletes — one stat-ing an entry the other has already removed. There was no
  # lock at all before. Non-blocking: if a run is already in flight, this one
  # exits rather than queueing up behind it (a queue of guards is its own leak).
  if [[ "${TMPFS_GUARD_NO_FLOCK:-0}" != "1" ]] && command -v flock >/dev/null 2>&1; then
    _lockfile="${TMPDIR:-/tmp}/.tmpfs-guard-$(id -u).lock"
    exec 9>"$_lockfile" 2>/dev/null || exec 9>/dev/null
    if ! flock -n 9; then
      guard_log "another tmpfs-guard run is in flight — skipping"
      exit 0
    fi
  fi
  main
fi
