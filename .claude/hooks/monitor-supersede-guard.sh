#!/usr/bin/env bash
# PreToolUse hook on Monitor.
# REPORTS — never blocks — arming a Monitor on a target this session is still
# watching, and names the task ids to stop.
#
# Source rule: hr-monitor-not-run-in-background-for-polling (AGENTS.rules.md)
# governs WHICH tool polls. This governs the tool's LIFETIME, which nothing
# enforced: a monitor is a resource, and re-scoping what you watch means
# stopping the old watcher, not layering a new one beside it.
#
# Why: 2026-09-02 — one session ran THREE monitors against `gh pr checks 7753`
# at once. Each re-scope (CI -> infra+CI -> CI) armed a new monitor and left the
# previous running; none self-terminated, because each exits only when the polled
# state goes terminal. The operator noticed; no gate did. (First-person account —
# no ledger entry corroborates it, necessarily, since this is the hook that would
# have recorded one.)
#
# LIVENESS IS MEASURED, NOT INFERRED — and this is the part to re-read before
# changing anything. An earlier revision asserted a hook "cannot observe a monitor
# finishing" and inferred liveness from the clock instead. That was false, and it
# was asserted after testing two of three routes:
#
#   1. Clock inference — "still inside its declared timeout_ms". Rejected: a
#      monitor usually ends by early exit or harness reap long before its window,
#      so this degrades into "armed recently" and fires mostly on dead monitors.
#   2. Process table — `pgrep -f <signature>`. Rejected, and instructively: the
#      agent's own Bash commands carry the PR number, so the probe matches the
#      shell asking the question. A control probe for a signature with NO monitor
#      matched its own shell.
#   3. The transcript. `transcript_path` is in the hook payload; a Monitor's
#      PostToolUse response carries `toolUseResult.taskId`; and a task's life is
#      reported as `<task-notification>` blocks keyed to that id. THIS ONE
#      WORKS, and is what the hook uses.
#
# THE TERMINAL RULE (#8420 / #7961, re-measured against ~300 real transcripts):
# a task is ended iff its MOST RECENT notification block is terminal, judged
# block by block — never record by record, since one record can batch several
# blocks (up to 17 seen) and a monitor's own output rides inside <event>. A
# block is terminal when, OUTSIDE its <event>/<summary>/<result>/<note> bodies,
# it carries `<status>completed</status>` or `<status>failed</status>`, or when
# its WHOLE <event> is the harness's expiry sentence, verbatim in the wild as
#   [Monitor expired after 30m with no events delivered. Re-arm it if you still
#    need the watch — and widen the filter if silence was unexpected.]
#   [Monitor expired after 30m with 3 events delivered. Re-arm it if you still
#    need the watch.]                       (also "with 1 event delivered.")
# or the older `[Monitor timed out — re-arm if needed.]` quoted in #7961 (zero
# occurrences today; kept). Anything else — an ordinary event, a `running`
# status — is a LIVE notification, and a later one supersedes an earlier end.
#
# killed / stopped are NOT terminal, deliberately. Measured: all 51 `killed`
# blocks are background Bash commands the harness reaped ("was stopped because
# the system is running low on memory"), and all 14 `stopped` blocks are
# resume-time orphan summaries for background shells of a PREVIOUS session —
# zero of either on a Monitor. A TaskStop'd monitor emits no terminal block at
# all (177 of 177 stopped monitors end on an ordinary event); it is cleared by
# the recorder's stop row instead, which is exact.
#
# Route 3 has the same contamination trap as route 2 and it must be filtered
# structurally: the transcript also holds the AGENT'S OWN text, the operator's
# prompts, compaction summaries and tool output, any of which can quote a
# `<task-id>X</task-id>` next to a terminal tag (a naive grep read a live
# monitor as finished the moment the agent grepped for it — verified). Only
# these harness-written record shapes are read; every other type — assistant,
# system, a user record without that origin, isCompactSummary — is ignored:
#   - type=user, origin.kind=="task-notification", message.content a string
#   - type=attachment, attachment.type=="queued_command",
#     attachment.commandMode=="task-notification", attachment.prompt a string
#   - type=queue-operation, operation enqueue|remove, content a string that is
#     NOTHING BUT notification blocks (typed prompts are queued the same way;
#     residual: a prompt consisting solely of a pasted block still counts)
#
# WHY THIS STILL DOES NOT DENY, given liveness now works: the transcript's record
# shape is an undocumented harness internal with no compatibility contract. If it
# changes, every task reads NOT-DEAD — which for a report means extra noise, and
# for a deny would mean blocking every re-arm in the repo. Fail-open is only
# available at the report tier. The cost asymmetry says the same thing: a false
# notice costs a paragraph, a false deny cost a ship run.
#
# Detection (anything missing falls through to silence):
#   tool_name == Monitor
#   AND a signature is extractable (lib/monitor-sig.sh; its misses are listed there)
#   AND this session has arms on that signature
#   AND those arms are neither stopped (exact, by task id) nor observed terminal
#
# Hook stdin: JSON payload with session_id + tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput:{additionalContext}, systemMessage} when
#   reporting; silent otherwise. BOTH fields deliberately: `additionalContext` is
#   the channel this repo has verified reaches the model (phase-surface-hint.sh),
#   while `systemMessage` is documented upstream as model-visible and in-repo as
#   operator-visible. The two sources disagree; emitting both is correct under
#   either reading and costs three lines. stderr is NOT a channel here — Claude
#   Code discards a PreToolUse hook's stderr on exit 0.
# Hook exit code: 0 always.
set -uo pipefail

_HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 0
[ -f "$_HOOK_DIR/lib/monitor-sig.sh" ] || exit 0
# shellcheck source=/dev/null
. "$_HOOK_DIR/lib/monitor-sig.sh" || exit 0
export SOLEUR_HOOK_NAME="monitor-supersede-guard"
# Sourced INSIDE emit(), not at the top: measured, the top-level source costs 8
# processes and ~19ms on every invocation, and emit() is reached on the
# reporting path only — well under 1% of calls.
emit() {
  if [ -f "$_HOOK_DIR/lib/incidents.sh" ]; then
    # shellcheck source=/dev/null
    . "$_HOOK_DIR/lib/incidents.sh" || return 0
  fi
  if command -v emit_incident >/dev/null 2>&1; then emit_incident "$@" || true; fi
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="${SOLEUR_MONITOR_LEDGER:-$PROJECT_DIR/.claude/.monitor-arms.jsonl}"

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
# DEVIN-SKIP reason=no-analog: Devin has no Monitor tool; Claude-canonical
# gate intentionally left on the raw name. Ledger: devin-dispositions.tsv.
[ "$TOOL" = "Monitor" ] || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r 'if ((.transcript_path? // null)|type)=="string" then .transcript_path else "" end' 2>/dev/null) || TRANSCRIPT=""
NOW=$(date +%s 2>/dev/null) || exit 0
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

SIG="$(monitor_sig "$INPUT")"
[ -n "$SIG" ] || exit 0
[ -r "$LEDGER" ] || exit 0

# ---- read the ledger -------------------------------------------------------
# `fromjson? | objects | select((.ts|type)=="number")` — all three filters are
# load-bearing and each was measured. `fromjson?` drops unparseable lines; that
# alone was the previous version, and it let a bare `12345` through pass 1 to
# kill pass 2 with "Cannot index number with string", disarming the gate
# PERMANENTLY and silently. `objects` drops scalars and arrays; the ts type test
# drops a string timestamp, which otherwise poisons `max` and makes every
# comparison false. Each malformed row now costs one record, which is what the
# comment here used to claim without covering.
# `tail -n 2000` is what removes the growth term: measured, an uncapped read is
# linear in file size (12s and 841MB RSS at 1M lines) while a capped one is flat
# at ~20ms from 10k lines to 1M. Rotation alone would still leave ~370ms at the
# 5MB threshold. Sound, not just faster: the query is session-scoped, a monitor
# cannot outlive its session, and the busiest observed session wrote 34 rows — so
# 2000 is ~60x the worst case, and any stop that clears an in-window arm is
# physically later than it in an append-only file, hence also inside the tail.
ROWS=$(tail -n 2000 "$LEDGER" 2>/dev/null | jq -R 'fromjson? | objects | select((.ts? | type) == "number")' 2>/dev/null) || exit 0
[ -n "$ROWS" ] || exit 0

STOPPED=$(printf '%s' "$ROWS" | jq -s -r --arg s "$SESSION" \
  '[ .[] | select(.event=="stop" and .session==$s) | (.task? // "") | select(. != "") ] | unique | join(" ")' 2>/dev/null) || STOPPED=""

CANDIDATES=$(printf '%s' "$ROWS" | jq -s -r --arg s "$SESSION" --arg sig "$SIG" --argjson now "$NOW" '
  [ .[]
    | select(.event=="arm" and .session==$s and .sig==$sig)
    # An arm with no task id predates the recorder or lost its response; fall
    # back to the old recency test for those rather than dropping them.
    | select((.task? // "") != "" or (.ts + (.window // 300) > $now))
  ] | .[] | [.ts, (.task // ""), (.desc // "")] | @tsv' 2>/dev/null) || exit 0
[ -n "$CANDIDATES" ] || exit 0

# Split one candidate row WITHOUT `IFS=$'\t' read`: tab is IFS-whitespace, so
# read collapses an empty middle field and shifts the description into the task
# id. @tsv above also escapes any tab/newline inside a field, so exactly two
# tabs separate the three fields.
split_row() {   # $1 = row; sets r_ts r_task r_desc
  local rest
  r_ts=${1%%$'\t'*}; rest=${1#*$'\t'}
  r_task=${rest%%$'\t'*}; r_desc=${rest#*$'\t'}
}

# ---- liveness: which candidate tasks are OBSERVED terminal? ----------------
# ONE read of the transcript for every candidate (a per-arm grep made the
# cost linear in arms x transcript size). Measured on a 100 MB synthetic
# transcript: ~100 ms vs ~270 ms before; ~275 ms either way in the worst case
# of 12k notification lines all naming candidates. The rule and the accepted record
# shapes are in the header; this is their implementation.
# Each candidate id is its own -e pattern. The grep only narrows lines; jq
# alone decides. jq reads to EOF, so there is no early-exiting consumer for
# pipefail to turn into a false failure (#6992); a grep matching nothing yields
# an empty, all-live answer.
WANT=""
GREP_ARGS=()
while IFS= read -r row; do
  split_row "$row"
  [ -n "$r_task" ] || continue
  case " $STOPPED " in *" $r_task "*) continue ;; esac
  WANT="$WANT $r_task"
  GREP_ARGS+=(-e "<task-id>$r_task</task-id>")
done <<ROWS
$CANDIDATES
ROWS

TERMINAL=""
if [ "${#GREP_ARGS[@]}" -gt 0 ] && [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  TERMINAL=$(grep -F "${GREP_ARGS[@]}" -- "$TRANSCRIPT" 2>/dev/null | jq -nR -r --arg want "$WANT" '
    # String splits, not regex, everywhere but the short event test: jq
    # match/sub/gsub cost ~5x the whole scan here (measured, 12k blocks).
    # -> [source, content]. Written to be error-free on any record shape (a
    # `try` costs ~40% here). source "e" = the enqueue, "d" = a later delivery
    # of the same block (user record, attachment, queue remove).
    def body:
      if .type == "user" then
        select((.origin | objects | .kind) == "task-notification") | .message | objects | .content
        | strings | ["d", .]
      elif .type == "attachment" then
        .attachment | objects
        | select(.type == "queued_command" and .commandMode == "task-notification") | .prompt
        | strings | ["d", .]
      elif .type == "queue-operation" and (.operation == "enqueue" or .operation == "remove") then
        .operation as $op | .content | strings
        | select(startswith("<task-notification>") and endswith("</task-notification>"))
        | [(if $op == "enqueue" then "e" else "d" end), .]
      else empty end;
    # Each <task-notification> body in a record, individually (the text after
    # the LAST opener before each closer; an unclosed tail is dropped).
    def blocks:
      split("</task-notification>") | .[:-1][]
      | select(contains("<task-notification>"))
      | split("<task-notification>") | last;
    # The block HEADER: everything before its first free-text body. In all
    # 6688 real blocks measured, <task-id> and <status> sit there and every
    # <summary>/<event>/<result>/<note>/<usage> follows them — and the bodies
    # are where monitor output and the agent-written description live.
    def header:
      reduce ("<summary>", "<event>", "<result>", "<note>", "<usage>") as $t
        (.; if contains($t) then split($t) | .[0] else . end);
    def events:
      split("<event>") | .[1:][] | split("</event>") | .[0];
    # The WHOLE event must be the harness sentence, not merely start like it.
    def terminal_event:
      contains("[Monitor ") and (
        test("\\A\\s*\\[Monitor expired after [0-9]+[a-z]{1,3} with (no|[0-9]+) events? delivered\\. Re-arm it if you still need the watch(\\.| — [^\\]\\n]*\\.)\\]\\s*\\z")
        or test("\\A\\s*\\[Monitor timed out( — [^\\]\\n]*)?\\]\\s*\\z"));
    # -> [task-id, is_terminal] for every id the block header names.
    def verdicts:
      . as $b
      | ($b | header) as $h
      | (($h | contains("<status>completed</status>") or contains("<status>failed</status>"))
         or any($b | events; terminal_event)) as $term
      | $h | split("<task-id>") | .[1:][] | select(contains("</task-id>"))
      | [(split("</task-id>") | .[0]), $term];
    # MOST RECENT WINS, read newest-first: the first block met for an id
    # decides it, and each pass stops once every id it serves is decided
    # (usually within the last few lines); nothing older is parsed.
    # "Most recent" is ENQUEUE order. Deliveries lag enqueues — measured, a
    # monitor `completed` block enqueued on one line and its PREVIOUS live event
    # delivered as a user record on the next — so a delivery decides an id only
    # when no enqueue for it exists (none such in ~300 transcripts: all 1683
    # delivered ids were enqueued; kept as a fallback for older harnesses).
    # So: pass 1 reads enqueues; pass 2 reads everything, only for ids pass 1
    # left undecided and only on lines naming one of them.
    # decide($lines; $ids; $srcs): newest-first over $lines, keeping blocks
    # whose source is in $srcs, stopping once every id in $ids is decided.
    def decide($lines; $ids; $srcs):
      ($ids | map({(.): true}) | add // {}) as $w
      | ($ids | length) as $n
      | [ label $done
          | foreach (($lines | reverse[] | fromjson? | objects | body
                      | select(.[0] as $s | $srcs | index([$s])) | .[1] | [blocks] | reverse[] | verdicts), null) as $v
              ({};
               if $v != null and $w[$v[0]] and (has($v[0]) | not) then .[$v[0]] = $v[1] else . end;
               if $v == null or length == $n then ., break $done else empty end)
        ] | (last // {});
    ($want | split(" ") | map(select(. != "")) | unique) as $ids
    | [inputs] as $lines
    # Raw-substring prefilter before parsing (jq-compact JSON has no space
    # after the colon; were that to change, pass 1 finds nothing and pass 2
    # still decides every id — correct, only slower).
    | decide([$lines[] | select(contains("\"type\":\"queue-operation\""))]; $ids; ["e"]) as $e
    | ($ids | map(select(. as $i | $e | has($i) | not))) as $rest
    | (if ($rest | length) == 0 then {}
       else decide([$lines[] | select(. as $l | any($rest[]; . as $i | $l | contains("<task-id>" + $i + "</task-id>")))]; $rest; ["e", "d"])
       end) as $d
    | $d + $e
    | to_entries | map(select(.value) | .key) | join(" ")' 2>/dev/null) || TERMINAL=""
fi

LIVE_N=0
LIVE_LIST=""
while IFS= read -r row; do
  split_row "$row"
  [ -n "$r_ts" ] || continue
  if [ -n "$r_task" ]; then
    case " $STOPPED " in *" $r_task "*) continue ;; esac
    case " $TERMINAL " in *" $r_task "*) continue ;; esac
  fi
  case "$r_ts" in ''|*[!0-9]*) age="?" ;; *) age=$(( NOW - r_ts )) ;; esac
  LIVE_N=$(( LIVE_N + 1 ))
  LIVE_LIST="${LIVE_LIST}  - ${r_task:-(no task id)} — \"${r_desc}\" (armed ${age}s ago)"$'\n'
done <<ROWS
$CANDIDATES
ROWS

[ "$LIVE_N" -gt 0 ] || exit 0

emit monitor-supersede warn "still-live monitor on $SIG" "$SIG" 2>/dev/null || true

MSG="monitor-supersede: this session has ${LIVE_N} monitor(s) still watching ${SIG}:
${LIVE_LIST}Arming another means duplicate work on one target — for a poll loop, duplicate
requests every interval; for a ws:// stream, a second subscription — and two
reports of the same result. TaskStop the one(s) above you are replacing.
A \`TaskStop\` answering \`No task found\` means that row had already ended."

jq -n --arg m "$MSG" '{
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $m },
  systemMessage: $m
}' 2>/dev/null || true
exit 0
