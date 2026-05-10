#!/usr/bin/env bash
# Category 5: third-party telemetry surface.
#
# URL host-aware allowlist (R14): adversarial https://attacker.com/?ref=soleur.ai
# is detected as host=attacker.com, NOT allowlisted as raw substring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ALLOWLIST_FILE="$SCRIPT_DIR/../references/first-party-allowlist.yaml"
REDIRECT_FILE="$SCRIPT_DIR/../references/redirect-domains.yaml"

tmp="$(stdin_to_tempfile)"
trap 'rm -f "$tmp"' EXIT

# Load allowlisted domains. Strip wildcard prefix `*.` for suffix-matching.
# (We compute suffix matching at use-time; both forms map to the same set.)
# YAML list parser: section header `<key>:`, items `  - <value>`, comments allowed.
# Sub-sections terminate when a new top-level key appears.
yaml_list() {
  local file="$1" key="$2"
  awk -v key="$key" '
    $0 ~ "^"key":[[:space:]]*$" { in_sec = 1; next }
    /^[a-zA-Z_]/ { in_sec = 0 }
    in_sec && /^[[:space:]]*-[[:space:]]/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", val)
      sub(/[[:space:]]*#.*$/, "", val)
      sub(/^["'"'"']/, "", val); sub(/["'"'"']$/, "", val)
      if (val != "") print val
    }
  ' "$file"
}

mapfile -t allowlist_hosts < <(yaml_list "$ALLOWLIST_FILE" "domains" | sed 's/^\*\.//')
mapfile -t allowlist_campaigns < <(yaml_list "$ALLOWLIST_FILE" "utm_campaigns")
mapfile -t redirect_hosts < <(yaml_list "$REDIRECT_FILE" "redirect_hosts")
mapfile -t tracking_prefixes < <(yaml_list "$REDIRECT_FILE" "tracking_host_prefixes")

# Domain-suffix match. Returns 0 if host is on allowlist (or its subdomain).
is_allowlisted_host() {
  local host="$1" entry
  for entry in "${allowlist_hosts[@]}"; do
    [ -z "$entry" ] && continue
    if [ "$host" = "$entry" ] || [[ "$host" == *.${entry} ]]; then
      return 0
    fi
  done
  return 1
}

is_redirect_host() {
  local host="$1" entry
  for entry in "${redirect_hosts[@]}"; do
    [ -z "$entry" ] && continue
    [ "$host" = "$entry" ] && return 0
    [[ "$host" == *.${entry} ]] && return 0
  done
  for entry in "${tracking_prefixes[@]}"; do
    [ -z "$entry" ] && continue
    [[ "$host" == ${entry}* ]] && return 0
  done
  return 1
}

is_allowed_campaign() {
  local camp="$1" entry
  for entry in "${allowlist_campaigns[@]}"; do
    [ -z "$entry" ] && continue
    [ "$camp" = "$entry" ] && return 0
  done
  return 1
}

findings_lines=""

# Extract URLs (http/https) and process each.
url_re='https?://[^[:space:]<>")]+\>?'
while IFS=':' read -r line rest; do
  [ -z "$line" ] && continue
  # Extract first URL on the line via grep -oE
  while read -r url; do
    [ -z "$url" ] && continue
    # Parse host: strip scheme, then take up to first / or ?
    nh="${url#http://}"
    nh="${nh#https://}"
    host="${nh%%[/?#]*}"
    host="${host,,}"  # lowercase
    # Detect utm tag
    if echo "$url" | grep -qE 'utm_(source|medium|campaign|term|content)='; then
      camp="$(echo "$url" | grep -oE 'utm_campaign=[^&[:space:]]+' | head -1 | cut -d'=' -f2)"
      if is_allowlisted_host "$host"; then
        # First-party + allowlisted campaign → LOW-RISK; non-allowlisted campaign on first-party host still REVIEW
        if [ -n "$camp" ] && ! is_allowed_campaign "$camp"; then
          findings_lines+="utm-non-allowlisted-campaign"$'\t'"REVIEW"$'\t'"$line"$'\t'"host=$host campaign=$camp"$'\n'
        fi
      else
        findings_lines+="utm-non-allowlisted-host"$'\t'"REVIEW"$'\t'"$line"$'\t'"host=$host"$'\n'
      fi
    fi
    # Redirect / tracking host?
    if is_redirect_host "$host"; then
      findings_lines+="redirect-tracking-host"$'\t'"HIGH-RISK"$'\t'"$line"$'\t'"host=$host"$'\n'
    fi
  done < <(echo "$rest" | grep -oE "$url_re" 2>/dev/null || true)
done < <(grep -nE -- "$url_re" "$tmp" 2>/dev/null || true)

# Branding-only patterns → finding-level WARN (script reports as REVIEW per Phase 3 mapping).
brand_re='(powered by|brought to you by|sponsored by)'
while IFS=':' read -r line rest; do
  [ -z "$line" ] && continue
  snippet="${rest:0:200}"
  snippet="${snippet//$'\t'/ }"
  findings_lines+="branding-footer"$'\t'"REVIEW"$'\t'"$line"$'\t'"$snippet"$'\n'
done < <(grep -niE -- "$brand_re" "$tmp" 2>/dev/null || true)

# Outbound beacon: fetch/axios.post/curl POST in code blocks targeting non-allowlisted hosts.
# Simplified: any `fetch(...)` or `axios.post(...)` whose URL host is not allowlisted → HIGH-RISK.
fetch_re='\b(fetch|axios\.post|axios\.put|http\.post)[[:space:]]*\([[:space:]]*["'"'"'`](https?://[^"'"'"'`)[:space:]]+)'
while IFS= read -r match; do
  url="$(echo "$match" | grep -oE "$url_re" | head -1)"
  [ -z "$url" ] && continue
  nh="${url#http://}"; nh="${nh#https://}"; host="${nh%%[/?#]*}"; host="${host,,}"
  if ! is_allowlisted_host "$host"; then
    findings_lines+="outbound-beacon"$'\t'"HIGH-RISK"$'\t'"0"$'\t'"host=$host url=$url"$'\n'
  fi
done < <(grep -niE -- "$fetch_re" "$tmp" 2>/dev/null || true)

verdict="$(printf '%s' "$findings_lines" | findings_to_verdict)"
findings_json="$(printf '%s' "$findings_lines" | build_findings_array)"

emit_result "$verdict" "telemetry-surface" "$findings_json"
