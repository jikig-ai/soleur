#!/usr/bin/env bash
# Shared helpers for skill-security-scan check-*.sh scripts.
#
# Usage from caller:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/lib.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Verdict aggregation
#
# `aggregate_verdict <severity1> [<severity2> ...]` echoes the max severity
# across the inputs. Empty input → LOW-RISK.
#
# Order: HIGH-RISK > REVIEW > LOW-RISK. WARN is finding-level metadata only;
# at script level it should be passed in as REVIEW (per plan Phase 3 WARN-tier
# semantics).
# ---------------------------------------------------------------------------
aggregate_verdict() {
  local v="LOW-RISK"
  local s
  for s in "$@"; do
    case "$s" in
      HIGH-RISK) echo "HIGH-RISK"; return 0 ;;
      REVIEW)    v="REVIEW" ;;
      LOW-RISK)  : ;;
      *)         : ;;  # ignore unknown
    esac
  done
  echo "$v"
}

# ---------------------------------------------------------------------------
# Emit a category result as JSON. Invoked at end of every check-*.sh.
#
# Usage: emit_result <verdict> <category> <findings_json_array>
#   - verdict: LOW-RISK | REVIEW | HIGH-RISK
#   - category: code-execution | prompt-injection | supply-chain |
#               filesystem-boundary | telemetry-surface
#   - findings_json_array: a JSON array string (use build_findings to assemble)
# ---------------------------------------------------------------------------
#
# ARGV CEILING (#6736). The findings array arrives here as a shell variable and is
# fed to jq on STDIN, never as an `--argjson` argument. `--argjson f "$findings_json"`
# makes the whole array ONE argv argument, and the kernel caps a SINGLE argv argument
# at MAX_ARG_STRLEN = 131,072 B — verified by bisect on this host: 131,071 B passes,
# 131,072 B fails E2BIG. This is NOT `getconf ARG_MAX` (2,097,152 B, the argv+envp
# total); a payload at 6% of ARG_MAX still dies.
#
# This is the only genuinely UNBOUNDED site in the scanner. `apply_yaml_rules` caps
# each snippet at 200 chars, but nothing caps the FINDING COUNT: one grep hit per
# matching line, over a file of any length. At ~265 B/finding the ceiling lands at
# ~490 findings — and this repo already carries a 220,523 B SKILL.md.
#
# The failure was SILENT, which is why it is worth a comment: run-scan.sh invokes each
# category as `bash check-*.sh … || echo '{"…check-failed…"}'`, so an E2BIG here is
# swallowed into a "category script error" placeholder and the scan reports a REVIEW
# verdict with ZERO real findings instead of the hundreds it actually found.
#
# A pipe has no size limit and streams, so this needs no spool file and no cleanup
# trap (unlike the --rawfile form used in run-scan.sh, which already owns a tmpdir).
emit_result() {
  local verdict="$1" category="$2" findings_json="$3"
  printf '%s' "$findings_json" | jq -c \
    --arg v "$verdict" \
    --arg c "$category" \
    '{verdict: $v, category: $c, findings: .}'
}

# ---------------------------------------------------------------------------
# Build a findings JSON array from a series of finding lines on stdin.
#
# Stdin format (one finding per line, tab-separated):
#   <rule_id>\t<severity>\t<line>\t<snippet>
# Output: JSON array suitable for emit_result.
# ---------------------------------------------------------------------------
build_findings_array() {
  jq -Rsn '
    [inputs | split("\n") | .[] | select(length > 0) |
      split("\t") |
      {rule_id: .[0], severity: .[1], line: (.[2]|tonumber? // 0), snippet: .[3]}]
  '
}

# ---------------------------------------------------------------------------
# Apply a single YAML rule pack against input content.
#
# Args:
#   $1 - path to YAML rule file
#   $2 - path to input content file (NOT stdin; needs random access)
#
# Output (stdout): tab-separated finding lines: rule_id\tseverity\tline\tsnippet
#
# Rules are extracted by line: each rule starts with `  - id: <name>` and is
# followed by `severity:` and `regex:` lines. We use a tiny awk parser rather
# than yq to keep the toolchain dependency-free (plan TR1).
# ---------------------------------------------------------------------------
apply_yaml_rules() {
  local yaml_file="$1"
  local content_file="$2"

  awk '
    /^[[:space:]]*-[[:space:]]*id:/ {
      gsub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      id = $0
      next
    }
    /^[[:space:]]+severity:/ {
      gsub(/^[[:space:]]+severity:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      sev = $0
      next
    }
    /^[[:space:]]+regex:/ {
      # Strip "    regex: " prefix; strip surrounding single quotes if present.
      sub(/^[[:space:]]+regex:[[:space:]]*/, "")
      sub(/^['"'"']/, "")
      sub(/['"'"']$/, "")
      print id "\t" sev "\t" $0
    }
  ' "$yaml_file" | while IFS=$'\t' read -r rule_id severity regex; do
    # Skip rule emission if any field is empty (defensive).
    [ -z "$rule_id" ] && continue
    [ -z "$severity" ] && continue
    [ -z "$regex" ] && continue
    # grep -nE: match line numbers + extended regex. Suppress errors (some
    # patterns may not match anywhere). cap match snippet to 200 chars.
    grep -nE -- "$regex" "$content_file" 2>/dev/null | while IFS=':' read -r line rest; do
      snippet="${rest:0:200}"
      # Replace tabs in snippet with spaces so output stays tab-delimited.
      snippet="${snippet//$'\t'/ }"
      printf '%s\t%s\t%s\t%s\n' "$rule_id" "$severity" "$line" "$snippet"
    done
  done
}

# ---------------------------------------------------------------------------
# Read stdin into a temporary file. Echoes the path on stdout.
# Caller is responsible for cleanup via trap.
# ---------------------------------------------------------------------------
stdin_to_tempfile() {
  local tmp
  tmp="$(mktemp -t skill-scan-XXXXXX)"
  cat > "$tmp"
  echo "$tmp"
}

# ---------------------------------------------------------------------------
# Compute aggregated severity from tab-separated finding lines on stdin.
# Echoes a single LOW-RISK | REVIEW | HIGH-RISK to stdout.
# ---------------------------------------------------------------------------
findings_to_verdict() {
  awk -F'\t' '
    { sev[$2]++ }
    END {
      if (sev["HIGH-RISK"] > 0) print "HIGH-RISK"
      else if (sev["REVIEW"] > 0) print "REVIEW"
      else print "LOW-RISK"
    }
  '
}

# ---------------------------------------------------------------------------
# yaml_list <file> <key> — emit the contents of a top-level YAML list section.
#
# Recognizes block-style lists only:
#
#   <key>:
#     - <value1>
#     - <value2>
#
# Section terminates at the next top-level key (line beginning with [a-zA-Z_]).
# Inline `# comment` suffixes are stripped. Surrounding single/double quotes
# stripped. Lines whose value resolves to empty after stripping are skipped.
#
# Does NOT mutate $0 (avoids the pattern-3 reset bug where gsub-mutated
# values match subsequent predicates).
# ---------------------------------------------------------------------------
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
