#!/usr/bin/env bash
# Follow-through verification for #9178 (dashboard CWV field RUM).
#
# The ship PR enables client-side field RUM: Sentry.browserTracingIntegration()
# + tracesSampler (probe marker -> 1.0, real sessions -> 0.1) in
# apps/web-platform/sentry.client.config.ts. Pageload transactions then carry
# LCP/CLS/INP/FCP/TTFB as measurements — the first FIELD signal for #9178's
# warm/cold FCP claims, which until now rested on the lab perf-probe alone.
# This probe is the post-deploy confirmation that the pipeline lands.
#
# Asserts >=1 web-vitals-bearing pageload/navigation transaction for
# /dashboard sessions in the window [START, now].
#
# start= IS PINNED STRICTLY AFTER DEPLOY, and the pin is load-bearing in the
# FAIL direction: a window that reached back before the deploy could hold
# pageload transactions from before browserTracingIntegration existed — none
# carries vitals, which is exactly the FAIL signature, so an unpinned start
# could report "the integration is dark" on a healthy deploy. Two pins, first
# wins:
#   - CWV_RUM_START        — manual/operator override (ISO instant).
#   - SOLEUR_FT_EARLIEST   — the sweeper forwards the directive's earliest=
#                            (authored <deploy+1d>) on every run; ONE CLOCK FOR
#                            BOTH HALVES, so the window the verdict reads and
#                            the run-gate the sweeper applied cannot drift.
# With no usable pin the probe CANNOT ESTABLISH rather than grade an unbounded
# window (mirrors ghcr-read-retired-8036.sh's evidence gate).
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS      (>=1 transaction row carries a vital measurement; sweeper closes #9178)
#   1 = FAIL      (>=1 /dashboard PAGELOAD transaction landed and NONE carries
#                  vital measurements — transactions reach Sentry but the
#                  webVitals attachment is dark: the integration is miswired)
#   2 = NOT YET / TRANSIENT (zero pageload transactions in the window — no
#                  sampled /dashboard pageload yet at the 0.1 rate; also every
#                  API/auth/parse failure; retry next sweep)
#   3 = CANNOT ESTABLISH (no usable post-deploy start pin)
#
# Why the FAIL arm keys on PAGELOAD rows only: navigation transactions do not
# carry FCP/LCP/TTFB, and a 0.1 tracesSampler samples each transaction
# independently — a window holding only navigation rows proves nothing in
# either direction (mirrors accounted-beacon-live-6462.sh's denominator rule:
# a vacuous absence is not a verdict).
#
# Required env: SENTRY_ACTIONS_RO_TOKEN (wired in scheduled-followthrough-sweeper.yml
#   as secrets.SENTRY_ACTIONS_RO_TOKEN — the org-level read-only `actions-read-prd`
#   integration, ADR-031;
#   rotation: knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md).
#   Mirrors dashboard-cold-tiers-8978.sh / reconcile-ff-only-sentry-4977.sh.
#
# Tracker directive (goes in the #9178 ISSUE body — the sweeper enumerates
# `gh issue list --label follow-through`, never PR bodies — plus the
# `follow-through` label on that issue. The ship PR references the issue with
# `Ref`/`Tracks`, not `Closes`: a merge that auto-closes #9178 before this
# probe can PASS makes the PASS-close arm unreachable):
#   <!-- soleur:followthrough script=scripts/followthroughs/cwv-field-rum-9178.sh earliest=<deploy+1d ISO> secrets=SENTRY_ACTIONS_RO_TOKEN -->

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797): tracing echoes commands after
# expansion — a credential prints the moment it is used.
case "$-" in
  *x*)
    if [ -n "${SENTRY_ACTIONS_RO_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (SENTRY_ACTIONS_RO_TOKEN). Unset it to trace safely (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then echo "TRANSIENT: SENTRY_ACTIONS_RO_TOKEN not set" >&2; exit 2; fi

ORG="jikigai-eu"
API="https://sentry.io/api/0"

# Post-deploy window start. ISO instant, `Z` optional; validated before it
# reaches the URL because `date -d` accepts natural language ("next friday")
# and would silently produce a nonsense window (mirrors the sweeper's own
# CLOSED_LOOKBACK_DAYS guard rationale).
START="${CWV_RUM_START:-${SOLEUR_FT_EARLIEST:-}}"
if [[ -z "$START" ]]; then
  echo "CANNOT ESTABLISH: no post-deploy window start — SOLEUR_FT_EARLIEST unset/empty and no CWV_RUM_START override; refusing to grade an unbounded window." >&2
  exit 3
fi
if ! [[ "$START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$ ]]; then
  echo "CANNOT ESTABLISH: window start '$START' is not an ISO instant (YYYY-MM-DDTHH:MM:SS[Z]); refusing to grade." >&2
  exit 3
fi
if ! date -u -d "$START" +%s >/dev/null 2>&1; then
  echo "CANNOT ESTABLISH: window start '$START' does not parse as a date; refusing to grade." >&2
  exit 3
fi
START="${START%Z}"   # bare form, matching the siblings' start=/end= shape
END=$(date -u +%Y-%m-%dT%H:%M:%S)
if [[ "$START" > "$END" ]]; then
  echo "NOT YET: window start $START is in the future (now $END) — the post-deploy window has not opened." >&2
  exit 2
fi

# /dashboard pageload + navigation transactions. `transaction:/dashboard`
# (unquoted) is a contains-match, covering both the browser-side route name
# `/dashboard` and a `GET /dashboard` server-style name; the op pair scopes
# to the browser-tracing surface this change created. The vitals check is
# done on the RETURNED measurement fields, not a `has:` query clause — the
# verdict this probe needs is "rows exist but carry NO vitals", a distinction
# only the columns can express.
QUERY='transaction:/dashboard (transaction.op:pageload OR transaction.op:navigation)'
QUERY_ENC=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="${API}/organizations/${ORG}/events/?query=${QUERY_ENC}&start=${START}&end=${END}&per_page=100&field=title&field=timestamp&field=transaction.op&field=measurements.lcp&field=measurements.fcp&field=measurements.cls&field=measurements.inp&field=measurements.ttfb"

RESP=$(curl --disable --noproxy '*' -sS -w '\nHTTP_STATUS:%{http_code}' \
  -H "Authorization: Bearer $SENTRY_ACTIONS_RO_TOKEN" \
  -H "Accept: application/json" \
  "$URL")

HTTP_STATUS=$(printf '%s' "$RESP" | sed -n 's/^HTTP_STATUS://p' | tr -d '[:space:]')
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "TRANSIENT: Sentry API returned $HTTP_STATUS" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

read -r ROWS PAGELOADS VITALS PAGELOAD_VITALS < <(printf '%s' "$BODY" | jq -r '
  (if type == "array" then . else .data end) as $d
  | if ($d | type) != "array" then error("no data array") else
      [ ($d | length),
        ([$d[] | select(."transaction.op" == "pageload")] | length),
        ([$d[] | select(
            (."measurements.lcp"  != null) or
            (."measurements.fcp"  != null) or
            (."measurements.cls"  != null) or
            (."measurements.inp"  != null) or
            (."measurements.ttfb" != null))] | length),
        # The PASS denominator is vital-bearing PAGELOADS — fcp/ttfb exist on
        # pageload transactions only, and cls/lcp/inp can ride navigations,
        # so a window of dark pageloads + vital-bearing navigations must NOT
        # PASS while the wiring this probe verifies stays unproven.
        ([$d[] | select(."transaction.op" == "pageload") | select(
            (."measurements.lcp"  != null) or
            (."measurements.fcp"  != null) or
            (."measurements.cls"  != null) or
            (."measurements.inp"  != null) or
            (."measurements.ttfb" != null))] | length)
      ] | @tsv
    end' 2>/dev/null)

if ! [[ "${ROWS:-}" =~ ^[0-9]+$ && "${PAGELOADS:-}" =~ ^[0-9]+$ && "${VITALS:-}" =~ ^[0-9]+$ && "${PAGELOAD_VITALS:-}" =~ ^[0-9]+$ ]]; then
  echo "TRANSIENT: could not grade the Sentry response (window $START..$END)" >&2
  printf '%s\n' "$BODY" | head -c 500 >&2
  exit 2
fi

if [[ "$PAGELOAD_VITALS" -gt 0 ]]; then
  echo "PASS: $PAGELOAD_VITALS vital-bearing /dashboard pageload transaction(s) since $START ($ROWS row(s), $PAGELOADS pageload, $VITALS vital-bearing overall) — field RUM is landing (#9178)"
  printf '%s\n' "$BODY" | jq -r '(if type == "array" then . else .data end)[] | select((."measurements.lcp" != null) or (."measurements.fcp" != null) or (."measurements.cls" != null) or (."measurements.inp" != null) or (."measurements.ttfb" != null)) | "  - \(."transaction.op") \(."title") @ \(.timestamp) lcp=\(."measurements.lcp" // "-") fcp=\(."measurements.fcp" // "-")"' | head -10
  exit 0
fi

if [[ "$PAGELOADS" -gt 0 ]]; then
  echo "FAIL: $PAGELOADS /dashboard pageload transaction(s) landed since $START and NONE carries web-vital measurements — transactions reach Sentry but the vitals attachment is dark (#9178: browserTracingIntegration/webVitals wiring regression)" >&2
  printf '%s\n' "$BODY" | jq -r '(if type == "array" then . else .data end)[] | "  - \(."transaction.op") \(."title") @ \(.timestamp)"' | head -10 >&2
  exit 1
fi

echo "NOT YET: zero /dashboard pageload transactions since $START ($ROWS navigation-only/other row(s)) — no sampled dashboard pageload yet at the 0.1 rate, or tracing is entirely dark; retry next sweep."
exit 2
