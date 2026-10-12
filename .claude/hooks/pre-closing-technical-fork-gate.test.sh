#!/usr/bin/env bash
# Fixture tests for pre-closing-technical-fork-gate.sh (a Stop hook) and the shared cue lib it calls.
#
# Both directions are load-bearing and the second is the worse failure:
#   a missed technical fork costs the status quo (the founder is asked a question they cannot answer);
#   a wrongly BLOCKED closing message costs a turn, and if it carried an authorization, trust in every hook.
# So the must-PASS rows (authorizations, operator-class questions, status reports, every parse doubt)
# outnumber the must-BLOCK rows, and the fail-open rows are rows, not comments.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only). The three headline questions B1-B3 are the
# sentences the 2026-10-12 incident put to the operator, supplied by the brief of this work and carrying no
# secret or personal data.
#
# MUTATION MATRIX (Guard 1 and Guard 2 of the plan). Every row builds a fresh tree beside copies of the hook and
# lib, applies ONE literal mutation, asserts the mutation LANDED (the file differs from the pristine copy) and
# that the mutant still PARSES (a mutant that does not parse is rejected, never counted as killed), requires the
# UNMUTATED control to give the expected verdict, and requires the mutant to give a different one.
#   G1-1  tfc_is_fork -> false (the guard's own dispatch)          B1 B2 B3 flip block -> pass
#   G1-2  delete the permission exemption                           Z1 flips pass -> block
#   G1-3  delete the stop_hook_active check                         L1 flips pass -> block
#   G1-4  judge only the first unit                                 U1 flips block -> pass
#   G1-5  veto CLOSING cues with BUSINESS|ACTION                    B2 flips block -> pass
#   G1-6  remove the BUSINESS veto                                  A7 flips pass -> block
#   G1-7  make a fail-open arm block (bad JSON; absent loop guard)  F2 F3 flip pass -> block
#   G1-8  delete the stop escape; drop the empty-label exclusion    E1 flips pass -> block; E3b block -> pass
#   G1-9  remove the code-span / quoted-line strip                  X2 flips pass -> block
#   G1-10 Operator-only escapes the whole window                    E4 flips block -> pass
#   G1-11 remove the 12-unit judging cap                               U3 exceeds its time bound
#   G1-12 delete the closing-only permission exemption              Q4a flips pass -> block
#   G1-13..16 leading-fragment drop, window size, first-12 judging, blank-line reset   W1b / W1d / L12b / E4b
#   G2-1  re-add a local RULING_PERM_RE to the closing hook         the definition-site census reports two
#   G2-2  the lib ignores its group argument                        a pre-ask row (NR2a) flips allow -> deny
#   G2-3  change RULING_OPVOCAB_RE in the lib                       the byte-equality row flips
# Harness rows: H1 neuters the decider the row helper uses (must-PASS rows redden); H3 drives the row helper
# through one real pass and one real fail before any row; the neutered-counter and floor mutants are built by
# scripts/guard-vacuity-floor.test.sh for any suite whose floor has the recognised shape, so the floor below
# keeps that shape.
set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs: the closing hook is an
# emit_incident caller, and an unredirected run writes fixtures into the operator's real ledger.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOKS_DIR/pre-closing-technical-fork-gate.sh"
PREASK="$HOOKS_DIR/pre-ask-technical-fork-gate.sh"
LIB="$HOOKS_DIR/lib/technical-fork-cues.sh"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd)"
SETTINGS="$REPO_ROOT/.claude/settings.json"
LEDGER_TSV="$HOOKS_DIR/devin-dispositions.tsv"
PASS=0; FAIL=0; TOTAL=0
[[ -x "$HOOK" ]] || { echo "FATAL: hook not executable at $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }

# The CANONICAL copy, asserted byte-for-byte against every other copy by plugins/soleur/test/fixture-dir-operand-assert.test.sh.
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
WORK="${SOLEUR_TEST_INCIDENT_ROOT:?incident sandbox root unset}/w"
assert_fixture_dir "$WORK"
mkdir -p "$WORK" || { echo "FATAL: cannot create the suite work dir" >&2; exit 2; }

# --- fixtures ---------------------------------------------------------------------------------------
B1="is the existing census enough to close the G2 issue, given a personal CLI token not listed and a branch-nameable write token on another config?"
B2="what is the right design for moving the three deploy-channel credentials out of branch-nameable storage?"
B3="should the two credentials be rotated now, and in what order?"
STATUS="Status: the census ran; 12 of 14 probes are green and the rest are queued."
BLOCK_REASON_HEAD='STOPPED: your closing message asks the operator to choose on a TECHNICAL fork'
TAB=$'\t'

# --- the row machinery ------------------------------------------------------------------------------
SPAWNS=0     # spawns the HARNESS made
RAN=0        # executions the SUT reported through its own stderr marker
OUT=""; ERR=""
BLOCKED_BY_THIS_HOOK=" "
DECIDER=decide_real

closing_json() { # <message> [stop_hook_active true|false]
  jq -nc --arg m "$1" --argjson a "${2:-false}" '{stop_hook_active:$a, last_assistant_message:$m, session_id:"t"}'
}
spawn() { # <hook> <json> [extra env assignment]: sets OUT and ERR, counts spawns and SUT markers
  local hook="$1" json="$2" errf="$WORK/stderr" l
  SPAWNS=$((SPAWNS+1))
  OUT="$(printf '%s' "$json" | env SOLEUR_HOOK_TRACE=1 ${3:+"$3"} bash "$hook" 2>"$errf")"
  ERR="$(cat "$errf")"
  while IFS= read -r l; do [[ "$l" == "SOLEUR_HOOK_RAN" ]] && RAN=$((RAN+1)); done <<<"$ERR"
  return 0
}
verdict_from_out() { # stdout of a hook run -> block | pass | bad
  local d
  [[ -n "$OUT" ]] || { echo pass; return; }
  d="$(jq -r '.decision // "none"' <<<"$OUT" 2>/dev/null)" || { echo bad; return; }
  case "$d" in block) echo block ;; none) echo pass ;; *) echo bad ;; esac
}
decide_real() { # <hook> <json> -> block | pass | bad
  spawn "$1" "$2" "${3:-}"
  verdict_from_out
}
decide_always_block() { echo block; }   # H1's neutered decider
# row <name> <expect block|pass> <message> [active]
row() {
  local name="$1" expect="$2" msg="$3" active="${4:-false}" got reason
  TOTAL=$((TOTAL+1))
  # The real decider runs in THIS shell (the spawn/marker bookkeeping lives in globals); a substitute decider
  # (H1's neutered one) is a pure function and is called in a substitution.
  if [[ "$DECIDER" == "decide_real" ]]; then
    spawn "$HOOK" "$(closing_json "$msg" "$active")"; got="$(verdict_from_out)"
  else
    got="$($DECIDER "$HOOK" "$(closing_json "$msg" "$active")")"
  fi
  if [[ "$got" == "$expect" ]]; then
    if [[ "$expect" == "block" && "$DECIDER" == "decide_real" ]]; then
      reason="$(jq -r '.reason // ""' <<<"$OUT" 2>/dev/null)"
      if [[ "$reason" == "$BLOCK_REASON_HEAD"* ]]; then BLOCKED_BY_THIS_HOOK="$BLOCKED_BY_THIS_HOOK$name "
      else printf '  FAIL: %s — blocked, but not with this hook'"'"'s reason\n' "$name" >&2; FAIL=$((FAIL+1)); return 0; fi
    fi
    printf '  PASS: %s (%s)\n' "$name" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL: %s — got %s want %s\n' "$name" "$got" "$expect" >&2; FAIL=$((FAIL+1))
  fi
  return 0
}

echo "== pre-closing-technical-fork-gate =="

# --- H3: INSTRUMENT SELF-TEST — the row helper's two branches go to DIFFERENT buckets ---------------
# Driven BEFORE any row: a satisfied expectation must pay PASS and a violated one FAIL. Reported with printf
# and exit 1, never through the helper under test (a check routed through the machinery it backstops is
# disarmed by the same edit it exists to catch).
h3_probe() { ( PASS=0; FAIL=0; TOTAL=0; row "h3 probe" "$1" "All green. Nothing to decide." >/dev/null 2>&1; printf '%s/%s' "$PASS" "$FAIL" ); }
h3_ok="$(h3_probe pass)"; h3_bad="$(h3_probe block)"
if [[ "$h3_ok" != "1/0" || "$h3_bad" != "0/1" ]]; then
  printf '\nFATAL: instrument: row() does not discriminate — a satisfied expectation scored %s and a violated one %s (want 1/0 and 0/1). The verdict helper is misrouting, so every PASS below is unproven.\n' "$h3_ok" "$h3_bad" >&2
  exit 1
fi

# --- MUST BLOCK -------------------------------------------------------------------------------------
row "B1 sufficiency question (CL1)" block "$STATUS $B1"
row "B2 design question; the ACTION word deploy must not veto it (CL2a)" block "$STATUS $B2"
row "B3 ordering question (CL3)" block "$STATUS $B3"
row "B4 all three under a Your calls lead-in" block "$STATUS

Your calls:
1. $B1
2. $B2
3. $B3"
row "B5a B1 then a courtesy closer" block "$B1 Let me know what you think."
row "B5b B2 then a courtesy closer" block "$B2 Let me know what you think."
row "B5c B3 then a courtesy closer" block "$B3 Let me know what you think."
row "B6 the founder-observed phrase (CL2b)" block "$STATUS do you want a migration design?"
row "B7 a SHARED cue through the closing hook" block "$STATUS how strict should the evidence bar be?"
row "U1 an authorization first, a technical unit second" block "Do you authorize the rotation? Also, what is the best design for the migration?"

# --- MUST PASS --------------------------------------------------------------------------------------
row "A1 an authorization to rotate" pass "$STATUS Do you authorize rotating HCLOUD_TOKEN now?"
row "A2 a brand question" pass "$STATUS which option do you want for the landing page headline?"
row "A3 a status report with no question" pass "$STATUS Everything is green; nothing is waiting on anyone."
row "A4 B1 plus a stop escape (OPERATOR-GATE)" pass "$STATUS $B1 <stop>OPERATOR-GATE: this is the accounting call (money).</stop>"
TOTAL=$((TOTAL+1))
a5_fail=""
for a5_q in "May I merge PR 123?" "Approve the rotation order?" "Do you want me to open the follow-up issue?"; do
  spawn "$HOOK" "$(closing_json "$STATUS $a5_q")"; [[ "$(verdict_from_out)" == "pass" ]] || a5_fail="$a5_fail [$a5_q]"
done
if [[ -z "$a5_fail" ]]; then echo "  PASS: A5 permission-shaped asks pass"; PASS=$((PASS+1)); else printf '  FAIL: A5 blocked:%s\n' "$a5_fail" >&2; FAIL=$((FAIL+1)); fi
row "A6 a money-vetoed sufficiency question" pass "$STATUS Is the evidence enough to start charging?"
TOTAL=$((TOTAL+1))
a7_fail=""
for a7_q in "what is the best design for the pricing page?" "Do you want a logo design for the landing page?"; do
  spawn "$HOOK" "$(closing_json "$STATUS $a7_q")"; [[ "$(verdict_from_out)" == "pass" ]] || a7_fail="$a7_fail [$a7_q]"
done
if [[ -z "$a7_fail" ]]; then echo "  PASS: A7 business-vetoed design questions pass"; PASS=$((PASS+1)); else printf '  FAIL: A7 blocked:%s\n' "$a7_fail" >&2; FAIL=$((FAIL+1)); fi
row "A8 an operator priority question" pass "$STATUS Which should I do first, the P1 or the feature?"
row "Z1 a cue AND a permission shape (the exemption must win)" pass "may i rotate the keys, and in what order?"
row "L1 B3 with the loop guard set: at most one block per turn" pass "$STATUS $B3" true
# W1 (i): B1 sits on line 2 so the leading-fragment drop (which only ever touches line 1) cannot hide it: ONLY the 1500-byte
# window excludes it. W1b/W1c: the leading-fragment drop, with a control twin that must BLOCK (a veto word cut off by the window
# start would otherwise make the fragment block). W1d: a question ~1200 bytes from the end is inside the window.
PADLINE() { printf 'The census run is recorded and the probes are queued for the next window. %.0s' $(seq 1 "$1"); }
row "W1 B1 on line 2 above 2000 bytes of status prose is outside the window" pass "x.
$B1
$(PADLINE 30)"
W1_RUNON="$(printf 'a word and %.0s' $(seq 1 125))what is the right design for the migration?"
W1_LEN=${#W1_RUNON}
W1_X="$(printf 'x%.0s' $(seq 1 $((1500 - W1_LEN))))"
row "W1b a window that starts mid-sentence drops the fragment (the pricing veto word was cut off)" pass "pricing $W1_X$W1_RUNON"
row "W1c the twin without the cut: the same run-on question blocks" block "$W1_X$W1_RUNON"
row "W1d B1 about 1200 bytes from the end is inside the window" block "$B1
$(PADLINE 15)"
# N1 — near-misses the plan measured: each must PASS.
row "N1a a dark design is not a technical noun" pass "$STATUS do you want a dark design?"
row "N1b a bare best-approach has no object" pass "$STATUS what is the best approach?"
row "N1c an auditor is a business reader" pass "$STATUS is the audit log sufficient for the SOC2 auditor?"
row "N1d publishing is a business act" pass "$STATUS is the baseline enough to publish the case study?"
row "N1e prioritising is the operator's call" pass "$STATUS in what order should we prioritize the migrations?"
row "N1f shipping features is a roadmap question" pass "$STATUS in what order should we ship the features, config first?"

# --- no per-unit cap (Ruled by CTO agent, 2026-10-12 review). O1: a worst-case ~1500-byte unit packed with cue vocabulary is
# bounded by the window and by the linear regexes, not by a cap that would let a long run-on question through unjudged.
# O2: the pre-ask hook still denies a long question, so no cap leaked into the shared lib either.
TOTAL=$((TOTAL+1))
O1_UNIT="$(printf 'is the evidence the census the audit the baseline the gate the proof %.0s' $(seq 1 22))enough?"
o1_t0="$(date +%s%N | cut -b1-13)"
spawn "$HOOK" "$(closing_json "$O1_UNIT")"
o1_ms=$(( $(date +%s%N | cut -b1-13) - o1_t0 ))
o1_v="$(verdict_from_out)"
if [[ "$o1_v" != "bad" ]] && (( o1_ms < 3000 )) && ! grep -qE 'SKIPPED|NOTE' <<<"$ERR"; then
  printf '  PASS: O1 a worst-case 1500-byte unit is judged (%s) within the bound (%s ms), no cap\n' "$o1_v" "$o1_ms"; PASS=$((PASS+1))
else printf '  FAIL: O1 verdict=%s elapsed=%s ms stderr=%s\n' "$o1_v" "$o1_ms" "$ERR" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
o2_q="$(printf 'How strict must the emptiness evidence be before the volume rebirth is dispatched, given %.0s' $(seq 1 12))and the plaintext volume deleted?"
o2_json="$(jq -nc --arg q "$o2_q" '{tool_name:"AskUserQuestion", cwd:".", session_id:"t", tool_input:{questions:[{question:$q, options:[{label:"Yes",description:"go"},{label:"No",description:"stop"}]}]}}')"
o2_dec="$(printf '%s' "$o2_json" | bash "$PREASK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
if (( ${#o2_q} > 600 )) && [[ "$o2_dec" == "deny" ]]; then echo "  PASS: O2 the same kind of oversize question still DENIES through the pre-ask hook (no cap leaked into the lib)"; PASS=$((PASS+1))
else printf '  FAIL: O2 len=%s decision=%s\n' "${#o2_q}" "$o2_dec" >&2; FAIL=$((FAIL+1)); fi

# --- escapes ----------------------------------------------------------------------------------------
row "E1 a BLOCKED stop escape" pass "$STATUS $B1 <stop>BLOCKED: waiting on the registry owner.</stop>"
row "E2 an Operator-only label whose own sentence is the unit" pass "Operator-only (money): should we charge for the second seat now?"
row "E2b an Operator-only label governs the next unit in its paragraph" pass "Operator-only (money): the accounting call is below. $B1"
row "E3 a final-sentence Paused label" pass "$STATUS $B1 Paused: waiting on CI."
row "E3c a bold final Paused label (the plugin hook's accepted form)" pass "$STATUS $B1 **Paused**: waiting on CI."
row "E3d a plain final Blocked label with content" pass "$STATUS $B1 Blocked: waiting on the registry owner."
row "E3e empty stop escapes do not escape (BLOCKED, then BLOCKED with a space)" block "$STATUS $B1 <stop>BLOCKED:</stop> <stop>BLOCKED: </stop>"
row "E4b an Operator-only label does not cross a blank line" block "Operator-only (money): the accounting call is below.

$B1"
row "E4c an Operator-only label covers ONE unit: the second question still blocks" block "Operator-only (money): the call is below. $B1 $B2"
row "E4d an Operator-only label with no content does not escape" block "Operator-only (money):
$B1"
row "E4e an empty category does not escape" block "Operator-only (): $B1"
TOTAL=$((TOTAL+1))
ec_fail=""
for ec_c in money scope priority schedule irreversible production-mutating legal-risk brand; do
  spawn "$HOOK" "$(closing_json "Operator-only ($ec_c): $B1")"; [[ "$(verdict_from_out)" == "pass" ]] || ec_fail="$ec_fail $ec_c"
done
if [[ -z "$ec_fail" ]]; then echo "  PASS: E2c all eight Operator-only categories release their own sentence (the reason teaches all eight)"; PASS=$((PASS+1)); else printf '  FAIL: E2c categories not recognised:%s\n' "$ec_fail" >&2; FAIL=$((FAIL+1)); fi
row "N1g an ordering question with no technical noun passes" pass "$STATUS in what order is the report?"
# The 12-unit cap by VERDICT: B1 eleven units from the end is judged; B1 thirteen from the end is not.
TINY11="$(printf 'a? %.0s' $(seq 1 11))"; TINY12="$(printf 'a? %.0s' $(seq 1 12))"
row "L12a B1 followed by 11 tiny units is the 12th from the end: judged" block "$B1 $TINY11"
row "L12b B1 followed by 12 tiny units is the 13th from the end: not judged" pass "$B1 $TINY12"
# Q4 (Ruled by CTO agent, 2026-10-12 review): closing-only permission shapes bound to an ACTION verb pass; the bare
# `can i` / `should i` / `go ahead` / `we` forms are technical-fork shapes and still block.
row "Q4a can-i with an action verb (cue: suff)" pass "can i merge pr 123 now, is the evidence enough?"
row "Q4b shall-i-proceed with an action verb (cue: cl3)" pass "shall i proceed and rotate the production credentials now, in what order?"
row "Q4c should-i-go-ahead-and with an action verb" pass "should i go ahead and rotate the storage credentials?"
row "Q4d shall-i-go-ahead with an action verb" pass "shall i go ahead and deploy to production?"
row "Q4e a we-form is not a permission shape (bar)" block "can we tighten the evidence threshold?"
row "Q4f should-i is a ruling shape (ab)" block "should i use approach a or b for the retry queue?"
row "Q4g can-i without an action verb is not an authorization (ab)" block "can i use approach a or b for the retry queue?"
row "Q4h should-we-go-ahead-with is a ruling shape (ab)" block "should we go ahead with approach a or b for the schema?"
row "Q4i the ordering half of an authorization ask stays technical (cl3)" block "which order should the storage credentials be rotated in?"
row "Q4j a sufficiency ask is the motivating miss (cl1)" block "is the coverage enough to deploy to production?"
# The full-hook form of Q4j: a neighbouring Approve? unit does NOT exempt the sufficiency unit above it (judged per sentence).
row "Q4k a sufficiency unit followed by an Approve? unit: the sufficiency ask is the motivating miss" block "Is the coverage enough to deploy to production? Approve?"
TOTAL=$((TOTAL+1))
qv_fail=""
for qv in "can i" "shall i"; do for qverb in "go ahead" proceed merge deploy ship release rotate flip arm delete revoke apply push; do
  spawn "$HOOK" "$(closing_json "$qv $qverb now, is the evidence enough?")"; [[ "$(verdict_from_out)" == "pass" ]] || qv_fail="$qv_fail [$qv $qverb]"
done; done
for qverb in merge deploy ship release rotate flip arm delete revoke apply push; do
  spawn "$HOOK" "$(closing_json "should i go ahead and $qverb now, is the evidence enough?")"; [[ "$(verdict_from_out)" == "pass" ]] || qv_fail="$qv_fail [should i go ahead and $qverb]"
done
if [[ -z "$qv_fail" ]]; then echo "  PASS: Q4l every action verb of the closing-only permission shapes exempts"; PASS=$((PASS+1)); else printf '  FAIL: Q4l verbs that did not exempt:%s\n' "$qv_fail" >&2; FAIL=$((FAIL+1)); fi
row "E3b an EMPTY final label does not escape" block "$STATUS $B1 Blocked: none."
row "E4 an unrelated Operator-only sentence does not escape another paragraph's question" block "Operator-only (money): should we charge for the second seat now?

$B1"
E5_BT="$STATUS the \` here is a stray backtick. $B1"
row "E5b a lone stray backtick does not eat the question" block "$E5_BT"
row "E5c NBSP at a literal-space position is normalised first" block "$STATUS is$(printf '\xc2\xa0')the existing census enough to close the G2 issue?"
row "E5e U+2009 at a literal-space position is normalised first" block "$STATUS is$(printf '\xe2\x80\x89')the existing census enough to close the G2 issue?"
row "E6a a CRLF closing is judged" block "$(printf 'Done.\r\nIs the existing census enough to close the G2 issue?\r\nBye')"
row "E6b a word joiner inside the cue is removed first" block "$STATUS is the existing cen$(printf '\xe2\x81\xa0')sus enough to close the G2 issue?"
row "E6c a BOM inside the cue is removed first" block "$STATUS is the existing census$(printf '\xef\xbb\xbf') enough to close the G2 issue?"
row "E5d a zero-width space inside the cue is removed first" block "$STATUS is the existing cen$(printf '\xe2\x80\x8b')sus enough to close the G2 issue?"
TOTAL=$((TOTAL+1))
spawn "$HOOK" "$(closing_json "$STATUS
\`\`\`
unterminated fence
$B1")"
if [[ "$(verdict_from_out)" == "pass" ]] && grep -qF 'unterminated fenced block' <<<"$ERR"; then echo "  PASS: E5a an unterminated fence is parse doubt (pass with a stderr line)"; PASS=$((PASS+1))
else printf '  FAIL: E5a verdict=%s stderr=%s\n' "$(verdict_from_out)" "$ERR" >&2; FAIL=$((FAIL+1)); fi

# --- URLs, fences, spans, quotes --------------------------------------------------------------------
row "U2a a URL query string is not a unit boundary" pass "is the census enough, see https://example.com/issues?id=3 for the run. $STATUS"
row "U2b a bold question: the ? is followed by closing punctuation" block "$STATUS **is the census enough to close the G2 issue?**"
row "X1 a fenced block holding B1 above a clean closing" pass "\`\`\`
$B1
\`\`\`
$STATUS"
row "X2a B1 inside inline backticks" pass "$STATUS \`$B1\` is the phrase the hook quotes."
row "X2b B1 on a quoted line" pass "$STATUS
> $B1
That quote is the hook's own fixture."

# --- fail open on every parse doubt ----------------------------------------------------------------
fo_row() { # <name> <stdin text> [env]  -> the hook must exit 0 with NO stdout and one stderr line
  TOTAL=$((TOTAL+1))
  spawn "$HOOK" "$2" "${3:-}"
  if [[ -z "$OUT" && -n "$ERR" ]]; then printf '  PASS: %s (fail open, stderr: %s)\n' "$1" "$(head -c 80 <<<"$ERR" | head -n 2 | tail -n 1)"; PASS=$((PASS+1))
  else printf '  FAIL: %s — stdout=[%s] stderr=[%s]\n' "$1" "$OUT" "$ERR" >&2; FAIL=$((FAIL+1)); fi
}
fo_row "F1 empty stdin" ""
fo_row "F2 invalid JSON" "{not json"
fo_row "F3 the loop guard key is absent" "$(jq -nc --arg m "$B1" '{last_assistant_message:$m}')"
fo_row "F4 a non-string message" '{"stop_hook_active":false,"last_assistant_message":["x"]}'
fo_row "F6 the message key is absent" '{"stop_hook_active":false}'
TOTAL=$((TOTAL+1))
NOJQ="$WORK/nojq"; assert_fixture_dir "$NOJQ"; mkdir -p "$NOJQ"
f5_json="$(closing_json "$B1")"
SPAWNS=$((SPAWNS+1))
f5_out="$(printf '%s' "$f5_json" | env SOLEUR_HOOK_TRACE=1 PATH="$NOJQ" "$BASH" "$HOOK" 2>"$WORK/stderr")"; f5_rc=$?
f5_err="$(cat "$WORK/stderr")"
while IFS= read -r l; do [[ "$l" == "SOLEUR_HOOK_RAN" ]] && RAN=$((RAN+1)); done <<<"$f5_err"
if [[ -z "$f5_out" && "$f5_rc" -eq 0 ]] && grep -qF 'jq unavailable' <<<"$f5_err"; then echo "  PASS: F5 jq absent (PATH stripped): fail open with a stderr line"; PASS=$((PASS+1))
else printf '  FAIL: F5 stdout=[%s] rc=%s stderr=[%s]\n' "$f5_out" "$f5_rc" "$f5_err" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
spawn "$HOOK" "$(closing_json "$B1")" "GITHUB_ACTIONS=true"
if [[ -z "$OUT" ]]; then echo "  PASS: G3 GITHUB_ACTIONS=true exits 0 (no operator to ask)"; PASS=$((PASS+1)); else echo "  FAIL: G3 blocked under GITHUB_ACTIONS" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
spawn "$HOOK" "$(closing_json "$B1")" "SOLEUR_ACK_TECHNICAL_FORK=1"
if [[ "$(jq -r '.systemMessage // ""' <<<"$OUT" 2>/dev/null)" == *'disarmed by SOLEUR_ACK_TECHNICAL_FORK=1'* && "$(jq -r '.decision // "none"' <<<"$OUT" 2>/dev/null)" == "none" ]]; then
  echo "  PASS: K1 the kill switch disarms, announced"; PASS=$((PASS+1)); else echo "  FAIL: K1 the kill switch did not disarm and announce" >&2; FAIL=$((FAIL+1)); fi

# --- missing, empty or truncated lib is parse doubt, never a blanket block --------------------------
TOTAL=$((TOTAL+1))
ML="$WORK/ml"; assert_fixture_dir "$ML"; mkdir -p "$ML/without/lib" "$ML/empty/lib" "$ML/with/lib" "$ML/trunc/lib"
ml_ok=1
for ml_f in "$HOOKS_DIR"/lib/*.sh; do
  cp "$ml_f" "$ML/with/lib/" || ml_ok=0
  [[ "${ml_f##*/}" == "technical-fork-cues.sh" ]] || { cp "$ml_f" "$ML/without/lib/" && cp "$ml_f" "$ML/empty/lib/" && cp "$ml_f" "$ML/trunc/lib/"; } || ml_ok=0
done
: > "$ML/empty/lib/technical-fork-cues.sh"
# A lib TRUNCATED before its completion sentinel (the realistic failure: a partial write or a bad merge) must fail open too.
grep -v '^_TFC_COMPLETE=1$' "$LIB" > "$ML/trunc/lib/technical-fork-cues.sh" || ml_ok=0
for ml_d in with without empty trunc; do cp "$HOOK" "$ML/$ml_d/pre-closing-technical-fork-gate.sh" || ml_ok=0; done
ml_j="$(closing_json "$B1")"
spawn "$ML/with/pre-closing-technical-fork-gate.sh" "$ml_j"; ml_ctl="$(verdict_from_out)"
spawn "$ML/without/pre-closing-technical-fork-gate.sh" "$ml_j"; ml_a="$(verdict_from_out)"; ml_a_err="$ERR"
spawn "$ML/empty/pre-closing-technical-fork-gate.sh" "$ml_j"; ml_b="$(verdict_from_out)"; ml_b_err="$ERR"
spawn "$ML/trunc/pre-closing-technical-fork-gate.sh" "$ml_j"; ml_c="$(verdict_from_out)"; ml_c_err="$ERR"
if [[ "$ml_ok" -eq 1 && "$ml_ctl" == "block" && "$ml_a" == "pass" && "$ml_b" == "pass" && "$ml_c" == "pass" ]] \
   && grep -qF 'cue lib missing or incomplete' <<<"$ml_a_err" && grep -qF 'cue lib missing or incomplete' <<<"$ml_b_err" \
   && grep -qF 'cue lib missing or incomplete' <<<"$ml_c_err"; then
  echo "  PASS: ML1 a missing, empty or truncated lib fails open with a stderr line (control with the lib blocks)"; PASS=$((PASS+1))
else printf '  FAIL: ML1 setup=%s control=%s missing=%s empty=%s truncated=%s\n' "$ml_ok" "$ml_ctl" "$ml_a" "$ml_b" "$ml_c" >&2; FAIL=$((FAIL+1)); fi

# --- the block output: one JSON object, byte-constant text, no model text ------------------------------
TOTAL=$((TOTAL+1))
spawn "$HOOK" "$(closing_json "$STATUS $B1")"; j1_out="$OUT"; j1_reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null)"; j1_sys="$(jq -r '.systemMessage' <<<"$OUT" 2>/dev/null)"
spawn "$HOOK" "$(closing_json "Different status entirely. $B3 Thanks.")"; j2_reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null)"; j2_sys="$(jq -r '.systemMessage' <<<"$OUT" 2>/dev/null)"
j_count="$(jq -s 'length' <<<"$j1_out" 2>/dev/null)"
if [[ "$j_count" == "1" && -n "$j1_reason" && "$j1_reason" == "$j2_reason" && "$j1_sys" == "$j2_sys" ]] \
   && ! grep -qiE 'census|credential|config' <<<"$j1_sys"; then
  echo "  PASS: J1 stdout is exactly one JSON object and reason/systemMessage are byte-identical for two closings"; PASS=$((PASS+1))
else printf '  FAIL: J1 objects=%s reason-equal=%s\n' "$j_count" "$([[ "$j1_reason" == "$j2_reason" ]] && echo yes || echo no)" >&2; FAIL=$((FAIL+1)); fi

# R1-R3: the reason's content (AC5).
r_fail=""
chk() { grep -qF -- "$1" <<<"$j1_reason" || r_fail="$r_fail [$1]"; }
TOTAL=$((TOTAL+1))
chk 'soleur:engineering:cto'; chk 'soleur:legal:clo'; chk 'Ruled by CTO agent'; chk 'do NOT use AskUserQuestion'
chk 'money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand'
chk 'Split the item: ask the operator only the authorization'; chk 'hr-technical-fork-is-not-an-operator-question'
chk 'technical-ruling-delegation.md'; chk 'Operator-only (money):'; chk 'Paused:'
if [[ -z "$r_fail" ]]; then echo "  PASS: R1 the reason names the CTO and CLO, the ruling record, the closed list, the split remedy and the rule id"; PASS=$((PASS+1))
else printf '  FAIL: R1 reason lacks:%s\n' "$r_fail" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
first_cto="${j1_reason%%soleur:engineering:cto*}"; first_esc="${j1_reason%%Operator-only*}"
if (( ${#first_cto} < ${#first_esc} )) && (( ${#first_cto} < ${#j1_reason} )); then echo "  PASS: R2 the first imperative is the CTO spawn; the escapes come after it"; PASS=$((PASS+1))
else echo "  FAIL: R2 the escapes are taught before the CTO spawn" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
if [[ "$j1_reason" != *'<'* && "$j1_reason" != *'>'* && "$j1_sys" != *'<'* && "$j1_sys" != *'>'* ]] \
   && ! grep -qiE 'promise|operator-gate|done' <<<"$j1_reason"; then
  echo "  PASS: R3 neither text carries angle-bracket markup, the retired escape, or a completion word"; PASS=$((PASS+1))
else echo "  FAIL: R3 the reason or systemMessage carries markup or a forbidden word" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
if grep -qF 'SOLEUR_ACK_TECHNICAL_FORK=1' <<<"$j1_sys" && grep -qF 'Operator-only (money):' <<<"$j1_sys" \
   && grep -qF 'Say in one line why you re-sent' <<<"$j1_reason"; then
  echo "  PASS: R4 the systemMessage names the kill switch and the plain escape; the reason asks for a one-line why"; PASS=$((PASS+1))
else echo "  FAIL: R4 systemMessage/reason lack the kill switch, the plain escape or the one-line request" >&2; FAIL=$((FAIL+1)); fi

# LG1 — the ledger row carries the cue, a length and a hash and NEVER the unit text.
TOTAL=$((TOTAL+1))
lg_file="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"
lg_last="$(tail -n 1 "$lg_file" 2>/dev/null)"
if [[ -n "$lg_last" ]] && jq -e '.rule_id == "pre-closing-technical-fork-gate" and .event_type == "deny" and (.command_snippet | test("^len=[0-9]+ sha256=[0-9a-f]{64}$"))' <<<"$lg_last" >/dev/null 2>&1 \
   && ! grep -qiE 'census|credential|storage' <<<"$lg_last"; then
  echo "  PASS: LG1 a block records cue, length and sha256, never the unit text"; PASS=$((PASS+1))
else printf '  FAIL: LG1 ledger row: %s\n' "$lg_last" >&2; FAIL=$((FAIL+1)); fi

# --- bounds: unit COUNT is the scaling variable ----------------------------------------------------------
now_ms() { date +%s%N | cut -b1-13; }
TINY="$(printf 'a? %.0s' $(seq 1 700))"
TOTAL=$((TOTAL+1))
u3_t0="$(now_ms)"
SPAWNS=$((SPAWNS+1))
u3_out="$(printf '%s' "$(closing_json "$TINY")" | env SOLEUR_HOOK_TRACE=1 timeout 5 bash "$HOOK" 2>"$WORK/stderr")"; u3_rc=$?
u3_ms=$(( $(now_ms) - u3_t0 ))
RAN=$((RAN + $(grep -c '^SOLEUR_HOOK_RAN$' "$WORK/stderr")))
if [[ "$u3_rc" -eq 0 && -z "$u3_out" ]]; then printf '  PASS: U3 700 tiny units pass within the bound (%s ms; only the last 12 are judged)\n' "$u3_ms"; PASS=$((PASS+1))
else printf '  FAIL: U3 rc=%s stdout=[%s] elapsed=%s ms\n' "$u3_rc" "$u3_out" "$u3_ms" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
t1_unit="$(printf 'the existing census covers the whole inventory of probes and all the rest of it, %.0s' $(seq 1 8))is the existing census enough to close the g2 issue?"
t30="$(printf '%s\n' "$(printf 'The probe run is recorded and the rest is queued for the next window. %.0s' $(seq 1 420))")"
t60="$t30 $t30"
t1_a0="$(now_ms)"; spawn "$HOOK" "$(closing_json "$t30 $B1")"; t1_a=$(( $(now_ms) - t1_a0 )); t1_va="$(verdict_from_out)"
t1_b0="$(now_ms)"; spawn "$HOOK" "$(closing_json "$t60 $B1")"; t1_b=$(( $(now_ms) - t1_b0 )); t1_vb="$(verdict_from_out)"
spawn "$HOOK" "$(closing_json "$t1_unit")"; t1_vc="$(verdict_from_out)"
if [[ "$t1_va" == "block" && "$t1_vb" == "block" ]] && (( t1_b <= 5 * t1_a + 3000 )) && (( t1_b < 10000 )) && [[ "$t1_vc" == "block" || "$t1_vc" == "pass" ]]; then
  printf '  PASS: T1 a 30 KB and a 60 KB closing both block and scale linearly (%s ms vs %s ms)\n' "$t1_a" "$t1_b"; PASS=$((PASS+1))
else printf '  FAIL: T1 30KB=%s ms (%s) 60KB=%s ms (%s)\n' "$t1_a" "$t1_va" "$t1_b" "$t1_vb" >&2; FAIL=$((FAIL+1)); fi

# --- registration (P1, AC1) ------------------------------------------------------------------------
TOTAL=$((TOTAL+1))
p1_reg="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("pre-closing-technical-fork-gate"))) | length' "$SETTINGS" 2>/dev/null)"
p1_to="$(jq -r '[.hooks.Stop[]?.hooks[]? | select(.command | test("pre-closing-technical-fork-gate")) | .timeout] | first // 0' "$SETTINGS" 2>/dev/null)"
p1_cnt="$(grep -c 'pre-closing-technical-fork-gate' "$SETTINGS")"
p1_led="$(grep -cF 'claude-settings'"$TAB"'.claude/hooks/pre-closing-technical-fork-gate.sh'"$TAB"'Stop' "$LEDGER_TSV")"
if [[ "$p1_reg" == "1" && "$p1_cnt" == "1" && "$p1_to" == "10" && "$p1_led" == "1" && -x "$HOOK" ]]; then
  echo "  PASS: P1 registered once under Stop with a 10 s timeout, ledger row present, exec bit set"; PASS=$((PASS+1))
else printf '  FAIL: P1 registrations=%s count=%s timeout=%s ledger=%s\n' "$p1_reg" "$p1_cnt" "$p1_to" "$p1_led" >&2; FAIL=$((FAIL+1)); fi

# --- Guard 2: one definition site, two callers (derived from the tree, never from a remembered list) ----
# `files` are tracked files under both hook directories (the plugin dir is included so a graduation PR does not
# have to rewrite the guard that protects it); a stale-exemption floor requires the derived caller set to be
# non-empty, so a census over nothing cannot pass.
census_defs() { local f; for f in "$@"; do grep -qE '^RULING_[A-Z_]*_RE=' "$f" 2>/dev/null && printf '%s\n' "$f"; done; return 0; }
census_callers() { local f; for f in "$@"; do case "$f" in *.test.sh|*/lib/technical-fork-cues.sh) continue ;; esac; grep -qE '(^|[^A-Za-z_])tfc_is_fork([^A-Za-z_]|$)' "$f" 2>/dev/null && printf '%s\n' "$f"; done; return 0; }
TRACKED="$(git -C "$REPO_ROOT" ls-files -- .claude/hooks plugins/soleur/hooks | grep -E '\.sh$' | sed "s|^|$REPO_ROOT/|")"
TRACKED_ARR=(); while IFS= read -r tr_f; do TRACKED_ARR+=("$tr_f"); done <<<"$TRACKED"
TOTAL=$((TOTAL+1))
c_defs="$(census_defs "${TRACKED_ARR[@]}")"; c_callers="$(census_callers "${TRACKED_ARR[@]}")"
c_ndefs="$(grep -c . <<<"$c_defs")"; c_ncallers="$(grep -c . <<<"$c_callers")"
if [[ "$c_defs" == "$REPO_ROOT/.claude/hooks/lib/technical-fork-cues.sh" && "$c_ndefs" == "1" && "$c_ncallers" -ge 2 ]] \
   && grep -qF '/pre-ask-technical-fork-gate.sh' <<<"$c_callers" && grep -qF '/pre-closing-technical-fork-gate.sh' <<<"$c_callers"; then
  echo "  PASS: C1 exactly one RULING_*_RE definition site (the lib) and both hooks call tfc_is_fork"; PASS=$((PASS+1))
else printf '  FAIL: C1 definition sites=[%s] callers=[%s]\n' "$(tr '\n' ' ' <<<"$c_defs")" "$(tr '\n' ' ' <<<"$c_callers")" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
c_fn="$(for f in "${TRACKED_ARR[@]}"; do grep -qE '^tfc_is_fork\(\)' "$f" 2>/dev/null && printf '%s\n' "$f"; done)"
c_tfc="$(for f in "${TRACKED_ARR[@]}"; do grep -qE '^TFC_[A-Z0-9_]*_RE=' "$f" 2>/dev/null && printf '%s\n' "$f"; done)"
if [[ "$c_fn" == "$REPO_ROOT/.claude/hooks/lib/technical-fork-cues.sh" && "$c_tfc" == "$REPO_ROOT/.claude/hooks/lib/technical-fork-cues.sh" ]]; then
  echo "  PASS: C3 the verdict function and every TFC_*_RE cue are defined in exactly one file (the lib)"; PASS=$((PASS+1))
else printf '  FAIL: C3 function sites=[%s] TFC cue sites=[%s]\n' "$(tr '\n' ' ' <<<"$c_fn")" "$(tr '\n' ' ' <<<"$c_tfc")" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
c_last="$(grep -vE '^[[:space:]]*(#|$)' "$LIB" | tail -n 1)"
if [[ "$c_last" == "_TFC_COMPLETE=1" ]]; then echo "  PASS: C4 the completion sentinel is the last statement of the lib"; PASS=$((PASS+1))
else printf '  FAIL: C4 the last statement of the lib is [%s], not the completion sentinel\n' "$c_last" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
c_lib_dirty="$(grep -vE '^[[:space:]]*#' "$LIB" | grep -ciE 'emit_incident|\.claude/|CLAUDE_PROJECT_DIR|soleur|hcloud|g2' || true)"
if [[ "$c_lib_dirty" == "0" ]]; then echo "  PASS: C2 the lib is pure: no emit_incident, no repo path, no repo-specific noun"; PASS=$((PASS+1))
else printf '  FAIL: C2 the lib carries %s impure or repo-specific line(s)\n' "$c_lib_dirty" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
v8_pinned='\b(prices?|pricing|plans?|tiers?|launch(es)?|dates?|deadlines?|licen[sc]es?|vendors?|logos?|copy|landing|budgets?|costs?|spend|revenue|invoices?|refunds?|schedules?|priorit(y|ies)|brand|hero|merge|deploy|ship|releases?|delete|prod|production)\b'
# shellcheck disable=SC1090  # the lib path is a parameter: this reads the pristine and the mutant lib
v8_of() { ( . "$1" 2>/dev/null; printf '%s' "${RULING_OPVOCAB_RE:-}" ); }
if [[ "$(v8_of "$LIB")" == "$v8_pinned" ]]; then echo "  PASS: V8 RULING_OPVOCAB_RE in the lib is byte-equal to the pinned literal"; PASS=$((PASS+1))
else echo "  FAIL: V8 RULING_OPVOCAB_RE drifted from the pinned literal" >&2; FAIL=$((FAIL+1)); fi
HB1="how strict should the evidence bar be?"
row "G2h a SHARED phrasing still blocks through the closing hook" block "$HB1"
TOTAL=$((TOTAL+1))
g2h_dec="$(qq="$HB1"; jq -nc --arg q "$qq" '{tool_name:"AskUserQuestion", cwd:".", session_id:"t", tool_input:{questions:[{question:$q, options:[{label:"Yes",description:"go"},{label:"No",description:"stop"}]}]}}' | bash "$PREASK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
if [[ "$g2h_dec" == "deny" ]]; then echo "  PASS: G2h the same SHARED phrasing still denies through the pre-ask hook (a stub lib cannot satisfy the census)"; PASS=$((PASS+1))
else printf '  FAIL: G2h pre-ask decision=%s\n' "$g2h_dec" >&2; FAIL=$((FAIL+1)); fi

# --- the MUTATION machinery ---------------------------------------------------------------------------
mk_tree() { # <id> -> sets TREE to a fresh tree holding the hook, the pre-ask hook and every lib file
  TREE="$WORK/tree-$1"; assert_fixture_dir "$TREE"
  mkdir -p "$TREE/lib" || return 1
  cp "$HOOKS_DIR"/lib/*.sh "$TREE/lib/" || return 1
  cp "$HOOK" "$TREE/pre-closing-technical-fork-gate.sh" || return 1
  cp "$PREASK" "$TREE/pre-ask-technical-fork-gate.sh" || return 1
}
apply_mut() { # <file> <old> <new>: 0 only if the mutation LANDED and the mutant still parses
  local f="$1" old="$2" new="$3" content
  content="$(cat "$f"; printf x)"; content="${content%x}"
  [[ "$content" == *"$old"* ]] || return 1
  assert_fixture_dir "$f"
  printf '%s' "${content/"$old"/"$new"}" > "$f" || return 1
  bash -n "$f" 2>/dev/null
}
# Self-test of the applier: an absent anchor and an unparseable result must both be REFUSED, or a mutation that
# did not land would report the baseline, which is indistinguishable from a pass.
TOTAL=$((TOTAL+1))
am_f="$WORK/am-probe.sh"; assert_fixture_dir "$am_f"; printf 'echo one\n' > "$am_f"
apply_mut "$am_f" "absent anchor" "x"; am_a=$?
apply_mut "$am_f" "echo one" "if then"; am_b=$?
assert_fixture_dir "$am_f"; printf 'echo one\n' > "$am_f"; apply_mut "$am_f" "echo one" "echo two"; am_c=$?
if [[ "$am_a" -ne 0 && "$am_b" -ne 0 && "$am_c" -eq 0 ]]; then echo "  PASS: H4 the mutation applier refuses an absent anchor and an unparseable mutant"; PASS=$((PASS+1))
else printf '  FAIL: H4 applier rc: absent=%s unparseable=%s ok=%s\n' "$am_a" "$am_b" "$am_c" >&2; FAIL=$((FAIL+1)); fi

KILLED=0
# mut_row <label> <hook|lib> <old> <new> <expect> <message> [active]: control gives <expect>, the mutant does not
mut_row() {
  local label="$1" which="$2" old="$3" new="$4" expect="$5" msg="$6" active="${7:-false}" raw="${8:-}" target pristine ctl got mut_input
  TOTAL=$((TOTAL+1))
  mk_tree "${label//[^A-Za-z0-9]/_}" || { printf '  FAIL: %s — could not build the tree\n' "$label" >&2; FAIL=$((FAIL+1)); return 0; }
  case "$which" in hook) target="$TREE/pre-closing-technical-fork-gate.sh"; pristine="$HOOK" ;; lib) target="$TREE/lib/technical-fork-cues.sh"; pristine="$LIB" ;; *) echo "FATAL: bad mutation target" >&2; exit 2 ;; esac
  mut_input="$(closing_json "$msg" "$active")"; [[ -n "$raw" ]] && mut_input="$raw"
  spawn "$TREE/pre-closing-technical-fork-gate.sh" "$mut_input"; ctl="$(verdict_from_out)"
  if ! apply_mut "$target" "$old" "$new"; then printf '  FAIL: %s — the mutation did not land or the mutant does not parse\n' "$label" >&2; FAIL=$((FAIL+1)); return 0; fi
  if cmp -s "$pristine" "$target"; then printf '  FAIL: %s — the mutant is byte-identical to the pristine file\n' "$label" >&2; FAIL=$((FAIL+1)); return 0; fi
  spawn "$TREE/pre-closing-technical-fork-gate.sh" "$mut_input"; got="$(verdict_from_out)"
  # A mutant that CRASHES (a bash diagnostic on stderr) fails open to "pass" and would be miscounted as killed.
  if grep -qE '(^|: )line [0-9]+: ' <<<"$ERR"; then printf '  FAIL: %s — the mutant crashed (bash diagnostic), not a behavioural kill: %s\n' "$label" "$(head -c 160 <<<"$ERR")" >&2; FAIL=$((FAIL+1)); return 0; fi
  if [[ "$ctl" == "$expect" && "$got" != "$expect" && "$got" != "bad" ]]; then printf '  PASS: %s killed (control %s, mutant %s)\n' "$label" "$ctl" "$got"; PASS=$((PASS+1)); KILLED=$((KILLED+1))
  else printf '  FAIL: %s — control=%s mutant=%s want control %s and a different mutant verdict\n' "$label" "$ctl" "$got" "$expect" >&2; FAIL=$((FAIL+1)); fi
  return 0
}

HOOK_DISPATCH='tfc_is_fork "$u" shared+closing'
mut_row "G1-1a dispatch -> false: B1" hook "$HOOK_DISPATCH" 'false' block "$STATUS $B1"
mut_row "G1-1b dispatch -> false: B2" hook "$HOOK_DISPATCH" 'false' block "$STATUS $B2"
mut_row "G1-1c dispatch -> false: B3" hook "$HOOK_DISPATCH" 'false' block "$STATUS $B3"
mut_row "G1-2 delete the permission exemption" lib 'grep -qE "$RULING_PERM_RE" <<<"$unit" && return 1' ':' pass "may i rotate the keys, and in what order?"
mut_row "G1-3 delete the loop-guard exit" hook '[[ "$ACTIVE" == "false" ]] || {' ': || {' pass "$STATUS $B3" true
mut_row "G1-4 judge only the first unit" hook 'for (( k = START; k < COUNT; k++ )); do' 'for (( k = START; k < START + 1 && k < COUNT; k++ )); do' block "Do you authorize the rotation? Also, what is the best design for the migration?"
mut_row "G1-5 veto CLOSING cues with BUSINESS|ACTION" lib "TFC_BUSINESS_RE='\\b('\"\${TFC_BUSINESS_WORDS}\"')\\b'" "TFC_BUSINESS_RE='\\b('\"\${TFC_BUSINESS_WORDS}|\${TFC_ACTION_WORDS}\"')\\b'" block "$STATUS $B2"
mut_row "G1-6 remove the BUSINESS veto" lib "TFC_BUSINESS_RE='\\b('\"\${TFC_BUSINESS_WORDS}\"')\\b'" "TFC_BUSINESS_RE='\\bzzzneverwordzzz\\b'" pass "$STATUS what is the best design for the pricing page?"
mut_row "G1-7a a fail-open arm blocks: bad JSON" hook '_note "SKIPPED — input is not a JSON object"; exit 0;' 'printf "{\"decision\":\"block\",\"reason\":\"x\"}\n"; exit 0;' pass "$STATUS" false '{not json'
mut_row "G1-8a delete the stop escape" hook "grep -qE '<stop>(operator-gate|blocked):" "grep -qE '<stop>(zzznever|zzznever2):" pass "$STATUS $B1 <stop>BLOCKED: waiting on the registry owner.</stop>"
mut_row "G1-8b drop the empty-label exclusion" hook 'if [[ -n "$CONTENT" ]] && ! [[ "$CONTENT" =~ ^(none|na|nothing|no|nil)$ ]]; then exit 0; fi' 'if [[ -n "$FINAL_SENT" ]]; then exit 0; fi' block "$STATUS $B1 Blocked: none."
mut_row "G1-9a remove the quoted-line strip" hook '/^[[:space:]]*>/ { next }' '' pass "$STATUS
> $B1
That quote is the hook's own fixture."
mut_row "G1-9b remove the code-span strip" hook 'gsub(/`[^`]*`/, ""); ' '' pass "$STATUS \`$B1\` is the phrase the hook quotes."
mut_row "G1-10 Operator-only escapes the whole window" hook 'declare -a JUDGE=()' 'grep -q "^U1" <<<"$UNITS" && exit 0; declare -a JUDGE=()' block "Operator-only (money): should we charge for the second seat now?

$B1"
# F3 needs its own mutant: make the absent-loop-guard arm block.
G17B_RAW="$(jq -nc --arg m "$B1" '{last_assistant_message:$m}')"
mut_row "G1-7b a fail-open arm blocks: absent loop guard" hook '_note "SKIPPED — stop_hook_active absent, the once-per-turn guard cannot be verified"; exit 0;' 'printf "{\"decision\":\"block\",\"reason\":\"x\"}\n"; exit 0;' pass "$STATUS" false "$G17B_RAW"
# (G1-7a/b feed the raw stdin the F2 and F3 rows use: the unmutated arm must PASS it and the mutant blocks it, which
#  proves each arm, not the cue list, is what keeps those rows green.)

# G1-11: the judged-unit cap. The mutant must EXCEED the time bound on 700 tiny units; the control must not.
TOTAL=$((TOTAL+1))
mk_tree g1_11 || true
g11_target="$TREE/pre-closing-technical-fork-gate.sh"
if apply_mut "$g11_target" 'if (( COUNT > 12 )); then START=$((COUNT - 12));' 'if (( COUNT > 100000 )); then START=$((COUNT - 12));' && ! cmp -s "$HOOK" "$g11_target"; then
  SPAWNS=$((SPAWNS+1))
  printf '%s' "$(closing_json "$TINY")" | env SOLEUR_HOOK_TRACE=1 timeout 5 bash "$g11_target" >/dev/null 2>"$WORK/stderr"; g11_rc=$?
  RAN=$((RAN + $(grep -c '^SOLEUR_HOOK_RAN$' "$WORK/stderr")))
  if [[ "$g11_rc" -eq 124 && "$u3_rc" -eq 0 ]]; then echo "  PASS: G1-11 killed (the control finished; the uncapped mutant exceeded 5 s)"; PASS=$((PASS+1)); KILLED=$((KILLED+1))
  else printf '  FAIL: G1-11 mutant rc=%s control rc=%s (want 124 and 0)\n' "$g11_rc" "$u3_rc" >&2; FAIL=$((FAIL+1)); fi
else echo "  FAIL: G1-11 the mutation did not land" >&2; FAIL=$((FAIL+1)); fi

mut_row "G1-13 drop the leading-fragment drop" hook 'if (NR == 1 && cut == 1) {' 'if (NR == 1 && cut == 99) {' pass "pricing $W1_X$W1_RUNON"
mut_row "G1-14 narrow the window to 800 bytes" hook "tail -c 1500)\"" "tail -c 800)\"" block "$B1
$(PADLINE 15)"
mut_row "G1-15 judge the FIRST 12 units instead of the last 12" hook 'if (( COUNT > 12 )); then START=$((COUNT - 12));' 'if (( COUNT > 12 )); then START=0; COUNT=12;' pass "$B1 $TINY12"
mut_row "G1-16 never reset the Operator-only cover on a blank line" hook '    if (line ~ /^ *$/) { esc = 0; next }' '    if (line ~ /^ *$/) { next }' block "Operator-only (money): the accounting call is below.

$B1"
# G1-12: delete the closing-only permission exemption (Q4): an authorization shape the shared vocabulary does not name must flip pass -> block.
mut_row "G1-12 delete the closing-only permission exemption" lib '[[ "$closing" -eq 1 ]] && grep -qE "$TFC_CLOSING_PERM_RE" <<<"$unit" && return 1' ':' pass "can i merge pr 123 now, is the evidence enough?"

# G2-1: a second RULING_*_RE definition in the closing hook must make the census report two sites.
TOTAL=$((TOTAL+1))
mk_tree g2_1 || true
g21_nl=$'\n'
if apply_mut "$TREE/pre-closing-technical-fork-gate.sh" 'LC_ALL=C' "LC_ALL=C${g21_nl}RULING_PERM_RE='(x)'" ; then
  g21_files=(); while IFS= read -r g21_f; do g21_files+=("$g21_f"); done < <(find "$TREE" -name '*.sh' -type f)
  g21_defs="$(census_defs "${g21_files[@]}" | grep -c .)"
  if [[ "$g21_defs" == "2" ]]; then echo "  PASS: G2-1 killed (the census reports a second definition site)"; PASS=$((PASS+1)); KILLED=$((KILLED+1))
  else printf '  FAIL: G2-1 census saw %s definition site(s), want 2\n' "$g21_defs" >&2; FAIL=$((FAIL+1)); fi
else echo "  FAIL: G2-1 the mutation did not land" >&2; FAIL=$((FAIL+1)); fi

preask_dec() { # <hook> <json> -> allow | deny
  local o; o="$(printf '%s' "$2" | bash "$1" 2>/dev/null)"
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${o:-{\}}" 2>/dev/null || echo allow
}
# G2-2: a lib that ignores its group argument must widen the pre-ask hook, which NR2a in the pre-ask suite forbids; the
# same pre-ask row is driven here against the mutant.
TOTAL=$((TOTAL+1))
mk_tree g2_2 || true
g22_json="$(jq -nc --arg q "what is the right design for the retry queue?" '{tool_name:"AskUserQuestion", cwd:".", session_id:"t", tool_input:{questions:[{question:$q, options:[{label:"Yes",description:"go"},{label:"No",description:"stop"}]}]}}')"
g22_ctl="$(preask_dec "$TREE/pre-ask-technical-fork-gate.sh" "$g22_json")"
if apply_mut "$TREE/lib/technical-fork-cues.sh" '    shared) ;;' '    shared) closing=1 ;;'; then
  g22_mut="$(preask_dec "$TREE/pre-ask-technical-fork-gate.sh" "$g22_json")"
  if [[ "$g22_ctl" == "allow" && "$g22_mut" == "deny" ]]; then echo "  PASS: G2-2 killed (control allow, a group-ignoring lib denies)"; PASS=$((PASS+1)); KILLED=$((KILLED+1))
  else printf '  FAIL: G2-2 control=%s mutant=%s\n' "$g22_ctl" "$g22_mut" >&2; FAIL=$((FAIL+1)); fi
else echo "  FAIL: G2-2 the mutation did not land" >&2; FAIL=$((FAIL+1)); fi

# G2-3: dropping a BUSINESS member in the lib must break the byte-equality row.
TOTAL=$((TOTAL+1))
mk_tree g2_3 || true
if apply_mut "$TREE/lib/technical-fork-cues.sh" '|brand|hero' '|brand'; then
  if [[ "$(v8_of "$TREE/lib/technical-fork-cues.sh")" != "$v8_pinned" && "$(v8_of "$LIB")" == "$v8_pinned" ]]; then echo "  PASS: G2-3 killed (the byte-equality row notices a dropped veto member)"; PASS=$((PASS+1)); KILLED=$((KILLED+1))
  else echo "  FAIL: G2-3 the byte-equality row did not notice the dropped member" >&2; FAIL=$((FAIL+1)); fi
else echo "  FAIL: G2-3 the mutation did not land" >&2; FAIL=$((FAIL+1)); fi

# H1 — neuter the decider the row helper consults: the must-PASS rows (authorization variants that are NOT the
# canonical sentence) must redden, which a RED-only matrix cannot show.
TOTAL=$((TOTAL+1))
h1_probe() { ( PASS=0; FAIL=0; TOTAL=0; DECIDER=decide_always_block
    row "h1a" pass "May I merge PR 123?" >/dev/null 2>&1
    row "h1b" pass "Approve the rotation order?" >/dev/null 2>&1
    row "h1c" pass "Do you authorize the rotation in what order?" >/dev/null 2>&1
    printf '%s/%s' "$PASS" "$FAIL" ); }
h1_res="$(h1_probe)"
if [[ "$h1_res" == "0/3" ]]; then echo "  PASS: H1 a decider that always says block reddens all three must-PASS authorization rows"; PASS=$((PASS+1))
else printf '  FAIL: H1 neutered decider scored %s (want 0/3)\n' "$h1_res" >&2; FAIL=$((FAIL+1)); fi

# --- dispatch non-vacuity: the named must-block rows were blocked with THIS hook's reason, and every spawn ran the SUT ---
TOTAL=$((TOTAL+1))
d_missing=""
D_NAMES="B1 B2 B3 B4 B5a B5b B5c B6 B7 U1 E3b E4 E5b E5c E5d U2b E4b E4c E6a"
for d_r in $D_NAMES; do
  d_found=0
  for d_n in $BLOCKED_BY_THIS_HOOK; do [[ "$d_n" == "$d_r" ]] && d_found=1; done
  [[ "$d_found" -eq 1 ]] || d_missing="$d_missing $d_r"
done
if [[ -z "$d_missing" && "$RAN" -eq "$SPAWNS" && "$SPAWNS" -ge 70 ]]; then
  printf '  PASS: V5 all %s named must-block rows were blocked by this hook'"'"'s reason; the SUT ran %s of %s spawns\n' "$(wc -w <<<"$D_NAMES" | tr -d ' ')" "$RAN" "$SPAWNS"; PASS=$((PASS+1))
else printf '  FAIL: V5 missing=[%s] SUT markers=%s harness spawns=%s (want equal and >= 70)\n' "$d_missing" "$RAN" "$SPAWNS" >&2; FAIL=$((FAIL+1)); fi
TOTAL=$((TOTAL+1))
if [[ "$KILLED" -ge 24 ]]; then printf '  PASS: V6 %s mutants killed (floor 24)\n' "$KILLED"; PASS=$((PASS+1))
else printf '  FAIL: V6 only %s mutants killed (floor 24)\n' "$KILLED" >&2; FAIL=$((FAIL+1)); fi

# --- inventory, accounting conservation and the assertion floor ---------------------------------------
TOTAL=$((TOTAL+1))
if [[ "$TOTAL" -eq 128 ]]; then echo "  PASS: V1 full inventory ran (128 cases)"; PASS=$((PASS+1))
else echo "  FAIL: V1 expected 128 cases, ran $TOTAL" >&2; FAIL=$((FAIL+1)); fi

# Reported with printf + exit 1, never through a verdict helper: a floor routed through the machinery it backstops
# is disarmed by the same edit it exists to catch (ADR-193).
if (( PASS + FAIL != TOTAL )); then
  printf '\nFATAL: accounting: PASS(%d) + FAIL(%d) != TOTAL(%d) — a case was counted but landed in neither bucket, or in both.\n' \
    "$PASS" "$FAIL" "$TOTAL" >&2
  exit 1
fi
MIN_CASES=128
if (( TOTAL < MIN_CASES )); then
  printf '\nFATAL: anti-vacuity: %d case(s) ran, floor is %d. The suite shrank rather than the hook improving.\n' \
    "$TOTAL" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
