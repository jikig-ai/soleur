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
# 3. CAUSE NAMING (#12283, D16): the `gh` stub also serves `api -X GET repos/o/r/actions/runs` from canned run JSON
#    synthesized from the live shape, and APPLIES event, the created range and per_page/--paginate, plus the
#    UNWINDOWED per-workflow merge_group-history lookup (`actions/workflows/<id>/runs`); a stub that ignored the
#    filters would make every cause row vacuous, so the L9 and L25 rows prove the stub itself filters and exits 64 on
#    an unexpected request. Rows L1-L24 and L26 drive the real run body (positive rows name the cause, every NEGATIVE
#    row also asserts the lookup ran, so a failed lookup cannot satisfy it); mutation rows C1-C26 prove each
#    load-bearing literal of `queue_candidate_cause`, run only the row they name, and are scored a KILL only if
#    (1) the mutant still compiles (bash -n), (2) it still completes a clean entry, (3) the named row went red with
#    ITS OWN assertion message, and (4) NO captured stream (the run's stdout/stderr and the stderr of every jq call,
#    logged by a wrapper because the workflow itself sends the naming jq's stderr to /dev/null) holds a crash
#    signature (jq: error, unbound variable, syntax error, command not found, Traceback, NameError). A run that
#    does is UNRESOLVED and FAILS the suite: a typo in a jq literal or an unbound variable on the naming path
#    otherwise turns every named row red for the wrong reason. CTL-i..j2 prove the criterion on those classes and
#    CTL-k proves lookup_ran is what kills C26 (both run-list fetches skipped).
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

# The EXACT number of PASS verdicts a healthy run records is the literal next to the final floor check at the bottom
# (EXPECTED_PASSES=<n>, adjacent to its `if`). Update it deliberately when a row is added or removed.

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
  jq -e '.permissions == {"contents":"read","issues":"write","actions":"read"} and (.job_permissions == null)' <<<"$f" >/dev/null \
    || { REASON="permissions are not exactly contents:read + issues:write + actions:read"; return 1; }
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
#   api -X GET repos/<GH_REPO>/actions/runs   serves GH_STUB_RUNS (a raw array of runs) and APPLIES the request:
#                 event=<push|merge_group> filters on .event, created=>=<iso> filters on .created_at (range),
#                 per_page=N sets the page size (capped by GH_STUB_PAGE_CAP to force several pages), and
#                 --paginate emits ONE {total_count, workflow_runs:[...]} object per page (without it only page
#                 1 is served), exactly as `gh api --paginate` prints them. exclude_pull_requests is REQUIRED.
#   api -X GET repos/<GH_REPO>/actions/workflows/<id>/runs   the UNWINDOWED merge_group-history lookup (D16): requires
#                 event=merge_group and per_page=1, REJECTS created=, exclude_pull_requests and --paginate (a windowed or
#                 paginated lookup is a different, wrong question and exits 64), and answers
#                 {total_count: <ALL merge_group runs of that workflow_id in GH_STUB_EVER and GH_STUB_RUNS>,
#                 workflow_runs: first per_page}; GH_STUB_WFHIST_FAIL=1 makes it fail; GH_STUB_WFHIST_BODY=<raw>
#                 answers with that raw body instead (a malformed reply).
#                 ANY other shape (other verb, endpoint, field, event, created form, missing field) exits 64, so
#                 a workflow that drops a filter fails loudly here instead of being served unfiltered data.
#   issue create  rejects (exit 1, nothing recorded) a title longer than GH_STUB_CREATE_MAX (default 256, GitHub's
#                 limit), counting every ATTEMPT in GH_STUB_LOG.attempts.
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
  "api -X")
    shift 2
    [[ "${1-}" == "GET" ]] || { echo "stub gh: api -X needs GET (got '${1-}')" >&2; exit 64; }
    shift
    endpoint=""; paginate=0; event=""; created=""; per_page=""; excl=""; has_created=0; has_excl=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --paginate) paginate=1; shift ;;
        -f) case "${2-}" in
              event=*)   event="${2#event=}" ;;
              created=*) created="${2#created=}"; has_created=1 ;;
              *) echo "stub gh: unexpected -f field '${2-}'" >&2; exit 64 ;;
            esac; shift 2 ;;
        -F) case "${2-}" in
              per_page=*) per_page="${2#per_page=}" ;;
              exclude_pull_requests=*) excl="${2#exclude_pull_requests=}"; has_excl=1 ;;
              *) echo "stub gh: unexpected -F field '${2-}'" >&2; exit 64 ;;
            esac; shift 2 ;;
        repos/*) endpoint="$1"; shift ;;
        *) echo "stub gh: unexpected api argument '$1'" >&2; exit 64 ;;
      esac
    done
    if [[ "$endpoint" =~ ^repos/${GH_REPO}/actions/workflows/([0-9]+)/runs$ ]]; then
      wid="${BASH_REMATCH[1]}"
      [[ "$event" == "merge_group" ]] || { echo "stub gh: the history lookup needs event=merge_group (got '$event')" >&2; exit 64; }
      [[ "$per_page" == "1" ]] || { echo "stub gh: the history lookup needs per_page=1 (got '$per_page')" >&2; exit 64; }
      [[ "$has_created" -eq 0 && "$has_excl" -eq 0 && "$paginate" -eq 0 ]] \
        || { echo "stub gh: the history lookup must be unwindowed, unpaginated and take no exclude_pull_requests" >&2; exit 64; }
      if [[ "${GH_STUB_WFHIST_FAIL:-0}" == "1" ]]; then printf 'stub: history 502 caf\303\251 bad gateway\n' >&2; exit 1; fi
      # GH_STUB_WFHIST_BODY: answer with this RAW body (a malformed reply, e.g. a non-numeric total_count)
      if [[ -n "${GH_STUB_WFHIST_BODY:-}" ]]; then printf '%s\n' "$GH_STUB_WFHIST_BODY"; exit 0; fi
      jq -c -s --argjson w "$wid" --argjson size "$per_page" '
        (add | map(select(.event == "merge_group" and .workflow_id == $w))) as $f
        | {total_count: ($f | length), workflow_runs: $f[0:$size]}' "${GH_STUB_EVER:?stub gh: GH_STUB_EVER unset}" "${GH_STUB_RUNS:?stub gh: GH_STUB_RUNS unset}"
      exit 0
    fi
    [[ "$endpoint" == "repos/${GH_REPO}/actions/runs" ]] || { echo "stub gh: unexpected endpoint '$endpoint'" >&2; exit 64; }
    case "$event" in push|merge_group) : ;; *) echo "stub gh: unexpected event '$event'" >&2; exit 64 ;; esac
    created_re='^>=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
    [[ "$created" =~ $created_re ]] || { echo "stub gh: created must be a >=<iso> range (got '$created')" >&2; exit 64; }
    [[ "$per_page" =~ ^[0-9]+$ && "$per_page" -ge 1 && "$per_page" -le 100 ]] || { echo "stub gh: per_page must be 1..100 (got '$per_page')" >&2; exit 64; }
    [[ "$excl" == "true" ]] || { echo "stub gh: exclude_pull_requests=true is required (got '$excl')" >&2; exit 64; }
    if [[ "${GH_STUB_RUNS_FAIL:-0}" == "1" ]]; then printf 'stub: runs 502 caf\303\251 bad gateway\n' >&2; exit 1; fi
    size="$per_page"; [[ -n "${GH_STUB_PAGE_CAP:-}" && "$GH_STUB_PAGE_CAP" -lt "$size" ]] && size="$GH_STUB_PAGE_CAP"
    jq -c --arg e "$event" --arg since "${created#>=}" --argjson size "$size" --argjson pg "$paginate" '
      (map(select(.event == $e and .created_at >= $since)) | sort_by(.created_at) | reverse) as $f
      | ([range(0; ($f | length); $size)] | if length == 0 then [0] else . end) as $starts
      | ($starts | if $pg == 1 then . else .[0:1] end)[]
      | {total_count: ($f | length), workflow_runs: $f[.:(. + $size)]}' "${GH_STUB_RUNS:?stub gh: GH_STUB_RUNS unset}" ;;
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
    # Failure precedes the record: a failed real close leaves the issue OPEN,
    # so a stub that records before failing would claim a close that never was.
    if [[ "${GH_STUB_CLOSE_FAIL:-0}" == "1" ]]; then echo "stub: issue close 500" >&2; exit 1; fi
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --comment) echo "COMMENT:$2" >> "$GH_STUB_LOG.close"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "CLOSE:$num" >> "$GH_STUB_LOG.close"
    exit 0 ;;
  "issue create")
    shift 2; ctitle=""; cbody=""; clabels=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) ctitle="$2"; shift 2 ;;
        --label) clabels+=("$2"); shift 2 ;;
        --body)  cbody="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "ATTEMPT" >> "$GH_STUB_LOG.attempts"
    # GitHub answers 422 for a title over 256 characters; nothing is created.
    if [[ "${#ctitle}" -gt "${GH_STUB_CREATE_MAX:-256}" ]]; then echo "stub: 422 title is too long (${#ctitle})" >&2; exit 1; fi
    echo "TITLE:$ctitle" >> "$GH_STUB_LOG.create"
    for cl in "${clabels[@]}"; do echo "LABEL:$cl" >> "$GH_STUB_LOG.create"; done
    printf '%s' "$cbody" > "$GH_STUB_LOG.body"
    printf '%s' "$cbody" > "$GH_STUB_LOG.body.$(grep -c '^TITLE:' "$GH_STUB_LOG.create")" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh"

# Logging jq wrapper (first on the PATH of every run_case): the workflow sends jq's stderr to /dev/null in the cause
# lookup (`named=$(jq ... 2>/dev/null) || return 0`), so a jq COMPILE error in a mutated literal would be swallowed
# into the plain "suspected" form and a named row would go red for the wrong reason. The wrapper runs the real jq,
# appends its stderr to $JQ_ERR_LOG, and still forwards it and the exit code unchanged.
JQBIN="$WORK/jqbin"; assert_fixture_dir "$JQBIN"; mkdir -p "$JQBIN" || exit 2
JQ_REAL="$(PATH="$SANDBOX_PATH" command -v jq)" || { echo "[FATAL] jq not on $SANDBOX_PATH" >&2; exit 2; }
cat > "$JQBIN/jq" <<WRAP
#!/usr/bin/env bash
_e="\$(mktemp)" || exit 70
"$JQ_REAL" "\$@" 2>"\$_e"; _rc=\$?
if [[ -s "\$_e" ]]; then cat "\$_e" >> "\${JQ_ERR_LOG:-/dev/null}"; cat "\$_e" >&2; fi
rm -f "\$_e"; exit "\$_rc"
WRAP
chmod +x "$JQBIN/jq"
JQ_ERR_LOG="$WORK/jq-err.log"; STREAM_LOG="$WORK/streams.log"; : > "$JQ_ERR_LOG"; : > "$STREAM_LOG"
# A run that printed any of these produced a CRASH, not a verdict about the property a mutant targets.
CRASH_RE='jq: error|unbound variable|syntax error|command not found|Traceback|NameError'
crash_reset() { : > "$JQ_ERR_LOG"; : > "$STREAM_LOG"; }
crash_scan() { cat "$STREAM_LOG" "$JQ_ERR_LOG" 2>/dev/null | grep -m1 -E "$CRASH_RE" || true; }

iso_ago() { date -u -d "-$1 minutes" +%Y-%m-%dT%H:%M:%SZ; }

# node <position> <minutes-ago> <pr> <state>
node() {
  jq -n --arg t "$(iso_ago "$2")" --argjson p "$1" --argjson n "$3" --arg s "${4:-AWAITING_CHECKS}" \
    '{enqueuedAt:$t, position:$p, state:$s, pullRequest:{number:$n, url:("https://github.com/o/r/pull/\($n)")}}'
}
queue_json() { jq -s '{data:{repository:{mergeQueue:{entries:{nodes:.}}}}}'; }

CASE_RC=0; CASE_CREATES=0; CASE_ATTEMPTS=0; CASE_TITLES=""; CASE_LABELS=""; CASE_BODY=""
# Actions-runs inputs for run_case (reset by reset_runs): the raw runs file, a forced list failure, a page cap, the
# all-time merge_group history file (GH_STUB_EVER), a forced history-lookup failure, the stub's create title limit.
CASE_RUNS=""; CASE_RUNS_FAIL=0; CASE_PAGE_CAP=""; CASE_EVER=""; CASE_WFHIST_FAIL=0; CASE_CREATE_MAX=256; CASE_WFHIST_BODY=""
reset_runs() { CASE_RUNS=""; CASE_RUNS_FAIL=0; CASE_PAGE_CAP=""; CASE_EVER=""; CASE_WFHIST_FAIL=0; CASE_CREATE_MAX=256; CASE_WFHIST_BODY=""; }
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
  rm -f "$WORK/gh.log" "$WORK/gh.log.create" "$WORK/gh.log.attempts" "$WORK/gh.log.body" "$WORK"/gh.log.body.*
  local runs="$CASE_RUNS" ever="$CASE_EVER"
  if [[ -z "$ever" ]]; then
    ever="$WORK/no-ever.json"
    assert_fixture_dir "$ever"
    printf '[]' > "$ever"
  fi
  if [[ -z "$runs" ]]; then
    runs="$WORK/no-runs.json"
    assert_fixture_dir "$runs"
    printf '[]' > "$runs"
  fi
  if [[ -z "$issues" ]]; then
    issues="$WORK/no-issues.json"
    assert_fixture_dir "$issues"
    printf '[]' > "$issues"
  fi
  env -i PATH="$JQBIN:$BIN:$SANDBOX_PATH" HOME="$WORK" TMPDIR="$WORK" GH_REPO="o/r" GH_TOKEN=x JQ_ERR_LOG="$JQ_ERR_LOG" \
    STALL_THRESHOLD_MINUTES="$thr" MAX_ENTRIES_TO_BUILD="$maxpos" \
    GH_STUB_LOG="$WORK/gh.log" GH_STUB_GRAPHQL="$gql" GH_STUB_FAIL="$failgh" GH_STUB_ISSUES="$issues" GH_STUB_LABEL_FAIL="$labelfail" \
    GH_STUB_RUNS="$runs" GH_STUB_RUNS_FAIL="$CASE_RUNS_FAIL" GH_STUB_PAGE_CAP="$CASE_PAGE_CAP" \
    GH_STUB_EVER="$ever" GH_STUB_WFHIST_FAIL="$CASE_WFHIST_FAIL" GH_STUB_CREATE_MAX="$CASE_CREATE_MAX" \
    GH_STUB_WFHIST_BODY="$CASE_WFHIST_BODY" \
    bash "$body" >"$WORK/out.txt" 2>"$WORK/err.txt"
  CASE_RC=$?
  cat "$WORK/out.txt" "$WORK/err.txt" >> "$STREAM_LOG" 2>/dev/null || true
  CASE_CREATES="$(grep -c '^TITLE:' "$WORK/gh.log.create" 2>/dev/null || true)"; CASE_CREATES="${CASE_CREATES:-0}"
  CASE_ATTEMPTS="$(grep -c '^ATTEMPT' "$WORK/gh.log.attempts" 2>/dev/null || true)"; CASE_ATTEMPTS="${CASE_ATTEMPTS:-0}"
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

  # UNMERGEABLE (#10641, #10319): the queue is waiting for the author to rebase; the entry has no
  # merge_group build at all, so "pending > threshold" says nothing about a required check not
  # reporting. It must not be filed as a stall, and must not hide a real stall beside it.
  { node 1 120 113 UNMERGEABLE; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="an UNMERGEABLE entry older than threshold was filed as a stall (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  { node 1 120 114 UNMERGEABLE; node 2 50 115; } | queue_json > "$g"
  run_case "$wf" "$g"
  [[ "$CASE_CREATES" -eq 1 && "$CASE_TITLES" == *"PR #115 pending"* ]] \
    || { REASON="UNMERGEABLE head hid or replaced the real stall beside it (creates=$CASE_CREATES titles=$CASE_TITLES)"; return 1; }

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

  # A failed close warns and retries next sweep — it must not abort the loop
  # or mark the issue closed.
  { issue 8 OPEN merge-queue-stall "$(stall_title 101)"; } | issues_json > "$iss"
  printf '101=MERGED\n' > "$sts"
  run_drain "$wf" "$iss" "$sts" 0 1
  [[ "$DRAIN_RC" -eq 0 && -z "$DRAIN_CLOSE_LIST" && "$DRAIN_ALL" == *"warning"* ]] \
    || { REASON="a failed close was not contained (rc=$DRAIN_RC closes=$DRAIN_CLOSE_LIST)"; return 1; }

  # The -L 50 bound emits a cap notice when the sweep hits it.
  { for i in $(seq 1 51); do issue "$i" OPEN merge-queue-stall "$(stall_title "9$i")"; done; } | issues_json > "$iss"
  { for i in $(seq 1 51); do echo "9$i=OPEN"; done; } > "$sts"
  run_drain "$wf" "$iss" "$sts"
  [[ -z "$DRAIN_CLOSE_LIST" && "$DRAIN_ALL" == *"::notice::"* ]] \
    || { REASON="the -L 50 enumeration cap did not emit a ::notice::"; return 1; }
  return 0
}

# ---- stall-cause naming harness (#12283) ----------------------------------------------------------
# Canned runs are SYNTHESIZED from the live shape (id, name, path, workflow_id, event, head_branch, head_sha,
# status, conclusion, created_at, html_url; read-only probe of run 42336368201 on 2026-11-07), never copied:
# the ids, shas and workflow ids are invented. A loaded workflow shows its own `name:`; a workflow file that
# could not be loaded shows its PATH as the name (the `name == path` signature this feature keys on).
WF_PATH_CI=".github/workflows/ci.yml"
SHA0="0000000000000000000000000000000000000a00"   # a superseded temp ref's sha
SHA1="1111111111111111111111111111111111111b11"   # the latest temp ref's sha
qref() { printf 'gh-readonly-queue/main/pr-%s-%s' "$1" "$2"; }

# mkrun <id> <event> <name> <path> <workflow_id> <branch> <conclusion|""> <minutes-ago>
mkrun() {
  jq -n --argjson id "$1" --arg ev "$2" --arg name "$3" --arg path "$4" --argjson wid "$5" --arg br "$6" \
    --arg c "$7" --arg t "$(iso_ago "$8")" '
    {id:$id, name:$name, path:$path, workflow_id:$wid, event:$ev, head_branch:$br,
     head_sha:"2222222222222222222222222222222222222c22", run_number:1, run_attempt:1,
     status:(if $c == "" then "in_progress" else "completed" end),
     conclusion:(if $c == "" then null else $c end),
     created_at:$t, updated_at:$t, html_url:("https://github.com/o/r/actions/runs/\($id)"), pull_requests:[]}'
}
# mg_noise <branch> <minutes-ago> <id-base>: the six OTHER workflows that DID run on merge_group for the ref
# (the real incident: only ci.yml was missing, so "no merge_group run at all" never held).
mg_noise() {
  local b="$1" m="$2" i="$3"
  mkrun $((i + 1)) merge_group "PR quality guards" .github/workflows/pr-quality-guards.yml 201 "$b" success "$m"
  mkrun $((i + 2)) merge_group "Secret scan" .github/workflows/secret-scan.yml 202 "$b" success "$m"
  mkrun $((i + 3)) merge_group "Vendor pin verify" .github/workflows/vendor-pin-verify.yml 203 "$b" success "$m"
  mkrun $((i + 4)) merge_group "Tenant integration" .github/workflows/tenant-integration.yml 204 "$b" "" "$m"
  mkrun $((i + 5)) merge_group "Apply sentry infra" .github/workflows/apply-sentry-infra.yml 205 "$b" success "$m"
  mkrun $((i + 6)) merge_group "Merge queue CLA synthetics" .github/workflows/merge-queue-cla-synthetics.yml 206 "$b" success "$m"
}
# the real-incident run set for PR <pr> enqueued 50 minutes ago (queue entry built by the caller). The window opens 55
# minutes ago (enqueuedAt - 5 min of slack). Chronology of a poisoned main: the first temp ref is created right after the
# enqueue (48 min ago), it is superseded, and the NEW ref (46 min ago) carries the load failure. Both sit INSIDE the
# window by 7 and 9 minutes, so no mutant of the slack is what keeps the superseded ref in the lists (only L21 is
# about the slack), and both are older than the sign-flipped bound (45 min ago), which C10b relies on.
incident_runs() {
  local pr="$1" ref ref0
  ref="$(qref "$pr" "$SHA1")"; ref0="$(qref "$pr" "$SHA0")"
  mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 46          # THE failed load (name == path)
  mg_noise "$ref" 46 9100
  mkrun 9000 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref0" failure 48         # a superseded temp ref of the same PR
  mg_noise "$ref0" 48 9200
  mkrun 9300 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$(qref 999 "$SHA1")" failure 49   # an unrelated PR's ref
  mkrun 9302 push .github/workflows/other.yml .github/workflows/other.yml 170 main failure 49  # not a queue ref
  mkrun 9400 push .github/workflows/old.yml .github/workflows/old.yml 150 "$ref" failure 56    # before the window
}

title_n() { grep '^TITLE:' "$WORK/gh.log.create" 2>/dev/null | sed -n "${1}p" || true; }
body_n()  { cat "$WORK/gh.log.body.$1" 2>/dev/null || true; }
THR_REAL="$(python3 "$HELPER" wf "$WF_REAL" | jq -r '.env.STALL_THRESHOLD_MINUTES')"

# title_anchors_ok <title-line> <pr>: BOTH consumers of the filed title still match it: the dedupe anchor
# (a title that STARTS WITH `merge-queue stall: PR #N pending`) and the drain capture.
title_anchors_ok() {
  local t="${1#TITLE:}" pr="$2" got
  [[ "$t" == "merge-queue stall: PR #${pr} pending"* ]] || return 1
  got="$(printf '%s\n' "$t" | jq -Rr 'try (capture("PR #(?<pr>[0-9]+) pending") | .pr) catch ""')"
  [[ "$got" == "$pr" ]]
}
# lookup_ran <label> [entries]: BOTH run lists were requested once per entry and nothing warned. A failed or
# malformed lookup is fail-soft and ALSO yields the suspected form, so a negative row that does not assert the
# lookup ran could be satisfied by a broken lookup (the positive rows alone would carry the whole suite).
# LOOKUP_RAN_OFF=1 neuters it. ONLY the CTL-k control sets that: it proves that without this helper a mutant which skips
# BOTH run-list fetches (C26) stays green on every negative row, i.e. that the helper is what kills it.
LOOKUP_RAN_OFF=0
lookup_ran() {
  local l="$1" k="${2:-1}" np nm
  [[ "$LOOKUP_RAN_OFF" -ne 1 ]] || return 0
  np="$(grep -c 'actions/runs.*-f event=push' "$WORK/gh.log" 2>/dev/null || true)"
  nm="$(grep -c 'actions/runs.*-f event=merge_group' "$WORK/gh.log" 2>/dev/null || true)"
  [[ "${np:-0}" -eq "$k" && "${nm:-0}" -eq "$k" ]] \
    || { REASON="$l: the lookup did not run (push lists=${np:-0}, merge_group lists=${nm:-0}, wanted $k each): a broken lookup would also look suspected"; return 1; }
  ! cat "$WORK/out.txt" "$WORK/err.txt" | grep -q 'could not read' \
    || { REASON="$l: the lookup warned (could not read): the suspected form came from a failed lookup, not from the evidence"; return 1; }
  return 0
}
# hist_calls <workflow_id>: how many unwindowed merge_group-history lookups the run made for that workflow
hist_calls() { grep -c "actions/workflows/$1/runs -f event=merge_group -F per_page=1\$" "$WORK/gh.log" 2>/dev/null || true; }
# check_named <label> <entry-index> <pr> <path> <run-id>; check_suspected <label> <entry-index> <pr> [lookups|none]
check_named() {
  local l="$1" n="$2" pr="$3" path="$4" rid="$5" t b ref
  t="$(title_n "$n")"; b="$(body_n "$n")"; ref="$(qref "$pr" "$SHA1")"
  title_anchors_ok "$t" "$pr" || { REASON="$l: entry $n title no longer matches the dedupe/drain anchor ('$t')"; return 1; }
  [[ "$t" == "TITLE:merge-queue stall: PR #${pr} pending >${THR_REAL}m (cause: load failure suspected in ${path}; for example a duplicate or invalid key)" ]] \
    || { REASON="$l: entry $n title lacks the named-cause suffix for ${path} ('$t')"; return 1; }
  [[ "$b" == "LIKELY CAUSE (inferred from the run signature)"* ]] || { REASON="$l: entry $n body does not open with the LIKELY CAUSE (inferred from the run signature) paragraph"; return 1; }
  [[ "$b" != *"CAUSE (observed)"* && "$b" != *"other workflows did run"* && "${b%%SUSPECTED merge-queue stall*}" != *"usual cause"* ]] \
    || { REASON="$l: entry $n body still claims what no code establishes (CAUSE (observed) / other workflows did run on that ref / a usual-cause base rate)"; return 1; }
  [[ "$b" == *"What is observed"* && "$b" == *"What is inferred"* ]] \
    || { REASON="$l: entry $n body does not separate the observed facts from the inferred cause"; return 1; }
  # the agent-runnable fetch names the REF (in a fenced block), never the workflow path
  [[ "$b" == *$'\n```text\ngit fetch origin '"${ref}"$'\n'* ]] \
    || { REASON="$l: entry $n body lacks 'git fetch origin ${ref}' in a fenced block (the ref, not the path)"; return 1; }
  [[ "$b" == *"${path}"* && "$b" == *"https://github.com/o/r/actions/runs/${rid}"* ]] \
    || { REASON="$l: entry $n body lacks the named path or the failed run URL"; return 1; }
  [[ "$b" == *'python3 .github/scripts/check-workflow-duplicate-keys.py'* ]] \
    || { REASON="$l: entry $n body lacks the agent-runnable duplicate-key check"; return 1; }
  [[ "$b" == *"SUSPECTED merge-queue stall (needs verification)"* && "$b" == *"Triage (every step"* ]] \
    || { REASON="$l: entry $n body lost the existing suspected/triage text"; return 1; }
  return 0
}
check_suspected() {
  local l="$1" n="$2" pr="$3" k="${4:-1}" t b
  t="$(title_n "$n")"; b="$(body_n "$n")"
  title_anchors_ok "$t" "$pr" || { REASON="$l: entry $n title no longer matches the dedupe/drain anchor ('$t')"; return 1; }
  [[ "$t" == "TITLE:merge-queue stall: PR #${pr} pending >${THR_REAL}m (suspected, verify first)" ]] \
    || { REASON="$l: entry $n was given a cause it has no evidence for ('$t')"; return 1; }
  [[ "$b" == "SUSPECTED merge-queue stall (needs verification)"* && "$b" != *"CAUSE ("* ]] \
    || { REASON="$l: entry $n body is not the unchanged suspected form"; return 1; }
  [[ "$k" == "none" ]] || lookup_ran "$l" "$k"
}
# one_entry <pr> <runs-array-file>: queue = PR at position 1, enqueued 50 minutes ago; runs from the file.
one_entry() {
  local wf="$1" pr="$2" rf="$3" g="$WORK/q.json"
  { node 1 50 "$pr"; } | queue_json > "$g"
  CASE_RUNS="$rf"; run_case "$wf" "$g"
}

# set_ever <workflow_id>...: the all-time merge_group history of those workflows, OUTSIDE every window (one run ten
# hours old each), served only by the unwindowed per-workflow lookup. The real incident needs it: ci.yml had run on
# merge_group for every earlier PR, but a one-entry queue window holds no ci.yml merge_group run at all.
set_ever() {
  local w f="$WORK/ever.json"
  { for w in "$@"; do mkrun $((7000 + w)) merge_group CI ".github/workflows/wf-${w}.yml" "$w" "$(qref 5 "$SHA0")" success 600; done; } | jq -s '.' > "$f"
  CASE_EVER="$f"
}

lrow1() { # the real incident: six other merge_group runs, a stale superseded ref, noise -> ci.yml named
  local wf="$1" rf="$WORK/runs.json"; REASON=""
  incident_runs 101 | jq -s '.' > "$rf"
  # 150/170 (old.yml, other.yml) HAVE merge_group history too, so only the window / prefix / ref filters keep them out
  set_ever 111 150 170; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L1: incident did not file exactly one issue (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L1 1 101 "$WF_PATH_CI" 9001 || return 1
  local b; b="$(body_n 1)"
  [[ "$b" != *"old.yml"* && "$b" != *"other.yml"* && "$b" != *"/runs/9000"* && "$b" != *"/runs/9300"* ]] \
    || { REASON="L1: the cause names more than the one failed load on the latest ref (a run outside the created window, off-prefix, or stale)"; return 1; }
  return 0
}
lrow2() { # no failed push run at all -> unchanged suspected form
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push CI "$WF_PATH_CI" 111 "$ref" success 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L2: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L2 1 101
}
lrow3() { # failed push run, but a merge_group run of the SAME workflow exists -> suspected
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49; mg_noise "$ref" 48 9100
    mkrun 9150 merge_group CI "$WF_PATH_CI" 111 "$ref" "" 48; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L3: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L3 1 101
}
lrow4() { # stale failure on a superseded ref, the LATEST ref has no failed push run -> suspected
  local wf="$1" rf="$WORK/runs.json" ref ref0; REASON=""; ref="$(qref 101 "$SHA1")"; ref0="$(qref 101 "$SHA0")"
  { mkrun 9000 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref0" failure 48; mg_noise "$ref0" 48 9200
    mkrun 9700 merge_group "Merge queue CLA synthetics" .github/workflows/merge-queue-cla-synthetics.yml 206 "$ref" success 46
  } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L4: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L4 1 101 || { REASON="${REASON} (a stale failure on a superseded ref named a cause for the latest ref)"; return 1; }
}
lrow5() { # PR 12 must not read PR 123's refs (prefix has the trailing dash)
  local wf="$1" rf="$WORK/runs.json"; REASON=""
  { mkrun 9800 merge_group "Merge queue CLA synthetics" .github/workflows/merge-queue-cla-synthetics.yml 206 "$(qref 12 "$SHA0")" success 49
    mkrun 9801 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$(qref 123 "$SHA1")" failure 48
  } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 12 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L5: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L5 1 12 || { REASON="${REASON} (pr-12 collided with pr-123: the prefix lacks its trailing dash)"; return 1; }
}
lrow6() { # the runs list fails -> suspected, ONE bounded ASCII warning, rc 0
  local wf="$1" rf="$WORK/runs.json" w n; REASON=""
  incident_runs 101 | jq -s '.' > "$rf"
  CASE_RUNS_FAIL=1; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L6: a failed runs lookup must not fail the step (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L6 1 101 none || return 1
  n="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep -c 'could not read the Actions runs' || true)"
  [[ "$n" -eq 1 ]] || { REASON="L6: expected exactly one could-not-read warning, got $n"; return 1; }
  w="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep 'could not read the Actions runs' | head -n 1)"
  [[ "$w" == "::warning::"* && "${#w}" -le 400 ]] || { REASON="L6: the warning is not a bounded ::warning:: (len ${#w})"; return 1; }
  ! LC_ALL=C grep -qP '[^\x20-\x7e]' <<<"$w" || { REASON="L6: the warning carries non-ASCII bytes from the API error"; return 1; }
  return 0
}
lrow7() { # two stalled entries: the cause must not leak between iterations, in either order
  local wf="$1" rf="$WORK/runs.json" g="$WORK/q.json" ref1 ref2; REASON=""
  ref1="$(qref 101 "$SHA1")"; ref2="$(qref 102 "$SHA1")"
  # (a) only the SECOND entry carries the signature
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref2" failure 49; mg_noise "$ref2" 48 9100
    mg_noise "$ref1" 48 9300; } | jq -s '.' > "$rf"
  { node 1 50 101; node 2 50 102; } | queue_json > "$g"
  set_ever 111; CASE_RUNS="$rf"; run_case "$wf" "$g"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 2 ]] || { REASON="L7: two stalled entries did not file two issues (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L7 1 101 none || return 1
  check_named L7 2 102 "$WF_PATH_CI" 9001 || return 1
  lookup_ran L7 2 || return 1
  # (b) only the FIRST entry carries it: a cause variable that is not reset per entry leaks into the second
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref1" failure 49; mg_noise "$ref1" 48 9100
    mg_noise "$ref2" 48 9300; } | jq -s '.' > "$rf"
  set_ever 111; CASE_RUNS="$rf"; run_case "$wf" "$g"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 2 ]] || { REASON="L7: (b) two stalled entries did not file two issues"; return 1; }
  check_named L7 1 101 "$WF_PATH_CI" 9001 || return 1
  lookup_ran L7 2 || return 1
  check_suspected L7 2 102 none || { REASON="${REASON} (the first entry's cause leaked into the second: the per-entry reset is missing)"; return 1; }
}
lrow8() { # a CANCELLED push run is not a load failure
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" cancelled 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L8: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L8 1 101
}
lrow10() { # a failed push run of a LOADED workflow (name differs from its path), no merge_group run of it -> suspected
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "Lint (push only)" .github/workflows/lint.yml 160 "$ref" failure 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 160; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L10: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L10 1 101 || { REASON="${REASON} (a legitimately failing push-only workflow was blamed as a load failure: the name == path gate is missing)"; return 1; }
}
lrow11() { # a SUCCESS push run is not a load failure
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" success 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L11: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L11 1 101
}
lrow12() { # two-or-more-page --paginate shape: the broken run is on page 2
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49
    mkrun 9611 push "Other A" .github/workflows/other-a.yml 181 "$ref" success 48
    mkrun 9612 push "Other B" .github/workflows/other-b.yml 182 "$ref" success 47
    mkrun 9613 push "Other C" .github/workflows/other-c.yml 183 "$ref" success 46
    mg_noise "$ref" 45 9100; } | jq -s '.' > "$rf"
  set_ever 111; CASE_PAGE_CAP=2; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L12: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L12 1 101 "$WF_PATH_CI" 9001 || { REASON="${REASON} (a run on page 2 of a paginated list was not read)"; return 1; }
}
lrow13() { # a deduped entry makes ZERO actions/runs calls (cause form and old form both dedupe)
  local wf="$1" rf="$WORK/runs.json" g="$WORK/q.json" iss="$WORK/issues.json" t n; REASON=""
  incident_runs 101 | jq -s '.' > "$rf"
  for t in "merge-queue stall: PR #101 pending >45m (cause: load failure suspected in .github/workflows/ci.yml; for example a duplicate or invalid key)" \
           "merge-queue stall: PR #101 pending >45m (suspected, verify first)"; do
    { node 1 50 101; } | queue_json > "$g"
    { issue 9 OPEN merge-queue-stall "$t"; } | issues_json > "$iss"
    CASE_RUNS="$rf"; run_case "$wf" "$g" 0 "$iss"; reset_runs
    n="$(grep -c 'actions/' "$WORK/gh.log" 2>/dev/null || true)"
    [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 0 ]] || { REASON="L13: an open stall issue did not dedupe (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
    [[ "${n:-0}" -eq 0 ]] || { REASON="L13: a deduped entry still made $n actions/ call(s) (the lookup runs before the dedupe check)"; return 1; }
  done
  return 0
}
lrow14() { # merge_group run whose path carries a ref suffix but the SAME workflow_id -> loaded, suspected
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49; mg_noise "$ref" 48 9100
    mkrun 9150 merge_group CI "${WF_PATH_CI}@refs/heads/${ref}" 111 "$ref" "" 48; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L14: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L14 1 101 || { REASON="${REASON} (the join is on path, not workflow_id)"; return 1; }
}
lrow15() { # D16: a push-only workflow with name == path and NO merge_group history ever -> suspected (two members)
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push .github/workflows/lint.yml .github/workflows/lint.yml 160 "$ref" failure 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L15: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L15 1 101 || { REASON="${REASON} (a push-only workflow that never ran on merge_group was blamed for the stall)"; return 1; }
  [[ "$(hist_calls 160)" -eq 1 ]] || { REASON="L15: the history lookup for workflow 160 did not run exactly once (n=$(hist_calls 160))"; return 1; }
  # second member: TWO such workflows -> two lookups, still suspected
  { mkrun 9001 push .github/workflows/lint.yml .github/workflows/lint.yml 160 "$ref" failure 49
    mkrun 9002 push .github/workflows/nightly.yml .github/workflows/nightly.yml 161 "$ref" failure 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  one_entry "$wf" 101 "$rf"; reset_runs
  check_suspected L15 1 101 || return 1
  [[ "$(hist_calls 160)" -eq 1 && "$(hist_calls 161)" -eq 1 ]] || { REASON="L15: (b) each candidate must get exactly one history lookup"; return 1; }
  return 0
}
lrow16() { # D16: the history lookup FAILS -> suspected, rc 0, ONE bounded ASCII warning even with two candidates
  local wf="$1" rf="$WORK/runs.json" ref w n; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49
    mkrun 9002 push .github/workflows/deploy-docs.yml .github/workflows/deploy-docs.yml 112 "$ref" failure 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111 112; CASE_WFHIST_FAIL=1; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L16: a failed history lookup must not fail the step (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_suspected L16 1 101 none || { REASON="${REASON} (a lookup error was taken as 'has merge_group history')"; return 1; }
  [[ "$(hist_calls 111)" -eq 1 && "$(hist_calls 112)" -eq 1 ]] || { REASON="L16: both candidates must have been looked up (111=$(hist_calls 111) 112=$(hist_calls 112))"; return 1; }
  n="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep -c 'could not read the merge_group history' || true)"
  [[ "$n" -eq 1 ]] || { REASON="L16: expected exactly one history warning for two failed lookups, got $n"; return 1; }
  [[ "$(cat "$WORK/out.txt" "$WORK/err.txt" | grep -c 'could not read the Actions runs' || true)" -eq 0 ]] || { REASON="L16: the runs lists were reported unreadable although only the history lookup failed"; return 1; }
  w="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep 'could not read the merge_group history' | head -n 1)"
  [[ "$w" == "::warning::"* && "${#w}" -le 400 ]] || { REASON="L16: the warning is not a bounded ::warning:: (len ${#w})"; return 1; }
  # the warning must carry the LOOKUP's own failure (rc=1 + the API error), not the malformed-reply message a dropped rc capture
  # would produce on the empty body (that one is L26's and says total_count)
  [[ "$w" == *"(rc=1: "* && "$w" == *"502"* && "$w" != *"total_count"* ]] || { REASON="L16: the warning does not carry the failed lookup's rc and API error ('$w')"; return 1; }
  ! LC_ALL=C grep -qP '[^\x20-\x7e]' <<<"$w" || { REASON="L16: the warning carries non-ASCII bytes from the API error"; return 1; }
  return 0
}
lrow17() { # untrusted head_branch: command substitution / backtick / semicolon / short sha / one trailing newline, NEWEST created_at -> never used
  local wf="$1" rf="$WORK/runs.json" ref h hs=() n b; REASON=""; ref="$(qref 101 "$SHA1")"
  hs=('gh-readonly-queue/main/pr-101-$(id)' 'gh-readonly-queue/main/pr-101-`id`' "${ref};id" "${ref}"'$(id)' "gh-readonly-queue/main/pr-101-${SHA1:0:39}" "${ref}"$'\n')   # the last: the valid ref plus EXACTLY ONE trailing newline (a jq `$` anchor accepts it, `\z` does not)
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49; mg_noise "$ref" 48 9100
    n=9500; for h in "${hs[@]}"; do n=$((n + 1)); mkrun "$n" push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$h" failure 30; done; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L17: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L17 1 101 "$WF_PATH_CI" 9001 || return 1     # the real ref is still named: the hostile runs are ignored, not an eraser
  b="$(body_n 1)$(title_n 1)"; b="${b//"$ref"/}"      # the real ref may appear; whatever a hostile ref adds to it (or any other pr-101- ref) may not
  [[ "$b" != *"${SHA1:0:39}"* && "$b" != *';id'* && "$b" != *'$(id)'* && "$b" != *'`id`'* ]] \
    || { REASON="L17: a head_branch outside gh-readonly-queue/main/pr-N-<40 hex> reached the issue"; return 1; }
  [[ "$b" != *"/runs/950"* ]] || { REASON="L17: a run on a hostile head_branch reached the issue"; return 1; }
  # (b) ONLY hostile refs -> nothing to name, the suspected form, and the lookup still ran
  { n=9500; for h in "${hs[@]}"; do n=$((n + 1)); mkrun "$n" push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$h" failure 30; done; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L17: (b) filing failed"; return 1; }
  check_suspected L17 1 101 || { REASON="${REASON} (a hostile head_branch alone produced a cause)"; return 1; }
}
lrow18() { # untrusted workflow path (mention, backtick, ref suffix, traversal) -> that candidate is dropped, the others stay
  local wf="$1" rf="$WORK/runs.json" ref b h hp i; REASON=""; ref="$(qref 101 "$SHA1")"
  hp=('.github/workflows/@org-team.yml' '.github/workflows/a`id`.yml' ".github/workflows/ci.yml@refs/heads/${ref}" '.github/workflows/../../x.yml' $'.github/workflows/nl-trailing.yml\n')
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49; mg_noise "$ref" 48 9100
    i=0; for h in "${hp[@]}"; do i=$((i + 1)); mkrun $((9700 + i)) push "$h" "$h" $((300 + i)) "$ref" failure 49; done; } | jq -s '.' > "$rf"
  set_ever 111 301 302 303 304 305; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L18: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L18 1 101 "$WF_PATH_CI" 9001 || return 1
  b="$(body_n 1)$(title_n 1)"
  [[ "$b" != *"@org-team"* && "$b" != *'`id`'* && "$b" != *"refs/heads"* && "$b" != *"../"* && "$b" != *"/runs/970"* && "$b" != *"nl-trailing"* ]] \
    || { REASON="L18: a workflow path outside .github/workflows/<name>.y(a)ml (or one with a trailing newline) reached the issue"; return 1; }
  # (b) ONLY hostile paths -> suspected, lookup ran
  { mg_noise "$ref" 48 9100
    i=0; for h in "${hp[@]}"; do i=$((i + 1)); mkrun $((9700 + i)) push "$h" "$h" $((300 + i)) "$ref" failure 49; done; } | jq -s '.' > "$rf"
  set_ever 111 301 302 303 304 305; one_entry "$wf" 101 "$rf"; reset_runs
  check_suspected L18 1 101 || { REASON="${REASON} (a hostile path alone produced a cause)"; return 1; }
  # (c) a legitimate path but a run URL outside https://github.com/<owner>/<repo>/actions/runs/<id> -> dropped
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49 | jq -c '.html_url = "https://evil.example/@org-team"'; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  check_suspected L18 1 101 || { REASON="${REASON} (a run URL of the wrong shape was linked from the issue)"; return 1; }
  # (d) the right URL plus EXACTLY ONE trailing newline -> dropped too (a jq `$` anchor accepts it, `\z` does not)
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49 | jq -c '.html_url = "https://github.com/o/r/actions/runs/9001\n"'; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  check_suspected L18 1 101 || { REASON="${REASON} (a run URL with a trailing newline was linked from the issue)"; return 1; }
}
lrow19() { # two load-failed workflows + two failed runs of one path: both named, order deterministic, newest URL once
  local wf="$1" rf="$WORK/runs.json" ref b t pass_i dd_min; REASON=""; ref="$(qref 101 "$SHA1")"
  for pass_i in 1 2; do
    dd_min=47; [[ "$pass_i" -eq 2 ]] && dd_min=52     # second member: the other workflow is NEWER / OLDER, the order must not follow created_at
    { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 49
      mkrun 9002 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 47                # a re-run of the SAME path, newer
      mkrun 9003 push .github/workflows/deploy-docs.yml .github/workflows/deploy-docs.yml 112 "$ref" failure "$dd_min"
      mg_noise "$ref" 46 9100; } | jq -s '.' > "$rf"
    set_ever 111 112; one_entry "$wf" 101 "$rf"; reset_runs
    [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L19.$pass_i: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
    t="$(title_n 1)"; b="$(body_n 1)"
    title_anchors_ok "$t" 101 || { REASON="L19.$pass_i: title no longer matches the dedupe/drain anchor ('$t')"; return 1; }
    [[ "$t" == "TITLE:merge-queue stall: PR #101 pending >${THR_REAL}m (cause: load failure suspected in .github/workflows/ci.yml (+1 more); for example a duplicate or invalid key)" ]] \
      || { REASON="L19.$pass_i: the title is not first path + (+1 more) in path order ('$t')"; return 1; }
    [[ "$b" == *"for .github/workflows/ci.yml, .github/workflows/deploy-docs.yml "* ]] \
      || { REASON="L19.$pass_i: the body does not list both paths, comma-joined, in path order"; return 1; }
    [[ "$b" == *$'\n- .github/workflows/ci.yml: https://github.com/o/r/actions/runs/9002\n- .github/workflows/deploy-docs.yml: https://github.com/o/r/actions/runs/9003\n'* ]] \
      || { REASON="L19.$pass_i: the run lines are not one per path with the NEWEST run URL (ci.yml -> 9002)"; return 1; }
    [[ "$b" != *"/runs/9001"* && "$(grep -o -- '- .github/workflows/ci.yml:' <<<"$b" | wc -l)" -eq 1 ]] \
      || { REASON="L19.$pass_i: a path with two failed runs was named more than once"; return 1; }
    [[ "$b" == *$'\n```text\ngit fetch origin '"${ref}"$'\n'* && "$b" != *"git fetch origin .github"* ]] \
      || { REASON="L19.$pass_i: the fetch step does not carry the REF"; return 1; }
  done
  return 0
}
lrow20() { # ci.yml's merge_group run exists on the OLD temp ref only; the load failure is on the NEW ref -> still named
  local wf="$1" rf="$WORK/runs.json" ref ref0; REASON=""; ref="$(qref 101 "$SHA1")"; ref0="$(qref 101 "$SHA0")"
  { mkrun 9205 merge_group CI "$WF_PATH_CI" 111 "$ref0" success 48; mg_noise "$ref0" 48 9200
    mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 46; mg_noise "$ref" 46 9100; } | jq -s '.' > "$rf"
  one_entry "$wf" 101 "$rf"; reset_runs   # no all-time history file: the OLD-ref run in the window is the history
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L20: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L20 1 101 "$WF_PATH_CI" 9001 || { REASON="${REASON} (a merge_group run of the workflow on the OLD ref hid a load failure on the NEW ref)"; return 1; }
}
lrow21() { # clock slack: the failed push run is created 2 minutes BEFORE the entry's enqueuedAt -> still read
  local wf="$1" rf="$WORK/runs.json" ref; REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 52; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 111; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L21: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L21 1 101 "$WF_PATH_CI" 9001 || { REASON="${REASON} (the 5-minute enqueuedAt slack does not cover a run 2 minutes before the enqueue)"; return 1; }
}
lrow22() { # title cap: <=250 chars; first path + (+N more); the full list stays in the body; an over-long single path falls back
  local wf="$1" rf="$WORK/runs.json" ref i t b p naive long first pre=".github/workflows/"; REASON=""; ref="$(qref 101 "$SHA1")"
  local ps=("${pre}scheduled-weekly-analytics-report-generation-job.yml" "${pre}apply-web-platform-infra-after-merge-verification.yml" \
            "${pre}skill-security-scan-postmerge-advisory-report.yml" "${pre}tenant-integration-isolation-regression-sweep.yml")
  { i=0; for p in "${ps[@]}"; do i=$((i + 1)); mkrun $((9600 + i)) push "$p" "$p" $((400 + i)) "$ref" failure 49; done; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  naive="merge-queue stall: PR #101 pending >${THR_REAL}m (cause: load failure suspected in $(IFS=,; printf '%s' "${ps[*]}" | sed 's/,/, /g'); for example a duplicate or invalid key)"
  [[ "${#naive}" -gt 256 ]] || { REASON="L22: the fixture is vacuous: the full-list title is only ${#naive} chars (must exceed GitHub's 256)"; return 1; }
  set_ever 401 402 403 404; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 && "$CASE_ATTEMPTS" -eq 1 ]] \
    || { REASON="L22: four long paths did not file exactly one issue on the first try (rc=$CASE_RC creates=$CASE_CREATES attempts=$CASE_ATTEMPTS)"; return 1; }
  t="$(title_n 1)"; b="$(body_n 1)"
  [[ "${#t}" -le $((250 + 6)) ]] || { REASON="L22: the title is ${#t} chars with the TITLE: prefix (cap 250)"; return 1; }
  title_anchors_ok "$t" 101 || { REASON="L22: title no longer matches the dedupe/drain anchor"; return 1; }
  first="${ps[1]}"      # alphabetical: the first path is the one named in the title
  [[ "$t" == *"suspected in ${first} (+3 more);"* ]] || { REASON="L22: the title is not first path + (+3 more) ('$t')"; return 1; }
  for p in "${ps[@]}"; do
    [[ "$b" == *"$p"* ]] || { REASON="L22: the body lost the path $p (the full list must stay in the body)"; return 1; }
  done
  # (b) ONE over-long path: the cause form would exceed the cap -> the plain suspected title, the cause stays in the body
  long="${pre}$(printf 'a%.0s' $(seq 1 200)).yml"
  { mkrun 9001 push "$long" "$long" 411 "$ref" failure 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  set_ever 411; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 && "$CASE_ATTEMPTS" -eq 1 ]] || { REASON="L22: (b) an over-long path did not file one issue on the first try (rc=$CASE_RC creates=$CASE_CREATES attempts=$CASE_ATTEMPTS)"; return 1; }
  t="$(title_n 1)"; b="$(body_n 1)"
  [[ "${#t}" -le $((250 + 6)) && "$t" == "TITLE:merge-queue stall: PR #101 pending >${THR_REAL}m (suspected, verify first)" ]] \
    || { REASON="L22: (b) an over-long cause title was not replaced by the plain title (len ${#t})"; return 1; }
  [[ "$b" == "LIKELY CAUSE"* && "$b" == *"$long"* ]] || { REASON="L22: (b) the cause paragraph was lost along with the long title"; return 1; }
  return 0
}
lrow23() { # a rejected cause-form title is retried ONCE with the plain title; a plain failure is not retried
  local wf="$1" rf="$WORK/runs.json" ref t b; REASON=""; ref="$(qref 101 "$SHA1")"
  incident_runs 101 | jq -s '.' > "$rf"
  set_ever 111; CASE_CREATE_MAX=100; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_ATTEMPTS" -eq 2 && "$CASE_CREATES" -eq 1 ]] \
    || { REASON="L23: a rejected cause title was not retried once (rc=$CASE_RC attempts=$CASE_ATTEMPTS creates=$CASE_CREATES)"; return 1; }
  t="$(title_n 1)"; b="$(body_n 1)"
  title_anchors_ok "$t" 101 && [[ "$t" == "TITLE:merge-queue stall: PR #101 pending >${THR_REAL}m (suspected, verify first)" ]] \
    || { REASON="L23: the retry did not use the plain suspected title ('$t')"; return 1; }
  [[ "$b" == "LIKELY CAUSE"* && "$b" == *"${WF_PATH_CI}"* ]] || { REASON="L23: the retry dropped the cause paragraph from the body"; return 1; }
  cat "$WORK/out.txt" "$WORK/err.txt" | grep -q 'retrying once with the plain title' || { REASON="L23: the retry is not announced"; return 1; }
  # both attempts rejected: the step fails LOUDLY after exactly one retry
  set_ever 111; CASE_CREATE_MAX=10; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -ne 0 && "$CASE_ATTEMPTS" -eq 2 && "$CASE_CREATES" -eq 0 ]] \
    || { REASON="L23: a create that fails twice must fail the step after one retry (rc=$CASE_RC attempts=$CASE_ATTEMPTS creates=$CASE_CREATES)"; return 1; }
  # a plain-form failure (no cause) is not retried with anything
  printf '[]' > "$WORK/l23-empty.json"
  CASE_CREATE_MAX=10; one_entry "$wf" 101 "$WORK/l23-empty.json"; reset_runs
  [[ "$CASE_RC" -ne 0 && "$CASE_ATTEMPTS" -eq 1 ]] || { REASON="L23: a plain-title failure must fail the step with no retry (rc=$CASE_RC attempts=$CASE_ATTEMPTS)"; return 1; }
  return 0
}
lrow24() { # an EMPTY or unparseable enqueuedAt reaches the cause lookup: no API call, no cause (date -d "" means TODAY)
  local wf="$1" rf="$WORK/runs.json" f body drv defs kind enq out; REASON=""
  incident_runs 101 | jq -s '.' > "$rf"; set_ever 111
  f="$(python3 "$HELPER" wf "$wf")"; body="$WORK/l24-body.sh"; drv="$WORK/l24-driver.sh"
  jq -r '.steps[] | select(.name | test("^Detect stalled")) | .run' <<<"$f" > "$body"
  defs="$(awk '/^# fetch_runs </{on=1} /^# Declared once/{on=0} on' "$body")"
  [[ "$defs" == *"queue_candidate_cause()"* && "$defs" == *"fetch_runs()"* ]] || { REASON="L24: could not extract the cause functions from the run body"; return 1; }
  for kind in empty garbage good; do
    case "$kind" in empty) enq="" ;; garbage) enq="not-a-date" ;; good) enq="$(iso_ago 50)" ;; esac
    { printf 'set -euo pipefail\nCAUSE_PATHS=""; CAUSE_LINES=""; CAUSE_REF=""; CAUSE_N=0\n%s\nqueue_candidate_cause 101 %q\nprintf "paths=[%%s]\\n" "$CAUSE_PATHS"\n' "$defs" "$enq"; } > "$drv"
    rm -f "$WORK/gh.log"
    out="$(env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" TMPDIR="$WORK" GH_REPO=o/r GH_TOKEN=x GH_STUB_LOG="$WORK/gh.log" GH_STUB_RUNS="$rf" GH_STUB_EVER="$CASE_EVER" bash "$drv" 2>/dev/null | tail -n 1)"
    if [[ "$kind" == good ]]; then
      [[ "$out" == "paths=[${WF_PATH_CI}]" ]] || { REASON="L24: the driver is vacuous: a good enqueuedAt did not name ci.yml (out='$out')"; return 1; }
    else
      [[ "$out" == "paths=[]" && ! -s "$WORK/gh.log" ]] \
        || { REASON="L24: enqueuedAt '$enq' still reached the Actions API or named a cause (out='$out' calls=$(wc -l < "$WORK/gh.log"))"; return 1; }
    fi
  done
  reset_runs
  return 0
}
# L9: the stub's own filters (the controls that make every L row non-vacuous). Runs against the stub only.
lrow9() {
  local pf="$WORK/l9-push.json" mf="$WORK/l9-mixed.json" ref rc n
  REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 1 push CI "$WF_PATH_CI" 111 "$ref" failure 49; mkrun 2 push B b.yml 112 "$ref" success 48; mkrun 3 push C c.yml 113 "$ref" success 47; } | jq -s '.' > "$pf"
  { mkrun 1 push CI "$WF_PATH_CI" 111 "$ref" failure 49; mkrun 2 push B b.yml 112 "$ref" success 48; mkrun 3 push C c.yml 113 "$ref" success 47
    mkrun 4 merge_group D d.yml 114 "$ref" success 46; mkrun 5 merge_group E e.yml 115 "$ref" success 45; } | jq -s '.' > "$mf"
  stub_runs() { # <runs-file> <page-cap> <args...>
    local f="$1" cap="$2"; shift 2
    env -i PATH="$BIN:$SANDBOX_PATH" GH_REPO=o/r GH_STUB_LOG="$WORK/l9.log" GH_STUB_RUNS="$f" GH_STUB_PAGE_CAP="$cap" \
      gh api -X GET repos/o/r/actions/runs "$@"
  }
  local base=(-F per_page=100 -F exclude_pull_requests=true) since60 since485 future
  since60="$(iso_ago 60)"; since485="$(date -u -d '-2910 seconds' +%Y-%m-%dT%H:%M:%SZ)"   # 48.5 min ago: 30 s clear of both neighbours
  future="$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)"
  count() { jq -s '[.[].workflow_runs[]] | length'; }
  # the right event serves its rows; the WRONG event serves nothing (the filter is applied, not ignored)
  n="$(stub_runs "$pf" "" --paginate -f event=push -f created=">=$since60" "${base[@]}" | count)"
  [[ "$n" == 3 ]] || { REASON="L9: stub did not serve the 3 push runs for event=push (got $n)"; return 1; }
  n="$(stub_runs "$pf" "" --paginate -f event=merge_group -f created=">=$since60" "${base[@]}" | count)"
  [[ "$n" == 0 ]] || { REASON="L9: stub ignored event= (a wrong event served $n runs)"; return 1; }
  n="$(stub_runs "$mf" "" --paginate -f event=merge_group -f created=">=$since60" "${base[@]}" | jq -s '[.[].workflow_runs[] | select(.event != "merge_group")] | length')"
  [[ "$n" == 0 ]] || { REASON="L9: stub served non-merge_group rows for event=merge_group"; return 1; }
  # the created RANGE is applied: a bound in the future serves nothing, a tight bound drops the older rows
  n="$(stub_runs "$pf" "" --paginate -f event=push -f created=">=$future" "${base[@]}" | count)"
  [[ "$n" == 0 ]] || { REASON="L9: stub ignored the created= range (a future bound served $n runs)"; return 1; }
  n="$(stub_runs "$pf" "" --paginate -f event=push -f created=">=$since485" "${base[@]}" | count)"
  [[ "$n" == 2 ]] || { REASON="L9: stub did not apply the created= lower bound (>=48.5m ago served $n, wanted 2)"; return 1; }
  # per_page and --paginate: one object per page with a cap; page 1 only without --paginate
  n="$(stub_runs "$pf" 2 --paginate -f event=push -f created=">=$since60" "${base[@]}" | jq -s 'length')"
  [[ "$n" == 2 ]] || { REASON="L9: --paginate with a 2-run page cap did not emit 2 page objects (got $n)"; return 1; }
  n="$(stub_runs "$pf" 2 -f event=push -f created=">=$since60" "${base[@]}" | jq -s '[length, (.[0].workflow_runs | length), .[0].total_count] | join(",")' | tr -d '"')"
  [[ "$n" == "1,2,3" ]] || { REASON="L9: without --paginate the stub must serve page 1 only (got $n)"; return 1; }
  n="$(stub_runs "$pf" "" -f event=push -f created=">=$since60" -F per_page=1 -F exclude_pull_requests=true | jq -s '.[0].workflow_runs | length')"
  [[ "$n" == 1 ]] || { REASON="L9: per_page=1 was not applied (got $n)"; return 1; }
  # an unexpected request exits 64 (never silently served)
  stub_runs "$pf" "" --paginate -f event=push "${base[@]}" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: a request without created= must exit 64 (rc=$rc)"; return 1; }
  stub_runs "$pf" "" --paginate -f event=push -f created=">=$since60" -F per_page=100 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: a request without exclude_pull_requests must exit 64 (rc=$rc)"; return 1; }
  stub_runs "$pf" "" --paginate -f event=schedule -f created=">=$since60" "${base[@]}" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: an unexpected event must exit 64 (rc=$rc)"; return 1; }
  stub_runs "$pf" "" --paginate -f event=push -f created=">=$since60" -f bogus=1 "${base[@]}" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: an unexpected field must exit 64 (rc=$rc)"; return 1; }
  env -i PATH="$BIN:$SANDBOX_PATH" GH_REPO=o/r GH_STUB_LOG="$WORK/l9.log" GH_STUB_RUNS="$pf" \
    gh api -X POST repos/o/r/actions/runs >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: a non-GET verb must exit 64 (rc=$rc)"; return 1; }
  env -i PATH="$BIN:$SANDBOX_PATH" GH_REPO=o/r GH_STUB_LOG="$WORK/l9.log" GH_STUB_RUNS="$pf" \
    gh api -X GET repos/o/r/actions/jobs -f event=push -f created=">=$since60" "${base[@]}" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L9: an unexpected endpoint must exit 64 (rc=$rc)"; return 1; }
  return 0
}

# L25: the stub's history endpoint (D16) -- the control that makes L1/L15/L16/L20 non-vacuous. Stub only.
lrow25() {
  local pf="$WORK/l25-runs.json" ef="$WORK/l25-ever.json" ref rc n
  REASON=""; ref="$(qref 101 "$SHA1")"
  { mkrun 1 merge_group D d.yml 114 "$ref" success 5; mkrun 2 push C c.yml 114 "$ref" success 5; mkrun 3 merge_group E e.yml 115 "$ref" success 5; } | jq -s '.' > "$pf"
  { mkrun 4 merge_group D d.yml 114 "$ref" success 600; mkrun 5 merge_group D d.yml 114 "$ref" success 700; } | jq -s '.' > "$ef"
  hist() { # <workflow-id> <args...>
    local w="$1"; shift
    env -i PATH="$BIN:$SANDBOX_PATH" GH_REPO=o/r GH_STUB_LOG="$WORK/l25.log" GH_STUB_RUNS="$pf" GH_STUB_EVER="$ef" GH_STUB_WFHIST_FAIL="${HIST_FAIL:-0}" \
      gh api -X GET "repos/o/r/actions/workflows/$w/runs" "$@"
  }
  n="$(hist 114 -f event=merge_group -F per_page=1 | jq -c '[.total_count, (.workflow_runs | length)] | join(",")' | tr -d '"')"
  [[ "$n" == "3,1" ]] || { REASON="L25: workflow 114 must report ALL 3 merge_group runs (2 outside any window, the push run excluded) with per_page=1 -> 1 row (got $n)"; return 1; }
  n="$(hist 115 -f event=merge_group -F per_page=1 | jq -r '.total_count')"
  [[ "$n" == "1" ]] || { REASON="L25: workflow 115 total_count (got $n, wanted 1)"; return 1; }
  n="$(hist 999 -f event=merge_group -F per_page=1 | jq -r '.total_count')"
  [[ "$n" == "0" ]] || { REASON="L25: an unknown workflow id must have total_count 0 (got $n)"; return 1; }
  hist 114 -f event=push -F per_page=1 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: event=push on the history endpoint must exit 64 (rc=$rc)"; return 1; }
  hist 114 -f event=merge_group >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: a history lookup without per_page must exit 64 (rc=$rc)"; return 1; }
  hist 114 -f event=merge_group -F per_page=100 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: a history lookup with per_page != 1 must exit 64 (rc=$rc)"; return 1; }
  hist 114 -f event=merge_group -f created=">=$(iso_ago 60)" -F per_page=1 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: a WINDOWED history lookup must exit 64 (rc=$rc)"; return 1; }
  hist 114 -f event=merge_group -F per_page=1 -F exclude_pull_requests=true >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: exclude_pull_requests on the history lookup must exit 64 (rc=$rc)"; return 1; }
  hist 114 --paginate -f event=merge_group -F per_page=1 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: a paginated history lookup must exit 64 (rc=$rc)"; return 1; }
  HIST_FAIL=1 hist 114 -f event=merge_group -F per_page=1 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 1 ]] || { REASON="L25: GH_STUB_WFHIST_FAIL=1 must make the lookup fail (rc=$rc)"; return 1; }
  env -i PATH="$BIN:$SANDBOX_PATH" GH_REPO=o/r GH_STUB_LOG="$WORK/l25.log" GH_STUB_RUNS="$pf" GH_STUB_EVER="$ef" \
    gh api -X GET "repos/o/r/actions/workflows/abc/runs" -f event=merge_group -F per_page=1 >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 64 ]] || { REASON="L25: a non-numeric workflow id must exit 64 (rc=$rc)"; return 1; }
  return 0
}

lrow26() { # a malformed history reply (non-numeric or missing total_count): suspected, ONE bounded ASCII warning, rc 0
  local wf="$1" rf="$WORK/runs.json" ref body w n; REASON=""; ref="$(qref 101 "$SHA1")"
  # (a) the same fixture with a WELL-FORMED reply names the cause: the raw-body channel itself is not what suppresses it
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 46; mg_noise "$ref" 46 9100; } | jq -s '.' > "$rf"
  set_ever 111; CASE_WFHIST_BODY='{"total_count":3,"workflow_runs":[]}'; one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L26: filing failed (rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
  check_named L26 1 101 "$WF_PATH_CI" 9001 || { REASON="${REASON} (control: a well-formed total_count must still name the cause)"; return 1; }
  # (b) total_count a STRING, and (c) total_count absent: each is a malformed reply, not "no history"
  for body in '{"total_count":"abc","workflow_runs":[]}' '{"workflow_runs":[]}'; do
    set_ever 111; CASE_WFHIST_BODY="$body"; one_entry "$wf" 101 "$rf"; reset_runs
    [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]] || { REASON="L26: a malformed history reply must not fail the step (body=$body rc=$CASE_RC creates=$CASE_CREATES)"; return 1; }
    check_suspected L26 1 101 none || { REASON="${REASON} (a malformed total_count was taken as 'has merge_group history' for body $body)"; return 1; }
    [[ "$(hist_calls 111)" -eq 1 ]] || { REASON="L26: the history lookup did not run exactly once (body=$body n=$(hist_calls 111))"; return 1; }
    n="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep -c 'could not read the merge_group history' || true)"
    [[ "$n" -eq 1 ]] || { REASON="L26: a malformed total_count must emit exactly one history warning, got $n (body=$body)"; return 1; }
    w="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep 'could not read the merge_group history' | head -n 1)"
    [[ "$w" == "::warning::"* && "$w" == *"total_count"* && "${#w}" -le 400 ]] || { REASON="L26: the warning is not a bounded ::warning:: naming total_count (len ${#w})"; return 1; }
    ! LC_ALL=C grep -qP '[^\x20-\x7e]' <<<"$w" || { REASON="L26: the warning carries non-ASCII bytes"; return 1; }
  done
  # (d) two candidates, both malformed: still ONE warning for the entry
  { mkrun 9001 push "$WF_PATH_CI" "$WF_PATH_CI" 111 "$ref" failure 46
    mkrun 9002 push .github/workflows/deploy-docs.yml .github/workflows/deploy-docs.yml 112 "$ref" failure 46; mg_noise "$ref" 46 9100; } | jq -s '.' > "$rf"
  set_ever 111 112; CASE_WFHIST_BODY='{"total_count":"abc"}'; one_entry "$wf" 101 "$rf"; reset_runs
  check_suspected L26 1 101 none || return 1
  n="$(cat "$WORK/out.txt" "$WORK/err.txt" | grep -c 'could not read the merge_group history' || true)"
  [[ "$n" -eq 1 && "$(hist_calls 111)" -eq 1 && "$(hist_calls 112)" -eq 1 ]] || { REASON="L26: two malformed lookups must warn once and both run (warnings=$n)"; return 1; }
  return 0
}

CAUSE_ROWS=(1 2 3 4 5 6 7 8 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 26)
# cause_check <workflow> [rows...]: executes the real run body against the cause rows (default: all). L9 and L25 are
# stub controls, run once on the real workflow.
cause_check() {
  local wf="$1" r; shift
  local rows=("${@:-${CAUSE_ROWS[@]}}")
  for r in "${rows[@]}"; do "lrow$r" "$wf" || return 1; done
  return 0
}
ldesc() {
  case "$1" in
    1) echo "real incident (six other merge_group runs, stale superseded ref, noise) names .github/workflows/ci.yml with the run URL" ;;
    2) echo "no failed push run -> unchanged suspected form" ;;
    3) echo "failed push run but a merge_group run of the same workflow exists -> suspected" ;;
    4) echo "stale failure on a superseded ref, latest ref healthy -> suspected" ;;
    5) echo "pr-12 does not read pr-123 refs (trailing dash)" ;;
    6) echo "runs endpoint fails -> suspected, one bounded ASCII warning, rc 0" ;;
    7) echo "two entries: the cause never leaks between iterations (both orders)" ;;
    8) echo "cancelled push run -> suspected" ;;
    9) echo "stub controls: event/created/per_page/paginate applied, unexpected request exits 64" ;;
    10) echo "failed push run whose name differs from its path (a loaded workflow) -> suspected" ;;
    11) echo "success push run -> suspected" ;;
    12) echo "two-page --paginate: the broken run on page 2 is still named" ;;
    13) echo "deduped entry (cause form and old form) makes zero actions/runs calls" ;;
    14) echo "merge_group run with a suffixed path but the same workflow_id -> suspected" ;;
    15) echo "push-only workflow (name == path) with NO merge_group history ever -> suspected, history lookup ran (two members)" ;;
    16) echo "history lookup error -> suspected, rc 0, ONE bounded ASCII warning for two candidates" ;;
    17) echo "hostile head_branch (command substitution, backtick, semicolon, short sha) with the newest created_at is never used" ;;
    18) echo "hostile workflow path (mention, backtick, ref suffix, traversal) is dropped, a legitimate one beside it is still named" ;;
    19) echo "two load-failed workflows and two failed runs of one path: both named once, path order, newest URL, fetch names the ref" ;;
    20) echo "ci.yml merge_group run on the OLD temp ref only, load failure on the NEW ref -> still named" ;;
    21) echo "failed run created 2 minutes before enqueuedAt is still read (clock slack)" ;;
    22) echo "title cap: four long paths -> first path + (+3 more) at <=250 chars, all in the body; one over-long path -> plain title" ;;
    23) echo "rejected cause-form title is retried once with the plain title; a double failure is loud; a plain failure is not retried" ;;
    24) echo "empty or unparseable enqueuedAt makes zero Actions calls and names nothing" ;;
    25) echo "stub history endpoint: unwindowed total_count, rejects every other shape with 64" ;;
    26) echo "malformed history reply (non-numeric or missing total_count) -> suspected, ONE bounded ASCII warning, rc 0" ;;
  esac
}

# ---- rows ---------------------------------------------------------------------------------------
if structural_check "$WF_REAL"; then pass "S0 real workflow: structural invariants hold"; else fail "S0 real workflow: structural invariants hold ($REASON)"; fi
if behav_check "$WF_REAL"; then pass "B0 real workflow: executed run body behaves on canned queues"; else fail "B0 real workflow: executed run body behaves on canned queues ($REASON)"; fi
if drain_check "$WF_REAL"; then pass "B1 real workflow: drain step closes only issues whose target PR left OPEN"; else fail "B1 real workflow: drain step behaves ($REASON)"; fi

for r in "${CAUSE_ROWS[@]}"; do
  if "lrow$r" "$WF_REAL"; then pass "L$r real workflow: $(ldesc "$r")"; else fail "L$r real workflow: $(ldesc "$r") ($REASON)"; fi
done
if lrow9 "$WF_REAL"; then pass "L9 $(ldesc 9)"; else fail "L9 $(ldesc 9) ($REASON)"; fi
if lrow25 "$WF_REAL"; then pass "L25 $(ldesc 25)"; else fail "L25 $(ldesc 25) ($REASON)"; fi

# Derivation sanity: the .tf numbers are real and the relation is not vacuous.
if [[ "$TF_TIMEOUT" -gt 0 && "$TF_BUILD" -ge 1 ]]; then pass "D0 derived tf timeout=$TF_TIMEOUT build window=$TF_BUILD (positive integers)"; else fail "D0 derived tf values"; fi

# Individual structural facts, so a failure names the fact (the real workflow, not a mutant).
FACTS="$(python3 "$HELPER" wf "$WF_REAL")"
chk() { if jq -e "$2" <<<"$FACTS" >/dev/null; then pass "$1"; else fail "$1"; fi; }
chk "S1 on.schedule cron present" '(.cron | length) > 0'
chk "S2 workflow_dispatch trigger present (manual / Inngest-driven runs)" '.on_keys | index("workflow_dispatch")'
chk "S3 STALL_THRESHOLD_MINUTES numeric" '.env.STALL_THRESHOLD_MINUTES | test("^[0-9]+$")'
chk "S4 permissions exactly contents:read + issues:write + actions:read" '.permissions == {"contents":"read","issues":"write","actions":"read"}'
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
chk "S16 cause lookup is a paginated -X GET of actions/runs, flattened with jq -s, exclude_pull_requests, per_page=100" 'any(.runs[]; test("queue_candidate_cause\\(\\)") and test("gh api -X GET --paginate") and test("-F per_page=100") and test("-F exclude_pull_requests=true") and test("jq -s \u0027\\[\\.\\[\\]\\.workflow_runs\\[\\]\\]\u0027"))'
# S17/S18 (comment-prose pins: the live run ids cited in an inline comment, the header sentence about actions: read)
# were dropped: the properties they stood for are covered behaviourally. The name == path signature by L10 + C8 (a
# loaded workflow with a different name is not blamed); the actions: read scope by S4 + M8/M8b (the exact permission
# set) and the lookup itself by L1/L12/L15/L16 (the stub serves the Actions endpoints only to a request that carries them).
chk "S13 drain step exists, gated on if: always()" 'any(.steps[]; .name == "Drain stale stall issues" and .if == "always()")'
chk "S14 drain enumeration is a bounded label-scoped --json list" 'any(.runs[]; test("gh issue list") and test("\\-L 50") and test("--label merge-queue-stall") and test("--json number,title"))'
chk "S15 drain reads the target state before closing" 'any(.runs[]; test("gh issue view") and test("--json state") and test("gh issue close"))'

# ---- mutation engine ----------------------------------------------------------------------------
# mutate <label> <engine: structural|behav|drain|causerow> <expected-reason-regex> <python-expr over s (str) returning str>
SB="$WORK/sandbox"; assert_fixture_dir "$SB"; mkdir -p "$SB" || exit 2
# mut_compiles <workflow>: every run body of the mutant parses as bash. A typo in a mutation literal makes the run
# body crash on EVERY row, including the named one, so "the named row went red" alone would score it as a kill.
mut_compiles() {
  local f i n; f="$(python3 "$HELPER" wf "$1" 2>/dev/null)" || return 0   # a YAML-broken mutant is the structural engine's verdict
  n="$(jq -r '.runs | length' <<<"$f")"
  for ((i = 0; i < n; i++)); do
    jq -r ".runs[$i]" <<<"$f" > "$SB/mut-run.sh"
    bash -n "$SB/mut-run.sh" 2>/dev/null || return 1
  done
  return 0
}
# cause_alive <workflow>: a CLEAN entry (a success push run) still completes: the step starts, reads the queue and
# files one issue. A mutant that crashed the run body fails every row, so only a mutant that still completes this
# is allowed to count as killed by a named row.
cause_alive() {
  local wf="$1" rf="$WORK/alive-runs.json" ref; ref="$(qref 101 "$SHA1")"
  { mkrun 9001 push CI "$WF_PATH_CI" 111 "$ref" success 49; mg_noise "$ref" 48 9100; } | jq -s '.' > "$rf"
  one_entry "$wf" 101 "$rf"; reset_runs
  [[ "$CASE_RC" -eq 0 && "$CASE_CREATES" -eq 1 ]]
}
# causerow engine: only the rows the mutant names (CAUSE_MUT_ROWS, set by mutate_lit from the expected-reason regex),
# then the liveness guard. A crash, or a verdict-less non-zero, is NOT a kill.
CAUSE_MUT_ROWS=""
causerow_check() {
  local wf="$1" reason
  # shellcheck disable=SC2086  # CAUSE_MUT_ROWS is a deliberate word list (empty = every row)
  cause_check "$wf" $CAUSE_MUT_ROWS && return 0
  reason="$REASON"
  if ! cause_alive "$wf"; then REASON="CRASH: the mutant run body no longer completes a clean entry (not a kill)"; return 1; fi
  REASON="$reason"; return 1
}
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
  mut_compiles "$SB/mutant.yml" || { fail "$label (the mutant run body does not compile: an instrument failure, not a kill)"; return; }
  crash_reset
  "${engine}_check" "$SB/mutant.yml"; rc=$?
  local crash; crash="$(crash_scan)"
  if [[ "$rc" -eq 0 ]]; then
    fail "$label (guard stayed GREEN under the mutation)"
  elif [[ -n "$crash" ]]; then
    # A named row that went red because the mutant CRASHED (a jq compile error swallowed by 2>/dev/null, an unbound
    # variable on the naming path, a missing command) says nothing about the property the mutant targets.
    fail "$label (UNRESOLVED: the run produced a crash signature, not a verdict: '${crash:0:160}')"
  elif grep -qE "$want" <<<"$REASON"; then
    pass "$label"
  else
    fail "$label (RED for the wrong reason: '$REASON', wanted /$want/)"
  fi
}

# Positive control: an UNMUTATED sandbox copy must be green on all engines, so a sandbox-harness
# fault cannot manufacture the RED verdicts below.
# It must also leave NO crash signature in any captured stream (jq stderr included): the kill criterion below treats one as
# UNRESOLVED, so a pristine run that printed one would make every kill ambiguous.
cp "$WF_REAL" "$SB/control.yml"; crash_reset
if structural_check "$SB/control.yml" && behav_check "$SB/control.yml" && drain_check "$SB/control.yml" && cause_check "$SB/control.yml" \
   && { REASON="the unmutated run printed a crash signature: $(crash_scan)"; [[ -z "$(crash_scan)" ]]; }; then
  pass "M0 positive control: unmutated sandbox copy is GREEN on all engines, with no crash signature in any stream"
else
  fail "M0 positive control ($REASON)"
fi

mutate "M1 threshold raised to the timeout -> RED" structural "threshold $TF_TIMEOUT >= check_response_timeout_minutes" \
  "re.sub(r\"STALL_THRESHOLD_MINUTES: '[0-9]+'\", \"STALL_THRESHOLD_MINUTES: '$TF_TIMEOUT'\", s)"
mutate "M2 threshold made non-numeric -> RED" structural 'not numeric' \
  "re.sub(r\"STALL_THRESHOLD_MINUTES: '[0-9]+'\", \"STALL_THRESHOLD_MINUTES: 'soon'\", s)"
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
mutate "M8 permissions widened (actions: read -> write) -> RED" structural 'permissions are not exactly' \
  "s.replace('  actions: read\n', '  actions: write\n', 1)"
mutate "M8b actions: read dropped (the cause lookup loses its scope) -> RED" structural 'permissions are not exactly' \
  "s.replace('  actions: read\n', '', 1)"
mutate "M8c a further scope added (pull-requests: write) -> RED" structural 'permissions are not exactly' \
  "s.replace('  actions: read\n', '  actions: read\n  pull-requests: write\n', 1)"
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
  "s.replace('(suspected, verify first)', '(unverified)')"
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

# ---- stall-cause mutations (#12283): each is a LITERAL replacement of one load-bearing fragment of
# queue_candidate_cause, applied to a sandbox copy; mutate() diffs it against the pristine copy first (it must
# LAND) and the `cause` engine must go RED for the NAMED row.
# mutate_lit <label> <engine> <want> <old> <new> [<old2> <new2>]
mutate_lit() {
  local rows pristine; pristine="$(<"$WF_REAL")"
  # every old fragment must exist in the pristine workflow (a second replacement that matched nothing would otherwise hide behind the first)
  [[ "$pristine" == *"$4"* && ( -z "${6-}" || "$pristine" == *"$6"* ) ]] || { fail "$1 (mutation anchor not found in the pristine workflow)"; return; }
  rows="$(grep -oE 'L[0-9]+' <<<"$3" | tr -d 'L' | tr '\n' ' ')"
  CAUSE_MUT_ROWS="$rows"
  export MUT_OLD="$4" MUT_NEW="$5" MUT_OLD2="${6-}" MUT_NEW2="${7-}"
  mutate "$1" "$2" "$3" '(lambda t: t.replace(os.environ["MUT_OLD2"], os.environ["MUT_NEW2"]) if os.environ.get("MUT_OLD2") else t)(s.replace(os.environ["MUT_OLD"], os.environ["MUT_NEW"]))'
  unset MUT_OLD MUT_NEW MUT_OLD2 MUT_NEW2
}
mutate_lit "C1 join: 'no merge_group run of P' -> 'no merge_group run at all' -> RED (the six other merge_group runs hide the cause)" causerow 'L1:' \
  '($mg | index($w)) == null' '($mg | length) == 0'
mutate_lit "C2 latest-ref selection dropped (every ref under the prefix) -> RED (a stale failure names a cause for a healthy ref)" causerow 'L4:' \
  '($a | map(select(.head_branch == $ref))) as $p' '$a as $p'
mutate_lit "C3 temp-ref match loses its trailing dash and tail (pr-12 matches pr-123) -> RED" causerow 'L5:' \
  'pr-${pr}-[0-9a-f]{40}\\z"' 'pr-${pr}"'
mutate_lit "C3b temp-ref match loses its end anchor (a valid sha followed by pusher text is accepted) -> RED" causerow 'L17:' \
  '[0-9a-f]{40}\\z"' '[0-9a-f]{40}"'
mutate_lit "C3b2 temp-ref end anchor \\z -> \$ (one trailing newline is accepted) -> RED (a head_branch with a trailing newline reaches the issue)" causerow 'L17:' \
  '[0-9a-f]{40}\\z"' '[0-9a-f]{40}\$"'
mutate_lit "C3c temp-ref match relaxed to the old prefix test (any text after pr-N-) -> RED (a hostile head_branch reaches the issue)" causerow 'L17:' \
  'pr-${pr}-[0-9a-f]{40}\\z"' 'pr-${pr}-"'
mutate_lit "C4a lookup failure exits the step (|| return 0 -> || exit 1) -> RED" causerow 'L6:' \
  'fetch_runs push PUSH_LIST || return 0' 'fetch_runs push PUSH_LIST || exit 1'
mutate_lit "C4b lookup failure is not captured (the explicit rc capture is dropped on the gh call) -> RED" causerow 'L6:' \
  '</dev/null)" || rc=$?' '</dev/null)"'
mutate_lit "C5 per-entry cause reset removed -> RED (the first entry's cause leaks into the second)" causerow 'L7:' \
  '            CAUSE_PATHS=""; CAUSE_LINES=""; CAUSE_REF=""; CAUSE_N=0
' ''
mutate_lit "C6 cause suffix moved in front of the PR anchor -> RED (dedupe/drain anchors stop matching)" causerow 'L1:.*anchor' \
  'cause_title="merge-queue stall: PR #${pr} pending >${STALL_THRESHOLD_MINUTES}m ${cause_suffix}"' 'cause_title="merge-queue stall: ${cause_suffix} PR #${pr} pending >${STALL_THRESHOLD_MINUTES}m"'
mutate_lit "C7 conclusion == \"failure\" -> != null (a cancelled or success push run counts as failed) -> RED" causerow 'L8:|L11:' \
  '.conclusion == "failure"' '.conclusion != null'
mutate_lit "C8 name == path conjunct dropped -> RED (a loaded push-only workflow is blamed)" causerow 'L10:' \
  '.name == .path' 'true'
mutate_lit "C9 join on path instead of workflow_id -> RED (a suffixed merge_group path is mistaken for a missing run)" causerow 'L14:' \
  '.workflow_id)) as $mg' '.path)) as $mg' \
  '(.workflow_id as $w |' '(.path as $w |'
mutate_lit "C10a created= bound dropped -> RED (the stub exits 64 on an unbounded list; the cause is lost)" causerow 'L1:' \
  ' -f created=">=${since}"' ''
mutate_lit "C10b slack sign flipped (enqueuedAt + 5 min) -> RED (the entry's own runs fall before the bound)" causerow 'L1:' \
  'enq_s - 300' 'enq_s + 300'
mutate_lit "C10c slack widened to hours -> RED (a run before the window is named too)" causerow 'L1:' \
  'enq_s - 300' 'enq_s - 30000'
mutate_lit "C10d slack removed (0 s) -> RED (a run created 2 minutes before enqueuedAt is missed)" causerow 'L21:' \
  'enq_s - 300' 'enq_s - 0'
mutate_lit "C10e slack cut to 60 s -> RED (a run created 2 minutes before enqueuedAt is missed)" causerow 'L21:' \
  'enq_s - 300' 'enq_s - 60'
mutate_lit "C11 lookup called before the dedupe check -> RED (a deduped entry spends API calls)" causerow 'L13:' \
  '            CAUSE_PATHS=""; CAUSE_LINES=""; CAUSE_REF=""; CAUSE_N=0
            queue_candidate_cause "$pr" "$enq"
' '' \
  '            existing=$(gh issue list' '            CAUSE_PATHS=""; CAUSE_LINES=""; CAUSE_REF=""; CAUSE_N=0
            queue_candidate_cause "$pr" "$enq"
            existing=$(gh issue list'
mutate_lit "C12 --paginate dropped -> RED (a run on page 2 is never read)" causerow 'L12:' \
  'gh api -X GET --paginate ' 'gh api -X GET '
mutate_lit "C13 exclude_pull_requests dropped -> RED (the stub exits 64; the cause is lost)" causerow 'L1:' \
  ' -F exclude_pull_requests=true' ''
mutate_lit "C14 merge_group-history conjunct dropped (every candidate is named) -> RED (a push-only workflow is blamed)" causerow 'L15:' \
  'if has_mg_history "$w"; then' 'if true; then'
mutate_lit "C15a total_count ignored (a zero count counts as history) -> RED" causerow 'L15:' \
  '[[ "$n" =~ ^[0-9]+$ ]] && [[ "$((10#$n))" -gt 0 ]]' 'true'
mutate_lit "C15b a failed history lookup counts as history (return 1 -> return 0) -> RED" causerow 'L16:' \
  '              HIST_WARNED=1
              rm -f "$errf"
              return 1' '              HIST_WARNED=1
              rm -f "$errf"
              return 0'
mutate_lit "C15c history lookup rc not captured (|| rc=\$? dropped) -> RED (the failed lookup aborts the step)" causerow 'L16:' \
  '-F per_page=1 </dev/null 2>"$errf")" || rc=$?' '-F per_page=1 </dev/null 2>"$errf")"'
mutate_lit "C15d history lookup windowed (created= added) -> RED (the stub rejects it; the real incident is lost)" causerow 'L1:' \
  '-f event=merge_group -F per_page=1 </dev/null' '-f event=merge_group -f created=">=${since}" -F per_page=1 </dev/null'
mutate_lit "C15e history warning not bounded per entry -> RED (two failed lookups warn twice)" causerow 'L16:' \
  'if [[ "$HIST_WARNED" -eq 0 ]]; then' 'if true; then'
mutate_lit "C16 workflow path validation dropped -> RED (a mention or backtick in a path reaches the issue)" causerow 'L18:' \
  'and ((.path // "") | test("^\\.github/workflows/[A-Za-z0-9._-]+\\.ya?ml\\z"))' ''
mutate_lit "C16c workflow path end anchor \\z -> \$ (one trailing newline is accepted) -> RED (a path with a trailing newline reaches the issue)" causerow 'L18:' \
  '\\.ya?ml\\z"))' '\\.ya?ml$"))'
mutate_lit "C16b run URL validation dropped -> RED (a foreign URL is linked from the issue)" causerow 'L18:' \
  'and ((.html_url // "") | test("^https://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/actions/runs/[0-9]+\\z"))' ''
mutate_lit "C16d run URL end anchor \\z -> \$ (one trailing newline is accepted) -> RED (a URL with a trailing newline is linked)" causerow 'L18:' \
  '/actions/runs/[0-9]+\\z"))' '/actions/runs/[0-9]+$"))'
mutate_lit "C17 title lists every path (first + (+N more) dropped) -> RED (the title exceeds the cap)" causerow 'L19\.1:|L22:' \
  '${CAUSE_PATHS%%, *}${cause_more}' '${CAUSE_PATHS}'
mutate_lit "C17b (+N more) suffix always added (the single-path test dropped) -> RED" causerow 'L1:' \
  '[[ "$CAUSE_N" -le 1 ]] || cause_more' 'cause_more'
mutate_lit "C18 250-character cap dropped -> RED (an over-long cause title goes to the API and is rejected)" causerow 'L22:' \
  'if [[ "${#cause_title}" -le 250 ]]; then title="$cause_title"; fi' 'title="$cause_title"'
mutate_lit "C19 retry with the plain title dropped -> RED (a rejected cause title files nothing)" causerow 'L23:' \
  'if [[ "$create_rc" -ne 0 && "$title" != "$plain_title" ]]; then' 'if false; then'
mutate_lit "C19b a double create failure is swallowed (exit dropped) -> RED" causerow 'L23:' \
  'exit "$create_rc"' 'true'
mutate_lit "C20 empty enqueuedAt guard dropped (date -d \"\" means today) -> RED" causerow 'L24:' \
  'if [[ -z "$enq" ]] || ! enq_s=' 'if ! enq_s='
mutate_lit "C21 CAUSE_REF taken from the path column -> RED (the fetch step names a file, not the ref)" causerow 'L1:' \
  'CAUSE_REF="$ref"' 'CAUSE_REF="$p"'
mutate_lit "C22 per-path dedupe dropped (unique_by) -> RED (a path with two failed runs is named twice)" causerow 'L19\.1:' \
  '| unique_by(.path)[]' '| .[]'
mutate_lit "C23 newest run per path dropped (reverse) -> RED (the oldest failed run is linked)" causerow 'L19\.1:' \
  '| sort_by(.created_at) | reverse' '| sort_by(.created_at)'
mutate_lit "C24 paths overwritten instead of appended -> RED (only the last workflow is named)" causerow 'L19\.1:' \
  'CAUSE_PATHS+="${CAUSE_PATHS:+, }${p}"' 'CAUSE_PATHS="${p}"'
mutate_lit "C15f non-numeric total_count handled silently (the explicit non-numeric branch dropped) -> RED (a malformed reply is indistinguishable from no history)" causerow 'L26:' \
  'if [[ "$rc" -eq 0 && ! "$n" =~ ^[0-9]+$ ]]; then' 'if false; then'
mutate_lit "C25 merge_group join not limited to the latest ref -> RED (a run on the OLD ref hides the load failure on the NEW one)" causerow 'L20:' \
  '($b | map(select(.head_branch == $ref) | .workflow_id)) as $mg' '($b | map(.workflow_id)) as $mg'
# C26: BOTH run-list fetches skipped, so no lookup happens and every entry is filed as "suspected". The negative rows
# all expect the suspected form, so only lookup_ran (the lookup must have run once per list) can see it.
mutate_lit "C26 both run-list fetches skipped -> RED only through lookup_ran (a negative row's suspected form came from no lookup at all)" causerow 'L2: the lookup did not run' \
  '            fetch_runs push PUSH_LIST || return 0
            fetch_runs merge_group MG_LIST || return 0
' '            return 0
'

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
  "re.sub(r\"STALL_THRESHOLD_MINUTES: '[0-9]+'\", \"STALL_THRESHOLD_MINUTES: '$TF_TIMEOUT'\", s)"
control_fails "mutate_lit (mutation anchor absent from the workflow)" "anchor not found" mutate_lit "CTL-f" causerow 'L1:' 'THIS TEXT IS NOT IN THE WORKFLOW' 'x'
control_fails "mutate_lit (a mutant that does not compile is not a kill)" "does not compile" mutate_lit "CTL-g" causerow 'L1:' \
  'queue_candidate_cause() {' 'queue_candidate_cause() {{'
control_fails "mutate_lit (a mutant that compiles but crashes the run body is not a kill)" "wrong reason" mutate_lit "CTL-h" causerow 'L1:' \
  'fetch_runs push PUSH_LIST || return 0' 'exit 3'
# kill criterion = the named row's own assertion message AND no crash signature in any captured stream. Each class below
# was scored a KILL before the criterion existed (the REASON was the plain suspected form or a row's message):
control_fails "mutate_lit (a jq compile error in the naming program is swallowed by 2>/dev/null: UNRESOLVED, not a kill)" "UNRESOLVED" mutate_lit "CTL-i" causerow 'L19\.1:' \
  '| unique_by(.path)[]' '| uniq_by(.path)[]'
control_fails "mutate_lit (a jq compile error elsewhere in the naming program: UNRESOLVED, not a kill)" "UNRESOLVED" mutate_lit "CTL-i2" causerow 'L20:' \
  '($b | map(select(.head_branch == $ref) | .workflow_id)) as $mg' '($b | mapp(select(.head_branch == $ref) | .workflow_id)) as $mg'
control_fails "mutate_lit (an unbound variable that only the naming path reaches: UNRESOLVED, not a kill)" "UNRESOLVED" mutate_lit "CTL-j" causerow 'L1:' \
  'CAUSE_REF="$ref"' 'CAUSE_REF="$pp"'
control_fails "mutate_lit (an unbound variable in the cause lines: UNRESOLVED, not a kill)" "UNRESOLVED" mutate_lit "CTL-j2" causerow 'L19\.1:' \
  'CAUSE_LINES+="- ${p}: ${u}"' 'CAUSE_LINES+="- ${p}: ${uu}"'
# lookup_ran control: with the helper neutered, C26 stays GREEN on EVERY pure-negative row (so the helper is what kills it)
LOOKUP_RAN_OFF=1
control_fails "lookup_ran (C26 stays GREEN on every negative row without it)" "stayed GREEN" mutate_lit "CTL-k" causerow 'L2:|L3:|L4:|L5:|L8:|L10:|L11:|L14:' \
  '            fetch_runs push PUSH_LIST || return 0
            fetch_runs merge_group MG_LIST || return 0
' '            return 0
'
LOOKUP_RAN_OFF=0
control_fails "chk (a false jq expression)" "CTL-d" chk "CTL-d" 'false'
control_fails "chk (a missing key)" "CTL-e" chk "CTL-e" '.no_such_fact'

# ---- accounting (exact floor, printf + exit so a neutered helper cannot mask it) ----------------
# Passes must equal the constant EXACTLY.
printf '=== %s passed, %s failed ===\n' "$passes" "$fails"
if [[ "$fails" -ne 0 ]]; then
  printf '[FAIL] rows failed:\n' >&2; printf '  %s\n' "${FAILED[@]}" >&2; exit 1
fi
EXPECTED_PASSES=142
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf '[FAIL] pass count %s != exact floor %s (a row was dropped or added)\n' "$passes" "$EXPECTED_PASSES" >&2; exit 1
fi
exit 0
