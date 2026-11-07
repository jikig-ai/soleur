#!/usr/bin/env bash
# Did the Cloudflare-to-origin hop for https://app.soleur.ai/ use TLS? (#10479, epic #10205)
#
# READS ONLY PUBLIC HTTP. No credential, no SSH, no private network. It is the plan's
# `discoverability_test` for the origin TLS listener and the handshake probe of the
# done-condition on #10479: the app's TLS listener (server/origin-tls.ts) stamps
# `x-origin-transport: <TLS version>` on /health, and the plain-HTTP listener never does.
#
# WHAT A PASS PROVES. A 200 carrying `x-origin-transport: TLSv1.2|TLSv1.3` proves the request
# reached the origin OVER TLS. It proves Cloudflare ACCEPTED THE CERTIFICATE only when the zone (or
# the canary rule) is in `strict` for that request: under `full`, Cloudflare dials TLS without
# validating the certificate, so the header appears with any certificate. Say which mode you
# measured. A 200 WITHOUT the header is the pre-flip truth (Flexible: plain HTTP to the origin).
#
# Usage: origin-tls-probe.sh [--require-tls] [--canary]
#   --require-tls  exit 3 unless the response is a 200 that carries a TLSv1.2/TLSv1.3 header.
#   --canary       send `x-origin-tls-probe: 1`, the header the ORIGIN-TLS CANARY Configuration Rule matches
#                  (seo-config-rules.tf, ADR-321): for a request to /health on app.soleur.ai that carries it, the edge
#                  dials the origin in `strict`. Implies --require-tls, because a canary that does not prove TLS is not a
#                  pass. Reading the verdicts in canary mode:
#                    exit 0  TLS-ON-ORIGIN-HOP: the rule applied AND Cloudflare accepted the Origin CA certificate
#                            (strict validated issuer, expiry and hostname for this request).
#                    exit 1  NOT-200, typically 525/526: the rule applied and Cloudflare REFUSED the certificate.
#                    exit 3  NO-TLS-ON-ORIGIN-HOP: the rule did not apply (not enabled, not yet propagated, or the phase
#                            rejected the header field) - the hop is still flexible. It says nothing about the certificate.
#                    exit 2  could not check.
#
# Output contract (one line, no ANSI, always starting `origin-tls-probe:`):
#   origin-tls-probe: http=<code|none> transport=<token|none> cf_cache=<token|none> result=<R>
#   (UNREACHABLE carries `curl_exit=<n>` instead of the three fields)
#   result is one of: TLS-ON-ORIGIN-HOP | PLAIN-ORIGIN-HOP | UNEXPECTED-TRANSPORT | NOT-200 |
#                     NO-TLS-ON-ORIGIN-HOP (only with --require-tls) | UNREACHABLE
# The exit code carries the verdict:
#   0  200 and transport is TLSv1.2/TLSv1.3 (TLS-ON-ORIGIN-HOP), or 200 with no header and no
#      --require-tls (PLAIN-ORIGIN-HOP: the pre-flip state, NOT a success of the flip)
#   1  reached, but not a 200 (a 521/525/526 here is Cloudflare refusing the origin TLS hop)
#   2  could not complete the request (transport failure): a COULD-NOT-CHECK, never a verdict
#   3  --require-tls and the 200 does not prove TLS (no header, or a value that is not TLSv1.2/1.3)
#  64  usage error (stderr, not the line above)
# The unreachable arm is its own exit code on purpose: it must never collapse into a verdict.
#
# The canary mode (--canary) sends the request header the ORIGIN-TLS CANARY Configuration Rule matches; the header
# name lives here and in seo-config-rules.tf, and origin-tls-probe.test.sh pins the two together.
#
# Env: ORIGIN_TLS_PROBE_URL overrides the target; it must be https unless
# ORIGIN_TLS_PROBE_ALLOW_HTTP=1 (the test points it at a local plain server).

set -uo pipefail

require_tls=0
canary=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-tls) require_tls=1 ;;
    --canary) canary=1; require_tls=1 ;;
    *) echo "origin-tls-probe: usage: $0 [--require-tls]" >&2; exit 64 ;;
  esac
  shift
done

base="${ORIGIN_TLS_PROBE_URL:-https://app.soleur.ai/health}"
case "$base" in
  https://*) ;;
  http://*) [ "${ORIGIN_TLS_PROBE_ALLOW_HTTP:-}" = 1 ] || { echo "origin-tls-probe: refusing a non-https target" >&2; exit 64; } ;;
  *) echo "origin-tls-probe: target must be an https URL" >&2; exit 64 ;;
esac
sep='?'; case "$base" in *\?*) sep='&' ;; esac
url="${base}${sep}origin-tls-probe=$(date +%s)-$$-${RANDOM}"

# -q first: ignore ~/.curlrc and CURL_HOME (an `insecure` there would change the verdict).
# --noproxy '*': an ambient https_proxy must not change what hop is measured.
args=(-q --silent --show-error --max-time 10 --noproxy '*' --output /dev/null --dump-header - --write-out 'HTTP_CODE=%{http_code}\n'
  -H 'Cache-Control: no-cache')
[ "$canary" -eq 1 ] && args+=(-H 'x-origin-tls-probe: 1')
[ "${ORIGIN_TLS_PROBE_ALLOW_HTTP:-}" = 1 ] || args+=(--proto '=https')

curl_exit=0
out="$(curl "${args[@]}" "$url" 2>&1)" || curl_exit=$?
if [ "$curl_exit" -ne 0 ]; then
  echo "origin-tls-probe: result=UNREACHABLE curl_exit=${curl_exit} (transport failure, could not check)"
  exit 2
fi

out="$(printf '%s\n' "$out" | tr -d '\r')"
code="$(printf '%s\n' "$out" | sed -n 's/^HTTP_CODE=//p' | tail -1)"
header() { printf '%s\n' "$out" | awk -F': *' -v n="$1" 'tolower($1)==n { print $2; exit }'; }
# Echoed values are attacker-influenceable (any hop can set a header): keep a safe alphabet, bounded.
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._-' | cut -c1-24; }
transport="$(clean "$(header x-origin-transport)")"
cache="$(clean "$(header cf-cache-status)")"
line="origin-tls-probe: http=${code:-none} transport=${transport:-none} cf_cache=${cache:-none}"
[ "$canary" -eq 1 ] && line="${line} mode=canary"

if [ "$code" != 200 ]; then
  echo "$line result=NOT-200"
  exit 1
fi
case "$transport" in
  TLSv1.2|TLSv1.3) echo "$line result=TLS-ON-ORIGIN-HOP"; exit 0 ;;
esac
if [ "$require_tls" -eq 1 ]; then
  if [ -z "$transport" ]; then echo "$line result=NO-TLS-ON-ORIGIN-HOP"; else echo "$line result=UNEXPECTED-TRANSPORT"; fi
  exit 3
fi
if [ -z "$transport" ]; then echo "$line result=PLAIN-ORIGIN-HOP"; else echo "$line result=UNEXPECTED-TRANSPORT"; fi
exit 0
