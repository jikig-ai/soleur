#!/usr/bin/env bash
# Tests for scripts/measure-plan-sharp-edges-turns.sh (#8325 §3).
#
# THE PROPERTY: for every `soleur:plan` run found in a local Claude Code
# transcript tree, the script reports how many assistant TURNS (requestId
# groups, never records) elapse between the invocation and the first Read of
# the extracted Sharp Edges catalogue, classifies the run by the skill body the
# harness actually loaded (the preamble record naming the catalogue), and emits
# NO byte of transcript content on either stream. A corpus with no file or no
# run is a loud null reading, never a bare zero.
#
# Every fixture is SYNTHESIZED (cq-test-fixtures-synthesized-only): no real
# session line, no UUID-shaped identifier, ids like `req-1`/`agent-t1`, strictly
# increasing timestamps. Every negative assertion (sentinel absent, no row
# printed) sits beside a positive control in the same case so a crashing SUT
# cannot pass by printing nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/measure-plan-sharp-edges-turns.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq missing — this suite cannot run its SUT (an exit-0 skip reads as green)"; exit 1; }

TMP_ROOT=$(mktemp -d -t measuretest.XXXXXXXX) || { echo "FATAL: cannot create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root" >&2; exit 1; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMP_ROOT"

fails=0
passes=0
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); }

# Instrument self-test: drive both helpers before any real case, so a gutted
# helper cannot report a clean sweep. Reports with printf + exit, never through
# the helpers it guards.
pass "instrument self-test (pass path)"
fail "instrument self-test (fail path — expected, subtracted below)"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: assertion helpers are not dispatching (passes=%s fails=%s)\n' "$passes" "$fails" >&2
  exit 2
fi
fails=0

[[ -x "$SUT" ]] || { echo "  FAIL: $SUT not executable (RED expected before implementation)"; echo "0 passed, 1 failed"; exit 1; }

echo "measure-plan-sharp-edges-turns.test.sh"

# --- record helpers -----------------------------------------------------------
# Each prints ONE synthesized JSONL record. `ts` is a real ISO timestamp (so
# window_from/window_to are pinned to dates), `id` a short non-UUID token used
# for requestId (assistant) or uuid (user). The optional trailing argument is a
# jq FILTER applied last (`del(.message.usage)`, `.isSidechain = true`, ...).
SENT='SENTINEL-DO-NOT-PRINT-7f3a'
CAT='skills/plan/references/plan-sharp-edges.md'
PLANS='knowledge-base/project/plans/'
rec_assistant_tool_use() { # ts id tool-name input-json [filter]
  jq -cn --arg ts "$1" --arg id "$2" --arg name "$3" --argjson input "$4" \
    '{type:"assistant", requestId:$id, uuid:($id+"-u"), isSidechain:false, timestamp:$ts,
      message:{id:$id, role:"assistant", usage:{cache_read_input_tokens:1000},
               content:[{type:"tool_use", id:("toolu-"+$id), name:$name, input:$input}]}}
     | '"${5:-.}"
}
rec_assistant_text() { # ts id text [filter]
  jq -cn --arg ts "$1" --arg id "$2" --arg text "$3" \
    '{type:"assistant", requestId:$id, uuid:($id+"-u"), isSidechain:false, timestamp:$ts,
      message:{id:$id, role:"assistant", usage:{cache_read_input_tokens:1000},
               content:[{type:"text", text:$text}]}}
     | '"${4:-.}"
}
rec_user_text() { # ts id text [filter]
  jq -cn --arg ts "$1" --arg id "$2" --arg text "$3" \
    '{type:"user", uuid:$id, isSidechain:false, timestamp:$ts,
      message:{role:"user", content:[{type:"text", text:$text}]}}
     | '"${4:-.}"
}
rec_user_tool_result() { # ts id text [filter]
  jq -cn --arg ts "$1" --arg id "$2" --arg text "$3" \
    '{type:"user", uuid:$id, isSidechain:false, timestamp:$ts,
      message:{role:"user", content:[{type:"tool_result", tool_use_id:"toolu-x", content:$text}]}}
     | '"${4:-.}"
}
rec_user_string() { # ts id text — message.content as a bare STRING
  jq -cn --arg ts "$1" --arg id "$2" --arg text "$3" \
    '{type:"user", uuid:$id, isSidechain:false, timestamp:$ts, message:{role:"user", content:$text}}'
}
rec_user_command() { # ts id — the operator-typed /soleur:plan form
  rec_user_text "$1" "$2" '<command-message>plan</command-message><command-name>/soleur:plan</command-name>'
}
skill_plan() { printf '{"skill":"soleur:plan","args":"%s"}' "${1:-do the thing}"; }
read_of()    { printf '{"file_path":"%s"}' "$1"; }
bash_of()    { printf '{"command":"%s"}' "$1"; }
write_of()   { jq -cn --arg p "$1" --arg c "$2" '{file_path:$p, content:$c}'; }
edit_of()    { jq -cn --arg p "$1" --arg n "$2" '{file_path:$p, old_string:"x", new_string:$n}'; }
# The loaded-skill preamble record. Post-extraction bodies name the catalogue.
preamble_post() { rec_user_text "$1" "$2" "Base directory for this skill: /base/skills/plan

Step 6.5: Read references/plan-sharp-edges.md before Plan Review."; }
preamble_pre()  { rec_user_text "$1" "$2" "Base directory for this skill: /base/skills/plan

## Sharp Edges (inline)"; }

new_root() { local r="$TMP_ROOT/$1"; mkdir -p "$r/sess-$1"; printf '%s' "$r"; }
# run <root> [args...] → sets OUT ERR RC
run() {
  local root=$1; shift
  local ef="$TMP_ROOT/stderr.$$"
  OUT=$(MEASURE_TRANSCRIPT_ROOT="$root" bash "$SUT" "$@" 2>"$ef"); RC=$?
  ERR=$(cat "$ef")
}
rows_of()    { printf '%s\n' "$OUT" | grep -vE '^(#|runs=)' || true; }
summary_of() { printf '%s\n' "$OUT" | grep -E '^runs=' || true; }
# Single site for the privacy predicate (Guard 3 row 12 deletes it).
assert_no_sentinel() { ! grep -qF -- "$SENT" <<<"$1"; }

# The basic post-extraction fixture (Guard 3 row 1): single-record invocation
# turn, preamble, a three-record turn, then the catalogue Read → k=2.
fx_post_basic() { # file [read-path]
  local f=$1 rp=${2:-/base/plugins/soleur/$CAT}
  assert_fixture_dir "$f"
  {
    rec_assistant_tool_use 2026-09-18T10:00:00Z req-1 Skill "$(skill_plan)"
    rec_user_tool_result   2026-09-18T10:00:01Z u-1 'Launching skill: soleur:plan'
    preamble_post          2026-09-18T10:00:02Z u-2
    rec_assistant_text     2026-09-18T10:00:03Z req-2 'thinking'
    rec_assistant_text     2026-09-18T10:00:04Z req-2 'more'
    rec_assistant_tool_use 2026-09-18T10:00:05Z req-2 Bash "$(bash_of 'ls')"
    rec_user_tool_result   2026-09-18T10:00:06Z u-3 'ok'
    rec_assistant_tool_use 2026-09-18T10:00:07Z req-3 Read "$(read_of "$rp")"
  } > "$f"
}

# --- 1. turns are requestId groups; rows are exact -----------------------------
R=$(new_root c1); assert_fixture_dir "$R"; fx_post_basic "$R/sess-c1/sess.jsonl"
run "$R" --rows
HDR=$(printf '# kind\tk\tk_first\tk_ac\tturns_in_window')
ROW=$(printf 'post\t2\t-1\t-1\t2')
if [[ "$RC" -eq 0 && "$(printf '%s\n' "$OUT" | sed -n 1p)" == "$HDR" && "$(rows_of)" == "$ROW" \
      && "$(summary_of)" == *"runs=1 post=1 post_skipped=0 pre=0 unknown=0 median_k=2 "* \
      && "$(summary_of)" == *"window_from=2026-09-18 window_to=2026-09-18 "* ]]; then
  pass "a three-record turn counts once: row 'post 2 -1 -1 2', median_k=2, window pinned to 2026-09-18"
else
  fail "record/turn confusion — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 1b. turn order is file order, never sorted by id --------------------------
R=$(new_root c1b); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T10:10:00Z req-b Skill "$(skill_plan)"
  preamble_post          2026-09-18T10:10:01Z u-1
  rec_assistant_tool_use 2026-09-18T10:10:02Z req-a Read "$(read_of "/base/$CAT")"
} > "$R/sess-c1b/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'post\t1\t-1\t-1\t1')" ]]; then
  pass "request ids req-b then req-a keep file order (k=1; a group_by would invert the turns)"
else
  fail "turn order sorted by id — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 2. the invocation may sit in the third record of its turn ----------------
R=$(new_root c2); assert_fixture_dir "$R"; {
  rec_assistant_text     2026-09-18T10:20:00Z req-1 'first'
  rec_assistant_text     2026-09-18T10:20:01Z req-1 'second'
  rec_assistant_tool_use 2026-09-18T10:20:02Z req-1 Skill "$(skill_plan)"
  preamble_post          2026-09-18T10:20:03Z u-1
  rec_assistant_tool_use 2026-09-18T10:20:04Z req-2 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c2/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'post\t1\t-1\t-1\t1')" ]]; then
  pass "an invocation in the third record of its turn starts the run (tool_use blocks are unioned per turn)"
else
  fail "only the first record of a turn was searched — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 3. suffix match: installed-plugin cache path counts, a .bak sibling does not
R=$(new_root c3); assert_fixture_dir "$R"; fx_post_basic "$R/sess-c3/sess.jsonl" "/home/x/.claude/plugins/cache/mp/soleur/h4sh/$CAT"
run "$R" --rows; A=$(rows_of)
R=$(new_root c3b); assert_fixture_dir "$R"; fx_post_basic "$R/sess-c3b/sess.jsonl" "/base/plugins/soleur/skills/work/references/plan-sharp-edges.md.bak"
run "$R" --rows; B=$(rows_of)
if [[ "$A" == "$(printf 'post\t2\t-1\t-1\t2')" && "$B" == "$(printf 'post_skipped\t-1\t-1\t-1\t2')" ]]; then
  pass "the installed-plugin cache path counts as post; a work/…/plan-sharp-edges.md.bak Read does not"
else
  fail "catalogue path matched by prefix or bare substring — cache='$A' bak='$B' err='$ERR'"
fi

# --- 4. a pre-extraction run: k=-1, k_first from a Bash heredoc, k_ac from an Edit
R=$(new_root c4); assert_fixture_dir "$R"; f="$R/sess-c4/sess.jsonl"; {
  rec_assistant_tool_use 2026-09-18T11:00:00Z req-1 Skill "$(skill_plan)"
  preamble_pre           2026-09-18T11:00:01Z u-1
  rec_user_text          2026-09-18T11:00:02Z u-2 "operator quoting ADR-229: references/plan-sharp-edges.md is 58k tokens"
  i=2; while [[ $i -le 41 ]]; do
    case $i in
      # NOTE: this Bash fixture deliberately does NOT contain a literal heredoc
      # opener. scripts/guard-vacuity-floor.test.sh detects heredoc bodies with
      # an awk scanner that keys on a here-doc opener anywhere in a line (this
      # comment must not spell one, or it trips the very detector it describes)
      # -- an unterminated
      # one inside a STRING made it treat every following line as heredoc body,
      # which excluded this suite's own anti-vacuity floor and silently dropped
      # the whole file from the meta-guard's population (NOT_IN_POPULATION, so
      # the closure assertions were satisfied vacuously for it). Keep it
      # heredoc-free; `k_first` only needs a Bash command naming a plans/ path.
      5)  rec_assistant_tool_use "2026-09-18T11:01:$(printf %02d $((i % 60)))Z" "req-$i" Bash "$(bash_of "printf %s x > ${PLANS}2026-09-18-x-plan.md")" ;;
      31) rec_assistant_tool_use "2026-09-18T11:02:$(printf %02d $((i % 60)))Z" "req-$i" Edit "$(edit_of "/w/${PLANS}2026-09-18-x-plan.md" '## Acceptance Criteria')" ;;
      41) rec_assistant_tool_use "2026-09-18T11:03:$(printf %02d $((i % 60)))Z" "req-$i" Read "$(read_of "/base/$CAT")" ;;
      *)  rec_assistant_text     "2026-09-18T11:04:$(printf %02d $((i % 60)))Z" "req-$i" "turn $i" ;;
    esac
    i=$((i + 1))
  done
} > "$f"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'pre\t-1\t4\t30\t40')" \
      && "$(summary_of)" == *"pre=1 "* && "$(summary_of)" == *"median_k=na "* \
      && "$(summary_of)" == *"median_k_first=4 n_k_first=1 median_k_ac=30 n_k_ac=1 "* ]]; then
  pass "a pre-extraction body classifies as pre even with a later Read: row 'pre -1 4 30 40' (Bash heredoc + AC Edit proxies)"
else
  fail "pre run misclassified or proxies wrong — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 5. post_skipped and unknown ------------------------------------------------
R=$(new_root c5); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T12:00:00Z req-1 Skill "$(skill_plan)"
  preamble_post          2026-09-18T12:00:01Z u-1
  rec_assistant_text     2026-09-18T12:00:02Z req-2 'no read'
} > "$R/sess-c5/sess.jsonl"
run "$R" --rows; A=$(rows_of); AS=$(summary_of)
R=$(new_root c5b); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T12:10:00Z req-1 Skill "$(skill_plan)"
  rec_user_tool_result   2026-09-18T12:10:01Z u-1 'Launching skill: soleur:plan'
  rec_assistant_tool_use 2026-09-18T12:10:02Z req-2 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c5b/sess.jsonl"
run "$R" --rows; B=$(rows_of); BE=$ERR
if [[ "$A" == "$(printf 'post_skipped\t-1\t-1\t-1\t1')" && "$AS" == *"post_skipped=1 "* && "$AS" == *"median_k=na "* \
      && "$B" == "$(printf 'unknown\t-1\t-1\t-1\t1')" && "$BE" == *"WARNING: unknown=1 run(s) had no skill-body record"* ]]; then
  pass "an extracted body with no Read is post_skipped (median_k=na); no preamble record is unknown with a stderr WARNING"
else
  fail "post_skipped/unknown wrong — a='$A' as='$AS' b='$B' be='$BE'"
fi

# --- 6. privacy: the sentinel in every string field the parser reads ------------
R=$(new_root "c6-$SENT"); assert_fixture_dir "$R"; mkdir -p "$R/sess-$SENT/subagents"; {
  rec_assistant_tool_use 2026-09-18T13:00:00Z "req-$SENT-1" Skill "$(skill_plan "$SENT")" ".uuid = \"u-$SENT\""
  rec_user_tool_result   2026-09-18T13:00:01Z "u-$SENT-1" "Launching $SENT"
  rec_user_text          2026-09-18T13:00:02Z "u-$SENT-2" "Base directory for this skill: /$SENT/skills/plan — references/plan-sharp-edges.md $SENT"
  rec_user_string        2026-09-18T13:00:03Z "u-$SENT-3" "bare string $SENT"
  rec_assistant_text     2026-09-18T13:00:04Z "req-$SENT-2" "text $SENT"
  rec_assistant_tool_use 2026-09-18T13:00:05Z "req-$SENT-3" Bash "$(bash_of "echo $SENT ${PLANS}x.md")"
  rec_assistant_tool_use 2026-09-18T13:00:06Z "req-$SENT-4" Write "$(write_of "/$SENT/${PLANS}x.md" "## Acceptance Criteria $SENT")"
  rec_assistant_tool_use 2026-09-18T13:00:07Z "req-$SENT-5" Edit "$(edit_of "/$SENT/${PLANS}x.md" "$SENT")"
  rec_assistant_tool_use 2026-09-18T13:00:08Z "req-$SENT-6" Read "$(read_of "/$SENT/plugins/soleur/$CAT")"
} | jq -c '.isSidechain = true' > "$R/sess-$SENT/subagents/agent-$SENT.jsonl"   # subagent records carry isSidechain: true
ef="$TMP_ROOT/c6.err"
# SHELLOPTS is READONLY: `SHELLOPTS=xtrace bash …` prints "readonly variable" to
# the caller's stderr and the child runs WITHOUT xtrace, so that spelling tested
# nothing. BASH_ENV is sourced by a non-interactive bash before the script runs,
# which is the only vector that actually arms `set -x` in the SUT's own shell.
xtrc="$TMP_ROOT/c6-xtrace.sh"; printf 'set -x\n' > "$xtrc"
OUT=$(MEASURE_TRANSCRIPT_ROOT="$R" BASH_ENV="$xtrc" bash "$SUT" --rows 2>"$ef"); RC=$?; ERR=$(cat "$ef")
# Positive control: the vector must actually be armed, or the arm is vacuous
# again in a new spelling. A traced run of a `set +x`-less script emits `+ `.
ctl="$TMP_ROOT/c6-ctl.sh"; printf 'echo hi\n' > "$ctl"
CTL_ERR=$(BASH_ENV="$xtrc" bash "$ctl" 2>&1 >/dev/null)
if [[ "$RC" -eq 0 && "$(summary_of)" == *"runs=1 post=1 "* && "$(rows_of)" == "$(printf 'post\t5\t2\t3\t5')" \
      && "$CTL_ERR" == *"+ echo hi"* ]] \
   && assert_no_sentinel "$OUT" && assert_no_sentinel "$ERR"; then
  pass "the sentinel planted in every parsed string field, the ids and the directory names never reaches stdout or stderr under an ARMED inherited xtrace (BASH_ENV control fired), while the run is parsed (runs=1)"
else
  fail "sentinel leaked or fixture unparsed — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 6b. a jq program error must not echo the offending value ------------------
R=$(new_root c6b); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T13:10:00Z req-1 Skill "$(skill_plan)"
  preamble_post          2026-09-18T13:10:01Z u-1
  rec_user_string        2026-09-18T13:10:02Z u-2 "bare $SENT"
  jq -cn --arg s "$SENT" '{type:"assistant", requestId:"req-2", timestamp:"2026-09-18T13:10:03Z", message:{role:"assistant", content:[{type:"tool_use", name:"Read", input:("str-"+$s)}]}}'
  jq -cn --arg s "$SENT" '{type:"assistant", requestId:"req-3", timestamp:"2026-09-18T13:10:04Z", message:("m-"+$s)}'
  rec_assistant_tool_use 2026-09-18T13:10:05Z req-4 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c6b/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(summary_of)" == *"files=1 "* ]] && { [[ "$(summary_of)" == *"runs=1 "* || "$(summary_of)" == *"dropped="[1-9]* ]]; } \
   && assert_no_sentinel "$OUT" && assert_no_sentinel "$ERR"; then
  pass "a string-typed tool_use.input / message does not surface a jq error carrying the value (rc 0, parsed or dropped)"
else
  fail "jq error leaked or aborted — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 6c. the slug on stderr masks HOME ----------------------------------------
H="$TMP_ROOT/fixture/$SENT-home"; mkdir -p "$H"
ef="$TMP_ROOT/c6c.err"
OUT=$(env -u MEASURE_TRANSCRIPT_ROOT HOME="$H" MEASURE_PROJECT_PATH="$H/proj" bash "$SUT" 2>"$ef"); RC=$?; ERR=$(cat "$ef")
if [[ "$RC" -eq 0 && "$ERR" == *"slug=HOME-proj "* && "$OUT" == *"null_reading=1"* ]] && assert_no_sentinel "$ERR" && assert_no_sentinel "$OUT"; then
  pass "stderr prints slug=HOME-proj, never the raw HOME slug"
else
  fail "HOME leaked into the slug — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 7. null reading: no files, and files with no run -------------------------
NULL_LINE='runs=0 post=0 post_skipped=0 pre=0 unknown=0 median_k=na p10_k=na p90_k=na saving_tokens_per_run=na median_k_first=na n_k_first=0 median_k_ac=na n_k_ac=0 window_from=na window_to=na files=0 parsed=0 dropped=0 unread=0 null_reading=1'
E=$(new_root c7empty); rmdir "$E/sess-c7empty"
run "$E"; A=$OUT; AE=$ERR; ARC=$RC
R=$(new_root c7b); assert_fixture_dir "$R"; rec_user_text 2026-09-18T14:00:00Z u-1 'please run soleur:plan later' > "$R/sess-c7b/sess.jsonl"
run "$R"; B=$OUT; BE=$ERR; BRC=$RC
if [[ "$ARC" -eq 0 && "$A" == "$NULL_LINE" && "$AE" == *"SOLEUR_PLAN_SHARP_EDGES_NO_PLAN_RUNS slug=override files=0 reason=no_files"* \
      && "$BRC" -eq 0 && "$B" == *"runs=0 "* && "$B" == *"files=1 "* && "$B" == *"null_reading=1"* && "$BE" == *"reason=no_runs"* ]]; then
  pass "an empty root prints the exact null line (reason=no_files, exit 0); a file with soleur:plan only in prose is reason=no_runs files=1"
else
  fail "null reading wrong — a_rc=$ARC a='$A' ae='$AE' b_rc=$BRC b='$B' be='$BE'"
fi

# --- 8. windows end at the next run start; two Skill blocks are one run -------
R=$(new_root c8); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T15:00:00Z req-1 Skill "$(skill_plan one)"
  preamble_post          2026-09-18T15:00:01Z u-1
  rec_assistant_text     2026-09-18T15:00:02Z req-2 'no read here'
  rec_assistant_tool_use 2026-09-18T15:00:03Z req-3 Skill "$(skill_plan two)"
  preamble_post          2026-09-18T15:00:04Z u-2
  rec_assistant_tool_use 2026-09-18T15:00:05Z req-4 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c8/sess.jsonl"
{
  rec_assistant_tool_use 2026-09-19T09:00:00Z req-1 Skill "$(skill_plan a)"
  rec_assistant_tool_use 2026-09-19T09:00:01Z req-1 Skill "$(skill_plan b)"
  preamble_post          2026-09-19T09:00:02Z u-1
  rec_assistant_tool_use 2026-09-19T09:00:03Z req-2 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c8/later.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(summary_of)" == *"runs=3 post=2 post_skipped=1 "* \
      && "$(summary_of)" == *"window_from=2026-09-18 window_to=2026-09-19 "* \
      && "$(rows_of | sort)" == "$(printf 'post\t1\t-1\t-1\t1\npost\t1\t-1\t-1\t1\npost_skipped\t-1\t-1\t-1\t1' | sort)" ]]; then
  pass "a window ends at the next run start (post_skipped then post), two Skill blocks in one turn are one run, a later file moves window_to"
else
  fail "window/run boundary wrong — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 9. post is decided by the PREAMBLE record, not by any text naming the file
# (row 4 pins the "later user text" arm; this pins the Read-only arm.)
R=$(new_root c9); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T16:00:00Z req-1 Skill "$(skill_plan)"
  preamble_pre           2026-09-18T16:00:01Z u-1
  # Same position, but the literals sit MID-text (a prompt quoting the plan):
  # only a block that STARTS with the harness preamble is the loaded body.
  rec_user_text          2026-09-18T16:00:01Z u-1b "quoted: Base directory for this skill … references/plan-sharp-edges.md"
  rec_assistant_tool_use 2026-09-18T16:00:02Z req-2 Read "$(read_of "/base/$CAT")"
  rec_user_text          2026-09-18T16:00:03Z u-2 "the file references/plan-sharp-edges.md was read"
  # A LATER skill body (compound's, loaded inside the window) also names the
  # catalogue: only the record at the invocation position may decide.
  rec_user_text          2026-09-18T16:00:04Z u-3 "Base directory for this skill: /base/skills/compound — see references/plan-sharp-edges.md"
  rec_assistant_text     2026-09-18T16:00:05Z req-3 'done'
} > "$R/sess-c9/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'pre\t-1\t-1\t-1\t2')" ]]; then
  pass "a catalogue Read, a same-position text quoting the literals mid-text, a later text naming the file and a later skill body naming it do not make a pre-extraction body post"
else
  fail "post decided by Read presence or by any user text — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 10. API-error records are not turns; the slash-typed form starts a run --
R=$(new_root c10); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T17:00:00Z req-1 Skill "$(skill_plan)"
  preamble_post          2026-09-18T17:00:01Z u-1
  rec_assistant_text     2026-09-18T17:00:02Z req-2 'overloaded' '.isApiErrorMessage = true'
  rec_assistant_tool_use 2026-09-18T17:00:03Z req-3 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c10/sess.jsonl"
run "$R" --rows; A=$(rows_of)
R=$(new_root c10b); assert_fixture_dir "$R"; {
  rec_user_tool_result   2026-09-18T17:09:58Z u-r '<command-message>plan</command-message><command-name>/soleur:plan</command-name>'
  rec_user_text          2026-09-18T17:09:59Z u-q 'the plan says: <command-name>/soleur:plan</command-name> lands as a user record'
  rec_assistant_text     2026-09-18T17:10:00Z req-0 'hello'
  rec_user_command       2026-09-18T17:10:01Z u-0
  preamble_post          2026-09-18T17:10:02Z u-1
  rec_assistant_text     2026-09-18T17:10:03Z req-1 'planning'
  rec_assistant_tool_use 2026-09-18T17:10:04Z req-2 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c10b/sess.jsonl"
run "$R" --rows; B=$(rows_of); BS=$(summary_of)
if [[ "$A" == "$(printf 'post\t1\t-1\t-1\t1')" && "$B" == "$(printf 'post\t2\t-1\t-1\t2')" && "$BS" == *"runs=1 "* ]]; then
  pass "an isApiErrorMessage record does not count as a turn (k=1); /soleur:plan typed by the operator starts a run with the same k as its Skill-tool twin (k=2); a tool_result or a mid-text quote of the literal does not (runs=1)"
else
  fail "api-error counted or slash form ignored — a='$A' b='$B' err='$ERR'"
fi

# --- 11. the corpus is the main slug, live worktree slugs and --worktrees-*, never <slug>* --
H="$TMP_ROOT/home11"; P="$H/.claude/projects"; SL='-fixture-proj'
mkdir -p "$P/$SL" "$P/$SL--worktrees-x" "$P/$SL-other" "$P/-outside-wt" "$TMP_ROOT/bin11"
for d in "$SL" "$SL--worktrees-x" "$SL-other" "-outside-wt"; do
  rec_assistant_text 2026-09-18T18:00:00Z req-1 'idle' > "$P/$d/s.jsonl"
done
printf '#!/usr/bin/env bash\ncase "$*" in *"worktree list"*) printf "worktree /outside/wt\\nHEAD 0\\n" ;; *) exit 1 ;; esac\n' > "$TMP_ROOT/bin11/git"
chmod +x "$TMP_ROOT/bin11/git"
ef="$TMP_ROOT/c11.err"
OUT=$(env -u MEASURE_TRANSCRIPT_ROOT HOME="$H" PATH="$TMP_ROOT/bin11:$PATH" MEASURE_PROJECT_PATH=/fixture/proj bash "$SUT" 2>"$ef"); RC=$?; ERR=$(cat "$ef")
H2="$TMP_ROOT/home11b"; mkdir -p "$H2"
ef2="$TMP_ROOT/c11b.err"
OUT2=$(env -u MEASURE_TRANSCRIPT_ROOT HOME="$H2" MEASURE_PROJECT_PATH=/tmp/a.b_c/x bash "$SUT" 2>"$ef2"); RC2=$?; ERR2=$(cat "$ef2")
if [[ "$RC" -eq 0 && "$OUT" == *"files=3 "* && "$OUT" == *"null_reading=1"* && "$ERR" == *"slug=-fixture-proj files=3 reason=no_runs"* && "$OUT2" == *"null_reading=1"* \
      && "$RC2" -eq 0 && "$ERR2" == *"slug=-tmp-a-b-c-x files=0 reason=no_files"* ]]; then
  pass "files counts <slug>, <slug>--worktrees-x and the git-listed worktree slug (3), never <slug>-other; the slug maps every non-alphanumeric to '-'"
else
  fail "corpus enumeration wrong — rc=$RC out='$OUT' err='$ERR' rc2=$RC2 err2='$ERR2'"
fi

# --- 12. harness row: the sentinel predicate can fail -------------------------
if ! assert_no_sentinel "scratch stdout carrying $SENT"; then
  pass "assert_no_sentinel reports a planted sentinel (the privacy assertion is not vacuous)"
else
  fail "assert_no_sentinel passed a planted sentinel"
fi

# --- 13. must-PASS: no usage field, and uuid-only identity ---------------------
R=$(new_root c13); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T19:00:00Z req-1 Skill "$(skill_plan)" 'del(.message.usage)'
  preamble_post          2026-09-18T19:00:01Z u-1
  rec_assistant_text     2026-09-18T19:00:02Z req-2 'x' 'del(.requestId)'
  rec_assistant_tool_use 2026-09-18T19:00:03Z req-3 Read "$(read_of "/base/$CAT")" 'del(.requestId) | del(.message.usage)'
} > "$R/sess-c13/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'post\t2\t-1\t-1\t2')" ]]; then
  pass "records without usage and records identified by uuid only are turns (k=2)"
else
  fail "fallback identity or missing usage broke the count — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 14. percentiles: conventional median, nearest-rank tails, 58000 × median --
fx_post_k() { # file k
  local f=$1 k=$2 i
  assert_fixture_dir "$f"
  {
    rec_assistant_tool_use 2026-09-18T20:00:00Z req-0 Skill "$(skill_plan)"
    preamble_post          2026-09-18T20:00:01Z u-1
    i=1; while [[ $i -lt $k ]]; do rec_assistant_text "2026-09-18T20:01:$(printf %02d $((i % 60)))Z" "req-$i" "t$i"; i=$((i + 1)); done
    rec_assistant_tool_use 2026-09-18T20:02:00Z "req-$k" Read "$(read_of "/base/$CAT")"
  } > "$f"
}
pct_case() { # name ks...
  local name=$1; shift; local R; R=$(new_root "c14-$name"); assert_fixture_dir "$R"; local k
  for k in "$@"; do fx_post_k "$R/sess-c14-$name/k$k.jsonl" "$k"; done
  run "$R"; summary_of
}
S5=$(pct_case five 3 9 20 41 50); S1=$(pct_case one 36); S2=$(pct_case two 10 36); S2b=$(pct_case twob 10 35)
if [[ "$S5" == *"median_k=20 p10_k=3 p90_k=50 saving_tokens_per_run=1160000 "* \
      && "$S1" == *"median_k=36 p10_k=36 p90_k=36 saving_tokens_per_run=2088000 "* \
      && "$S2" == *"median_k=23 p10_k=10 p90_k=36 saving_tokens_per_run=1334000 "* \
      && "$S2b" == *"median_k=22.5 p10_k=10 p90_k=35 saving_tokens_per_run=1305000 "* ]]; then
  pass "[3,9,20,41,50] → 20/3/50/1160000; [36] → 36/36/36; [10,36] → 23/10/36/1334000; [10,35] → 22.5/1305000"
else
  fail "percentiles wrong — five='$S5' one='$S1' two='$S2' twob='$S2b'"
fi

# --- 15. k=0 is a legal reading, not absent ------------------------------------
R=$(new_root c15); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T21:00:00Z req-1 Skill "$(skill_plan)"
  rec_assistant_tool_use 2026-09-18T21:00:01Z req-1 Read "$(read_of "/base/$CAT")"
  preamble_post          2026-09-18T21:00:02Z u-1
  rec_assistant_text     2026-09-18T21:00:03Z req-2 'done'
} > "$R/sess-c15/sess.jsonl"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'post\t0\t-1\t-1\t1')" && "$(summary_of)" == *"median_k=0 "* ]]; then
  pass "a catalogue Read in the invocation turn is post with k=0 and enters the median"
else
  fail "k=0 treated as absent — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 16. a truncated line is dropped, the run still counted --------------------
R=$(new_root c16); assert_fixture_dir "$R"; f="$R/sess-c16/sess.jsonl"; fx_post_basic "$f"
printf '{"type":"assistant","requestId":"req-9","time' >> "$f"
run "$R" --rows
if [[ "$RC" -eq 0 && "$(rows_of)" == "$(printf 'post\t2\t-1\t-1\t2')" && "$(summary_of)" == *"parsed=8 dropped=1 unread=0"* ]]; then
  pass "one truncated line → dropped=1 and the run is still counted (parsed=8)"
else
  fail "truncated line aborted the file — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 17. AC5 hygiene: no UUID-shaped identifier in the script or this suite ----
if ! grep -qE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}' "$SUT" "$SCRIPT_DIR/measure-plan-sharp-edges-turns.test.sh" \
   && ! printf '%s\n' "$OUT" | grep -q '/'; then
  pass "no UUID-shaped identifier in the SUT or the suite; --rows stdout carries no '/'"
else
  fail "UUID-shaped literal or a path reached the sources/stdout"
fi

# --- 18. the preamble is a BLOCK that starts with the harness literal ----------
# (a) only a mid-text quote at the invocation position → unknown, not pre;
# (b) a two-block record whose FIRST block is a pre-extraction body and whose
#     SECOND block names the catalogue → pre (the same block must carry both).
R=$(new_root c18); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T22:00:00Z req-1 Skill "$(skill_plan)"
  rec_user_text          2026-09-18T22:00:01Z u-1 "a prompt quoting: Base directory for this skill … references/plan-sharp-edges.md"
  rec_assistant_text     2026-09-18T22:00:02Z req-2 'x'
} > "$R/sess-c18/sess.jsonl"
run "$R" --rows; A=$(rows_of)
R=$(new_root c18b); assert_fixture_dir "$R"; {
  rec_assistant_tool_use 2026-09-18T22:10:00Z req-1 Skill "$(skill_plan)"
  jq -cn '{type:"user", uuid:"u-1", isSidechain:false, timestamp:"2026-09-18T22:10:01Z",
           message:{role:"user", content:[{type:"text", text:"Base directory for this skill: /base/skills/plan\n\n## Sharp Edges (inline)"},
                                          {type:"text", text:"see also references/plan-sharp-edges.md"}]}}'
  rec_assistant_tool_use 2026-09-18T22:10:02Z req-2 Read "$(read_of "/base/$CAT")"
} > "$R/sess-c18b/sess.jsonl"
run "$R" --rows; B=$(rows_of)
if [[ "$A" == "$(printf 'unknown\t-1\t-1\t-1\t1')" && "$B" == "$(printf 'pre\t-1\t-1\t-1\t1')" ]]; then
  pass "a mid-text quote at the invocation position is unknown (no preamble); a preamble block plus a sibling block naming the catalogue is pre"
else
  fail "preamble/extracted decided across blocks or by contains — a='$A' b='$B'"
fi

# --- 19-20. review round (#8382) -----------------------------------------------

# --- 19. a corpus that PARSES TO NOTHING is not an empty corpus ----------------
# Every survivor failing to parse rendered as `null_reading=1 parsed=0`, which is
# byte-identical to "this corpus genuinely holds no plan runs". The sibling
# classifier refuses exactly this shape; the guard was not carried over.
R=$(new_root c19); assert_fixture_dir "$R"
# Carries the pre-filter literal (so it survives to the jq stage) but is not JSON
# at any line, so the per-file program yields no rows at all.
printf 'soleur:plan but not json at all\nstill not json\n' > "$R/sess-c19/sess.jsonl"
run "$R"
if [[ "$RC" -eq 2 && "$ERR" == *"parsed 0 record(s)"* && "$ERR" == *"not an absence of plan runs"* ]]; then
  pass "a corpus where every survivor fails to parse exits 2, never a clean null_reading=1 parsed=0"
else
  fail "unreadable corpus read as empty — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 20. a blank line is not a dropped record, and an unread file is counted ---
# `grep -c .` counted NON-EMPTY lines; the first fix counted every line, so each
# blank line became a fabricated drop — and `dropped=0` is the integrity signal
# ADR-229 quotes this reading with.
R=$(new_root c20); assert_fixture_dir "$R"
fx_post_basic "$R/sess-c20/sess.jsonl"
printf '\n\n\n' >> "$R/sess-c20/sess.jsonl"
run "$R"
if [[ "$RC" -eq 0 && "$(summary_of)" == *"parsed=8 dropped=0 unread=0"* ]]; then
  pass "three trailing blank lines are not drops (parsed=8 dropped=0 unread=0)"
else
  fail "blank lines counted as drops — rc=$RC out='$OUT' err='$ERR'"
fi

# --- 21. an UNREADABLE survivor is counted, never silently better -------------
# A survivor jq cannot open contributes to NEITHER parsed nor dropped, so before
# `unread=` the integrity number IMPROVED when a file became unreadable. Skipped
# as root, where chmod 000 is not a barrier and the case would be vacuous.
if [[ $(id -u) -ne 0 ]]; then
  R=$(new_root c21); assert_fixture_dir "$R"
  fx_post_basic "$R/sess-c21/sess.jsonl"
  cp "$R/sess-c21/sess.jsonl" "$R/sess-c21/locked.jsonl"
  chmod 000 "$R/sess-c21/locked.jsonl"
  run "$R"
  chmod 644 "$R/sess-c21/locked.jsonl" 2>/dev/null || true
  if [[ "$RC" -eq 0 && "$(summary_of)" == *"files=2 "* && "$(summary_of)" == *"unread=1"* && "$(summary_of)" == *"runs=1 "* ]]; then
    pass "an unreadable survivor is reported as unread=1 (files=2), not silently absent from every counter"
  else
    fail "unreadable survivor invisible — rc=$RC out='$OUT' err='$ERR'"
  fi

  # And when EVERY survivor is unreadable, that is an unreadable corpus, not an
  # absence of plan runs: parsed+dropped are both 0, so the read-but-parsed-zero
  # guard above cannot see it.
  R=$(new_root c21b); assert_fixture_dir "$R"
  fx_post_basic "$R/sess-c21b/sess.jsonl"
  chmod 000 "$R/sess-c21b/sess.jsonl"
  run "$R"
  chmod 644 "$R/sess-c21b/sess.jsonl" 2>/dev/null || true
  if [[ "$RC" -eq 2 && "$ERR" == *"unreadable by the parser"* ]]; then
    pass "every survivor unreadable exits 2, never a clean null reading"
  else
    fail "all-unread corpus read as empty — rc=$RC out='$OUT' err='$ERR'"
  fi
fi

# SELFTEST_PASSES is a LITERAL here, not the variable bound after the self-test:
# guard-vacuity-floor.test.sh slices the floor plus its CONTIGUOUS assignments into
# a mutant, and a binding far above is unbound there. The self-test above asserts
# passes == 1, so the literal is proven, not chosen.
SELFTEST_PASSES=1
REAL_PASSES=$((passes - SELFTEST_PASSES))
MIN_CASES=25
if [[ "$fails" -eq 0 && "$REAL_PASSES" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: anti-vacuity floor — %s real assertions passed, expected at least %s\n' \
    "$REAL_PASSES" "$MIN_CASES" >&2
  exit 1
fi

echo "$REAL_PASSES passed, $fails failed"
[[ "$fails" -eq 0 ]] || exit 1
