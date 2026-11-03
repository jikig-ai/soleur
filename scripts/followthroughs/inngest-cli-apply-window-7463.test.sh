#!/usr/bin/env bash
# Verdict matrix for inngest-cli-apply-window-7463.sh. Every row is synthetic.
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches no
# SUITE_GLOBS entry, so an unregistered .test.sh is an orphan that never gates.
#
# WHAT THIS PINS. The probe verifies #7463's apply window: a post-merge
# apply-web-platform-infra.yml dispatch whose inngest_host_replace job succeeded,
# PLUS a post-dating green scheduled-inngest-health.yml run. It must reach rc 0 on
# that pair ONLY; a replace job concluded failure/cancelled is rc 1; absent or
# in-flight evidence is rc 2; a uniformly failing per-run jobs read is rc 3
# (CANNOT-ESTABLISH) — the #9782 arm: an absent-or-null `.jobs` payload must parse
# as "no replace job in this run", never crash jq into a swallowed `|| true` that
# reports skip-forever as NOT-YET. Every arm drives the REAL probe against a
# PATH-shimmed `gh` that answers from per-arm fixture files and EXITS 64 on any
# argv it was not written for (the #7081 stub-argv-fidelity class). `jq` is the
# real binary: for `--jq` calls the shim applies the probe's own expression to the
# fixture payload, and for `--paginate` calls the probe's own jq parses the raw
# page stream the fixture carries — so a fixture can hold two page objects and the
# page-2 job still counts (the never-PASS class the paginate switch closed).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/inngest-cli-apply-window-7463.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Instrument self-test: both counters must move before any verdict is trusted.
_p0=$total; pass "instrument" >/dev/null; _f0=$fails
fail "instrument" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

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

WORK="$(mktemp -d -t icaw-7463.XXXXXXXX)"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

MERGED="2026-10-01T00:00:00Z"
T1="2026-10-05T09:00:00Z"
T2="2026-10-06T09:00:00Z"
T3="2026-10-07T09:00:00Z"

# --- the `gh` shim ----------------------------------------------------------------------
# Answers from $FX (one fixture dir per arm). Every accepted argv shape is spelled out; any
# other exits 64 and is logged, which the arms assert never happens. `--jq` calls apply the
# probe's own expression via the real jq; `--paginate` calls emit the fixture's raw page
# stream for the probe's own `jq -rs`.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/calls"
[[ -n "${GH_TOKEN:-}" ]] || { echo "shim: GH_TOKEN absent" >&2; exit 65; }
answer() { [[ -f "$FX/$1.fail" ]] && { cat "$FX/$1.fail" >&2; exit 1; }; [[ -f "$FX/$1" ]] || exit 1; cat "$FX/$1"; exit 0; }
answer_jq() { [[ -f "$FX/$1.fail" ]] && { cat "$FX/$1.fail" >&2; exit 1; }; [[ -f "$FX/$1" ]] || exit 1; jq -r "$2" "$FX/$1"; exit 0; }
if [[ "$#" -eq 3 && "$1" == api && "$2" == --paginate ]]; then
  case "$3" in
    repos/jikig-ai/soleur/actions/runs/*/jobs\?per_page=100)
      id="${3#repos/jikig-ai/soleur/actions/runs/}"; id="${id%/jobs?per_page=100}"
      answer "jobs-$id.json" ;;
  esac
fi
if [[ "$#" -eq 4 && "$1" == api && "$3" == --jq ]]; then
  case "$2" in
    repos/jikig-ai/soleur/pulls/9201)
      answer_jq pr.json "$4" ;;
    "repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml/runs?event=workflow_dispatch&branch=main&per_page=15")
      answer_jq runs.json "$4" ;;
    "repos/jikig-ai/soleur/actions/workflows/scheduled-inngest-health.yml/runs?branch=main&per_page=10")
      answer_jq health.json "$4" ;;
  esac
fi
printf 'BADARGV %s\n' "$*" >> "$FX/calls"
exit 64
SHIM
chmod +x "$WORK/bin/gh"

# --- fixture builders -------------------------------------------------------------------
# new_fx <name> — a fresh fixture dir for one arm: the PR merged at $MERGED, zero dispatch
# runs, zero health runs.
new_fx() {
  local d="$WORK/fx-$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  : > "$d/calls"
  jq -n --arg m "$MERGED" '{merged_at:$m}' > "$d/pr.json"
  printf '%s' '{"total_count":0,"workflow_runs":[]}' > "$d/runs.json"
  printf '%s' '{"total_count":0,"workflow_runs":[]}' > "$d/health.json"
}
# add_run <fx> <databaseId> <created_at> [conclusion] — append a dispatch run; call order is
# newest-first, matching the API's ordering contract.
add_run() {
  local d="$1"; assert_fixture_dir "$d"
  jq --argjson id "$2" --arg c "$3" --arg k "${4:-null}" \
    '.workflow_runs += [{databaseId:$id, created_at:$c, conclusion:(if $k == "null" then null else $k end)}]' \
    "$d/runs.json" > "$d/runs.tmp" && mv "$d/runs.tmp" "$d/runs.json"
}
# add_health <fx> <databaseId> <created_at> <conclusion|null> — append a health run.
add_health() {
  local d="$1"; assert_fixture_dir "$d"
  jq --argjson id "$2" --arg c "$3" --arg k "$4" \
    '.workflow_runs += [{databaseId:$id, created_at:$c, conclusion:(if $k == "null" then null else $k end)}]' \
    "$d/health.json" > "$d/health.tmp" && mv "$d/health.tmp" "$d/health.json"
}
# add_job <fx> <run_id> <name> <conclusion|null> — append a job to page 1 of jobs-<rid>.json.
add_job() {
  local d="$1"; assert_fixture_dir "$d"
  [[ -f "$d/jobs-$2.json" ]] || printf '%s' '{"total_count":0,"jobs":[]}' > "$d/jobs-$2.json"
  jq --arg n "$3" --arg c "$4" \
    '.jobs += [{name:$n, conclusion:(if $c == "null" then null else $c end), status:"completed"}] | .total_count = (.jobs | length)' \
    "$d/jobs-$2.json" > "$d/jobs.tmp" && mv "$d/jobs.tmp" "$d/jobs-$2.json"
}
# jobs_raw <fx> <run_id> <stream> — overwrite the page stream verbatim (multi-page docs,
# absent/null .jobs shapes, error payloads).
jobs_raw() {
  local d="$1"; assert_fixture_dir "$d"
  printf '%s' "$3" > "$d/jobs-$2.json"
}

# run_arm <fx> [extra env...] — runs the REAL probe with the shim first on PATH; prints rc.
run_arm() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  env -i PATH="$WORK/bin:/usr/local/bin:/usr/bin:/bin" HOME="$WORK" FX="$d" \
    "$@" bash "$SUT" > "$d/out" 2>&1
  echo $?
}
TOKEN="GH_TOKEN=synthetic-not-a-token"

expect() { # expect <arm> <want-rc> <got-rc> <fx>
  if [[ "$3" == "$2" ]]; then pass "$1 (rc=$3)"; else fail "$1 (expected rc=$2, got $3): $(tr '\n' ' ' < "$4/out" | cut -c1-300)"; fi
  if grep -q '^BADARGV' "$4/calls"; then fail "$1: probe sent an argv the shim does not accept: $(grep '^BADARGV' "$4/calls" | head -1)"; fi
}
expect_out() { # expect_out <arm> <fx> <fixed-string>
  if grep -qF -- "$3" "$2/out"; then pass "$1 names: $3"; else fail "$1 output lacks '$3': $(tr '\n' ' ' < "$2/out" | cut -c1-300)"; fi
}
expect_no_out() { # expect_no_out <arm> <fx> <fixed-string>
  if grep -qF -- "$3" "$2/out"; then fail "$1 output carries '$3': $(tr '\n' ' ' < "$2/out" | cut -c1-300)"; else pass "$1 output lacks: $3"; fi
}

# HELPER CANARIES: expect() and expect_out()/expect_no_out() own their verdicts, so the
# pass()/fail() self-test above cannot see them go silent. Each is driven once where it
# must fail.
_cfx="$WORK/fx-canary"; mkdir -p "$_cfx"; : > "$_cfx/calls"; printf 'canary-out\n' > "$_cfx/out"
for _c in "expect canary 0 1 $_cfx" "expect_out canary $_cfx __absent__" "expect_no_out canary $_cfx canary-out"; do
  _f0=$fails; _t0=$total
  # shellcheck disable=SC2086
  $_c >/dev/null 2>&1
  if (( fails != _f0 + 1 )); then printf 'FATAL: helper canary "%s" recorded no failure\n' "${_c%% *}" >&2; exit 1; fi
  fails=$_f0; total=$_t0
done

echo "== credentials and anchor"
fx="$WORK/fx-notoken"; new_fx notoken
expect "no GH_TOKEN -> CANNOT ESTABLISH" 3 "$(run_arm "$fx")" "$fx"

fx="$WORK/fx-xtrace"; new_fx xtrace
rc=$(env -i PATH="$WORK/bin:/usr/local/bin:/usr/bin:/bin" HOME="$WORK" FX="$fx" GH_TOKEN=synthetic-not-a-token bash -x "$SUT" > "$fx/out" 2>&1; echo $?)
expect "xtrace with GH_TOKEN -> 78" 78 "$rc" "$fx"
if ! grep -q 'synthetic-not-a-token' "$fx/out"; then pass "xtrace refusal leaks no token"; else fail "xtrace output carries the token"; fi

fx="$WORK/fx-prfail"; new_fx prfail; : > "$fx/pr.json.fail"
expect "PR read fails -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-prnull"; new_fx prnull
jq -n '{merged_at:null}' > "$fx/pr.json"
expect "merged_at null -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== dispatch enumeration"
fx="$WORK/fx-noruns"; new_fx noruns
expect "merged, zero dispatches -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "noruns" "$fx" "NOT-YET: no post-merge apply dispatches on main"

fx="$WORK/fx-runsfail"; new_fx runsfail; : > "$fx/runs.json.fail"
expect "run list read fails -> NOT YET (empty read == no dispatches)" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"

# A run carrying a successful replace job but created AT or BEFORE the merge second. The
# probe's --jq applies the strict `>` filter — either leaking through is a PASS on
# possibly-pre-merge evidence.
fx="$WORK/fx-atmerge"; new_fx atmerge
add_run "$fx" 90 "$MERGED"; add_run "$fx" 89 "2026-09-30T09:00:00Z"
for r in 90 89; do add_job "$fx" "$r" inngest_host_replace success; done
add_health "$fx" 95 "$T3" success
expect "replace run AT/before merge second is not evidence -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== per-run jobs reads (#9782)"
# Every enumerated run's jobs read fails -> CANNOT-ESTABLISH, never NOT-YET. Two runs so
# jobq_total > 1 exercises the counter, not a single-element degenerate.
fx="$WORK/fx-allfail"; new_fx allfail
add_run "$fx" 200 "$T1"; add_run "$fx" 201 "$T2"
: > "$fx/jobs-200.json.fail"; : > "$fx/jobs-201.json.fail"
expect "all per-run jobs reads fail -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "allfail" "$fx" "CANNOT-ESTABLISH: all 2 per-run job queries failed"

# A payload lacking `.jobs` entirely (error shape / drifted response): the `.jobs? // []`
# guard parses it as a valid read with zero jobs — the run is skipped, and it counts as a
# SUCCESSFUL read, so it never feeds the rc-3 arm. The uncaught `Cannot iterate over null`
# is the exact string the fix exists to kill.
fx="$WORK/fx-nojobs"; new_fx nojobs
add_run "$fx" 210 "$T1"
jobs_raw "$fx" 210 '{"total_count":1,"incomplete_results":false,"message":"drifted"}'
expect "absent .jobs payload -> skipped, NOT YET (never a jq crash)" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_no_out "nojobs" "$fx" "Cannot iterate"

# `.jobs: null` — the literal crash payload from the issue.
fx="$WORK/fx-nulljobs"; new_fx nulljobs
add_run "$fx" 211 "$T1"
jobs_raw "$fx" 211 '{"total_count":1,"jobs":null}'
expect "null .jobs payload -> skipped, NOT YET (never a jq crash)" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_no_out "nulljobs" "$fx" "Cannot iterate"

# `.jobs: []` present-but-empty — a permitted member: parses as a valid read with zero
# replace jobs, and iteration CONTINUES to the next run (an empty page must not eat the
# rest of the enumeration).
fx="$WORK/fx-emptyjobs"; new_fx emptyjobs
add_run "$fx" 220 "$T1"; add_run "$fx" 221 "$T2"
jobs_raw "$fx" 220 '{"total_count":0,"jobs":[]}'
add_job "$fx" 221 inngest_host_replace success
add_health "$fx" 295 "$T3" success
expect "empty .jobs page does not stop enumeration -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"

# Mixed: run A's jobs read fails, run B carries the evidence. A partial failure is a skip,
# not a poison — the verdict is still reachable.
fx="$WORK/fx-mixedfail"; new_fx mixedfail
add_run "$fx" 230 "$T1"; add_run "$fx" 231 "$T2"
: > "$fx/jobs-230.json.fail"
add_job "$fx" 231 inngest_host_replace success
add_health "$fx" 296 "$T3" success
expect "one failed jobs read does not poison the verdict -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"

# A dispatch for a different apply_target: jobs exist, none replace-named.
fx="$WORK/fx-othertarget"; new_fx othertarget
add_run "$fx" 240 "$T1"
add_job "$fx" 240 terraform_apply success
add_job "$fx" 240 notify success
expect "dispatch with no replace-named job is skipped -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "othertarget" "$fx" "NOT-YET: post-merge dispatches exist but none reached an inngest_host_replace job"

# The paginate contract: a replace job on PAGE 2 still counts — a single-page read would
# report NOT-YET forever on real history.
fx="$WORK/fx-page2"; new_fx page2
add_run "$fx" 250 "$T1"
jobs_raw "$fx" 250 "$(printf '%s\n%s' '{"total_count":2,"jobs":[{"name":"terraform_apply","conclusion":"success","status":"completed"}]}' '{"total_count":2,"jobs":[{"name":"inngest_host_replace","conclusion":"success","status":"completed"}]}')"
add_health "$fx" 297 "$T3" success
expect "replace job on page 2 still counts -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== verdict"
fx="$WORK/fx-pass"; new_fx pass
add_run "$fx" 260 "$T1"
add_job "$fx" 260 inngest_host_replace success
add_health "$fx" 298 "$T3" success
expect "replace success + post-dating green health -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "pass" "$fx" "PASS: inngest-host-replace applied (run 260)"

# Newest supersedes: the newest dispatch's replace job failed even though an older one
# succeeded — the newest attempt is the verdict.
fx="$WORK/fx-newestfail"; new_fx newestfail
add_run "$fx" 270 "$T2"; add_run "$fx" 271 "$T1"
add_job "$fx" 270 inngest_host_replace failure
add_job "$fx" 271 inngest_host_replace success
add_health "$fx" 299 "$T3" success
expect "newest replace concluded failure -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "newestfail" "$fx" "FAIL: inngest_host_replace job in run 270 concluded 'failure'"

fx="$WORK/fx-cancelled"; new_fx cancelled
add_run "$fx" 275 "$T1"
add_job "$fx" 275 inngest_host_replace cancelled
expect "replace job cancelled -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-nohealth"; new_fx nohealth
add_run "$fx" 280 "$T1"
add_job "$fx" 280 inngest_host_replace success
expect "replace ran, no health run post-dates -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "nohealth" "$fx" "NOT-YET: replace ran (280) but no health run post-dates it yet"

# A health run created BEFORE the replace dispatch must not satisfy the second half.
fx="$WORK/fx-oldhealth"; new_fx oldhealth
add_run "$fx" 285 "$T2"
add_job "$fx" 285 inngest_host_replace success
add_health "$fx" 286 "$T1" success
expect "health run pre-dating replace -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-inflight"; new_fx inflight
add_run "$fx" 287 "$T1"
add_job "$fx" 287 inngest_host_replace success
add_health "$fx" 288 "$T3" null
expect "post-dating health still in flight -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "inflight" "$fx" "still in flight"

fx="$WORK/fx-healthfail"; new_fx healthfail
add_run "$fx" 289 "$T1"
add_job "$fx" 289 inngest_host_replace success
add_health "$fx" 290 "$T3" failure
expect "post-replace health failed -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "healthfail" "$fx" "FAIL: post-replace health run 290 concluded 'failure'"

printf 'inngest-cli-apply-window-7463.test.sh: %s passed, %s failed\n' "$((total - fails))" "$fails"
[[ "$fails" -eq 0 ]]
