#!/usr/bin/env bash
# Better Stack ingest-refusal probe (#7569) — CAUSE ANNOTATION ONLY.
#
# WHAT IT ANSWERS. The reader side can establish that the warehouse is returning nothing. It
# structurally cannot establish WHY, because a refused write and a quiet producer look identical
# from a SELECT. This probe asks the write endpoint directly and reports the refusal code.
#
# WHAT IT MUST NEVER DO — have a veto. The verdict of record is the reader-derived one from
# scripts/lib/betterstack-absence.sh. This probe annotates it. Inverting that (letting a 2xx
# here override a dark reader result) would reintroduce exactly the #7569 failure: on
# 2026-08-14 the READ path answered 200 throughout while writes were refused, so a single
# healthy-looking signal was already available and already misleading.
#
# WHY IT IS NON-WRITING, AND WHY THAT IS LOAD-BEARING RATHER THAN TIDY. Measured against the
# live endpoint on 2026-08-16: an empty batch (`[]`) is refused with the SAME
# HTTP 402 {"error": "Quota exceeded"} as a real payload, and an invalid token returns 401. So
# the full discrimination is available without writing a row. That matters because the alarm's
# positive control is an unfiltered "is there any row" read: a probe that wrote its own marker
# would satisfy that control forever and convert a two-day outage into a permanent blind spot.
# The probe would mask the silence it exists to detect. Do not add a payload here.
#
# The 2xx arm is the one arm NOT measured against production, because the account was already
# over quota when this was written — every live call returns 402. It is asserted by the unit
# suite and by the soak follow-through, which is time-gated for exactly that reason.
#
# Observability layer: 3 (the producer path into Better Stack). `hr-observability-layer-citation`.
#
# EXIT CODES: 0 accepting | 4 refused (quota or auth) | 2 unreachable/vendor error/unconfigured.
# These mirror scripts/zot-restart-loop-alarm.sh's contract so a caller can propagate directly.

set -uo pipefail
export LC_ALL=C

: "${BETTERSTACK_INGEST_URL:=https://s2457081.eu-fsn-3.betterstackdata.com/}"
TIMEOUT="${BETTERSTACK_INGEST_PROBE_TIMEOUT:-20}"

emit() { printf 'SOLEUR_BETTERSTACK_INGEST_PROBE verdict=%s http=%s detail=%s\n' "$1" "$2" "$3"; }

if [[ -z "${BETTERSTACK_LOGS_TOKEN:-}" ]]; then
  # An unset credential is NOT a refusal. Reporting it as one would name a vendor-side cause
  # this run did not measure (AP-021 / ADR-166).
  emit "INGEST_PROBE_UNCONFIGURED" "-" "BETTERSTACK_LOGS_TOKEN is not set in this environment; the probe made no request and can say nothing about the vendor"
  exit 2
fi

# `-o /dev/null -w '%{http_code}'` and NOT `-f`: a 402 body is the answer, so failing the
# request on an HTTP error would discard the very thing being measured.
#
# The empty batch is the whole point — see the header. Keep it literal so the test's source
# grep can pin it.
rc=0
http="$(curl -sS -m "$TIMEOUT" -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${BETTERSTACK_LOGS_TOKEN}" \
  -H 'Content-Type: application/json' \
  "$BETTERSTACK_INGEST_URL" \
  --data-raw '[]')" || rc=$?

if [[ "$rc" -ne 0 ]]; then
  emit "INGEST_UNREACHABLE" "-" "curl exited ${rc} before an HTTP status was observed — this run learned nothing about whether writes are accepted"
  exit 2
fi

case "$http" in
  2*)
    emit "INGEST_ACCEPTING" "$http" "the write endpoint accepted an empty batch"
    exit 0
    ;;
  402)
    emit "INGEST_REFUSED_QUOTA" "$http" "the vendor is refusing writes for quota reasons; this is an account-level state and no code change restores it"
    exit 4
    ;;
  401 | 403)
    emit "INGEST_REFUSED_AUTH" "$http" "the ingest token was rejected; check BETTERSTACK_LOGS_TOKEN against the source's current token"
    exit 4
    ;;
  429)
    emit "INGEST_RATE_LIMITED" "$http" "the vendor is throttling; distinct from quota exhaustion and usually self-clearing"
    exit 2
    ;;
  5*)
    emit "INGEST_VENDOR_ERROR" "$http" "vendor-side error; this says nothing about our quota or credentials"
    exit 2
    ;;
  *)
    emit "INGEST_UNEXPECTED_STATUS" "$http" "unrecognised status; not classified rather than guessed"
    exit 2
    ;;
esac
