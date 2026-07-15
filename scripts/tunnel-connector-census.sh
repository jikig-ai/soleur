#!/usr/bin/env bash
# tunnel-connector-census.sh — pure classifier for the Cloudflare Tunnel connector census
# (#6425). SOURCED by .github/workflows/scheduled-inngest-health.yml and by
# scripts/tunnel-connector-census.test.sh. No network, no side effects: given the
# /cfd_tunnel/<id>/connections response body it echoes exactly one verdict token.
#
# WHY THIS EXISTS (the detector gap #6425 closed):
# Cloudflare binds ingress to a TUNNEL and then selects a connector per edge colo. With two
# connectors registered, `localhost:` ingress means "whichever replica answered" — not "this
# host" (ADR-114 I1/I2). On 2026-07-15 that produced 16h of false `inngest_down` P1s: a US
# runner read functions=61 healthy while EU probes read inactive 10/10 identical. Both were
# telling the truth about DIFFERENT hosts.
#
# A response-poll cannot detect this. Connector selection is colo-STICKY, so 10/10 identical
# reads from one vantage prove nothing at all. The connector census is the only
# VANTAGE-INDEPENDENT instrument: it asks Cloudflare's control plane how many connectors are
# registered, and the answer does not depend on who is asking or from where. This is the check
# that would have caught the bug on day one — and every day after.
#
# THE COUNTING TRAP (verified live 2026-07-15 — pin the jq):
# Three different countable things exist in this API, and two of them make a CORRECT fix look
# broken. On the real 2-connector tunnel they returned:
#   - the tunnel object's `connections` int ......... 8   (total QUIC conns, not connectors)
#   - each entry's `conns` array length ............. 4   (per-connector QUIC conns)
#   - entries with >=1 live conn ................... 2   <-- THE INVARIANT
# So the census counts ENTRIES-WITH-LIVE-CONNS. Anything else silently measures QUIC fan-out.
#
# WHY AN API FAILURE IS NOT "ZERO CONNECTORS" (the #6374 lesson, applied):
# A naive `connectors != 1 -> alert` fires on every API failure: an expired token, a 5xx, or a
# network blip yields no `.result` array, jq reports length 0, and `0 != 1` files a FALSE
# action-required P1 — every 15 minutes, against a perfectly healthy tunnel. That is precisely
# the relocated-false-positive class the sibling inngest-liveness-classify.sh was written to
# fix (its `probe_unavailable` mode). So an unreadable census is `census_unavailable` (soft,
# no page), never a connector verdict. Only a body we RECOGNISE as a well-formed census
# declares a connector state.
#
# Verdicts:
#   ok                  exactly 1 connector with live conns — the ADR-114 I1 invariant holds
#   multi_connector     >1 — ingress is non-deterministic RIGHT NOW (the #6425 regression)
#   zero_connectors     a well-formed census reporting 0 — the tunnel serves nothing; every
#                       tunnel-routed surface (deploy./ssh./registry.) is dark. Distinct from
#                       census_unavailable: here Cloudflare answered and said "none".
#   census_unavailable  unreadable/failed census — soft, NEVER a page (see above)
set -euo pipefail

# classify_connector_census <http_code> <body> -> echoes "<verdict> <count>"
# count is the connector count for well-formed censuses, or -1 when it is unknown (so a
# consumer can never mistake "unknown" for a real zero).
classify_connector_census() {
  local code="$1" body="$2"
  # Any non-200 is unreadable by definition — do not attempt to parse an error envelope.
  if [[ "$code" != "200" ]]; then
    echo "census_unavailable -1"
    return 0
  fi
  # Cloudflare reports its own failures in-band with HTTP 200 + success:false.
  local success
  success=$(printf '%s' "$body" | jq -r '.success // false' 2>/dev/null || echo false)
  if [[ "$success" != "true" ]]; then
    echo "census_unavailable -1"
    return 0
  fi
  # `.result` must be an ARRAY. A null/absent/object result is malformed, NOT zero connectors.
  local is_array
  is_array=$(printf '%s' "$body" | jq -r '(.result | type) == "array"' 2>/dev/null || echo false)
  if [[ "$is_array" != "true" ]]; then
    echo "census_unavailable -1"
    return 0
  fi
  # THE pinned invariant. Count entries holding >=1 live conn — never `.conns|length` (QUIC
  # conns per connector) and never the tunnel object's `connections` int.
  local n
  n=$(printf '%s' "$body" | jq -r '[.result[] | select((.conns | length) > 0)] | length' 2>/dev/null || echo "")
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "census_unavailable -1"
    return 0
  fi
  if (( n == 1 )); then
    echo "ok $n"
  elif (( n == 0 )); then
    echo "zero_connectors $n"
  else
    echo "multi_connector $n"
  fi
}

# describe_connectors <body> -> "id=<8-char> colos=a,b,c" per connector, for the alert body.
# Colo geography is how a connector is attributed to a host: origin_ip is null on BOTH entries
# (verified live), so identity is NOT assertable from this endpoint — ams*/hel* = hel1 = web-1,
# fra* = fsn1 = web-2. Best-effort: never fails the census.
#
# The output is SANITISED to [A-Za-z0-9=,._ -] because it crosses two injection boundaries: a
# GITHUB_OUTPUT heredoc (a line equal to the delimiter would break out and let the rest of the
# field forge arbitrary step outputs) and a markdown issue body. The values are Cloudflare's,
# not a user's, so this is defense-in-depth rather than a known vector — but the cost of the
# tr is zero and the failure mode is silent forgery of an operator-facing alert.
describe_connectors() {
  # Sanitise PER FIELD inside jq, not with a trailing `tr`: the output is intentionally one
  # line per connector, so a trailing filter has to keep "\n" and therefore cannot strip an
  # INJECTED newline — a colo_name of "x\nCENSUS_EOF\nverdict=ok" would still break out. Doing
  # it per field means the only newlines in the output are jq's own record separators.
  printf '%s' "$1" | jq -r '
    def clean: tostring | gsub("[^A-Za-z0-9._-]"; "");
    (.result // [])[]
    | select((.conns | length) > 0)
    | "id=\(.id[0:8] | clean) conns=\(.conns | length) colos=\([.conns[].colo_name | clean] | join(","))"
  ' 2>/dev/null || true
}
