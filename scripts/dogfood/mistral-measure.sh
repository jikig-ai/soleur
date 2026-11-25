#!/usr/bin/env bash
# #9648 Phase A0 — measure a Mistral model through an existing vehicle:
# `codex exec --json` against api.mistral.ai's /v1/responses surface. The codex
# event stream is adapted to the grok-measure.sh canonical shape and summarized
# by the same jq pipeline, so eval-table columns are identical across vehicles.
#
# Usage:
#   mistral-measure.sh --prompt "..." [--model ID] [--cwd PATH] [--log FILE]
#     [--provider NAME] [--base-url URL] [--env-key VAR] [--wire-api API]
#     [--profile NAME] [--sandbox MODE] [--add-dir DIR]
#     [--in-usd-per-mtok X] [--out-usd-per-mtok Y]
#   mistral-measure.sh --parse-only [--in-usd-per-mtok X --out-usd-per-mtok Y]
#
# Requires: codex (unless --parse-only), jq, bash 4+. The provider key is read
# by codex from the env var named by --env-key (default MISTRAL_API_KEY) —
# export it before running; the script never touches the value.
# --profile <name> selects a codex config profile instead of the inline
# -c model_providers.<provider> override (profile defines its own env_key).
# --sandbox defaults to read-only — the YOLO-off analogue; workspace-write or
# danger-full-access are deliberate per-class choices (see the runbook).
set -euo pipefail

# Credential-binding script (#7797): refuse to run under xtrace while the key
# is live in the environment — a traced expansion would print it.
case "$-" in
  *x*)
    if [ -n "${ENV_KEY:+x}${MISTRAL_API_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

PROMPT=""
MODEL="mistral-large-latest"
CWD="."
LOG_FILE=""
PARSE_ONLY=0
PROVIDER="mistral"
BASE_URL="https://api.mistral.ai/v1"
ENV_KEY="MISTRAL_API_KEY"
WIRE_API="responses"
PROFILE=""
SANDBOX="read-only"
ADD_DIRS=()
IN_USD=""
OUT_USD=""

usage() {
  sed -n '2,17p' "$0" | sed 's/^# //'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-.}"; shift 2 ;;
    --log) LOG_FILE="${2:-}"; shift 2 ;;
    --parse-only) PARSE_ONLY=1; shift ;;
    --provider) PROVIDER="${2:-mistral}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --env-key) ENV_KEY="${2:-MISTRAL_API_KEY}"; shift 2 ;;
    --wire-api) WIRE_API="${2:-responses}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --sandbox) SANDBOX="${2:-read-only}"; shift 2 ;;
    --add-dir) ADD_DIRS+=("${2:-}"); shift 2 ;;
    --in-usd-per-mtok) IN_USD="${2:-}"; shift 2 ;;
    --out-usd-per-mtok) OUT_USD="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

# Re-check after arg-parse so a --env-key override is refused under xtrace too.
case "$-" in
  *x*)
    if [ -n "${!ENV_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# Normalize NDJSON: ensure each event has ts_ms (inject 50ms steps if missing).
# Same shape as grok-measure.sh.
normalize_stream() {
  jq -s -c '
    to_entries | map(
      .value as $v
      | if ($v | has("ts_ms")) then $v
        else $v + {ts_ms: (.key * 50)}
        end
    )
  '
}

# Adapt `codex exec --json` events to the canonical event shape. Events that are
# already canonical (text/end/raw) pass through untouched — a pre-canonical
# stream is not double-adapted. Non-terminal `error` events (reconnect notices)
# also pass through: `turn.failed` is the terminal marker (measured 2026-10-07,
# codex 0.160.1 — a fatal rejection emits the reconnect notices then a final
# turn.failed), and the summary's exit_code records a bare-error abort anyway.
# Item kind is read from item_type OR type — codex emits `type` on error-class
# items (measured: the model-metadata warning arrives as item.type=="error").
adapt_codex() {
  jq -c '
    . as $evs
    | ([$evs[] | select(.type == "thread.started") | .thread_id] | first // null) as $tid
    | ([$evs[] | select(.type == "turn.completed")] | length) as $nturns
    | [
        $evs[]
        | . as $e
        | ($e.item.item_type // $e.item.type // "") as $kind
        | if $e.type == "item.completed" and $kind == "agent_message"
            then {type: "text", data: ($e.item.text // ""), ts_ms: $e.ts_ms}
          elif $e.type == "item.completed" and $kind == "reasoning"
            then {type: "reasoning", data: ($e.item.text // ""), ts_ms: $e.ts_ms}
          elif $e.type == "turn.completed"
            then {
              type: "end", ts_ms: $e.ts_ms, session_id: $tid,
              num_turns: $nturns, stop_reason: "end_turn",
              usage: (($e.usage // {})
                + (if ($e.usage.cached_input_tokens? != null)
                   then {cache_read_input_tokens: $e.usage.cached_input_tokens}
                   else {} end))
            }
          elif $e.type == "turn.failed"
            then {type: "end", ts_ms: $e.ts_ms, session_id: $tid,
                  num_turns: $nturns, stop_reason: "turn.failed",
                  error: ($e.error.message // "unknown")}
          else $e
          end
      ]
  '
}

# Parse normalized event array → summary object. Verbatim from grok-measure.sh.
parse_events() {
  jq -c '
    def first_text_ms:
      ([.[] | select(.type == "text") | .ts_ms // empty] | min) // null;
    def end_obj:
      ([.[] | select(.type == "end")] | last) // {};
    def text_chunks:
      [.[] | select(.type == "text") | .data // ""] | join("");
    (end_obj) as $end
    | (first_text_ms) as $ttft
    | ([.[] | select(.type == "text") | .ts_ms // empty] | max) as $last_text
    | ($end.usage // {}) as $u
    | ($u.output_tokens // $u.outputTokens // null) as $out_tok
    | (if $ttft != null and $last_text != null and $last_text > $ttft and $out_tok != null and $out_tok > 0
       then ($out_tok / (($last_text - $ttft) / 1000.0))
       else null end) as $tps
    | {
        ttft_ms: $ttft,
        tok_per_sec: $tps,
        output_tokens: $out_tok,
        input_tokens: ($u.input_tokens // $u.inputTokens // null),
        cache_read_input_tokens: ($u.cache_read_input_tokens // $u.cacheReadInputTokens // null),
        total_cost_usd: ($end.total_cost_usd // null),
        num_turns: ($end.num_turns // null),
        session_id: ($end.sessionId // $end.session_id // null),
        stop_reason: ($end.stopReason // $end.stop_reason // null),
        text_chars: (text_chunks | length),
        event_count: length
      }
  '
}

# Codex emits no cost field. When a rate card is supplied, fill total_cost_usd
# from measured tokens — but never overwrite a vendor-reported cost.
price_from_tokens() {
  if [[ -n "$IN_USD" && -n "$OUT_USD" ]]; then
    jq -c --argjson pin "$IN_USD" --argjson pout "$OUT_USD" '
      if .total_cost_usd == null and .input_tokens != null and .output_tokens != null
      then . + {total_cost_usd: ((.input_tokens * $pin + .output_tokens * $pout) / 1000000), cost_basis: "rate-card"}
      else . end'
  else
    cat
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required" >&2
  exit 1
fi

if [[ "$PARSE_ONLY" -eq 1 ]]; then
  normalize_stream | adapt_codex | parse_events | price_from_tokens
  exit 0
fi

if [[ -z "$PROMPT" ]]; then
  echo "error: --prompt required (or --parse-only)" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "error: codex CLI not found on PATH" >&2
  exit 1
fi

cmd=(codex exec --json --color never --skip-git-repo-check -C "$CWD" -s "$SANDBOX")
if [[ -n "$PROFILE" ]]; then
  cmd+=(-p "$PROFILE")
else
  if [[ -z "${!ENV_KEY:-}" ]]; then
    echo "error: \$${ENV_KEY} is not set — the provider env_key must be exported" >&2
    exit 1
  fi
  # --ignore-user-config keeps ambient ~/.codex/config.toml out: no MCP workers
  # racing the turn (measured 2026-10-07: 27 rmcp stderr lines -> 0) and no
  # inherited model_provider fighting the inline override. The provider table
  # is self-supplied via -c.
  cmd+=(--ignore-user-config)
  cmd+=(-c "model_providers.${PROVIDER}={name=\"${PROVIDER}\",base_url=\"${BASE_URL}\",env_key=\"${ENV_KEY}\",wire_api=\"${WIRE_API}\"}")
  cmd+=(-c "model_provider=\"${PROVIDER}\"")
fi
for d in "${ADD_DIRS[@]:-}"; do
  [[ -n "$d" ]] && cmd+=(--add-dir "$d")
done
if [[ -n "$MODEL" ]]; then
  cmd+=(-m "$MODEL")
fi
cmd+=("$PROMPT")

raw="$(mktemp)"
err_file="$(mktemp)"
stamp_start_ms=$(($(date +%s%N) / 1000000))

set +e
# </dev/null: codex appends piped stdin to the prompt otherwise.
"${cmd[@]}" </dev/null 2>"$err_file" | while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  now_ms=$(($(date +%s%N) / 1000000))
  rel=$((now_ms - stamp_start_ms))
  if echo "$line" | jq -e . >/dev/null 2>&1; then
    echo "$line" | jq -c --argjson ts "$rel" '. + {ts_ms: $ts}'
  else
    jq -nc --arg d "$line" --argjson ts "$rel" '{type:"raw",data:$d,ts_ms:$ts}'
  fi
done >"$raw"
rc=${PIPESTATUS[0]}
set -e

summary="$(normalize_stream <"$raw" | adapt_codex | parse_events | price_from_tokens)"
prompt_chars=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')
summary="$(echo "$summary" | jq -c \
  --argjson rc "$rc" \
  --argjson start "$stamp_start_ms" \
  --arg model "${MODEL:-default}" \
  --arg vehicle "codex" \
  --argjson prompt_chars "$prompt_chars" \
  '. + {exit_code: $rc, started_ms: $start, model: $model, vehicle: $vehicle, prompt_chars: $prompt_chars}')"

echo "$summary"

if [[ "$rc" -ne 0 && -s "$err_file" ]]; then
  echo "codex stderr (tail):" >&2
  tail -5 "$err_file" >&2
fi

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$summary" >>"$LOG_FILE"
  cat "$raw" >>"${LOG_FILE}.ndjson"
fi

rm -f "$raw" "$err_file"
exit "$rc"
