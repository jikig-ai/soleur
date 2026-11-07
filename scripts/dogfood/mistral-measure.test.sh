#!/usr/bin/env bash
# Unit test for scripts/dogfood/mistral-measure.sh --parse-only (#9648 Phase A0)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/dogfood/mistral-measure.sh"
FIXTURE="$ROOT/scripts/dogfood/fixtures/sample-codex-stream.ndjson"
CANON="$ROOT/scripts/dogfood/fixtures/sample-stream.ndjson"
chmod +x "$SCRIPT"

fails=0
fail() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

# --parse-only adapts a codex exec --json stream and emits the canonical summary.
out="$(bash "$SCRIPT" --parse-only <"$FIXTURE")"

# ttft = first agent_message text event. Fixture order: thread.started(0),
# turn.started(50), reasoning(100), agent_message "Hello "(150), agent_message
# "world"(200), turn.completed(250). Reasoning must NOT count as text.
echo "$out" | jq -e '.ttft_ms == 150' >/dev/null || fail "ttft_ms expected 150 (first agent_message, not reasoning), got $(echo "$out" | jq -c '.ttft_ms')"
echo "$out" | jq -e '.text_chars == 11' >/dev/null || fail "text_chars expected 11 ('Hello world'), got $(echo "$out" | jq -c '.text_chars')"
echo "$out" | jq -e '.output_tokens == 30' >/dev/null || fail "output_tokens expected 30, got $(echo "$out" | jq -c '.output_tokens')"
echo "$out" | jq -e '.input_tokens == 120' >/dev/null || fail "input_tokens expected 120, got $(echo "$out" | jq -c '.input_tokens')"
# 30 tokens over 50ms => 600 tok/s
echo "$out" | jq -e '.tok_per_sec == 600' >/dev/null || fail "tok_per_sec expected 600, got $(echo "$out" | jq -c '.tok_per_sec')"
echo "$out" | jq -e '.session_id == "codex-fixture-1"' >/dev/null || fail "session_id expected codex-fixture-1 (from thread.started), got $(echo "$out" | jq -c '.session_id')"
echo "$out" | jq -e '.num_turns == 1' >/dev/null || fail "num_turns expected 1, got $(echo "$out" | jq -c '.num_turns')"
# codex cached_input_tokens must land on the canonical cache_read_input_tokens
echo "$out" | jq -e '.cache_read_input_tokens == 0' >/dev/null || fail "cache_read_input_tokens expected 0, got $(echo "$out" | jq -c '.cache_read_input_tokens')"

# Rate-card pricing arms the cost column (codex emits no cost field).
priced="$(bash "$SCRIPT" --parse-only --in-usd-per-mtok 2 --out-usd-per-mtok 8 <"$FIXTURE")"
# (120*2 + 30*8)/1e6 = 0.00048
echo "$priced" | jq -e '.total_cost_usd == 0.00048' >/dev/null || fail "total_cost_usd expected 0.00048, got $(echo "$priced" | jq -c '.total_cost_usd')"

# Without rate args the cost column stays null, never a silent $0.
echo "$out" | jq -e '.total_cost_usd == null' >/dev/null || fail "total_cost_usd expected null without rate args, got $(echo "$out" | jq -c '.total_cost_usd')"

# A stream-reported cost is never overwritten by the rate-card estimate.
priced_canon="$(bash "$SCRIPT" --parse-only --in-usd-per-mtok 2 --out-usd-per-mtok 8 <"$CANON")"
echo "$priced_canon" | jq -e '.total_cost_usd == 0.0012' >/dev/null || fail "stream-reported cost must win over rate args, got $(echo "$priced_canon" | jq -c '.total_cost_usd')"

# num_turns counts turn.completed events, not lines or 1.
two_turns='{"type":"thread.started","thread_id":"codex-two"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"a","item_type":"agent_message","text":"x"}}
{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"b","item_type":"agent_message","text":"y"}}
{"type":"turn.completed","usage":{"input_tokens":8,"output_tokens":4}}'
tout="$(printf '%s\n' "$two_turns" | bash "$SCRIPT" --parse-only)"
echo "$tout" | jq -e '.num_turns == 2' >/dev/null || fail "num_turns expected 2, got $(echo "$tout" | jq -c '.num_turns')"

# turn.failed must still produce an end event (a failed run is a measured row).
failed_stream='{"type":"thread.started","thread_id":"codex-fail-1"}
{"type":"turn.started"}
{"type":"turn.failed","error":{"message":"provider rejected request"}}'
fout="$(printf '%s\n' "$failed_stream" | bash "$SCRIPT" --parse-only)"
echo "$fout" | jq -e '.session_id == "codex-fail-1"' >/dev/null || fail "failed run lost session_id"
echo "$fout" | jq -e '.stop_reason == "turn.failed"' >/dev/null || fail "failed run stop_reason expected turn.failed, got $(echo "$fout" | jq -c '.stop_reason')"

# Non-codex passthrough: canonical grok-shape input still parses unchanged
# (same summarizer, so a pre-canonical stream must not double-adapt).
cout="$(bash "$SCRIPT" --parse-only <"$CANON")"
echo "$cout" | jq -e '.session_id == "sess-test"' >/dev/null || fail "canonical passthrough broke: got $(echo "$cout" | jq -c '.session_id')"
echo "$cout" | jq -e '.total_cost_usd == 0.0012' >/dev/null || fail "canonical passthrough cost expected 0.0012, got $(echo "$cout" | jq -c '.total_cost_usd')"

if [[ "$fails" -gt 0 ]]; then
  echo "FAIL mistral-measure.test.sh ($fails failures)" >&2
  exit 1
fi
echo "PASS mistral-measure.test.sh"
