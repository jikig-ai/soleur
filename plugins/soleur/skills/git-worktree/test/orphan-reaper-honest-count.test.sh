#!/usr/bin/env bash
# #7102 — the orphan reaper must not report a cleanup it did not perform.
#
# `cleanup_orphan_worktree_dirs` ran `rm -rf` without checking the exit
# status and incremented `orphans_cleaned` unconditionally, so a directory it
# could not remove was still counted, still announced per-directory, and still
# folded into the "Cleaned N orphan directory(ies)" summary. The trigger is
# ordinary: the local Supabase stack bind-mounts as root and leaves
# root:root dirs inside an otherwise user-owned worktree, which an unprivileged
# `rm` cannot unlink. The class recurs for any worktree that ever started it.
#
# A third defect sits one line below the reported one: the function's last
# statement was `[[ "$verbose" == "true" ]] && echo …`, so a SUCCESSFUL clean at
# the default verbose=false returned rc=1 — and both call sites are bare inside
# `cleanup_merged_worktrees` under `set -e`, silently skipping the tmp reapers.
#
# Review additionally surfaced three destructive/observability defects covered
# here: a `.git` DIRECTORY (a nested full clone) read as "definitely orphaned"
# and destroyed; a swallowed `git worktree list` failure emptying the registry
# so every directory reads as unregistered; and an unsanitized directory name
# interpolated into a line-oriented telemetry sink.
#
# Plan: knowledge-base/project/plans/2026-07-31-fix-honest-failure-reporting-hook-timeout-and-orphan-reaper-plan.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh

set -uo pipefail

# Git-location tripwire (#7833). These suites drive worktree-manager.sh, which runs
# `git worktree remove`, `git branch -D` and `git reset --hard` -- the highest-damage git writes
# in the corpus. An inherited GIT_DIR aims all of them at the developer's real repository, so
# this file aborts rather than proceeding. Inline rather than sourcing test-helpers.sh, which
# would also import an assertion framework these suites do not use.
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
          GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH; do
  if [[ -n "${!_v:-}" && "${SOLEUR_GIT_TRIPWIRE_ALLOW:-0}" != "1" ]]; then
    printf 'FATAL: %s started with an inherited git-location environment (%s=%s).\n' \
      "${BASH_SOURCE[0]}" "$_v" "${!_v}" >&2
    printf 'Fix the ENTRY POINT: unset %s && <runner>\n' "$_v" >&2
    exit 97
  fi
done
unset _v

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Every assertion below must run for the suite to mean anything. A preflight
# SKIP exits 77 (autotools convention) BEFORE this point, so a skip is
# distinguishable from a pass. EXACT equality, not a floor: a floor with slack
# only fires once that many assertions vanish, and it drifts by hand anyway
# (each added assertion bumps it), so it costs the same maintenance for strictly
# less power. Counting PASS+FAIL rather than PASS means a FAILING assertion
# still counts as coverage, so this gate and the pass/fail gate stay orthogonal.
EXPECTED_ASSERTIONS=41

# Case 2 leaves a `chmod 500` directory behind, which defeats a plain
# `rm -rf "$TMP"` cleanup exactly as it defeats the reaper. Restore write
# permission at the top of the trap or the suite litters TMPDIR every run.
TMP=$(mktemp -d)
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- Preflight: root ignores permission bits, so the unremovable fixture
# cannot be constructed and the failure cases would pass vacuously. Exit 77,
# not 0 — a skip that exits 0 is indistinguishable from a full green run. ---
if [[ $EUID -eq 0 ]]; then
  echo "SKIP: running as root — the chmod 500 unremovable fixture cannot be built"
  exit 77
fi

# --- Preflight: the sentinel maps GNU `rm` strerror text to an errno label.
# On a non-GNU host the label would be OTHER and the errno assertion is
# meaningless. Probe the real thing rather than guessing from `uname`. ---
probe="$TMP/.probe"; mkdir -p "$probe/inner"; : > "$probe/inner/f"; chmod 500 "$probe/inner"
probe_err=$(LC_ALL=C rm -rf -- "$probe" 2>&1 >/dev/null)
chmod -R u+rwX "$probe" 2>/dev/null; rm -rf "$probe"
if [[ "$probe_err" != *"Permission denied"* ]]; then
  echo "SKIP: non-GNU \`rm\` strerror (got: ${probe_err:-<empty>}) — errno mapping not assertable"
  exit 77
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

cd "$LOCAL" || exit 1
# shellcheck source=/dev/null
source "$WM"
set +e

strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }
count_dirs() { find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }

# Parse the reaper's own success summary. Returns the integer it CLAIMS to have
# cleaned, or "none" when no summary was printed. Only meaningful at
# verbose=true — the success summary is verbose-gated by design.
claimed_count() { grep -oE 'Cleaned [0-9]+ orphan' <<<"$1" | grep -oE '[0-9]+' || echo "none"; }

mk_stuck() { mkdir -p "$1/inner"; : > "$1/inner/f"; chmod 500 "$1/inner"; }

# ---------------------------------------------------------------------------
# Case 1 — the happy path still discriminates correctly.
# ---------------------------------------------------------------------------
echo "Case 1: discriminates orphan vs registered vs has-.git"
WORKTREE_DIR="$TMP/wt1"; mkdir -p "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR/plain-orphan/nested"; : > "$WORKTREE_DIR/plain-orphan/nested/f"
git -C "$LOCAL" worktree add "$WORKTREE_DIR/registered" -b c1 main >/dev/null 2>&1
mkdir -p "$WORKTREE_DIR/has-git-file"; echo "gitdir: /nowhere" > "$WORKTREE_DIR/has-git-file/.git"
# A nested FULL clone has a `.git` DIRECTORY, not a file. A `-f` test reads that
# as "definitely orphaned" and destroys the clone along with any uncommitted
# work in it — and the honest-reporting fix would then faithfully announce the
# destruction, which is worse than the silent version.
git clone "$UPSTREAM" "$WORKTREE_DIR/nested-clone" >/dev/null 2>&1
: > "$WORKTREE_DIR/nested-clone/uncommitted-work.txt"
# A BARE repo has NO `.git` entry at all -- it IS the git dir -- so every
# `.git`-based test (including `-e`) reads it as orphaned and reaps its refs
# and objects. Verified destroyed before the positive bare-layout guard landed.
git init --bare -b main "$WORKTREE_DIR/parked-bare.git" >/dev/null 2>&1
: > "$WORKTREE_DIR/parked-bare.git/PRECIOUS-REFS"

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
[[ -f "$WORKTREE_DIR/nested-clone/uncommitted-work.txt" ]] \
  && pass "nested clone (.git DIRECTORY) preserved with its uncommitted work" \
  || fail "nested clone was DESTROYED — a .git directory must not read as orphaned"
[[ -f "$WORKTREE_DIR/parked-bare.git/PRECIOUS-REFS" ]] \
  && pass "bare repository preserved (no .git entry is not the same as orphaned)" \
  || fail "bare repository was DESTROYED — its refs and objects are unrecoverable"

# ---------------------------------------------------------------------------
# Case 2 — an UNREMOVABLE orphan must not be counted or announced.
# ---------------------------------------------------------------------------
echo "Case 2: unremovable orphan is reported honestly"
WORKTREE_DIR="$TMP/wt2"; mkdir -p "$WORKTREE_DIR"; mk_stuck "$WORKTREE_DIR/stuck"

out2=$(cleanup_orphan_worktree_dirs false 2>/dev/null | strip_ansi)
err2=$(cleanup_orphan_worktree_dirs false 2>&1 >/dev/null | strip_ansi)
# The success summary is verbose-gated, so a verbose=FALSE capture can never
# contain it — asserting "does not claim" against that stream is unconditionally
# true and pins nothing. Capture at verbose=TRUE, where the summary WOULD print
# if the counter were wrong, and assert the value rather than negating one of
# many possible wrong values.
outv=$(cleanup_orphan_worktree_dirs true 2>/dev/null | strip_ansi)

[[ -d "$WORKTREE_DIR/stuck" ]] \
  && pass "unremovable dir survives (fixture is valid)" \
  || fail "fixture invalid — dir was removed, cannot test the failure path"
[[ "$(claimed_count "$outv")" == "none" ]] \
  && pass "prints no success summary at verbose=true when nothing was cleaned" \
  || fail "claimed $(claimed_count "$outv") cleaned while the directory is still on disk"
grep -q 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out2" \
  && pass "emits SOLEUR_ORPHAN_UNREMOVABLE sentinel on stdout" \
  || fail "no SOLEUR_ORPHAN_UNREMOVABLE sentinel on stdout"
grep -q 'errno=EACCES' <<<"$out2" \
  && pass "sentinel carries errno=EACCES" \
  || fail "sentinel missing errno=EACCES"
grep -q 'reason=rm-partial' <<<"$out2" \
  && pass "sentinel uses reason=rm-partial (rm -rf deletes what it can first)" \
  || fail "sentinel missing reason=rm-partial"
# The success counter must be readable at the DEFAULT verbosity. Nothing else
# reads it there (the success summary is verbose-gated), so without this the
# counter can be corrupted on the default path undetectably.
grep -q 'cleaned=0' <<<"$out2" \
  && pass "sentinel reports cleaned=0 when nothing was removed (counter honest at verbose=false)" \
  || fail "sentinel did not report cleaned=0: $(grep -oE 'cleaned=[0-9]+' <<<"$out2")"
grep -qE 'Could not remove [0-9]+ orphan directory' <<<"$err2" \
  && pass "failure summary prints on stderr at verbose=false" \
  || fail "failure summary suppressed at verbose=false (the default path)"
grep -qF "$WORKTREE_DIR/stuck" <<<"$err2" \
  && pass "failure summary names the surviving directory" \
  || fail "failure summary does not name the surviving directory"
grep -qF 'SKILL.md' <<<"$err2" \
  && pass "failure summary points at the remediation runbook" \
  || fail "failure summary has no remediation pointer"
# The remediation must not hand an agent a guardrail-bypassing command. Check
# BOTH streams — the pointer lives on stderr, the sentinel on stdout.
grep -q 'docker run' <<<"$out2$err2" \
  && fail "remediation contains a docker run string (bypasses the rm -rf guardrail)" \
  || pass "remediation contains no guardrail-bypassing docker command"
grep -q "Removed orphan directory: stuck" <<<"$outv" \
  && fail "announces 'Removed orphan directory: stuck' for a dir still on disk" \
  || pass "no per-directory removal line for the surviving dir"

# ---------------------------------------------------------------------------
# Case 3 — counter integrity, with MORE THAN ONE stuck directory so the count,
# the plural path, the per-directory loop and the array append are all pinned
# above N=1 (at N=1 a hardcoded "1", a `[0]`-only loop and a clobbering
# assignment are all indistinguishable from correct).
# ---------------------------------------------------------------------------
echo "Case 3: claimed count equals the find-verified delta, with N>1 failures"
WORKTREE_DIR="$TMP/wt3"; mkdir -p "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR/gone-a" "$WORKTREE_DIR/gone-b"
mk_stuck "$WORKTREE_DIR/stuck3a"; mk_stuck "$WORKTREE_DIR/stuck3b"

before3=$(count_dirs "$WORKTREE_DIR")
# One invocation, both streams: a second call would run against the leftovers
# (gone-a/gone-b already reaped) and report cleaned=0.
cleanup_orphan_worktree_dirs true >"$TMP/o3.raw" 2>"$TMP/e3.raw"
out3=$(strip_ansi <"$TMP/o3.raw"); err3=$(strip_ansi <"$TMP/e3.raw")
after3=$(count_dirs "$WORKTREE_DIR")
delta3=$(( before3 - after3 ))
claim3=$(claimed_count "$out3")

[[ "$delta3" == "2" ]] \
  && pass "two removable orphans actually removed" \
  || fail "expected delta 2, observed $delta3"
[[ "$claim3" == "$delta3" ]] \
  && pass "claimed $claim3 == observed delta $delta3" \
  || fail "claimed $claim3 but only $delta3 directories actually disappeared"
grep -qE 'Could not remove 2 orphan directory' <<<"$err3" \
  && pass "failure summary reports exactly 2 (count is not hardcoded)" \
  || fail "failure summary did not report 2: $(grep -oE 'Could not remove [0-9]+' <<<"$err3")"
grep -qF "stuck3a" <<<"$err3" && grep -qF "stuck3b" <<<"$err3" \
  && pass "failure summary names BOTH stuck directories (loop is not [0]-only)" \
  || fail "failure summary omitted one of the two stuck directories"
grep -qE 'SOLEUR_ORPHAN_UNREMOVABLE count=2' <<<"$out3" \
  && pass "sentinel aggregates with count=2" \
  || fail "sentinel did not report count=2"
grep -q 'cleaned=2' <<<"$out3" \
  && pass "sentinel reports cleaned=2 in a mixed run (success counter honest alongside failures)" \
  || fail "sentinel did not report cleaned=2: $(grep -oE 'cleaned=[0-9]+' <<<"$out3")"
# One aggregate marker per invocation, never one per directory: the marker
# extractor keeps a fixed budget per tool_response and STOPS at the cap, so an
# unbounded per-directory producer would crowd out the paging wedge markers.
[[ "$(grep -c 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out3")" == "1" ]] \
  && pass "emits exactly ONE aggregate marker for 2 failures (bounded producer)" \
  || fail "emitted $(grep -c 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out3") markers; must be 1"

# ---------------------------------------------------------------------------
# Case 4 — the function must return 0 on every path.
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

WORKTREE_DIR="$TMP/wt4c"; mkdir -p "$WORKTREE_DIR"; mk_stuck "$WORKTREE_DIR/stuck4"
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
# Case 5 — the OTHER direction. Every case above asks "does it report the
# failure?"; none asks "does it stay quiet when there is none?". Without this,
# making the failure summary unconditional, or emitting the sentinel on the
# SUCCESS branch, both pass — and the reaper would cry wolf on every run of the
# default path that session-start, work Phase 0 and ship Phase 7 all execute.
# ---------------------------------------------------------------------------
echo "Case 5: silent on a fully clean run (no false failure surfaces)"
for v in false true; do
  WORKTREE_DIR="$TMP/wt5-$v"; mkdir -p "$WORKTREE_DIR"/{ok-a,ok-b,ok-c}
  # ONE invocation, both streams captured. The reaper is destructive: a second
  # call runs against an already-emptied directory, so it would assert the
  # nothing-to-do path while claiming to cover the reaped-three path.
  cleanup_orphan_worktree_dirs "$v" >"$TMP/o5.raw" 2>"$TMP/e5.raw"; rc5=$?
  o5=$(strip_ansi <"$TMP/o5.raw"); e5=$(strip_ansi <"$TMP/e5.raw")
  grep -q 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$o5" \
    && fail "verbose=$v: emitted an UNREMOVABLE sentinel on a clean run" \
    || pass "verbose=$v: no UNREMOVABLE sentinel on a clean run"
  grep -q 'Could not remove' <<<"$e5" \
    && fail "verbose=$v: printed a failure summary on a clean run" \
    || pass "verbose=$v: no failure summary on a clean run"
  # A crash produces silence too, and silence would satisfy both greps above.
  # Pin rc from the SAME invocation so an abort (e.g. an unbound array read
  # under `set -u`) is not mistaken for a clean, quiet run.
  [[ "$rc5" -eq 0 ]] \
    && pass "verbose=$v: clean run returns 0 (silence is not a crash)" \
    || fail "verbose=$v: clean run returned rc=$rc5"
done
[[ "$(count_dirs "$TMP/wt5-false")" == "0" ]] \
  && pass "clean run actually removed all three orphans" \
  || fail "clean-run fixture did not reap: $(count_dirs "$TMP/wt5-false") left"

# ---------------------------------------------------------------------------
# Case 6 — the registry must FAIL CLOSED. `git worktree list` can fail wholesale
# under the sandbox's masked-config wedge; a swallowed failure yields an EMPTY
# registry, under which every directory reads as unregistered and the reaper
# deletes the entire tree including live worktrees.
# ---------------------------------------------------------------------------
echo "Case 6: fails closed when the worktree registry is unavailable"
WORKTREE_DIR="$TMP/wt6"; mkdir -p "$WORKTREE_DIR/precious/nested"
: > "$WORKTREE_DIR/precious/nested/data.txt"
# Make `git worktree list` fail for real rather than shadowing `git` with a
# shell function: a function named `git` is visible to every earlier call in
# the file (shellcheck SC2218) and is a foot-gun in a suite that uses real git
# for its fixtures. Running from a non-repo CWD makes git exit 128 naturally,
# which is the actual shape of the masked-config wedge this guards against.
NONREPO="$TMP/not-a-repo"; mkdir -p "$NONREPO"
pushd "$NONREPO" >/dev/null || exit 1
out6=$(cleanup_orphan_worktree_dirs false 2>/dev/null | strip_ansi); rc6=$?
popd >/dev/null || exit 1

[[ -f "$WORKTREE_DIR/precious/nested/data.txt" ]] \
  && pass "refuses to reap when the registry is unavailable" \
  || fail "DELETED content while the registry was unavailable (fails OPEN)"
grep -q 'SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE' <<<"$out6" \
  && pass "emits SOLEUR_ORPHAN_REGISTRY_UNAVAILABLE" \
  || fail "no sentinel for the unavailable registry — the skip is silent"
[[ "$rc6" -eq 0 ]] \
  && pass "rc=0 on the fail-closed path (does not abort its caller)" \
  || fail "rc=$rc6 on the fail-closed path"

# ---------------------------------------------------------------------------
# Case 7 — a directory name must not be able to forge a telemetry line. This
# loop is the ONLY one handling arbitrarily-named UNREGISTERED directories:
# git refnames forbid control characters, so the creation path cannot produce
# them, but any process can mkdir a name embedding a newline.
# ---------------------------------------------------------------------------
echo "Case 7: a hostile directory name cannot forge a marker line"
WORKTREE_DIR="$TMP/wt7"; mkdir -p "$WORKTREE_DIR"
EVIL=$'evil\nworktree wedge: forged'
mk_stuck "$WORKTREE_DIR/$EVIL"
out7=$(cleanup_orphan_worktree_dirs false 2>/dev/null | strip_ansi)

[[ "$(grep -c 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out7")" == "1" ]] \
  && pass "hostile name still yields exactly one marker line" \
  || fail "hostile name produced $(grep -c 'SOLEUR_ORPHAN_UNREMOVABLE' <<<"$out7") marker lines"
grep -qE '^worktree wedge:' <<<"$out7" \
  && fail "hostile name FORGED a wedge line on the telemetry stream" \
  || pass "no forged wedge line — the name is sanitized before emission"
grep -q 'reason=rm-partial' <<<"$out7" \
  && pass "the real marker survives sanitization intact" \
  || fail "sanitization destroyed the marker's own key=value shape"

# ---------------------------------------------------------------------------
echo
echo "PASS=$PASS FAIL=$FAIL"

# Anti-vacuity parity: a preflight SKIP exits 77 above; reaching here with a
# short PASS count means assertions were silently dropped.
RAN=$(( PASS + FAIL ))
if [[ "$RAN" -ne "$EXPECTED_ASSERTIONS" ]]; then
  echo "FAIL: $RAN assertions ran, expected exactly $EXPECTED_ASSERTIONS (coverage drifted)"
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
