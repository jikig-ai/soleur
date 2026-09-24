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
cleanup() { rm -rf "$TESTROOT" "${DISK_BASE:-}"; }
trap cleanup EXIT

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
  env -i PATH="$PATH" HOME="$HOME" \
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

reset_fixtures() {
  rm -rf "$FAKE_TMP"; mkdir -p "$FAKE_TMP"
  [[ -n "$DISK_BASE" ]] && { find "$DISK_BASE" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true; }
  rm -rf "$FAKE_PROC"; mkdir -p "$FAKE_PROC"
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
  _soleur_scratch_cleanup
" >/dev/null 2>&1
[[ -d "$FAKE_TMP/not-schema" ]] && pass "cleanup refuses non-schema root" || fail "cleanup deleted non-schema dir"

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

# marker-bearing dir, dead owner → reclaimed
reset_fixtures
mkdir -p "$FAKE_TMP/fixture-tree.abcdef"; printf 'pid=%s\nschema=1\n' "$DEAD" > "$FAKE_TMP/fixture-tree.abcdef/.soleur-owned"; : > "$FAKE_TMP/fixture-tree.abcdef/x"
out="$(reap3)"
cases=$((cases + 1)); [[ ! -d "$FAKE_TMP/fixture-tree.abcdef" ]] \
  && pass "dead-owner marker dir reaped" || fail "marker dir retained: $out"

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
fi

# --- Arm 4: fail-closed surfaces ------------------------------------------------------
reset_fixtures
mkdir -p "$FAKE_TMP/soleur-run.${DEAD}.guardtest1"
# empty base list → no reap
out="$(SCRATCH_BASES='' reap3)"
cases=$((cases + 1)); [[ -d "$FAKE_TMP/soleur-run.${DEAD}.guardtest1" ]] \
  && pass "empty SCRATCH_BASES → no reap (fail closed)" || fail "empty bases reaped"
# unreadable procfs → no reap
out="$(env -i PATH="$PATH" HOME="$HOME" \
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

# --- Conservation ----------------------------------------------------------------------
echo ""
echo "test-scratch-session: $pass_n passed, $fails failed ($cases cases)"
[[ $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
