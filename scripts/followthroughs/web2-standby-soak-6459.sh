#!/usr/bin/env bash
# Follow-through soak for #6459 (ADR-143): is the fresh cattle web-2 out-of-band standby HEALTHY —
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
# ADR-143 R1 out-of-band health composite: a dark web-2 goes silent → the heartbeat's Better Stack
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
#   1 = FAIL       — a web-2 monitor EXISTS and is in a genuinely-DOWN status (down / validation-
#                    failed) — web-2 booted or drifted DARK (the #6538 regression). A real verdict.
#   2 = TRANSIENT  — token unset, API fault, OR a web-2 monitor is not yet a data point: ABSENT (not
#                    born / ingest lag / on an unfetched page), OR `paused`/`pending` (BORN but the
#                    apply arm-gate has not unpaused it yet — for_each creates monitors `paused`, so
#                    the born-but-arming window reads paused/pending, NEVER ABSENT). Sweeper retries;
#                    never a false PASS. NOTE: paused/pending is TRANSIENT (not FAIL) precisely so a
#                    healthy-but-unarmed web-2 is not certified DARK — see the ARMING branch below.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so BETTERSTACK_API_TOKEN would be printed in full the moment it is
# bound -- which is exactly how two live tokens reached an agent transcript.
# `$-` is the load-bearing arm: bash applies an env-supplied SHELLOPTS or
# BASH_ENV before line 1, so `x` is already set by the time this runs. Do not
# delete it. Tracing stays available with the credential unset, so this refuses
# a leak without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with BETTERSTACK_API_TOKEN set (see #7797). Re-run with BETTERSTACK_API_TOKEN= to trace safely.\n' >&2
      exit 78
    fi
    ;;
esac

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

# Pagination guard: this fetches page 1 only. Today the account is well under one page (~50/page), so
# `.pagination.next` is null. If the monitor count ever crosses a page boundary (active-active-N, more
# infra beats), a web-2 monitor could land on page 2 → this page reads it ABSENT and a genuinely-DARK
# web-2 would be mis-read as not-born → TRANSIENT-forever (dark-masking). Fail-safe: if a next page
# exists AND we do not observe both targets here, hold TRANSIENT with a paginate-me signal rather than
# concluding ABSENT. (Never a false PASS either way; PASS still requires both monitors present + `up`.)
NEXT="$(printf '%s' "$BODY" | jq -r '.pagination.next // empty' 2>/dev/null)"

# Look each target up by its exact name. jq emits the status, or the literal ABSENT sentinel when
# the monitor is not in the payload yet (web-2 not born / ingest lag ⇒ TRANSIENT, not a verdict).
lookup_status() {
  local name="$1"
  printf '%s' "$BODY" | jq -r --arg n "$name" \
    'first(.data[]? | select(.attributes.name == $n) | .attributes.status) // "ABSENT"' 2>/dev/null
}

declare -a NOT_UP=()
declare -a MISSING=()
declare -a ARMING=()   # paused / pending — born but not yet armed/pinging; TRANSIENT, not DARK
declare -a REPORT=()
for name in "${TARGETS[@]}"; do
  st="$(lookup_status "$name")"
  [[ -z "$st" ]] && st="ABSENT"
  REPORT+=("${name}=${st}")
  case "$st" in
    ABSENT)         MISSING+=("$name") ;;
    up)             : ;;                              # healthy
    paused|pending) ARMING+=("${name}(${st})") ;;     # born, not yet armed by the apply arm-gate
    *)              NOT_UP+=("${name}(${st})") ;;      # down / validation-failed / … → genuinely DARK
  esac
done

SUMMARY="${REPORT[*]}"

# Absent ⇒ web-2 has not been born yet (its birth is a post-merge gated dispatch), or ingest lag,
# OR (if a next page exists) the monitor is on a page we did not fetch. Not a data point — never a
# false FAIL on "not yet". Held as TRANSIENT so the sweeper retries.
if (( ${#MISSING[@]} > 0 )); then
  if [[ -n "$NEXT" ]]; then
    echo "TRANSIENT: ${#MISSING[@]} web-2 monitor(s) not on heartbeats page 1 AND a next page exists — cannot conclude ABSENT (monitor may be on a later page). PAGINATE this probe before trusting an ABSENT verdict. [${SUMMARY}]" >&2
  else
    echo "TRANSIENT: ${#MISSING[@]} web-2 monitor(s) not yet present in Better Stack — web-2 has not been born (its birth is a gated workflow_dispatch), or ingest is lagging. [${SUMMARY}]" >&2
  fi
  exit 2
fi

# paused/pending ⇒ the monitor is born but the apply workflow's arm-gate has not unpaused it yet.
# web-2's heartbeats are created `paused=true` (web-probe.tf ignore_changes=[paused]); the arm-gate
# ("Arm web-host probe heartbeats" in apply-web-platform-infra.yml) is the ONLY unpause path. A
# for_each monitor is created `paused`, NEVER `ABSENT`, so the born-but-arming window reads
# paused/pending — this is NOT a dark host. Hold TRANSIENT (never a false DARK FAIL) so the sweeper
# retries until the arm-gate lands. Distinct from ABSENT (not born) and a genuinely-down status (DARK).
if (( ${#ARMING[@]} > 0 )); then
  echo "TRANSIENT: ${#ARMING[@]} web-2 monitor(s) present but not yet ARMED — ${ARMING[*]} (created paused; the apply arm-gate unpauses them). Retrying next sweep — NOT a DARK verdict. [${SUMMARY}]" >&2
  exit 2
fi

# Both exist. If any is not `up`, web-2 is DARK: it booted or drifted unhealthy during the soak.
# That is a real, loud verdict — the standby is not healthy — so FAIL, not a silent retry.
if (( ${#NOT_UP[@]} > 0 )); then
  echo "FAIL: soak criterion not met — ${NOT_UP[*]} is/are not \`up\`. web-2 is a DARK host (booted or drifted unhealthy, the #6538 regression). Diagnose: bash scripts/betterstack-query.sh \"host:soleur-web-2 | count\" and check web-2's SOLEUR_FRESH_BOOT_READY marker in Better Stack. [${SUMMARY}]"
  exit 1
fi

echo "PASS: both web-2 out-of-band heartbeats are armed + green (up): ${SUMMARY}. web-2 has soaked N=7d healthy (not dark) — ADR-143 Phase 4.3 soak-close criterion met (#6459)."
exit 0
