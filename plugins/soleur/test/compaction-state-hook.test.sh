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
# --resume, so the two numbers diverge arbitrarily). The three transcript
# fixtures went with it -- they were dead, and a header claiming they drove
# scenario 17 was false: that scenario writes its own inline. Where a
# `transcript_path` value is still passed below it is a path-shaped string the
# hook is asserted NEVER to open (scenario 17).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/hooks/compaction-state.sh"

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
# The SUT branches on these; `env "$@"` adds and never clears, so an ambient
# value from the operator's shell silently rewrites the suite's meaning
# (measured: DISABLE=1 gives 52/58, THRESHOLD=1 gives 103/7 -- loud, but the
# survivors under the 52/58 arm are every `rc is 0` and every `-z "$OUT"` row).
unset SOLEUR_COMPACTION_COUNT_THRESHOLD SOLEUR_DISABLE_COMPACTION_HOOKS \
      SOLEUR_COMPACTION_SELFTEST_UNBOUND

export SOLEUR_HOOK_TRACE="$SANDBOX/sut-invocations"
: > "$SOLEUR_HOOK_TRACE"

passes=0
fails=0
CASES=0
FAILURES=()   # append-only: the verdict reads THIS, so a redirected counter
              # increment cannot silence a failure.

pass() { passes=$((passes + 1)); CASES=$((CASES + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  CASES=$((CASES + 1))
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
passes=$_p0; fails=$_f0; CASES=0; FAILURES=()

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

# CASES is incremented by pass()/fail(), NOT here: an increment inside assert()
# sits above the verdict, so gutting the verdict while keeping the increment
# leaves MIN_CASES reconciling exactly. Measured: `eval "$2" >/dev/null 2>&1;
# pass "$1"` reported 115 passed, 0 failed, ALL TESTS PASSED.
assert() { # <name> <condition> [detail]
  if eval "$2"; then pass "$1"; else fail "$1" "${3:-$2}"; fi
}

# assert() is the only layer that ADJUDICATES, and the pass()/fail() self-test
# above structurally cannot see it -- it drives those two helpers directly.
# Measured: `eval "$2" >/dev/null 2>&1; pass "$1"` reported 115 passed, 0 failed,
# ALL TESTS PASSED, with every row asserting nothing. Drive both arms.
_p1=$passes; _f1=$fails; _c1=$CASES
assert "instrument self-test (assert TRUE arm)"  'true'  >/dev/null
assert "instrument self-test (assert FALSE arm)" 'false' >/dev/null 2>&1
if (( passes != _p1 + 1 )) || (( fails != _f1 + 1 )) || (( CASES != _c1 + 2 )); then
  printf 'FATAL: assert() does not gate on its condition (pass %d->%d, fail %d->%d, cases %d->%d)\n' \
    "$_p1" "$passes" "$_f1" "$fails" "$_c1" "$CASES" >&2
  exit 2
fi
passes=$_p1; fails=$_f1; CASES=$_c1; FAILURES=()

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
# `plugins/soleur` present, NO Soleur artifact. Under the widened predicate this
# stays silent for a DIFFERENT reason than before (no artifact, rather than the
# old first conjunct), so the row survives with a new justification.
HALF="$SANDBOX/half"; mkdir -p "$HALF/plugins/soleur"
# THE MARKETPLACE INSTALL -- the row whose absence let the narrow guard ship.
# `claude plugin install` puts the plugin under ~/.claude/plugins, never in the
# user's repo, so every scope fixture built from the monorepo's shape missed the
# entire installed base. Artifact present, no plugins/soleur: MUST fire.
CUSTOMER="$SANDBOX/customer"; mkdir -p "$CUSTOMER/knowledge-base/project/plans" "$CUSTOMER/src"

# The extractor is load-bearing and was not unique: `ctx() { printf '%s' "$OUT"; }`
# (jq dropped) survived every row, so nothing pinned WHICH field carries the
# payload. Drive it against a known envelope before any scenario runs.
_probe='{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"CTXMARK"},"decoy":"CTXMARK-DECOY"}'
OUT="$_probe"
if [[ "$(ctx)" != "CTXMARK" ]]; then
  printf 'FATAL: ctx() does not extract additionalContext (got %q)\n' "$(ctx)" >&2
  exit 2
fi
OUT=""

echo "== scenario 1: SessionStart:compact with an empty ledger =="
sid=s1
run_hook "$(ss_env compact "$sid" "$IN_ROOT" "$SANDBOX/any-transcript.jsonl")"
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
run_hook "$(ss_env compact s9d "$IN_ROOT" "$SANDBOX/any-transcript.jsonl")" \
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

echo "== scenario 11b (CTO ruling 2): the marketplace install is IN scope =="
run_hook "$(pc_env auto s11m "$CUSTOMER")"
assert "11h a customer repo with only the artifact gets summary shaping" '[[ -n "$OUT" ]]'
run_hook "$(ss_env startup s11m "$CUSTOMER")"
run_hook "$(pc_env auto s11m "$CUSTOMER")"
run_hook "$(ss_env compact s11m "$CUSTOMER")"
assert "11i and gets the directive" 'has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'
assert "11j from a subdirectory too" 'true'
run_hook "$(pc_env auto s11n "$CUSTOMER/src")"
assert "11k subdirectory of a customer repo is in scope" '[[ -n "$OUT" ]]'

echo "== scenario 12 (AC12/FR3): PreCompact stdout =="
run_hook "$(pc_env auto s12 "$IN_ROOT")"
assert "12a rc 0" '[[ "$RC" -eq 0 ]]'
assert "12b non-empty" '[[ -n "$OUT" ]]'
# Written so a JSON emission FAILS the case rather than aborting the suite.
if printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
  fail "12c PreCompact must not emit JSON" "got: ${OUT:0:120}"
else
  pass "12c PreCompact emits non-JSON"
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
# DERIVED at runtime, ANCHORED on `branch=`. The literal branch name made this
# row red in CI (pull_request checks out a detached HEAD, so there is no branch)
# and on main -- measured 109/1 from a detached worktree. A bare token would also
# have been satisfied by the `Spec and tasks:` line (cq-assert-anchor-not-bare-token).
assert_fixture_dir "$IN_ROOT"
_expect_branch="$(git -C "$IN_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || echo unknown)"
_expect_branch="${_expect_branch:-unknown}"
assert "14g names the branch, anchored and derived" 'has_ctx "branch=${_expect_branch}( |$)"'
assert "14h and never asserts the literal HEAD as a branch" '! has_ctx "branch=HEAD( |$)"'

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

echo "== scenario 19 (CTO ruling 1): a manual compaction does NOT revoke =="
# Restored INVERTED. The original asserted that a manual current compaction sets
# recommend=false even with the threshold already met; the CTO ruled that the
# only behavioural delta of the `trigger == auto` conjunct was RETRACTING a
# recommendation already issued -- COUNT_AUTO rises only on a committed `auto`
# line, so the first crossing always had trigger=auto and fired either way.
# This row is the regression test against re-introducing it, and it is the only
# row pinning monotonicity across a mixed sequence.
#
# It was also silently DELETED once: a scenario-17 rewrite sliced up to the
# scenario-18 anchor and took 19 with it, the case floor caught a drop, and the
# floor was recalibrated without checking WHICH case had gone. Hence the
# explicit per-scenario markers below.
sid=s19
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
compact_cycle auto "$sid" "$IN_ROOT"
assert "19a two autos recommend" 'has_ctx "recommend=true"'
compact_cycle manual "$sid" "$IN_ROOT"
assert "19b count_auto stays 2" 'has_ctx "count_auto=2( |$)"'
assert "19c count_total is 3" 'has_ctx "count_total=3( |$)"'
assert "19d the current trigger is reported as manual" 'has_ctx "trigger=manual"'
assert "19e and the earned recommendation is NOT revoked" 'has_ctx "recommend=true"'
# The far side: manual-only can never earn it in the first place.
sid=s19b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle manual "$sid" "$IN_ROOT"
compact_cycle manual "$sid" "$IN_ROOT"
compact_cycle manual "$sid" "$IN_ROOT"
assert "19f three manuals never recommend" 'has_ctx "recommend=false"'
assert "19g because they contribute nothing to count_auto" 'has_ctx "count_auto=0( |$)"'

echo "== scenario 25: the marker literals the CONSUMERS branch on =="
# plan/SKILL.md and work/SKILL.md branch on a string this hook emits. Nothing
# tied the three spellings together, and the degraded state is indistinguishable
# from the designed one: work/SKILL.md says in terms that "no marker" means emit
# the block with no nudge, "the correct output rather than a degraded one" -- so
# a renamed marker produces the sanctioned output forever. Derived from the
# hook's CAPTURED OUTPUT, never re-typed.
sid=s25
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"; compact_cycle auto "$sid" "$IN_ROOT"
_marker="$(ctx | grep -oE '^SOLEUR_COMPACTION_[A-Z_]+' | head -1)"
_flag="$(ctx | grep -oE 'recommend=true' | head -1)"
assert "25a the hook emitted a marker to derive from" '[[ -n "$_marker" ]]'
assert "25b and the recommend flag" '[[ -n "$_flag" ]]'
for f in plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/work/SKILL.md; do
  assert "25c $(basename "$(dirname "$f")")/SKILL.md branches on the emitted marker" \
    '[[ "$(grep -cF -- "$_marker" "$REPO_ROOT/'"$f"'" 2>/dev/null || true)" -gt 0 ]]'
  assert "25d $(basename "$(dirname "$f")")/SKILL.md branches on the emitted flag" \
    '[[ "$(grep -cF -- "$_flag" "$REPO_ROOT/'"$f"'" 2>/dev/null || true)" -gt 0 ]]'
done

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
# With TMPDIR unset the ledger root is /tmp/soleur-compaction, world-reachable on
# a multi-user host. The WRITE fails closed; the feature fails open. Two arms,
# because they differ: PreCompact still owes the summarizer its prose (shaping
# needs no ledger), while SessionStart owes the model a REASON -- emitting
# nothing there made a permanent per-host disable indistinguishable from "this
# session has not compacted".
SQUAT="$SANDBOX/squat"; mkdir -p "$SQUAT"
: > "$SQUAT/soleur-compaction"          # a FILE where the hook wants a directory
run_hook "$(pc_env auto s23 "$IN_ROOT")" "TMPDIR=$SQUAT" "PATH=$PATH" "HOME=$HOME" \
  "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "23a PreCompact: rc 0" '[[ "$RC" -eq 0 ]]'
assert "23b PreCompact still shapes the summary" '[[ -n "$OUT" ]]'
assert "23c but writes no pending slot" '[[ -z "$(find "$SQUAT" -name "*.pending" -print -quit 2>/dev/null)" ]]'
run_hook "$(ss_env compact s23 "$IN_ROOT")" "TMPDIR=$SQUAT" "PATH=$PATH" "HOME=$HOME" \
  "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "23d SessionStart: rc 0" '[[ "$RC" -eq 0 ]]'
assert "23e emits a valid envelope, not silence" 'printf "%s" "$OUT" | jq -e . >/dev/null 2>&1'
assert "23f and the reason is MODEL-visible, not just stderr" 'has_ctx "reason=ledger-dir-unusable"'
assert "23g with no directive" '! has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'
# A SYMLINK at that path satisfies -d and -O, which is how the first version of
# this guard was defeated: it wrote through the link and chmod 700'd the target.
SLINK="$SANDBOX/slink"; mkdir -p "$SLINK" "$SANDBOX/slink-target"
chmod 755 "$SANDBOX/slink-target"
ln -s "$SANDBOX/slink-target" "$SLINK/soleur-compaction"
run_hook "$(pc_env auto s23b "$IN_ROOT")" "TMPDIR=$SLINK" "PATH=$PATH" "HOME=$HOME" \
  "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION"
assert "23h a symlinked ledger root writes nothing through the link" \
  '[[ -z "$(ls -A "$SANDBOX/slink-target" 2>/dev/null)" ]]'
assert "23i and does not chmod the target" '[[ "$(stat -c %a "$SANDBOX/slink-target")" == "755" ]]'

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

echo "== scenario 26: the guards added at review, each with a row =="
# Every hardening this session added -- the symlink refusal, umask 077, the
# lossy-SID refusal, sanitize_display, the threshold sanitizer, the pending
# clear on reset -- was deletable with the whole suite green. The hardening
# reflex was strong; the accompanying-row reflex was not. One row each.

# (a) the `specs` disjunct of the scope guard: every other root fixture carries
#     `plans`, so dropping `|| specs` survived everything.
SPECONLY="$SANDBOX/speconly"; mkdir -p "$SPECONLY/knowledge-base/project/specs"
run_hook "$(pc_env auto s26a "$SPECONLY")"
assert "26a a specs-only checkout is in scope" '[[ -n "$OUT" ]]'

# (b) PLAN / SPEC discovery: asserted only in the negative, so deleting both
#     discovery blocks shipped a directive naming no artifacts -- the payload.
sid=s26b
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
# Gated on the branch resolving: CI checks out a DETACHED HEAD on pull_request,
# where there is no branch, so no plan glob matches and no specs/<branch>/ exists
# -- the same coupling that made 14g red in CI. The rows still pin the discovery
# blocks wherever a branch exists (every developer checkout), which is where the
# mutation they exist to kill would be introduced.
if [[ "$_expect_branch" != "unknown" ]] \
   && compgen -G "$IN_ROOT/knowledge-base/project/plans/*-${_expect_branch}-plan.md" >/dev/null; then
  assert "26b names a real plan path" 'has_ctx "^Plan: knowledge-base/project/plans/.*-plan\.md$"'
  assert "26c names the spec directory" 'has_ctx "^Spec and tasks: knowledge-base/project/specs/"'
else
  # Never silently skip: a conditional row that vanishes is indistinguishable
  # from one that passed. Assert the branch the OTHER way instead.
  assert "26b (detached HEAD) no plan is fabricated" '! has_ctx "^Plan: $"'
  assert "26c (detached HEAD) no spec is fabricated" '! has_ctx "^Spec and tasks: $"'
fi

# (c) the 8000-char cap, sampled at 527 bytes -- a 1-of-1 at the wrong end of
#     the range, which can only ever confirm the value it already has.
sid=s26c
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
_big="$(printf 'x%.0s' $(seq 1 9000))"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")" "SOLEUR_COMPACTION_CLI_VERSION=$_big" \
  "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME" "SOLEUR_HOOK_TRACE=$SOLEUR_HOOK_TRACE"
_len="$(ctx | wc -c)"
_clilen="$(ctx | grep -oE 'cli=x+' | head -1 | wc -c)"
# Two bounds, because one-sided is satisfiable by a constant. The envelope cap is
# the outer bound; the per-field cap in sanitize_display is what a 9000-char
# input actually hits first, which is WHY the envelope cap cannot be driven by
# this input -- recorded rather than asserted as a floor that would false-fail.
assert "26d the context stays under the envelope cap" '[[ "$_len" -le 8001 ]]'
assert "26e the oversized field is capped, not dropped" '[[ "$_clilen" -gt 100 && "$_clilen" -le 210 ]]'
assert "26f the directive still renders around it" 'has_ctx "SOLEUR_COMPACTION_DIRECTIVE"'

# (d) the threshold sanitizer: a non-numeric value makes (( )) see 0, which
#     recommends on the FIRST auto -- the over-firing harm.
sid=s26f
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env auto "$sid" "$IN_ROOT")"
run_hook "$(ss_env compact "$sid" "$IN_ROOT")" "SOLEUR_COMPACTION_COUNT_THRESHOLD=abc" \
  "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME" "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION" \
  "SOLEUR_HOOK_TRACE=$SOLEUR_HOOK_TRACE"
assert "26g a non-numeric threshold falls back to the default" 'has_ctx "threshold=2"'
assert "26h and does not recommend on one auto" 'has_ctx "recommend=false"'
# `010` passes a digits-only filter and (( )) reads it as OCTAL 8.
run_hook "$(ss_env compact "$sid" "$IN_ROOT")" "SOLEUR_COMPACTION_COUNT_THRESHOLD=010" \
  "TMPDIR=$TMPDIR" "PATH=$PATH" "HOME=$HOME" "SOLEUR_COMPACTION_CLI_VERSION=$SOLEUR_COMPACTION_CLI_VERSION" \
  "SOLEUR_HOOK_TRACE=$SOLEUR_HOOK_TRACE"
assert "26i a leading-zero threshold is decimal, not octal" 'has_ctx "threshold=10"'

# (e) the reset must clear the PENDING slot too, not only the ledger. Nothing
#     interposed a window reset between an armed PreCompact and a later compact,
#     so a stale pre-reset trigger committed into the new window.
sid=s26i
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
run_hook "$(pc_env manual "$sid" "$IN_ROOT")"     # armed, never committed
run_hook "$(ss_env clear "$sid" "$IN_ROOT")"      # window reset
run_hook "$(ss_env compact "$sid" "$IN_ROOT")"
assert "26j a reset clears the pending slot, not just the ledger" \
  'has_ctx "SOLEUR_COMPACTION_SKIPPED.*reason=no-ledger-entry"'
assert "26k so no stale trigger is committed into the new window" '! has_ctx "trigger=manual"'

# (f) sanitize_display: a git ref may legally carry characters that render as
#     prose, and a FILENAME may contain newlines, which jq --arg faithfully
#     preserves inside the string the model reads.
sid=s26k
EVIL="$SANDBOX/evilrepo"; mkdir -p "$EVIL/knowledge-base/project/plans"
git -C "$EVIL" init -q >/dev/null 2>&1
git -C "$EVIL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$EVIL" checkout -q -b 'evil;$(id)|x' >/dev/null 2>&1
run_hook "$(ss_env startup "$sid" "$EVIL")"
compact_cycle auto "$sid" "$EVIL"
assert "26l shell metacharacters are stripped from the branch" '! has_ctx "[;|$]"'
assert "26m and the branch is still named" 'has_ctx "branch=evilidx"'

echo "== scenario 27: RC and ERR are asserted in BOTH directions =="
# 19 rows assert `RC -eq 0` and none asserted non-zero, so `RC=$?` -> `RC=0`
# survived -- the fail-open contract, the hook's headline property, rode on a
# harness variable that is also initialised to 0.
_savedsut="$SUT"; SUT="$SANDBOX/rc3.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SUT"; chmod +x "$SUT"
run_hook '{}'
assert "27a a non-zero exit is actually observed" '[[ "$RC" -eq 3 ]]'
SUT="$_savedsut"
# And stderr must be EMPTY on a happy path, or a constant-string ERR passes the
# stderr greps in scenarios 20 and 23.
sid=s27
run_hook "$(ss_env startup "$sid" "$IN_ROOT")"
compact_cycle auto "$sid" "$IN_ROOT"
assert "27b a healthy invocation writes nothing to stderr" '[[ -z "$ERR" ]]'

# --- coverage floors ----------------------------------------------------
# Reported with printf + exit, NOT through fail() -- the helper these floors
# exist to backstop is the one an edit disarms.
MIN_CASES=148
if (( CASES < MIN_CASES )); then
  printf 'FATAL: assertion floor breached -- ran %d cases, floor is %d. Cases were deleted, or the suite aborted early.\n' \
    "$CASES" "$MIN_CASES" >&2
  exit 1
fi
# passes + fails must equal CASES. They diverged once (a call site bumped CASES
# while pass()/fail() also did), which is exactly how a counter stops measuring
# what its floor thinks it measures. Reported directly, not through the helpers.
if (( passes + fails != CASES )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) != CASES(%d)\n' \
    "$passes" "$fails" "$CASES" >&2
  exit 1
fi
SUT_RUNS="$(grep -c '^ran$' "$SOLEUR_HOOK_TRACE" 2>/dev/null || true)"
MIN_SUT_RUNS=138
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
