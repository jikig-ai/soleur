#!/usr/bin/env bash
# Executes the real `probe` run: body of .github/workflows/scheduled-realtime-probe.yml under
# `bash --noprofile --norc -eo pipefail` (a stand-in for the runner's default `bash -e {0}`; the
# step enables pipefail itself) with stubbed `doppler` and `node`,
# and pins what each arm DECIDES. The probe exists to canary the no-native-WebSocket path; a
# silent loss of that path (flag dropped, env block edited away, Node line that removed the flag)
# is the failure this suite exists to catch. Every fixture is synthesized
# (cq-test-fixtures-synthesized-only): an invalid token, no network, no real Doppler.
#
# The step's own `env:` block (NODE_OPTIONS) is read from the workflow and applied to the stubs,
# so deleting that declaration from the workflow reddens the control row.
#
# Auto-globbed by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$ROOT/.github/workflows/scheduled-realtime-probe.yml"

PASS=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAILURES+=("$1"); }

TMP="$(mktemp -d -t soleur-run.$$.XXXXXXXX)" || exit 2
trap 'rm -rf "$TMP"' EXIT

python3 - "$WF" "$TMP" <<'PY' || { echo "  FATAL: could not extract the probe step"; exit 2; }
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
st = [s for s in d["jobs"]["probe"]["steps"] if s.get("id") == "probe"][0]
open(f"{sys.argv[2]}/probe.sh", "w").write(st["run"])
open(f"{sys.argv[2]}/step_node_options", "w").write(str(st.get("env", {}).get("NODE_OPTIONS", "")))
sn = [s for s in d["jobs"]["probe"]["steps"] if str(s.get("uses", "")).startswith("actions/setup-node")][0]
open(f"{sys.argv[2]}/node_version", "w").write(str(sn.get("with", {}).get("node-version", "")))
PY
STEP_NODE_OPTIONS="$(cat "$TMP/step_node_options")"
SETUP_NODE_VERSION="$(cat "$TMP/node_version")"

mkdir -p "$TMP/bin"
# doppler stub: `configs get` answers a dev config; `run -- <cmd>` executes <cmd> unless the case
# simulates a Doppler outage (exit 1, no output, the script never starts).
cat > "$TMP/bin/doppler" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "configs" ]]; then echo '{"environment":"dev"}'; exit 0; fi
if [[ "${1:-}" == "run" ]]; then
  echo x >> "$STUB_DOPPLER_RUNS"
  [[ "${STUB_DOPPLER_DOWN:-0}" == "1" ]] && exit 1
  shift; while [[ "${1:-}" != "--" ]]; do shift; done; shift; exec "$@"
fi
exit 64
STUB
# node stub: `-p 'typeof WebSocket'` reports `undefined` only when NODE_OPTIONS carries the flag
# (as real Node 22 does) unless STUB_NODE_REJECT makes it reject the option; a probe invocation
# prints the polyfill line per STUB_POLYFILL_SKIP_ITER (iteration number that omits it, 0 = never).
# STUB_NODE_WARN adds a stderr warning to a healthy `-p` answer; the `-p` branch also records
# whether DOPPLER_TOKEN was in its environment.
cat > "$TMP/bin/node" <<'STUB'
#!/usr/bin/env bash
# Real Node rejects a NODE_OPTIONS token it does not allow, at startup, for every invocation.
for tok in ${NODE_OPTIONS:-}; do
  case "$tok" in
    --no-experimental-websocket|--max-old-space-size=*) ;;
    *) echo "node: $tok is not allowed in NODE_OPTIONS" >&2; exit 9 ;;
  esac
done
native=function
case " ${NODE_OPTIONS:-} " in *" --no-experimental-websocket "*) native=undefined ;; esac
if [[ "${1:-}" == "-p" ]]; then
  [[ "${STUB_NODE_REJECT:-0}" == "1" ]] && { echo "node: bad option: --no-experimental-websocket" >&2; exit 9; }
  echo "${DOPPLER_TOKEN:+set}" > "$STUB_TOKEN_SEEN"
  [[ "${STUB_NODE_WARN:-0}" == "1" ]] && echo "(node:1) ExperimentalWarning: simulated stderr noise" >&2
  echo "$native"; exit 0
fi
n=$(( $(cat "$STUB_COUNTER" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_COUNTER"
if [[ "$n" != "${STUB_POLYFILL_SKIP_ITER:-0}" && "$native" == "undefined" ]]; then
  echo "[probe] polyfill: applied (globalThis.WebSocket = ws)"
else
  echo "[probe] polyfill: not needed (native WebSocket present)"
fi
echo "SUBSCRIBED"; exit 0
STUB
chmod +x "$TMP/bin/doppler" "$TMP/bin/node"

run_step() {  # env assignments... -> $TMP/out (GITHUB_OUTPUT), $TMP/log, RC
  : > "$TMP/out"; : > "$TMP/counter"; : > "$TMP/token_seen"; : > "$TMP/doppler_runs"
  env -i PATH="$TMP/bin:/usr/bin:/bin" DOPPLER_TOKEN=dp.st.invalid-fixture GITHUB_OUTPUT="$TMP/out" \
    STUB_COUNTER="$TMP/counter" STUB_TOKEN_SEEN="$TMP/token_seen" STUB_DOPPLER_RUNS="$TMP/doppler_runs" "$@" \
    bash --noprofile --norc -eo pipefail "$TMP/probe.sh" > "$TMP/log" 2>&1; RC=$?
}
mode() { sed -n 's/^failure_mode=//p' "$TMP/out"; }
detail() { sed -n 's/^failure_detail=//p' "$TMP/out"; }

echo "instrument controls"
[[ -s "$TMP/probe.sh" ]] && grep -q 'typeof WebSocket' "$TMP/probe.sh" \
  && pass "X1: the extracted probe step is non-empty and carries the typeof guard" \
  || fail "X1: probe step extraction came back empty or without the guard"
case " $STEP_NODE_OPTIONS " in *" --no-experimental-websocket "*) X2_OK=1 ;; *) X2_OK=0 ;; esac
[[ "$X2_OK" == 1 ]] \
  && pass "X2: the workflow's probe step env declares --no-experimental-websocket" \
  || fail "X2: step env NODE_OPTIONS is '$STEP_NODE_OPTIONS'"

[[ -n "$SETUP_NODE_VERSION" && "$SETUP_NODE_VERSION" == "$(tr -d '[:space:]' < "$ROOT/apps/web-platform/.nvmrc")" ]] \
  && pass "X3: the probe's setup-node version equals apps/web-platform/.nvmrc ($SETUP_NODE_VERSION), so it moves with the deployed Node line" \
  || fail "X3: probe node-version='$SETUP_NODE_VERSION' vs .nvmrc='$(cat "$ROOT/apps/web-platform/.nvmrc")'"

echo "guard + per-iteration check"
run_step NODE_OPTIONS="$STEP_NODE_OPTIONS"
[[ "$RC" -eq 0 && -z "$(mode)" && "$(cat "$TMP/counter")" == "5" ]] && grep -q 'passed (5/5 SUBSCRIBED)' "$TMP/log" \
  && pass "G1: control (step env applied) -> green, exactly 5 probe invocations" \
  || fail "G1: rc=$RC mode='$(mode)' runs=$(cat "$TMP/counter")"
run_step NODE_OPTIONS=
[[ "$(mode)" == "probe_contract_drift" ]] && detail | grep -q 'NODE_OPTIONS no longer removes' \
  && pass "G2: NODE_OPTIONS removed -> the precondition guard names the drift" \
  || fail "G2: mode='$(mode)'"
run_step NODE_OPTIONS= STUB_POLYFILL_SKIP_ITER=0
PROBE_RUNS="$(cat "$TMP/counter")"; PROBE_RUNS="${PROBE_RUNS:-0}"
[[ "$PROBE_RUNS" == "0" && "$(mode)" == "probe_contract_drift" ]] \
  && pass "G3: the guard fails closed BEFORE any probe run (0 probe invocations)" \
  || fail "G3: probe ran $PROBE_RUNS time(s) after a failed guard"
G4_OK=1
for k in 1 2 3 4 5; do
  run_step NODE_OPTIONS="$STEP_NODE_OPTIONS" STUB_POLYFILL_SKIP_ITER="$k"
  [[ "$(mode)" == "probe_contract_drift" ]] && detail | grep -q "Run $k/5" && detail | grep -q "no 'polyfill: applied'" \
    && [[ "$(cat "$TMP/counter")" == "$k" ]] \
    || { G4_OK=0; echo "    G4 iteration $k: mode='$(mode)' detail='$(detail)'"; }
done
[[ "$G4_OK" == 1 ]] \
  && pass "G4: a missing polyfill line in ANY iteration (1..5) -> drift naming that run, and the loop stops there" \
  || fail "G4: per-iteration check missed an iteration (see above)"
run_step NODE_OPTIONS="--no-experimental-websocket --max-old-space-size=512"
[[ "$RC" -eq 0 && -z "$(mode)" ]] && grep -q 'passed (5/5 SUBSCRIBED)' "$TMP/log" \
  && pass "G5: a non-canonical NODE_OPTIONS that still removes the global stays green (5/5)" \
  || fail "G5: rc=$RC mode='$(mode)'"
run_step NODE_OPTIONS="$STEP_NODE_OPTIONS" STUB_NODE_REJECT=1
[[ "$RC" -eq 0 && "$(mode)" == "probe_contract_drift" ]] && detail | grep -q 'unavailable' \
  && pass "G6: node rejecting the option -> drift recorded and the output still written (no step abort)" \
  || fail "G6: rc=$RC mode='$(mode)'"

run_step NODE_OPTIONS="$STEP_NODE_OPTIONS" STUB_NODE_WARN=1
[[ "$RC" -eq 0 && -z "$(mode)" ]] && grep -q 'passed (5/5 SUBSCRIBED)' "$TMP/log" \
  && pass "G7: a healthy 'undefined' with a Node warning on stderr is NOT read as drift (stdout only)" \
  || fail "G7: rc=$RC mode='$(mode)'"
run_step NODE_OPTIONS="$STEP_NODE_OPTIONS"
[[ -s "$TMP/token_seen" && -z "$(cat "$TMP/token_seen")" ]] \
  && pass "G8: the typeof guard's node ran, and without DOPPLER_TOKEN in its environment" \
  || fail "G8: DOPPLER_TOKEN reached the guard's node ('$(cat "$TMP/token_seen")')"

echo "classification"
run_step NODE_OPTIONS="$STEP_NODE_OPTIONS" STUB_DOPPLER_DOWN=1
[[ "$(mode)" == "realtime_join_timeout" && "$(wc -l < "$TMP/doppler_runs")" -eq 1 ]] \
  && pass "C1: a Doppler outage that never reaches the script stays realtime_join_timeout, not drift, and stops at run 1" \
  || fail "C1: mode='$(mode)' doppler_runs=$(wc -l < "$TMP/doppler_runs")"

# Helper self-test: drive both helpers once and require both to count, then unwind the failure
# so the verdict stays honest (precedent: registry-host-replace-dispatch-verdict.test.sh).
_cp=$PASS; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting; every verdict above is void.\n' >&2; exit 2
fi
unset 'FAILURES[-1]'

# Floor: the count is derived from the assertions above and sits adjacent to its `if`; it is
# reported with printf + exit directly, never through pass()/fail(), so silencing the helpers
# cannot silence it.
MIN_ASSERTIONS=13
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion-count floor: only %s assertions passed (floor %s)\n' "$PASS" "$MIN_ASSERTIONS"
  exit 1
fi

echo "scheduled-realtime-probe-guard.test.sh: $PASS passed, ${#FAILURES[@]} failed"
exit $(( ${#FAILURES[@]} > 0 ))
