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
  # SCRATCH_TEST_NO_DISK=1 forces the tmpfs-only path (what a CI box with no disk-class dir runs),
  # so the conditional-block floor below can be measured instead of assumed.
  [[ -n "${SCRATCH_TEST_NO_DISK:-}" ]] && break
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
rm -rf "${FAKE_PROC:?}/$LIVE"

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
  slowmap)    tc_build_inuse_map() { sleep 4; } ;;
  badmap)     tc_build_inuse_map() { return 1; } ;;
  slowdecide) eval "$(declare -f tc_reap_decide | sed '1s/tc_reap_decide/_orig_tc_reap_decide/')"
              tc_reap_decide() { sleep 1; _orig_tc_reap_decide "$@"; } ;;
  argprobe)   tc_drain_quarantine() { echo "ARGS dry=$2 sttl=$3 wttl=$4 box=$(( $5 - $(date +%s) )) cap=$6" >> "${FX_LOG:?}"; TC_DRAINED=0; TC_DRAINED_BYTES=0; } ;;
  handleflip) eval "$(declare -f tc_tree_has_live_handles | sed '1s/tc_tree_has_live_handles/_orig_tc_tree_has_live_handles/')"
              tc_tree_has_live_handles() { echo x >> "${FX_LOG:?}.flip"; (( $(wc -l < "${FX_LOG:?}.flip") >= 2 )) && return 0; _orig_tc_tree_has_live_handles "$@"; } ;;  # tc_reap_decide runs in a $(...) subshell: count in a file
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
    bash -c "source '$WM' >/dev/null 2>&1 || true; SCRIPT_DIR='$FX_SD'; sweep_orphan_scratch_dirs; echo \"SPACE_LOGICAL=\${_SPACE_LOGICAL_BYTES:-unset}\"" 2>&1 || true
}

# T1: a map build slower than the timebox must not starve every later candidate. now_s has 1 s
# granularity, so the margins are whole seconds wide (4 s build vs 3 s timebox) — a 1 s timebox would
# flake whenever the clock ticked while the three candidates were being decided.
reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"
for i in 1 2 3; do mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i"; : > "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i/x"; done
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=slowmap SOLEUR_SWEEP_TIMEBOX_S=3)"
left=0; for i in 1 2 3; do [[ -d "$FAKE_TMP/soleur-run.${DEAD}.slowmap$i" ]] && left=$((left + 1)); done
cases=$((cases + 1)); [[ "$left" == "0" ]] && grep -q 'deferred=0' <<<"$out" \
  && pass "T1 map build (4s) over the 3s timebox: all 3 dead roots still reclaimed, deferred=0" || fail "T1 left=$left out=$out"
cases=$((cases + 1)); grep -qE 'drained=0 drained_bytes=0 map_s=[3-9] ' <<<"$out" \
  && pass "T1s summary carries drained=, drained_bytes=, and the MEASURED map_s (a 4s build reads 3-9, never 0)" || fail "T1s summary shape: $out"

# T1b: the rebase must not remove the bound — slow per-candidate work still defers.
reset_fixtures
for i in 1 2 3 4 5 6; do mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i"; : > "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i/x"; done
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=slowdecide SOLEUR_SWEEP_TIMEBOX_S=2)"
left=0; for i in 1 2 3 4 5 6; do [[ -d "$FAKE_TMP/soleur-run.${DEAD}.slowdec$i" ]] && left=$((left + 1)); done
cases=$((cases + 1)); [[ "$left" -ge 1 ]] && grep -qE 'deferred=[1-9]' <<<"$out" \
  && pass "T1b per-candidate work past the rebased timebox still defers ($left of 6 left)" || fail "T1b left=$left out=$out"

# T8: a candidate whose owner is ALIVE is retained before the liveness map is needed, so it must not
# pay for the build (a slow 4 s build would otherwise be charged to every session start while any
# sibling session's soleur-run.<pid>.* dir exists).
reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"
mkdir -p "$FAKE_TMP/soleur-run.${LIVE}.liveonly1" "$FAKE_PROC/$LIVE"
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=slowmap)"
cases=$((cases + 1)); grep -qE 'map_s=0 ' <<<"$out" && [[ -d "$FAKE_TMP/soleur-run.${LIVE}.liveonly1" ]] \
  && pass "T8 a live-owner-only sweep builds no map (map_s=0) and keeps the dir" || fail "T8: $out"
rm -rf "${FAKE_PROC:?}/$LIVE"

# T9: the action-time liveness check before a tmpfs DIRECT delete. The first check (inside
# tc_reap_decide) reads the map as not-live; a handle appearing before the delete is simulated by the
# second call reading live. The dir must then NOT be deleted — it takes the reversible quarantine path.
reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.handleflip1"; : > "$FAKE_TMP/soleur-run.${DEAD}.handleflip1/x"
rm -f "$FX_LOG.flip"
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=handleflip)"
cases=$((cases + 1)); fst="$(findmnt -no FSTYPE --target "$FAKE_TMP" 2>/dev/null || true)"
if [[ "$fst" == "tmpfs" || "$fst" == "ramfs" ]]; then
  [[ ! -d "$FAKE_TMP/soleur-run.${DEAD}.handleflip1" && -e "$FAKE_TMP/soleur-quarantine.$(id -u)/scratch/soleur-run.${DEAD}.handleflip1/x" ]] && grep -q 'reaped=0 quarantined=1' <<<"$out" \
    && pass "T9 a handle that appears before the tmpfs direct delete diverts the dir to quarantine, not deletion" || fail "T9: $out"
else
  pass "T9 [skip] the fixture base is not tmpfs ($fst): the direct-delete arm is not reachable here"
fi

# T12: a FAILING map build falls back to the per-candidate walk (fail closed): the live owner survives.
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.badmapdead" "$FAKE_TMP/soleur-run.${LIVE}.badmaplive" "$FAKE_PROC/$LIVE"
: > "$FAKE_TMP/soleur-run.${DEAD}.badmapdead/x"
out="$(TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx FX_MODE=badmap)"
cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/soleur-run.${DEAD}.badmapdead" && -d "$FAKE_TMP/soleur-run.${LIVE}.badmaplive" ]] \
  && pass "T12 failing map build: dead root reclaimed, live-owner root retained" || fail "T12: $out"
rm -rf "${FAKE_PROC:?}/$LIVE"

# T4: every env var that feeds the drain is normalised to a decimal integer BEFORE it is compared or
# passed on. `08`/`09` are octal ERRORS (a floor comparison then reads false and is skipped, so the
# TTL would be 8 minutes), 0 means unbounded in the library, and the argument the library receives is
# the only place the effective values are observable — hence the argprobe seam.
argprobe() { # VAR=val ... -> the ARGS line the library would have received
  reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"; : > "$FX_LOG"
  sweep_fx FX_MODE=argprobe SOLEUR_QUARANTINE_DRAIN=1 "$@" >/dev/null
  grep '^ARGS' "$FX_LOG" | head -n 1
}
a="$(argprobe)"
cases=$((cases + 1)); [[ "$a" == "ARGS dry=0 sttl=10080 wttl=43200 box="[45]" cap=200" ]] \
  && pass "T4a defaults reach the library: TTLs 10080/43200 min, 5 s box, cap 200" || fail "T4a: $a"
a="$(argprobe SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=08 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=09)"
cases=$((cases + 1)); [[ "$a" == "ARGS dry=0 sttl=1440 wttl=1440 "* ]] \
  && pass "T4b TTL=08 / 09 are floored to 1440, not read as an octal error that skips the floor" || fail "T4b: $a"
a="$(argprobe SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0100000 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0090)"
cases=$((cases + 1)); [[ "$a" == "ARGS dry=0 sttl=100000 wttl=1440 "* ]] \
  && pass "T4c leading zeros are decimal: 0100000 -> 100000 (not octal 32768), 0090 -> floored" || fail "T4c: $a"
for v in 0 abc -1 ""; do
  a="$(argprobe SOLEUR_SWEEP_DRAIN_MAX_ENTRIES="$v")"
  cases=$((cases + 1)); [[ "$a" == *" cap=200" ]] \
    && pass "T4d SOLEUR_SWEEP_DRAIN_MAX_ENTRIES='$v' -> the 200 default (never unbounded)" || fail "T4d '$v': $a"
done
a="$(argprobe SOLEUR_SWEEP_DRAIN_MAX_ENTRIES=7)"
cases=$((cases + 1)); [[ "$a" == *" cap=7" ]] && pass "T4e a valid cap is passed through" || fail "T4e: $a"
a="$(argprobe SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN=08 SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=5)"
cases=$((cases + 1)); [[ "$a" == "ARGS dry=0 sttl=8 "* ]] \
  && pass "T4f floor=08 is decimal 8: a 5-minute TTL is raised to it" || fail "T4f: $a"
a="$(argprobe SOLEUR_SWEEP_DRAIN_TIMEBOX_S=0)"
cases=$((cases + 1)); [[ "$a" == *"box=0 cap="* ]] && pass "T4g a zero drain timebox is honoured (drains nothing), not read as unbounded" || fail "T4g: $a"

# T5: a hostile or sloppy timebox must not abort the sweep before it prints its summary, and must
# never execute: `BASH_SOURCE[$(touch FLAG)]` is an arithmetic-expression command substitution.
reset_fixtures; mkdir -p "$SWEEP_STATE/soleur"; PWNED="$TESTROOT/pwned.flag"; rm -f "$PWNED"
for v in '5s' "BASH_SOURCE[\$(touch $PWNED)]"; do
  out="$(sweep_fx SOLEUR_QUARANTINE_DRAIN=1 SOLEUR_SWEEP_TIMEBOX_S="$v" SOLEUR_SWEEP_DRAIN_TIMEBOX_S="$v")"
  cases=$((cases + 1)); [[ ! -e "$PWNED" ]] && grep -q 'SOLEUR_TMP_SWEEP bases=' <<<"$out" \
    && pass "T5 timebox '${v:0:12}...': no command ran and the sweep still printed its summary" || fail "T5 '$v': pwned=$([[ -e $PWNED ]] && echo yes || echo no) out=$out"
done

# T6: tc_drain_quarantine called BARE under errexit (what tmpfs-guard.sh and soleur-tmp-purge.sh do)
# must survive an unreadable size. A `du` shim that fails with output after the size reproduces an
# unreadable subtree without needing root-vs-user permission semantics.
reset_fixtures; Q_UID="$(id -u)"; Q6="$FAKE_TMP/soleur-quarantine.$Q_UID"
mkdir -p "$Q6/scratch/e1" "$Q6/scratch/e2" "$TESTROOT/du-shim"; chmod 0700 "$Q6"
printf '#!/bin/sh\nprintf "4\\t%%s\\n" "$3"\nexit 1\n' > "$TESTROOT/du-shim/du"; chmod +x "$TESTROOT/du-shim/du"
out="$(env -i PATH="$TESTROOT/du-shim:$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" XDG_STATE_HOME="$SWEEP_STATE" \
  bash -c 'set -euo pipefail; source "$1"; tc_drain_quarantine "$2" 0 0 0; echo "AFTER drained=$TC_DRAINED bytes=$TC_DRAINED_BYTES"' _ "$REAL_TC" "$FAKE_TMP" 2>&1 || true)"
cases=$((cases + 1)); grep -q 'AFTER drained=2 ' <<<"$out" \
  && pass "T6 a failing du does not abort a bare caller under set -euo pipefail; both entries drained" || fail "T6: $out"

# T7: the drain's own bounds, driven on the real library: a cap of 1 deletes one of three expired
# entries, and a deadline already in the past deletes none.
reset_fixtures; Q7="$FAKE_TMP/soleur-quarantine.$Q_UID"; mkdir -p "$Q7/scratch/c1" "$Q7/scratch/c2" "$Q7/scratch/c3"; chmod 0700 "$Q7"
out="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" XDG_STATE_HOME="$SWEEP_STATE" \
  bash -c 'source "$1"; tc_drain_quarantine "$2" 0 0 0 0 1; echo "CAP drained=$TC_DRAINED"; tc_drain_quarantine "$2" 0 0 0 1 0; echo "DEADLINE drained=$TC_DRAINED"' _ "$REAL_TC" "$FAKE_TMP" 2>&1 || true)"
cases=$((cases + 1)); grep -q 'CAP drained=1' <<<"$out" && grep -q 'DEADLINE drained=0' <<<"$out" && [[ "$(find "$Q7/scratch" -mindepth 1 -maxdepth 1 | wc -l)" == "2" ]] \
  && pass "T7 max_entries=1 drains exactly one entry; an expired deadline drains none" || fail "T7: $out"
rm -rf "$Q6" "$Q7"

# --- drain (needs a disk-class base: tmpfs bases direct-delete, so quarantine never forms there) ---
if [[ -n "$DISK_BASE" ]]; then
  UID_N="$(id -u)"; QR="$DISK_BASE/soleur-quarantine.$UID_N"
  mk_quar() { # scratch-entry worktree-entry
    reset_fixtures; assert_fixture_dir "$QR"; rm -rf "$QR"; mkdir -p "$QR/scratch/$1" "$QR/worktrees/$2"; chmod 0700 "$QR"
    head -c 2048 /dev/zero > "$QR/scratch/$1/blob"; head -c 2048 /dev/zero > "$QR/worktrees/$2/blob"
  }
  DRAIN_ON=(SOLEUR_QUARANTINE_DRAIN=1 SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN=0)

  # T2: per-class TTLs — scratch past TTL drains, worktrees inside TTL stays; counts are summed
  # ACROSS bases (the second base has no quarantine, so a last-call-wins counter would read 0).
  mk_quar old-scratch keep-wt
  out="$(SWEEP_BASES="$DISK_BASE $FAKE_TMP" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=999999)"
  cases=$((cases + 1)); [[ ! -e "$QR/scratch/old-scratch" && -d "$QR/worktrees/keep-wt" ]] \
    && pass "T2a drain removes the past-TTL class and keeps the inside-TTL class" || fail "T2a: $out"
  cases=$((cases + 1)); grep -qE 'drained=1 drained_bytes=[0-9]{4,}' <<<"$out" \
    && pass "T2b summary reports drained=1 with a measured drained_bytes (du -sk based)" || fail "T2b summary: $out"
  cases=$((cases + 1)); db="$(sed -n 's/.*drained_bytes=\([0-9]*\) .*/\1/p' <<<"$out" | head -n 1)"; sl="$(sed -n 's/^SPACE_LOGICAL=//p' <<<"$out" | head -n 1)"
  [[ -n "$db" && "$db" -gt 0 && "$sl" == "$db" ]] \
    && pass "T2b2 drained bytes reach the report's logical_bytes accumulator ($sl)" || fail "T2b2 drained_bytes=$db SPACE_LOGICAL=$sl"
  cases=$((cases + 1)); ! grep -q 'holds entries' <<<"$out" \
    && pass "T2b3 with the drain on, the 'holds entries' hint is not printed" || fail "T2b3: $out"

  # T2e: the OTHER direction — a worktrees-class entry past its TTL drains while the scratch entry
  # inside its TTL stays (a swapped or hardcoded TTL argument reddens exactly one of the two).
  mk_quar fresh-scratch old-wt
  out="$(SWEEP_BASES="$DISK_BASE" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=999999 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
  cases=$((cases + 1)); [[ -d "$QR/scratch/fresh-scratch" && ! -e "$QR/worktrees/old-wt" ]] \
    && pass "T2e past-TTL worktrees entry drains, inside-TTL scratch entry stays" || fail "T2e: $out"

  # T2h: the drain visits EVERY base, not just the first (the entry sits in the last one).
  reset_fixtures; mkdir -p "$DISK_BASE/second"; rm -rf "$QR" "$DISK_BASE/second/soleur-quarantine.$UID_N"
  Q2="$DISK_BASE/second/soleur-quarantine.$UID_N"; mkdir -p "$Q2/scratch/lastbase"; chmod 0700 "$Q2"; head -c 2048 /dev/zero > "$Q2/scratch/lastbase/blob"
  out="$(SWEEP_BASES="$DISK_BASE $DISK_BASE/second" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0)"
  cases=$((cases + 1)); [[ ! -e "$Q2/scratch/lastbase" ]] && grep -q 'drained=1 ' <<<"$out" \
    && pass "T2h an entry in the last base drains (the loop does not stop after the first base)" || fail "T2h: $out"
  rm -rf "$DISK_BASE/second"

  # T2c: an exported recovery seam of 0 must not drain entries younger than the default floor.
  mk_quar young-scratch young-wt
  out="$(SWEEP_BASES="$DISK_BASE" sweep_fx SOLEUR_QUARANTINE_DRAIN=1 SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
  cases=$((cases + 1)); [[ -d "$QR/scratch/young-scratch" && -d "$QR/worktrees/young-wt" ]] \
    && pass "T2c TTL=0 is floored (default 1440 min): fresh quarantine entries survive" || fail "T2c: $out"

  # T3: opt-in — unset / 0 / yes drain nothing and the 'holds entries' note prints; =1 drains.
  for v in "" 0 yes; do
    mk_quar optin-scratch optin-wt
    out="$(SWEEP_BASES="$DISK_BASE" sweep_fx SOLEUR_QUARANTINE_DRAIN="$v" SOLEUR_SWEEP_QUAR_TTL_FLOOR_MIN=0 SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 SOLEUR_SWEEP_QUAR_WT_TTL_MIN=0)"
    cases=$((cases + 1)); [[ -d "$QR/scratch/optin-scratch" ]] && grep -q 'holds entries' <<<"$out" \
      && pass "T3 SOLEUR_QUARANTINE_DRAIN='$v': nothing drained, the undrained-quarantine note prints" || fail "T3 '$v': $out"
  done

  # T2d: restore after a drain reports the entry gone instead of failing.
  reset_fixtures; assert_fixture_dir "$QR"; rm -rf "$QR"
  assert_fixture_dir "$DISK_BASE"; mkdir -p "$DISK_BASE/soleur-run.${DEAD}.restoreme"; : > "$DISK_BASE/soleur-run.${DEAD}.restoreme/x"
  SWEEP_BASES="$DISK_BASE" TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx >/dev/null
  SWEEP_BASES="$DISK_BASE" TC_PROC_OVERRIDE="$FAKE_PROC" sweep_fx "${DRAIN_ON[@]}" SOLEUR_SWEEP_QUAR_SCRATCH_TTL_MIN=0 >/dev/null
  rout="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$SOLEUR_PURGE_LEDGER" SOLEUR_PURGE_BASES="$DISK_BASE" XDG_STATE_HOME="$SWEEP_STATE" bash "$REPO_ROOT/scripts/soleur-tmp-purge.sh" --restore all 2>&1 || true)"
  cases=$((cases + 1)); [[ ! -d "$DISK_BASE/soleur-run.${DEAD}.restoreme" ]] && grep -q 'already gone' <<<"$rout" \
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
  cases=$((cases + 1)); [[ -d "$QR/scratch/contend-scratch" ]] && grep -q 'reason=lock-contended' <<<"$out" \
    && pass "T14b lock-contended sweep drains nothing" || fail "T14b: $out"
  rm -rf "$QR"
fi

# --- Conservation ----------------------------------------------------------------------
MIN_ASSERTIONS_NODISK=59    # measured with SCRATCH_TEST_NO_DISK=1 (the unconditional assertions)
MIN_ASSERTIONS_DISK=75        # measured with a disk-class base: the disk-class block adds the rest
MIN_ASSERTIONS="$MIN_ASSERTIONS_NODISK"; [[ -n "$DISK_BASE" ]] && MIN_ASSERTIONS="$MIN_ASSERTIONS_DISK"
# anti-vacuity floor — a truncated run can't pass at 0/0; set to the FULL current count so a deleted
# assertion is a failure, not slack.
echo ""
echo "test-scratch-session: $pass_n passed, $fails failed ($cases cases)"
[[ $((pass_n + fails)) -ge $MIN_ASSERTIONS && $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
