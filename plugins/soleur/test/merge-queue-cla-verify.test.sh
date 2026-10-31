#!/usr/bin/env bash
# Suite for scripts/merge-queue-cla-verify.sh (#9454, enumeration rework #11678): the
# verification half of .github/workflows/merge-queue-cla-synthetics.yml. The workflow may post
# synthetic cla-check/cla-evidence on a merge_group candidate ONLY if the verifier proves every
# constituent queue member's REAL cla-check/cla-evidence (app 15368) is green on its queued head.
# Everything else fails closed.
#
# SEAM: `gh` is a PATH stub that serves synthesized data for the two read shapes the script
# makes — `gh api graphql` (mergeQueue entries, from $GH_FIX_DIR/entries.json) and
# `gh api repos/*/commits/<ref>/check-runs?...` (per-ref pages cr.<ref>.<n>; any ref with no
# fixture pages gets main.json). It records every argv line to GH_CALLS, refuses unknown calls
# (exit 64), models --paginate (all cr.<ref>.* pages concatenated, else page 1 only), requires
# filter=all + per_page on check-runs, and honours GH_FIX_FAIL=<mq|checks> / GH_FIX_FLAKY the
# same way the old suite did.
#
# Fixtures: mkfix = a singleton entry (one node, headCommit == HEAD_SHA). mkgrp = a 2-member
# group (shallow member PR 4241 head S40_E + own candidate S40_B; deepest member PR 4242 head
# S40_A, candidate S40_C == HEAD_SHA, and head_ref names 4242).
# shellcheck disable=SC2016,SC2329  # jq/sed programs are literal text
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
  printf '[FATAL] instrument self-test\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: .. in %s\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: synthetic fs %s\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fs root\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: relative %s\n' "$1" >&2; exit 2 ;;
  esac
}
command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq not found" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN" || exit 2

cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "${GH_CALLS:?GH_CALLS unset}"
[[ "${1-}" == "api" ]] || { echo "stub gh: only 'gh api' is expected, got: $*" >&2; exit 64; }
shift
path=""; paginate=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate) paginate=1; shift ;;
    --silent) shift ;;
    -H|--header|--jq|-q) shift 2 ;;
    -f|--field|-F|--raw-field) shift 2 ;;          # graphql -f query= -F var= are read inputs
    -X|--method|--input) echo "stub gh: write-shaped flag $1" >&2; exit 64 ;;
    -*) echo "stub gh: unexpected flag $1" >&2; exit 64 ;;
    *) path="$1"; shift ;;
  esac
done
fix="${GH_FIX_DIR:?GH_FIX_DIR unset}"
flaky() {
  local ep="$1" n="${GH_FIX_FLAKY_N:-1}" c=0
  [[ "${GH_FIX_FLAKY-}" == "$ep" ]] || return 1
  [[ -f "$fix/flaky.$ep" ]] && c="$(cat "$fix/flaky.$ep")"
  c=$((c + 1)); printf '%s' "$c" > "$fix/flaky.$ep"
  [[ "$c" -le "$n" ]]
}
case "$path" in
  graphql)
    flaky mq && { echo "gh: HTTP 502 (graphql, transient)" >&2; exit 1; }
    [[ "${GH_FIX_FAIL-}" == "mq" ]] && { echo "gh: HTTP 500 (graphql)" >&2; exit 1; }
    cat "$fix/entries.json" ;;
  repos/*/commits/*/check-runs\?*)
    flaky checks && { echo "gh: HTTP 503 (check-runs, transient)" >&2; exit 1; }
    [[ "${GH_FIX_FAIL-}" == "checks" ]] && { echo "gh: HTTP 500 (check-runs)" >&2; exit 1; }
    [[ "$path" == *"filter=all"* ]] || { echo "stub gh: check-runs query lacks filter=all" >&2; exit 64; }
    [[ "$path" =~ per_page=[0-9]+ ]] || { echo "stub gh: check-runs query lacks per_page" >&2; exit 64; }
    ref="${path#repos/*/commits/}"; ref="${ref%%/check-runs*}"
    if [[ -f "$fix/cr.$ref.1" ]]; then
      if [[ "$paginate" -eq 1 ]]; then for page in "$fix"/cr."$ref".*; do cat "$page"; done; else cat "$fix/cr.$ref.1"; fi
    else cat "$fix/main.json"; fi ;;
  *) echo "stub gh: unexpected path $path" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh" || exit 2

S40_A="1111111111111111111111111111111111111111"   # named PR 4242 head (deepest member)
S40_B="2222222222222222222222222222222222222222"   # shallow member's own candidate
S40_C="3333333333333333333333333333333333333333"   # HEAD_SHA — deepest candidate
S40_E="5555555555555555555555555555555555555555"   # shallow member PR 4241 head
PR=4242

cr() {
  jq -n --arg n "$1" --argjson a "$2" --arg s "$3" --argjson c "$4" --arg t "$5" --argjson i "$6" \
    '{id:$i,name:$n,status:$s,conclusion:$c,started_at:(if $t == "null" then null else $t end),app:{id:$a,slug:"github-actions"}}'
}
green1() { jq -nc --argjson x "$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)" \
              --argjson y "$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)" \
              --argjson z "$(cr test 15368 completed '"success"' 2026-10-03T10:00:02Z 103)" \
              '{total_count:3,check_runs:[$x,$y,$z]}'; }
entry() { jq -nc --argjson p "$1" --arg hc "$2" --argjson n "$3" --arg h "$4" \
              '{position:$p,headCommit:{oid:$hc},pullRequest:{number:$n,headRefOid:$h}}'; }
entries_json() { jq -nc --argjson nx "${2:-false}" --argjson n "$1" \
                    '{data:{repository:{mergeQueue:{entries:{pageInfo:{hasNextPage:$nx},nodes:$n}}}}}' ; }

mkfix() { # singleton: one entry owning HEAD_SHA, green head runs
  local d="$1"; assert_fixture_dir "$d"; mkdir -p "$d" || exit 2
  entries_json "[$(entry 1 "$S40_C" $PR "$S40_A")]" > "$d/entries.json"
  green1 > "$d/cr.$S40_A.1"
  printf '{"total_count":0,"check_runs":[]}\n' > "$d/main.json"
}
mkgrp() { # 2-member group: 4241@pos1 (head S40_E, own candidate S40_B), 4242@pos2 owns S40_C
  local d="$1"; assert_fixture_dir "$d"; mkdir -p "$d" || exit 2
  entries_json "[$(entry 1 "$S40_B" 4241 "$S40_E"),$(entry 2 "$S40_C" $PR "$S40_A")]" > "$d/entries.json"
  green1 > "$d/cr.$S40_A.1"; green1 > "$d/cr.$S40_E.1"
  printf '{"total_count":0,"check_runs":[]}\n' > "$d/main.json"
}
pages() { # pages <dir> <ref> <json-array>... : replace a member head's check-runs pages
  local d="$1" ref="$2"; shift 2
  assert_fixture_dir "$d"; rm -f "$d"/cr."$ref".* || exit 2
  local arr n=0
  for arr in "$@"; do n=$((n + 1)); jq -n --argjson c "$arr" '{total_count:($c|length),check_runs:$c}' > "$d/cr.$ref.$n"; done
}

GOOD_REF="refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"
OUT=""; RC=0; CALLS=""
run_sut() {
  local d="$1"; shift; assert_fixture_dir "$d"
  CALLS="$d/calls.log"; : > "$d/calls.log"
  OUT="$(env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_TOKEN=synthetic-token \
    REPO=example-org/example-repo HEAD_REF="$GOOD_REF" HEAD_SHA="$S40_C" BASE_REF=refs/heads/main \
    MQ_VERIFY_RETRY_DELAY=0 GH_FIX_DIR="$d" GH_CALLS="$CALLS" "$@" bash "$SUT" 2>&1)"
  RC=$?
}
ncalls() { if [[ -s "$CALLS" ]]; then wc -l < "$CALLS" | tr -d ' '; else echo 0; fi; }
expect_green() {
  local label="$1"
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK members="* && "$(ncalls)" -ge 2 ]]; then
    pass "$label"
  else fail "$label (rc=$RC calls=$(ncalls))"; [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2; fi
}
expect_red() {
  local label="$1" anchor="$2"
  if [[ "$RC" -ne 0 && "$OUT" != *"merge-queue-cla-verify=OK"* && "$OUT" == *"$anchor"* ]]; then
    pass "$label"
  else fail "$label (rc=$RC, wanted anchor: $anchor)"; [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2; fi
}
expect_no_calls() { if [[ "$(ncalls)" -eq 0 ]]; then pass "$1"; else fail "$1 (made $(ncalls) gh call(s))"; fi; }

CASE_N=0
newfix() { CASE_N=$((CASE_N + 1)); FX="$WORK/fx.$CASE_N"; mkfix "$FX"; }
newgrp() { CASE_N=$((CASE_N + 1)); FX="$WORK/fx.$CASE_N"; mkgrp "$FX"; }

run_cases() {
  # ---- must PASS --------------------------------------------------------------------------
  newfix; run_sut "$FX"
  expect_green "P1 singleton entry: both real contexts green on the head (backward-compat)"
  if grep -Eq -- ' (-X|--method|--input)( |$)| --method(POST|PATCH|PUT|DELETE)' "$CALLS"; then
    fail "P1b verifier sent a write-shaped gh call"
  else pass "P1b every gh call is a read (no -X/--method/--input; graphql -f/-F are read inputs)"; fi

  newgrp; run_sut "$FX"
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK members=2"* ]]; then
    pass "P2 2-member group all-green verifies members=2"
  else fail "P2 group all-green did not verify members=2 (rc=$RC out=$OUT)"; fi

  # anchor fallback: no headCommit match — the named PR's own entry anchors membership.
  newgrp
  entries_json "[$(entry 1 "$S40_B" 4241 "$S40_E"),$(entry 2 "9999999999999999999999999999999999999999" $PR "$S40_A")]" > "$FX/entries.json"
  run_sut "$FX"
  expect_green "P3 anchor falls back to the named PR's entry when no headCommit matches HEAD_SHA"

  # deeper-position entries NOT in this candidate are excluded even with red CLA.
  newgrp
  entries_json "[$(entry 1 "$S40_B" 4241 "$S40_E"),$(entry 2 "$S40_C" $PR "$S40_A"),$(entry 3 "6666666666666666666666666666666666666666" 4243 "7777777777777777777777777777777777777777")]" > "$FX/entries.json"
  pages "$FX" "7777777777777777777777777777777777777777" "[$(cr cla-check 15368 completed '"failure"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  if [[ "$RC" -eq 0 && "$OUT" == *"members=2"* ]] && ! grep -Fq 'commits/7777' "$CALLS"; then
    pass "P4 deeper-position non-member with RED cla is excluded and never read"
  else fail "P4 a deeper-position entry leaked into the member set (rc=$RC out=$OUT)"; fi

  # per-member pagination: member head's cla-check only on page 2.
  newgrp
  filler="$(jq -nc '[range(0;100) | {id:(1000+.),name:("filler-"+tostring),status:"completed",conclusion:"success",started_at:"2026-10-03T08:00:00Z",app:{id:15368,slug:"github-actions"}}]')"
  pages "$FX" "$S40_E" "$filler" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_green "P6 member head check-runs paginated (--paginate on each member)"

  newfix; run_sut "$FX"
  if grep -Fq -- '--paginate' "$CALLS" && grep -Fq -- 'filter=all' "$CALLS" && grep -Fq -- 'per_page=100' "$CALLS" \
     && grep -Fq -- "commits/${S40_A}/check-runs" "$CALLS" && ! grep -Fq -- 'commits/main/' "$CALLS"; then
    pass "P7 check-runs calls carry --paginate/filter=all/per_page=100 and read member heads, never main"
  else fail "P7 check-runs argv missing flags or reads the wrong ref"; sed -n 1,5p "$CALLS" >&2; fi

  # ---- must FAIL --------------------------------------------------------------------------
  # the CLO negative row: named PR green, a groupmate member red -> fail closed.
  # (older green then newer red on the member's cla-check — the highest-id run decides)
  newgrp
  pages "$FX" "$S40_E" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T09:00:00Z 90),$(cr cla-check 15368 completed '"failure"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F1 named-PR-green + member-red group fails (cla-check on a member)" "cla-check"

  newgrp
  pages "$FX" "$S40_E" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F2 member missing cla-evidence fails" "cla-evidence"

  newgrp
  pages "$FX" "$S40_E" "[$(cr cla-check 99999 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F6 a member success from a different app id (spoof) does not count" "cla-check"

  newfix
  entries_json "[]" > "$FX/entries.json"
  run_sut "$FX"
  expect_red "F-empty empty entries list cannot bind the candidate" "bind"

  newfix
  jq -nc '{data:{repository:{mergeQueue:{entries:{pageInfo:{hasNextPage:true},nodes:[]}}}}}' > "$FX/entries.json"
  run_sut "$FX"
  expect_red "F-page entries pagination beyond first page refuses a truncated member set" "paginat"

  # named PR absent from the member set (head_ref names a non-member).
  newgrp
  run_sut "$FX" HEAD_REF="refs/heads/gh-readonly-queue/main/pr-9999-${S40_C}"
  expect_red "F-absent named PR absent from the member set fails" "non-member"

  # named PR present but NOT deepest: a deeper entry owns HEAD_SHA.
  newgrp
  entries_json "[$(entry 1 "$S40_B" $PR "$S40_A"),$(entry 2 "$S40_C" 4241 "$S40_E")]" > "$FX/entries.json"
  run_sut "$FX"
  expect_red "F-tail named PR not the deepest member — tail would go unverified" "deeper"

  # a member head sha that is not 40-hex dies.
  newgrp
  entries_json "[$(entry 1 "$S40_B" 4241 "not-a-sha"),$(entry 2 "$S40_C" $PR "$S40_A")]" > "$FX/entries.json"
  run_sut "$FX"
  expect_red "F-shape member head sha of wrong shape fails" "sha"

  local ep
  for ep in mq checks; do
    newfix; run_sut "$FX" GH_FIX_FAIL="$ep"
    expect_red "F5-$ep gh error on the $ep endpoint fails" "::error::"
  done

  # retry budget: one transient per read rides out; two is fatal and bounded.
  ncalls_of() { grep -c -- "$1" "$CALLS" || true; }
  newfix; run_sut "$FX" GH_FIX_FLAKY=mq
  if [[ "$RC" -eq 0 && "$(ncalls_of 'graphql')" == "2" ]]; then
    pass "T1 transient graphql failure is retried once and verifies"
  else fail "T1 graphql transient not retried (rc=$RC, reads=$(ncalls_of 'graphql'))"; fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=checks
  if [[ "$RC" -eq 0 && "$(ncalls_of '/check-runs')" == "2" ]]; then
    pass "T2 transient check-runs failure is retried once and verifies"
  else fail "T2 check-runs transient not retried (rc=$RC, reads=$(ncalls_of '/check-runs'))"; fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=mq GH_FIX_FLAKY_N=2
  if [[ "$RC" -ne 0 && "$OUT" == *"gh api failed reading merge queue entries"* && "$(ncalls_of 'graphql')" == "2" ]]; then
    pass "T3 two graphql failures fail closed after exactly one retry"
  else fail "T3 graphql retry not bounded (rc=$RC, reads=$(ncalls_of 'graphql'))"; fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=checks GH_FIX_FLAKY_N=2
  if [[ "$RC" -ne 0 && "$OUT" == *"gh api failed reading"*check-runs* && "$(ncalls_of '/check-runs')" == "2" ]]; then
    pass "T4 two check-runs failures fail closed after exactly one retry"
  else fail "T4 check-runs retry not bounded (rc=$RC, reads=$(ncalls_of '/check-runs'))"; fi

  # head_ref shapes: each must be rejected BEFORE any API call.
  local bad idx=0
  local -a bads=(
    "" "refs/heads/main"
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

  # reason= output rows (unchanged contract for the workflow's failure-post step).
  newfix; : > "$FX/out"
  entries_json "[$(entry 1 "$S40_C" $PR "$S40_A")]" > "$FX/entries.json"
  pages "$FX" "$S40_A" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX" GITHUB_OUTPUT="$FX/out"
  if [[ "$RC" -ne 0 && "$(grep -c '^reason=' "$FX/out")" == "1" && "$(wc -l < "$FX/out" | tr -d ' ')" == "1" \
        && "$(cat "$FX/out")" == *"cla-evidence"* ]]; then
    pass "R1 a verify failure writes exactly one reason= line naming the failed context"
  else fail "R1 reason= output wrong (rc=$RC)"; fi
  newfix; : > "$FX/out"
  run_sut "$FX" GITHUB_OUTPUT="$FX/out" HEAD_REF="refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"$'\n'"forged=1"
  if [[ "$RC" -ne 0 && "$(wc -l < "$FX/out" | tr -d ' ')" == "1" && "$(cat "$FX/out")" != *"forged"* ]]; then
    pass "R2 a forged head_ref never reaches the reason= output"
  else fail "R2 reason= carries event text (rc=$RC)"; fi
  newfix; : > "$FX/out"; run_sut "$FX" GITHUB_OUTPUT="$FX/out"
  if [[ "$RC" -eq 0 && ! -s "$FX/out" ]]; then pass "R3 a passing verify writes no reason="
  else fail "R3 a passing verify wrote output or failed (rc=$RC)"; fi
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
mutant() {
  local id="$1" row="$2" expr="$3" m="$MUTDIR/$1.sh" hit=0 f
  cp "$SUT_REAL" "$m" || exit 2
  sed -i "$expr" "$m"
  if cmp -s "$SUT_REAL" "$m"; then fail "mutant $id: mutation did not land"; return; fi
  SUT="$m"; QUIET=1; MUT_FAILED=()
  run_cases
  QUIET=0; SUT="$SUT_REAL"
  for f in "${MUT_FAILED[@]}"; do case "$f" in "$row"*) hit=1 ;; esac; done
  if [[ "$hit" -eq 1 ]]; then pass "mutant $id turns row $row RED"
  else fail "mutant $id did not turn row $row RED (red rows: ${MUT_FAILED[*]:-none})"; fi
}

mutant app     "F6"  's/ and \.app\.id == 15368//'
mutant latest  "F1"  's/^  | last$/  | first/'
# shellcheck disable=SC2016
mutant base    "F3b" 's/"\${BASE_REF:-}" == "refs\/heads\/main"/-n "${BASE_REF:-}"/'
# membership mutants:
#   include-all: verify EVERY listed entry (deeper non-members leak in) — P4 must RED.
# shellcheck disable=SC2016
mutant includeall "P4" 's/select(\.position <= \$pos)/./'
#   no-maximal: drop the deepest-member invariant — F-tail must RED.
# shellcheck disable=SC2016
mutant nomaximal  "F-tail" 's/"\$named_pos" == "\$max_pos"/1 = 1/'
#   no-headCommit-binding: anchor becomes the FIRST listed entry (member set
#   shrinks to the shallow member) — P2 (members=2) must RED.
# shellcheck disable=SC2016
mutant nobind      "P2" 's/\.headCommit\.oid == \$sha/true/'
#   paginate: drop the check-runs --paginate so page-2 runs are missed — P6 must RED.
mutant paginate "P6" 's/ --paginate / /'
