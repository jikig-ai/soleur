#!/usr/bin/env bash
# Follow-through soak for #6459 (ADR-142): is the fresh cattle web-2 out-of-band standby HEALTHY —
# not a dark host — after it is born via the gated dispatch? (Phase 4.3 soak; AC14 + AC15.)
#
# WHY THIS EXISTS. web-2 is an out-of-band standby (serving-weight 0, no ingress): it serves NO
# user traffic pre-flip, so nothing user-facing would notice if it booted silently unhealthy — the
# exact #6538 "dark host" regression this cluster work exists to prevent (a host shipping zero
# telemetry that reads as coverage while providing none). The pre-merge ACs prove the cattle
# cloud-init parity + the fresh-boot readiness marker CODE is present; they cannot prove web-2
# actually STAYS healthy across the soak. This script is that close-criterion, mechanized —
# self-pulled from the Better Stack heartbeats API, NO ssh, NO dashboard (hr-no-dashboard-eyeball-
# pull-data, hr-no-ssh-fallback-in-runbooks; mirrors the plan's discoverability_test).
#
# web-2's two per-host OUTBOUND heartbeats (web-probe.tf, for_each var.web_hosts) ARE the AC9 /
# ADR-142 R1 out-of-band health composite: a dark web-2 goes silent → the heartbeat's Better Stack
# absence alert fires, and this soak reads that same signal to a PASS/FAIL close-criterion.
#
# Enrollment (the directive the sweeper discovers — plus the `follow-through` label on #6459):
#   <!-- soleur:followthrough script=scripts/followthroughs/web2-standby-soak-6459.sh earliest=<web-2-birth+7d> secrets=BETTERSTACK_API_TOKEN -->
#
#   earliest= is set to (web-2 birth dispatch date + 7 days): the N=7d soak (plan 4.3) can only be
#   judged once web-2 has been out-of-band healthy for a full week. Until web-2 is born (its birth
#   is a post-merge gated workflow_dispatch), its monitors are ABSENT → TRANSIENT, so the sweeper
#   holds without a false PASS/FAIL. BETTERSTACK_API_TOKEN (account-wide) is already wired into
#   scheduled-followthrough-sweeper.yml (l3-probe-armed-6438.sh shares it); if unset it resolves to
#   "" and this probe is fail-safe TRANSIENT (never a false PASS/close).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       — both web-2 monitors are live `up` (armed + green); the standby is healthy, not
#                    dark; sweeper closes #6459.
#   1 = FAIL       — a web-2 monitor EXISTS but is not `up` (paused/down/pending) — web-2 booted or
#                    drifted DARK (the #6538 regression). A real verdict; comments + leaves open.
#   2 = TRANSIENT  — token unset, API fault, or a web-2 monitor is ABSENT/not-yet-ingested (web-2 not
#                    born yet, or ingest lag). Not a data point; sweeper retries. Never a false PASS.

set -uo pipefail

if [[ -z "${BETTERSTACK_API_TOKEN:-}" ]]; then
  echo "TRANSIENT: BETTERSTACK_API_TOKEN is unset or empty — cannot query the Better Stack heartbeats API (declare it in the directive's secrets= clause and wire it into the sweeper env)." >&2
  exit 2
fi

API="https://uptime.betterstack.com/api/v2/heartbeats"

# web-2's two per-host heartbeats. web-probe.tf names them soleur-web-<probe>-${each.key}, so the
# web-2 instances carry the web-2 suffix. The anti-masking per-host naming (web-probe.tf:10-15)
# guarantees a healthy web-1 can never mask a dark web-2 — this soak reads ONLY the web-2 monitors.
TARGETS=(
  "soleur-web-zot-consumer-web-2"
  "soleur-web-nic-guard-web-2"
)

# Pull the full heartbeats page once. A non-200 / unexpected shape is a probe fault, never a
# verdict — do NOT default a missing .data to empty (a defaulted 0 reads as "monitor absent" on
# what is really an auth/transport failure, the same false-DARK trap the probes it guards avoid).
RESP="$(curl -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer ${BETTERSTACK_API_TOKEN}" -H "Accept: application/json" \
  "$API" 2>/dev/null)"
STATUS="$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')"
BODY="$(printf '%s' "$RESP" | sed '$d')"

if [[ "$STATUS" != "200" ]]; then
  echo "TRANSIENT: Better Stack heartbeats API returned HTTP ${STATUS:-000} — probe fault, not a verdict. Retry next sweep." >&2
  exit 2
fi

if ! printf '%s' "$BODY" | jq -e 'if (.data | type) == "array" then true else error("no data array") end' >/dev/null 2>&1; then
  echo "TRANSIENT: heartbeats API payload had no .data array (unexpected shape) — probe fault, not a verdict." >&2
  exit 2
fi

# Look each target up by its exact name. jq emits the status, or the literal ABSENT sentinel when
# the monitor is not in the payload yet (web-2 not born / ingest lag ⇒ TRANSIENT, not a verdict).
lookup_status() {
  local name="$1"
  printf '%s' "$BODY" | jq -r --arg n "$name" \
    'first(.data[]? | select(.attributes.name == $n) | .attributes.status) // "ABSENT"' 2>/dev/null
}

declare -a NOT_UP=()
declare -a MISSING=()
declare -a REPORT=()
for name in "${TARGETS[@]}"; do
  st="$(lookup_status "$name")"
  [[ -z "$st" ]] && st="ABSENT"
  REPORT+=("${name}=${st}")
  if [[ "$st" == "ABSENT" ]]; then
    MISSING+=("$name")
  elif [[ "$st" != "up" ]]; then
    NOT_UP+=("${name}(${st})")
  fi
done

SUMMARY="${REPORT[*]}"

# Absent ⇒ web-2 has not been born yet (its birth is a post-merge gated dispatch), or ingest lag.
# Not a data point — never a false FAIL on "not yet". Held as TRANSIENT so the sweeper retries.
if (( ${#MISSING[@]} > 0 )); then
  echo "TRANSIENT: ${#MISSING[@]} web-2 monitor(s) not yet present in Better Stack — web-2 has not been born (its birth is a gated workflow_dispatch), or ingest is lagging. [${SUMMARY}]" >&2
  exit 2
fi

# Both exist. If any is not `up`, web-2 is DARK: it booted or drifted unhealthy during the soak.
# That is a real, loud verdict — the standby is not healthy — so FAIL, not a silent retry.
if (( ${#NOT_UP[@]} > 0 )); then
  echo "FAIL: soak criterion not met — ${NOT_UP[*]} is/are not \`up\`. web-2 is a DARK host (booted or drifted unhealthy, the #6538 regression). Diagnose: bash scripts/betterstack-query.sh \"host:soleur-web-2 | count\" and check web-2's SOLEUR_FRESH_BOOT_READY marker in Better Stack. [${SUMMARY}]"
  exit 1
fi

echo "PASS: both web-2 out-of-band heartbeats are armed + green (up): ${SUMMARY}. web-2 has soaked N=7d healthy (not dark) — ADR-142 Phase 4.3 soak-close criterion met (#6459)."
exit 0
