#!/usr/bin/env bash
# test-infra-suite-registration-mutations.sh -- prove test-infra-suite-registration.sh is not
# vacuous: every arm of it must go RED under a mutation that violates the property that arm
# asserts, and legitimate variants must stay GREEN.
#
# WHY THIS FILE EXISTS (#7068). The gate it tests is a fail-closed guard on a REQUIRED,
# merge_group-triggered, path-filter-free check. A guard that cannot fail is observationally
# identical to one that passed, and #7068 exists because exactly that happened one level down.
# An earlier revision of the gate carried a comment saying it was "mutation-proved inline, and
# that proof is recorded in the PR body". That is the perishable-evidence anti-pattern in
# knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md:
# a `mutation-proven` adjective asserts a property nothing re-checks, which is worse than
# silence because it discourages the next reader from checking. This is that proof, committed.
#
# It also answers the gate's own former objection ("a companion suite would reproduce the
# orphan problem in miniature"): this file sits in .github/scripts/test/, so run-all.sh's
# `test-*.sh` glob picks it up automatically. It cannot be orphaned.
#
# CONTRACT (#6454): BASH-ONLY. git + sed + awk + grep, no terraform, no apt, no python.
#
# It NEVER mutates a tracked file. Everything happens in a `mktemp -d` sandbox, so an
# interrupted run cannot leave the repo altered -- the failure mode that a mutate-in-place
# harness has, which is unacceptable for a file that runs in CI.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE_REL=".github/scripts/test/test-infra-suite-registration.sh"
WF_REL=".github/workflows/infra-validation.yml"
INFRA_PREFIX="apps/web-platform/infra"

SB=$(mktemp -d -t infra-reg-mut.XXXXXXXX) || { echo "SETUP: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

pass=0
fail=0
asserts=0

ok()   { asserts=$((asserts+1)); pass=$((pass+1)); echo "[ok] $1"; }
bad()  { asserts=$((asserts+1)); fail=$((fail+1)); echo "[FAIL] $1"; }
setup_die() { echo "SETUP FAILED: $1" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Sandbox. Suite STUBS (empty files) rather than copies of the real suites: the gate reads
# only path names, via `git ls-files`, so stubs are faithful for its purpose and keep this
# harness cheap enough to sit on the merge-queue critical path.
#
# The stub list is DERIVED from the real repo, so the harness cannot drift out of sync with
# the suite set it is meant to model.
# ---------------------------------------------------------------------------
mkdir -p "$SB/.github/scripts/test" "$SB/.github/workflows" || setup_die "mkdir"
cp "$REPO_ROOT/$GATE_REL" "$SB/$GATE_REL" || setup_die "cp gate"
cp "$REPO_ROOT/$WF_REL"   "$SB/$WF_REL"   || setup_die "cp workflow"
cp "$REPO_ROOT/$WF_REL"   "$SB/wf.pristine" || setup_die "cp pristine"

mapfile -t REAL_SUITES < <(git -C "$REPO_ROOT" ls-files \
  "${INFRA_PREFIX}/*.test.sh" "${INFRA_PREFIX}/**/*.test.sh" | LC_ALL=C sort -u)
(( ${#REAL_SUITES[@]} >= 50 )) || setup_die "only ${#REAL_SUITES[@]} real suites enumerated"

# Batch the directory creation and use parameter expansion, not `dirname`. A `$(dirname)` +
# `mkdir -p` pair per suite measured 4.2s for 94 files -- 97% of this harness's entire runtime,
# spent on forks, on a gate that runs for every PR in the repo. Builtins bring it to ~0.05s.
declare -A STUB_DIRS=()
for s in "${REAL_SUITES[@]}"; do STUB_DIRS["${s%/*}"]=1; done
# Build the prefixed list explicitly: `${!arr[@]/#/pfx}` is parsed as INDIRECT expansion of the
# values, not as key-prefixing, and fails with "invalid variable name".
STUB_DIR_PATHS=()
for d in "${!STUB_DIRS[@]}"; do STUB_DIR_PATHS+=("$SB/$d"); done
mkdir -p "${STUB_DIR_PATHS[@]}" || setup_die "mkdir stub dirs"
for s in "${REAL_SUITES[@]}"; do
  : > "$SB/$s" || setup_die "stub $s"
done

git -C "$SB" init -q                >/dev/null 2>&1 || setup_die "git init"
git -C "$SB" add -A                 >/dev/null 2>&1 || setup_die "git add"

run_gate() { ( cd "$SB" && bash "$GATE_REL" >"$SB/out.log" 2>&1; echo $?; ); }

restore_wf() { cp "$SB/wf.pristine" "$SB/$WF_REL" || setup_die "restore workflow"; }

# A mutation that did not LAND reports the baseline result, which reads exactly like a real
# pass. Assert the bytes changed before believing any verdict.
assert_landed() {
  if cmp -s "$SB/wf.pristine" "$SB/$WF_REL"; then
    setup_die "mutation '$1' did not land (workflow byte-identical to pristine)"
  fi
}

# ---------------------------------------------------------------------------
# POSITIVE CONTROL. Every row below is meaningless if the unmutated sandbox is not GREEN --
# a red baseline makes each "mutation caught!" indistinguishable from an environment fault.
# ---------------------------------------------------------------------------
rc=$(run_gate)
if [[ "$rc" != "0" ]]; then
  echo "VOID: control (unmutated sandbox) exited $rc, not 0. No row below can be believed." >&2
  sed 's/^/    /' "$SB/out.log" >&2
  exit 2
fi
ok "control: unmutated sandbox is GREEN (rc=0)"

# Guard the control against the opposite error: a gate that greens because it inspected
# nothing. The success line must report the real suite population.
if grep -qE "^infra suite registration: ${#REAL_SUITES[@]} suites registered" "$SB/out.log"; then
  ok "control: success line accounts for all ${#REAL_SUITES[@]} suites"
else
  bad "control: success line does not report ${#REAL_SUITES[@]} suites -- $(tail -1 "$SB/out.log")"
fi

# ---------------------------------------------------------------------------
# RED rows. Each mutates the workflow (or the suite set) and must produce rc!=0 AND a message
# naming the right failure mode -- rc alone is a symptom several arms share, so asserting only
# "non-zero" would let one arm's message masquerade as another's.
# ---------------------------------------------------------------------------
expect_red() {
  local label="$1" needle="$2"; shift 2
  restore_wf
  "$@" || setup_die "mutation cmd for $label"
  assert_landed "$label"
  local rc; rc=$(run_gate)
  if [[ "$rc" == "0" ]]; then
    bad "$label: gate stayed GREEN (vacuous arm)"
  elif grep -qF "$needle" "$SB/out.log"; then
    ok "$label: rc=$rc and message names the right mode"
  else
    bad "$label: rc=$rc but expected message missing ($needle)"
  fi
}

TOP_SUITE="$INFRA_PREFIX/audit-bwrap-uid.test.sh"
TOP_SUITE2="$INFRA_PREFIX/cat-infra-config-state.test.sh"
TOP_SUITE3="$INFRA_PREFIX/live-verify.tf.test.sh"
LOOPBACK="$INFRA_PREFIX/workspaces-luks-loopback.test.sh"

# M1 -- the #7068 defect itself: a suite registered nowhere.
expect_red "M1 delete a single-line run: step" "is registered in NO single-line" \
  sed -i "\|^[[:space:]]*run: bash ${TOP_SUITE}[[:space:]]*\$|d" "$SB/$WF_REL"

# M2 -- IC-1's class: still runs in CI, invisible to the local runner's single-line derivation.
expect_red "M2 single-line -> multi-line run: |" "not in the single-line" \
  sed -i "s|^\([[:space:]]*\)run: bash ${TOP_SUITE2}[[:space:]]*\$|\1run: \|\n\1  bash ${TOP_SUITE2}|" "$SB/$WF_REL"

# M3 -- RF-2's class: an exclusion must waive SHAPE, never EXISTENCE.
expect_red "M3 delete the excluded suite's invocation" "not invoked" \
  sed -i "\|sudo bash ${LOOPBACK}|d" "$SB/$WF_REL"

# M4 -- the comment-strip is the anti-vacuity core; a commented invocation must not satisfy it.
expect_red "M4 comment out a registration" "is registered in NO single-line" \
  sed -i "s|^\([[:space:]]*\)run: bash ${TOP_SUITE3}[[:space:]]*\$|\1# run: bash ${TOP_SUITE3}|" "$SB/$WF_REL"

# M5 -- masking: a step that exists can still be neutralised.
expect_red "M5 add continue-on-error to the job" "continue-on-error" \
  sed -i "s|^\([[:space:]]*\)run: bash ${TOP_SUITE}[[:space:]]*\$|\1continue-on-error: true\n\1run: bash ${TOP_SUITE}|" "$SB/$WF_REL"

# M6 -- the exclusion must cite a real tracking issue; a placeholder must not satisfy it.
# Handled inline rather than via expect_red: this row mutates the GATE, not the workflow, so
# it needs its own landing check. (expect_red's workflow-scoped assert_landed correctly
# refused to score this row when it was first written that way -- the check earning its keep.)
restore_wf
sed -i 's|#7076|#0|g' "$SB/$GATE_REL" || setup_die "M6 mutation cmd"
if cmp -s "$REPO_ROOT/$GATE_REL" "$SB/$GATE_REL"; then
  setup_die "mutation 'M6' did not land (gate byte-identical to source)"
fi
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M6 exclusion cites #0: gate stayed GREEN (a placeholder satisfied 'cites an issue')"
elif grep -qF "no reason or no tracking issue" "$SB/out.log"; then
  ok "M6 exclusion cites #0: rc=$rc and message names the right mode"
else
  bad "M6 exclusion cites #0: rc=$rc but expected message missing"
fi
cp "$REPO_ROOT/$GATE_REL" "$SB/$GATE_REL" || setup_die "restore gate after M6"

# M7 -- job scoping: a step relocated out of deploy-script-tests runs in no CI job on most PRs.
# Emulated by renaming the job header, which is the same observable (the steps are no longer in
# a job called deploy-script-tests).
expect_red "M7 relocate steps out of deploy-script-tests" "could not slice" \
  sed -i "s|^  deploy-script-tests:\$|  deploy-script-tests-renamed:|" "$SB/$WF_REL"

restore_wf

# ---------------------------------------------------------------------------
# Suite-set rows. These change which files exist, so they touch the git index rather than
# the workflow, and each restores the index afterwards.
# ---------------------------------------------------------------------------

# M8 -- THE P1 THIS GATE WAS EXTENDED FOR: a NEW subdirectory suite registers green under a
# path-blind gate and then never runs through the mandated local runner, forever (#7076).
NEWSUB="$INFRA_PREFIX/newdir/zzz-mutation-subdir.test.sh"
mkdir -p "$SB/$(dirname "$NEWSUB")" || setup_die "mkdir newsub"
: > "$SB/$NEWSUB" || setup_die "stub newsub"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add newsub"
# Register it correctly, so the ONLY defect is that the runner cannot derive it.
awk -v ins="        run: bash $NEWSUB" \
    -v anchor="        run: bash $TOP_SUITE" \
    '{ print } $0 == anchor { print "      - name: Run zzz-mutation-subdir" ; print ins }' \
    "$SB/wf.pristine" > "$SB/$WF_REL" || setup_die "awk insert newsub step"
assert_landed "M8"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M8 new subdirectory suite, correctly registered: gate stayed GREEN (the #7076 accretion hole)"
elif grep -qF "SUBDIRECTORY" "$SB/out.log"; then
  ok "M8 new subdirectory suite: rc=$rc and message names the derivation gap"
else
  bad "M8 new subdirectory suite: rc=$rc but message does not name the subdirectory gap"
fi
rm -f "$SB/$NEWSUB"; rmdir "$SB/$(dirname "$NEWSUB")" 2>/dev/null
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after M8"
restore_wf

# M9 -- a stale pin silently licenses a gap that is no longer real.
PINNED="$INFRA_PREFIX/inngest-rls/inngest-rls.test.sh"
if [[ -f "$SB/$PINNED" ]]; then
  rm -f "$SB/$PINNED"
  git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after pin removal"
  rc=$(run_gate)
  if [[ "$rc" == "0" ]]; then
    bad "M9 stale KNOWN_UNDERIVABLE entry: gate stayed GREEN"
  elif grep -qF "not a tracked infra suite" "$SB/out.log"; then
    ok "M9 stale KNOWN_UNDERIVABLE entry: rc=$rc and message names the stale pin"
  else
    bad "M9 stale KNOWN_UNDERIVABLE entry: rc=$rc but message does not name it"
  fi
  : > "$SB/$PINNED"; git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add restore pin"
else
  bad "M9 fixture missing: $PINNED is not in the sandbox"
fi

# M10 -- enumeration collapse must fail closed, not pass with zero coverage.
mv "$SB/$INFRA_PREFIX" "$SB/${INFRA_PREFIX}-moved" || setup_die "mv infra dir"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after mv"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M10 enumeration collapse: gate stayed GREEN with zero suites"
else
  ok "M10 enumeration collapse: rc=$rc (fails closed)"
fi
mv "$SB/${INFRA_PREFIX}-moved" "$SB/$INFRA_PREFIX" || setup_die "mv back"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after mv back"

# ---------------------------------------------------------------------------
# GREEN rows. A guard that fires on everything is as useless as one that never fires, and
# RED-only evidence cannot tell the two apart. RF-1 is the measured instance: an earlier gate
# anchored on `[[:space:]]*$` and red-failed every PR in the repo on an ordinary comment.
# ---------------------------------------------------------------------------
restore_wf
sed -i "s|^\([[:space:]]*\)run: bash ${TOP_SUITE}[[:space:]]*\$|\1run: bash ${TOP_SUITE}  # ordinary note|" "$SB/$WF_REL" \
  || setup_die "M11 mutation cmd"
assert_landed "M11"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  ok "M11 legitimate trailing # comment: stays GREEN (RF-1 regression)"
else
  bad "M11 legitimate trailing # comment: gate red-failed a valid line (rc=$rc)"
fi

restore_wf
sed -i "s|^\([[:space:]]*\)run: bash ${TOP_SUITE}[[:space:]]*\$|\1env:\n\1  FOO: bar\n\1run: bash ${TOP_SUITE}|" "$SB/$WF_REL" \
  || setup_die "M12 mutation cmd"
assert_landed "M12"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  ok "M12 step-level env: block: stays GREEN"
else
  bad "M12 step-level env: block: gate red-failed a valid shape (rc=$rc)"
fi

# ---------------------------------------------------------------------------
# Assertion floor. Nothing above asserts that the assertions RAN: deleting every ok()/bad()
# call would leave this suite exiting 0. A FLOOR, not equality -- the count is
# developer-incremented, and `-eq` turns every added row into a spurious failure.
# ---------------------------------------------------------------------------
MIN_ASSERTS=14
if (( asserts < MIN_ASSERTS )); then
  echo "[FAIL] assertion floor: only $asserts assertion(s) ran, expected >= $MIN_ASSERTS." >&2
  echo "       Rows were removed or short-circuited. Lower the floor deliberately, with a reason." >&2
  fail=$((fail+1))
fi

echo ""
echo "=== infra-suite-registration mutations: $pass passed, $fail failed ($asserts assertions) ==="
(( fail == 0 ))
