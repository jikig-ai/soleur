#!/usr/bin/env bash
# inngest-liveness-classify.sh — pure classifier for the external inngest liveness
# probe response (#6374, Defect 2). SOURCED by .github/workflows/scheduled-inngest-health.yml
# (the probe step) AND by scripts/inngest-liveness-classify.test.sh. No network, no side
# effects: given an HTTP code + response body it echoes exactly one mode token.
#
# WHY (deploy-race tolerance, the #6374 relocated-false-positive fix): the consumer (the
# repointed workflow) goes live at merge, but the producer (the /hooks/inngest-liveness
# hook) lands async via the infra-config push. A */15 tick in that window — or a
# CF-Access / webhook.service degrade — returns 404/000/403 with NO body from our script.
# That MUST classify probe_unavailable (a soft alert, NO restart), NOT inngest_down (which
# would churn a healthy scheduler — the exact #6374 harm). Only a body we RECOGNISE as
# coming from inngest-inventory.sh (a 200 JSON verdict, or the FATAL sentinel it prints
# when the functions query fails) declares a real inngest state.
#
# Modes:
#   healthy            200 + a JSON object whose .functions is a non-empty array
#   cold_start         200 + .functions is an EMPTY array (transient post-restart — the
#                      caller graces/retries before declaring inngest_unhealthy)
#   inngest_unhealthy  200 but no .functions array (malformed / proxy body) — restart family
#   inngest_down       any code + the inngest-inventory.sh FATAL sentinel (functions query
#                      failed AND loopback /health != 200 → wedged/down) — restart family
#   functions_query_degraded  any code + the inngest-inventory.sh DEGRADED sentinel (the
#                      /v0/gql functions read transiently failed but loopback /health=200 →
#                      inngest-server IS serving; #6407) — SOFT, NO restart, own soft issue
#                      class. A sustained degraded state escalates to inngest_down in the
#                      watchdog (persistence-escalation ceiling), not here.
#   probe_unavailable  non-200 WITHOUT our FATAL/DEGRADED sentinel (404 undeployed hook, 000
#                      conn refused, 403 CF-Access, gateway 5xx) — soft alert, NO restart

# $1 = HTTP status code (string; "000" for a curl transport failure), $2 = response body.
classify_liveness_mode() {
  local code="$1" body="$2"
  if [[ "$code" == "200" ]]; then
    if printf '%s' "$body" | jq -e 'type == "object" and (.functions | type == "array")' >/dev/null 2>&1; then
      local fn
      fn=$(printf '%s' "$body" | jq -r '.functions | length' 2>/dev/null || echo 0)
      if [[ "$fn" == "0" ]]; then echo "cold_start"; else echo "healthy"; fi
    else
      echo "inngest_unhealthy"
    fi
    return 0
  fi
  # Non-200. Our script prints one of two distinct sentinels when the /v0/gql functions
  # query fails (webhook wraps the non-zero exit body — include-command-output-in-response-
  # on-error). DEGRADED (checked FIRST) = functions read blipped but loopback /health=200,
  # so inngest IS serving (#6407): SOFT, no restart. FATAL = functions read failed AND
  # /health != 200 (wedged/down): restart family. The prefixes are distinct (grep -qF, no
  # shared boundary) so order is safe; DEGRADED-first documents the soft path as primary.
  if printf '%s' "$body" | grep -qF 'inngest-inventory: DEGRADED'; then
    echo "functions_query_degraded"
  elif printf '%s' "$body" | grep -qF 'inngest-inventory: FATAL'; then
    echo "inngest_down"
  else
    echo "probe_unavailable"
  fi
}

# Restart-dispatch predicate: ONLY the down family churns a restart. cold_start (grace),
# probe_unavailable (broken/undeployed probe), and healthy never restart.
is_restart_family() {
  [[ "$1" == "inngest_down" || "$1" == "inngest_unhealthy" ]]
}
