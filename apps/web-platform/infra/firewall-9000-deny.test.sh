#!/usr/bin/env bash
#
# Drift guard: hcloud_firewall.web MUST NOT open port 9000 (the webhook listener)
# on the public interface (#5274 Phase 3, ADR-068). Phase 3 rebinds the webhook to
# 0.0.0.0 so the private-net peer can reach /hooks/deploy-peer for the deploy
# fan-out — that is SAFE only because the firewall default-denies 9000 publicly
# (Hetzner firewalls filter the public interface; intra-hcloud_network traffic is
# open by membership). This default-deny is therefore LOAD-BEARING for webhook
# exposure: a future inbound rule opening 9000 would expose the HMAC-gated deploy
# endpoint to the internet. This guard fails CI if any inbound rule references 9000.
#
# Run: bash apps/web-platform/infra/firewall-9000-deny.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="${DIR}/firewall.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$FW" ] || { echo "FAIL: firewall.tf not found at $FW" >&2; exit 1; }

# Enumerate every inbound `port = "…"` value (the shape hcloud_firewall rules use).
# A silent-empty extraction (parser drift) must fail loud, so assert we saw the
# known-good ports first.
ports="$(grep -oE 'port[[:space:]]*=[[:space:]]*"[0-9-]+"' "$FW" \
  | grep -oE '"[0-9-]+"' | tr -d '"')"
n=$(printf '%s\n' "$ports" | grep -c '.')
if [ "$n" -lt 3 ]; then
  fail "extracted <3 firewall ports (got $n) — parser drift; refusing to pass vacuously"
fi

# No inbound rule may reference port 9000 — exact, or a range straddling it.
bad=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ "$p" = "9000" ]; then
    fail "firewall.tf opens port 9000 (exact) — deploy webhook would be publicly exposed"
    bad=1
    continue
  fi
  case "$p" in
    *-*)
      lo="${p%%-*}"; hi="${p##*-}"
      if [ "$lo" -le 9000 ] 2>/dev/null && [ "$hi" -ge 9000 ] 2>/dev/null; then
        fail "firewall.tf opens port range $p straddling 9000 — deploy webhook would be publicly exposed"
        bad=1
      fi
      ;;
  esac
done <<< "$ports"
[ "$bad" -eq 0 ] && pass

total=$((passes + fails))
echo "firewall-9000-deny: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
