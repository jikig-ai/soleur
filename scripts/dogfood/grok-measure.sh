#!/usr/bin/env bash
# #6545 — Measure headless Grok Build run: TTFT, approx tok/s, cost fields.
# Substrate: model comes from grok config / -m flag; not hard-coded to xAI.
#
# Usage:
#   grok-measure.sh --prompt "..." [--model ID] [--max-turns N] [--cwd PATH] [--log FILE]
#   grok-measure.sh --parse-only < streaming-json.ndjson
#
# Requires: grok (unless --parse-only), jq, bash 4+
set -euo pipefail

PROMPT=""
MODEL=""
MAX_TURNS=30
CWD="."
LOG_FILE=""
PARSE_ONLY=0
# Default OFF — opt in with --yolo; pair with --deny rules for unattended runs (FR4).
YOLO=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# //'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --max-turns) MAX_TURNS="${2:-30}"; shift 2 ;;
    --cwd) CWD="${2:-.}"; shift 2 ;;
    --log) LOG_FILE="${2:-}"; shift 2 ;;
    --parse-only) PARSE_ONLY=1; shift ;;
    --yolo) YOLO=1; shift ;;
    --no-yolo) YOLO=0; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

# Normalize NDJSON: ensure each event has ts_ms (inject 50ms steps if missing).
normalize_stream() {
  # jq -s slurps one object per line into an array
  jq -s -c '
    to_entries | map(
      .value as $v
      | if ($v | has("ts_ms")) then $v
        else $v + {ts_ms: (.key * 50)}
        end
    )
  '
}

# Parse normalized event array → summary object.
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

if [[ "$PARSE_ONLY" -eq 1 ]]; then
  normalize_stream | parse_events
  exit 0
fi

if [[ -z "$PROMPT" ]]; then
  echo "error: --prompt required (or --parse-only)" >&2
  exit 1
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "error: grok CLI not found on PATH" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required" >&2
  exit 1
fi

# Approach A (#6546 / ADR-119): when measuring local-open, re-assert loopback every run.
# Bootstrap-once is insufficient — config drift or public rebind must refuse the campaign.
_MEASURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${MODEL:-}" == "local-open" || "${MODEL:-}" == local-open/* ]]; then
  # shellcheck source=scripts/dogfood/assert-ollama-loopback.sh
  if [[ -f "${_MEASURE_DIR}/assert-ollama-loopback.sh" ]]; then
    # shellcheck disable=SC1091
    source "${_MEASURE_DIR}/assert-ollama-loopback.sh"
    assert_ollama_loopback_listen || {
      echo "error: Ollama not loopback-only — refuse local-open measure (Approach A)" >&2
      exit 1
    }
    _cfg="${HOME}/.grok/config.toml"
    assert_config_base_url_loopback "$_cfg" || {
      echo "error: non-loopback base_url in ${_cfg} — refuse local-open measure" >&2
      exit 1
    }
    if ! curl -fsS --max-time 5 "http://127.0.0.1:11434/api/tags" >/dev/null; then
      echo "error: Ollama not healthy on 127.0.0.1:11434 — refuse local-open measure" >&2
      exit 1
    fi
  else
    echo "error: missing assert-ollama-loopback.sh — refuse local-open measure" >&2
    exit 1
  fi
fi

cmd=(grok -p "$PROMPT" --cwd "$CWD" --output-format streaming-json --max-turns "$MAX_TURNS" --no-auto-update)
if [[ -n "$MODEL" ]]; then
  cmd+=(-m "$MODEL")
fi
if [[ "$YOLO" -eq 1 ]]; then
  cmd+=(--yolo)
fi

raw="$(mktemp)"
stamp_start_ms=$(($(date +%s%N) / 1000000))

set +e
"${cmd[@]}" 2>/tmp/grok-measure.err | while IFS= read -r line; do
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

summary="$(normalize_stream <"$raw" | parse_events)"
prompt_chars=$(printf '%s' "$PROMPT" | wc -c | tr -d ' ')
summary="$(echo "$summary" | jq -c \
  --argjson rc "$rc" \
  --argjson start "$stamp_start_ms" \
  --arg model "${MODEL:-default}" \
  --argjson prompt_chars "$prompt_chars" \
  '. + {exit_code: $rc, started_ms: $start, model: $model, prompt_chars: $prompt_chars}')"

echo "$summary"

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$summary" >>"$LOG_FILE"
  cat "$raw" >>"${LOG_FILE}.ndjson"
fi

rm -f "$raw"
exit "$rc"
