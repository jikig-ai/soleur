#!/usr/bin/env bash
# Follow-through soak for #6604 — the /workspaces LUKS cutover (ADR-119). Source: the #6604 infra PR.
#
# READ-ONLY, verify-completion (DP-4). The sweeper runs this under `env -i` with ONLY the directive's
# declared secrets (no GH_TOKEN, no DOPPLER_TOKEN) and contents:read + issues:write, so it CANNOT run
# the irreversible wipe, `state rm`, or open PR 3 — that rides a SEPARATE environment-gated dispatch
# authorized by a human who saw the soak pass. This script only OBSERVES.
#
# CLOSE CRITERION IS "THE WHOLE CUTOVER IS DONE", NOT "the soak window elapsed". The elegant,
# sweeper-reachable completion signal is ADR-119 `status: accepted` in the checkout (contents:read):
# per the Phase-5 sequencing, the ADR flips adopting→accepted ONLY by the destructive dispatch AFTER
# the wipe + convergence + PR 3. So `accepted` on main is a downstream, file-observable proxy that all
# the destructive work happened — it cannot false-close before the wipe (the ADR is still `adopting`).
#
# DP-5 — the elapsed floor is INTERNAL and derived from OBSERVED heartbeat rows spanning ≥7d, never
# the directive's `earliest=` (a literal `<canary+7d>` placeholder parses to epoch 0 and would open
# the gate on day 0). A day-0 sweep therefore cannot PASS even if the directive is mis-filled.
#
# The parent soak could never go RED (query matched zero unconditionally, no positive control,
# earliest= placeholder). This one:
#   - status-checks the Sentry API FIRST (non-200 ⇒ TRANSIENT exit 2, never a false PASS on auth-zero);
#   - gates on the luks-monitor heartbeat being PRESENT (a dead probe FAILS, not silently passes);
#   - requires the heartbeat rows to SPAN ≥7d (the internal floor).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (drift=0 ∧ heartbeat spans ≥7d ∧ ADR-119 accepted → the cutover is complete; close)
#   1 = FAIL       (still soaking, OR "SOAK PASSED — wipe authorized" but not yet observed complete)
#   * = TRANSIENT  (Sentry/Better Stack unreachable, auth/parse failure — retry next sweep)
#
# Required env (declared in the tracker directive's secrets=): SENTRY_AUTH_TOKEN,
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ADR="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md"
SOAK_DAYS="${WORKSPACES_LUKS_SOAK_DAYS:-7}"

# Explicit empty-checks, NOT ${VAR:?} (which aborts status 1 = FAIL, the opposite of TRANSIENT).
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_AUTH_TOKEN not set" >&2; exit 2; fi
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then echo "TRANSIENT: $v not set" >&2; exit 2; fi
done

# ---- 1. Sentry: ZERO op:workspaces-luks-drift events (status-checked FIRST) --------------------
ORG="jikigai-eu"
SENTRY_API="https://sentry.io/api/0"
# feature/op are the tags workspaces-luks-emit.sh sets; statsPeriod=7d rolling window.
QUERY='feature:"workspaces-luks" op:"workspaces-luks-drift"'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="${SENTRY_API}/organizations/${ORG}/events/?query=${QUERY_ENC}&statsPeriod=${SOAK_DAYS}d&per_page=10&field=title&field=timestamp"
RESP=$(curl -sS -w '\nHTTP_STATUS:%{http_code}' -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" -H "Accept: application/json" "$URL")
HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')
if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS (never a false PASS on an auth failure)" >&2
  printf '%s\n' "$BODY" | head -c 400 >&2
  exit 2
fi
DRIFT=$(printf '%s' "$BODY" | jq -r '.data | length // 0' 2>/dev/null)
if ! [[ "$DRIFT" =~ ^[0-9]+$ ]]; then echo "TRANSIENT: could not parse Sentry event count" >&2; exit 2; fi
if [[ "$DRIFT" -ne 0 ]]; then
  echo "FAIL: ${DRIFT} workspaces-luks-drift Sentry event(s) in the ${SOAK_DAYS}d window — the at-rest volume drifted; do NOT authorize the wipe."
  printf '%s' "$BODY" | jq -r '.data[] | "  - \(.title) @ \(.timestamp)"' | head -5
  exit 1
fi

# ---- 2. Better Stack: the luks-monitor heartbeat is PRESENT and SPANS ≥ SOAK_DAYS (DP-5) -------
# Positive control: a probe that never emitted a SUCCESS line leaves ZERO OK rows ⇒ FAIL (the parent
# could never go RED). The archive arm gives the real multi-day span (NOT --no-archive, the ~40-min
# hot window). NOTE the count/span filter to the probe's `OK:` SUCCESS line (luks-monitor.sh logs
# `OK: /mnt/data is LUKS-backed …` only on a fully-green run) — NOT the bare `luks-monitor` tag, which
# also matches the `FAIL (...)` lines: a probe that runs daily but fails every assert would otherwise
# satisfy this "heartbeat present" gate.
BS_OUT=$(SINCE="${SOAK_DAYS}d" "$SCRIPT_DIR/../betterstack-query.sh" --since "${SOAK_DAYS}d" --grep 'luks-monitor' 2>/dev/null)
BS_RC=$?
if [[ "$BS_RC" -ne 0 ]]; then
  echo "TRANSIENT: Better Stack query failed (rc=$BS_RC) — cannot confirm the heartbeat is live" >&2
  exit 2
fi
OK_ROWS=$(printf '%s\n' "$BS_OUT" | grep 'luks-monitor' | grep -c 'OK:' || true)
if [[ "${OK_ROWS:-0}" -eq 0 ]]; then
  echo "FAIL: ZERO luks-monitor OK rows in the ${SOAK_DAYS}d Better Stack window — the daily probe is DEAD, never armed, or failing every run. A probe that is not steadily green cannot authorize a wipe (positive control)."
  exit 1
fi
# Internal ≥7d span floor: the first and last SUCCESS (OK) rows must be ≥SOAK_DAYS apart. Derive from
# the OK-row timestamps (best-effort; if unparseable, stay conservative — never PASS on a sub-7d span).
OK_LINES=$(printf '%s\n' "$BS_OUT" | grep 'luks-monitor' | grep 'OK:')
FIRST_TS=$(printf '%s\n' "$OK_LINES" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}' | sort | head -1)
LAST_TS=$(printf '%s\n' "$OK_LINES" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}' | sort | tail -1)
SPAN_OK=0
if [[ -n "$FIRST_TS" && -n "$LAST_TS" ]]; then
  F_EPOCH=$(date -u -d "${FIRST_TS/ /T}" +%s 2>/dev/null || echo 0)
  L_EPOCH=$(date -u -d "${LAST_TS/ /T}" +%s 2>/dev/null || echo 0)
  if [[ "$F_EPOCH" -gt 0 && "$L_EPOCH" -gt 0 && $((L_EPOCH - F_EPOCH)) -ge $((SOAK_DAYS * 86400)) ]]; then SPAN_OK=1; fi
fi
if [[ "$SPAN_OK" -ne 1 ]]; then
  echo "FAIL: still soaking — the luks-monitor heartbeat rows do not yet span ${SOAK_DAYS}d (first=${FIRST_TS:-?} last=${LAST_TS:-?}). The internal floor (DP-5) refuses a day-0 PASS regardless of the directive earliest=."
  exit 1
fi

# ---- 3. Observed completion: ADR-119 accepted (the destructive dispatch flips it LAST) ----------
ADR_STATUS=$(grep -m1 -E '^status:' "$ADR" 2>/dev/null | sed -E 's/^status:[[:space:]]*//; s/[[:space:]]+$//')
if [[ "$ADR_STATUS" == "accepted" ]]; then
  echo "PASS: drift=0 over ${SOAK_DAYS}d, luks-monitor heartbeat live and spanning ≥${SOAK_DAYS}d, and ADR-119 is 'accepted' — the wipe + convergence + PR 3 are DONE. Closing #6604's soak."
  exit 0
fi

echo "SOAK PASSED — wipe authorized: drift=0 over ${SOAK_DAYS}d and the luks-monitor heartbeat is live and spans ≥${SOAK_DAYS}d. The retained plaintext volume may now be wiped via the SEPARATE environment-gated destructive dispatch (blkdiscard -z + read-back + detach + API-delete), the for_each convergence landed, and ADR-119 flipped to 'accepted' + PR 3 opened. This tracker stays OPEN until this script OBSERVES ADR-119 'accepted' (currently: '${ADR_STATUS:-unknown}')."
exit 1
