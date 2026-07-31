#!/usr/bin/env bash
# #7102 — the orphan reaper must not report a cleanup it did not perform.
#
# `cleanup_orphan_worktree_dirs` ran `rm -rf "$dir"` without checking the exit
# status and incremented `orphans_cleaned` unconditionally, so a directory it
# could not remove was still counted, still announced per-directory, and still
# folded into the "Cleaned N orphan directory(ies)" summary. The trigger is
# ordinary: the local Supabase stack bind-mounts as root and leaves
# root:root dirs inside an otherwise user-owned worktree, which an unprivileged
# `rm` cannot unlink. The class recurs for any worktree that ever started it.
#
# A third defect sits one line below the reported one: the function's last
# statement is `[[ "$verbose" == "true" ]] && echo …`, so a SUCCESSFUL clean at
# the default verbose=false returns rc=1 — and both call sites are bare inside
# `cleanup_merged_worktrees` under `set -e`, silently skipping the tmp reapers.
#
# Plan: knowledge-base/project/plans/2026-07-31-fix-honest-failure-reporting-hook-timeout-and-orphan-reaper-plan.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Every assertion below must run for the suite to mean anything. A preflight
# SKIP exits 0 BEFORE this point; reaching the end with fewer passes than this
# means assertions were silently skipped, which must not read as coverage.
MIN_PASS=20

# Case 2 leaves a `chmod 500` directory behind, which defeats a plain
# `rm -rf "$TMP"` cleanup exactly as it defeats the reaper. Restore write
# permission at the top of the trap or the suite litters TMPDIR every run.
TMP=$(mktemp -d)
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Preflight: root ignores permission bits, so the unremovable fixture
# cannot be constructed and case 2 would vacuously "pass". ---
if [[ $EUID -eq 0 ]]; then
  echo "SKIP: running as root — the chmod 500 unremovable fixture cannot be built"
  exit 0
fi

# --- Preflight: the sentinel maps GNU `rm` strerror text to an errno label.
# On a non-GNU host the label would be OTHER and the errno assertion is
# meaningless. Probe the real thing rather than guessing from `uname`. ---
probe="$TMP/.probe"; mkdir -p "$probe/inner"; : > "$probe/inner/f"; chmod 500 "$probe/inner"
probe_err=$(LC_ALL=C rm -rf -- "$probe" 2>&1 >/dev/null)
chmod -R u+rwX "$probe" 2>/dev/null; rm -rf "$probe"
if [[ "$probe_err" != *"Permission denied"* ]]; then
  echo "SKIP: non-GNU \`rm\` strerror (got: ${probe_err:-<empty>}) — errno mapping not assertable"
  exit 0
fi

# --- Stand up a real repo so `git worktree list --porcelain` returns a real
# registered path (the reaper's allowlist). Mirrors the sibling suites. ---
UPSTREAM="$TMP/upstream.git"
git init --bare -b main "$UPSTREAM" >/dev/null
SEED="$TMP/seed"
git clone "$UPSTREAM" "$SEED" >/dev/null 2>&1
( cd "$SEED" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null \
    && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED"

LOCAL="$TMP/local.git"
git init --bare -b main "$LOCAL" >/dev/null
( cd "$LOCAL" && git remote add origin "$UPSTREAM" && git fetch origin main:main >/dev/null 2>&1 )

cd "$LOCAL"
# shellcheck source=/dev/null
source "$WM"
set +e

strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

# Count directories directly under a WORKTREE_DIR (the reaper's own unit).
count_dirs() { find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

# Parse the reaper's own summary. Returns the integer it CLAIMS to have cleaned,
# or "none" when no summary was printed.
claimed_count() { grep -oE 'Cleaned [0-9]+ orphan' <<<"$1" | grep -oE '[0-9]+' || echo "none"; }

# ---------------------------------------------------------------------------
# Case 1 — the happy path still discriminates correctly.
#   plain-orphan     : no .git file, removable        -> reaped
#   registered       : a real registered worktree     -> preserved
#   has-git-file     : unregistered but has .git      -> preserved (needs prune)
# ---------------------------------------------------------------------------
echo "Case 1: discriminates orphan vs registered vs has-.git"
WORKTREE_DIR="$TMP/wt1"; mkdir -p "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR/plain-orphan/nested"; : > "$WORKTREE_DIR/plain-orphan/nested/f"
git -C "$LOCAL" worktree add "$WORKTREE_DIR/registered" -b c1 main >/dev/null 2>&1
mkdir -p "$WORKTREE_DIR/has-git-file"; echo "gitdir: /nowhere" > "$WORKTREE_DIR/has-git-file/.git"

out1=$(cleanup_orphan_worktree_dirs true 2>&1 | strip_ansi)

[[ "$(claimed_count "$out1")" == "1" ]] \
  && pass "claims exactly 1 cleaned" \
  || fail "claims $(claimed_count "$out1") cleaned, expected 1"
[[ ! -d "$WORKTREE_DIR/plain-orphan" ]] \
  && pass "plain orphan removed" \
  || fail "plain orphan survived"
[[ -d "$WORKTREE_DIR/registered" ]] \
  && pass "registered worktree preserved" \
  || fail "registered worktree was destroyed"
[[ -d "$WORKTREE_DIR/has-git-file" ]] \
  && pass "orphan with .git file preserved" \
  || fail "orphan with .git file was destroyed"

# ---------------------------------------------------------------------------
# Case 2 (RED) — an UNREMOVABLE orphan must not be counted or announced.
# `chmod 500` on an inner dir leaves it readable/traversable but not writable,
# so its entries cannot be unlinked and `rm -rf` fails EACCES.
# ---------------------------------------------------------------------------
echo "Case 2: unremovable orphan is reported honestly"
WORKTREE_DIR="$TMP/wt2"; mkdir -p "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR/stuck/inner"; : > "$WORKTREE_DIR/stuck/inner/f"
chmod 500 "$WORKTREE_DIR/stuck/inner"

# stdout only — the sentinel is specified to land on stdout (the stream agents grep).
out2=$(cleanup_orphan_worktree_dirs false 2>/dev/null | strip_ansi)
rc2=$?

[[ -d "$WORKTREE_DIR/stuck" ]] \
  && pass "unremovable dir survives (fixture is valid)" \
  || fail "fixture invalid — dir was removed, cannot test the failure path"
[[ "$(claimed_count "$out2")" != "1" ]] \
  && pass "does not claim a cleanup it did not perform" \
  || fail "claimed 1 cleaned while the directory is still on disk"
grep -q 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out2" \
  && pass "emits SOLEUR_ORPHAN_UNREMOVABLE sentinel on stdout" \
  || fail "no SOLEUR_ORPHAN_UNREMOVABLE sentinel on stdout"
grep -q 'errno=EACCES' <<<"$out2" \
  && pass "sentinel carries errno=EACCES" \
  || fail "sentinel missing errno=EACCES"
grep -q 'reason=rm-partial' <<<"$out2" \
  && pass "sentinel uses reason=rm-partial (rm -rf deletes what it can first)" \
  || fail "sentinel missing reason=rm-partial"
# The failure summary must print even at the DEFAULT verbose=false — that is
# the path session-start, work Phase 0, and ship Phase 7 actually run. Capture
# stderr SEPARATELY: asserting this against combined output is satisfied by the
# stdout sentinel (which contains the substring UNREMOVABLE) and would pass
# with the summary deleted entirely.
err2=$(cleanup_orphan_worktree_dirs false 2>&1 >/dev/null | strip_ansi)
grep -qE 'Could not remove [0-9]+ orphan directory' <<<"$err2" \
  && pass "failure summary prints on stderr at verbose=false" \
  || fail "failure summary suppressed at verbose=false (the default path)"
grep -qF "$WORKTREE_DIR/stuck" <<<"$err2" \
  && pass "failure summary names the surviving directory" \
  || fail "failure summary does not name the surviving directory"
grep -qF 'SKILL.md' <<<"$err2" \
  && pass "failure summary points at the remediation runbook" \
  || fail "failure summary has no remediation pointer"
# The remediation hint must not hand an agent a guardrail-bypassing command:
# `guardrails:block-rm-rf-worktrees` matches `rm -rf … .worktrees/` but NOT the
# docker-wrapped form, and this stream is what agents grep.
grep -q 'docker run' <<<"$out2" \
  && fail "hint contains a docker run string (bypasses guardrails:block-rm-rf-worktrees)" \
  || pass "hint contains no guardrail-bypassing docker command"
# The third lying surface: the per-directory line printed even on failure.
out2v=$(cleanup_orphan_worktree_dirs true 2>/dev/null | strip_ansi)
grep -q "Removed orphan directory: stuck" <<<"$out2v" \
  && fail "announces 'Removed orphan directory: stuck' for a dir still on disk" \
  || pass "no per-directory removal line for the surviving dir"

# ---------------------------------------------------------------------------
# Case 3 — counter integrity: the claimed count equals the observed delta.
# Mixed fixture so a counter that is merely always-0 or always-N cannot pass.
# ---------------------------------------------------------------------------
echo "Case 3: claimed count equals the find-verified removal delta"
WORKTREE_DIR="$TMP/wt3"; mkdir -p "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR/gone-a" "$WORKTREE_DIR/gone-b"
mkdir -p "$WORKTREE_DIR/stuck3/inner"; : > "$WORKTREE_DIR/stuck3/inner/f"
chmod 500 "$WORKTREE_DIR/stuck3/inner"

before3=$(count_dirs "$WORKTREE_DIR")
out3=$(cleanup_orphan_worktree_dirs true 2>/dev/null | strip_ansi)
after3=$(count_dirs "$WORKTREE_DIR")
delta3=$(( before3 - after3 ))
claim3=$(claimed_count "$out3")

[[ "$delta3" == "2" ]] \
  && pass "two removable orphans actually removed" \
  || fail "expected delta 2, observed $delta3"
[[ "$claim3" == "$delta3" ]] \
  && pass "claimed $claim3 == observed delta $delta3" \
  || fail "claimed $claim3 but only $delta3 directories actually disappeared"

# ---------------------------------------------------------------------------
# Case 4 (RED, defect 3) — the function must return 0 on every success path.
# Both call sites are bare inside `cleanup_merged_worktrees` under `set -e`, so
# a non-zero return on a SUCCESSFUL clean aborts the caller mid-flight and
# silently skips the tmp reapers that follow it.
# ---------------------------------------------------------------------------
echo "Case 4: returns 0 on every path (defect 3)"

WORKTREE_DIR="$TMP/wt4a"; mkdir -p "$WORKTREE_DIR/orphan-a"
cleanup_orphan_worktree_dirs false >/dev/null 2>&1; rc4a=$?
[[ "$rc4a" -eq 0 ]] \
  && pass "rc=0 for (cleaned>=1, verbose=false)" \
  || fail "rc=$rc4a for (cleaned>=1, verbose=false) — aborts its caller under set -e"

WORKTREE_DIR="$TMP/wt4b"; mkdir -p "$WORKTREE_DIR/orphan-b"
cleanup_orphan_worktree_dirs true >/dev/null 2>&1; rc4b=$?
[[ "$rc4b" -eq 0 ]] \
  && pass "rc=0 for (cleaned>=1, verbose=true)" \
  || fail "rc=$rc4b for (cleaned>=1, verbose=true)"

WORKTREE_DIR="$TMP/wt4c"; mkdir -p "$WORKTREE_DIR/stuck4/inner"
: > "$WORKTREE_DIR/stuck4/inner/f"; chmod 500 "$WORKTREE_DIR/stuck4/inner"
cleanup_orphan_worktree_dirs false >/dev/null 2>&1; rc4c=$?
[[ "$rc4c" -eq 0 ]] \
  && pass "rc=0 for (failed removal, verbose=false)" \
  || fail "rc=$rc4c for (failed removal, verbose=false)"

WORKTREE_DIR="$TMP/wt4d"; mkdir -p "$WORKTREE_DIR"
cleanup_orphan_worktree_dirs false >/dev/null 2>&1; rc4d=$?
[[ "$rc4d" -eq 0 ]] \
  && pass "rc=0 for (nothing to clean)" \
  || fail "rc=$rc4d for (nothing to clean)"

# ---------------------------------------------------------------------------
echo
echo "PASS=$PASS FAIL=$FAIL"

# Anti-vacuity parity: a preflight SKIP exits 0 above; reaching here with a
# short PASS count means assertions were silently dropped.
if [[ "$FAIL" -eq 0 && "$PASS" -lt "$MIN_PASS" ]]; then
  echo "FAIL: only $PASS assertions ran, expected >= $MIN_PASS (coverage regressed)"
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
