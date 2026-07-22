#!/usr/bin/env bash
# Runtime contract has moved to apps/web-platform/server/inngest/functions/cron-compound-promote.ts
# (TR9 PR-11). This script remains on disk for operator-local hand-testing only.
#
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
# awk extraction tolerates trailing inline comments and surrounding whitespace.
# `^enabled[ \t]*:` matches both `enabled: x` and `enabled : x` (space before
# colon is legal YAML and the previous regex missed it). Avoids the yq dep.
ENABLED=$(awk '/^[ \t]*enabled[ \t]*:/ { sub(/^[^:]*:[ \t]*/, "", $0); sub(/[ \t]*#.*/, "", $0); gsub(/[ "'\''\t]/, "", $0); print $0; exit }' "$CONFIG")
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
# Heuristic PII / credential regex (fails OPEN — any match excludes the file):
#   - email | IPv4 | IBAN (canonical PII shapes)
#   - JWT / Anthropic / GitHub / AWS / Stripe / Slack token shapes
# Cheap, deterministic. Human reviewer at PR time + Anthropic processor DPA
# are the second and third lines of defense. The runbook acknowledges that
# novel shapes (phone numbers, customer slugs, prod IDs without prefix) still
# slip through.
PII_REGEX='([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|([0-9]{1,3}(\.[0-9]{1,3}){3})|([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})|(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)|(sk-ant-[A-Za-z0-9_-]{20,})|(gh[psr]_[A-Za-z0-9]{20,})|(AKIA[0-9A-Z]{16})|((sk|pk)_(live|test)_[A-Za-z0-9]{20,})|(xox[baprs]-[A-Za-z0-9-]{10,})'
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
    # Broadened from `knowledge-base/project/learnings/...` to any kb path so
    # the extractor matches both manual retirements (constitution, skills) and
    # rule-prune-generated rows. Strips trailing `|` so the regex doesn't eat
    # the column separator. Path tokens with spaces are not supported (the
    # repo's convention is kebab-case).
    done < <(printf '%s\n' "$breadcrumb" | grep -oE 'knowledge-base/[^ |]+\.md' || true)
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
#
# Pattern: emit one NDJSON line per file into a tempfile, then `jq -s` slurps
# the whole tempfile in a single pass. Avoids the O(n²) "re-parse the whole
# array on every iteration" pattern from the first draft (measured 22s on
# 953 files; the slurp variant is ~1.3s — 15x faster and degrades linearly).
CORPUS_NDJSON=$(mktemp)
trap 'rm -f "$CORPUS_NDJSON"' EXIT
for file in "${SAFE_FILES[@]}"; do
  rel="${file#"$REPO_ROOT/"}"
  summary=$(head -n 10 "$file" | jq -Rs .)
  jq -nc --arg path "$rel" --argjson summary "$summary" '{path: $path, summary: $summary}' >> "$CORPUS_NDJSON"
done

# Compute live always-loaded byte size of the AGENTS payload. The LLM cannot
# inspect the repo filesystem, so the driver injects the current size into the
# prompt. The post-apply byte cap is also enforced in the workflow after
# `git apply` lands (defense-in-depth — prompt compliance is best-effort).
AGENTS_INDEX="$REPO_ROOT/AGENTS.md"
AGENTS_CORE="$REPO_ROOT/AGENTS.core.md"
ALWAYS_LOADED_NOW=0
[[ -f "$AGENTS_INDEX" ]] && ALWAYS_LOADED_NOW=$(( ALWAYS_LOADED_NOW + $(wc -c < "$AGENTS_INDEX") ))
[[ -f "$AGENTS_CORE"  ]] && ALWAYS_LOADED_NOW=$(( ALWAYS_LOADED_NOW + $(wc -c < "$AGENTS_CORE")  ))
# Always-loaded byte budgets. Source of truth: scripts/lint-agents-rule-budget.py
# (B_ALWAYS_REJECT / B_ALWAYS_WARN); agreement is enforced by
# scripts/lint-agents-compound-sync.sh. Do not edit one side alone — that de-sync
# is what issue #6461 was filed for.
#
# UNIT SKEW (deliberate, fail-safe): the linter's thresholds are defined over
# FRONTMATTER-STRIPPED bytes; the `wc -c` measurements above are RAW. Raw is
# structurally >= stripped, so this comparison refuses no later than the commit
# gate would — the safe direction, accepted knowingly. (The exact gap drifts with
# frontmatter size; the direction is the invariant.)
#
# Hard ceiling, mirroring the commit gate (post-apply enforcement).
ALWAYS_LOADED_CAP=23000
# Budget the LLM proposes against: the WARN floor, deliberately below the hard
# ceiling so a cluster cannot pin the registry at the cap with zero headroom.
PROPOSE_ALWAYS_LOADED_BUDGET=20000

# Clustering prompt: tier='skill'|'agents-core' (post AGENTS.md split per PR #3496).
# - agents-core targets AGENTS.core.md and is gated on the live always-loaded
#   payload size injected below. The workflow enforces target_path allowlist
#   AND a post-apply byte cap — the LLM is told the numbers but not trusted.
# - cluster_hash is now computed in the workflow from source_learnings, so the
#   LLM no longer needs to compute it (the field is ignored if supplied; the
#   prompt asks for it only as a structural placeholder so older clients keep
#   parsing the schema). Removed the "compute sha256" instruction so the LLM
#   stops generating speculative hex.
PROMPT=$(cat <<EOF
You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${REMAINING} qualifying clusters (each with >=5 source learnings) as a JSON array.
Schema: [{cluster_hash:'', tier:'skill'|'agents-core', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}].
Apply AGENTS.md cq-agents-md-tier-gate: already-enforced -> skip; domain-scoped -> skill; cross-cutting -> agents-core targeting AGENTS.core.md. Per PR #3496 sidecar split, AGENTS.md (index) + AGENTS.core.md are always-loaded; conditional sidecars (AGENTS.docs.md, AGENTS.rest.md) are deferred to v2.
Current always-loaded payload (AGENTS.md + AGENTS.core.md) is ${ALWAYS_LOADED_NOW} bytes; propose against a budget of ${PROPOSE_ALWAYS_LOADED_BUDGET} bytes (the warn floor — leave headroom, do not aim for the hard ceiling). For agents-core targets, REFUSE the cluster if ${ALWAYS_LOADED_NOW} + your byte_impact.delta exceeds ${PROPOSE_ALWAYS_LOADED_BUDGET} — emit fewer/smaller clusters instead.
target_path MUST be one of: AGENTS.core.md, plugins/soleur/skills/<skill-name>/SKILL.md. The workflow refuses any other path. cluster_hash is ignored (the workflow computes it).
Output ONLY the JSON array, nothing else.
EOF
)
printf '::compound-promote-byte-budget::%d:%d\n' "$ALWAYS_LOADED_NOW" "$ALWAYS_LOADED_CAP"

REQUEST=$(jq -n \
  --arg model "claude-sonnet-5" \
  --argjson max_tokens 16384 \
  --arg prompt "$PROMPT" \
  --slurpfile corpus "$CORPUS_NDJSON" \
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

# Defense against truncation: a `stop_reason: "max_tokens"` response means the
# JSON array is almost certainly malformed (cut mid-cluster). Fail soft on
# this — emit empty clusters rather than letting downstream jq fail loud.
STOP_REASON=$(echo "$RESPONSE" | jq -r '.stop_reason // empty' 2>/dev/null || echo "")
if [[ "$STOP_REASON" == "max_tokens" ]]; then
  echo "::warning::Anthropic response truncated at max_tokens — emitting empty clusters" >&2
  printf '::compound-promote-clusters-json::%s\n' "$(printf '%s' '[]' | base64 | tr -d '\n')"
  exit 0
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
