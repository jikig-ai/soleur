#!/usr/bin/env bash
# Fixture tests for pre-ask-technical-fork-gate.sh.
#
# The gate sits in front of the ONE tool that stalls a pipeline waiting on a human, so both
# directions are load-bearing and neither is the "happy path":
#   a wrongly-ALLOWED investigative question costs a stalled pipeline and an operator guess;
#   a wrongly-DENIED authorization question costs a production action taken without consent.
# The second is worse, which is why the gate requires an investigative signal AND the absence of
# any authority signal, and why the A-cases below outnumber the D-cases.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only) but the two headline cases are
# verbatim from 2026-08-19: D1 is the question that prompted this hook, A1 is the ack-destroy
# authorization from the same session that must keep working.
set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-ask-technical-fork-gate.sh"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/technical-fork-cues.sh"
PASS=0; FAIL=0; TOTAL=0
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
[[ -x "$HOOK" ]] || { echo "FATAL: hook not executable at $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }

# payload <question> <label1> <desc1> [<label2> <desc2>]
payload() {
  jq -nc --arg q "$1" --arg l1 "${2:-}" --arg d1 "${3:-}" --arg l2 "${4:-}" --arg d2 "${5:-}" '
    {tool_name:"AskUserQuestion", cwd:".", session_id:"t",
     tool_input:{questions:[{question:$q, options:[{label:$l1,description:$d1},{label:$l2,description:$d2}]}]}}'
}

run_case() { # name expect(allow|deny) payload...
  local name="$1" expect="$2"; shift 2
  TOTAL=$((TOTAL+1))
  local out dec
  out=$(payload "$@" | "$HOOK" 2>/dev/null)
  dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null || echo allow)
  if [[ "$dec" == "$expect" ]]; then printf '  PASS: %s (%s)\n' "$name" "$dec"; PASS=$((PASS+1))
  else printf '  FAIL: %s — got %s want %s\n' "$name" "$dec" "$expect" >&2; FAIL=$((FAIL+1)); fi
}

echo "== pre-ask-technical-fork-gate =="

# --- DENY: investigative forks the agent must resolve itself ---------------------------------
run_case "D1 the verbatim 2026-08-19 question" deny \
  "How should I resolve the cutover path?" \
  "Read the runbook properly first" "Find the documented order for a cold host rather than reasoning it out from guard comments." \
  "Ask whoever owns the cutover section" "The plan deferred the cutover window to numbered steps I have not read."
run_case "D2 which file to inspect" deny \
  "Which source should I check?" "Check whether the ADR says" "look at the decision record" "Grep the codebase" "search the repo for callers"
run_case "D3 hypothesis selection" deny \
  "How do we find the cause?" "Investigate the pooler" "diagnose the connection path" "Look into the guard" "read the guard comments"

# D4 — BEHAVIOURAL, and the reason it is not a grep on the hook source.
#
# An outside expert's question (accountant / lawyer / auditor / insurer / bank / regulator /
# landlord) is a dead end at the founder too: they cannot answer it either. The hook's
# EXTERNAL_EXPERT arm denies it and names the skill that writes the questions instead.
#
# Asserting only that the skill's NAME appears in the hook file would have passed against the
# design this replaced. The name was present, in rung 5 of the investigative REASON ladder, and the
# deny was UNREACHABLE: AUTHORITY_RE is evaluated first and wins outright on cost / budget / price /
# priorit / scope / schedule / spend, which this class carries in the same breath, and the surviving
# path then also requires INVESTIGATIVE_RE, which this class never matches. So the payload below
# deliberately carries "cost" in an option description — it passes only if the expert arm is
# evaluated AHEAD of the authority short-circuit. Decision AND reason are both asserted; a deny
# carrying a reason that does not route anywhere is the same dead end wearing a hook's clothes.
#
# Both halves of the routing claim are checked here rather than in two cases, so the inventory
# below moves by one: the dedicated arm, and rung 5 of the ladder the investigative path emits.
TOTAL=$((TOTAL+1))
expert_out=$(payload "Should we treat the plugin revenue as capex or opex this year?" \
  "Capex" "capitalise it and carry the cost forward across future years" \
  "Opex" "expense the whole amount in the current year" | "$HOOK" 2>/dev/null)
expert_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${expert_out:-{\}}" 2>/dev/null || echo allow)
expert_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${expert_out:-{\}}" 2>/dev/null || echo "")
ladder_out=$(payload "How should I resolve the cutover path?" \
  "Read the runbook properly first" "find the documented order rather than reasoning it out" \
  "Ask whoever owns the cutover section" "the plan deferred it to numbered steps I have not read" | "$HOOK" 2>/dev/null)
ladder_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${ladder_out:-{\}}" 2>/dev/null || echo "")
if [[ "$expert_dec" == "deny" ]] \
   && grep -qF 'instead: soleur:questionnaire-generate' <<<"$expert_reason" \
   && grep -qE '^ +5\. If the answer is held OUTSIDE the company' <<<"$ladder_reason" \
   && grep -qF 'soleur:questionnaire-generate' <<<"$ladder_reason"; then
  echo "  PASS: D4 outside-expert question denied AND routed to soleur:questionnaire-generate (arm + ladder rung 5)"; PASS=$((PASS+1))
else
  printf '  FAIL: D4 outside-expert routing — decision was %s; arm reason named the skill: %s; ladder rung 5 present: %s\n' \
    "$expert_dec" \
    "$(grep -qF 'instead: soleur:questionnaire-generate' <<<"$expert_reason" && echo yes || echo no)" \
    "$(grep -qE '^ +5\. If the answer is held OUTSIDE the company' <<<"$ladder_reason" && echo yes || echo no)" >&2
  FAIL=$((FAIL+1))
fi

# --- ALLOW: real operator decisions --------------------------------------------------------
run_case "A1 the ack-destroy authorization from the same session" allow \
  "This merge fires a production apply. How do you want to proceed?" \
  "Merge WITH [ack-destroy]" "Authorizes replacing terraform_data.journald_persistent on production web-1." \
  "Hold" "Leave the PR open."
run_case "A2 destructive host replace" allow \
  "Dispatch the host replace?" "Replace the host" "destroys and re-creates the production inngest host" "Wait" "leave it dark"
run_case "A3 cost" allow \
  "This adds a recurring vendor cost. Proceed?" "Approve the spend" "about 20 EUR/month" "Decline" "find a free tier"
run_case "A4 scope/priority" allow \
  "Which should I do first?" "Fix the P1" "priority order" "Ship the feature" "scope for this milestone"
# The mixed case is the one a careless implementation gets wrong: an authorization that happens
# to mention reading something must still reach the operator.
run_case "A5 MIXED — authorization that also mentions reading" allow \
  "Merge with [ack-destroy], or investigate further?" \
  "Merge with [ack-destroy]" "authorize the production apply" \
  "Investigate first" "read the runbook before merging"

# --- ALLOW: not our tool / empty ------------------------------------------------------------
TOTAL=$((TOTAL+1))
out=$(jq -nc '{tool_name:"Bash",cwd:".",tool_input:{command:"read the runbook"}}' | "$HOOK" 2>/dev/null)
if [[ -z "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"${out:-{\}}" 2>/dev/null)" ]]; then
  echo "  PASS: N1 non-AskUserQuestion tool is untouched"; PASS=$((PASS+1))
else echo "  FAIL: N1 hook fired on the wrong tool" >&2; FAIL=$((FAIL+1)); fi

# --- Devin wire name (kind map, #8205): ask_user_question reaches the gate ---
TOTAL=$((TOTAL+1))
out=$(jq -nc '{tool_name:"ask_user_question",cwd:".",tool_input:{questions:[{question:"Which source should I check?",options:[{label:"Check the ADR",description:"look at the decision record"}]}]}}' | "$HOOK" 2>/dev/null)
if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null)" == "deny" ]]; then
  echo "  PASS: N2 Devin ask_user_question reaches the gate (deny)"; PASS=$((PASS+1))
else echo "  FAIL: N2 Devin ask_user_question did not reach the gate" >&2; FAIL=$((FAIL+1)); fi

# --- the hatch -------------------------------------------------------------------------------
TOTAL=$((TOTAL+1))
out=$(payload "How?" "Read the runbook" "read the runbook first" "Ask the owner" "ask the owner" | SOLEUR_ACK_TECHNICAL_FORK=1 "$HOOK" 2>/dev/null)
if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null)" == "allow" ]] \
   && grep -q 'SOLEUR_ACK_TECHNICAL_FORK' <<<"${out:-}"; then
  echo "  PASS: H1 hatch allows AND announces itself"; PASS=$((PASS+1))
else echo "  FAIL: H1 hatch silent or ineffective" >&2; FAIL=$((FAIL+1)); fi

# --- anti-vacuity ----------------------------------------------------------------------------
# D5 — the OTHER DIRECTION of D4, which D4 alone cannot see.
#
# D4 fixtures the direction where a weak implementation under-fires: it proves the expert arm is
# reachable. Every fixture pointed that way passes just as well against an arm that fires on
# EVERYTHING, and this arm is evaluated BEFORE the authority short-circuit and DENIES — so an
# over-broad token silently converts legitimate authorization questions into refusals. That is the
# one direction this hook's header otherwise refuses to fail in, so it gets its own case.
#
# Both inputs below were measured as FALSE POSITIVES against the arm as first written and are the
# reason the pattern changed: a leading-only `\btax` accepts "taxonomy" (it rejects "syntax" only
# because there is no boundary before "tax" there), and `statutory` is ambient in this repository's
# own compliance prose while identifying no profession. The assertion is scoped to the expert arm's
# own sentinel rather than to overall allow, so an unrelated arm denying for an unrelated reason
# cannot make this case pass or fail for the wrong reason.
TOTAL=$((TOTAL+1))
neg_fp=0
# Six cases, not two, and that distinction is the finding. The first two are the tokens that were
# trimmed by hand; the last four were measured by the review panel AFTER that trim, on the same axis
# — `\bregulator` accepting "regulatory", `\bauditor` accepting the shipped agent name
# `legal-compliance-auditor`, `\bamorti[sz]` accepting "amortized", `\binsurance\b` accepting
# "insurance-claims". A control that covers only the tokens someone already noticed pins the
# INSTANCES; these six pin the PREDICATE, because every one of them carries an authorization verb
# or a right-anchoring failure and none of them names a profession.
for neg_q in "Should we rename the event taxonomy before the launch?" \
             "Approve the statutory breach-notification clock change?" \
             "Approve deploying the regulatory-disclosure page to prd?" \
             "Run legal-compliance-auditor before merge, or merge now?" \
             "Authorize the amortized replay-buffer rollout to production?" \
             "Merge the insurance-claims copy fix?"; do
  neg_out=$(payload "$neg_q" \
    "Yes" "go ahead with it as described" \
    "No" "leave it as it stands for now" | "$HOOK" 2>/dev/null)
  neg_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${neg_out:-{\}}" 2>/dev/null || echo "")
  if grep -qF 'instead: soleur:questionnaire-generate' <<<"$neg_reason"; then
    printf '  FAIL: D5 expert arm fired on a non-expert question: %s\n' "$neg_q" >&2
    neg_fp=$((neg_fp+1))
  fi
done
if [[ "$neg_fp" -eq 0 ]]; then
  echo "  PASS: D5 expert arm does not fire on any of 6 non-expert asks (4 of them authorization verbs)"; PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# D6 — the skill the expert arm ROUTES TO must be able to run its own first step.
#
# This is the case the suite was missing, and its absence is why 14/14 was green over an unrunnable
# skill. `soleur:questionnaire-generate` Step 1 asks the founder "Who receives this?" with options
# labelled `Accountant` / `Lawyer`, because the recipient's role is one of exactly three fields its
# `## Context` allowlist permits. So the skill is SPECIFIED to emit the string the expert arm denies,
# and the primary invocation path was a loop: deny -> invoke the skill -> the skill asks -> deny.
# The advertised override cannot break it either, because SOLEUR_ACK_TECHNICAL_FORK is read from the
# hook process environment and shell state does not persist between Bash tool calls.
#
# Both directions are asserted, because an allow arm that fires on any profession noun would be a
# bypass rather than a fix: the interview shape must ALLOW, and a real expert ask carrying no
# interview shape must still DENY.
TOTAL=$((TOTAL+1))
d6_fail=0
for d6_q in "Who receives this?" "What has to come back from them?"; do
  d6_out=$(payload "$d6_q" \
    "Accountant" "the firm that files our accounts" \
    "Lawyer" "outside counsel" | "$HOOK" 2>/dev/null)
  d6_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d6_out:-{\}}" 2>/dev/null || echo allow)
  if [[ "$d6_dec" != "allow" ]]; then
    printf '  FAIL: D6 the skill cannot run its own interview — %s was %s\n' "$d6_q" "$d6_dec" >&2
    d6_fail=$((d6_fail+1))
  fi
done
# The other direction: the arm must not have become a bypass.
d6_out=$(payload "Can you ask my accountant whether this is deductible?" \
  "Yes" "put it to them" "No" "leave it" | "$HOOK" 2>/dev/null)
d6_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d6_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d6_dec" != "deny" ]]; then
  printf '  FAIL: D6 the self-invocation arm became a bypass — a real expert ask was %s\n' "$d6_dec" >&2
  d6_fail=$((d6_fail+1))
fi
if [[ "$d6_fail" -eq 0 ]]; then
  echo "  PASS: D6 questionnaire-generate can run its own interview, and the arm is not a bypass"; PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# D7 — the interview exemption is scoped to the EXPERT ARM, and disarms nothing else.
#
# D6 asserts the exemption WORKS. It cannot see the failure mode that matters, because an exemption
# written as a standalone `if … then exit 0` block ahead of every arm satisfies D6 exactly as well as
# one written as a conjunct of the expert arm — and the standalone form is a whole-hook bypass. It was
# the shipped form until this case existed: prefixing `"Who receives this?"` to D1, the verbatim
# 2026-08-19 fork this hook was built to refuse, ALLOWED it, and the suite stayed 15/15.
#
# So D7 asserts from the other side: a corpus carrying the interview shape must still be judged by
# every arm below the expert one. Two payloads, because they fail for different reasons — the first
# carries a profession noun (so the expert arm's other conjuncts are live), the second carries none
# (so only the investigative default-deny can refuse it), and a regression in either direction shows
# up in exactly one of them.
TOTAL=$((TOTAL+1))
d7_fail=0

d7_out=$(payload "Who receives this? How should I resolve the cutover path?" \
  "Read the runbook properly first" "Find the documented order for a cold host rather than reasoning it out from guard comments." \
  "Ask whoever owns the cutover section" "The plan deferred the cutover window to numbered steps I have not read." | "$HOOK" 2>/dev/null)
d7_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d7_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d7_dec" != "deny" ]]; then
  printf '  FAIL: D7 the interview shape disarmed the INVESTIGATIVE arm — D1 prefixed with the interview phrase was %s, so the exemption is a whole-hook bypass, not a narrowing of the expert arm\n' "$d7_dec" >&2
  d7_fail=$((d7_fail+1))
fi

d7_out=$(payload "What has to come back? Which source should I check for the retry semantics?" \
  "Check whether the ADR says" "look at the decision record" \
  "Grep the codebase" "search the repo for callers" | "$HOOK" 2>/dev/null)
d7_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d7_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d7_dec" != "deny" ]]; then
  printf '  FAIL: D7 an investigative fork carrying NO profession noun was %s once the interview phrase was present — the exemption reaches arms it has no business reaching\n' "$d7_dec" >&2
  d7_fail=$((d7_fail+1))
fi

if [[ "$d7_fail" -eq 0 ]]; then
  echo "  PASS: D7 the interview exemption narrows only the expert arm; the investigative default-deny stays armed"; PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# D8 — the corpus survives a foreign OPTION SHAPE, and a partial corpus is never judged.
#
# Every other case here goes through `payload`, which emits Claude Code's own shape: each option is
# an object, `{label, description}`. A foreign harness may send a bare string instead. `.label` on a
# string is a jq ERROR: jq exits 5 having already printed the question, so the corpus came back
# NON-EMPTY with every label and description missing, the emptiness guard did not fire, and
# `2>/dev/null` ate the diagnostic. The arm then classified a question whose entire signal lives in
# the option text — which is the shape D4 exists to catch — and allowed it. Measured.
#
# Both halves are asserted. First: the signal is reachable in the string shape at all. The question
# text is deliberately contentless ("Which one?") so the ONLY thing that can produce a deny is option
# text, which is what makes this a real reachability assertion rather than a restatement of D1.
# Second: an option shape nothing can read must announce itself on stderr and allow, never allow
# silently — a partial corpus can only ever produce a false allow, so it must not be judged.
TOTAL=$((TOTAL+1))
d8_fail=0

d8_out=$(printf '%s' '{"tool_name":"AskUserQuestion","cwd":".","session_id":"t","tool_input":{"questions":[{"question":"Which one?","options":["Read the runbook properly first","Ask whoever owns the cutover section"]}]}}' \
  | "$HOOK" 2>/dev/null)
d8_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d8_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d8_dec" != "deny" ]]; then
  printf '  FAIL: D8 option-as-string shape was %s — the label/description text is being dropped, so every arm classifies a TRUNCATED corpus and can only fail toward a false allow\n' "$d8_dec" >&2
  d8_fail=$((d8_fail+1))
fi

# An options value that is neither an object nor a string: unreadable, so it must be announced.
d8_err=$(printf '%s' '{"tool_name":"AskUserQuestion","cwd":".","session_id":"t","tool_input":{"questions":[{"question":"How should I resolve the cutover path?","options":[[1,2]]}]}}' \
  | "$HOOK" 2>&1 >/dev/null)
if ! grep -q 'corpus extraction failed' <<<"$d8_err"; then
  printf '  FAIL: D8 an unreadable options shape produced no stderr breadcrumb — a could-not-measure is being reported as a clean measurement\n' >&2
  d8_fail=$((d8_fail+1))
fi

if [[ "$d8_fail" -eq 0 ]]; then
  echo "  PASS: D8 option text is reachable in a foreign shape, and an unreadable corpus announces itself"; PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# D9 — the expert arm's exemption is scoped to the QUESTION, and the verbs that exempt are witnessed.
#
# Two defects in one case, because they are two ends of the same conjunct.
#
# (a) THE EXEMPTION WAS A ONE-WORD BYPASS. `AUTHZ_VERB_RE` was tested against the whole flattened
#     corpus, so relabelling a BUTTON exempted the question. Measured: this suite's own D4 fixture
#     ("Should the new rack be capex or opex?") and its own D6 fixture ("Can you ask my accountant
#     whether this is deductible?") both flipped deny -> ALLOW when an option was labelled `Approve`.
#     Two fixtures that exist to prove the arm fires, disarmed by one word in a place a founder reads
#     as a button rather than as a question. The exemption now reads the question text only.
#
# (b) `AUTHZ_VERB_RE` HAD NO WITNESS AT ALL. An independent per-member sweep found all 17 alternatives
#     individually deletable with the suite still green — on the arm that decides which outside-expert
#     questions escape the deny, and therefore on the exact edge where this hook's header says a wrong
#     answer is "strictly worse". D4 exercises the arm's ORDERING and D5 its non-firing, but nothing
#     exercised the vocabulary that lets a real authorization through. The sweep below pins the five
#     highest-consequence verbs one at a time, so deleting any of them reds this case by name.
TOTAL=$((TOTAL+1))
d9_fail=0

# (a) The authorization verb lives ONLY in an option label. Both of the suite's own escaped fixtures.
d9_out=$(payload "Should the new rack be capex or opex?" \
  "Approve as capex" "cost lands this year" "Opex" "spread it" | "$HOOK" 2>/dev/null)
d9_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d9_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d9_dec" != "deny" ]]; then
  printf '  FAIL: D9(a) an option LABEL carrying an authorization verb exempted an expert question (%s) — the exemption reads the whole corpus, so relabelling a button bypasses the arm\n' "$d9_dec" >&2
  d9_fail=$((d9_fail+1))
fi
d9_out=$(payload "Can you ask my accountant whether this is deductible?" \
  "Approve" "put it to them" "No" "leave it" | "$HOOK" 2>/dev/null)
d9_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d9_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$d9_dec" != "deny" ]]; then
  printf '  FAIL: D9(a) D6 own fixture escaped once an option was labelled Approve (%s)\n' "$d9_dec" >&2
  d9_fail=$((d9_fail+1))
fi

# (b) The verb IN THE QUESTION must still exempt — one case per verb, so each is individually pinned.
# Every payload names a profession, so the expert arm is live and only the exemption can permit it.
# THE PRECONDITION IS ASSERTED, not assumed. A payload that does not match EXTERNAL_EXPERT_RE is
# permitted by a later arm and says nothing whatever about the exemption — it is the "fixture passes
# for a second reason" shape. Measured on the first draft of this sweep: "Rotate the bank API token
# now?" matched no expert token (`bank API` satisfies neither `\bbank(er|ing)\b` nor
# `\bbank (account|statement|transfer|mandate|covenant)\b`), so deleting `rotate` from AUTHZ_VERB_RE
# left the suite fully green and that sub-case witnessed nothing.
d9_expert_re="$(sed -n "s/^EXTERNAL_EXPERT_RE='\(.*\)'$/\1/p" "$HOOK")"
if [[ -z "$d9_expert_re" ]]; then
  printf '  FAIL: D9(b) could not read EXTERNAL_EXPERT_RE out of the hook — the precondition below cannot be checked\n' >&2
  d9_fail=$((d9_fail+1))
fi
while IFS='|' read -r d9_q d9_why; do
  [[ -n "$d9_q" ]] || continue
  if [[ -n "$d9_expert_re" ]] \
     && ! grep -qE "$d9_expert_re" <<<"$(printf '%s' "$d9_q" | tr '[:upper:]' '[:lower:]')"; then
    printf '  FAIL: D9(b) the payload does not arm the expert regex, so it cannot witness %s: %s\n' "$d9_why" "$d9_q" >&2
    d9_fail=$((d9_fail+1))
    continue
  fi
  d9_out=$(payload "$d9_q" "Yes" "go ahead" "No" "hold" | "$HOOK" 2>/dev/null)
  d9_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${d9_out:-{\}}" 2>/dev/null || echo allow)
  if [[ "$d9_dec" != "allow" ]]; then
    printf '  FAIL: D9(b) a real authorization was BLOCKED (%s): %s — %s. This hook header calls a wrongly-blocked authorization strictly worse than a wrongly-permitted question.\n' \
      "$d9_dec" "$d9_q" "$d9_why" >&2
    d9_fail=$((d9_fail+1))
  fi
done <<'D9CASES'
Approve the September payroll run now?|approve
Authorize the bank mandate change?|authori[sz]
Deploy the tax calculation fix to production now?|deploy
Rotate the credentials on the bank mandate now?|rotate
Delete the landlord contact record? This is irreversible.|delete
D9CASES

if [[ "$d9_fail" -eq 0 ]]; then
  echo "  PASS: D9 the expert exemption reads the question only, and its five load-bearing verbs are each witnessed"; PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi

# V3 — AUTHZ_VERB_RE must be a SUBSET of AUTHORITY_RE. Structural, not behavioural, and deliberately
# so: the behavioural symptom needs a payload carrying a profession noun AND an authorization verb AND
# an investigative cue all at once, which is why it survived a suite that tests each of those.
#
# The two lists answer the same question — "is this an operator authorization?" — for two different
# arms. `AUTHZ_VERB_RE` exempts a question from the expert arm; `AUTHORITY_RE` short-circuits it to
# allow. A verb in the first and not the second therefore produces a question that is exempted from
# the deny it should have been exempted from and then falls PAST the allow into the investigative
# default-deny. Measured: `roll ?out` was in AUTHZ and absent from AUTHORITY, so "Roll out the payroll
# export now, or read the runbook first?" was DENIED while the same question with `Approve` was
# allowed — a wrongly-blocked authorization, which this hook's header calls strictly worse than a
# wrongly-permitted question, reached by two token lists drifting rather than by a missing token.
#
# Asserted over the MEMBERS rather than by a payload sweep, because containment is the invariant and a
# sweep would need one fixture per member to say the same thing less reliably. `\b` is stripped before
# comparing: AUTHZ spells one member `\bmerge` where AUTHORITY spells it `merge`, and the anchored form
# is strictly narrower, so it cannot match anything the looser one misses.
TOTAL=$((TOTAL+1))
v3_authz="$(sed -n "s/^AUTHZ_VERB_RE='(\(.*\))'$/\1/p" "$HOOK")"
v3_authority="$(sed -n "s/^AUTHORITY_RE='(\(.*\))'$/\1/p" "$HOOK")"
if [[ -z "$v3_authz" || -z "$v3_authority" ]]; then
  printf '  FAIL: V3 could not extract one of the two vocabularies (AUTHZ=%s chars, AUTHORITY=%s chars) — the containment below would pass over an empty set\n' \
    "${#v3_authz}" "${#v3_authority}" >&2
  FAIL=$((FAIL+1))
else
  v3_missing=""
  v3_n=0
  while IFS= read -r v3_m; do
    [[ -n "$v3_m" ]] || continue
    v3_n=$((v3_n+1))
    v3_bare="${v3_m//\\b/}"
    printf '%s\n' "$v3_authority" | tr '|' '\n' | sed 's/\\b//g' | grep -cxF >/dev/null -- "$v3_bare" \
      || v3_missing="$v3_missing $v3_m"
  done <<< "$(printf '%s\n' "$v3_authz" | tr '|' '\n')"
  # Non-vacuity: a split that yielded nothing would report perfect containment.
  if [[ "$v3_n" -lt 10 ]]; then
    printf '  FAIL: V3 the AUTHZ vocabulary split yielded only %s member(s) — containment over a near-empty set proves nothing\n' "$v3_n" >&2
    FAIL=$((FAIL+1))
  elif [[ -n "$v3_missing" ]]; then
    printf '  FAIL: V3 AUTHZ_VERB_RE is not a subset of AUTHORITY_RE; missing from AUTHORITY_RE:%s. Each such verb exempts the expert arm and then falls past the authority arm into the investigative default-deny, blocking a real authorization.\n' \
      "$v3_missing" >&2
    FAIL=$((FAIL+1))
  else
    printf '  PASS: V3 all %s AUTHZ_VERB_RE members are present in AUTHORITY_RE (no verb exempts the expert arm and then falls past the allow)\n' "$v3_n"
    PASS=$((PASS+1))
  fi
fi

# --- TECHNICAL-RULING ARM (R1-R10, Z1-Z4, V4, V5) ----------------------------------------------------
# A technical RULING (how strict the evidence bar is, which of two designs, whether a status flips, which
# threshold) is the CTO agent's call, not the operator's. The arm denies it with a reason naming
# soleur:engineering:cto and the shared reference, and it is evaluated AHEAD of the authority
# short-circuit (R1/R3 carry "dispatched", "deleted" and a money word, so they only deny if the order holds).
# The arm judges EACH question separately; the exemption reads that question's TEXT only.
#
# The existing payload() emits ONE question. These builders emit several.
qobj() { # <question> [label1 desc1 label2 desc2] -> one question object
  jq -nc --arg q "$1" --arg l1 "${2:-Yes}" --arg d1 "${3:-go ahead as described}" --arg l2 "${4:-No}" --arg d2 "${5:-leave it as it stands}" \
    '{question:$q, options:[{label:$l1,description:$d1},{label:$l2,description:$d2}]}'
}
mq_payload() { # question objects on stdin, one per line -> one AskUserQuestion payload
  jq -sc '{tool_name:"AskUserQuestion", cwd:".", session_id:"t", tool_input:{questions:.}}'
}
RULING_HIT_NAMES=""
# ruling_check <label> <expect allow|deny> <mode ruling|invest|none> <payload-json>; 0 = satisfied.
ruling_check() {
  local label="$1" expect="$2" mode="$3" json="$4" out dec reason
  out=$(printf '%s' "$json" | "$HOOK" 2>/dev/null)
  dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null || echo allow)
  reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"${out:-{\}}" 2>/dev/null || echo "")
  if [[ "$dec" != "$expect" ]]; then
    printf '  FAIL: %s — got %s want %s\n' "$label" "$dec" "$expect" >&2; return 1
  fi
  if [[ "$expect" == "deny" && "$mode" == "ruling" ]]; then
    if ! grep -qF 'soleur:engineering:cto' <<<"$reason" \
       || ! grep -qF 'technical-ruling-delegation.md' <<<"$reason" \
       || ! grep -qF 'split the item; ask the operator only the authorization' <<<"$reason" \
       || ! grep -qF 'May I' <<<"$reason" \
       || grep -qF 'SOLEUR_ACK_TECHNICAL_FORK' <<<"$reason"; then
      printf '  FAIL: %s — denied, but the reason does not name soleur:engineering:cto, technical-ruling-delegation.md, the split instruction and the permission-ask reword, or it still suggests an env var a tool call cannot set\n' "$label" >&2; return 1
    fi
    RULING_HIT_NAMES="$RULING_HIT_NAMES $label"
  elif [[ "$expect" == "deny" && "$mode" == "invest" ]]; then
    if ! grep -qF 'TECHNICAL INVESTIGATION' <<<"$reason" || grep -qF 'soleur:engineering:cto' <<<"$reason"; then
      printf '  FAIL: %s — denied, but not with the investigation reason (the ruling arm must not claim a non-ruling question)\n' "$label" >&2; return 1
    fi
  fi
  return 0
}
run_ruling() { # <name> <expect> <mode> <payload-json>
  TOTAL=$((TOTAL+1))
  if ruling_check "${1%% *}" "$2" "$3" "$4"; then printf '  PASS: %s (%s)\n' "$1" "$2"; PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
}

R1_Q="How strict must the emptiness evidence be before the volume rebirth is dispatched and the plaintext volume deleted?"
run_ruling "R1 evidence-strictness ruling (carries dispatched + deleted)" deny ruling \
  "$(qobj "$R1_Q" "Tighten the ceiling" "require two independent proofs" "Keep the thresholds" "retain the current bar" | mq_payload)"
run_ruling "R2 ADR status flip from adopting to accepted" deny ruling \
  "$(qobj "Should the ADR status move from adopting to accepted now that the grader passes?" "Move it" "record the new status" "Hold" "keep the current status" | mq_payload)"
# R2 reason: a flip whose criterion the ADR states is mechanical, otherwise the CTO rules.
TOTAL=$((TOTAL+1))
r2_reason=$(qobj "Should the ADR status move from adopting to accepted now that the grader passes?" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
if grep -qF 'run the grader, cite it, flip' <<<"$r2_reason" && grep -qF 'the CTO rules' <<<"$r2_reason"; then
  echo "  PASS: R2b the reason says a stated-criterion flip is mechanical and otherwise the CTO rules"; PASS=$((PASS+1))
else echo "  FAIL: R2b the ruling reason lacks the mechanical-flip / CTO-rules guidance" >&2; FAIL=$((FAIL+1)); fi
# L1 — all three deny reasons name the CLOSED list of what is the operator's call, not the old four-word list.
TOTAL=$((TOTAL+1))
l1_list='money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand'
l1_fail=""
l1_rul=$(qobj "$R1_Q" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
l1_inv=$(qobj "How should I resolve the cutover path?" "Read the runbook properly first" "find the documented order" "Ask whoever owns the cutover section" "the plan deferred it" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
l1_exp=$(qobj "Can you ask my accountant whether this is deductible?" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
grep -qF "$l1_list" <<<"$l1_rul" || l1_fail="$l1_fail ruling"
grep -qF "$l1_list" <<<"$l1_inv" || l1_fail="$l1_fail investigation"
grep -qF "$l1_list" <<<"$l1_exp" || l1_fail="$l1_fail expert"
if [[ -z "$l1_fail" ]]; then echo "  PASS: L1 the ruling, investigation and expert reasons all carry the closed operator-only list"; PASS=$((PASS+1))
else printf '  FAIL: L1 the closed operator-only list is missing from the reason(s):%s\n' "$l1_fail" >&2; FAIL=$((FAIL+1)); fi
run_ruling "R3 R1 plus a money word in an option description (arm is ahead of the authority short-circuit)" deny ruling \
  "$(qobj "$R1_Q" "Tighten the ceiling" "costs one more run" "Keep the thresholds" "retain the current bar" | mq_payload)"

# R4 — per-question evaluation. Question 1 is a compliant authorization; question 2 is R1's ruling.
TOTAL=$((TOTAL+1))
r4_fail=0
r4_auth="$(qobj "Approve the merge of PR 9628?")"
r4_rule="$(qobj "$R1_Q" "Tighten the ceiling" "require two independent proofs" "Keep the thresholds" "retain the current bar")"
ruling_check "R4a" deny ruling "$(printf '%s\n%s\n' "$r4_auth" "$r4_rule" | mq_payload)" || r4_fail=$((r4_fail+1))
ruling_check "R4b" allow none "$(printf '%s\n' "$r4_auth" | mq_payload)" || r4_fail=$((r4_fail+1))
ruling_check "R4c" deny ruling "$(printf '%s\n%s\n' "$r4_rule" "$r4_auth" | mq_payload)" || r4_fail=$((r4_fail+1))
if [[ "$r4_fail" -eq 0 ]]; then
  echo "  PASS: R4 each question is judged alone: an Approve in question 1 does not exempt a ruling in question 2 (and the lone authorization allows)"; PASS=$((PASS+1))
else FAIL=$((FAIL+1)); fi

run_ruling "R5 a permission ask naming dispatch, no ruling cue" allow none \
  "$(qobj "May I dispatch the rebirth now?" | mq_payload)"
run_ruling "R6 stated residual: appending an Approve ask exempts the question" allow none \
  "$(qobj "How strict should the evidence bar be? Approve the stricter threshold?" | mq_payload)"
run_ruling "R7 a button labelled Approve never exempts" deny ruling \
  "$(qobj "$R1_Q" "Approve" "require two independent proofs" "Keep the thresholds" "retain the current bar" | mq_payload)"

TOTAL=$((TOTAL+1))
r8_fail=0
ruling_check "R8a" allow none "$(qobj "Is it ok to go ahead and flip the flag?" | mq_payload)" || r8_fail=$((r8_fail+1))
ruling_check "R8b" allow none "$(qobj "What is the budget for the second host?" | mq_payload)" || r8_fail=$((r8_fail+1))
if [[ "$r8_fail" -eq 0 ]]; then echo "  PASS: R8 cue-free permission and budget asks allow"; PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

run_ruling "R9 a brand choice is not a technical ruling" allow none \
  "$(qobj "Which of the two logo designs should the landing page use?" "The rounded one" "friendlier" "The sharp one" "more technical" | mq_payload)"
run_ruling "R10 the 2026-08-19 investigation fixture keeps the investigation reason" deny invest \
  "$(qobj "How should I resolve the cutover path?" \
     "Read the runbook properly first" "Find the documented order for a cold host rather than reasoning it out from guard comments." \
     "Ask whoever owns the cutover section" "The plan deferred the cutover window to numbered steps I have not read." | mq_payload)"

run_ruling "Z1 a permission ask that DOES carry a ruling cue (witnesses the exemption)" allow none \
  "$(qobj "May I tighten the evidence threshold to 64 MiB?" | mq_payload)"
run_ruling "Z2 approach A or approach B (should is not an exemption)" deny ruling \
  "$(qobj "Should I use approach A or approach B for the retry design?" "Approach A" "queue it" "Approach B" "retry inline" | mq_payload)"
run_ruling "Z3 evidence sufficiency" deny ruling \
  "$(qobj "Is the evidence sufficient to retire the guard?" "Sufficient" "retire it" "Not yet" "keep it" | mq_payload)"
run_ruling "Z4 an Approve ask over a threshold" allow none \
  "$(qobj "Approve the stricter evidence bar?" | mq_payload)"
run_ruling "R11 a money threshold question is not a ruling" allow none \
  "$(qobj "What revenue threshold should trigger the second paid host?" | mq_payload)"

# --- NARROWED CUE (W, C, E, F, O, S, B, T rows) ------------------------------------------------------
# The arm's WORSE failure mode is wrongly denying a genuine operator-class question (money, scope,
# priority/schedule, irreversible or production authorization, legal risk, brand). Review measured the W
# rows below as wrong denies against a cue that matched a bare "stricter" or "A or B"; origin/main allowed
# every one. A weak cue now needs a TECHNICAL CO-SIGNAL (an evidence noun, an ADR word, a technical noun),
# and the A/B cue reads the QUESTION TEXT only, never an option label.

# W — operator-class questions that carry a cue word but no technical co-signal. All must allow.
run_ruling "W1 pricing plan A or B" allow none \
  "$(qobj "Which pricing plan do you want to launch, A or B?" | mq_payload)"
run_ruling "W2 scope variant A or variant B" allow none \
  "$(qobj "Scope: ship variant A (basic export) or variant B (full export)?" | mq_payload)"
run_ruling "W3 launch date A or B" allow none \
  "$(qobj "Which launch date: A or B?" | mq_payload)"
run_ruling "W4 spend cap stricter (money, no evidence noun)" allow none \
  "$(qobj "Should the monthly spend cap be stricter?" | mq_payload)"
run_ruling "W5 logo variant A (brand)" allow none \
  "$(qobj "Which logo variant A do you prefer?" | mq_payload)"
run_ruling "W6 the brainstorm skill's own prompt shape (approach letters only in options)" allow none \
  "$(qobj "Which approach do you prefer?" "Approach A: hosted checkout" "" "Approach B: embedded form" "" | mq_payload)"
run_ruling "W7 pricing page layout with Variant A/B options" allow none \
  "$(qobj "Which pricing page layout do you prefer?" "Variant A" "" "Variant B" "" | mq_payload)"
run_ruling "W8 ship variant A to prod (authorization)" allow none \
  "$(qobj "Ship variant A to prod?" | mq_payload)"
run_ruling "W9 roll out the stricter CSP to production (authorization)" allow none \
  "$(qobj "Roll out the stricter CSP to production now?" | mq_payload)"
run_ruling "W10 merge ask whose DECLARATIVE second sentence names a stricter evidence gate" allow none \
  "$(qobj "Merge PR 9628 now? It adds the stricter evidence gate." | mq_payload)"
run_ruling "W11 close an issue (a status change that is not an ADR flip)" allow none \
  "$(qobj "Close issue 123 (status change to done)?" | mq_payload)"
run_ruling "W12 scope/schedule approach A vs approach B" allow none \
  "$(qobj "Approach A: ship the pricing page this week. Approach B: delay it a month. Which?" | mq_payload)"
run_ruling "W13 priority A or B first" allow none \
  "$(qobj "Should we do A or B first: onboarding or billing?" | mq_payload)"
run_ruling "W14 stricter rule vs delaying a merge (schedule)" allow none \
  "$(qobj "Is a stricter rule worth delaying the merge of PR 9628 by a week?" | mq_payload)"
run_ruling "W15 hero copy variant A or variant B (brand)" allow none \
  "$(qobj "Which variant A or variant B of the hero copy reads better?" | mq_payload)"

# Q — measured wrong denies of the second review: operator-class asks (brand, schedule, money, merge/ship/release,
# legal-risk vocabulary) that carry a cue word. Weak cues (C1 C2 C6 C7) need an interrogative sentence AND no
# operator vocabulary in the question; the technical-noun list is engineering nouns only (design, api, index,
# library, migration, implementation and cache are pricing/brand/schedule words as often as technical ones).
run_ruling "Q1 logo A or B, 'design' is not a technical noun" allow none \
  "$(qobj "Which logo, A or B? The new design reads cleaner." | mq_payload)"
run_ruling "Q2 run the migration in window A or B (schedule)" allow none \
  "$(qobj "Run the migration in window A or B?" | mq_payload)"
run_ruling "Q3 API plan A or B for the budget" allow none \
  "$(qobj "Which API plan, A or B, for the budget?" | mq_payload)"
run_ruling "Q4 pay for index plan A or B" allow none \
  "$(qobj "Pay for index plan A or B?" | mq_payload)"
run_ruling "Q5 budget for a stricter check of invoices (C2 vetoed)" allow none \
  "$(qobj "Raise the budget for a stricter check of invoices?" | mq_payload)"
run_ruling "Q6 merge ask, no question mark, weak cues only" allow none \
  "$(qobj "Merge PR 9628 now. It adds the stricter evidence gate" | mq_payload)"
run_ruling "Q7 should we merge the release (cue only in an option description)" allow none \
  "$(qobj "Should we merge the release?" "Merge" "stricter gate on the CI check" "Hold" "wait" | mq_payload)"
run_ruling "Q8 pricing tier for the new API plan, A or B" allow none \
  "$(qobj "Which pricing tier should the new API plan use, A or B?" | mq_payload)"
run_ruling "Q9 library migration shipping this sprint, option A or option B for the timeline" allow none \
  "$(qobj "Should the new library migration ship this sprint, option A or option B for the timeline?" | mq_payload)"
run_ruling "Q10 close the ADR 12 issue (adr alone is not an ADR word)" allow none \
  "$(qobj "Close the ADR 12 issue now (status change)?" | mq_payload)"
run_ruling "Q11 evidence enough to start charging (C4 money veto)" allow none \
  "$(qobj "Is the evidence enough to start charging for the beta?" | mq_payload)"
run_ruling "Q12 C1 vetoed by launch and date" allow none \
  "$(qobj "How strict should the check on launch dates be?" | mq_payload)"
run_ruling "Q13 C6 vetoed by launch" allow none \
  "$(qobj "Should the decision record status change before the launch?" | mq_payload)"
run_ruling "Q14 how strict guard, but a statement with no question mark" allow none \
  "$(qobj "Decide how strict the guard should be." | mq_payload)"
run_ruling "Q15 option A or B for a queue, but a statement with no question mark" allow none \
  "$(qobj "Use option A or option B for the queue." | mq_payload)"
run_ruling "Q16 C4 money veto, a vendor contract" allow none \
  "$(qobj "Is the proof adequate to sign the vendor contract?" | mq_payload)"
run_ruling "Q17 a cue in a declarative sentence before an unrelated question" allow none \
  "$(qobj "We made the gate stricter last week. Which issue first?" | mq_payload)"

# S1 — the strictness cue needs an evidence noun: "how strict" about a budget is a money ask.
run_ruling "S1 how strict should the monthly budget be (no evidence noun)" allow none \
  "$(qobj "How strict should the monthly budget be?" | mq_payload)"

# C — one deny witness per strong cue, each in a DIFFERENT vocabulary and firing exactly one cue, so
# dropping that cue reds exactly that case by name. All must reach the ruling arm's own reason.
run_ruling "C1 how strict + an evidence noun (guard)" deny ruling \
  "$(qobj "How strict should the guard be about leftover volumes?" | mq_payload)"
run_ruling "C2 stricter + an evidence noun (verification)" deny ruling \
  "$(qobj "Should the verification step on rebirth be stricter?" | mq_payload)"
run_ruling "C3 an emptiness floor" deny ruling \
  "$(qobj "Is the emptiness floor right for the rebirth?" | mq_payload)"
run_ruling "C4 proof adequate" deny ruling \
  "$(qobj "Is the proof adequate to retire the old lock?" | mq_payload)"
run_ruling "C5 adopting to accepted without any status word" deny ruling \
  "$(qobj "Should we move the record from adopting to accepted?" | mq_payload)"
run_ruling "C6 status flip + decision record (ADR word)" deny ruling \
  "$(qobj "Should the decision record status flip once the grader passes?" | mq_payload)"
run_ruling "C7 variant A or variant B for a schema" deny ruling \
  "$(qobj "Should the schema follow variant A or variant B?" | mq_payload)"
run_ruling "C7b A vs B for a queue layout" deny ruling \
  "$(qobj "Pick the queue layout: A vs B?" | mq_payload)"

# K — one deny witness per remaining CUE MEMBER, each in its own vocabulary and carrying exactly one member of
# the list it witnesses, so deleting that member reds that row by name.
run_ruling "K1 strictness (noun: evidence)" deny ruling \
  "$(qobj "What strictness should the evidence for a rebirth carry?" | mq_payload)"
run_ruling "K2 how stringent (noun: evidence)" deny ruling \
  "$(qobj "How stringent should the evidence be before retiring the old lock?" | mq_payload)"
run_ruling "K3 how rigorous (noun: evidence)" deny ruling \
  "$(qobj "How rigorous does the evidence need to be for the rebirth?" | mq_payload)"
run_ruling "K4 bar word ceiling" deny ruling \
  "$(qobj "Is the emptiness ceiling too loose for old volumes?" | mq_payload)"
run_ruling "K5 bar word standard, left word proof" deny ruling \
  "$(qobj "Does the proof standard need to change for retired locks?" | mq_payload)"
run_ruling "K6 bar word bar, no question mark (strong cues need none)" deny ruling \
  "$(qobj "Decide the evidence bar for the rebirth" | mq_payload)"
run_ruling "K7 enough" deny ruling \
  "$(qobj "Is the evidence enough to retire the old lock?" | mq_payload)"
run_ruling "K8 status move + accepted" deny ruling \
  "$(qobj "Does the status move to accepted after the grader passes?" | mq_payload)"
run_ruling "K9 status change + adopting" deny ruling \
  "$(qobj "Should the status change before we start adopting the new scheme?" | mq_payload)"
run_ruling "K10 are + proof (the plural copula member of the sufficiency cue)" deny ruling \
  "$(qobj "Are the proof adequate for retiring the old lock?" | mq_payload)"

# N — one deny witness per EVIDENCE NOUN (C1/C2 co-signal), exactly one noun per row.
run_ruling "N1 noun proof" deny ruling \
  "$(qobj "How strict should the proof of leftover volume emptiness be?" | mq_payload)"
run_ruling "N2 noun check" deny ruling \
  "$(qobj "How strict should the post-rebirth check be?" | mq_payload)"
run_ruling "N3 noun gate" deny ruling \
  "$(qobj "Should the rebirth gate be stricter?" | mq_payload)"
run_ruling "N4 noun validation" deny ruling \
  "$(qobj "How strict should validation of the exported rows be?" | mq_payload)"
run_ruling "N5 noun criteria" deny ruling \
  "$(qobj "Should the criteria for retiring a lock be stricter?" | mq_payload)"
run_ruling "N6 noun assertion" deny ruling \
  "$(qobj "Is a stricter assertion warranted on the replay count?" | mq_payload)"
run_ruling "N7 noun test" deny ruling \
  "$(qobj "How strict should the smoke test be for the volume rebirth?" | mq_payload)"
run_ruling "N8 noun lint" deny ruling \
  "$(qobj "Should the lint rule on shell scripts be stricter?" | mq_payload)"

# M — one deny witness per TECHNICAL NOUN (C7 co-signal), exactly one noun per row, varying the A/B spelling.
run_ruling "M1 noun architecture, approach" deny ruling \
  "$(qobj "Should we take approach A or approach B for the architecture?" | mq_payload)"
run_ruling "M2 noun algorithm, a or b" deny ruling \
  "$(qobj "Which algorithm, A or B, handles the tie-break?" | mq_payload)"
run_ruling "M3 noun substrate, option" deny ruling \
  "$(qobj "Pick option A or option B for the substrate?" | mq_payload)"
run_ruling "M4 noun data model, a vs. b" deny ruling \
  "$(qobj "Should the data model follow A vs. B?" | mq_payload)"
run_ruling "M5 noun queue, option" deny ruling \
  "$(qobj "Should the worker use option A or option B for the queue?" | mq_payload)"
run_ruling "M6 noun refactor, option" deny ruling \
  "$(qobj "Refactor path: option A or option B?" | mq_payload)"

# E — one allow witness per KEPT exemption member, each carrying a cue, so deleting any member reds a case.
# (Z1 witnesses `may i`; Z4 witnesses `approve`.) `is it ok to` is subsumed by `ok(ay)? to` and is not a member.
run_ruling "E1 is it fine to (exemption member)" allow none \
  "$(qobj "Is it fine to tighten the evidence bar?" | mq_payload)"
run_ruling "E2 is it ok to (exemption member ok(ay)? to)" allow none \
  "$(qobj "Is it ok to tighten the evidence bar?" | mq_payload)"
run_ruling "E3 OK to (exemption member ok(ay)? to)" allow none \
  "$(qobj "OK to relax the evidence standard?" | mq_payload)"
run_ruling "E4 go-ahead (exemption member)" allow none \
  "$(qobj "Go-ahead to raise the evidence floor?" | mq_payload)"
run_ruling "E5 authorize (exemption member)" allow none \
  "$(qobj "Authorize raising the evidence threshold?" | mq_payload)"
run_ruling "E7 okay to, spelled out (exemption member ok(ay)? to)" allow none \
  "$(qobj "Okay to tighten the evidence bar?" | mq_payload)"
run_ruling "E8 authorise, British spelling (exemption member authori[sz]e)" allow none \
  "$(qobj "Authorise raising the evidence threshold?" | mq_payload)"
run_ruling "E9 approved is an approve form" allow none \
  "$(qobj "Approved to raise the evidence floor?" | mq_payload)"
run_ruling "E6 ack-destroy (exemption member)" allow none \
  "$(qobj "ack-destroy: is the evidence bar enough?" | mq_payload)"

# F — `can we`, `can i`, `may we` and `should we` are RULING shapes, not permission shapes: a question
# carrying a cue is denied however it is phrased.
run_ruling "F1 can we is not an exemption" deny ruling \
  "$(qobj "Can we tighten the evidence threshold to 64 MiB?" | mq_payload)"
run_ruling "F2 can i is not an exemption" deny ruling \
  "$(qobj "Can I relax the evidence bar for the rebirth?" | mq_payload)"
run_ruling "F3 may we is not an exemption" deny ruling \
  "$(qobj "May we decide how strict the evidence bar should be?" | mq_payload)"
run_ruling "F4 should we is not an exemption" deny ruling \
  "$(qobj "Should we tighten the evidence bar?" | mq_payload)"

run_ruling "F5 approver is not an approve form (the exemption is approve[ds]? with a right anchor)" deny ruling \
  "$(qobj "Should the approver need a stricter evidence bar?" | mq_payload)"

# O1 — the A/B cue reads the QUESTION TEXT only. The question names a technical noun but no letter; the
# letters live only in the option labels. A cue read over options would deny this.
run_ruling "O1 approach letters only in option labels" allow none \
  "$(qobj "Which approach do you prefer for the retry design?" "Approach A" "hosted" "Approach B" "embedded" | mq_payload)"

# P1 — a ruling that lives ONLY in an option label is not read: every cue reads the QUESTION TEXT. An option
# label is a button; the operator is not being asked to rule on it. (Flipped from deny on the second review.)
run_ruling "P1 a ruling carried only by an option label is not read" allow none \
  "$(qobj "Which do you want?" "Tighten the evidence bar" "require two independent proofs" "Keep it" "retain the current bar" | mq_payload)"
run_ruling "P2 a strict cue carried only by an option description is not read" allow none \
  "$(qobj "Should we merge the release?" "Merge" "stricter gate on the CI check" "Hold" "wait" | mq_payload)"
run_ruling "P3 a bar cue carried only by an option description is not read" allow none \
  "$(qobj "Dispatch the rebirth now?" "Dispatch" "after the emptiness evidence threshold is tightened" "Hold" "wait" | mq_payload)"

run_ruling "P4 a strictness cue carried only by option text (interrogative question, no cue)" allow none \
  "$(qobj "Which do you want?" "Make the check stricter" "tighten the guard" "Keep it" "leave as is" | mq_payload)"
run_ruling "P5 a status flip plus ADR word carried only by option text" allow none \
  "$(qobj "Which do you want?" "Status flip" "decision record accepted" "Keep it" "leave as is" | mq_payload)"
run_ruling "P6 an evidence-sufficiency phrase carried only by option text" allow none \
  "$(qobj "Which do you want?" "Is the evidence sufficient?" "then retire it" "Keep it" "leave as is" | mq_payload)"

# X — the dropped technical nouns each stay NON-cues: "approach A or approach B for the <noun>" is an ordinary
# product/schedule/brand sentence as often as an engineering one. One row per noun so re-adding any one reds it by name.
for x_n in design api index library migration implementation cache; do
  run_ruling "X-$x_n approach A or approach B for the $x_n is not a technical-noun co-signal" allow none \
    "$(qobj "Should I use approach A or approach B for the $x_n?" | mq_payload)"
done

# B — shapes that must not crash and must allow.
run_ruling "B1 an empty question with cue words only in its options" allow none \
  "$(jq -nc '{tool_name:"AskUserQuestion",cwd:".",session_id:"t",tool_input:{questions:[{question:"",options:[{label:"How strict is the evidence bar?",description:"approach A or B"}]}]}}')"
run_ruling "B3 a cue only in the header" allow none \
  "$(jq -nc '{tool_name:"AskUserQuestion",cwd:".",session_id:"t",tool_input:{questions:[{header:"How strict is the evidence bar?",question:"Pick one?",options:[{label:"Yes",description:"go"},{label:"No",description:"stop"}]}]}}')"
# B2 — a non-string question is skipped, announced on stderr, and allowed.
TOTAL=$((TOTAL+1))
b2_json="$(jq -nc '{tool_name:"AskUserQuestion",cwd:".",session_id:"t",tool_input:{questions:[{question:42,options:[{label:"How strict is the evidence bar?",description:"approach A or B"}]}]}}')"
b2_out="$(printf '%s' "$b2_json" | "$HOOK" 2>/dev/null)"
b2_err="$(printf '%s' "$b2_json" | "$HOOK" 2>&1 >/dev/null)"
b2_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${b2_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$b2_dec" == "allow" ]] && grep -qF 'skipped' <<<"$b2_err"; then
  echo "  PASS: B2 a non-string question is skipped, announced on stderr, and allowed"; PASS=$((PASS+1))
else printf '  FAIL: B2 non-string question — decision %s, stderr announced skip: %s\n' "$b2_dec" "$(grep -qF 'skipped' <<<"$b2_err" && echo yes || echo no)" >&2; FAIL=$((FAIL+1)); fi

# T1 — a ~64 KB question with the cue absent and plenty of whitespace runs must finish quickly. The
# extraction once collapsed whitespace with a jq regex gsub that was quadratic (a 32 KB question took 9.5 s).
TOTAL=$((TOTAL+1))
t1_q="$(printf 'lorem ipsum dolor sit amet \n\t  consectetur %.0s' $(seq 1 1600))?"
t1_json="$(qobj "$t1_q" | mq_payload)"
t1_start=$(date +%s%N)
t1_out="$(printf '%s' "$t1_json" | timeout 10 "$HOOK" 2>/dev/null)"; t1_rc=$?
t1_ms=$(( ( $(date +%s%N) - t1_start ) / 1000000 ))
t1_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${t1_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$t1_rc" -eq 0 && "$t1_dec" == "allow" && "$t1_ms" -lt 3000 && "${#t1_q}" -gt 60000 ]]; then
  echo "  PASS: T1 a ${#t1_q}-char question with the cue absent allowed in ${t1_ms} ms (< 3000)"; PASS=$((PASS+1))
else printf '  FAIL: T1 timing guard — rc=%s decision=%s took %s ms (limit 3000) on %s chars\n' "$t1_rc" "$t1_dec" "$t1_ms" "${#t1_q}" >&2; FAIL=$((FAIL+1)); fi

# T2/T3/T4 — the interrogative-sentence extraction must be LINEAR. A regex with a nested quantifier
# (`([^.!?]|\.[^ ?!])*\?`) cost ~13 s on a 32 KB question with a strictness cue, one `?` and a long tail
# (2.6 s at 16 KB, 60 s at 64 KB). The cost is only visible through a pipe or command substitution: a
# standalone `grep >/dev/null` stops at the first match and hides it, so the whole hook is timed here.
timed_deny() { # <name> <expect> <question>
  TOTAL=$((TOTAL+1))
  local json out rc ms dec start
  json="$(qobj "$3" | mq_payload)"
  start=$(date +%s%N)
  out="$(printf '%s' "$json" | timeout 10 "$HOOK" 2>/dev/null)"; rc=$?
  ms=$(( ( $(date +%s%N) - start ) / 1000000 ))
  dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null || echo allow)
  if [[ "$rc" -eq 0 && "$dec" == "$2" && "$ms" -lt 3000 && "${#3}" -gt "${TIMED_MIN:-0}" ]]; then
    printf '  PASS: %s a %s-char question: %s in %s ms (< 3000)\n' "$1" "${#3}" "$dec" "$ms"; PASS=$((PASS+1))
  else printf '  FAIL: %s timing guard — rc=%s decision=%s (want %s) took %s ms (limit 3000) on %s chars\n' "$1" "$rc" "$dec" "$2" "$ms" "${#3}" >&2; FAIL=$((FAIL+1)); fi
}
t_tail32="$(printf 'lorem ipsum dolor sit amet consectetur %.0s' $(seq 1 820))"
t_tail64="${t_tail32}${t_tail32}"
TIMED_MIN=30000 timed_deny "T2" deny "How strict the evidence gate? ${t_tail32}"
TIMED_MIN=60000 timed_deny "T3" deny "How strict the evidence gate? ${t_tail64}"
# Many `?` and many sentence boundaries, so an extraction that is linear per `?` but quadratic in their number is also caught.
t_many="$(printf 'ok. fine! how strict the evidence gate? %.0s' $(seq 1 1500))"
TIMED_MIN=55000 timed_deny "T4" deny "$t_many"

# V6 — every member of the operator-vocabulary VETO is witnessed. One weak-cue (C1) question per member; each must
# allow. The list is spelled here, not read out of the hook, so deleting a member from the hook reds this case.
TOTAL=$((TOTAL+1))
v6_bad=""
for v6_w in price prices pricing plan plans tier tiers launch launches date dates deadline deadlines license licenses licence licences vendor vendors logo logos copy landing budget budgets cost costs spend revenue invoice invoices refund refunds schedule schedules priority priorities brand hero merge deploy ship release releases delete prod production; do
  v6_out=$(qobj "How strict should the check on the $v6_w be?" | mq_payload | "$HOOK" 2>/dev/null)
  v6_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${v6_out:-{\}}" 2>/dev/null || echo allow)
  [[ "$v6_dec" == "allow" ]] || v6_bad="$v6_bad $v6_w"
done
# Non-vacuity: the same question with a neutral noun must DENY, or the loop above passes over a dead arm.
v6_ctl=$(qobj "How strict should the check on the volume be?" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
if [[ -z "$v6_bad" && "$v6_ctl" == "deny" ]]; then echo "  PASS: V6 every operator-vocabulary veto member silences a weak cue (control denies)"; PASS=$((PASS+1))
else printf '  FAIL: V6 veto members that did not veto:%s (control decision %s)\n' "$v6_bad" "$v6_ctl" >&2; FAIL=$((FAIL+1)); fi

# V7 — every member of the C4 MONEY veto is witnessed, against a control that denies.
TOTAL=$((TOTAL+1))
v7_bad=""
for v7_w in charging paying refund refunds invoice invoices price pricing cost costs spend revenue contract vendor vendors; do
  v7_out=$(qobj "Is the evidence enough to start on the $v7_w?" | mq_payload | "$HOOK" 2>/dev/null)
  v7_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${v7_out:-{\}}" 2>/dev/null || echo allow)
  [[ "$v7_dec" == "allow" ]] || v7_bad="$v7_bad $v7_w"
done
v7_ctl=$(qobj "Is the evidence enough to start on the rebirth?" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
if [[ -z "$v7_bad" && "$v7_ctl" == "deny" ]]; then echo "  PASS: V7 every money-veto member silences the sufficiency cue (control denies)"; PASS=$((PASS+1))
else printf '  FAIL: V7 money members that did not veto:%s (control decision %s)\n' "$v7_bad" "$v7_ctl" >&2; FAIL=$((FAIL+1)); fi

# V8 — the shared lib's RULING_OPVOCAB_RE (the BUSINESS|ACTION concatenation) is byte-equal to the literal this
# hook carried before the cues moved. A dropped or added member would change what the weak cues are vetoed by; V6
# checks each member behaviourally, this pins the whole string, and a BUSINESS word added for a closing-only reason
# would change it and silence THIS hook too (the lib header names that as never the fix).
TOTAL=$((TOTAL+1))
v8_pinned='\b(prices?|pricing|plans?|tiers?|launch(es)?|dates?|deadlines?|licen[sc]es?|vendors?|logos?|copy|landing|budgets?|costs?|spend|revenue|invoices?|refunds?|schedules?|priorit(y|ies)|brand|hero|merge|deploy|ship|releases?|delete|prod|production)\b'
# shellcheck disable=SC1090  # the lib path is a variable by design; the value is read by sourcing
v8_live="$( ( . "$LIB" 2>/dev/null; printf '%s' "${RULING_OPVOCAB_RE:-}" ) )"
if [[ -n "$v8_live" && "$v8_live" == "$v8_pinned" ]]; then echo "  PASS: V8 the lib's RULING_OPVOCAB_RE is byte-equal to the pinned pre-move literal"; PASS=$((PASS+1))
else printf '  FAIL: V8 RULING_OPVOCAB_RE in the lib differs from the pinned literal (live: %s)\n' "$v8_live" >&2; FAIL=$((FAIL+1)); fi

# L2 — one definition site. This hook sources the lib and defines no RULING_*_RE cue itself; the lib defines them.
TOTAL=$((TOTAL+1))
if grep -qE '^[[:space:]]*(source|\.)[[:space:]].*TFC_LIB' "$HOOK" && ! grep -qE '^RULING_[A-Z_]*_RE=' "$HOOK" && grep -qE '^RULING_PERM_RE=' "$LIB"; then
  echo "  PASS: L2 the hook sources the shared lib and carries no RULING_*_RE definition of its own"; PASS=$((PASS+1))
else echo "  FAIL: L2 the hook must source TFC_LIB and define no RULING_*_RE cue (one definition site: the lib)" >&2; FAIL=$((FAIL+1)); fi

# AK / AL — the `ask` cue (group `shared+ask`, reachable from this hook only). A brief that says "ask the operator"
# about how leftover items are DISPOSED OF (run them as a new pipeline vs record them as not fixed) is a technical
# routing call, not a scope ask. AK1-AK5 are synthesized from a description of the 2026-10-14 incident, not its text.
# AL1-AL8 are genuine operator asks and near-misses that must stay allowed; AL9-AL11 are the STATED RESIDUAL
# (ownership-only and scope-limited phrasings) pinned as allow so a later session cannot claim they are covered.
run_ruling "AK1 ownership plus disposition of named roadmap items" deny ruling \
  "$(qobj "Roadmap items 3 and 4 were listed in the brief but the fix only covers item 1. Who owns items 3 and 4 - should they be run as a new pipeline, or recorded as not fixed?" | mq_payload)"
run_ruling "AK2 handle here, run as a new pipeline, or record as not fixed" deny ruling \
  "$(qobj "Should the remaining roadmap items be handled in this PR, run as a new pipeline, or recorded as not fixed?" | mq_payload)"
run_ruling "AK3 two-option disposition with letters" deny ruling \
  "$(qobj "These remaining items are outside the original fix. Run them as a new pipeline now (a), or record them as not fixed (b)?" | mq_payload)"
run_ruling "AK4 start a new pipeline or leave not fixed" deny ruling \
  "$(qobj "Should I start a new pipeline for the leftover items or leave them not fixed?" | mq_payload)"
run_ruling "AK5 lowercased, differently punctuated" deny ruling \
  "$(qobj "who owns the leftover items? run them as a separate pipeline, or note them as unfixed?" | mq_payload)"
run_ruling "AL1 drop an item from a release (a genuine scope ask)" allow none \
  "$(qobj "Drop item 3 from this release?" | mq_payload)"
run_ruling "AL2 defer a change to next quarter (a genuine schedule ask)" allow none \
  "$(qobj "Should I defer the billing change to next quarter?" | mq_payload)"
run_ruling "AL3 an authorization to run the new pipeline" allow none \
  "$(qobj "Approve running the new pipeline for items 3 and 4?" | mq_payload)"
run_ruling "AL4 an assignment ask between two people" allow none \
  "$(qobj "Who should own the remaining items, Alice or Bob?" | mq_payload)"
run_ruling "AL5 the route half only" allow none \
  "$(qobj "Do you want the remaining items run as a new pipeline, or should I drop them?" | mq_payload)"
run_ruling "AL6 the record half only" allow none \
  "$(qobj "Should I record the migration as not fixed and tell the customers?" | mq_payload)"
run_ruling "AL7 both halves, but a permission shape exempts it" allow none \
  "$(qobj "Is it okay to run items 3 and 4 as a new pipeline instead of recording them as not fixed?" | mq_payload)"
run_ruling "AL8 both halves, vetoed by operator vocabulary (launch)" allow none \
  "$(qobj "Should I move the launch of items 3 and 4 into a new pipeline or mark them not fixed?" | mq_payload)"
run_ruling "AL9 stated residual: ownership wording only, no disposition pair" allow none \
  "$(qobj "Which of the two roadmap items does this PR own? Option A: both. Option B: only the first." | mq_payload)"
run_ruling "AL10 stated residual: a bare ownership question" allow none \
  "$(qobj "Who owns the remaining roadmap items?" | mq_payload)"
run_ruling "AL11 stated residual: a scope-limited question" allow none \
  "$(qobj "Is the scope of this fix limited to item 1, or does it include roadmap items 3 and 4? Ask once then act." | mq_payload)"
run_ruling "AK6 per segment: a later question carries both halves" deny ruling \
  "$(qobj "Is the audit ready? Should the leftover items run as a new pipeline or be recorded as not fixed?" | mq_payload)"
# Review-driven pins (2026-10-14): each row kills a surviving mutant of the ask cue.
run_ruling "AL12 two unrelated questions are not one disposition ask (per-segment)" allow none \
  "$(qobj "Should I run the migration as a new pipeline? Should I note the backup as unfixed?" | mq_payload)"
run_ruling "AL13 the ask-only veto: a sentence that names scope stays the operator's" allow none \
  "$(qobj "Item 3 is out of scope per your brief; should it be run as a new pipeline or recorded as not fixed?" | mq_payload)"
run_ruling "AL14 the ask-only veto: a sentence that names defer stays the operator's" allow none \
  "$(qobj "Should I defer items 3 and 4 as a new pipeline or record them as not fixed?" | mq_payload)"
run_ruling "AL15 ROUTE is pipeline-shaped: a triage ask about an issue is not a routing call" allow none \
  "$(qobj "Should I file a new issue for the typo or note it as not addressed?" | mq_payload)"
run_ruling "AL16 no question mark: the weak-cue block is not entered" allow none \
  "$(qobj "Run them as a new pipeline now, or record them as not fixed." | mq_payload)"
run_ruling "AL17 the RECORD gap is bounded at 30 characters" allow none \
  "$(qobj "Should I record the remaining roadmap items from the earlier brief as not fixed, or run them as a new pipeline?" | mq_payload)"
run_ruling "AL18 stated residual: the halves only in the option labels (never read)" allow none \
  "$(qobj "How should I handle roadmap items 3 and 4?" "Run as a new pipeline" "start the work as a new pipeline" "Record as not fixed" "leave them as known gaps" | mq_payload)"
run_ruling "AL19 stated residual: a permission-shaped question with both halves" allow none \
  "$(qobj "Approve running the remaining items as a new pipeline, or recording them as not fixed?" | mq_payload)"
# AK1 reason: the ask lead replaces the generic ruling lead. Checked on the lead (line 1) and on the tail: the ask reason
# carries its own tail (no ADR-flip paragraph, no second reword), the generic reasons never carry the ask lead.
TOTAL=$((TOTAL+1))
ak_reason=$(qobj "Roadmap items 3 and 4 were listed in the brief but the fix only covers item 1. Who owns items 3 and 4 - should they be run as a new pipeline, or recorded as not fixed?" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
ak_lead=$(head -n 1 <<<"$ak_reason")
r1_reason=$(qobj "$R1_Q" | mq_payload | "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
if grep -qF 'items the brief already named' <<<"$ak_lead" && grep -qF 'spawn soleur:engineering:cto' <<<"$ak_lead" && grep -qF 'DROP, DEFER or ADD' <<<"$ak_lead" \
   && ! grep -qF 'puts a TECHNICAL RULING' <<<"$ak_reason" && ! grep -qF 'run the grader' <<<"$ak_reason" \
   && grep -qF 'Then split the item' <<<"$ak_reason" && grep -qF 'pending - assumed' <<<"$ak_reason" \
   && ! grep -qF 'items the brief already named' <<<"$r1_reason" && grep -qF 'puts a TECHNICAL RULING' <<<"$r1_reason"; then
  echo "  PASS: AK1b the ask denial has its own lead and tail; a generic ruling denial keeps the generic lead"; PASS=$((PASS+1))
else echo "  FAIL: AK1b the ask reason lead/tail is wrong, or a generic denial carries the ask lead" >&2; FAIL=$((FAIL+1)); fi
# AK1c — the incident message names the cue that fired, so the ledger can tell an ask denial from the other ruling denials
# (the miss, cue, fixture loop counts per cue). The ledger is the suite's own sandbox, written by the AK/R rows above.
TOTAL=$((TOTAL+1))
ak_ledger="${INCIDENTS_REPO_ROOT:?sandbox root unset}/.claude/.rule-incidents.jsonl"
if [[ -s "$ak_ledger" ]] && grep -qF '[cue=ask]' "$ak_ledger" && grep -qF '[cue=strict]' "$ak_ledger"; then
  echo "  PASS: AK1c the incident message carries the cue name ([cue=ask] and [cue=strict] both recorded)"; PASS=$((PASS+1))
else echo "  FAIL: AK1c the incident ledger lacks [cue=ask] or [cue=strict] (the deny message must name the cue)" >&2; FAIL=$((FAIL+1)); fi
# NR3 — the group argument is honoured by the lib itself: `shared` and `shared+closing` never reach the ask cue, only
# `shared+ask` does, and it reports the cue name. A lib that ignored the group (or set ask=1 for every group) fails here.
TOTAL=$((TOTAL+1))
nr3_unit="these remaining items are outside the original fix. run them as a new pipeline now (a), or record them as not fixed (b)?"
# shellcheck disable=SC1090  # the lib path is a variable by design
nr3_out="$( ( . "$LIB" 2>/dev/null
  tfc_is_fork "$nr3_unit" shared; a=$?
  tfc_is_fork "$nr3_unit" shared+closing; b=$?
  tfc_is_fork "$nr3_unit" shared+ask; c=$?
  h="${TFC_HIT:-}"
  tfc_is_fork "what is the right design for the retry queue?" shared; d=$?
  tfc_is_fork "what is the right design for the retry queue?" shared+closing; e=$?
  printf '%s %s %s %s %s %s' "$a" "$b" "$c" "$h" "$d" "$e" ) )"
if [[ "$nr3_out" == "1 1 0 ask 1 0" ]]; then echo "  PASS: NR3 the lib honours the group: shared and shared+closing pass, shared+ask hits with TFC_HIT=ask, plain shared stays closing-blind"; PASS=$((PASS+1))
else printf '  FAIL: NR3 got "%s", want "1 1 0 ask 1 0"\n' "$nr3_out" >&2; FAIL=$((FAIL+1)); fi

# ML2 — version skew: a lib that predates group shared+ask answers exit 2 for it. The hook must announce that and fall back
# to group shared, so every OTHER ruling cue keeps working (R1 still denies) while the ask cue is off (AK3 allows).
TOTAL=$((TOTAL+1))
m2_root="${SOLEUR_TEST_INCIDENT_ROOT:?sandbox root unset}/m2-lib-skew"
m2_fail=0
assert_fixture_dir "$m2_root"
mkdir -p "$m2_root/lib" || m2_fail=1
if [[ "$m2_fail" -eq 0 ]]; then
  for m2_f in "$(dirname "$HOOK")"/lib/*.sh; do cp "$m2_f" "$m2_root/lib/" || m2_fail=1; done
  cp "$HOOK" "$m2_root/pre-ask-technical-fork-gate.sh" || m2_fail=1
  sed -i '/^    shared+ask) ask=1 ;;$/d' "$m2_root/lib/technical-fork-cues.sh" || m2_fail=1
  cmp -s "$LIB" "$m2_root/lib/technical-fork-cues.sh" && m2_fail=1
fi
m2_err="$m2_root/skew.stderr"
m2_r1=$(qobj "$R1_Q" | mq_payload | bash "$m2_root/pre-ask-technical-fork-gate.sh" 2>"$m2_err" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
m2_ak_out=$(qobj "These remaining items are outside the original fix. Run them as a new pipeline now (a), or record them as not fixed (b)?" | mq_payload | bash "$m2_root/pre-ask-technical-fork-gate.sh" 2>/dev/null)
m2_ak=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${m2_ak_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$m2_fail" -eq 0 && "$m2_r1" == "deny" && "$m2_ak" == "allow" ]] && grep -qF 'retrying with group shared' "$m2_err"; then
  echo "  PASS: ML2 a lib without group shared+ask is announced and falls back to shared (R1 still denies, the ask cue is off)"; PASS=$((PASS+1))
else printf '  FAIL: ML2 skew: setup_fail=%s r1=%s ask=%s (want 0/deny/allow plus the stderr line)\n' "$m2_fail" "$m2_r1" "$m2_ak" >&2; FAIL=$((FAIL+1)); fi

# NR1 — the pre-ask hook is NOT widened for the CLOSING cues (it asks for `shared+ask`, which adds only the ask cue).
# The five sentences the plan measured against the pre-ask cues (the three closing-message questions that must block
# there, and two that must pass) still ALLOW through an AskUserQuestion: the closing group's cues are reachable only
# from the closing hook. A lib that ignored its group argument, or a
# hook that asked for `shared+closing`, would deny the first three.
TOTAL=$((TOTAL+1))
nr1_fail=0
nr1_i=0
for nr1_q in \
  "is the existing census enough to close the G2 issue, given a personal CLI token not listed and a branch-nameable write token on another config?" \
  "what is the right design for moving the three deploy-channel credentials out of branch-nameable storage?" \
  "should the two credentials be rotated now, and in what order?" \
  "Do you authorize rotating HCLOUD_TOKEN now?" \
  "which option do you want for the landing page headline?"; do
  nr1_i=$((nr1_i+1))
  ruling_check "NR1.$nr1_i" allow none "$(qobj "$nr1_q" | mq_payload)" || nr1_fail=$((nr1_fail+1))
done
if [[ "$nr1_fail" -eq 0 ]]; then echo "  PASS: NR1 the five closing-message sentences still ALLOW through AskUserQuestion (pre-ask is not widened)"; PASS=$((PASS+1))
else FAIL=$((FAIL+1)); fi

# NR2 — closing-only phrasings that the pre-ask hook must not deny, and a control that still does. The first two
# are CL2 shapes; the control is a SHARED cue, which both hooks judge.
TOTAL=$((TOTAL+1))
nr2_fail=0
ruling_check "NR2a" allow none "$(qobj "what is the right design for the retry queue?" | mq_payload)" || nr2_fail=$((nr2_fail+1))
ruling_check "NR2b" allow none "$(qobj "do you want a migration design?" | mq_payload)" || nr2_fail=$((nr2_fail+1))
ruling_check "NR2c" deny ruling "$(qobj "how strict should the evidence bar be?" | mq_payload)" || nr2_fail=$((nr2_fail+1))
if [[ "$nr2_fail" -eq 0 ]]; then echo "  PASS: NR2 closing-only phrasings allow, the shared cue still denies (group argument honoured)"; PASS=$((PASS+1))
else FAIL=$((FAIL+1)); fi

# ML1 — a missing lib is parse doubt, never a blanket deny. The hook is copied beside a lib directory that lacks the
# cue file; the ruling arm is skipped with a stderr line and the R1 ruling question is ALLOWED. A control run against
# a copy that HAS the lib must still deny, or the row would pass over a hook that never reaches the arm at all.
TOTAL=$((TOTAL+1))
m1_root="${SOLEUR_TEST_INCIDENT_ROOT:?sandbox root unset}/m1-missing-lib"
m1_fail=0
assert_fixture_dir "$m1_root"
mkdir -p "$m1_root/with/lib" "$m1_root/without/lib" || m1_fail=1
if [[ "$m1_fail" -eq 0 ]]; then
  for m1_f in "$(dirname "$HOOK")"/lib/*.sh; do
    cp "$m1_f" "$m1_root/with/lib/" || m1_fail=1
    [[ "${m1_f##*/}" == "technical-fork-cues.sh" ]] || cp "$m1_f" "$m1_root/without/lib/" || m1_fail=1
  done
  cp "$HOOK" "$m1_root/with/pre-ask-technical-fork-gate.sh" || m1_fail=1
  cp "$HOOK" "$m1_root/without/pre-ask-technical-fork-gate.sh" || m1_fail=1
fi
m1_json="$(qobj "$R1_Q" | mq_payload)"
m1_ctl=$(printf '%s' "$m1_json" | bash "$m1_root/with/pre-ask-technical-fork-gate.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
m1_err_file="$m1_root/without.stderr"
m1_out=$(printf '%s' "$m1_json" | bash "$m1_root/without/pre-ask-technical-fork-gate.sh" 2>"$m1_err_file")
m1_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${m1_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$m1_fail" -eq 0 && "$m1_ctl" == "deny" && "$m1_dec" == "allow" ]] && grep -qF 'cue lib missing or incomplete' "$m1_err_file"; then
  echo "  PASS: ML1 a missing cue lib allows with a stderr line (control with the lib still denies)"; PASS=$((PASS+1))
else printf '  FAIL: ML1 missing-lib: setup_fail=%s control=%s without_lib=%s (want 0/deny/allow plus the stderr line)\n' "$m1_fail" "$m1_ctl" "$m1_dec" >&2; FAIL=$((FAIL+1)); fi

# ML3 — a lib that lost one of its ask constants is parse doubt: an EMPTY TFC_ASK_VETO_RE would veto every segment and an empty
# ROUTE/RECORD would match every line, so tfc_self_check must refuse it and the ruling arm must be skipped with the stderr line.
TOTAL=$((TOTAL+1))
m3_root="${SOLEUR_TEST_INCIDENT_ROOT:?sandbox root unset}/m3-empty-ask-constant"
m3_fail=0
assert_fixture_dir "$m3_root"
mkdir -p "$m3_root/lib" || m3_fail=1
if [[ "$m3_fail" -eq 0 ]]; then
  for m3_f in "$(dirname "$HOOK")"/lib/*.sh; do cp "$m3_f" "$m3_root/lib/" || m3_fail=1; done
  cp "$HOOK" "$m3_root/pre-ask-technical-fork-gate.sh" || m3_fail=1
  sed -i "s/^TFC_ASK_VETO_RE=.*/TFC_ASK_VETO_RE=''/" "$m3_root/lib/technical-fork-cues.sh" || m3_fail=1
  cmp -s "$LIB" "$m3_root/lib/technical-fork-cues.sh" && m3_fail=1
fi
m3_err="$m3_root/empty.stderr"
m3_out=$(qobj "$R1_Q" | mq_payload | bash "$m3_root/pre-ask-technical-fork-gate.sh" 2>"$m3_err")
m3_dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${m3_out:-{\}}" 2>/dev/null || echo allow)
if [[ "$m3_fail" -eq 0 && "$m3_dec" == "allow" ]] && grep -qF 'cue lib missing or incomplete' "$m3_err"; then
  echo "  PASS: ML3 a lib with an emptied ask constant fails the self-check and the ruling arm is skipped with a stderr line"; PASS=$((PASS+1))
else printf '  FAIL: ML3 empty-constant: setup_fail=%s decision=%s (want 0/allow plus the stderr line)\n' "$m3_fail" "$m3_dec" >&2; FAIL=$((FAIL+1)); fi

# V4— the ruling arm's EXEMPTION must stay a permission-shape vocabulary. Structural, like V3: extract
# the regex from the hook source, require a non-vacuous member count, and refuse any bare action verb. A
# bare verb here would exempt every ruling that merely MENTIONS the action ("...before the rebirth is
# dispatched and the volume deleted") and turn the arm off for the sentences it exists to catch.
TOTAL=$((TOTAL+1))
# The cue regexes live in the shared lib (technical-fork-cues.sh). Read the VALUE by sourcing the lib in a
# subshell, never by sed over its source text: the lib builds RULING_OPVOCAB_RE by concatenation, so a text
# read would see the assignment expression, not the regex.
# shellcheck disable=SC1090  # the lib path is a variable by design; the value is read by sourcing
v4_re="$( ( . "$LIB" 2>/dev/null; printf '%s' "${RULING_PERM_RE:-}" ) )"
v4_re="${v4_re#(}"; v4_re="${v4_re%)}"
if [[ -z "$v4_re" ]]; then
  printf '  FAIL: V4 could not extract RULING_PERM_RE from the hook — the member checks below would pass over an empty set\n' >&2
  FAIL=$((FAIL+1))
else
  v4_n=0; v4_bad=""
  while IFS= read -r v4_m; do
    [[ -n "$v4_m" ]] || continue
    v4_n=$((v4_n+1))
    v4_bare="${v4_m//\\b/}"
    case "$v4_bare" in
      delete|dispatch|deploy|merge|rotate|revoke|replace|destroy|flip|apply|arm|rollout|"roll out"|"roll ?out"|force-push|"should i"|"should we") v4_bad="$v4_bad $v4_m" ;;
    esac
  done <<< "$(printf '%s\n' "$v4_re" | tr '|' '\n')"
  if [[ "$v4_n" -lt 6 ]]; then
    printf '  FAIL: V4 the exemption split yielded only %s member(s) (floor 6) — a near-empty set proves nothing\n' "$v4_n" >&2
    FAIL=$((FAIL+1))
  elif [[ -n "$v4_bad" ]]; then
    printf '  FAIL: V4 RULING_PERM_RE carries a bare action verb:%s — it would exempt any ruling that merely mentions the action\n' "$v4_bad" >&2
    FAIL=$((FAIL+1))
  else
    printf '  PASS: V4 the ruling exemption has %s permission-shape members and no bare action verb\n' "$v4_n"; PASS=$((PASS+1))
  fi
fi

# V5 — dispatch non-vacuity. Every distinct-vocabulary DENY row (R1 R2 Z2 Z3, the strong-cue witnesses C1-C7b, and one
# witness per cue member K1-K9, evidence noun N1-N8, technical noun M1-M6) must have been denied with THIS arm's reason.
# An emptied or mis-ordered cue makes every row read allow or fall to another arm, and a suite that only checks the
# decision would not say the arm never ran.
TOTAL=$((TOTAL+1))
v5_n=0; v5_missing=""
v5_rows="R1 R2 Z2 Z3 AK1 AK2 AK3 AK4 AK5 AK6 C1 C2 C3 C4 C5 C6 C7 C7b K1 K2 K3 K4 K5 K6 K7 K8 K9 K10 N1 N2 N3 N4 N5 N6 N7 N8 M1 M2 M3 M4 M5 M6"
v5_want=0
for v5_r in $v5_rows; do
  v5_want=$((v5_want+1))
  if [[ " $RULING_HIT_NAMES " == *" $v5_r "* ]]; then v5_n=$((v5_n+1)); else v5_missing="$v5_missing $v5_r"; fi
done
if [[ "$v5_n" -eq "$v5_want" && "$v5_want" -ge 42 ]]; then
  echo "  PASS: V5 all $v5_want distinct-vocabulary deny rows reached the ruling arm's reason"; PASS=$((PASS+1))
else
  printf '  FAIL: V5 only %s of %s distinct-vocabulary rows reached the ruling reason; missing:%s\n' "$v5_n" "$v5_want" "$v5_missing" >&2; FAIL=$((FAIL+1))
fi

TOTAL=$((TOTAL+1))
if [[ "$TOTAL" -eq 175 ]]; then echo "  PASS: V1 full inventory ran (175 cases)"; PASS=$((PASS+1))
else echo "  FAIL: V1 expected 175 cases, ran $TOTAL" >&2; FAIL=$((FAIL+1)); fi

# --- V2: INSTRUMENT SELF-TEST — the helper's two branches must go to DIFFERENT buckets ------------
#
# Measured on this file: paying `PASS=$((PASS+1))` from `run_case`'s FAIL branch reported `17/17
# passed` and exited 0 while every `FAIL:` line still printed to stderr, so the human-readable and
# machine verdicts actively disagreed. The accounting identity below CANNOT see it — exactly one
# bucket pays per case either way, so `PASS + FAIL == TOTAL` holds under the swap. Nor can any floor:
# they all bound how MUCH was counted, never WHERE it landed.
#
# Only driving both branches catches it. Each is run in a subshell with its own counters, against the
# real hook, with a payload whose correct decision is known — so the expectation, not the hook, is
# what differs between the two. `V2` is the reason a misrouted verdict cannot ship green; it is the
# same gap the lint battery's H1 has, and the same remedy.
v2_probe() { # <expect> -> "PASS/FAIL" from a single isolated case
  ( PASS=0; FAIL=0; TOTAL=0
    run_case "v2 instrument self-test" "$1" \
      "Approve the production deploy of the retry fix?" \
      "Yes, deploy now" "ship it" "No, hold" "wait for the window" >/dev/null 2>&1
    printf '%s/%s' "$PASS" "$FAIL" )
}
# The payload is an authorization, so the hook allows it. Expecting `allow` must pay PASS; expecting
# `deny` must pay FAIL. Any other pair of readings means the buckets are crossed or one is dead.
v2_ok="$(v2_probe allow)"
v2_bad="$(v2_probe deny)"
if [[ "$v2_ok" != "1/0" || "$v2_bad" != "0/1" ]]; then
  printf '\nFATAL: instrument: run_case does not discriminate — a satisfied expectation scored %s and a violated one scored %s (want 1/0 and 0/1). The verdict helper is misrouting, so every PASS above is unproven.\n' \
    "$v2_ok" "$v2_bad" >&2
  exit 1
fi

# --- V2b: DECIDER SELF-TEST — ruling_check must pass what it should and fail what it should ---------
#
# V2 proves `run_case` routes verdicts to the right bucket. It says nothing about `ruling_check`, which every
# R/Z/W/C/K/N/M/Q row goes through. Measured: neutering its decision comparator, or its reason-content branch, left
# the suite green. A ruling row that expects `deny` therefore passed against an allow, and one that expects the
# ruling reason passed against the investigation reason. Only driving the decider with KNOWN-good and KNOWN-bad
# inputs catches a decider that always says yes: the expectation, not the hook, is what differs.
#
# Each control runs `run_ruling` in a subshell with its own counters against the real hook. Reported with printf and
# `exit 1`, never through the helper under test (ADR-193): a check routed through the machinery it backstops is
# disarmed by the same edit it exists to catch.
v2b_probe() { # <expect> <mode> <payload-json> -> "PASS/FAIL" from one isolated run_ruling
  ( PASS=0; FAIL=0; TOTAL=0
    run_ruling "v2b instrument self-test" "$1" "$2" "$3" >/dev/null 2>&1
    printf '%s/%s' "$PASS" "$FAIL" )
}
v2b_allow_json="$(qobj "Approve the merge of PR 9628?" | mq_payload)"
v2b_rule_json="$(qobj "$R1_Q" | mq_payload)"
v2b_invest_json="$(qobj "How should I resolve the cutover path?" "Read the runbook properly first" "find the documented order" "Ask whoever owns the cutover section" "the plan deferred it" | mq_payload)"
v2b_i="$(v2b_probe deny ruling "$v2b_allow_json")"      # an allow payload expected to deny      -> must FAIL
v2b_ii="$(v2b_probe deny ruling "$v2b_rule_json")"      # a ruling deny expected to deny ruling   -> must PASS
v2b_iii="$(v2b_probe deny ruling "$v2b_invest_json")"   # an investigation deny expected ruling   -> must FAIL
v2b_iv="$(v2b_probe allow none "$v2b_rule_json")"       # a deny payload expected to allow        -> must FAIL
v2b_v="$(v2b_probe deny invest "$v2b_rule_json")"       # a ruling deny expected investigation    -> must FAIL
v2b_vi="$(v2b_probe deny invest "$v2b_invest_json")"    # an investigation deny expected the same -> must PASS
if [[ "$v2b_i" != "0/1" || "$v2b_ii" != "1/0" || "$v2b_iii" != "0/1" || "$v2b_iv" != "0/1" || "$v2b_v" != "0/1" || "$v2b_vi" != "1/0" ]]; then
  printf '\nFATAL: instrument: ruling_check does not discriminate — pass/fail for (allow-as-deny, ruling, invest-as-ruling, deny-as-allow, ruling-as-invest, invest) was %s %s %s %s %s %s (want 0/1 1/0 0/1 0/1 0/1 1/0). The ruling decider is neutered, so every ruling row above is unproven.\n' \
    "$v2b_i" "$v2b_ii" "$v2b_iii" "$v2b_iv" "$v2b_v" "$v2b_vi" >&2
  exit 1
fi

# --- ACCOUNTING CONSERVATION + ASSERTION FLOOR ----------------------------------------------------
# Measured on this file: paying `PASS=$((PASS+1))` from the FAIL branch reported `17/17 passed` and
# exited 0 while every `FAIL:` line still printed — to stderr, where the footer's own claim
# contradicted it. Nothing reddened, because `TOTAL` increments once per case regardless of branch and
# nothing compared the buckets against it. The same shape appears in this PR's lint battery, and both
# get the same remedy: a case must land in exactly one bucket, and the buckets must account for the
# population.
#
# Reported with printf + exit 1, never through a verdict helper — a floor routed through the
# machinery it backstops is disarmed by the same edit it exists to catch (ADR-193).
if (( PASS + FAIL != TOTAL )); then
  printf '\nFATAL: accounting: PASS(%d) + FAIL(%d) != TOTAL(%d) — a case was counted but landed in neither bucket, or in both.\n' \
    "$PASS" "$FAIL" "$TOTAL" >&2
  exit 1
fi
# The floor is the inventory literal V1 already pins, so there is ONE number to change when a case is
# added and V1 names it in its own message. A suite that ran no cases, or whose verdict helper stopped
# paying anything, cannot satisfy it.
MIN_CASES=175
if (( TOTAL < MIN_CASES )); then
  printf '\nFATAL: anti-vacuity: %d case(s) ran, floor is %d. The suite shrank rather than the hook improving.\n' \
    "$TOTAL" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
