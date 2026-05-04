#!/usr/bin/env bash
# Skill freshness aggregator (Track C3 of #3122).
#
# Builds a per-skill freshness report from:
#   1. Skill inventory walked from plugins/soleur/skills/*/SKILL.md
#   2. Invocation log .claude/.skill-invocations.jsonl (gitignored, may be
#      empty in CI runs — that's OK, output is then "all skills never_invoked")
#
# Output: knowledge-base/engineering/operations/skill-freshness.json
#
# Schema:
#   {
#     "schema": 1,
#     "generated_at": "<ISO 8601 UTC>",
#     "skills": [
#       {
#         "name": "<skill-name>",
#         "last_invoked": "<ISO 8601 UTC>" | null,
#         "invocation_count": <int>,
#         "days_since_last": <int> | null,
#         "status": "fresh" | "idle" | "archival_candidate" | "never_invoked"
#       },
#       ...
#     ],
#     "summary": {
#       "total_skills": <int>,
#       "idle_180d": <int>,
#       "idle_365d": <int>,
#       "never_invoked": <int>
#     }
#   }
#
# Status thresholds:
#   fresh                <180 days since last_invoked
#   idle                 ≥180 and <365 days
#   archival_candidate   ≥365 days
#   never_invoked        no invocations recorded
#
# Materially-changed write: existing skill-freshness.json is unchanged unless
# the report differs (ignoring generated_at). Mirrors rule-metrics-aggregate.sh.
#
# Mirrors precedent at scripts/rule-metrics-aggregate.sh and
# .claude/hooks/lib/incidents.sh canonical-path resolution.
#
# Flags:
#   --dry-run   print the JSON to stdout; do not write skill-freshness.json
#
# Tests set SKILL_FRESHNESS_REPO_ROOT to redirect reads/writes off the
# operator's real .claude/.skill-invocations.jsonl and the canonical
# knowledge-base output path.

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SKILL_FRESHNESS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

SKILLS_DIR="$REPO_ROOT/plugins/soleur/skills"
INVOCATIONS="$REPO_ROOT/.claude/.skill-invocations.jsonl"
OUT="$REPO_ROOT/knowledge-base/engineering/operations/skill-freshness.json"

# --- Build skill inventory -----------------------------------------------
# Walk SKILL.md files. The skill name is the parent directory name.
[[ -d "$SKILLS_DIR" ]] || { echo "ERROR: $SKILLS_DIR not found" >&2; exit 2; }

# Materialize inventory as a JSON array of skill names.
inventory_json=$(
  find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md -print 2>/dev/null \
    | awk -F/ '{print $(NF-1)}' \
    | sort -u \
    | jq -R -s -c 'split("\n") | map(select(length > 0))'
)
total_skills=$(echo "$inventory_json" | jq -r 'length')
[[ "$total_skills" -gt 0 ]] || { echo "ERROR: no skills found under $SKILLS_DIR" >&2; exit 2; }

# --- Parse invocation log ------------------------------------------------
# Tolerant of missing file and malformed lines (per learning
# 2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md).
if [[ -f "$INVOCATIONS" ]]; then
  # Tolerate malformed lines: parse line-by-line. A pipe-based
  # `jq -c < file` aborts the entire stream on the first parse error
  # (subsequent valid lines are dropped). The `|| true` after a pipeline
  # only catches the exit code — it doesn't recover already-aborted stdout.
  # Per-line filtering with each `jq` call independent gives true
  # tolerance: malformed lines are silently skipped, valid lines flow through.
  parsed_lines=""
  while IFS= read -r line; do
    valid=$(echo "$line" | jq -c 'select(.skill != null)' 2>/dev/null || true)
    if [[ -n "$valid" ]]; then
      parsed_lines+="$valid"$'\n'
    fi
  done < "$INVOCATIONS"

  if [[ -n "$parsed_lines" ]]; then
    invocations_json=$(printf '%s' "$parsed_lines" \
                       | jq -s -c 'group_by(.skill)
                                   | map({
                                       skill: .[0].skill,
                                       last_invoked: (map(.ts) | sort | last),
                                       invocation_count: length
                                     })')
  else
    invocations_json='[]'
  fi
else
  invocations_json='[]'
fi

# --- Build per-skill freshness records -----------------------------------
mkdir -p "$(dirname "$OUT")"

now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
now_epoch=$(date -u +%s)
threshold_idle=$((180 * 86400))
threshold_archival=$((365 * 86400))

report=$(
  jq -n \
    --argjson inventory "$inventory_json" \
    --argjson invocations "$invocations_json" \
    --argjson now_epoch "$now_epoch" \
    --argjson idle_secs "$threshold_idle" \
    --argjson archival_secs "$threshold_archival" \
    --arg generated_at "$now_iso" '
      # Group invocations by skill name for fast lookup.
      ($invocations | map({key: .skill, value: .}) | from_entries) as $by_skill
      |
      ($inventory | map(
        . as $name
        | ($by_skill[$name] // null) as $inv
        | if $inv == null then
            {
              name: $name,
              last_invoked: null,
              invocation_count: 0,
              days_since_last: null,
              status: "never_invoked"
            }
          else
            ($inv.last_invoked | fromdateiso8601) as $last_epoch
            | ($now_epoch - $last_epoch) as $age_secs
            | {
                name: $name,
                last_invoked: $inv.last_invoked,
                invocation_count: $inv.invocation_count,
                days_since_last: ($age_secs / 86400 | floor),
                status: (
                  if   $age_secs >= $archival_secs then "archival_candidate"
                  elif $age_secs >= $idle_secs     then "idle"
                  else "fresh"
                  end
                )
              }
          end
      )) as $skills
      |
      {
        schema: 1,
        generated_at: $generated_at,
        skills: $skills,
        summary: {
          total_skills: ($skills | length),
          idle_180d: ($skills | map(select(.status == "idle")) | length),
          idle_365d: ($skills | map(select(.status == "archival_candidate")) | length),
          never_invoked: ($skills | map(select(.status == "never_invoked")) | length)
        }
      }
  '
)

# Schema-version sanity (matches rule-metrics-aggregate.sh shape-gate).
echo "$report" | jq -e '.schema == 1' >/dev/null 2>&1 \
  || { echo "ERROR: skill-freshness output missing or wrong schema version" >&2; exit 4; }

if [[ "$DRY_RUN" == "1" ]]; then
  echo "$report" | jq '.'
  exit 0
fi

# --- Materially-changed write --------------------------------------------
# Skip the write (and PR diff noise) if only generated_at changed.
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
  echo "Wrote $OUT (total_skills=$(jq -r '.summary.total_skills' < "$OUT"), idle_180d=$(jq -r '.summary.idle_180d' < "$OUT"), idle_365d=$(jq -r '.summary.idle_365d' < "$OUT"), never_invoked=$(jq -r '.summary.never_invoked' < "$OUT"))"
else
  echo "No material change to $OUT"
fi
