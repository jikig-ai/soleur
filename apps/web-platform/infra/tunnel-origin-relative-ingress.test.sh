#!/usr/bin/env bash
# Drift guard: the `deploy.` and `ssh.` tunnel ingress services MUST be
# origin-relative (a private-net IP), never connector-relative (`localhost`).
#
# ADR-114 I2 / #6425 / #6594. ONE tunnel, MULTIPLE connector replicas, and CF
# load-balances across them. A `localhost:` service resolves on WHICHEVER replica
# answers, so the management plane is a coin flip: #6594's infra-config POST was a
# coin-flipped WRITE self-verified against a separately coin-flipped READ, and the
# gate's retry loop laundered it into a green. An origin-relative service makes
# whichever replica answers proxy to web-1 — the only host that can serve these
# routes. The registry rule (#6122) already ships this pattern; tunnel.tf's own
# comment names it "the RIGHT pattern and the one to generalize".
#
# Anchored on `service` ASSIGNMENT shape (`service[[:space:]]*=`), never a bare
# token: tunnel.tf's prose quotes `ssh://localhost:22` and `http://localhost:9000`
# verbatim while explaining why they are wrong, so a bare-token grep matches the
# comment that documents the fix and passes vacuously forever (the #6456 class).
# `terraform fmt` re-aligns `=` when a block gains an attribute, hence `[[:space:]]*`
# rather than a single literal space (#5132).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$SCRIPT_DIR/tunnel.tf"
fails=0

pass() { echo "  PASS: $1"; }
fail() {
  echo "  FAIL: $1" >&2
  fails=$((fails + 1))
}

echo "tunnel-origin-relative-ingress.test.sh"

if [[ ! -f "$TF" ]]; then
  echo "FATAL: $TF not found" >&2
  exit 1
fi

# Extract the ingress_rule block for a given hostname prefix and return its
# `service = "..."` value. Keyed off the config resource so a same-named hostname
# elsewhere in the file cannot satisfy the assertion.
service_for() {
  local host_prefix="$1"
  awk -v want="$host_prefix" '
    /^resource "cloudflare_zero_trust_tunnel_cloudflared_config"/ { inres = 1 }
    inres && /ingress_rule[[:space:]]*\{/ { inblock = 1; svc = ""; hit = 0 }
    inblock && $0 ~ ("hostname[[:space:]]*=[[:space:]]*\"" want "\\.") { hit = 1 }
    inblock && /^[[:space:]]*service[[:space:]]*=/ {
      svc = $0
      sub(/^[[:space:]]*service[[:space:]]*=[[:space:]]*/, "", svc)
      # Strip ONLY the surrounding quote pair. A gsub of every `"` also eats the
      # inner quotes of var.web_hosts["web-1"], silently defeating the assertion
      # that the origin is var-derived.
      sub(/^"/, "", svc)
      sub(/"$/, "", svc)
    }
    inblock && /^[[:space:]]*\}/ {
      if (hit && svc != "") { print svc; exit }
      inblock = 0
    }
  ' "$TF"
}

# --- AC1/AC2: deploy. and ssh. services are origin-relative, not localhost ---
n_checked=0
for host in deploy ssh; do
  svc="$(service_for "$host")"
  n_checked=$((n_checked + 1))

  if [[ -z "$svc" ]]; then
    fail "$host.: no service found in its ingress_rule — extraction broke (guard is blind)"
    continue
  fi

  if [[ "$svc" == *localhost* || "$svc" == *127.0.0.1* ]]; then
    fail "$host.: service is connector-relative ($svc) — ADR-114 I2 / #6594 coin-flip. Pin to web-1's private IP."
  else
    pass "$host.: service is not connector-relative ($svc)"
  fi

  if [[ "$svc" != *'var.web_hosts["web-1"].private_ip'* ]]; then
    fail "$host.: service ($svc) does not reference var.web_hosts[\"web-1\"].private_ip — never hardcode 10.0.1.10"
  else
    pass "$host.: service derives the origin from var.web_hosts[\"web-1\"].private_ip"
  fi
done

# Minimum-cardinality guard: an extraction that silently matches nothing would
# otherwise exit 0 with ZERO coverage (the #5721 empty-loop trap).
if [[ "$n_checked" -lt 2 ]]; then
  fail "expected to check 2 ingress rules, checked $n_checked — the guard ran blind"
else
  pass "checked both ingress rules ($n_checked)"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED ($fails)" >&2
  exit 1
fi
echo "OK"
