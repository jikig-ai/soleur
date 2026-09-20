#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion. Denies questions that ask the OPERATOR to pick between
# TECHNICAL INVESTIGATION paths — reading a runbook, checking a file, asking an owner. Soleur
# operators are non-technical by design; a question they cannot answer is not a question, it is
# the agent declining to do its job and stalling the pipeline until someone guesses.
#
# WHAT IS AND IS NOT THE OPERATOR'S CALL — the distinction this hook encodes:
#
#   THEIRS (allow):     an irreversible or production-mutating action (merge, replace, destroy,
#                       arm, flip, delete, force-push, deploy, rotate, revoke), money, scope,
#                       priority, or schedule. These need authority the agent does not have.
#   NOT THEIRS (deny):  which file to read, which hypothesis to chase, whether to consult the
#                       runbook/ADR/issue, who to ask. These need only effort the agent has.
#
# **Why:** 2026-08-19 — mid-cutover the agent asked "read the runbook properly first, or ask
# whoever owns #7462's cutover section?". The runbook was two commands away and answered the
# question definitively, including that the immediately preceding operator action had been wrong.
# Three days of dead-ends preceded it, all downstream of an ordered sequence in the linked issue
# that was never opened. `hr-exhaust-all-automated-options-before` and
# `hr-never-label-any-step-as-manual-without` already forbid this; prose did not hold, so this is
# the mechanical form.
#
# CONSERVATIVE BY CONSTRUCTION, WITH ONE DECLARED CARVE-OUT. The deny needs an investigative signal
# AND the absence of any authority signal. A question that mentions BOTH ("investigate, or merge with
# [ack-destroy]?") is ALLOWED — an ask that carries a real authorization is never blocked on the
# strength of one co-occurring word. This fails toward permitting, because a wrongly-blocked
# authorization is a production action taken without consent, which is strictly worse than a
# wrongly-permitted question.
#
# THE CARVE-OUT: the EXTERNAL EXPERT arm below is evaluated AHEAD of the authority short-circuit and
# denies on a profession noun without requiring an investigative signal — so for that one vocabulary
# the polarity above is inverted, deliberately. Stated here rather than only at the arm, because this
# paragraph is the contract a reader takes away and an absolute claim it no longer honours is how a
# later session "fixes" the ordering and silently removes the routing. The arm's own comment block
# carries the reason (an accountant question always carries cost/scope/schedule, so behind the
# authority arm it is unreachable), its residual, and the `AUTHZ_VERB_RE` conjunct that returns real
# authorizations to the permitting side. Test D4 pins the ordering behaviourally.
#
# Escape hatch: SOLEUR_ACK_TECHNICAL_FORK=1 — announced, never silent.
#
# Fail-open: any infrastructure error exits 0 (allow), reporting itself via systemMessage and an
# incident row. A hook must never wedge the turn on its own bug.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$_LIB_DIR/incidents.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/incidents.sh"
fi
export SOLEUR_HOOK_NAME="pre-ask-technical-fork-gate"

command -v jq >/dev/null 2>&1 || {
  printf 'pre-ask-technical-fork-gate: SKIPPED — jq unavailable, question NOT scanned\n' >&2
  exit 0
}

# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
declare -f hook_parse_input >/dev/null 2>&1 || {
  echo "[pre-ask-technical-fork-gate] hook-input helper missing — guard did NOT run" >&2
  exit 0
}

INPUT=$(cat)
__HI_RAW="$INPUT"
# ADR-156/157 canonical parse-failure block: report, then let the DESIGNATED RESPONDER ask.
# guardrails.sh is registered on this tool too (A9) and is the one that emits the ask; this hook
# reports and exits 0. Deviating here is how a hook ends up silently un-gated (#7164 defect 2).
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "pre-ask-technical-fork-gate"
  hook_input_should_ask && { hook_input_emit_ask "pre-ask-technical-fork-gate"; exit 0; }
  exit 0
fi

[[ "$HOOK_TOOL_KIND" == "AskUserQuestion" ]] || exit 0

if [[ "${SOLEUR_ACK_TECHNICAL_FORK:-}" == "1" ]]; then
  jq -n '{systemMessage:"pre-ask-technical-fork-gate: disarmed by SOLEUR_ACK_TECHNICAL_FORK=1"}' 2>/dev/null
  exit 0
fi

# Flatten every operator-visible string: question text, option labels, option descriptions. The
# label alone is too thin — "Option A" carries no signal while its description says "read the
# runbook", and the description is what the operator actually reads.
# `if type == "string"` is load-bearing, not defensive garnish. Claude Code sends each option as an
# OBJECT (`{label, description}`), but a foreign harness may send a bare string, and `.label` on a
# string is a jq ERROR — jq exits 5 having already emitted the question, so `CORPUS` came back
# non-empty, the emptiness guard below did not fire, `2>/dev/null` ate the diagnostic, and EVERY
# label and description was silently dropped. That is precisely the loss the comment above says this
# corpus exists to prevent, and it is worse than an empty corpus because a truncated one looks clean:
# D4 denies on a word carried only in an option DESCRIPTION, so in that shape the arm went dark on
# exactly the input it exists to catch. Measured on this file before the fix.
__CORPUS_RC=0
CORPUS="$(printf '%s' "$__HI_RAW" | jq -r '
  ( .tool_input.questions // [] )[]
  | (.question // ""),
    ( (.options // [])[]
      | if type == "string" then . else (.label // ""), (.description // "") end )
' 2>/dev/null)" || __CORPUS_RC=$?
# A non-zero jq status means the corpus is PARTIAL, and a partial corpus must never be judged: every
# arm below is a positive match, so missing text can only ever produce a false allow. Fail toward
# permitting (this hook's stated polarity, see the header) but ANNOUNCE it — the silent version of
# this path is the could-not-measure/measured-clean collapse.
if [[ "$__CORPUS_RC" -ne 0 ]]; then
  printf 'pre-ask-technical-fork-gate: corpus extraction failed (jq rc=%s) — unrecognised questions/options shape, allowing without classification.\n' \
    "$__CORPUS_RC" >&2
  exit 0
fi
CORPUS="$(printf '%s' "$CORPUS" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')"
[[ -n "$CORPUS" ]] || exit 0

# THE QUESTION TEXT ALONE, as a second, narrower corpus. Used by exactly one conjunct below, and the
# distinction is what stops the expert arm's own exemption from being a one-word bypass.
#
# An AUTHORIZATION is asked in the QUESTION. An option LABEL reading "Approve" is a button — it is
# what the founder clicks, not what they are being asked to decide. Testing the authorization
# vocabulary against the full corpus therefore let any question be exempted by relabelling a button:
# measured, the suite's OWN deny fixtures escaped that way. "Should the new rack be capex or opex?"
# with an option labelled `Approve as capex`, and "Can you ask my accountant whether this is
# deductible?" with an option labelled `Approve`, both flipped from deny to ALLOW — two fixtures the
# suite carries specifically to prove the arm fires, disarmed by one word in a place the founder does
# not read as a question.
#
# The full corpus stays correct for DETECTION (a profession noun or an investigative cue is a real
# signal wherever it appears, which is why the option text is flattened in at all). It is only the
# EXEMPTION that has to be narrow, because an exemption is the one thing an author can add.
QUESTION_CORPUS="$(printf '%s' "$__HI_RAW" | jq -r '
  ( .tool_input.questions // [] )[] | (.question // "")
' 2>/dev/null | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')"

# EXTERNAL EXPERT signal — a question whose answer is held OUTSIDE the company, by a professional
# the founder pays: an accountant, a bookkeeper, a lawyer, a notary, an auditor, an insurer, a bank,
# a regulator, a landlord. The founder cannot answer it either, so putting it to them is the same
# dead end this hook exists to remove — one class over.
#
# THIS ARM IS EVALUATED BEFORE THE AUTHORITY SHORT-CIRCUIT, AND THAT ORDER IS THE WHOLE MECHANISM.
# Placed after it, the arm is unreachable: an accountant or lawyer question almost always carries a
# money word, and AUTHORITY_RE matches cost/budget/price/priorit/scope/schedule/spend and wins
# outright. ("capex or opex" arrives with "cost" in the same breath.) The surviving path then also
# demands INVESTIGATIVE_RE, which this class never matches. So a deny ladder naming the skill would
# have shipped as a string nothing could reach — measured, not supposed.
#
# THE RESIDUAL, STATED. This ordering means an authorization that merely NAMES one of these
# professions is denied rather than reaching the founder — the one direction this hook's header
# otherwise refuses to fail in. It is accepted because the remedy is cheap and announced in the
# reason text (re-word to name the action, or SOLEUR_ACK_TECHNICAL_FORK=1), whereas the failure it
# replaces is silent: the founder guesses at an accountant's answer and the guess becomes a filing.
# Word-anchored on purpose, and the anchoring is TWO-SIDED where it has to be — measured, because a
# leading `\b` alone is not enough. `\btax` rejects "syntax" (no boundary before "tax" there) but
# ACCEPTS "taxonomy", which begins at one; an AskUserQuestion about renaming an event taxonomy would
# have been denied and routed to a questionnaire. Hence `\btax(es|ation|able|payer)?\b`.
# `statutory` was proposed for this list and cut for the same reason at one remove: it is ambient in
# this repository's own compliance prose ("statutory clock", "statutory register"), it identifies no
# profession, and on this arm — which denies ahead of the authority short-circuit — it would have
# blocked authorization questions about breach-notification deadlines. The profession nouns plus
# `fiscal`/`vat`/`capex`/`opex` carry the intent without the collision.
# `tax` in a genuinely technical sentence ("fix the tax calculation bug") still matches; that is
# accepted rather than hidden, because an AskUserQuestion naming tax is far more often an
# accountant's question than a code question, and the reason text names the override.
# Every token here is RIGHT-anchored or bound to a profession sense, because the list's failure mode
# is one-directional: a domain term of art is always also somebody's ordinary noun, and the ordinary
# use is what an engineer types. Measured false positives that shaped this line, each found only by
# feeding real AskUserQuestion JSON: `\btax` accepted "taxonomy"; `statutory` is ambient compliance
# prose and was dropped; `\bregulator` accepted "regulatory" (43 files); `\bauditor` accepted the
# shipped agent name `legal-compliance-auditor` (210 hyphenated hits repo-wide); `\bamorti[sz]`
# accepted "amortized" (live in apps/web-platform/server/observability.ts and stream-replay-buffer.ts);
# `\bbank` accepted "bank holiday", which is SCHEDULE and therefore the founder's own call; and
# `\bfiscal\b` was dropped outright — its only three repo hits were this PR's own documents, and
# `capex`/`opex`/`vat`/`depreciat`/`payroll` already carry the accounting sense.
EXTERNAL_EXPERT_RE='(\baccountant|\bbookkeep|\blawyer|\bsolicitor|\bnotar(y|ies)|(^|[^A-Za-z0-9-])auditors?\b|\btax(es|ation|able|payer)?\b|\binsurer|\binsurance (claim|polic|premium|cover|renewal|broker)|\bbank(er|ing)\b|\bbank (account|statement|transfer|mandate|covenant)\b|\bregulators?\b|\blandlord|\bcapex|\bopex|\bdepreciat|\bamorti[sz]ation\b|\bpayroll|\bvat\b)'

# THE AUTHORIZATION EXEMPTION — this is what keeps the arm inside the invariant the header states,
# and it is a PREDICATE, not another token trim. Two tokens were removed from the list above by
# hand (`taxonomy` via a right-anchor, `statutory` outright) and review then measured four MORE
# false positives on the same axis: `\bregulator` accepted "regulatory" (43 files),
# `\bauditor` accepted the shipped agent name `legal-compliance-auditor`, `\bamorti[sz]` accepted
# "amortized" (live in apps/web-platform/server/observability.ts), and `\binsurance\b` accepted
# "insurance-claims". Trimming tokens one at a time was fixing the INSTANCE; the class needed the
# predicate to change, because the list can never be finished — any domain term of art is also
# somebody's ordinary noun.
#
# So the arm now requires an external-expert signal AND the absence of an authorization VERB,
# which is exactly the "conservative by construction" shape this file's header promises 90 lines
# above: "an ask that carries a real authorization is never blocked on the strength of one
# co-occurring word. This fails toward permitting, because a wrongly-blocked authorization is a
# production action taken without consent."
#
# It exempts on the ACTION-AUTHORIZING verbs only, never on the money nouns (`cost`, `budget`, `price`,
# `spend`, `priorit`, `scope`, `schedule`) that `AUTHORITY_RE` also carries. That split is the
# whole reason this arm exists: an accountant question arrives WITH a money noun ("treat the
# plugin revenue as capex or opex"), so exempting on those would restore the unreachability the
# arm was added to fix, while exempting on "approve"/"merge"/"deploy" costs nothing — a founder
# authorizing a deploy is not asking their accountant anything.
#
# It is NOT a strict subset of AUTHORITY_RE, and that is deliberate rather than drift:
# it spells `\bmerge` where AUTHORITY_RE has a bare `merge` (which also matches
# "submerge"), and it adds `roll ?out`, which AUTHORITY_RE lacks. Both differences make
# this arm exempt MORE readily than AUTHORITY_RE would, which is the safe direction for
# a DENY arm. The hook's own test pins the relationship so the two cannot drift apart
# unnoticed — review measured them disagreeing within one edit of each other.
# SELF-INVOCATION ALLOW ARM — evaluated BEFORE the expert arm, and it is what makes the skill the
# expert arm routes to actually runnable. Measured: `soleur:questionnaire-generate` Step 1 asks the
# founder "Who receives this?" with options labelled `Accountant` / `Lawyer`, because the recipient's
# role is one of exactly three fields its `## Context` allowlist permits — so the skill is SPECIFIED
# to emit the precise string the expert arm denies. Driven through this hook, both spellings of its
# own interview came back `deny`: the primary invocation path was a loop, and the advertised override
# is unreachable from a tool call because `SOLEUR_ACK_TECHNICAL_FORK` is read from the hook process
# environment and shell state does not persist between Bash calls.
#
# The exemption keys on the send-interview SHAPE, which is fixed by that skill's Step 1 and is not a
# phrase an ordinary technical or authorization ask produces. It is deliberately narrow: it does not
# allow on the mere presence of a profession noun, so an expert question that does not carry the
# interview shape is still denied.
#
# IT IS A CONJUNCT OF THE EXPERT ARM, NEVER A STANDALONE `exit 0`. An earlier revision of this file
# wrote it as its own `if … then exit 0` block placed here, ahead of every arm — which made it a
# WHOLE-HOOK BYPASS: any corpus carrying the interview phrase also skipped the AUTHORITY arm and, far
# worse, the INVESTIGATIVE default-deny at the bottom. Measured: this hook's own founding fixture (the
# 2026-08-19 technical fork it was built to refuse) was ALLOWED once `"Who receives this?"` was
# prefixed to it, and the suite stayed fully green because nothing asserted the investigative arm was
# still armed. The narrowing belongs to the arm it narrows; `D7` pins that scoping from the other side.
QUESTIONNAIRE_INTERVIEW_RE='(who (receives|should receive) (this|it)|what (has to|needs to|must) come back|who holds the answer)'

AUTHZ_VERB_RE='(ack-destroy|authori[sz]|approve|\bmerge|replace|destroy|delete|force-push|deploy|dispatch|apply |arm the|flip |rotate|revoke|roll ?out|proceed with the (merge|replace|destroy|apply|cutover))'
# Detection reads the FULL corpus; both exemptions read the QUESTION only. See the QUESTION_CORPUS
# comment above for why the asymmetry is the point rather than an oversight.
if grep -qE "$EXTERNAL_EXPERT_RE" <<<"$CORPUS" \
   && ! grep -qE "$AUTHZ_VERB_RE" <<<"$QUESTION_CORPUS" \
   && ! grep -qiE "$QUESTIONNAIRE_INTERVIEW_RE" <<<"$QUESTION_CORPUS"; then
  EXPERT_REASON="BLOCKED: this AskUserQuestion puts an OUTSIDE EXPERT's question to the founder.

The answer is held by an accountant, bookkeeper, lawyer, notary, auditor, insurer, bank, regulator or landlord — not by the founder, and not by you. Asking the founder produces a guess that then gets acted on.

Write them the questions instead: soleur:questionnaire-generate.

That skill interviews the founder about the SEND only — who receives it, what has to come back, by when — and emits one document they send from their own mail client. It never asks the founder about the subject matter, because not knowing the subject matter is why it is being used.

Ask the founder ONLY for: authorization for an irreversible or production-mutating action, money, scope, priority, or schedule.

If this question genuinely carries an authorization and the wording tripped the classifier, re-word it to name the action being authorized — or re-run with SOLEUR_ACK_TECHNICAL_FORK=1.

See hr-technical-fork-is-not-an-operator-question."

  declare -f emit_incident >/dev/null 2>&1 && \
    emit_incident pre-ask-technical-fork-gate deny "outside-expert question put to a non-expert founder" "$CORPUS" 2>/dev/null || true

  jq -n --arg r "$EXPERT_REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

# AUTHORITY signal — a real operator decision. Checked FIRST among the remaining arms and wins
# outright. (The external-expert arm above is the one decision evaluated ahead of it, and its
# comment block says why.)
AUTHORITY_RE='(ack-destroy|authori[sz]|approve|merge|replace|destroy|delete|force-push|deploy|dispatch|apply |arm the|flip |rotate|revoke|spend|cost|budget|price|priorit|scope|schedule|which (issue|feature|milestone)|proceed with the (merge|replace|destroy|apply|cutover))'
if grep -qE "$AUTHORITY_RE" <<<"$CORPUS"; then exit 0; fi

# INVESTIGATIVE signal — work the agent can do itself.
INVESTIGATIVE_RE='(read the |re-?read |check whether|check if|investigate|look at |look into|find out|diagnose|figure out|ask (the )?(owner|author|whoever)|consult the |search (the )?(repo|codebase|issue)|inspect the |grep |open the (runbook|adr|issue|plan|spec)|(runbook|adr|issue|plan|spec) first)'
if ! grep -qE "$INVESTIGATIVE_RE" <<<"$CORPUS"; then exit 0; fi

REASON="BLOCKED: this AskUserQuestion asks the operator to choose between TECHNICAL INVESTIGATION paths.

Soleur operators are non-technical. They cannot pick between 'read the runbook' and 'ask the owner', and asking stalls the pipeline until someone guesses. That choice is yours, and the work is cheap.

Resolve it yourself, in this order, before asking anything:
  1. The linked ISSUE's own ordered sequence   (gh issue view <N>)
  2. The RUNBOOK for the operation             (knowledge-base/engineering/operations/runbooks/)
  3. The ADR that owns the decision            (knowledge-base/engineering/architecture/decisions/)
  4. The guard's / script's own comments       (the code refusing you usually says why)
  5. If the answer is held OUTSIDE the company — by an accountant, lawyer, auditor, insurer, bank,
     regulator or landlord — the founder cannot answer it either. Write them the questions:
     soleur:questionnaire-generate.

Then ACT on what you find.

Ask the operator ONLY for: authorization for an irreversible or production-mutating action, money, scope, priority, or schedule.

If this question genuinely carries an authorization and the wording tripped the classifier, re-word it to name the action being authorized — or re-run with SOLEUR_ACK_TECHNICAL_FORK=1.

See hr-exhaust-all-automated-options-before and hr-never-label-any-step-as-manual-without."

declare -f emit_incident >/dev/null 2>&1 && \
  emit_incident pre-ask-technical-fork-gate deny "technical fork put to a non-technical operator" "$CORPUS" 2>/dev/null || true

jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
