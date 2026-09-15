#!/usr/bin/env bash
# Guard 3 (#7884 plan) — routing in the `heartbeat-live-reconcile` job of
# `.github/workflows/scheduled-terraform-drift.yml`.
#
# PROPERTY. Every MISMATCH row reaches the reconcile issue even when another arm errors,
# each new routing key re-emails exactly once, unmanaged rows add the `infra-drift` label,
# and the issue step can neither create a duplicate nor fail silently.
#
# HOW. Every step under test is EXTRACTED from the workflow with yaml.safe_load (never
# re-implemented here) and executed against stubs on PATH (`gh` logs its argv; `bun` prints a
# fixture; `doppler` prints a fake token) with temp RUNNER_TEMP / GITHUB_OUTPUT. `if:` and
# `with.status` expressions are EVALUATED by a small GitHub-expression interpreter below
# (loose `==` with number coercion, case-insensitive string compare, value-returning `&&`/`||`)
# rather than grepped, so a comment or a reordered clause cannot satisfy them.
#
# SHELL. None of these steps declares `shell:` and the workflow has no `defaults.run.shell`, so
# Actions runs them as `bash -e {0}` — WITHOUT pipefail. That is exactly why #8140 happened
# (`gh issue list … | head -1` failed, `head` exited 0, EXISTING read empty, a duplicate was
# filed). Running the extracted bodies under `-o pipefail` would make W1 pass on the defective
# body by harness choice, so they run under `bash --noprofile --norc -e`.
#
# Rows: W1-W7, keyless escalation, subject precedence, H1 (a non-logging gh stub must turn W1
# and W6 RED), H2 (vendor text with spaces, `id=`, `reason=` and backticks inside quotes never
# routes).
#
# Run: bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh
# Override the workflow under test (mutation proofs on a COPY):
#   HEARTBEAT_ISSUE_STEP_WF=/path/to/copy.yml bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
WF="${HEARTBEAT_ISSUE_STEP_WF:-$REPO_ROOT/.github/workflows/scheduled-terraform-drift.yml}"
JOB="heartbeat-live-reconcile"

# `/tmp` is a shared tmpfs and a direct invocation of this suite inherits it.
export TMPDIR="${TMPDIR:-/var/tmp}"
PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
fatal() { echo "FATAL: $1" >&2; exit 2; }

[[ -f "$WF" ]] || fatal "missing workflow $WF"
command -v python3 >/dev/null || fatal "python3 not found"
python3 -c 'import yaml' 2>/dev/null || fatal "python3 yaml module not importable"
command -v openssl >/dev/null || fatal "openssl not found (the email step mints its heredoc delimiter with it, as the runner does)"

TMP=$(mktemp -d) || fatal "sandbox"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/steps" || fatal "mkdir"

echo "=== heartbeat-live-reconcile issue-step routing (Guard 3) ==="

# ---------------------------------------------------------------------------
# EXTRACTION. job_step <selector> <path> — selector `id:<id>` or `name:<prefix>`, restricted to
# the heartbeat-live-reconcile job (the drift-check job has look-alike label/issue steps).
# exit 2 = no such step, 3 = no such field.
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

SEL_RECONCILE="id:reconcile"
SEL_LABEL="name:Ensure heartbeat-reconcile-mismatch label exists"
SEL_ISSUE="id:reconcile_issue"
SEL_PREP="id:reconcile_email"
SEL_EMAIL="name:Email notification (reconcile)"
SEL_SENTRY="name:Sentry check-in (final)"

for pair in "reconcile|$SEL_RECONCILE" "label|$SEL_LABEL" "issue|$SEL_ISSUE" "prep|$SEL_PREP"; do
  key="${pair%%|*}"; sel="${pair#*|}"
  job_step "$sel" run > "$TMP/steps/$key.sh" || fatal "could not extract run: of $sel — re-point the extractor rather than deleting the case"
  [[ -s "$TMP/steps/$key.sh" ]] || fatal "empty run: body for $sel"
done
LABEL_IF=$(job_step "$SEL_LABEL" if) || fatal "label step has no if:"
ISSUE_IF=$(job_step "$SEL_ISSUE" if) || fatal "issue step has no if:"
PREP_IF=$(job_step "$SEL_PREP" if) || fatal "email-prep step has no if:"
EMAIL_IF=$(job_step "$SEL_EMAIL" if) || fatal "email step has no if:"
SENTRY_IF=$(job_step "$SEL_SENTRY" if) || fatal "sentry step has no if:"
SENTRY_STATUS=$(job_step "$SEL_SENTRY" with.status) || fatal "sentry step has no with.status"
pass "extracted 4 run: bodies, 5 if: expressions and the Sentry status expression from job $JOB"

# ---------------------------------------------------------------------------
# GitHub expression evaluator (subset: literals, dotted context refs, ==, !=, !, &&, ||, (),
# always()/success()/failure()/cancelled()). Semantics per the Actions docs: `==` across
# different types coerces both to numbers (null -> 0, '' -> 0, non-numeric string -> NaN);
# same-type strings compare case-insensitively; `&&`/`||` return an operand. A context ref not
# in the JSON context is null. Unknown syntax exits 3 (a harness error, never a verdict).
# ---------------------------------------------------------------------------
cat > "$TMP/expr.py" <<'PYE'
import sys, json, re, math
src, ctx = sys.argv[1], json.loads(sys.argv[2])
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
FUNCS = {"always": True, "success": True, "failure": False, "cancelled": False}
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
print("true" if out is True else "false" if out is False or out is None else out if isinstance(out, str) else out)
PYE

# ev <expr> <json-ctx> -> printed value; harness error is FATAL.
ev() {
  local v
  v=$(python3 "$TMP/expr.py" "$1" "$2") || fatal "expression evaluator could not parse: $1"
  printf '%s' "$v"
}

echo "S0: instrument self-test — the evaluator reproduces documented Actions semantics"
_s0=1
[[ "$(ev "'2' == 2" '{}')" == "true" ]] || { _s0=0; echo "    '2' == 2 should coerce to true"; }
[[ "$(ev "steps.x.outputs.rc == '0'" '{}')" == "true" ]] || { _s0=0; echo "    null == '0' should coerce to 0 == 0 (the unset-output hazard)"; }
[[ "$(ev "steps.x.outputs.rc == '2'" '{}')" == "false" ]] || { _s0=0; echo "    null == '2' should be false"; }
[[ "$(ev "'' == '0'" '{}')" == "false" ]] || { _s0=0; echo "    '' == '0' (both strings) should be false"; }
[[ "$(ev "'TRUE' == 'true'" '{}')" == "true" ]] || { _s0=0; echo "    string compare should be case-insensitive"; }
[[ "$(ev "false && 'ok' || 'error'" '{}')" == "error" ]] || { _s0=0; echo "    && / || should return operands"; }
[[ "$(ev "always() && (a == '1' || b == 'x')" '{"b":"x"}')" == "true" ]] || { _s0=0; echo "    grouping/always() misparsed"; }
if python3 "$TMP/expr.py" "a === b" '{}' >/dev/null 2>&1; then _s0=0; echo "    unknown syntax must be a harness error, not a verdict"; fi
if [[ "$_s0" == 1 ]]; then pass "evaluator self-test"; else fail "evaluator self-test — every expression verdict below would be untrustworthy"; fi

# ---------------------------------------------------------------------------
# STUBS
# ---------------------------------------------------------------------------
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${GH_STUB_MODE:-log}" != "nolog" && "${GH_STUB_FORCE_NOLOG:-}" != "1" ]]; then
  { printf 'gh'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$GH_LOG"
fi
case "${1:-} ${2:-}" in
  "issue list")
    if [[ "${GH_LIST_RC:-0}" != "0" ]]; then echo "stub: gh issue list failed (HTTP 502)" >&2; exit "$GH_LIST_RC"; fi
    [[ -n "${GH_LIST_OUT:-}" ]] && printf '%s\n' "$GH_LIST_OUT"
    exit 0 ;;
  "issue view")
    cat "$GH_VIEW_FILE"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
cat > "$TMP/bin/doppler" <<'STUB'
#!/usr/bin/env bash
printf 'stub-not-a-credential'
STUB
cat > "$TMP/bin/bun" <<'STUB'
#!/usr/bin/env bash
cat "$BUN_FIXTURE"
exit "${BUN_RC:-0}"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/doppler" "$TMP/bin/bun" || fatal "chmod stubs"

CASE_N=0
# new_case <marker lines...> — fresh RUNNER_TEMP/GITHUB_OUTPUT/gh log; fixture = the args, one per line.
new_case() {
  CASE_N=$((CASE_N + 1))
  CASE="$TMP/case.$CASE_N"
  mkdir -p "$CASE/rt" || fatal "mkdir case"
  : > "$CASE/out"; : > "$CASE/gh.log"; : > "$CASE/view"
  if (( $# > 0 )); then printf '%s\n' "$@" > "$CASE/rt/reconcile-output.txt"; else : > "$CASE/rt/reconcile-output.txt"; fi
}
# run_step <step-key> [VAR=val...] — execute an extracted body the way Actions does (see SHELL above).
run_step() {
  local key="$1"; shift
  CASE_RC=0
  env -u BASH_ENV \
    PATH="$TMP/bin:$PATH" RUNNER_TEMP="$CASE/rt" GITHUB_OUTPUT="$CASE/out" \
    GH_LOG="$CASE/gh.log" GH_VIEW_FILE="$CASE/view" GH_TOKEN=stub \
    RUN_NUMBER=7 SERVER_URL=https://github.com REPOSITORY=o/r RUN_ID=99 \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=99 \
    DOPPLER_TOKEN=stub DOPPLER_PROJECT=soleur DOPPLER_CONFIG=prd_terraform \
    BUN_FIXTURE="$CASE/rt/reconcile-output.txt.fixture" \
    "$@" bash --noprofile --norc -e "$TMP/steps/$key.sh" > "$CASE/stdout" 2>&1 || CASE_RC=$?
}
out_val() { sed -n "s/^$1=//p" "$CASE/out" | tail -1; }
logged() { grep -qE "$1" "$CASE/gh.log"; }

# Marker fixtures (the reconcile script's grammar: routing tokens before the first `"`).
M_GITDATA='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-git-data-prd live=absent reason=absent-live resource=betteruptime_heartbeat.git_data_prd'
M_GITDATA_SHORT='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-git-data live=absent reason=absent-live resource=betteruptime_heartbeat.git_data'
M_UNMANAGED_9='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=9 url="https://example.soleur.ai/" name="example"'
M_DRIFT='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=4226366 resource=betteruptime_monitor.app_health field=monitor_type detail="declared=keyword live=status"'
M_ABSENT_MON='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=absent-live resource=betteruptime_monitor.app_health url="https://app.soleur.ai/health"'
M_KEYLESS='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-legacy live=paused reason=fed-but-paused'
M_ERROR='SOLEUR_HEARTBEAT_RECONCILE_ERROR surface=heartbeats reason=unauthorized detail="401"'
M_OK='SOLEUR_HEARTBEAT_RECONCILE_OK surface=monitors declared=4 live=4 matched=4226366,4422675'
# H2: vendor name carrying spaces, forged routing tokens and a backtick fence inside quotes.
M_FORGED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=7 url="https://x.soleur.ai/" name="evil id=1 resource=betteruptime_monitor.app_health ``` reason=monitor-config-drift"'
M_DRIFT_FORGED='SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=monitor-config-drift id=4226366 resource=betteruptime_monitor.app_health field=required_keyword detail="declared=a live=b reason=unmanaged-live"'

# ---------------------------------------------------------------------------
echo "R: the reconcile step publishes has_mismatch from line-anchored MISMATCH markers"
# ---------------------------------------------------------------------------
new_case "$M_ERROR" "$M_GITDATA"; cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture"
run_step reconcile BUN_RC=1
if [[ "$(out_val rc)" == "1" && "$(out_val has_mismatch)" == "true" ]]; then
  pass "R1 rc=1 with a MISMATCH row publishes rc=1 has_mismatch=true"
else
  fail "R1 an ERROR arm plus a MISMATCH row must publish rc=1 AND has_mismatch=true (got rc='$(out_val rc)' has_mismatch='$(out_val has_mismatch)') — without it the rc=1 run hides the mismatch from the issue"
fi
new_case "$M_OK"; cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture"
run_step reconcile BUN_RC=0
if [[ "$(out_val has_mismatch)" == "false" ]]; then pass "R2 OK-only output publishes has_mismatch=false"
else fail "R2 OK-only output must publish has_mismatch=false (got '$(out_val has_mismatch)')"; fi
new_case 'SOLEUR_HEARTBEAT_RECONCILE_ERROR reason=uncaught detail=boom SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=x'
cp "$CASE/rt/reconcile-output.txt" "$CASE/rt/reconcile-output.txt.fixture"
run_step reconcile BUN_RC=1
if [[ "$(out_val has_mismatch)" == "false" ]]; then pass "R3 a MISMATCH spelling mid-line (inside an ERROR detail) does not set has_mismatch"
else fail "R3 has_mismatch must be anchored at line start (got '$(out_val has_mismatch)')"; fi

# ---------------------------------------------------------------------------
echo "W1: a failing 'gh issue list' fails the step and files nothing"
# ---------------------------------------------------------------------------
check_w1() {
  [[ "$CASE_RC" != "0" ]] && logged '^gh issue list ' && ! logged '^gh issue (create|comment) '
}
new_case "$M_GITDATA"
run_step issue GH_LIST_RC=1
if check_w1; then pass "W1 lookup failure -> step rc=$CASE_RC, lookup logged, no create/comment"
else fail "W1 a failing gh issue list must fail the step with no issue create/comment (step rc=$CASE_RC; gh log: $(tr '\n' '|' < "$CASE/gh.log")) — the #8140 duplicate"; fi

# ---------------------------------------------------------------------------
# escalate_case <history-file-content> <marker lines...> -> runs the existing-issue path.
escalate_case() {
  local hist="$1"; shift
  new_case "$@"
  printf '%s' "$hist" > "$CASE/view"
  run_step issue GH_LIST_OUT=6645
}
echo "W2-W5 + keyless: escalation keys are whole resource=/id= tokens from the pre-quote prefix"
escalate_case "$M_GITDATA" "$M_GITDATA_SHORT"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "W2 resource=…git_data is new although history has …git_data_prd -> escalate=true"
else fail "W2 a key that is a PREFIX of a recorded key must escalate (rc=$CASE_RC escalate='$(out_val escalate)') — substring matching hides a new row"; fi

escalate_case "$(printf 'old line\n%s' "$M_GITDATA")" "$M_GITDATA"
_a=$(out_val escalate); _arc=$CASE_RC
escalate_case "$(printf '%s\ntrailing prose' "$M_GITDATA")" "$M_GITDATA"
if [[ "$_arc" == 0 && "$_a" == "false" && "$CASE_RC" == 0 && "$(out_val escalate)" == "false" ]]; then
  pass "W3 a key recorded at end of text / end of line -> escalate=false"
else
  fail "W3 a recorded key at end of text or end of line must NOT escalate (end-of-text: rc=$_arc escalate='$_a'; end-of-line: rc=$CASE_RC escalate='$(out_val escalate)')"
fi

escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=94 url="u" name="n"' "$M_UNMANAGED_9"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "W4 current id=9 vs history id=94 -> escalate=true"
else fail "W4 id=9 must not match a recorded id=94 (rc=$CASE_RC escalate='$(out_val escalate)')"; fi

escalate_case "$M_GITDATA" "$M_GITDATA" "$M_UNMANAGED_9"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "W5 a new key after a known key in the same run -> escalate=true"
else fail "W5 the second, new key must escalate even though the first key is known (rc=$CASE_RC escalate='$(out_val escalate)')"; fi

escalate_case "$M_KEYLESS" "$M_KEYLESS"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "K1 a MISMATCH row with no resource=/id= key escalates (fail safe), even if its text is already recorded"
else fail "K1 a keyless MISMATCH row must escalate (rc=$CASE_RC escalate='$(out_val escalate)')"; fi

escalate_case "$M_GITDATA" "$M_GITDATA"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "false" && "$(out_val created)" == "false" ]] && logged '^gh issue comment 6645 ' && ! logged '^gh issue create '; then
  pass "K2 must-pass: every key already recorded -> comment on #6645, escalate=false, no create"
else
  fail "K2 a fully-recorded run must comment on the open issue without escalating (rc=$CASE_RC escalate='$(out_val escalate)' created='$(out_val created)'; gh log: $(tr '\n' '|' < "$CASE/gh.log"))"
fi

# ---------------------------------------------------------------------------
echo "W6: unmanaged rows route to infra-drift"
# ---------------------------------------------------------------------------
check_w6_existing() { [[ "$CASE_RC" == 0 ]] && logged '^gh issue edit 6645 --add-label infra-drift$'; }
check_w6_new() {
  [[ "$CASE_RC" == 0 ]] && logged '^gh issue create .*--label heartbeat-reconcile-mismatch( |$)' \
    && logged '^gh issue create .*--label infra-drift( |$)' && logged '^gh issue create .*--milestone '
}
escalate_case "$M_GITDATA" "$M_GITDATA" "$M_UNMANAGED_9"
if check_w6_existing; then pass "W6a existing issue + unmanaged-live row -> gh issue edit 6645 --add-label infra-drift"
else fail "W6a an unmanaged-live row on an open issue must add the infra-drift label (rc=$CASE_RC; gh log: $(tr '\n' '|' < "$CASE/gh.log"))"; fi
new_case "$M_UNMANAGED_9"
run_step issue
if check_w6_new && [[ "$(out_val created)" == "true" ]]; then pass "W6b no open issue + unmanaged-live row -> create carries both labels and a milestone"
else fail "W6b a new issue for an unmanaged-live row must be created with heartbeat-reconcile-mismatch AND infra-drift labels and a milestone (rc=$CASE_RC; gh log: $(tr '\n' '|' < "$CASE/gh.log"))"; fi
new_case "$M_GITDATA"
run_step issue
if [[ "$CASE_RC" == 0 ]] && logged '^gh issue create .*--label heartbeat-reconcile-mismatch' && ! logged 'infra-drift'; then
  pass "W6c must-pass: no unmanaged row -> create without infra-drift"
else
  fail "W6c a run with no unmanaged-live row must not apply infra-drift (rc=$CASE_RC; gh log: $(tr '\n' '|' < "$CASE/gh.log"))"
fi
new_case "$M_UNMANAGED_9"
run_step label
if logged '^gh label create infra-drift ' && logged '^gh label create heartbeat-reconcile-mismatch '; then
  pass "W6d the label step ensures both heartbeat-reconcile-mismatch and infra-drift exist"
else
  fail "W6d the label step must ensure infra-drift exists as well (gh log: $(tr '\n' '|' < "$CASE/gh.log"))"
fi
new_case "$M_UNMANAGED_9"
run_step issue
BODY="$CASE/rt/reconcile-body.md"
if [[ -f "$BODY" ]] && grep -qi 'untrusted vendor data' "$BODY" && grep -qF '/soleur:one-shot' "$BODY" \
   && grep -qF 'import {}' "$BODY" && grep -qF 'monitor-config-drift' "$BODY" && grep -qF 'unmanaged-live' "$BODY"; then
  pass "W6e the new-issue body frames markers as untrusted vendor data and decodes/remediates unmanaged-live and monitor-config-drift"
else
  fail "W6e the issue body (written under RUNNER_TEMP) must frame the markers as untrusted vendor data, decode unmanaged-live and monitor-config-drift, and give the /soleur:one-shot import {} adoption path"
fi

# ---------------------------------------------------------------------------
echo "H2: vendor text inside quotes never routes"
# ---------------------------------------------------------------------------
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=1 resource=betteruptime_monitor.app_health' "$M_FORGED"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "H2a quoted 'id=1 resource=…' in a vendor name is not a key: real id=7 is new -> escalate=true"
else fail "H2a a forged id=/resource= inside a quoted vendor name must not be used as a routing key (rc=$CASE_RC escalate='$(out_val escalate)')"; fi
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=7 url="u" name="n"' "$M_FORGED"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "false" ]]; then pass "H2b must-pass: the real pre-quote id=7 is the key -> recorded -> escalate=false"
else fail "H2b the pre-quote id=7 must be the routing key (rc=$CASE_RC escalate='$(out_val escalate)')"; fi
escalate_case 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=8 url="u" name="old id=7"' "$M_FORGED"
if [[ "$CASE_RC" == 0 && "$(out_val escalate)" == "true" ]]; then pass "H2c a key that appears only inside quotes in the HISTORY does not count as recorded -> escalate=true"
else fail "H2c vendor text echoed into history must not pre-register a key (rc=$CASE_RC escalate='$(out_val escalate)')"; fi
escalate_case "$M_DRIFT_FORGED" "$M_DRIFT_FORGED"
if [[ "$CASE_RC" == 0 ]] && ! logged 'infra-drift'; then pass "H2d 'reason=unmanaged-live' inside a quoted detail does not add infra-drift"
else fail "H2d a quoted reason=unmanaged-live must not route to infra-drift (rc=$CASE_RC; gh log: $(tr '\n' '|' < "$CASE/gh.log"))"; fi
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
echo "H1: a gh stub that logs nothing must turn W1 and W6 RED (the checks are not vacuous)"
# ---------------------------------------------------------------------------
new_case "$M_GITDATA"
run_step issue GH_LIST_RC=1 GH_STUB_MODE=nolog
if check_w1; then fail "H1 W1's check passed with a non-logging gh stub — it asserts nothing"; else pass "H1 W1 goes RED under a non-logging gh stub"; fi
new_case "$M_GITDATA" "$M_UNMANAGED_9"
printf '%s' "$M_GITDATA" > "$CASE/view"
run_step issue GH_LIST_OUT=6645 GH_STUB_MODE=nolog
if check_w6_existing; then fail "H1 W6a's check passed with a non-logging gh stub"; else pass "H1 W6a goes RED under a non-logging gh stub"; fi
new_case "$M_UNMANAGED_9"
run_step issue GH_STUB_MODE=nolog
if check_w6_new; then fail "H1 W6b's check passed with a non-logging gh stub"; else pass "H1 W6b goes RED under a non-logging gh stub"; fi

# ---------------------------------------------------------------------------
echo "W7: evaluated if: / status expressions"
# ---------------------------------------------------------------------------
# w7_row <label> <expr> <ctx-json> <expected>
w7_row() {
  local got; got=$(ev "$2" "$3")
  if [[ "$got" == "$4" ]]; then pass "W7 $1 -> $4"
  else fail "W7 $1: expected '$4', got '$got' (expr: $(tr -s ' \n' ' ' <<<"$2"); ctx: $3)"; fi
}
for pair in "label|$LABEL_IF" "issue|$ISSUE_IF"; do
  n="${pair%%|*}"; e="${pair#*|}"
  w7_row "$n if: rc=2" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile.outputs.has_mismatch":"true"}' true
  w7_row "$n if: rc=1 has_mismatch=true" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile.outputs.has_mismatch":"true"}' true
  w7_row "$n if: rc=1 has_mismatch=false" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile.outputs.has_mismatch":"false"}' false
  w7_row "$n if: rc=1 has_mismatch unset" "$e" '{"steps.reconcile.outputs.rc":"1"}' false
  w7_row "$n if: rc=0" "$e" '{"steps.reconcile.outputs.rc":"0","steps.reconcile.outputs.has_mismatch":"false"}' false
  w7_row "$n if: rc unset" "$e" '{}' false
done
for pair in "email-prep|$PREP_IF" "email|$EMAIL_IF"; do
  n="${pair%%|*}"; e="${pair#*|}"
  w7_row "$n if: rc=2, known rows, filer failed" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"failure"}' true
  w7_row "$n if: rc=2, known rows, filer ok" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"false","steps.reconcile_issue.outputs.escalate":"false"}' false
  w7_row "$n if: rc=2 escalate=true" "$e" '{"steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success","steps.reconcile_issue.outputs.created":"false","steps.reconcile_issue.outputs.escalate":"true"}' true
  w7_row "$n if: rc=1" "$e" '{"steps.reconcile.outputs.rc":"1","steps.reconcile_issue.outcome":"skipped"}' true
  w7_row "$n if: rc=0 filer skipped" "$e" '{"steps.reconcile.outputs.rc":"0","steps.reconcile_issue.outcome":"skipped"}' false
done
w7_row "sentry if: always runs" "$SENTRY_IF" '{"steps.reconcile_issue.outcome":"failure"}' true
w7_row "sentry status: rc=2 filer failed" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"failure"}' error
w7_row "sentry status: rc=2 filer ok" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"2","steps.reconcile_issue.outcome":"success"}' ok
w7_row "sentry status: rc=0 filer skipped" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"0","steps.reconcile_issue.outcome":"skipped"}' ok
w7_row "sentry status: rc=1" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"success","steps.reconcile.outputs.rc":"1","steps.reconcile_issue.outcome":"success"}' error
w7_row "sentry status: reconcile step failed before writing rc (null == '0' hazard)" "$SENTRY_STATUS" '{"steps.reconcile.outcome":"failure","steps.reconcile_issue.outcome":"skipped"}' error

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
email_case 1 success "$M_ERROR" "$M_DRIFT" "$M_UNMANAGED_9"
if [[ "$CASE_RC" == 0 && "$SUBJ" == "[ERROR] Better Stack heartbeat live-reconcile failed" ]]; then pass "E1 rc=1 outranks config drift and unmanaged rows -> existing [ERROR] subject"
else fail "E1 rc=1 must keep the existing [ERROR] subject (rc=$CASE_RC subject='$SUBJ')"; fi
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
if [[ "$SUBJ" == "[INFRA-DRIFT] Better Stack object live but unmanaged by Terraform" ]]; then pass "E5 (H2) a quoted 'reason=monitor-config-drift' in a vendor name does not raise the subject"
else fail "E5 vendor text must not select the subject, got '$SUBJ'"; fi
email_case 1 failure "$M_ERROR" "$M_GITDATA"
if [[ "$SUBJ" == "[ERROR]"* && "$SUBJ" == *"issue filer failed"* ]]; then pass "E6 rc=1 + failed filer -> [ERROR] subject naming the issue filer failure"
else fail "E6 expected an [ERROR] subject that says 'issue filer failed', got '$SUBJ'"; fi
email_case 2 failure "$M_UNMANAGED_9"
if [[ "$SUBJ" == "[ERROR]"* && "$SUBJ" == *"issue filer failed"* ]]; then pass "E7 rc=2 + failed filer -> [ERROR] subject naming the issue filer failure"
else fail "E7 a failed filer is an error the subject must name, got '$SUBJ'"; fi

MAIL="$_E2_MAIL"
_ul=$(grep -n '<li>' <<<"$MAIL" | head -1 | cut -d: -f1)
_pre=$(grep -n '<pre>' <<<"$MAIL" | head -1 | cut -d: -f1)
_li=$(grep -o '<li>' <<<"$MAIL" | grep -c .) || _li=0
if [[ -n "$_ul" && -n "$_pre" ]] && (( _ul < _pre )) && [[ "$_li" == "3" ]]; then
  pass "E8 one plain sentence per class (3 classes -> 3 items) above the raw markers"
else
  fail "E8 expected 3 class sentences before the <pre> markers block (items=$_li, first <li> line=${_ul:-none}, <pre> line=${_pre:-none})"
fi
email_case 2 success 'SOLEUR_HEARTBEAT_RECONCILE_MISMATCH surface=monitors reason=unmanaged-live id=3 url="u" name="<b>x</b> EOFBODY"'
_d1="$DELIM"
if [[ "$_d1" =~ ^EOF_[0-9a-f]{16}$ ]] && grep -qF '&lt;b&gt;x&lt;/b&gt; EOFBODY' <<<"$MAIL"; then
  pass "E9 random EOF_<16 hex> delimiter; vendor HTML is escaped and a literal EOFBODY survives inside the body"
else
  fail "E9 expected a delimiter matching EOF_[0-9a-f]{16} and escaped vendor text (delimiter='$_d1')"
fi
email_case 2 success "$M_GITDATA"
if [[ -n "$DELIM" && "$DELIM" != "$_d1" ]]; then pass "E10 the delimiter differs between runs"
else fail "E10 the heredoc delimiter must be random per run (run1='$_d1' run2='$DELIM')"; fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR at the REALIZED count: deleting assertions must show up as a diff here.
if [[ "$((PASS + FAIL))" -lt 63 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 63." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
