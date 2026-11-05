#!/usr/bin/env bash
# Did the Cloudflare-to-origin hop for https://app.soleur.ai/ use TLS? (#10479, epic #10205)
#
# READS ONLY PUBLIC HTTP. No credential, no SSH, no private network. It is the plan's
# `discoverability_test` for the origin TLS listener and the handshake probe of the
# done-condition on #10479: the app's TLS listener (server/origin-tls.ts) stamps
# `x-origin-transport: <TLS version>` on /health, and the plain-HTTP listener never does. A 200
# that carries the header therefore proves the request reached the origin over TLS and that
# Cloudflare accepted the certificate (a rejected certificate under `strict` is a 526, not a 200).
# A 200 WITHOUT the header is the pre-flip truth (Flexible: plain HTTP to the origin) and is
# reported as such, never as an error, unless --expect tls is given.
#
# Usage: origin-tls-probe.sh [--canary] [--expect tls|any]
#   --canary       also send `x-origin-tls-probe: 1`, which the (later) canary configuration rule
#                  matches to run ONLY this request in `strict` before the host-wide flip.
#   --expect tls   exit 3 when the response is a 200 without the transport header.
#
# One output line, always starting `origin-tls-probe:`; the exit code carries the verdict:
#   0  200, and (transport=TLS... or --expect any)
#   1  reached, but not a 200 (a 521/525/526 here is Cloudflare refusing the origin TLS hop)
#   2  could not complete the request (transport failure): a COULD-NOT-CHECK, never a verdict
#   3  200 without the transport header while --expect tls
# The unreachable arm is its own exit code on purpose: it must never collapse into a verdict.
#
# Env: ORIGIN_TLS_PROBE_URL overrides the target (the test points it at a local server).

set -uo pipefail

canary=0
expect=any
while [ "$#" -gt 0 ]; do
  case "$1" in
    --canary) canary=1 ;;
    --expect) shift; expect="${1:-}" ;;
    *) echo "origin-tls-probe: usage: $0 [--canary] [--expect tls|any]" >&2; exit 64 ;;
  esac
  shift
done
case "$expect" in tls|any) ;; *) echo "origin-tls-probe: --expect must be tls or any" >&2; exit 64 ;; esac

base="${ORIGIN_TLS_PROBE_URL:-https://app.soleur.ai/health}"
url="${base}?origin-tls-probe=$(date +%s)"
args=(--silent --show-error --max-time 10 --output /dev/null --dump-header - --write-out 'HTTP_CODE=%{http_code}\n'
  -H 'Cache-Control: no-cache')
[ "$canary" -eq 1 ] && args+=(-H 'x-origin-tls-probe: 1')

mode=plain; [ "$canary" -eq 1 ] && mode=canary
if ! out="$(curl "${args[@]}" "$url" 2>&1)"; then
  echo "origin-tls-probe: mode=$mode result=UNREACHABLE (transport failure, could not check)"
  exit 2
fi

out="$(printf '%s\n' "$out" | tr -d '\r')"
code="$(printf '%s\n' "$out" | sed -n 's/^HTTP_CODE=//p' | tail -1)"
header() { printf '%s\n' "$out" | awk -F': *' -v n="$1" 'tolower($1)==n { print $2; exit }'; }
transport="$(header x-origin-transport)"
cache="$(header cf-cache-status)"
line="origin-tls-probe: mode=$mode http=${code:-none} transport=${transport:-none} cf_cache=${cache:-none}"

if [ "$code" != 200 ]; then
  echo "$line result=NOT-200"
  exit 1
fi
if [ -z "$transport" ] && [ "$expect" = tls ]; then
  echo "$line result=NO-TLS-ON-ORIGIN-HOP"
  exit 3
fi
echo "$line result=OK"
exit 0
