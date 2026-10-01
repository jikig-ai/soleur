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

# --- Real-state hygiene (#9339 review) -------------------------------------------
# The classifier resolves its ledger as SOLEUR_PURGE_LEDGER, else XDG_STATE_HOME, else
# $HOME/.local/state — so an invocation that forgets SOLEUR_PURGE_LEDGER appends rows to the
# OPERATOR's real ledger even under a private HOME if XDG_STATE_HOME is inherited. Every
# invocation below therefore pins HOME, XDG_STATE_HOME AND SOLEUR_PURGE_LEDGER privately, and
# the suite proves the real ledger(s) did not grow (size signature before/after the whole run).
PRIV_HOME="$TESTROOT/home"; PRIV_STATE="$TESTROOT/xdg-state"
mkdir -p "$PRIV_HOME" "$PRIV_STATE"
ledger_sig() { # path -> "absent" | byte size (GNU stat, BSD stat, wc fallback)
  if [[ -e "$1" ]]; then stat -c %s -- "$1" 2>/dev/null || stat -f %z -- "$1" 2>/dev/null || wc -c < "$1" | tr -d ' '; else echo absent; fi
}
REAL_LEDGERS=("${HOME:-/nonexistent}/.local/state/soleur/tmp-purge-ledger.log")
[[ -n "${XDG_STATE_HOME:-}" ]] && REAL_LEDGERS+=("$XDG_STATE_HOME/soleur/tmp-purge-ledger.log")
REAL_SIG_BEFORE=""
for _l in "${REAL_LEDGERS[@]}"; do REAL_SIG_BEFORE+="$_l=$(ledger_sig "$_l");"; done

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
  env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" \
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
out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" \
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
out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" \
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
rc=0; out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" SOLEUR_PURGE_LEDGER="$LEDGER" SOLEUR_PURGE_LOCKFILE="$LOCKFILE" SOLEUR_PURGE_BASES="" bash "$PURGE" --dry-run 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q 'FATAL' \
  && pass "empty bases env refuses loudly" || fail "empty bases rc=$rc out=$out"

# --base REPLACES the env list, so an empty SOLEUR_PURGE_BASES must not be fatal when --base is given
# (the header documents the replacement); the empty list stays fatal for every base-less mode above.
mkdir -p "$TESTROOT/base-only"
rc=0; out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" SOLEUR_PURGE_LEDGER="$LEDGER" SOLEUR_PURGE_BASES="" TMP_CLASSIFY_PROC="$FAKE_PROC" bash "$PURGE" --report --base "$TESTROOT/base-only" 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'REPORT done' \
  && pass "empty SOLEUR_PURGE_BASES + --report --base DIR runs (--base replaces the env list)" || fail "empty bases + --base rc=$rc out=$out"
rc=0; out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" SOLEUR_PURGE_LEDGER="$LEDGER" SOLEUR_PURGE_BASES="" bash "$PURGE" --report 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q 'FATAL' \
  && pass "control: empty SOLEUR_PURGE_BASES + --report WITHOUT --base is still fatal" || fail "empty bases + bare --report rc=$rc"

# --- Arm 14: symlinked quarantine root / class dir refuses the drain -------------
# The victim carries a real <class>/<entry> level and TTL=0 (every entry is past TTL): a drain that
# FOLLOWS the link would delete victim/prefix/precious. A fresh lone file (the previous fixture)
# could not distinguish a guarded drain from an unguarded one — the guards were deletable green.
reset_fixtures
VICT="$TESTROOT/victim-tree"; assert_fixture_dir "$VICT"; rm -rf "$VICT"
mkdir -p "$VICT/prefix/precious"; : > "$VICT/prefix/precious/data"; : > "$VICT/keep"
ln -s "$VICT" "$FAKE_A/soleur-quarantine.$(id -u)"
out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ -f "$VICT/keep" && -f "$VICT/prefix/precious/data" ]] \
  && pass "symlinked quarantine root — TTL=0 drain refuses, aged target entries untouched" \
  || fail "drain followed symlinked quarantine root: $out"
# symlinked CLASS dir under a real quarantine root, with a real sibling class as the live control
reset_fixtures
VICT2="$TESTROOT/victim-class"; assert_fixture_dir "$VICT2"; rm -rf "$VICT2"
mkdir -p "$VICT2/precious"; : > "$VICT2/precious/data"
QD="$FAKE_A/soleur-quarantine.$(id -u)"; mkdir -p "$QD/scratch/ctl-entry"; chmod 0700 "$QD"
ln -s "$VICT2" "$QD/prefix"
out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ -f "$VICT2/precious/data" ]] \
  && pass "symlinked CLASS dir — TTL=0 drain refuses, target entries untouched" || fail "drain followed a symlinked class dir: $out"
cases=$((cases + 1)); [[ ! -e "$QD/scratch/ctl-entry" ]] \
  && pass "control: the same drain DOES remove an entry under a real class dir (the fixture is drainable)" || fail "control entry survived — the drain did nothing, arm 14 would be vacuous: $out"

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
cls="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" SOLEUR_PURGE_LEDGER="$LEDGER" TMP_CLASSIFY_PROC="$FAKE_PROC" bash -c 'source "$1"; tc_classify_entry "$2"' _ "$REPO_ROOT/plugins/soleur/scripts/lib/tmp-classify.sh" "$QR")"
cases=$((cases + 1)); [[ "$cls" == "protected" ]] \
  && pass "classifier: quarantine root is protected even when it carries a dead-owner marker" || fail "quarantine root classified [$cls]"
h_q="$(tree_hash "$QR")"
purge_env bash "$PURGE" --apply >/dev/null 2>&1; purge_env bash "$PURGE" --report >/dev/null 2>&1
cases=$((cases + 1)); [[ "$h_q" == "$(tree_hash "$QR")" && -d "$QR/scratch/marked-dead.zzzzzzzz" ]] \
  && pass "apply + report leave everything under the quarantine root untouched" || fail "purge touched quarantine content"
# Reaper 3 BEHAVIOUR probe (replaces two source greps that broke on any comment and proved nothing):
# source the guard and run reap_orphan_scratch_roots over a fixture base holding (a) the quarantine
# root with dead-owner content + a hostile root marker, (b) a dead-owner marker dir one level too
# deep, (c) an undeclared look-alike dir, and (d) a dead-owner soleur-run.* root as the LIVE
# control. Only (d) may go; everything else must be byte-identical afterwards.
reset_fixtures
QR="$FAKE_A/soleur-quarantine.$(id -u)"
mkdir -p "$QR/scratch/marked-dead.zzzzzzzz"; mk_marker "$QR/scratch/marked-dead.zzzzzzzz" 424242
printf 'pid=424242\nschema=1\nns=%s\n' "$FAKE_NS" > "$QR/.soleur-owned"
mkdir -p "$FAKE_A/x/marked-dead.eeeeeeee"; mk_marker "$FAKE_A/x/marked-dead.eeeeeeee" 424242; : > "$FAKE_A/x/marked-dead.eeeeeeee/f"
mkdir -p "$FAKE_A/attest-fake.ffffffff"; : > "$FAKE_A/attest-fake.ffffffff/f"
mkdir -p "$FAKE_A/soleur-run.424242.cccccccc"; : > "$FAKE_A/soleur-run.424242.cccccccc/f"
h_keep="$(tree_hash "$QR" "$FAKE_A/x" "$FAKE_A/attest-fake.ffffffff")"
guard_out="$(env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$PRIV_STATE" SOLEUR_PURGE_LEDGER="$LEDGER" \
  TMPFS_GUARD_SCRATCH_BASES="$FAKE_A" TMPFS_GUARD_PROC="$FAKE_PROC" TMPFS_GUARD_SCRATCH_AGE_MIN=0 \
  TMPFS_GUARD_LOG_SINK="$TESTROOT/guard.log" TMPFS_GUARD_ALARM_FILE="$TESTROOT/guard-alarms.log" \
  TMPFS_GUARD_HEARTBEAT_FILE="$TESTROOT/guard-heartbeat" TMPFS_GUARD_WATERMARK_FILE="$TESTROOT/guard-watermark" \
  TMPFS_GUARD_LOCKFILE="$TESTROOT/guard.lock" \
  bash -c 'source "$1"; reap_orphan_scratch_roots' _ "$REPO_ROOT/scripts/tmpfs-guard.sh" 2>&1)" || true
cases=$((cases + 1)); [[ ! -e "$FAKE_A/soleur-run.424242.cccccccc" ]] \
  && pass "control: Reaper 3 reclaims the dead-owner soleur-run.* root (the probe is live)" || fail "Reaper 3 did not reap the control root — behavioural probe is vacuous: $guard_out"
cases=$((cases + 1)); [[ "$h_keep" == "$(tree_hash "$QR" "$FAKE_A/x" "$FAKE_A/attest-fake.ffffffff")" && -d "$QR/scratch/marked-dead.zzzzzzzz" && -d "$FAKE_A/x/marked-dead.eeeeeeee" && -d "$FAKE_A/attest-fake.ffffffff" ]] \
  && pass "Reaper 3 leaves the quarantine root, a too-deep marker dir and an undeclared look-alike byte-identical" || fail "Reaper 3 touched a non-candidate: $guard_out"

# --- Arm 19: an empty base is a clean no-op (rc 0), not a set -u crash -----------
reset_fixtures
rc=0; out="$(purge_env bash "$PURGE" --apply 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'SOLEUR_TMP_PURGE mode=apply' \
  && pass "--apply on empty bases exits 0 and prints the report" || fail "empty-base apply rc=$rc out=$out"
rc=0; out="$(purge_env bash "$PURGE" --report 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'REPORT done' \
  && pass "--report on empty bases exits 0" || fail "empty-base report rc=$rc out=$out"

# --- Arm 20: report accuracy arms (entries=, leading-zero days, unreadable subtree, flag shapes) ---
reset_fixtures
Q20="$FAKE_B/soleur-quarantine.$(id -u)"
mkdir -p "$Q20/scratch/e1" "$Q20/scratch/e2" "$Q20/prefix/e3"
fill "$Q20/scratch/e1/blob" 8192
mkdir -p "$FAKE_B/oldx-9876" "$FAKE_B/newx-9876"
fill "$FAKE_B/oldx-9876/blob" 65536; fill "$FAKE_B/newx-9876/blob" 65536
touch -d '-40 days' "$FAKE_B/oldx-9876/blob" "$FAKE_B/oldx-9876"
rc=0; purge_env bash "$PURGE" --report --base "$FAKE_B" > "$TESTROOT/r20.out" 2>/dev/null || rc=$?
qline="$(grep '^SOLEUR_TMP_PURGE_REPORT quarantine ' "$TESTROOT/r20.out" || true)"
cases=$((cases + 1)); [[ "$rc" == "0" && "$qline" == *" entries=3 "* ]] \
  && pass "quarantine line counts exactly the 3 <class>/<entry> rows (entries=3)" || fail "entries= wrong rc=$rc line=[$qline]"
mkdir -p "$Q20/prefix/e4"
purge_env bash "$PURGE" --report --base "$FAKE_B" > "$TESTROOT/r20b.out" 2>/dev/null || true
cases=$((cases + 1)); grep '^SOLEUR_TMP_PURGE_REPORT quarantine ' "$TESTROOT/r20b.out" | grep -q ' entries=4 ' \
  && pass "control: entries= follows the fixture (adding a row moves 3 -> 4)" || fail "entries= did not follow the fixture"
cases=$((cases + 1)); grep -q 'kb=' <<< "$qline" && printf '%s' "$qline" | grep -Eq 'kb=[0-9]+' \
  && pass "quarantine line carries a numeric kb=" || fail "quarantine kb= missing: [$qline]"
cases=$((cases + 1)); grep -q '^SOLEUR_TMP_PURGE_REPORT note kb=' "$TESTROOT/r20.out" \
  && pass "report states what kb means (allocated blocks, own-uid, shared extents, unreadable dropped)" || fail "report has no honest kb note"

# A leading-zero day count is DECIMAL 8 (never octal-parsed): accepted, normalized, and it filters.
for dd in 08 09; do
  rc=0; purge_env bash "$PURGE" --report --base "$FAKE_B" --older-than-days "$dd" > "$TESTROOT/r20d.out" 2> "$TESTROOT/r20d.err" || rc=$?
  cases=$((cases + 1)); [[ "$rc" == "0" ]] && grep -q "older_than_days=${dd#0} " "$TESTROOT/r20d.out" && grep -c 'REPORT done' "$TESTROOT/r20d.out" | grep -qx 1 \
    && [[ -n "$(grep -F 'family=oldx-* ' "$TESTROOT/r20d.out" || true)" && -z "$(grep -F 'family=newx-* ' "$TESTROOT/r20d.out" || true)" ]] \
    && pass "--older-than-days $dd is accepted as ${dd#0}: header normalized, 40d family kept, fresh family dropped" || fail "--older-than-days $dd rc=$rc err=$(head -c 200 "$TESTROOT/r20d.err")"
done
rc=0; purge_env bash "$PURGE" --report --older-than-days 99999999999999999999 >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && pass "an absurd --older-than-days (arithmetic overflow bait) refuses (rc 1)" || fail "overlong --older-than-days rc=$rc"

# Unreadable subtree under the quarantine root must not abort the report (set -e + pipefail): the
# footer survives and the dropped subtree is counted. Root bypasses mode bits, so skip there.
cases=$((cases + 1))
if [[ "$(id -u)" == "0" ]]; then
  pass "unreadable-subtree arm skipped (running as root; mode bits are not enforced)"
else
  mkdir -p "$Q20/scratch/e1/locked/inner"; : > "$Q20/scratch/e1/locked/inner/f"; chmod 000 "$Q20/scratch/e1/locked"
  chmod 000 "$Q20/prefix"   # a whole class dir unreadable: the depth-2 `find` (entries=) fails too, not just du
  rc=0; purge_env bash "$PURGE" --report --base "$FAKE_B" > "$TESTROOT/r20u.out" 2>/dev/null || rc=$?
  chmod 755 "$Q20/scratch/e1/locked" "$Q20/prefix"
  uline="$(grep '^SOLEUR_TMP_PURGE_REPORT quarantine ' "$TESTROOT/r20u.out" || true)"
  if [[ "$rc" == "0" ]] && grep -c 'REPORT done' "$TESTROOT/r20u.out" | grep -qx 1 && [[ "$uline" == *"skipped_unreadable="[1-9]* ]]; then
    pass "unreadable quarantine subtree: report still completes (rc 0, footer present) and counts skipped_unreadable"
  else fail "unreadable quarantine subtree aborted or hid the loss: rc=$rc line=[$uline] tail=$(tail -c 200 "$TESTROOT/r20u.out")"; fi
fi

# Flag shapes. --base with whitespace cannot survive the space-separated list: refuse, don't split.
mkdir -p "$TESTROOT/with space"
rc=0; purge_env bash "$PURGE" --report --base "$TESTROOT/with space" >/dev/null 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "1" ]] && pass "--base DIR containing whitespace refuses (rc 1)" || fail "whitespace --base rc=$rc"
# Every explicit mode, placed BEFORE --report, must still be refused as a combination.
for m in --apply --dry-run --restore --drain; do
  rc=0; purge_env bash "$PURGE" "$m" --report >/dev/null 2>&1 || rc=$?
  cases=$((cases + 1)); [[ "$rc" == "1" ]] && pass "$m --report refuses (explicit mode set before --report)" || fail "$m --report rc=$rc (EXPLICIT_MODE not set by $m?)"
done
# A glob character in --base is a literal path, never expanded against the cwd/filesystem.
GL="$TESTROOT/glb"; mkdir -p "$GL-one/vacG1"; fill "$GL-one/vacG1/blob" 4096
rc=0; purge_env bash "$PURGE" --report --base "$GL*" > "$TESTROOT/r20g.out" 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -z "$(grep -F 'family=vacG*' "$TESTROOT/r20g.out" || true)" && -n "$(grep -F 'missing or a symlink' "$TESTROOT/r20g.out" || true)" ]] \
  && pass "--base 'glb*' is a literal (missing) path — never glob-expanded into $GL-one" || fail "--base glob was expanded rc=$rc: $(head -c 300 "$TESTROOT/r20g.out")"
rc=0; purge_env bash "$PURGE" --report --base "$GL-one" > "$TESTROOT/r20g2.out" 2>&1 || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -n "$(grep -F 'family=vacG' "$TESTROOT/r20g2.out" || true)" ]] \
  && pass "control: the literal base is scanned (the glob arm above is not vacuous)" || fail "control literal base not scanned"

# --- Arm 21: quarantine TTL env values are validated, never evaluated as arithmetic -------------
# Bad values must NOT drain a fresh entry (nor abort): fall back to the default TTL with a WARN.
reset_fixtures
mkdir -p "$FAKE_B/rung2-archive.TtlVal01"; : > "$FAKE_B/rung2-archive.TtlVal01/git-data-bootstrap.sh"
mkdir -p "$FAKE_B/phantom-ttl-src"; printf 'gitdir: %s\n' "$GITROOT/main/.git/worktrees/phantom" > "$FAKE_B/phantom-ttl-src/.git"
purge_env bash "$PURGE" --apply >/dev/null 2>&1
Q21="$FAKE_B/soleur-quarantine.$(id -u)"
cases=$((cases + 1)); [[ -d "$Q21/prefix/rung2-archive.TtlVal01" && -d "$Q21/worktrees/phantom-ttl-src" ]] \
  && pass "TTL fixtures quarantined moments ago (scratch + worktrees classes)" || fail "TTL fixtures not quarantined"
# Each TTL is validated on its own: bad scratch TTL with a good worktrees TTL and vice versa, so a
# dropped validation on ONE of them cannot hide behind the other's WARN.
for bad in -1 abc 7d 1.5 " 0"; do
  for which in SCRATCH WT; do
    rc=0; out="$(purge_env "SOLEUR_PURGE_QUAR_${which}_TTL_MIN=$bad" bash "$PURGE" --drain 2>&1)" || rc=$?
    case "$which" in SCRATCH) want='scratch TTL' ;; *) want='worktrees TTL' ;; esac
    cases=$((cases + 1))
    [[ "$rc" == "0" && -d "$Q21/prefix/rung2-archive.TtlVal01" && -d "$Q21/worktrees/phantom-ttl-src" ]] && printf '%s' "$out" | grep -q "WARN.*$want" \
      && pass "TTL_${which} '$bad' is rejected with a WARN naming the $want, default applies, fresh entries kept" || fail "TTL_${which} '$bad' drained/aborted/no WARN rc=$rc: $out"
  done
done
rc=0; out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN= SOLEUR_PURGE_QUAR_WT_TTL_MIN= bash "$PURGE" --drain 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -d "$Q21/prefix/rung2-archive.TtlVal01" && -d "$Q21/worktrees/phantom-ttl-src" ]] \
  && pass "empty TTL env falls to the default (fresh entries kept, no abort)" || fail "empty TTL env drained or aborted rc=$rc: $out"
rc=0; out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=08 SOLEUR_PURGE_QUAR_WT_TTL_MIN=09 bash "$PURGE" --drain 2>&1)" || rc=$?
cases=$((cases + 1)); [[ "$rc" == "0" && -d "$Q21/prefix/rung2-archive.TtlVal01" && -d "$Q21/worktrees/phantom-ttl-src" ]] && ! printf '%s' "$out" | grep -qi 'too great\|syntax\|error' \
  && pass "TTL '08'/'09' are decimal minutes (no octal arithmetic error); fresh entries kept" || fail "TTL 08 octal-parsed rc=$rc: $out"
out="$(purge_env SOLEUR_PURGE_QUAR_SCRATCH_TTL_MIN=0 bash "$PURGE" --drain 2>&1)"
cases=$((cases + 1)); [[ ! -e "$Q21/prefix/rung2-archive.TtlVal01" && -d "$Q21/worktrees/phantom-ttl-src" ]] \
  && pass "control: a VALID TTL=0 still drains the scratch entry (and only that class)" || fail "valid TTL=0 no longer drains: $out"

# --- Arm 22: the suite never wrote the operator's real ledger -----------------------------------
# Sensitivity control first: with SOLEUR_PURGE_LEDGER unset, a private XDG_STATE_HOME is where the
# classifier appends — proving (a) XDG_STATE_HOME is the leak vector and (b) the size signature
# moves when rows are appended, so an unchanged real signature is evidence, not a blind spot.
reset_fixtures
CTLSTATE="$TESTROOT/ctl-state"; mkdir -p "$CTLSTATE"
CTL_LEDGER="$CTLSTATE/soleur/tmp-purge-ledger.log"
sig_ctl_before="$(ledger_sig "$CTL_LEDGER")"
mkdir -p "$FAKE_A/rung2-archive.LedgerCtl1"; : > "$FAKE_A/rung2-archive.LedgerCtl1/git-data-bootstrap.sh"
env -i PATH="$PATH" HOME="$PRIV_HOME" XDG_STATE_HOME="$CTLSTATE" SOLEUR_PURGE_BASES="$FAKE_A" SOLEUR_PURGE_LOCKFILE="$LOCKFILE" \
  TMP_CLASSIFY_PROC="$FAKE_PROC" TMP_CLASSIFY_AGE_FLOOR_MIN=0 TMP_CLASSIFY_RETAIN_DIR="$RETAIN_DIR" bash "$PURGE" --apply >/dev/null 2>&1 || true
cases=$((cases + 1)); [[ "$sig_ctl_before" == "absent" && "$(ledger_sig "$CTL_LEDGER")" != "absent" && "$(ledger_sig "$CTL_LEDGER")" -gt 0 ]] \
  && pass "control: XDG_STATE_HOME alone redirects the ledger and the size signature sees the appended row" || fail "ledger-leak control did not observe an append (sig=$(ledger_sig "$CTL_LEDGER"))"
REAL_SIG_AFTER=""
for _l in "${REAL_LEDGERS[@]}"; do REAL_SIG_AFTER+="$_l=$(ledger_sig "$_l");"; done
cases=$((cases + 1)); [[ "$REAL_SIG_BEFORE" == "$REAL_SIG_AFTER" ]] \
  && pass "the operator's real ledger(s) are byte-size-identical across the whole run" || fail "REAL LEDGER CHANGED during the suite: before=[$REAL_SIG_BEFORE] after=[$REAL_SIG_AFTER]"

# --- Conservation -------------------------------------------------------------------
EXPECTED_CASES=112   # exact case count — a dropped arm or truncated run cannot pass; bump in lockstep
echo ""
echo "test-tmp-purge: $pass_n passed, $fails failed ($cases cases)"
# Exact compare + exit, deliberately not routed through pass()/fail().
[[ "$cases" -eq "$EXPECTED_CASES" ]] || { printf 'FAIL: ran %s cases, expected exactly %s\n' "$cases" "$EXPECTED_CASES" >&2; exit 1; }
[[ $((pass_n + fails)) -eq $cases && $fails -eq 0 ]]
