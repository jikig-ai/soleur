#!/usr/bin/env bash
# Guard 2, unit arm — tests for scripts/lib/repo-write-boundary.sh (#7652).
#
# WHAT THIS FILE IS FOR. `scripts/test-all.sh` claims, in capitals, that "A SUITE WROTE TO THE
# LIVE REPOSITORY" — while inspecting only `git rev-parse HEAD` and `git status --porcelain`.
# Those two are structurally blind to the write that motivated the claim: on 2026-08-20 a fixture
# put `commit.gpgsign=false` into the SHARED bare-repo config, which touches neither HEAD nor the
# porcelain, and six commits were then created unsigned across every worktree on the machine. A
# message that names a cause its check cannot observe is an ADR-166 violation; the fix is to widen
# the check and RENDER the claim from what was actually measured, never from a literal list.
#
# So the properties under test here are not "does it hash things". They are:
#   (a) each dimension actually SEES its own write class (config, refs, HEAD, worktree);
#   (b) the carve-outs remove ONLY tooling churn, and specifically do NOT remove `branch.*.remote`
#       / `.merge`, which `git push -u` and `checkout -b --track` write and which are therefore the
#       one config trace a `git -C "" checkout -b` escape leaves behind;
#   (c) no config VALUE ever reaches the output — the digest is not an optimisation, it is what
#       keeps `credential.*` and `http.*.extraheader` out of a log that gets pasted into issues;
#   (d) the manifest is the single source of truth for the rendered claim, so a narrowed check
#       narrows the claim with it.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/repo-write-boundary.sh"

TMP_ROOT=$(mktemp -d -t repowriteboundary.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 2; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root '$TMP_ROOT'" >&2; exit 2; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

passes=0; fails=0; asserted=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }
# Incremented at the CALL SITE, never inside pass()/fail(): the conservation check at the bottom
# exists to detect a neutered verdict helper, and a counter living inside the helper it polices
# cannot do that (ADR-193).
ck() { asserted=$((asserted + 1)); }

[[ -f "$LIB" ]] || { echo "FATAL: missing $LIB" >&2; exit 2; }

# A probe repository, standing in for "the caller's live repo". Every case operates on a FRESH
# one: a case that inherits the previous case's writes measures the wrong delta.
new_probe() { # new_probe <name> -> prints an absolute path
  # Two statements, not one `local a=.. b=$a`: bash expands every word of a `local` before it
  # performs any of its assignments, so the second would read an unbound `$name` under `set -u`.
  local name="${1:?probe name required}"
  local d="$TMP_ROOT/$name"
  mkdir -p "$d" || return 1
  git -C "$d" init -q -b main || return 1
  git -C "$d" config user.email t@t.dev || return 1
  git -C "$d" config user.name t || return 1
  git -C "$d" commit -q --allow-empty -m seed || return 1
  printf '%s\n' "$d"
}

# Snapshot the probe by running the lib with the probe as CWD. `state` sets STATE_OUT / STATE_RC
# in the CALLER's scope rather than returning through `$( )`: a subshell would discard them, which
# is the very defect class this branch exists to close.
state() { # state <dir> [extra env assignments...]
  local dir="${1:?dir required}"; shift
  STATE_OUT=$(cd "$dir" && env REPO_BOUNDARY_SALT=fixed-test-salt "$@" \
    bash -c 'source "'"$LIB"'"; _repo_state' 2>"$TMP_ROOT/err")
  STATE_RC=$?
  STATE_ERR=$(cat "$TMP_ROOT/err")
}

echo "repo-write-boundary.test.sh"

# --- 1. The named function set is defined ------------------------------------------------
# Mirrors the _TC_LIB shape: `test -f` proves a file exists, never that it defines what the
# caller will call. A STALE lib must be named, not silently narrow the gate.
ck
missing=""
for fn in _repo_state repo_boundary_dimensions repo_boundary_manifest \
          repo_boundary_render_inspected repo_boundary_render_not_inspected \
          repo_boundary_classify; do
  bash -c 'source "'"$LIB"'"; declare -F '"$fn"' >/dev/null' || missing="$missing $fn"
done
if [[ -z "$missing" ]]; then pass "every named function is defined"
else fail "lib is missing:$missing"; fi

# --- 2. The manifest names all four dimensions -------------------------------------------
ck
p=$(new_probe manifest) || { echo "FATAL: probe setup failed" >&2; exit 2; }
man=$(cd "$p" && bash -c 'source "'"$LIB"'"; _repo_state >/dev/null; repo_boundary_manifest')
if [[ "$(printf '%s\n' "$man" | awk '{print $1}' | sort | tr '\n' ' ')" == "config head refs worktree " ]]; then
  pass "manifest enumerates head, worktree, config, refs"
else
  fail "manifest dimensions wrong: $(printf '%s' "$man" | tr '\n' '|')"
fi

# --- 3. A clean re-read is stable ----------------------------------------------------------
ck
p=$(new_probe stable) || exit 2
state "$p"; a="$STATE_OUT"; arc=$STATE_RC
state "$p"; b="$STATE_OUT"
if [[ $arc -eq 0 && "$a" == "$b" && -n "$a" ]]; then pass "two reads of an unchanged repo are identical"
else fail "unstable snapshot (rc=$arc)"; fi

# --- 4. ROW 1 — a shared-config write is SEEN ----------------------------------------------
# The instance-1 regression. This is the write the narrow form cannot see, and the entire reason
# this lib exists.
ck
p=$(new_probe cfgwrite) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" config --local commit.gpgsign false
state "$p"; after="$STATE_OUT"
if [[ "$before" != "$after" ]]; then pass "a git config --local write changes the snapshot"
else fail "config write invisible — this is the #7652 instance-1 regression"; fi

# --- 5. ROW 1 control — the NARROW form does NOT see it -------------------------------------
# AC2's control arm. Without this, "the widened form reports it" is a claim with no contrast.
ck
p=$(new_probe cfgnarrow) || exit 2
narrow() { (cd "$1" && git rev-parse HEAD 2>/dev/null && git status --porcelain 2>/dev/null | sha256sum); }
nb=$(narrow "$p")
git -C "$p" config --local commit.gpgsign false
na=$(narrow "$p")
if [[ "$nb" == "$na" ]]; then pass "control: the pre-#7652 narrow snapshot is blind to a config write"
else fail "control invalid — the narrow form saw the config write"; fi

# --- 6. ROW 10 / AC7 — no config VALUE reaches the output -----------------------------------
# Asserted against BOTH key families that carry a credential in the wild: `credential.*` (local
# dev) and `http.*.extraheader` (the CI vector — this is how Actions injects its token).
ck
p=$(new_probe secrets) || exit 2
git -C "$p" config --local credential.helper 'store --file=/tmp/SECRET-HELPER-VALUE'
git -C "$p" config --local http.https://example.invalid/.extraheader 'Authorization: basic SECRET-CI-TOKEN'
state "$p"
leaked=""
grep -qF 'SECRET-HELPER-VALUE' <<<"$STATE_OUT" && leaked="$leaked credential.helper"
grep -qF 'SECRET-CI-TOKEN'    <<<"$STATE_OUT" && leaked="$leaked http.extraheader"
if [[ -z "$leaked" ]]; then pass "no config value reaches the output (credential.* and http.*.extraheader)"
else fail "config VALUE leaked into boundary output:$leaked"; fi

# --- 7. ... but the KEY NAME is kept, and a value CHANGE is still detected -------------------
# Digesting must not degrade into discarding: a snapshot that drops values entirely would go blind
# to `commit.gpgsign` flipping true->false, which is instance 1 with an extra step.
ck
p=$(new_probe valuechange) || exit 2
git -C "$p" config --local commit.gpgsign true
state "$p"; before="$STATE_OUT"
git -C "$p" config --local commit.gpgsign false
state "$p"; after="$STATE_OUT"
if [[ "$before" != "$after" ]] && grep -q 'commit.gpgsign' <<<"$after"; then
  pass "a value CHANGE is detected and the key name is retained"
else
  fail "value change undetected or key name dropped"
fi

# --- 8. Must-PASS — branch.*.vscode-merge-base is carved out ---------------------------------
ck
p=$(new_probe vscode) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" config --local branch.main.vscode-merge-base origin/main
state "$p"; after="$STATE_OUT"
if [[ "$before" == "$after" ]]; then pass "branch.*.vscode-merge-base is tooling churn and is carved out"
else fail "vscode-merge-base churn is not carved out"; fi

# --- 9. ROW 12 (config half) — branch.*.remote / .merge are NOT carved out --------------------
# The composition row. A blanket `branch.*` cut is individually defensible and, composed with a
# refs REPORT class, makes `git -C "" checkout -b probe origin/main` invisible in BOTH dimensions
# at once. `git push -u` writes exactly these two keys, so they are the trace an escape leaves.
ck
p=$(new_probe branchtrack) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" config --local branch.probe.remote origin
git -C "$p" config --local branch.probe.merge refs/heads/probe
state "$p"; after="$STATE_OUT"
if [[ "$before" != "$after" ]]; then pass "branch.*.remote/.merge remain inspected (composition hole closed)"
else fail "branch.*.remote/.merge were carved out — the composition hole is open"; fi

# --- 10. ROW 4 — a commit (HEAD move) is seen ------------------------------------------------
ck
p=$(new_probe headmove) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" commit -q --allow-empty -m second
state "$p"; after="$STATE_OUT"
if [[ "$before" != "$after" ]]; then pass "a commit moves HEAD and is seen"
else fail "HEAD move invisible"; fi

# --- 11. ROW 2 — a ref moving while HEAD stays put is seen ------------------------------------
# The 2026-08-20 shape: a fixture moved a branch ref that was not the checked-out one.
ck
p=$(new_probe refmove) || exit 2
git -C "$p" branch other
state "$p"; before="$STATE_OUT"
git -C "$p" commit -q --allow-empty -m tip
git -C "$p" update-ref refs/heads/other "$(git -C "$p" rev-parse HEAD)"
git -C "$p" reset -q --hard HEAD~1
state "$p"; after="$STATE_OUT"
if [[ "$before" != "$after" ]]; then pass "a non-checked-out ref moving is seen"
else fail "ref move invisible"; fi

# --- 12. ROW 3 — deleting every local ref is FATAL, not not-measured --------------------------
# `git show-ref` exits 1 on NO REFS. Treating that as a capture failure would fail OPEN on the
# most destructive outcome the dimension has.
ck
p=$(new_probe refdel) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" branch doomed
state "$p"; mid="$STATE_OUT"
git -C "$p" branch -D doomed -q 2>/dev/null
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$mid" "$after")
if [[ "$mid" != "$after" ]] && grep -q 'FATAL' <<<"$verdict"; then
  pass "a ref DELETION classifies FATAL (show-ref rc=1 is not read as unmeasured)"
else
  fail "ref deletion not FATAL: verdict='$(printf '%s' "$verdict" | tr '\n' '|')'"
fi

# --- 13. Must-PASS — a remote-tracking ref update does not fire --------------------------------
ck
p=$(new_probe remoteref) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" update-ref refs/remotes/origin/main "$(git -C "$p" rev-parse HEAD)"
state "$p"; after="$STATE_OUT"
if [[ "$before" == "$after" ]]; then pass "refs/remotes/** is excluded"
else fail "a remote-tracking ref update fired the boundary"; fi

# --- 14. Must-PASS — a .git/hooks change does not fire -----------------------------------------
# Hooks are named in the not-inspected list; `lefthook install` must not red the gate.
ck
p=$(new_probe hooks) || exit 2
state "$p"; before="$STATE_OUT"
printf '#!/bin/sh\nexit 0\n' > "$p/.git/hooks/pre-commit"; chmod +x "$p/.git/hooks/pre-commit"
state "$p"; after="$STATE_OUT"
if [[ "$before" == "$after" ]]; then pass ".git/hooks is not a dimension and does not fire"
else fail "a hook install fired the boundary"; fi

# --- 15. Must-PASS — an already-dirty tree that stays equally dirty does not fire ---------------
ck
p=$(new_probe dirty) || exit 2
echo dirt > "$p/dirt.txt"
state "$p"; before="$STATE_OUT"
state "$p"; after="$STATE_OUT"
if [[ "$before" == "$after" ]]; then pass "a stably-dirty tree is not a delta"
else fail "a stably-dirty tree reported a delta"; fi

# --- 16. ROW 5 — the guard's own dispatch: an unreadable HEAD returns non-zero ------------------
# Whole-function degrade-OPEN. The runner must be able to print an honest not-measured NOTE
# rather than a silent clean claim.
ck
notrepo="$TMP_ROOT/notrepo"; mkdir -p "$notrepo"
state "$notrepo" "GIT_CEILING_DIRECTORIES=$TMP_ROOT"
if [[ $STATE_RC -ne 0 ]]; then pass "outside a repository _repo_state returns non-zero (degrade open)"
else fail "_repo_state returned 0 outside a repository — a clean claim with no measurement"; fi

# --- 17. ROW 14/15 — the rendered claim comes from the MANIFEST, not a literal -------------------
# A stale lib measuring three dimensions beside a four-dimension claim is #7652 one layer up.
# Drop a dimension from the manifest and the inspected list must shrink with it.
ck
p=$(new_probe manifestrender) || exit 2
full=$(cd "$p" && bash -c 'source "'"$LIB"'"; _repo_state >/dev/null; repo_boundary_render_inspected')
narrowed=$(cd "$p" && bash -c 'source "'"$LIB"'"
  _repo_state >/dev/null
  # Simulate a stale lib whose manifest no longer carries the config dimension.
  repo_boundary_manifest() { printf "head\tmeasured\nworktree\tmeasured\nrefs\tmeasured\n"; }
  repo_boundary_render_inspected')
if grep -qi 'config' <<<"$full" && ! grep -qi 'config' <<<"$narrowed"; then
  pass "the inspected list renders from the manifest and shrinks with it"
else
  fail "inspected list is a literal, not a manifest render"
fi

# --- 18. The not-inspected list names the classes a reader will otherwise assume covered ---------
ck
ni=$(cd "$p" && bash -c 'source "'"$LIB"'"; _repo_state >/dev/null; repo_boundary_render_not_inspected')
miss=""
for anchor in 'push to a remote' 'objects' 'hooks' 'vscode-merge-base' 'remote-tracking' 'reflog' 'did not start'; do
  grep -qi -- "$anchor" <<<"$ni" || miss="$miss [$anchor]"
done
if [[ -z "$miss" ]]; then pass "the not-inspected list names every class a reader would assume covered"
else fail "not-inspected list is missing:$miss"; fi

# --- 19. Harm class — this worktree's own checked-out branch moving is FATAL ----------------------
ck
p=$(new_probe ownbranch) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" commit -q --allow-empty -m advance
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -q 'FATAL' <<<"$verdict"; then pass "moving this worktree's checked-out branch is FATAL"
else fail "own-branch move not FATAL: '$(printf '%s' "$verdict" | tr '\n' '|')'"; fi

# --- 20. Harm class — a branch checked out in ANOTHER worktree is REPORT, not FATAL ---------------
# Measured from `git worktree list`, so it is a read of the ref store rather than a concurrency
# sniff — which is what disqualified the ${CI:-} severity tier.
ck
p=$(new_probe siblingwt) || exit 2
git -C "$p" branch sibling
git -C "$p" worktree add -q "$TMP_ROOT/siblingwt-checkout" sibling 2>/dev/null
state "$p"; before="$STATE_OUT"
git -C "$p" update-ref refs/heads/sibling "$(git -C "$p" rev-parse HEAD)" 2>/dev/null
git -C "$p" commit -q --allow-empty -m advance-for-sibling
git -C "$p" update-ref refs/heads/sibling "$(git -C "$p" rev-parse HEAD)"
git -C "$p" reset -q --hard HEAD~1
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -q 'REPORT' <<<"$verdict" && ! grep -q 'FATAL' <<<"$verdict"; then
  pass "a branch checked out in another worktree classifies REPORT, not FATAL"
else
  fail "sibling-worktree branch harm class wrong: '$(printf '%s' "$verdict" | tr '\n' '|')'"
fi

# --- Accounting. Emitted DIRECTLY, never through pass()/fail(): a conservation check routed
# through the verdict helper it exists to police cannot report the fault that corrupted it.
if [[ $((passes + fails)) -ne $asserted ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt $asserted ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded without a counted case — a call site is missing its increment.\n' >&2
  fi
  exit 1
fi

MIN_ASSERTIONS=20
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — arms were deleted or neutered" >&2
  exit 1
fi

echo
echo "repo-write-boundary.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
