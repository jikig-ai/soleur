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
assert_eq "is_restart_family cold_start → no" "no" "$(is_restart_family cold_start && echo yes || echo no)"
assert_eq "is_restart_family healthy → no" "no" "$(is_restart_family healthy && echo yes || echo no)"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
