#!/usr/bin/env bash
# test-infra-suite-registration-mutations.sh -- prove test-infra-suite-registration.sh is not
# vacuous: every arm of it must go RED under a mutation that violates the property that arm
# asserts, and legitimate variants must stay GREEN.
#
# WHY THIS FILE EXISTS (#7068; re-shaped by #8736 for the glob-registration contract).
# The gate it tests is a fail-closed guard on a REQUIRED, merge_group-triggered,
# path-filter-free check. A guard that cannot fail is observationally identical to one
# that passed. Under presence-is-registration the per-suite step checks are gone — what
# remains is the CONNECTION (runner step wired + sharded + unmasked, privileged suites
# sudo-invoked in the fixed job, aggregator needing both), and every arm gets a row.
#
# It also answers the gate's own former objection ("a companion suite would reproduce the
# orphan problem in miniature"): this file sits in .github/scripts/test/, so run-all.sh's
# `test-*.sh` glob picks it up automatically. It cannot be orphaned.
#
# CONTRACT (#6454): BASH-ONLY. git + sed + awk + grep, no terraform, no apt, no python.
#
# It NEVER mutates a tracked file. Everything happens in a `mktemp -d` sandbox, so an
# interrupted run cannot leave the repo altered.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE_REL=".github/scripts/test/test-infra-suite-registration.sh"
WF_REL=".github/workflows/infra-validation.yml"
RUNNER_REL="apps/web-platform/infra/run-registered-suites.sh"
INFRA_PREFIX="apps/web-platform/infra"

# The shell fixture chokepoint (#7849). Sourcing it here keeps the #6454 CONTRACT above intact.
#
# `git_fixture_env` is called LATER, after the `git -C "$REPO_ROOT" ls-files` enumeration below:
# that read is of the REAL repo and deliberately runs outside the constructed environment.
# shellcheck source=../../../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

SB=$(mktemp -d -t infra-reg-mut.XXXXXXXX) || { echo "SETUP: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT

pass=0
fail=0
asserts=0

ok()   { asserts=$((asserts+1)); pass=$((pass+1)); echo "[ok] $1"; }
bad()  { asserts=$((asserts+1)); fail=$((fail+1)); echo "[FAIL] $1" >&2; }
setup_die() { echo "SETUP FAILED: $1" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Sandbox. Suite STUBS (empty files) rather than copies of the real suites: the gate reads
# only path names, via `git ls-files`, so stubs are faithful for its purpose and keep this
# harness cheap. The gate also READS the runner's PRIVILEGED_WHY map, so the runner file
# is copied into the sandbox too.
# ---------------------------------------------------------------------------
mkdir -p "$SB/.github/scripts/test" "$SB/.github/workflows" "$SB/$INFRA_PREFIX" || setup_die "mkdir"
cp "$REPO_ROOT/$GATE_REL"   "$SB/$GATE_REL"   || setup_die "cp gate"
cp "$REPO_ROOT/$WF_REL"     "$SB/$WF_REL"     || setup_die "cp workflow"
cp "$REPO_ROOT/$WF_REL"     "$SB/wf.pristine" || setup_die "cp pristine"
cp "$REPO_ROOT/$RUNNER_REL" "$SB/$RUNNER_REL" || setup_die "cp runner"
cp "$REPO_ROOT/$RUNNER_REL" "$SB/runner.pristine" || setup_die "cp runner pristine"
# Arm 3b scans ALL workflows for test/infra registrations (a suite may legitimately
# live in another workflow), so the sandbox carries the whole directory.
cp "$REPO_ROOT"/.github/workflows/*.yml "$SB/.github/workflows/" || setup_die "cp workflows"
# The manifest coherence arm only runs when the file exists — carry it (and a
# pristine copy) or the whole arm is dead code inside this battery.
mkdir -p "$SB/$INFRA_PREFIX"
cp "$REPO_ROOT/apps/web-platform/infra/suite-shard-legs.tsv" \
  "$SB/apps/web-platform/infra/suite-shard-legs.tsv" || setup_die "cp manifest"
cp "$SB/apps/web-platform/infra/suite-shard-legs.tsv" "$SB/manifest.pristine" \
  || setup_die "cp manifest pristine"

mapfile -t REAL_SUITES < <(git -C "$REPO_ROOT" ls-files \
  "${INFRA_PREFIX}/*.test.sh" | LC_ALL=C sort -u)
(( ${#REAL_SUITES[@]} >= 50 )) || setup_die "only ${#REAL_SUITES[@]} real suites enumerated"

# The gate also enumerates apps/web-platform/test/infra/*.test.sh (Arm 3b: those
# are step-registered in the fixed job, outside the runner's glob) — stub them too.
mapfile -t TESTINFRA_SUITES < <(git -C "$REPO_ROOT" ls-files 'apps/web-platform/test/infra/*.test.sh')
for s in "${TESTINFRA_SUITES[@]}"; do
  mkdir -p "$SB/$(dirname "$s")" || setup_die "mkdir testinfra dir"
  : > "$SB/$s" || setup_die "stub $s"
done

declare -A STUB_DIRS=()
for s in "${REAL_SUITES[@]}"; do STUB_DIRS["${s%/*}"]=1; done
STUB_DIR_PATHS=()
for d in "${!STUB_DIRS[@]}"; do STUB_DIR_PATHS+=("$SB/$d"); done
mkdir -p "${STUB_DIR_PATHS[@]}" || setup_die "mkdir stub dirs"
for s in "${REAL_SUITES[@]}"; do
  : > "$SB/$s" || setup_die "stub $s"
done

# The real-repo enumeration above is done; from here every git call is sandbox-scoped.
git_fixture_env "$SB" || setup_die "git_fixture_env refused the mutation sandbox $SB"
git -C "$SB" init -q                >/dev/null 2>&1 || setup_die "git init"
sb_commit() { git -C "$SB" -c user.email=t@t -c user.name=t commit -qm "${1:-m}"   >/dev/null 2>&1 || setup_die "commit ${1:-m}"; }
# The gate enumerates HEAD's TREE (ls-tree), matching the runner — staged-but-
# uncommitted files are invisible to it, so every add below needs a commit.
git -C "$SB" add -A                 >/dev/null 2>&1 || setup_die "git add"
sb_commit init

run_gate() { ( cd "$SB" && bash "$GATE_REL" >"$SB/out.log" 2>&1; echo $?; ); }

restore_wf() { cp "$SB/wf.pristine" "$SB/$WF_REL" || setup_die "restore workflow"; }
restore_runner() { cp "$SB/runner.pristine" "$SB/$RUNNER_REL" || setup_die "restore runner"; }

assert_landed() {
  if cmp -s "$SB/wf.pristine" "$SB/$WF_REL"; then
    setup_die "mutation '$1' did not land (workflow byte-identical to pristine)"
  fi
}
assert_landed_runner() {
  if cmp -s "$SB/runner.pristine" "$SB/$RUNNER_REL"; then
    setup_die "mutation '$1' did not land (runner byte-identical to pristine)"
  fi
}

# ---------------------------------------------------------------------------
# POSITIVE CONTROL. Every row below is meaningless if the unmutated sandbox is not GREEN.
# ---------------------------------------------------------------------------
rc=$(run_gate)
if [[ "$rc" != "0" ]]; then
  echo "VOID: control (unmutated sandbox) exited $rc, not 0. No row below can be believed." >&2
  sed 's/^/    /' "$SB/out.log" >&2
  exit 2
fi
ok "control: unmutated sandbox is GREEN (rc=0)"

if grep -qE "^infra suite registration: ${#REAL_SUITES[@]} suites covered" "$SB/out.log"; then
  ok "control: success line accounts for all ${#REAL_SUITES[@]} suites"
else
  bad "control: success line does not report ${#REAL_SUITES[@]} suites -- $(tail -1 "$SB/out.log")"
fi

# ---------------------------------------------------------------------------
# RED rows.
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
    bad "$label: rc=$rc but expected message missing ($needle): $(tail -3 "$SB/out.log")"
  fi
}

LOOPBACK="$INFRA_PREFIX/workspaces-luks-loopback.test.sh"
RUNNER_LINE="        run: bash ${RUNNER_REL}"

# M1 -- the connection itself: delete the runner invocation and NO suite runs in CI.
expect_red "M1 delete the runner step" "invocations" \
  sed -i "\|^${RUNNER_LINE}\$|d" "$SB/$WF_REL"

# M2 -- an unsharded leg runs the FULL set: 4x the wall clock wearing a shard's clothes.
expect_red "M2 drop the SOLEUR_INFRA_SHARD wiring" "SOLEUR_INFRA_SHARD" \
  sed -i "\|SOLEUR_INFRA_SHARD:|d" "$SB/$WF_REL"

# M3 -- the exclusion waives the runner, never the invocation (the old M3, same property).
expect_red "M3 delete a privileged suite's sudo invocation" "NOT" \
  sed -i "\|sudo bash ${LOOPBACK}|d" "$SB/$WF_REL"

# M4 -- the comment-strip is the anti-vacuity core; a commented invocation must not satisfy it.
expect_red "M4 comment out the runner step" "invocations" \
  sed -i "s|^\([[:space:]]*\)run: bash ${RUNNER_REL}[[:space:]]*\$|\1# run: bash ${RUNNER_REL}|" "$SB/$WF_REL"

# M5 -- masking: the runner step can still be neutralised by continue-on-error.
expect_red "M5 add continue-on-error to the runner step" "continue-on-error" \
  sed -i "s|^\([[:space:]]*\)run: bash ${RUNNER_REL}[[:space:]]*\$|\1continue-on-error: true\n\1run: bash ${RUNNER_REL}|" "$SB/$WF_REL"

# M6 -- a privileged entry must cite a real tracking issue; #0 must not satisfy it.
# Mutates the RUNNER (the gate reads PRIVILEGED_WHY from it), not the workflow.
restore_wf; restore_runner
sed -i 's|#7695|#0|g' "$SB/$RUNNER_REL" || setup_die "M6 mutation cmd"
assert_landed_runner "M6"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M6 privileged entry cites #0: gate stayed GREEN (a placeholder satisfied 'cites an issue')"
elif grep -qF "cites no tracking" "$SB/out.log"; then
  ok "M6 privileged entry cites #0: rc=$rc and message names the right mode"
else
  bad "M6 privileged entry cites #0: rc=$rc but expected message missing"
fi
restore_runner

# M7 -- job scoping: relocating the matrix job leaves nothing sliced.
expect_red "M7 rename deploy-script-tests" "could not slice" \
  sed -i "s|^  deploy-script-tests:\$|  deploy-script-tests-renamed:|" "$SB/$WF_REL"

restore_wf

# M8 -- a STALE privileged entry: the runner's map names a suite that does not exist.
# (Replaces the old subdirectory-gap row — subdir suites now derive by glob, see M11.)
restore_runner
sed -i 's|\[workspaces-luks-loopback\.test\.sh\]=|[zzz-nonexistent-loopback.test.sh]=|' "$SB/$RUNNER_REL" \
  || setup_die "M8 mutation cmd"
assert_landed_runner "M8"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M8 stale privileged entry: gate stayed GREEN"
elif grep -qF "not a tracked infra" "$SB/out.log"; then
  ok "M8 stale privileged entry: rc=$rc and message names the stale pin"
else
  bad "M8 stale privileged entry: rc=$rc but message does not name it: $(tail -3 "$SB/out.log")"
fi
restore_runner

# M9 -- enumeration collapse must fail closed, not pass with zero coverage.
mv "$SB/$INFRA_PREFIX" "$SB/${INFRA_PREFIX}-moved" || setup_die "mv infra dir"
# The runner file lives under the moved dir too — the gate exits on a missing
# runner before enumerating, which is also fail-closed. Restore the runner path
# so this row measures the ENUMERATION arm specifically.
mkdir -p "$SB/$INFRA_PREFIX"
cp "$SB/runner.pristine" "$SB/$RUNNER_REL" || setup_die "restore runner under moved dir"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after mv"
sb_commit after-mv
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M9 enumeration collapse: gate stayed GREEN with zero suites"
else
  ok "M9 enumeration collapse: rc=$rc (fails closed)"
fi
rm -rf "$SB/$INFRA_PREFIX"
mv "$SB/${INFRA_PREFIX}-moved" "$SB/$INFRA_PREFIX" || setup_die "mv back"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after mv back"
sb_commit mv-back

# M10 -- fail-fast removed: one RED leg cancels the other three and a quarter of
# the suite set silently never runs.
expect_red "M10 drop fail-fast: false" "fail-fast" \
  sed -i "s|^      fail-fast: false\$|      fail-fast: true|" "$SB/$WF_REL"
# the key lives under `    strategy:` at indent 6 — a bare `fail-fast:` sed over the
# whole file could hit another job's; scoped by the exact indentation here.

# M11 -- the aggregator disconnect: -done without `needs: deploy-script-tests`
# means a red leg alerts nobody.
expect_red "M11 drop deploy-script-tests from -done needs:" "needs:" \
  sed -i "s|^    needs: \[deploy-script-tests, deploy-script-tests-fixed\]\$|    needs: [deploy-script-tests-fixed]|" "$SB/$WF_REL"

# M12 -- masking the other direction: `if: false` on the runner step is the same
# fail-open as continue-on-error.
expect_red "M12 add if: false to the runner step" "if:" \
  sed -i "s|^\([[:space:]]*\)run: bash ${RUNNER_REL}[[:space:]]*\$|\1if: false\n\1run: bash ${RUNNER_REL}|" "$SB/$WF_REL"

# ---------------------------------------------------------------------------
# GREEN rows. A guard that fires on everything is as useless as one that never fires.
# ---------------------------------------------------------------------------

# M13 -- THE NEW CONTRACT: a suite landing on disk with NO workflow edit stays
# green — presence IS registration now. (This row was RED under the old gate: the
# #7076 subdirectory hole it guarded is closed by glob derivation.)
NEWSUB="$INFRA_PREFIX/newdir/zzz-mutation-subdir.test.sh"
mkdir -p "$SB/$(dirname "$NEWSUB")" || setup_die "mkdir newsub"
: > "$SB/$NEWSUB" || setup_die "stub newsub"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add newsub"
sb_commit newsub
restore_wf
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  ok "M13 new subdirectory suite, NO workflow edit: GREEN — glob registration covers it"
else
  bad "M13 new subdirectory suite: gate red-failed a correctly-registered suite: $(tail -3 "$SB/out.log")"
fi
rm -f "$SB/$NEWSUB"; rmdir "$SB/$(dirname "$NEWSUB")" 2>/dev/null
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after M13"
sb_commit after-M13

# M14 -- `if:` on an ARTIFACT-UPLOAD step stays green: the masking check is
# scoped to the runner step, not the job. The pristine workflow ALREADY carries
# `if: failure()`/`always()` on its upload steps and the control run is GREEN —
# so this row pins that the scope is real, not vacuous: if the upload steps ever
# lose their `if:` keys, a job-wide masking regression would be untestable.
restore_wf
if grep -qE 'if: (failure\(\)|always\(\))' "$SB/$WF_REL"; then
  ok "M14 upload steps carry if: keys and the gate is GREEN (masking is step-scoped)"
else
  bad "M14 expected an if: failure()/always() upload step in the pristine workflow — the gate's masking check may be vacuously scoped"
fi

# M15 -- an apps/web-platform/test/infra/ suite is OUTSIDE the runner's glob and
# stays step-registered in the fixed job: landing one unwired must red (Arm 3b).
NEWTI="apps/web-platform/test/infra/zzz-mutation-unwired.test.sh"
mkdir -p "$SB/$(dirname "$NEWTI")" || setup_die "mkdir newti"
: > "$SB/$NEWTI" || setup_die "stub newti"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add newti"
sb_commit newti
restore_wf
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  bad "M15 unwired test/infra suite: gate stayed GREEN (the directory is not glob-registered)"
elif grep -qF "invoked by NO workflow" "$SB/out.log"; then
  ok "M15 unwired test/infra suite: rc=$rc and message names the coverage gap"
else
  bad "M15 unwired test/infra suite: rc=$rc but expected message missing: $(tail -3 "$SB/out.log")"
fi
rm -f "$SB/$NEWTI"
git -C "$SB" add -A >/dev/null 2>&1 || setup_die "git add after M15"
sb_commit after-M15

# M16 -- drop a leg from the matrix list. Every remaining leg still greens, but
# the dropped residue class is executed by NO leg — silent coverage shrink.
# The leg-totality arm (ADR-238 Decision 3) must catch it.
expect_red "M16 drop-a-leg" "does not tile 1..N" \
  sed -i 's/leg: \["1\/4", "2\/4", "3\/4", "4\/4"\]/leg: ["1\/4", "2\/4", "3\/4"]/' "$SB/$WF_REL"

# M17 -- duplicate a leg: ["1/4","1/4","2/4","4/4"] still tiles nothing for k=3.
expect_red "M17 duplicate-leg" "does not tile 1..N" \
  sed -i 's/leg: \["1\/4", "2\/4", "3\/4", "4\/4"\]/leg: ["1\/4", "1\/4", "2\/4", "4\/4"]/' "$SB/$WF_REL"

# M18 -- a SECOND `leg:` key: the gate reads the first list, YAML executes the
# last. An appended `leg: ["5/5"]` greens totality while every leg runs one
# residue class.
expect_red "M18 duplicate leg: key" "keys" \
  sed -i 's|^        leg: \["1/4", "2/4", "3/4", "4/4"\]|        leg: ["1/4", "2/4", "3/4", "4/4"]\n        leg: ["5/5"]|' "$SB/$WF_REL"

MANIFEST_REL="apps/web-platform/infra/suite-shard-legs.tsv"
restore_manifest() { cp "$SB/manifest.pristine" "$SB/$MANIFEST_REL" || setup_die "restore manifest"; }
expect_red_manifest() {  # manifest-mutating variant of expect_red
  local label="$1" needle="$2"; shift 2
  restore_wf; restore_manifest
  "$@" || setup_die "mutation cmd for $label"
  local rc; rc=$(run_gate)
  restore_manifest
  if [[ "$rc" == "0" ]]; then
    bad "$label: gate stayed GREEN (vacuous arm)"
  elif grep -qF "$needle" "$SB/out.log"; then
    ok "$label: rc=$rc and message names the right mode"
  else
    bad "$label: rc=$rc but expected message missing ($needle): $(tail -3 "$SB/out.log")"
  fi
}

# M19 -- a manifest row naming a suite that does not exist is drift the hash
# fallback would absorb; the coherence arm must name it.
expect_red_manifest "M19 stale manifest row" "not an executable infra" \
  sh -c 'printf "%s\t%s\n" "apps/web-platform/infra/zzz-stale-row.test.sh" "1" >> "$1"' _ "$SB/$MANIFEST_REL"

# M20 -- a manifest row assigned to a leg that does not exist (runner exit-2s
# on this exact shape; the gate must surface it pre-merge).
expect_red_manifest "M20 manifest leg out of range" "not a leg" \
  sh -c 'printf "%s\t%s\n" "apps/web-platform/infra/ci-deploy.test.sh" "9" >> "$1"' _ "$SB/$MANIFEST_REL"

# M21 -- a `# n=` header that disagrees with the matrix is the same drift one
# level up (the runner degrades to positional silently).
expect_red_manifest "M21 manifest n= mismatch" "leg count" \
  sed -i 's|^# n=4$|# n=3|' "$SB/$MANIFEST_REL"

# M22 -- `if: always()` dropped from -done: default needs: semantics render a
# cancelled upstream `skipped`, which branch protection can treat as success.
expect_red "M22 drop if: always() from -done" "always" \
  sed -i '/^  deploy-script-tests-done:/,/^  [a-z][a-z0-9_-]*:/{/^    if: always()$/d}' "$SB/$WF_REL"

# M23 -- notify reads the MATRIX job's result instead of the aggregate's: the
# #8735 blind spot restored (a cancelled leg passes `== "failure"`).
expect_red "M23 notify reads matrix result" "needs.deploy-script-tests-done.result" \
  sed -i 's|needs\.deploy-script-tests-done\.result|needs.deploy-script-tests.result|' "$SB/$WF_REL"

# M24 -- a second runner invocation means every suite runs twice (and the
# zero-count twin is no coverage at all).
expect_red "M24 duplicate runner step" "invocations" \
  sed -i "s|^\(        run: bash ${RUNNER_REL}[[:space:]]*\)\$|\1\n      - name: duplicate runner\n        run: bash ${RUNNER_REL}|" "$SB/$WF_REL"

# M25 -- a masked privileged sudo step: `if: false` under the loopback step
# greens presence while the suite never executes.
expect_red "M25 if: false on a privileged sudo step" "sudo step" \
  sed -i 's|^\(      - name: Run /workspaces LUKS staging-target.*\)$|\1\n        if: false|' "$SB/$WF_REL"

# M26 -- the fixed job's aggregate step masked: `if: false` on the aggregate
# step greens every leg regardless of their results.
expect_red "M26 if: false on the aggregate step" "aggregate step" \
  sed -i 's|^\(      - name: Aggregate deploy-script-tests results\)$|\1\n        if: false|' "$SB/$WF_REL"

# M27 -- SOLEUR_INFRA_DIR wired into the matrix job narrows the derived root:
# legs tile and green on a silently shrunken suite set.
expect_red "M27 SOLEUR_INFRA_DIR in matrix job" "SOLEUR_INFRA_DIR" \
  sed -i 's|^\(          SOLEUR_INFRA_SHARD:.*\)$|\1\n          SOLEUR_INFRA_DIR: apps/web-platform/infra/inngest-rls|' "$SB/$WF_REL"

# ---------------------------------------------------------------------------
# Assertion floor.
# ---------------------------------------------------------------------------
MIN_ASSERTS=28
if (( asserts < MIN_ASSERTS )); then
  echo "[FAIL] assertion floor: only $asserts assertion(s) ran, expected >= $MIN_ASSERTS." >&2
  echo "       Rows were removed or short-circuited. Lower the floor deliberately, with a reason." >&2
  fail=$((fail+1))
fi

echo ""
echo "=== infra-suite-registration mutations: $pass passed, $fail failed ($asserts assertions) ==="
(( fail == 0 ))
