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
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT

[[ -f "$PURGE" ]] || { echo "ERROR: $PURGE missing" >&2; exit 1; }

FAKE_A="$TESTROOT/baseA"   # "tmpfs-class" sentinel
FAKE_B="$TESTROOT/baseB"   # "disk-class" sentinel
FAKE_PROC="$TESTROOT/proc"
LEDGER="$TESTROOT/ledger.log"
LOCKFILE="$TESTROOT/lock"
RETAIN_DIR="$TESTROOT/retain"
mkdir -p "$FAKE_A" "$FAKE_B" "$FAKE_PROC" "$RETAIN_DIR"

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

mk_marker() { # dir pid — writes a valid marker (no ns= so fake-proc runs pass)
  mkdir -p "$1"; printf 'pid=%s\nschema=1\n' "$2" > "$1/.soleur-owned"
}
mk_dead_proc() { :; }   # absent from $FAKE_PROC is dead by construction
mk_live_proc() { mkdir -p "$FAKE_PROC/$1"; }   # presence == alive under the seam

reset_fixtures() {
  rm -rf "$FAKE_A" "$FAKE_B"; mkdir -p "$FAKE_A" "$FAKE_B"
  rm -rf "$FAKE_PROC"; mkdir -p "$FAKE_PROC"
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

# --- Conservation -------------------------------------------------------------------
echo ""
echo "test-tmp-purge: $pass_n passed, $fails failed ($cases cases)"
[[ $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
