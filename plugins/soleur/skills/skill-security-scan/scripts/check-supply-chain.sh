#!/usr/bin/env bash
# Category 3: supply-chain risk via OSV.dev batch API.
#
# Self-defense (CPO Decision 11):
# - Schema-validate response shape (require results array; reject malformed)
# - Cap response body size at 32 MiB
# - Ecosystem allowlist; unknown → REVIEW (never LOW-RISK)
# - Network/5xx → REVIEW (never silent LOW-RISK)
# - Hardcoded endpoint (no user-controllable redirection)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

CONFIG="$SCRIPT_DIR/../references/rules/supply-chain.yaml"
TYPOSQUAT_FILE="$SCRIPT_DIR/../references/typosquat-targets.yaml"

tmp="$(stdin_to_tempfile)"
trap 'rm -f "$tmp" "$tmp.req"' EXIT

# yaml_list shared helper lives in lib.sh.
mapfile -t ecosystems < <(yaml_list "$CONFIG" "ecosystem_allowlist")

is_known_ecosystem() {
  local eco="$1" entry
  for entry in "${ecosystems[@]}"; do
    [ -z "$entry" ] && continue
    [ "$eco" = "$entry" ] && return 0
  done
  return 1
}

findings_lines=""
queries='[]'

# Detect references to manifest files / deps in body. Heuristic patterns:
# - `pip install <pkg>` / `npm install <pkg>` / `cargo add <pkg>` / `go get <pkg>`
# - inline package.json, requirements.txt, pyproject.toml lines
#
# `seen` is a dedup hash; `ordered_keys` preserves insertion order so we can
# attribute OSV results (which are returned in submission order) to packages.
# Bash associative-array iteration order is NOT insertion order — using `seen`
# alone produced silent rule_id-to-package misattribution in OSV findings.
declare -A seen=()
declare -a ordered_keys=()

add_query() {
  local pkg="$1" eco="$2" key="$eco:$pkg"
  [ -n "${seen[$key]:-}" ] && return
  seen[$key]=1
  ordered_keys+=("$key")
  queries="$(echo "$queries" | jq --arg n "$pkg" --arg e "$eco" '. + [{package: {name: $n, ecosystem: $e}}]')"
}

# pip install <pkg>
while read -r pkg; do
  [ -z "$pkg" ] && continue
  pkg="${pkg%%[<>=!~]*}"  # strip version specifier
  pkg="${pkg// /}"
  [ -z "$pkg" ] && continue
  add_query "$pkg" "PyPI"
done < <(grep -oE 'pip[[:space:]]+install[[:space:]]+[A-Za-z0-9_.-]+' "$tmp" | awk '{print $NF}')

# npm install <pkg>
while read -r pkg; do
  [ -z "$pkg" ] && continue
  pkg="${pkg// /}"
  [ -z "$pkg" ] && continue
  add_query "$pkg" "npm"
done < <(grep -oE 'npm[[:space:]]+(install|i)[[:space:]]+[@A-Za-z0-9/_.-]+' "$tmp" | awk '{print $NF}' | grep -v '^-' || true)

# cargo add <pkg>
while read -r pkg; do
  [ -z "$pkg" ] && continue
  pkg="${pkg// /}"
  [ -z "$pkg" ] && continue
  add_query "$pkg" "crates.io"
done < <(grep -oE 'cargo[[:space:]]+add[[:space:]]+[A-Za-z0-9_.-]+' "$tmp" | awk '{print $NF}')

# go get <pkg>
while read -r pkg; do
  [ -z "$pkg" ] && continue
  pkg="${pkg// /}"
  [ -z "$pkg" ] && continue
  add_query "$pkg" "Go"
done < <(grep -oE 'go[[:space:]]+get[[:space:]]+[A-Za-z0-9./_-]+' "$tmp" | awk '{print $NF}')

# Typosquat detection (Levenshtein distance ≤ 2 against vendored top-N seed)
levenshtein() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    la=length(a); lb=length(b)
    if (la == 0) { print lb; exit }
    if (lb == 0) { print la; exit }
    for (i=0; i<=la; i++) d[i,0]=i
    for (j=0; j<=lb; j++) d[0,j]=j
    for (i=1; i<=la; i++) {
      for (j=1; j<=lb; j++) {
        cost = (substr(a,i,1) == substr(b,j,1)) ? 0 : 1
        v1 = d[i-1,j] + 1
        v2 = d[i,j-1] + 1
        v3 = d[i-1,j-1] + cost
        m = v1; if (v2 < m) m = v2; if (v3 < m) m = v3
        d[i,j] = m
      }
    }
    print d[la,lb]
  }'
}

mapfile -t pypi_targets < <(yaml_list "$TYPOSQUAT_FILE" "PyPI")
mapfile -t npm_targets < <(yaml_list "$TYPOSQUAT_FILE" "npm")

check_typosquat() {
  local pkg="$1" eco="$2"
  local arr
  case "$eco" in
    PyPI) arr=("${pypi_targets[@]}") ;;
    npm)  arr=("${npm_targets[@]}") ;;
    *)    return 1 ;;
  esac
  for target in "${arr[@]}"; do
    [ -z "$target" ] && continue
    [ "$pkg" = "$target" ] && return 1   # exact match → not typosquat
    local dist
    dist="$(levenshtein "$pkg" "$target")"
    if [ "$dist" -le 2 ] && [ "$dist" -gt 0 ]; then
      echo "$target"
      return 0
    fi
  done
  return 1
}

# Run typosquat check on each parsed package (iterate insertion-ordered keys
# so attribution lines stay deterministic — bash hash order is not stable).
for key in "${ordered_keys[@]}"; do
  eco="${key%%:*}"
  pkg="${key#*:}"
  if target="$(check_typosquat "$pkg" "$eco")"; then
    findings_lines+="typosquat-suspect"$'\t'"REVIEW"$'\t'"0"$'\t'"$pkg ~ $target ($eco)"$'\n'
  fi
  if ! is_known_ecosystem "$eco"; then
    findings_lines+="unknown-ecosystem"$'\t'"REVIEW"$'\t'"0"$'\t'"$pkg ($eco not in OSV allowlist)"$'\n'
  fi
done

# Skip OSV query if no packages or if SKILL_SECURITY_SCAN_OFFLINE=1.
n_queries="$(echo "$queries" | jq 'length')"
if [ "$n_queries" -gt 0 ] && [ "${SKILL_SECURITY_SCAN_OFFLINE:-0}" != "1" ]; then
  request_body="$(jq -cn --argjson q "$queries" '{queries: $q}')"
  echo "$request_body" > "$tmp.req"
  # 8s timeout; capture body and HTTP status via -w. Cap body via head -c.
  http_status="$(curl -sS -X POST \
    --max-time 8 \
    --max-filesize 33554432 \
    -H 'Content-Type: application/json' \
    -d @"$tmp.req" \
    -o "$tmp.resp" \
    -w '%{http_code}' \
    "https://api.osv.dev/v1/querybatch" 2>/dev/null || echo "000")"

  case "$http_status" in
    200)
      # Validate response shape: must have .results array
      if ! jq -e '.results | type == "array"' "$tmp.resp" >/dev/null 2>&1; then
        findings_lines+="osv-response-malformed"$'\t'"REVIEW"$'\t'"0"$'\t'"OSV response shape invalid"$'\n'
      else
        # Inspect each results[i].vulns
        n_results="$(jq '.results | length' "$tmp.resp")"
        # OSV.dev returns results in submission order; iterate insertion-
        # ordered keys to preserve attribution. Reject mismatched-length
        # response (per security review P2: MITM 200-with-empty-results).
        if [ "$n_results" -ne "${#ordered_keys[@]}" ]; then
          findings_lines+="osv-response-length-mismatch"$'\t'"REVIEW"$'\t'"0"$'\t'"OSV results length $n_results != queries ${#ordered_keys[@]}"$'\n'
        fi
        i=0
        for key in "${ordered_keys[@]}"; do
          if [ "$i" -ge "$n_results" ]; then break; fi
          n_vulns="$(jq ".results[$i].vulns // [] | length" "$tmp.resp")"
          if [ "$n_vulns" -gt 0 ]; then
            sev="REVIEW"
            if [ "$n_vulns" -ge 3 ]; then
              sev="HIGH-RISK"
            elif jq -e ".results[$i].vulns[] | select(.severity[]?.score | test(\"HIGH|CRITICAL\"; \"i\"))" "$tmp.resp" >/dev/null 2>&1; then
              sev="HIGH-RISK"
            fi
            findings_lines+="osv-advisory"$'\t'"$sev"$'\t'"0"$'\t'"$key has $n_vulns advisory(ies)"$'\n'
          fi
          i=$((i + 1))
        done
      fi
      ;;
    5*)
      # Retry once on 5xx
      sleep 1
      http_status_retry="$(curl -sS -X POST \
        --max-time 8 \
        --max-filesize 33554432 \
        -H 'Content-Type: application/json' \
        -d @"$tmp.req" \
        -o "$tmp.resp" \
        -w '%{http_code}' \
        "https://api.osv.dev/v1/querybatch" 2>/dev/null || echo "000")"
      if [ "$http_status_retry" != "200" ]; then
        findings_lines+="osv-network-failure"$'\t'"REVIEW"$'\t'"0"$'\t'"OSV query failed (HTTP $http_status_retry after retry)"$'\n'
      fi
      ;;
    *)
      findings_lines+="osv-network-failure"$'\t'"REVIEW"$'\t'"0"$'\t'"OSV query failed (HTTP $http_status)"$'\n'
      ;;
  esac
  rm -f "$tmp.resp" 2>/dev/null || true
fi

verdict="$(printf '%s' "$findings_lines" | findings_to_verdict)"
findings_json="$(printf '%s' "$findings_lines" | build_findings_array)"

emit_result "$verdict" "supply-chain" "$findings_json"
