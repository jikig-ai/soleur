#!/usr/bin/env bash
# Guard suite for plugins/soleur/hooks/compaction-state.sh (#8323).
#
# WHY THE LEDGER AND NOT THE TRANSCRIPT. Phase 0 measured, twice, that at
# SessionStart:compact the just-fired compaction's compact_boundary record is
# NOT yet on disk (count read 0 with 1 present afterwards; then 1 with 2
# present). It also measured that PreCompact fires on no-op compactions -- 3
# fires produced 2 boundaries -- so counting PreCompact fires over-counts. The
# shipped mechanism is therefore pending-then-commit over a per-session ledger
# under TMPDIR, and THAT is what these scenarios drive: event SEQUENCES, not
# transcript fixtures. See the plan's Phase 0 addendum.
#
# BOTH DIRECTIONS, DELIBERATELY. Every recommend=true row is paired with a
# recommend=false row that differs in exactly one field (trigger, count, or an
# intervening window reset). A suite whose rows all assert must-RECOMMEND
# cannot see the rule becoming too aggressive, and over-firing is precisely the
# failure this feature exists to avoid -- a spurious "abandon your session".
#
# The transcript fixtures survive for ONE property: prior_boundaries, the
# corroboration marker. A format rename degrades that marker and nothing else,
# which is why FR7's canary -- not this suite -- is the drift detector.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/hooks/compaction-state.sh"
FIX="$DIR/fixtures/compaction"

# test-helpers.sh owns assert_fixture_dir -- the guard the fixture scanners
# (fixture-relative-assert, fixture-dir-operand-assert) recognize. It sets
# -euo pipefail, so the +e below restores this suite's accumulate-then-exit
# contract.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required by this suite" >&2; exit 2; }

SANDBOX="$(mktemp -d -t compstate.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

# Ledger isolation. The hook keys its ledger off TMPDIR, so pointing TMPDIR at
# the sandbox is what keeps this suite from reading -- or writing -- the
# operator's live session ledger, and from colliding with a sibling worktree.
export TMPDIR="$SANDBOX/tmp"
mkdir -p "$TMPDIR" || { echo "FATAL: could not create sandbox TMPDIR" >&2; exit 2; }

# Pin the version string so no scenario spawns `claude --version`. The override
# is a documented seam, not test-only plumbing: an operator pinning a version
# for drift attribution uses the same variable.
export SOLEUR_COMPACTION_CLI_VERSION="test-cli-0.0.0"

# Written by the SUT on entry, before any guard. It certifies the subject
# actually ran: a harness that increments its own counters and skips the spawn
# produces none of these.
export SOLEUR_HOOK_TRACE="$SANDBOX/sut-invocations"
: > "$SOLEUR_HOOK_TRACE"

passes=0
fails=0
CASES=0
FAILURES=()   # append-only: the verdict reads THIS, so a redirected counter
              # increment cannot silence a failure.

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  FAILURES+=("$1")
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

# --- INSTRUMENT SELF-TEST -----------------------------------------------
# Drives both arms once and refuses to continue unless both counters AND the
# failure ledger moved. Reported with printf + exit, never through the helpers
# it backstops (ADR-193) -- a gutted fail() cannot report its own gutting.
_p0=$passes; _f0=$fails; _l0=${#FAILURES[@]}
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm)" >/dev/null
if (( passes != _p0 + 1 )) || (( fails != _f0 + 1 )) || (( ${#FAILURES[@]} != _l0 + 1 )); then
  printf 'FATAL: instrument self-test did not move all three (pass %d->%d, fail %d->%d, ledger %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" "$_l0" "${#FAILURES[@]}" >&2
  exit 2
fi
passes=$_p0; fails=$_f0; FAILURES=()

# --- harness ------------------------------------------------------------
OUT=""; ERR=""; RC=0
run_hook() { # <envelope-json> [env assignments...]
  local envelope="$1"; shift
  local ef; ef="$(mktemp -t csh-err.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
  OUT="$(printf '%s' "$envelope" | env "$@" bash "$SUT" 2>"$ef")"
  RC=$?
  ERR="$(cat "$ef")"
  rm -f "$ef"
}

# Envelope shapes transcribed VERBATIM from the Phase 0 probe (CLI 2.1.273),
# including the fields the hook does not read -- a fixture that omits them
# cannot notice the hook growing a dependency on one.
ss_env() { # <source> <session_id> <cwd> [transcript_path]
  jq -nc --arg s "$1" --arg sid "$2" --arg cwd "$3" --arg tp "${4-}" \
    '{cwd:$cwd,hook_event_name:"SessionStart",model:"claude-opus-5",
      prompt_id:"prompt-0001",session_id:$sid,source:$s,transcript_path:$tp}'
}
pc_env() { # <trigger> <session_id> <cwd> [transcript_path]
  jq -nc --arg t "$1" --arg sid "$2" --arg cwd "$3" --arg tp "${4-}" \
    '{custom_instructions:"",cwd:$cwd,hook_event_name:"PreCompact",
      prompt_id:"prompt-0001",session_id:$sid,transcript_path:$tp,trigger:$t}'
}

assert() { # <name> <condition> [detail]
  CASES=$((CASES + 1))
  if eval "$2"; then pass "$1"; else fail "$1" "${3:-$2}"; fi
}

# Field extraction goes through a FILE, never `... | grep -q`: under pipefail a
# grep that closes the pipe early takes the producer down with SIGPIPE (141)
# and a negative assertion then passes open.
ctx() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
has_ctx() { # <extended-regex>
  local c; c="$(ctx)"
  local n; n="$(printf '%s' "$c" | grep -cE -- "$1" 2>/dev/null || true)"
  [[ "${n:-0}" -gt 0 ]]
}

# A window is one full lifecycle: the SessionStart that opens it, then N
# compactions, each of which is a PreCompact followed by a SessionStart:compact.
compact_cycle() { # <trigger> <session_id> <cwd>
  run_hook "$(pc_env "$1" "$2" "$3")"
  run_hook "$(ss_env compact "$2" "$3")"
}

# --- roots --------------------------------------------------------------
# IN scope: this repo -- plugins/soleur present AND a Soleur plan/spec artifact.
IN_ROOT="$REPO_ROOT"
# OUT of scope, half A: a stranger's repo with neither.
STRANGER="$SANDBOX/stranger"; mkdir -p "$STRANGER/src"
# OUT of scope, half B: plugins/soleur present but NO Soleur artifact. This row
# is what makes the guard's second conjunct load-bearing -- without it, a
# directory check alone would pass here.
HALF="$SANDBOX/half"; mkdir -p "$HALF/plugins/soleur"

echo "== scenario 1: SessionStart:compact with an empty ledger =="
sid=s1
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$FIX/no-boundary.jsonl")"
assert "1a rc is 0" '[[ "$RC" -eq 0 ]]'
assert "1b stdout parses as JSON in full" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
assert "1c no directive" '! has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'
assert "1d names the reason" 'has_ctx "SOLEUR_COMPACTION_SKIPPED.*reason=no-ledger-entry"'

echo "== scenario 2: one auto compaction -> recommend=false =="
sid=s2
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
assert "2a directive present" 'has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'
assert "2b count_auto=1" 'has_ctx "count_auto=1( |$)"'
assert "2c recommend=false" 'has_ctx "recommend=false"'
assert "2d no fresh-session prose" '! has_ctx "fresh session"'
assert "2e trigger=auto" 'has_ctx "trigger=auto"'

echo "== scenario 3: two auto compactions -> recommend=true =="
sid=s3
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
assert "3a first still recommend=false" 'has_ctx "recommend=false"'
compact_cycle auto "$sid" "$IN_ROOT"
assert "3b count_auto=2" 'has_ctx "count_auto=2( |$)"'
assert "3c recommend=true" 'has_ctx "recommend=true"'
assert "3d carries the fresh-session prose" 'has_ctx "fresh session"'
assert "3e defers to the next phase boundary" 'has_ctx "next phase boundary"'
assert "3f tells one-shot not to pause" 'has_ctx "one-shot"'

echo "== scenario 4: manual compactions never recommend =="
sid=s4
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle manual "$sid" "$IN_ROOT"
compact_cycle manual "$sid" "$IN_ROOT"
compact_cycle manual "$sid" "$IN_ROOT"
assert "4a count_auto=0 after 3 manual" 'has_ctx "count_auto=0( |$)"'
assert "4b count_total=3" 'has_ctx "count_total=3( |$)"'
assert "4c recommend=false" 'has_ctx "recommend=false"'
assert "4d directive still emitted" 'has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'

echo "== scenario 5: mixed manual+auto counts only auto toward the rule =="
# Separates count_total from count_auto. Without this row, an implementation
# that counted every boundary would pass scenarios 3 and 4 both.
sid=s5
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle manual "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
assert "5a count_total=2" 'has_ctx "count_total=2( |$)"'
assert "5b count_auto=1" 'has_ctx "count_auto=1( |$)"'
assert "5c recommend=false" 'has_ctx "recommend=false"'

echo "== scenario 6: threshold override =="
sid=s6
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")" SOLEUR_COMPACTION_COUNT_THRESHOLD=1 \
  "TMPDIR=$TMPDIR" "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION" \
  "SOLEUR_HOOK_TRACE=$SOLEUR_HOOK_TRACE" "PATH=$PATH" "HOME=$HOME"
assert "6a threshold=1 makes one auto sufficient" 'has_ctx "recommend=true"'
# The far side: the SAME ledger state with the default threshold must NOT
# recommend. A one-sided override row cannot tell an honoured override from an
# implementation that always recommends.
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "6b default threshold on the same ledger does not recommend" '! has_ctx "recommend=true"'

echo "== scenario 7 (TR2/AC11): a window reset rescopes the count =="
sid=s7
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
assert "7a three autos in one window recommend" 'has_ctx "recommend=true"'
run_hook "$(ss_env resume "$sid" "$IN_ROOT")"
assert "7b the reset arm emits nothing on stdout" '[[ -z "$OUT" ]]'
assert "7c the reset arm exits 0" '[[ "$RC" -eq 0 ]]'
compact_cycle auto "$sid" "$IN_ROOT"
assert "7d count_auto is 1, not 4" 'has_ctx "count_auto=1( |$)"'
assert "7e recommend=false after the reset" 'has_ctx "recommend=false"'
# `clear` and `startup` reset too -- resume alone would leave two of the three
# window-opening sources unguarded.
sid=s7b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"; compact_cycle auto "$sid" "$IN_ROOT"
run_hook "$(ss_env clear "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
assert "7f clear resets the window too" 'has_ctx "count_auto=1( |$)"'

echo "== scenario 8 (AC22): a no-op PreCompact contributes nothing =="
# MEASURED, not imagined: 3 PreCompact fires produced 2 boundaries, because a
# /compact with nothing left to compact fires PreCompact and then no
# SessionStart:compact. An append-per-PreCompact ledger reads 2 here and fires
# the recommendation one compaction early.
sid=s8
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"   # no-op: no SessionStart:compact follows
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"   # the real one
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "8a two PreCompact fires, one compaction -> count_auto=1" 'has_ctx "count_auto=1( |$)"'
assert "8b and does not recommend" 'has_ctx "recommend=false"'

echo "== scenario 9: fail-open rc and a valid envelope on every path =="
sid=s9
run_hook 'not json at all'
assert "9a malformed stdin: rc 0" '[[ "$RC" -eq 0 ]]'
run_hook "$(jq -nc '{hook_event_name:"SessionStart",source:"compact",session_id:"s9b",cwd:"'"$IN_ROOT"'"}')"
assert "9b absent transcript_path: rc 0" '[[ "$RC" -eq 0 ]]'
assert "9c absent transcript_path: still valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
run_hook "$(ss_env compact s9c "$IN_ROOT" "$SANDBOX/does-not-exist.jsonl")"
assert "9d unreadable transcript: rc 0" '[[ "$RC" -eq 0 ]]'
assert "9e unreadable transcript: still valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
run_hook "$(ss_env compact s9d "$IN_ROOT" "$FIX/one-auto.jsonl")" \
  SOLEUR_DISABLE_COMPACTION_HOOKS=1 "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME"
assert "9f kill-switch: rc 0" '[[ "$RC" -eq 0 ]]'
assert "9g kill-switch: silent" '[[ -z "$OUT" ]]'
run_hook "$(pc_env auto s9e "$IN_ROOT")" SOLEUR_DISABLE_COMPACTION_HOOKS=1 \
  "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME"
assert "9h kill-switch silences PreCompact too" '[[ -z "$OUT" && "$RC" -eq 0 ]]'
run_hook "$(jq -nc '{hook_event_name:"SomeFutureEvent",cwd:"'"$IN_ROOT"'"}')"
assert "9i unknown event: rc 0, silent" '[[ "$RC" -eq 0 && -z "$OUT" ]]'
run_hook '{}'
assert "9j empty object: rc 0" '[[ "$RC" -eq 0 ]]'
run_hook ''
assert "9k empty stdin: rc 0" '[[ "$RC" -eq 0 ]]'

echo "== scenario 10: the set -u case the EXIT trap exists for =="
# `set -u` terminates the shell with status 1 WITHOUT firing ERR, so a trap on
# ERR alone leaves the fail-open contract broken on exactly this fault. Driven
# by injecting an unbound-variable reference through the documented seam.
run_hook "$(ss_env compact s10 "$IN_ROOT")" "SOLEUR_COMPACTION_SELFTEST_UNBOUND=1" \
  "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME"
assert "10a unbound-variable fault still exits 0" '[[ "$RC" -eq 0 ]]'

echo "== scenario 11 (AC10/TR1): the scope guard =="
run_hook "$(ss_env compact s11 "$STRANGER")"
assert "11a stranger repo, SessionStart: silent" '[[ -z "$OUT" ]]'
assert "11b stranger repo, SessionStart: rc 0" '[[ "$RC" -eq 0 ]]'
run_hook "$(pc_env auto s11 "$STRANGER")"
assert "11c stranger repo, PreCompact: silent" '[[ -z "$OUT" ]]'
assert "11d stranger repo, PreCompact: rc 0" '[[ "$RC" -eq 0 ]]'
run_hook "$(pc_env auto s11b "$HALF")"
assert "11e plugins/soleur without a Soleur artifact: silent" '[[ -z "$OUT" ]]'
run_hook "$(ss_env compact s11b "$HALF")"
assert "11f same, SessionStart: silent" '[[ -z "$OUT" ]]'
# The guard must not write a ledger for an out-of-scope root either -- a hook
# that stays quiet while still recording state is a hook that leaks.
assert "11g no ledger written for an out-of-scope session" \
  '[[ -z "$(find "$TMPDIR" -name "*s11*" -print -quit 2>/dev/null)" ]]'

echo "== scenario 12 (AC12/FR3): PreCompact stdout =="
run_hook "$(pc_env auto s12 "$IN_ROOT")"
assert "12a rc 0" '[[ "$RC" -eq 0 ]]'
assert "12b non-empty" '[[ -n "$OUT" ]]'
# Written so a JSON emission FAILS the case rather than aborting the suite.
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
  CASES=$((CASES + 1)); fail "12c PreCompact must not emit JSON" "got: ${OUT:0:120}"
else
  CASES=$((CASES + 1)); pass "12c PreCompact emits non-JSON"
fi
# Tokens are anchored, not bare: a bare "PR" matches the word "preserve" in
# this very block and the row would pass on the instruction text alone
# (cq-assert-anchor-not-bare-token).
for tok in "branch" "worktree" "PR #" "issue #" "plan path" "acceptance criteria" "Operator Holds"; do
  n="$(grep -ciF -- "$tok" <<<"$OUT" 2>/dev/null || true)"
  assert "12d names '$tok'" '[[ "${n:-0}" -gt 0 ]]'
done
# Herestring, never a pipe: `... | grep -q` under pipefail takes the producer
# down with SIGPIPE on an early match, and a negated assertion then passes open.
n12e="$(grep -ciE "file (contents|bodies)" <<<"$OUT" 2>/dev/null || true)"
assert "12e never asks the summarizer for file bodies" '[[ "${n12e:-0}" -eq 0 ]]'

echo "== scenario 13 (AC9): jq unavailable =="
NOJQ="$SANDBOX/nojq-bin"; mkdir -p "$NOJQ"
for t in grep git date cat mkdir rm find head tail tr cut wc sed awk timeout env bash; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOJQ/$t"
done
assert "13a the nojq PATH really has no jq" '! PATH="$NOJQ" command -v jq >/dev/null 2>&1'
assert "13b the nojq PATH really does have grep" 'PATH="$NOJQ" command -v grep >/dev/null 2>&1'
run_hook "$(ss_env compact s13 "$IN_ROOT")" "PATH=$NOJQ" "TMPDIR=$TMPDIR" "HOME=$HOME"
assert "13c rc 0 without jq" '[[ "$RC" -eq 0 ]]'
assert "13d stdout is still valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
assert "13e and names the reason" 'has_ctx "reason=jq-unavailable"'

echo "== scenario 14 (AC8): stdout purity and the 8k cap =="
sid=s14
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
assert "14a stdout parses as JSON in full" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
assert "14b additionalContext within 8000 chars" '[[ "$(ctx | wc -c)" -le 8000 ]]'
assert "14c envelope names the event" \
  '[[ "$(printf "%s" "$OUT" | jq -r ".hookSpecificOutput.hookEventName")" == "SessionStart" ]]'
assert "14d carries the CLI version for drift attribution" 'has_ctx "cli=test-cli-0.0.0"'
assert "14e orders a re-read before editing" 'has_ctx "re-read"'
assert "14f cites the rule that mandates it" 'has_ctx "hr-always-read-a-file-before-editing-it"'
assert "14g names the branch" 'has_ctx "feat-compaction-aware-session-hooks"'

echo "== scenario 15 (AC14): the boundary grep tolerates CLI spacing =="
# The transcript read feeds prior_boundaries ONLY. Pinning it here is what keeps
# FR7's canary attached to a string the shipped hook actually greps.
sid=s15
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$FIX/spaced-boundary.jsonl")"
assert "15a spaced '\"subtype\": \"compact_boundary\"' still counted" 'has_ctx "prior_boundaries=1"'
sid=s15b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$FIX/two-auto.jsonl")"
assert "15b compact spelling counted" 'has_ctx "prior_boundaries=2"'
sid=s15c
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$FIX/no-boundary.jsonl")"
assert "15c zero boundaries reported as 0, not as an error" 'has_ctx "prior_boundaries=0"'

echo "== scenario 16 (AC13): hooks.json bindings =="
HJ="$REPO_ROOT/plugins/soleur/hooks/hooks.json"
assert "16a hooks.json is valid JSON" 'jq -e . "$HJ" >/dev/null 2>&1'
assert "16b binds PreCompact with matcher manual|auto" \
  '[[ "$(jq -r "[.hooks.PreCompact[]? | select(.hooks[]?.command | test(\"compaction-state\")) | .matcher] | join(\",\")" "$HJ")" == "manual|auto" ]]'
assert "16c binds SessionStart with matcher startup|resume|clear|compact" \
  '[[ "$(jq -r "[.hooks.SessionStart[]? | select(.hooks[]?.command | test(\"compaction-state\")) | .matcher] | join(\",\")" "$HJ")" == "startup|resume|clear|compact" ]]'
assert "16d exactly two bindings reference the hook" \
  '[[ "$(jq "[.hooks[]?[]? | .hooks[]? | select(.command | test(\"compaction-state\"))] | length" "$HJ")" -eq 2 ]]'
assert "16e no PostCompact key (deferred to #8328)" '[[ "$(jq -r "has(\"PostCompact\") or (.hooks | has(\"PostCompact\"))" "$HJ")" == "false" ]]'
assert "16f the script is executable" '[[ -x "$SUT" ]]'
assert "16g bindings resolve via CLAUDE_PLUGIN_ROOT" \
  '[[ "$(jq -r "[.hooks[]?[]? | .hooks[]? | .command | select(test(\"compaction-state\")) | select(test(\"CLAUDE_PLUGIN_ROOT\"))] | length" "$HJ")" -eq 2 ]]'

echo "== scenario 17: the directive never echoes transcript prose =="
# NG5 / the elevated-authority constraint: the hook must emit pointers, never
# content it read out of the transcript.
sid=s17
PROSE="$SANDBOX/prose.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"CANARY-SECRET-STRING-DO-NOT-ECHO"}}' > "$PROSE"
printf '%s\n' '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":9,"postTokens":1},"content":"CANARY-BOUNDARY-CONTENT"}' >> "$PROSE"
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$PROSE")"
assert "17a no user prose in the directive" '! has_ctx "CANARY-SECRET-STRING"'
assert "17b no boundary content in the directive" '! has_ctx "CANARY-BOUNDARY-CONTENT"'
assert "17c but the boundary was still counted" 'has_ctx "prior_boundaries=1"'

echo "== scenario 19: a MANUAL compaction never satisfies the rule =="
# The row that makes the rule's trigger operand load-bearing. Scenario 4
# (manual-only) cannot: with count_auto already 0 there, deleting the
# `trigger == auto` conjunct changes nothing and the mutation survives --
# measured. The discriminating state is count_auto ALREADY OVER THRESHOLD with
# the CURRENT compaction manual, which is reachable in practice the moment an
# operator types /compact on a session that has auto-compacted twice.
sid=s19
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
assert "19a two autos recommend" 'has_ctx "recommend=true"'
compact_cycle manual "$sid" "$IN_ROOT"
assert "19b count_auto is still 2" 'has_ctx "count_auto=2( |$)"'
assert "19c but a manual current compaction does not recommend" 'has_ctx "recommend=false"'
assert "19d and carries no fresh-session prose" '! has_ctx "fresh session"'
# Same shape with an unrecognized trigger -- "not auto" must mean not auto,
# rather than "manual specifically".
sid=s19b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
run_hook "$(jq -nc --arg cwd "$IN_ROOT" '{cwd:$cwd,hook_event_name:"PreCompact",session_id:"s19b",transcript_path:""}')"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "19e a PreCompact with no trigger field does not recommend" 'has_ctx "recommend=false"'
assert "19f and reports the trigger as unknown" 'has_ctx "trigger=unknown"'

echo "== scenario 18: sessions do not contaminate each other =="
run_hook "$(ss_env startup s18a "$IN_ROOT")"
run_hook "$(ss_env startup s18b "$IN_ROOT")"
compact_cycle auto s18a "$IN_ROOT"
compact_cycle auto s18a "$IN_ROOT"
assert "18a session A recommends after two autos" 'has_ctx "recommend=true"'
compact_cycle auto s18b "$IN_ROOT"
assert "18b session B is unaffected" 'has_ctx "count_auto=1( |$)"'

echo "== scenario 20: a degenerate TMPDIR is refused, not written through =="
# assert_fixture_dir is present for the P1b ratchet; this drives it, so the
# guard is not merely present but falsifiable. TMPDIR is caller-supplied, so a
# relative value would scatter ledger files under whatever cwd the hook
# inherits.
run_hook "$(pc_env auto s20 "$IN_ROOT")" "TMPDIR=relative/not/absolute" \
  "PATH=$PATH" "HOME=$HOME" "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "20a relative TMPDIR: rc 0 (fail-open)" '[[ "$RC" -eq 0 ]]'
assert "20b relative TMPDIR: no summary-shaping output" '[[ -z "$OUT" ]]'
assert "20c relative TMPDIR: says why on stderr" \
  '[[ "$(grep -cF "RELATIVE" <<<"$ERR" 2>/dev/null || true)" -gt 0 ]]'
assert "20d nothing written under the relative path" '[[ ! -d "$REPO_ROOT/relative" ]]'
run_hook "$(ss_env compact s20 "$IN_ROOT")" "TMPDIR=/proc/self/soleur" \
  "PATH=$PATH" "HOME=$HOME" "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "20e synthetic-fs TMPDIR: rc 0 and silent" '[[ "$RC" -eq 0 && -z "$OUT" ]]'

# --- coverage floors ----------------------------------------------------
# Reported with printf + exit, NOT through fail() -- the helper these floors
# exist to backstop is the one an edit disarms.
MIN_CASES=100
if (( CASES < MIN_CASES )); then
  printf 'FATAL: assertion floor breached -- ran %d cases, floor is %d. Cases were deleted, or the suite aborted early.\n' \
    "$CASES" "$MIN_CASES" >&2
  exit 1
fi
SUT_RUNS="$(grep -c '^ran$' "$SOLEUR_HOOK_TRACE" 2>/dev/null || true)"
MIN_SUT_RUNS=101
if (( ${SUT_RUNS:-0} < MIN_SUT_RUNS )); then
  printf 'FATAL: the subject ran %s times, floor is %d. The harness asserted without spawning the hook.\n' \
    "${SUT_RUNS:-0}" "$MIN_SUT_RUNS" >&2
  exit 1
fi

printf '\n%d passed, %d failed (%d cases, %s subject invocations)\n' \
  "$passes" "$fails" "$CASES" "${SUT_RUNS:-0}"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
