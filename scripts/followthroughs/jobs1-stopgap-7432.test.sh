#!/usr/bin/env bash
# jobs1-stopgap-7432.test.sh — Guard 2 for #7432 (Item I of #9217): drives the soak probe through a strict fake `gh`
# and pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED, 78 xtrace
# refusal), with kill rows against mutated COPIES of the probe. An exit-code contract nothing drives is a comment.
#
# The fake `gh` accepts EXACTLY the argv the probe is modeled to send and exits 64 on anything else, logging the
# refusal to $FX/refused.log; every row asserts that log is empty (or, for a kill row, non-empty), so a mutation of a
# selector (the branch, the window, the limit) cannot survive by reading a wrong-but-plausible fixture. Fixtures are
# synthesized (run ids are 9xxxx, the tracker number is the real #7432 only because the probe names it).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
export TZ=UTC
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/jobs1-stopgap-7432.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/jobs1-soak.XXXXXXXX")" || exit 2
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
assert_fixture_dir "$TMP"

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

START="2026-11-01T00:00:00Z"
START_EPOCH="$(date -u -d "$START" +%s)"
isoat() { date -u -d "@$((START_EPOCH + $1))" +%Y-%m-%dT%H:%M:%SZ; }   # <seconds after the window start>

# --- the strict fake gh ----------------------------------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
refuse() { printf 'REFUSED %s\n' "$*" >> "$FX/refused.log"; exit 64; }
R=jikig-ai/soleur
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  # gh run list -R R --workflow W --branch main --limit 200 --created ">=START" --json F   (nothing else)
  [ $# -eq 14 ] || refuse "$@"
  [ "$3" = "-R" ] && [ "$4" = "$R" ] && [ "$5" = "--workflow" ] && [ "$6" = "main-health-monitor.yml" ] || refuse "$@"
  [ "$7" = "--branch" ] && [ "$8" = "main" ] && [ "$9" = "--limit" ] && [ "${10}" = "200" ] || refuse "$@"
  [ "${11}" = "--created" ] && [ "${13}" = "--json" ] && [ "${14}" = "databaseId,status,conclusion,createdAt,event" ] || refuse "$@"
  case "${12}" in ">="*) since="${12#>=}" ;; *) refuse "$@" ;; esac
  [ -f "$FX/fail-runs" ] && { echo "gh: HTTP 500" >&2; exit 1; }
  jq -c --arg s "$since" '[.[] | select(.createdAt >= $s)] | sort_by(.createdAt) | reverse | .[0:200]' "$FX/runs.json"
  exit 0
fi
[ "$1" = "api" ] || refuse "$@"
ep="$2"
case "$ep" in
  "repos/$R/contents/.github/workflows/main-health-monitor.yml?ref=main")
    [ "$3" = "--jq" ] && [ "$4" = ".content" ] && [ $# -eq 4 ] || refuse "$@"
    [ -f "$FX/fail-contents" ] && { echo "gh: HTTP 502" >&2; exit 1; }
    base64 -w0 "$FX/workflow.txt"; echo; exit 0 ;;
  "repos/$R/actions/runs/"*"/jobs?per_page=100")
    rid="${ep#repos/$R/actions/runs/}"; rid="${rid%%/*}"
    [ -f "$FX/jobs-$rid.json" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    cat "$FX/jobs-$rid.json"; exit 0 ;;
  "repos/$R/check-runs/"*"/annotations?per_page=100")
    jid="${ep#repos/$R/check-runs/}"; jid="${jid%%/*}"
    [ -f "$FX/ann-$jid.json" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    cat "$FX/ann-$jid.json"; exit 0 ;;
  "repos/$R/actions/jobs/"*"/logs")
    jid="${ep#repos/$R/actions/jobs/}"; jid="${jid%%/*}"
    [ -f "$FX/log-$jid.txt" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    cat "$FX/log-$jid.txt"; exit 0 ;;
esac
refuse "$@"
FAKE
chmod +x "$TMP/bin/gh"

# --- fixture builders ------------------------------------------------------------------------------------------------------
# new_fx: a fresh fixture dir with a compliant workflow (exactly one JOBS assignment, in the tests step) and no runs
new_fx() {
  FX="$TMP/fx.$1"; assert_fixture_dir "$FX"; rm -rf "$FX"; mkdir -p "$FX"
  export FX
  printf '%s\n' 'name: main-health-monitor' '# JOBS: 1 in a whole-line comment is not an assignment' 'jobs:' '  health-check:' '    steps:' \
    '      - name: Run test suite' '        id: tests' '        env:' '          JOBS: 1' '      - name: Run infra suites' '        id: infra' '        env:' '          TEST_GROUP: infra' > "$FX/workflow.txt"
  echo '[]' > "$FX/runs.json"
}
# mkrun <rid> <offset s> <status> <conclusion> <infra: success|failure|ABSENT|skipped> <timeout 0|1> [red suite...]
mkrun() {
  local rid="$1" off="$2" st="$3" concl="$4" infra="$5" to="$6"; shift 6
  local jid=$((rid + 1000)) created; created="$(isoat "$off")"
  jq -c --argjson id "$rid" --arg c "$created" --arg s "$st" --arg k "$concl" \
    '. + [{databaseId:$id, createdAt:$c, status:$s, conclusion:$k, event:"workflow_dispatch"}]' "$FX/runs.json" > "$FX/runs.tmp" && mv "$FX/runs.tmp" "$FX/runs.json"
  printf '{"jobs":[{"id":%d,"name":"health-check"},{"id":%d,"name":"other"}]}\n' "$jid" "$((jid + 1))" > "$FX/jobs-$rid.json"
  if [ "$infra" = ABSENT ]; then echo '[]' > "$FX/ann-$jid.json"
  else jq -n --arg m "SOLEUR_MAIN_HEALTH tests=failure infra=$infra tests_elapsed_s=100 infra_elapsed_s=200" '[{title:"main-health-outcomes",message:$m}]' > "$FX/ann-$jid.json"
  fi
  if [ "$to" = 1 ]; then
    jq '. + [{title:"",message:"The action '"'"'Run infra suites'"'"' has timed out after 60 minutes."}]' "$FX/ann-$jid.json" > "$FX/ann.tmp" && mv "$FX/ann.tmp" "$FX/ann-$jid.json"
  fi
  { echo "2026-11-01T00:00:00.0000000Z RED  apps/web-platform/infra/tests-part-decoy.test.sh"
    echo "2026-11-01T00:01:00.0000000Z   TEST_GROUP: infra"
    local s; for s in "$@"; do echo "2026-11-01T00:02:00.0000000Z RED  apps/web-platform/infra/$s"; done
    echo "2026-11-01T00:03:00.0000000Z === done ==="; } > "$FX/log-$jid.txt"
}
good_runs() { local i; for i in $(seq 1 "$1"); do mkrun $((90000 + i)) $((i * 3600)) completed success success 0; done; }
FAKE_ENV_OK=1
run_probe() {  # run_probe <probe path> [extra env...]; sets RC and OUT, resets the refused log first
  : > "$FX/refused.log"
  OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="${EARLIEST-$START}" "${@:2}" bash "$1" 2>&1)"; RC=$?
}
expect() {  # expect <label> <rc> [output substring...]
  local label="$1" want="$2" sub; shift 2
  if [ "$RC" -eq "$want" ]; then pass "$label: exit $want"; else fail "$label: want exit $want, got $RC ($OUT)"; fi
  for sub in "$@"; do
    case "$OUT" in *"$sub"*) pass "$label: output names '$sub'" ;; *) fail "$label: output lacks '$sub' ($OUT)" ;; esac
  done
  if [ -s "$FX/refused.log" ]; then fail "$label: the probe sent a refused argv ($(head -1 "$FX/refused.log"))"; else pass "$label: every gh argv was modeled"; fi
}
mutant() {  # mutant <name> <sed expr>: a mutated COPY of the probe; the mutation must land
  local m="$TMP/mut.$1.sh"
  sed -e "$2" "$PROBE" > "$m"
  if cmp -s "$PROBE" "$m"; then fail "mutant $1: the mutation did not land"; return 1; fi
  MUT="$m"
}

[ -r "$PROBE" ] || { echo "[FATAL] probe not found at $PROBE"; exit 1; }

# R0 control: 12 clean runs, one JOBS assignment on main
new_fx r0; good_runs 12; run_probe "$PROBE"; expect "R0 12 clean runs" 0
# R1 the infra pin is still on main -> NOT YET, never 0 (the stub workflow gains a second assignment)
new_fx r1; good_runs 12; printf '%s\n' '        env:' '          JOBS: 1' >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1 infra pin still on main" 2
# R2 fewer than 12 runs; bad runs before the window start are ignored; a bad run exactly at the start is counted
new_fx r2a; good_runs 11; run_probe "$PROBE"; expect "R2a 11 clean runs" 2
new_fx r2b; good_runs 12; mkrun 90100 -1 completed success failure 1; run_probe "$PROBE"; expect "R2b a ceiling kill one second BEFORE the window start is ignored" 0
new_fx r2c; good_runs 11; mkrun 90101 0 completed success failure 1; run_probe "$PROBE"; expect "R2c a ceiling kill exactly AT the window start is counted" 1 90101
# R3 two ceiling kills among 12 -> exit 1 naming both
new_fx r3; mkrun 90001 3600 completed success success 0; mkrun 90002 7200 completed success failure 1; mkrun 90003 10800 completed success failure 1; for i in $(seq 4 12); do mkrun $((90000 + i)) $((i * 3600)) completed success success 0; done
run_probe "$PROBE"; expect "R3 two ceiling kills" 1 90002 90003
# R4 precedence and the allowlist boundary
new_fx r4a; good_runs 10; mkrun 90020 40000 completed success failure 0 some-other.test.sh; mkrun 90021 41000 completed success failure 1
run_probe "$PROBE"; expect "R4a a RED outside the allowlist AND a ceiling kill: the kill wins" 1 90021
new_fx r4b; good_runs 11; mkrun 90030 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh some-other.test.sh
run_probe "$PROBE"; expect "R4b an allowlisted RED plus another suite" 5 some-other.test.sh 90030
new_fx r4c; good_runs 11; mkrun 90031 40000 completed success failure 0
run_probe "$PROBE"; expect "R4c infra=failure with no RED line at all needs a human" 5 90031
# R5 never 0 on a read it could not make
new_fx r5a; good_runs 11; mkrun 90040 40000 completed success ABSENT 0; run_probe "$PROBE"; expect "R5a a non-cancelled run with no main-health-outcomes annotation" 3
new_fx r5b; good_runs 12; : > "$FX/fail-contents"; run_probe "$PROBE"; expect "R5b a failed contents read" 3
new_fx r5c; good_runs 12; EARLIEST="" run_probe "$PROBE"; expect "R5c SOLEUR_FT_EARLIEST empty" 3
new_fx r5d; good_runs 12; EARLIEST="not-a-date" run_probe "$PROBE"; expect "R5d SOLEUR_FT_EARLIEST not an ISO timestamp" 3
new_fx r5e; for i in $(seq 1 200); do mkrun $((80000 + i)) $((i * 60)) completed success success 0; done; run_probe "$PROBE"; expect "R5e a run list that fills the limit" 3
new_fx r5f; good_runs 12; : > "$FX/fail-runs"; run_probe "$PROBE"; expect "R5f a failed run-list read" 3
new_fx r5g; good_runs 12; rm "$FX/ann-91001.json"; run_probe "$PROBE"; expect "R5g a failed annotation read" 3
# R5h: an empty annotation list is ABSENT and counts as unread, never as zero findings
new_fx r5h; good_runs 12; echo '[]' > "$FX/ann-91003.json"; run_probe "$PROBE"; expect "R5h an empty annotation list on a counted run" 3
# R6 monotone: 12 clean then a later bad run still passes
new_fx r6; good_runs 12; mkrun 90200 99999 completed success failure 1; run_probe "$PROBE"; expect "R6 a bad run AFTER the 12 oldest" 0
# R7 pending: a still-running run among the first 12
new_fx r7; good_runs 11; mkrun 90300 50000 in_progress "" ABSENT 0; run_probe "$PROBE"; expect "R7 a counted run is still running" 2
# R8 xtrace refusal
new_fx r8; good_runs 12; : > "$FX/refused.log"
OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="$START" bash -x "$PROBE" 2>&1)"; RC=$?
expect "R8 run under xtrace with GH_TOKEN set" 78
# P1 must-PASS non-canonical: 14 runs in shuffled order, 2 cancelled, one clean run whose only RED is the allowlisted suite
new_fx p1
mkrun 90012 12 completed success success 0; mkrun 90005 5 completed cancelled ABSENT 0; mkrun 90001 1 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
mkrun 90009 9 completed success success 0; mkrun 90003 3 completed success success 0; mkrun 90013 13 completed cancelled ABSENT 0; mkrun 90002 2 completed success success 0
mkrun 90004 4 completed success success 0; mkrun 90006 6 completed success success 0; mkrun 90007 7 completed success success 0; mkrun 90008 8 completed success success 0
mkrun 90010 10 completed success success 0; mkrun 90011 11 completed success success 0; mkrun 90015 14 completed success success 0; mkrun 90014 16 completed success failure 1
run_probe "$PROBE"; expect "P1 shuffled, two cancelled, allowlisted RED, a bad run after the 12th" 0 "Allowlisted tag-drift RED in run(s): 90001"
# X cross-check: the real post-edit workflow, served by the stub, counts exactly one JOBS assignment (the tests step)
new_fx x; good_runs 12; cp "$WORKFLOW" "$FX/workflow.txt"; run_probe "$PROBE"; expect "X the real workflow on this tree passes the pin-count read" 0
_tok="$(grep -vE '^[[:space:]]*#' "$WORKFLOW" | grep -cE '(^|[^A-Za-z0-9_])JOBS[[:space:]]*[:=]' || true)"
if [ "$_tok" = 1 ]; then pass "X the real workflow carries exactly one JOBS assignment"; else fail "X the real workflow carries $_tok JOBS assignments, want 1"; fi

# --- kill rows: each mutated copy of the probe must change the verdict of the row that guards it -----------------------------
new_fx m1; good_runs 12; printf '%s\n' '        env:' '          JOBS: 1' >> "$FX/workflow.txt"
if mutant m1 's/-ge 2/-ge 99/'; then run_probe "$MUT"; [ "$RC" -ne 2 ] && pass "K1 dropping the pin-count threshold is caught by R1" || fail "K1 survived (rc $RC)"; fi
new_fx m2; good_runs 11
if mutant m2 's/^N=12$/N=11/'; then run_probe "$MUT"; [ "$RC" -ne 2 ] && pass "K2 lowering the sample size is caught by R2a" || fail "K2 survived (rc $RC)"; fi
new_fx m3; good_runs 11; mkrun 90030 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutant m3 's/^KNOWN_DETERMINISTIC_REDS=.*/KNOWN_DETERMINISTIC_REDS=""/'; then run_probe "$MUT"; [ "$RC" -ne 0 ] && pass "K3 emptying the allowlist is caught (an allowlisted RED stops passing)" || fail "K3 survived (rc $RC)"; fi
new_fx m4; good_runs 12
if mutant m4 's/--branch main/--branch feat-x/'; then run_probe "$MUT"; if [ "$RC" -ne 0 ] && [ -s "$FX/refused.log" ]; then pass "K4 a wrong branch selector is refused by the strict stub"; else fail "K4 survived (rc $RC)"; fi; fi
new_fx m5; good_runs 12; mkrun 90500 -1 completed success failure 1
if mutant m5 's/--created ">=\$EARLIEST"/--created ">=2000-01-01T00:00:00Z"/'; then run_probe "$MUT"; [ "$RC" -ne 0 ] && pass "K5 a hard-coded window start is caught by R2b" || fail "K5 survived (rc $RC)"; fi
new_fx m6; good_runs 12; mkrun 90500 -1 completed success failure 1
if mutant m6 's/--limit 200/--limit 100/'; then run_probe "$MUT"; if [ "$RC" -ne 0 ] && [ -s "$FX/refused.log" ]; then pass "K6 a changed list limit is refused by the strict stub"; else fail "K6 survived (rc $RC)"; fi; fi
new_fx m7; good_runs 12
if mutant m7 's/\*x\*)/*zz*)/'; then
  OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="$START" bash -x "$MUT" 2>&1)"; RC=$?
  [ "$RC" -ne 78 ] && pass "K7 removing the xtrace refusal is caught by R8" || fail "K7 survived (rc $RC)"
fi

# --- accounting --------------------------------------------------------------------------------------------------------------
printf '=== jobs1-stopgap-7432: %d passed, %d failed ===\n' "$passes" "$fails"
MIN_ASSERTIONS=60
if [ "$asserted" -lt "$MIN_ASSERTIONS" ] || [ $((passes + fails)) -ne "$asserted" ]; then
  printf '[FATAL] anti-vacuity: %d assertions (floor %d), %d recorded\n' "$asserted" "$MIN_ASSERTIONS" $((passes + fails)) >&2
  exit 1
fi
[ "$fails" -eq 0 ] || { printf 'FAILED:\n'; printf '  %s\n' "${FAILURES[@]}"; exit 1; }
exit 0
