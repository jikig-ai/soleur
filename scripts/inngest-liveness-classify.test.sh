#!/usr/bin/env bash
# Unit tests for scripts/inngest-liveness-classify.sh (#6374, Defect 2 deploy-race
# tolerance). The external inngest health watchdog classifies the liveness-probe
# response WITHOUT the LLM/network in the assertion path: given an HTTP code + body,
# it must distinguish a genuine inngest_down (restart) from a broken/undeployed probe
# path (probe_unavailable — NO restart), and grace a cold-start empty registry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/inngest-liveness-classify.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== inngest-liveness-classify.sh tests ==="

# Healthy: 200 + a functions array with >=1 entry.
assert_eq "200 + functions array (>=1) → healthy" "healthy" \
  "$(classify_liveness_mode 200 '{"functions":["cron-a","cron-b"],"event_names":[],"armed_reminders":[],"durability_state":"durable"}')"

# Cold-start grace: 200 + empty functions array (transient post-restart).
assert_eq "200 + empty functions array → cold_start (grace, not immediate unhealthy)" "cold_start" \
  "$(classify_liveness_mode 200 '{"functions":[],"event_names":[],"armed_reminders":[],"durability_state":"durable"}')"

# 200 but no .functions array (malformed/proxy body) → unhealthy (restart family).
assert_eq "200 + object without .functions → inngest_unhealthy" "inngest_unhealthy" \
  "$(classify_liveness_mode 200 '{"status":"weird"}')"
assert_eq "200 + non-JSON body → inngest_unhealthy" "inngest_unhealthy" \
  "$(classify_liveness_mode 200 'not json at all')"

# Genuine down: the script ran and its functions query failed → FATAL sentinel body,
# regardless of the surrounding HTTP code the webhook assigns (500).
assert_eq "500 + inventory FATAL sentinel → inngest_down (restart)" "inngest_down" \
  "$(classify_liveness_mode 500 'inngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=[connection refused]); is inngest-server.service up?')"

# #6407 Defect A: a TRANSIENT functions-query failure corroborated by loopback /health=200
# yields the DEGRADED sentinel (inngest-server is serving; the /v0/gql read blipped). Must
# classify functions_query_degraded — a SOFT mode, NO restart (distinct from inngest_down).
assert_eq "500 + inventory DEGRADED sentinel → functions_query_degraded (soft, NO restart)" "functions_query_degraded" \
  "$(classify_liveness_mode 500 'inngest-inventory: DEGRADED /v0/gql functions query transiently unreachable but /health=200 (errors=[__FETCH_FAILED__]) — soft, no restart')"

# #6407 review F1 (security-sentinel): the sentinel match is ANCHORED to line-start, so an
# untrusted (errors=...) payload embedded in the FATAL line that happens to CONTAIN the literal
# substring "inngest-inventory: DEGRADED" must NOT downgrade a genuine hard-down to soft. Under
# the pre-fix unanchored `grep -F` this classified functions_query_degraded (no restart → a
# wedged inngest masked); anchored ^ it correctly stays inngest_down. Non-vacuous regression.
assert_eq "FATAL line whose errors payload embeds the DEGRADED substring → inngest_down (anchored, not masked)" "inngest_down" \
  "$(classify_liveness_mode 500 'inngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=["backend said inngest-inventory: DEGRADED once"]); is inngest-server.service up?')"

# #6921/#8077: op=quiesce-web leaves the web unit inactive|failed + disabled; inngest-inventory.sh
# then prints the QUIESCED sentinel instead of FATAL. It is a DELIBERATE state — never restart.
assert_eq "500 + QUIESCED sentinel → inngest_quiesced (no restart)" "inngest_quiesced" \
  "$(classify_liveness_mode 500 'inngest-inventory: QUIESCED host_id=soleur-web-1 unit=inactive enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart')"

# Anchored: a FATAL line whose untrusted errors payload embeds the QUIESCED substring must stay
# a genuine down (an unanchored match would mask a wedged scheduler as deliberate → no restart).
assert_eq "FATAL line embedding QUIESCED → inngest_down (anchored)" "inngest_down" \
  "$(classify_liveness_mode 500 'inngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=["x inngest-inventory: QUIESCED host_id=y"]); is inngest-server.service up?')"

# Must-PASS non-canonical: trailing diagnostic text, a different host_id and the post-SIGKILL
# `unit=failed` form still classify quiesced.
assert_eq "QUIESCED with trailing text + different host_id → inngest_quiesced" "inngest_quiesced" \
  "$(classify_liveness_mode 503 'inngest-inventory: QUIESCED host_id=soleur-web-9 unit=failed enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart (extra diagnostic tail: health_code=000)')"

# Review-fix contract §4/§8: the QUIESCED line now carries quiesced_since/capture/rebooted fields.
assert_eq "503 + contract-§4 QUIESCED line (quiesced_since/capture/rebooted) → inngest_quiesced" "inngest_quiesced" \
  "$(classify_liveness_mode 503 'inngest-inventory: QUIESCED host_id=soleur-web-1 unit=inactive enabled=disabled quiesced_since=1789000000 capture=present rebooted_since_quiesce=false — deliberate stop+disable (op=quiesce-web); no restart')"

# DISABLED_UNATTRIBUTED: the quiesced shape with no valid marker — an alarm (op=rollback), not a quiesce.
assert_eq "503 + DISABLED_UNATTRIBUTED sentinel → inngest_disabled_unattributed" "inngest_disabled_unattributed" \
  "$(classify_liveness_mode 503 'inngest-inventory: DISABLED_UNATTRIBUTED host_id=soleur-web-1 unit=inactive enabled=disabled — scheduler disabled with no valid quiesce marker; not a deliberate quiesce; dispatch op=rollback')"
assert_eq "FATAL line embedding DISABLED_UNATTRIBUTED → inngest_down (anchored)" "inngest_down" \
  "$(classify_liveness_mode 500 'inngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=["x inngest-inventory: DISABLED_UNATTRIBUTED host_id=y"]); is inngest-server.service up?')"

# Per-LINE anchoring on a multi-line body (the webhook returns stdout+stderr combined): a sentinel on
# line 2 still classifies; the same sentinel mid-line inside a non-FATAL 503 body does not.
ML_Q=$'<!-- proxy preamble -->\ninngest-inventory: QUIESCED host_id=h unit=failed enabled=disabled quiesced_since=1789000000 capture=absent rebooted_since_quiesce=true — deliberate stop+disable (op=quiesce-web); no restart\nQUIESCED: host_id=h'
assert_eq "multi-line body, QUIESCED sentinel on line 2 → inngest_quiesced" "inngest_quiesced" "$(classify_liveness_mode 503 "$ML_Q")"
ML_U=$'Service Unavailable\ninngest-inventory: DISABLED_UNATTRIBUTED host_id=h unit=inactive enabled=disabled — scheduler disabled with no valid quiesce marker; not a deliberate quiesce; dispatch op=rollback'
assert_eq "multi-line body, DISABLED_UNATTRIBUTED sentinel on line 2 → inngest_disabled_unattributed" "inngest_disabled_unattributed" "$(classify_liveness_mode 503 "$ML_U")"
assert_eq "503 body with the QUIESCED sentinel MID-line (not FATAL) → probe_unavailable" "probe_unavailable" \
  "$(classify_liveness_mode 503 $'Service Unavailable\nupstream said inngest-inventory: QUIESCED host_id=h unit=inactive enabled=disabled')"
assert_eq "503 body with the DISABLED_UNATTRIBUTED sentinel MID-line (not FATAL) → probe_unavailable" "probe_unavailable" \
  "$(classify_liveness_mode 503 $'Service Unavailable\nupstream said inngest-inventory: DISABLED_UNATTRIBUTED host_id=h')"
# 200 never reads sentinels: a JSON verdict body wins even if a sentinel line trails it.
assert_eq "200 + functions array with a trailing QUIESCED line → inngest_unhealthy (200 parses JSON only)" "inngest_unhealthy" \
  "$(classify_liveness_mode 200 $'{"functions":["a"]}\ninngest-inventory: QUIESCED host_id=h')"
# Herestring, not `printf | grep -q`: under the watchdog's `set -o pipefail` an early-exiting
# `grep -q` SIGPIPEs the printf on a body larger than the pipe buffer, the pipeline reports 141,
# and a genuine sentinel on line 1 falls through to probe_unavailable. (This suite runs pipefail.)
BIG_TAIL="$(head -c 300000 /dev/zero | tr '\0' 'x')"
assert_eq "300 kB body, FATAL sentinel on line 1, pipefail on → inngest_down (no SIGPIPE fall-through)" "inngest_down" \
  "$(classify_liveness_mode 500 "inngest-inventory: FATAL host_id=h x"$'\n'"$BIG_TAIL")"
assert_eq "300 kB body, QUIESCED sentinel on line 1, pipefail on → inngest_quiesced" "inngest_quiesced" \
  "$(classify_liveness_mode 503 "inngest-inventory: QUIESCED host_id=h unit=inactive enabled=disabled"$'\n'"$BIG_TAIL")"
# Precedence on a (script-impossible) two-sentinel body: the alarm-bearing verdict wins.
assert_eq "two sentinel lines FATAL + QUIESCED → inngest_down (alarm wins)" "inngest_down" \
  "$(classify_liveness_mode 503 $'inngest-inventory: QUIESCED host_id=h unit=inactive enabled=disabled\ninngest-inventory: FATAL host_id=h x')"
assert_eq "two sentinel lines QUIESCED + DISABLED_UNATTRIBUTED → inngest_disabled_unattributed (alarm wins)" "inngest_disabled_unattributed" \
  "$(classify_liveness_mode 503 $'inngest-inventory: QUIESCED host_id=h unit=inactive enabled=disabled\ninngest-inventory: DISABLED_UNATTRIBUTED host_id=h unit=inactive enabled=disabled')"

# Deploy race / broken probe path: non-200 WITHOUT our FATAL sentinel — the hook is
# not deployed yet (404), CF-Access/webhook.service degrade (403/000), gateway 5xx.
# Must be probe_unavailable → NO restart (closes the relocated false-positive).
assert_eq "404 (hook not deployed yet) → probe_unavailable (NO restart)" "probe_unavailable" \
  "$(classify_liveness_mode 404 'hook not found')"
assert_eq "000 (connection refused / webhook.service down) → probe_unavailable" "probe_unavailable" \
  "$(classify_liveness_mode 000 '')"
assert_eq "403 (CF-Access interstitial) → probe_unavailable" "probe_unavailable" \
  "$(classify_liveness_mode 403 '<html>Cloudflare Access</html>')"
assert_eq "502 gateway (no FATAL sentinel) → probe_unavailable" "probe_unavailable" \
  "$(classify_liveness_mode 502 'Bad Gateway')"

# Restart-family predicate: down + unhealthy dispatch; probe_unavailable + cold_start + healthy do not.
assert_eq "is_restart_family inngest_down → yes" "yes" "$(is_restart_family inngest_down && echo yes || echo no)"
assert_eq "is_restart_family inngest_unhealthy → yes" "yes" "$(is_restart_family inngest_unhealthy && echo yes || echo no)"
assert_eq "is_restart_family probe_unavailable → no" "no" "$(is_restart_family probe_unavailable && echo yes || echo no)"
# #6407: functions_query_degraded is SOFT — excluded from the restart family (no churn).
assert_eq "is_restart_family functions_query_degraded → no" "no" "$(is_restart_family functions_query_degraded && echo yes || echo no)"
# #8077: the deliberate quiesce is never remediated by the watchdog.
assert_eq "is_restart_family inngest_quiesced → no" "no" "$(is_restart_family inngest_quiesced && echo yes || echo no)"
assert_eq "is_restart_family inngest_disabled_unattributed → no (op=rollback, not a restart)" "no" "$(is_restart_family inngest_disabled_unattributed && echo yes || echo no)"
assert_eq "is_restart_family cold_start → no" "no" "$(is_restart_family cold_start && echo yes || echo no)"
assert_eq "is_restart_family healthy → no" "no" "$(is_restart_family healthy && echo yes || echo no)"

echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact assertion floor: a deleted or skipped row changes the dispatched count.
readonly EXPECTED_ASSERTIONS=34
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf '  FAIL: dispatched %s assertions, expected exactly %s — a row was added, removed or skipped\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS"
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
