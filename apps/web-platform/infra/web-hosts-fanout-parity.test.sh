#!/usr/bin/env bash
#
# Drift guard: EVERY workflow copy of the WEB_HOST_PRIVATE_IPS fan-out peer list
# (#5274 Phase 3 / ADR-068) MUST equal the set of private_ips in var.web_hosts
# (variables.tf). A drift means a deploy fans out to the wrong peers (or misses
# web-2 entirely) → web-2 silently ships stale code (single-user incident). There
# are THREE in-repo copies of this roster today and this guard covers EVERY one:
#   1. web-platform-release.yml — the tagged-release deploy fan-out (×1).
#   2. apply-web-platform-infra.yml `warm_standby` job — the ADR-068 warm-standby
#      dispatch re-uses the SAME literal to fan a current-version redeploy out to
#      web-2 (env WEB_HOST_PRIVATE_IPS).
#   3. apply-web-platform-infra.yml `web_2_recreate` job (#6030) — the same env,
#      a 2nd copy in the apply workflow. Previously this guard extracted only the
#      FIRST occurrence per file (`head -1`), so this copy would have shipped
#      un-guarded; it now validates EACH copy independently.
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
[ -f "$APPLY_WORKFLOW" ] || { echo "FAIL: apply workflow not found at $APPLY_WORKFLOW" >&2; exit 1; }

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
# per-copy normalization above. Must itself be non-empty (>=2 hosts). ---
tf_n=$(printf '%s\n' "$tf_ips" | grep -c '.')
if [ "$tf_n" -lt 2 ]; then fail "extracted <2 private_ips from var.web_hosts (got $tf_n) — parser drift"; fi
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
# Operand 3: apply-web-platform-infra.yml — 2 copies (warm_standby + web_2_recreate, #6030).
check_all_copies "$APPLY_WORKFLOW" "apply-workflow" 2

total=$((passes + fails))
echo "web-hosts-fanout-parity: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
