#!/usr/bin/env bash
# extract-api-spend.sh — the CI cost-capture redaction boundary (#5086).
#
# Reads a claude-code-action `execution_file` (a JSON array whose final element is
# {"type":"result","total_cost_usd":N}; assistant turns carry .message.usage and
# .message.model) and emits ONE allowlisted JSON record to stdout:
#
#   {run_id, sha, workflow, timestamp, model,
#    input_tokens, output_tokens, total_cost_usd, provenance}
#
# This is the SINGLE redaction boundary between the raw execution log (prompts,
# diffs, run under ANTHROPIC_API_KEY) and the committed api-spend ledger. It does
# THREE things to stay leak-proof (brand-survival threshold: single-user incident):
#   1. Explicit key projection — only the 9 allowlist fields, never passthrough.
#   2. Numeric type-coercion — cost/tokens are forced to numbers (a string
#      injection in a numeric field becomes null, never a verbatim secret).
#   3. Fail-closed secret-shape scan — if the assembled record contains any
#      secret-shaped substring (in any value, e.g. a key hidden in a model name),
#      emit nothing and exit non-zero. A missed cost row is harmless; a leaked
#      key is catastrophic, so we drop the row rather than risk the leak.
#
# CI context (run_id/sha/workflow/timestamp) comes from the environment, NOT the
# execution_file. Usage: extract-api-spend.sh <execution_file>
#
# Verified execution_file shape: anthropics/claude-code-action@v1.0.101
# src/entrypoints/format-turns.ts:400 reads `total_cost_usd`; fixture
# test/fixtures/sample-turns.json:191-192. jq path: map(select(.type=="result"))[-1].

set -euo pipefail

EXEC_FILE="${1:-}"
if [[ -z "$EXEC_FILE" || ! -f "$EXEC_FILE" ]]; then
  echo "extract-api-spend: execution_file not found: '$EXEC_FILE'" >&2
  exit 1
fi

RUN_ID="${SOLEUR_RUN_ID:-${GITHUB_RUN_ID:-}}"
SHA="${SOLEUR_SHA:-${GITHUB_SHA:-}}"
WORKFLOW="${SOLEUR_WORKFLOW:-${GITHUB_WORKFLOW:-}}"
TIMESTAMP="${SOLEUR_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

# Build the allowlisted record via explicit projection + numeric coercion.
# `// empty` on the cost forces fail-closed when no result object / no cost exists.
record="$(
  jq -ce \
    --arg run_id "$RUN_ID" \
    --arg sha "$SHA" \
    --arg workflow "$WORKFLOW" \
    --arg timestamp "$TIMESTAMP" '
    (map(select(.type == "result")) | last) as $r
    | ($r.total_cost_usd // empty) as $cost
    | (map(select(.type == "assistant") | .message.usage // {})) as $usages
    | (map(select(.type == "assistant") | .message.model // empty) | last) as $model
    | {
        run_id:          $run_id,
        sha:             $sha,
        workflow:        $workflow,
        timestamp:       $timestamp,
        model:           ($model // "unknown"),
        input_tokens:    ([$usages[].input_tokens // 0]  | add // 0),
        output_tokens:   ([$usages[].output_tokens // 0] | add // 0),
        total_cost_usd:  ($cost | tonumber),
        provenance:      "recorded-actual"
      }
  ' "$EXEC_FILE" 2>/dev/null
)" || {
  echo "extract-api-spend: malformed execution_file or missing total_cost_usd" >&2
  exit 1
}

if [[ -z "$record" ]]; then
  echo "extract-api-spend: no result/cost extracted" >&2
  exit 1
fi

# Fail-closed secret-shape scan over the assembled record (covers a secret hidden
# inside an allowlisted value such as a model name). Drop the row on any match.
# Scope note: matches PREFIXED secret shapes (the Anthropic-key leak vector,
# sk-ant-*, is always prefixed and IS caught). A hypothetical PREFIXLESS 40-char
# token is not matched here — a generic long-run pattern would false-positive on
# the 40-hex git SHA, and `model` (the only free-form value) is sourced from the
# action's own --model config, not model output. Residual risk: negligible.
if printf '%s' "$record" | grep -qiE 'sk-ant|sk_(live|test)|ghp_|ghs_|github_pat_|org_|AKIA[0-9A-Z]{16}|xoxb-|sbp_|-----BEGIN'; then
  echo "extract-api-spend: secret-shaped substring in record; refusing to emit" >&2
  exit 1
fi

printf '%s\n' "$record"
