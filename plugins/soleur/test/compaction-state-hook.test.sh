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
# THE HOOK DOES NOT READ THE TRANSCRIPT. An earlier revision greped it for a
# `prior_boundaries` corroboration marker; review deleted that (nothing consumed
# it, and the ledger resets per window while the transcript accumulates across
# --resume, so the two numbers diverge arbitrarily). The three remaining
# fixtures are kept only to drive scenario 17, which asserts that handing the
# hook a transcript changes nothing about its output.

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

echo "== scenario 17: the hook never dereferences transcript_path =="
# Formerly an assertion that no transcript prose reached the directive. Since
# review deleted the corroboration read, that property is STRUCTURAL rather than
# behavioural -- the hook never opens the file -- so a content assertion would be
# vacuous by construction. Pinned at the source instead, comment-stripped so the
# measured-payload-contract header (which necessarily names the field) cannot
# satisfy it.
_src_nc="$(grep -vE '^[[:space:]]*#' "$SUT")"
assert "17a no live read of transcript_path outside comments" \
  '[[ "$(grep -cF "transcript" <<<"$_src_nc" 2>/dev/null || true)" -eq 0 ]]'
# Control: the stripper must not simply be eating the whole file.
assert "17b (control) the stripped source is non-trivial" '[[ "$(wc -l <<<"$_src_nc")" -gt 100 ]]'
# And a transcript handed to the hook changes nothing about its output.
sid=s17
PROSE="$SANDBOX/prose.jsonl"
printf '%s\n' '{"type":"system","subtype":"compact_boundary","content":"CANARY-DO-NOT-ECHO"}' > "$PROSE"
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$PROSE")"
assert "17c a supplied transcript leaks nothing" '! has_ctx "CANARY-DO-NOT-ECHO"'
assert "17d and the directive is unaffected by it" 'has_ctx "count_auto=1( |$)"'

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

echo "== scenario 21: a branch with no matching plan still gets a directive =="
# The optional Plan:/Spec: lines are appended with `[[ -n "$X" ]] && CTX=...`.
# Bash exempts the LEFT operand of && from the ERR trap, so the failing test
# does not abort -- but that exemption is the only thing standing between a
# plan-less branch and a hook that exits silently, and nothing else asserts it.
# Measured by hand first, pinned here so a refactor to a plain `test && x` or a
# reordering cannot quietly reintroduce the silent-exit.
NOPLAN="$SANDBOX/noplan"
mkdir -p "$NOPLAN/plugins/soleur" "$NOPLAN/knowledge-base/project/plans"
run_hook "$(ss_env startup s21 "$NOPLAN")"
run_hook "$(pc_env auto s21 "$NOPLAN")"
run_hook "$(ss_env compact s21 "$NOPLAN")"
assert "21a directive still emitted with no plan file" 'has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'
assert "21b stdout is valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
assert "21c and no Plan: line is fabricated" '! has_ctx "^Plan: $"'

echo "== scenario 22 (review P1): the scope walk stops at the enclosing repo =="
# An unanchored walk is strictly wider than welcome-hook.sh, which resolves one
# GIT_ROOT and tests exactly one directory: a Soleur checkout at ~/dev makes the
# guard pass for every unrelated repo nested beneath it. That is not a
# hypothetical shape -- it is this repo's own .worktrees/ layout.
OUTER="$SANDBOX/outer"
mkdir -p "$OUTER/plugins/soleur" "$OUTER/knowledge-base/project/plans" "$OUTER/.git"
mkdir -p "$OUTER/nested-stranger/.git" "$OUTER/nested-stranger/src"
run_hook "$(ss_env startup s22 "$OUTER")"
run_hook "$(pc_env auto s22 "$OUTER")"
assert "22a the Soleur root itself is still in scope" '[[ -n "$OUT" ]]'
run_hook "$(pc_env auto s22b "$OUTER/nested-stranger/src")"
assert "22b a git repo nested under a Soleur checkout is OUT of scope" '[[ -z "$OUT" ]]'
assert "22c and exits 0" '[[ "$RC" -eq 0 ]]'
run_hook "$(ss_env compact s22b "$OUTER/nested-stranger/src")"
assert "22d same for SessionStart" '[[ -z "$OUT" ]]'
# A plain subdirectory of the Soleur root (no .git of its own) must STILL be in
# scope -- the anchor must not break the ordinary cwd-is-a-subdir case.
mkdir -p "$OUTER/plugins/soleur/skills"
run_hook "$(pc_env auto s22c "$OUTER/plugins/soleur/skills")"
assert "22e a plain subdir of the Soleur root stays in scope" '[[ -n "$OUT" ]]'

echo "== scenario 23 (review P1): an unusable ledger directory fails CLOSED =="
# With TMPDIR unset the ledger root is /tmp/soleur-compaction, world-reachable
# on a multi-user host. Degrading silently there lets a pre-seeded pending file
# reach the directive. Simulated by making the path unusable as a directory.
SQUAT="$SANDBOX/squat"; mkdir -p "$SQUAT"
: > "$SQUAT/soleur-compaction"          # a FILE where the hook wants a directory
run_hook "$(pc_env auto s23 "$IN_ROOT")" "TMPDIR=$SQUAT" "PATH=$PATH" "HOME=$HOME" \
  "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "23a rc 0 (fail-open for the feature)" '[[ "$RC" -eq 0 ]]'
assert "23b no summary-shaping output (fail-closed for the write)" '[[ -z "$OUT" ]]'
assert "23c names the reason on stderr" \
  '[[ "$(grep -cF "ledger-dir-unusable" <<<"$ERR" 2>/dev/null || true)" -gt 0 ]]'
assert "23d and wrote nothing" '[[ ! -d "$SQUAT/soleur-compaction" ]]'

echo "== scenario 24 (review P1): trigger is validated, not trusted =="
# AP-020: `trigger` both GATES the recommendation and is interpolated into text
# the model reads at elevated authority. Unvalidated, a multi-line value
# inflates the ledger's line count -- which IS count_total -- and can force
# recommend=true from a single compaction.
sid=s24
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(jq -nc --arg cwd "$IN_ROOT" --arg sid "$sid" \
  '{cwd:$cwd,hook_event_name:"PreCompact",session_id:$sid,transcript_path:"",
    trigger:"auto\nauto\nauto"}')"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "24a a multi-line trigger does not inflate count_total" 'has_ctx "count_total=1( |$)"'
assert "24b nor count_auto" 'has_ctx "count_auto=0( |$)"'
assert "24c and does not recommend" 'has_ctx "recommend=false"'
assert "24d renders as trigger=unknown" 'has_ctx "trigger=unknown"'
assert "24e no injected line reaches additionalContext" '! has_ctx "^auto$"'
# An unrecognized single-token trigger is equally not auto.
sid=s24b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env "AUTO" "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "24f trigger matching is exact, not case-folded" 'has_ctx "trigger=unknown"'

# --- coverage floors ----------------------------------------------------
# Reported with printf + exit, NOT through fail() -- the helper these floors
# exist to backstop is the one an edit disarms.
MIN_CASES=110
if (( CASES < MIN_CASES )); then
  printf 'FATAL: assertion floor breached -- ran %d cases, floor is %d. Cases were deleted, or the suite aborted early.\n' \
    "$CASES" "$MIN_CASES" >&2
  exit 1
fi
SUT_RUNS="$(grep -c '^ran$' "$SOLEUR_HOOK_TRACE" 2>/dev/null || true)"
MIN_SUT_RUNS=93
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
