#!/usr/bin/env bash
# Wiring suite for .github/workflows/codeql-to-issues.yml (#12065 convergence; #12066 reaper fix).
#
# PROPERTY UNDER TEST. The daily sweep's check-alerts job runs scripts/codeql-main-alert-gate.sh in
# SWEEP mode — nothing between the trigger and the script can skip it, soften it, dry-run it
# unexpectedly, reintroduce inline filing, or kill it before its own deadline — and close-orphans
# reaps a tracker iff every referenced alert is dismissed OR fixed (keep-open and lookup failure
# keep it open). The script's verdicts are proven by codeql-main-alert-gate.test.sh; THIS suite
# proves the caller's wiring, the same way codeql-main-alert-gate-workflow-wiring.test.sh proves
# the push caller's.
#
# WHY NOT GREPS. Same argument as the sibling suite: the workflow is PARSED (PyYAML; `on` -> True)
# and the gate step's env expressions are EVALUATED for the schedule and dispatch variants. The
# close-orphans predicate stays an inline run block (ruled: the job stays separate), so it is
# pinned by exact-string assertions over the parsed run text — a grep would satisfy the same
# strings in a comment, so the assertions read the PARSED run field.
#
# Knobs (tests only): none. Fixtures: fixtures/codeql-to-issues-sweep-wiring/sweep_facts.py.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$ROOT/.github/workflows/codeql-to-issues.yml"
FACTS="$SCRIPT_DIR/fixtures/codeql-to-issues-sweep-wiring/sweep_facts.py"

# The EXACT assertion count of a green run (re-derive it from a green run, never from arithmetic; -ne, not -lt).
FLOOR=70

ASSERTS=0 passes=0 fails=0 FAILED=()
pass() { passes=$((passes + 1)); ASSERTS=$((ASSERTS + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); ASSERTS=$((ASSERTS + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"; _iv_a="$ASSERTS"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) || "$ASSERTS" -ne $((_iv_a + 2)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); ASSERTS=0

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

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "UNRESOLVED: python3 missing — this suite asserted nothing; install python3"; exit 3; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "UNRESOLVED: PyYAML missing — this suite asserted nothing; install python3-yaml"; exit 3; }
[[ -f "$FACTS" && -f "$WF" ]] || { printf 'FAIL: workflow or facts helper missing — the files under test are repo-owned\n' >&2; exit 1; }

SANDBOX="$(mktemp -d)" || { echo "[FATAL] mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

t()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
tn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got <$2> want <$3>)"; fi; }

verdict_helper_controls() {
  local p_orig="$passes" f_orig="$fails" p0="$passes" f0="$fails" a0="$ASSERTS" n0="${#FAILED[@]}" bad=""
  { t "vc" true; } >/dev/null 2>&1;                [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad t-pass"
  p0="$passes"; f0="$fails"
  { t "vc" false; } >/dev/null 2>&1;               [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad t-fail"
  p0="$passes"; f0="$fails"
  { tn "vc" false; } >/dev/null 2>&1;              [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad tn-pass"
  p0="$passes"; f0="$fails"
  { tn "vc" true; } >/dev/null 2>&1;               [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad tn-fail"
  p0="$passes"; f0="$fails"
  { eq "vc" "same" "same"; } >/dev/null 2>&1;      [[ "$passes" -eq $((p0 + 1)) && "$fails" -eq "$f0" ]] || bad="$bad eq-pass"
  p0="$passes"; f0="$fails"
  { eq "vc" "one" "two"; } >/dev/null 2>&1;        [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] || bad="$bad eq-fail"
  passes="$p_orig"; fails="$f_orig"; ASSERTS="$a0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ -n "$bad" ]]; then
    printf '[FATAL] verdict helper positive control: a helper did not record the verdict it was handed:%s\n' "$bad" >&2
    exit 1
  fi
}
verdict_helper_controls

# ---------------------------------------------------------------------------------------------
# The assertion engine. check_wf <workflow> <out>: one line per assertion, `ok <id> <desc>` or
# `FAIL <id> <desc>`; returns the number of failures.
# ---------------------------------------------------------------------------------------------
CHECK_N=0
_a() { # <id> <description> <jq -e filter over the facts document>
  CHECK_N=$((CHECK_N + 1))
  assert_fixture_dir "$CHECK_OUT"
  if jq -e "$3" "$FACTS_JSON" >/dev/null 2>&1; then printf 'ok %s %s\n' "$1" "$2" >>"$CHECK_OUT"; else printf 'FAIL %s %s\n' "$1" "$2" >>"$CHECK_OUT"; fi
}
FACTS_JSON="" CHECK_OUT=""
check_wf() { # <workflow> <out>
  FACTS_JSON="$2.facts.json" CHECK_OUT="$2"; CHECK_N=0
  assert_fixture_dir "$CHECK_OUT"; assert_fixture_dir "$FACTS_JSON"
  : >"$CHECK_OUT"
  python3 "$FACTS" "$1" >"$FACTS_JSON" 2>"$2.facts.err" || printf '{"parse_ok": false, "error": "helper crashed"}\n' >"$FACTS_JSON"
  [[ -s "$FACTS_JSON" ]] || printf '{"parse_ok": false, "error": "helper printed nothing"}\n' >"$FACTS_JSON"

  _a B01 "the workflow parses as a YAML mapping" '.parse_ok == true'
  _a B02 "triggers are exactly schedule and workflow_dispatch" '.trigger_found == true and .triggers == ["schedule","workflow_dispatch"]'
  _a B03 "workflow_dispatch has exactly the dry_run input (boolean, optional, default false)" \
    '(.dispatch_inputs | keys) == ["dry_run"] and .dispatch_inputs.dry_run.type == "boolean" and .dispatch_inputs.dry_run.required == false and .dispatch_inputs.dry_run.default == false'
  _a B04 "the schedule is exactly the 06:00 UTC daily cron" '.schedule == [{"cron":"0 6 * * *"}]'
  _a B05 "check-alerts has no job-level if, continue-on-error or strategy and needs nothing" \
    '((.check_alerts.keys - ["runs-on","timeout-minutes","steps"]) | length) == 0'
  _a B06 "check-alerts runs exactly two steps, neither with if or continue-on-error" \
    '(.check_alerts.steps | length) == 2 and ([.check_alerts.steps[] | select(.has_if or .has_continue_on_error)] | length) == 0'
  _a B07 "exactly one step invokes the gate script" '.gate_step_count == 1'
  _a B08 "the sweep step runs exactly: bash scripts/codeql-main-alert-gate.sh" \
    '[.check_alerts.steps[] | select(.run != null)] | map(.run | gsub("^\\s+|\\s+$"; "")) == ["bash scripts/codeql-main-alert-gate.sh"]'
  _a B09 "the sweep step has no || ; & | or newline that could swallow the exit status" \
    '[.check_alerts.steps[] | select(.run != null) | .run | gsub("\\n$"; "") | select(test("\\|\\||;|&|\\||\\n"))] | length == 0'
  _a B10 "the sweep step follows a pinned-SHA checkout with persist-credentials false and a sparse checkout of the script" \
    '.gate_step_index == 1 and (.check_alerts.steps[0].uses | test("^actions/checkout@[0-9a-f]{40}$")) and (.check_alerts.steps[0].with["persist-credentials"] == false) and ((.check_alerts.steps[0].with["sparse-checkout"] | tostring) | contains("scripts/codeql-main-alert-gate.sh")) and (.check_alerts.steps[0].with["sparse-checkout-cone-mode"] == false)'
  _a B11 "the sweep step env is EXACTLY GH_TOKEN, GH_REPO, SWEEP, DRY_RUN, GITHUB_RUN_ID, DEADLINE_SECONDS" \
    '.gate_env_keys == ["DEADLINE_SECONDS","DRY_RUN","GH_REPO","GH_TOKEN","GITHUB_RUN_ID","SWEEP"]'
  _a B12 "SWEEP is the literal true in every event" '[.evals[] | .SWEEP] | all(. == "true")'
  _a B13 "GH_TOKEN, GH_REPO and GITHUB_RUN_ID are the real values in every event" \
    '([.evals[] | .GH_TOKEN] | all(. == "SYNTHETIC-TOKEN")) and ([.evals[] | .GH_REPO] | all(. == "example-org/example-repo")) and ([.evals[] | .GITHUB_RUN_ID] | all(. == "424242"))'
  _a B14 "DRY_RUN is false on schedule and a default dispatch, true on a dry_run dispatch" \
    '.evals.schedule.DRY_RUN == "false" and .evals.dispatch_default.DRY_RUN == "false" and .evals.dispatch_dry.DRY_RUN == "true"'
  _a B15 "timeout-minutes leaves room after the script deadline for one hung call plus the degraded upsert (300 s)" \
    '(.check_alerts.timeout | type) == "number" and (.check_alerts.timeout * 60) >= ((.evals.schedule.DEADLINE_SECONDS | tonumber) + 300)'
  _a B16 "no inline filing remains: no gh api, gh issue, gh search, jq or EXISTING/ALERTS assignments in check-alerts run text" \
    '(.check_alerts.run_text | test("gh (api|issue|search)|jq |[A-Z]+=")) | not'
  _a B17 "permissions are exactly contents:read issues:write security-events:read" \
    '.permissions == {"contents":"read","issues":"write","security-events":"read"}'
  _a B18 "every action in the workflow is pinned to a 40-hex commit SHA" \
    '[.check_alerts.steps[] , .close_orphans.steps[] | select(.uses != null) | .uses] as $u | ($u | length) >= 1 and ($u | all(test("@[0-9a-f]{40}$")))'
  _a B19 "close-orphans is a separate job that needs check-alerts (the ruling's boundary)" \
    '.job_ids == ["check-alerts","close-orphans"] and .close_orphans.needs == ["check-alerts"]'
  _a B20 "the reaper accepts exactly the two terminal states dismissed and fixed" \
    '.close_orphans.run_text | contains("[ \"$STATE\" != \"dismissed\" ] && [ \"$STATE\" != \"fixed\" ]")'
  _a B21 "the keep-open escape hatch is intact" '.close_orphans.run_text | contains("keep-open")'
  _a B22 "the per-alert reason records the actual state" '.close_orphans.run_text | contains("- alert #${AN}: ${STATE}")'
  _a B23 "a lookup failure still keeps the issue open (the empty-STATE branch)" \
    '.close_orphans.run_text | test("if \\[ -z \"\\$STATE\" \\]")'
  _a B24 "no run: block anywhere carries a GitHub expression (event data reaches scripts by env only)" \
    '[.check_alerts.steps[] , .close_orphans.steps[] | select(.run != null) | .run | select(contains("${{"))] | length == 0'
  _a B25 "no || true and no 2>&1 capture remains in check-alerts run text (the dedupe-rot class)" \
    '(.check_alerts.run_text | test("\\|\\| true|2>&1")) | not'
  _a B26 "env lives only on the sweep step inside check-alerts (nothing else can ride along)" \
    '.workflow_env == null and .check_alerts.env == null and ([.env_sites[] | select(.site != "step:1")] | length) == 0'
  _a B27 "every check-alerts step carries only name/uses/with/run/env keys" \
    '.check_alerts.steps | length >= 1 and all(((.keys - ["name","uses","with","run","env"]) | length) == 0)'
  _a B28 "the reaper is gated on inputs.dry_run — skipped only on a dry_run dispatch" \
    '.close_orphans_if.schedule == true and .close_orphans_if.dispatch_default == true and .close_orphans_if.dispatch_dry == false'

  return "$(grep -c '^FAIL' "$CHECK_OUT")"
}

CHECKS_PER_RUN=28

# ---------------------------------------------------------------------------------------------
# Pristine workflow: every assertion must pass, and the engine must have run all of them.
# ---------------------------------------------------------------------------------------------
echo "== pristine workflow: every sweep wiring assertion holds =="
P="$SANDBOX/pristine"; mkdir -p "$P" || exit 2
check_wf "$WF" "$P/out.txt"; prc=$?
eq "engine ran every assertion against the real workflow" "$CHECK_N" "$CHECKS_PER_RUN"
eq "engine recorded one line per assertion" "$(wc -l <"$P/out.txt" | tr -d ' ')" "$CHECKS_PER_RUN"
eq "the real workflow has zero failing sweep wiring assertions" "$prc" "0"
while read -r verdict id desc; do
  if [[ "$verdict" == "ok" ]]; then pass "$id $desc"; else fail "$id $desc"; fi
done <"$P/out.txt"
t "the PyYAML quirk is real and handled: on parses to boolean True, not the string on" jq -e '.on_key_is_bool_true == true and .on_key_is_string == false' "$P/out.txt.facts.json"

# ---------------------------------------------------------------------------------------------
# Mutation rows. mutate_wf <label> <expected-failing-id> <sed -E expression>
# ---------------------------------------------------------------------------------------------
echo "== mutation rows: each defect must land and red the assertion that owns it =="
MI=0
mutate_wf() {
  local label="$1" want_id="$2" expr="$3" m rc=0
  MI=$((MI + 1)); m="$SANDBOX/m$MI"; mkdir -p "$m" || exit 2
  sed -E "$expr" "$WF" >"$m/wf.yml" || { fail "mutant $MI ($label): sed failed"; return; }
  if cmp -s "$WF" "$m/wf.yml"; then fail "mutant $MI ($label): the mutation did NOT land"; return; fi
  check_wf "$m/wf.yml" "$m/out.txt" || rc=$?
  if [[ "$rc" -gt 0 ]] && grep -q "^FAIL $want_id " "$m/out.txt" && [[ "$CHECK_N" -eq "$CHECKS_PER_RUN" ]]; then
    pass "mutant $MI ($label) lands and reds $want_id"
  else
    fail "mutant $MI ($label): $want_id did not fail (failing: $(grep '^FAIL' "$m/out.txt" | cut -d' ' -f2 | tr '\n' ' '))"
  fi
}
G='bash scripts\/codeql-main-alert-gate\.sh'
mutate_wf "continue-on-error on the sweep step" B06 "s/^(        run: ${G})\$/\\1\\n        continue-on-error: true/"
mutate_wf "|| true after the script" B08 "s/^(        run: ${G})\$/\\1 || true/"
mutate_wf "|| true after the script (swallower)" B09 "s/^(        run: ${G})\$/\\1 || true/"
mutate_wf "SWEEP env deleted (the caller becomes a second push-mode invocation)" B11 '/^          SWEEP:/d'
mutate_wf "SWEEP env deleted (mode lost)" B12 '/^          SWEEP:/d'
mutate_wf "an inline filer returns to check-alerts" B16 "s/^(        run: ${G})\$/\\1\\n          gh issue create --title x --body-file \/dev\/null/"
mutate_wf "fixed dropped from the reaper's allowlist (#12066 regressed)" B20 's/ && \[ "\$STATE" != "fixed" \]//'
mutate_wf "keep-open escape hatch removed" B21 's/keep-open/keep-closed/g'
mutate_wf "checkout unpinned to a tag" B10 's/(uses: actions\/checkout)@[0-9a-f]{40}/\1@v4/'
mutate_wf "timeout-minutes below the deadline-plus-upsert invariant" B15 's/^(    timeout-minutes: )10$/\15/'
mutate_wf "checkout persists credentials" B10 's/persist-credentials: false/persist-credentials: true/'
mutate_wf "dry_run dispatch input removed" B03 '/^      dry_run:$/d'
mutate_wf "sparse-checkout line removed (the job checks out everything)" B10 '/^          sparse-checkout:/d'
mutate_wf "needs edge removed (the reaper runs against a failed sweep)" B19 '/^    needs: check-alerts$/d'
mutate_wf "schedule cron changed" B04 's/0 6 \* \* \*/0 7 * * */'
mutate_wf "contents:read permission dropped (checkout cannot fetch)" B17 '/^  contents: read$/d'
mutate_wf "an extra env key rides along on the sweep step" B11 's/^(          DEADLINE_SECONDS:.*)$/\1\n          PATH: \/tmp\/evil/'
mutate_wf "workflow-level env sets DEADLINE_SECONDS" B26 's/^(permissions:)$/env:\n  DEADLINE_SECONDS: 5\n\n\1/'
mutate_wf "DRY_RUN pinned to true (every scheduled run is a dry run)" B14 "s/\&\& 'true' \|\| 'false' \}\}/\&\& 'true' || 'true' }}/"
mutate_wf "reaper predicate widened to a third state" B20 's/\[ "\$STATE" != "fixed" \]/[ "$STATE" != "open" ]/'
mutate_wf "lookup-failure branch flipped to close" B23 's/if \[ -z "\$STATE" \]/if [ -n "$STATE" ]/'
mutate_wf "workflow_dispatch trigger renamed (dry_run input unreachable)" B02 's/^  workflow_dispatch:/  workflow_dispatchx:/'
mutate_wf "a third step in check-alerts" B06 "s/^(        run: ${G})\$/\\1\\n      - run: echo extra/"
mutate_wf "the reaper reason hardcodes the state" B22 's/- alert #\$\{AN\}: \$\{STATE\}/- alert #${AN}: fixed/'
mutate_wf "a GitHub expression smuggled into the reaper run text" B24 's/keep-open/${{ github.sha }}/'
mutate_wf "sparse-checkout-cone-mode removed" B10 '/^          sparse-checkout-cone-mode:/d'
mutate_wf "the dry_run reaper gate removed" B28 '/^    if: inputs.dry_run != true$/d'

# Guard 2 row 7: a facts helper neutered to always report parse_ok must red the suite — a green
# with no parse is vacuous.
neut="$SANDBOX/neutered-facts.py"
printf 'import json\nprint(json.dumps({"parse_ok": True}))\n' >"$neut"
FACTS_SAVE="$FACTS"; FACTS="$neut"
rc=0; check_wf "$WF" "$SANDBOX/neut.out" || rc=$?
FACTS="$FACTS_SAVE"
[[ "$rc" -gt 0 ]] && pass "a facts helper that always reports parse_ok reds the suite" || fail "a facts helper that always reports parse_ok reds the suite"

mutate_wf_control() { # <label> <want-message-substring> <wanted-id> <sed expr>
  local label="$1" want_msg="$2" p0="$passes" f0="$fails" a0="$ASSERTS" n0="${#FAILED[@]}" moved=0 msg_ok=0
  mutate_wf "ctl-$label" "$3" "$4" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] && msg_ok=1
  passes="$p0"; fails="$f0"; ASSERTS="$a0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: mutate_wf rejects $label"
  else
    printf '[FATAL] mutate_wf control: %s was not rejected (moved=%s msg=%s)\n' "$label" "$moved" "$msg_ok" >&2
    exit 1
  fi
}
mutate_wf_control "a mutation that does not land" "did NOT land" B06 's/^NO_SUCH_LINE_ANYWHERE$/x/'
mutate_wf_control "a landed mutation that breaks nothing" "did not fail" B06 '$a # harmless trailing comment'
mutate_wf_control "a mutation that reds a different assertion than the one named" "did not fail" B10 's/^(    timeout-minutes: )10$/\15/'

# ---------------------------------------------------------------------------------------------
# Engine controls: an unreadable or non-workflow input is RED on B01, never green and never a crash.
# ---------------------------------------------------------------------------------------------
echo "== engine controls: an unreadable workflow cannot read as green =="
ec="$SANDBOX/engine"; mkdir -p "$ec" || exit 2
printf 'on: [\n  push\n' >"$ec/broken.yml"
rc=0; check_wf "$ec/broken.yml" "$ec/broken.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL B01 ' "$ec/broken.out" && pass "malformed YAML fails B01" || fail "malformed YAML fails B01"
printf -- '- just\n- a list\n' >"$ec/list.yml"
rc=0; check_wf "$ec/list.yml" "$ec/list.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL B01 ' "$ec/list.out" && pass "a YAML list (not a workflow) fails B01" || fail "a YAML list (not a workflow) fails B01"
rc=0; check_wf "$ec/does-not-exist.yml" "$ec/missing.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL B01 ' "$ec/missing.out" && pass "a missing workflow fails B01" || fail "a missing workflow fails B01"
printf 'name: x\njobs: {}\n' >"$ec/empty.yml"
rc=0; check_wf "$ec/empty.yml" "$ec/empty.out" || rc=$?
[[ "$rc" -ge 10 ]] && pass "a workflow with no jobs fails many assertions ($rc)" || fail "a workflow with no jobs fails many assertions (got $rc)"
eq "the engine still ran every assertion against the empty workflow" "$CHECK_N" "$CHECKS_PER_RUN"

# ---------------------------------------------------------------------------------------------
# Evaluator parity: sweep_facts.py's expression evaluator is a verbatim copy of wiring_facts.py's
# (self-contained fixtures can't import a shared module). The copy that RUNS must equal the copy
# that was reviewed — a normalized logic-parity guard, not a presence grep.
# ---------------------------------------------------------------------------------------------
echo "== evaluator parity: the two *_facts.py evaluator copies stay identical =="
WIRING_FACTS="$SCRIPT_DIR/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py"
eval_blocks() { # <facts.py>: the evaluator's nine top-level units, one __block__ marker each
  python3 - "$1" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
names = {"ExprError", "TOKEN", "tokenize", "truthy", "to_num", "loose_eq", "Parser", "EXPR", "evaluate"}
out = []
for node in ast.parse(src).body:
    nm = getattr(node, "name", None)
    if nm in names or (isinstance(node, ast.Assign) and any(getattr(t, "id", None) in names for t in node.targets)):
        seg = ast.get_source_segment(src, node)
        if seg:
            out.append("__block__\n" + seg.rstrip())
print("\n".join(out))
PY
}
eq "the parity extractor covers all nine evaluator units in both facts helpers" \
  "$( { eval_blocks "$FACTS"; eval_blocks "$WIRING_FACTS"; } | grep -c '__block__' )" "18"
eq "the sweep evaluator is verbatim the wiring evaluator" \
  "$(diff <(eval_blocks "$FACTS") <(eval_blocks "$WIRING_FACTS") >/dev/null; echo $?)" "0"

# ---------------------------------------------------------------------------------------------
# Verdict. The floor is reported with printf + exit, outside the pass/fail helpers.
# ---------------------------------------------------------------------------------------------
printf '\nassertions=%d passes=%d fails=%d floor=%d\n' "$ASSERTS" "$passes" "$fails" "$FLOOR"
if [[ "$fails" -gt 0 ]]; then
  printf '[RED] %d assertion(s) failed:\n' "$fails" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
if [[ "$ASSERTS" -ne "$FLOOR" ]]; then
  printf '[RED] assertion count %d != the exact floor %d (a case stopped running, or one was added without re-deriving the floor)\n' "$ASSERTS" "$FLOOR" >&2
  exit 1
fi
printf '[GREEN] codeql-to-issues sweep wiring suite\n'
exit 0
