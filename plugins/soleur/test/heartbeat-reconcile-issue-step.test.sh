#!/usr/bin/env bash
# Guard 3 (#7884 plan) — routing in the `heartbeat-live-reconcile` job of
# `.github/workflows/scheduled-terraform-drift.yml`.
#
# PROPERTY. Every MISMATCH row reaches the reconcile issue even when another arm errors; a
# routing key re-emails when it is absent from the workflow's OWN most recent reconcile post
# (so a persisting row stays quiet and a row that clears and returns is loud again); a
# monitor-config-drift row always emails; routing labels are added before the comment and a label
# failure only warns; a failed/cancelled filer, a failed email-prep step and an undelivered email
# each surface as an email or a Sentry `error` check-in; and the issue step can neither create a
# duplicate nor fail silently.
#
# HOW. Every step under test is EXTRACTED from the workflow with yaml.safe_load (never
# re-implemented here) and executed against stubs on PATH (`gh` logs its argv and applies the real
# `--jq` filter with jq; `bun` prints a fixture; `doppler` prints a fake token; `curl` prints an
# HTTP code) with temp RUNNER_TEMP / GITHUB_OUTPUT. `if:`, `with.status` and `with.subject` are
# EVALUATED by a small GitHub-expression interpreter below rather than grepped, so a comment or a
# reordered clause cannot satisfy them. The reason list and ROUTE_TOKEN_RE are READ from
# plugins/soleur/lib/heartbeat-live-reconcile.ts at test time (parity rows P*).
#
# SHELL. None of the workflow steps declares `shell:` and the workflow has no
# `defaults.run.shell`, so Actions runs them as `bash -e {0}` — WITHOUT pipefail. That is exactly
# why #8140 happened (`gh issue list … | head -1` failed, `head` exited 0, EXISTING read empty, a
# duplicate was filed). So the bodies run under `bash --noprofile --norc -e` with BASH_ENV,
# SHELLOPTS and BASHOPTS scrubbed: an exported SHELLOPTS=…:pipefail in the invoking shell would
# otherwise switch pipefail on inside the child and pass a defective body (self-test S1).
#
# COUNTING. The suite re-runs itself and counts its own `  pass: ` / `  FAIL: ` output lines, then
# checks them against the inner summary (conservation) and the floor — so a helper that stops
# counting, or a deleted row, cannot turn the run green.
#
# Run: bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh
# Override the files under test (mutation proofs on a COPY):
#   HEARTBEAT_ISSUE_STEP_WF=/path/to/workflow-copy.yml
#   HEARTBEAT_ISSUE_STEP_ACTION=/path/to/notify-ops-email-copy.yml
#   HEARTBEAT_ISSUE_STEP_LIB=/path/to/heartbeat-live-reconcile-copy.ts

set -uo pipefail

# `/tmp` is a shared tmpfs and a direct invocation of this suite inherits it.
export TMPDIR="${TMPDIR:-/var/tmp}"

# ANTI-VACUITY FLOOR at the REALIZED count: deleting assertions must show up as a diff here.
FLOOR=139

# ---------------------------------------------------------------------------
# OUTER RUN. Counts the inner run's own output lines; never trusts pass()/fail() for the verdict.
# ---------------------------------------------------------------------------
if [[ -z "${_HB_ISSUE_STEP_INNER:-}" ]]; then
  _log=$(mktemp "$TMPDIR/hb-issue-step.XXXXXX") || { printf 'FATAL: mktemp for the suite log\n' >&2; exit 2; }
  trap 'rm -f "$_log"' EXIT
  _HB_ISSUE_STEP_INNER=1 bash "${BASH_SOURCE[0]}" "$@" 2>&1 | tee "$_log"
  _rc=${PIPESTATUS[0]}
  _np=$(grep -c '^  pass: ' "$_log")
  _nf=$(grep -c '^  FAIL: ' "$_log")
  _summary=$(sed -n 's|^=== Results: \([0-9][0-9]*\)/\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed ===$|\1 \2 \3|p' "$_log")
  if [[ "$(grep -c . <<<"$_summary")" != "1" ]]; then
    printf 'FATAL: the inner run printed no single Results line (rc=%s) — it died before finishing\n' "$_rc" >&2
    exit 2
  fi
  read -r _sp _st _sf <<<"$_summary"
  if [[ "$_sp" != "$_np" || "$_sf" != "$_nf" || "$_st" != "$((_np + _nf))" ]]; then
    printf 'FATAL: count conservation broken — summary says %s/%s passed, %s failed; the output has %s pass lines and %s FAIL lines\n' \
      "$_sp" "$_st" "$_sf" "$_np" "$_nf" >&2
    exit 1
  fi
  if (( _np + _nf < FLOOR )); then
    printf 'FATAL: only %s assertions ran; expected >= %s.\n' "$((_np + _nf))" "$FLOOR" >&2
    exit 1
  fi
  if (( _nf > 0 )); then exit 1; fi
  if [[ "$_rc" != "0" ]]; then printf 'FATAL: inner run exited %s with no FAIL line\n' "$_rc" >&2; exit "$_rc"; fi
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${HEARTBEAT_ISSUE_STEP_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"
ACTION="${HEARTBEAT_ISSUE_STEP_ACTION:-$REPO_ROOT/.github/actions/notify-ops-email/action.yml}"
LIB="${HEARTBEAT_ISSUE_STEP_LIB:-$REPO_ROOT/plugins/soleur/lib/heartbeat-live-reconcile.ts}"
JOB="heartbeat-live-reconcile"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
fatal() { echo "FATAL: $1" >&2; exit 2; }

[[ -f "$WF" ]] || fatal "missing workflow $WF"
[[ -f "$ACTION" ]] || fatal "missing composite action $ACTION"
[[ -f "$LIB" ]] || fatal "missing reconcile lib $LIB"
command -v python3 >/dev/null || fatal "python3 not found"
python3 -c 'import yaml' 2>/dev/null || fatal "python3 yaml module not importable"
command -v openssl >/dev/null || fatal "openssl not found (the email step mints its heredoc delimiter with it, as the runner does)"
command -v jq >/dev/null || fatal "jq not found (the gh stub applies the step's real --jq filter, and the composite builds its payload with jq)"

TMP=$(mktemp -d) || fatal "sandbox"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/steps" || fatal "mkdir"

# POSITIVE CONTROL for the outer count: drive pass() and fail() once each, off the counted output,
# and report through printf + exit only.
if ! ( PASS=0; FAIL=0
       pass "positive-control" > "$TMP/pc.out"; fail "positive-control" >> "$TMP/pc.out"
       [[ "$PASS" == 1 && "$FAIL" == 1 ]] || exit 1
       [[ "$(sed -n 1p "$TMP/pc.out")" == "  pass: positive-control" ]] || exit 1
       [[ "$(sed -n 2p "$TMP/pc.out")" == "  FAIL: positive-control" ]] || exit 1 ); then
  printf 'FATAL: positive control — pass()/fail() did not each move their counter and print the line the outer run counts\n' >&2
  exit 2
fi
printf 'positive control: pass() and fail() each moved their counter and printed a countable line\n'

echo "=== heartbeat-live-reconcile issue-step routing (Guard 3) ==="

# ---------------------------------------------------------------------------
# EXTRACTION. yq_get <file> <python-path-expr> ; job_step <selector> <path> — selector `id:<id>` or
# `name:<prefix>`, restricted to the heartbeat-live-reconcile job (the drift-check job has
# look-alike label/issue steps). exit 2 = no such step, 3 = no such field.
# ---------------------------------------------------------------------------
job_step() {
  python3 - "$WF" "$JOB" "$1" "$2" <<'PYF'
import sys, yaml
wf, job, sel, path = sys.argv[1:5]
kind, want = sel.split(":", 1)
steps = (yaml.safe_load(open(wf))["jobs"].get(job) or {}).get("steps") or []
hits = [s for s in steps if (kind == "id" and s.get("id") == want)
        or (kind == "name" and str(s.get("name", "")).startswith(want))]
if len(hits) != 1:
    sys.stderr.write("expected exactly 1 step matching %s in job %s, found %d\n" % (sel, job, len(hits)))
    raise SystemExit(2)
cur = hits[0]
for part in path.split("."):
    if not isinstance(cur, dict) or part not in cur:
        sys.stderr.write("step %s has no '%s'\n" % (sel, path))
        raise SystemExit(3)
    cur = cur[part]
sys.stdout.write(str(cur))
PYF
}
job_env() {
  python3 - "$WF" "$JOB" "$1" <<'PYF'
import sys, yaml
wf, job, key = sys.argv[1:4]
env = (yaml.safe_load(open(wf))["jobs"].get(job) or {}).get("env") or {}
if key not in env:
    sys.stderr.write("job %s has no env.%s\n" % (job, key)); raise SystemExit(3)
sys.stdout.write(str(env[key]))
PYF
}

SEL_RECONCILE="id:reconcile"
SEL_LABEL="name:Ensure heartbeat-reconcile-mismatch label exists"
SEL_ISSUE="id:reconcile_issue"
SEL_CLEAR="id:reconcile_clear"
SEL_PREP="id:reconcile_email"
SEL_EMAIL="id:reconcile_notify"
SEL_SENTRY="name:Sentry check-in (final)"

for pair in "reconcile|$SEL_RECONCILE" "label|$SEL_LABEL" "issue|$SEL_ISSUE" "clear|$SEL_CLEAR" "prep|$SEL_PREP"; do
  key="${pair%%|*}"; sel="${pair#*|}"
  job_step "$sel" run > "$TMP/steps/$key.sh" || fatal "could not extract run: of $sel — re-point the extractor rather than deleting the case"
  [[ -s "$TMP/steps/$key.sh" ]] || fatal "empty run: body for $sel"
done
LABEL_IF=$(job_step "$SEL_LABEL" if) || fatal "label step has no if:"
ISSUE_IF=$(job_step "$SEL_ISSUE" if) || fatal "issue step has no if:"
CLEAR_IF=$(job_step "$SEL_CLEAR" if) || fatal "clear step has no if:"
PREP_IF=$(job_step "$SEL_PREP" if) || fatal "email-prep step has no if:"
EMAIL_IF=$(job_step "$SEL_EMAIL" if) || fatal "email step has no if:"
EMAIL_SUBJECT=$(job_step "$SEL_EMAIL" with.subject) || fatal "email step has no with.subject"
EMAIL_BODY=$(job_step "$SEL_EMAIL" with.body) || fatal "email step has no with.body"
SENTRY_IF=$(job_step "$SEL_SENTRY" if) || fatal "sentry step has no if:"
SENTRY_STATUS=$(job_step "$SEL_SENTRY" with.status) || fatal "sentry step has no with.status"
LATEST_JQ=$(job_env RECONCILE_LATEST_POST_JQ) || fatal "job has no env.RECONCILE_LATEST_POST_JQ (the shared latest-reconcile-post filter)"
python3 - "$ACTION" > "$TMP/steps/action.sh" <<'PYF' || fatal "could not extract the composite's send step"
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
hits = [s for s in steps if s.get("id") == "send"]
if len(hits) != 1:
    sys.stderr.write("expected exactly 1 composite step with id: send, found %d\n" % len(hits)); raise SystemExit(2)
sys.stdout.write(hits[0]["run"])
PYF
pass "extracted 5 run: bodies, 6 if: expressions, the email subject/body and Sentry status expressions, the shared jq filter and the composite send step"

# ---------------------------------------------------------------------------
# GitHub expression evaluator (subset: literals, dotted context refs, ==, !=, !, &&, ||, (),
# always()/success()/failure()/cancelled()). Semantics per the Actions docs: `==` across
# different types coerces both to numbers (null -> 0, '' -> 0, non-numeric string -> NaN);
# same-type strings compare case-insensitively; `&&`/`||` return an operand. A context ref not
# in the JSON context is null. The job status the status functions read is ctx `__job_status`
# (default success). Mode `if` models the runner: an expression with no status function is
# wrapped in an implicit `success() && (…)`, and the result is TRUTHY unless it is
# false/0/''/null — the STRING 'false' is true. Unknown syntax exits 3 (a harness error).
# ---------------------------------------------------------------------------
cat > "$TMP/expr.py" <<'PYE' || fatal "write expr.py"
import sys, json, re, math
mode, src, ctx = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
job_status = ctx.get("__job_status", "success")
s = src.strip()
if s.startswith("${{") and s.endswith("}}"):
    s = s[3:-2]
tok_re = re.compile(r"\s*(?:('(?:[^']|'')*')|(&&|\|\||==|!=|!|\(|\))|([A-Za-z_][A-Za-z0-9_\-]*(?:\.[A-Za-z_][A-Za-z0-9_\-]*)*)|(\d+(?:\.\d+)?))")
toks, i = [], 0
while i < len(s):
    if s[i:].strip() == "":
        break
    m = tok_re.match(s, i)
    if not m or m.end() == i:
        sys.stderr.write("unparseable expression at %r\n" % s[i:])
        raise SystemExit(3)
    if m.group(1) is not None: toks.append(("str", m.group(1)[1:-1].replace("''", "'")))
    elif m.group(2) is not None: toks.append(("op", m.group(2)))
    elif m.group(3) is not None: toks.append(("id", m.group(3)))
    else: toks.append(("num", float(m.group(4))))
    i = m.end()
FUNCS = {"always": True, "success": job_status == "success",
         "failure": job_status == "failure", "cancelled": job_status == "cancelled"}
uses_status_fn = any(t[0] == "id" and t[1] in FUNCS and k + 1 < len(toks) and toks[k + 1] == ("op", "(")
                     for k, t in enumerate(toks))
pos = 0
def peek():
    return toks[pos] if pos < len(toks) else (None, None)
def take(kind=None, val=None):
    global pos
    t = peek()
    if t[0] is None or (kind and t[0] != kind) or (val and t[1] != val):
        sys.stderr.write("unexpected token %r (wanted %s %s)\n" % (t, kind, val))
        raise SystemExit(3)
    pos += 1
    return t
def truthy(v):
    if v is None or v is False: return False
    if v is True: return True
    if isinstance(v, float): return not (v == 0 or math.isnan(v))
    return v != ""
def tonum(v):
    if v is None: return 0.0
    if isinstance(v, bool): return 1.0 if v else 0.0
    if isinstance(v, float): return v
    t = v.strip()
    if t == "": return 0.0
    try: return float(t)
    except ValueError: return math.nan
def eq(a, b):
    if type(a) is type(b):
        return a.lower() == b.lower() if isinstance(a, str) else a == b
    return tonum(a) == tonum(b)
def primary():
    t = peek()
    if t == ("op", "("):
        take(); v = p_or(); take("op", ")"); return v
    if t[0] == "str": take(); return t[1]
    if t[0] == "num": take(); return t[1]
    if t[0] == "id":
        take()
        if peek() == ("op", "("):
            take(); take("op", ")")
            if t[1] not in FUNCS:
                sys.stderr.write("unsupported function %s\n" % t[1]); raise SystemExit(3)
            return FUNCS[t[1]]
        if t[1] == "true": return True
        if t[1] == "false": return False
        if t[1] == "null": return None
        return ctx.get(t[1])
    sys.stderr.write("unexpected token %r\n" % (t,)); raise SystemExit(3)
def unary():
    if peek() == ("op", "!"):
        take(); return not truthy(unary())
    v = primary()
    if peek() in (("op", "=="), ("op", "!=")):
        op = take()[1]; r = primary()
        return eq(v, r) if op == "==" else not eq(v, r)
    return v
def p_and():
    v = unary()
    while peek() == ("op", "&&"):
        take(); r = unary(); v = r if truthy(v) else v
    return v
def p_or():
    v = p_and()
    while peek() == ("op", "||"):
        take(); r = p_and(); v = v if truthy(v) else r
    return v
out = p_or()
if pos != len(toks):
    sys.stderr.write("trailing tokens %r\n" % (toks[pos:],)); raise SystemExit(3)
if mode == "if":
    ok = truthy(out) and (uses_status_fn or FUNCS["success"])
    print("true" if ok else "false")
else:
    print("true" if out is True else "false" if out is False or out is None else out if isinstance(out, str) else out)
PYE

# ev <expr> <json-ctx> -> printed VALUE; evif <expr> <json-ctx> -> runner if: verdict. Harness error is FATAL.
ev() {
  local v
  v=$(python3 "$TMP/expr.py" value "$1" "$2") || fatal "expression evaluator could not parse: $1"
  printf '%s' "$v"
}
evif() {
  local v
  v=$(python3 "$TMP/expr.py" if "$1" "$2") || fatal "expression evaluator could not parse: $1"
  printf '%s' "$v"
}

echo "S0: instrument self-test — the evaluator reproduces documented Actions semantics"
_s0=1
[[ "$(ev "'2' == 2" '{}')" == "true" ]] || { _s0=0; echo "    '2' == 2 should coerce to true"; }
[[ "$(ev "steps.x.outputs.rc == '0'" '{}')" == "true" ]] || { _s0=0; echo "    null == '0' should coerce to 0 == 0 (the unset-output hazard)"; }
[[ "$(ev "steps.x.outputs.rc == '2'" '{}')" == "false" ]] || { _s0=0; echo "    null == '2' should be false"; }
[[ "$(ev "'' == '0'" '{}')" == "false" ]] || { _s0=0; echo "    '' == '0' (both strings) should be false"; }
[[ "$(ev "'TRUE' == 'true'" '{}')" == "true" ]] || { _s0=0; echo "    string compare should be case-insensitive"; }
[[ "$(ev "'true' == true" '{}')" == "false" ]] || { _s0=0; echo "    'true' == true should be NaN == 1 -> false (the boolean-literal hazard)"; }
[[ "$(ev "false && 'ok' || 'error'" '{}')" == "error" ]] || { _s0=0; echo "    && / || should return operands"; }
[[ "$(ev "always() && (a == '1' || b == 'x')" '{"b":"x"}')" == "true" ]] || { _s0=0; echo "    grouping/always() misparsed"; }
if python3 "$TMP/expr.py" value "a === b" '{}' >/dev/null 2>&1; then _s0=0; echo "    unknown syntax must be a harness error, not a verdict"; fi
if [[ "$_s0" == 1 ]]; then pass "S0a evaluator value semantics"; else fail "S0a evaluator value semantics — every expression verdict below would be untrustworthy"; fi
_s0=1
[[ "$(evif "'false'" '{}')" == "true" ]] || { _s0=0; echo "    if: 'false' (a non-empty STRING) must be truthy"; }
[[ "$(evif "steps.x.outputs.flag" '{"steps.x.outputs.flag":"false"}')" == "true" ]] || { _s0=0; echo "    if: an output holding the string false must be truthy"; }
[[ "$(evif "false" '{}')" == "false" ]] || { _s0=0; echo "    if: false must be falsy"; }
[[ "$(evif "0" '{}')" == "false" ]] || { _s0=0; echo "    if: 0 must be falsy"; }
[[ "$(evif "''" '{}')" == "false" ]] || { _s0=0; echo "    if: '' must be falsy"; }
[[ "$(evif "steps.x.outputs.unset" '{}')" == "false" ]] || { _s0=0; echo "    if: null must be falsy"; }
if [[ "$_s0" == 1 ]]; then pass "S0b if: verdict models runner truthiness (the string 'false' is TRUE)"; else fail "S0b if: truthiness"; fi
_s0=1
[[ "$(evif "a == 'x'" '{"a":"x"}')" == "true" ]] || { _s0=0; echo "    no status fn, job success -> implicit success() true"; }
[[ "$(evif "a == 'x'" '{"a":"x","__job_status":"failure"}')" == "false" ]] || { _s0=0; echo "    no status fn, earlier failure -> implicit success() skips the step"; }
[[ "$(evif "always() && a == 'x'" '{"a":"x","__job_status":"failure"}')" == "true" ]] || { _s0=0; echo "    always() must run after an earlier failure"; }
[[ "$(evif "failure()" '{"__job_status":"failure"}')" == "true" ]] || { _s0=0; echo "    failure() with a failed job"; }
[[ "$(evif "failure()" '{}')" == "false" ]] || { _s0=0; echo "    failure() with a successful job"; }
[[ "$(evif "cancelled()" '{"__job_status":"cancelled"}')" == "true" ]] || { _s0=0; echo "    cancelled() with a cancelled job"; }
[[ "$(evif "success() && a == 'x'" '{"a":"x","__job_status":"cancelled"}')" == "false" ]] || { _s0=0; echo "    explicit success() with a cancelled job"; }
if [[ "$_s0" == 1 ]]; then pass "S0c if: implicit success() prefix and always()/success()/failure()/cancelled() read the job status"; else fail "S0c status functions"; fi

# ---------------------------------------------------------------------------
# STUBS
# ---------------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB' || fatal "write gh stub"
#!/usr/bin/env bash
if [[ "${GH_STUB_MODE:-log}" != "nolog" ]]; then
  { printf 'gh'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$GH_LOG"
fi
case "${1:-} ${2:-}" in
  "issue list")
    if [[ "${GH_LIST_RC:-0}" != "0" ]]; then echo "stub: gh issue list failed (HTTP 502)" >&2; exit "$GH_LIST_RC"; fi
    [[ -n "${GH_LIST_OUT:-}" ]] && printf '%s\n' "$GH_LIST_OUT"
    exit 0 ;;
  "issue view")
    if [[ "${GH_VIEW_RC:-0}" != "0" ]]; then echo "stub: gh issue view failed" >&2; exit "$GH_VIEW_RC"; fi
    filter=""
    while (( $# > 0 )); do if [[ "$1" == "--jq" ]]; then filter="$2"; fi; shift; done
    if [[ -z "$filter" ]]; then cat "$GH_VIEW_FILE"; exit 0; fi
    jq -r "$filter" "$GH_VIEW_FILE"; exit $? ;;
  "issue create")
    printf 'https://github.com/o/r/issues/7001\n'; exit 0 ;;
  "issue edit")
    if [[ "${GH_EDIT_RC:-0}" != "0" ]]; then echo "stub: could not add label" >&2; exit "$GH_EDIT_RC"; fi
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
cat > "$TMP/bin/doppler" <<'STUB' || fatal "write doppler stub"
#!/usr/bin/env bash
printf 'stub-not-a-credential'
STUB
cat > "$TMP/bin/bun" <<'STUB' || fatal "write bun stub"
#!/usr/bin/env bash
cat "$BUN_FIXTURE"
exit "${BUN_RC:-0}"
STUB
cat > "$TMP/bin/curl" <<'STUB' || fatal "write curl stub"
#!/usr/bin/env bash
if [[ "${CURL_CODE:-200}" == "transport" ]]; then exit 7; fi
printf '%s' "${CURL_CODE:-200}"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/doppler" "$TMP/bin/bun" "$TMP/bin/curl" || fatal "chmod stubs"

CASE_N=0
# new_case <marker lines...> — fresh RUNNER_TEMP/GITHUB_OUTPUT/gh log; fixture = the args, one per line.
new_case() {
  CASE_N=$((CASE_N + 1))
  CASE="$TMP/case.$CASE_N"
  mkdir -p "$CASE/rt" || fatal "mkdir case"
  : > "$CASE/out" || fatal "init out"
  : > "$CASE/gh.log" || fatal "init gh.log"
  printf '{"author":{"login":"app/github-actions"},"body":"","comments":[]}' > "$CASE/view" || fatal "init view"
  if (( $# > 0 )); then
    printf '%s\n' "$@" > "$CASE/rt/reconcile-output.txt" || fatal "write fixture"
  else
    : > "$CASE/rt/reconcile-output.txt" || fatal "write fixture"
  fi
}
# mk_view <issue-author> <issue-body> [<comment-author> <comment-body>]... — the issue JSON `gh issue view` reads.
mk_view() {
  local -a args=(--arg a "$1" --arg b "$2")
  local filt='[]' n=0
  shift 2
  while (( $# >= 2 )); do
    args+=(--arg "l$n" "$1" --arg "c$n" "$2")
    filt="$filt + [{author:{login:\$l$n},body:\$c$n}]"
    n=$((n + 1)); shift 2
  done
  jq -n "${args[@]}" "{author:{login:\$a},body:\$b,comments:($filt)}" > "$CASE/view" || fatal "mk_view"
}
# run_step <step-key> [VAR=val...] — execute an extracted body the way Actions does (see SHELL above).
run_step() {
  local key="$1"; shift
  CASE_RC=0
  env -u BASH_ENV -u SHELLOPTS -u BASHOPTS \
    PATH="$TMP/bin:$PATH" RUNNER_TEMP="$CASE/rt" GITHUB_OUTPUT="$CASE/out" \
    GH_LOG="$CASE/gh.log" GH_VIEW_FILE="$CASE/view" GH_TOKEN=stub \
    RUN_NUMBER=7 SERVER_URL=https://github.com REPOSITORY=o/r RUN_ID=99 \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=99 \
    DOPPLER_TOKEN=stub DOPPLER_PROJECT=soleur DOPPLER_CONFIG=prd_terraform \
    RECONCILE_LATEST_POST_JQ="$LATEST_JQ" \
    BUN_FIXTURE="$CASE/rt/reconcile-output.txt.fixture" \
    "$@" bash --noprofile --norc -e "$TMP/steps/$key.sh" > "$CASE/stdout" 2>&1 || CASE_RC=$?
}
out_val() { sed -n "s/^$1=//p" "$CASE/out" | tail -1; }
logged() { grep -qE "$1" "$CASE/gh.log"; }
ghlog() { tr '\n' '|' < "$CASE/gh.log"; }
# edit_adds <issue> <label> — an `issue edit` on <issue> adds <label>.
edit_adds() { logged "^gh issue edit $1( .*)? --add-label $2( |\$)"; }

echo "S1: instrument self-test — run_step scrubs an exported SHELLOPTS (pipefail) from the step shell"
printf 'false | true\n' > "$TMP/steps/selftest-pipefail.sh" || fatal "write selftest body"
new_case
_pf=$(set -o pipefail; export SHELLOPTS; run_step selftest-pipefail; printf '%s' "$CASE_RC")
_ctl=$(set -o pipefail; export SHELLOPTS; bash --noprofile --norc -e "$TMP/steps/selftest-pipefail.sh" >/dev/null 2>&1; printf '%s' "$?")
if [[ "$_pf" == "0" && "$_ctl" != "0" ]]; then
  pass "S1 'false | true' exits 0 through run_step under an exported SHELLOPTS=…pipefail (control without the scrub exits $_ctl)"
else
  fail "S1 run_step must scrub SHELLOPTS: got rc=$_pf through run_step, control rc=$_ctl (the control must fail, or the row proves nothing)"
fi

# ---------------------------------------------------------------------------
# PARITY INPUTS — derived from the lib at test time, never restated here.
# ---------------------------------------------------------------------------
REASONS_LIST=$(python3 - "$LIB" <<'PYF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"export\s+type\s+ViolationReason\s*=([^;]*);", src)
if not m:
    raise SystemExit(2)
body = m.group(1)
# Either a literal union (`"a" | "b"`) or `(typeof CONST)[number]` over an exported `as const` array.
ref = re.search(r"typeof\s+([A-Za-z_][A-Za-z0-9_]*)", body)
if ref:
    arr = re.search(r"export\s+const\s+" + re.escape(ref.group(1)) + r"\s*=\s*\[([^\]]*)\]", src)
    if not arr:
        raise SystemExit(2)
    body = arr.group(1)
print("\n".join(re.findall(r'"([a-z][a-z-]*)"', body)))
PYF
) || fatal "could not read the ViolationReason union from $LIB"
[[ -n "$REASONS_LIST" ]] || fatal "the ViolationReason union in $LIB named no reasons"
LIB_ROUTE_RE=$(python3 - "$LIB" <<'PYF'
import re, sys
src = open(sys.argv[1]).read()
# A regex literal (`/…/flags`) or a regex SOURCE string (`"…"`).
m = re.search(r'export\s+const\s+ROUTE_TOKEN_RE\s*(?::[^=]+)?=\s*(?:/(.+)/[a-z]*|"([^"]*)")\s*;', src)
print((m.group(1) or m.group(2)) if m else "")
PYF
) || fatal "could not scan $LIB for ROUTE_TOKEN_RE"

# Marker fixtures — the reconcile script's grammar: routing tokens (incl. the single route=) before
# the first `"`; every vendor-sourced field quoted and last.
M_GITDATA='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-git-data-prd live=absent reason=absent-live resource=betteruptime_heartbeat.git_data_prd route=absent-live~resource.betteruptime_heartbeat.git_data_prd'
M_GITDATA_SHORT='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-git-data live=absent reason=absent-live resource=betteruptime_heartbeat.git_data route=absent-live~resource.betteruptime_heartbeat.git_data'
M_GITDATA_PAUSED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-git-data-prd live=paused reason=fed-but-paused resource=betteruptime_heartbeat.git_data_prd route=fed-but-paused~resource.betteruptime_heartbeat.git_data_prd'
M_ZOT_1='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-web-zot-consumer-web-1 live=absent reason=absent-live resource=betteruptime_heartbeat.web_zot_consumer route=absent-live~resource.betteruptime_heartbeat.web_zot_consumer.web-1'
M_ZOT_2='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-web-zot-consumer-web-2 live=absent reason=absent-live resource=betteruptime_heartbeat.web_zot_consumer route=absent-live~resource.betteruptime_heartbeat.web_zot_consumer.web-2'
M_UNMANAGED_9='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=9 route=unmanaged-live~id.9 url="https://example.soleur.ai/" name="example"'
M_UNMANAGED_94='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=94 route=unmanaged-live~id.94 url="https://u.soleur.ai/" name="n"'
M_DRIFT='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=4226366 resource=betteruptime_monitor.app_health field=monitor_type route=monitor-config-drift~id.4226366.monitor_type detail="declared=keyword live=status"'
M_DRIFT_PAUSED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=4226366 resource=betteruptime_monitor.app_health field=paused route=monitor-config-drift~id.4226366.paused detail="declared=false live=true"'
M_ABSENT_MON='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=betteruptime_monitor.app_health route=absent-live~resource.betteruptime_monitor.app_health url="https://app.soleur.ai/health"'
M_KEYLESS='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-legacy live=paused reason=fed-but-paused'
M_ERROR='SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=auth detail="HTTP 401"'
M_DECL_ERROR='SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=declarations reason=parse-error detail="uptime-alerts.tf: unterminated block"'
M_OK='SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=4 live=4 matched=4226366,4422675'
M_OK_HB='SOLEUR_HEARTBEAT_RECONCILE_OK surface=heartbeats checked=5 live=5'
M_UNREACHABLE='SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=monitors detail="fetch failed after 3 attempts"'
# H2: vendor name carrying spaces, forged routing tokens and a backtick fence inside quotes.
M_FORGED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=7 route=unmanaged-live~id.7 url="https://x.soleur.ai/" name="evil id=1 route=monitor-config-drift~id.1.paused resource=betteruptime_monitor.app_health ``` reason=monitor-config-drift"'
M_DRIFT_FORGED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=4226366 resource=betteruptime_monitor.app_health field=required_keyword route=monitor-config-drift~id.4226366.required_keyword detail="declared=a live=b reason=unmanaged-live route=unmanaged-live~id.5"'
BOT=github-actions
HUMAN=deruelle
# A reconcile post as the workflow writes it (prose + fenced markers).
post() { printf 'Mismatch still present as of 2026-09-14 06:00 UTC.\n\n<details><summary>Reconcile markers</summary>\n\n```\n'; printf '%s\n' "$@"; printf '```\n\n</details>\n'; }

# ---------------------------------------------------------------------------
echo "R: the reconcile step publishes has_mismatch from line-anchored MISMATCH markers"
# ---------------------------------------------------------------------------
new_case "$M_ERROR" "$M_GITDATA"; cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture" || fatal "cp fixture"
run_step reconcile BUN_RC=1
if [[ "$(out_val rc)" == "1" && "$(out_val has_mismatch)" == "true" ]]; then
  pass "R1 rc=1 with a MISMATCH row publishes rc=1 has_mismatch=true"
else
  fail "R1 an ERROR arm plus a MISMATCH row must publish rc=1 AND has_mismatch=true (got rc='$(out_val rc)' has_mismatch='$(out_val has_mismatch)') — without it the rc=1 run hides the mismatch from the issue"
fi
new_case "$M_OK"; cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture" || fatal "cp fixture"
run_step reconcile BUN_RC=0
if [[ "$(out_val has_mismatch)" == "false" ]]; then pass "R2 OK-only output publishes has_mismatch=false"
else fail "R2 OK-only output must publish has_mismatch=false (got '$(out_val has_mismatch)')"; fi
new_case 'SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=uncaught detail="boom SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=x"'
cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture" || fatal "cp fixture"
run_step reconcile BUN_RC=1
if [[ "$(out_val has_mismatch)" == "false" ]]; then pass "R3 a MISMATCH spelling mid-line (inside an ERROR detail) does not set has_mismatch"
else fail "R3 has_mismatch must be anchored at line start (got '$(out_val has_mismatch)')"; fi

# ---------------------------------------------------------------------------
echo "W1: a failing 'gh issue list' fails the step and files nothing"
# ---------------------------------------------------------------------------
check_w1() {
  [[ "$CASE_RC" != "0" ]] && logged '^gh issue list ' && ! logged '^gh issue (create|comment|edit) '
}
new_case "$M_GITDATA" "$M_UNMANAGED_9"
run_step issue GH_LIST_RC=1
if check_w1; then pass "W1 lookup failure -> step rc=$CASE_RC, lookup logged, no create/comment/edit"
else fail "W1 a failing gh issue list must fail the step with no issue create/comment/edit (step rc=$CASE_RC; gh log: $(ghlog)) — the #8140 duplicate"; fi

# ---------------------------------------------------------------------------
# escalate_case <latest-bot-post-markers (newline-joined)> <marker lines...> -> existing-issue path,
# history = ONE bot comment carrying those markers.
escalate_case() {
  local hist="$1"; shift
  new_case "$@"
  mk_view app/github-actions "" "$BOT" "$(post "$hist")"
  run_step issue GH_LIST_OUT=6645
}
# history_case <mk_view args...> -- <marker lines...>
history_case() {
  local -a view=()
  while (( $# > 0 )) && [[ "$1" != "--" ]]; do view+=("$1"); shift; done
  shift
  new_case "$@"
  mk_view "${view[@]}"
  run_step issue GH_LIST_OUT=6645
}
esc_row() { # esc_row <id> <expected escalate> <description>
  if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "$2" ]]; then pass "$1 $3 -> escalate=$2"
  else fail "$1 $3 must give escalate=$2 (rc=$CASE_RC escalate='$(out_val escalate)'; stdout: $(tail -3 "$CASE/stdout" | tr '\n' '|'))"; fi
}
echo "W2-W5 + K: escalation keys are whole route= tokens from the pre-quote prefix"
escalate_case "$M_GITDATA" "$M_GITDATA_SHORT"
esc_row W2 true "route=…git_data is new although the latest post has …git_data_prd (a prefix is not a match)"
escalate_case "$(printf 'old line\n%s' "$M_GITDATA")" "$M_GITDATA"
_a=$(out_val escalate); _arc=$CASE_RC
new_case "$M_GITDATA"; mk_view app/github-actions "" "$BOT" "$(printf '%s\ntrailing prose' "$M_GITDATA")"; run_step issue GH_LIST_OUT=6645
if [[ "$_arc" == 0 && "$_a" == "false" && "$CASE_RC" == 0 && "$(out_val escalate)" == "false" ]]; then
  pass "W3 a key recorded mid-post / at the very end of the post -> escalate=false"
else
  fail "W3 a recorded key must NOT escalate wherever it sits in the post (fenced: rc=$_arc escalate='$_a'; end-of-text: rc=$CASE_RC escalate='$(out_val escalate)')"
fi
escalate_case "$M_UNMANAGED_94" "$M_UNMANAGED_9"
esc_row W4 true "current id.9 vs recorded id.94"
escalate_case "$M_GITDATA" "$M_GITDATA" "$M_UNMANAGED_9"
esc_row W5 true "a new key after a known key in the same run"
escalate_case "$M_KEYLESS" "$M_KEYLESS"
esc_row K1 true "a MISMATCH row with no route= token (fail safe), even if its text is already recorded"
escalate_case "$M_GITDATA" "$M_GITDATA"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "false" && "$(out_val created)" == "false" ]] && logged '^gh issue comment 6645 ' && ! logged '^gh issue create '; then
  pass "K2 must-pass: every key already recorded -> comment on #6645, escalate=false, no create"
else
  fail "K2 a fully-recorded run must comment on the open issue without escalating (rc=$CASE_RC escalate='$(out_val escalate)' created='$(out_val created)'; gh log: $(ghlog))"
fi

# ---------------------------------------------------------------------------
echo "G: history is the workflow's OWN most recent reconcile post, MISMATCH lines only"
# ---------------------------------------------------------------------------
escalate_case "$M_DRIFT_PAUSED" "$M_DRIFT"
esc_row G1 true "a new field (monitor_type) on an id whose paused drift is recorded"
escalate_case "$M_ZOT_1" "$M_ZOT_1" "$M_ZOT_2"
esc_row G2 true "a second for_each instance (web-2) of a recorded resource (web-1)"
escalate_case "$M_GITDATA_PAUSED" "$M_GITDATA"
esc_row G3 true "a reason change (fed-but-paused -> absent-live) on the same resource"
history_case app/github-actions "" "$BOT" "$(post "$M_GITDATA")" "$BOT" "$(post "$M_UNMANAGED_9")" -- "$M_GITDATA" "$M_UNMANAGED_9"
esc_row G4 true "a key present in an OLDER bot post but absent from the latest one (the row cleared and returned)"
history_case app/github-actions "" "$BOT" "$(post "$M_UNMANAGED_9")" "$BOT" "$(post "$M_GITDATA" "$M_UNMANAGED_9")" -- "$M_GITDATA" "$M_UNMANAGED_9"
esc_row G5 false "every key in the latest bot post (must-pass: a persisting row does not re-email)"
history_case app/github-actions "" "$BOT" "$(post "$M_UNMANAGED_9")" "$HUMAN" "$(post "$M_GITDATA")" -- "$M_GITDATA"
esc_row G6 true "a key present only in a HUMAN comment posted after the latest bot post"
escalate_case "$M_KEYLESS" "$M_KEYLESS" "$M_GITDATA"
esc_row G7 true "a keyless row alongside a recorded key"
escalate_case "$M_DRIFT" "$M_DRIFT"
esc_row G8 true "a monitor-config-drift row whose key IS in the latest bot post (alarm disarm is never silent)"
history_case app/github-actions "$(post "$M_GITDATA")" -- "$M_GITDATA"
esc_row G9a false "no bot comments yet: the bot-authored issue BODY is the latest post and records the key"
history_case "$HUMAN" "$(post "$M_GITDATA")" -- "$M_GITDATA"
esc_row G9b true "an issue body authored by a human does not record the key"
escalate_case "$(printf '%s\nprose that mentions %s' "$M_UNMANAGED_9" "route=absent-live~resource.betteruptime_heartbeat.git_data_prd")" "$M_GITDATA"
esc_row G10 true "a route= token on a non-MISMATCH line of the bot post does not record the key"
history_case app/github-actions "" "$BOT" "$(post "$M_GITDATA")" "$BOT" "$(printf 'All reconcile rows cleared as of 2026-09-14 18:00 UTC.\n\n```\nSOLEUR_HEARTBEAT_RECONCILE_CLEAR\n%s\n```\n' "$M_OK")" -- "$M_GITDATA"
esc_row G11 true "a key recorded before a later bot CLEAR post (the row cleared fully and returned)"
new_case "$M_GITDATA"; mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")"; run_step issue GH_LIST_OUT=6645 GH_VIEW_RC=1
esc_row G12 true "a failed history read (too loud, never silent)"

# ---------------------------------------------------------------------------
echo "L: routing labels — added before the comment; a label failure only warns"
# ---------------------------------------------------------------------------
comment_after_edit() {
  local e c
  e=$(grep -n '^gh issue edit ' "$CASE/gh.log" | head -1 | cut -d: -f1)
  c=$(grep -n '^gh issue comment ' "$CASE/gh.log" | head -1 | cut -d: -f1)
  [[ -n "$e" && -n "$c" ]] && (( e < c ))
}
check_w6_existing() { [[ "$CASE_RC" == 0 ]] && edit_adds 6645 infra-drift && edit_adds 6645 'priority/p2-medium'; }
check_w6_new() {
  [[ "$CASE_RC" == 0 ]] && logged '^gh issue create .*--label heartbeat-reconcile-mismatch( |$)' \
    && logged '^gh issue create .*--milestone ' && edit_adds 7001 infra-drift && edit_adds 7001 'priority/p2-medium'
}
escalate_case "$M_GITDATA" "$M_GITDATA" "$M_UNMANAGED_9"
if check_w6_existing && ! edit_adds 6645 action-required; then pass "W6a existing issue + unmanaged-live row -> edit 6645 adds infra-drift + priority/p2-medium (not action-required)"
else fail "W6a an unmanaged-live row on an open issue must add infra-drift and priority/p2-medium only (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_UNMANAGED_9"
run_step issue
if check_w6_new && [[ "$(out_val created)" == "true" ]]; then pass "W6b no open issue + unmanaged-live row -> create (base label + milestone), then edit 7001 adds infra-drift + priority/p2-medium"
else fail "W6b a new issue for an unmanaged-live row must be created with the base label and a milestone, then gain infra-drift + priority/p2-medium (rc=$CASE_RC created='$(out_val created)'; gh log: $(ghlog))"; fi
new_case "$M_GITDATA"
run_step issue
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue create .*--label heartbeat-reconcile-mismatch' && ! logged '^gh issue edit '; then
  pass "W6c must-pass: no unmanaged/drift row -> create, no label edit"
else
  fail "W6c a run with no unmanaged-live or monitor-config-drift row must not edit labels (rc=$CASE_RC; gh log: $(ghlog))"
fi
new_case "$M_UNMANAGED_9"
run_step label
_lbl_ok=1
for _l in heartbeat-reconcile-mismatch infra-drift action-required 'priority/p1-high' 'priority/p2-medium'; do
  logged "^gh label create $_l " || _lbl_ok=0
done
if [[ "$_lbl_ok" == 1 ]]; then pass "W6d the label step ensures heartbeat-reconcile-mismatch, infra-drift, action-required, priority/p1-high and priority/p2-medium exist"
else fail "W6d the label step must ensure every routing label exists (gh log: $(ghlog))"; fi
escalate_case "$M_GITDATA" "$M_GITDATA" "$M_DRIFT"
if [[ "$CASE_RC" == 0 ]] && edit_adds 6645 action-required && edit_adds 6645 'priority/p1-high' && ! edit_adds 6645 infra-drift; then
  pass "L1 existing issue + monitor-config-drift row -> edit 6645 adds action-required + priority/p1-high"
else
  fail "L1 a monitor-config-drift row must add action-required and priority/p1-high (rc=$CASE_RC; gh log: $(ghlog))"
fi
if comment_after_edit; then pass "L2 the label edit runs BEFORE the comment"
else fail "L2 gh issue edit must precede gh issue comment (gh log: $(ghlog))"; fi
new_case "$M_GITDATA" "$M_DRIFT" "$M_UNMANAGED_9"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")"
run_step issue GH_LIST_OUT=6645 GH_EDIT_RC=1
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue comment 6645 ' && [[ "$(out_val escalate)" == "true" ]] && grep -q '::warning::' "$CASE/stdout"; then
  pass "L3 a failing label edit on the existing issue warns; the comment and escalate=true still land (step succeeds)"
else
  fail "L3 a label failure alone must not fail the filer (rc=$CASE_RC escalate='$(out_val escalate)'; gh log: $(ghlog); stdout: $(tail -3 "$CASE/stdout" | tr '\n' '|'))"
fi
new_case "$M_DRIFT"
run_step issue GH_EDIT_RC=1
if [[ "$CASE_RC" == 0 && "$(out_val created)" == "true" ]] && edit_adds 7001 action-required && grep -q '::warning::' "$CASE/stdout"; then
  pass "L4 new issue + drift row: a failing label edit warns and created=true still lands"
else
  fail "L4 a label failure on a new issue must warn, not fail the filer (rc=$CASE_RC created='$(out_val created)'; gh log: $(ghlog))"
fi
new_case "$M_UNMANAGED_9"
run_step issue
BODY="$CASE/rt/reconcile-body.md"
if [[ -f "$BODY" ]] && grep -qi 'untrusted vendor data' "$BODY" && grep -qF '/soleur:one-shot' "$BODY" \
   && grep -qF 'import {}' "$BODY" && grep -qF 'monitor-config-drift' "$BODY" && grep -qF 'unmanaged-live' "$BODY" && grep -qF 'route=' "$BODY"; then
  pass "W6e the new-issue body frames markers as untrusted vendor data, decodes route=, unmanaged-live and monitor-config-drift, and gives the adoption path"
else
  fail "W6e the issue body (written under RUNNER_TEMP) must frame the markers as untrusted vendor data, decode route=, unmanaged-live and monitor-config-drift, and give the /soleur:one-shot import {} adoption path"
fi

# ---------------------------------------------------------------------------
echo "H2: vendor text inside quotes never routes"
# ---------------------------------------------------------------------------
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=1 route=unmanaged-live~id.1 url="u" name="n"' "$M_FORGED"
esc_row H2a true "a quoted 'id=1 route=…' in a vendor name is not a key: the real id.7 is new"
if ! edit_adds 6645 action-required; then pass "H2a' a quoted route=monitor-config-drift~… adds no action-required label"
else fail "H2a' vendor text must not add action-required (gh log: $(ghlog))"; fi
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=7 route=unmanaged-live~id.7 url="u" name="n"' "$M_FORGED"
esc_row H2b false "must-pass: the real pre-quote route=unmanaged-live~id.7 is the key and is recorded"
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=8 route=unmanaged-live~id.8 url="u" name="old route=unmanaged-live~id.7"' "$M_FORGED"
esc_row H2c true "a key that appears only inside quotes in the HISTORY is not recorded"
escalate_case "$M_DRIFT_FORGED" "$M_DRIFT_FORGED"
if [[ "$CASE_RC" == 0 ]] && ! logged 'infra-drift'; then pass "H2d 'reason=unmanaged-live route=unmanaged-live~…' inside a quoted detail does not add infra-drift"
else fail "H2d a quoted reason=/route= must not route to infra-drift (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_FORGED"
run_step issue
BODY="$CASE/rt/reconcile-body.md"
_fence=$(grep -m1 -E '^`{3,}$' "$BODY" 2>/dev/null || true)
if [[ -n "$_fence" && "${#_fence}" -gt 3 ]] && [[ "$(grep -cxF "$_fence" "$BODY")" == "2" ]]; then
  pass "H2e a backtick run in vendor text gets a longer fence (${#_fence} backticks), so it cannot close the block"
else
  fail "H2e the markers fence must be longer than any backtick run in the markers (fence='${_fence}')"
fi

# ---------------------------------------------------------------------------
echo "H1: a gh stub that logs nothing must turn W1, W6 and L1 RED (the checks are not vacuous)"
# ---------------------------------------------------------------------------
new_case "$M_GITDATA"
run_step issue GH_LIST_RC=1 GH_STUB_MODE=nolog
if check_w1; then fail "H1 W1's check passed with a non-logging gh stub — it asserts nothing"; else pass "H1 W1 goes RED under a non-logging gh stub"; fi
new_case "$M_GITDATA" "$M_UNMANAGED_9"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")"
run_step issue GH_LIST_OUT=6645 GH_STUB_MODE=nolog
if check_w6_existing; then fail "H1 W6a's check passed with a non-logging gh stub"; else pass "H1 W6a goes RED under a non-logging gh stub"; fi
new_case "$M_UNMANAGED_9"
run_step issue GH_STUB_MODE=nolog
if check_w6_new; then fail "H1 W6b's check passed with a non-logging gh stub"; else pass "H1 W6b goes RED under a non-logging gh stub"; fi
if comment_after_edit; then fail "H1 L2's ordering check passed with a non-logging gh stub"; else pass "H1 L2 goes RED under a non-logging gh stub"; fi

# ---------------------------------------------------------------------------
echo "C: a fully clean run records a CLEAR post once, so a returning row re-emails"
# ---------------------------------------------------------------------------
new_case "$M_OK" "$M_OK_HB"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")"
run_step clear GH_LIST_OUT=6645
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue comment 6645 ' && grep -qx 'SOLEUR_HEARTBEAT_RECONCILE_CLEAR' "$CASE/rt/reconcile-clear.md" 2>/dev/null \
   && ! grep -q '^SOLEUR_HEARTBEAT_RECONCILE_MISMATCH ' "$CASE/rt/reconcile-clear.md"; then
  pass "C1 clean run + latest bot post has MISMATCH rows -> one CLEAR comment on #6645"
else
  fail "C1 a clean run must record a CLEAR post when the latest reconcile post still lists rows (rc=$CASE_RC; gh log: $(ghlog))"
fi
# The CLEAR post C1 wrote must itself be read as the latest post by the issue step's filter (G11 uses a hand-written copy).
if [[ -f "$CASE/rt/reconcile-clear.md" ]]; then
  _clear_body=$(cat "$CASE/rt/reconcile-clear.md")
  history_case app/github-actions "" "$BOT" "$(post "$M_GITDATA")" "$BOT" "$_clear_body" -- "$M_GITDATA"
  esc_row C1b true "the CLEAR post the clear step writes is the latest post for the issue step"
else
  fail "C1b the clear step wrote no reconcile-clear.md to feed back through the issue step"
fi
new_case "$M_OK" "$M_OK_HB"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")" "$BOT" "$(printf 'All reconcile rows cleared.\n\n```\nSOLEUR_HEARTBEAT_RECONCILE_CLEAR\n%s\n```\n' "$M_OK")"
run_step clear GH_LIST_OUT=6645
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue view 6645 ' && ! logged '^gh issue comment '; then pass "C2 the latest post is already a CLEAR post -> no second comment"
else fail "C2 a clear must be recorded once, not every clean run (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_OK" "$M_UNREACHABLE"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")"
run_step clear GH_LIST_OUT=6645
if [[ "$CASE_RC" == 0 ]] && ! logged '^gh issue comment '; then pass "C3 an arm UNREACHABLE this run -> no CLEAR (its rows were not observed)"
else fail "C3 an unreachable arm must not record a clear (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_OK" "$M_OK_HB"
run_step clear
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue list ' && ! logged '^gh issue (comment|view) '; then pass "C4 no open reconcile issue -> nothing to clear"
else fail "C4 with no open issue the clear step must post nothing (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_OK" "$M_OK_HB"
run_step clear GH_LIST_RC=1
if [[ "$CASE_RC" != 0 ]] && ! logged '^gh issue comment '; then pass "C5 a failing lookup fails the clear step (the Sentry status reads its outcome)"
else fail "C5 a failed lookup must fail the clear step (rc=$CASE_RC; gh log: $(ghlog))"; fi
new_case "$M_OK" "$M_OK_HB"
mk_view app/github-actions "" "$BOT" "$(post "$M_GITDATA")" "$HUMAN" "All fixed, thanks"
run_step clear GH_LIST_OUT=6645
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue comment 6645 '; then pass "C6 a later human comment does not read as a recorded clear"
else fail "C6 only a bot CLEAR post suppresses the clear comment (rc=$CASE_RC; gh log: $(ghlog))"; fi

# ---------------------------------------------------------------------------
echo "A: the notify-ops-email composite exposes whether the email was sent"
# ---------------------------------------------------------------------------
run_action() {
  CASE_RC=0
  env -u BASH_ENV -u SHELLOPTS -u BASHOPTS \
    PATH="$TMP/bin:$PATH" RUNNER_TEMP="$CASE/rt" GITHUB_OUTPUT="$CASE/out" \
    EMAIL_SUBJECT=s EMAIL_BODY=b "$@" \
    bash --noprofile --norc -eo pipefail "$TMP/steps/action.sh" > "$CASE/stdout" 2>&1 || CASE_RC=$?
}
new_case; run_action RESEND_API_KEY=stub CURL_CODE=200
if [[ "$CASE_RC" == 0 && "$(out_val sent)" == "true" ]]; then pass "A1 HTTP 200 -> sent=true, exit 0"
else fail "A1 a 2xx must publish sent=true (rc=$CASE_RC sent='$(out_val sent)')"; fi
new_case; run_action RESEND_API_KEY=stub CURL_CODE=500
if [[ "$CASE_RC" == 0 && "$(out_val sent)" == "false" ]] && grep -q '::warning::Email notification failed' "$CASE/stdout"; then
  pass "A2 HTTP 500 -> sent=false, still only a warning and exit 0 (other callers unchanged)"
else
  fail "A2 a non-2xx must publish sent=false and keep the warning-only exit 0 (rc=$CASE_RC sent='$(out_val sent)')"
fi
new_case; run_action RESEND_API_KEY=stub CURL_CODE=transport
if [[ "$CASE_RC" == 0 && "$(out_val sent)" == "false" ]]; then pass "A3 transport failure (000) -> sent=false, exit 0"
else fail "A3 a transport failure must publish sent=false (rc=$CASE_RC sent='$(out_val sent)')"; fi
new_case; run_action RESEND_API_KEY=
if [[ "$CASE_RC" != 0 && "$(out_val sent)" == "false" ]]; then pass "A4 missing RESEND_API_KEY -> exit non-zero (unchanged) and sent=false"
else fail "A4 a missing key must still fail the step and publish sent=false (rc=$CASE_RC sent='$(out_val sent)')"; fi
_aout=$(python3 -c 'import sys,yaml; print(((yaml.safe_load(open(sys.argv[1])).get("outputs") or {}).get("sent") or {}).get("value",""))' "$ACTION") || fatal "read action outputs"
if [[ "$(tr -d ' ' <<<"$_aout")" == '${{steps.send.outputs.sent}}' ]]; then pass "A5 the composite maps outputs.sent to steps.send.outputs.sent"
else fail "A5 the composite must expose outputs.sent from its send step (got '$_aout')"; fi

# ---------------------------------------------------------------------------
echo "W7: evaluated if: / status / subject expressions"
# ---------------------------------------------------------------------------
# w7_if <label> <expr> <ctx-json> <expected> — runner if: verdict (truthiness + implicit success()).
w7_if() {
  local got; got=$(evif "$2" "$3")
  if [[ "$got" == "$4" ]]; then pass "W7 $1 -> $4"
  else fail "W7 $1: expected '$4', got '$got' (expr: $(tr -s ' \n' ' ' <<<"$2"); ctx: $3)"; fi
}
# w7_val <label> <expr> <ctx-json> <expected> — expression VALUE.
w7_val() {
  local got; got=$(ev "$2" "$3")
  if [[ "$got" == "$4" ]]; then pass "W7 $1 -> $4"
  else fail "W7 $1: expected '$4', got '$got' (expr: $(tr -s ' \n' ' ' <<<"$2"); ctx: $3)"; fi
}
for pair in "label|$LABEL_IF" "issue|$ISSUE_IF"; do
  n="${pair%%|*}"; e="${pair#*|}"
  w7_if "$n if: rc=2" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile.outputs.has_mismatch":"true"}' true
  w7_if "$n if: rc=1 has_mismatch=true" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile.outputs.has_mismatch":"true"}' true
  w7_if "$n if: rc=1 has_mismatch=false" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile.outputs.has_mismatch":"false"}' false
  w7_if "$n if: rc=1 has_mismatch unset" "$e" '{"steps.reconcile.outputs.rc":"1"}' false
  w7_if "$n if: rc=0" "$e" '{"steps.reconcile.outputs.rc":"0","steps.reconcile.outputs.has_mismatch":"false"}' false
  w7_if "$n if: rc unset" "$e" '{}' false
  w7_if "$n if: rc=2 after an earlier failed step" "$e" '{"__job_status":"failure","steps.reconcile.outputs.rc":"2","steps.reconcile.outputs.has_mismatch":"true"}' true
done
w7_if "clear if: rc=0 clean" "$CLEAR_IF" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"0","steps.reconcile.outputs.has_mismatch":"false"}' true
w7_if "clear if: rc=2" "$CLEAR_IF" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"2","steps.reconcile.outputs.has_mismatch":"true"}' false
w7_if "clear if: rc=1" "$CLEAR_IF" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"1","steps.reconcile.outputs.has_mismatch":"false"}' false
w7_if "clear if: reconcile step never wrote rc (null == '0' hazard)" "$CLEAR_IF" '{"steps.reconcile.outcome":"failure"}' false
w7_if "clear if: reconcile skipped after an earlier failure" "$CLEAR_IF" '{"__job_status":"failure","steps.reconcile.outcome":"skipped"}' false
for pair in "email-prep|$PREP_IF" "email|$EMAIL_IF"; do
  n="${pair%%|*}"; e="${pair#*|}"
  w7_if "$n if: rc=2, known rows, filer failed" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"failure"}' true
  w7_if "$n if: rc=2, known rows, filer cancelled" "$e" '{"__job_status":"cancelled","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"cancelled"}' true
  w7_if "$n if: rc=2, known rows, filer ok" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"false","steps.reconcile_issue.outputs.escalate":"false"}' false
  w7_if "$n if: rc=2 escalate=true" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"false","steps.reconcile_issue.outputs.escalate":"true"}' true
  w7_if "$n if: rc=1" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile_issue.outcome":"skipped"}' true
  w7_if "$n if: rc=0 filer skipped" "$e" '{"steps.reconcile.outputs.rc":"0","steps.reconcile_issue.outcome":"skipped"}' false
  w7_if "$n if: created=true after an earlier failed step" "$e" '{"__job_status":"failure","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"true"}' true
done
w7_if "email if: prep step FAILED after created=true (the job is failing) -> still sends" "$EMAIL_IF" '{"__job_status":"failure","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"true","steps.reconcile_email.outcome":"failure"}' true
_subj=$(ev "$EMAIL_SUBJECT" '{"steps.reconcile_email.outcome":"failure"}')
if [[ "$_subj" == "[ERROR]"* ]]; then pass "W7 email subject falls back to an [ERROR] subject when the prep step wrote none ('$_subj')"
else fail "W7 a failed prep step must still produce a non-empty [ERROR] subject (got '$_subj')"; fi
_body=$(ev "$EMAIL_BODY" '{"steps.reconcile_email.outcome":"failure"}')
if [[ -n "$_body" && "$_body" != "false" ]]; then pass "W7 email body falls back to a non-empty notice when the prep step wrote none"
else fail "W7 a failed prep step must still produce a non-empty body (got '$_body')"; fi
w7_val "email subject: prep ok keeps the prepared subject" "$EMAIL_SUBJECT" '{"steps.reconcile_email.outputs.subject":"[HEARTBEAT] x"}' "[HEARTBEAT] x"
w7_if "sentry if: always runs" "$SENTRY_IF" '{"__job_status":"failure","steps.reconcile_issue.outcome":"failure"}' true
# The all-good baseline, then one fault at a time.
OKCTX='"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_clear.outcome":"skipped","steps.reconcile_email.outcome":"success","steps.reconcile_notify.outcome":"success","steps.reconcile_notify.outputs.sent":"true"'
w7_val "sentry status: rc=2 filer ok, email sent" "$SENTRY_STATUS" "{$OKCTX}" ok
w7_val "sentry status: rc=2 filer failed" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_issue.outcome\":\"failure\"}" error
w7_val "sentry status: rc=2 filer cancelled" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_issue.outcome\":\"cancelled\"}" error
w7_val "sentry status: email-prep failed" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_email.outcome\":\"failure\"}" error
w7_val "sentry status: email-prep cancelled" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_email.outcome\":\"cancelled\"}" error
w7_val "sentry status: email required but not delivered (sent=false)" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_notify.outputs.sent\":\"false\"}" error
w7_val "sentry status: email step failed (missing key, sent unset)" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_notify.outcome\":\"failure\",\"steps.reconcile_notify.outputs.sent\":null}" error
w7_val "sentry status: clear step failed" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile_clear.outcome\":\"failure\"}" error
w7_val "sentry status: rc=0, nothing required (filer/prep/email skipped, clear ok)" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"0","steps.reconcile_issue.outcome":"skipped","steps.reconcile_clear.outcome":"success","steps.reconcile_email.outcome":"skipped","steps.reconcile_notify.outcome":"skipped"}' ok
w7_val "sentry status: rc=1" "$SENTRY_STATUS" "{$OKCTX,\"steps.reconcile.outputs.rc\":\"1\"}" error
w7_val "sentry status: reconcile step failed before writing rc (null == '0' hazard)" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"failure","steps.reconcile_issue.outcome":"skipped","steps.reconcile_clear.outcome":"skipped","steps.reconcile_email.outcome":"skipped","steps.reconcile_notify.outcome":"skipped"}' error
w7_val "sentry status: reconcile skipped after an earlier failed step" "$SENTRY_STATUS" '{"__job_status":"failure","steps.reconcile.outcome":"skipped","steps.reconcile_issue.outcome":"skipped","steps.reconcile_clear.outcome":"skipped","steps.reconcile_email.outcome":"skipped","steps.reconcile_notify.outcome":"skipped"}' error

# ---------------------------------------------------------------------------
echo "E: email content — subject precedence, class sentences above raw markers, random delimiter"
# ---------------------------------------------------------------------------
# email_case <RC> <ISSUE_OUTCOME> <marker lines...>
email_case() {
  local rc="$1" oc="$2"; shift 2
  new_case "$@"
  run_step prep RC="$rc" ISSUE_OUTCOME="$oc"
  SUBJ=$(out_val subject)
  DELIM=$(sed -n 's/^body<<//p' "$CASE/out" | head -1)
  MAIL=""
  if [[ -n "$DELIM" ]]; then
    MAIL=$(awk -v d="$DELIM" 'f && $0 == d {exit} f {print} $0 == "body<<" d {f=1}' "$CASE/out")
  fi
}
email_case 1 success "$M_DECL_ERROR" "$M_DRIFT" "$M_UNMANAGED_9"
if [[ "$CASE_RC" == 0 && "$SUBJ" == "[ERROR] Better Stack heartbeat live-reconcile failed" ]] && grep -qF '<h2>Reconcile error</h2>' <<<"$MAIL"; then
  pass "E1 rc=1 outranks config drift and unmanaged rows -> existing [ERROR] subject, 'Reconcile error' heading"
else
  fail "E1 rc=1 must keep the existing [ERROR] subject and a 'Reconcile error' heading (rc=$CASE_RC subject='$SUBJ')"
fi
email_case 2 success "$M_UNMANAGED_9" "$M_DRIFT" "$M_GITDATA"
if [[ "$SUBJ" == "[ALARM DISARMED] Better Stack monitor config drift" ]]; then pass "E2 monitor-config-drift outranks unmanaged-live"
else fail "E2 expected the [ALARM DISARMED] subject, got '$SUBJ'"; fi
_E2_MAIL="$MAIL"
email_case 2 success "$M_GITDATA" "$M_ABSENT_MON" "$M_UNMANAGED_9"
if [[ "$SUBJ" == "[INFRA-DRIFT] Better Stack object live but unmanaged by Terraform" ]]; then pass "E3 unmanaged-live outranks the default mismatch subject"
else fail "E3 expected the [INFRA-DRIFT] subject, got '$SUBJ'"; fi
email_case 2 success "$M_GITDATA"
if [[ "$SUBJ" == "[HEARTBEAT] Better Stack heartbeat live-reconcile mismatch" ]]; then pass "E4 default mismatch subject unchanged"
else fail "E4 expected the existing [HEARTBEAT] subject, got '$SUBJ'"; fi
email_case 2 success "$M_FORGED"
if [[ "$SUBJ" == "[INFRA-DRIFT] Better Stack object live but unmanaged by Terraform" ]]; then pass "E5 (H2) a quoted 'reason=/route=monitor-config-drift' in a vendor name does not raise the subject"
else fail "E5 vendor text must not select the subject, got '$SUBJ'"; fi
email_case 1 failure "$M_ERROR" "$M_GITDATA"
if [[ "$SUBJ" == "[ERROR]"* && "$SUBJ" == *"issue filer failed"* ]]; then pass "E6 rc=1 + failed filer -> [ERROR] subject naming the issue filer failure"
else fail "E6 expected an [ERROR] subject that says 'issue filer failed', got '$SUBJ'"; fi
email_case 2 failure "$M_UNMANAGED_9"
if [[ "$SUBJ" == "[ERROR]"* && "$SUBJ" == *"issue filer failed"* ]]; then pass "E7 rc=2 + failed filer -> [ERROR] subject naming the issue filer failure"
else fail "E7 a failed filer is an error the subject must name, got '$SUBJ'"; fi
email_case 2 cancelled "$M_UNMANAGED_9"
if [[ "$SUBJ" == "[ERROR]"* && "$SUBJ" == *"issue filer failed"* ]]; then pass "E7b rc=2 + CANCELLED filer -> [ERROR] subject naming the issue filer failure"
else fail "E7b a cancelled filer is a filer failure the subject must name, got '$SUBJ'"; fi

MAIL="$_E2_MAIL"
_ul=$(grep -n '<li>' <<<"$MAIL" | head -1 | cut -d: -f1)
_pre=$(grep -n '<pre>' <<<"$MAIL" | head -1 | cut -d: -f1)
_li=$(grep -o '<li>' <<<"$MAIL" | grep -c .) || _li=0
if [[ -n "$_ul" && -n "$_pre" ]] && (( _ul < _pre )) && [[ "$_li" == "3" ]]; then
  pass "E8 one plain sentence per class (3 classes -> 3 items) above the raw markers"
else
  fail "E8 expected 3 class sentences before the <pre> markers block (items=$_li, first <li> line=${_ul:-none}, <pre> line=${_pre:-none})"
fi
email_case 2 success 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=3 route=unmanaged-live~id.3 url="u" name="<b>x</b> EOFBODY"'
_d1="$DELIM"
if [[ "$_d1" =~ ^EOF_[0-9a-f]{16}$ ]] && grep -qF '&lt;b&gt;x&lt;/b&gt; EOFBODY' <<<"$MAIL"; then
  pass "E9 random EOF_<16 hex> delimiter; vendor HTML is escaped and a literal EOFBODY survives inside the body"
else
  fail "E9 expected a delimiter matching EOF_[0-9a-f]{16} and escaped vendor text (delimiter='$_d1')"
fi
email_case 2 success "$M_GITDATA"
if [[ -n "$DELIM" && "$DELIM" != "$_d1" ]]; then pass "E10 the delimiter differs between runs"
else fail "E10 the heredoc delimiter must be random per run (run1='$_d1' run2='$DELIM')"; fi

# ---------------------------------------------------------------------------
echo "P: parity with plugins/soleur/lib/heartbeat-live-reconcile.ts (reasons: $(tr '\n' ' ' <<<"$REASONS_LIST"))"
# ---------------------------------------------------------------------------
if [[ -z "$LIB_ROUTE_RE" ]]; then
  fail "P0 the lib exports no ROUTE_TOKEN_RE — the route= contract has no single source to check the workflow against"
else
  _p0=1
  for key in issue prep; do
    _lits=$(grep -oE "^[[:space:]]*ROUTE_RE='[^']*'" "$TMP/steps/$key.sh" | sed -E "s/^[[:space:]]*ROUTE_RE='(.*)'$/\1/" | sort -u)
    if [[ "$_lits" != "$LIB_ROUTE_RE" ]]; then _p0=0; echo "    $key step ROUTE_RE='${_lits}' vs lib ROUTE_TOKEN_RE=/${LIB_ROUTE_RE}/"; fi
  done
  if [[ "$_p0" == 1 ]]; then pass "P0 the issue and email-prep steps' ROUTE_RE literal equals the lib's ROUTE_TOKEN_RE source"
  else fail "P0 the workflow's route= token regex must equal the lib's ROUTE_TOKEN_RE"; fi
fi
while IFS= read -r reason; do
  line="SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=${reason} id=1 route=${reason}~id.1 detail=\"x\""
  email_case 2 success "$line"
  _li=$(grep -o '<li>' <<<"$MAIL" | grep -c .) || _li=0
  if [[ "$CASE_RC" == 0 && "$_li" == "1" ]]; then pass "P1 reason ${reason}: the email names it in exactly one plain sentence"
  else fail "P1 reason ${reason} from the lib union has no email sentence (items=$_li rc=$CASE_RC) — widen the email-prep step"; fi
  new_case "$M_KEYLESS"
  run_step issue
  _decode=$(awk '/<details>/{skip=1} !skip{print} /<\/details>/{skip=0}' "$CASE/rt/reconcile-body.md" 2>/dev/null)
  if grep -qF "reason=${reason}" <<<"$_decode"; then pass "P2 reason ${reason}: the new-issue body's decode list names it"
  else fail "P2 reason ${reason} from the lib union is missing from the issue body's decode list"; fi
  escalate_case "$line" "$line"
  _want=false
  if [[ "$reason" == "monitor-config-drift" ]]; then _want=true; fi
  esc_row P3 "$_want" "reason ${reason}: route=${reason}~id.1 parses as a key and is matched against the latest post"
done <<<"$REASONS_LIST"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
