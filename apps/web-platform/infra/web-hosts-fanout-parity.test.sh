#!/usr/bin/env bash
#
# Drift guard: EVERY workflow copy of the WEB_HOST_PRIVATE_IPS fan-out peer list
# (#5274 Phase 3 / ADR-068) MUST equal the set of private_ips in var.web_hosts
# (variables.tf). A drift means a deploy fans out to the wrong peers → a host
# silently ships stale code (single-user incident). There is ONE in-repo copy of
# this roster today and this guard covers it:
#   1. web-platform-release.yml — the tagged-release deploy fan-out (×1).
#
# reason: the two apply-web-platform-infra.yml copies lived in the `warm_standby` and
# `web_2_recreate` jobs, both DELETED with the web-2 dispatch sweep (#6575, 2026-07-20).
# The operand is KEPT at floor 0 rather than dropped.
#
# Keeping it at 0 was initially rejected as "vacuous", which was wrong and was measured
# wrong at review: `check_all_copies`'s third argument is a `-lt` FLOOR, not an equality
# check, and the per-copy content-comparison loop runs regardless of it. So floor 0 costs
# nothing today and keeps the roster check LIVE over any copy that ever reappears in that
# file. Measured: adding a job with a wrong roster (10.0.1.10,10.0.1.99) is INVISIBLE with
# the operand dropped and FAILS LOUD with it at 0.
#
# The extractor-break scenario that motivated dropping it is already covered by operand 2
# (floor 1) — breaking the IP regex fails that operand loudly.
#
# The multi-copy machinery is RETAINED deliberately: an earlier version extracted only the
# FIRST occurrence per file (`head -1`) and would have shipped a second copy un-guarded.
# Do not re-introduce head -1.
# Extracts EACH copy by shape and compares its sorted set to var.web_hosts.
#
# Run: bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_TF="${DIR}/variables.tf"
WORKFLOW="${DIR}/../../../.github/workflows/web-platform-release.yml"
APPLY_WORKFLOW="${DIR}/../../../.github/workflows/apply-web-platform-infra.yml"

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

# --- WEB_HOST_PRIVATE_IPS extractor: emit ONE normalized IP-set (sorted,
# comma-joined) PER occurrence — one line per in-file copy — so EACH copy is
# checked independently. The prior `head -1` validated only the FIRST copy; a
# union-then-compare would also hide a copy that DROPS an IP (the union carries
# it from the sibling copy), so we compare per-copy.
extract_wf_ip_sets() {
  local file="$1" line
  grep -oE 'WEB_HOST_PRIVATE_IPS:[[:space:]]*"[0-9.,]+"' "$file" \
    | grep -oE '"[0-9.,]+"' | tr -d '"' \
    | while IFS= read -r line; do
        printf '%s\n' "$line" | tr ',' '\n' | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd, -
      done
}

# --- Expected set: var.web_hosts private_ips, sorted + comma-joined to match the
# per-copy normalization above. Must itself be NON-EMPTY.
#
# This floor is an anti-PARSER-DRIFT tripwire, not a host-count policy: if the
# grep above stops matching variables.tf's shape, `tf_ips` silently empties and
# every parity assertion below would compare "" against "" and PASS — a green
# test proving nothing. The floor exists to make that failure loud.
#
# It was `-lt 2` until 2026-07-17 (#6538), which conflated "the parser works"
# with "there are two hosts". Retiring web-2 left ONE host and tripped it with
# "parser drift" — blaming the parser for a roster change it was not measuring.
# The correct floor is >=1: one host is a legitimate roster, zero is drift. ---
tf_n=$(printf '%s\n' "$tf_ips" | grep -c '.')
if [ "$tf_n" -lt 1 ]; then fail "extracted 0 private_ips from var.web_hosts — parser drift (the grep no longer matches variables.tf's shape; every assertion below would vacuously pass)"; fi
tf_set="$(printf '%s\n' "$tf_ips" | grep -E '.' | paste -sd, -)"

# --- Assert EVERY WEB_HOST_PRIVATE_IPS copy in a workflow equals var.web_hosts.
# min_copies pins the KNOWN copy count so a silently-removed copy (or a
# silent-empty extraction) fails loud instead of vacuously passing. ---
check_all_copies() {
  local file="$1" label="$2" min_copies="$3"
  local s i=0 n
  local sets=()
  mapfile -t sets < <(extract_wf_ip_sets "$file")
  n=${#sets[@]}
  if [ "$n" -lt "$min_copies" ]; then
    fail "$label: expected >=$min_copies WEB_HOST_PRIVATE_IPS copies, found $n — a copy was removed or the parser drifted"
    return
  fi
  for s in "${sets[@]}"; do
    i=$((i + 1))
    if [ "$s" = "$tf_set" ]; then
      pass
    else
      fail "$label copy #$i fan-out peer list drift: var.web_hosts=[$tf_set] copy=[$s]"
    fi
  done
}

# Operand 2: web-platform-release.yml — 1 copy (the tagged-release deploy fan-out).
check_all_copies "$WORKFLOW" "release-workflow" 1
# Operand 3: apply-web-platform-infra.yml — 0 copies today (both deleted with #6575), but the
# content check stays armed for any copy that reappears. See the reason block in the header.
check_all_copies "$APPLY_WORKFLOW" "apply-workflow" 0

total=$((passes + fails))
echo "web-hosts-fanout-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
