#!/usr/bin/env bash
# Suite for .github/workflows/merge-queue-stall-check.yml (#9454, L10/L19).
#
# The stall probe is the only post-enable detector for "a required check never reports on
# merge_group, the entry pends until the queue ejects it silently". Its safety rests on numbers
# that live in two files (threshold in the workflow, timeout + build window in the ruleset .tf)
# and on a jq filter nobody executed. This suite therefore does two things the text-grep style
# cannot:
#   1. STRUCTURE: parse the workflow with PyYAML (key `on` parses as the boolean True, handled)
#      and assert cron / workflow_dispatch / numeric threshold / threshold < the .tf's
#      check_response_timeout_minutes / the position filter equals the .tf's
#      max_entries_to_build / least-privilege permissions / no continue-on-error / label set /
#      no `${{ }}` interpolation inside any run body. The two .tf numbers are DERIVED from
#      infra/github/ruleset-ci-required.tf (comments stripped), never hand-written here.
#   2. BEHAVIOUR: extract the real run body of the detection step, put a `gh` stub on PATH that
#      serves canned GraphQL JSON, and EXECUTE it for: head entry old -> files; entry deeper than
#      the build window old -> does NOT file; young -> no file; empty queue -> no file; gh error ->
#      the step fails loudly; existing open issue -> deduped.
# Every structural/behavioural arm is proven live by a mutation row run against a SANDBOX COPY of
# the workflow (the mutation is diffed against the pristine copy first, then the guard must go
# RED for the expected reason), with an unmutated sandbox copy as the positive control. The
# suite ends in an EXACT assertion floor, so a row silently dropped or a verdict helper neutered
# turns it red rather than green.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF_REAL="$REPO_ROOT/.github/workflows/merge-queue-stall-check.yml"
TF_REAL="$REPO_ROOT/infra/github/ruleset-ci-required.tf"
SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin"

# EXACT number of PASS verdicts a healthy run records. Update deliberately when a row is added.
EXPECTED_PASSES=31

passes=0; fails=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before anything is trusted.
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
python3 -c 'import yaml' 2>/dev/null || { echo "[FATAL] PyYAML is required" >&2; exit 2; }
[[ -f "$WF_REAL" ]] || { echo "[FATAL] missing $WF_REAL" >&2; exit 2; }
[[ -f "$TF_REAL" ]] || { echo "[FATAL] missing $TF_REAL" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; assert_fixture_dir "$BIN"; mkdir -p "$BIN" || exit 2

# ---- python helper: workflow facts + .tf merge_queue params as JSON ----------------------------
HELPER="$WORK/facts.py"
cat > "$HELPER" <<'PY'
import json, re, sys, yaml

def wf_facts(path):
    d = yaml.safe_load(open(path))
    on = d.get("on", d.get(True))          # PyYAML parses a bare `on:` key as boolean True
    jobs = d.get("jobs") or {}
    runs, coe, steps = [], [], []
    for jn, job in jobs.items():
        if "continue-on-error" in job:
            coe.append("job:%s" % jn)
        for st in job.get("steps") or []:
            steps.append({"name": st.get("name"), "run": st.get("run")})
            if "continue-on-error" in st:
                coe.append("step:%s" % st.get("name"))
            if isinstance(st.get("run"), str):
                runs.append(st["run"])
    job = next(iter(jobs.values())) if jobs else {}
    return {
        "on_keys": sorted(on.keys()) if isinstance(on, dict) else (on if isinstance(on, list) else [on]),
        "cron": [s.get("cron") for s in ((on or {}).get("schedule") or [])] if isinstance(on, dict) else [],
        "permissions": d.get("permissions"),
        "job_permissions": job.get("permissions"),
        "env": job.get("env") or {},
        "continue_on_error": coe,
        "runs": runs,
        "steps": steps,
        "has_expr_in_run": any("${{" in r for r in runs),
    }

def tf_params(path):
    s = open(path).read()
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)                     # block comments
    s = "\n".join(re.sub(r"(#|//).*$", "", l) for l in s.split("\n"))  # line comments
    m = re.search(r"merge_queue\s*\{(.*?)\n\s*\}", s, flags=re.S)
    out = {}
    if m:
        for l in m.group(1).split("\n"):
            km = re.match(r'\s*([a-z_]+)\s*=\s*"?([^"\s]+)"?\s*$', l)
            if km:
                out[km.group(1)] = km.group(2)
    return out

if __name__ == "__main__":
    cmd, path = sys.argv[1], sys.argv[2]
    print(json.dumps(wf_facts(path) if cmd == "wf" else tf_params(path)))
PY

TF_JSON="$(python3 "$HELPER" tf "$TF_REAL")"
TF_TIMEOUT="$(jq -r '.check_response_timeout_minutes // empty' <<<"$TF_JSON")"
TF_BUILD="$(jq -r '.max_entries_to_build // empty' <<<"$TF_JSON")"
if [[ ! "$TF_TIMEOUT" =~ ^[0-9]+$ || ! "$TF_BUILD" =~ ^[0-9]+$ ]]; then
  echo "[FATAL] could not derive check_response_timeout_minutes ('$TF_TIMEOUT') / max_entries_to_build ('$TF_BUILD') from $TF_REAL" >&2
  exit 2
fi

REASON=""

# structural_check <workflow-file>: 0 = every structural invariant holds; else REASON says which.
structural_check() {
  local wf="$1" f
  REASON=""
  f="$(python3 "$HELPER" wf "$wf" 2>/dev/null)" || { REASON="workflow does not parse as YAML"; return 1; }
  local thr maxpos
  jq -e '.on_keys | index("workflow_dispatch")' <<<"$f" >/dev/null || { REASON="workflow_dispatch trigger missing"; return 1; }
  jq -e '(.cron | length) > 0 and all(.cron[]; type == "string" and length > 0)' <<<"$f" >/dev/null \
    || { REASON="schedule cron missing"; return 1; }
  thr="$(jq -r '.env.STALL_THRESHOLD_MINUTES // empty' <<<"$f")"
  [[ "$thr" =~ ^[0-9]+$ ]] || { REASON="STALL_THRESHOLD_MINUTES missing or not numeric ('$thr')"; return 1; }
  if (( thr >= TF_TIMEOUT )); then
    REASON="threshold $thr >= check_response_timeout_minutes $TF_TIMEOUT (probe could not report before the queue ejects)"; return 1
  fi
  maxpos="$(jq -r '.env.MAX_ENTRIES_TO_BUILD // empty' <<<"$f")"
  if [[ "$maxpos" != "$TF_BUILD" ]]; then
    REASON="MAX_ENTRIES_TO_BUILD '$maxpos' != max_entries_to_build $TF_BUILD in the .tf"; return 1
  fi
  if ! jq -e 'any(.runs[]; test("select\\(\\.position <= \\$maxpos\\)") and test("--argjson maxpos \"\\$MAX_ENTRIES_TO_BUILD\""))' <<<"$f" >/dev/null; then
    REASON="position filter (position <= \$maxpos from MAX_ENTRIES_TO_BUILD) missing from the run body"; return 1
  fi
  jq -e '.permissions == {"contents":"read","issues":"write"} and (.job_permissions == null)' <<<"$f" >/dev/null \
    || { REASON="permissions are not exactly contents:read + issues:write"; return 1; }
  jq -e '.continue_on_error | length == 0' <<<"$f" >/dev/null \
    || { REASON="continue-on-error present: $(jq -c .continue_on_error <<<"$f")"; return 1; }
  jq -e '.has_expr_in_run | not' <<<"$f" >/dev/null || { REASON="a run body interpolates \${{ }}"; return 1; }
  jq -e 'any(.runs[]; test("gh label create merge-queue-stall")) and any(.runs[]; test("gh label create action-required"))' <<<"$f" >/dev/null \
    || { REASON="label-creation step does not create both merge-queue-stall and action-required"; return 1; }
  jq -e 'any(.runs[]; test("--label merge-queue-stall --label action-required"))' <<<"$f" >/dev/null \
    || { REASON="filed issue label set lacks merge-queue-stall + action-required"; return 1; }
  jq -e 'any(.runs[]; test("gh run list [^\\n]*--event merge_group") and test("gh api graphql -f query="))' <<<"$f" >/dev/null \
    || { REASON="issue body lacks agent-runnable gh run list --event merge_group / gh api graphql commands"; return 1; }
  return 0
}

# ---- gh stub + behavioural harness --------------------------------------------------------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: serves canned GraphQL JSON, records issue creation, refuses anything unexpected.
echo "gh $*" >> "$GH_STUB_LOG"
case "$1 $2" in
  "api graphql")
    if [[ "${GH_STUB_FAIL:-0}" == "1" ]]; then echo "stub: graphql 502" >&2; exit 1; fi
    cat "$GH_STUB_GRAPHQL" ;;
  "label create") exit 0 ;;
  "issue list") printf '%b' "${GH_STUB_EXISTING:-}" ;;
  "issue create")
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) echo "TITLE:$2" >> "$GH_STUB_LOG.create"; shift 2 ;;
        --label) echo "LABEL:$2" >> "$GH_STUB_LOG.create"; shift 2 ;;
        --body)  printf '%s' "$2" > "$GH_STUB_LOG.body"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh"

iso_ago() { date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ; }

# node <position> <minutes-ago> <pr> <state>
node() {
  jq -n --arg t "$(iso_ago "$2")" --argjson p "$1" --argjson n "$3" --arg s "${4:-AWAITING_CHECKS}" \
    '{enqueuedAt:$t, position:$p, state:$s, pullRequest:{number:$n, url:("https://github.com/o/r/pull/\($n)")}}'
}
queue_json() { jq -s '{data:{repository:{mergeQueue:{entries:{nodes:.}}}}}'; }

CASE_RC=0; CASE_CREATES=0; CASE_TITLES=""; CASE_LABELS=""; CASE_BODY=""
# run_case <workflow> <graphql-json-file> [fail] [existing-issues-tsv]
run_case() {
  local wf="$1" gql="$2" failgh="${3:-0}" existing="${4:-}" f body thr maxpos
  f="$(python3 "$HELPER" wf "$wf")"
  body="$WORK/run-body.sh"
  jq -r '.steps[] | select(.name | test("^Detect stalled")) | .run' <<<"$f" > "$body"
  thr="$(jq -r '.env.STALL_THRESHOLD_MINUTES' <<<"$f")"
  maxpos="$(jq -r '.env.MAX_ENTRIES_TO_BUILD // "999"' <<<"$f")"
  rm -f "$WORK/gh.log" "$WORK/gh.log.create" "$WORK/gh.log.body"
  env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_REPO="o/r" GH_TOKEN=x \
    STALL_THRESHOLD_MINUTES="$thr" MAX_ENTRIES_TO_BUILD="$maxpos" \
    GH_STUB_LOG="$WORK/gh.log" GH_STUB_GRAPHQL="$gql" GH_STUB_FAIL="$failgh" GH_STUB_EXISTING="$existing" \
    bash "$body" >"$WORK/out.txt" 2>"$WORK/err.txt"
  CASE_RC=$?
  CASE_CREATES="$(grep -c '^TITLE:' "$WORK/gh.log.create" 2>/dev/null || true)"; CASE_CREATES="${CASE_CREATES:-0}"
  CASE_TITLES="$(grep '^TITLE:' "$WORK/gh.log.create" 2>/dev/null || true)"
  CASE_LABELS="$(grep '^LABEL:' "$WORK/gh.log.create" 2>/dev/null | tr '\n' ' ' || true)"
  CASE_BODY="$(cat "$WORK/gh.log.body" 2>/dev/null || true)"
}

# behav_check <workflow>: executes the run body against canned queues. 0 = all behaviours hold.
behav_check() {
  local wf="$1" g="$WORK/q.json"
  REASON=""
  { node 1 50 101; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 && "$CASE_TITLES" == *"PR #101 pending"* ]] \
    || { REASON="position 1 older than threshold did not file exactly one issue (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  [[ "$CASE_LABELS" == *"merge-queue-stall"* && "$CASE_LABELS" == *"action-required"* ]] \
    || { REASON="filed issue labels lack merge-queue-stall + action-required ('$CASE_LABELS')"; return 1; }
  [[ "$CASE_BODY" == *"gh run list"* && "$CASE_BODY" == *"--event merge_group"* && "$CASE_BODY" == *"pr-101-"* \
     && "$CASE_BODY" == *"gh api graphql"* && "$CASE_BODY" != *"@PR@"* && "$CASE_BODY" != *"@REPO@"* ]] \
    || { REASON="filed issue body lacks substituted agent-runnable gh commands"; return 1; }

  { node 1 10 102; node 3 80 103; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="position 3 older than threshold filed (healthy deep queue false positive; rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }

  { node 1 10 104; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] || { REASON="young entry filed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }

  printf '%s' '{"data":{"repository":{"mergeQueue":null}}}' > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] || { REASON="null mergeQueue was not a green no-op (rc=$CASE_RC)"; return 1; }
  printf '%s' '{"data":{"repository":{"mergeQueue":{"entries":{"nodes":[]}}}}}' > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] || { REASON="empty queue was not a green no-op (rc=$CASE_RC)"; return 1; }

  { node 1 50 105; } | queue_json > "$g"
  run_case "$wf" "$g" 1
  [[ "$CASE_RC" -ne 0 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="gh error did not fail the step loudly (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }

  { node 2 50 106; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] \
    || { REASON="position 2 (last building slot) older than threshold did not file (creates=$CASE_CREATES)"; return 1; }

  { node 1 50 107; node 3 90 108; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_CREATES" -eq 1 && "$CASE_TITLES" == *"PR #107 pending"* ]] \
    || { REASON="mixed queue: wanted exactly PR #107 filed (creates=$CASE_CREATES titles=$CASE_TITLES)"; return 1; }

  { node 1 50 109; } | queue_json > "$g"
  run_case "$wf" "$g" 0 "9\tmerge-queue stall: PR #109 pending >45m\n"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="open stall issue for the same PR was not deduped (creates=$CASE_CREATES)"; return 1; }
  return 0
}

# ---- rows ---------------------------------------------------------------------------------------
if structural_check "$WF_REAL"; then pass "S0 real workflow: structural invariants hold"; else fail "S0 real workflow: structural invariants hold ($REASON)"; fi
if behav_check "$WF_REAL"; then pass "B0 real workflow: executed run body behaves on canned queues"; else fail "B0 real workflow: executed run body behaves on canned queues ($REASON)"; fi

# Derivation sanity: the .tf numbers are real and the relation is not vacuous.
if [[ "$TF_TIMEOUT" -gt 0 && "$TF_BUILD" -ge 1 ]]; then pass "D0 derived tf timeout=$TF_TIMEOUT build window=$TF_BUILD (positive integers)"; else fail "D0 derived tf values"; fi

# Individual structural facts, so a failure names the fact (the real workflow, not a mutant).
FACTS="$(python3 "$HELPER" wf "$WF_REAL")"
chk() { if jq -e "$2" <<<"$FACTS" >/dev/null; then pass "$1"; else fail "$1"; fi; }
chk "S1 on.schedule cron present" '(.cron | length) > 0'
chk "S2 workflow_dispatch trigger present (manual / Inngest-driven runs)" '.on_keys | index("workflow_dispatch")'
chk "S3 STALL_THRESHOLD_MINUTES numeric" '.env.STALL_THRESHOLD_MINUTES | test("^[0-9]+$")'
chk "S4 permissions exactly contents:read + issues:write" '.permissions == {"contents":"read","issues":"write"}'
chk "S5 no continue-on-error anywhere" '.continue_on_error | length == 0'
chk "S6 no \${{ }} inside any run body" '.has_expr_in_run | not'
if (( $(jq -r '.env.STALL_THRESHOLD_MINUTES' <<<"$FACTS") < TF_TIMEOUT )); then pass "S7 threshold < tf check_response_timeout_minutes ($TF_TIMEOUT)"; else fail "S7 threshold < tf timeout"; fi
if [[ "$(jq -r '.env.MAX_ENTRIES_TO_BUILD' <<<"$FACTS")" == "$TF_BUILD" ]]; then pass "S8 MAX_ENTRIES_TO_BUILD == tf max_entries_to_build ($TF_BUILD)"; else fail "S8 MAX_ENTRIES_TO_BUILD == tf"; fi
chk "S9 label set carries merge-queue-stall and action-required" 'any(.runs[]; test("--label merge-queue-stall --label action-required")) and any(.runs[]; test("gh label create action-required"))'
if grep -q 'detection latency = threshold + schedule delivery' "$WF_REAL" && grep -qi 'degraded' "$WF_REAL" && ! grep -q 'reported by about minute 55' "$WF_REAL"; then
  pass "S11 header measured-latency statement present, old minute-55 claim gone"
else
  fail "S11 header measured-latency statement present, old minute-55 claim gone"
fi

# ---- mutation engine ----------------------------------------------------------------------------
# mutate <label> <engine: structural|behav> <expected-reason-regex> <python-expr over s (str) returning str>
SB="$WORK/sandbox"; assert_fixture_dir "$SB"; mkdir -p "$SB" || exit 2
mutate() {
  local label="$1" engine="$2" want="$3" expr="$4" rc
  cp "$WF_REAL" "$SB/pristine.yml"
  MUT_EXPR="$expr" python3 - "$SB/pristine.yml" "$SB/mutant.yml" <<'PY'
import os, re, sys
s = open(sys.argv[1]).read()
out = eval(os.environ["MUT_EXPR"])
open(sys.argv[2], "w").write(out)
PY
  if cmp -s "$SB/pristine.yml" "$SB/mutant.yml"; then fail "$label (mutation did not land)"; return; fi
  "${engine}_check" "$SB/mutant.yml"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    fail "$label (guard stayed GREEN under the mutation)"
  elif grep -qE "$want" <<<"$REASON"; then
    pass "$label"
  else
    fail "$label (RED for the wrong reason: '$REASON', wanted /$want/)"
  fi
}

# Positive control: an UNMUTATED sandbox copy must be green on both engines, so a sandbox-harness
# fault cannot manufacture the RED verdicts below.
cp "$WF_REAL" "$SB/control.yml"
if structural_check "$SB/control.yml" && behav_check "$SB/control.yml"; then pass "M0 positive control: unmutated sandbox copy is GREEN on both engines"; else fail "M0 positive control ($REASON)"; fi

mutate "M1 threshold raised to the timeout -> RED" structural 'threshold 60 >= check_response_timeout_minutes' \
  "s.replace(\"STALL_THRESHOLD_MINUTES: '45'\", \"STALL_THRESHOLD_MINUTES: '$TF_TIMEOUT'\")"
mutate "M2 threshold made non-numeric -> RED" structural 'not numeric' \
  "s.replace(\"STALL_THRESHOLD_MINUTES: '45'\", \"STALL_THRESHOLD_MINUTES: 'soon'\")"
mutate "M3 position filter removed from the run body -> RED (structural)" structural 'position filter' \
  "s.replace('            | select(.position <= \$maxpos)\n', '')"
mutate "M3b position filter removed -> RED (behavioural: depth-3 entry now files)" behav 'position 3 older than threshold filed' \
  "s.replace('            | select(.position <= \$maxpos)\n', '')"
mutate "M4 MAX_ENTRIES_TO_BUILD drifted from the .tf -> RED" structural 'MAX_ENTRIES_TO_BUILD' \
  "s.replace(\"MAX_ENTRIES_TO_BUILD: '$TF_BUILD'\", \"MAX_ENTRIES_TO_BUILD: '$((TF_BUILD + 3))'\")"
mutate "M5 cron removed -> RED" structural 'schedule cron missing' \
  "re.sub(r\"  schedule:\\n    - cron:[^\\n]*\\n\", '', s)"
mutate "M6 workflow_dispatch removed -> RED" structural 'workflow_dispatch trigger missing' \
  "s.replace('  workflow_dispatch: {}\n', '')"
mutate "M7 continue-on-error added at job level -> RED" structural 'continue-on-error present' \
  "s.replace('    timeout-minutes: 10\n', '    timeout-minutes: 10\n    continue-on-error: true\n')"
mutate "M8 permissions widened -> RED" structural 'permissions are not exactly' \
  "s.replace('  issues: write\n', '  issues: write\n  actions: write\n', 1)"
mutate "M9 action-required dropped from the filed label set -> RED" structural 'label set lacks|does not create both' \
  "s.replace('--label merge-queue-stall --label action-required', '--label merge-queue-stall')"
mutate "M9b action-required label creation dropped -> RED" structural 'does not create both' \
  "s.replace('gh label create action-required', 'gh label list action-required')"
mutate "M10 event interpolation added to a run body -> RED" structural 'interpolates' \
  "s.replace('owner=\"\${GH_REPO%/*}\"', 'owner=\"\${{ github.event.inputs.x }}\"')"
mutate "M11 set -e dropped: gh error no longer fails the step -> RED (behavioural)" behav 'gh error did not fail' \
  "s.replace('set -euo pipefail', 'set -uo pipefail', 1)"
mutate "M12 age threshold ignored (every entry files) -> RED (behavioural)" behav 'older than threshold filed|young entry filed' \
  "s.replace('| select(\$age > \$thr)', '')"
mutate "M13 issue body drops the gh run list command -> RED" structural 'agent-runnable' \
  "s.replace('gh run list', 'open the UI')"
mutate "M14 dedupe anchor broken -> RED (behavioural)" behav 'not deduped' \
  "s.replace('match_anchor=\"merge-queue stall: PR #\${pr} pending\"', 'match_anchor=\"merge-queue stall: PR #\${pr}X pending\"')"
# M15: a negative-space check on the S11 text arm, run directly rather than via mutate() (the header is a comment, not YAML structure).
cp "$WF_REAL" "$SB/m15.yml"; printf '# an entry stuck from minute 0 is reported by about minute 55 at the latest\n' >> "$SB/m15.yml"
if grep -q 'reported by about minute 55' "$SB/m15.yml" && ! cmp -s "$SB/m15.yml" "$WF_REAL"; then pass "M15 minute-55 claim is detectable by the S11 text arm"; else fail "M15 minute-55 claim detectable"; fi

# ---- accounting (exact floor, printf + exit so a neutered helper cannot mask it) ----------------
# Passes must equal the constant EXACTLY.
printf '=== %s passed, %s failed (expected exactly %s passes) ===\n' "$passes" "$fails" "$EXPECTED_PASSES"
if [[ "$fails" -ne 0 ]]; then
  printf '[FAIL] rows failed:\n' >&2; printf '  %s\n' "${FAILED[@]}" >&2; exit 1
fi
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf '[FAIL] pass count %s != exact floor %s (a row was dropped or added)\n' "$passes" "$EXPECTED_PASSES" >&2; exit 1
fi
exit 0
