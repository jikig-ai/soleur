#!/usr/bin/env bash
# tmpfs-guard.test.sh — arms for the scratch reaper in scripts/tmpfs-guard.sh (#6789).
#
# This suite exists because the reaper DELETES FILES. Every gate it applies
# (age, size, ownership, in-use, protected-path) is asserted here in BOTH
# directions: the reap happens when it should, and — more importantly — does
# NOT happen when any single gate says no. R3 in the plan is explicit that
# reaping on a single dimension deletes live work.
#
# AUTHORING CONSTRAINTS (see work/SKILL.md):
#   - Never `producer | grep -q` under pipefail; grep a FILE or use `grep -c`.
#   - Deliberately-nonzero commands inside `$(...)` need `|| true` under set -e.
#   - Every arm carries a mutation control.
#
# Fixtures are synthesized under this test's own temp dir. The reaper is driven
# through its seams (TMPFS_GUARD_TMP / TMPFS_GUARD_PROC), so NOTHING outside
# TESTROOT is ever a deletion candidate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/tmpfs-guard.sh"

pass_n=0
fails=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t tmpfs-guard.XXXXXXXX)"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

if [[ ! -f "$GUARD" ]]; then
  echo "ERROR: $GUARD does not exist" >&2
  exit 1
fi

UID_NOW="$(id -u)"

# --- Fixture builders ------------------------------------------------------
# `-mmin` on a directory reflects the directory's own mtime, which does NOT
# change when a nested file is modified. So a fixture must set mtimes on the
# whole tree to be meaningful, and the reaper must check the NEWEST mtime in
# the tree rather than the top-level one.
mk_dir() {  # name, size_mb, age_min
  local d="$FAKE_TMP/$1" mb="$2" age="$3"
  mkdir -p "$d"
  dd if=/dev/zero of="$d/blob" bs=1M count="$mb" status=none 2>/dev/null
  find "$d" -exec touch -d "-${age} minutes" {} + 2>/dev/null || true
  touch -d "-${age} minutes" "$d"
}

reset_fixtures() {
  rm -rf "$FAKE_TMP"; mkdir -p "$FAKE_TMP"
}

FAKE_TMP="$TESTROOT/tmp"
FAKE_PROC="$TESTROOT/proc"
mkdir -p "$FAKE_TMP" "$FAKE_PROC"

guard_env() {
  # LOG_SINK and LOCKFILE are defaulted for EVERY arm, not per-arm.
  #
  # LOG_SINK: without it the suite writes its fixture paths straight into the
  # operator's production journal. That was the #6991 defect (344 of 346
  # `Reaped` lines there were this suite's), and setting it only on the arms
  # that assert against it leaves the other ~20 arms polluting — measured at
  # ~232 lines per run, which is worse than what the PR set out to fix.
  #
  # LOCKFILE: the guard serialises on `${TMPDIR:-/tmp}/.tmpfs-guard-<uid>.lock`,
  # which is the REAL /tmp regardless of TMPFS_GUARD_TMP — so the suite competes
  # for the same lock as the operator's live */5 crontab entry. When cron wins,
  # the CLI arms exit 0 before `main` runs and assertions pass VACUOUSLY (an
  # "exits 0" arm) or fail inexplicably (a "liveness line" arm). Observed 28/4
  # on a run that raced the live cron. Scoping the lock to TESTROOT keeps the
  # locking behaviour under test instead of disabling it.
  env TMPFS_GUARD_TMP="$FAKE_TMP" \
      TMPFS_GUARD_PROC="$FAKE_PROC" \
      TMPFS_GUARD_SCRATCH_MIN_MB=10 \
      TMPFS_GUARD_SCRATCH_AGE_MIN=60 \
      TMPFS_GUARD_LOG_SINK="${TMPFS_GUARD_LOG_SINK:-$TESTROOT/guard.log}" \
      TMPFS_GUARD_LOCKFILE="$TESTROOT/tmpfs-guard.lock" \
      TMPFS_GUARD_ALARM_FILE="${TMPFS_GUARD_ALARM_FILE:-$TESTROOT/alarms.log}" \
      TMPFS_GUARD_WATERMARK_FILE="${TMPFS_GUARD_WATERMARK_FILE:-$TESTROOT/count-watermark}" \
      "$@"
}

# Seed the count watermark. Arms that assert on ABSOLUTE count must pin the
# floor to 0 explicitly: with no watermark file the guard SEEDS from the
# current count (the rebaseline) and is deliberately silent on that first run,
# so an unseeded arm would assert against the seeding path, not the alarm path.
seed_watermark() { printf '%s\n' "$1" > "$TESTROOT/count-watermark"; }

reap() { guard_env "$@" bash -c "source '$GUARD'; reap_scratch_entries" 2>&1 || true; }

echo "=== tmpfs-guard scratch reaper ==="

# --- Arm 1: reaps a large + old + own-uid entry ----------------------------
reset_fixtures
mk_dir "tmp.stale" 20 120
out="$(reap)"
if [[ ! -e "$FAKE_TMP/tmp.stale" ]]; then
  pass "reaps a large, stale, own-uid scratch entry"
else
  fail "did not reap the stale entry; got: $out"
fi

# --- Arm 2: AGE gate — a large but RECENT entry survives -------------------
reset_fixtures
mk_dir "tmp.fresh" 20 1
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.fresh" ]]; then
  pass "AGE gate: a large but recent entry is NOT reaped"
else
  fail "reaped a recent entry — age gate missing (R3); got: $out"
fi

# --- Arm 3: SIZE gate — an old but SMALL entry survives --------------------
# The measurement that motivated this: 4294 small entries held 160MB while
# THREE entries held 3.1GB. Reaping by count would recover 4.5% of the problem
# and delete far more than it reclaims.
reset_fixtures
mk_dir "tmp.small" 1 120
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.small" ]]; then
  pass "SIZE gate: an old but small entry is NOT reaped"
else
  fail "reaped a small entry — size gate missing (R3); got: $out"
fi

# --- Arm 4: IN-USE gate — an entry a live process sits in survives ---------
reset_fixtures
mk_dir "tmp.inuse" 20 120
mkdir -p "$FAKE_PROC/4242"
ln -sfn "$FAKE_TMP/tmp.inuse" "$FAKE_PROC/4242/cwd"
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.inuse" ]]; then
  pass "IN-USE gate: an entry holding a live process cwd is NOT reaped"
else
  fail "reaped an in-use entry — a running session lost its scratch; got: $out"
fi
# MUTATION CONTROL: once the process is gone, the same entry IS reaped, so the
# arm above cannot pass by simply never reaping anything.
rm -rf "$FAKE_PROC/4242"
out="$(reap)"
if [[ ! -e "$FAKE_TMP/tmp.inuse" ]]; then
  pass "the same entry IS reaped once no process cwd points into it"
else
  fail "in-use gate never releases; got: $out"
fi

# --- Arm 4b: IN-USE gate — a NESTED cwd (the real case) is honoured ---------
# A real process's cwd is NEVER the scratch dir itself — it is a checkout DEEP
# inside it (/tmp/tmp.X/repo/sub). Arm 4 points cwd directly AT the top-level
# entry, where the `${rest%%/*}` top-level strip is a no-op, so it cannot
# distinguish exact-cwd from nested-cwd handling: a mutation recognising only
# the exact cwd passes Arm 4 while reaping every real nested-cwd tree. This arm
# forces the nesting so that mapping is actually tested.
reset_fixtures
mkdir -p "$FAKE_TMP/tmp.nestcwd/repo/sub"
dd if=/dev/zero of="$FAKE_TMP/tmp.nestcwd/repo/sub/blob" bs=1M count=20 status=none 2>/dev/null
find "$FAKE_TMP/tmp.nestcwd" -exec touch -d "-120 minutes" {} + 2>/dev/null || true
touch -d "-120 minutes" "$FAKE_TMP/tmp.nestcwd"
mkdir -p "$FAKE_PROC/4243"
ln -sfn "$FAKE_TMP/tmp.nestcwd/repo/sub" "$FAKE_PROC/4243/cwd"
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.nestcwd" ]]; then
  pass "IN-USE gate: a NESTED process cwd marks the top-level tree in use"
else
  fail "reaped a tree a live process is nested inside (R3 catastrophe); got: $out"
fi

# --- Arm 4c: IN-USE gate — an OPEN FILE DESCRIPTOR (cwd elsewhere) survives --
# The SAFETY header promises "no open file handle". A process can mmap/hold-open
# a file inside a scratch tree while its cwd is elsewhere and nothing in the
# tree has a recent mtime; cwd-only liveness would reap the live data. This arm
# simulates /proc/<pid>/fd/<n> pointing into a candidate, cwd unset.
reset_fixtures
mkdir -p "$FAKE_TMP/tmp.openfd/data"
dd if=/dev/zero of="$FAKE_TMP/tmp.openfd/data/blob" bs=1M count=20 status=none 2>/dev/null
find "$FAKE_TMP/tmp.openfd" -exec touch -d "-120 minutes" {} + 2>/dev/null || true
touch -d "-120 minutes" "$FAKE_TMP/tmp.openfd"
mkdir -p "$FAKE_PROC/4244/fd"
ln -sfn "$FAKE_TMP/tmp.openfd/data/blob" "$FAKE_PROC/4244/fd/3"
# no cwd symlink → liveness must come from the fd scan alone
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.openfd" ]]; then
  pass "IN-USE gate: an OPEN FD into the tree marks it in use (cwd elsewhere)"
else
  fail "reaped a tree with a live open fd inside it — data loss; got: $out"
fi
# MUTATION CONTROL: with the fd gone, the same tree IS reaped, so the arm above
# cannot pass by never reaping.
rm -rf "$FAKE_PROC/4244"
out="$(reap)"
if [[ ! -e "$FAKE_TMP/tmp.openfd" ]]; then
  pass "the same tree IS reaped once no fd points into it"
else
  fail "fd liveness never releases; got: $out"
fi

# --- Arm 5: PROTECTED paths — claude session dirs are never touched --------
# worktree-manager.sh's cleanup_claude_tmp owns that boundary; duplicating or
# contradicting it here would race a different owner.
reset_fixtures
mk_dir "claude-$UID_NOW" 20 120
out="$(reap)"
if [[ -e "$FAKE_TMP/claude-$UID_NOW" ]]; then
  pass "PROTECTED: /tmp/claude-<uid> is never reaped (owned by worktree-manager)"
else
  fail "reaped a claude session dir — contradicts cleanup_claude_tmp; got: $out"
fi

# --- Arm 5b: PROTECTED — node-compile-cache is a reusable cache, not a leak --
# worktree-manager.sh's cleanup_stale_sandbox_tmp spares it; this reaper must
# too, or a stale >=100MB V8 cache gets destroyed.
reset_fixtures
mk_dir "node-compile-cache" 20 120
out="$(reap)"
if [[ -e "$FAKE_TMP/node-compile-cache" ]]; then
  pass "PROTECTED: node-compile-cache is never reaped (reusable V8 cache)"
else
  fail "reaped node-compile-cache — contradicts cleanup_stale_sandbox_tmp; got: $out"
fi

# --- Arm 6: recursive age — old dir with a FRESH file inside survives ------
# A directory's own mtime does not change when a nested file is written, so a
# top-level -mmin test alone would delete an actively-used scratch tree.
reset_fixtures
mk_dir "tmp.freshinside" 20 120
# Touch an EXISTING file, never create a new one: creating an entry updates the
# PARENT directory's mtime too, so the top-level check would also see it as
# fresh and the arm would pass against a top-level-only implementation. The
# mutation battery caught exactly that gap in this fixture.
touch "$FAKE_TMP/tmp.freshinside/blob"
out="$(reap)"
if [[ -e "$FAKE_TMP/tmp.freshinside" ]]; then
  pass "recursive age: a stale dir containing a FRESH file is NOT reaped"
else
  fail "top-level mtime only — deleted a tree with active contents; got: $out"
fi

# --- Arm 7: dry run deletes nothing ----------------------------------------
reset_fixtures
mk_dir "tmp.dry" 20 120
# Reap detail now goes to the log sink, not stdout (#6991): the caller used to
# capture stdout and throw it away, so the journal carried zero `reaping` lines.
: > "$TESTROOT/dry.log"
out="$(guard_env env TMPFS_GUARD_DRY_RUN=1 TMPFS_GUARD_LOG_SINK="$TESTROOT/dry.log" \
  bash -c "source '$GUARD'; reap_scratch_entries" 2>&1 || true)"
if [[ -e "$FAKE_TMP/tmp.dry" ]]; then
  pass "TMPFS_GUARD_DRY_RUN=1 deletes nothing"
else
  fail "dry run deleted a file; got: $out"
fi
# The dry run must still REPORT what it would have done, or it is untestable.
if [[ "$(grep -cF -- "tmp.dry" "$TESTROOT/dry.log" || true)" -ge 1 ]]; then
  pass "dry run still reports the candidate it would reap"
else
  fail "dry run reported nothing; sink: $(cat "$TESTROOT/dry.log")"
fi

# --- Arm 8: the guard runs even when no claude tmp dir exists --------------
# Pre-existing shape: the script exited 0 immediately when /tmp/claude-<uid>
# was absent. Left as-is, the new reaper would inherit that early exit and
# silently never run on a machine without an active Claude session.
reset_fixtures
mk_dir "tmp.noclaude" 20 120
out="$(guard_env bash "$GUARD" 2>&1 || true)"
if [[ ! -e "$FAKE_TMP/tmp.noclaude" ]]; then
  pass "the scratch reaper runs even with no /tmp/claude-<uid> present"
else
  fail "reaper was skipped by the claude-dir early exit; got: $out"
fi

# --- Arm 8b: only the TOP-LEVEL entry is a reap target, never its subdirs ---
# `du -sm` summarizes each candidate to one line; a plain `du -m` descends and
# emits every subdirectory, which would enqueue non-top-level paths (a scratch
# tree's inner node_modules) for reaping. The reaper must report/reap ONLY the
# top-level scratch entry. Fixture: a stale tree with a large NESTED subdir.
reset_fixtures
mkdir -p "$FAKE_TMP/tmp.nested/inner"
dd if=/dev/zero of="$FAKE_TMP/tmp.nested/inner/blob" bs=1M count=20 status=none 2>/dev/null
find "$FAKE_TMP/tmp.nested" -exec touch -d "-120 minutes" {} + 2>/dev/null || true
touch -d "-120 minutes" "$FAKE_TMP/tmp.nested"
: > "$TESTROOT/nested.txt"
out="$(guard_env env TMPFS_GUARD_DRY_RUN=1 TMPFS_GUARD_LOG_SINK="$TESTROOT/nested.txt" \
  bash -c "source '$GUARD'; reap_scratch_entries" 2>&1 || true)"
if [[ "$(grep -cF -- "tmp.nested/inner" "$TESTROOT/nested.txt" || true)" -eq 0 ]] \
   && [[ "$(grep -cE 'would reap .*/tmp\.nested \(' "$TESTROOT/nested.txt" || true)" -ge 1 ]]; then
  pass "reaps the top-level scratch entry, never its nested subdirs (du -sm)"
else
  fail "a nested subdir was enqueued for reaping; got: $out"
fi

# --- Arm 9: ownership gate is applied --------------------------------------
# Cannot synthesize a foreign-owned file without root, so assert the gate is
# expressed in the source, anchored on the find predicate rather than a bare
# word that a comment could satisfy (cq-assert-anchor-not-bare-token).
if [[ "$(grep -cE '^[^#]*-user[[:space:]]' "$GUARD" || true)" -ge 1 ]]; then
  pass "OWNERSHIP gate: the reaper's find is -user scoped"
else
  fail "no -user predicate in the reaper — it could reap another user's files"
fi

# ===========================================================================
# #6991 — count-shaped leaks, socket liveness, log sink, return contract.
# ===========================================================================

# --- Arm 10: a socket-held directory is never reaped, in EITHER tier --------
# The fd walk is architecturally blind to unix sockets: a socket fd readlinks
# to `socket:[inode]`, never to its path. Measured 2026-07-27, /tmp's live
# Chrome IPC directory cleared ownership, top-level age, recursive age, the
# denylist AND the fd liveness scan — only the 100 MB size floor stood between
# it and deletion. The pressure tier drops that floor, so without the
# /proc/net/unix pass below, engaging pressure would kill a running browser.
reset_fixtures
mkdir -p "$FAKE_TMP/sockdir"
dd if=/dev/zero of="$FAKE_TMP/sockdir/blob" bs=1M count=20 status=none 2>/dev/null
SOCK_PATH="$FAKE_TMP/sockdir/live.sock"
python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('$SOCK_PATH'); s.listen(1)
sys.stdout.write('ready\n'); sys.stdout.flush()
time.sleep(60)
" > "$TESTROOT/sock.ready" 2>/dev/null &
SOCK_PID=$!
for _ in $(seq 1 40); do [[ -s "$TESTROOT/sock.ready" ]] && break; sleep 0.25; done
find "$FAKE_TMP/sockdir" -exec touch -d "-120 minutes" {} + 2>/dev/null || true
touch -d "-120 minutes" "$FAKE_TMP/sockdir"

if [[ -S "$SOCK_PATH" ]] && grep -qF -- "$SOCK_PATH" /proc/net/unix 2>/dev/null; then
  reap env TMPFS_GUARD_COUNT_TRIGGER=99999 >/dev/null
  if [[ -d "$FAKE_TMP/sockdir" ]]; then
    pass "SOCKET liveness: a socket-held tree is NOT reaped (normal tier)"
  else
    fail "a live socket-held tree was deleted in the normal tier"
  fi
  # A socket path CONTAINING A SPACE must be protected too. `$NF` in awk is the
  # last whitespace-separated field, so "/tmp/x/sock dir/live.sock" would yield
  # "dir/live.sock", fail the leading-slash test, and be dropped — deleting a
  # live socket-held directory. Measured before the prefix-strip fix.
  mkdir -p "$FAKE_TMP/sock dir"
  dd if=/dev/zero of="$FAKE_TMP/sock dir/blob" bs=1M count=20 status=none 2>/dev/null
  SPACE_SOCK="$FAKE_TMP/sock dir/live.sock"
  python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('$SPACE_SOCK'); s.listen(1)
sys.stdout.write('ready\n'); sys.stdout.flush()
time.sleep(60)
" > "$TESTROOT/sock2.ready" 2>/dev/null &
  SOCK2_PID=$!
  for _ in $(seq 1 40); do [[ -s "$TESTROOT/sock2.ready" ]] && break; sleep 0.25; done
  find "$FAKE_TMP/sock dir" -exec touch -d "-120 minutes" {} + 2>/dev/null || true
  touch -d "-120 minutes" "$FAKE_TMP/sock dir"
  reap >/dev/null
  if [[ -d "$FAKE_TMP/sock dir" ]]; then
    pass "SOCKET liveness: a socket path containing a SPACE is still protected"
  else
    fail "a live socket-held tree with a space in its path was deleted"
  fi
  kill "$SOCK2_PID" 2>/dev/null || true
  wait "$SOCK2_PID" 2>/dev/null || true
  # Non-vacuity: blind the seam and the SAME fixture must be deleted. Without
  # this the two assertions above could pass because of some unrelated gate.
  reap env TMPFS_GUARD_UNIX_SOCKETS=/dev/null >/dev/null
  if [[ ! -d "$FAKE_TMP/sockdir" ]]; then
    pass "SOCKET liveness is non-vacuous: blinding /proc/net/unix reaps it"
  else
    fail "blinding the socket seam changed nothing — the arm proves nothing"
  fi
else
  fail "socket fixture did not register in /proc/net/unix — arm cannot run"
  fail "socket fixture unavailable (pressure arm)"
  fail "socket fixture unavailable (non-vacuity arm)"
fi
kill "$SOCK_PID" 2>/dev/null || true
wait "$SOCK_PID" 2>/dev/null || true

# --- Arm 11: count pressure ALARMS but does NOT widen deletion -------------
# The tier that would reclaim this shape was measured to take ~1,500 authored
# artifacts with it on the operator's real /tmp, in a pass exceeding the cron
# interval. So the count signal reports and stops. These arms pin BOTH halves —
# the report happens, and nothing extra dies.
reset_fixtures
for i in $(seq 1 40); do
  mkdir -p "$FAKE_TMP/tmp.tiny$i"
  printf 'x%.0s' $(seq 1 300) > "$FAKE_TMP/tmp.tiny$i/f"
done
find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
: > "$TESTROOT/count.alarm"
seed_watermark 0
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/count.alarm" >/dev/null
remaining=$(find "$FAKE_TMP" -mindepth 1 -maxdepth 1 -name 'tmp.tiny*' | wc -l)
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/count.alarm" || true)" -ge 1 ]]; then
  pass "COUNT pressure raises an alarm the operator will see"
else
  fail "no alarm at count pressure — the #6991 incident stays silent"
fi
if [[ "$remaining" -eq 40 ]]; then
  pass "COUNT pressure does NOT widen deletion (report, never reap)"
else
  fail "count pressure deleted $((40 - remaining)) sub-floor entries — the measured-unsafe tier"
fi

# Below the trigger: no alarm at all. A healthy machine must stay quiet.
reset_fixtures
mk_dir "tmp.quiet" 1 120
: > "$TESTROOT/quiet.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=99999 TMPFS_GUARD_ALARM_FILE="$TESTROOT/quiet.alarm" >/dev/null
if [[ ! -s "$TESTROOT/quiet.alarm" ]]; then
  pass "below the trigger, no count alarm is raised"
else
  fail "spurious count alarm: $(cat "$TESTROOT/quiet.alarm")"
fi

# --- Arm 11b: an entry whose NAME contains a newline is never reaped -------
# `du -sm` emits newline-delimited records with no NUL option, so such a name
# splits into two and the read loop attributes the SIBLING's size to it —
# measured deleting a 14-byte directory because a 20 MB sibling named
# "<name>\nx" existed, with neither gate ever evaluated against it.
reset_fixtures
mkdir -p "$FAKE_TMP/victim"
printf 'precious' > "$FAKE_TMP/victim/keep"
mkdir -p "$FAKE_TMP/victim"$'\n'"x"
dd if=/dev/zero of="$FAKE_TMP/victim"$'\n'"x/blob" bs=1M count=20 status=none 2>/dev/null
find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
reap >/dev/null
if [[ -e "$FAKE_TMP/victim/keep" ]]; then
  pass "a newline-named sibling cannot cause the wrong entry to be reaped"
else
  fail "VICTIM DESTROYED — newline in a sibling name misattributed its size"
fi

# --- Arm 12: the suite must not write to the production journal ------------
# 344 of 346 `Reaped` lines in the real journal came from THIS suite's fixture
# roots. Anyone reading it to judge the guard saw a healthy reaper that had in
# fact reaped once in 14 days.
# Comment lines are stripped first. A prose mention of `logger -t` in a comment
# explaining why the sink exists would otherwise fail this assertion — the same
# false-match trap that cq-assert-anchor-not-bare-token warns about, and which
# this suite hit while being written.
logger_sites=$(grep -vE '^[[:space:]]*#' "$GUARD" | grep -cE 'logger[[:space:]]+-t' || true)
if [[ "$logger_sites" -eq 1 ]]; then
  pass "exactly one logger call site remains, inside guard_log (was 3)"
else
  fail "expected 1 logger call site (guard_log's own), found $logger_sites"
fi

reset_fixtures
mk_dir "tmp.sink" 20 120
: > "$TESTROOT/sink.log"
reap env TMPFS_GUARD_LOG_SINK="$TESTROOT/sink.log" >/dev/null
if [[ "$(grep -cF -- "tmp.sink" "$TESTROOT/sink.log" || true)" -ge 1 ]]; then
  pass "per-entry reap detail reaches the log sink (was stdout, discarded)"
else
  fail "reap detail did not reach the sink: $(cat "$TESTROOT/sink.log")"
fi

# --- Arm 13: return contract is globals, not stdout -------------------------
# `reaped="$(reap_scratch_entries)"` captured the per-entry lines AND the count
# into one multi-line string; `[[ "$reaped" -eq 0 ]]` then parsed the leading
# word `tmpfs` as a variable name and `set -u` made it FATAL. main exited 1 and
# the high-usage alarm never ran — on exactly the runs that had reaped
# something while /tmp was full.
# Comments stripped: the fix's own explanation quotes the defective
# `reaped="$(reap_scratch_entries)"` shape, and a naive grep matches that.
subst_sites=$(grep -vE '^[[:space:]]*#' "$GUARD" \
  | grep -cE '\$\((reap_scratch_entries|reap_output_files)' || true)
if [[ "$subst_sites" -eq 0 ]]; then
  pass "no command substitution captures the reapers (globals contract)"
else
  fail "a reaper is still called in \$( ) in code — found $subst_sites"
fi

reset_fixtures
mk_dir "tmp.exit" 20 120
: > "$TESTROOT/exit.log"
if guard_env env TMPFS_GUARD_USAGE_WARN_PCT=0 TMPFS_GUARD_LOG_SINK="$TESTROOT/exit.log" \
     TMPFS_GUARD_ALARM_FILE="$TESTROOT/alarm.log" bash "$GUARD" >/dev/null 2>&1; then
  pass "a run that reaps >=1 entry at high usage exits 0 (was: unbound variable)"
else
  fail "the reaping-at-high-usage run still aborts"
fi

# --- Arm 14: liveness line on every run, alarm only when alarming ----------
if [[ "$(grep -cE 'run complete' "$TESTROOT/exit.log" || true)" -ge 1 ]]; then
  pass "every run emits a liveness line (silent != not running)"
else
  fail "no liveness line: $(cat "$TESTROOT/exit.log")"
fi

# A run that REAPED something is not an alarm — nothing should be recorded.
if [[ ! -s "$TESTROOT/alarm.log" ]]; then
  pass "a run that reclaimed space records no alarm"
else
  fail "an alarm was recorded on a successful reap: $(cat "$TESTROOT/alarm.log")"
fi

# --- Arm 15: the alarm fires and is capped ---------------------------------
# High usage AND nothing reapable — the 94-times-in-14-days case.
reset_fixtures
: > "$TESTROOT/alarm2.log"
guard_env env TMPFS_GUARD_USAGE_WARN_PCT=0 TMPFS_GUARD_LOG_SINK=/dev/null \
  TMPFS_GUARD_ALARM_FILE="$TESTROOT/alarm2.log" bash "$GUARD" >/dev/null 2>&1 || true
if [[ "$(grep -cE 'nothing reapable' "$TESTROOT/alarm2.log" || true)" -ge 1 ]]; then
  pass "high usage with nothing reapable writes a durable alarm record"
else
  fail "the alarm reached no durable channel: $(cat "$TESTROOT/alarm2.log")"
fi

# Size cap: drive it past the ceiling and confirm it stops growing.
for _ in $(seq 1 40); do
  guard_env env TMPFS_GUARD_USAGE_WARN_PCT=0 TMPFS_GUARD_LOG_SINK=/dev/null \
    TMPFS_GUARD_ALARM_FILE="$TESTROOT/alarm2.log" bash "$GUARD" >/dev/null 2>&1 || true
done
alarm_lines=$(wc -l < "$TESTROOT/alarm2.log")
if [[ "$alarm_lines" -le 200 ]]; then
  pass "alarm file size cap holds ($alarm_lines lines <= 200)"
else
  fail "alarm file grew unbounded ($alarm_lines lines)"
fi

# --- Arm 16: notify-send is gone -------------------------------------------
# A no-op under cron (no DBUS session), additionally swallowed by
# `2>/dev/null || true`. Keeping it as a best-effort extra is how the dead
# channel came to exist.
if [[ "$(grep -cE '^[^#]*notify-send' "$GUARD" || true)" -eq 0 ]]; then
  pass "notify-send is gone (it was a silent no-op under cron)"
else
  fail "notify-send call sites remain"
fi

# --- Arm 17: alarm fires on COUNT alone, before disk pressure --------------
# The #6991 incident was 17,898 entries at 29% blocks. Gating the alarm on the
# 70% usage threshold — as the reap tier is gated — would have left that
# incident silent. Alarm early (free), reap late (destructive).
reset_fixtures
for i in $(seq 1 12); do
  mkdir -p "$FAKE_TMP/tmp.c$i"; printf 'x' > "$FAKE_TMP/tmp.c$i/f"
done
find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
: > "$TESTROOT/lowusage.alarm"
seed_watermark 0
reap env TMPFS_GUARD_COUNT_TRIGGER=5 TMPFS_GUARD_USAGE_WARN_PCT=70 \
  TMPFS_GUARD_ALARM_FILE="$TESTROOT/lowusage.alarm" >/dev/null
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/lowusage.alarm" || true)" -ge 1 ]]; then
  pass "COUNT alarm fires below the usage threshold (the #6991 state)"
else
  fail "no alarm at count pressure with low usage — the filed incident stays silent"
fi
# ...and the destructive tier did NOT engage at that usage.
remaining=$(find "$FAKE_TMP" -mindepth 1 -maxdepth 1 -name 'tmp.c*' | wc -l)
if [[ "$remaining" -eq 12 ]]; then
  pass "REAP tier stays disengaged below the usage threshold (alarm != delete)"
else
  fail "pressure reaping ran at low usage; $remaining/12 left"
fi

# --- Arm 18: a healthy run clears a stale alarm ----------------------------
# Without this the operator must hand-delete the file, so one resolved incident
# banners every future session forever.
reset_fixtures
printf '2026-01-01T00:00:00Z old alarm\n' > "$TESTROOT/stale.alarm"
guard_env env TMPFS_GUARD_USAGE_WARN_PCT=101 TMPFS_GUARD_COUNT_TRIGGER=999999 \
  TMPFS_GUARD_ALARM_FILE="$TESTROOT/stale.alarm" bash "$GUARD" >/dev/null 2>&1 || true
if [[ ! -f "$TESTROOT/stale.alarm" ]]; then
  pass "a healthy run clears the alarm file (no manual operator step)"
else
  fail "alarm file survived a healthy run: $(cat "$TESTROOT/stale.alarm")"
fi

# --- Arm 19: the heartbeat is written on every completed run ---------------
# This is the ONLY signal that can report "the cron entry stopped": an absent
# alarm file cannot, because a dead guard writes no alarms.
reset_fixtures
rm -f "$TESTROOT/hb"
guard_env env TMPFS_GUARD_HEARTBEAT_FILE="$TESTROOT/hb" bash "$GUARD" >/dev/null 2>&1 || true
if [[ -s "$TESTROOT/hb" ]] && [[ "$(grep -cF -- 'run complete' "$TESTROOT/hb" || true)" -ge 1 ]]; then
  pass "heartbeat written on a completed run (staleness is detectable)"
else
  fail "no heartbeat written; SessionStart cannot detect a stopped cron entry"
fi
# Overwrite, not append — an append would grow without bound.
guard_env env TMPFS_GUARD_HEARTBEAT_FILE="$TESTROOT/hb" bash "$GUARD" >/dev/null 2>&1 || true
if [[ "$(wc -l < "$TESTROOT/hb")" -eq 1 ]]; then
  pass "heartbeat is overwritten, not appended"
else
  fail "heartbeat grew to $(wc -l < "$TESTROOT/hb") lines"
fi

# --- Arm 20: alarm + heartbeat paths agree with the SessionStart reader ----
# The guard WRITES these paths and session-rules-loader.sh READS them, each
# defaulting the literal independently. A one-sided edit silently disables the
# only channel by which the alarm reaches a human — the dead-channel class
# #6991 exists to fix — and no other test would notice.
LOADER="$REPO_ROOT/.claude/hooks/session-rules-loader.sh"
for var in TMPFS_GUARD_ALARM_FILE TMPFS_GUARD_HEARTBEAT_FILE; do
  g_default=$(grep -oE "\\\$\{${var}:-[^}]*\}" "$GUARD" | head -1)
  l_default=$(grep -oE "\\\$\{${var}:-[^}]*\}" "$LOADER" | head -1)
  if [[ -n "$g_default" && "$g_default" == "$l_default" ]]; then
    pass "$var default matches between the guard and the SessionStart reader"
  else
    fail "$var default drifted: guard='$g_default' loader='$l_default'"
  fi
done

# --- Arm 21 (AC-A1): the count alarm is a re-floored watermark -------------
# COUNT_TRIGGER=5000 against 20,582 legacy entries means the guard alarms every
# five minutes, forever, before any reaper exists. Rebaselining is not a matter
# of raising the constant: a FROZEN ship-time baseline fails two ways this arm
# pins directly.
#
#   (c) it goes BLIND while the legacy drains — a new leak of thousands reads
#       as "below baseline" for the whole drain window, i.e. exactly this
#       feature's own validation period.
#   (d) it is permanently DISARMED by a reboot — /tmp is tmpfs, so a stored
#       ~20,500 sits against an actual ~0 and nothing can alarm until a new
#       leak regrows past 20,500. That is the inverse of the bug, and it is
#       invisible because the failure surface is silence.
#
# A watermark re-floored to min(stored, current) every run follows the drain
# down and survives the reboot. Arms (c) and (d) are the non-vacuous core.
wm() { cat "$TESTROOT/count-watermark" 2>/dev/null || echo MISSING; }
mk_many() {  # prefix, count — tiny, old, sub-floor entries (never reap targets)
  local p="$1" n="$2" i
  for ((i = 1; i <= n; i++)); do
    mkdir -p "$FAKE_TMP/$p$i"; printf 'x' > "$FAKE_TMP/$p$i/f"
  done
  find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
}

# (a) legacy present, zero orphans, no prior watermark ⇒ SEED, and stay quiet.
reset_fixtures
rm -f "$TESTROOT/count-watermark"
mk_many "legacy" 30
: > "$TESTROOT/wm.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/wm.alarm" >/dev/null
if [[ ! -s "$TESTROOT/wm.alarm" ]]; then
  pass "AC-A1(a): legacy backlog alone does NOT alarm (absolute count is not pressure)"
else
  fail "AC-A1(a): legacy alarmed on absolute count — the every-5-min alarm survives: $(cat "$TESTROOT/wm.alarm")"
fi
if [[ "$(wm)" == "30" ]]; then
  pass "AC-A1(a): first run seeds the watermark from the current count"
else
  fail "AC-A1(a): watermark seeded to '$(wm)', expected 30"
fi

# (b) the legacy drains ⇒ the persisted watermark DECREASES to follow it.
reset_fixtures
mk_many "legacy" 12
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/wm.alarm" >/dev/null
if [[ "$(wm)" == "12" ]]; then
  pass "AC-A1(b): the watermark ratchets DOWN as the legacy drains"
else
  fail "AC-A1(b): watermark is '$(wm)' after draining 30 -> 12; a frozen baseline would still read 30"
fi

# (c) growth above the NEW (drained) watermark ⇒ ALARMS.
# A frozen ship-time baseline of 30 would swallow this entirely: 27 < 30.
reset_fixtures
mk_many "legacy" 27
: > "$TESTROOT/wm.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/wm.alarm" >/dev/null
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/wm.alarm" || true)" -ge 1 ]]; then
  pass "AC-A1(c): growth above the drained watermark ALARMS (a frozen baseline is blind here)"
else
  fail "AC-A1(c): 12 -> 27 raised no alarm; the guard went blind during the drain window"
fi
if [[ "$(wm)" == "12" ]]; then
  pass "AC-A1(c): growth does NOT raise the watermark (it only ever ratchets down)"
else
  fail "AC-A1(c): watermark rose to '$(wm)'; a rising floor self-silences on every leak"
fi

# (d) a /tmp reset to ~0 (reboot; tmpfs) ⇒ re-floor, and do NOT disarm.
reset_fixtures
mk_many "post_reboot" 1
: > "$TESTROOT/wm.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/wm.alarm" >/dev/null
if [[ "$(wm)" == "1" ]]; then
  pass "AC-A1(d): the watermark re-floors after a reboot clears tmpfs"
else
  fail "AC-A1(d): watermark stuck at '$(wm)' after reset; the alarm is disarmed until a leak regrows past it"
fi
# ...and the re-floored guard still fires. This is the half that proves (d) is
# not merely "the number got smaller": a frozen baseline of 12 would NOT alarm
# at 16, so this assertion fails against the implementation (d) rules out.
reset_fixtures
mk_many "post_reboot" 16
: > "$TESTROOT/wm.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/wm.alarm" >/dev/null
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/wm.alarm" || true)" -ge 1 ]]; then
  pass "AC-A1(d): a post-reboot leak ALARMS against the re-floored watermark"
else
  fail "AC-A1(d): post-reboot leak stayed silent — the reboot permanently disarmed the guard"
fi

# --- Arm 22: the count is over UNOWNED entries only ------------------------
# Entries carrying the declared ownership schema are PR 1's reclamation target,
# so counting them here would re-arm the same forever-alarm the moment the
# allocator ships. Excluding them is what makes A.1 "count only entries that do
# not parse as the schema" true.
reset_fixtures
seed_watermark 0
for i in $(seq 1 30); do
  mkdir -p "$FAKE_TMP/soleur-run.$$.abcdef$(printf '%02d' "$i")"
done
find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
: > "$TESTROOT/schema.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/schema.alarm" >/dev/null
if [[ ! -s "$TESTROOT/schema.alarm" ]]; then
  pass "schema-named roots are excluded from the count (PR 1 reclaims them; the alarm ignores them)"
else
  fail "schema-named roots counted as a leak — the alarm re-arms forever once the allocator ships"
fi
# MUTATION CONTROL: the SAME count of non-schema entries DOES alarm, so the arm
# above cannot pass by the alarm simply never firing.
reset_fixtures
seed_watermark 0
mk_many "unowned" 30
: > "$TESTROOT/schema.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/schema.alarm" >/dev/null
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/schema.alarm" || true)" -ge 1 ]]; then
  pass "the same count of NON-schema entries does alarm (arm 22 is not vacuous)"
else
  fail "30 unowned entries above a 0 floor raised no alarm — the count path is dead"
fi
# ...and a near-miss name is NOT treated as schema (anchored, fixed-arity).
reset_fixtures
seed_watermark 0
for i in $(seq 1 30); do
  mkdir -p "$FAKE_TMP/soleur-run.notapid.abcdef$(printf '%02d' "$i")"
done
find "$FAKE_TMP" -mindepth 1 -exec touch -d "-120 minutes" {} + 2>/dev/null || true
: > "$TESTROOT/nearmiss.alarm"
reap env TMPFS_GUARD_COUNT_TRIGGER=10 TMPFS_GUARD_ALARM_FILE="$TESTROOT/nearmiss.alarm" >/dev/null
if [[ "$(grep -cF -- 'count-shaped leak' "$TESTROOT/nearmiss.alarm" || true)" -ge 1 ]]; then
  pass "a near-miss name (non-numeric pid) does NOT parse as schema"
else
  fail "near-miss name accepted as schema — the exclusion is a substring match, not a parse"
fi

# --- Minimum-cardinality guard ---------------------------------------------
if [[ "$pass_n" -lt 49 ]]; then
  fail "cardinality guard: only $pass_n assertions ran (expected >= 49)"
fi

echo "=== tmpfs-guard: $pass_n passed, $fails failed ==="
[[ "$fails" -eq 0 ]] || exit 1
