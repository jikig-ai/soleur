#!/usr/bin/env bash
# ci-push-dedupe-soak-9512.test.sh — Guard 2 for #9512 (ADR-276 S2): drives the soak probe through a fake `gh`
# and pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal), with
# mutation rows against mutated COPIES of the probe. An exit-code contract nothing drives is a comment.
#
# The clock is injected (SOAK_NOW_EPOCH), so no row sleeps and none depends on the wall clock.
# Fixtures are synthesized (shas are `sha###`, the tracker is #4242); nothing is written outside a mktemp dir.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/pds-soak.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

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
passes=0; fails=0; asserted=0
FAILURES=()
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }

# instrument self-test: both helpers must move their counters
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not each record"; exit 1
fi
passes=0; fails=0; asserted=0; FAILURES=()

NOW_ISO="2026-11-01T00:00:00Z"
NOW_EPOCH="$(date -u -d "$NOW_ISO" +%s)"
MERGED_ISO="2026-10-10T00:00:00Z"

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = "api" ] || exit 64
shift
paginate=0; jqx=""; ep=""
while (( $# )); do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) jqx="$2"; shift ;;
    -*) exit 64 ;;
    *) ep="$1" ;;
  esac
  shift
done
printf '%s\n' "$ep" >> "$FX/requests.log"
[ -f "$FX/fail-$(basename "${ep%%\?*}")" ] && { echo "gh: HTTP 500 boom" >&2; exit 1; }
case "$ep" in
  repos/*/pulls/9808) f="$FX/pr.json" ;;
  repos/*/actions/variables/CI_PUSH_DEDUPE)
    [ -f "$FX/fail-variable" ] && { echo "gh: HTTP 500 boom" >&2; exit 1; }
    [ -f "$FX/var.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    f="$FX/var.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=push*) [ -f "$FX/fail-push" ] && { echo "gh: HTTP 500" >&2; exit 1; }; f="$FX/push.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=merge_group*)
    [ -f "$FX/fail-mg" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    (( paginate )) || exit 64
    cat "$FX"/mg-*.json; exit 0 ;;
  repos/*/actions/runs/*/jobs*) [ -f "$FX/fail-jobs" ] && { echo "gh: HTTP 500" >&2; exit 1; }; r="${ep#*runs/}"; f="$FX/jobs-${r%%/*}.json" ;;
  repos/*/issues?labels=follow-through*) f="$FX/issues.json" ;;
  repos/*/issues/*/comments*) n="${ep#*issues/}"; f="$FX/comments-${n%%/*}.json" ;;
  *) exit 64 ;;
esac
[ -f "$f" ] || exit 1
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
FAKE
chmod +x "$TMP/bin/gh"

# build_fx <dir> <n_elided> <n_full> <elided_run_seconds> <full_run_seconds> [key=value ...]
#   actdays=D    activation D days before the injected now (default 12); noact: variable unset (404); val=V: variable value
#   unmatched=K  the K oldest elided runs have no merge_group voucher   early=K  K extra elided runs BEFORE the activation
#   nomarker / midline: no S2-EXIT-CENSUS comment / the marker not at a line start   pdfail: one full run's push-dedupe is red
#   unmerged: the S2 PR is not merged   noissue: no tracker among the follow-through issues   failX: the X read fails
build_fx() {
  local fx="$1" ne="$2" nf="$3" es="$4" fs="$5"; shift 5
  assert_fixture_dir "$fx"; rm -rf "$fx"; mkdir -p "$fx"
  local actdays=12 val=on noact=0 unmatched=0 early=0 marker=yes pdfail=0 unmerged=0 noissue=0 kv
  for kv in "$@"; do
    case "$kv" in
      actdays=*) actdays="${kv#*=}" ;; val=*) val="${kv#*=}" ;; noact) noact=1 ;; unmatched=*) unmatched="${kv#*=}" ;;
      early=*) early="${kv#*=}" ;; nomarker) marker=no ;; midline) marker=mid ;; pdfail) pdfail=1 ;; unmerged) unmerged=1 ;;
      noissue) noissue=1 ;; fail*) : > "$fx/${kv/fail/fail-}" ;;
    esac
  done
  local act_epoch=$((NOW_EPOCH - actdays * 86400)) act_iso
  act_iso="$(date -u -d "@$act_epoch" +%Y-%m-%dT%H:%M:%SZ)"
  if (( unmerged )); then printf '{"merged_at":null}\n' > "$fx/pr.json"; else printf '{"merged_at":"%s"}\n' "$MERGED_ISO" > "$fx/pr.json"; fi
  (( noact )) || printf '{"name":"CI_PUSH_DEDUPE","value":"%s","updated_at":"%s"}\n' "$val" "$act_iso" > "$fx/var.json"
  local i total=$((early + ne + nf)) runs="" id sha created secs elided mg1="" mg2="" k=0
  for ((i = 1; i <= total; i++)); do
    id=$((1000 + i)); sha="sha$(printf '%03d' "$i")"
    if (( i <= early )); then
      created=$((act_epoch - 3600 * (early - i + 1))); elided=1; secs="$es"
    elif (( i <= early + ne )); then
      created=$((act_epoch + 3600 * i)); elided=1; secs="$es"
    else
      created=$((act_epoch + 3600 * i)); elided=0; secs="$fs"
    fi
    runs="{\"id\":$id,\"head_sha\":\"$sha\",\"created_at\":\"$(date -u -d "@$created" +%Y-%m-%dT%H:%M:%SZ)\"},$runs"   # newest first
    if (( elided )); then
      jq -n --argjson s "$secs" '{jobs:[
        {name:"push-dedupe",conclusion:"success",runner_id:9,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-20T10:00:00Z"},
        {name:"test-scripts",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null},
        {name:"test-webplat",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null},
        {name:"lint",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)}]}' > "$fx/jobs-$id.json"
    else
      local pd=success; (( pdfail && i == total )) && pd=failure
      jq -n --argjson s "$secs" --arg pd "$pd" '{jobs:[
        {name:"push-dedupe",conclusion:$pd,runner_id:9,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-20T10:00:00Z"},
        {name:"test-scripts (1/8)",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)},
        {name:"skipped-with-huge-duration",conclusion:"skipped",runner_id:null,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-21T10:00:00Z"}]}' > "$fx/jobs-$id.json"
    fi
    if (( elided )) && (( k >= unmatched )); then
      if (( k % 2 )); then mg1="$mg1{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"$sha\"},"
      else mg2="$mg2{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"$sha\"},"; fi
    fi
    (( elided )) && k=$((k + 1))
  done
  # noise a correct voucher check must ignore: a failed merge_group run and a pull_request run for the elided SHAs
  mg1="$mg1{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"sha001\"},{\"event\":\"pull_request\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"sha001\"}"
  printf '{"workflow_runs":[%s]}\n' "${runs%,}" > "$fx/push.json"
  printf '{"workflow_runs":[%s]}\n' "${mg1%,}" > "$fx/mg-1.json"
  printf '{"workflow_runs":[%s{"event":"merge_group","status":"in_progress","conclusion":null,"head_sha":"shaZZZ"}]}\n' "$mg2" > "$fx/mg-2.json"
  if (( noissue )); then printf '[]\n' > "$fx/issues.json"
  else printf '[{"number":4242,"body":"<!-- soleur:followthrough script=scripts/followthroughs/ci-push-dedupe-soak-9512.sh earliest=2026-10-10T00:00:00Z secrets=GH_TOKEN -->"},{"number":4243,"body":"unrelated"}]\n' > "$fx/issues.json"; fi
  case "$marker" in
    yes) printf '[{"body":"noted"},{"body":"exit census\\nS2-EXIT-CENSUS: https://github.com/jikig-ai/soleur/issues/4242#issuecomment-1"}]\n' > "$fx/comments-4242.json" ;;
    mid) printf '[{"body":"we will post an S2-EXIT-CENSUS: https://x later"}]\n' > "$fx/comments-4242.json" ;;
    *)   printf '[{"body":"nothing yet"}]\n' > "$fx/comments-4242.json" ;;
  esac
}

# expect <label> <want-rc> <want-text> <fx> [env...]  — runs $PROBE_UNDER (default the live probe)
PROBE_UNDER="$PROBE"
expect() {
  local label="$1" want="$2" text="$3" fx="$4"; shift 4
  local out rc
  out="$(env FX="$fx" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" "$@" bash "$PROBE_UNDER" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" && "$out" == *"$text"* ]]; then pass "$label (rc=$rc)"; else fail "$label: want rc=$want containing '$text', got rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}

# 25 runs: 10 elided at 510 s + 15 full at 2568 s => total 43620 s => exactly 29.08 min/run (the limit, a must-PASS)
EXACT_ARGS=(10 15 510 2568)
core_rows() {
  build_fx "$TMP/c1" 10 15 510 2568;                  expect "PASS: 10 elided, 12 days, mean exactly 29.08, marker present" 0 "PASS" "$TMP/c1"
  build_fx "$TMP/c2" 0 25 510 2568;                   expect "NOT YET: zero elided runs is never a pass" 2 "NOT YET: 0 elided" "$TMP/c2"
  build_fx "$TMP/c3" 10 15 510 2568 unmatched=1;      expect "FAIL: an elided run with no merge_group voucher" 1 "no completed success merge_group run" "$TMP/c3"
  build_fx "$TMP/c4" 10 15 510 2568 unmatched=3;      expect "FAIL: a second and third unvouched run after a compliant first" 1 "3 elided push run" "$TMP/c4"
  build_fx "$TMP/c5" 10 15 510 2569;                  expect "FAIL: mean 29.0801 over ALL runs (one second over the limit)" 1 "mean" "$TMP/c5"
  build_fx "$TMP/c6" 10 20 510 4200;                  expect "FAIL: the mean is over ALL runs; the elided-only mean (8.5) would pass" 1 "over 29.08" "$TMP/c6"
  build_fx "$TMP/c7" 10 15 510 2568 nomarker;         expect "NOT YET: no S2-EXIT-CENSUS marker (the sweeper closes on exit 0)" 2 "S2-EXIT-CENSUS" "$TMP/c7"
  build_fx "$TMP/c8" 9 16 510 2568;                   expect "NOT YET: 9 elided runs" 2 "9 elided" "$TMP/c8"
  build_fx "$TMP/c9" 10 15 510 2568 actdays=6;        expect "NOT YET: 6 days since activation" 2 "6 day" "$TMP/c9"
  build_fx "$TMP/c10" 10 15 510 2568 actdays=7;       expect "boundary: exactly 7 days PASSES" 0 "PASS" "$TMP/c10"
  build_fx "$TMP/c11" 3 20 510 2568 unmatched=1 actdays=2 nomarker; expect "FAIL takes precedence over NOT YET (wrong elision with too few runs, days, no marker)" 1 "FAIL" "$TMP/c11"
  build_fx "$TMP/c12" 10 15 510 2568; : > "$TMP/c12/fail-jobs"
                                                      expect "CANNOT ESTABLISH: a jobs read fails" 3 "CANNOT ESTABLISH" "$TMP/c12"
}
core_rows

# --- the rest of the contract (not mutated below) -----------------------------------------------------------------
build_fx "$TMP/d1" 5 20 510 2568 noact;                 expect "FAIL: elided runs with the variable unset (an org-level or deleted variable)" 1 "no activation record" "$TMP/d1"
build_fx "$TMP/d2" 10 15 510 2568 early=2;              expect "FAIL: two runs elided BEFORE the variable was updated" 1 "2 push run" "$TMP/d2"
build_fx "$TMP/d3" 0 25 510 2568 noact;                 expect "NOT YET: not activated (variable unset), nothing elided" 2 "not activated" "$TMP/d3"
build_fx "$TMP/d4" 0 25 510 2568 val=ON;                expect "NOT YET: the value ON is not exactly 'on'" 2 "not activated" "$TMP/d4"
build_fx "$TMP/d5" 0 25 510 2568 val=true;              expect "NOT YET: the value true is not exactly 'on'" 2 "not activated" "$TMP/d5"
build_fx "$TMP/d6" 5 20 510 2568 val=ON;                expect "FAIL: elided runs while the value is ON, not 'on'" 1 "no activation record" "$TMP/d6"
build_fx "$TMP/d7" 0 25 510 2568 noact;                 expect "FAIL: 30 days after the merge and still unset: activate, or revert" 1 "activate it, or revert" "$TMP/d7" SOAK_NOW_EPOCH=$((NOW_EPOCH + 31 * 86400))
build_fx "$TMP/d8" 10 15 510 2568 unmerged;             expect "NOT YET: the S2 PR is not merged" 2 "not merged" "$TMP/d8"
build_fx "$TMP/d9" 10 15 510 2568 midline;              expect "NOT YET: the marker must start a line, a mention does not count" 2 "S2-EXIT-CENSUS" "$TMP/d9"
build_fx "$TMP/d10" 10 15 510 2568 noissue;             expect "NOT YET: the tracker is not among the open follow-through issues" 2 "tracker issue" "$TMP/d10"
build_fx "$TMP/d11" 10 15 510 2568 pdfail;              expect "PASS: a full run whose push-dedupe is red is a normal full run, not a wrong elision" 0 "PASS" "$TMP/d11"
for r in variable push mg; do
  build_fx "$TMP/e-$r" 10 15 510 2568; : > "$TMP/e-$r/fail-$r"
                                                        expect "CANNOT ESTABLISH: the $r read fails (never a pass, never a fail)" 3 "CANNOT ESTABLISH" "$TMP/e-$r"
done
build_fx "$TMP/e1" 10 15 510 2568;                      expect "an unset GH_TOKEN is CANNOT ESTABLISH, never a pass" 3 "GH_TOKEN is not set" "$TMP/e1" GH_TOKEN=
build_fx "$TMP/e2" 10 15 510 2568
out="$(env FX="$TMP/e2" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi
# the runs and merge_group queries are windowed and shaped as the probe documents
if grep -cF 'created=%3E2026-10-10T00:00:00Z' "$TMP/c1/requests.log" >/dev/null && grep -cF 'branch=main&status=completed' "$TMP/c1/requests.log" >/dev/null \
   && grep -cF 'event=merge_group' "$TMP/c1/requests.log" >/dev/null; then pass "the push query is windowed after the merge, completed and main-only; the merge_group listing is read"
else fail "the queries lost their parameters: $(head -5 "$TMP/c1/requests.log" | tr '\n' '|')"; fi

# --- mutation rows: each mutated COPY of the probe must turn at least one core row red ----------------------------------
mut_probe() { # <name> <old> <new>
  local f="$TMP/mut-$1.sh"
  if ! python3 - "$PROBE" "$f" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  then fail "MUTANT $1: mutation did NOT land"; return 1; fi
  cmp -s "$f" "$PROBE" && { fail "MUTANT $1: byte-identical to the probe"; return 1; }
  chmod +x "$f"; MUT_FILE="$f"; return 0
}
MUT_RUN=0; MUT_CAUGHT=0
mutant() { # <name> <old> <new>
  MUT_RUN=$((MUT_RUN + 1))
  mut_probe "$1" "$2" "$3" || return
  local before=$fails
  PROBE_UNDER="$MUT_FILE"; core_rows_quiet
  PROBE_UNDER="$PROBE"
  if [ "$MUT_REDS" -gt 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "MUTANT $1 turned $MUT_REDS core row(s) red"
  else fail "MUTANT $1: no core row went red"; fi
}
core_rows_quiet() { # runs core_rows against $PROBE_UNDER, counts reds without recording them as this suite's failures
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]}
  core_rows >/dev/null
  MUT_REDS=$((fails - f0))
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}")
}
mutant m-min-elided   '(( elided < MIN_ELIDED || age_days < MIN_DAYS ))' '(( 0 ))'
mutant m-no-voucher   'if ! [ "${covered:-0}" -gt 0 ] 2>/dev/null; then' 'if false; then'
mutant m-first-only   'elided=$((elided + 1))' 'elided=$((elided + 1)); [ "$elided" -gt 1 ] && continue'
mutant m-elided-mean  'n=$((n + 1)); total_s=$((total_s + secs))' 'n=$((n + 1)); [ "$is_elided" = "yes" ] && total_s=$((total_s + secs))'
mutant m-boundary     'total_s * 100 > MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n' 'total_s * 100 >= MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n'
mutant m-api-quiet    'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }' 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 0; }'
mutant m-precedence   'if (( wrong > 0 )); then' 'if (( wrong > 0 && ${age_days:-0} >= 7 )); then'
mutant m-no-marker    'if ! [ "${marked:-0}" -gt 0 ] 2>/dev/null; then' 'if false; then'
mutant m-unmatched-ok 'covered="$(jq -r --arg sha "$sha" '"'"'map(select(. == $sha)) | length'"'"' <<<"$mg_json" 2>/dev/null)" || fail_api "voucher lookup"' 'covered=1'
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -ge 9 ]; then pass "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 9)"; fi

# harness row: a probe that always exits 0 must be refused by the core rows (the rows can fail)
printf '#!/usr/bin/env bash\necho PASS\nexit 0\n' > "$TMP/always-pass.sh"; chmod +x "$TMP/always-pass.sh"
PROBE_UNDER="$TMP/always-pass.sh"; core_rows_quiet; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -ge 8 ]; then pass "HARNESS: an always-PASS probe turns $MUT_REDS core rows red"; else fail "HARNESS: an always-PASS probe turned only $MUT_REDS core rows red"; fi

printf 'ci-push-dedupe-soak-9512: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
# DELIBERATELY NOT ROUTED THROUGH fail(): compares against a literal and exits directly.
_total=$((passes + fails))
_FLOOR=40
if [ "$_total" -lt "$_FLOOR" ]; then
  printf '[FATAL] assertion floor: executed %d < %d\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
exit $(( ${#FAILURES[@]} > 0 ))
