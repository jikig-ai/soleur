#!/usr/bin/env bash
# Detect Cloudflare API tokens that are DEAD or inconsistent across Doppler configs.
#
# WHY THIS EXISTS (2026-07-29 incident response)
# ----------------------------------------------
# Every `doppler_secret` that carries a Cloudflare token declares
# `lifecycle { ignore_changes = [value] }` (cf-cert-reissue-token.tf,
# tunnel.tf, zot-registry.tf). That rule is deliberate — it stops refresh-time
# churn — but it has a consequence nothing surfaces: **Terraform can never
# propagate a rotated token**. `terraform apply` reports `No changes` while the
# `prd` root config still holds the dead value, and every branch config that
# inherits from root serves it too.
#
# The failure is silent and delayed. Rotating a token in the Cloudflare
# dashboard and updating `prd_terraform` looks completely successful — the
# operator verifies the one config they edited, gets a green result, and moves
# on. The stale copies surface days later as an unrelated-looking 403 in cron,
# GHCR, or the LUKS workflow, with nothing pointing back at the rotation.
#
# Observed three times in a single session, each time only because the fan-out
# was checked by hand:
#   - REGISTRY_PUSH_ACCESS_TOKEN_*  — `prd` root stale after a Terraform replace
#   - CF_API_TOKEN_DNS_EDIT         — 5 of 7 configs stale after a dashboard roll
#   - CF_API_TOKEN_PURGE            — 6 of 7 configs stale after a dashboard roll
#
# This script makes that class fail loudly. It does NOT change the lifecycle
# rules: removing `ignore_changes` would trade a silent-staleness bug for a
# churn bug the comments say was hit before. Detection is the safer fix.
#
# USAGE
#   doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh
#   bash scripts/check-cloudflare-token-drift.sh --json
#
# EXIT CODES
#   0  every token value resolves LIVE against the Cloudflare API
#   1  at least one DEAD token value found (rotation did not propagate)
#   2  preconditions missing (doppler CLI, curl, python3)

set -uo pipefail

PROJECT="${DOPPLER_PROJECT:-soleur}"
JSON_OUT=0
[[ "${1:-}" == "--json" ]] && JSON_OUT=1

for bin in doppler curl python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not on PATH" >&2; exit 2; }
done

# Enumerate configs from Doppler rather than hardcoding. A hardcoded list is
# exactly how CF_API_TOKEN_AUDIT was missed during the incident: it lived only
# in the dev* configs, which the audit sweep never looked at.
mapfile -t CONFIGS < <(doppler configs -p "$PROJECT" --json 2>/dev/null |
  python3 -c 'import json,sys; [print(c["name"]) for c in json.load(sys.stdin)]' 2>/dev/null)
if [[ ${#CONFIGS[@]} -eq 0 ]]; then
  echo "ERROR: could not enumerate Doppler configs for project '$PROJECT'" >&2
  exit 2
fi

# Enumerate token-shaped keys the same way — never a fixed list.
declare -A KEYSET=()
for cfg in "${CONFIGS[@]}"; do
  while read -r k; do
    [[ -n "$k" ]] && KEYSET["$k"]=1
  done < <(doppler secrets -p "$PROJECT" -c "$cfg" --only-names 2>/dev/null |
    grep -oE 'CF_API_TOKEN[A-Z0-9_]*' || true)
done

declare -A VERDICT=()   # token value -> LIVE|DEAD  (verify each distinct value once)
DEAD_ROWS=()
LIVE_N=0
DEAD_N=0

verify_value() {
  local v="$1"
  if [[ -z "${VERDICT[$v]:-}" ]]; then
    local ok
    ok=$(curl -s --max-time 20 -H "Authorization: Bearer $v" \
      "https://api.cloudflare.com/client/v4/user/tokens/verify" |
      python3 -c 'import json,sys
try: print("LIVE" if json.load(sys.stdin).get("success") else "DEAD")
except Exception: print("DEAD")' 2>/dev/null)
    VERDICT[$v]="${ok:-DEAD}"
  fi
  printf '%s' "${VERDICT[$v]}"
}

for key in $(printf '%s\n' "${!KEYSET[@]}" | sort); do
  for cfg in "${CONFIGS[@]}"; do
    val=$(doppler secrets get "$key" -p "$PROJECT" -c "$cfg" --plain 2>/dev/null)
    [[ -z "$val" ]] && continue
    state=$(verify_value "$val")
    if [[ "$state" == "DEAD" ]]; then
      DEAD_N=$((DEAD_N + 1)); DEAD_ROWS+=("$key|$cfg")
    else
      LIVE_N=$((LIVE_N + 1))
    fi
  done
done

if [[ "$JSON_OUT" -eq 1 ]]; then
  python3 - "$LIVE_N" "$DEAD_N" "${DEAD_ROWS[@]:-}" <<'PY'
import json, sys
live, dead = int(sys.argv[1]), int(sys.argv[2])
rows = [r for r in sys.argv[3:] if r]
print(json.dumps({
    "live": live, "dead": dead,
    "stale": [{"key": r.split("|")[0], "config": r.split("|")[1]} for r in rows],
}, indent=2))
PY
else
  echo "Cloudflare token drift check — project '$PROJECT'"
  echo "  configs scanned: ${#CONFIGS[@]}   token keys: ${#KEYSET[@]}"
  echo "  live entries: $LIVE_N   dead entries: $DEAD_N"
  if [[ "$DEAD_N" -gt 0 ]]; then
    echo
    echo "STALE — these configs hold a token value Cloudflare no longer accepts:"
    for r in "${DEAD_ROWS[@]}"; do echo "  ${r%%|*}  in  ${r##*|}"; done
    echo
    echo "A rotation did not propagate. Terraform will NOT fix this: the"
    echo "doppler_secret resources carry lifecycle.ignore_changes = [value], so"
    echo "'terraform apply' reports 'No changes' while the stale value persists."
    echo "Set the live value on the 'prd' ROOT config; branch configs inherit it."
  fi
fi

[[ "$DEAD_N" -gt 0 ]] && exit 1
exit 0
