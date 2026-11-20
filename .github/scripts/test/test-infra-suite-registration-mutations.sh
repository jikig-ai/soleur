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
# The durations-table arm (#9232) compares the committed suite-durations.tsv
# against the manifest's label set. Synthesize it FROM the manifest so the
# sandbox is self-consistent regardless of whether the real table has been
# regenerated yet — all-floor rows are valid under the src enum.
awk -F'\t' '!/^#/ && NF >= 1 {print $1 "\t60000\tfloor"}' \
  "$SB/apps/web-platform/infra/suite-shard-legs.tsv" \
  > "$SB/apps/web-platform/infra/suite-durations.tsv" || setup_die "synthesize durations"
cp "$SB/apps/web-platform/infra/suite-durations.tsv" "$SB/durations.pristine" \
  || setup_die "cp durations pristine"

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
rm -rf "${SB:?}/${INFRA_PREFIX:?}"
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
  sed -i "s|^    needs: \[detect-changes, deploy-script-tests, deploy-script-tests-fixed, bastion-boot-rehearsal\]\$|    needs: [detect-changes, deploy-script-tests-fixed, bastion-boot-rehearsal]|" "$SB/$WF_REL"

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
  sed -i 's|^    if: always() && needs.detect-changes.outputs.pr_duplicate != .true.$|    if: needs.detect-changes.outputs.pr_duplicate != '"'"'true'"'"'|' "$SB/$WF_REL"

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

# Durations-table arm (#9232): the sandbox's suite-durations.tsv is derived from
# the manifest above, so mutations here must restore it the same way.
DURATIONS_REL="apps/web-platform/infra/suite-durations.tsv"
restore_durations() { cp "$SB/durations.pristine" "$SB/$DURATIONS_REL" || setup_die "restore durations"; }
expect_red_durations() {  # durations-mutating variant of expect_red
  local label="$1" needle="$2"; shift 2
  restore_wf; restore_manifest; restore_durations
  "$@" || setup_die "mutation cmd for $label"
  local rc; rc=$(run_gate)
  restore_durations
  if [[ "$rc" == "0" ]]; then
    bad "$label: gate stayed GREEN (vacuous arm)"
  elif grep -qF "$needle" "$SB/out.log"; then
    ok "$label: rc=$rc and message names the right mode"
  else
    bad "$label: rc=$rc but expected message missing ($needle): $(tail -3 "$SB/out.log")"
  fi
}

# M28 -- a durations row naming a suite that does not exist is the same
# phantom class as a stale manifest row.
expect_red_durations "M28 phantom durations row" "not an executable infra" \
  sh -c 'printf "%s\t%s\t%s\n" "apps/web-platform/infra/zzz-stale-dur.test.sh" "100" "measured" >> "$1"' _ "$SB/$DURATIONS_REL"

# M29 -- a src value outside {measured,floor,estimate} is a malformed row; a typo'd
# enum must not silently pass as a fourth class.
expect_red_durations "M29 durations src outside enum" "malformed" \
  sh -c 'printf "%s\t%s\t%s\n" "apps/web-platform/infra/ci-deploy.test.sh" "100" "weighed" >> "$1"' _ "$SB/$DURATIONS_REL"

# M30 -- dropping a label from the durations table diverges the two committed
# key sets: the label has placement in the manifest and no weight in the
# table.
expect_red_durations "M30 durations/manifest key divergence" "different label" \
  sed -i '/^apps\/web-platform\/infra\/ci-deploy\.test\.sh\t/d' "$SB/$DURATIONS_REL"

# ---------------------------------------------------------------------------
# Arm 5 + the exclusion-map cross-check (#12941 review). The DEDICATED counterparts of
# M3/M6/M8/M25, the job-posture arms, and one row per review gap G1-G13 — every one of
# those was GREEN against the gate before the fix, so each row here is the proof the fix
# bites. Workflow edits are scoped to the bastion-boot-rehearsal job's line range: a bare
# `runs-on:`/`timeout-minutes:` sed would land in whichever job comes first.
# ---------------------------------------------------------------------------
DED_P="${INFRA_PREFIX}/bastion-runcmd-rehearsal.test.sh"
DJ='/^  bastion-boot-rehearsal:$/,/^  [a-z-]*:$/'
CI_REL=".github/workflows/ci.yml"
cp "$SB/$CI_REL" "$SB/ci.pristine" || setup_die "cp ci pristine"

expect_red_runner() {  # runner-mutating variant of expect_red
  local label="$1" needle="$2"; shift 2
  restore_wf; restore_runner
  "$@" || setup_die "mutation cmd for $label"
  assert_landed_runner "$label"
  local rc; rc=$(run_gate)
  restore_runner
  if [[ "$rc" == "0" ]]; then
    bad "$label: gate stayed GREEN (vacuous arm)"
  elif grep -qF -- "$needle" "$SB/out.log"; then
    ok "$label: rc=$rc and message names the right mode"
  else
    bad "$label: rc=$rc but expected message missing ($needle): $(tail -3 "$SB/out.log")"
  fi
}

# A5-1..A5-9: Arm 5 itself.
expect_red "A5-1 delete the dedicated suite step's run: line" "DEDICATED (never executed by the runner) but is NOT" \
  sed -i "\|^        run: bash ${DED_P}\$|d" "$SB/$WF_REL"
expect_red "A5-2 if: false on the dedicated step" "step for bastion-runcmd-rehearsal.test.sh carries" \
  sed -i "s|^        run: bash ${DED_P}\$|        if: false\n        run: bash ${DED_P}|" "$SB/$WF_REL"
expect_red "A5-3 continue-on-error on the dedicated step" "step for bastion-runcmd-rehearsal.test.sh carries" \
  sed -i "s|^        run: bash ${DED_P}\$|        continue-on-error: true\n        run: bash ${DED_P}|" "$SB/$WF_REL"
expect_red "A5-4 dedicated job on a self-hosted runner" "pinned GitHub-hosted" \
  sed -i "${DJ} s|^    runs-on: ubuntu-24.04\$|    runs-on: self-hosted|" "$SB/$WF_REL"
expect_red "A5-5 dedicated job binds secrets.X" "references a credential" \
  sed -i "${DJ} s|^    timeout-minutes: 18\$|    timeout-minutes: 18\n    env:\n      T: \${{ secrets.HCLOUD_TOKEN }}|" "$SB/$WF_REL"
expect_red "A5-6 dedicated checkout drops persist-credentials: false" "actions/checkout step(s) without" \
  sed -i "${DJ} {/^          persist-credentials: false\$/d}" "$SB/$WF_REL"
expect_red "A5-7 dedicated job permissions widened" "permissions are not exactly" \
  sed -i "${DJ} s|^      contents: read\$|      contents: write|" "$SB/$WF_REL"
# shellcheck disable=SC2016  # the needle is the gate's literal backtick-quoted job name
expect_red "A5-8 dedicated job dropped from -done needs:" 'does not list `bastion-boot-rehearsal`' \
  sed -i "s|^    needs: \[detect-changes, deploy-script-tests, deploy-script-tests-fixed, bastion-boot-rehearsal\]\$|    needs: [detect-changes, deploy-script-tests, deploy-script-tests-fixed]|" "$SB/$WF_REL"
expect_red "A5-9 dedicated job renamed" "has no such job" \
  sed -i "s|^  bastion-boot-rehearsal:\$|  bastion-boot-rehearsal-renamed:|" "$SB/$WF_REL"

# D1..D5: the DEDICATED_JOB_WHY parse (runner mutations).
expect_red_runner "D1 dedicated entry cites #0" "DEDICATED_JOB_WHY cites no tracking" \
  sed -i 's|bastion-boot-rehearsal job (#12941)"|bastion-boot-rehearsal job (#0)"|' "$SB/$RUNNER_REL"
expect_red_runner "D2 stale dedicated entry" "lists 'zzz-nonexistent-rehearsal.test.sh', which is not a tracked" \
  sed -i 's|^  \[bastion-runcmd-rehearsal\.test\.sh\]=|  [zzz-nonexistent-rehearsal.test.sh]=|' "$SB/$RUNNER_REL"
expect_red_runner "D3 dedicated entry names no owning job" "names no owning job" \
  sed -i 's|; runs in the bastion-boot-rehearsal job (#12941)"|; runs in its own lane (#12941)"|' "$SB/$RUNNER_REL"
expect_red_runner "D4 suite in both exclusion maps" "is in BOTH" \
  sed -i 's|^declare -A PRIVILEGED_WHY=($|declare -A PRIVILEGED_WHY=(\n  [bastion-runcmd-rehearsal.test.sh]="x (#12941)"|' "$SB/$RUNNER_REL"
expect_red_runner "D5 dedicated entry deleted (map parses to zero)" "DEDICATED_JOB_WHY exists in" \
  sed -i '/^  \[bastion-runcmd-rehearsal\.test\.sh\]=/d' "$SB/$RUNNER_REL"

# G1..G8: the invocation and posture gaps (A2/A4/A5).
expect_red "G1 invocation is an echo" "none or more than one" \
  sed -i "s|^        run: bash ${DED_P}\$|        run: echo bash ${DED_P}|" "$SB/$WF_REL"
expect_red "G2 invocation masked with || true" "none or more than one" \
  sed -i "s|^        run: bash ${DED_P}\$|        run: bash ${DED_P} \|\| true|" "$SB/$WF_REL"
expect_red "G3 job-level continue-on-error" "carries a job-level" \
  sed -i "${DJ} s|^    timeout-minutes: 18\$|    timeout-minutes: 18\n    continue-on-error: true|" "$SB/$WF_REL"
expect_red "G4 job env binds github.token" "references a credential" \
  sed -i "${DJ} s|^    timeout-minutes: 18\$|    timeout-minutes: 18\n    env:\n      GH_TOKEN: \${{ github.token }}|" "$SB/$WF_REL"
expect_red "G5 job env binds secrets['X']" "references a credential" \
  sed -i "${DJ} s|^    timeout-minutes: 18\$|    timeout-minutes: 18\n    env:\n      T: \${{ secrets['HCLOUD_TOKEN'] }}|" "$SB/$WF_REL"
expect_red "G6 second checkout without persist-credentials: false" "actions/checkout step(s) without" \
  sed -i "${DJ} s|^\(      - uses: hashicorp/setup-terraform@.*\)\$|      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5\n        with:\n          path: second\n\1|" "$SB/$WF_REL"
expect_red "G7 step env CI: ''" "sets CI" \
  sed -i "s|^        run: bash ${DED_P}\$|        env:\n          CI: ''\n        run: bash ${DED_P}|" "$SB/$WF_REL"
expect_red "G8 step env BRH_PARTIAL_MIN" "sets BRH_PARTIAL_MIN" \
  sed -i "s|^        run: bash ${DED_P}\$|        env:\n          BRH_PARTIAL_MIN: '1'\n        run: bash ${DED_P}|" "$SB/$WF_REL"
expect_red "G8b workflow-level env CI: '' (inherited by the job)" "sets CI" \
  sed -i "s|^  TERRAFORM_VERSION: \"1.10.5\"\$|  TERRAFORM_VERSION: \"1.10.5\"\n  CI: ''|" "$SB/$WF_REL"

# G9..G11 + the cross-check's own arms (A1): entries the text parse cannot see.
expect_red_runner "G9 second dedicated entry with a trailing comment" "cannot parse" \
  sed -i 's|^\(  \[bastion-runcmd-rehearsal\.test\.sh\]=.*\)$|  [bastion.test.sh]="x; runs in the bastion-boot-rehearsal job (#1)"  # note\n\1|' "$SB/$RUNNER_REL"
expect_red_runner "G10 second dedicated entry assigned after the block" "assigned at 2 site(s)" \
  sed -i 's|^_dedicated_job() {|DEDICATED_JOB_WHY[bastion.test.sh]="x; runs in the bastion-boot-rehearsal job (#1)"\n_dedicated_job() {|' "$SB/$RUNNER_REL"
expect_red_runner "G11 second dedicated entry single-quoted" "cannot parse" \
  sed -i "s|^\(  \[bastion-runcmd-rehearsal\.test\.sh\]=.*\)\$|  [bastion.test.sh]='x; runs in the bastion-boot-rehearsal job (#1)'\n\1|" "$SB/$RUNNER_REL"
# Set equality alone: block parses, one assignment site, but bash's set differs.
expect_red_runner "X1 dedicated entry unset after the block (runner set != parsed set)" "SKIP dedicated set differs" \
  sed -i "s|^_dedicated_job() {|unset 'DEDICATED_JOB_WHY[bastion-runcmd-rehearsal.test.sh]'\n_dedicated_job() {|" "$SB/$RUNNER_REL"
expect_red_runner "X2 privileged entry with a trailing comment (same parse, same class)" "PRIVILEGED_WHY in ${RUNNER_REL} has block line(s)" \
  sed -i 's|^\(  \[workspaces-luks-loopback\.test\.sh\]=".*"\)$|\1  # note|' "$SB/$RUNNER_REL"
expect_red_runner "X3 privileged entry unset after the block" "SKIP privileged set differs" \
  sed -i "s|^PRIV_SUITES=()\$|unset 'PRIVILEGED_WHY[workspaces-luks-loopback.test.sh]'\nPRIV_SUITES=()|" "$SB/$RUNNER_REL"
expect_red_runner "X4 runner --list fails (sets unreadable)" "--list\` exited 3" \
  sed -i 's|^  --list) LIST_ONLY=1 ;;$|  --list) exit 3 ;;|' "$SB/$RUNNER_REL"

# G12/G13 (A3): a second invocation anywhere else.
expect_red "G12 second invocation in deploy-script-tests-fixed" "is mentioned on 2" \
  sed -i "s|^\(        run: bash .github/scripts/test/fixtures-validate-infra-templates.sh\)\$|\1\n      - name: extra\n        run: bash ${DED_P}|" "$SB/$WF_REL"
restore_wf
sed -i "s|^\(        run: bash scripts/test-all.sh webplat\)\$|\1\n      - run: bash ${DED_P}|" "$SB/$CI_REL" || setup_die "G13 mutation cmd"
cmp -s "$SB/ci.pristine" "$SB/$CI_REL" && setup_die "mutation 'G13' did not land (ci.yml byte-identical)"
rc=$(run_gate)
cp "$SB/ci.pristine" "$SB/$CI_REL" || setup_die "restore ci.yml"
if [[ "$rc" == "0" ]]; then
  bad "G13 second invocation in ci.yml: gate stayed GREEN (vacuous arm)"
elif grep -qF "is mentioned on 2" "$SB/out.log"; then
  ok "G13 second invocation in ci.yml: rc=$rc and message names the right mode"
else
  bad "G13 second invocation in ci.yml: rc=$rc but expected message missing: $(tail -3 "$SB/out.log")"
fi

# GREEN: a trailing comment on the bare invocation is still the one unmasked invocation.
restore_wf; restore_runner
sed -i "s|^        run: bash ${DED_P}\$|        run: bash ${DED_P}  # the one CI home (Q25)|" "$SB/$WF_REL" \
  || setup_die "G-green mutation cmd"
assert_landed "G-green"
rc=$(run_gate)
if [[ "$rc" == "0" ]]; then
  ok "G-green trailing comment on the bare invocation stays GREEN (anchor is not over-strict)"
else
  bad "G-green trailing comment on the bare invocation: gate red-failed a valid step: $(tail -3 "$SB/out.log")"
fi
restore_wf

# ---------------------------------------------------------------------------
# Round 2 (#12941 review round 2): the dedicated job is held to an ALLOWLIST. One row per shape
# the round-1 seats measured GREEN at 851355d84b, each asserting the refusal that names it.
# ---------------------------------------------------------------------------
RS_NAME='      - name: Rehearse the bastion first boot'
RUN_DED="        run: bash ${DED_P}"
FIX_SITE='        run: bash .github/scripts/test/fixtures-validate-infra-templates.sh'
pre_step() { sed -i "${DJ} s|^\(${RS_NAME}\)|${1}\n\1|" "$SB/$WF_REL"; }   # a step before the run step
on_run()   { sed -i "s|^${RUN_DED}\$|${1}\n${RUN_DED}|" "$SB/$WF_REL"; }   # a key on the run step
job_key()  { sed -i "${DJ} s|^    timeout-minutes: 18\$|    timeout-minutes: 18\n${1}|" "$SB/$WF_REL"; }
elsewhere() { sed -i "s|^\(${FIX_SITE}\)\$|\1\n      - name: extra\n        run: ${1}|" "$SB/$WF_REL"; }
# shellcheck disable=SC2016  # literal workflow text: `$GITHUB_ENV` and `${{ }}` must reach the YAML unexpanded
{
GH_ENV_STEP='      - run: echo "CI=" >> "$GITHUB_ENV"'
GH_PATH_STEP='      - run: echo /tmp/shim >> "$GITHUB_PATH"'
EXPR_TOJSON_GH='    env:\n      CTX: ${{ toJSON(github) }}'
EXPR_TOJSON_SEC='    env:\n      CTX: ${{ toJson(secrets) }}'
EXPR_CAP_SEC='    env:\n      FOO: ${{ Secrets.FOO }}'
EXPR_FMT_SEC="    env:\n      CTX: \${{ format('{0}', secrets) }}"
WS_PATH='bash ${{ github.workspace }}/'"${DED_P}"
NAME_EXPR='      - name: Rehearse ${{ github.event.pull_request.title }}'
}

# shellcheck disable=SC2016  # needles are the gate's literal backtick-quoted text
{
expect_red "H1 pre-step rewrites the suite (sed -i '2i exit 0')" "the job has 2 run: step(s)" \
  pre_step "      - run: sed -i '2i exit 0' ${DED_P}"
expect_red "H2 shell: true {0} on the run step" "refused key(s): shell:" \
  on_run "        shell: true {0}"
expect_red "H3 job-level defaults: run: shell: true {0}" "refused key(s): defaults:" \
  job_key "    defaults:\n      run:\n        shell: true {0}"
expect_red "H4 workflow-level defaults: run: shell: true {0}" "workflow-level defaults: block" \
  sed -i 's|^env:$|defaults:\n  run:\n    shell: true {0}\n\nenv:|' "$SB/$WF_REL"
expect_red "H5 pre-step writes \$GITHUB_ENV" "references GITHUB_ENV" pre_step "$GH_ENV_STEP"
expect_red "H5b pre-step writes \$GITHUB_PATH" "references GITHUB_PATH" pre_step "$GH_PATH_STEP"
expect_red "H6 decoy echo-xbash step + continue-on-error on the real step" \
  "step for bastion-runcmd-rehearsal.test.sh carries" \
  sed -i -e "${DJ} s|^\(${RS_NAME}\)|      - run: echo xbash ${DED_P}\n\1|" \
    -e "s|^${RUN_DED}\$|        continue-on-error: true\n${RUN_DED}|" "$SB/$WF_REL"
expect_red "H7 job env toJSON(github)" "references a credential" job_key "$EXPR_TOJSON_GH"
expect_red "H8 job env toJson(secrets)" "references a credential" job_key "$EXPR_TOJSON_SEC"
expect_red "H9 job env Secrets.FOO" "references a credential" job_key "$EXPR_CAP_SEC"
expect_red "H10 job env format('{0}', secrets)" "references a credential" job_key "$EXPR_FMT_SEC"
expect_red "H11 step flow env { CI: '' }" "sets CI" on_run "        env: { CI: '' }"
expect_red "H12 step env quoted \"CI\" key" "sets CI" on_run "        env:\n          \"CI\": ''"
expect_red "H13 step env quoted 'BRH_STATIC_ONLY' key" "sets BRH_STATIC_ONLY" \
  on_run "        env:\n          'BRH_STATIC_ONLY': '1'"
expect_red "H14 workflow env quoted \"CI\" key" "sets CI" \
  sed -i "s|^  TERRAFORM_VERSION: \"1.10.5\"\$|&\n  \"CI\": ''|" "$SB/$WF_REL"
expect_red "H14b workflow env BASH_ENV (no knob name)" "inherits is outside its allowlist" \
  sed -i "s|^  TERRAFORM_VERSION: \"1.10.5\"\$|&\n  BASH_ENV: apps/web-platform/infra/x.sh|" "$SB/$WF_REL"
expect_red "H15 step env with a harmless key (env: itself refused)" "refused key(s): env:" \
  on_run "        env:\n          FOO: bar"
expect_red "H16 working-directory: on the run step" "refused key(s): working-directory:" \
  on_run "        working-directory: apps"
expect_red "H16b expression outside the allowlist" "expression(s) outside its allowlist" \
  sed -i "${DJ} s|^${RS_NAME}.*\$|${NAME_EXPR}|" "$SB/$WF_REL"
expect_red "H16c a local composite action step in the job" "allowed: actions/checkout" \
  pre_step "      - uses: ./.github/actions/zz"
expect_red "H16d a job key outside the allowlist (container:)" "is not allowlisted (needs, if" \
  job_key "    container: ubuntu:24.04"
expect_red "H17 second invocation ./<path>" "is mentioned on 2" elsewhere "./${DED_P}"
expect_red "H18 second invocation, bare <path>" "is mentioned on 2" elsewhere "${DED_P}"
expect_red "H19 second invocation bash -x <path>" "is mentioned on 2" elsewhere "bash -x ${DED_P}"
expect_red "H20 second invocation bash \"<path>\"" "is mentioned on 2" elsewhere "bash \"${DED_P}\""
expect_red "H21 second invocation \${{ github.workspace }}/<path>" "is mentioned on 2" elsewhere "$WS_PATH"
# (`\\|`: the helper's sed uses `|` as its delimiter.)
expect_red "H23 second checkout whose persist-credentials is block-scalar text" \
  "actions/checkout step(s) without" \
  pre_step "      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5\n        with:\n          path: other\n          sparse-checkout: \\|\n            persist-credentials: false"
expect_red "H24 steps re-indented by two spaces" "non-canonical indentation" \
  sed -i "${DJ} { /^    steps:\$/,/^  [a-z-]*:\$/ s|^      |        | }" "$SB/$WF_REL"
expect_red "H25 suite step moved into a glued job whose header carries a comment" \
  "DEDICATED (never executed by the runner) but is NOT" \
  sed -i "s|^${RUN_DED}\$|        run: echo ok\n\n  sneaky:  # glued\n    needs: detect-changes\n    runs-on: [self-hosted, linux]\n    steps:\n      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5\n        with:\n          persist-credentials: false\n      - name: Rehearse\n${RUN_DED}|" "$SB/$WF_REL"
expect_red_runner "H26 same-count swap of the dedicated member (set equality, not a count)" \
  "SKIP dedicated set differs" \
  sed -i "s|^_dedicated_job() {|declare -n _dj=DEDICATED_JOB_WHY; _dj[bastion.test.sh]=\"x; runs in the bastion-boot-rehearsal job (#1)\"; unset '_dj[bastion-runcmd-rehearsal.test.sh]'; unset -n _dj\n_dedicated_job() {|" "$SB/$RUNNER_REL"
expect_red_runner "H27 --list prints nothing and exits 0" "SKIP privileged set differs" \
  sed -i 's|^if (( LIST_ONLY )); then$|&\n  exit 0|' "$SB/$RUNNER_REL"

# P1..P4: the privileged arm's anchored invocation (R2A-7).
SMP="${INFRA_PREFIX}/sandbox-masked-proc-docker.test.sh"
expect_red "P1 privileged step masked with || true" \
  "sandbox-masked-proc-docker.test.sh is PRIVILEGED (excluded from the runner, needs root) but is NOT" \
  sed -i "s#^\(        run: sudo bash ${SMP}\)\$#\1 || true#" "$SB/$WF_REL"
expect_red "P2 privileged invocation is an echo" \
  "sandbox-masked-proc-docker.test.sh is PRIVILEGED (excluded from the runner, needs root) but is NOT" \
  sed -i "s#^        run: sudo bash ${SMP}\$#        run: echo sudo bash ${SMP}#" "$SB/$WF_REL"
expect_red "P3 set +e before a privileged run: | line" \
  "sudo step for workspaces-luks-loopback.test.sh masks its exit" \
  sed -i "s#^          sudo bash ${LOOPBACK}\$#          set +e\n&#" "$SB/$WF_REL"
expect_red "P4 decoy echo step before a privileged step masked with if: false" \
  "sudo step for sandbox-masked-proc-docker.test.sh carries" \
  sed -i "s#^        run: sudo bash ${SMP}\$#        run: echo decoy\n      - run: echo sudo bash ${SMP}\n      - name: real\n        if: false\n        run: sudo bash ${SMP}#" "$SB/$WF_REL"
}

# H22: a local composite action invoking the suite (the scan covers .github/actions/**).
restore_wf
mkdir -p "$SB/.github/actions/zz" || setup_die "mkdir composite action"
printf 'runs:\n  using: composite\n  steps:\n    - run: bash %s\n      shell: bash\n' "$DED_P" \
  > "$SB/.github/actions/zz/action.yml" || setup_die "H22 mutation cmd"
rc=$(run_gate)
rm -rf "$SB/.github/actions/zz"
if [[ "$rc" == "0" ]]; then
  bad "H22 composite action invoking the suite: gate stayed GREEN (vacuous arm)"
elif grep -qF "is mentioned on 2" "$SB/out.log"; then
  ok "H22 composite action invoking the suite: rc=$rc and message names the right mode"
else
  bad "H22 composite action invoking the suite: rc=$rc but expected message missing: $(tail -3 "$SB/out.log")"
fi

# GREEN: the allowlist is not over-strict on the shapes it allows.
green_row() {  # <label> <mutation cmd…>
  local label="$1"; shift
  restore_wf; restore_runner
  "$@" || setup_die "mutation cmd for $label"
  assert_landed "$label"
  local rc; rc=$(run_gate)
  if [[ "$rc" == "0" ]]; then ok "$label stays GREEN"
  else bad "$label: gate red-failed a valid shape: $(grep -m2 '::error::' "$SB/out.log")"; fi
}
green_row "P-green trailing comment on a privileged sudo line" \
  sed -i "s|^        run: sudo bash ${SMP}\$|&  # note|" "$SB/$WF_REL"
green_row "H-green the run step written as its step's first key (- run:)" \
  sed -i -e "${DJ} {/^${RS_NAME}/d}" -e "s|^${RUN_DED}\$|      - run: bash ${DED_P}|" "$SB/$WF_REL"
green_row "H-green a comment line inside the job mentioning env:/shell:/secrets" \
  sed -i "s|^${RUN_DED}\$|        # env: shell: secrets.X \$GITHUB_ENV (commented, so inert)\n${RUN_DED}|" "$SB/$WF_REL"
restore_wf; restore_runner

# ---------------------------------------------------------------------------
# Assertion floor.
# ---------------------------------------------------------------------------
# 31 -> 65 with the #12941 review rows (A5-1..9, D1..5, G1..G13 + G8b, X1..X4, G-green = 33
# rows, plus the pre-existing 32): measured on the green run that added them.
# 65 -> 104 with the round-2 allowlist rows (H1..H27 incl. H5b/H14b/H16b-d = 32, P1..P4, and
# 3 GREEN rows = 39): measured on the green run that added them.
MIN_ASSERTS=104
if (( asserts < MIN_ASSERTS )); then
  echo "[FAIL] assertion floor: only $asserts assertion(s) ran, expected >= $MIN_ASSERTS." >&2
  echo "       Rows were removed or short-circuited. Lower the floor deliberately, with a reason." >&2
  fail=$((fail+1))
fi

echo ""
echo "=== infra-suite-registration mutations: $pass passed, $fail failed ($asserts assertions) ==="
(( fail == 0 ))
