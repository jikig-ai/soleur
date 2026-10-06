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
EXPECTED_PASSES=61

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
            steps.append({"name": st.get("name"), "run": st.get("run"), "if": st.get("if")})
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
  # ---- drain step invariants (#9513) -----------------------------------------
  local drain_step drain_run
  drain_step="$(jq -c '.steps[] | select(.name == "Drain stale stall issues")' <<<"$f" | head -n 1)"
  [[ -n "$drain_step" ]] || { REASON="drain step 'Drain stale stall issues' missing"; return 1; }
  [[ "$(jq -r '.if // empty' <<<"$drain_step")" == "always()" ]] \
    || { REASON="drain step is not gated on if: always() (an aborted detect run must not skip it)"; return 1; }
  drain_run="$(jq -r '.run // empty' <<<"$drain_step")"
  [[ "$drain_run" == *"gh issue list"* && "$drain_run" == *"--json number,title --label merge-queue-stall"* && "$drain_run" == *"-L 50"* ]] \
    || { REASON="drain enumeration is not a bounded (-L 50) label-scoped gh issue list --json"; return 1; }
  [[ "$drain_run" == *"gh issue view"* && "$drain_run" == *"--json state"* && "$drain_run" == *"gh issue close"* ]] \
    || { REASON="drain does not read the target PR state before closing"; return 1; }
  # The flag-arg form (--jq '<expr>' / --jq='...') on an issue-list line —
  # anchored to the command so a comment mentioning `--jq` cannot false-hit.
  ! grep -qE 'gh issue list[^#\n]*--jq[ =]' <<<"$drain_run" \
    || { REASON="drain pushes a filter through gh --jq (use standalone jq — gh --jq does not forward --arg)"; return 1; }
  return 0
}

# ---- gh stub + behavioural harness --------------------------------------------------------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh. It serves RAW data and APPLIES the arguments the workflow passes, so the real projection runs:
#   api graphql   serves the full raw queue JSON, then (a) answers null unless the query names
#                 mergeQueue(branch:"main"), (b) cuts entries to the query's `entries(first:N)`, and
#                 (c) keeps only the node fields the query SELECTS (enqueuedAt, position, state,
#                 pullRequest.number, pullRequest.url): a field the query forgot to ask for is absent,
#                 exactly as GitHub answers.
#   issue list    serves the raw issue array and APPLIES --state (an absent --state is treated as ALL, so
#                 the workflow must pin it, it may not lean on gh's default), --label, --limit and --json
#                 (field projection), then runs the workflow's own --jq expression on the result.
#   issue create  records the title, labels and body.
echo "gh $*" >> "$GH_STUB_LOG"
case "$1 $2" in
  "api graphql")
    if [[ "${GH_STUB_FAIL:-0}" == "1" ]]; then echo "stub: graphql 502" >&2; exit 1; fi
    shift 2; query=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f) case "$2" in query=*) query="${2#query=}" ;; esac; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -n "$query" ]] || { echo "stub gh: graphql call without a query= field" >&2; exit 64; }
    branch="$(grep -oE 'mergeQueue\(branch:"[^"]*"\)' <<<"$query" | sed 's/.*branch:"\(.*\)".*/\1/')"
    first="$(grep -oE 'entries\(first:[0-9]+\)' <<<"$query" | grep -oE '[0-9]+' | head -n 1)"
    has() { if grep -qw -- "$1" <<<"$query"; then echo true; else echo false; fi; }
    jq --arg branch "$branch" --argjson first "${first:-0}" \
       --argjson enq "$(has enqueuedAt)" --argjson pos "$(has position)" \
       --argjson st "$(has state)" --argjson num "$(has number)" --argjson url "$(has url)" '
      .data.repository.mergeQueue |= (
        if . == null or $branch != "main" then null
        else .entries.nodes |= (.[0:$first] | map(
          (if $enq then . else del(.enqueuedAt) end)
          | (if $pos then . else del(.position) end)
          | (if $st then . else del(.state) end)
          | (if $num then . else del(.pullRequest.number) end)
          | (if $url then . else del(.pullRequest.url) end)))
        end)' "$GH_STUB_GRAPHQL" ;;
  "label create")
    if [[ "${GH_STUB_LABEL_FAIL:-0}" == "1" ]]; then echo "stub: label already exists" >&2; exit 1; fi
    exit 0 ;;
  "issue list")
    if [[ "${GH_STUB_LIST_FAIL:-0}" == "1" ]]; then echo "stub: issue list 502" >&2; exit 1; fi
    shift 2; state="all"; label=""; limit=30; fields=""; jqx=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --state) state="$2"; shift 2 ;;
        --label) label="$2"; shift 2 ;;
        --limit|-L) limit="$2"; shift 2 ;;
        --json)  fields="$2"; shift 2 ;;
        --jq)    jqx="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    # --jq is optional: the drain lists --json then filters in standalone jq
    # (the real `gh --jq` does not forward --arg, so the workflow never passes
    # an arg-bearing filter through it).
    [[ -n "$fields" ]] || { echo "stub gh: issue list needs --json" >&2; exit 64; }
    jq -c --arg state "$state" --arg label "$label" --argjson limit "$limit" --arg fields "$fields" '
      map(select($state == "all" or (.state | ascii_downcase) == $state))
      | map(select($label == "" or any(.labels[]?; .name == $label)))
      | .[0:$limit]
      | map(with_entries(select(.key as $k | ($fields | split(",")) | index($k))))' "$GH_STUB_ISSUES" \
      | if [[ -n "$jqx" ]]; then jq -r "$jqx"; else jq -c '.'; fi ;;
  "issue view")
    # Serves per-number target states from GH_STUB_STATES (lines `NUM=STATE`;
    # `NUM=FAIL` simulates a view failure — the drain must fail toward keeping).
    shift 2; num="$1"
    while [[ $# -gt 0 ]]; do
      case "$1" in *) shift ;; esac
    done
    st="$(awk -F= -v n="$num" '$1==n {print $2}' "${GH_STUB_STATES:-/dev/null}" 2>/dev/null || true)"
    case "$st" in
      FAIL) echo "stub: issue view 500" >&2; exit 1 ;;
      "")   echo "stub gh: no canned state for issue $num" >&2; exit 1 ;;
      *)    jq -nc --arg s "$st" '{state:$s}' ;;
    esac ;;
  "issue close")
    shift 2; num="$1"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --comment) echo "COMMENT:$2" >> "$GH_STUB_LOG.close"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "CLOSE:$num" >> "$GH_STUB_LOG.close"
    if [[ "${GH_STUB_CLOSE_FAIL:-0}" == "1" ]]; then echo "stub: issue close 500" >&2; exit 1; fi
    exit 0 ;;
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
# issue <number> <state> <label> <title>: one raw `gh issue list` row (labels as GitHub returns them)
issue() {
  jq -n --argjson n "$1" --arg s "$2" --arg l "$3" --arg t "$4" \
    '{number:$n, state:$s, title:$t, labels:(if $l == "" then [] else [{name:$l}] end)}'
}
issues_json() { jq -s '.'; }

# run_case <workflow> <graphql-json-file> [fail] [issues-json-file] [label-create-fails]
run_case() {
  local wf="$1" gql="$2" failgh="${3:-0}" issues="${4:-}" labelfail="${5:-0}" f body thr maxpos
  f="$(python3 "$HELPER" wf "$wf")"
  body="$WORK/run-body.sh"
  jq -r '.steps[] | select(.name | test("^Detect stalled")) | .run' <<<"$f" > "$body"
  thr="$(jq -r '.env.STALL_THRESHOLD_MINUTES' <<<"$f")"
  maxpos="$(jq -r '.env.MAX_ENTRIES_TO_BUILD // "999"' <<<"$f")"
  rm -f "$WORK/gh.log" "$WORK/gh.log.create" "$WORK/gh.log.body"
  if [[ -z "$issues" ]]; then
    issues="$WORK/no-issues.json"
    assert_fixture_dir "$issues"
    printf '[]' > "$issues"
  fi
  env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_REPO="o/r" GH_TOKEN=x \
    STALL_THRESHOLD_MINUTES="$thr" MAX_ENTRIES_TO_BUILD="$maxpos" \
    GH_STUB_LOG="$WORK/gh.log" GH_STUB_GRAPHQL="$gql" GH_STUB_FAIL="$failgh" GH_STUB_ISSUES="$issues" GH_STUB_LABEL_FAIL="$labelfail" \
    bash "$body" >"$WORK/out.txt" 2>"$WORK/err.txt"
  CASE_RC=$?
  CASE_CREATES="$(grep -c '^TITLE:' "$WORK/gh.log.create" 2>/dev/null || true)"; CASE_CREATES="${CASE_CREATES:-0}"
  CASE_TITLES="$(grep '^TITLE:' "$WORK/gh.log.create" 2>/dev/null || true)"
  CASE_LABELS="$(grep '^LABEL:' "$WORK/gh.log.create" 2>/dev/null | tr '\n' ' ' || true)"
  CASE_BODY="$(cat "$WORK/gh.log.body" 2>/dev/null || true)"
}

# behav_check <workflow>: executes the run body against raw queues / raw issue lists. 0 = all behaviours hold.
behav_check() {
  local wf="$1" g="$WORK/q.json" iss="$WORK/issues.json"
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
  # the projection the real query + real jq produce: age, URL and state reach the body
  [[ "$CASE_BODY" == *"was enqueued about 50 minutes ago"* ]] || { REASON="issue body does not carry the computed age (enqueued about 50 minutes ago)"; return 1; }
  [[ "$CASE_BODY" == *"https://github.com/o/r/pull/101"* ]] || { REASON="issue body lacks the PR url (the query did not select it)"; return 1; }
  [[ "$CASE_BODY" == *"queue state AWAITING_CHECKS"* ]] || { REASON="issue body lacks the queue state (the query did not select it)"; return 1; }
  # honesty: a SUSPECTED stall, may be a healthy slow build, triage listed before the real-stall explanation
  [[ "$CASE_TITLES" == *"suspected"* ]] || { REASON="issue title does not say the stall is suspected"; return 1; }
  [[ "$CASE_BODY" == "SUSPECTED merge-queue stall (needs verification)"* && "$CASE_BODY" == *"healthy slow build"* ]] \
    || { REASON="issue body does not open with the suspected / healthy-slow-build caveat"; return 1; }
  local pre_triage="${CASE_BODY%%Triage (every step*}" pre_real="${CASE_BODY%%If it is a real stall*}"
  [[ "$pre_triage" != "$CASE_BODY" && "${#pre_triage}" -lt "${#pre_real}" ]] \
    || { REASON="issue body does not list the agent-runnable triage before the real-stall explanation"; return 1; }

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

  # a stalled entry BEHIND a young head must still be read (entries(first:N) covers more than the head)
  { node 1 10 110; node 2 50 111; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_CREATES" -eq 1 && "$CASE_TITLES" == *"PR #111 pending"* ]] \
    || { REASON="stalled entry behind a young head was not filed (the query reads too few entries; creates=$CASE_CREATES)"; return 1; }

  # the label-create step must tolerate an already-existing label (|| true)
  { node 1 50 112; } | queue_json > "$g"
  run_case "$wf" "$g" 0 "" 1
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] \
    || { REASON="an already-existing label aborted the step (label create is not guarded; rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }

  # dedupe, driven through the real `gh issue list --state --label --json --jq` projection
  { node 1 50 109; } | queue_json > "$g"
  { issue 9 OPEN merge-queue-stall "merge-queue stall: PR #109 pending >45m (suspected, verify first)"; } | issues_json > "$iss"
  run_case "$wf" "$g" 0 "$iss"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="open stall issue for the same PR was not deduped (creates=$CASE_CREATES)"; return 1; }
  { issue 9 CLOSED merge-queue-stall "merge-queue stall: PR #109 pending >45m"; } | issues_json > "$iss"
  run_case "$wf" "$g" 0 "$iss"
  [[ "$CASE_CREATES" -eq 1 ]] \
    || { REASON="a CLOSED stall issue suppressed a new stall (the open-state filter is missing; creates=$CASE_CREATES)"; return 1; }
  { issue 9 OPEN other-label "merge-queue stall: PR #109 pending >45m"; } | issues_json > "$iss"
  run_case "$wf" "$g" 0 "$iss"
  [[ "$CASE_CREATES" -eq 1 ]] \
    || { REASON="an unrelated-label issue with a matching title suppressed a new stall (the label filter is missing; creates=$CASE_CREATES)"; return 1; }
  { node 1 50 10; } | queue_json > "$g"
  { issue 9 OPEN merge-queue-stall "merge-queue stall: PR #109 pending >45m"; } | issues_json > "$iss"
  run_case "$wf" "$g" 0 "$iss"
  [[ "$CASE_CREATES" -eq 1 && "$CASE_TITLES" == *"PR #10 pending"* ]] \
    || { REASON="PR #109's issue suppressed PR #10 (the ' pending' anchor is missing; creates=$CASE_CREATES)"; return 1; }
  return 0
}

# ---- drain behavioural harness (#9513) -------------------------------------------------
# run_drain <workflow> <issues-json> <states-file> [list-fail] [close-fail]
# The states file maps target PR numbers to `gh issue view --json state` results:
# one `NUM=STATE` line each; `NUM=FAIL` simulates a view error (must fail toward
# keeping). Closes land in GH_STUB_LOG.close as CLOSE:<issue> + COMMENT:<text>.
DRAIN_RC=0; DRAIN_CLOSE_LIST=""
run_drain() {
  local wf="$1" iss="$2" sts="$3" listfail="${4:-0}" closefail="${5:-0}" f body
  f="$(python3 "$HELPER" wf "$wf")"
  body="$WORK/drain-body.sh"
  jq -r '.steps[] | select(.name == "Drain stale stall issues") | .run' <<<"$f" > "$body"
  if [[ ! -s "$body" ]]; then DRAIN_RC=64; DRAIN_CLOSE_LIST=""; return; fi
  rm -f "$WORK/gh.log" "$WORK/gh.log.close" "$WORK/drain.out" "$WORK/drain.err"
  env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_REPO="o/r" GH_TOKEN=x RUN_URL="https://run/x" \
    GH_STUB_LOG="$WORK/gh.log" GH_STUB_ISSUES="$iss" GH_STUB_STATES="$sts" \
    GH_STUB_LIST_FAIL="$listfail" GH_STUB_CLOSE_FAIL="$closefail" \
    bash "$body" >"$WORK/drain.out" 2>"$WORK/drain.err"
  DRAIN_RC=$?
  DRAIN_CLOSE_LIST="$(grep '^CLOSE:' "$WORK/gh.log.close" 2>/dev/null | cut -d: -f2 | tr '\n' ' ' || true)"
  DRAIN_ALL="$(cat "$WORK/drain.out" "$WORK/drain.err" 2>/dev/null || true)"
}

stall_title() { printf 'merge-queue stall: PR #%s pending >45m (suspected, verify first)' "$1"; }

# drain_check <workflow>: executes the real drain step body against canned issues.
# 0 = every drain behaviour holds.
drain_check() {
  local wf="$1" iss="$WORK/drain-issues.json" sts="$WORK/drain-states.txt"
  REASON=""

  # An OPEN target is kept — the close decision is the whole guard, so this arm
  # runs first: a mutation that closes everything REDs here before the merged arm.
  { issue 8 OPEN merge-queue-stall "$(stall_title 101)"; } | issues_json > "$iss"
  printf '101=OPEN\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_RC" -eq 0 && -z "$DRAIN_CLOSE_LIST" ]] \
    || { REASON="open target's stall issue was drained (closes=$DRAIN_CLOSE_LIST rc=$DRAIN_RC)"; return 1; }

  # A MERGED target drains.
  printf '101=MERGED\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_RC" -eq 0 && "$DRAIN_CLOSE_LIST" == *"8"* ]] \
    || { REASON="merged target's stall issue was not drained (closes=$DRAIN_CLOSE_LIST rc=$DRAIN_RC)"; return 1; }

  # A CLOSED-unmerged target drains too.
  printf '101=CLOSED\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_CLOSE_LIST" == *"8"* ]] \
    || { REASON="closed-unmerged target's stall issue was not drained"; return 1; }

  # The close is per-issue: a merged sibling drains while the open one stays.
  { issue 8 OPEN merge-queue-stall "$(stall_title 101)";
    issue 9 OPEN merge-queue-stall "$(stall_title 102)";
    issue 10 OPEN merge-queue-stall "hand-filed note with no PR anchor"; } | issues_json > "$iss"
  printf '101=MERGED\n102=OPEN\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_CLOSE_LIST" == *"8"* && "$DRAIN_CLOSE_LIST" != *"9"* && "$DRAIN_CLOSE_LIST" != *"10"* ]] \
    || { REASON="mixed sweep did not close exactly the merged-target issue (closes=$DRAIN_CLOSE_LIST)"; return 1; }

  # A title without the filed 'PR #N pending' anchor is never examined or closed.
  { issue 10 OPEN merge-queue-stall "hand-filed note with no PR anchor"; } | issues_json > "$iss"
  : > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_RC" -eq 0 && -z "$DRAIN_CLOSE_LIST" \
     && "$(grep -c 'issue view' "$WORK/gh.log" 2>/dev/null || true)" -eq 0 ]] \
    || { REASON="a non-filed-title stall issue was examined or closed (closes=$DRAIN_CLOSE_LIST)"; return 1; }

  # An unreadable target state fails toward keeping, with a warning.
  { issue 8 OPEN merge-queue-stall "$(stall_title 101)"; } | issues_json > "$iss"
  printf '101=FAIL\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ "$DRAIN_RC" -eq 0 && -z "$DRAIN_CLOSE_LIST" && "$DRAIN_ALL" == *"warning"* ]] \
    || { REASON="an unreadable target state did not fail toward keeping (closes=$DRAIN_CLOSE_LIST)"; return 1; }

  # An enumeration failure fails OPEN: sanitized ::error:: and zero closes.
  printf '101=MERGED\n' > "$sts"
  run_drain "$wf" "$iss" "$sts" 1
  [[ "$DRAIN_RC" -eq 0 && -z "$DRAIN_CLOSE_LIST" && "$DRAIN_ALL" == *"::error::"* ]] \
    || { REASON="a failed enumeration did not fail open with ::error:: (closes=$DRAIN_CLOSE_LIST)"; return 1; }

  # Label scope: an other-label issue with a stall-shaped title is never drained.
  { issue 12 OPEN other-label "$(stall_title 105)"; } | issues_json > "$iss"
  printf '105=MERGED\n' > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ -z "$DRAIN_CLOSE_LIST" ]] \
    || { REASON="an issue outside the merge-queue-stall label was drained"; return 1; }

  # The -L 50 bound emits a cap notice when the sweep hits it.
  { for i in $(seq 1 51); do issue "$i" OPEN merge-queue-stall "$(stall_title 9$i)"; done; } | issues_json > "$iss"
  { for i in $(seq 1 51); do echo "9$i=OPEN"; done; } > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ -z "$DRAIN_CLOSE_LIST" && "$DRAIN_ALL" == *"::notice::"* ]] \
    || { REASON="the -L 50 enumeration cap did not emit a ::notice::"; return 1; }
  return 0
}

# ---- rows ---------------------------------------------------------------------------------------
if structural_check "$WF_REAL"; then pass "S0 real workflow: structural invariants hold"; else fail "S0 real workflow: structural invariants hold ($REASON)"; fi
if behav_check "$WF_REAL"; then pass "B0 real workflow: executed run body behaves on canned queues"; else fail "B0 real workflow: executed run body behaves on canned queues ($REASON)"; fi
if drain_check "$WF_REAL"; then pass "B1 real workflow: drain step closes only issues whose target PR left OPEN"; else fail "B1 real workflow: drain step behaves ($REASON)"; fi

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
if grep -q 'FALSE POSITIVES ARE POSSIBLE' "$WF_REAL" && grep -q 'SUSPECTED stall that needs verification' "$WF_REAL" && grep -qE 'STALL_THRESHOLD_MINUTES, 45\) sits BELOW the measured merge_group CI maximum' "$WF_REAL"; then
  pass "S12 header states the false-positive possibility and that the threshold (45) sits below the measured merge_group CI maximum"
else
  fail "S12 header states the false-positive possibility and the threshold-below-CI-maximum fact"
fi
chk "S13 drain step exists, gated on if: always()" 'any(.steps[]; .name == "Drain stale stall issues" and .if == "always()")'
chk "S14 drain enumeration is a bounded label-scoped --json list" 'any(.runs[]; test("gh issue list") and test("\\-L 50") and test("--label merge-queue-stall") and test("--json number,title"))'
chk "S15 drain reads the target state before closing" 'any(.runs[]; test("gh issue view") and test("--json state") and test("gh issue close"))'

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

# Positive control: an UNMUTATED sandbox copy must be green on all engines, so a sandbox-harness
# fault cannot manufacture the RED verdicts below.
cp "$WF_REAL" "$SB/control.yml"
if structural_check "$SB/control.yml" && behav_check "$SB/control.yml" && drain_check "$SB/control.yml"; then pass "M0 positive control: unmutated sandbox copy is GREEN on all engines"; else fail "M0 positive control ($REASON)"; fi

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

# ---- query / issue-list mutations (F4): the stub serves RAW data and applies what the workflow passes, so
# each of these changes what the real projection produces and must turn the behavioural engine RED.
Q="                        "
mutate "Q1 enqueuedAt dropped from the query -> RED (the age can never be computed, the probe never fires)" behav 'position 1 older than threshold did not file' \
  "s.replace('${Q}enqueuedAt\n', '')"
mutate "Q2 position dropped from the query -> RED (the false-positive filter reads null)" behav 'position 3 older than threshold filed' \
  "s.replace('${Q}position\n', '')"
mutate "Q3 state dropped from the query -> RED (the body loses the queue state)" behav 'lacks the queue state' \
  "s.replace('${Q}state\n', '')"
mutate "Q4 mergeQueue(branch:\"dev\") -> RED (reads the wrong branch)" behav 'position 1 older than threshold did not file' \
  "s.replace('mergeQueue(branch:\"main\")', 'mergeQueue(branch:\"dev\")')"
mutate "Q5 entries(first:50) -> first:1 -> RED (a stall behind the head is never read)" behav 'behind a young head' \
  "s.replace('entries(first:50)', 'entries(first:1)', 1)"
mutate "Q6 pullRequest url dropped from the query -> RED" behav 'lacks the PR url' \
  "s.replace('pullRequest { number url }', 'pullRequest { number }')"
mutate "Q7 --state open dropped from the dedupe read -> RED (a closed issue suppresses a new stall)" behav 'CLOSED stall issue suppressed' \
  "s.replace(' --state open', '')"
mutate "Q8 --label merge-queue-stall dropped from the dedupe read -> RED" behav 'label filter is missing' \
  "s.replace('--label merge-queue-stall --json', '--json')"
mutate "Q9 dedupe --jq columns swapped ([.title, .number]) -> RED" behav 'not deduped' \
  "s.replace('[.number, .title] | @tsv', '[.title, .number] | @tsv')"
mutate "Q10 age divisor changed (/60 -> /6) -> RED" behav 'computed age' \
  "s.replace('((\$age/60)|floor)', '((\$age/6)|floor)')"
mutate "Q11 gh label create made fatal (|| true removed) -> RED" behav 'label create is not guarded' \
  "s.replace('2>/dev/null || true', '2>/dev/null')"
mutate "Q12 dedupe anchor loses the ' pending' suffix -> RED (PR #109 suppresses PR #10)" behav "' pending' anchor" \
  "s.replace('PR #\${pr} pending\"', 'PR #\${pr}\"', 1)"
mutate "Q13 title no longer says the stall is suspected -> RED" behav 'does not say the stall is suspected' \
  "s.replace(' (suspected, verify first)', '')"
mutate "Q14 body no longer opens with the SUSPECTED caveat -> RED" behav 'suspected / healthy-slow-build caveat' \
  "s.replace('SUSPECTED merge-queue stall (needs verification)', 'Merge-queue stall')"

# ---- drain mutations (#9513): the drain engine executes the real drain run body ---------
mutate "MD1 drain step renamed -> RED (structural)" structural 'drain step' \
  "s.replace('name: Drain stale stall issues', 'name: Drain something else')"
mutate "MD2 drain loses if: always() -> RED (structural)" structural 'always' \
  "s.replace('        if: always()\\n', '')"
mutate "MD3 drain drops the state read -> RED (merged target kept)" drain 'merged target' \
  "s.replace('gh issue view ', 'echo ')"
mutate "MD4 drain closes OPEN targets -> RED" drain 'open target' \
  "s.replace('\"\$state\" != \"OPEN\"', '\"\$state\" == \"OPEN\"')"
mutate "MD5 drain drops the label scope -> RED" drain 'outside the merge-queue-stall label' \
  "s.replace('--json number,title --label merge-queue-stall', '--json number,title')"
mutate "MD6 drain drops the -L 50 bound -> RED" drain 'cap' \
  "s.replace('-L 50 ', '')"

# ---- controls: the mutation engine and the chk helper must FAIL on inputs that must fail ---------------
# control_fails <label> <wanted-message-substring> <cmd...>: drive a verdict helper once with an input that
# must fail; the failure counter must move by exactly one (and the message must carry the substring); the
# recorded failure is then unwound. A control that did not fail aborts by printf + exit, so a neutered helper
# (`pass "$label"; return`) cannot be masked by a green count.
control_fails() {
  local label="$1" want_msg="$2"; shift 2
  local p0="$passes" f0="$fails" n0="${#FAILED[@]}" moved=0 msg_ok=0
  "$@" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] && msg_ok=1
  passes="$p0"; fails="$f0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: $label fails on an input that must fail"
  else
    printf '[FATAL] control: %s did not record a failure carrying "%s" on an input that must fail (moved=%s msg=%s)\n' "$label" "$want_msg" "$moved" "$msg_ok" >&2
    exit 1
  fi
}
control_fails "mutate (mutation did not land)" "mutation did not land" mutate "CTL-a" structural 'x' "s"
control_fails "mutate (guard stayed GREEN)" "stayed GREEN" mutate "CTL-b" structural 'x' "s + '# harmless\n'"
control_fails "mutate (RED for the wrong reason)" "wrong reason" mutate "CTL-c" structural 'will-not-match' \
  "s.replace(\"STALL_THRESHOLD_MINUTES: '45'\", \"STALL_THRESHOLD_MINUTES: '$TF_TIMEOUT'\")"
control_fails "chk (a false jq expression)" "CTL-d" chk "CTL-d" 'false'
control_fails "chk (a missing key)" "CTL-e" chk "CTL-e" '.no_such_fact'

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
