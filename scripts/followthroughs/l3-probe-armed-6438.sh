#!/usr/bin/env bash
# Follow-through probe for #6438/#6548: are web-1's private-net probe heartbeats ARMED and GREEN
# after the measured-beat arm gate ran? (2.9.1 soak follow-through.)
#
# WHY THIS EXISTS. This feature's whole point is honesty about a signal that can ship
# GREEN-but-inert: a probe that installs, never pings, and reads as coverage while providing none
# (the #6400 shape reproduced INSIDE the monitor — ADR-117). The pre-merge ACs prove the arm gate
# is freshness-correct; they cannot prove the beat KEEPS HOLDING through the soak. The arm gate
# PATCHes `paused=false` only on a fresh measured beat and rolls back on timeout, so at merge the
# three monitors should be live `up` — but "stays armed and green after the measured beat" is a
# post-deploy close-criterion, and without enrollment that promise rests on human memory (the exact
# dependency ADR-117 exists to kill). This script is that close-criterion, mechanized — self-pulled
# from the Better Stack heartbeats API, NO ssh, NO dashboard (hr-no-dashboard-eyeball-pull-data,
# hr-no-ssh-fallback-in-runbooks; mirrors the plan's discoverability_test).
#
# Enrollment (the directive the sweeper discovers — plus the `follow-through` label on #6438):
#   <!-- soleur:followthrough script=scripts/followthroughs/l3-probe-armed-6438.sh earliest=2026-07-25T00:00:00Z secrets=BETTERSTACK_API_TOKEN -->
#
#   BETTERSTACK_API_TOKEN is the account-wide Better Stack API token (mirror of Doppler
#   soleur/prd_terraform BETTERSTACK_API_TOKEN, the same token the apply workflow's status read
#   uses). If the GH secret is not yet wired into scheduled-followthrough-sweeper.yml's env: block
#   it resolves to "" and this probe is fail-safe TRANSIENT (never a false PASS/close) until it is.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       — all three monitors are live `up` (armed + green); sweeper closes #6438
#   1 = FAIL       — a monitor EXISTS but is not `up` (paused/down/pending) — the arm rolled back or
#                    the beat regressed; a real verdict, sweeper comments + leaves open
#   2 = TRANSIENT  — token unset, API fault, or a monitor is absent/not-yet-ingested (arm not landed
#                    yet); not a data point, sweeper retries next sweep. Never closes on "not yet".

set -uo pipefail

if [[ -z "${BETTERSTACK_API_TOKEN:-}" ]]; then
  echo "TRANSIENT: BETTERSTACK_API_TOKEN is unset or empty — cannot query the Better Stack heartbeats API (declare it in the directive's secrets= clause and wire it into the sweeper env)." >&2
  exit 2
fi

API="https://uptime.betterstack.com/api/v2/heartbeats"

# The three monitors this soak must find live `up`. web_zot_consumer + web_nic_guard are per-host
# (for_each var.web_hosts), so their live names carry the web-1 suffix; git_data_prd is the shared
# beat this feature finally FEEDS (#6548). Single-host today ⇒ exactly the web-1 instances exist;
# the anti-masking per-host naming is preserved by construction for #6459 active-active-N.
TARGETS=(
  "soleur-web-zot-consumer-web-1"
  "soleur-web-nic-guard-web-1"
  "soleur-git-data-prd"
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
# the monitor is not in the payload yet (arm not landed / ingest lag ⇒ TRANSIENT, not a verdict).
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

# Absent ⇒ the arm has not landed on this monitor yet (or ingest lag). Not a data point — never a
# false FAIL on "not yet". This is the arm-gate-may-still-be-pending case, held as TRANSIENT so the
# sweeper retries rather than paging on an in-flight soak.
if (( ${#MISSING[@]} > 0 )); then
  echo "TRANSIENT: ${#MISSING[@]} monitor(s) not yet present in Better Stack — the measure-then-arm gate has not created/armed them yet, or ingest is lagging. [${SUMMARY}]" >&2
  exit 2
fi

# All three exist. If any is not `up`, the beat did NOT hold: the arm rolled back on a withheld
# ping, or a monitor regressed to down/paused during the soak. That is a real, loud verdict — the
# soak-close criterion is definitively not met — so FAIL, not a silent retry.
if (( ${#NOT_UP[@]} > 0 )); then
  echo "FAIL: soak criterion not met — ${NOT_UP[*]} is/are not \`up\`. The probe is inert or the arm rolled back (a GREEN-but-inert monitor is the #6400 shape this feature exists to kill — ADR-117). Diagnose: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh, and check the apply workflow's arm-gate step for a rolled-back PATCH. [${SUMMARY}]"
  exit 1
fi

echo "PASS: all three private-net probe heartbeats are armed + green (up): ${SUMMARY}. The measured beat holds — #6438/#6548's soak-close criterion is met."
exit 0
