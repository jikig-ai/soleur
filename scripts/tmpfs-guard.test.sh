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
  env TMPFS_GUARD_TMP="$FAKE_TMP" \
      TMPFS_GUARD_PROC="$FAKE_PROC" \
      TMPFS_GUARD_SCRATCH_MIN_MB=10 \
      TMPFS_GUARD_SCRATCH_AGE_MIN=60 \
      "$@"
}

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
out="$(guard_env env TMPFS_GUARD_DRY_RUN=1 bash -c "source '$GUARD'; reap_scratch_entries" 2>&1 || true)"
if [[ -e "$FAKE_TMP/tmp.dry" ]]; then
  pass "TMPFS_GUARD_DRY_RUN=1 deletes nothing"
else
  fail "dry run deleted a file; got: $out"
fi
# The dry run must still REPORT what it would have done, or it is untestable.
if [[ "$(grep -cF -- "tmp.dry" <<<"$out" || true)" -ge 1 ]]; then
  pass "dry run still reports the candidate it would reap"
else
  fail "dry run reported nothing; got: $out"
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
out="$(guard_env env TMPFS_GUARD_DRY_RUN=1 bash -c "source '$GUARD'; reap_scratch_entries" 2>&1 || true)"
echo "$out" > "$TESTROOT/nested.txt"
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

# --- Minimum-cardinality guard ---------------------------------------------
if [[ "$pass_n" -lt 12 ]]; then
  fail "cardinality guard: only $pass_n assertions ran (expected >= 12)"
fi

echo "=== tmpfs-guard: $pass_n passed, $fails failed ==="
[[ "$fails" -eq 0 ]] || exit 1
