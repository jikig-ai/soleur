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
PASS=0; FAIL=0; TOTAL=0
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
    printf '%s\n' "$v3_authority" | tr '|' '\n' | sed 's/\\b//g' | grep -qxF -- "$v3_bare" \
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

TOTAL=$((TOTAL+1))
if [[ "$TOTAL" -eq 19 ]]; then echo "  PASS: V1 full inventory ran (19 cases)"; PASS=$((PASS+1))
else echo "  FAIL: V1 expected 19 cases, ran $TOTAL" >&2; FAIL=$((FAIL+1)); fi

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
MIN_CASES=19
if (( TOTAL < MIN_CASES )); then
  printf '\nFATAL: anti-vacuity: %d case(s) ran, floor is %d. The suite shrank rather than the hook improving.\n' \
    "$TOTAL" "$MIN_CASES" >&2
  exit 1
fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
