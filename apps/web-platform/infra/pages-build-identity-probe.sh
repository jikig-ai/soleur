#!/usr/bin/env bash
# Are the bytes now being served the bytes this run built?
#
# WHY THIS IS A COMMITTED SCRIPT AND NOT INLINE YAML
#
# Same reason as apex-origin-probe.sh, plus one specific to this probe: ADR-194
# AC19 requires the failing arm to be "exercised by a run where the expected SHA
# is deliberately wrong". A block of bash embedded in a workflow has nothing to
# invoke with a wrong SHA, so that half of AC19 is unsatisfiable by construction.
# As a script it is invocable, shellcheck'd, and covered by a sibling test.
#
# THE ARMS ARE SPLIT BY WHETHER THE ANSWER IS DEFINITE, NOT BY SEVERITY.
#
#   0  MATCH        served body == expected SHA
#   1  MISMATCH     200, body != SHA          definite: wrong bytes are served
#   3  ABSENT       non-200                   definite: this origin is not
#                                             serving this build at all
#   2  UNREACHABLE  no HTTP response          could NOT check (AP-021)
#
# The caller decides which are fatal; the probe only reports. That split is why
# ABSENT is its own code rather than folded into MISMATCH: at the cutover the
# two have different causes (a preview-alias deploy vs a stale origin) and
# different remedies.
#
# `curl -f` is deliberately NOT used. It prints nothing and exits non-zero on
# any >=400, which collapses a 404 — the exact stale/preview signature — into
# the same empty string a transport failure produces, sending the flagship
# failure to the inconclusive arm. Measured: `curl -fsS` against a live 404
# captures 0 bytes.
#
# Reads only public HTTP. No credentials.

set -uo pipefail

URL="${PROBE_URL:?PROBE_URL is required}"
EXPECTED="${EXPECTED_SHA:?EXPECTED_SHA is required}"
ATTEMPTS="${PROBE_ATTEMPTS:-3}"
SLEEP_S="${PROBE_SLEEP_SECONDS:-10}"

# Bodies are interpolated into CI annotations and the job summary. An origin
# misconfigured to serve HTML on this path would otherwise flood both, and a
# backtick in the body breaks out of the summary's code span. apex-origin-probe.sh
# discards the body entirely for the same reason; here it IS the signal, so it is
# truncated and backtick-stripped instead.
sanitize() { printf '%s' "${1//\`/}" | head -c 200 | tr -d '\n'; }

code=""; body=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  # A separate status write keeps the sentinel a literal 000 on transport
  # failure rather than an empty field (the contract inngest.test.sh asserts).
  tmp="$(mktemp)"
  code="$(curl -sS --max-time 20 -o "$tmp" -w '%{http_code}' "$URL" 2>/dev/null)" || code="000"
  [ -z "$code" ] && code="000"
  body="$(cat "$tmp")"; rm -f "$tmp"
  if [ "$code" = "200" ] && [ "$body" = "$EXPECTED" ]; then break; fi
  if [ "$attempt" -lt "$ATTEMPTS" ]; then sleep "$SLEEP_S"; fi
done

if [ "$code" = "000" ]; then
  echo "UNREACHABLE — no HTTP response from ${URL} after ${ATTEMPTS} attempt(s)."
  echo "This is 'could not check', NOT 'the deploy is correct'."
  exit 2
fi

if [ "$code" != "200" ]; then
  echo "ABSENT — ${URL} returned HTTP ${code}."
  echo "This origin is not serving this build. The usual cause is a deploy that"
  echo "landed on a preview alias; check the branch flag the deploy step passed."
  exit 3
fi

if [ "$body" != "$EXPECTED" ]; then
  echo "MISMATCH — ${URL} serves $(sanitize "$body"), this run built ${EXPECTED}."
  exit 1
fi

echo "MATCH — ${URL} serves ${EXPECTED}."
exit 0
