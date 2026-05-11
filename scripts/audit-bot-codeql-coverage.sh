#!/usr/bin/env bash
# Audit CodeQL coverage on bot PRs (R15 follow-up D2, #3545).
#
# Empirically verifies that the `CodeQL` required status check on the
# `CI Required` ruleset (#14145388) is being satisfied on bot-authored PRs.
# CodeQL is pinned to integration_id 57789 (github-advanced-security app);
# default setup runs on every PR and concludes `neutral` when no analyzable
# changes are in scope. Per GitHub Docs, `neutral` satisfies required checks.
# This audit confirms that behavior across the live bot-workflow inventory.
#
# Exit codes:
#   0  — pass (all sampled bot PRs have CodeQL conclusion ∈ {success, neutral, skipped})
#   1  — drift (a bot PR has CodeQL missing, failure, cancelled, timed_out, or wrong app)
#   2  — re-poll required (a bot PR has CodeQL still in_progress)
#
# Flags:
#   --limit N       per-workflow PR sample size (default 5)
#   --json          structured envelope on stdout; human prose on stderr
#   --dry-run       skip telemetry write
#   --workflows X,Y override workflow enumeration (comma-separated filenames)
#
# Test-only env vars:
#   AUDIT_FIXTURE_OVERRIDE     path to a single check-runs JSON; replaces gh api fetch
#   AUDIT_FIXED_WORKFLOWS      "workflow.yml:pr_number:head_sha[,..]" — bypass gh pr list
#   AUDIT_TELEMETRY_DIR        override ~/.local/state/soleur/
#   AUDIT_ENUMERATE_ONLY       print workflow inventory + exit (no fetch)
#
# Ref #3545, #3542, #2719.

set -uo pipefail

REPO="jikig-ai/soleur"
CODEQL_APP_ID=57789  # github-advanced-security
LIMIT=5
JSON_OUT=0
DRY_RUN=0
WORKFLOWS_OVERRIDE=""

while (( "$#" )); do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --workflows) WORKFLOWS_OVERRIDE="$2"; shift 2 ;;
    *) echo "::error::Unknown flag: $1" >&2; exit 1 ;;
  esac
done

say() {
  if (( JSON_OUT )); then
    printf '%s\n' "$*" >&2
  else
    printf '%s\n' "$*"
  fi
}

# Strip CR/LF/U+2028/U+2029 from operator-rendered strings before echoing
# to $GITHUB_OUTPUT / ::error:: annotations. Octal \177 per PR #3555 learning.
strip_log_injection() {
  tr -d '\r\n\f\v\177' | sed -e 's/\xc2\x85//g' -e 's/\xe2\x80\xa8//g' -e 's/\xe2\x80\xa9//g'
}

# Enumerate bot workflows via two-source union + runtime cross-check.
# Returns one filename per line (relative to repo root).
enumerate_workflows() {
  if [[ -n "$WORKFLOWS_OVERRIDE" ]]; then
    echo "$WORKFLOWS_OVERRIDE" | tr ',' '\n' | sed -E 's|^(.github/workflows/)?|.github/workflows/|'
    return
  fi
  # (a) composite-action consumers (anchored uses: line)
  local composite
  composite=$(grep -lE '^[[:space:]]*uses:[[:space:]]*\./\.github/actions/bot-pr-with-synthetic-checks' .github/workflows/*.yml 2>/dev/null || true)
  # (b) inline-pattern enumeration (scheduled-* with synthetic check-run posts).
  # Match files containing BOTH `gh api ... check-runs` AND `name=test` (possibly
  # on different lines — multi-line `gh api` continuations are the norm in
  # scheduled-content-publisher.yml). Skip files matching (a) to avoid double-counting.
  local inline=""
  for f in .github/workflows/scheduled-*.yml; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *"skill-security-scan-pr-trailer"* ]] && continue
    if printf '%s\n' "$composite" | grep -qFx "$f"; then continue; fi
    if grep -qE 'check-runs' "$f" && grep -qE '(name=test|"name":[[:space:]]*"test")' "$f"; then
      inline+="$f"$'\n'
    fi
  done
  # Union, dedupe, sort
  printf '%s\n%s\n' "$composite" "$inline" | grep -v '^$' | awk '!seen[$0]++' | sort
}

# Fetch check-runs JSON for a head SHA (or fixture override). Echoes JSON to stdout.
fetch_check_runs() {
  local sha="$1"
  if [[ -n "${AUDIT_FIXTURE_OVERRIDE:-}" ]]; then
    cat "$AUDIT_FIXTURE_OVERRIDE"
    return
  fi
  timeout 60 gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" 2>/dev/null || echo '{"check_runs":[]}'
}

# Classify a single check-runs payload.
# Outputs: codeql_state (passing|missing|failure|cancelled|timed_out|action_required|wrong_app|in_progress)
classify_codeql() {
  local json="$1"
  # Find CodeQL entry by name; prefer one with app.id == 57789.
  local row
  row=$(printf '%s' "$json" | jq -c --argjson aid "$CODEQL_APP_ID" \
    '[.check_runs[] | select(.name == "CodeQL")] as $rows
     | (($rows | map(select(.app.id == $aid)) | .[0])
        // ($rows | .[0])
        // null)')
  if [[ "$row" == "null" || -z "$row" ]]; then
    echo "missing"
    return
  fi
  local app_id status conclusion
  app_id=$(printf '%s' "$row" | jq -r '.app.id // empty')
  status=$(printf '%s' "$row" | jq -r '.status // empty')
  conclusion=$(printf '%s' "$row" | jq -r '.conclusion // empty')
  if [[ "$app_id" != "$CODEQL_APP_ID" ]]; then
    echo "wrong_app"
    return
  fi
  if [[ "$status" != "completed" ]]; then
    echo "in_progress"
    return
  fi
  case "$conclusion" in
    success|neutral|skipped) echo "passing" ;;
    failure|cancelled|timed_out|action_required) echo "$conclusion" ;;
    *) echo "missing" ;;  # null or unrecognized conclusion
  esac
}

# Enumerate-only mode (test hook + ad-hoc inventory inspection)
if [[ -n "${AUDIT_ENUMERATE_ONLY:-}" ]]; then
  enumerate_workflows
  exit 0
fi

# Sanity floor (deferred until after enumeration): require >= 8 workflows
WORKFLOWS=$(enumerate_workflows)
COUNT=$(printf '%s\n' "$WORKFLOWS" | grep -v '^$' | wc -l)
if [[ -z "$WORKFLOWS_OVERRIDE" && "$COUNT" -lt 8 ]]; then
  echo "::error::bot-workflow inventory shrank — verify before proceeding (got $COUNT, expect >=8)" >&2
  exit 1
fi
# When --workflows override is used, --workflows is allowed to specify <8 (testing path)
if [[ -n "$WORKFLOWS_OVERRIDE" && "$COUNT" -lt 1 ]]; then
  echo "::error::workflow override resolved to zero files" >&2
  exit 1
fi

say "Enumerated $COUNT bot workflows."

# Build PR head-SHA tuples per workflow.
# Format: "workflow.yml:pr_number:head_sha"
TUPLES=""
if [[ -n "${AUDIT_FIXED_WORKFLOWS:-}" ]]; then
  TUPLES=$(echo "$AUDIT_FIXED_WORKFLOWS" | tr ',' '\n')
else
  # Fetch a wide page of recent bot PRs once. Bot branches follow
  # `ci/<short-name>-<date>` convention but the short-name slug is NOT
  # the workflow filename stem (e.g., `rule-metrics-aggregate.yml`
  # creates `ci/rule-metrics-*` branches). Rather than encode the mapping
  # (which would drift), sample the most-recent LIMIT*N bot PRs flat and
  # attribute each by best-effort stem prefix match for reporting.
  # GitHub GraphQL cost: requesting `commits[]` for N PRs blows the
  # 500k-node cap. Fetch number+headRefName first (cheap), pick the sample,
  # then resolve head SHA per-PR via `gh pr view`.
  bot_prs=$(gh pr list --state all --limit 100 --author "app/github-actions" \
    --json number,headRefName 2>/dev/null || echo '[]')
  sample_size=$((LIMIT * COUNT))
  picked=$(printf '%s' "$bot_prs" | jq -r --argjson lim "$sample_size" \
    '.[:$lim] | .[] | "\(.headRefName):\(.number)"' 2>/dev/null || true)
  samples=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    branch="${line%%:*}"
    pr="${line#*:}"
    sha=$(gh pr view "$pr" --json commits --jq '.commits[-1].oid' 2>/dev/null || echo "")
    [[ -z "$sha" ]] && continue
    samples+="$branch:$pr:$sha"$'\n'
  done <<<"$picked"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    branch="${line%%:*}"
    rest="${line#*:}"
    # Best-effort workflow attribution by checking if any enumerated workflow's
    # stem (minus `scheduled-` prefix where applicable) appears in the branch.
    attributed=""
    for wf in $WORKFLOWS; do
      stem=$(basename "$wf" .yml)
      # Strip `scheduled-` prefix for matching since branches use short names
      short="${stem#scheduled-}"
      # Try short-form (e.g., "skill-freshness" matches "ci/skill-freshness-...")
      if [[ "$branch" == *"$short"* ]]; then
        attributed="$wf"
        break
      fi
    done
    [[ -z "$attributed" ]] && attributed="<unattributed-bot-pr>"
    TUPLES+="$attributed:$rest"$'\n'
  done <<<"$samples"
fi

# Classify each tuple
PASSING=0
DRIFT=0
IN_PROGRESS=0
DRIFT_ENTRIES="[]"
while IFS=: read -r wf pr sha; do
  [[ -z "$wf" ]] && continue
  json=$(fetch_check_runs "$sha")
  state=$(classify_codeql "$json")
  url="https://github.com/${REPO}/pull/${pr}"
  case "$state" in
    passing)
      PASSING=$((PASSING + 1))
      say "[ok] $wf #$pr ($sha) -> CodeQL passing"
      ;;
    in_progress)
      IN_PROGRESS=$((IN_PROGRESS + 1))
      say "[poll] $wf #$pr ($sha) -> CodeQL in_progress (re-poll recommended)"
      DRIFT_ENTRIES=$(printf '%s' "$DRIFT_ENTRIES" | jq --arg wf "$wf" --argjson pr "$pr" --arg sha "$sha" --arg state "$state" --arg url "$url" \
        '. + [{workflow: $wf, pr: $pr, head_sha: $sha, codeql_state: $state, url: $url}]')
      ;;
    *)
      DRIFT=$((DRIFT + 1))
      detail=$(printf '%s' "[drift] $wf #$pr ($sha) -> CodeQL $state" | strip_log_injection)
      say "$detail"
      DRIFT_ENTRIES=$(printf '%s' "$DRIFT_ENTRIES" | jq --arg wf "$wf" --argjson pr "$pr" --arg sha "$sha" --arg state "$state" --arg url "$url" \
        '. + [{workflow: $wf, pr: $pr, head_sha: $sha, codeql_state: $state, url: $url}]')
      ;;
  esac
done <<<"$TUPLES"

TOTAL=$((PASSING + DRIFT + IN_PROGRESS))
ENVELOPE=$(jq -n \
  --argjson total "$TOTAL" \
  --argjson passing "$PASSING" \
  --argjson drift "$DRIFT" \
  --argjson in_progress "$IN_PROGRESS" \
  --argjson drift_entries "$DRIFT_ENTRIES" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{summary: {total: $total, passing: $passing, drift: $drift, in_progress: $in_progress}, drift: $drift_entries, generated_at: $generated_at}')

# Telemetry write (skip on --dry-run)
if (( ! DRY_RUN )); then
  state_dir="${AUDIT_TELEMETRY_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/soleur}"
  mkdir -p "$state_dir"
  ts=$(date -u +%Y%m%d-%H%M%S)
  tmpf=$(mktemp)
  printf '%s' "$ENVELOPE" > "$tmpf"
  mv "$tmpf" "$state_dir/codeql-bot-coverage-${ts}.json"
fi

if (( JSON_OUT )); then
  printf '%s\n' "$ENVELOPE"
fi

say "Summary: total=$TOTAL passing=$PASSING drift=$DRIFT in_progress=$IN_PROGRESS"

# Exit code: 0 on green, 1 on drift, 2 on in_progress-only (no drift).
if (( DRIFT > 0 )); then
  exit 1
elif (( IN_PROGRESS > 0 )); then
  exit 2
else
  exit 0
fi
