#!/usr/bin/env bash
#
# Drift guard: the release workflow's WEB_HOST_PRIVATE_IPS (the 2-host deploy
# fan-out peer list, #5274 Phase 3 / ADR-068) MUST equal the set of private_ips in
# var.web_hosts (variables.tf). A drift means a deploy fans out to the wrong peers
# (or misses web-2 entirely) → web-2 silently ships stale code (single-user
# incident). Extracts BOTH operands by shape and compares the sorted sets.
#
# Run: bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_TF="${DIR}/variables.tf"
WORKFLOW="${DIR}/../../../.github/workflows/web-platform-release.yml"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$VARS_TF" ] || { echo "FAIL: variables.tf not found at $VARS_TF" >&2; exit 1; }
[ -f "$WORKFLOW" ] || { echo "FAIL: workflow not found at $WORKFLOW" >&2; exit 1; }

# --- Operand 1: private_ips declared in var.web_hosts (variables.tf) ---
# Match `private_ip = "10.0.1.NN"` — the only shape these lines take. Sorted,
# newline-joined for a set comparison independent of declaration order.
tf_ips="$(grep -oE 'private_ip[[:space:]]*=[[:space:]]*"[0-9.]+"' "$VARS_TF" \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u)"

# --- Operand 2: WEB_HOST_PRIVATE_IPS in the release workflow ---
wf_csv="$(grep -oE 'WEB_HOST_PRIVATE_IPS:[[:space:]]*"[0-9.,]+"' "$WORKFLOW" \
  | grep -oE '"[0-9.,]+"' | tr -d '"' | head -1)"
wf_ips="$(printf '%s' "$wf_csv" | tr ',' '\n' | grep -oE '10\.0\.1\.[0-9]+' | sort -u)"

# --- Minimum-cardinality guard (a silent-empty extraction must fail loud) ---
tf_n=$(printf '%s\n' "$tf_ips" | grep -c '.')
wf_n=$(printf '%s\n' "$wf_ips" | grep -c '.')
if [ "$tf_n" -lt 2 ]; then fail "extracted <2 private_ips from var.web_hosts (got $tf_n) — parser drift"; fi
if [ "$wf_n" -lt 2 ]; then fail "extracted <2 IPs from workflow WEB_HOST_PRIVATE_IPS (got $wf_n) — parser drift"; fi

# --- The sets MUST be identical ---
if [ "$tf_ips" = "$wf_ips" ]; then
  pass
else
  fail "fan-out peer list drift: var.web_hosts=[$(echo "$tf_ips" | tr '\n' ' ')] workflow=[$(echo "$wf_ips" | tr '\n' ' ')]"
fi

total=$((passes + fails))
echo "web-hosts-fanout-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
