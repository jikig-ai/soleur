#!/usr/bin/env bash
# Category 2: prompt-injection.
#
# Frontmatter (high-precision, HIGH-RISK), body (proximity-gated, REVIEW),
# Soleur prose allowlist (downgrade legitimate flow-control prose), zero-width
# character detection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

tmp="$(stdin_to_tempfile)"
trap 'rm -f "$tmp" "$tmp.fm" "$tmp.body"' EXIT

# Split frontmatter (between leading --- and second ---) from body.
awk '
  BEGIN { phase = "pre" }
  phase == "pre" && /^---[[:space:]]*$/ { phase = "fm"; next }
  phase == "fm"  && /^---[[:space:]]*$/ { phase = "body"; next }
  phase == "fm"  { print > FM }
  phase == "body" { print > BODY }
  phase == "pre" { print > BODY }   # no frontmatter case → all is body
' FM="$tmp.fm" BODY="$tmp.body" "$tmp" || true

touch "$tmp.fm" "$tmp.body"

# Allowlist: legitimate flow-control prose around "ignore".
soleur_allowlist_re='ignore[[:space:]]+(the[[:space:]]+)?(step|cache|warning|error|file|test|null|undefined|empty|comment)'

findings_lines=""

# ---- Frontmatter rules (HIGH-RISK) ----
fm_rules=(
  'role-hijack-fm|HIGH-RISK|(ignore|disregard|forget)[[:space:]]+(all[[:space:]]+)?(previous|prior|above|the[[:space:]]+(system|prior))'
  'mode-jailbreak-fm|HIGH-RISK|\b(DAN|developer[[:space:]]+mode|jailbreak)\b'
  'sysprompt-exfil-fm|HIGH-RISK|(reveal|print|show|output|leak)[[:space:]]+([a-z]+[[:space:]]+){0,3}(system[[:space:]]+prompt|the[[:space:]]+system)'
  'delim-breakout-fm|HIGH-RISK|(</system>|<\|im_(start|end)\|>|^system:)'
)
for spec in "${fm_rules[@]}"; do
  IFS='|' read -r rule_id severity regex <<<"$spec"
  while IFS=':' read -r line rest; do
    [ -z "$line" ] && continue
    snippet="${rest:0:200}"
    snippet="${snippet//$'\t'/ }"
    # Apply allowlist downgrade
    if echo "$rest" | grep -qiE "$soleur_allowlist_re"; then
      continue
    fi
    findings_lines+="$rule_id"$'\t'"$severity"$'\t'"$line"$'\t'"$snippet"$'\n'
  done < <(grep -niE -- "$regex" "$tmp.fm" 2>/dev/null || true)
done

# ---- Body rules (REVIEW with proximity gate) ----
body_proximity_re='(you[[:space:]]+(must|should)|base64|[A-Za-z0-9+/]{40,})'
body_rules=(
  'role-hijack-body|REVIEW|(ignore|disregard|forget)[[:space:]]+(all[[:space:]]+)?(previous|prior|above)'
  'sysprompt-exfil-body|REVIEW|(reveal|print|show|leak)[[:space:]]+([a-z]+[[:space:]]+){0,3}(system[[:space:]]+prompt)'
  'delim-breakout-body|REVIEW|(</system>|<\|im_(start|end)\|>)'
)
for spec in "${body_rules[@]}"; do
  IFS='|' read -r rule_id severity regex <<<"$spec"
  while IFS=':' read -r line rest; do
    [ -z "$line" ] && continue
    snippet="${rest:0:200}"
    snippet="${snippet//$'\t'/ }"
    if echo "$rest" | grep -qiE "$soleur_allowlist_re"; then
      continue
    fi
    # Proximity gate: require either you-must phrasing OR base64 nearby.
    # Approximate: search ±3 lines for proximity terms.
    start=$((line - 3 < 1 ? 1 : line - 3))
    end=$((line + 3))
    window="$(sed -n "${start},${end}p" "$tmp.body" 2>/dev/null || true)"
    if echo "$window" | grep -qiE -- "$body_proximity_re"; then
      findings_lines+="$rule_id"$'\t'"$severity"$'\t'"$line"$'\t'"$snippet"$'\n'
    fi
  done < <(grep -niE -- "$regex" "$tmp.body" 2>/dev/null || true)
done

# ---- Zero-width characters anywhere → REVIEW ----
# U+200B U+200C U+200D U+FEFF
if grep -nP -- '[\x{200B}\x{200C}\x{200D}\x{FEFF}]' "$tmp" >/dev/null 2>&1; then
  while IFS=':' read -r line rest; do
    [ -z "$line" ] && continue
    findings_lines+="zero-width-char"$'\t'"REVIEW"$'\t'"$line"$'\t'"<zero-width-char>"$'\n'
  done < <(grep -nP -- '[\x{200B}\x{200C}\x{200D}\x{FEFF}]' "$tmp" 2>/dev/null || true)
fi

verdict="$(printf '%s' "$findings_lines" | findings_to_verdict)"
findings_json="$(printf '%s' "$findings_lines" | build_findings_array)"

emit_result "$verdict" "prompt-injection" "$findings_json"
