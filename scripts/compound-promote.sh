#!/usr/bin/env bash
# Driver for the compound-promotion-loop weekly cron (Issue: #2720).
#
# Pipeline (5 stages, fail-soft):
#   1. Opt-in gate — exit no-op unless promotion-config.yml has enabled:true.
#   2. Per-week cap — derived from open `self-healing/auto` PRs (no state file).
#   3. GDPR shell pre-pass — drop any learning whose body matches the canonical
#      PII regex BEFORE the Anthropic call. Load-bearing safety: a leaked PII
#      learning becomes a public PR body.
#   4. Retired-rule pre-pass — drop any learning whose path appears in a
#      breadcrumb in scripts/retired-rule-ids.txt (no re-promotion of demoted
#      rules).
#   5. Anthropic API call — cluster the surviving corpus via plain `curl`.
#      No claude-code-action wrapper (token-revocation post-step would break
#      subsequent gh calls in the same job — see ADR-021).
#
# Output sentinels (stdout, one per line):
#   ::compound-promote-status::<no-config|disabled|enabled|week-cap-reached|empty-corpus>
#   ::compound-promote-week-cap::<remaining-int>
#   ::compound-promote-pii-excluded::<path>
#   ::compound-promote-retired-excluded::<path>
#   ::compound-promote-clusters-json::<base64-no-newline>
#
# Test toggles:
#   COMPOUND_PROMOTE_FIXTURE_ROOT — override repo root (default: git toplevel).
#   GH_BIN  — mock `gh`  binary path.
#   CURL_BIN — mock `curl` binary path.
#
# Sister scripts: scripts/rule-prune.sh (demotion); scripts/rule-metrics-aggregate.sh.
# Plan: knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md.
set -euo pipefail

REPO_ROOT="${COMPOUND_PROMOTE_FIXTURE_ROOT:-$(git rev-parse --show-toplevel)}"
CONFIG="$REPO_ROOT/knowledge-base/project/promotion-config.yml"
LEARNINGS_DIR="$REPO_ROOT/knowledge-base/project/learnings"
RETIRED_FILE="$REPO_ROOT/scripts/retired-rule-ids.txt"
WEEK_CAP_DEFAULT=2
GH_BIN="${GH_BIN:-gh}"
CURL_BIN="${CURL_BIN:-curl}"

# 1. Opt-in gate ---------------------------------------------------------------
if [[ ! -f "$CONFIG" ]]; then
  printf '::compound-promote-status::no-config\n'
  exit 0
fi
# awk extraction tolerates trailing inline comments and surrounding whitespace
# so we can avoid the yq dependency.
ENABLED=$(awk -F': *' '/^enabled:/ { sub(/[ \t]*#.*/, "", $2); gsub(/[ "'\''\t]/, "", $2); print $2; exit }' "$CONFIG")
if [[ "$ENABLED" != "true" ]]; then
  printf '::compound-promote-status::disabled\n'
  exit 0
fi
printf '::compound-promote-status::enabled\n'

# 2. Per-week cap (derived from open self-healing/auto PRs) --------------------
OPEN_COUNT=$("$GH_BIN" pr list --label self-healing/auto --state open --json number --jq length 2>/dev/null || echo 0)
[[ -z "$OPEN_COUNT" ]] && OPEN_COUNT=0
REMAINING=$(( WEEK_CAP_DEFAULT - OPEN_COUNT ))
if (( REMAINING <= 0 )); then
  printf '::compound-promote-week-cap::0\n'
  printf '::compound-promote-status::week-cap-reached\n'
  exit 0
fi
printf '::compound-promote-week-cap::%d\n' "$REMAINING"

# 3. GDPR shell pre-pass -------------------------------------------------------
# Canonical PII regex: email | IPv4 | IBAN. Heuristic — matches the lefthook
# advisory layer. Cheap, deterministic, fails OPEN (excludes the file) on any
# match. The human reviewer at PR time is the second line of defense.
PII_REGEX='([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|([0-9]{1,3}(\.[0-9]{1,3}){3})|([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})'
SAFE_FILES=()
if [[ -d "$LEARNINGS_DIR" ]]; then
  while IFS= read -r -d '' file; do
    rel="${file#"$REPO_ROOT/"}"
    if grep -qE "$PII_REGEX" "$file" 2>/dev/null; then
      printf '::compound-promote-pii-excluded::%s\n' "$rel"
      continue
    fi
    SAFE_FILES+=("$file")
  done < <(find "$LEARNINGS_DIR" -type f -name '*.md' ! -path '*/archive/*' -print0 2>/dev/null || true)
fi

# 4. Retired-rule pre-pass ------------------------------------------------------
# Read scripts/retired-rule-ids.txt; for any path-like token in the breadcrumb
# column (col 4, `|`-separated), drop matching learnings from the corpus.
if [[ -f "$RETIRED_FILE" && ${#SAFE_FILES[@]} -gt 0 ]]; then
  declare -A RETIRED_PATHS=()
  while IFS='|' read -r _id _date _pr breadcrumb; do
    [[ -z "${breadcrumb:-}" ]] && continue
    while IFS= read -r token; do
      [[ -z "$token" ]] && continue
      RETIRED_PATHS["$token"]=1
    done < <(printf '%s\n' "$breadcrumb" | grep -oE 'knowledge-base/project/learnings/[^ ]+\.md' || true)
  done < "$RETIRED_FILE"

  FILTERED_FILES=()
  for file in "${SAFE_FILES[@]}"; do
    rel="${file#"$REPO_ROOT/"}"
    if [[ -n "${RETIRED_PATHS[$rel]:-}" ]]; then
      printf '::compound-promote-retired-excluded::%s\n' "$rel"
      continue
    fi
    FILTERED_FILES+=("$file")
  done
  SAFE_FILES=("${FILTERED_FILES[@]+"${FILTERED_FILES[@]}"}")
fi

if (( ${#SAFE_FILES[@]} == 0 )); then
  printf '::compound-promote-status::empty-corpus\n'
  exit 0
fi

# 5. Anthropic API call --------------------------------------------------------
# Plain curl — no claude-code-action wrapper (see ADR-021). The API key only
# enters the env block of the workflow's promote step; never logged.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "::error::ANTHROPIC_API_KEY not set" >&2
  exit 1
fi

# Build corpus JSON: { path, summary } per file. Summary is head -n 10 of the
# file body — bounds prompt size on the ~947-file corpus and avoids piping
# full file contents to Anthropic.
CORPUS_JSON=$(jq -n '[]')
for file in "${SAFE_FILES[@]}"; do
  rel="${file#"$REPO_ROOT/"}"
  summary=$(head -n 10 "$file" | jq -Rs .)
  CORPUS_JSON=$(echo "$CORPUS_JSON" | jq --arg path "$rel" --argjson summary "$summary" '. + [{path: $path, summary: $summary}]')
done

# Clustering prompt: tier='skill'|'agents-core' (post AGENTS.md split per PR #3496).
# agents-core targets AGENTS.core.md and is gated on always-loaded payload size.
PROMPT=$(cat <<EOF
You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${REMAINING} qualifying clusters (each with >=5 source learnings) as a JSON array.
Schema: [{cluster_hash:'<sha256>', tier:'skill'|'agents-core', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}].
Apply AGENTS.md cq-agents-md-tier-gate: already-enforced -> skip; domain-scoped -> skill; cross-cutting -> agents-core targeting AGENTS.core.md. Per PR #3496 sidecar split, AGENTS.md (index) + AGENTS.core.md are always-loaded; conditional sidecars (AGENTS.docs.md, AGENTS.rest.md) are deferred to v2.
For agents-core targets, refuse if (current AGENTS.md size + AGENTS.core.md size + delta) > 18000 bytes.
Compute cluster_hash = sha256(sorted(source_learnings)).
Output ONLY the JSON array, nothing else.
EOF
)

REQUEST=$(jq -n \
  --arg model "claude-sonnet-4-6" \
  --argjson max_tokens 8192 \
  --arg prompt "$PROMPT" \
  --argjson corpus "$CORPUS_JSON" \
  '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: ($prompt + "\n\nCorpus:\n" + ($corpus | tostring))}]}')

RESPONSE=$("$CURL_BIN" -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$REQUEST")

# Extract the assistant's text reply.
CLUSTERS_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // empty' 2>/dev/null || echo "")
if [[ -z "$CLUSTERS_TEXT" ]]; then
  echo "::error::Anthropic API returned empty content" >&2
  echo "$RESPONSE" | head -c 500 >&2
  exit 1
fi

# Defensive JSON-shape validation. Fail soft (emit empty array) so the caller
# workflow does not crash on a malformed response.
if ! CLUSTERS_JSON=$(echo "$CLUSTERS_TEXT" | jq -e 'if type == "array" then . else error("not an array") end' 2>/dev/null); then
  echo "::error::Anthropic response is not a valid JSON array" >&2
  echo "$CLUSTERS_TEXT" | head -c 500 >&2
  printf '::compound-promote-clusters-json::%s\n' "$(printf '%s' '[]' | base64 | tr -d '\n')"
  exit 0
fi

# Hard slice at REMAINING — load-bearing defense against the LLM emitting more
# clusters than the per-week cap allows.
CLUSTERS_JSON=$(echo "$CLUSTERS_JSON" | jq --argjson cap "$REMAINING" '.[0:$cap]')

CLUSTERS_B64=$(printf '%s' "$CLUSTERS_JSON" | base64 | tr -d '\n')
printf '::compound-promote-clusters-json::%s\n' "$CLUSTERS_B64"
