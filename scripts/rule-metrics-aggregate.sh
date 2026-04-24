#!/usr/bin/env bash
# Weekly aggregator: parse AGENTS.md rule IDs + .claude/.rule-incidents.jsonl
# and write knowledge-base/project/rule-metrics.json.
#
# Output schema (plan Phase 5):
#   {
#     "schema": 1,
#     "generated_at": "<ISO 8601>",
#     "rules": [{id, section, hit_count, bypass_count, prevented_errors,
#                last_hit, first_seen}, ...],
#     "summary": {total_rules_tagged, rules_unused_over_8w, rules_bypassed_over_baseline,
#                 orphan_rule_ids}
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
# shellcheck source=lib/rule-metrics-constants.sh
source "$SCRIPT_DIR/lib/rule-metrics-constants.sh"

REPO_ROOT="${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

AGENTS_MD="$REPO_ROOT/AGENTS.md"
INCIDENTS="$REPO_ROOT/.claude/.rule-incidents.jsonl"
OUT="$REPO_ROOT/knowledge-base/project/rule-metrics.json"

[[ -f "$AGENTS_MD" ]] || { echo "ERROR: $AGENTS_MD not found" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

# Threshold: rules with no hits in N weeks considered "unused" (default 8).
UNUSED_WEEKS=$UNUSED_WEEKS_DEFAULT
UNUSED_CUTOFF_EPOCH=$(( $(date -u +%s) - UNUSED_WEEKS * 7 * 86400 ))

# Work area — TSV materialization plus the final-report tmpfile live here.
_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

# --- Parse AGENTS.md into id + section tuples -----------------------------
# Output format (one line per rule): "<id>\t<section>\t<prefix>"
rules_tsv=$(awk -v plen="$RULE_PREFIX_LEN" '
  /^## / { section=$0; sub(/^## /, "", section); next }
  section != "" && /^- / {
    # Extract the first [id: <slug>] on the line
    if (match($0, /\[id: [a-z0-9-]+\]/)) {
      id = substr($0, RSTART+5, RLENGTH-6)
      # First ~plen chars of the bullet body for prefix/forensics
      line = $0
      sub(/^- /, "", line)
      sub(/ ?\[id:[^]]+\]/, "", line)
      prefix = substr(line, 1, plen)
      gsub(/\t/, " ", prefix)
      printf "%s\t%s\t%s\n", id, section, prefix
    }
  }
' "$AGENTS_MD")

# Materialize the TSV to a real file — jq --rawfile is happier with a path
# than a process substitution when the producer is long-lived.
rules_tsv_file="$_tmpdir/rules.tsv"
printf '%s' "$rules_tsv" > "$rules_tsv_file"

# Guard against an AGENTS.md that parses to zero rules — otherwise the
# aggregator would silently emit a valid-but-empty report and callers
# (compound SKILL.md step 8, /soleur:sync rule-prune) would see
# `total_rules_tagged: 0` with no error signal. This is a malformed-input
# condition, not a normal state.
if [[ ! -s "$rules_tsv_file" ]]; then
  echo "ERROR: $AGENTS_MD parsed to zero rules — check section headers and [id: ...] tags." >&2
  exit 3
fi

# --- Counts from jsonl ----------------------------------------------------
# Per-line parse via `jq -R 'fromjson?'` so a single malformed line from a
# crash-mid-write or OOM does NOT abort the whole weekly aggregation. Bad
# lines are dropped with a stderr warning; valid lines are still counted.
jq_counts='{}'
if [[ -s "$INCIDENTS" ]]; then
  total_lines=$(wc -l < "$INCIDENTS")
  # Tolerant parse: fromjson? yields null on parse failure; select(.) drops nulls.
  valid_stream=$(jq -R 'fromjson? | select(.)' < "$INCIDENTS" 2>/dev/null || echo "")
  valid_lines=0
  if [[ -n "$valid_stream" ]]; then
    # `|| echo 0` + `${…:-0}` protect the arithmetic below from a failed
    # second-stage jq (e.g., missing jq binary, corrupt internals). Both
    # guards are defensive — a successful first-stage `jq -R` makes a
    # broken second-stage parse exceedingly unlikely.
    valid_lines=$(echo "$valid_stream" | jq -s 'length' 2>/dev/null || echo 0)
    valid_lines=${valid_lines:-0}
  fi
  bad_lines=$(( total_lines - valid_lines ))
  if [[ "$bad_lines" -gt 0 ]]; then
    # GitHub Actions picks up `::warning::` for workflow annotations; harmless locally.
    echo "::warning::Dropped $bad_lines malformed line(s) from $INCIDENTS (kept $valid_lines)" >&2
  fi
  if [[ "$valid_lines" -gt 0 ]]; then
    # fire_count increments on any recognized event_type (deny, bypass,
    # applied, warn). Unknown event_types do not increment fire_count —
    # they are silently skipped so a typo'd emit call does not inflate the
    # "rule fired" signal used by rule-prune.
    jq_counts=$(echo "$valid_stream" | jq -s '
      reduce .[] as $e ({};
        (.[$e.rule_id] //= {hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, last_hit:null, first_seen:null}) |
        (if $e.event_type == "deny"    then .[$e.rule_id].hit_count     += 1 else . end) |
        (if $e.event_type == "bypass"  then .[$e.rule_id].bypass_count  += 1 else . end) |
        (if $e.event_type == "applied" then .[$e.rule_id].applied_count += 1 else . end) |
        (if $e.event_type == "warn"    then .[$e.rule_id].warn_count    += 1 else . end) |
        (if ($e.event_type == "deny" or $e.event_type == "bypass" or $e.event_type == "applied" or $e.event_type == "warn")
           then .[$e.rule_id].fire_count += 1 else . end) |
        (if .[$e.rule_id].first_seen == null or ($e.timestamp < .[$e.rule_id].first_seen)
           then .[$e.rule_id].first_seen = $e.timestamp else . end) |
        (if .[$e.rule_id].last_hit   == null or ($e.timestamp > .[$e.rule_id].last_hit)
           then .[$e.rule_id].last_hit   = $e.timestamp else . end)
      )
    ')
  fi
fi

# --- Stitch rules + counts into the final report --------------------------
# Pipeline split into three sequential jq stages, each gated by `jq empty`
# so an off-by-one in one stage fails loudly instead of producing bogus JSON.
#   Stage A (_parse_rules) — raw TSV → $rules array
#   Stage B (_enrich)      — $rules + $counts → $enriched
#   Stage C (_summarize)   — $enriched → final top-level object
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

stage_rules=$(jq -n \
  --rawfile rules_tsv "$rules_tsv_file" '
    $rules_tsv
    | split("\n")
    | map(select(length > 0))
    | map(split("\t"))
    | map({id: .[0], section: .[1], rule_text_prefix: .[2]})
  ')
echo "$stage_rules" | jq empty >/dev/null 2>&1 || { echo "ERROR: stage A (rules parse) malformed" >&2; exit 4; }

stage_enriched=$(jq -n \
  --argjson rules "$stage_rules" \
  --argjson counts "$jq_counts" '
    $rules
    | map(
        . as $r
        | ($counts[$r.id] // {hit_count:0, bypass_count:0, applied_count:0, warn_count:0, fire_count:0, last_hit:null, first_seen:null}) as $c
        | {
            id: $r.id,
            section: $r.section,
            hit_count: $c.hit_count,
            bypass_count: $c.bypass_count,
            applied_count: $c.applied_count,
            warn_count: $c.warn_count,
            fire_count: $c.fire_count,
            prevented_errors: ([$c.hit_count - $c.bypass_count, 0] | max),
            last_hit: $c.last_hit,
            first_seen: $c.first_seen,
            rule_text_prefix: $r.rule_text_prefix
          }
      )
    | sort_by(.fire_count, .id)
  ')
echo "$stage_enriched" | jq empty >/dev/null 2>&1 || { echo "ERROR: stage B (enrich) malformed" >&2; exit 4; }

report=$(jq -n \
  --argjson schema "$SCHEMA_VERSION" \
  --arg generated_at "$GENERATED_AT" \
  --argjson enriched "$stage_enriched" \
  --argjson counts "$jq_counts" \
  --argjson cutoff "$UNUSED_CUTOFF_EPOCH" '
    # Orphan events: rule_ids in the jsonl that don'"'"'t match any AGENTS.md id.
    # Surfacing these prevents silent data loss when a hook emits a rule_id
    # that was renamed / removed / never tagged (e.g., historical sentinel names).
    ($enriched | map(.id)) as $known_ids
    | ($counts | keys | map(select(. as $id | ($known_ids | index($id)) | not))) as $orphan_ids
    | {
        schema: $schema,
        generated_at: $generated_at,
        rules: $enriched,
        summary: {
          total_rules_tagged: ($enriched | length),
          # first_seen may be null (rule exists in AGENTS.md, never emitted)
          # or a malformed timestamp string (crash-mid-write). try/catch
          # treats parse failure as epoch 0 — pushes the rule into "unused"
          # which matches intent: we can'"'"'t prove recent activity.
          rules_unused_over_8w: ($enriched
            | map(select(.fire_count == 0
                and (.first_seen == null
                     or (try (.first_seen | fromdateiso8601) catch 0) < $cutoff)))
            | length),
          rules_bypassed_over_baseline: ($enriched
            | map(select(.bypass_count > 0))
            | length),
          orphan_rule_ids: $orphan_ids
        }
      }
  ')
echo "$report" | jq empty >/dev/null 2>&1 || { echo "ERROR: stage C (summarize) malformed" >&2; exit 4; }

# Schema field assertion — shape-gate so downstream consumers can trust the
# field is present without defensive `// null` in every reader.
echo "$report" | jq -e '.schema == 1' >/dev/null 2>&1 \
  || { echo "ERROR: rule-metrics output missing or wrong schema version" >&2; exit 4; }

# Orphan invariant: any rule_id emitted by a hook / skill that is not tagged
# in AGENTS.md indicates drift (renamed rule, typo in snippet, dead rule-id).
# Weekly cron surfaces this as a failing workflow step — the next run is a
# silent normalization otherwise.
orphan_count=$(echo "$report" | jq -r '.summary.orphan_rule_ids | length')
if [[ "${orphan_count:-0}" -gt 0 ]]; then
  orphan_list=$(echo "$report" | jq -r '.summary.orphan_rule_ids | join(", ")')
  echo "ERROR: orphan rule_id(s) in incidents jsonl not tagged in AGENTS.md: $orphan_list" >&2
  exit 5
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "$report" | jq '{schema, generated_at, summary}'
  exit 0
fi

# --- Materially-changed write (R5 mitigation) -----------------------------
# Compare against existing file ignoring generated_at so cron Sunday runs
# don't produce diff-noise-only commits. `jq -S` sorts keys so ordering
# differences (e.g., a jq pipeline refactor that swaps two object fields)
# don't trigger a spurious rewrite.
write=1
if [[ -f "$OUT" ]]; then
  existing_body=$(jq -S 'del(.generated_at)' < "$OUT" 2>/dev/null || echo "")
  new_body=$(echo "$report" | jq -S 'del(.generated_at)')
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
#
# Flock re-entrancy: `flock -x 9 … 9>>"$INCIDENTS"` acquires the same
# file-backed lock that the hook-writer's emit_incident acquires. Both use
# `-x` (exclusive), both target the same inode — they queue behind each
# other. Moving to a different fd would create two separate locks on the
# same inode and reintroduce the rotate/write race.
if [[ "${AGGREGATOR_ROTATE:-0}" == "1" && -s "$INCIDENTS" ]]; then
  ts=$(date -u +%Y-%m)
  archive="$REPO_ROOT/.claude/.rule-incidents-${ts}.jsonl"
  # Uniquify BEFORE entering the flock subshell — subshell variable
  # assignments do not propagate back, so reassigning `archive` inside
  # would leave the outer gzip pointing at a non-existent basename.
  # An already-rotated `.gz` or a lingering uncompressed file from a
  # mid-run crash both count as "already exists" here; we append to a
  # fresh suffixed name rather than clobbering.
  # Suffix uses nanoseconds so two rotations within the same second (rare
  # in production, common in tests) do not re-collide. Tests may override
  # the suffix via RULE_METRICS_ROTATE_SUFFIX for deterministic paths.
  if [[ -f "${archive}.gz" || -f "$archive" ]]; then
    suffix="${RULE_METRICS_ROTATE_SUFFIX:-$(date -u +%H%M%S%N)}"
    archive="$REPO_ROOT/.claude/.rule-incidents-${ts}-${suffix}.jsonl"
  fi
  (
    flock -x 9
    cat "$INCIDENTS" >> "$archive"
    : > "$INCIDENTS"
  ) 9>>"$INCIDENTS"
  gzip -f "$archive" 2>/dev/null || true
  echo "Rotated $INCIDENTS to $archive.gz"
fi
