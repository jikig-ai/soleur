#!/usr/bin/env bash
# scripts-shard-runtime-coverage.test.sh — every runtime a scripts-shard suite
# invokes must actually be installed in the `test-scripts` CI job.
#
# WHY THIS EXISTS (#7332). `ci.yml`'s `test-scripts` job carried a comment asserting
# "No `bun` in the scripts group", justified by
# `grep -l '^bun ' plugins/soleur/test/*.test.sh` returning zero matches. That
# predicate is anchored to column 1, so it was structurally unable to see a `bun`
# call inside a function body — which is exactly what
# `c4-from-components.test.sh:60` added (`run_producer() { bun "$PRODUCER" … }`).
#
# The result: a guard that restated the condition it protected, kept reporting
# "clean", and let a suite into a shard with no `bun`. It failed with
# `bun: command not found` — and because the failure was inside the suite rather
# than at collection, its actual render arms never ran while the shard went red for
# a reason unrelated to the code under test.
#
# So the lesson is not "add setup-bun" (already done). It is that a detection
# predicate anchored more narrowly than the thing it detects fails SILENTLY and in
# the reassuring direction. This asserts the invariant directly instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

echo "=== scripts-shard runtime coverage ==="
echo ""

assert_file_exists "$CI_YML" "ci.yml exists"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

# A scripts shard's own job block. Bounded by the next top-level job key so a
# later job's steps cannot leak in and satisfy an assertion about this one.
# NOTE: `^  test-scripts:` does NOT match `test-scripts-heavy:` (the colon
# differs), so the light job's block terminates correctly at the heavy job.
job_block() {  # $1 = job name
  local job="$1"
  awk -v j="^  ${job}:" '$0 ~ j {f=1} f&&/^  [^ #][^:]*:[[:space:]]*(#.*)?$/&&$0 !~ j {exit} f' "$CI_YML"
}
BLOCK="$(job_block test-scripts)"
HEAVY_BLOCK="$(job_block test-scripts-heavy)"

if [[ -z "$BLOCK" ]]; then
  echo "  FAIL: could not extract the test-scripts job block from ci.yml"
  FAIL=$((FAIL + 1))
  print_results
fi
if [[ -z "$HEAVY_BLOCK" ]]; then
  echo "  FAIL: could not extract the test-scripts-heavy job block from ci.yml — the heavy job runs the same suites' toolchain contract and is unguarded without it"
  FAIL=$((FAIL + 1))
  print_results
fi

# Non-vacuity: the extraction must have found a real job, not an empty string that
# makes every `grep -q` below trivially false and every negative assertion pass.
BLOCK_LINES="$(printf '%s\n' "$BLOCK" | wc -l)"
if [[ "$BLOCK_LINES" -lt 10 ]]; then
  echo "  FAIL: test-scripts block is only $BLOCK_LINES lines — extraction is wrong"
  FAIL=$((FAIL + 1))
  print_results
fi
echo "  PASS: extracted the test-scripts job block ($BLOCK_LINES lines)"
PASS=$((PASS + 1))
HEAVY_LINES="$(printf '%s\n' "$HEAVY_BLOCK" | wc -l)"
if [[ "$HEAVY_LINES" -lt 10 ]]; then
  echo "  FAIL: test-scripts-heavy block is only $HEAVY_LINES lines — extraction is wrong"
  FAIL=$((FAIL + 1))
  print_results
fi
echo "  PASS: extracted the test-scripts-heavy job block ($HEAVY_LINES lines)"
PASS=$((PASS + 1))

# Which suites does the scripts shard actually run? Mirror test-all.sh's glob.
# NOT anchored to column 1 — that anchoring is the defect this file exists to stop.
RUNTIME_RE='(^|[^[:alnum:]_./-])'

# The suites in <dir> that invoke <runtime>. ONE scan, used by the contract and by the real-list
# check below, so the two cannot drift. Approximate by design: it matches the runtime as a word
# after a command boundary in the suite's own text (comments stripped), one level deep, so a call
# moved into a sourced helper is invisible and a runtime named only in a string or a `for` word list
# still counts. That errs toward requiring the install, which is the safe direction.
users_of() {  # $1 = runtime, $2 = dir
  local f body
  for f in "$2"/*.test.sh; do
    [[ -f "$f" ]] || continue
    # Strip comments before searching so a suite that merely DISCUSSES a runtime
    # is not counted as invoking it (the comment-vs-code collision class).
    # Herestring, not `sed | grep -q`: under pipefail an early match closes the pipe and the
    # producer's SIGPIPE (141) would read as "no match" on a large suite.
    body="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$f")"
    if grep -qE "${RUNTIME_RE}${1}[[:space:]]" <<<"$body"; then basename "$f"; fi
  done
}

# check_runtime <runtime> <setup_marker> <block> <job> <users_dir> <required>
# Prints ONE status line and returns 0 (pass), 1 (fail) or 2 (skip); it bumps no global
# counter, so the mutation rows below can drive it in a subshell against fixtures and the
# caller (not the function) decides what a status means.
#   required=1 turns "no suite invokes it" from a SKIP into a FAIL: an empty users list is
#   the vacuous case a real contract must not pass (the likec4 row below).
check_runtime() {
  local runtime="$1" setup_marker="$2" block="$3" job="$4" users_dir="$5" required="$6"
  local users=() stripped
  mapfile -t users < <(users_of "$runtime" "$users_dir")

  if [[ ${#users[@]} -eq 0 ]]; then
    if [[ "$required" == "1" ]]; then
      echo "  FAIL: no scripts-shard suite invokes '$runtime' — an empty users list must fail, not skip, for a required row"
      return 1
    fi
    echo "  SKIP: no scripts-shard suite invokes '$runtime'"
    return 2
  fi

  # Whole-line AND trailing comments are dropped from the job block first: a keep-decision comment
  # that quotes the marker would otherwise satisfy the match after the real step is deleted. Text
  # level only: a step that quotes the command without running it, or carries `if: false`, is caught
  # by the parsed per-job checks in apps/web-platform/test/c4-likec4-version-pin.test.ts.
  # Herestring for the same SIGPIPE reason as above.
  stripped="$(printf '%s\n' "$block" | sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//')"
  if grep -qE "$setup_marker" <<<"$stripped"; then
    echo "  PASS: '$runtime' is invoked by ${#users[@]} suite(s) (${users[*]}) and installed in $job"
    return 0
  fi
  echo "  FAIL: ${#users[@]} scripts-shard suite(s) invoke '$runtime' but $job does not install it"
  echo "    suites: ${users[*]}"
  echo "    expected a step matching: $setup_marker"
  return 1
}

# Count a check_runtime status into the suite's counters.
tally() {  # $1 = status, $2 = the check_runtime output line(s)
  printf '%s\n' "$2"
  case "$1" in
    0) PASS=$((PASS + 1)) ;;
    2) SKIPPED=$((SKIPPED + 1)) ;;
    *) FAIL=$((FAIL + 1)) ;;
  esac
}

REAL_USERS_DIR="$REPO_ROOT/plugins/soleur/test"

for _job_block in "test-scripts|$BLOCK" "test-scripts-heavy|$HEAVY_BLOCK"; do
  _job="${_job_block%%|*}"
  _blk="${_job_block#*|}"
  _out="$(check_runtime "bun" 'oven-sh/setup-bun' "$_blk" "$_job" "$REAL_USERS_DIR" 0)" && _rc=0 || _rc=$?
  tally "$_rc" "$_out"
  # likec4 is asserted for the LIGHT job only. Three light suites (render-c4-model,
  # c4-from-components, c4-model-freshness) render through `npx`, and the install is their
  # download-cache warm-up, so the light job must carry it. No registration the heavy job runs
  # invokes likec4 and every consumer falls back to `npx`, so the heavy install was never a
  # correctness requirement and this contract does not demand one there; the pin test's ci.yml
  # install count (2) is what notices a silent re-add or a deleted light install.
  if [[ "$_job" == "test-scripts" ]]; then
    _out="$(check_runtime "likec4" 'npm install -g likec4@' "$_blk" "$_job" "$REAL_USERS_DIR" 1)" && _rc=0 || _rc=$?
    tally "$_rc" "$_out"
  fi
  _out="$(check_runtime "gitleaks" 'gitleaks' "$_blk" "$_job" "$REAL_USERS_DIR" 0)" && _rc=0 || _rc=$?
  tally "$_rc" "$_out"
done

# The real light users list must be non-empty and include the renderer suite: an empty or
# renamed list would turn the likec4 row above into a SKIP-shaped pass.
LIGHT_LIKEC4_USERS="$(users_of likec4 "$REAL_USERS_DIR")"
if printf '%s\n' "$LIGHT_LIKEC4_USERS" | grep -qx 'render-c4-model.test.sh'; then
  echo "  PASS: the real light users list is non-empty and includes render-c4-model.test.sh"
  PASS=$((PASS + 1))
else
  echo "  FAIL: the real light users list does not include render-c4-model.test.sh — the likec4 row would be reading nothing"
  FAIL=$((FAIL + 1))
fi

# Mutation-proof the central assertion: with the setup step removed from the block,
# the bun check MUST fail. A guard nobody has seen red is not a guard.
MUTATED="$(printf '%s\n' "$BLOCK" | grep -v 'oven-sh/setup-bun')"
if printf '%s\n' "$MUTATED" | grep -qE 'oven-sh/setup-bun'; then
  echo "  FAIL: self-check — could not remove the setup-bun line to prove non-vacuity"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: self-check — the setup-bun assertion is reading a real line (removing it changes the block)"
  PASS=$((PASS + 1))
fi

# --- fixture-fed mutation rows for the likec4 row ----------------------
# Fixture-fed calls of check_runtime in a subshell: no live file is mutated and this suite's own
# counters are untouched. The setup-bun self-check above only proves `grep -v` removes a line;
# these prove the likec4 row's decisions, including the two it must NOT get wrong in the
# reassuring direction (a comment quoting the marker, an empty users list).
# Under the scratch root test-helpers.sh already owns and removes on EXIT: a second `trap ... EXIT`
# here would REPLACE the helper's composed one and leak its sandbox (#8659).
FIX_DIR="$(mktemp -d "$INCIDENTS_REPO_ROOT/shard-cov.XXXXXXXX")"
mkdir -p "$FIX_DIR/users" "$FIX_DIR/empty" "$FIX_DIR/commentonly"
printf '#!/usr/bin/env bash\nlikec4 --version\n' >"$FIX_DIR/users/uses-likec4.test.sh"
printf '#!/usr/bin/env bash\n# likec4 --version is only discussed here\nx=1 # likec4 render\n' >"$FIX_DIR/commentonly/discusses-likec4.test.sh"
GOOD_BLOCK=$'  test-scripts:\n    steps:\n      - name: Install likec4 CLI (pinned)\n        run: npm install -g likec4@1.50.0 --before=2026-09-28 --ignore-scripts\n      - run: bash scripts/test-all.sh\n'
REMOVED_BLOCK=$'  test-scripts:\n    steps:\n      - run: bash scripts/test-all.sh\n'
COMMENT_BLOCK=$'  test-scripts:\n    steps:\n      # Install likec4 CLI: npm install -g likec4@1.50.0 --before=2026-09-28 (keep decision)\n      - run: bash scripts/test-all.sh\n'
TRAILING_BLOCK=$'  test-scripts:\n    steps:\n      - run: bash scripts/test-all.sh  # npm install -g likec4@1.50.0 --before=2026-09-28 --ignore-scripts\n'
RENAMED_BLOCK=$'  test-scripts:\n    steps:\n      - name: Warm the renderer cache\n        run: npm install -g likec4@1.50.0 --before=2026-09-28\n'

row() {  # <want> <label> <block> <users_dir> <required>
  local want="$1" label="$2" block="$3" users_dir="$4" required="$5" rc=0
  ( check_runtime "likec4" 'npm install -g likec4@' "$block" "fixture-job" "$users_dir" "$required" >/dev/null ) && rc=0 || rc=$?
  if [[ "$rc" == "$want" ]]; then
    echo "  PASS: $label (status $rc)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — wanted status $want, got $rc"
    FAIL=$((FAIL + 1))
  fi
}
row 0 "control: a block with the install and a likec4 user passes" "$GOOD_BLOCK" "$FIX_DIR/users" 1
row 1 "mutation 1: the install step removed from the light block fails" "$REMOVED_BLOCK" "$FIX_DIR/users" 1
row 1 "mutation 2: only a COMMENT quoting the marker (step deleted) fails" "$COMMENT_BLOCK" "$FIX_DIR/users" 1
row 1 "mutation 2b: the marker only in a TRAILING comment on an unrelated step fails" "$TRAILING_BLOCK" "$FIX_DIR/users" 1
row 1 "mutation 3: an empty users list with required=1 fails instead of skipping" "$GOOD_BLOCK" "$FIX_DIR/empty" 1
row 0 "must-PASS: the install under a different step name still passes" "$RENAMED_BLOCK" "$FIX_DIR/users" 1
row 2 "must-PASS: required=0 with an empty users list is a SKIP (bun and gitleaks keep skipping)" "$GOOD_BLOCK" "$FIX_DIR/empty" 0
row 2 "must-PASS: a suite that only DISCUSSES the runtime in comments is not a user (SKIP, not FAIL)" "$GOOD_BLOCK" "$FIX_DIR/commentonly" 0

# Instrument controls. The floor below counts runs, not verdicts, so drive row() and tally() once each
# with a deliberately wrong expectation in a subshell and require the verdict to register as a FAILURE
# (a row() or tally() whose verdict is always "ok" would otherwise keep the floor and the counters happy).
_ctl() {  # <label> <expected "PASS FAIL SKIPPED"> <command...>
  local label="$1" want="$2" got; shift 2
  got="$( PASS=0 FAIL=0 SKIPPED=0; "$@" >/dev/null 2>&1 || true; echo "$PASS $FAIL $SKIPPED" )"
  if [[ "$got" == "$want" ]]; then
    echo "  PASS: instrument control — $label (counters $got)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: instrument control — $label: wanted counters '$want', got '$got'"
    FAIL=$((FAIL + 1))
  fi
}
_ctl "row() with a wrong expectation registers a FAILURE" "0 1 0" row 1 "wrong-on-purpose" "$GOOD_BLOCK" "$FIX_DIR/users" 1
_tally_ctl() { tally 0 "ok"; tally 1 "bad"; tally 2 "skip"; }
_ctl "tally() counts status 0 as a pass, 1 as a failure and 2 as a skip" "1 1 1" _tally_ctl
rm -rf "$FIX_DIR"

# --- every executable producer must have a documented call site ---------------
# #7332: write-kb-coverage.ts shipped with NO invocation anywhere. sync.md linked the
# pure lib (unrunnable — no import.meta.main) and gave no command, so the artifact was
# never produced and every control that depends on it — the wording rule, determinism,
# the counts-only marker, the degraded rows — was unreachable. Five review agents found
# it independently; nothing mechanical did.
#
# A producer that nothing invokes is indistinguishable from one that works.
echo ""
echo "=== executable producers have call sites ==="
PRODUCERS=0
for prod in "$REPO_ROOT"/plugins/soleur/scripts/*.ts; do
  [[ -f "$prod" ]] || continue
  # Only entry points — a module without import.meta.main is a library, not a producer.
  grep -q 'import.meta.main' "$prod" || continue
  base="$(basename "$prod")"
  PRODUCERS=$((PRODUCERS + 1))
  # A call site is a `bun …/<name>` in a command/skill doc or a workflow. Its own
  # source and its own tests do not count.
  # `|| true` is load-bearing: grep exits 1 when it finds NOTHING, which is exactly
  # the case this check exists to report. Under `set -euo pipefail` the bare form
  # aborted the whole suite at this assignment — before the FAIL below could print —
  # so a producer with no call site produced a silent non-zero exit instead of a
  # diagnostic. Verified by mutation: removing the sync.md invocation left this guard
  # reporting zero failures until the `|| true` was added.
  hits="$(grep -rlE "bun[[:space:]]+[^[:space:]]*${base%.ts}\.ts" \
            "$REPO_ROOT/plugins/soleur/commands" \
            "$REPO_ROOT/plugins/soleur/skills" \
            "$REPO_ROOT/.github/workflows" 2>/dev/null | wc -l || true)"
  if [[ "$hits" -gt 0 ]]; then
    echo "  PASS: $base is invoked from $hits documented call site(s)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $base is an executable producer with NO documented call site"
    echo "    add a 'bun plugins/soleur/scripts/$base' invocation to the command/skill that runs it"
    FAIL=$((FAIL + 1))
  fi
done

# Anti-vacuity floor: neutering tally()/row() leaves PASS and FAIL at 0 and would otherwise exit 0. The fixed
# assertions number 20 (derived from a green run); the producer loop above adds one per executable producer,
# so the floor tracks it instead of tripping on a legitimate removal. A FLOOR, never equality.
print_results $((20 + PRODUCERS))
