#!/usr/bin/env bash
# test-tmp-purge.sh — arms for scripts/soleur-tmp-purge.sh +
# plugins/soleur/scripts/lib/tmp-classify.sh (#7004 / feat-tmp-scratch-reclamation).
#
# This suite exists because the purge MOVES operator files. Every ladder rung
# is asserted in BOTH directions: the action happens when it should, and —
# more importantly — does NOT happen when any conjunct says no.
#
# AUTHORING CONSTRAINTS (see work/SKILL.md):
#   - Never `producer | grep -q` under pipefail; grep a FILE or use `grep -c`.
#   - Deliberately-nonzero commands inside `$(...)` need `|| true` under set -e.
#   - Every arm carries a mutation control.
#
# Fixtures are synthesized under this test's own TESTROOT. The purge is driven
# entirely through its seams (SOLEUR_PURGE_BASES/LEDGER/LOCKFILE,
# TMP_CLASSIFY_*), so NOTHING outside TESTROOT is ever a candidate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PURGE="$REPO_ROOT/scripts/soleur-tmp-purge.sh"

pass_n=0; fails=0; cases=0
# `cases` increments at the CALL SITE, never inside pass()/fail() — see
# tmpfs-guard.test.sh for why (stubbing a verdict helper must drop the count).
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t soleur-tmp-purge.XXXXXXXX)"
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
cleanup() { assert_fixture_dir "$TESTROOT"; rm -rf "$TESTROOT"; }
trap cleanup EXIT

# Fixture-env adoption (#7833/#7849): fixture git writes run under the
# synthesized identity + hermetic config + discovery ceiling, not the
# ambient developer environment.
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
git_fixture_env "$TESTROOT" || { echo "FATAL: git_fixture_env refused fixture root $TESTROOT" >&2; exit 2; }

[[ -f "$PURGE" ]] || { echo "ERROR: $PURGE missing" >&2; exit 1; }

FAKE_A="$TESTROOT/baseA"   # "tmpfs-class" sentinel
FAKE_B="$TESTROOT/baseB"   # "disk-class" sentinel
FAKE_PROC="$TESTROOT/proc"
LEDGER="$TESTROOT/ledger.log"
LOCKFILE="$TESTROOT/lock"
RETAIN_DIR="$TESTROOT/retain"
mkdir -p "$FAKE_A" "$FAKE_B" "$FAKE_PROC" "$RETAIN_DIR"

# The fake procfs carries a self/ns/pid link so marker `ns=` fields verify
# against it — the marker parser now REQUIRES a matching namespace.
FAKE_NS='pid:[42424242]'
mk_fake_proc() {
  rm -rf "$FAKE_PROC"; mkdir -p "$FAKE_PROC/self/ns"
  ln -s "$FAKE_NS" "$FAKE_PROC/self/ns/pid"
}
mk_fake_proc

purge_env() {
  env -i PATH="$PATH" HOME="$HOME" \
    SOLEUR_PURGE_BASES="$FAKE_A $FAKE_B" \
    SOLEUR_PURGE_LEDGER="$LEDGER" \
    SOLEUR_PURGE_LOCKFILE="$LOCKFILE" \
    TMP_CLASSIFY_PROC="$FAKE_PROC" \
    TMP_CLASSIFY_AGE_FLOOR_MIN="${TC_FLOOR:-0}" \
    TMP_CLASSIFY_WT_FLOOR_MIN="${TC_FLOOR:-0}" \
    TMP_CLASSIFY_RETAIN_DIR="$RETAIN_DIR" \
    TMP_CLASSIFY_RETAIN_FLOOR_MIN="${TC_RETAIN_FLOOR:-10080}" \
    "$@"
}

# A valid marker now REQUIRES ns= matching the fake proc's self/ns/pid —
# absent or foreign namespaces veto the marker (unattributable, never moved).
mk_marker() { # dir pid [ns]
  mkdir -p "$1"; printf 'pid=%s\nschema=1\nns=%s\n' "$2" "${3:-$FAKE_NS}" > "$1/.soleur-owned"
}
mk_live_proc() { mkdir -p "$FAKE_PROC/$1"; }   # presence == alive under the seam
mk_live_fd() { # pid dir — fake a live fd handle into a target dir
  mkdir -p "$FAKE_PROC/$1/fd"; ln -s "$2" "$FAKE_PROC/$1/fd/3"
}

reset_fixtures() {
  assert_fixture_dir "$FAKE_A"; rm -rf "$FAKE_A" "$FAKE_B"; mkdir -p "$FAKE_A" "$FAKE_B"
  mk_fake_proc
  : > "$LEDGER" 2>/dev/null || true
}
reset_fixtures

echo "=== test-tmp-purge ==="

# --- Arm 1: dry-run mutates nothing ------------------------------------------
mkdir -p "$FAKE_A/rung2-archive.DeadBeef1"; : > "$FAKE_A/rung2-archive.DeadBeef1/git-data-bootstrap.sh"
mkdir -p "$FAKE_A/tmp.PlainMktemp123"; : > "$FAKE_A/tmp.PlainMktemp123/x"
out="$(purge_env bash "$PURGE" --dry-run 2>&1)"

cases=$((cases + 1)); printf '%s' "$out" | grep -q 'SOLEUR_TMP_PURGE mode=dry-run' \
  && pass "dry-run prints report header" || fail "dry-run header missing"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'prefix:rung2-archive' \
  && pass "dry-run counts prefix class" || fail "prefix class not reported"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'protected' \
  && pass "dry-run counts protected class" || fail "protected class not reported"
cases=$((cases + 1)); [[ -d "$FAKE_A/rung2-archive.DeadBeef1" && -d "$FAKE_A/tmp.PlainMktemp123" ]] \
  && pass "dry-run moved nothing" || fail "dry-run mutated fixtures"

# --- Arm 2: apply quarantines certain-attribution classes ----------------------
reset_fixtures
mkdir -p "$FAKE_A/rung2-archive.AaBbCcDd"; : > "$FAKE_A/rung2-archive.AaBbCcDd/git-data-bootstrap.sh"
mkdir -p "$FAKE_B/gdboot.XxYyZz00"; : > "$FAKE_B/gdboot.XxYyZz00/rows"; : > "$FAKE_B/gdboot.XxYyZz00/err"
mkdir -p "$FAKE_A/infra-suites.QqWwEe11"; : > "$FAKE_A/infra-suites.QqWwEe11/_t.test.sh.meta"
mkdir -p "$FAKE_A/soleur-inc-abcdef"; mkdir -p "$FAKE_A/soleur-inc-abcdef/.claude"
mkdir -p "$FAKE_A/emptydir-Ab1Cd2Ef3Gh4"
: > "$FAKE_A/inngest-ci-block-Ab12Cd.sh"
: > "$FAKE_A/pr-1234-body.md"
out="$(purge_env bash "$PURGE" --apply 2>&1)"

cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/rung2-archive.AaBbCcDd" ]] \
  && pass "prefix class quarantined" || fail "prefix class not quarantined: $out"
cases=$((cases + 1)); [[ -d "$FAKE_B/soleur-quarantine.$(id -u)/prefix/gdboot.XxYyZz00" ]] \
  && pass "second base quarantined" || fail "baseB not swept"
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/infra-suites.QqWwEe11" ]] \
  && pass "infra-suites quarantined" || fail "infra-suites missed"
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/soleur-inc-abcdef" ]] \
  && pass "soleur-inc quarantined" || fail "soleur-inc missed"
cases=$((cases + 1)); [[ ! -e "$FAKE_A/emptydir-Ab1Cd2Ef3Gh4" ]] \
  && pass "empty long-named dir rmdir'd" || fail "empty dir retained"
cases=$((cases + 1)); [[ -f "$FAKE_A/soleur-quarantine.$(id -u)/prefix/inngest-ci-block-Ab12Cd.sh" ]] \
  && pass "file-shape class quarantined" || fail "file class missed"
cases=$((cases + 1)); grep -q $'move\t' "$LEDGER" \
  && pass "ledger recorded moves" || fail "ledger empty"

# --- Arm 3: protected/unattributable never move ---------------------------------
reset_fixtures
mkdir -p "$FAKE_A/tmp.PlainMktemp999"; : > "$FAKE_A/tmp.PlainMktemp999/x"
mkdir -p "$FAKE_A/plan-fixture-abc"; : > "$FAKE_A/plan-fixture-abc/x"
mkdir -p "$FAKE_A/shared-c4-08twCoX"
mkdir -p "$FAKE_A/skill-security-scan-99"; : > "$FAKE_A/skill-security-scan-99/x"
mkdir -p "$FAKE_A/systemd-private-xyz"; : > "$FAKE_A/systemd-private-xyz/x"
mkdir -p "$FAKE_A/mystery-dir-zz"; : > "$FAKE_A/mystery-dir-zz/x"
out="$(purge_env bash "$PURGE" --apply 2>&1)"

cases=$((cases + 1)); [[ -d "$FAKE_A/tmp.PlainMktemp999" ]] \
  && pass "bare tmp.* retained (tmpfiles' job)" || fail "bare tmp.* moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/plan-fixture-abc" ]] \
  && pass "plan-* protected" || fail "plan-* moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/shared-c4-08twCoX" ]] \
  && pass "shared-* protected (even empty)" || fail "shared-* moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/skill-security-scan-99" ]] \
  && pass "skill-security-scan-* protected (#6760)" || fail "security-scan moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/systemd-private-xyz" ]] \
  && pass "systemd-private-* protected" || fail "systemd-private moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/mystery-dir-zz" ]] \
  && pass "unattributable retained" || fail "unattributable moved"
cases=$((cases + 1)); [[ ! -d "$FAKE_A/soleur-quarantine.$(id -u)" ]] \
  && pass "no quarantine dir created when nothing moves" || fail "spurious quarantine"

# --- Arm 4: marker + schema liveness ---------------------------------------------
reset_fixtures
DEAD=424242; LIVE=434343; mk_live_proc "$LIVE"
mkdir -p "$FAKE_A/marked-dead.aaaaaaaa"; mk_marker "$FAKE_A/marked-dead.aaaaaaaa" "$DEAD"; : > "$FAKE_A/marked-dead.aaaaaaaa/x"
mkdir -p "$FAKE_A/marked-live.bbbbbbbb"; mk_marker "$FAKE_A/marked-live.bbbbbbbb" "$LIVE"; : > "$FAKE_A/marked-live.bbbbbbbb/x"
mkdir -p "$FAKE_A/marked-nopid.cccccccc"; printf 'schema=1\n' > "$FAKE_A/marked-nopid.cccccccc/.soleur-owned"; : > "$FAKE_A/marked-nopid.cccccccc/x"
mkdir -p "$FAKE_A/soleur-run.${DEAD}.deadbeef"; : > "$FAKE_A/soleur-run.${DEAD}.deadbeef/x"
mkdir -p "$FAKE_A/soleur-run.${LIVE}.livebeef"; : > "$FAKE_A/soleur-run.${LIVE}.livebeef/x"
out="$(purge_env bash "$PURGE" --apply 2>&1)"

cases=$((cases + 1)); [[ ! -d "$FAKE_A/marked-dead.aaaaaaaa" ]] \
  && pass "dead-owner marker dir quarantined" || fail "dead marker retained"
cases=$((cases + 1)); [[ -d "$FAKE_A/marked-live.bbbbbbbb" ]] \
  && pass "live-owner marker dir retained" || fail "live marker moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/marked-nopid.cccccccc" ]] \
  && pass "marker without pid= ignored (unattributable → retain)" || fail "nopid marker moved"
cases=$((cases + 1)); [[ ! -d "$FAKE_A/soleur-run.${DEAD}.deadbeef" ]] \
  && pass "dead-owner schema dir quarantined" || fail "dead schema retained"
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-run.${LIVE}.livebeef" ]] \
  && pass "live-owner schema dir retained" || fail "live schema moved"

# --- Arm 4b: marker verification — foreign ns veto, owner_root cycle, live fd --
reset_fixtures
DEAD=424242
# Foreign-namespace marker on a SCHEMA-named dir: the container-producer case.
# The marker's ns= must VETO the schema name — the pid in the name belongs to
# the foreign namespace and is meaningless on this host.
mkdir -p "$FAKE_A/soleur-run.${DEAD}.foreignns"; mk_marker "$FAKE_A/soleur-run.${DEAD}.foreignns" "$DEAD" 'pid:[99999999]'
# owner_root A↔B cycle: resolution is depth-bounded → unverifiable → retain,
# never hang.
mkdir -p "$FAKE_A/cycle-aaaaaaaa" "$FAKE_A/cycle-bbbbbbbb"
printf 'owner_root=%s\nschema=1\nns=%s\n' "$FAKE_A/cycle-bbbbbbbb" "$FAKE_NS" > "$FAKE_A/cycle-aaaaaaaa/.soleur-owned"
printf 'owner_root=%s\nschema=1\nns=%s\n' "$FAKE_A/cycle-aaaaaaaa" "$FAKE_NS" > "$FAKE_A/cycle-bbbbbbbb/.soleur-owned"
# Dead owner + live fd handle held by a surviving descendant → retain.
mkdir -p "$FAKE_A/marked-handle.cccccccc"; mk_marker "$FAKE_A/marked-handle.cccccccc" "$DEAD"; : > "$FAKE_A/marked-handle.cccccccc/x"
mk_live_fd 999 "$FAKE_A/marked-handle.cccccccc"
# Marker dir containing a nested .git tree → registry-relevant → retain.
mkdir -p "$FAKE_A/marked-nested.dddddddd/wt"; printf 'gitdir: /nonexistent\n' > "$FAKE_A/marked-nested.dddddddd/wt/.git"
mk_marker "$FAKE_A/marked-nested.dddddddd" "$DEAD"
out="$(purge_env bash "$PURGE" --apply 2>&1)"

cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-run.${DEAD}.foreignns" ]] \
  && pass "foreign-ns marker vetoes schema name (container case)" || fail "foreign-ns dir moved: $out"
cases=$((cases + 1)); [[ -d "$FAKE_A/cycle-aaaaaaaa" && -d "$FAKE_A/cycle-bbbbbbbb" ]] \
  && pass "owner_root cycle bounded → retained" || fail "cycle dirs moved/hung"
cases=$((cases + 1)); [[ -d "$FAKE_A/marked-handle.cccccccc" ]] \
  && pass "dead-owner dir with live fd handle retained" || fail "live-handle marker dir moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/marked-nested.dddddddd" ]] \
  && pass "marker dir with nested .git retained" || fail "nested-git dir moved"

# --- Arm 5: live handles retain a prefix-class dir (real /proc arm) --------------
reset_fixtures
mkdir -p "$FAKE_A/rung2-archive.LiveFd99"; : > "$FAKE_A/rung2-archive.LiveFd99/git-data-bootstrap.sh"
# Hold a real fd on the dir from a background process (the holder-fd mechanism).
(sleep 30 < "$FAKE_A/rung2-archive.LiveFd99") & HOLDER=$!
sleep 0.3
out="$(env -i PATH="$PATH" HOME="$HOME" \
  SOLEUR_PURGE_BASES="$FAKE_A" SOLEUR_PURGE_LEDGER="$LEDGER" \
  SOLEUR_PURGE_LOCKFILE="$LOCKFILE" TMP_CLASSIFY_AGE_FLOOR_MIN=0 \
  TMP_CLASSIFY_RETAIN_DIR="$RETAIN_DIR" bash "$PURGE" --apply 2>&1)"
kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true

cases=$((cases + 1)); [[ -d "$FAKE_A/rung2-archive.LiveFd99" ]] \
  && pass "dir with live fd handle retained" || fail "live-handle dir moved"

# --- Arm 6: worktree classification ----------------------------------------------
reset_fixtures
GITROOT="$TESTROOT/gitrepos"; mkdir -p "$GITROOT"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$GITROOT/main" && git -C "$GITROOT/main" commit -qm init --allow-empty
# Worktrees are created IN the sweep base — a worktree's .git file and registry
# entry both name its real path, so relocating it post-add would falsify the
# fixture (and matches the real backlog: /var/tmp worktrees never moved).
WT_OK="$FAKE_A/wt-ok-src"; WT_DIRTY="$FAKE_A/wt-dirty-src"; WT_UNPUSHED="$FAKE_A/wt-unpushed-src"; WT_IGNORED="$FAKE_A/wt-ignored-src"
git -C "$GITROOT/main" worktree add -q -b wt-ok "$WT_OK" >/dev/null 2>&1
git -C "$GITROOT/main" worktree add -q "$WT_DIRTY" >/dev/null 2>&1
git -C "$GITROOT/main" worktree add -q "$WT_UNPUSHED" >/dev/null 2>&1
git -C "$GITROOT/main" worktree add -q "$WT_IGNORED" >/dev/null 2>&1
# wt-ok: clean, merged (HEAD == main tip), upstream → a local branch so ahead==0.
git -C "$WT_OK" branch --set-upstream-to=main >/dev/null 2>&1 || true
# wt-dirty: untracked file.
: > "$WT_DIRTY/dirty.txt"
# wt-unpushed: a commit ahead of main with no upstream covering it.
git -C "$WT_UNPUSHED" checkout -qb feature >/dev/null 2>&1
git -C "$WT_UNPUSHED" commit -qm wip --allow-empty
# wt-ignored: only an ignored file (the .env.local defect class).
echo '*.local' > "$GITROOT/main/.gitignore"
git -C "$GITROOT/main" add .gitignore >/dev/null 2>&1 && git -C "$GITROOT/main" commit -qm gitignore
: > "$WT_IGNORED/secret.local"
# phantom: .git FILE pointing at a real but non-registering gitdir → proven unregistered.
mkdir -p "$GITROOT/main/.git/worktrees/phantom"
mkdir -p "$FAKE_A/phantom-wt-src"
printf 'gitdir: %s\n' "$GITROOT/main/.git/worktrees/phantom" > "$FAKE_A/phantom-wt-src/.git"
# stale pointer: .git file → nonexistent gitdir → unverifiable → retain.
mkdir -p "$FAKE_A/stale-wt-src"
printf 'gitdir: %s\n' "$GITROOT/main/.git/worktrees/gone" > "$FAKE_A/stale-wt-src/.git"
# standalone clone: real .git dir, no prefix signature → report-only.
git init -q "$FAKE_A/lone-clone" >/dev/null 2>&1
out="$(purge_env bash "$PURGE" --apply 2>&1)"

cases=$((cases + 1)); [[ ! -d "$FAKE_A/wt-ok-src" && -z "$(git --git-dir="$GITROOT/main/.git" worktree list --porcelain | grep -F 'wt-ok-src')" ]] \
  && pass "clean+merged+no-unpushed registered worktree removed" || fail "wt-ok not removed: $out"
cases=$((cases + 1)); [[ -d "$FAKE_A/wt-dirty-src" ]] \
  && pass "dirty registered worktree retained" || fail "dirty worktree removed"
cases=$((cases + 1)); [[ -d "$FAKE_A/wt-unpushed-src" ]] \
  && pass "unpushed-commit worktree retained" || fail "unpushed worktree removed"
cases=$((cases + 1)); [[ -d "$FAKE_A/wt-ignored-src" ]] \
  && pass "ignored-file-only worktree retained (clean includes ignored)" || fail "ignored-file worktree removed"
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/worktrees/phantom-wt-src" ]] \
  && pass "proven-unregistered worktree quarantined" || fail "phantom worktree: $out"
cases=$((cases + 1)); [[ -d "$FAKE_A/stale-wt-src" ]] \
  && pass "stale-gitdir worktree retained (unverifiable)" || fail "stale gitdir moved"
cases=$((cases + 1)); [[ -d "$FAKE_A/lone-clone" ]] \
  && pass "standalone .git dir report-only" || fail "standalone clone moved"

# --- Arm 7: idempotence -----------------------------------------------------------
out2="$(purge_env bash "$PURGE" --apply 2>&1)"
cases=$((cases + 1)); printf '%s' "$out2" | grep -qc 'QUARANTINE' \
  && { printf '%s' "$out2" | grep -c 'QUARANTINE' | grep -qx 0 && pass "second apply moves nothing" || fail "second apply moved entries"; } \
  || pass "second apply moves nothing"

# --- Arm 8: retain-since escalation ------------------------------------------------
reset_fixtures
mkdir -p "$FAKE_A/stale2-wt-src"
printf 'gitdir: %s\n' "$GITROOT/main/.git/worktrees/gone2" > "$FAKE_A/stale2-wt-src/.git"
purge_env bash "$PURGE" --apply >/dev/null 2>&1 || true
stamp="$RETAIN_DIR/$(printf '%s' "$FAKE_A/stale2-wt-src" | sha256sum | cut -d' ' -f1)"
[[ -f "$stamp" ]] && touch -d "-200 hours" "$stamp"
out="$(purge_env bash "$PURGE" --apply 2>&1)"
cases=$((cases + 1)); printf '%s' "$out" | grep -q 'OPERATOR-DECISION' \
  && pass "unverifiable past retain floor escalates to operator list" || fail "no escalation: $out"
cases=$((cases + 1)); [[ -d "$FAKE_A/stale2-wt-src" ]] \
  && pass "escalated entry still not moved" || fail "escalated entry moved"

# --- Arm 9: lock contention ---------------------------------------------------------
reset_fixtures
( flock -n 200 || exit 9; sleep 4 ) 200>"$LOCKFILE" & LOCKPID=$!
sleep 0.3
rc=0; out="$(purge_env bash "$PURGE" --apply 2>&1)" || rc=$?
wait "$LOCKPID" 2>/dev/null || true
cases=$((cases + 1)); [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'SKIP' \
  && pass "concurrent run skips loudly (rc=2)" || fail "contention rc=$rc out=$out"

# --- Arm 10: restore + drain ----------------------------------------------------------
reset_fixtures
mkdir -p "$FAKE_A/rung2-archive.Restore1"; : > "$FAKE_A/rung2-archive.Restore1/git-data-bootstrap.sh"
purge_env bash "$PURGE" --apply >/dev/null 2>&1
cases=$((cases + 1)); [[ ! -d "$FAKE_A/rung2-archive.Restore1" && -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/rung2-archive.Restore1" ]] \
  && pass "apply quarantined for restore test" || fail "restore fixture missing"
out="$(purge_env bash "$PURGE" --restore rung2-archive.Restore1 2>&1)"
cases=$((cases + 1)); [[ -d "$FAKE_A/rung2-archive.Restore1" ]] \
  && pass "--restore returns entry to origin" || fail "restore failed: $out"
# drain: TTL 0 forces deletion beneath the quarantine root only
purge_env bash "$PURGE" --apply >/dev/null 2>&1
out="$(env -i PATH="$PATH" HOME="$HOME" \
  SOLEUR_PURGE_BASES="$FAKE_A" SOLEUR_PURGE_LEDGER="$LEDGER" \
  SOLEUR_PURGE_LOCKFILE="$LOCKFILE" TMP_CLASSIFY_AGE_FLOOR_MIN=0 \
  TMP_CLASSIFY_RETAIN_DIR="$RETAIN_DIR" \
  SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 TMP_CLASSIFY_PROC="$FAKE_PROC" \
  bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ ! -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/rung2-archive.Restore1" ]] \
  && pass "--drain deletes past-TTL quarantine entries" || fail "drain no-op: $out"

# --- Arm 11: drain dwell is quarantine-arrival (ctime), not content age ---------
reset_fixtures
mkdir -p "$FAKE_A/rung2-archive.DrainTTLx"; : > "$FAKE_A/rung2-archive.DrainTTLx/git-data-bootstrap.sh"
# Content made ancient — pre-fix code drained on content mtime, collapsing the
# recovery window to ~0 for exactly the stale backlog quarantine exists to save.
touch -d '-20000 minutes' "$FAKE_A/rung2-archive.DrainTTLx/git-data-bootstrap.sh" "$FAKE_A/rung2-archive.DrainTTLx"
purge_env bash "$PURGE" --apply >/dev/null 2>&1
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/rung2-archive.DrainTTLx" ]] \
  && pass "fixture quarantined for drain-dwell arm" || fail "drain-dwell fixture missing"
out="$(purge_env bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ -d "$FAKE_A/soleur-quarantine.$(id -u)/prefix/rung2-archive.DrainTTLx" ]] \
  && pass "drain retains fresh quarantine dwell despite ancient content" \
  || fail "drain used content mtime — recovery window collapsed: $out"

# --- Arm 12: bare --restore replays all moves; flag-shaped target not swallowed -
reset_fixtures
mkdir -p "$FAKE_A/rung2-archive.RestoreAll"; : > "$FAKE_A/rung2-archive.RestoreAll/git-data-bootstrap.sh"
purge_env bash "$PURGE" --apply >/dev/null 2>&1
rc=0; out="$(purge_env bash "$PURGE" --restore 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -d "$FAKE_A/rung2-archive.RestoreAll" ]] \
  && pass "bare --restore replays all ledger moves" || fail "bare --restore rc=$rc out=$out"

# --- Arm 13: empty SOLEUR_PURGE_BASES refuses loudly, never defaults ------------
rc=0; out="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_BASES="" bash "$PURGE" --dry-run 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q 'FATAL' \
  && pass "empty bases env refuses loudly" || fail "empty bases rc=$rc out=$out"

# --- Arm 14: symlinked quarantine root refuses the drain ------------------------
reset_fixtures
mkdir -p "$TESTROOT/victim-tree"; : > "$TESTROOT/victim-tree/keep"
ln -s "$TESTROOT/victim-tree" "$FAKE_A/soleur-quarantine.$(id -u)"
out="$(purge_env bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ -f "$TESTROOT/victim-tree/keep" ]] \
  && pass "symlinked quarantine root — drain refuses, target untouched" \
  || fail "drain followed symlinked quarantine root"

# --- Arm 15: --report is strictly read-only and attributes bytes per family ------
# Fixture: two non-.git `vac*` dirs, a REGISTERED git worktree named td-123
# (must report as worktree and carry its bytes in the .git split), a non-.git
# unattributable perf-* dir, and a quarantine root with content that must stay
# out of the scan. A before/after tree hash of every base + ledger proves the
# report mutated nothing; a control proves the hash would notice a mutation.
reset_fixtures
tree_hash() { # base... — name, type, size, mtime, owner of every node
  find "$@" -printf '%p\t%y\t%s\t%T@\t%U\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}
fill() { head -c "$2" /dev/zero > "$1"; }   # fill <file> <bytes>
mkdir -p "$FAKE_B/vac111" "$FAKE_B/vac222" "$FAKE_B/perf-9" "$FAKE_B/oldx-9876" "$FAKE_B/newx-9876"
fill "$FAKE_B/vac111/blob" 131072; fill "$FAKE_B/vac222/blob" 131072
fill "$FAKE_B/perf-9/blob" 65536
fill "$FAKE_B/oldx-9876/blob" 65536; fill "$FAKE_B/newx-9876/blob" 65536
touch -d '-40 days' "$FAKE_B/oldx-9876/blob" "$FAKE_B/oldx-9876"
git -C "$GITROOT/main" worktree add -q -b td-123 "$FAKE_B/td-123" >/dev/null 2>&1
fill "$FAKE_B/td-123/blob" 262144
# quarantine root holding a dead-owner marker dir: if the scan ever walked into
# it, apply would re-quarantine it and the report would count it.
QROOT="$FAKE_B/soleur-quarantine.$(id -u)"
mkdir -p "$QROOT/scratch/marked-dead.qqqqqqqq"; mk_marker "$QROOT/scratch/marked-dead.qqqqqqqq" 424242
fill "$QROOT/scratch/marked-dead.qqqqqqqq/blob" 65536
: > "$LEDGER"
h_before="$(tree_hash "$FAKE_A" "$FAKE_B")"; l_before="$(sha256sum < "$LEDGER" | cut -d' ' -f1)"
rm -f "$LOCKFILE"
rc=0; purge_env bash "$PURGE" --report > "$TESTROOT/report.out" 2> "$TESTROOT/report.err" || rc=$?
h_after="$(tree_hash "$FAKE_A" "$FAKE_B")"; l_after="$(sha256sum < "$LEDGER" | cut -d' ' -f1)"
fam_row() { grep -F "family=$1 " "$TESTROOT/report.out" | head -1 || true; }   # first row for a family
kv() { printf '%s' "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2 || true; }

cases=$((cases + 1)); [[ "$rc" == "0" ]] && grep -c '^SOLEUR_TMP_PURGE_REPORT mode=report' "$TESTROOT/report.out" | grep -qx 1 \
  && pass "--report exits 0 and prints exactly one SOLEUR_TMP_PURGE_REPORT header" || fail "report rc=$rc: $(head -c 400 "$TESTROOT/report.out")"
cases=$((cases + 1)); [[ "$h_before" == "$h_after" && "$l_before" == "$l_after" ]] \
  && pass "--report mutated nothing (tree hash of both bases + ledger unchanged)" || fail "--report mutated the fixture tree or ledger"
cases=$((cases + 1)); [[ ! -e "$LOCKFILE" ]] \
  && pass "--report takes no lock (strictly read-only, no state-dir writes)" || fail "--report created the lockfile"
# mutation control: the hash must change when a node changes
: > "$FAKE_B/vac111/control"; h_ctl="$(tree_hash "$FAKE_A" "$FAKE_B")"; rm -f "$FAKE_B/vac111/control"
cases=$((cases + 1)); [[ "$h_ctl" != "$h_before" ]] \
  && pass "control: tree hash is sensitive to a one-file change" || fail "tree hash cannot see mutations (vacuous mutation proof)"
row="$(fam_row 'vac*')"
cases=$((cases + 1)); [[ "$(kv "$row" n)" == "2" && "$(kv "$row" kb)" -ge 256 && "$(kv "$row" git_kb)" == "0" && "$(kv "$row" nogit_kb)" -ge 256 ]] \
  && pass "vac* family: n=2, >=256 KiB, all bytes in the non-.git split" || fail "vac* row wrong: [$row]"
row="$(fam_row 'td-*')"
cases=$((cases + 1)); [[ "$row" == *"class=worktree:registered"* && "$(kv "$row" git_kb)" -ge 256 && "$(kv "$row" nogit_kb)" == "0" ]] \
  && pass "registered td-123 worktree reported as worktree:registered with its bytes in the .git split" || fail "td-* row wrong: [$row]"
row="$(fam_row 'perf-*')"
cases=$((cases + 1)); [[ "$row" == *"class=unattributable"* && "$(kv "$row" nogit_kb)" -ge 64 ]] \
  && pass "perf-* is visible as its own unattributable family (non-.git)" || fail "perf-* row wrong: [$row]"
cases=$((cases + 1)); [[ -z "$(grep -F 'marked-dead' "$TESTROOT/report.out" || true)" && -d "$QROOT/scratch/marked-dead.qqqqqqqq" ]] \
  && pass "quarantine root content is neither scanned nor touched by --report" || fail "report walked the quarantine root"
cases=$((cases + 1)); [[ -d "$FAKE_B/td-123" && -n "$(git --git-dir="$GITROOT/main/.git" worktree list --porcelain | grep -F 'td-123' || true)" ]] \
  && pass "registered td-123 worktree still present and still registered" || fail "td-123 worktree disturbed"
cases=$((cases + 1)); grep -c '^SOLEUR_TMP_PURGE_REPORT quarantine ' "$TESTROOT/report.out" | grep -qx 1 \
  && pass "report names the quarantine bytes awaiting drain" || fail "no quarantine line in report"

# More rows than SOLEUR_PURGE_REPORT_TOP must truncate cleanly: a `| head` in the
# table pipeline gave sort a SIGPIPE and, under pipefail, killed the report
# before the quarantine/done lines (measured on the operator host, 56 rows).
rc=0; purge_env SOLEUR_PURGE_REPORT_TOP=2 bash "$PURGE" --report > "$TESTROOT/report-top2.out" 2>/dev/null || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && grep -c 'REPORT done' "$TESTROOT/report-top2.out" | grep -qx 1 \
  && [[ "$(awk '/REPORT families/{f=1;next} /REPORT unattributable-families/{f=0} f' "$TESTROOT/report-top2.out" | grep -c 'family=')" == "2" ]] \
  && pass "TOP=2 truncates the family table to 2 rows and the report still completes" || fail "TOP=2 report rc=$rc: $(tail -c 300 "$TESTROOT/report-top2.out")"

# --- Arm 16: --older-than-days filters the report; --report-only flags refuse elsewhere
rc=0; purge_env bash "$PURGE" --report --older-than-days 30 > "$TESTROOT/report30.out" 2>/dev/null || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && [[ -n "$(grep -F 'family=oldx-* ' "$TESTROOT/report30.out" || true)" && -z "$(grep -F 'family=newx-* ' "$TESTROOT/report30.out" || true)" ]] \
  && pass "--older-than-days 30 keeps the 40d-old family, drops the fresh one" || fail "older-than filter wrong rc=$rc"
cases=$((cases + 1)); [[ -n "$(grep -F 'family=newx-* ' "$TESTROOT/report.out" || true)" ]] \
  && pass "control: without --older-than-days the fresh family is reported" || fail "fresh family missing from the unfiltered report"
rc=0; purge_env bash "$PURGE" --report --older-than-days 3x >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && pass "non-numeric --older-than-days refuses (rc 1)" || fail "bad --older-than-days rc=$rc"
rc=0; purge_env bash "$PURGE" --apply --older-than-days 30 >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" && -d "$FAKE_B/vac111" ]] && pass "--older-than-days refuses with --apply (report-only flag)" || fail "--apply accepted --older-than-days rc=$rc"
rc=0; purge_env bash "$PURGE" --apply --base "$FAKE_B" >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" && -d "$FAKE_B/vac111" ]] && pass "--base refuses with --apply (report-only seam)" || fail "--apply accepted --base rc=$rc"
rc=0; purge_env bash "$PURGE" --report --drain >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && pass "--report combined with --drain refuses" || fail "--report --drain rc=$rc"
# --base replaces the env bases and is repeatable
rc=0; purge_env bash "$PURGE" --report --base "$FAKE_A" > "$TESTROOT/report-base.out" 2>/dev/null || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -z "$(grep -F 'family=vac* ' "$TESTROOT/report-base.out" || true)" ]] \
  && pass "--base DIR overrides SOLEUR_PURGE_BASES (baseB families absent)" || fail "--base did not override rc=$rc"
rc=0; purge_env bash "$PURGE" --report --base "$FAKE_A" --base "$FAKE_B" > "$TESTROOT/report-base2.out" 2>/dev/null || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -n "$(grep -F 'family=vac* ' "$TESTROOT/report-base2.out" || true)" ]] \
  && pass "--base is repeatable (both bases scanned)" || fail "repeated --base failed rc=$rc"

# --- Arm 17: SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 --drain frees a FRESHLY quarantined entry
reset_fixtures
mkdir -p "$FAKE_B/rung2-archive.Fresh001"; : > "$FAKE_B/rung2-archive.Fresh001/git-data-bootstrap.sh"
mkdir -p "$FAKE_B/phantom-drain-src"; printf 'gitdir: %s\n' "$GITROOT/main/.git/worktrees/phantom" > "$FAKE_B/phantom-drain-src/.git"
purge_env bash "$PURGE" --apply >/dev/null 2>&1
Q="$FAKE_B/soleur-quarantine.$(id -u)"
cases=$((cases + 1)); [[ -d "$Q/prefix/rung2-archive.Fresh001" && -d "$Q/worktrees/phantom-drain-src" ]] \
  && pass "fixtures quarantined moments ago (prefix + worktrees classes)" || fail "drain-TTL fixtures not quarantined"
out="$(purge_env bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ -d "$Q/prefix/rung2-archive.Fresh001" ]] \
  && pass "control: default TTL retains a freshly quarantined entry" || fail "default drain removed a fresh entry: $out"
out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ ! -e "$Q/prefix/rung2-archive.Fresh001" ]] && printf '%s' "$out" | grep -q 'drain: 1 entry removed' \
  && pass "SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 --drain drains the fresh scratch entry (space recovery path)" || fail "TTL=0 drain no-op: $out"
cases=$((cases + 1)); [[ -d "$Q/worktrees/phantom-drain-src" ]] \
  && pass "TTL=0 seam does not shorten the worktrees class (separate TTL)" || fail "TTL=0 drained a worktrees entry"
cases=$((cases + 1)); grep -q $'drain\tprefix\t' "$LEDGER" \
  && pass "TTL=0 drain lands a ledger row" || fail "TTL=0 drain left no ledger row"

# --- Arm 18: nothing under the quarantine root is ever a scan/reap candidate -----
reset_fixtures
QR="$FAKE_A/soleur-quarantine.$(id -u)"
mkdir -p "$QR/scratch/marked-dead.zzzzzzzz"; mk_marker "$QR/scratch/marked-dead.zzzzzzzz" 424242
printf 'pid=424242\nschema=1\nns=%s\n' "$FAKE_NS" > "$QR/.soleur-owned"   # hostile: marker on the root itself
cls="$(env -i PATH="$PATH" HOME="$HOME" TMP_CLASSIFY_PROC="$FAKE_PROC" bash -c 'source "$1"; tc_classify_entry "$2"' _ "$REPO_ROOT/plugins/soleur/scripts/lib/tmp-classify.sh" "$QR")"
cases=$((cases + 1)); [[ "$cls" == "protected" ]] \
  && pass "classifier: quarantine root is protected even when it carries a dead-owner marker" || fail "quarantine root classified [$cls]"
h_q="$(tree_hash "$QR")"
purge_env bash "$PURGE" --apply >/dev/null 2>&1; purge_env bash "$PURGE" --report >/dev/null 2>&1
cases=$((cases + 1)); [[ "$h_q" == "$(tree_hash "$QR")" && -d "$QR/scratch/marked-dead.zzzzzzzz" ]] \
  && pass "apply + report leave everything under the quarantine root untouched" || fail "purge touched quarantine content"
cases=$((cases + 1)); [[ "$(grep -c 'soleur-run\.\*|soleur-quarantine\.\*' "$REPO_ROOT/scripts/tmpfs-guard.sh")" -ge 1 ]] \
  && pass "tmpfs-guard session sweep skips soleur-quarantine.* by name" || fail "sweep skip-case for the quarantine root is gone"
cases=$((cases + 1)); [[ "$(grep -c -- "-name 'soleur-run\.\*'" "$REPO_ROOT/scripts/tmpfs-guard.sh")" -ge 1 && "$(grep -c 'attest' "$REPO_ROOT/scripts/tmpfs-guard.sh" || true)" == "0" ]] \
  && pass "Reaper 3 candidates are soleur-run.* roots + depth-2 markers only; no attest path exists" || fail "Reaper 3 candidate set changed"

# --- Arm 19: an empty base is a clean no-op (rc 0), not a set -u crash -----------
reset_fixtures
rc=0; out="$(purge_env bash "$PURGE" --apply 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'SOLEUR_TMP_PURGE mode=apply' \
  && pass "--apply on empty bases exits 0 and prints the report" || fail "empty-base apply rc=$rc out=$out"
rc=0; out="$(purge_env bash "$PURGE" --report 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'REPORT done' \
  && pass "--report on empty bases exits 0" || fail "empty-base report rc=$rc out=$out"

# --- Conservation -------------------------------------------------------------------
MIN_ASSERTIONS=77   # anti-vacuity floor — a truncated run can't pass at 0/0
echo ""
echo "test-tmp-purge: $pass_n passed, $fails failed ($cases cases)"
[[ $((pass_n + fails)) -ge $MIN_ASSERTIONS && $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
