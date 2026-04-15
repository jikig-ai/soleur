#!/usr/bin/env bash
# Weekly aggregator: parse AGENTS.md rule IDs + .claude/.rule-incidents.jsonl
# and write knowledge-base/project/rule-metrics.json.
#
# Output schema (plan Phase 5):
#   {
#     "generated_at": "<ISO 8601>",
#     "rules": [{id, section, hit_count, bypass_count, prevented_errors,
#                last_hit, first_seen}, ...],
#     "summary": {total_rules_tagged, rules_unused_over_8w, rules_bypassed_over_baseline}
#   }
#
# Honors $INCIDENTS_REPO_ROOT for tests (falls back to the repo this script
# lives in).
#
# Flags:
#   --dry-run   print the JSON to stdout; do not write rule-metrics.json
#               and do not rotate jsonl.
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

AGENTS_MD="$REPO_ROOT/AGENTS.md"
INCIDENTS="$REPO_ROOT/.claude/.rule-incidents.jsonl"
OUT="$REPO_ROOT/knowledge-base/project/rule-metrics.json"

[[ -f "$AGENTS_MD" ]] || { echo "ERROR: $AGENTS_MD not found" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# Threshold: rules with no hits in 8 weeks considered "unused".
UNUSED_WEEKS=8
UNUSED_CUTOFF_EPOCH=$(( $(date -u +%s) - UNUSED_WEEKS * 7 * 86400 ))

# --- Parse AGENTS.md into id + section tuples -----------------------------
# Output format (one line per rule): "<id>\t<section>\t<prefix>"
rules_tsv=$(awk '
  /^## / { section=$0; sub(/^## /, "", section); next }
  section != "" && /^- / {
    # Extract the first [id: <slug>] on the line
    if (match($0, /\[id: [a-z0-9-]+\]/)) {
      id = substr($0, RSTART+5, RLENGTH-6)
      # First ~50 chars of the bullet body for prefix/forensics
      line = $0
      sub(/^- /, "", line)
      sub(/ ?\[id:[^]]+\]/, "", line)
      prefix = substr(line, 1, 50)
      gsub(/\t/, " ", prefix)
      printf "%s\t%s\t%s\n", id, section, prefix
    }
  }
' "$AGENTS_MD")

# --- Counts from jsonl ----------------------------------------------------
# `jq -s` reads the whole stream. Empty / missing file is handled gracefully.
jq_counts='{}'
if [[ -s "$INCIDENTS" ]]; then
  # Build {rule_id: {deny, bypass, last_hit, first_seen}}
  if ! jq -s . "$INCIDENTS" >/dev/null 2>&1; then
    echo "ERROR: $INCIDENTS contains malformed JSON" >&2
    exit 3
  fi
  jq_counts=$(jq -s '
    reduce .[] as $e ({};
      (.[$e.rule_id] //= {hit_count:0, bypass_count:0, last_hit:null, first_seen:null}) |
      (if $e.event_type == "deny"  then .[$e.rule_id].hit_count    += 1 else . end) |
      (if $e.event_type == "bypass" then .[$e.rule_id].bypass_count += 1 else . end) |
      (if .[$e.rule_id].first_seen == null or ($e.timestamp < .[$e.rule_id].first_seen)
         then .[$e.rule_id].first_seen = $e.timestamp else . end) |
      (if .[$e.rule_id].last_hit   == null or ($e.timestamp > .[$e.rule_id].last_hit)
         then .[$e.rule_id].last_hit   = $e.timestamp else . end)
    )
  ' "$INCIDENTS")
fi

# --- Stitch rules + counts into the final report --------------------------
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Stream rules_tsv to jq, merge with counts, sort by hit_count ASC.
report=$(jq -n \
  --arg generated_at "$GENERATED_AT" \
  --argjson counts "$jq_counts" \
  --argjson cutoff "$UNUSED_CUTOFF_EPOCH" \
  --rawfile rules_tsv <(printf '%s' "$rules_tsv") '
    ($rules_tsv | split("\n") | map(select(length > 0)) | map(split("\t")) |
     map({id: .[0], section: .[1], rule_text_prefix: .[2]})) as $rules |
    ($rules | map(
      . as $r |
      ($counts[$r.id] // {hit_count:0, bypass_count:0, last_hit:null, first_seen:null}) as $c |
      {
        id: $r.id,
        section: $r.section,
        hit_count: $c.hit_count,
        bypass_count: $c.bypass_count,
        prevented_errors: ([$c.hit_count - $c.bypass_count, 0] | max),
        last_hit: $c.last_hit,
        first_seen: $c.first_seen,
        rule_text_prefix: $r.rule_text_prefix
      }
    ) | sort_by(.hit_count, .id)) as $enriched |
    {
      generated_at: $generated_at,
      rules: $enriched,
      summary: {
        total_rules_tagged: ($enriched | length),
        rules_unused_over_8w: ($enriched
          | map(select(.hit_count == 0 and (.first_seen == null or (.first_seen | fromdateiso8601) < $cutoff)))
          | length),
        rules_bypassed_over_baseline: ($enriched
          | map(select(.bypass_count > 0))
          | length)
      }
    }
  ')

# --- jq empty gate on the constructed JSON (Kieran review) ----------------
if ! echo "$report" | jq empty >/dev/null 2>&1; then
  echo "ERROR: constructed rule-metrics is malformed" >&2
  exit 4
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "$report" | jq '{generated_at, summary}'
  exit 0
fi

# --- Materially-changed write (R5 mitigation) -----------------------------
# Compare against existing file ignoring generated_at so cron Sunday runs
# don't produce diff-noise-only commits.
write=1
if [[ -f "$OUT" ]]; then
  existing_body=$(jq 'del(.generated_at)' < "$OUT" 2>/dev/null || echo "")
  new_body=$(echo "$report" | jq 'del(.generated_at)')
  if [[ "$existing_body" == "$new_body" ]]; then
    write=0
  fi
fi

if [[ "$write" == "1" ]]; then
  echo "$report" > "$OUT.tmp"
  jq empty "$OUT.tmp" >/dev/null 2>&1 || { echo "ERROR: tmp file malformed" >&2; rm -f "$OUT.tmp"; exit 5; }
  mv "$OUT.tmp" "$OUT"
  echo "Wrote $OUT"
else
  echo "No material change to $OUT"
fi

# --- Rotate jsonl after a successful aggregation --------------------------
# Scope down: only rotate when we're in a real CI/aggregator run (not tests).
# Detection: the incidents file exists AND it's non-empty AND rotation was
# explicitly requested via env AGGREGATOR_ROTATE=1 (default off to keep
# tests deterministic).
if [[ "${AGGREGATOR_ROTATE:-0}" == "1" && -s "$INCIDENTS" ]]; then
  ts=$(date -u +%Y-%m)
  archive="$REPO_ROOT/.claude/.rule-incidents-${ts}.jsonl"
  # Append rather than clobber if a monthly archive already exists
  cat "$INCIDENTS" >> "$archive"
  gzip -f "$archive" 2>/dev/null || true
  : > "$INCIDENTS"
  echo "Rotated $INCIDENTS to $archive.gz"
fi
