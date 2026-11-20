#!/usr/bin/env bash
# Emission-site test for the SOLEUR_ZOT_BRIDGE marker (#12937, plan Phase 2.3/2.4).
#
# PROPERTY. Every bridge failure prints exactly ONE closed-grammar line
#   SOLEUR_ZOT_BRIDGE stage=<setup|listener|login|push> verdict=<v> cause=<c> host=<h> rc=<n> runbook=<path>
# from the library's single emitter (zot_bridge_marker in scripts/zot-mirror-diagnosis.sh):
#   - .github/actions/cf-tunnel-registry-bridge/action.yml first step              -> ZOT_BRIDGE_STAGE=setup
#   - the same action, listener never bound                                        -> stage=listener
#   - the same action, docker login failed (or its ZOT_PUSH_* read was empty)      -> stage=login
#   - .github/workflows/reusable-release.yml mirror step, bridge outcome failure    -> the action's stage
#   - the same step, crane copy (or the verify read) over a bridge that came up    -> stage=push
# Each printed line is also emitted as `::notice title=SOLEUR_ZOT_BRIDGE::<line>` so the
# check-runs annotations API carries it. The step rows chain their env through the GITHUB_ENV
# files the earlier steps wrote, the way the runner does, rather than supplying it by hand.
# and the release path hands the SAME line, re-validated, to the notify-ops email as the
# step output `bridge_marker`. A success path prints none. A hostile value riding in from a
# step output (CR/LF, `::`) cannot forge a second line, an annotation or a second output key.
#
# HOW. Steps are selected with PyYAML (never sliced by delimiter) and their `run:` bodies are
# executed under `bash --noprofile --norc -eo pipefail` — the runner's own invocation for a
# `shell: bash` step and for a workflow `run:` with no `shell:` key — with every external
# command stubbed on PATH. Nothing here touches the network. Every credential is synthesized
# (cq-test-fixtures-synthesized-only).
#
# MUTATION MATRIX — run 2026-11-19 against pristine copies, restored after each row; every row RED:
#   1  drop the zot_bridge_marker call in the listener branch        RED  L1, L2
#   2  drop it in the login branch                                   RED  G1, G2
#   3  `if ! docker login` again (rc lost)                           RED  G1 (rc=invalid / branch shape)
#   4  drop emit_bridge_marker from degraded()                       RED  R1, R2, P1
#   5  write the marker to GITHUB_OUTPUT without zot_bridge_marker_valid  RED  R4
#   6  the email body loses the bridge_marker expression             RED  E1
#   7  every row below skipped                                       RED  the row floor
#   8  (fix round) see the report for the setup/notice/verify/host-chain rows' mutations
#
# Run: bash plugins/soleur/test/zot-bridge-marker-emission.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${REPO_ROOT:?repo root resolved empty}"
ACTION="$REPO_ROOT/.github/actions/cf-tunnel-registry-bridge/action.yml"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"
LIB="$REPO_ROOT/scripts/zot-mirror-diagnosis.sh"
RUNBOOK="knowledge-base/engineering/operations/runbooks/zot-registry-revert.md"

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing; this suite asserted nothing"; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "FAIL: PyYAML missing; this suite asserted nothing"; exit 1; }

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

BRIDGE_BODY="$TMP/bridge.sh";  step_run "$ACTION" "Start cloudflared registry bridge" > "$BRIDGE_BODY" || { echo "FATAL: bridge step not found" >&2; exit 2; }
LOGIN_BODY="$TMP/login.sh";    step_run "$ACTION" "Docker login to zot" > "$LOGIN_BODY" || { echo "FATAL: login step not found" >&2; exit 2; }
MIRROR_BODY="$TMP/mirror.sh";  step_run "$WF" "Mirror image GHCR→zot" > "$MIRROR_BODY" || { echo "FATAL: mirror step not found" >&2; exit 2; }
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
mk docker 'cat >/dev/null; exit "${MOCK_DOCKER_RC:-1}"'
# Mirror-path stubs (same shapes as reusable-release-zot-mirror-retry.test.sh).
for c in sudo tar cosign; do mk "$c" 'exit 0'; done
mk sha256sum 'cat >/dev/null 2>&1; exit 0'
mk curl 'exit "${MOCK_CURL_RC:-0}"'
mk crane 'if [[ "${1:-}" == copy ]]; then exit "${MOCK_CRANE_COPY_RC:-0}"; fi; if [[ "${1:-}" == digest ]]; then echo "${MOCK_ZOT_DIGEST-$DIGEST}"; fi; exit 0'

RC=""; OUTF=""; ERRF=""; ENVF=""; GHOUT=""
# run_body <label> <body> [VAR=value ...] — executes under the runner's own shell flags.
run_body() {
  local label="$1" body="$2"; shift 2
  OUTF="$TMP/$label.out"; ERRF="$TMP/$label.err"; ENVF="$TMP/$label.env"; GHOUT="$TMP/$label.ghout"
  : > "$ENVF"; : > "$GHOUT"; : > "$TMP/$label.sum"
  env -i PATH="$STUB:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMPDIR" \
    GITHUB_WORKSPACE="$WS" GITHUB_ENV="$ENVF" GITHUB_OUTPUT="$GHOUT" GITHUB_STEP_SUMMARY="$TMP/$label.sum" \
    MOCK_SECRET="$SECRET_SENTINEL" "$@" \
    bash --noprofile --norc -eo pipefail "$body" > "$OUTF" 2> "$ERRF"
  RC=$?
}
markers() { grep -h '^SOLEUR_ZOT_BRIDGE ' "$OUTF" "$ERRF" 2>/dev/null || true; }
nmarkers() { cat "$OUTF" "$ERRF" 2>/dev/null | grep -c '^SOLEUR_ZOT_BRIDGE ' || true; }
notices() { grep -h '^::notice title=SOLEUR_ZOT_BRIDGE::' "$OUTF" 2>/dev/null || true; }
want_line() { printf 'SOLEUR_ZOT_BRIDGE stage=%s verdict=%s cause=%s host=%s rc=%s runbook=%s' "$1" "$2" "$3" "$4" "$5" "$RUNBOOK#grep-for-the-bridge-markers-first"; }
# env_from <GITHUB_ENV file...> — the KEY=VALUE lines earlier steps published, in order (a later
# line wins, as on the runner). Every value written by these steps is single-line.
ENV_FROM=()
env_from() { ENV_FROM=(); local f l; for f in "$@"; do while IFS= read -r l; do [[ "$l" == *=* ]] && ENV_FROM+=("$l"); done < "$f"; done; }

echo "=== bridge action: first step publishes stage=setup ==="
ROWS=$((ROWS + 1))
SETUP_BODY="$TMP/setup.sh"; step_run "$ACTION" "Validate skip-docker-login input" > "$SETUP_BODY" || : > "$SETUP_BODY"
_first="$(python3 -I -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["runs"]["steps"][0].get("name",""))' "$ACTION" 2>/dev/null)"
run_body s1 "$SETUP_BODY" SKIP=false
S1ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$_first" == "Validate skip-docker-login input" ]] || _ok=0
[[ "$(head -1 "$S1ENV")" == "ZOT_BRIDGE_STAGE=setup" ]] || _ok=0
check "S1: the action's first step writes ZOT_BRIDGE_STAGE=setup before anything can fail (rc=$RC, first=$_first)" "$_ok"

echo "=== bridge action: listener never bound ==="
ROWS=$((ROWS + 1))
run_body l1 "$BRIDGE_BODY" TOKEN_VERDICT=unverifiable TOKEN_CHECKED_AT=10:00:00Z TOKEN_CAUSE=edge-error-1000 MOCK_NC_RC=1
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
run_body l3 "$BRIDGE_BODY" TOKEN_VERDICT=live TOKEN_CAUSE=$'edge-error-1000\n::error::forged' MOCK_NC_RC=1
_ok=1
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line listener live invalid registry.soleur.ai 1)" ]] || _ok=0
grep -q '^::error::forged' "$ERRF" "$OUTF" && _ok=0
check "L3: a CR/LF-carrying cause from a step output renders cause=invalid and forges nothing (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body l4 "$BRIDGE_BODY" TOKEN_VERDICT=live MOCK_NC_RC=0
L4ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
grep -q 'ZOT_BRIDGE_STAGE' "$ENVF" && _ok=0
# The SUCCESS path publishes the host: the login and push markers below read it from here.
grep -qxF 'ZOT_BRIDGE_HOST=registry.soleur.ai' "$ENVF" || _ok=0
check "L4: a bound listener prints no marker, sets no failure stage, and publishes ZOT_BRIDGE_HOST (rc=$RC)" "$_ok"

echo "=== bridge action: docker login failed (env chained from the setup and bridge steps) ==="
env_from "$S1ENV" "$L4ENV"
ROWS=$((ROWS + 1))
run_body g1 "$LOGIN_BODY" "${ENV_FROM[@]}" TOKEN_VERDICT=unverifiable TOKEN_CAUSE=host-nxdomain MOCK_DOCKER_RC=1
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
run_body g3 "$LOGIN_BODY" "${ENV_FROM[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown MOCK_DOCKER_RC=0
G3ENV="$ENVF"
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
check "G3: a successful login prints no marker (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
run_body g4 "$LOGIN_BODY" "${ENV_FROM[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown MOCK_NO_ZOT_PUSH=1 MOCK_DOCKER_RC=0
G4ENV="$ENVF"
_ok=1
[[ "$RC" == "1" ]] || _ok=0
grep -qxF 'ZOT_BRIDGE_STAGE=login' "$ENVF" || _ok=0
grep -q 'ZOT_BRIDGE_STAGE=listener' "$ENVF" && _ok=0
check "G4: an empty ZOT_PUSH_* read (listener already up) publishes stage=login, never listener (rc=$RC)" "$_ok"

echo "=== reusable-release mirror failure path ==="
MIRROR_ENV=(IMAGE=ghcr.io/jikig-ai/soleur-web-platform DIGEST=sha256:deadbeef VERSION=1.2.3 COMMIT_SHA=abc123def
  TOKEN_VERDICT=unverifiable TOKEN_CHECKED_AT=10:00:00Z TOKEN_CAUSE=edge-error-1000 MIRROR_OVERRIDE_REASON=)

ROWS=$((ROWS + 1))
env_from "$S1ENV" "$L4ENV" "$G1ENV"
run_body r1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" BRIDGE_OUTCOME=failure
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
grep -qxF 'mirror_reason=bridge' "$GHOUT" || _ok=0
check "R2: the same line leaves the step as the bridge_marker output for the email" "$_ok"

ROWS=$((ROWS + 1))
run_body r3 "$MIRROR_BODY" "${MIRROR_ENV[@]}" BRIDGE_OUTCOME=failure
_ok=1
[[ "$(markers)" == "$(want_line setup unverifiable edge-error-1000 invalid invalid)" ]] || _ok=0
check "R3: an action failure that set no stage renders stage=setup (never listener), host/rc=invalid (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
env_from "$S1ENV"
run_body r3b "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" BRIDGE_OUTCOME=failure
_ok=1
[[ "$(markers)" == "$(want_line setup unverifiable edge-error-1000 invalid invalid)" ]] || _ok=0
check "R3b: a failure before the listener (only the first step's env) renders stage=setup (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
env_from "$S1ENV" "$L4ENV" "$G4ENV"
run_body r3c "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" BRIDGE_OUTCOME=failure
_ok=1
[[ "$(markers)" == "$(want_line login unverifiable edge-error-1000 registry.soleur.ai invalid)" ]] || _ok=0
check "R3c: the missing-ZOT_PUSH_* failure renders stage=login rc=invalid, not listener (got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body r4 "$MIRROR_BODY" "${MIRROR_ENV[@]}" BRIDGE_OUTCOME=failure ZOT_BRIDGE_STAGE=$'login\n::error::forged' ZOT_BRIDGE_RC=$'1\nmirror_status=ok' ZOT_BRIDGE_HOST=registry.soleur.ai
_ok=1
[[ "$(markers)" == "$(want_line invalid unverifiable edge-error-1000 registry.soleur.ai invalid)" ]] || _ok=0
[[ "$(grep -c '^bridge_marker=' "$GHOUT")" == "1" ]] || _ok=0
grep -qxF 'mirror_status=ok' "$GHOUT" && _ok=0
grep -q '^::error::forged' "$ERRF" "$OUTF" && _ok=0
check "R4: hostile env values collapse to invalid and cannot add an output key or annotation" "$_ok"

echo "=== reusable-release: crane copy over a bridge that came up (env chained from the action) ==="
env_from "$S1ENV" "$L4ENV" "$G3ENV"
ROWS=$((ROWS + 1))
run_body p1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown BRIDGE_OUTCOME=success MOCK_CRANE_COPY_RC=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
[[ "$(nmarkers)" == "1" ]] || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai 1)" ]] || _ok=0
grep -qE '^mirror_reason=copy_' "$GHOUT" || _ok=0
check "P1: a failed copy prints stage=push with crane's rc and the host the bridge step published (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body p2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown BRIDGE_OUTCOME=success MOCK_CRANE_COPY_RC=0
_ok=1
[[ "$RC" == "0" ]] || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "P2: a green mirror prints no marker and no bridge_marker output (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
run_body v1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown BRIDGE_OUTCOME=success MOCK_ZOT_DIGEST=
_ok=1
[[ "$RC" == "1" ]] || _ok=0
grep -qxF 'mirror_reason=verify' "$GHOUT" || _ok=0
[[ "$(markers)" == "$(want_line push live unknown registry.soleur.ai invalid)" ]] || _ok=0
grep -qxF "bridge_marker=$(want_line push live unknown registry.soleur.ai invalid)" "$GHOUT" || _ok=0
check "V1: an unresolvable read-back after the copy (the bridge died) prints stage=push (rc=$RC, got: $(markers))" "$_ok"

ROWS=$((ROWS + 1))
run_body v2 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown BRIDGE_OUTCOME=success MOCK_ZOT_DIGEST=sha256:0ther
_ok=1
[[ "$RC" == "1" ]] || _ok=0
grep -qxF 'mirror_reason=verify' "$GHOUT" || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "V2: a digest MISMATCH is a writer question, not a bridge failure: no marker (rc=$RC)" "$_ok"

ROWS=$((ROWS + 1))
run_body n1 "$MIRROR_BODY" "${ENV_FROM[@]}" "${MIRROR_ENV[@]}" TOKEN_VERDICT=live TOKEN_CAUSE=unknown BRIDGE_OUTCOME=success MOCK_CURL_RC=1
_ok=1
[[ "$RC" == "1" ]] || _ok=0
grep -qxF 'mirror_reason=crane_install' "$GHOUT" || _ok=0
[[ "$(nmarkers)" == "0" ]] || _ok=0
[[ -z "$(notices)" ]] || _ok=0
grep -q '^bridge_marker=' "$GHOUT" && _ok=0
check "N1: a non-bridge failure (crane_install) prints no marker, no notice and no bridge_marker output (rc=$RC)" "$_ok"

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

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# Conservation: every row reports exactly once, so a neutered pass()/fail() breaks the
# equality even when the row counter is intact.
if (( ROWS < 23 || PASS + FAIL != ROWS )); then
  echo "FATAL: only ${ROWS} rows / $((PASS + FAIL)) assertions ran, expected >= 23." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
