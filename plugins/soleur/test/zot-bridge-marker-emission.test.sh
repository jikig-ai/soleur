#!/usr/bin/env bash
# Emission-site test for the SOLEUR_ZOT_BRIDGE marker (#12937, plan Phase 2.3/2.4).
#
# PROPERTY. Every bridge failure prints exactly ONE closed-grammar line
#   SOLEUR_ZOT_BRIDGE stage=<setup|listener|login|push> verdict=<v> cause=<c> host=<h> rc=<n> runbook=<path>
# from the library's single emitter (zot_bridge_marker in scripts/zot-mirror-diagnosis.sh):
#   - .github/actions/cf-tunnel-registry-bridge/action.yml first step              -> ZOT_BRIDGE_STAGE=setup
#   - the same action, as the listener / login stage starts                        -> stage=listener / login
#   - the same action, listener never bound                                        -> stage=listener
#   - the same action, docker login failed, hung, or its ZOT_PUSH_* read was empty -> stage=login
#   - .github/workflows/reusable-release.yml mirror step, bridge outcome failure    -> the action's stage
#   - the same step, crane copy / the verify read / a bridge-refused cosign sign    -> stage=push
# Each printed line is also emitted as `::notice title=SOLEUR_ZOT_BRIDGE::<line>` so the
# check-runs annotations API carries it, and the release path hands the SAME line, re-validated,
# to the notify-ops email as the step output `bridge_marker`. A success path prints none. A
# hostile value riding in from a step output (CR/LF, `::`) cannot forge a second line, an
# annotation or a second output key. A hung bridged call is bounded by its own `timeout`, and a
# mirror step killed before it reported leaves `mirror_reason=killed` for the email.
#
# HOW. Steps are selected with PyYAML (never sliced by delimiter) and their `run:` bodies are
# executed under `bash --noprofile --norc -eo pipefail` — the runner's own invocation for a
# `shell: bash` step and for a workflow `run:` with no `shell:` key — with every external
# command stubbed on PATH. Each step's `env:` is DERIVED from the YAML: its `${{ }}` expressions
# are evaluated against a synthetic context (the preflight's outputs, the bridge outcome), and the
# action's `inputs.*` come from reusable-release's `with:` plus the action's declared defaults. So
# deleting a mapping anywhere on that chain changes what the body sees. Earlier steps' GITHUB_ENV
# files are chained the way the runner does. Nothing here touches the network. Every credential is
# synthesized (cq-test-fixtures-synthesized-only).
#
# MUTATION MATRIX — run against pristine copies, restored after each row; every row RED:
#   1  drop the zot_bridge_marker call in the listener branch        RED  L1, L2
#   2  drop it in the login branch                                   RED  G1, G2
#   3  `if ! docker login` again (rc lost)                           RED  G1 (rc=invalid / branch shape)
#   4  drop emit_bridge_marker from degraded()                       RED  R1, R2, P1
#   5  write the marker to GITHUB_OUTPUT without zot_bridge_marker_valid  RED  R4
#   6  the email body loses the bridge_marker expression             RED  E1
#   7  every row below skipped                                       RED  the row floor
#   8  setup write dropped (S1); `*) stage=push` in the emitter (R3, N1); listener/login stage
#      writes mislabelled (G4, R3c, L1, G1, R1); verify arm dropped (V1) or widened (V2); step
#      timeouts dropped (T1); host not published on success (L4)
#   9  TOKEN_CAUSE dropped from the listener / login / mirror env, or `token-cause:` from the
#      caller's `with:`                                              RED  D1, L1, G1, R1
#  10  stage written only on failure again (R3d, G3, L4); a per-call `timeout` dropped (T2, H1, H2);
#      the top-of-step `mirror_reason=killed` dropped (K1) or not cleared on success (K2); the
#      email fallback reverted (E3); the sign bridge-error arm dropped (SG1) or unconditional (SG2);
#      the mirror ::notice moved above zot_bridge_marker_valid (I1)
#
# Run: bash plugins/soleur/test/zot-bridge-marker-emission.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
ACTION="$REPO_ROOT/.github/actions/cf-tunnel-registry-bridge/action.yml"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"
LIB="$REPO_ROOT/scripts/zot-mirror-diagnosis.sh"
RUNBOOK="knowledge-base/engineering/operations/runbooks/zot-registry-revert.md"
BRIDGE_STEP="Bridge to zot registry (CF Tunnel)"
MIRROR_STEP="Mirror image GHCR→zot (crane) + cosign-sign the zot digest"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing; this suite asserted nothing"; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML missing; this suite asserted nothing"; exit 1; }
REAL_TIMEOUT="$(type -P timeout)"; REAL_SLEEP="$(type -P sleep)"
[[ -n "$REAL_TIMEOUT" && -n "$REAL_SLEEP" ]] || { echo "FAIL: coreutils timeout/sleep missing; this suite asserted nothing"; exit 1; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP=$(mktemp -d -t zot-bridge-marker.XXXXXXXX) || { echo "FATAL: cannot create scratch dir" >&2; exit 2; }
[[ -n "$TMP" && "$TMP" == /* && -d "$TMP" ]] || { echo "FATAL: bad scratch dir" >&2; exit 2; }
trap 'rm -rf -- "$TMP"' EXIT

PASS=0
FAIL=0
ROWS=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "1" ]]; then pass "$1"; else fail "$1"; fi; }

# Instrument self-test: a true and a false verdict must each move their own counter. Its voice is
# printf + exit, never the helpers it checks.
_sp=$PASS; _sf=$FAIL
check "instrument self-test (pass path)" 1 >/dev/null
check "instrument self-test (fail path)" 0 >/dev/null
if (( PASS != _sp + 1 || FAIL != _sf + 1 )); then
  printf 'FATAL: the assertion helpers do not count (pass %d->%d, fail %d->%d); every verdict below would be void.\n' "$_sp" "$PASS" "$_sf" "$FAIL" >&2
  exit 2
fi
PASS=$_sp; FAIL=$_sf

# step_run <file> <selector> — print the run: body of the first step whose name starts with
# <selector>, across composite `runs.steps` and workflow `jobs.*.steps`. Exit 2 if absent.
step_run() {
  python3 -I - "$1" "$2" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
want = sys.argv[2]
steps = list((doc.get("runs") or {}).get("steps") or [])
for job in (doc.get("jobs") or {}).values():
    steps += job.get("steps") or []
for st in steps:
    if str(st.get("name", "")).startswith(want) and "run" in st:
        sys.stdout.write(st["run"])
        raise SystemExit(0)
raise SystemExit(2)
PY
}
step_field() { # <file> <selector> <with-key>
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
want, key = sys.argv[2], sys.argv[3]
for job in (doc.get("jobs") or {}).values():
    for st in job.get("steps") or []:
        if str(st.get("name", "")).startswith(want):
            sys.stdout.write(str((st.get("with") or {}).get(key, "")))
            raise SystemExit(0)
raise SystemExit(2)
PY
}

# A GitHub expression evaluator for the subset these files use (paths, '…' literals, ==, !=, !,
# &&, ||, parentheses) and the env derivation built on it.
#   derive.py env    <file> <step> <ctx-json>                        workflow step env
#   derive.py action <action> <step> <ctx-json> <wf> <caller-step>   composite step env, inputs
#                                                                   from the caller's with: + defaults
#   derive.py expr   <expression> <ctx-json>                         one ${{ }} body
#   derive.py keys   <file> <step>                                   the step's env keys
# env/action print NUL-separated KEY=VALUE records (a value may carry a newline on purpose).
DERIVE="$TMP/derive.py"
cat > "$DERIVE" <<'PY'
import json, re, sys, yaml
TOK = re.compile(r"(\|\||&&|==|!=|!|\(|\))|'((?:[^']|'')*)'|([A-Za-z_][A-Za-z0-9_.\-]*)")
def tokenize(e):
    out, i = [], 0
    while i < len(e):
        if e[i].isspace():
            i += 1; continue
        m = TOK.match(e, i)
        if not m:
            raise SystemExit("untokenizable expression %r at %d" % (e, i))
        if m.group(1): out.append(("op", m.group(1)))
        elif m.group(2) is not None: out.append(("str", m.group(2).replace("''", "'")))
        else: out.append(("id", m.group(3)))
        i = m.end()
    return out
def parse(toks):
    pos = [0]
    peek = lambda: toks[pos[0]] if pos[0] < len(toks) else (None, None)
    def nxt():
        t = peek(); pos[0] += 1; return t
    def p_or():
        l = p_and()
        while peek() == ("op", "||"): nxt(); l = ("or", l, p_and())
        return l
    def p_and():
        l = p_eq()
        while peek() == ("op", "&&"): nxt(); l = ("and", l, p_eq())
        return l
    def p_eq():
        l = p_un()
        while peek() in (("op", "=="), ("op", "!=")): l = (nxt()[1], l, p_un())
        return l
    def p_un():
        k, v = nxt()
        if (k, v) == ("op", "!"): return ("not", p_un())
        if (k, v) == ("op", "("):
            e = p_or()
            if nxt() != ("op", ")"): raise SystemExit("unbalanced expression")
            return e
        if k == "str": return ("lit", v)
        if k == "id": return ("lit", v == "true") if v in ("true", "false") else ("path", v)
        raise SystemExit("bad expression token %r" % (v,))
    e = p_or()
    if pos[0] != len(toks): raise SystemExit("trailing expression tokens")
    return e
truthy = lambda v: v not in (None, "", False)
def ev(n, ctx):
    t = n[0]
    if t == "lit": return n[1]
    if t == "path":
        cur = ctx
        for part in n[1].split("."):
            if not isinstance(cur, dict) or part not in cur: return ""
            cur = cur[part]
        return cur
    if t == "or":
        l = ev(n[1], ctx); return l if truthy(l) else ev(n[2], ctx)
    if t == "and":
        l = ev(n[1], ctx); return ev(n[2], ctx) if truthy(l) else l
    if t == "not": return not truthy(ev(n[1], ctx))
    l, r = str(ev(n[1], ctx)).lower(), str(ev(n[2], ctx)).lower()
    return (l == r) if t == "==" else (l != r)
def render(val, ctx):
    def sub(m):
        v = ev(parse(tokenize(m.group(1))), ctx)
        return {True: "true", False: "false", None: ""}.get(v, v) if isinstance(v, (bool, type(None))) else str(v)
    return re.sub(r"\$\{\{(.*?)\}\}", sub, str(val), flags=re.S)
def steps_of(doc):
    st = list((doc.get("runs") or {}).get("steps") or [])
    for job in (doc.get("jobs") or {}).values(): st += job.get("steps") or []
    return st
def step(path, want):
    for st in steps_of(yaml.safe_load(open(path))):
        if str(st.get("name", "")).startswith(want): return st
    raise SystemExit("step not found: %s" % want)
def emit(env, ctx):
    sys.stdout.write("".join("%s=%s\0" % (k, render(v, ctx)) for k, v in (env or {}).items()))
mode = sys.argv[1]
if mode == "env":
    emit(step(sys.argv[2], sys.argv[3]).get("env"), json.loads(sys.argv[4]))
elif mode == "action":
    ctx = json.loads(sys.argv[4])
    decl = (yaml.safe_load(open(sys.argv[2])).get("inputs") or {})
    inputs = {k: str((v or {}).get("default", "")) for k, v in decl.items()}
    for k, v in (step(sys.argv[5], sys.argv[6]).get("with") or {}).items():
        inputs[k] = render(v, ctx)   # an explicitly passed empty string does NOT fall back to the default
    emit(step(sys.argv[2], sys.argv[3]).get("env"), {"inputs": inputs})
elif mode == "expr":
    v = ev(parse(tokenize(sys.argv[2])), json.loads(sys.argv[3]))
    sys.stdout.write("" if v is None else str(v))
elif mode == "keys":
    sys.stdout.write("\n".join(sorted((step(sys.argv[2], sys.argv[3]).get("env") or {}).keys())))
PY

# ctx <verdict> <cause> <checked_at> <bridge_outcome> — the workflow context the derivation reads.
ctx() {
  python3 -I -c '
import json, sys
v, c, t, b = sys.argv[1:5]
print(json.dumps({
  "inputs": {"docker_image": "ghcr.io/jikig-ai/soleur-web-platform", "allow_unmirrored_reason": ""},
  "github": {"sha": "abc123def", "event_name": "push"},
  "secrets": {},
  "steps": {
    "token_preflight": {"outputs": {"verdict": v, "cause": c, "checked_at": t}},
    "docker_build": {"outcome": "success", "outputs": {"digest": "sha256:deadbeef"}},
    "version": {"outputs": {"next": "1.2.3"}},
    "zot_bridge": {"outcome": b}}}))' "$@"
}
DERIVED=()
# derive_action <step> <ctx-json> / derive_mirror <ctx-json> — fill DERIVED from the YAML.
derive_action() {
  DERIVED=()
  python3 -I "$DERIVE" action "$ACTION" "$1" "$2" "$WF" "$BRIDGE_STEP" > "$TMP/derived" || { echo "FATAL: env derivation failed for $1" >&2; exit 2; }
  mapfile -d '' -t DERIVED < "$TMP/derived"
}
derive_mirror() {
  DERIVED=()
  python3 -I "$DERIVE" env "$WF" "$MIRROR_STEP" "$1" > "$TMP/derived" || { echo "FATAL: env derivation failed for the mirror step" >&2; exit 2; }
  mapfile -d '' -t DERIVED < "$TMP/derived"
}

BRIDGE_BODY="$TMP/bridge.sh";  step_run "$ACTION" "Start cloudflared registry bridge" > "$BRIDGE_BODY" || { echo "FATAL: bridge step not found" >&2; exit 2; }
LOGIN_BODY="$TMP/login.sh";    step_run "$ACTION" "Docker login to zot" > "$LOGIN_BODY" || { echo "FATAL: login step not found" >&2; exit 2; }
MIRROR_BODY="$TMP/mirror.sh";  step_run "$WF" "$MIRROR_STEP" > "$MIRROR_BODY" || { echo "FATAL: mirror step not found" >&2; exit 2; }
for f in "$BRIDGE_BODY" "$LOGIN_BODY" "$MIRROR_BODY"; do
  [[ -s "$f" ]] || { echo "FATAL: empty run body extracted ($f)" >&2; exit 2; }
done

# A sandbox GITHUB_WORKSPACE: the REAL diagnosis library, and a derive-app-domain-base stub
# (the real script reads the committed variables.tf; the base is not what is under test).
WS="$TMP/ws"; mkdir -p "$WS/scripts"
cp "$LIB" "$WS/scripts/zot-mirror-diagnosis.sh" || { echo "FATAL: copy lib" >&2; exit 2; }
printf '#!/usr/bin/env bash\nprintf "soleur.ai"\n' > "$WS/scripts/derive-app-domain-base.sh"

STUB="$TMP/bin"; mkdir -p "$STUB"
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUB/$1"; chmod +x "$STUB/$1"; }
# Synthesized values. The sentinel must never appear in any marker.
SECRET_SENTINEL="synth$((6 * 7))secretNOTREAL"
mk doppler 'case "$*" in *ACCESS_TOKEN_ID*) printf "0123456789abcdef0123456789abcdef.access";; *ACCESS_TOKEN_SECRET*|*ZOT_PUSH_TOKEN*) printf "%s" "${MOCK_SECRET}";; *ZOT_PUSH_USER*) [[ -n "${MOCK_NO_ZOT_PUSH:-}" ]] || printf "pusher";; esac'
mk cloudflared 'exit 0'
mk sleep 'exit 0'
mk nc 'exit "${MOCK_NC_RC:-1}"'
mk docker 'cat >/dev/null; [[ -z "${MOCK_DOCKER_HANG:-}" ]] || exec '"$REAL_SLEEP"' 3; exit "${MOCK_DOCKER_RC:-1}"'
# Mirror-path stubs (same shapes as reusable-release-zot-mirror-retry.test.sh).
for c in sudo tar; do mk "$c" 'exit 0'; done
mk cosign 'if [[ -n "${MOCK_COSIGN_ERR:-}" ]]; then printf "%s\n" "$MOCK_COSIGN_ERR" >&2; exit 1; fi; exit 0'
mk sha256sum 'cat >/dev/null 2>&1; exit 0'
mk curl 'exit "${MOCK_CURL_RC:-0}"'
mk crane 'case "${1:-}" in
  copy) [[ -z "${MOCK_CRANE_HANG:-}" ]] || exec '"$REAL_SLEEP"' 30; exit "${MOCK_CRANE_COPY_RC:-0}" ;;
  digest) [[ -z "${MOCK_DIGEST_HANG:-}" ]] || exec '"$REAL_SLEEP"' 30; echo "${MOCK_ZOT_DIGEST-$DIGEST}" ;;
esac
exit 0'
# The real coreutils timeout, with the bound the body asked for logged and (MOCK_BOUND) scaled
# down, so a hung call is killed for real in one second instead of minutes.
mk timeout 'printf "%s\n" "$*" >> "${MOCK_TIMEOUT_LOG:-/dev/null}"; [[ "${1:-}" != -k ]] || shift 2; b="$1"; shift; exec '"$REAL_TIMEOUT"' -k 1 "${MOCK_BOUND:-$b}" "$@"'

RC=""; OUTF=""; ERRF=""; ENVF=""; GHOUT=""
# run_body <label> <body> [VAR=value ...] — executes under the runner's own shell flags.
# RUN_KILL_AFTER=<s> kills the step shell with SIGKILL after <s> seconds, as a step timeout does.
run_body() {
  local label="$1" body="$2"; shift 2
  OUTF="$TMP/$label.out"; ERRF="$TMP/$label.err"; ENVF="$TMP/$label.env"; GHOUT="$TMP/$label.ghout"
  : > "$ENVF"; : > "$GHOUT"; : > "$TMP/$label.sum"
  local -a pre=()
  [[ -z "${RUN_KILL_AFTER:-}" ]] || pre=("$REAL_TIMEOUT" -s KILL "$RUN_KILL_AFTER")
  # The subshell (not exec-optimised: `exit $?` follows) keeps the shell's own "Killed" notice out of the log.
  ( "${pre[@]}" env -i PATH="$STUB:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMPDIR" \
    GITHUB_WORKSPACE="$WS" GITHUB_ENV="$ENVF" GITHUB_OUTPUT="$GHOUT" GITHUB_STEP_SUMMARY="$TMP/$label.sum" \
    MOCK_SECRET="$SECRET_SENTINEL" MOCK_TIMEOUT_LOG="$TMP/$label.timeouts" "$@" \
    bash --noprofile --norc -eo pipefail "$body" > "$OUTF" 2> "$ERRF"; exit $? ) 2>/dev/null
  RC=$?
}
markers() { grep -h '^SOLEUR_ZOT_BRIDGE ' "$OUTF" "$ERRF" 2>/dev/null || true; }
nmarkers() { cat "$OUTF" "$ERRF" 2>/dev/null | grep -c '^SOLEUR_ZOT_BRIDGE ' || true; }
notices() { grep -h '^::notice title=SOLEUR_ZOT_BRIDGE::' "$OUTF" 2>/dev/null || true; }
want_line() { printf 'SOLEUR_ZOT_BRIDGE stage=%s verdict=%s cause=%s host=%s rc=%s runbook=%s' "$1" "$2" "$3" "$4" "$5" "$RUNBOOK#grep-for-the-bridge-markers-first"; }
last_reason() { grep '^mirror_reason=' "$GHOUT" | tail -1; }
# env_from <GITHUB_ENV file...> — the KEY=VALUE lines earlier steps published, in order (a later
# line wins, as on the runner). Every value written by these steps is single-line.
ENV_FROM=()
env_from() { ENV_FROM=(); local f l; for f in "$@"; do while IFS= read -r l; do [[ "$l" == *=* ]] && ENV_FROM+=("$l"); done < "$f"; done; }

echo "=== each executed step declares the env its body reads ==="
ROWS=$((ROWS + 1))
_ok=1; _miss=""
for _pair in "Start cloudflared registry bridge|$ACTION|$BRIDGE_BODY" "Docker login to zot|$ACTION|$LOGIN_BODY" "$MIRROR_STEP|$WF|$MIRROR_BODY"; do
  IFS='|' read -r _st _file _body <<<"$_pair"
  _keys="$(python3 -I "$DERIVE" keys "$_file" "$_st")"
  _need="TOKEN_VERDICT TOKEN_CHECKED_AT TOKEN_CAUSE"
  [[ "$_body" == "$MIRROR_BODY" ]] && _need="$_need BRIDGE_OUTCOME IMAGE DIGEST VERSION COMMIT_SHA"
  for _k in $_need; do
    grep -qE "\\\$\\{?${_k}\\b" "$_body" || _miss="$_miss ${_st%% *}:${_k}(unread)"
    grep -qxF "$_k" <<<"$_keys" || { _ok=0; _miss="$_miss ${_st%% *}:${_k}(undeclared)"; }
  done
done
[[ -z "$_miss" ]] || _ok=0
_tc="$(step_field "$WF" "$BRIDGE_STEP" token-cause)"
[[ "$_tc" == *"steps.token_preflight.outputs.cause"* ]] || { _ok=0; _miss="$_miss caller:token-cause"; }
check "D1: the listener, login and mirror steps read and declare TOKEN_* (mirror also its image/bridge inputs); the caller forwards token-cause (missing:${_miss:- none})" "$_ok"

echo "=== bridge action: first step publishes stage=setup ==="
ROWS=$((ROWS + 1))
SETUP_BODY="$TMP/setup.sh"; step_run "$ACTION" "Validate skip-docker-login input" > "$SETUP_BODY" || : > "$SETUP_BODY"
_first="$(python3 -I -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["runs"]["steps"][0].get("name",""))' "$ACTION" 2>/dev/null)"
derive_action "Validate skip-docker-login input" "$(ctx unverifiable edge-error-1000 10:00:00Z success)"
run_body s1 "$SETUP_BODY" "${DERIVED[@]}"
S1ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$_first" == "Validate skip-docker-login input" ]] || _ok=0
[[ "$(head -1 "$S1ENV")" == "ZOT_BRIDGE_STAGE=setup" ]] || _ok=0
check "S1: the action's first step writes ZOT_BRIDGE_STAGE=setup before anything can fail (rc=$RC, first=$_first)" "$_ok"

echo "=== bridge action: listener never bound ==="
ROWS=$((ROWS + 1))
derive_action "Start cloudflared registry bridge" "$(ctx unverifiable edge-error-1000 10:00:00Z success)"
run_body l1 "$BRIDGE_BODY" "${DERIVED[@]}" MOCK_NC_RC=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(grep -c '^SOLEUR_ZOT_BRIDGE' "$ERRF")" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line listener unverifiable edge-error-1000 registry.soleur.ai 1)" ]] || _ok=0
[[ "$(notices)" == "::notice title=SOLEUR_ZOT_BRIDGE::$(want_line listener unverifiable edge-error-1000 registry.soleur.ai 1)" ]] || _ok=0
check "L1: one marker on stderr and one notice, stage=listener, the preflight's verdict and cause, nc's rc (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
grep -qxF 'ZOT_BRIDGE_STAGE=listener' "$ENVF" || _ok=0
grep -qxF 'ZOT_BRIDGE_RC=1' "$ENVF" || _ok=0
grep -qxF 'ZOT_BRIDGE_HOST=registry.soleur.ai' "$ENVF" || _ok=0
grep -qF "$SECRET_SENTINEL" "$ERRF" && _ok=0
grep -qF "$SECRET_SENTINEL" <<<"$(notices)" && _ok=0
grep -qF "$SECRET_SENTINEL" "$ENVF" && _ok=0
check "L2: stage/rc/host published job-wide; no secret in the marker, the notice or GITHUB_ENV" "$_ok"

ROWS=$((ROWS + 1))
derive_action "Start cloudflared registry bridge" "$(ctx live $'edge-error-1000\n::error::forged' '' success)"
run_body l3 "$BRIDGE_BODY" "${DERIVED[@]}" MOCK_NC_RC=1
_ok=1
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line listener live invalid registry.soleur.ai 1)" ]] || _ok=0
grep -q '^::error::forged' "$ERRF" "$OUTF" && _ok=0
check "L3: a CR/LF-carrying cause from a step output renders cause=invalid and forges nothing (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
derive_action "Start cloudflared registry bridge" "$(ctx live unknown '' success)"
run_body l4 "$BRIDGE_BODY" "${DERIVED[@]}" MOCK_NC_RC=0
L4ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
# The stage is the last one ENTERED; only a failure writes an rc.
[[ "$(grep '^ZOT_BRIDGE_STAGE=' "$ENVF")" == "ZOT_BRIDGE_STAGE=listener" ]] || _ok=0
grep -q '^ZOT_BRIDGE_RC=' "$ENVF" && _ok=0
# The SUCCESS path publishes the host: the login and push markers below read it from here.
grep -qxF 'ZOT_BRIDGE_HOST=registry.soleur.ai' "$ENVF" || _ok=0
check "L4: a bound listener prints no marker, records stage=listener with no rc, and publishes ZOT_BRIDGE_HOST (rc=$RC)" "$_ok"

echo "=== bridge action: docker login failed (env chained from the setup and bridge steps) ==="
env_from "$S1ENV" "$L4ENV"
ROWS=$((ROWS + 1))
derive_action "Docker login to zot" "$(ctx unverifiable host-nxdomain '' success)"
run_body g1 "$LOGIN_BODY" "${ENV_FROM[@]}" "${DERIVED[@]}" MOCK_DOCKER_RC=1
G1ENV="$ENVF"
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(grep -c '^SOLEUR_ZOT_BRIDGE' "$ERRF")" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line login unverifiable host-nxdomain registry.soleur.ai 1)" ]] || _ok=0
[[ "$(notices)" == "::notice title=SOLEUR_ZOT_BRIDGE::$(want_line login unverifiable host-nxdomain registry.soleur.ai 1)" ]] || _ok=0
grep -qF "$SECRET_SENTINEL" "$ERRF" && _ok=0
grep -qF "$SECRET_SENTINEL" <<<"$(notices)" && _ok=0
check "G1: one marker and one notice, stage=login, the host the bridge step published, docker's rc, no secret (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
grep -qxF 'ZOT_BRIDGE_STAGE=login' "$ENVF" || _ok=0
grep -qxF 'ZOT_BRIDGE_RC=1' "$ENVF" || _ok=0
check "G2: the login failure publishes stage=login and its rc" "$_ok"

ROWS=$((ROWS + 1))
derive_action "Docker login to zot" "$(ctx live unknown '' success)"
run_body g3 "$LOGIN_BODY" "${ENV_FROM[@]}" "${DERIVED[@]}" MOCK_DOCKER_RC=0
G3ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ "$(head -1 "$ENVF")" == "ZOT_BRIDGE_STAGE=login" ]] || _ok=0
grep -q '^ZOT_BRIDGE_RC=' "$ENVF" && _ok=0
check "G3: a successful login prints no marker; it wrote stage=login on entry and no rc (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
run_body g4 "$LOGIN_BODY" "${ENV_FROM[@]}" "${DERIVED[@]}" MOCK_NO_ZOT_PUSH=1 MOCK_DOCKER_RC=0
G4ENV="$ENVF"
_ok=1
[[ "$RC" == "1" ]] || _ok=0
grep -qxF 'ZOT_BRIDGE_STAGE=login' "$ENVF" || _ok=0
grep -q 'ZOT_BRIDGE_STAGE=listener' "$ENVF" && _ok=0
check "G4: an empty ZOT_PUSH_* read (listener already up) publishes stage=login, never listener (rc=$RC)" "$_ok"

# docker login hangs; the step is killed (SIGKILL, as its timeout-minutes does) before any branch.
RUN_KILL_AFTER=1 run_body g5 "$LOGIN_BODY" "${ENV_FROM[@]}" "${DERIVED[@]}" MOCK_DOCKER_HANG=1
G5ENV="$ENVF"; G5RC="$RC"

echo "=== reusable-release mirror failure path ==="
MIRROR_CTX_FAIL="$(ctx unverifiable edge-error-1000 10:00:00Z failure)"
derive_mirror "$MIRROR_CTX_FAIL"; MIRROR_FAIL_ENV=("${DERIVED[@]}")

ROWS=$((ROWS + 1))
env_from "$S1ENV" "$L4ENV" "$G1ENV"
run_body r1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_FAIL_ENV[@]}"
_want="$(want_line login unverifiable edge-error-1000 registry.soleur.ai 1)"
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(markers)" == "$_want" ]] || _ok=0
[[ "$(notices)" == "::notice title=SOLEUR_ZOT_BRIDGE::${_want}" ]] || _ok=0
grep -q "^::error::zot mirror FAILED at stage 'bridge'.* ${_want}\$" "$OUTF" || _ok=0
check "R1: bridge failure prints the action's stage once, as a notice, and on the ::error:: line (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
[[ "$(grep -c '^bridge_marker=' "$GHOUT")" == "1" ]] || _ok=0
grep -qxF "bridge_marker=${_want}" "$GHOUT" || _ok=0
[[ "$(last_reason)" == "mirror_reason=bridge" ]] || _ok=0
check "R2: the same line leaves the step as the bridge_marker output for the email" "$_ok"

ROWS=$((ROWS + 1))
run_body r3 "$MIRROR_BODY" "${MIRROR_FAIL_ENV[@]}"
_ok=1
[[ "$(markers)" == "$(want_line setup unverifiable edge-error-1000 invalid invalid)" ]] || _ok=0
check "R3: an action failure that set no stage renders stage=setup (never listener), host/rc=invalid (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
env_from "$S1ENV"
run_body r3b "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_FAIL_ENV[@]}"
_ok=1
[[ "$(markers)" == "$(want_line setup unverifiable edge-error-1000 invalid invalid)" ]] || _ok=0
check "R3b: a failure before the listener (only the first step's env) renders stage=setup (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
env_from "$S1ENV" "$L4ENV" "$G4ENV"
run_body r3c "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_FAIL_ENV[@]}"
_ok=1
[[ "$(markers)" == "$(want_line login unverifiable edge-error-1000 registry.soleur.ai invalid)" ]] || _ok=0
check "R3c: the missing-ZOT_PUSH_* failure renders stage=login rc=invalid, not listener (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
env_from "$S1ENV" "$L4ENV" "$G5ENV"
run_body r3d "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_FAIL_ENV[@]}"
_ok=1
[[ "$G5RC" == "137" ]] || _ok=0
[[ "$(markers)" == "$(want_line login unverifiable edge-error-1000 registry.soleur.ai invalid)" ]] || _ok=0
check "R3d: listener up, docker login hung and the step killed: stage=login (killed rc=$G5RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body r4 "$MIRROR_BODY" "${MIRROR_FAIL_ENV[@]}" ZOT_BRIDGE_STAGE=$'login\n::error::forged' ZOT_BRIDGE_RC=$'1\nmirror_status=ok' ZOT_BRIDGE_HOST=registry.soleur.ai
_ok=1
[[ "$(markers)" == "$(want_line invalid unverifiable edge-error-1000 registry.soleur.ai invalid)" ]] || _ok=0
[[ "$(grep -c '^bridge_marker=' "$GHOUT")" == "1" ]] || _ok=0
grep -qxF 'mirror_status=ok' "$GHOUT" && _ok=0
grep -q '^::error::forged' "$ERRF" "$OUTF" && _ok=0
check "R4: hostile env values collapse to invalid and cannot add an output key or annotation" "$_ok"

ROWS=$((ROWS + 1))
# An emitter that returns a line outside the grammar: the release path must print nothing of it.
WS_BAD="$TMP/ws-bad"; mkdir -p "$WS_BAD/scripts"
{ cat "$LIB"; printf '%s\n' "zot_bridge_marker() { printf 'SOLEUR_ZOT_BRIDGE stage=bogus rc=1\\n'; }"; } > "$WS_BAD/scripts/zot-mirror-diagnosis.sh"
env_from "$S1ENV" "$L4ENV" "$G1ENV"
run_body i1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_FAIL_ENV[@]}" GITHUB_WORKSPACE="$WS_BAD"
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
grep -q '::notice title=SOLEUR_ZOT_BRIDGE' "$OUTF" "$ERRF" && _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
[[ "$(last_reason)" == "mirror_reason=bridge" ]] || _ok=0
grep -q "^::error::zot mirror FAILED at stage 'bridge'" "$OUTF" || _ok=0
check "I1: an emitter line that fails zot_bridge_marker_valid yields no notice, no output and no marker line; the ::error:: still prints (rc=$RC)" "$_ok"

echo "=== reusable-release: crane copy over a bridge that came up (env chained from the action) ==="
env_from "$S1ENV" "$L4ENV" "$G3ENV"
derive_mirror "$(ctx live unknown '' success)"; MIRROR_OK_ENV=("${DERIVED[@]}")
ROWS=$((ROWS + 1))
run_body p1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_CRANE_COPY_RC=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai 1)" ]] || _ok=0
grep -qE '^mirror_reason=copy_' "$GHOUT" || _ok=0
check "P1: a failed copy prints stage=push with crane's rc and the host the bridge step published (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body p2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_CRANE_COPY_RC=0
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "P2: a green mirror prints no marker and no bridge_marker output (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
[[ "$(head -1 "$GHOUT")" == "mirror_reason=killed" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=" ]] || _ok=0
check "K2: a green mirror clears the provisional mirror_reason=killed (last value empty; the BLOCKED Slack reads it), got: $(last_reason)" "$_ok"

ROWS=$((ROWS + 1))
run_body v1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_ZOT_DIGEST=
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=verify" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai invalid)" ]] || _ok=0
grep -qxF "bridge_marker=$(want_line push live unknown registry.soleur.ai invalid)" "$GHOUT" || _ok=0
check "V1: an unresolvable read-back after the copy (the bridge died) prints stage=push (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body v2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_ZOT_DIGEST=sha256:0ther
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=verify" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "V2: a digest MISMATCH is a writer question, not a bridge failure: no marker (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
run_body n1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_CURL_RC=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=crane_install" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "N1: a non-bridge failure (crane_install) prints no marker, no notice and no bridge_marker output (rc=$RC)" "$_ok"

echo "=== reusable-release: cosign sign over the bridge ==="
ROWS=$((ROWS + 1))
run_body sg1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" \
  MOCK_COSIGN_ERR='Error: signing [127.0.0.1:5000/jikig-ai/soleur-web-platform@sha256:deadbeef]: Put "http://127.0.0.1:5000/v2/x/manifests/sha256-deadbeef.sig": dial tcp 127.0.0.1:5000: connect: connection refused'
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=sign" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai 1)" ]] || _ok=0
grep -qxF "bridge_marker=$(want_line push live unknown registry.soleur.ai 1)" "$GHOUT" || _ok=0
grep -q "^::error::zot mirror FAILED at stage 'sign'.*connection error to 127.0.0.1:5000" "$OUTF" || _ok=0
grep -q 'Sigstore/Fulcio is down' "$OUTF" && _ok=0
check "SG1: a signing failure whose stderr shows a connection error to 127.0.0.1:5000 prints stage=push and does not blame Fulcio (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body sg2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" \
  MOCK_COSIGN_ERR='Error: signing [127.0.0.1:5000/x@sha256:deadbeef]: getting signer: retrieving cert: POST https://fulcio.sigstore.dev/api/v2/signingCert: 503 Service Unavailable'
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=sign" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
grep -q 'Sigstore/Fulcio is down' "$OUTF" || _ok=0
check "SG2: a signing failure with no bridge connection error prints no marker and keeps the Sigstore detail (rc=$RC)" "$_ok"

echo "=== reusable-release: a hung bridged call is bounded and still reports ==="
ROWS=$((ROWS + 1))
run_body h1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_CRANE_HANG=1 MOCK_BOUND=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=copy_v" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai 124)" ]] || _ok=0
[[ "$(grep -c '^-k 5 300 crane copy ' "$TMP/h1.timeouts" 2>/dev/null)" == "3" ]] || _ok=0
check "H1: a hung crane copy is killed by its own bound on each of 3 attempts and degraded() prints stage=push rc=124 (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body h2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_DIGEST_HANG=1 MOCK_BOUND=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=verify" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai invalid)" ]] || _ok=0
grep -q '^-k 5 60 crane digest ' "$TMP/h2.timeouts" 2>/dev/null || _ok=0
grep -q '^-k 5 120 cosign sign ' "$TMP/h2.timeouts" 2>/dev/null || _ok=0
check "H2: a hung read-back is bounded and reads as verify unresolvable, stage=push; cosign sign is bounded too (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
# The step itself killed mid-copy (its timeout-minutes), before degraded() could run.
RUN_KILL_AFTER=2 run_body k1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_OK_ENV[@]}" MOCK_CRANE_HANG=1 MOCK_BOUND=1
_ok=1
[[ "$RC" == "137" ]] || _ok=0
[[ "$(grep -c . "$GHOUT")" == "1" ]] || _ok=0
[[ "$(last_reason)" == "mirror_reason=killed" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
check "K1: a mirror step killed before degraded() leaves exactly mirror_reason=killed (rc=$RC, outputs: $(tr '\n' ' ' < "$GHOUT"))" "$_ok"

echo "=== reusable-release: the bridge and mirror steps are time-bounded inside the job ==="
ROWS=$((ROWS + 1))
_ok=1
python3 -I - "$WF" <<'PY2' || _ok=0
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for job in doc["jobs"].values():
    steps = {st.get("name", ""): st for st in job.get("steps") or []}
    b = steps.get("Bridge to zot registry (CF Tunnel)")
    m = steps.get("Mirror image GHCR→zot (crane) + cosign-sign the zot digest")
    if b and m:
        cap = job.get("timeout-minutes")
        tb, tm = b.get("timeout-minutes"), m.get("timeout-minutes")
        assert isinstance(tb, int) and isinstance(tm, int), (tb, tm)
        # A hang must fail the step (the failure email still runs), not cancel the job.
        assert isinstance(cap, int) and tb + tm < cap, (tb, tm, cap)
        raise SystemExit(0)
raise SystemExit("bridge/mirror steps not found")
PY2
check "T1: both steps carry timeout-minutes, together inside the job's own cap" "$_ok"

ROWS=$((ROWS + 1))
_t2="$(python3 -I - "$WF" <<'PY3' 2>&1
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for job in doc["jobs"].values():
    steps = {st.get("name", ""): st for st in job.get("steps") or []}
    b = steps.get("Bridge to zot registry (CF Tunnel)")
    m = steps.get("Mirror image GHCR→zot (crane) + cosign-sign the zot digest")
    if not (b and m):
        continue
    tb, tm, run = b["timeout-minutes"], m["timeout-minutes"], m["run"]
    # cloudflared download: 4 attempts x --max-time 120 + 3 x 5 s retry delay = 8.25 min, plus the 15 s listener wait.
    assert tb >= 9, "bridge timeout-minutes %s is under the cloudflared retry budget" % tb
    bounds = {}
    for name, pat in (("copy", r"timeout -k 5 (\d+) crane copy "), ("sign", r"timeout -k 5 (\d+) cosign sign "), ("digest", r"timeout -k 5 (\d+) crane digest ")):
        found = re.findall(pat, run)
        assert len(found) == 1, "%s: %d bounded call sites" % (name, len(found))
        bounds[name] = int(found[0])
        # retry(): 3 attempts of (bound + 5 s kill grace) and 5 + 15 s of backoff must end inside the step.
        assert 3 * (bounds[name] + 5) + 20 < tm * 60, "%s chain does not fit %s min" % (name, tm)
    # The whole mirror measured up to 190 s (n=12); one copy call must be allowed at least that.
    assert bounds["copy"] >= 190, bounds
    # No bridged call outside a bound: strip strings and comments, then every call site needs `timeout -k`.
    for line in run.splitlines():
        code = re.sub(r"#.*", "", re.sub(r"'[^']*'", "", re.sub(r'"(?:[^"\\]|\\.)*"', "", line)))
        for mm in re.finditer(r"\b(crane\s+(copy|digest)|cosign\s+sign)\b", code):
            assert re.search(r"timeout -k \d+ \d+ $", code[:mm.start()]), "unbounded: " + line.strip()
    print("ok", tb, tm, bounds)
    raise SystemExit(0)
raise SystemExit("bridge/mirror steps not found")
PY3
)"
_ok=0; [[ "$_t2" == ok* ]] && _ok=1
check "T2: bridge >= the 9-min cloudflared budget; every crane copy / cosign sign / crane digest is bounded, each retry chain fits the mirror step, copy >= the 190 s measured max ($_t2)" "$_ok"

echo "=== the notify-ops email carries the output ==="
ROWS=$((ROWS + 1))
BODY="$(step_field "$WF" "Email notification (release FAILED)" body)" || BODY=""
_ok=1
[[ "$BODY" == *"steps.zot_mirror.outputs.bridge_marker != '' && format('<p>Bridge marker: <code>{0}</code></p>', steps.zot_mirror.outputs.bridge_marker) || ''"* ]] || _ok=0
check "E1: the failure email appends the re-validated bridge_marker output verbatim" "$_ok"

ROWS=$((ROWS + 1))
_ok=1
# The output is written only after zot_bridge_marker_valid, inside the one emitter function.
python3 -I - "$MIRROR_BODY" <<'PY' || _ok=0
import re, sys
body = open(sys.argv[1]).read()
m = re.search(r"emit_bridge_marker\(\) \{(.*?)\n          \}", body, re.S) or re.search(r"emit_bridge_marker\(\) \{(.*?)\n\}", body, re.S)
assert m, "emit_bridge_marker not found"
fn = m.group(1)
assert fn.count("bridge_marker=") == 1
assert fn.index("zot_bridge_marker_valid") < fn.index("bridge_marker=")
assert body.count("bridge_marker=") == 1, "a second writer of bridge_marker"
PY
check "E2: bridge_marker has one writer, gated on the grammar re-validation" "$_ok"

ROWS=$((ROWS + 1))
# Evaluate the email's stage expression itself under each shape the mirror step can leave.
_expr="$(python3 -I -c '
import re, sys
for m in re.finditer(r"\$\{\{(.*?)\}\}", sys.argv[1], re.S):
    if "mirror_reason" in m.group(1) and "bridge_marker" not in m.group(1):
        print(m.group(1).strip()); break' "$BODY")"
stage_of() { python3 -I "$DERIVE" expr "$_expr" "{\"steps\":{\"zot_mirror\":{\"outcome\":\"$1\",\"outputs\":{\"mirror_reason\":\"$2\"}}}}"; }
_ok=1
[[ -n "$_expr" ]] || _ok=0
[[ "$(stage_of failure killed)" == *"killed by its timeout"* ]] || _ok=0
[[ "$(stage_of failure '')" == *"killed by its timeout"* ]] || _ok=0
[[ "$(stage_of failure copy_v)" == "copy_v" ]] || _ok=0
[[ "$(stage_of skipped '')" == *"before or outside the mirror step"* ]] || _ok=0
check "E3: the email names a killed mirror step as killed (reason 'killed', or failure with none), a recorded stage verbatim, and 'outside' only when the step did not fail (got: $(stage_of failure ''))" "$_ok"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# Conservation: every row reports exactly once, so a neutered pass()/fail() breaks the
# equality even when the row counter is intact.
if (( ROWS < 34 || PASS + FAIL != ROWS )); then
  printf 'FATAL: only %d rows / %d assertions ran, expected >= 34.\n' "$ROWS" "$((PASS + FAIL))" >&2
  exit 1
fi
if (( FAIL > 0 )); then
  printf 'FAILED: %d of %d rows.\n' "$FAIL" "$ROWS" >&2
  exit 1
fi
exit 0
