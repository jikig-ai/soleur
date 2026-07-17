#!/usr/bin/env bash
# inngest-server-flip-guard.sh — the P1-5 arm-atomicity ExecStartPre guard for
# inngest-server.service on the dedicated Inngest host (#6178, ADR-100).
#
# Wired ONLY on the dedicated host (DOPPLER_PROJECT=soleur-inngest; inngest-bootstrap.sh
# gates the ExecStartPre line on that project so the co-located web host's inngest-server
# is never gated). Invoked via `doppler run --project soleur-inngest --config prd` so the
# env carries INNGEST_POSTGRES_URI + INNGEST_CUTOVER_FLIP.
#
# It BLOCKS the start (exit non-zero) when BOTH:
#   * INNGEST_POSTGRES_URI resolves to the PROD durable backend, AND
#   * the cutover flag is NOT in {armed, flipping, flushed, done}
# i.e. the prod URI has been armed into Doppler but the gated flip has not begun. Without
# this, a crash / OnBootSec / operator restart in that window would bring up a SECOND prod
# scheduler against the still-dirty dark Redis (the double-fire race). armed/flipping/flushed/done
# are the only states where a prod-URI start is legitimate (mid-flip, or post-cutover). `flushed`
# is included because the flip FSM itself starts the server AT flag=flushed (ADR-100; the flip
# oneshot's forward path and its flushed-RESUME arm both call `start_server` while flag=flushed,
# after asserting DBSIZE==0 on the dark Redis) — so without it the guard blocks the FSM's OWN
# controlled start, not just an unplanned restart.
#
# Prod detection: the prod backend is the dedicated Supabase project ref
# `pigsfuxruiopinouvjwy` (a NON-secret identifier, already in inngest.tf) — a stable
# substring of INNGEST_POSTGRES_URI. Override the marker via INNGEST_PROD_URI_MARKER.
# The URI itself is NEVER echoed (AC-NOBODY) — only the is_prod boolean + the flag.
#
# Fixture seams (CI has no doppler): GUARD_POSTGRES_URI, GUARD_FLIP_FLAG.
set -euo pipefail

readonly LOG_TAG="inngest-server-flip-guard"
readonly PROD_MARKER="${INNGEST_PROD_URI_MARKER:-pigsfuxruiopinouvjwy}"

# Seam-or-env, with whitespace trimmed off the flag.
POSTGRES_URI="${GUARD_POSTGRES_URI-${INNGEST_POSTGRES_URI:-}}"
FLIP_FLAG="$(printf '%s' "${GUARD_FLIP_FLAG-${INNGEST_CUTOVER_FLIP:-}}" | tr -d '[:space:]')"

is_prod=false
if [[ -n "$POSTGRES_URI" && "$POSTGRES_URI" == *"$PROD_MARKER"* ]]; then
  is_prod=true
fi

flag_ok=false
case "$FLIP_FLAG" in
  armed | flipping | flushed | done) flag_ok=true ;;
esac

if [[ "$is_prod" == true && "$flag_ok" == false ]]; then
  logger -t "$LOG_TAG" "BLOCK: prod Postgres URI with cutover flag='${FLIP_FLAG:-unset}' not in {armed,flipping,flushed,done} — refusing inngest-server start (P1-5)" 2>/dev/null || true
  echo "ERROR: refusing inngest-server start — prod Postgres URI with cutover flag '${FLIP_FLAG:-unset}' is not in {armed,flipping,flushed,done} (P1-5 arm-atomicity guard; would start a second prod scheduler)" >&2
  exit 1
fi

logger -t "$LOG_TAG" "ALLOW: is_prod=$is_prod flag='${FLIP_FLAG:-unset}'" 2>/dev/null || true
exit 0
