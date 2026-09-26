#!/usr/bin/env bash
#
# arm-checkpoint.sh -- arm an alpha tester's checkpoint + quiet-probe reminders.
#
# Usage:  bash scripts/arm-checkpoint.sh <tester-N> <tracking-issue>
#   e.g.: bash scripts/arm-checkpoint.sh 2 8881
#
# Arms two reminders via POST /api/internal/schedule-reminder:
#   1. checkpoint-tester-<N>-<YYYY-MM-DD>  — issue-comment at +14d on the
#      tester's tracking issue (body = the runbook's checkpoint template).
#      The DATE is embedded in the reminder_id because Inngest dedupes on the
#      event id: re-arming a different fire_at under the same id returns a
#      lie-shaped 202 and silently keeps the first schedule.
#   2. cohort-quiet-tester-<N>-<YYYY-MM-DD> — named-check "cohort-quiet" at +3d;
#      same date-in-id rule — a same-day re-arm dedupes (idempotent), a
#      different-day re-arm creates a NEW live event (the old one still fires;
#      there is no cancel path).
#
# The ids are self-describing by convention — cohort-status derives expected
# ids from the convention, so this script only PRINTS the armed ids (it does
# not write into the runbook table).
#
# Requires: INNGEST_MANUAL_TRIGGER_SECRET in env. Read it via:
#   export INNGEST_MANUAL_TRIGGER_SECRET=$(doppler secrets get \
#     INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
#
# Portability: operator machines may be macOS — bash 3.2-safe, no GNU-isms,
# no python3 (same portability contract as emit-decision.sh).

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

N="${1:-}"
ISSUE="${2:-}"
BASE_URL="${SOLEUR_BASE_URL:-https://app.soleur.ai}"

fail() { echo "arm-checkpoint: $*" >&2; exit 1; }

case "$N" in
  ''|*[!0-9]*) fail "first arg must be the tester number (e.g. 2)" ;;
esac
case "$ISSUE" in
  ''|*[!0-9]*) fail "second arg must be the tracking issue number (e.g. 8881)" ;;
esac

# Scheme pin — an http:// override would send the shared secret in cleartext.
case "$BASE_URL" in
  https://*) ;;
  *) fail "SOLEUR_BASE_URL must be https://... (got: $BASE_URL)" ;;
esac

if [ -z "${INNGEST_MANUAL_TRIGGER_SECRET:-}" ]; then
  fail "INNGEST_MANUAL_TRIGGER_SECRET unset — read it via: export INNGEST_MANUAL_TRIGGER_SECRET=\$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)"
fi

date_plus() { # $1 = days ahead; prints UTC ISO instant
  date -u -v+"$1"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "+$1 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

TODAY="$(date -u +%Y-%m-%d)"
CHECKPOINT_ID="checkpoint-tester-${N}-${TODAY}"
QUIET_ID="cohort-quiet-tester-${N}-${TODAY}"
CHECKPOINT_AT="$(date_plus 14)"
QUIET_AT="$(date_plus 3)"
[ -n "$CHECKPOINT_AT" ] && [ -n "$QUIET_AT" ] || fail "could not compute future dates (need BSD date -v or GNU date -d)"

CHECKPOINT_BODY="@deruelle — Alpha tester #${N} 14-day checkpoint. Pull: open https://app.soleur.ai/dashboard/admin/analytics?cohort=alpha in a browser (admin session required — it is cookie-gated, not curl-able) for the funnel; if the tester runs the CLI plugin, ask them to run \`bash plugins/soleur/scripts/alpha-metrics.sh\` in their repo and paste the aggregate. Interview: which domain leaders did they use, did anything compound, willingness-to-pay (\$49/mo) signal. Report assisted vs unassisted usage — check the runbook row for nudged_at."

RESP="$(mktemp "${TMPDIR:-/tmp}/arm-checkpoint.XXXXXX")" || fail "mktemp failed"
trap 'rm -f "$RESP"' EXIT

post() { # $1 = json body; prints HTTP status
  curl --disable --noproxy '*' -sS -o "$RESP" -w '%{http_code}' -X POST \
    "${BASE_URL}/api/internal/schedule-reminder" \
    -H "Authorization: Bearer ${INNGEST_MANUAL_TRIGGER_SECRET}" \
    -H "Content-Type: application/json" \
    -d "$1" 2>/dev/null
}

# Build bodies without jq (macOS stock has none).
CHECKPOINT_JSON=$(cat <<EOF
{"reminder_id":"${CHECKPOINT_ID}","fire_at":"${CHECKPOINT_AT}","actor":"platform","action":{"type":"issue-comment","issue":${ISSUE},"body":$(printf '%s' "$CHECKPOINT_BODY" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/^/"/; s/$/"/')}}
EOF
)
QUIET_JSON=$(cat <<EOF
{"reminder_id":"${QUIET_ID}","fire_at":"${QUIET_AT}","actor":"platform","action":{"type":"named-check","check":"cohort-quiet","report_to_issue":${ISSUE},"params":{"cohort_key":"alpha"}}}
EOF
)

code="$(post "$CHECKPOINT_JSON")"
[ "$code" = "202" ] || { echo "checkpoint arm FAILED (HTTP $code):"; cat "$RESP"; exit 1; }
code="$(post "$QUIET_JSON")"
[ "$code" = "202" ] || { echo "quiet-probe arm FAILED (HTTP $code):"; cat "$RESP"; exit 1; }

echo "armed:"
echo "  ${CHECKPOINT_ID}  fires ${CHECKPOINT_AT}  -> issue #${ISSUE} (comment)"
echo "  ${QUIET_ID}  fires ${QUIET_AT}  -> issue #${ISSUE} (cohort-quiet check)"
echo
echo "Record tester-N + cohort_key in the runbook recruitment-mix row."
exit 0
