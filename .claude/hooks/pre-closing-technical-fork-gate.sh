#!/usr/bin/env bash
# Stop hook: stop a turn whose CLOSING message asks the operator to choose on a TECHNICAL fork, once.
#
# WHY. `hr-technical-fork-is-not-an-operator-question` had three enforcers and each reads a different
# carrier: pre-ask-technical-fork-gate.sh reads AskUserQuestion tool calls, ship's Technical-Ruling Gate
# reads a `## Decision Classes` table, and one-shot runs that gate once after the plan phase. On
# 2026-10-12 the carrier was none of them: interrogative sentences in the END-OF-TURN PROSE ("Decision
# for you: 1. 2. 3." / "Your calls: ..."). The founder corrected it: "you should ask the CTO, not me".
# An enforcer that cannot read a carrier does not enforce it; this hook reads that carrier.
#
# ON A WRONGFUL BLOCK: the procedure lives in the header of lib/technical-fork-cues.sh (find the closing by the ledger
# row's sha256, which hashes the NORMALISED unit: lowercased, fences, quotes and code spans stripped, invisible
# characters removed, whitespace squeezed; narrow the cue in the lib; add a must-PASS fixture).
#
# WHAT THIS IS NOT. It is ONE forced reconsideration per turn, not a guarantee: a repeat of the same
# question after the block runs with `stop_hook_active == true` and passes. It is cue-based, so a
# phrasing outside the vocabulary passes (recall decay: the remedy is the miss, cue, fixture loop, never
# preemptive widening). And it is mostly inert INSIDE a ralph loop: plugins/soleur/hooks/stop-hook.sh
# blocks every Stop while a loop (soleur:one-shot) is active and never reads `stop_hook_active`, so only the
# FIRST Stop of a chain is judged (it carries false; ralph and this hook may both block it, and the model then
# sees two reasons, which is benign: the next Stop carries true for both). Every later Stop in the chain,
# including the one-shot Step 8 closing, carries true and exits at arm 4, so mid-pipeline closing messages
# are not judged; the pointer line in the one-shot skill is signage there, not hook-backed.
#
# FAIL OPEN, AND WHY (ADR-157 "What this supersedes": absorbing a failure is correct for a Stop hook; a
# Stop hook cannot ask). A wrongly blocked closing message is the worse failure, so every parse doubt
# exits 0 with ONE stderr line naming the arm: jq missing, empty or non-JSON stdin, an absent
# `stop_hook_active` key (the loop guard cannot be verified, which matters under Devin where the Stop
# payload is unmeasured), a non-string message, a lib that fails its self-check (an EMPTY cue regex
# matches every line), an unterminated fence. It never sources lib/hook-input.sh (PreToolUse-shaped).
#
# ESCAPES (each needs non-empty content). `<stop>OPERATOR-GATE: ...</stop>` or `<stop>BLOCKED: ...</stop>`
# anywhere in the window, and a final-sentence plain `Paused:` / `Blocked:` label (shared with
# unkept-promise-hook.sh, so one appended label disarms both gates), pass the whole closing.
# `Operator-only (category): ...` governs ONLY its own sentence and the next `?` unit in the same paragraph,
# so one appended self-label cannot pass three unrelated technical questions. The block reason teaches the
# plain forms only: it carries no angle-bracket text (the model echoes markup it is taught).
#
# Trace marker: SOLEUR_HOOK_TRACE makes the hook write one line to STDERR at entry so a suite can count
# real executions (a path operand would trip the relative-path guard). stdout is reserved for the protocol.
set -uo pipefail
[ -n "${SOLEUR_HOOK_TRACE:-}" ] && printf 'SOLEUR_HOOK_RAN\n' >&2
export LC_ALL=C

_NAME="pre-closing-technical-fork-gate"
_note() { printf '%s: %s\n' "$_NAME" "$1" >&2; }

command -v jq >/dev/null 2>&1 || { _note "SKIPPED — jq unavailable, closing message NOT scanned"; exit 0; }

if [[ "${SOLEUR_ACK_TECHNICAL_FORK:-}" == "1" ]]; then
  jq -n '{systemMessage:"pre-closing-technical-fork-gate: disarmed by SOLEUR_ACK_TECHNICAL_FORK=1"}' 2>/dev/null
  exit 0
fi
# Headless CI has no operator to ask; a block there only burns a turn.
[[ "${GITHUB_ACTIONS:-}" == "true" ]] && exit 0

# --- parse: every doubt fails OPEN -----------------------------------------------------------------
INPUT="$(head -c 8000000)" || { _note "SKIPPED — stdin unreadable"; exit 0; }
[[ -n "$INPUT" ]] || { _note "SKIPPED — empty stdin"; exit 0; }
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$INPUT" || { _note "SKIPPED — input is not a JSON object"; exit 0; }
jq -e 'has("stop_hook_active")' >/dev/null 2>&1 <<<"$INPUT" \
  || { _note "SKIPPED — stop_hook_active absent, the once-per-turn guard cannot be verified"; exit 0; }
ACTIVE="$(jq -r '.stop_hook_active | if type == "boolean" then tostring else "other" end' 2>/dev/null <<<"$INPUT")" \
  || { _note "SKIPPED — stop_hook_active unreadable"; exit 0; }
[[ "$ACTIVE" == "false" ]] || { [[ "$ACTIVE" == "true" ]] || _note "SKIPPED — stop_hook_active is not a boolean"; exit 0; }
jq -e '(.last_assistant_message | type) == "string"' >/dev/null 2>&1 <<<"$INPUT" \
  || { _note "SKIPPED — last_assistant_message absent or not a string"; exit 0; }
MSG="$(jq -r '.last_assistant_message' 2>/dev/null <<<"$INPUT")" || { _note "SKIPPED — message unreadable"; exit 0; }
[[ -n "$MSG" ]] || exit 0
# Cheap pre-filter (performance seat): only a `?`-terminated unit can ever hit, and stripping can only REMOVE a `?`,
# so a raw message without one cannot change a verdict; this skips ~14 of ~20 forks on the common turn end.
# CL4 (2026-10-19) judges declarative hand-offs, so a message carrying one of its phrases is also scanned.
if [[ "$MSG" != *"?"* ]]; then
  grep -qiE 'your call|up to you|(tell|ask) me to|say the word|let me know|want me to|like me to|prefer me to|(you|owner) (decide|choose|pick)' <<<"$MSG" || exit 0
fi

# One path variable, one place to edit when the pair graduates to the plugin.
TFC_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/technical-fork-cues.sh"
if [[ -s "$TFC_LIB" ]]; then
  # shellcheck source=lib/technical-fork-cues.sh
  source "$TFC_LIB" >/dev/null 2>&1
fi
tfc_self_check 2>/dev/null || { _note "SKIPPED — cue lib missing or incomplete ($TFC_LIB)"; exit 0; }

# --- the window: tail -> fence parity -> strip fences, quotes, spans -> normalise -> 1500 bytes ------
TAIL="$(printf '%s' "$MSG" | tail -c 200000)"
FENCES="$(printf '%s' "$TAIL" | awk '/^[[:space:]]*```/ { c++ } END { print c + 0 }')" || { _note "SKIPPED — fence count failed"; exit 0; }
if (( FENCES % 2 != 0 )); then _note "SKIPPED — unterminated fenced block, window unreliable"; exit 0; fi
# Fenced blocks go FIRST (a byte cut inside a fence would flip the toggle and drop the real closing), then
# `>` quoted lines and inline code spans PER LINE: sessions in this repo quote these very phrases while
# editing the hook, and stripping can only make the hook block less.
PROSE="$(printf '%s\n' "$TAIL" | awk '
  /^[[:space:]]*```/ { f = !f; next }
  f { next }
  /^[[:space:]]*>/ { next }
  { gsub(/`[^`]*`/, ""); print }')" || { _note "SKIPPED — strip failed"; exit 0; }
# CR is dropped (a CRLF closing would otherwise leave `?` followed by a byte that is no boundary). The unicode
# spaces (NBSP, U+2000-200A, U+202F, U+205F, U+3000) become a space and the invisible characters (zero-width
# U+200B-U+200F, U+2060, U+FEFF, soft hyphen, U+180E) vanish, BEFORE any matching, so text the model can type
# but the cue cannot see does not defeat the cue. Stripping can only make the hook block MORE on a real cue.
NORM="$(printf '%s\n' "$PROSE" | tr -d '\r' \
  | sed -e 's/\xc2\xa0/ /g' -e 's/\xe2\x80[\x80-\x8a]/ /g' -e 's/\xe2\x80\xaf/ /g' -e 's/\xe2\x81\x9f/ /g' -e 's/\xe3\x80\x80/ /g' \
        -e 's/\xe2\x80[\x8b-\x8f]//g' -e 's/\xe2\x81\xa0//g' -e 's/\xef\xbb\xbf//g' -e 's/\xc2\xad//g' -e 's/\xe1\xa0\x8e//g' \
  | tr '\t' ' ' | tr '[:upper:]' '[:lower:]' | tr -s ' ')" || { _note "SKIPPED — normalise failed"; exit 0; }
CUT=0
(( ${#NORM} > 1500 )) && CUT=1
WIN="$(printf '%s' "$NORM" | tail -c 1500)"
[[ -n "${WIN//[[:space:]]/}" ]] || exit 0

# --- whole-window escapes ---------------------------------------------------------------------------
if grep -qE '<stop>(operator-gate|blocked):[[:space:]]*[^<[:space:]][^<]*</stop>' <<<"$WIN"; then exit 0; fi

# --- units: the `?`-terminated sentences, each with its own escape flag, plus the final sentence --------
# A `?` ends a unit only before whitespace, end of line or closing punctuation, so a URL query string is
# not a boundary. `esc` is set by a sentence-initial `Operator-only (category):` label and covers exactly
# one unit (its own sentence if that is a unit, else the next one) and never crosses a blank line.
# awk program text: no apostrophe may appear (single-quoted); \047 is used where one is needed.
UNITS="$(printf '%s\n' "$WIN" | awk -v cut="$CUT" '
  function isclose(c) { return (c == "" || c == " " || c == ")" || c == "]" || c == "\"" || c == "\047" || c == "*" || c == "_" || c == "`") }
  function islabel(s) { return (s ~ /^[ *_>-]*operator-only \((money|scope|priority|schedule|irreversible|production-mutating|legal-risk|brand)\): *[^ ]/) }
  function note_sentences(pre,   n, a, i) {
    n = split(pre, a, /[.!] /)
    for (i = 1; i <= n; i++) {
      if (islabel(a[i])) esc = 1
      else if (a[i] ~ /(your call|up to you|(tell|ask) me to|say the word|let me know|want me to|like me to|prefer me to|(you|owner) (decide|choose|pick))/) print "U" esc "\t" a[i]
    }
  }
  BEGIN { esc = 0; last_line = "" }
  {
    line = $0
    if (NR == 1 && cut == 1) {
      if (match(line, /[.!?]( |$)/)) line = substr(line, RSTART + RLENGTH); else line = ""
    }
    if (line ~ /^ *$/) { esc = 0; next }
    last_line = line
    rest = line
    while (rest != "") {
      q = 0
      for (i = 1; i <= length(rest); i++) {
        if (substr(rest, i, 1) == "?" && isclose(substr(rest, i + 1, 1))) { q = i; break }
      }
      if (q == 0) { note_sentences(rest); break }
      seg = substr(rest, 1, q); rest = substr(rest, q + 1)
      pre = ""; unit = seg; p = 0
      for (j = length(seg) - 1; j >= 1; j--) {
        c = substr(seg, j, 1)
        if ((c == "." || c == "!") && substr(seg, j + 1, 1) == " ") { p = j; break }
      }
      if (p > 0) { pre = substr(seg, 1, p); unit = substr(seg, p + 2) }
      note_sentences(pre)
      sub(/^ +/, "", unit)
      if (islabel(unit)) esc = 1
      print "U" esc "\t" unit
      esc = 0
    }
  }
  END {
    if (last_line != "") {
      n = split(last_line, a, /[.!?] /)
      s = a[n]; sub(/^[ *_>-]+/, "", s)
      print "F\t" s
    }
  }')" || { _note "SKIPPED — unit split failed"; exit 0; }

# Final-sentence `Paused:` / `Blocked:` label passes the whole closing (it mirrors the plugin hook). A label
# with no content, or only a no-op word ("Blocked: none."), is a status line and does not count.
TAB=$'\t'
FINAL="$(grep -E "^F${TAB}" <<<"$UNITS" | tail -n 1)"
if [[ -n "$FINAL" ]]; then
  FINAL_SENT="${FINAL#F"$TAB"}"
  # `**Paused**:` is the plugin hook's accepted bold form too, so strip emphasis markers before the match.
  FINAL_SENT="${FINAL_SENT//[*_]/}"
  if [[ "$FINAL_SENT" =~ ^(paused|blocked): ]]; then
    CONTENT="${FINAL_SENT#*:}"; CONTENT="${CONTENT//[[:punct:][:space:]]/}"
    if [[ -n "$CONTENT" ]] && ! [[ "$CONTENT" =~ ^(none|na|nothing|no|nil)$ ]]; then exit 0; fi
  fi
fi

# --- judge the last 12 units, each alone ------------------------------------------------------------
declare -a JUDGE=()
while IFS= read -r row; do
  [[ "$row" == "U0${TAB}"* ]] && JUDGE+=("${row#"U0${TAB}"}")
done <<<"$UNITS"
COUNT=${#JUDGE[@]}
START=0
if (( COUNT > 12 )); then START=$((COUNT - 12)); _note "NOTE — $COUNT question units, judging the last 12"; fi

HIT_UNIT=""; HIT_CUE=""
for (( k = START; k < COUNT; k++ )); do
  u="${JUDGE[$k]}"
  # No per-unit size cap (Ruled by CTO agent, 2026-10-12 review): the 1500-byte window already bounds a unit, the
  # regexes are linear (bounded gaps), and a cap would turn any long run-on question into an unjudged bypass.
  # The suite pins a worst-case 1500-byte unit under a time bound instead.
  tfc_is_fork "$u" shared+closing
  rc=$?
  if (( rc == 0 )); then HIT_UNIT="$u"; HIT_CUE="$TFC_HIT"; break; fi
  (( rc == 2 )) && { _note "SKIPPED — tfc_is_fork rejected its arguments"; exit 0; }
done
[[ -n "$HIT_UNIT" ]] || exit 0

# --- block: ONE JSON object, byte-constant text (never the unit, the cue or any model text) --------
REASON='STOPPED: your closing message asks the operator to choose on a TECHNICAL fork (whether evidence is enough, which design, or in what order). The operator is non-technical and cannot rule on it; the CTO agent can.

Do this now: spawn soleur:engineering:cto with the Agent tool (legal questions: soleur:legal:clo), hand it the evidence and the options, and tell it "do NOT use AskUserQuestion". Act on its ruling and record it as "Ruled by CTO agent". The procedure and the closed list of rulings that do NOT go to the CTO are in technical-ruling-delegation.md (plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md).

Then re-send your closing message with the ruling in it. Split the item: ask the operator only the authorization that remains, and only for a decision in this closed list: money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand. Say in one line why you re-sent (the CTO ruled, or the fork is operator-only), and restate only the delta plus the authorization: the operator has already read the first message.

Only if the fork is genuinely operator-only, classify it instead of asking the CTO: put Operator-only (money): or the matching category, then the reason, directly before the question it covers (same paragraph). A final sentence beginning Paused: or Blocked: followed by what you are waiting on also ends this check.

See hr-technical-fork-is-not-an-operator-question.'
SYSMSG='pre-closing-technical-fork-gate: stopped once because the closing message asked the operator to rule on a technical fork; the assistant was told to consult its CTO agent. If that was wrong, reply "send it anyway" (a repeat close always passes). The assistant can also release it with Operator-only (money): the reason, placed before the question. To disarm this check for a whole session, start the session with SOLEUR_ACK_TECHNICAL_FORK=1.'
jq -n --arg r "$REASON" --arg m "$SYSMSG" '{decision:"block", reason:$r, systemMessage:$m}'

# --- ledger row, AFTER the decision is printed (emit_incident takes an indefinite flock; if that flock hung until
# the registration's 10 s timeout the harness might discard the printed block, a fail-open loss, accepted: holds are brief) ---
# Cue name, unit length and sha256 only: CL3 vocabulary (credentials, tokens, keys) makes the units
# secret-adjacent, and the row only has to let a later reader find the unit by hash in a local transcript.
# One function, the only repo-local dependency, so graduation to the plugin rewrites exactly this.
_tfc_record() {
  local cue="$1" unit="$2" len sha
  len="${#unit}"
  sha="$(printf '%s' "$unit" | sha256sum 2>/dev/null | cut -d' ' -f1)"
  [[ -n "$sha" ]] || sha="nohash"
  umask 077
  if [[ -f "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" ]]; then
    # shellcheck source=lib/incidents.sh
    source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" >/dev/null 2>&1
  fi
  declare -f emit_incident >/dev/null 2>&1 \
    && emit_incident "$_NAME" deny "$cue" "len=${len} sha256=${sha}" Stop >/dev/null 2>&1 || true
}
_tfc_record "$HIT_CUE" "$HIT_UNIT"
exit 0
