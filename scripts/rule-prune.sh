#!/usr/bin/env bash
# Surfaces AGENTS.md rules with zero hits over N weeks. Two output modes:
#
#   Default: files one GitHub issue per candidate, milestoned to
#   "Post-MVP / Later". Idempotent via `gh issue list --search` title
#   match. Used by /soleur:sync rule-prune.
#
#   --propose-retirement: appends candidates to scripts/retired-rule-ids.txt
#   in canonical format and emits stdout sentinels for the calling
#   workflow to consume into PR title/body via $GITHUB_OUTPUT. Used by the
#   quarterly .github/workflows/scheduled-rule-prune.yml (#3120 C2). The
#   workflow then opens a single consolidated PR via the
#   bot-pr-with-synthetic-checks composite action.
#
# Neither mode edits AGENTS.md — humans retire rule text in a separate PR.
# Both modes filter `^hr-` ids out (per cq-rule-ids-are-immutable + the
# hr-rule-retirement-guard). hr-* retirement requires a human edit to
# scripts/lint-rule-ids.py's HR_RETIREMENT_ALLOWLIST and is not automated.
#
# Reads knowledge-base/project/rule-metrics.json (written by
# scripts/rule-metrics-aggregate.sh). Default threshold is
# $UNUSED_WEEKS_DEFAULT (8) weeks; override with --weeks=<n>.
#
# Flags:
#   --weeks=<n>             Threshold in weeks (default 8)
#   --dry-run               Print what would be filed/appended; do not
#                           mutate state. Honored in both modes.
#   --propose-retirement    Switch to retirement-proposal mode: append
#                           candidates to scripts/retired-rule-ids.txt
#                           and emit ::rule-prune-pr-{title,body}::
#                           sentinels on stdout. Skips ^hr-* and ids
#                           already listed in retired-rule-ids.txt.
#
# Honors $RULE_METRICS_ROOT for tests (rule-metrics.json AND retired-rule-ids.txt).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/rule-metrics-constants.sh
source "$SCRIPT_DIR/lib/rule-metrics-constants.sh"

WEEKS=$UNUSED_WEEKS_DEFAULT
DRY_RUN=0
PROPOSE_RETIREMENT=0
for arg in "$@"; do
  case "$arg" in
    --weeks=*)             WEEKS="${arg#--weeks=}" ;;
    --dry-run)             DRY_RUN=1 ;;
    --propose-retirement)  PROPOSE_RETIREMENT=1 ;;
  esac
done

ROOT="${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
METRICS="$ROOT/knowledge-base/project/rule-metrics.json"

[[ -f "$METRICS" ]] || { echo "ERROR: $METRICS not found — run scripts/rule-metrics-aggregate.sh first." >&2; exit 2; }

# Schema contract: make SCHEMA_VERSION load-bearing at the consumer
# boundary. If the aggregator ever bumps to schema 2 with a different
# rules shape, this fails loudly instead of producing nonsense issues.
jq -e --argjson v "$SCHEMA_VERSION" '.schema == $v' "$METRICS" >/dev/null 2>&1 \
  || { echo "ERROR: $METRICS has unexpected schema (expected $SCHEMA_VERSION). Re-run scripts/rule-metrics-aggregate.sh." >&2; exit 3; }

# Compute cutoff epoch. Use --weeks=0 to force-match all zero-hit rules.
cutoff_epoch=$(( $(date -u +%s) - WEEKS * 7 * 86400 ))

# Emit candidate tuples: id\tsection\tfirst_seen\trule_text_prefix.
# try/catch on fromdateiso8601 mirrors the aggregator: malformed timestamps
# get treated as "seen long ago" (epoch 0 < any finite cutoff).
candidates=$(jq -r \
  --argjson cutoff "$cutoff_epoch" \
  '.rules
   | map(select(.fire_count == 0
        and (.first_seen == null
             or (try (.first_seen | fromdateiso8601) catch 0) < $cutoff)))
   | .[]
   | [.id, .section, (.first_seen // "unknown"), .rule_text_prefix]
   | @tsv' \
  "$METRICS")

# Also pull generated_at for the issue body's Verify block.
generated_at=$(jq -r '.generated_at // "unknown"' "$METRICS")

if [[ -z "$candidates" ]]; then
  echo "No prune candidates (fire_count=0 for >=${WEEKS}w)."
  exit 0
fi

candidate_count=$(printf '%s\n' "$candidates" | wc -l | tr -d ' ')

# Rule ID format regex — mirrors scripts/lint-rule-ids.py ID_RE. Kept here
# (not in rule-metrics-constants.sh) because bash ERE and Python `re`
# differ in syntax. Drift guard: a comment in lint-rule-ids.py points back
# here, and vice versa.
_RULE_ID_RE='^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$'

# --- propose-retirement mode (#3120 C2) ----------------------------------
# Parses scripts/retired-rule-ids.txt to skip already-retired ids.
# Strips leading + trailing whitespace AND internal whitespace in the id
# field; tolerates malformed rows by extracting only the id segment.
_load_retired_ids() {
  local file="$ROOT/scripts/retired-rule-ids.txt"
  [[ -f "$file" ]] || return 0
  awk '/^[^#]/ {
    sub(/^[ \t]+/,""); sub(/[ \t]+$/,"")
    if ($0 == "") next
    split($0, a, "[ \t]*\\|[ \t]*")
    gsub(/[ \t]+/, "", a[1])
    if (a[1] != "") print a[1]
  }' "$file"
}

if [[ "$PROPOSE_RETIREMENT" == "1" ]]; then
  retired_file="$ROOT/scripts/retired-rule-ids.txt"
  declare -A retired_set
  while IFS= read -r r; do
    [[ -n "$r" ]] && retired_set["$r"]=1
  done < <(_load_retired_ids)

  declare -A appended_set
  declare -a pending_lines
  appended=0
  hook_enforced=0
  today=$(date -u +%Y-%m-%d)

  # First pass: validate, filter, decide. No file mutation.
  while IFS=$'\t' read -r id section first_seen prefix; do
    # Sanitize prefix: collapse CR/LF to space so the id breadcrumb stays
    # on a single line in retired-rule-ids.txt (a stray \n in rule_text_prefix
    # would break the file's line-oriented contract).
    sanitized_prefix="${prefix//[$'\n\r']/ }"
    if [[ "$sanitized_prefix" != "$prefix" ]]; then
      echo "::warning::rule_text_prefix for $id contained CR/LF; sanitized to single line" >&2
    fi
    if ! [[ "$id" =~ $_RULE_ID_RE ]]; then
      echo "::warning::Skipping invalid rule_id: $id" >&2
      continue
    fi
    if [[ "$id" == hr-* ]]; then
      echo "[skip] hr-* retirement requires lint-rule-ids.py edit, not automated: $id"
      continue
    fi
    if [[ -n "${retired_set[$id]:-}" ]]; then
      echo "[skip] already retired: $id"
      continue
    fi
    if [[ -n "${appended_set[$id]:-}" ]]; then
      echo "[skip] duplicate candidate id (rule-metrics drift): $id"
      continue
    fi
    is_he=0
    if [[ "$sanitized_prefix" == *"[hook-enforced"* || "$sanitized_prefix" == *"[skill-enforced"* ]]; then
      is_he=1
    fi
    # Canonical retired-rule-ids.txt format:
    # <id> | YYYY-MM-DD | PR #<N> or - | <breadcrumb>
    pending_lines+=( "$id | $today | - | scheduled by rule-prune (first_seen=$first_seen, fire_count=0, hook_enforced=$is_he)" )
    appended_set["$id"]=1
    appended=$((appended + 1))
    hook_enforced=$((hook_enforced + is_he))
  done < <(printf '%s\n' "$candidates")

  if (( appended == 0 )); then
    echo "No retirement candidates for >=${WEEKS}w."
    exit 0
  fi

  # Second pass: atomic single-redirect append.
  if [[ "$DRY_RUN" != "1" ]]; then
    # Ensure parent dir exists (test fixtures sometimes seed an empty file
    # via `: > file`; production path always has a tracked file).
    mkdir -p "$(dirname "$retired_file")"
    printf '%s\n' "${pending_lines[@]}" >> "$retired_file"
  fi

  # Emit sentinels for the workflow to consume. Both lines are tr -d'd
  # defensively even though sanitized_prefix already stripped CR/LF.
  pr_title="feat(rule-prune): propose retirement of $appended rules ($hook_enforced hook/skill-enforced)"
  pr_body="Quarterly rule-prune retirement proposal: $appended rules with fire_count=0 over >=${WEEKS} weeks. Per-rule rationale in the diff. $hook_enforced flagged hook-/skill-enforced — review them carefully. Spec: knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md."
  printf '::rule-prune-pr-title::%s\n' "$(printf '%s' "$pr_title" | tr -d '\n\r')"
  printf '::rule-prune-pr-body::%s\n'  "$(printf '%s' "$pr_body"  | tr -d '\n\r')"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Done (dry-run). Pending: $appended. Hook/skill-enforced: $hook_enforced. No file written."
  else
    echo "Done. Appended: $appended. Hook/skill-enforced: $hook_enforced."
  fi
  exit 0
fi
# --- end propose-retirement mode -----------------------------------------

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Would file $candidate_count issue(s):"
  printf '%s\n' "$candidates" | while IFS=$'\t' read -r id section first_seen prefix; do
    if ! [[ "$id" =~ $_RULE_ID_RE ]]; then
      echo "::warning::Skipping invalid rule_id: $id" >&2
      continue
    fi
    echo "  - rule-prune: consider retiring $id (section=$section, first_seen=$first_seen)"
  done
  exit 0
fi

filed=0
skipped=0
skipped_invalid=0
# Process substitution so counter mutations land in the parent shell,
# not a subshell created by a pipeline.
while IFS=$'\t' read -r id section first_seen prefix; do
  if ! [[ "$id" =~ $_RULE_ID_RE ]]; then
    # Reject early — feeding an unvalidated id into `gh issue list --search`
    # is both a data-quality violation (we'd file an issue for a row that
    # couldn't possibly have come from AGENTS.md) and a minor injection
    # surface (id becomes part of the --search query string).
    echo "::warning::Skipping invalid rule_id: $id" >&2
    skipped_invalid=$((skipped_invalid + 1))
    continue
  fi
  title="rule-prune: consider retiring $id"
  # Idempotency: does an open issue with this exact title already exist?
  # --json title forces JSON output; without it, `gh` emits a TSV table
  # that jq would silently error on via the `|| echo "0"` tail (working
  # by accident — we'd re-file every time gh's default format changed).
  existing=$(gh issue list --search "$title in:title" --json title 2>/dev/null \
    | jq --arg t "$title" '[.[] | select(.title == $t)] | length' 2>/dev/null \
    || echo "0")
  if [[ "${existing:-0}" -gt 0 ]]; then
    echo "[skip] issue already exists: $title"
    skipped=$((skipped + 1))
    continue
  fi

  # Build body in a tempfile — avoids multi-line CLI arg pitfalls.
  # Unquoted heredoc (<<BODY) interpolates $id/$prefix/$section/$WEEKS/
  # $first_seen/$generated_at. Every backslash-backtick escapes a literal
  # backtick so bash does not command-substitute inside the body.
  body_file=$(mktemp)
  cat > "$body_file" <<BODY
- **Rule:** \`$id\`
- **Text (first 50 chars):** $prefix
- **Section:** $section
- **fire_count:** 0 over >=${WEEKS} weeks (no deny, bypass, applied, or warn events)
- **First seen:** $first_seen

### Verify

\`\`\`
jq '.rules[] | select(.id=="$id")' knowledge-base/project/rule-metrics.json
\`\`\`

Based on metrics generated at: \`$generated_at\`

### Reassessment criteria

Re-run \`/soleur:sync rule-prune\` in 4 weeks. If \`hit_count\` is still 0 and
no bypasses were recorded, propose removal in \`AGENTS.md\` via a normal PR.

### This issue does NOT authorize removal

A human must edit \`AGENTS.md\` and open a PR. Rules protecting rare but
catastrophic failures (e.g., \`hr-never-git-stash-in-worktrees\`) may have
zero hits and still be load-bearing.

_Filed by \`scripts/rule-prune.sh --weeks=${WEEKS}\`. See plan #2210._
BODY

  if gh issue create \
    --title "$title" \
    --body-file "$body_file" \
    --milestone "Post-MVP / Later" >/dev/null; then
    echo "[filed] $title"
    filed=$((filed + 1))
  fi
  rm -f "$body_file"
done < <(printf '%s\n' "$candidates")

echo "Done. Candidates: $candidate_count. Filed: $filed. Skipped: $skipped. Invalid: $skipped_invalid."
