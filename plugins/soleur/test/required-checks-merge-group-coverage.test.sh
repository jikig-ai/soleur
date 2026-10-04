#!/usr/bin/env bash
# Guard 1 suite (#9454): every context required by ANY ruleset on main must have a
# producer on a `merge_group` event. The engine is scripts/probe-merge-group-coverage.sh
# (offline, reads both canonical required-status-check JSONs and every workflow); this
# file is the mutation battery around it.
#
# Case map (plan "Guard 1"):
#   case 0   the engine against the REAL repo and under `env -i` (sandbox PATH, <15s)
#   rows 1-9 mutations of a pristine copy of the real inputs; each must turn the engine RED
#            with a message that names the mutated context (anchor = the engine's own
#            error-line shape, never a bare token)
#   rows 10+ the `if:` shapes that exclude merge_group (negated, `&& false`), the synthetic
#            workflow's step-level if / continue-on-error / needs, and the queue-off SKIPPED
#            path (a rollback PR re-adding CodeQL must not go red; SKIPPED is never read as OK)
#   C1-C4    controls: each verdict helper (engine_green, engine_skipped, row_red, row_green)
#            is driven once with an input that must fail and must record that failure
#   H1       loader mutant (reads d["on"] only, misses the PyYAML True key) must be caught
#   H2       must-PASS synthesized fixtures (map/list/string `on:` forms, always(), an
#            event-name `if:` that names merge_group, a context resolved from `name:`)
#   H3       a mutant without the floor, fed an empty canonical, prints OK with contexts=0:
#            the suite's own verdict (engine_green) must still call that RED
#
# Every mutation is applied to a COPY and proven to land (diff against the pristine copy)
# before the engine runs: a sed that silently matches nothing would otherwise score as
# "the guard detected it" or "the guard missed it" for the wrong reason.
# shellcheck disable=SC2329  # the m<N>/h<N> mutation functions are invoked indirectly via mutate()
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENGINE_REL="scripts/probe-merge-group-coverage.sh"
ENGINE="$REPO_ROOT/$ENGINE_REL"
FIXTURES="$SCRIPT_DIR/fixtures/merge-group-coverage"
SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin"

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

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

command -v python3 >/dev/null 2>&1 || { echo "[FATAL] python3 not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq not found" >&2; exit 2; }
[[ -d "$FIXTURES/pass" ]] || { echo "[FATAL] fixture dir $FIXTURES/pass missing" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

PRISTINE="$WORK/pristine"; assert_fixture_dir "$PRISTINE"
SBX="$WORK/sbx"; assert_fixture_dir "$SBX"

# The mutable copy holds only what the engine reads: the workflows, the two canonical
# JSONs, the ruleset terraform (queue on/off) and the engine itself. A missing source is a harness setup failure (exit 2),
# never a result: a copy that silently omitted a file would score every row wrongly.
build_pristine() {
  mkdir -p "$PRISTINE/.github" "$PRISTINE/scripts" || exit 2
  cp -R "$REPO_ROOT/.github/workflows" "$PRISTINE/.github/workflows" || exit 2
  cp "$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json" "$PRISTINE/scripts/" || exit 2
  cp "$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json" "$PRISTINE/scripts/" || exit 2
  mkdir -p "$PRISTINE/infra/github" || exit 2
  cp "$REPO_ROOT/infra/github/ruleset-ci-required.tf" "$PRISTINE/infra/github/" || exit 2
  cp "$ENGINE" "$PRISTINE/$ENGINE_REL" || exit 2
}

reset_sbx() {
  rm -rf "$SBX" || exit 2
  cp -a "$PRISTINE" "$SBX" || exit 2
}

# run_engine <root> [VAR=value ...] -> sets OUT and RC. Always under env -i so the result
# does not depend on the caller's environment.
OUT=""; RC=0
run_engine() {
  local root="$1"; shift
  assert_fixture_dir "$root"
  OUT="$(cd "$root" && env -i PATH="$SANDBOX_PATH" "$@" bash "$root/$ENGINE_REL" 2>&1)"
  RC=$?
}

# engine_green <min-contexts>: the engine must exit 0, print the OK line in its exact shape,
# and have examined at least <min-contexts>. The floor is re-asserted HERE rather than
# trusted to the engine, so an engine that lost its own floor is still called RED (H3).
engine_green() {
  local min="$1" line n
  [[ "$RC" -eq 0 ]] || return 1
  line="$(grep -E -- '^merge-group-coverage=OK contexts=[0-9]+ producers=[0-9]+$' <<<"$OUT" | head -n 1)"
  [[ -n "$line" ]] || return 1
  n="${line#*contexts=}"; n="${n%% *}"
  [[ "$n" -ge "$min" ]]
}

# landed: the mutation must have changed the copy.
landed() {
  if diff -rq "$PRISTINE" "$SBX" >/dev/null 2>&1; then return 1; fi
  return 0
}

# row_red <label> <anchor-substring>: the engine must be non-green and its output must
# carry the anchor (the engine's own error-line shape for the mutated context).
row_red() {
  local label="$1" anchor="$2"
  if ! landed; then fail "$label: mutation did not land (copy identical to pristine)"; return; fi
  if engine_green 1; then
    fail "$label: engine stayed GREEN under the mutation"
  elif [[ "$OUT" != *"$anchor"* ]]; then
    fail "$label: RED but the output lacks the anchor: $anchor"
    printf '%s\n' "$OUT" | head -n 12 >&2
  else
    pass "$label"
  fi
}

# engine_skipped: the queue-off verdict. rc 0, the exact SKIPPED line, and NO OK line: a SKIPPED
# that printed OK would let a rule-less repo pass as "all producers covered".
engine_skipped() {
  [[ "$RC" -eq 0 ]] || return 1
  grep -E -- '^merge-group-coverage=SKIPPED \(no merge_queue rule: producers not required\)$' <<<"$OUT" >/dev/null || return 1
  ! grep -E -- '^merge-group-coverage=OK' <<<"$OUT" >/dev/null
}

# row_skipped <label>: the mutation landed and the engine reports SKIPPED (never green, never red).
row_skipped() {
  local label="$1"
  if ! landed; then fail "$label: mutation did not land (copy identical to pristine)"; return; fi
  if engine_green 1; then
    fail "$label: SKIPPED was read as a GREEN OK line"
  elif engine_skipped; then
    pass "$label"
  else
    fail "$label: expected the SKIPPED line, rc=$RC"
    printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

# row_green <label> <contexts-line-substring>: the mutation landed and the engine STAYS green with
# the same counts (a spelling the engine must accept).
row_green() {
  local label="$1" want="$2"
  if ! landed; then fail "$label: mutation did not land (copy identical to pristine)"; return; fi
  if engine_green 25 && [[ "$OUT" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label: expected GREEN with $want (rc=$RC)"
    printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

mutate() { reset_sbx; "$@"; run_engine "$SBX"; }

echo "== Guard 1: merge_group coverage =="

# ---- case 0: the real repo -------------------------------------------------------------
echo "-- case 0: real repo"
if [[ ! -f "$ENGINE" ]]; then
  fail "case 0: engine $ENGINE_REL is missing"
else
  run_engine "$REPO_ROOT"
  if engine_green 25; then
    pass "case 0: real repo is GREEN with >= 25 contexts ($(grep -E -- '^merge-group-coverage=OK' <<<"$OUT" | head -n 1))"
  else
    fail "case 0: real repo is not green (rc=$RC)"
    printf '%s\n' "$OUT" | head -n 15 >&2
  fi

  start=$SECONDS
  run_engine "$REPO_ROOT"
  elapsed=$((SECONDS - start))
  if [[ "$elapsed" -lt 15 ]] && engine_green 25; then
    pass "case 0b: runs under env -i PATH=$SANDBOX_PATH in ${elapsed}s (< 15s)"
  else
    fail "case 0b: env -i run was not green within 15s (rc=$RC, ${elapsed}s)"
  fi
fi

build_pristine

# Control: the pristine COPY must behave exactly like the live tree, or every row below is
# measured against a different baseline than the one case 0 reports.
run_engine "$PRISTINE"
if [[ -f "$ENGINE" ]]; then
  ctrl_rc="$RC"
  run_engine "$REPO_ROOT"
  if [[ "$ctrl_rc" -eq "$RC" ]]; then
    pass "control: pristine copy and live tree agree (rc=$RC)"
  else
    fail "control: pristine copy rc=$ctrl_rc differs from the live tree rc=$RC"
  fi
fi

# ---- rows 1-8 ---------------------------------------------------------------------------
echo "-- mutation rows"

m1() { sed -i '/^  merge_group:$/d' "$SBX/.github/workflows/ci.yml"; }
mutate m1
row_red "row 1: ci.yml loses merge_group (names lockfile-sync)" "merge-group-coverage: lockfile-sync:"

m2() { sed -i "/^  adr-ordinals:\$/a\\    if: github.event_name == 'pull_request'" "$SBX/.github/workflows/ci.yml"; }
mutate m2
row_red "row 2: required job gains a pull_request-only if (adr-ordinals)" "merge-group-coverage: adr-ordinals:"

m3() {
  printf '[]\n' > "$SBX/scripts/ci-required-ruleset-canonical-required-status-checks.json"
  printf '[]\n' > "$SBX/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
}
mutate m3
row_red "row 3: both canonical JSONs empty (0 contexts examined)" "0 contexts examined"

m4() {
  local f="$SBX/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json" t
  t="$(mktemp -p "$WORK")" || exit 2
  jq '. + [{"context":"cla-new","integration_id":15368}]' "$f" > "$t" || exit 2
  mv "$t" "$f" || exit 2
}
mutate m4
row_red "row 4: CLA ruleset gains cla-new with no producer" "merge-group-coverage: cla-new:"

m5() { sed -i 's/for check in cla-check cla-evidence; do/for check in cla-check; do/' "$SBX/.github/workflows/merge-queue-cla-synthetics.yml"; }
if [[ -f "$PRISTINE/.github/workflows/merge-queue-cla-synthetics.yml" ]]; then
  mutate m5
  row_red "row 5: synthetic loses the cla-evidence iteration" "merge-group-coverage: cla-evidence:"
else
  fail "row 5: merge-queue-cla-synthetics.yml is missing from the workflows (nothing to mutate)"
fi

m6() { sed -i 's/^  lockfile-sync:$/  lockfile-sync2:/' "$SBX/.github/workflows/ci.yml"; }
mutate m6
row_red "row 6: required job renamed (lockfile-sync -> lockfile-sync2) has no producer" "merge-group-coverage: lockfile-sync: no merge_group producer"

m7() {
  cat > "$SBX/.github/workflows/zz-duplicate-name.yml" <<'EOF'
name: duplicate producer fixture
on:
  merge_group:
jobs:
  other:
    name: lockfile-sync
    runs-on: ubuntu-latest
    steps:
      - run: echo duplicate
EOF
}
mutate m7
row_red "row 7: a second job named lockfile-sync is an ambiguous producer" "merge-group-coverage: lockfile-sync: ambiguous"

# Row 8: the synthetic workflow posts a name the CLA ruleset does not require. The synthetic
# names are DERIVED from the CLA canonical, so the workflow's posted set must equal it: an extra
# posted name is drift (the reverse, a missing name, is row 5).
m8() { sed -i 's/for check in cla-check cla-evidence; do/for check in cla-check cla-evidence cla-extra; do/' "$SBX/.github/workflows/merge-queue-cla-synthetics.yml"; }
mutate m8
row_red "row 8: synthetic posts cla-extra, which the CLA ruleset does not require" "merge-group-coverage: cla-extra:"

# Row 9: an `if:` that names merge_group only inside a NEGATION excludes the event; a substring
# check would accept it. (Control: the positive spelling on the same job is accepted, see H2.)
m9() { sed -i "/^  adr-ordinals:\$/a\\    if: github.event_name != 'merge_group'" "$SBX/.github/workflows/ci.yml"; }
mutate m9
row_red "row 9: required job gains a merge_group-NEGATING if (adr-ordinals)" "merge-group-coverage: adr-ordinals:"

# ---- rows 10+: if: shapes, synthetic step wiring, queue-off ------------------------------------
echo "-- rows 10+"

ifjob() { sed -i "/^  adr-ordinals:\$/a\\    if: $1" "$SBX/.github/workflows/ci.yml"; }
m10() { ifjob "\${{ !(github.event_name == 'merge_group') }}"; }
mutate m10
row_red "row 10: job if is !(github.event_name == 'merge_group') (adr-ordinals)" "merge-group-coverage: adr-ordinals:"
m11() { ifjob "github.event_name == 'merge_group' \&\& false"; }
mutate m11
row_red "row 11: job if is merge_group && false (adr-ordinals)" "merge-group-coverage: adr-ordinals:"
m12() { ifjob "github.event_name == 'merge_group' \&\& 0"; }
mutate m12
row_red "row 12: job if is merge_group && 0 (adr-ordinals)" "merge-group-coverage: adr-ordinals:"
m13() { ifjob "\${{ !contains(fromJSON('[\"merge_group\"]'), github.event_name) }}"; }
mutate m13
row_red "row 13: job if is !contains(..merge_group..) (adr-ordinals)" "merge-group-coverage: adr-ordinals:"
m14() { ifjob "false"; }
mutate m14
row_red "row 14: job if is the YAML boolean false (adr-ordinals)" "merge-group-coverage: adr-ordinals:"
m15() { ifjob "true"; }
mutate m15
row_green "row 15: job if is the YAML boolean true stays GREEN" "contexts=25 producers=24"
m16() { ifjob "github.event_name == 'merge_group' || github.event_name == 'pull_request'"; }
mutate m16
row_green "row 16: a positive merge_group || pull_request if stays GREEN" "contexts=25 producers=24"

SYN_WF=".github/workflows/merge-queue-cla-synthetics.yml"
POST_STEP='/^      - name: Re-post cla-check/'
m17() { sed -i "${POST_STEP}a\\        if: github.event_name == 'merge_group'" "$SBX/$SYN_WF"; }
mutate m17
row_red "row 17: the synthetic posting step gains a step-level if" "merge-group-coverage: cla-check:"
m18() { sed -i "${POST_STEP}a\\        continue-on-error: true" "$SBX/$SYN_WF"; }
mutate m18
row_red "row 18: the synthetic posting step gains continue-on-error" "merge-group-coverage: cla-check:"
m19() { sed -i '/^    runs-on: ubuntu-latest$/a\    needs: other' "$SBX/$SYN_WF"; }
mutate m19
row_red "row 19: the synthetic job gains needs:" "merge-group-coverage: cla-check:"
m20() { sed -i '/^    runs-on: ubuntu-latest$/a\    continue-on-error: true' "$SBX/$SYN_WF"; }
mutate m20
row_red "row 20: the synthetic job gains continue-on-error" "merge-group-coverage: cla-check:"
m21() { sed -i "/^    runs-on: ubuntu-latest\$/a\\    if: github.event_name != 'merge_group'" "$SBX/$SYN_WF"; }
mutate m21
row_red "row 21: the synthetic job gains an if that excludes merge_group" "merge-group-coverage: cla-check:"
m22() { sed -i '0,/conclusion=success/s//conclusion=neutral/' "$SBX/$SYN_WF"; }
mutate m22
row_red "row 22: the synthetic posts conclusion=neutral, not success" "merge-group-coverage: cla-check:"
# the failure-report step keeps its own `if: failure()` and must NOT be rejected (case 0 proves it
# on the live tree; this row proves the step-level-if rule is scoped to the success poster).
m23() { sed -i 's/^        if: failure()$/        if: always()/' "$SBX/$SYN_WF"; }
mutate m23
row_green "row 23: an if on the failure-report step (not the success poster) stays GREEN" "contexts=25 producers=24"

# Queue-off (rows 24-28): no merge_queue block means no queue and no merge_group producer is
# required. A rollback PR re-adding CodeQL to the canonical must not go red; the queue-on
# equivalent must (row 24, the pre-existing behaviour).
TF="infra/github/ruleset-ci-required.tf"
add_codeql() {
  local f="$SBX/scripts/ci-required-ruleset-canonical-required-status-checks.json" t
  t="$(mktemp -p "$WORK")" || exit 2
  jq '. + [{"context":"CodeQL","integration_id":57789}]' "$f" > "$t" || exit 2
  mv "$t" "$f" || exit 2
}
drop_queue() { sed -i '/^    merge_queue {$/,/^    }$/d' "$SBX/$TF"; }
m24() { add_codeql; }
mutate m24
row_red "row 24: queue block present + a CodeQL canonical row with no producer" "merge-group-coverage: CodeQL:"
m25() { add_codeql; drop_queue; }
mutate m25
row_skipped "row 25: queue block removed + the CodeQL canonical row is SKIPPED, rc 0"
m26() { drop_queue; }
mutate m26
row_skipped "row 26: queue block removed alone is SKIPPED, rc 0"
m27() { sed -i 's/^    merge_queue {$/    # merge_queue {/' "$SBX/$TF"; add_codeql; }
mutate m27
row_skipped "row 27: a COMMENTED-OUT merge_queue block counts as absent (SKIPPED)"
m28() { sed -i 's/^    merge_queue {$/    \/* merge_queue {/; s/^    }$/    } *\//' "$SBX/$TF"; }
mutate m28
if landed && grep -Fq '/* merge_queue {' "$SBX/$TF" && [[ "$(grep -c '^    } \*/$' "$SBX/$TF")" -ge 1 ]]; then
  row_skipped "row 28: a block-commented merge_queue block counts as absent (SKIPPED)"
else
  fail "row 28: the block-comment mutation did not wrap the merge_queue block"
fi
# the tf file missing is a setup error (exit 2), never a skip or an OK
m29() { rm -f "$SBX/$TF"; }
mutate m29
if landed && [[ "$RC" -eq 2 && "$OUT" == *"ruleset terraform file not found"* ]] && ! engine_skipped && ! engine_green 1; then
  pass "row 29: a missing ruleset terraform file is exit 2, not SKIPPED or OK"
else
  fail "row 29: a missing terraform file was not an exit-2 setup error (rc=$RC)"
fi

# ---- harness rows -----------------------------------------------------------------------
echo "-- harness rows"

# H1: the loader mutant reads d["on"] only. Under PyYAML (YAML 1.1) the bare key `on` is
# the boolean True, so every workflow loses its trigger map. The suite must see that on the
# real tree AND on the synthesized fixtures.
h1() { sed -i 's/for k in ("on", True):/for k in ("on",):/' "$SBX/$ENGINE_REL"; }
mutate h1
row_red "H1a: loader reads d[\"on\"] only -> real tree goes RED" "merge-group-coverage:"

reset_sbx; h1
if ! landed; then
  fail "H1b: loader mutation did not land"
else
  run_engine "$SBX" MGC_WORKFLOWS_DIR="$FIXTURES/pass/workflows" MGC_CI_JSON="$FIXTURES/pass/ci-canonical.json" \
    MGC_CLA_JSON="$FIXTURES/pass/cla-canonical.json" MGC_MIN_CONTEXTS=5
  if engine_green 5; then
    fail "H1b: loader mutant still classified the fixtures GREEN"
  else
    pass "H1b: loader mutant is caught on the fixtures (rc=$RC)"
  fi
fi

# H2: must-PASS non-canonical fixtures (unmodified engine).
run_engine "$PRISTINE" MGC_WORKFLOWS_DIR="$FIXTURES/pass/workflows" MGC_CI_JSON="$FIXTURES/pass/ci-canonical.json" \
  MGC_CLA_JSON="$FIXTURES/pass/cla-canonical.json" MGC_MIN_CONTEXTS=5
if engine_green 5; then
  if [[ "$OUT" == *"contexts=6 producers=5"* ]]; then
    pass "H2: map/list/string on-forms, always(), merge_group-naming if, name-resolved job all PASS (contexts=6 producers=5)"
  else
    fail "H2: GREEN but the counts differ from contexts=6 producers=5"
    printf '%s\n' "$OUT" | head -n 6 >&2
  fi
else
  fail "H2: the must-PASS fixtures were not green (rc=$RC)"
  printf '%s\n' "$OUT" | head -n 12 >&2
fi

# H2b: the same fixtures with one non-merge_group-safe edit must go RED, so H2 is not a
# fixture the engine would accept whatever it contained.
reset_sbx
H2B="$WORK/h2b"; assert_fixture_dir "$H2B"
mkdir -p "$H2B" && cp -R "$FIXTURES/pass" "$H2B" || exit 2
sed -i "s/^    if: always()\$/    if: github.event_name == 'pull_request'/" "$H2B/pass/workflows/map-form.yml"
if diff -rq "$FIXTURES/pass" "$H2B/pass" >/dev/null 2>&1; then
  fail "H2b: fixture edit did not land"
else
  run_engine "$PRISTINE" MGC_WORKFLOWS_DIR="$H2B/pass/workflows" MGC_CI_JSON="$H2B/pass/ci-canonical.json" \
    MGC_CLA_JSON="$H2B/pass/cla-canonical.json" MGC_MIN_CONTEXTS=5
  if engine_green 5 || [[ "$OUT" != *"merge-group-coverage: fx-map:"* ]]; then
    fail "H2b: an excluding if on a fixture job was not reported"
  else
    pass "H2b: the same fixtures with an excluding if go RED naming fx-map"
  fi
fi

# H3: engine output shape and the floor. (a) the OK line has the documented shape (checked
# by engine_green on the fixtures above). (b) A mutant with the floor deleted, fed empty
# canonicals, prints OK contexts=0; the suite's own verdict must still call it RED.
h3() {
  printf '[]\n' > "$SBX/scripts/ci-required-ruleset-canonical-required-status-checks.json"
  printf '[]\n' > "$SBX/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"
  sed -i 's/^MIN_CONTEXTS_DEFAULT = [0-9]*$/MIN_CONTEXTS_DEFAULT = 0/' "$SBX/$ENGINE_REL"
  # no CLA names are required, so the synthetic workflow's posted names would read as drift
  rm -f "$SBX/.github/workflows/merge-queue-cla-synthetics.yml"
}
mutate h3
if ! landed; then
  fail "H3: floor mutation did not land"
elif [[ "$OUT" != *"merge-group-coverage=OK contexts=0 "* ]]; then
  fail "H3: the floorless mutant did not print OK contexts=0, so this row measures nothing"
  printf '%s\n' "$OUT" | head -n 6 >&2
elif engine_green 20; then
  fail "H3: an OK line with contexts=0 was accepted as GREEN"
else
  pass "H3: a floorless engine printing OK contexts=0 is still RED in the suite"
fi

# ---- controls: each verdict helper must fail on an input that must fail ----------------------
echo "-- controls"
control_fails() {
  local label="$1" want_msg="$2"; shift 2
  local p0="$passes" f0="$fails" n0="${#FAILED[@]}" moved=0 msg_ok=1
  "$@" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  if [[ -n "$want_msg" ]]; then
    [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] || msg_ok=0
  fi
  passes="$p0"; fails="$f0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: $label fails on an input that must fail"
  else
    fail "control: $label did not record a failure on an input that must fail"
  fi
}
# engine_green / engine_skipped are predicates: they must say "no" to the wrong verdict.
RC=0; OUT="merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)"
if engine_green 1; then fail "C1a: engine_green accepted a SKIPPED line"; else pass "C1a: engine_green rejects SKIPPED"; fi
RC=0; OUT="merge-group-coverage=OK contexts=25 producers=24"
if engine_skipped; then fail "C1b: engine_skipped accepted an OK line"; else pass "C1b: engine_skipped rejects OK"; fi
RC=1; OUT="merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)"
if engine_skipped; then fail "C1c: engine_skipped accepted rc 1"; else pass "C1c: engine_skipped rejects a non-zero exit"; fi
RC=0; OUT="merge-group-coverage=OK contexts=3 producers=3"
if engine_green 25; then fail "C1d: engine_green ignored its own floor"; else pass "C1d: engine_green enforces its floor"; fi
# row_red: no mutation landed / engine stayed green / anchor missing
reset_sbx
RC=1; OUT="::error::merge-group-coverage: other: reason"
control_fails "row_red (mutation did not land)" "did not land" row_red "C2a" "merge-group-coverage: x:"
reset_sbx; ctl_mut() { printf '# harmless\n' >> "$SBX/.github/workflows/ci.yml"; }; ctl_mut
run_engine "$SBX"
control_fails "row_red (engine stayed GREEN)" "stayed GREEN" row_red "C2b" "merge-group-coverage: x:"
mutate m1
control_fails "row_red (anchor absent from a RED engine)" "lacks the anchor" row_red "C2c" "merge-group-coverage: no-such-context:"
# row_skipped / row_green
reset_sbx
control_fails "row_skipped (mutation did not land)" "did not land" row_skipped "C3a"
mutate m1
control_fails "row_skipped (engine is RED, not SKIPPED)" "expected the SKIPPED line" row_skipped "C3b"
control_fails "row_green (engine is RED)" "expected GREEN" row_green "C3c" "contexts=25"

echo
echo "=== merge-group coverage: $passes passed, $fails failed ==="
# Exact assertion floor (printf + exit): a deleted row or a neutered helper changes the count.
EXPECTED_PASSES=47
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf 'FAIL: %s assertions passed, the floor is exactly %s\n' "$passes" "$EXPECTED_PASSES" >&2
  exit 1
fi
if [[ "$fails" -ne 0 ]]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
