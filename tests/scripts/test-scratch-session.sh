#!/usr/bin/env bash
# test-scratch-session.sh — arms for soleur_scratch_session_begin /
# soleur_scratch_mark_owned (scripts/lib/scratch-root.sh) and Reaper 3 +
# quarantine drain in scripts/tmpfs-guard.sh (#7004).
#
# This suite exists because the reaper DELETES/MOVES files. Every conjunct is
# asserted in BOTH directions under sentinel bases. Nothing outside TESTROOT /
# FAKE_PROC is ever a candidate.
#
# AUTHORING CONSTRAINTS (see work/SKILL.md):
#   - Never `producer | grep -q` under pipefail; grep a FILE or use `grep -c`.
#   - Deliberately-nonzero commands inside `$(...)` need `|| true` under set -e.
#   - `cases` increments at the CALL SITE, never inside pass()/fail().

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/tmpfs-guard.sh"
LIB="$REPO_ROOT/scripts/lib/scratch-root.sh"

pass_n=0; fails=0; cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t soleur-scratch-session.XXXXXXXX)"
# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# it); do not reword.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
cleanup() { assert_fixture_dir "$TESTROOT"; rm -rf "$TESTROOT" "${DISK_BASE:-}"; }
trap cleanup EXIT
# Isolate the purge ledger/state from the operator home: unisolated arms appended rows naming this
# suite fixtures to the real ~/.local/state/soleur/tmp-purge-ledger.log (review of #9339).
export SOLEUR_PURGE_LEDGER="$TESTROOT/tmp-purge-ledger.log" XDG_STATE_HOME="$TESTROOT/xdg-state"

# Fixture-env adoption (#7833/#7849): fixture git writes run under the
# synthesized identity + hermetic config + discovery ceiling, not the
# ambient developer environment.
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
git_fixture_env "$TESTROOT" || { echo "FATAL: git_fixture_env refused fixture root $TESTROOT" >&2; exit 2; }

# Under the battery, test-all.sh exports its OWN session root — the nested
# no-op is correct behaviour, but every begin arm below must start un-nested
# or it measures the parent's root, not the allocation under test.
unset SOLEUR_SCRATCH_SESSION_ROOT SOLEUR_SCRATCH_OWNER_PID SOLEUR_SCRATCH_BASE

[[ -f "$GUARD" && -f "$LIB" ]] || { echo "ERROR: fixture targets missing" >&2; exit 1; }

# TESTROOT lives under /tmp — tmpfs on the reference host → exercises the
# direct-delete arm. DISK_BASE sits on a real filesystem to exercise the
# quarantine arm; if no non-tmpfs writable dir exists the arm is skipped.
DISK_BASE=""
for cand in /var/tmp "${XDG_CACHE_HOME:-$HOME/.cache}" "$HOME"; do
  if [[ -d "$cand" && -w "$cand" ]]; then
    fst="$(findmnt -no FSTYPE --target "$cand" 2>/dev/null || true)"
    if [[ "$fst" != "tmpfs" && "$fst" != "ramfs" && -n "$fst" ]]; then
      DISK_BASE="$(mktemp -d -p "$cand" soleur-scratch-disk.XXXXXXXX)"; break
    fi
  fi
done

FAKE_TMP="$TESTROOT/tmpfs-base"
FAKE_PROC="$TESTROOT/proc"
LOGSINK="$TESTROOT/guard.log"
mkdir -p "$FAKE_TMP" "$FAKE_PROC"
[[ -n "$DISK_BASE" ]] || echo "  [skip] no non-tmpfs writable dir — disk-class arm untested"

guard_env() {
  env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" \
    TMPFS_GUARD_TMP="$FAKE_TMP" TMPFS_GUARD_PROC="$FAKE_PROC" \
    TMPFS_GUARD_SCRATCH_BASES="${SCRATCH_BASES-$FAKE_TMP $DISK_BASE}" \
    TMPFS_GUARD_LOG_SINK="$LOGSINK" \
    TMPFS_GUARD_ALARM_FILE="$TESTROOT/alarm.log" \
    TMPFS_GUARD_HEARTBEAT_FILE="$TESTROOT/hb" \
    TMPFS_GUARD_WATERMARK_FILE="$TESTROOT/wm" \
    TMPFS_GUARD_LOCKFILE="$TESTROOT/lock" \
    TMPFS_GUARD_DRY_RUN="${DRY_RUN:-0}" \
    TMPFS_GUARD_SCRATCH_AGE_MIN="${AGE_FLOOR:-0}" \
    TMP_CLASSIFY_AGE_FLOOR_MIN="${TC_FLOOR:-0}" \
    TMPFS_GUARD_QUAR_TTL_MIN="${QUAR_TTL:-0}" \
    TMPFS_GUARD_QUAR_WT_TTL_MIN="${QUAR_TTL:-0}" \
    TMP_CLASSIFY_RETAIN_DIR="$TESTROOT/retain" \
    "$@"
}
reap3() { guard_env "$@" bash -c "source '$GUARD'; reap_orphan_scratch_roots" 2>&1 || true; }
drain() { guard_env "$@" bash -c "source '$GUARD'; drain_scratch_quarantine" 2>&1 || true; }

# The fake procfs carries a self/ns/pid link so marker `ns=` fields verify
# against it — marker verification now REQUIRES a matching namespace (a
# foreign-namespace marker vetoes even a matching schema name).
FAKE_NS='pid:[42424242]'
mk_fake_proc() {
  rm -rf "$FAKE_PROC"; mkdir -p "$FAKE_PROC/self/ns"
  ln -s "$FAKE_NS" "$FAKE_PROC/self/ns/pid"
}
mk_marker() { # dir pid [ns]
  printf 'pid=%s\nschema=1\nns=%s\n' "$2" "${3:-$FAKE_NS}" > "$1/.soleur-owned"
}

reset_fixtures() {
  assert_fixture_dir "$FAKE_TMP"; rm -rf "$FAKE_TMP"; mkdir -p "$FAKE_TMP"
  [[ -n "$DISK_BASE" ]] && { find "$DISK_BASE" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true; }
  mk_fake_proc
  : > "$LOGSINK"
}
reset_fixtures

echo "=== test-scratch-session ==="

# --- Arm 1: allocator -------------------------------------------------------------
out="$(bash -c "
  set -euo pipefail
  source '$LIB'
  soleur_scratch_session_begin '$FAKE_TMP'
  printf 'ROOT=%s\nTMPDIR=%s\n' \"\$SOLEUR_SCRATCH_SESSION_ROOT\" \"\$TMPDIR\"
  [[ -f \"\$SOLEUR_SCRATCH_SESSION_ROOT/.soleur-owned\" ]] && echo MARKER
  grep -q \"pid=\$\$\" \"\$SOLEUR_SCRATCH_SESSION_ROOT/.soleur-owned\" && echo MARKER_PID
  grep -q 'ns=pid:\[' \"\$SOLEUR_SCRATCH_SESSION_ROOT/.soleur-owned\" && echo MARKER_NS
  mktemp -d -t child.XXXXXXXX >/dev/null && echo CHILD_OK
" 2>&1)"

cases=$((cases + 1)); printf '%s' "$out" | grep -q "ROOT=$FAKE_TMP/soleur-run\." \
  && pass "begin allocates soleur-run.<pid>.* under base" || fail "begin root: $out"
cases=$((cases + 1)); printf '%s' "$out" | grep -q "TMPDIR=$FAKE_TMP/soleur-run\." \
  && pass "begin exports TMPDIR at the root" || fail "TMPDIR export: $out"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'MARKER' \
  && pass "begin writes .soleur-owned" || fail "marker missing"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'MARKER_PID' \
  && pass "marker carries top-level pid" || fail "marker pid wrong"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'MARKER_NS' \
  && pass "marker carries ns discriminator" || fail "marker ns missing"
# child mktemp lands INSIDE the root (TMPDIR redirect) — verify via a follow-up probe
cases=$((cases + 1)); child="$(bash -c "
  set -euo pipefail; source '$LIB'; soleur_scratch_session_begin '$FAKE_TMP'
  mktemp -d -t child.XXXXXXXX
" 2>/dev/null)"; [[ "$child" == "$FAKE_TMP"/soleur-run.*/* ]] \
  && pass "descendant mktemp lands inside the session root" || fail "child outside root: $child"

# subshell refusal
cases=$((cases + 1)); rc=0; bash -c "source '$LIB'; r=\$(soleur_scratch_session_begin '$FAKE_TMP')" >/dev/null 2>&1 || rc=$?
[[ "$rc" != "0" ]] && pass "begin inside \$() subshell refuses" || fail "subshell begin allowed"

# nested begin no-ops
cases=$((cases + 1)); out="$(bash -c "
  set -euo pipefail; source '$LIB'
  soleur_scratch_session_begin '$FAKE_TMP'
  first=\"\$SOLEUR_SCRATCH_SESSION_ROOT\"
  soleur_scratch_session_begin '$TESTROOT/other'
  printf '%s' \"\$SOLEUR_SCRATCH_SESSION_ROOT\"; [[ \"\$SOLEUR_SCRATCH_SESSION_ROOT\" == \"\$first\" ]] && echo ' SAME'
" 2>&1)"; printf '%s' "$out" | grep -q 'SAME' \
  && pass "nested begin no-ops (parent root governs)" || fail "nested begin allocated: $out"

# cleanup deletes the root (shape-pinned)
cases=$((cases + 1)); bash -c "
  set -euo pipefail; source '$LIB'
  soleur_scratch_session_begin '$FAKE_TMP'
  echo \"\$SOLEUR_SCRATCH_SESSION_ROOT\" > '$TESTROOT/rootpath'
  _soleur_scratch_cleanup
" >/dev/null 2>&1
rootp="$(cat "$TESTROOT/rootpath")"
[[ ! -d "$rootp" ]] && pass "cleanup deletes the session root" || fail "cleanup left $rootp"

# cleanup refuses a non-schema TMPDIR shape
cases=$((cases + 1)); mkdir -p "$FAKE_TMP/not-schema"; bash -c "
  set -euo pipefail; source '$LIB'
  SOLEUR_SCRATCH_SESSION_ROOT='$FAKE_TMP/not-schema'
  SOLEUR_SCRATCH_OWNER_PID=\"\$\$\"
  _soleur_scratch_cleanup
" >/dev/null 2>&1
[[ -d "$FAKE_TMP/not-schema" ]] && pass "cleanup refuses non-schema root" || fail "cleanup deleted non-schema dir"

# cleanup never deletes an INHERITED root — the exported owner pid belongs to
# the parent; a child's EXIT trap must leave the parent's live root alone.
# The child runs as a SCRIPT FILE — nested `bash -c` quoting can pre-expand
# `$$` in the parent, which would mask the very conjunct under test.
cat > "$TESTROOT/child-cleanup.sh" <<EOF
#!/usr/bin/env bash
source '$LIB'
_soleur_scratch_cleanup
EOF
cases=$((cases + 1)); bash -c "
  set -euo pipefail; source '$LIB'
  soleur_scratch_session_begin '$FAKE_TMP'
  echo \"\$SOLEUR_SCRATCH_SESSION_ROOT\" > '$TESTROOT/inh-rootpath'
  bash '$TESTROOT/child-cleanup.sh'
" >/dev/null 2>&1
rootp="$(cat "$TESTROOT/inh-rootpath")"
[[ -d "$rootp" ]] && pass "inherited root survives child cleanup" || fail "child cleanup deleted parent root"
rm -rf "$rootp" 2>/dev/null || true

# mark_owned refuses to follow a pre-planted marker symlink (arbitrary-write pin)
cases=$((cases + 1)); mkdir -p "$FAKE_TMP/evil-owned"; : > "$TESTROOT/innocent-file"
ln -s "$TESTROOT/innocent-file" "$FAKE_TMP/evil-owned/.soleur-owned"
rc=0; bash -c "
  set -euo pipefail; source '$LIB'
  soleur_scratch_mark_owned '$FAKE_TMP/evil-owned'
" >/dev/null 2>&1 || rc=$?
[[ "$rc" != "0" && -L "$FAKE_TMP/evil-owned/.soleur-owned" && -f "$TESTROOT/innocent-file" ]] \
  && pass "mark_owned refuses pre-planted marker symlink" || fail "mark_owned followed symlink"

# mark_owned writes a valid marker; owner_root form resolves
cases=$((cases + 1)); mkdir -p "$FAKE_TMP/fixture-owned"; bash -c "
  set -euo pipefail; source '$LIB'
  soleur_scratch_session_begin '$FAKE_TMP'
  soleur_scratch_mark_owned '$FAKE_TMP/fixture-owned'
" >/dev/null 2>&1
grep -q 'pid=' "$FAKE_TMP/fixture-owned/.soleur-owned" \
  && pass "mark_owned writes harness-pid marker" || fail "mark_owned marker missing pid"

# --- Arm 2: Reaper 3 — dead vs live, per base ---------------------------------------
reset_fixtures
DEAD=424242; LIVE=434343; mkdir -p "$FAKE_PROC/$LIVE"
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.deadcode1"; : > "$FAKE_TMP/soleur-run.${DEAD}.deadcode1/x"
mkdir -p "$FAKE_TMP/soleur-run.${LIVE}.livecode1"; : > "$FAKE_TMP/soleur-run.${LIVE}.livecode1/x"
out="$(reap3)"

cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/soleur-run.${DEAD}.deadcode1" ]] \
  && pass "dead-owner schema root deleted on tmpfs base" || fail "dead root retained: $out"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${LIVE}.livecode1" ]] \
  && pass "live-owner schema root retained" || fail "live root reaped"
cases=$((cases + 1)); grep -q 'SOLEUR_TMP_REAP' "$LOGSINK" \
  && pass "reaper emits SOLEUR_TMP_REAP telemetry" || fail "telemetry missing"

# marker-bearing dir, dead owner → quarantined (a self-declared marker is
# weaker attribution than the creation-time schema name — it quarantines on
# EVERY base, tmpfs included, so restore can undo a bad verdict)
reset_fixtures
mkdir -p "$FAKE_TMP/fixture-tree.abcdef"; mk_marker "$FAKE_TMP/fixture-tree.abcdef" "$DEAD"; : > "$FAKE_TMP/fixture-tree.abcdef/x"
out="$(reap3)"
cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/fixture-tree.abcdef" && -d "$FAKE_TMP/soleur-quarantine.$(id -u)/scratch/fixture-tree.abcdef" ]] \
  && pass "dead-owner marker dir quarantined (even on tmpfs)" || fail "marker dir mishandled: $out"

# foreign-namespace marker VETOES the schema name — the container-producer
# case: a dead-in-container pid can collide with a live host pid, so the
# schema name alone must never suffice when a marker declares a foreign ns.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.foreignns1"; mk_marker "$FAKE_TMP/soleur-run.${DEAD}.foreignns1" "$DEAD" 'pid:[99999999]'
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.foreignns1" ]] \
  && pass "foreign-ns marker vetoes schema name" || fail "foreign-ns schema root reaped: $out"

# dead-owner schema root with a live handle surviving in a descendant's
# environ — the reparented-child case the environ pass exists for.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.envheld01"; : > "$FAKE_TMP/soleur-run.${DEAD}.envheld01/x"
mkdir -p "$FAKE_PROC/555"; printf 'TMPDIR=%s\0' "$FAKE_TMP/soleur-run.${DEAD}.envheld01" > "$FAKE_PROC/555/environ"
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.envheld01" ]] \
  && pass "environ handle retains dead-owner root" || fail "environ-held root reaped"

# mmap handle: a mapped file inside the tree marks the top dir in-use.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.mmapheld1"; : > "$FAKE_TMP/soleur-run.${DEAD}.mmapheld1/lib.so"
mkdir -p "$FAKE_PROC/556/map_files"; ln -s "$FAKE_TMP/soleur-run.${DEAD}.mmapheld1/lib.so" "$FAKE_PROC/556/map_files/7f000000-7f001000"
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.mmapheld1" ]] \
  && pass "mmap handle retains dead-owner root" || fail "mmap-held root reaped"

# unix-socket handle: a live socket path beneath the tree retains it.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.sockheld1"
mkdir -p "$FAKE_PROC/net"
printf 'Num RefCount Protocol Flags Type St Inode Path\n0 00000000 0 0 0 2 999 %s/sock\n' "$FAKE_TMP/soleur-run.${DEAD}.sockheld1" > "$FAKE_PROC/net/unix"
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.sockheld1" ]] \
  && pass "unix-socket path retains dead-owner root" || fail "socket-held root reaped"
rm -rf "$FAKE_PROC/net"

# a schema-named root containing a nested .git tree is registry-relevant —
# never deleted by the scratch arm (nested-worktree corruption guard).
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.nestgit01/wt"; printf 'gitdir: /nonexistent\n' > "$FAKE_TMP/soleur-run.${DEAD}.nestgit01/wt/.git"
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.nestgit01" ]] \
  && pass "schema root with nested .git retained" || fail "nested-git root reaped"

# fresh content retains even with a dead owner
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.freshtree1"; : > "$FAKE_TMP/soleur-run.${DEAD}.freshtree1/x"
out="$(SCRATCH_BASES="$FAKE_TMP" AGE_FLOOR=999999 reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.freshtree1" ]] \
  && pass "fresh tree retained despite dead owner" || fail "fresh tree reaped"

# --- Arm 3: disk-class base → quarantine, not delete ---------------------------------
if [[ -n "$DISK_BASE" ]]; then
  reset_fixtures
  mkdir -p "$DISK_BASE/soleur-run.${DEAD}.diskdead1"; : > "$DISK_BASE/soleur-run.${DEAD}.diskdead1/x"
  out="$(reap3)"
  cases=$((cases + 1)); [[ -d "$DISK_BASE/soleur-quarantine.$(id -u)/scratch/soleur-run.${DEAD}.diskdead1" ]] \
    && pass "disk-class base quarantines (no direct delete)" || fail "disk arm: $out"

  # drain: TTL 0 deletes quarantined entries
  out="$(QUAR_TTL=0 drain)"
  cases=$((cases + 1)); [[ ! -d "$DISK_BASE/soleur-quarantine.$(id -u)/scratch/soleur-run.${DEAD}.diskdead1" ]] \
    && pass "TTL drain deletes quarantined entries" || fail "drain no-op: $out"

  # drain dwell is quarantine-ARRIVAL (ctime), not content age — a stale tree
  # moved in seconds ago must NOT drain: the recovery window is measured from
  # the move, or it collapses to ~0 for the stale backlog.
  reset_fixtures
  mkdir -p "$DISK_BASE/soleur-run.${DEAD}.dwellage1"; : > "$DISK_BASE/soleur-run.${DEAD}.dwellage1/x"
  touch -d '-20000 minutes' "$DISK_BASE/soleur-run.${DEAD}.dwellage1/x" "$DISK_BASE/soleur-run.${DEAD}.dwellage1"
  reap3 >/dev/null 2>&1 || true
  [[ -d "$DISK_BASE/soleur-quarantine.$(id -u)/scratch/soleur-run.${DEAD}.dwellage1" ]] || { fail "dwell fixture not quarantined"; }
  out="$(QUAR_TTL=999999 drain)"
  cases=$((cases + 1)); [[ -d "$DISK_BASE/soleur-quarantine.$(id -u)/scratch/soleur-run.${DEAD}.dwellage1" ]] \
    && pass "drain dwell counts from arrival, not content mtime" || fail "drain used content mtime: $out"
fi

# --- Arm 4: fail-closed surfaces ------------------------------------------------------
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.guardtest1"
# empty base list → no reap
out="$(SCRATCH_BASES='' reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.guardtest1" ]] \
  && pass "empty SCRATCH_BASES → no reap (fail closed)" || fail "empty bases reaped"
# unreadable procfs → no reap
out="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" \
  TMPFS_GUARD_TMP="$FAKE_TMP" TMPFS_GUARD_PROC="$TESTROOT/nonexistent-proc" \
  TMPFS_GUARD_SCRATCH_BASES="$FAKE_TMP" TMPFS_GUARD_LOG_SINK="$LOGSINK" \
  TMPFS_GUARD_ALARM_FILE="$TESTROOT/alarm2.log" TMPFS_GUARD_HEARTBEAT_FILE="$TESTROOT/hb2" \
  TMPFS_GUARD_WATERMARK_FILE="$TESTROOT/wm2" TMPFS_GUARD_LOCKFILE="$TESTROOT/lock2" \
  bash -c "source '$GUARD'; reap_orphan_scratch_roots" 2>&1 || true)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.guardtest1" ]] \
  && pass "unreadable procfs → no reap (fail closed)" || fail "degraded proc reaped"
# DRY_RUN inert
out="$(DRY_RUN=1 reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.guardtest1" ]] \
  && pass "DRY_RUN reaps nothing" || fail "dry-run reaped"

# --- Arm 5: foreign process never reaped -----------------------------------------------
reset_fixtures
# a foreign-uid candidate is invisible to the -user scope (simulated: dir owned by us,
# but a NON-soleur-run name carrying a marker owned by us still parses — the pin is
# that a NON-marker, non-schema dir is never a candidate)
mkdir -p "$FAKE_TMP/random-dir"; : > "$FAKE_TMP/random-dir/x"
mkdir -p "$FAKE_TMP/tmp.nonschema999"; : > "$FAKE_TMP/tmp.nonschema999/x"
out="$(reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/random-dir" && -d "$FAKE_TMP/tmp.nonschema999" ]] \
  && pass "non-schema non-marker dirs never touched" || fail "foreign dir reaped"

# --- Arm 6: session-start sweep (worktree-manager.sh) -----------------------------------
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
SWEEP_STATE="$TESTROOT/sweep-state"
GITROOT_SWEEP="$TESTROOT/sweep-gitrepos"
sweep() {
  env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" \
    SOLEUR_SWEEP_BASES="${SWEEP_BASES:-$FAKE_TMP}" SOLEUR_SWEEP_AGE_MIN=0 \
    SOLEUR_SWEEP_WT_AGE_MIN=0 SOLEUR_SWEEP_WT_CAP="${SOLEUR_SWEEP_WT_CAP:-50}" \
    SOLEUR_SWEEP_TIMEBOX_S="${SOLEUR_SWEEP_TIMEBOX_S:-10}" \
    XDG_STATE_HOME="$SWEEP_STATE" TMP_CLASSIFY_PROC="${TC_PROC_OVERRIDE:-/proc}" \
    TMP_CLASSIFY_RETAIN_DIR="$TESTROOT/retain" \
    bash -c "source '$WM' >/dev/null 2>&1 || true; sweep_orphan_scratch_dirs" 2>&1 || true
}

# dead schema root reclaimed; protected/unattributable untouched
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.sweepdead1"; : > "$FAKE_TMP/soleur-run.${DEAD}.sweepdead1/x"
mkdir -p "$FAKE_TMP/soleur-run.${LIVE}.sweeplive1"; mkdir -p "$FAKE_PROC/$LIVE"
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep)"
cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/soleur-run.${DEAD}.sweepdead1" ]] \
  && pass "sweep reaps dead schema root" || fail "sweep retained dead root: $out"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${LIVE}.sweeplive1" ]] \
  && pass "sweep retains live schema root" || fail "sweep reaped live root"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'SOLEUR_TMP_SWEEP.*reaped=[0-9]' \
  && pass "sweep emits SOLEUR_TMP_SWEEP telemetry" || fail "sweep telemetry missing: $out"
rm -rf "$FAKE_PROC/$LIVE"

# lock contention → loud skip, no mutation
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.sweeplock1"; : > "$FAKE_TMP/soleur-run.${DEAD}.sweeplock1/x"
mkdir -p "$SWEEP_STATE/soleur"
( flock -n 9 && sleep 5 ) 9>"$SWEEP_STATE/soleur/tmp-guard.lock" & sleep 0.3
out="$(sweep)"; wait || true
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'reason=lock-contended' \
  && pass "sweep skips loudly on lock contention" || fail "contention not reported: $out"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.sweeplock1" ]] \
  && pass "contended sweep mutates nothing" || fail "contended sweep still reaped"

# missing classifier → loud skip (SCRIPT_DIR rebound so the lib path misses)
out="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" bash -c "
  source '$WM' >/dev/null 2>&1 || true
  SCRIPT_DIR=/nonexistent
  sweep_orphan_scratch_dirs
" 2>&1 || true)"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'reason=classifier-missing' \
  && pass "missing classifier skips loudly" || fail "classifier-missing not reported: $out"

# bounded worktree batch defers past the cap
reset_fixtures
for i in 1 2 3; do mkdir -p "$FAKE_TMP/wt-$i"; printf 'gitdir: /nonexistent\n' > "$FAKE_TMP/wt-$i/.git"; done
out="$(SOLEUR_SWEEP_WT_CAP=1 sweep)"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'SWEEP-DEFER' \
  && pass "over-cap worktree batch emits SWEEP-DEFER" || fail "no defer marker: $out"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/wt-2" ]] \
  && pass "deferred worktrees are not moved" || fail "deferred worktree moved"

# the timebox bounds EVERY arm — a TIMEBOX_S=0 sweep defers the marker/schema
# arm too, not just the worktree batch
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.timeboxxx1"; : > "$FAKE_TMP/soleur-run.${DEAD}.timeboxxx1/x"
out="$(SOLEUR_SWEEP_TIMEBOX_S=0 TC_PROC_OVERRIDE="$FAKE_PROC" sweep)"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'SWEEP-DEFER' \
  && pass "timebox=0 defers the declared-owner arm" || fail "declared-owner arm unbounded: $out"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.timeboxxx1" ]] \
  && pass "deferred schema root survives" || fail "deferred root reaped"

# sweep honors the same foreign-ns marker veto as the reaper/purge
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.swpnsveto"; mk_marker "$FAKE_TMP/soleur-run.${DEAD}.swpnsveto" "$DEAD" 'pid:[99999999]'
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.swpnsveto" ]] \
  && pass "sweep honors foreign-ns marker veto" || fail "sweep reaped foreign-ns root: $out"

# a marker-bearing .git-FILE dir takes the worktree arm, never the marker arm —
# the registered worktree must be judged by the registry, not quarantined.
reset_fixtures
mkdir -p "$GITROOT_SWEEP"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$GITROOT_SWEEP/main" && git -C "$GITROOT_SWEEP/main" commit -qm init --allow-empty
SWEEP_WT="$FAKE_TMP/wt-marked"; git -C "$GITROOT_SWEEP/main" worktree add -q "$SWEEP_WT" >/dev/null 2>&1
mk_marker "$SWEEP_WT" "$DEAD"   # registered worktree ALSO bearing a marker
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep)"
cases=$((cases + 1)); [[ -d "$SWEEP_WT" ]] \
  && pass "marker-bearing worktree kept on the worktree arm (registry first)" \
  || fail "marker-bearing worktree left the registry arm: $out"

# --- Arm 7: session-start sweep — timebox vs the one-time map build, opt-in drain (#9677) -----
# The sweep sources its classifier from $SCRIPT_DIR/../../../scripts/lib, so the seam for a SLOW
# map build is a copied script tree whose classifier wrapper sources the REAL library and then
# redefines one function. FX_MODE selects the override.
REAL_TC="$REPO_ROOT/plugins/soleur/scripts/lib/tmp-classify.sh"
FX="$TESTROOT/fx"; FX_SD="$FX/skills/git-worktree/scripts"; FX_LOG="$TESTROOT/fx.log"
assert_fixture_dir "$FX"; mkdir -p "$FX_SD" "$FX/scripts/lib"
cat > "$FX/scripts/lib/tmp-classify.sh" <<'WRAP'
source "${REAL_TC:?}"
case "${FX_MODE:-}" in
  slowmap)    tc_build_inuse_map() { sleep 2; } ;;
  badmap)     tc_build_inuse_map() { return 1; } ;;
  slowdecide) eval "$(declare -f tc_reap_decide | sed '1s/tc_reap_decide/_orig_tc_reap_decide/')"
              tc_reap_decide() { sleep 1; _orig_tc_reap_decide "$@"; } ;;
  drainprobe) eval "$(declare -f tc_drain_quarantine | sed '1s/tc_drain_quarantine/_orig_tc_drain_quarantine/')"
              tc_drain_quarantine() {
                if ( exec 8<"${XDG_STATE_HOME}/soleur/tmp-guard.lock"; flock -n 8 ); then echo DRAIN-LOCK-FREE >> "${FX_LOG:?}"
                else echo DRAIN-LOCK-HELD >> "${FX_LOG:?}"; fi
                _orig_tc_drain_quarantine "$@"; } ;;
esac
WRAP
# sweep_fx [VAR=val ...]: like sweep(), but against the fixture script tree; later assignments win.
sweep_fx() {
  env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" \
    SOLEUR_SWEEP_BASES="${SWEEP_BASES:-$FAKE_TMP}" SOLEUR_SWEEP_AGE_MIN=0 SOLEUR_SWEEP_WT_AGE_MIN=0 \
    SOLEUR_SWEEP_TIMEBOX_S=10 XDG_STATE_HOME="$SWEEP_STATE" TMP_CLASSIFY_PROC="${TC_PROC_OVERRIDE:-/proc}" \
    TMP_CLASSIFY_RETAIN_DIR="$TESTROOT/retain" REAL_TC="$REAL_TC" FX_LOG="$FX_LOG" "$@" \
    bash -c "source '$WM' >/dev/null 2>&1 || true; SCRIPT_DIR='$FX_SD'; sweep_orphan_scratch_dirs" 2>&1 || true
}

# T1: a map build slower than the timebox must not starve every later candidate.
reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"
for i in 1 2 3; do mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i"; : > "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i/x"; done
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=slowmap SOLEUR_SWEEP_TIMEBOX_S=1)"
left=0; for i in 1 2 3; do [[ -d "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i" ]] && left=$((left + 1)); done
cases=$((cases + 1)); [[ "$left" == "0" ]] && printf '%s' "$out" | grep -q 'deferred=0' \
  && pass "T1 map build (2s) over the 1s timebox: all 3 dead roots still reclaimed, deferred=0" || fail "T1 left=$left out=$out"
cases=$((cases + 1)); printf '%s' "$out" | grep -qE 'drained=0 drained_bytes=0 map_s=[0-9]+' \
  && pass "T1s summary carries drained=, drained_bytes=, map_s=" || fail "T1s summary shape: $out"

# T1b: the rebase must not remove the bound — slow per-candidate work still defers.
reset_fixtures
for i in 1 2 3 4 5 6; do mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i"; : > "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i/x"; done
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=slowdecide SOLEUR_SWEEP_TIMEBOX_S=2)"
left=0; for i in 1 2 3 4 5 6; do [[ -d "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i" ]] && left=$((left + 1)); done
cases=$((cases + 1)); [[ "$left" -ge 1 ]] && printf '%s' "$out" | grep -qE 'deferred=[1-9]' \
  && pass "T1b per-candidate work past the rebased timebox still defers ($left of 6 left)" || fail "T1b left=$left out=$out"

# T12: a FAILING map build falls back to the per-candidate walk (fail closed): the live owner survives.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.badmapdead" "$FAKE_TMP/soleur-run.${LIVE}.badmaplive" "$FAKE_PROC/$LIVE"
: > "$FAKE_TMP/soleur-run.${DEAD}.badmapdead/x"
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=badmap)"
cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/soleur-run.${DEAD}.badmapdead" && -d "$FAKE_TMP/soleur-run.${LIVE}.badmaplive" ]] \
  && pass "T12 failing map build: dead root reclaimed, live-owner root retained" || fail "T12: $out"
rm -rf "$FAKE_PROC/$LIVE"

# --- drain (needs a disk-class base: tmpfs bases direct-delete, so quarantine never forms there) ---
if [[ -n "$DISK_BASE" ]]; then
  UID_N="$(id -u)"; QR="$DISK_BASE/soleur-quarantine.$UID_N"
  mk_quar() { # scratch-entry worktree-entry
    reset_fixtures; assert_fixture_dir "$QR"; rm -rf "$QR"; mkdir -p "$QR/scratch/$1" "$QR/worktrees/$2"; chmod 0700 "$QR"
    head -c 2048 /dev/zero > "$QR/scratch/$1/blob"; head -c 2048 /dev/zero > "$QR/worktrees/$2/blob"
  }
  DRAIN_ON=(SWEEP_BASES_UNUSED=1 SOLEUR_QUARANTINE_DRAIN=1 SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN=0)

  # T2: per-class TTLs — scratch past TTL drains, worktrees inside TTL stays; counts are summed
  # ACROSS bases (the second base has no quarantine, so a last-call-wins counter would read 0).
  mk_quar old-scratch keep-wt
  out="$(SWEEP_BASES="$DISK_BASE $FAKE_TMP" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=999999)"
  cases=$((cases + 1)); [[ ! -e "$QR/scratch/old-scratch" && -d "$QR/worktrees/keep-wt" ]] \
    && pass "T2a drain removes the past-TTL class and keeps the inside-TTL class" || fail "T2a: $out"
  cases=$((cases + 1)); printf '%s' "$out" | grep -qE 'drained=1 drained_bytes=[0-9]{4,}' \
    && pass "T2b summary reports drained=1 with a measured drained_bytes (du -sk based)" || fail "T2b summary: $out"

  # T2c: an exported recovery seam of 0 must not drain entries younger than the default floor.
  mk_quar young-scratch young-wt
  out="$(SWEEP_BASES="$DISK_BASE" sweep_fx SOLEUR_QUARANTINE_DRAIN=1 SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
  cases=$((cases + 1)); [[ -d "$QR/scratch/young-scratch" && -d "$QR/worktrees/young-wt" ]] \
    && pass "T2c TTL=0 is floored (default 1440 min): fresh quarantine entries survive" || fail "T2c: $out"

  # T3: opt-in — unset / 0 / yes drain nothing and the 'holds entries' note prints; =1 drains.
  for v in "" 0 yes; do
    mk_quar optin-scratch optin-wt
    out="$(SWEEP_BASES="$DISK_BASE" sweep_fx SOLEUR_QUARANTINE_DRAIN="$v" SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN=0 SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
    cases=$((cases + 1)); [[ -d "$QR/scratch/optin-scratch" ]] && printf '%s' "$out" | grep -q 'holds entries' \
      && pass "T3 SOLEUR_QUARANTINE_DRAIN='$v': nothing drained, the undrained-quarantine note prints" || fail "T3 '$v': $out"
  done

  # T2d: restore after a drain reports the entry gone instead of failing.
  reset_fixtures; assert_fixture_dir "$QR"; rm -rf "$QR"
  mkdir -p "$DISK_BASE/soleur-run.${DEAD}.restoreme"; : > "$DISK_BASE/soleur-run.${DEAD}.restoreme/x"
  SWEEP_BASES="$DISK_BASE" TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx >/dev/null
  SWEEP_BASES="$DISK_BASE" TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 >/dev/null
  rout="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" SOLEUR_PURGE_BASES="$DISK_BASE" XDG_STATE_HOME="$SWEEP_STATE" bash "$REPO_ROOT/scripts/soleur-tmp-purge.sh" --restore all 2>&1 || true)"
  cases=$((cases + 1)); [[ ! -d "$DISK_BASE/soleur-run.${DEAD}.restoreme" ]] && printf '%s' "$rout" | grep -q 'already gone' \
    && pass "T2d restore after a drain says 'already gone' and resurrects nothing" || fail "T2d: $rout"

  # T14: the drain runs INSIDE the tmp-guard lock window (serialised against the guard and purge).
  mk_quar lockwin-scratch lockwin-wt; : > "$FX_LOG"
  out="$(SWEEP_BASES="$DISK_BASE" sweep_fx FX_MODE=drainprobe "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
  cases=$((cases + 1)); grep -q 'DRAIN-LOCK-HELD' "$FX_LOG" && ! grep -q 'DRAIN-LOCK-FREE' "$FX_LOG" \
    && pass "T14 the drain executes while the sweep still holds the tmp-guard lock" || fail "T14 log: $(cat "$FX_LOG") out=$out"

  # T14b: no drain on the early-return paths — a contended lock drains nothing.
  mk_quar contend-scratch contend-wt; mkdir -p "$SWEEP_STATE/soleur"
  ( flock -n 9 && sleep 4 ) 9>"$SWEEP_STATE/soleur/tmp-guard.lock" & sleep 0.3
  out="$(SWEEP_BASES="$DISK_BASE" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0)"; wait || true
  cases=$((cases + 1)); [[ -d "$QR/scratch/contend-scratch" ]] && printf '%s' "$out" | grep -q 'reason=lock-contended' \
    && pass "T14b lock-contended sweep drains nothing" || fail "T14b: $out"
  rm -rf "$QR"
fi

# --- Conservation ----------------------------------------------------------------------
MIN_ASSERTIONS=44   # anti-vacuity floor — a truncated run can't pass at 0/0
                    # (the disk-class block is conditional on a non-tmpfs dir)
echo ""
echo "test-scratch-session: $pass_n passed, $fails failed ($cases cases)"
[[ $((pass_n + fails)) -ge $MIN_ASSERTIONS && $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
