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
#   (the four sentinel modes below are read from NON-200 bodies only — a 200 is parsed as JSON)
#   inngest_down       non-200 + the inngest-inventory.sh FATAL sentinel (functions query
#                      failed AND loopback /health != 200 → wedged/down) — restart family
#   functions_query_degraded  non-200 + the inngest-inventory.sh DEGRADED sentinel (the
#                      /v0/gql functions read transiently failed but loopback /health=200 →
#                      inngest-server IS serving; #6407) — SOFT, NO restart, own soft issue
#                      class. A sustained degraded state escalates to inngest_down in the
#                      watchdog (persistence-escalation ceiling), not here.
#   inngest_quiesced   non-200 + the inngest-inventory.sh QUIESCED sentinel (functions query
#                      failed, /health != 200, unit inactive|failed AND disabled AND a valid
#                      op=quiesce-web marker; #6921/#8077) — deliberate, NO restart, no issue
#   inngest_disabled_unattributed  non-200 + the DISABLED_UNATTRIBUTED sentinel (the quiesced unit
#                      shape with NO valid marker, or a marker voided by a later start) — an
#                      alarm (remedy op=rollback), NOT restart family: a restart would START a
#                      disabled unit nobody attributed
#   probe_unavailable  non-200 WITHOUT one of the four sentinels at a line start (404 undeployed
#                      hook, 000 conn refused, 403 CF-Access, gateway 5xx) — soft alert, NO restart

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
  # Non-200. When the /v0/gql functions query fails, inngest-inventory.sh prints EXACTLY ONE of
  # four sentinel lines (the webhook wraps the non-zero exit body — include-command-output-in-
  # response-on-error — and appends the script's stderr lines, none of which carry the prefix):
  #   DEGRADED              functions read blipped, loopback /health=200 (#6407) — soft
  #   FATAL                 functions read failed, /health != 200, not quiesced — restart family
  #   DISABLED_UNATTRIBUTED quiesced unit shape, no valid marker (#8077) — alarm, op=rollback
  #   QUIESCED              quiesced unit shape + valid op=quiesce-web marker — deliberate
  #
  # ANCHOR each match to a LINE start (^ — grep matches per line, so a sentinel on line 2 of a
  # combined body still counts), NEVER an unanchored substring: the FATAL/DEGRADED lines embed the
  # scrubbed `(errors=<fn_errs>)` GraphQL payload, and a hard-down FATAL whose errors text CONTAINS
  # "inngest-inventory: QUIESCED" would, unanchored, mask a real down as deliberate → no restart.
  # fn_errs is newline-scrubbed by _pf_scrub, so untrusted text can never start a line.
  #
  # ORDER only matters for a body carrying two sentinel lines, which the script cannot produce.
  # DEGRADED stays first (the #6407 soft path); among the rest the alarm-bearing verdict wins —
  # FATAL, then DISABLED_UNATTRIBUTED, then QUIESCED (the only verdict that files nothing).
  #
  # HERESTRINGS, not `printf '%s' "$body" | grep -q`: the watchdog runs `set -o pipefail`, and an
  # early-exiting `grep -q` SIGPIPEs the printf on a body larger than the pipe buffer — the
  # pipeline then reports 141 and a genuine sentinel falls through to probe_unavailable.
  if grep -qE '^inngest-inventory: DEGRADED' <<<"$body"; then
    echo "functions_query_degraded"
  elif grep -qE '^inngest-inventory: FATAL' <<<"$body"; then
    echo "inngest_down"
  elif grep -qE '^inngest-inventory: DISABLED_UNATTRIBUTED' <<<"$body"; then
    echo "inngest_disabled_unattributed"
  elif grep -qE '^inngest-inventory: QUIESCED' <<<"$body"; then
    echo "inngest_quiesced"
  else
    echo "probe_unavailable"
  fi
}

# Restart-dispatch predicate: ONLY the down family churns a restart. cold_start (grace),
# probe_unavailable (broken/undeployed probe), functions_query_degraded (soft), inngest_quiesced
# (deliberate), inngest_disabled_unattributed (op=rollback alarm) and healthy never restart.
is_restart_family() {
  [[ "$1" == "inngest_down" || "$1" == "inngest_unhealthy" ]]
}
