#!/usr/bin/env bash
# Wiring suite for .github/workflows/codeql-main-alert-gate.yml (review #9455, finding L6).
#
# PROPERTY UNDER TEST. A push to main runs scripts/codeql-main-alert-gate.sh, on the pushed commit, with the
# real token and repository, with DRY_RUN false, and the job's conclusion is the script's exit status: nothing
# between the trigger and the script can skip it, soften it, or turn it into a dry run. The script's verdicts
# are proven by codeql-main-alert-gate.test.sh; THIS suite proves the script is the thing that runs.
#
# WHY NOT GREPS. The previous guard grepped the workflow text. `push:` renamed to `pull_request:` kept
# `branches: [main]` green, `continue-on-error: true` and `|| true` matched nothing it looked for, an inverted
# DRY_RUN expression matched `inputs.dry_run`, and a deleted `GH_TOKEN:` line was never looked for. Here the
# workflow is PARSED (PyYAML; the key `on` parses to the boolean True, handled in the helper) and the gate step's
# env expressions are EVALUATED for a push and for each dispatch variant with GitHub's `&&`/`||`/`==` semantics.
#
# HOW THE ASSERTIONS ARE PROVEN. check_wf runs the SAME assertion list against a workflow path. The pristine
# workflow must pass every one; each MUTATION ROW applies a sed edit to a COPY of the pristine workflow (the copy
# is compared against the original so a mutation that did not land is itself RED) and requires the specific
# assertion that owns that defect to fail. A positive control proves an unreadable file is RED, never green.
#
# Knobs (tests only): none. Fixtures: fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$ROOT/.github/workflows/codeql-main-alert-gate.yml"
GATE="$ROOT/scripts/codeql-main-alert-gate.sh"
FACTS="$SCRIPT_DIR/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py"

# The exact assertion count of a green run (re-derive it from a green run, never from arithmetic). Reported by
# printf + exit at the bottom, NOT through pass/fail, so a harness that stops counting cannot report its own shortfall.
FLOOR=65

ASSERTS=0 passes=0 fails=0 FAILED=()
pass() { passes=$((passes + 1)); ASSERTS=$((ASSERTS + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); ASSERTS=$((ASSERTS + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before anything is trusted.
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

command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "SKIP: PyYAML missing"; exit 0; }
[[ -f "$FACTS" && -f "$WF" && -f "$GATE" ]] || { printf '[FATAL] workflow, gate script or facts helper missing\n' >&2; exit 2; }

SANDBOX="$(mktemp -d)" || { echo "[FATAL] mktemp -d failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

# t <desc> <cmd...>: pass when the command exits 0.   tn: pass when it exits non-zero.
t()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
tn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got <$2> want <$3>)"; fi; }

# Positive controls for the verdict-owning helpers t, tn, eq (pass/fail are covered by the self-test above): each is
# driven with an input that must pass and one that must fail; the counters are unwound; a shortfall is a FATAL by printf.
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
# The assertion engine. check_wf <workflow> <gate-script> <out>: writes one line per assertion,
# `ok <id> <description>` or `FAIL <id> <description>`, and returns the number of failures.
# ---------------------------------------------------------------------------------------------
CHECK_N=0
_a() { # <id> <description> <jq -e filter over the facts document>
  CHECK_N=$((CHECK_N + 1))
  if jq -e "$3" "$FACTS_JSON" >/dev/null 2>&1; then printf 'ok %s %s\n' "$1" "$2" >>"$CHECK_OUT"; else printf 'FAIL %s %s\n' "$1" "$2" >>"$CHECK_OUT"; fi
}
FACTS_JSON="" CHECK_OUT=""
check_wf() { # <workflow> <script> <out>
  FACTS_JSON="$3.facts.json" CHECK_OUT="$3"; CHECK_N=0
  : >"$CHECK_OUT"
  python3 "$FACTS" "$1" "$2" >"$FACTS_JSON" 2>"$3.facts.err" || printf '{"parse_ok": false, "error": "helper crashed"}\n' >"$FACTS_JSON"
  [[ -s "$FACTS_JSON" ]] || printf '{"parse_ok": false, "error": "helper printed nothing"}\n' >"$FACTS_JSON"

  _a A01 "the workflow parses as a YAML mapping" '.parse_ok == true'
  _a A02 "triggers are exactly push and workflow_dispatch (the key on is found, however PyYAML spells it)" '.trigger_found == true and .triggers == ["push","workflow_dispatch"]'
  _a A03 "the push trigger is branches [main] and nothing else (no paths, tags or ignore filter)" '.push == {"branches": ["main"]}'
  _a A04 "workflow_dispatch has exactly the inputs sha (string, optional) and dry_run (boolean, default false)" \
    '(.dispatch_inputs | keys) == ["dry_run","sha"] and .dispatch_inputs.sha.type == "string" and .dispatch_inputs.sha.required == false and .dispatch_inputs.dry_run.type == "boolean" and .dispatch_inputs.dry_run.default == false and .dispatch_inputs.dry_run.required == false'
  _a A05 "one job named gate with no job-level if, continue-on-error, needs or strategy" \
    '.job_ids == ["gate"] and ((.job_keys | map(select(. == "if" or . == "continue-on-error" or . == "needs" or . == "strategy")) | length) == 0)'
  _a A06 "no step has an if or a continue-on-error (nothing can skip a push or soften a failure)" \
    '(.steps | length) == 2 and ([.steps[] | select(.has_if or .has_continue_on_error)] | length) == 0'
  _a A07 "exactly one step runs the gate script" '.gate_step_count == 1'
  _a A08 "the gate step runs exactly: bash scripts/codeql-main-alert-gate.sh" '[.steps[] | select(.run != null)] | map(.run | gsub("^\\s+|\\s+$"; "")) == ["bash scripts/codeql-main-alert-gate.sh"]'
  _a A09 "the gate step has no || ; & | or newline that could swallow the exit status" '[.steps[] | select(.run != null) | .run | gsub("\\n$"; "") | select(test("\\|\\||;|&|\\||\\n"))] | length == 0'
  _a A10 "the gate step follows a checkout that fetches the script and does not persist credentials" \
    '.gate_step_index == 1 and (.steps[0].uses | test("^actions/checkout@")) and (.steps[0].with["persist-credentials"] == false) and ((.steps[0].with["sparse-checkout"] | tostring) | contains("scripts/codeql-main-alert-gate.sh"))'
  _a A11 "the gate step env provides GH_TOKEN, GH_REPO, SHA and DRY_RUN" \
    '(["GH_TOKEN","GH_REPO","SHA","DRY_RUN"] - .gate_env_keys) == []'
  _a A12 "GH_TOKEN is the workflow token, in every event" \
    '[.evals[] | .GH_TOKEN] | all(. == "SYNTHETIC-TOKEN")'
  _a A13 "GH_REPO is the repository, in every event" \
    '[.evals[] | .GH_REPO] | all(. == "example-org/example-repo")'
  _a A14 "SHA is the pushed commit for a push and for a dispatch without a sha" \
    '.evals.push.SHA == .expected_values.sha and .evals.dispatch_default.SHA == .expected_values.sha and .evals.dispatch_dry.SHA == .expected_values.sha'
  _a A15 "SHA is the dispatched sha when one is given" '.evals.dispatch_sha.SHA == .expected_values.dispatch_sha'
  _a A16 "DRY_RUN is false for a push" '.evals.push.DRY_RUN == "false"'
  _a A17 "DRY_RUN follows the dispatch input (true when true, false when false or absent)" \
    '.evals.dispatch_dry.DRY_RUN == "true" and .evals.dispatch_dry_false.DRY_RUN == "false" and .evals.dispatch_default.DRY_RUN == "false"'
  _a A18 "permissions are exactly contents:read security-events:read issues:write checks:read" \
    '.permissions == {"contents":"read","security-events":"read","issues":"write","checks":"read"}'
  _a A19 "concurrency group is the fixed string codeql-main-alert-gate and never cancels a verdict" \
    '.concurrency.group == "codeql-main-alert-gate" and .concurrency["cancel-in-progress"] == false'
  _a A20 "the script defaults (poll interval, polls, settle polls, deadline) were found in the gate script" \
    '[.script[]] | all(type == "number" and . > 0)'
  _a A21 "timeout-minutes leaves room after the script deadline for one hung call plus the degraded upsert (300 s)" \
    '(.job_timeout | type) == "number" and (.job_timeout * 60) >= (.script.deadline_seconds + 300)'
  _a A22 "the poll budgets fit inside the deadline (so a clean exhaustion degrades by cap, not by clock)" \
    '((.script.max_polls - 1) * .script.poll_interval) + ((.script.settle_polls - 1) * .script.poll_interval) <= .script.deadline_seconds'
  _a A23 "no run: block contains a GitHub expression (event data reaches the script by env only)" \
    '[.steps[] | select(.run != null) | .run | select(contains("${{"))] | length == 0'
  _a A24 "every action is pinned to a 40-hex commit SHA" \
    '[.steps[] | select(.uses != null) | .uses] as $u | ($u | length) >= 1 and ($u | all(test("@[0-9a-f]{40}$")))'
  _a A25 "no top-level needs/workflow_run (the gate is not part of any chain)" '(.top_level_keys | map(select(. == "needs" or . == "workflow_run")) | length) == 0'

  return "$(grep -c '^FAIL' "$CHECK_OUT")"
}

# expected number of assertions per check_wf run (a hand-counted anchor; the floor below is re-derived from a green run)
CHECKS_PER_RUN=25

# ---------------------------------------------------------------------------------------------
# Pristine workflow: every assertion must pass, and the engine must have run all of them.
# ---------------------------------------------------------------------------------------------
echo "== pristine workflow: every wiring assertion holds =="
P="$SANDBOX/pristine"; mkdir -p "$P" || exit 2
check_wf "$WF" "$GATE" "$P/out.txt"; prc=$?
eq "engine ran every assertion against the real workflow" "$CHECK_N" "$CHECKS_PER_RUN"
eq "engine recorded one line per assertion" "$(wc -l <"$P/out.txt" | tr -d ' ')" "$CHECKS_PER_RUN"
eq "the real workflow has zero failing wiring assertions" "$prc" "0"
while read -r verdict id desc; do
  if [[ "$verdict" == "ok" ]]; then pass "$id $desc"; else fail "$id $desc"; fi
done <"$P/out.txt"
t "the PyYAML quirk is real and handled: on parses to boolean True, not the string on" jq -e '.on_key_is_bool_true == true and .on_key_is_string == false' "$P/out.txt.facts.json"

# ---------------------------------------------------------------------------------------------
# Mutation rows. mutate_wf <label> <expected-failing-id> <sed -E expression>: the edit is applied to a COPY of the
# pristine workflow; it must LAND (the copy differs), the engine must see the defect (the owning assertion FAILs),
# and the engine must still have run every assertion (a crashed engine cannot pass a mutant by erroring).
# ---------------------------------------------------------------------------------------------
echo "== mutation rows: each defect must land and red the assertion that owns it =="
MI=0
mutate_wf() {
  local label="$1" want_id="$2" expr="$3" m rc=0
  MI=$((MI + 1)); m="$SANDBOX/m$MI"; mkdir -p "$m" || exit 2
  sed -E "$expr" "$WF" >"$m/wf.yml" || { fail "mutant $MI ($label): sed failed"; return; }
  if cmp -s "$WF" "$m/wf.yml"; then fail "mutant $MI ($label): the mutation did NOT land"; return; fi
  check_wf "$m/wf.yml" "$GATE" "$m/out.txt" || rc=$?
  if [[ "$rc" -gt 0 ]] && grep -q "^FAIL $want_id " "$m/out.txt" && [[ "$CHECK_N" -eq "$CHECKS_PER_RUN" ]]; then
    pass "mutant $MI ($label) lands and reds $want_id"
  else
    fail "mutant $MI ($label): $want_id did not fail (failing: $(grep '^FAIL' "$m/out.txt" | cut -d' ' -f2 | tr '\n' ' '))"
  fi
}
G='bash scripts\/codeql-main-alert-gate\.sh'
mutate_wf "continue-on-error: true on the gate step" A06 "s/^(        run: ${G})\$/\\1\\n        continue-on-error: true/"
mutate_wf "continue-on-error: true on the job" A05 's/^(    timeout-minutes: 40)$/\1\n    continue-on-error: true/'
mutate_wf "|| true after the script" A09 "s/^(        run: ${G})\$/\\1 || true/"
mutate_wf "|| true after the script (exact command)" A08 "s/^(        run: ${G})\$/\\1 || true/"
mutate_wf "DRY_RUN expression inverted" A16 "s/\&\& 'true' \|\| 'false' \}\}/\&\& 'false' || 'true' }}/"
mutate_wf "DRY_RUN expression inverted (dispatch)" A17 "s/\&\& 'true' \|\| 'false' \}\}/\&\& 'false' || 'true' }}/"
mutate_wf "DRY_RUN pinned to true" A16 "s/^(          DRY_RUN: ).*\$/\\1'true'/"
mutate_wf "step if: skips a push" A06 "s/^(      - name: Evaluate CodeQL alerts for the pushed commit)\$/\\1\\n        if: github.event_name != 'push'/"
mutate_wf "job if: skips a push" A05 "s/^(    runs-on: ubuntu-latest)\$/\\1\\n    if: github.event_name != 'push'/"
mutate_wf "push renamed to pull_request, branches: [main] kept" A02 's/^  push:$/  pull_request:/'
mutate_wf "workflow_run trigger added" A02 's/^(  workflow_dispatch:)$/  workflow_run:\n    workflows: [x]\n    types: [completed]\n\1/'
mutate_wf "push narrowed by a paths filter" A03 's/^(    branches: \[main\])$/\1\n    paths: [docs\/**]/'
mutate_wf "GH_TOKEN deleted from the env" A11 '/^          GH_TOKEN:/d'
mutate_wf "GH_REPO deleted from the env" A11 '/^          GH_REPO:/d'
mutate_wf "SHA deleted from the env" A11 '/^          SHA:/d'
mutate_wf "GH_TOKEN no longer the workflow token" A12 's/^(          GH_TOKEN: ).*$/\1${{ secrets.OTHER }}/'
mutate_wf "SHA taken from the event before-sha" A14 's/\$\{\{ inputs\.sha \|\| github\.sha \}\}/${{ github.event.before }}/'
mutate_wf "SHA ignores the dispatched sha" A15 's/\$\{\{ inputs\.sha \|\| github\.sha \}\}/${{ github.sha }}/'
mutate_wf "timeout-minutes cut below the script deadline" A21 's/^(    timeout-minutes: )40$/\120/'
mutate_wf "an extra permission" A18 's/^(  checks: read)$/\1\n  pull-requests: write/'
mutate_wf "contents permission widened" A18 's/^(  contents: )read$/\1write/'
mutate_wf "concurrency cancels in progress" A19 's/cancel-in-progress: false/cancel-in-progress: true/'
mutate_wf "concurrency group derived from the ref" A19 's/group: codeql-main-alert-gate/group: codeql-${{ github.ref }}/'
mutate_wf "event data interpolated into run:" A23 "s/^(        run: ${G})\$/\\1 \"\${{ github.event.head_commit.message }}\"/"
mutate_wf "an action pinned by tag" A24 's/(uses: actions\/checkout)@[0-9a-f]{40} # v4\.3\.1/\1@v4/'
mutate_wf "checkout persists credentials" A10 's/persist-credentials: false/persist-credentials: true/'
mutate_wf "gate step is not the one that runs the script" A07 "s/^(        run: )${G}\$/\\1echo skipped/"

# Cross-file mutants: the SCRIPT's own defaults are the other half of A20..A22.
sm="$SANDBOX/script-mut"; mkdir -p "$sm" || exit 2
for spec in "deadline 1800 to 2400 (no room left in the 40 minute job)|A21|s/(DEADLINE_SECONDS:-)1800/\12400/" \
            "poll interval 30 to 300 (budgets no longer fit the deadline)|A22|s/(POLL_INTERVAL:-)30\}/\1300}/" \
            "settle polls default removed|A20|s/^SETTLE_POLLS=.*$/SETTLE_POLLS=\"\${SETTLE_POLLS:-x}\"/"; do
  IFS='|' read -r label want expr <<<"$spec"
  MI=$((MI + 1)); mkdir -p "$sm/$MI" || exit 2; rc=0
  sed -E "$expr" "$GATE" >"$sm/$MI/gate.sh" || { fail "script mutant $MI: sed failed"; continue; }
  if cmp -s "$GATE" "$sm/$MI/gate.sh"; then fail "script mutant $MI ($label): the mutation did NOT land"; continue; fi
  check_wf "$WF" "$sm/$MI/gate.sh" "$sm/$MI/out.txt" || rc=$?
  if [[ "$rc" -gt 0 ]] && grep -q "^FAIL $want " "$sm/$MI/out.txt" && [[ "$CHECK_N" -eq "$CHECKS_PER_RUN" ]]; then
    pass "script mutant $MI ($label) lands and reds $want"
  else
    fail "script mutant $MI ($label): $want did not fail (failing: $(grep '^FAIL' "$sm/$MI/out.txt" | cut -d' ' -f2 | tr '\n' ' '))"
  fi
done

# ---------------------------------------------------------------------------------------------
# Engine controls: an unreadable or non-workflow input is RED on A01, never green and never a crash.
# ---------------------------------------------------------------------------------------------
echo "== engine controls: an unreadable workflow cannot read as green =="
ec="$SANDBOX/engine"; mkdir -p "$ec" || exit 2
printf 'on: [\n  push\n' >"$ec/broken.yml"
rc=0; check_wf "$ec/broken.yml" "$GATE" "$ec/broken.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL A01 ' "$ec/broken.out" && pass "malformed YAML fails A01" || fail "malformed YAML fails A01"
printf -- '- just\n- a list\n' >"$ec/list.yml"
rc=0; check_wf "$ec/list.yml" "$GATE" "$ec/list.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL A01 ' "$ec/list.out" && pass "a YAML list (not a workflow) fails A01" || fail "a YAML list (not a workflow) fails A01"
rc=0; check_wf "$ec/does-not-exist.yml" "$GATE" "$ec/missing.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL A01 ' "$ec/missing.out" && pass "a missing workflow fails A01" || fail "a missing workflow fails A01"
rc=0; check_wf "$WF" "$ec/no-such-script.sh" "$ec/noscript.out" || rc=$?
[[ "$rc" -gt 0 ]] && grep -q '^FAIL A20 ' "$ec/noscript.out" && pass "a missing gate script fails A20 (the budget assertions cannot pass vacuously)" || fail "a missing gate script fails A20"
printf 'name: x\njobs: {}\n' >"$ec/empty.yml"
rc=0; check_wf "$ec/empty.yml" "$GATE" "$ec/empty.out" || rc=$?
[[ "$rc" -ge 10 ]] && pass "a workflow with no triggers and no job fails many assertions ($rc)" || fail "a workflow with no triggers and no job fails many assertions (got $rc)"
eq "the engine still ran every assertion against the empty workflow" "$CHECK_N" "$CHECKS_PER_RUN"

# ---------------------------------------------------------------------------------------------
# Verdict. The floor is reported with printf + exit, outside the pass/fail helpers.
# ---------------------------------------------------------------------------------------------
printf '\nassertions=%d passes=%d fails=%d floor=%d\n' "$ASSERTS" "$passes" "$fails" "$FLOOR"
if [[ "$fails" -gt 0 ]]; then
  printf '[RED] %d assertion(s) failed:\n' "$fails" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
if [[ "$ASSERTS" -lt "$FLOOR" ]]; then
  printf '[RED] assertion floor not met: %d < %d (a case stopped running)\n' "$ASSERTS" "$FLOOR" >&2
  exit 1
fi
printf '[GREEN] codeql-main-alert-gate workflow wiring suite\n'
exit 0
