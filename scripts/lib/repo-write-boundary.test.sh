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
# repo-write-boundary-sandbox: tests-refusal arms 23/24 deliberately build sandboxes WITHOUT the
# lib (and with a stale one) to prove the runner refuses. This file must never be read as a
# relocator that forgot to copy it.
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
  # GLOBAL/SYSTEM config pinned empty. Without this, "the config dimension reads --local" was
  # killed only by this machine happening to have a populated ~/.gitconfig — on a bare CI image
  # dropping `--local` would have survived, and the arm would have been measuring the environment.
  STATE_OUT=$(cd "$dir" && env REPO_BOUNDARY_SALT=fixed-test-salt \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$@" \
    bash -c 'source "'"$LIB"'"; _repo_state' 2>"$TMP_ROOT/err")
  STATE_RC=$?
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
# `wt` is the fifth dimension: the branches-checked-out-elsewhere set is a classification INPUT
# (it decides refs FATAL vs REPORT), and a classification input outside the manifest is the exact
# thing this design exists to prevent.
if [[ "$(printf '%s\n' "$man" | awk '{print $1}' | sort | tr '\n' ' ')" == "config head refs worktree wt " ]]; then
  pass "manifest enumerates head, worktree, config, refs, wt"
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
# Driven through a real SNAPSHOT rather than by stubbing repo_boundary_manifest, because that is
# how the runner calls it: `before="$(_repo_state)"` is a command substitution, so a stubbed
# global would not survive to the render anyway. Stripping the config manifest row is what a
# STALE lib measuring three dimensions actually produces.
full=$(cd "$p" && bash -c 'source "'"$LIB"'"; s="$(_repo_state)"; repo_boundary_render_inspected "$s"')
narrowed=$(cd "$p" && bash -c 'source "'"$LIB"'"
  s="$(_repo_state | grep -v "^manifest	config	")"
  repo_boundary_render_inspected "$s"')
if grep -qi 'config' <<<"$full" && ! grep -qi 'config' <<<"$narrowed"; then
  pass "the inspected list renders from the manifest and shrinks with it"
else
  fail "inspected list is a literal, not a manifest render"
fi

# --- 18. The not-inspected list names the classes a reader will otherwise assume covered ---------
ck
ni=$(cd "$p" && bash -c 'source "'"$LIB"'"; s="$(_repo_state)"; repo_boundary_render_not_inspected "$s"')
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

# ==============================================================================================
# RUNNER INTEGRATION. The lib being correct is half the property; the other half is that
# `scripts/test-all.sh` actually calls it, calls it in the right WINDOW, and cannot print a claim
# the lib did not produce. These arms drive the real runner as SUT.
# ==============================================================================================

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"

# --- 21. The lib is sourced, and sourced ABOVE tc_acquire ---------------------------------------
# Placement is load-bearing, not style: both SUT-sandbox suites splice out everything between
# `tc_acquire "test-all"` and `tc_epilogue`, and the end block runs under `set -u`. A source line
# or a boundary variable below the anchor is deleted in those sandboxes, and the failure surfaces
# as two unrelated red suites rather than as this one.
ck
src_ln=$(grep -n 'repo-write-boundary\.sh' "$RUNNER" | head -n1 | cut -d: -f1)
acq_ln=$(grep -n '^tc_acquire "test-all"' "$RUNNER" | head -n1 | cut -d: -f1)
if [[ -n "$src_ln" && -n "$acq_ln" ]] && (( src_ln < acq_ln )); then
  pass "the boundary lib is sourced above tc_acquire (line $src_ln < $acq_ln)"
else
  fail "boundary lib source placement wrong (src=${src_ln:-none} acquire=${acq_ln:-none})"
fi

# --- 22. Exactly two _repo_state call sites in the runner ------------------------------------------
# The window has to span the whole suite list. One call site means a boundary that never closes;
# three means a window whose extent is no longer obvious from reading.
ck
calls=$(grep -cE '^[[:space:]]*(if )?_repo_state_(before|after)="\$\(_repo_state\)"' "$RUNNER" || true)
if [[ "$calls" == "2" ]]; then pass "_repo_state has exactly two call sites in the runner"
else fail "_repo_state call sites in runner: $calls (want 2)"; fi

# --- 23. ROW 13 — a missing lib exits 2 and does NOT blame git --------------------------------------
# The `|| true` contract would leave `_repo_state` undefined, return 127 inside the `if`, and make
# the run print "the repo-write boundary was not measured (git unavailable at run start)" — an
# AP-021 violation manufactured by this very fix. A lib that decides whether the gate means
# anything is a hard failure when missing (the _REL_LIB class).
ck
sb="$TMP_ROOT/nolib"; mkdir -p "$sb/lib"
cp "$RUNNER" "$sb/test-all.sh"
cp "$REPO_ROOT/scripts/lib/test-relevance-paths.sh" "$sb/lib/" 2>/dev/null
cp "$REPO_ROOT/scripts/lib/test-contention.sh" "$sb/lib/" 2>/dev/null
# deliberately do NOT copy repo-write-boundary.sh
# rc captured from the RUNNER, not from a `| head` pipeline (which is what `$?` after a pipe
# reports, and which is always 0). TC_LOCK_TIMEOUT is pinned low: if the above-tc_acquire
# placement invariant ever regresses, this sandbox reaches the lock the PARENT run holds and
# burns the full timeout, turning a precise red into a slow one.
nolib_raw="$TMP_ROOT/nolib.out"
( cd "$REPO_ROOT" && TC_LOCK_TIMEOUT=5 timeout 60 bash "$sb/test-all.sh" >"$nolib_raw" 2>&1 </dev/null )
nolib_rc=$?
nolib_out=$(head -20 "$nolib_raw")
if [[ "$nolib_rc" -eq 2 ]] && grep -q 'repo-write-boundary' <<<"$nolib_out" \
   && ! grep -qi 'git unavailable' <<<"$nolib_out"; then
  pass "a missing boundary lib exits 2, names the lib, and does not blame git"
else
  fail "missing-lib contract wrong (rc=$nolib_rc): '$(printf '%s' "$nolib_out" | tr '\n' '|' | cut -c1-220)'"
fi

# --- 24. ROW 14 — a STALE lib narrows the CLAIM, not just the check -----------------------------
# `test -f` proves a file exists, never that it defines what the caller calls. A lib that defines
# a narrower _repo_state beside a full-dimension claim is #7652 one layer up, across this new
# module seam — so the runner checks the named function SET, in the _TC_LIB shape.
ck
stale="$TMP_ROOT/stalelib"; mkdir -p "$stale/lib"
cp "$RUNNER" "$stale/test-all.sh"
for f in test-relevance-paths.sh test-contention.sh; do cp "$REPO_ROOT/scripts/lib/$f" "$stale/lib/" 2>/dev/null; done
printf '%s\n' '#!/usr/bin/env bash' '_repo_state() { git rev-parse HEAD; }' > "$stale/lib/repo-write-boundary.sh"
stale_raw="$TMP_ROOT/stale.out"
( cd "$REPO_ROOT" && TC_LOCK_TIMEOUT=5 timeout 60 bash "$stale/test-all.sh" >"$stale_raw" 2>&1 </dev/null )
stale_rc=$?
stale_out=$(head -20 "$stale_raw")
if [[ "$stale_rc" -eq 2 ]] && grep -qiE 'repo_boundary_(manifest|classify|dimensions|render)' <<<"$stale_out"; then
  pass "a stale lib exits 2 and is NAMED by the missing-function check, not silently narrowed"
else
  fail "stale-lib contract wrong: '$(printf '%s' "$stale_out" | tr '\n' '|' | cut -c1-220)'"
fi

# --- 25. AC8 — the message renders inspected / not-inspected / per-dimension next action ----------
# Asserted by CONTENT ANCHOR on the runner's own rendering path, driven with a synthetic delta, so
# the assertion cannot be satisfied by prose sitting in a comment.
ck
render=$(cd "$REPO_ROOT" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c '
  source "'"$LIB"'"
  b="$(_repo_state)"
  printf "INSPECTED\n%s\nNOTINSPECTED\n%s\nNEXT\n" "$(repo_boundary_render_inspected "$b")" "$(repo_boundary_render_not_inspected "$b")"
  for d in head worktree config refs; do printf "%s: %s\n" "$d" "$(repo_boundary_next_action "$d")"; done')
missing_anchor=""
for a in 'HEAD' 'tree and index' 'local (shared) config' 'harm class' \
         'push to a remote' 'did not start' \
         'git reflog' 'git config --local --unset' 'git show-ref'; do
  grep -qF -- "$a" <<<"$render" || missing_anchor="$missing_anchor [$a]"
done
if [[ -z "$missing_anchor" ]]; then
  pass "the rendered message carries inspected, not-inspected and a per-dimension next action"
else
  fail "rendered message missing anchors:$missing_anchor"
fi

# --- 26. AC9 / ROW 11 — a run killed before the end boundary emits the not-measured NOTE -----------
# A run has no `trap ... EXIT` today, so a kill emits NOTHING — and the escape most likely to kill a
# run is exactly the one that suppresses the verdict. "No FATAL line" must never read as clean.
ck
if grep -qE "trap .*_repo_boundary_exit_note|_repo_boundary_exit_note.*EXIT" "$RUNNER"; then
  pass "the runner arms an EXIT trap so a killed run cannot read as a clean boundary"
else
  fail "no EXIT-trap not-measured NOTE in the runner"
fi

# --- 27. The EXIT CONTRACT documents the REPORT class ----------------------------------------------
# A new result class that increments nothing and changes no exit code is a state the runner's own
# contract does not describe — which is the same claim/check drift being fixed here.
ck
# Anchored on the CLASS DESCRIPTION, not the bare word "REPORT": `sed -n 1,60p` of this runner
# already contains that word in unrelated prose, so a bare-token check passed before the contract
# was written (cq-assert-anchor-not-bare-token — this branch's own subject).
contract=$(sed -n '1,60p' "$RUNNER")
if grep -qi 'REPORT.*increments nothing' <<<"$contract" \
   || grep -qi 'REPORT class' <<<"$contract"; then
  pass "the EXIT CONTRACT block describes the REPORT class"
else
  fail "EXIT CONTRACT does not mention the REPORT class"
fi

# --- 28. EVERY sandbox that relocates the runner carries the lib, or says why not ---------------
# The finding that produced this arm named ONE file; the fix is scoped to the CLASS. The runner
# sources this lib fail-closed, so any suite that copies `scripts/test-all.sh` into a sandbox and
# executes it exits 2 before its first arm — and the failure surfaces as that suite's own arms all
# going red for unrelated-looking reasons, not as a missing file. Two of the three relocators were
# named in the plan; the third (`fanout-suite-scope.test.sh`) was found only by a red shard, after
# the first two had been fixed and read as complete.
#
# So the population is ENUMERATED from the tree rather than remembered, and a relocator that
# genuinely does not need the lib must SAY SO — a silent exemption is how this class regrows.
ck
relocators=""; unlisted=""
while IFS= read -r f; do
  grep -qE '^[[:space:]]*cp\b.*test-all\.sh|cp "\$TARGET"|cp "\$MAIN_TARGET"|cp "\$RUNNER"' "$f" || continue
  relocators="$relocators $f"
  # Anchored on the COPY, never on the lib's name. The previous form was `grep -q
  # 'repo-write-boundary'`, which any file mentioning the lib satisfies — including THIS file,
  # which names it eight times and was therefore counted as compliant while deliberately building
  # sandboxes without it. A guard satisfied by prose about the guard is this branch's own subject.
  grep -qE 'cp .*repo-write-boundary\.sh' "$f" && continue           # actually copies the lib
  grep -q 'repo-write-boundary-sandbox: not-needed' "$f" && continue  # declared early-exit-only
  grep -q 'repo-write-boundary-sandbox: tests-refusal' "$f" && continue # declared refusal-tester
  unlisted="$unlisted
    $(realpath --relative-to="$REPO_ROOT" "$f")"
done < <(git -C "$REPO_ROOT" ls-files '*.sh' | sed "s#^#$REPO_ROOT/#" | xargs grep -l 'test-all\.sh' 2>/dev/null)
n_reloc=$(printf '%s' "$relocators" | wc -w)
if [[ "$n_reloc" -lt 3 ]]; then
  # Anti-vacuity, reported directly: an enumeration that finds nothing passes trivially, and this
  # arm's whole value is that the population is derived rather than remembered.
  printf '[FATAL] only %s runner-relocating suite(s) enumerated (expected >=3) — the derivation is broken, not the tree.\n' "$n_reloc" >&2
  exit 1
fi
if [[ -z "$unlisted" ]]; then
  pass "all $n_reloc runner-relocating sandbox(es) copy the lib or declare not-needed"
else
  fail "sandbox(es) that relocate test-all.sh without the boundary lib and without a declaration:$unlisted"
fi

# --- 29. ROWS 6 & 7 — the WINDOW, not just the call count -------------------------------------------
# Arm 22 counts the call sites; it cannot see a window that shrank. Two orderings carry the whole
# meaning of the measurement and a delete-only battery is blind to both:
#   row 7 — the START snapshot must sit AFTER `tc_acquire`. A run that queued behind a sibling can
#           wait up to TC_LOCK_TIMEOUT (3600 s), so a reading taken before the wait describes a
#           machine state up to an hour stale and the delta means nothing.
#   row 6 — the END snapshot must sit AFTER the last `run_suite`. Moved above it, the window stops
#           spanning the suite list and the boundary reports clean about suites it never covered.
ck
acq=$(grep -n '^tc_acquire "test-all"' "$RUNNER" | head -n1 | cut -d: -f1)
# Anchored on the STATEMENT, not the bare token: the runner's own explanatory comment above the
# lib-source block QUOTES `if _repo_state_before="$(_repo_state)"` to explain why the contract is
# fail-closed, and an unanchored grep matched that comment at line 331 instead of the code at 1008.
# That is cq-assert-anchor-not-bare-token firing inside the arm written to check ordering.
start_snap=$(grep -nE '^[[:space:]]*if _repo_state_before="\$\(_repo_state\)"' "$RUNNER" \
  | grep -v ':[[:space:]]*#' | head -n1 | cut -d: -f1)
end_snap=$(grep -nE '^[[:space:]]*if _repo_state_after="\$\(_repo_state\)"' "$RUNNER" \
  | grep -v ':[[:space:]]*#' | head -n1 | cut -d: -f1)
last_suite=$(grep -n '^\s*run_suite ' "$RUNNER" | tail -n1 | cut -d: -f1)
if [[ -n "$acq" && -n "$start_snap" && -n "$end_snap" && -n "$last_suite" ]] \
   && (( start_snap > acq )) && (( end_snap > last_suite )); then
  pass "the boundary window spans the suite list: tc_acquire($acq) < start($start_snap), last run_suite($last_suite) < end($end_snap)"
else
  fail "boundary window ordering wrong: acquire=$acq start=$start_snap last_run_suite=$last_suite end=$end_snap"
fi

# --- 30. THE CONFIG HARM PARTITION — a sibling `git push -u` must NOT red the gate ------------
# The refs partition exists because "a sibling worktree's branch advancing" and "this run corrupted
# the repo" are not the same event. `--local` in a linked worktree reads the SHARED config, so the
# config dimension carries the SAME sibling side effect via branch.<n>.remote/.merge — and before
# this arm existed it was unconditionally FATAL. Measured on this repo: 22 worktrees, branch.*
# entries moving 46 -> 48 within one session. That is a false RED on the ordinary workflow.
ck
p=$(new_probe cfgpartition) || exit 2
git -C "$p" branch sibling-br
state "$p"; before="$STATE_OUT"
git -C "$p" config --local branch.sibling-br.remote origin
git -C "$p" config --local branch.sibling-br.merge refs/heads/sibling-br
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -q '^REPORT' <<<"$verdict" && ! grep -q '^FATAL' <<<"$verdict" \
   && grep -q 'branch.sibling-br.remote' <<<"$verdict"; then
  pass "a \`git push -u\`-shaped config add is REPORT, not FATAL, and NAMES the key"
else
  fail "config partition wrong: '$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-200)'"
fi

# --- 31. ... and the INCIDENT key must stay FATAL, and be named --------------------------------
# The property that must not regress under the partition above. This is the exact key from
# 2026-08-20, and the whole reason the config dimension exists.
ck
p=$(new_probe cfgincident) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" config --local commit.gpgsign false
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -q '^FATAL' <<<"$verdict" && grep -q 'commit.gpgsign' <<<"$verdict"; then
  pass "the 2026-08-20 incident key stays FATAL and is NAMED in the detail"
else
  fail "incident key not FATAL/named: '$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-200)'"
fi

# --- 32. A key DELETION, and a tracking add on OUR OWN branch, both stay FATAL -----------------
# The two fail-closed edges of the partition. Nothing routine deletes a shared key; and our own
# branch gaining tracking config mid-run is ambiguous, so it takes the harsher class.
ck
p=$(new_probe cfgedges) || exit 2
git -C "$p" config --local core.somekey somevalue
state "$p"; before="$STATE_OUT"
git -C "$p" config --local --unset core.somekey
state "$p"; after="$STATE_OUT"
v1=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
own=$(git -C "$p" symbolic-ref --short HEAD)
state "$p"; before2="$STATE_OUT"
git -C "$p" config --local "branch.${own}.remote" origin
state "$p"; after2="$STATE_OUT"
v2=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before2" "$after2")
if grep -q 'DELETED' <<<"$v1" && grep -q '^FATAL' <<<"$v1" && grep -q '^FATAL' <<<"$v2"; then
  pass "a config DELETION and an own-branch tracking add both stay FATAL (fail closed)"
else
  fail "edges wrong: del='$(printf '%s' "$v1" | tr '\n' '|')' own='$(printf '%s' "$v2" | tr '\n' '|')'"
fi

# --- 33. MANIFEST PAIRING — a dimension measured at one boundary only is UNMEASURABLE ----------
# Reachable, not theoretical: `git status --porcelain` refreshes the index and fails under
# index.lock contention, which parallel worktrees produce routinely. Without pairing, the body
# diff sees a delta and emits FATAL naming a dimension the INSPECTED list does not claim.
ck
p=$(new_probe pairing) || exit 2
state "$p"; before="$STATE_OUT"
# A stale/narrower lib: the worktree dimension vanishes from the after snapshot entirely.
after_narrow=$(printf '%s' "$STATE_OUT" | grep -v '^manifest	worktree	' | grep -v '^worktree	')
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt bash -c \
  'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after_narrow")
inspected=$(cd "$p" && bash -c 'source "'"$LIB"'"; repo_boundary_render_inspected "$1" "$2"' _ "$before" "$after_narrow")
if grep -q '^UNMEASURABLE' <<<"$verdict" && ! grep -qE '^FATAL[[:space:]]+worktree' <<<"$verdict" \
   && ! grep -qi 'tree and index' <<<"$inspected"; then
  pass "a dimension measured at one boundary only is UNMEASURABLE, and drops out of INSPECTED"
else
  fail "manifest pairing wrong: verdict='$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-160)' inspected='$(printf '%s' "$inspected" | tr '\n' '|')'"
fi

# --- 34. FIXTURE DIRECTION: the worktree dimension must SEE its own write class ----------------
# Every existing worktree arm dirties the tree BEFORE the first snapshot, i.e. asserts must-NOT-
# fire. So the dimension could be replaced by a constant and the suite stayed 33/33 green. A suite
# whose fixtures all point one way cannot see the other way.
ck
p=$(new_probe wtdirection) || exit 2
state "$p"; before="$STATE_OUT"
echo "written between the snapshots" > "$p/new-file.txt"
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null bash -c 'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -qE '^FATAL[[:space:]]+worktree' <<<"$verdict"; then
  pass "a working-tree write BETWEEN the snapshots is FATAL (the dimension is not a constant)"
else
  fail "worktree dimension blind to its own write class: '$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-160)'"
fi

# --- 35. FIXTURE SHAPE: a branch registered MID-WINDOW must not launder itself ------------------
# The anti-laundering rule reads `elsewhere` from the BEFORE snapshot. Every existing arm registers
# the sibling worktree before BOTH snapshots, so both sides carry it and reading from `$after`
# instead was fully green. The escape the lib's own comment names is `git -C "" worktree add -b
# probe` DURING the window.
ck
p=$(new_probe midwindow) || exit 2
state "$p"; before="$STATE_OUT"
git -C "$p" worktree add -q "$TMP_ROOT/midwindow-co" -b probe-mid 2>/dev/null
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null bash -c 'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -qE '^FATAL[[:space:]]+refs.*probe-mid' <<<"$verdict"; then
  pass "a branch whose worktree appeared MID-WINDOW cannot launder itself into REPORT"
else
  fail "mid-window laundering not caught: '$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-200)'"
fi

# --- 36. POPULATION: the tags half of the refs dimension is live -------------------------------
# No arm created or moved a tag, so `--tags` was deletable at 33/33 green and the classifier's
# `refs/tags/*` branch was unreachable from the suite. `git -C "" tag -f v1.0` retargets a release
# tag, and `tag` is in the sibling scanner's own write-verb list.
ck
p=$(new_probe tagdim) || exit 2
state "$p"; before="$STATE_OUT"
# `-c tag.gpgSign=false` and an explicit precondition check: the operator's GLOBAL gitconfig forces
# signed/annotated tags here, so a bare `git tag` fails with "no tag message?" and the arm would be
# measuring a broken fixture rather than the dimension. A fixture that cannot CONTAIN the thing the
# arm looks for is not a test — so its failure is made a loud FIXTURE error, not a phantom SUT one.
git -C "$p" -c tag.gpgSign=false -c tag.forceSignAnnotated=false tag probe-tag 2>/dev/null
if ! git -C "$p" show-ref --tags --quiet -- refs/tags/probe-tag; then
  printf '[FATAL] fixture setup failed: could not create refs/tags/probe-tag in the probe repo.\n' >&2
  printf '        This arm cannot measure the tags dimension without it.\n' >&2
  exit 1
fi
state "$p"; after="$STATE_OUT"
verdict=$(cd "$p" && env REPO_BOUNDARY_SALT=fixed-test-salt GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null bash -c 'source "'"$LIB"'"; repo_boundary_classify "$1" "$2"' _ "$before" "$after")
if grep -q 'probe-tag' <<<"$verdict"; then
  pass "a tag write is seen by the refs dimension (--tags is load-bearing)"
else
  fail "tag write invisible: '$(printf '%s' "$verdict" | tr '\n' '|' | cut -c1-160)'"
fi

# --- 37. EXTRACTOR UNIQUENESS: the next-action MAPPING, per dimension ---------------------------
# Arm 25 concatenates all four next-actions into one blob and greps substrings, so the MAPPING is
# unasserted — permuting the four strings across the four dimensions was fully green. The defect
# this function exists to fix is precisely a wrong mapping (the old text offered `git reflog` for
# every outcome).
ck
map_bad=""
declare -A _want=( [head]='reflog' [worktree]='status' [config]='--unset' [refs]='show-ref' )
for d in head worktree config refs; do
  got=$(bash -c 'source "'"$LIB"'"; repo_boundary_next_action "$1"' _ "$d")
  grep -qF -- "${_want[$d]}" <<<"$got" || map_bad="$map_bad [$d wanted '${_want[$d]}' got '${got:0:40}']"
done
if [[ -z "$map_bad" ]]; then
  pass "each dimension's next action names ITS OWN remedy (the mapping, not just the strings)"
else
  fail "next-action mapping wrong:$map_bad"
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

# Derived from a green run, then ratcheted upward: 37 arms execute today, so a deleted or
# neutered arm cannot hide behind slack. Raise it in lockstep when adding arms; never lower it.
MIN_ASSERTIONS=37
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — arms were deleted or neutered" >&2
  exit 1
fi

echo
echo "repo-write-boundary.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
