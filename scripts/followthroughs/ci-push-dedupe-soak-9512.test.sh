#!/usr/bin/env bash
# ci-push-dedupe-soak-9512.test.sh — Guard 2 for #9512 (ADR-276 S2): drives the soak probe through a fake `gh`
# and pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal), with
# mutation rows against mutated COPIES of the probe. An exit-code contract nothing drives is a comment.
#
# The clock is injected (SOAK_NOW_EPOCH), the ADR file and test-all.sh are fixture copies (SOAK_ADR_FILE,
# SOAK_TEST_ALL), so no row sleeps and none depends on the wall clock or the live repo.
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
case "$ep" in
  repos/*/pulls/9808) f="$FX/pr.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=push*) [ -f "$FX/fail-push" ] && { echo "gh: HTTP 500" >&2; exit 1; }; f="$FX/push.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=merge_group*)
    [ -f "$FX/fail-mg" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    (( paginate )) || exit 64
    cat "$FX"/mg-*.json; exit 0 ;;
  repos/*/actions/runs/*/jobs\?per_page=100\&filter=latest) [ -f "$FX/fail-jobs" ] && { echo "gh: HTTP 500" >&2; exit 1; }; r="${ep#*runs/}"; f="$FX/jobs-${r%%/*}.json" ;;
  repos/*/issues\?labels=follow-through\&state=open\&per_page=100) f="$FX/issues.json" ;;
  repos/*/issues/*/comments\?per_page=100) [ -f "$FX/fail-comments" ] && { echo "gh: HTTP 403 Resource not accessible" >&2; exit 1; }; n="${ep#*issues/}"; f="$FX/comments-${n%%/*}.json" ;;
  *) exit 64 ;;
esac
[ -f "$f" ] || exit 1
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
FAKE
chmod +x "$TMP/bin/gh"

# build_fx <dir> <n_elided> <n_full> <elided_run_seconds> <full_run_seconds> [key=value ...]
#   actdays=D    S2-ACTIVATED comment D days before the injected now (default 12), by an OWNER; noact: none
#   untrustedact: the activation comment is by a NONE-association commenter   deact: a LATER S2-DEACTIVATED (OWNER)
#   unmatched=K  the K oldest elided runs have no merge_group voucher   early=K  K extra elided runs BEFORE the activation
#   marker=yes|none|mid|untrusted|nonurl|placeholder   the S2-EXIT-CENSUS comment (default yes)
#   adr=<status>  ADR-276 status line (default adopting)   noreg: test-all.sh lacks the proof suite
#   extra=<kind>  one more NON-elided run (mixed|nots|pdred): a shape a loose elision predicate would call elided
#   pdred: one full run's push-dedupe is red   unmerged / noissue / failX: the X read fails (jobs|push|mg|comments)
build_fx() {
  local fx="$1" ne="$2" nf="$3" es="$4" fs="$5"; shift 5
  assert_fixture_dir "$fx"; rm -rf "$fx"; mkdir -p "$fx"
  local actdays=12 noact=0 untrustedact=0 deact=0 unmatched=0 early=0 marker=yes pdred=0 unmerged=0 noissue=0 adr=adopting noreg=0 extra="" kv
  for kv in "$@"; do
    case "$kv" in
      actdays=*) actdays="${kv#*=}" ;; noact) noact=1 ;; untrustedact) untrustedact=1 ;; deact) deact=1 ;;
      unmatched=*) unmatched="${kv#*=}" ;; early=*) early="${kv#*=}" ;; marker=*) marker="${kv#*=}" ;;
      pdred) pdred=1 ;; unmerged) unmerged=1 ;; noissue) noissue=1 ;; adr=*) adr="${kv#*=}" ;; noreg) noreg=1 ;; extra=*) extra="${kv#*=}" ;;
      fail*) : > "$fx/fail-${kv#fail}" ;;
    esac
  done
  local act_epoch=$((NOW_EPOCH - actdays * 86400)) act_iso
  act_iso="$(date -u -d "@$act_epoch" +%Y-%m-%dT%H:%M:%SZ)"
  if (( unmerged )); then printf '{"merged_at":null}\n' > "$fx/pr.json"; else printf '{"merged_at":"%s"}\n' "$MERGED_ISO" > "$fx/pr.json"; fi
  printf -- '---\nstatus: %s\n---\n# ADR-276 fixture\n' "$adr" > "$fx/ADR-276-fixture.md"
  if (( noreg )); then printf 'run_suite "other" bash other.test.sh\n' > "$fx/test-all.sh"
  else printf 'run_suite "scripts/ci-push-dedupe" bash scripts/ci-push-dedupe.test.sh\n' > "$fx/test-all.sh"; fi
  local i total=$((early + ne + nf)) runs="" id sha created secs elided mg1="" mg2="" k=0 kind
  for ((i = 1; i <= total + (${#extra} > 0 ? 1 : 0); i++)); do
    id=$((1000 + i)); sha="sha$(printf '%03d' "$i")"; kind=""
    if (( i <= early )); then
      created=$((act_epoch - 3600 * (early - i + 1))); elided=1; secs="$es"
    elif (( i <= early + nf )); then
      created=$((act_epoch + 3600 * i)); elided=0; secs="$fs"
    elif (( i <= total )); then
      created=$((act_epoch + 3600 * i)); elided=1; secs="$es"
    else
      created=$((act_epoch + 3600 * i)); elided=0; secs="$es"; kind="$extra"
    fi
    runs="{\"id\":$id,\"head_sha\":\"$sha\",\"created_at\":\"$(date -u -d "@$created" +%Y-%m-%dT%H:%M:%SZ)\"},$runs"   # newest first
    # cost-accounting decoys on EVERY run: none of these may count (skipped+runner, runner-less+running time, negative duration)
    local decoys='{name:"skipped-with-runner",conclusion:"skipped",runner_id:5,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-21T10:00:00Z"},
      {name:"runnerless-timed",conclusion:"cancelled",runner_id:null,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-21T10:00:00Z"},
      {name:"negative-duration",conclusion:"success",runner_id:6,started_at:"2026-10-20T10:10:00Z",completed_at:"2026-10-20T10:00:00Z"}'
    if (( elided )); then
      jq -n --argjson s "$secs" "{jobs:[
        {name:\"push-dedupe\",conclusion:\"success\",runner_id:9,started_at:\"2026-10-20T10:00:00Z\",completed_at:\"2026-10-20T10:00:00Z\",steps:[{name:\"Proof holds for this SHA\",conclusion:\"success\"}]},
        {name:\"test-scripts\",conclusion:\"skipped\",runner_id:null,started_at:null,completed_at:null},
        {name:\"test-scripts-heavy\",conclusion:\"skipped\",runner_id:null,started_at:null,completed_at:null},
        {name:\"lint\",conclusion:\"success\",runner_id:7,started_at:\"2026-10-20T10:00:00Z\",completed_at:(\"2026-10-20T10:00:00Z\"|fromdateiso8601 + \$s | todate)},
        $decoys]}" > "$fx/jobs-$id.json"
    else
      local pd=success; { (( pdred && i == total )) || [ "$kind" = pdred ]; } && pd=failure
      local tsjobs='{name:"test-scripts (1/8)",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)}'
      case "$kind" in
        mixed) tsjobs="$tsjobs"',{name:"test-scripts (2/8)",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null}' ;;
        nots)  tsjobs='{name:"test-webplat (1/2)",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)}' ;;
        pdred) tsjobs='{name:"test-scripts (1/8)",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null}' ;;
      esac
      jq -n --argjson s "$secs" --arg pd "$pd" "{jobs:[
        {name:\"push-dedupe\",conclusion:\$pd,runner_id:9,started_at:\"2026-10-20T10:00:00Z\",completed_at:\"2026-10-20T10:00:00Z\"},
        $tsjobs, $decoys]}" > "$fx/jobs-$id.json"
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
  # the tracker's comments: [{body, author_association}]
  local cm='[{"body":"noted","author_association":"OWNER"}'
  if (( ! noact )); then
    local assoc=OWNER; (( untrustedact )) && assoc=NONE
    cm="$cm,{\"body\":\"activated\\nS2-ACTIVATED: $act_iso\",\"author_association\":\"$assoc\"}"
  fi
  (( deact )) && cm="$cm,{\"body\":\"S2-DEACTIVATED: $(date -u -d "@$((act_epoch + 3600))" +%Y-%m-%dT%H:%M:%SZ)\",\"author_association\":\"OWNER\"}"
  case "$marker" in
    yes)         cm="$cm,{\"body\":\"exit census\\nS2-EXIT-CENSUS: https://github.com/jikig-ai/soleur/issues/4242#issuecomment-1\",\"author_association\":\"MEMBER\"}" ;;
    mid)         cm="$cm,{\"body\":\"we will post an S2-EXIT-CENSUS: https://github.com/x later\",\"author_association\":\"OWNER\"}" ;;
    untrusted)   cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://github.com/x/y\",\"author_association\":\"NONE\"}" ;;
    nonurl)      cm="$cm,{\"body\":\"S2-EXIT-CENSUS: see-my-notes\",\"author_association\":\"OWNER\"}" ;;
    placeholder) cm="$cm,{\"body\":\"S2-EXIT-CENSUS: <url>\",\"author_association\":\"OWNER\"}" ;;
  esac
  printf '%s]\n' "$cm" > "$fx/comments-4242.json"
}

# expect <label> <want-rc> <want-text> <fx> [env...]  — runs $PROBE_UNDER (default the live probe)
PROBE_UNDER="$PROBE"
expect() {
  local label="$1" want="$2" text="$3" fx="$4"; shift 4
  local out rc
  out="$(env FX="$fx" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$fx/ADR-276-fixture.md" SOAK_TEST_ALL="$fx/test-all.sh" "$@" bash "$PROBE_UNDER" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" && "$out" == *"$text"* ]]; then pass "$label (rc=$rc)"; else fail "$label: want rc=$want containing '$text', got rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}

# 25 runs: 10 elided at 510 s + 15 full at 2568 s => total 43620 s => exactly 29.08 min/run (the limit, a must-PASS)
r_pass()      { build_fx "$TMP/c1" 10 15 510 2568;                  expect "PASS: 10 elided, 12 days, mean exactly 29.08, marker present, decoy jobs ignored" 0 "PASS" "$TMP/c1"; }
r_zero()      { build_fx "$TMP/c2" 0 25 510 2568;                   expect "NOT YET: zero elided runs is never a pass" 2 "NOT YET: 0 elided" "$TMP/c2"; }
r_unmatched1(){ build_fx "$TMP/c3" 10 15 510 2568 unmatched=1;      expect "FAIL: an elided run with no merge_group voucher" 1 "no completed success merge_group run" "$TMP/c3"; }
r_unmatched3(){ build_fx "$TMP/c4" 10 15 510 2568 unmatched=3;      expect "FAIL: a second and third unvouched run after a compliant first" 1 "3 elided push run" "$TMP/c4"; }
r_over()      { build_fx "$TMP/c5" 10 15 510 2569;                  expect "FAIL: mean 29.0801 over ALL runs (one second over the limit)" 1 "mean" "$TMP/c5"; }
r_allmean()   { build_fx "$TMP/c6" 10 20 510 4200;                  expect "FAIL: the mean is over ALL runs; the elided-only mean (8.5) would pass" 1 "over 29.08" "$TMP/c6"; }
r_nomarker()  { build_fx "$TMP/c7" 10 15 510 2568 marker=none;      expect "NOT YET: no S2-EXIT-CENSUS marker (the sweeper closes on exit 0)" 2 "S2-EXIT-CENSUS" "$TMP/c7"; }
r_nine()      { build_fx "$TMP/c8" 9 16 510 2568;                   expect "NOT YET: 9 elided runs" 2 "9 elided" "$TMP/c8"; }
r_six()       { build_fx "$TMP/c9" 10 15 510 2568 actdays=6;        expect "NOT YET: 6 days since activation" 2 "6 day" "$TMP/c9"; }
r_seven()     { build_fx "$TMP/c10" 10 15 510 2568 actdays=7;       expect "boundary: exactly 7 days PASSES" 0 "PASS" "$TMP/c10"; }
r_precedence(){ build_fx "$TMP/c11" 3 20 510 2568 unmatched=1 actdays=2 marker=none; expect "FAIL takes precedence over NOT YET (wrong elision with too few runs, days, no marker)" 1 "FAIL" "$TMP/c11"; }
r_jobsfail()  { build_fx "$TMP/c12" 10 15 510 2568 failjobs;        expect "CANNOT ESTABLISH: a jobs read fails" 3 "CANNOT ESTABLISH" "$TMP/c12"; }
r_decoy_mixed(){ build_fx "$TMP/c13" 10 15 510 2568 extra=mixed;    expect "PASS: a run with mixed skipped/success test-scripts legs is NOT elided" 0 "elided=10 " "$TMP/c13"; }
r_decoy_nots() { build_fx "$TMP/c14" 10 15 510 2568 extra=nots;     expect "PASS: a run with no test-scripts job at all is NOT elided" 0 "elided=10 " "$TMP/c14"; }
r_decoy_pdred(){ build_fx "$TMP/c15" 10 15 510 2568 extra=pdred;    expect "PASS: skipped test-scripts with a RED push-dedupe is NOT elided" 0 "elided=10 " "$TMP/c15"; }
r_untrusted_act(){ build_fx "$TMP/d4" 0 25 510 2568 untrustedact;   expect "NOT YET: an activation comment by a NONE-association commenter is ignored" 2 "not activated" "$TMP/d4"; }
r_untrusted_act_elided(){ build_fx "$TMP/d5" 5 20 510 2568 untrustedact; expect "FAIL: elided runs while only an untrusted activation exists" 1 "no activation on record" "$TMP/d5"; }
r_untrusted_marker(){ build_fx "$TMP/d6" 10 15 510 2568 marker=untrusted; expect "NOT YET: an exit-census marker by an untrusted commenter does not count" 2 "S2-EXIT-CENSUS" "$TMP/d6"; }
r_nonurl_marker(){ build_fx "$TMP/d6b" 10 15 510 2568 marker=nonurl; expect "NOT YET: an exit-census marker without an https github URL does not count" 2 "S2-EXIT-CENSUS" "$TMP/d6b"; }
r_adr_proposed(){ build_fx "$TMP/d12" 10 15 510 2568 adr=proposed;  expect "FAIL: elided runs while ADR-276 still reads proposed" 1 "'proposed'" "$TMP/d12"; }
r_unregistered(){ build_fx "$TMP/d13" 10 15 510 2568 noreg;         expect "FAIL: the proof suite is no longer registered in test-all.sh" 1 "no longer registered" "$TMP/d13"; }
r_stuck29()   { build_fx "$TMP/d14" 4 21 510 2568 actdays=29;       expect "NOT YET: 29 days active with 4 elided runs (the deadline is 30)" 2 "4 elided" "$TMP/d14"; }
r_stuck30()   { build_fx "$TMP/d15" 4 21 510 2568 actdays=30;       expect "FAIL: 30 days active and the proof is not eliding" 1 "proof is not eliding" "$TMP/d15"; }
r_nonactive_deadline(){ build_fx "$TMP/d7" 0 25 510 2568 noact;     expect "FAIL: 30 days after the merge and nothing activated: activate, or revert" 1 "activate, or revert" "$TMP/d7" SOAK_NOW_EPOCH=$((NOW_EPOCH + 31 * 86400)); }
r_deact()     { build_fx "$TMP/d16" 0 25 510 2568 deact;            expect "NOT YET: a later S2-DEACTIVATED ends the activation" 2 "not activated" "$TMP/d16"; }
r_commentsfail(){ build_fx "$TMP/e-c" 10 15 510 2568 failcomments;  expect "CANNOT ESTABLISH: the tracker comments read fails (403)" 3 "CANNOT ESTABLISH" "$TMP/e-c"; }
ALL_ROWS=(r_pass r_zero r_unmatched1 r_unmatched3 r_over r_allmean r_nomarker r_nine r_six r_seven r_precedence r_jobsfail
          r_decoy_mixed r_decoy_nots r_decoy_pdred r_untrusted_act r_untrusted_act_elided r_untrusted_marker r_nonurl_marker
          r_adr_proposed r_unregistered r_stuck29 r_stuck30 r_nonactive_deadline r_deact r_commentsfail)
run_rows() { local r; for r in "$@"; do "$r"; done; }
run_rows "${ALL_ROWS[@]}"

# --- the rest of the contract (not mutated below) -----------------------------------------------------------------
build_fx "$TMP/d1" 5 20 510 2568 noact;                 expect "FAIL: elided runs with nothing activated on the tracker (an org-level or unrecorded flip)" 1 "no activation on record" "$TMP/d1"
build_fx "$TMP/d2" 10 15 510 2568 early=2;              expect "FAIL: two runs elided BEFORE the recorded activation" 1 "2 push run" "$TMP/d2"
build_fx "$TMP/d3" 0 25 510 2568 noact;                 expect "NOT YET: not activated, nothing elided" 2 "not activated" "$TMP/d3"
build_fx "$TMP/d8" 10 15 510 2568 unmerged;             expect "NOT YET: the S2 PR is not merged" 2 "not merged" "$TMP/d8"
build_fx "$TMP/d9" 10 15 510 2568 marker=mid;           expect "NOT YET: the marker must start a line, a mention does not count" 2 "S2-EXIT-CENSUS" "$TMP/d9"
build_fx "$TMP/d9b" 10 15 510 2568 marker=placeholder;  expect "NOT YET: the literal placeholder S2-EXIT-CENSUS: <url> does not count" 2 "S2-EXIT-CENSUS" "$TMP/d9b"
build_fx "$TMP/d10" 10 15 510 2568 noissue;             expect "NOT YET: the tracker is not among the open follow-through issues" 2 "tracker issue" "$TMP/d10"
build_fx "$TMP/d11" 10 15 510 2568 pdred;               expect "PASS: a full run whose push-dedupe is red is a normal full run, not a wrong elision" 0 "PASS" "$TMP/d11"
build_fx "$TMP/d17" 10 15 510 2568 adr=adopting;        expect "PASS: ADR-276 reading adopting allows the soak to pass" 0 "adr_status=adopting" "$TMP/d17"
for r in push mg; do
  build_fx "$TMP/e-$r" 10 15 510 2568 "fail$r"
                                                        expect "CANNOT ESTABLISH: the $r read fails (never a pass, never a fail)" 3 "CANNOT ESTABLISH" "$TMP/e-$r"
done
build_fx "$TMP/e1" 10 15 510 2568;                      expect "an unset GH_TOKEN is CANNOT ESTABLISH, never a pass" 3 "GH_TOKEN is not set" "$TMP/e1" GH_TOKEN=
build_fx "$TMP/e2" 10 15 510 2568
out="$(env FX="$TMP/e2" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/e2/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/e2/test-all.sh" bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi
# the query shapes the probe documents: the push window, the exact jobs read, open-only tracker lookup, and a
# merge_group window anchored one day before the OLDEST sampled run (the oldest of c1's runs is act+1h)
_act=$((NOW_EPOCH - 12 * 86400)); _bound="$(date -u -d "@$((_act + 3600 - 86400))" +%Y-%m-%dT%H:%M:%SZ)"
if grep -cF 'created=%3E2026-10-10T00:00:00Z' "$TMP/c1/requests.log" >/dev/null && grep -cF 'branch=main&status=completed' "$TMP/c1/requests.log" >/dev/null \
   && grep -cF "event=merge_group&per_page=100&created=%3E$_bound" "$TMP/c1/requests.log" >/dev/null \
   && grep -cF '/jobs?per_page=100&filter=latest' "$TMP/c1/requests.log" >/dev/null \
   && grep -cF 'issues?labels=follow-through&state=open&per_page=100' "$TMP/c1/requests.log" >/dev/null; then pass "the queries carry their documented parameters (push window, merge_group bound, jobs filter, open tracker)"
else fail "the queries lost their parameters: $(head -6 "$TMP/c1/requests.log" | tr '\n' '|')"; fi

# --- mutation rows: each mutated COPY of the probe must turn at least one named row red ----------------------------------
MUT_RUN=0; MUT_CAUGHT=0
mutant() { # <name> <old> <new> <row ids...>
  local name="$1" old="$2" new="$3"; shift 3
  MUT_RUN=$((MUT_RUN + 1))
  local f="$TMP/mut-$name.sh"
  if ! python3 - "$PROBE" "$f" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  then fail "MUTANT $name: mutation did NOT land"; return; fi
  cmp -s "$f" "$PROBE" && { fail "MUTANT $name: byte-identical to the probe"; return; }
  chmod +x "$f"
  PROBE_UNDER="$f"; core_rows_quiet "$@"; PROBE_UNDER="$PROBE"
  if [ "$MUT_REDS" -gt 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "MUTANT $name turned $MUT_REDS named row(s) red"
  else fail "MUTANT $name: none of rows [$*] went red"; fi
}
core_rows_quiet() { # run the named rows against $PROBE_UNDER, counting reds without recording them as this suite's failures
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]}
  run_rows "$@" >/dev/null
  MUT_REDS=$((fails - f0))
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}")
}
mutant m-min-elided   '(( elided < MIN_ELIDED || age_days < MIN_DAYS ))' '(( 0 ))' r_nine r_six r_zero
mutant m-no-voucher   'if ! [ "${covered:-0}" -gt 0 ] 2>/dev/null; then' 'if false; then' r_unmatched1 r_unmatched3
mutant m-first-only   'elided=$((elided + 1))' 'elided=$((elided + 1)); [ "$elided" -gt 1 ] && continue' r_unmatched3
mutant m-elided-mean  'n=$((n + 1)); total_s=$((total_s + secs))' 'n=$((n + 1)); [ "$is_elided" = "yes" ] && total_s=$((total_s + secs))' r_allmean r_over
mutant m-boundary     'total_s * 100 > MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n' 'total_s * 100 >= MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n' r_pass
mutant m-api-quiet    'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }' 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 0; }' r_jobsfail r_commentsfail
mutant m-precedence   'if (( wrong > 0 )); then' 'if (( wrong > 0 && ${age_days:-0} >= 7 )); then' r_precedence r_unmatched1
mutant m-no-marker    'if (( census_marked == 0 )); then' 'if false; then' r_nomarker r_untrusted_marker r_nonurl_marker
mutant m-unmatched-ok 'covered="$(jq -r --arg sha "$sha" '"'"'map(select(. == $sha)) | length'"'"' <<<"$mg_json" 2>/dev/null)" || fail_api "voucher lookup"' 'covered=1' r_unmatched1
mutant m-trusted      'IN("OWNER", "MEMBER", "COLLABORATOR")' 'IN("OWNER", "MEMBER", "COLLABORATOR", "NONE")' r_untrusted_act r_untrusted_marker
mutant m-adr-status   '[ "$adr_status" = "proposed" ]' '[ "$adr_status" = "never" ]' r_adr_proposed
mutant m-registered   'if (( suite_registered == 0 )); then' 'if false; then' r_unregistered
mutant m-stuck-deadline 'if (( age_days >= DEADLINE_DAYS )); then' 'if false; then' r_stuck30
mutant m-ts-any       '($ts | all(.conclusion == "skipped"))' '($ts | any(.conclusion == "skipped"))' r_decoy_mixed
mutant m-ts-empty     '($ts | length) > 0 and ' '' r_decoy_nots
mutant m-pd-success   '$pd > 0 and ' '' r_decoy_pdred
mutant m-skipped-filter '.conclusion != "skipped" and ((.runner_id' '((.runner_id' r_pass
mutant m-runner-type  '((.runner_id | type) == "number") and .runner_id > 0 and ' '' r_pass
mutant m-negdur       ' | select(. >= 0)' '' r_over
mutant m-deact        'if [ "$on_epoch" -gt "$off_epoch" ]; then' 'if true; then' r_deact
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -ge 20 ]; then pass "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 20)"; fi

# the request-shape mutants cannot reach a row's EXIT CODE (the fake gh answers any well-formed jobs path), so they are
# pinned by the requests.log assertion above: drop each parameter from a copy and confirm the assertion text no longer holds
_shape_bad=""
for pair in "jobs?per_page=100&filter=latest|jobs?per_page=100" "state=open&per_page=100|state=all&per_page=100" "oldest_epoch - 86400|oldest_epoch + 864000"; do
  old="${pair%%|*}"; new="${pair#*|}"
  python3 - "$PROBE" "$TMP/shape.sh" "$old" "$new" <<'PY' || { _shape_bad="$_shape_bad nolanding($old)"; continue; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/shape.sh"
  build_fx "$TMP/shp" 10 15 510 2568
  # the shimmed gh rejects the mutated endpoint shapes (exit 64), so the probe cannot read: CANNOT ESTABLISH, never a pass
  out="$(env FX="$TMP/shp" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/shp/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/shp/test-all.sh" bash "$TMP/shape.sh" 2>&1)"; rc=$?
  case "$old" in
    oldest_epoch*) # the fake gh does no server-side filtering: the window bound shows only in the request it was sent
      grep -cF "event=merge_group&per_page=100&created=%3E$_bound" "$TMP/shp/requests.log" >/dev/null && _shape_bad="$_shape_bad window-unchanged($new)" ;;
    *) [ "$rc" != 0 ] || _shape_bad="$_shape_bad passes($new)" ;;
  esac
done
if [ -z "$_shape_bad" ]; then pass "request-shape mutants (jobs filter dropped, tracker state widened) are refused by the fake gh, never a pass"; else fail "request-shape mutants survived:$_shape_bad"; fi

# harness row: a probe that always exits 0 must be refused by the named rows (the rows can fail)
printf '#!/usr/bin/env bash\necho PASS\nexit 0\n' > "$TMP/always-pass.sh"; chmod +x "$TMP/always-pass.sh"
PROBE_UNDER="$TMP/always-pass.sh"; core_rows_quiet "${ALL_ROWS[@]}"; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -ge 15 ]; then pass "HARNESS: an always-PASS probe turns $MUT_REDS rows red"; else fail "HARNESS: an always-PASS probe turned only $MUT_REDS rows red"; fi

printf 'ci-push-dedupe-soak-9512: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
# DELIBERATELY NOT ROUTED THROUGH fail(): compares against a literal and exits directly.
_total=$((passes + fails))
_FLOOR=63
if [ "$_total" -lt "$_FLOOR" ]; then
  printf '[FATAL] assertion floor: executed %d < %d\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
exit $(( ${#FAILURES[@]} > 0 ))
