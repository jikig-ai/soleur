#!/usr/bin/env bash
# Fixture suite for the #9905 follow-through probe (bearer-curl-s4-first-runs-9905.sh).
#
# The probe reads GitHub run lists, run jobs and run logs through `gh`. Here a stub `gh` on a scratch
# PATH replays fixture files and EXITS 64 on any request shape it does not expect, so a probe that
# starts asking for something else turns a row red instead of being answered by accident.
#
# What the rows pin:
#   * the marker is matched only as an EMITTED log line (job TAB step TAB timestamp, then the marker
#     as the whole text). The false-FAIL regression: GitHub echoes a step's `run:` source into the
#     log, the inline wrappers carry the marker as literal text in that source, and an unanchored
#     pattern then fails the merge's own healthy release run;
#   * a run counts as exercised only when every required (job, step) pair CONCLUDED success: a
#     workflow that succeeded with its converted step skipped is not evidence;
#   * the wait-deadline arm (NOT YET before it, ACTION REQUIRED at or after it), the sampling bounds
#     (newest 6 logs, newest 20 jobs reads), the CANNOT ESTABLISH arms (gh failure, hang, budget,
#     unexpected shape), the xtrace refusal, and the table's agreement with the committed workflows;
#   * each rule is MUTATED out of a scratch copy of the probe and a row must go red.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): every run id and timestamp is made up.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/bearer-curl-s4-first-runs-9905.sh"

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

# --- instrument self-test: drive both counters once and refuse to continue unless both moved. ---
# A suite whose helpers are inert reports a clean run having asserted nothing. Reported with
# printf + exit, not through the helpers it checks.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path, EXPECTED and discounted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'harness: instrument self-test did not move both counters (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0
echo "--- instrument verified; counters reset ---"

[[ -f "$PROBE" ]] || abort "the probe is missing at $PROBE"
command -v jq >/dev/null || abort "jq is required for the fixture stub"

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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

ROOT="$(mktemp -d "${TMPDIR:-/var/tmp}/bc-s4-9905.XXXXXXXX")" || abort "mktemp -d failed"
assert_fixture_dir "$ROOT"
[[ -d "$ROOT" && ! -L "$ROOT" ]] || abort "scratch root is not a plain directory: $ROOT"
readonly ROOT
trap 'rm -rf -- "$ROOT"' EXIT
STUBDIR="$ROOT/bin"
OUT="$ROOT/out.txt"
ERR="$ROOT/err.txt"
mkdir -p "$STUBDIR" "$ROOT/home" "$ROOT/tmp"

# ---------------------------------------------------------------------------------------------
# The stub gh. Unknown request shape => exit 64 and a line in $FX/unexpected.
#   pr view 9893 --json mergedAt --jq EXPR      -> $FX/pr.json
#   run list --workflow WF --status completed -L 100 --json databaseId,createdAt --jq EXPR
#                                               -> $FX/list/WF
#   run view ID --log                           -> $FX/log/ID
#   run view ID --json jobs                     -> $FX/jobs/ID.json
# Switches: $FX/gh_hang (sleep), $FX/gh_fail_on (fail when the argument line contains its content).
# ---------------------------------------------------------------------------------------------
cat > "$STUBDIR/gh" <<'STUB'
#!/usr/bin/env bash
FX="${FX:?}"
printf '%s\n' "$*" >> "$FX/calls.log"
unexpected() { printf '%s\n' "$*" >> "$FX/unexpected"; echo "stub gh: unexpected request: $*" >&2; exit 64; }
if [[ -f "$FX/gh_hang" ]]; then sleep 30; exit 0; fi
if [[ -f "$FX/gh_fail_on" ]]; then
  needle="$(<"$FX/gh_fail_on")"
  if [[ "$*" == *"$needle"* ]]; then echo "stub gh: injected failure" >&2; exit 1; fi
fi
group="${1:-} ${2:-}"
[[ $# -ge 2 ]] || unexpected "$@"
shift 2
wf="" status="" limit="" json="" jq_expr="" want_log=0 pos=()
while (( $# )); do
  case "$1" in
    --workflow) wf="${2:-}"; shift 2 ;;
    --status) status="${2:-}"; shift 2 ;;
    -L) limit="${2:-}"; shift 2 ;;
    --json) json="${2:-}"; shift 2 ;;
    --jq) jq_expr="${2:-}"; shift 2 ;;
    --log) want_log=1; shift ;;
    -*) unexpected "$group" "$@" ;;
    *) pos+=("$1"); shift ;;
  esac
done
emit() { # emit <file>
  [[ -f "$1" ]] || unexpected "$group" "missing fixture $1"
  if [[ -n "$jq_expr" ]]; then jq -r "$jq_expr" "$1"; else cat "$1"; fi
}
case "$group" in
  "pr view")
    [[ "${pos[*]}" == "9893" && "$json" == "mergedAt" ]] || unexpected "$group" "${pos[@]}" "$json"
    emit "$FX/pr.json" ;;
  "run list")
    [[ ${#pos[@]} -eq 0 && "$status" == "completed" && "$limit" == "100" && "$json" == "databaseId,createdAt" && -n "$wf" ]] \
      || unexpected "$group" "wf=$wf status=$status limit=$limit json=$json"
    emit "$FX/list/$wf" ;;
  "run view")
    [[ ${#pos[@]} -eq 1 && "${pos[0]}" =~ ^[0-9]+$ ]] || unexpected "$group" "${pos[@]}"
    if (( want_log )); then
      [[ -z "$json" ]] || unexpected "$group" "log+json"
      emit "$FX/log/${pos[0]}"
    else
      [[ "$json" == "jobs" && -z "$jq_expr" ]] || unexpected "$group" "json=$json"
      emit "$FX/jobs/${pos[0]}.json"
    fi ;;
  *) unexpected "$group" "$@" ;;
esac
STUB
chmod +x "$STUBDIR/gh"

# ---------------------------------------------------------------------------------------------
# Fixture model.
# ---------------------------------------------------------------------------------------------
MERGED="2026-10-12T09:30:00Z"
T_OLD="2026-10-11T00:00:00Z"   # before the merge
TS="2026-10-13T09:47:06.9957172Z"
DEADLINE_EPOCH="$(date -u -d "$MERGED + 30 days" +%s)"
# "Now" is pinned one day after the merge in every row (BC_S4_NOW_EPOCH), so no row depends on the
# wall clock and the suite does not rot when the real date passes the deadline.
NOW_EPOCH="$(date -u -d "$MERGED + 1 day" +%s)"
ESC=$'\033'

# Concrete names, as `gh run view --json jobs` reports them for the committed workflows (measured on
# real runs 2026-10-10). Independent of the probe's regex table: if the probe's table stops matching
# these, the all-exercised rows go red.
CONC='scheduled-inngest-health.yml|probe|Run set -uo pipefail
apply-inngest-rls.yml|apply|Apply lockdown + authoritative verification
apply-deploy-pipeline-fix.yml|apply|Capture pre-apply infra-config frame (#7104)
apply-deploy-pipeline-fix.yml|apply|Verify webhook is alive post-apply
apply-deploy-pipeline-fix.yml|apply|Verify infra-config apply succeeded
apply-web-platform-infra.yml|apply|Verify tunnel ingress origins are live and origin-relative
web-platform-release.yml|deploy|Deploy via webhook
web-platform-release.yml|deploy|Verify deploy script completion
build-inngest-bootstrap-image.yml|bump-cloud-init-pin|Bump the cloud-init pin
mint-inngest-bootstrap-tag.yml|mint|Mint soleur-infra App token (actions:write on soleur)
apply-github-infra.yml|apply|Mint soleur-infra App token (administration:write on soleur-marketplace)
apply-github-infra.yml|apply|Revoke the soleur-infra token
restart-inngest-server.yml|restart|Trigger restart via webhook
restart-inngest-server.yml|restart|Verify restart completion
deploy-inngest-image.yml|deploy|Trigger deploy via webhook
deploy-inngest-image.yml|deploy|Verify deploy completion
workspaces-luks-cutover.yml|cutover|Run workspaces-luks cutover
git-data-cutover.yml|cutover|Same-version redeploy of the web fleet (/hooks/deploy fan-out)'

WFS=()
while IFS='|' read -r w _; do
  [[ " ${WFS[*]:-} " == *" $w "* ]] || WFS+=("$w")
done <<<"$CONC"

FXN=0
FX=""
NEXT_ID=1000
LAST_ID=0
RC=0
RCS=" "

fx_new() {
  FXN=$((FXN + 1))
  FX="$ROOT/fx$FXN"
  assert_fixture_dir "$FX"
  mkdir -p "$FX/list" "$FX/rows" "$FX/log" "$FX/jobs"
  : > "$FX/calls.log"
  printf '{"mergedAt":"%s"}\n' "$MERGED" > "$FX/pr.json"
  local wf
  for wf in "${WFS[@]}"; do
    printf '[]\n' > "$FX/list/$wf"
    : > "$FX/rows/$wf"
  done
}

# fx_put <path-under-$FX> <content>: write one fixture file, guarded.
fx_put() { local f="$FX/$1"; assert_fixture_dir "$f"; printf '%s\n' "$2" > "$f"; }
# fx_reset_wf <wf>: an empty run list (and no recorded rows) for one workflow.
fx_reset_wf() { local l="$FX/list/$1" r="$FX/rows/$1"; assert_fixture_dir "$l"; assert_fixture_dir "$r"; printf '[]\n' > "$l"; : > "$r"; }
# fx_clear_rows <wf>: forget the recorded rows (the next add_run rebuilds the list from them).
fx_clear_rows() { local r="$FX/rows/$1"; assert_fixture_dir "$r"; : > "$r"; }

# line <job> <step> <text>: one GitHub-shaped log line.
line() { printf '%s\t%s\t%s %s\n' "$1" "$2" "$TS" "$3"; }

# mk_log <file> <mode>. Modes: plain | echo (echoed source only) | marker | marker-cr | marker-cc
#   | decoy-indent | decoy-mid | decoy-raw.
mk_log() {
  local f="$1" mode="$2" j="deploy" s="Deploy via webhook" bom=$'\xef\xbb\xbf'
  assert_fixture_dir "$f"
  {
    printf '%s\t%s\t%s2026-10-13T09:46:49.1121980Z Current runner version: %s\n' "$j" "Set up job" "$bom" "'2.337.0'"
    line "$j" "$s" "##[group]Run bash deploy.sh"
    case "$mode" in
      plain) : ;;
      decoy-indent) line "$j" "$s" '  echo "SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape" >&2' ;;
      decoy-mid) line "$j" "$s" '::error::mint: the exchange did not complete (a SOLEUR_CREDENTIAL_REFUSED script=mint reason=token_shape line above means the JWT was refused)' ;;
      decoy-raw) printf 'SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape\n' ;;
      *)
        # The echoed `run:` source: colourised and indented, exactly as GitHub prints it.
        line "$j" "$s" "${ESC}[36;1m  echo \"SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape\" >&2${ESC}[0m"
        line "$j" "$s" "${ESC}[36;1m  grep -m1 '^SOLEUR_CREDENTIAL_REFUSED' \"\$BS_ERR\" >&2 || true${ESC}[0m"
        line "$j" "$s" "${ESC}[36;1m    _bearer_ok \"\${X:-}\" || { echo \"SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape\" >&2; return 2; }${ESC}[0m"
        line "$j" "$s" '::error::mint-infra-app-token: the exchange did not complete (a SOLEUR_CREDENTIAL_REFUSED script=mint reason=token_shape line above means the JWT was refused)'
        ;;
    esac
    line "$j" "$s" "##[endgroup]"
    case "$mode" in
      marker) line "$j" "$s" 'SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape' ;;
      marker-cc) line "$j" "$s" 'SOLEUR_CREDENTIAL_REFUSED script=mint-infra-app-token reason=control_char' ;;
      marker-cr) printf '%s\t%s\t%s %s\r\n' "$j" "$s" "$TS" 'SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape' ;;
    esac
    line "$j" "Complete job" "Cleaning up orphan processes"
  } > "$f"
}

# jobs_for <wf> <mode>: the jobs JSON of a run. Modes: ok | skip-all | skip-first | drop-last | wrongjob | failure.
jobs_for() {
  local wf="$1" mode="$2" n=0 total w job step concl jname
  total="$(grep -c "^$wf|" <<<"$CONC")"
  while IFS='|' read -r w job step; do
    [[ "$w" == "$wf" ]] || continue
    n=$((n + 1))
    concl=success
    jname="$job"
    case "$mode" in
      ok) : ;;
      skip-all) concl=skipped ;;
      skip-first) if (( n == 1 )); then concl=skipped; fi ;;
      drop-last) if (( n == total )); then continue; fi ;;
      wrongjob) jname="other-job" ;;
      failure) concl=failure ;;
    esac
    printf '%s\tSet up job\tsuccess\n' "$jname"
    printf '%s\t%s\t%s\n' "$jname" "$step" "$concl"
  done <<<"$CONC" | jq -R -s -c '[split("\n")[] | select(length > 0) | split("\t")] | group_by(.[0])
    | {jobs: map({name: .[0][0], conclusion: "success", steps: map({name: .[1], conclusion: .[2]})})}'
}

# add_run <wf> <created> <jobs-mode> <log-mode>: sets LAST_ID.
add_run() {
  local wf="$1" created="$2" jmode="$3" lmode="$4"
  assert_fixture_dir "$FX"
  NEXT_ID=$((NEXT_ID + 1))
  LAST_ID="$NEXT_ID"
  jq -nc --argjson id "$LAST_ID" --arg c "$created" '{databaseId: $id, createdAt: $c}' >> "$FX/rows/$wf"
  jq -s -c '.' "$FX/rows/$wf" > "$FX/list/$wf"
  jobs_for "$wf" "$jmode" > "$FX/jobs/$LAST_ID.json"
  mk_log "$FX/log/$LAST_ID" "$lmode"
}

# fx_all_ok: every workflow has one exercised run since the merge, with an echo-heavy but clean log.
fx_all_ok() {
  fx_new
  local wf
  for wf in "${WFS[@]}"; do add_run "$wf" "2026-10-13T00:00:00Z" ok echo; done
}

run_probe() { # run_probe [VAR=value ...]; honours PROBE_UNDER_TEST
  assert_fixture_dir "$OUT"
  assert_fixture_dir "$ERR"
  env -i PATH="$STUBDIR:$PATH" HOME="$ROOT/home" TMPDIR="$ROOT/tmp" FX="$FX" BC_S4_NOW_EPOCH="$NOW_EPOCH" "$@" \
    bash "${PROBE_UNDER_TEST:-$PROBE}" > "$OUT" 2> "$ERR"
  RC=$?
  RCS="$RCS$RC "
  if [[ -e "$FX/unexpected" ]]; then
    cases=$((cases + 1))
    fail "the stub saw a request shape it does not expect: $(head -c 160 "$FX/unexpected")"
  fi
}

expect_rc() { # expect_rc <label> <want>
  cases=$((cases + 1))
  if [[ "$RC" == "$2" ]]; then pass "$1 (rc=$RC)"; else fail "$1: want rc=$2, got rc=$RC; out: $(head -c 200 "$OUT") err: $(head -c 120 "$ERR")"; fi
}
expect_out() { # expect_out <label> <substring>
  local got; got="$(<"$OUT")$(<"$ERR")"
  cases=$((cases + 1))
  if [[ "$got" == *"$2"* ]]; then pass "$1"; else fail "$1: output lacks '$2': $(head -c 240 <<<"$got")"; fi
}
expect_not_out() { # expect_not_out <label> <substring>
  local got; got="$(<"$OUT")$(<"$ERR")"
  cases=$((cases + 1))
  if [[ "$got" != *"$2"* ]]; then pass "$1"; else fail "$1: output wrongly carries '$2'"; fi
}
expect_num() { # expect_num <label> <got> <want>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1 ($2)"; else fail "$1: want $3, got $2"; fi
}
count_calls() { # count_calls <exact-line>
  local n; n="$(grep -cxF -- "$1" "$FX/calls.log")" || true
  printf '%s' "${n:-0}"
}
count_matching() { # count_matching <ERE>
  local n; n="$(grep -cE -- "$1" "$FX/calls.log")" || true
  printf '%s' "${n:-0}"
}

echo "bearer-curl-s4-first-runs-9905 probe:"

# --- 0. the stub itself --------------------------------------------------------------------------
fx_new
env -i PATH="$PATH" FX="$FX" "$STUBDIR/gh" repo view > /dev/null 2>&1
expect_num "the stub refuses a request shape it does not expect (exit 64)" "$?" "64"

# --- 1. not merged / PR read -----------------------------------------------------------------------
fx_all_ok
fx_put pr.json '{"mergedAt":null}'
run_probe
expect_rc "an unmerged PR is NOT YET" 2
expect_num "an unmerged PR lists no runs" "$(count_matching '^run list ')" "0"

fx_all_ok
fx_put gh_fail_on 'pr view'
run_probe
expect_rc "a failing PR read is CANNOT ESTABLISH" 3

fx_all_ok
fx_put pr.json '{"mergedAt":"yesterday"}'
run_probe
expect_rc "an unexpected mergedAt shape is CANNOT ESTABLISH" 3

# --- 2. the false-FAIL regression: echoed source text in a healthy run's log ------------------------
fx_all_ok
echoed="$(grep -cF 'SOLEUR_CREDENTIAL_REFUSED script=web-platform-release reason=token_shape' "$FX/log/$LAST_ID")" || true
cases=$((cases + 1))
if [[ "${echoed:-0}" -ge 1 ]]; then pass "the healthy fixture log carries the marker as echoed source text"; else fail "fixture is vacuous: no echoed marker text in the log"; fi
unanchored="$(grep -cE 'SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason=' "$FX/log/$LAST_ID")" || true
cases=$((cases + 1))
if [[ "${unanchored:-0}" -ge 1 ]]; then pass "the old unanchored pattern WOULD have matched that log"; else fail "fixture is vacuous: the old pattern does not match the echoed text"; fi
run_probe
expect_rc "healthy runs whose logs echo the marker in their run source: PASS, never FAIL" 0
expect_out "the PASS line is printed" "PASS:"

for decoy in decoy-indent decoy-mid decoy-raw; do
  fx_all_ok
  mk_log "$FX/log/$LAST_ID" "$decoy"
  run_probe
  expect_rc "a $decoy line is not a marker" 0
done

# --- 3. an emitted marker is FAIL -------------------------------------------------------------------
for mode in marker marker-cr marker-cc; do
  fx_all_ok
  marker_id="$LAST_ID"
  mk_log "$FX/log/$marker_id" "$mode"
  run_probe
  expect_rc "an emitted marker line ($mode) is FAIL" 1
done
expect_out "the FAIL line names the run" "FAIL:"

fx_all_ok
mk_log "$FX/log/$LAST_ID" marker
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 100))
expect_rc "a marker is FAIL even after the wait budget is spent" 1

# a marker outranks both NOT YET and a later transient failure
fx_all_ok
fx_put list/restart-inngest-server.yml '[]'
mk_log "$FX/log/$(jq -r '.[0].databaseId' "$FX/list/scheduled-inngest-health.yml")" marker
run_probe
expect_rc "a marker outranks an unexercised workflow" 1

fx_all_ok
mk_log "$FX/log/$(jq -r '.[0].databaseId' "$FX/list/scheduled-inngest-health.yml")" marker
fx_put gh_fail_on 'run list --workflow git-data-cutover.yml'
run_probe
expect_rc "a marker already found outranks a later gh failure" 1

# --- 4. the exercised check needs positive proof ------------------------------------------------------
fx_all_ok
fx_reset_wf mint-inngest-bootstrap-tag.yml
add_run mint-inngest-bootstrap-tag.yml "2026-10-13T01:00:00Z" skip-all plain
run_probe
expect_rc "a mint run that succeeded but decided noop (step skipped) is not exercised" 2
expect_out "the unexercised workflow is named" "mint-inngest-bootstrap-tag.yml"

fx_all_ok
add_run mint-inngest-bootstrap-tag.yml "2026-10-14T01:00:00Z" skip-all plain
run_probe
expect_rc "a newer noop run does not hide an older exercised run" 0

fx_all_ok
fx_reset_wf apply-github-infra.yml
add_run apply-github-infra.yml "2026-10-13T01:00:00Z" drop-last plain
run_probe
expect_rc "an apply run with no revoke step is not exercised" 2

fx_all_ok
fx_reset_wf apply-deploy-pipeline-fix.yml
add_run apply-deploy-pipeline-fix.yml "2026-10-13T01:00:00Z" skip-first plain
run_probe
expect_rc "one of three required steps skipped: not exercised" 2

fx_all_ok
fx_reset_wf apply-deploy-pipeline-fix.yml
add_run apply-deploy-pipeline-fix.yml "2026-10-13T01:00:00Z" failure plain
run_probe
expect_rc "required steps that FAILED are not exercised" 2

fx_all_ok
fx_reset_wf web-platform-release.yml
add_run web-platform-release.yml "2026-10-13T01:00:00Z" wrongjob plain
run_probe
expect_rc "the right step names in the wrong job are not exercised" 2

# --- 5. no run since the merge; the wait-deadline arm ----------------------------------------------------
fx_all_ok
fx_put list/restart-inngest-server.yml '[]'
run_probe
expect_rc "a workflow with no run, budget open: NOT YET" 2
expect_out "the no-run workflow is named" "restart-inngest-server.yml has no completed run"
expect_num "no log is downloaded for a workflow without a run" "$(count_matching ' --log$')" "11"

fx_all_ok
fx_put list/restart-inngest-server.yml '[]'
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 1))
expect_rc "a workflow with no run, budget spent: ACTION REQUIRED" 5
expect_out "ACTION REQUIRED names the workflow" "restart-inngest-server.yml"

fx_all_ok
fx_put list/restart-inngest-server.yml '[]'
run_probe BC_S4_NOW_EPOCH="$DEADLINE_EPOCH"
expect_rc "exactly at the deadline the budget is spent" 5

fx_all_ok
fx_put list/restart-inngest-server.yml '[]'
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH - 1))
expect_rc "one second before the deadline the budget is still open" 2

fx_all_ok
fx_clear_rows restart-inngest-server.yml
add_run restart-inngest-server.yml "$T_OLD" ok plain
run_probe
expect_rc "a run from BEFORE the merge does not count" 2

fx_all_ok
fx_reset_wf restart-inngest-server.yml
add_run restart-inngest-server.yml "$T_OLD" ok plain
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 1))
expect_rc "only pre-merge runs and the budget spent: ACTION REQUIRED" 5

fx_all_ok
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 1))
expect_rc "everything exercised and clean passes even after the deadline" 0

# --- 6. sampling bounds and ordering --------------------------------------------------------------------
# 8 runs of web-platform-release, ids ASCENDING with age so the newest by date has the smallest id;
# the list is served oldest-first, so only a sort by createdAt finds the right six.
fx_all_ok
fx_reset_wf web-platform-release.yml
wids=()
for d in 20 19 18 17 16 15 14 13; do
  add_run web-platform-release.yml "2026-10-${d}T00:00:00Z" ok plain
  wids+=("$LAST_ID")
done
# wids[0] is the NEWEST by date (Oct 20) but has the SMALLEST id; wids[7] is the oldest.
mk_log "$FX/log/${wids[6]}" marker
mk_log "$FX/log/${wids[7]}" marker
run_probe
expect_rc "a marker in the 7th and 8th newest runs is outside the scan bound" 0
expect_num "exactly six logs of the 8-run workflow are downloaded, plus one per other workflow" "$(count_matching ' --log$')" "17"

fx_all_ok
fx_reset_wf web-platform-release.yml
wids=()
for d in 20 19 18 17 16 15 14 13; do
  add_run web-platform-release.yml "2026-10-${d}T00:00:00Z" ok plain
  wids+=("$LAST_ID")
done
mk_log "$FX/log/${wids[5]}" marker
run_probe
expect_rc "a marker in the 6th newest run is inside the bound" 1

fx_all_ok
fx_reset_wf web-platform-release.yml
wids=()
for d in 20 19 18 17 16 15 14 13; do
  add_run web-platform-release.yml "2026-10-${d}T00:00:00Z" ok plain
  wids+=("$LAST_ID")
done
mk_log "$FX/log/${wids[0]}" marker
run_probe
expect_rc "a marker in the newest run (smallest id) is found: newest is by date, not by list order" 1

# exercised bound: 22 runs, only one satisfying run, at rank 20 / rank 21 by newness.
for rank in 20 21; do
  fx_all_ok
  fx_reset_wf apply-github-infra.yml
  gids=()
  for ((i = 1; i <= 22; i++)); do
    d=$(printf '%02d' $((30 - i)))
    if (( i == rank )); then m=ok; else m=skip-all; fi
    # day-of-month 29 down to 08 of November: strictly decreasing, so rank i is the i-th newest
    add_run apply-github-infra.yml "2026-11-${d}T00:00:00Z" "$m" plain
    gids+=("$LAST_ID")
  done
  run_probe
  jobs_reads=0
  for id in "${gids[@]}"; do jobs_reads=$((jobs_reads + $(count_calls "run view $id --json jobs"))); done
  if [[ "$rank" == 20 ]]; then
    expect_rc "an exercised run at rank 20 is found" 0
  else
    expect_rc "an exercised run at rank 21 is outside the exercised bound: NOT YET" 2
  fi
  expect_num "the jobs of at most 20 runs are read (rank $rank fixture)" "$jobs_reads" "20"
done

fx_all_ok
fx_reset_wf apply-github-infra.yml
gids=()
for d in 25 24 23 22 21; do add_run apply-github-infra.yml "2026-10-${d}T00:00:00Z" ok plain; gids+=("$LAST_ID"); done
run_probe
jobs_reads=0
for id in "${gids[@]}"; do jobs_reads=$((jobs_reads + $(count_calls "run view $id --json jobs"))); done
expect_num "the jobs reads stop at the first exercised run" "$jobs_reads" "1"

# --- 7. CANNOT ESTABLISH ---------------------------------------------------------------------------------
fx_all_ok
fx_put gh_fail_on 'run list --workflow web-platform-release.yml'
run_probe
expect_rc "a failing run list is CANNOT ESTABLISH" 3

fx_all_ok
fx_put gh_fail_on '--log'
run_probe
expect_rc "a failing log read is CANNOT ESTABLISH" 3

fx_all_ok
fx_put gh_fail_on '--json jobs'
run_probe
expect_rc "a failing jobs read is CANNOT ESTABLISH" 3

fx_all_ok
fx_put "jobs/$LAST_ID.json" 'this is not json'
run_probe
expect_rc "an unparseable jobs payload is CANNOT ESTABLISH" 3

fx_all_ok
fx_put "jobs/$LAST_ID.json" '{"jobs":null}'
run_probe
expect_rc "a jobs payload of the wrong shape is CANNOT ESTABLISH" 3

fx_all_ok
fx_put list/deploy-inngest-image.yml '[{"databaseId":"abc","createdAt":"2026-10-13T00:00:00Z"}]'
run_probe
expect_rc "a non-numeric run id is CANNOT ESTABLISH" 3

fx_all_ok
fx_put gh_hang hang
SECONDS=0
run_probe BC_S4_GH_TIMEOUT=1
expect_rc "a hanging gh call times out as CANNOT ESTABLISH" 3
cases=$((cases + 1))
if (( SECONDS < 20 )); then pass "the hang was cut by the per-call timeout (${SECONDS}s)"; else fail "the hang was not cut by the per-call timeout (${SECONDS}s)"; fi

fx_all_ok
run_probe BC_S4_BUDGET_S=0
expect_rc "a spent total budget is CANNOT ESTABLISH" 3
expect_out "the budget message names itself" "budget"

fx_all_ok
run_probe BC_S4_NOW_EPOCH=abc
expect_rc "a non-numeric BC_S4_NOW_EPOCH is CANNOT ESTABLISH" 3

# --- 8. xtrace refusal ------------------------------------------------------------------------------------
fx_all_ok
assert_fixture_dir "$OUT"
assert_fixture_dir "$ERR"
env -i PATH="$STUBDIR:$PATH" HOME="$ROOT/home" TMPDIR="$ROOT/tmp" FX="$FX" bash -x "$PROBE" > "$OUT" 2> "$ERR"
RC=$?
RCS="$RCS$RC "
expect_rc "running under xtrace is refused (EX_CONFIG)" 78
expect_num "the refused run made no gh call" "$(count_matching '.')" "0"

# --- 9. the probe's table agrees with the committed workflows --------------------------------------------
eval "$(sed -n '/^REQUIRED=(/,/^)/p' "$PROBE")"
expect_num "the probe tracks the same number of pairs as the suite's concrete table" "${#REQUIRED[@]}" "$(grep -c . <<<"$CONC")"
for req in "${REQUIRED[@]}"; do
  wf="${req%%@@*}"
  rest="${req#*@@}"
  job_re="${rest%%@@*}"
  step_re="${rest#*@@}"
  job_name="${job_re#^}"; job_name="${job_name%\$}"
  wf_file="$REPO_ROOT/.github/workflows/$wf"
  cases=$((cases + 1))
  if [[ ! -f "$wf_file" ]]; then fail "$wf: the workflow file does not exist"; continue; fi
  # the job key exists
  jobs_hit="$(grep -cE "^  ${job_name}:[[:space:]]*$" "$wf_file")" || true
  if [[ "${jobs_hit:-0}" -lt 1 ]]; then fail "$wf: no job key '$job_name'"; continue; fi
  # the step name exists; failing that, for an unnamed run step ("Run <first script line>"), the line does
  found=0
  while IFS= read -r nm; do
    nm="${nm#\"}"; nm="${nm%\"}"; nm="${nm#\'}"; nm="${nm%\'}"
    if [[ "$nm" =~ $step_re ]]; then found=1; break; fi
  done < <(sed -nE 's/^[[:space:]]*(- )?name:[[:space:]]*//p' "$wf_file")
  if (( found == 0 )) && [[ "$step_re" == '^Run '* ]]; then
    first_line="${step_re#^Run }"; first_line="${first_line%\$}"
    hit="$(grep -cE "^[[:space:]]+${first_line}[[:space:]]*$" "$wf_file")" || true
    if [[ "${hit:-0}" -ge 1 ]]; then found=1; fi
  fi
  if (( found == 1 )); then pass "$wf: '$job_name' / '$step_re' exists in the committed workflow"; else fail "$wf: no step matches $step_re (the workflow renamed it?)"; fi
done

# --- 10. mutation checks: each probe rule, mutated out of a scratch copy, must turn a row red ---------------
PRISTINE="$ROOT/probe-pristine.sh"
assert_fixture_dir "$PRISTINE"
cp "$PROBE" "$PRISTINE"

mutate() { # mutate <dst> <old> <new>; returns 1 when <old> is absent
  local content dst="$1"
  assert_fixture_dir "$dst"
  content="$(<"$PRISTINE")"
  [[ "$content" == *"$2"* ]] || return 1
  printf '%s\n' "${content/"$2"/"$3"}" > "$dst"
}

landed() { # landed <label> <mutant>: the mutant differs from the pristine copy
  cases=$((cases + 1))
  if diff -q "$PRISTINE" "$2" > /dev/null 2>&1; then fail "$1: the mutation did NOT land (identical to the pristine copy)"; else pass "$1: the mutation landed"; fi
}

# unmutated control first: the scratch copy behaves like the probe on all four discriminating fixtures
PROBE_UNDER_TEST="$PRISTINE"
fx_all_ok;                 run_probe;                                       expect_rc "control: echoed-source healthy fixture" 0
fx_all_ok
fx_reset_wf mint-inngest-bootstrap-tag.yml
add_run mint-inngest-bootstrap-tag.yml "2026-10-14T01:00:00Z" skip-all plain
run_probe;                                                                  expect_rc "control: noop-mint fixture" 2
fx_all_ok; fx_put list/restart-inngest-server.yml '[]'
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 1));                          expect_rc "control: no-run workflow after the deadline" 5
fx_all_ok; fx_reset_wf web-platform-release.yml
add_run web-platform-release.yml "2026-10-13T01:00:00Z" wrongjob plain
run_probe;                                                                  expect_rc "control: wrong-job fixture" 2

# M1: revert the anchor to the old unanchored pattern
M1="$ROOT/m1.sh"
if mutate "$M1" "MARKER_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason=[a-z_]+[[:space:]]*\$'" \
  "MARKER_RE='SOLEUR_CREDENTIAL_REFUSED script=[A-Za-z0-9._-]+ reason='"; then landed "M1 unanchored regex" "$M1"; else cases=$((cases + 1)); fail "M1: the anchor line was not found to mutate"; fi
PROBE_UNDER_TEST="$M1"
fx_all_ok; run_probe;                                                       expect_rc "M1 goes red: the echoed-source healthy run now false-FAILs" 1

# M2: drop the step-conclusion requirement
M2="$ROOT/m2.sh"
if mutate "$M2" '(.name | test($s)) and .conclusion == "success"' '(.name | test($s)) and true'; then landed "M2 no step-conclusion requirement" "$M2"; else cases=$((cases + 1)); fail "M2: the conclusion test was not found to mutate"; fi
PROBE_UNDER_TEST="$M2"
fx_all_ok
fx_reset_wf mint-inngest-bootstrap-tag.yml
add_run mint-inngest-bootstrap-tag.yml "2026-10-14T01:00:00Z" skip-all plain
run_probe;                                                                  expect_rc "M2 goes red: the noop mint now counts as exercised" 0

# M3: drop the deadline arm
M3="$ROOT/m3.sh"
if mutate "$M3" 'if (( now_epoch >= deadline_epoch )); then' 'if false; then'; then landed "M3 no deadline arm" "$M3"; else cases=$((cases + 1)); fail "M3: the deadline test was not found to mutate"; fi
PROBE_UNDER_TEST="$M3"
fx_all_ok; fx_put list/restart-inngest-server.yml '[]'
run_probe BC_S4_NOW_EPOCH=$((DEADLINE_EPOCH + 1));                          expect_rc "M3 goes red: ACTION REQUIRED is never reached" 2

# M4: drop the job-name requirement
M4="$ROOT/m4.sh"
if mutate "$M4" 'select((.name | test($j)) and ' 'select(true and '; then landed "M4 no job-name requirement" "$M4"; else cases=$((cases + 1)); fail "M4: the job-name test was not found to mutate"; fi
PROBE_UNDER_TEST="$M4"
fx_all_ok
fx_reset_wf web-platform-release.yml
add_run web-platform-release.yml "2026-10-13T01:00:00Z" wrongjob plain
run_probe;                                                                  expect_rc "M4 goes red: the wrong job now counts as exercised" 0
PROBE_UNDER_TEST=""

# --- 11. exit-code vocabulary ---------------------------------------------------------------------------------
bad_rcs=""
for r in $RCS; do
  case "$r" in 0|1|2|3|5|78) : ;; *) bad_rcs="$bad_rcs $r" ;; esac
done
cases=$((cases + 1))
if [[ -z "$bad_rcs" ]]; then pass "every probe exit was in the registered vocabulary {0,1,2,3,5,78}"; else fail "an exit outside the vocabulary occurred:$bad_rcs"; fi

# ---------------------------------------------------------------------------------------------
# Accounting and floor, reported with printf + exit rather than through fail(), which is the
# helper they exist to backstop.
# ---------------------------------------------------------------------------------------------
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'ACCOUNTING: %s assertions recorded but %s cases counted: an assertion site is unpaired\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi
MIN_ASSERTIONS=90
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf '%s passed, %s failed (%s assertions)\n' "$passes" "$fails" "$((passes + fails))"
[[ "$fails" -eq 0 ]] || exit 1
exit 0
