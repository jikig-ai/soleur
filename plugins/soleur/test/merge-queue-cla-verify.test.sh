#!/usr/bin/env bash
# Suite for scripts/merge-queue-cla-verify.sh (#9454): the verification half of
# .github/workflows/merge-queue-cla-synthetics.yml. The workflow may post a synthetic
# cla-check/cla-evidence on a merge_group candidate ONLY if this script has proven the PR
# head's REAL cla-check/cla-evidence are green. The script must fail closed on every other
# outcome.
#
# HOW THE SEAM IS BUILT: `gh` is a PATH stub that serves synthesized JSON for the three
# endpoints the script is allowed to read (pulls/N, commits/SHA, commits/PR_HEAD/check-runs),
# records every call, refuses any request it was not told to expect (exit 64), and can be
# told to fail one endpoint. The check-runs reply replays the real `gh api --paginate` shape:
# one top-level JSON object per page, concatenated, with no outer array.
#
# Cases are plain functions, so the same battery runs against the real script (all must
# pass) and against mutants of it (each mutant must turn the specific row that guards the
# mutated line RED, proven by diffing the mutant against the pristine copy first).
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT_REAL="$REPO_ROOT/scripts/merge-queue-cla-verify.sh"
SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin"

passes=0; fails=0; FAILED=()
QUIET=0; MUT_FAILED=()
pass() { if [[ "$QUIET" -eq 1 ]]; then return 0; fi; passes=$((passes + 1)); echo "  PASS: $1"; }
fail() {
  if [[ "$QUIET" -eq 1 ]]; then MUT_FAILED+=("$1"); return 0; fi
  fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2
}

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

command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq not found" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"; assert_fixture_dir "$BIN"
mkdir -p "$BIN" || exit 2

# ---- the gh stub ---------------------------------------------------------------------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Synthesized gh. Reads GH_FIX_DIR (pr.json, commit.json, checkruns.pages) and appends every
# call to GH_CALLS. GH_FIX_FAIL=<pr|commit|checks> makes that endpoint exit 1.
set -u
printf '%s\n' "$*" >> "${GH_CALLS:?GH_CALLS unset}"
[[ "${1-}" == "api" ]] || { echo "stub gh: only 'gh api' is expected, got: $*" >&2; exit 64; }
shift
path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate|--silent) shift ;;
    -H|--header|--jq|-q) shift 2 ;;
    -*) echo "stub gh: unexpected flag $1 (a read-only verifier sends no write flags)" >&2; exit 64 ;;
    *) path="$1"; shift ;;
  esac
done
fix="${GH_FIX_DIR:?GH_FIX_DIR unset}"
case "$path" in
  repos/*/pulls/[0-9]*)
    [[ "${GH_FIX_FAIL-}" == "pr" ]] && { echo "gh: HTTP 500 (pulls)" >&2; exit 1; }
    cat "$fix/pr.json" ;;
  repos/*/commits/*/check-runs\?*)
    [[ "${GH_FIX_FAIL-}" == "checks" ]] && { echo "gh: HTTP 500 (check-runs)" >&2; exit 1; }
    cat "$fix/checkruns.pages" ;;
  repos/*/commits/*)
    [[ "${GH_FIX_FAIL-}" == "commit" ]] && { echo "gh: HTTP 500 (commits)" >&2; exit 1; }
    cat "$fix/commit.json" ;;
  *) echo "stub gh: unexpected path $path" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh" || exit 2

# ---- fixture builders (synthesized only) ---------------------------------------------------
S40_A="1111111111111111111111111111111111111111"   # PR head
S40_B="2222222222222222222222222222222222222222"   # previous queue candidate (first parent)
S40_C="3333333333333333333333333333333333333333"   # merge_group head (the candidate)
S40_D="4444444444444444444444444444444444444444"   # some other commit
PR=4242

# cr <name> <app_id> <status> <conclusion|null> <started_at> <id>
cr() {
  jq -n --arg n "$1" --argjson a "$2" --arg s "$3" --argjson c "$4" --arg t "$5" --argjson i "$6" \
    '{id:$i,name:$n,status:$s,conclusion:$c,started_at:$t,app:{id:$a,slug:"github-actions"}}'
}

# mkfix <dir> : default = both contexts green on the PR head, PR head is the 2nd parent.
mkfix() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d" || exit 2
  jq -n --arg h "$S40_A" '{number:4242,state:"open",base:{ref:"main"},head:{sha:$h}}' > "$d/pr.json"
  jq -n --arg b "$S40_B" --arg a "$S40_A" '{sha:"3333333333333333333333333333333333333333",parents:[{sha:$b},{sha:$a}]}' > "$d/commit.json"
  # one page, as gh prints it
  jq -n --argjson x "$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)" \
        --argjson y "$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)" \
        --argjson z "$(cr test 15368 completed '"success"' 2026-10-03T10:00:02Z 103)" \
        '{total_count:3,check_runs:[$x,$y,$z]}' > "$d/checkruns.pages"
}

# pages <dir> <json-array-of-check_runs>...  : replace the check-runs reply by N concatenated pages.
pages() {
  local d="$1"; shift
  : > "$d/checkruns.pages"
  local arr
  for arr in "$@"; do
    jq -n --argjson c "$arr" '{total_count:($c|length),check_runs:$c}' >> "$d/checkruns.pages"
  done
}

GOOD_REF="refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"
OUT=""; RC=0; CALLS=""

# run_sut <fixture-dir> [VAR=value ...]: defaults are a valid event; overrides win.
run_sut() {
  local d="$1"; shift
  CALLS="$d/calls.log"; : > "$CALLS"
  OUT="$(env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_TOKEN=synthetic-token \
    REPO=example-org/example-repo HEAD_REF="$GOOD_REF" HEAD_SHA="$S40_C" BASE_REF=refs/heads/main \
    GH_FIX_DIR="$d" GH_CALLS="$CALLS" "$@" bash "$SUT" 2>&1)"
  RC=$?
}

ncalls() { if [[ -s "$CALLS" ]]; then wc -l < "$CALLS" | tr -d ' '; else echo 0; fi; }

# expect_green <label> : rc 0, OK line, and the stub really was consulted (a verifier that
# answers without reading anything is a vacuous pass).
expect_green() {
  local label="$1"
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK pr=${PR} "* && "$(ncalls)" -ge 3 ]]; then
    pass "$label"
  else
    fail "$label (rc=$RC calls=$(ncalls))"
    [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

# expect_red <label> <anchor> : non-zero, never the OK line, and the output names the failure.
expect_red() {
  local label="$1" anchor="$2"
  if [[ "$RC" -ne 0 && "$OUT" != *"merge-queue-cla-verify=OK"* && "$OUT" == *"$anchor"* ]]; then
    pass "$label"
  else
    fail "$label (rc=$RC, wanted anchor: $anchor)"
    [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

# no_api_calls <label>: validation rejects must happen BEFORE any API call.
expect_no_calls() {
  if [[ "$(ncalls)" -eq 0 ]]; then pass "$1"; else fail "$1 (made $(ncalls) gh call(s))"; fi
}

CASE_N=0
newfix() { CASE_N=$((CASE_N + 1)); FX="$WORK/fx.$CASE_N"; mkfix "$FX"; }

run_cases() {
  # ---- must PASS --------------------------------------------------------------------------
  newfix; run_sut "$FX"
  expect_green "P1 both real contexts green on the PR head"

  # Read-only: the verifier must not post anything (the workflow's later step does).
  if grep -Eq -- ' (-f|-F|-X|--method|--field|--raw-field|--input)( |$)' "$CALLS"; then
    fail "P1b verifier sent a write-shaped gh call"
  else
    pass "P1b every gh call is a read (no -f/-F/-X/--method)"
  fi

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"failure"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"failure"' 2026-10-03T09:00:01Z 91),$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_green "P2 old red then newer green passes (latest run per name)"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"failure"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]" \
              "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_green "P3 newer green on page 2 beats older red on page 1"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  # bot PR: the composite action's synthetic runs (app 15368) are the PR head's only CLA runs
  run_sut "$FX"
  expect_green "P4 bot-PR synthetic cla-check/cla-evidence (app 15368) on the head passes"

  # ---- must FAIL --------------------------------------------------------------------------
  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T09:00:01Z 91),$(cr cla-check 15368 completed '"failure"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F1 old green then newer red fails" "cla-check"

  newfix
  pages "$FX" "[$(cr cla-evidence 15368 completed '"success"' 2026-10-03T09:00:00Z 90),$(cr cla-check 15368 completed '"success"' 2026-10-03T09:00:01Z 91)]" \
              "[$(cr cla-evidence 15368 completed '"failure"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F1b newer red on page 2 beats older green on page 1" "cla-evidence"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F2 cla-evidence missing fails" "cla-evidence"

  newfix
  pages "$FX" "[$(cr test 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F2b both contexts missing fails" "cla-check"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 in_progress null 2026-10-03T10:00:05Z 102)]"
  run_sut "$FX"
  expect_red "F7 newest cla-evidence run still in progress fails" "cla-evidence"

  newfix
  pages "$FX" "[$(cr cla-check 99999 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F6 a success from a different app id (spoof) does not count" "cla-check"

  newfix
  jq -n --arg b "$S40_B" --arg d "$S40_D" '{sha:"3333333333333333333333333333333333333333",parents:[{sha:$b},{sha:$d}]}' > "$FX/commit.json"
  run_sut "$FX"
  expect_red "F4 PR head is not a parent of the candidate fails" "not a parent"

  newfix
  jq -n --arg h "$S40_A" '{number:4242,state:"open",base:{ref:"release"},head:{sha:$h}}' > "$FX/pr.json"
  run_sut "$FX"
  expect_red "F8 PR base is not main fails" "base"

  newfix
  printf '{"number":4242,"base":{"ref":"main"},"head":{"sha":"not-a-sha"}}\n' > "$FX/pr.json"
  run_sut "$FX"
  expect_red "F9 wrong-shape PR head sha fails" "head"

  local ep
  for ep in pr commit checks; do
    newfix; run_sut "$FX" GH_FIX_FAIL="$ep"
    expect_red "F5-$ep gh error on the $ep endpoint fails" "::error::"
  done

  # head_ref shapes: each must be rejected BEFORE any API call.
  local bad idx=0
  local -a bads=(
    ""
    "refs/heads/main"
    "refs/heads/gh-readonly-queue/main/pr-abc-${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-abc123"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}x"
    "refs/heads/gh-readonly-queue/dev/pr-${PR}-${S40_C}"
    "gh-readonly-queue/main/pr-${PR}-${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr--${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"$'\n'"::error::forged"
  )
  for bad in "${bads[@]}"; do
    idx=$((idx + 1))
    newfix; run_sut "$FX" HEAD_REF="$bad"
    expect_red "F3.$idx unparseable or wrong-shape head_ref is rejected" "head_ref"
    expect_no_calls "F3.$idx ... before any API call"
  done

  newfix; run_sut "$FX" BASE_REF=refs/heads/other
  expect_red "F3b merge_group base_ref other than refs/heads/main is rejected" "base_ref"
  expect_no_calls "F3b ... before any API call"

  newfix; run_sut "$FX" HEAD_SHA="not-40-hex"
  expect_red "F3c head_sha that is not 40 hex is rejected" "head_sha"
  expect_no_calls "F3c ... before any API call"

  newfix; run_sut "$FX" REPO=""
  expect_red "F10 an empty REPO is rejected" "REPO"
  expect_no_calls "F10 ... before any API call"
}

echo "== merge-queue-cla-verify =="
if [[ ! -f "$SUT_REAL" ]]; then
  fail "scripts/merge-queue-cla-verify.sh is missing"
  echo; echo "=== merge-queue-cla-verify: $passes passed, $fails failed ==="; exit 1
fi

SUT="$SUT_REAL"
run_cases

# ---- mutation battery over the script itself ----------------------------------------------
echo "-- mutants of the script (each must turn its guarding row RED)"
MUTDIR="$WORK/mut"; assert_fixture_dir "$MUTDIR"; mkdir -p "$MUTDIR" || exit 2

# mutant <id> <row-label-that-must-fail> <sed-expression>
mutant() {
  local id="$1" row="$2" expr="$3" m="$MUTDIR/$1.sh" hit=0 f
  cp "$SUT_REAL" "$m" || exit 2
  sed -i "$expr" "$m"
  if cmp -s "$SUT_REAL" "$m"; then fail "mutant $id: mutation did not land"; return; fi
  SUT="$m"; QUIET=1; MUT_FAILED=()
  run_cases
  QUIET=0; SUT="$SUT_REAL"
  for f in "${MUT_FAILED[@]}"; do
    case "$f" in "$row"*) hit=1 ;; esac
  done
  if [[ "$hit" -eq 1 ]]; then
    pass "mutant $id turns row $row RED"
  else
    fail "mutant $id did not turn row $row RED (rows that went red: ${MUT_FAILED[*]:-none})"
  fi
}

# shellcheck disable=SC2016  # sed expressions: $a and ${BASE_REF} are literal text to match
mutant parent  "F4"   's/\[\.parents\[\]\.sha\] | index(\$a) != null/true/'
mutant app     "F6"   's/ and \.app\.id == 15368//'
mutant latest  "F1 "  's/^  | last$/  | first/'
# shellcheck disable=SC2016  # sed expression: ${BASE_REF} is literal text
mutant base    "F3b"  's/"\${BASE_REF:-}" == "refs\/heads\/main"/-n "${BASE_REF:-}"/'

echo
echo "=== merge-queue-cla-verify: $passes passed, $fails failed ==="
if [[ "$fails" -ne 0 ]]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
