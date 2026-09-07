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

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797 / #7858).
#
# This probe forwards `Authorization: Bearer $BETTERSTACK_LOGS_TOKEN` to an ingest endpoint, so a
# `set -x` anywhere above it would trace the write credential into this job's output. The rule
# arrived on main from #7858 while this branch was in flight; touching this file forfeits its
# baseline grandfathering, which is the correct behaviour — a credential-binding script being
# edited is exactly when the refusal should be added.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_LOGS_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
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

# BETTERSTACK_INGEST_URL is env-overridable and this request carries a bearer credential, so the
# destination is validated before the token is forwarded: `--proto '=https'` refuses a plaintext
# override outright, and the host assertion refuses one pointed anywhere but the vendor. Neither
# is hypothetical — the same variable name is already exported into host environments elsewhere
# in this repo, so an http:// value would put the ingest token on the wire in cleartext. No `-L`,
# so a 30x cannot forward the header either.
#
# (#7855) MATCH THE AUTHORITY, NOT THE WHOLE URL. This was
# `case "$BETTERSTACK_INGEST_URL" in https://*.betterstackdata.com/*)`, and a shell glob's `*`
# crosses `/` and `?` — so the leading wildcard swallowed the entire authority and the vendor
# name only had to appear SOMEWHERE later in the string. Measured against that pattern on
# 2026-09-04:
#
#   https://evil.com/?x=.betterstackdata.com/              -> ACCEPTED
#   https://attacker.example.org/a/.betterstackdata.com/x  -> ACCEPTED
#
# The scheme anchor was sound; the host anchor was decorative. Both URLs would have put a live
# bearer ingest token on an attacker-controlled host. The fix extracts the authority first, so
# every wildcard below is confined to a string that cannot contain a path, a query or a
# fragment.
_bs_rest="${BETTERSTACK_INGEST_URL#https://}"
if [[ "$_bs_rest" == "$BETTERSTACK_INGEST_URL" ]]; then
  # No https:// prefix was removed, so the scheme is not https.
  emit "INGEST_PROBE_UNCONFIGURED" "-" "BETTERSTACK_INGEST_URL is not an https:// URL; refusing to forward the ingest credential to it"
  exit 2
fi
_bs_auth="${_bs_rest%%/*}"      # cut the path
_bs_auth="${_bs_auth%%\?*}"     # and a query on an authority-only URL
_bs_auth="${_bs_auth%%#*}"      # and a fragment
# Userinfo is the third way to put a vendor-looking string to the LEFT of the real host
# (`https://s1.betterstackdata.com@evil.com/` resolves to evil.com). This probe never needs
# credentials in the URL, so the whole component is refused rather than parsed around.
if [[ "$_bs_auth" == *"@"* ]]; then
  emit "INGEST_PROBE_UNCONFIGURED" "-" "BETTERSTACK_INGEST_URL carries userinfo, which puts the real host after an @; refusing to forward the ingest credential to it"
  exit 2
fi
_bs_host="${_bs_auth%%:*}"      # drop an explicit port
# The leading dot is load-bearing: without it `notbetterstackdata.com` — a registrable lookalike
# — would satisfy a bare suffix match.
case "$_bs_host" in
  *.betterstackdata.com) : ;;
  *)
    emit "INGEST_PROBE_UNCONFIGURED" "-" "BETTERSTACK_INGEST_URL host '${_bs_host}' is not a betterstackdata.com endpoint; refusing to forward the ingest credential to it"
    exit 2
    ;;
esac

# `-o /dev/null -w '%{http_code}'` and NOT `-f`: a 402 body is the answer, so failing the
# request on an HTTP error would discard the very thing being measured.
#
# The empty batch is the whole point — see the header. Keep it literal so the test's source
# grep can pin it.
rc=0
http="$(curl --disable --noproxy '*' -sS -m "$TIMEOUT" --proto '=https' -o /dev/null -w '%{http_code}' \
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
    # (#7855) THE NAME IS THE FINDING. This read `INGEST_ACCEPTING`, and that token was printed
    # verbatim with http=202 for the whole 27-hour window of #7811 — an issue titled "Better
    # Stack is accepting no writes". The endpoint acknowledged every batch and stored none of
    # them, so the only word in the verdict was the one thing the run had not established.
    #
    # A 2xx from this endpoint means the request was ACKNOWLEDGED. Storage is a separate claim
    # and this probe cannot make it: it posts an empty batch by design (see the header — a
    # writing probe would satisfy the absence alarm's any-row control forever), so there is
    # nothing for it to read back. The instrument that CAN establish storage is
    # scripts/followthroughs/betterstack-roundtrip-latency-7855.sh, which writes a marker and
    # reads it out again.
    emit "INGEST_ACKNOWLEDGED" "$http" "the write endpoint acknowledged an empty batch; this establishes reachability and credential validity ONLY — it does NOT establish that any row was stored, which needs a readback (scripts/followthroughs/betterstack-roundtrip-latency-7855.sh)"
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
