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
#
# Cross-stream contract: hook emits namespaced names ("soleur:plan"),
# inventory walks bare directory names ("plan"). The join normalizes
# via `bare = split(":") | last`. Any test that touches the join MUST
# include at least one fixture per producer's production format —
# bare-only fixtures hide format-mismatch bugs (see learning
# 2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md).

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
# Single-pass parse with `fromjson?` for malformed-line tolerance and
# schema-version pinning at the consumer boundary. `fromjson?` swallows
# parse errors (returns empty), `select(.schema == 1 ...)` drops anything
# that isn't a v1 record. One jq fork regardless of file size.
bad_lines=0
parsed_count=0
if [[ -f "$INVOCATIONS" ]]; then
  total_lines=$(wc -l < "$INVOCATIONS" 2>/dev/null || echo 0)
  parsed_records=$(jq -c -R 'fromjson? | select(.schema == 1 and .skill != null and (.ts | type) == "string")' < "$INVOCATIONS" 2>/dev/null || true)
  parsed_count=$(printf '%s' "$parsed_records" | grep -c '^' || true)
  bad_lines=$((total_lines - parsed_count))
  [[ "$bad_lines" -lt 0 ]] && bad_lines=0

  if [[ "$bad_lines" -gt 0 ]]; then
    echo "::warning::Dropped $bad_lines malformed line(s) from $INVOCATIONS" >&2
  fi

  if [[ -n "$parsed_records" ]]; then
    invocations_json=$(printf '%s' "$parsed_records" \
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
    --argjson bad_lines "$bad_lines" \
    --arg generated_at "$now_iso" '
      # Normalize namespaced skill names ("soleur:plan") to bare names
      # ("plan") so they join against the directory-name inventory.
      def bare: split(":") | last;
      ($invocations | map({key: (.skill | bare), value: .}) | from_entries) as $by_skill
      |
      (($invocations | map(.skill | bare)) - $inventory) as $orphan_skills
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
      ) | sort_by(.name)) as $skills
      |
      {
        schema: 1,
        generated_at: $generated_at,
        skills: $skills,
        summary: {
          total_skills: ($skills | length),
          idle_180d: ($skills | map(select(.status == "idle")) | length),
          idle_365d: ($skills | map(select(.status == "archival_candidate")) | length),
          never_invoked: ($skills | map(select(.status == "never_invoked")) | length),
          orphan_skills: $orphan_skills,
          bad_jsonl_lines: $bad_lines
        }
      }
  '
)

# Surface orphan skills as a CI warning (renamed/deleted skills with stale logs).
orphan_count=$(echo "$report" | jq -r '.summary.orphan_skills | length')
if [[ "$orphan_count" -gt 0 ]]; then
  orphan_names=$(echo "$report" | jq -r '.summary.orphan_skills | join(", ")')
  echo "::warning::Found $orphan_count orphan skill(s) in invocation log (likely renamed/deleted): $orphan_names" >&2
fi

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
  trap 'rm -f "$OUT.tmp"' EXIT
  echo "$report" > "$OUT.tmp"
  jq empty "$OUT.tmp" >/dev/null 2>&1 || { echo "ERROR: tmp file malformed (try --dry-run to inspect output)" >&2; exit 5; }
  mv "$OUT.tmp" "$OUT" || { echo "ERROR: mv $OUT.tmp -> $OUT failed (check filesystem permissions)" >&2; exit 6; }
  trap - EXIT
  echo "Wrote $OUT (total_skills=$(jq -r '.summary.total_skills' < "$OUT"), idle_180d=$(jq -r '.summary.idle_180d' < "$OUT"), idle_365d=$(jq -r '.summary.idle_365d' < "$OUT"), never_invoked=$(jq -r '.summary.never_invoked' < "$OUT"))"
else
  echo "No material change to $OUT"
fi
