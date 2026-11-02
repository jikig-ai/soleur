#!/usr/bin/env bash
# Shared cue vocabulary and verdict function for the two hooks that enforce
# `hr-technical-fork-is-not-an-operator-question` on a carrier a model controls:
#   pre-ask-technical-fork-gate.sh      (an AskUserQuestion tool call; group `shared+ask`)
#   pre-closing-technical-fork-gate.sh  (the closing message of a turn; group `shared+closing`)
#
# WHY ONE LIB. The 2026-10-12 miss was a carrier the pre-ask hook cannot read, and the first draft
# of the fix copied its cue list. Two copies of a vocabulary drift on the first edit (this repo's own
# twin-copy libs are held together by parity tests), so the cues and the one verdict function live
# here and both hooks call `tfc_is_fork`. A suite row in each hook's suite derives the definition
# sites and the callers from the tree and fails on a second definition.
#
# WHY IT HAS TO GROW AS WELL AS BE SHARED. Measured 2026-10-12: the existing cues match none of the
# three questions that triggered this work (evidence sufficiency, a design choice, an ordering), and
# the existing veto silences one of them (the word `deploy` inside `deploy-channel`). So the closing
# group adds three `?` cues and a narrower veto, plus one declarative cue (CL4, its own function `tfc_is_handoff`, 2026-10-19) and one label-sentence cue (its own function `tfc_is_label_handoff`, 2026-10-26); the pre-ask hook is NOT widened by them. It asks for `shared+ask`, which
# adds ONE cue of its own (`ask`, 2026-10-14: a brief's "ask the operator" question about how named leftover items are
# disposed of, run as a new pipeline vs recorded as not fixed). `shared` itself is unchanged; no production hook asks for
# plain `shared` first, but the pre-ask hook's version-skew fallback does (do not "clean it up"). The closing
# group never sets `ask`, so the Stop carrier cannot reach it: the cue was fitted to AskUserQuestion text, a closing
# message was never sampled against it, and a cue nobody measured on that carrier is not added to it.
#
# ON A WRONGFUL BLOCK (a closing message stopped that carried a real operator question):
#   1. Find the closing in the local session transcript by the ledger row's sha256 of the unit (the hash is of the
#      NORMALISED unit: lowercased, fences, quote lines and code spans stripped, CR and invisible characters removed,
#      whitespace squeezed, then cut at the last '. ' or '! '; hash each candidate sentence of the closing the same way).
#   2. Narrow the CLOSING cue in this file (a tighter shape, or a word in TFC_CLOSING_EXTRA_RE) and
#      add a must-PASS fixture to pre-closing-technical-fork-gate.test.sh; raise MIN_CASES and the
#      V1 literal together. That touches no other file.
#   3. A BUSINESS word is NEVER the fix: it changes the pinned RULING_OPVOCAB_RE literal and would
#      silence the pre-ask hook too. guard-vacuity-floor and the shard manifest need no change.
#
# CONTRACT
#   tfc_is_fork <unit> <groups>   exit 0 = technical fork (block), 1 = pass, 2 = bad arguments.
#       <unit> is ONE sentence, ALREADY lowercased and single-spaced by the caller. <groups> is
#       `shared`, `shared+closing` or `shared+ask`; anything else is exit 2 so a typo can never silently mean
#       "shared only". Prints nothing; sets the global TFC_HIT to the matching cue name. It MUST be
#       called in the current shell (never inside $(...)), or TFC_HIT is lost. No size cap lives
#       here: the pre-ask suite pins DENY on 30-60 KB questions, and the closing hook bounds what
#       it feeds this function itself.
#   tfc_self_check                exit 0 only if the lib was sourced COMPLETELY: `_TFC_COMPLETE` is the very last
#       statement of this file, so a truncated source never reaches it, and `tfc_is_fork` must be defined. An EMPTY
#       cue regex matches every line, so a consumer that sources a truncated lib must treat a failed self-check as
#       parse doubt and fail OPEN, never judge with it. (Ruled by CTO agent, 2026-10-12: a sentinel instead of a
#       per-variable list, which a new cue would silently miss.)
#
# PURE BY CONSTRUCTION: no set options, no emit_incident, no .claude/ or CLAUDE_PROJECT_DIR paths, no
# repo-specific nouns (so graduating the pair to the plugin is a move, not a rewrite). Linear regexes
# only (bounded gaps); no eval.

[[ -n "${_TFC_LOADED:-}" ]] && return 0
_TFC_LOADED=1

# ---- SHARED group: moved byte-identical from pre-ask-technical-fork-gate.sh (RULING_OPVOCAB_RE is recomposed from two halves, pinned equal)  ---------------------
RULING_STRICT_RE='(\bhow (strict|rigorous)|\b(strictness|stricter|stringen[a-z]*))'
RULING_EVID_NOUN_RE='\b(evidence|proof|check|gate|guard|validation|verification|criteria|assertion|test|lint)\b'
RULING_BAR_RE='(\b(evidence|proof|emptiness) (bar|threshold|ceiling|floor|standard)|\badopting\b.*\baccepted\b)'
RULING_SUFF_RE='\b(is|are) (the )?(evidence|proof) (enough|sufficient|adequate)'
RULING_STATUS_RE='\bstatus (flip|move|change)'
RULING_ADR_RE='\b(adopting|accepted|decision record)\b'
RULING_AB_RE='(\b(approach|variant|option) [ab]\b|\b[ab] (or|vs) [ab]\b)'
RULING_TECH_RE='\b(architecture|schema|algorithm|substrate|data model|retry|queue|refactor)\b'
RULING_PERM_RE='(\bmay i\b|\bis it fine to\b|\bok(ay)? to\b|\bgo-ahead\b|\bapprove[ds]?\b|\bauthori[sz]e|\back-destroy)'
# Operator vocabulary, split so the CLOSING cues can be vetoed by BUSINESS alone: the design of a
# deploy channel is technical, a landing-page headline is not. RULING_OPVOCAB_RE is their
# concatenation and is pinned byte-for-byte by a suite row (V8); `headline` is deliberately NOT a
# member (a new member would change that literal and silence the pre-ask hook).
TFC_BUSINESS_WORDS='prices?|pricing|plans?|tiers?|launch(es)?|dates?|deadlines?|licen[sc]es?|vendors?|logos?|copy|landing|budgets?|costs?|spend|revenue|invoices?|refunds?|schedules?|priorit(y|ies)|brand|hero'
TFC_ACTION_WORDS='merge|deploy|ship|releases?|delete|prod|production'
RULING_OPVOCAB_RE='\b('"${TFC_BUSINESS_WORDS}|${TFC_ACTION_WORDS}"')\b'
RULING_MONEY_RE='\b(charging|paying|refunds?|invoices?|price|pricing|costs?|spend|revenue|contract|vendors?)\b'

# ---- CLOSING group: new for the closing-message carrier ----------------------------------------
# CL1 sufficiency, CL2a/CL2b design, CL3 ordering. Each sits on a `?` sentence, so no co-signal is
# needed. (CL4, the declarative hand-off, is the one closing cue with no `?`: see `tfc_is_handoff` below.) Narrowed on purpose (never widened): CL2a needs an object, CL2b needs a technical noun.
TFC_CL1_RE='\b(is|are) [^?]{0,60}\b(evidence|census|inventory|coverage|audit|baseline|gate|proof)\b[^?]{0,60}\b(enough|sufficient|adequate)\b'
TFC_CL2A_RE='\b(what|which)( is|'"'"'s| are| would be)? (the )?(right|best|correct|proper|cleanest) (design|architecture|mechanism|approach) (for|to|of|when)\b'
TFC_CL2B_RE='\bdo you want (a|an|the) ([a-z -]{0,20} )?(migration|rotation|storage|credential|schema|pipeline|rollout|cutover)[a-z -]{0,20}(design|architecture)\b'
TFC_CL3_ORDER_RE='\b(in what|what|which) (order|sequence)\b'
TFC_CL3_NOUN_RE='\b(credentials?|tokens?|secrets?|keys?|configs?|configuration|storage|migrations?|cutover|pipelines?|schema|hosts?|rotat[a-z]*)\b'
TFC_BUSINESS_RE='\b('"${TFC_BUSINESS_WORDS}"')\b'
# CL4 declarative hand-off (2026-10-19, miss, cue, fixture): a closing that makes the operator the decider of a technical
# step WITHOUT a question mark ("Next step: your call. Tell me to build #10297.") was invisible to CL1-CL3, which all read `?`
# units. Review of the first draft (8 seats, PR #10547) found a broad "phrase + common noun" cue blocks courtesy closers
# ("let me know if you want the design doc") and operator authorizations ("say the word and I will merge #123"), so CL4 is
# deliberately narrow and lives in its OWN function, `tfc_is_handoff`, judged apart from the `?` cues: a declarative sentence
# never reaches the strong cues (bar, suff) and never spends the 12-unit `?` budget.
#   SELF  = an explicit instruction to start work ("tell me to build"): the verb is the technical-work noun.
#   PHRASE + NOUN = a hand-off phrase AND a DECISION noun (design, approach, order, sequencing, ruling, next step ...). Bare
#       `pr`, `fix`, `build`, `#N` are NOT decision nouns: they are everyday words in a courtesy closer.
# CANDIDATE is the one alternation the hook's prefilter and its awk emitter use, so the hook can never judge fewer
# sentences than this function accepts. It has no `\b`, so grep -E and awk read it the same way.
# PURE: no repo-specific nouns beyond the decision-noun list; the lib's graduation rule is unchanged.
TFC_CL4_SELF_ERE='(tell|ask) me to (build|implement|fix|draft|write|start)'
TFC_CL4_PHRASE_ERE='your call|up to you|^[^a-z]*(so |then |now )?you (decide|choose|pick)'
TFC_CL4_CANDIDATE_ERE="${TFC_CL4_SELF_ERE}|${TFC_CL4_PHRASE_ERE}"
TFC_CL4_NOUN_RE='\b(design|approach|sequenc[a-z]*|order(ing)?|ruling|rehearsal|diagnostic|collector|architecture|trade-?offs?|next steps?)\b'
# An authorization or production-mutating verb in the sentence makes it the operator's call, not a technical fork. This is the
# CL4 veto list; the closing-permission shapes (TFC_CLOSING_PERM_RE) are a second, separate exemption.
TFC_CL4_AUTH_RE='\b(flip|dispatch|rotate|rotation|wipe|delete|revoke|deploy|redeploy|apply|force[- ]push|arm (the|auto|it)|ack-destroy|go[- ]ahead|authori[sz]e[a-z]*|approv[a-z]*|merge|ship|release|push|revert|roll ?back|migrat[a-z]*|cutover|cancel|restart|prod|production)\b'
# A seed list tuned by the false-positive sample; applies to EVERY cue in the closing group (SHARED
# ones included) and to no cue in the pre-ask group.
TFC_CLOSING_EXTRA_RE='\b(prioriti[sz]\w*|publish\w*|announce\w*|auditors?|accountants?|lawyers?|investors?|customers?|features?|roadmap|milestones?)\b'

# LABEL arm (2026-10-26, Ruled by CTO agent; the last cue the ADR-084 tripwire budget allows): the final sentence of a closing that begins `Paused:` or
# `Blocked:` used to end the whole check, and a label whose own sentence handed a technical ruling to the operator ("... needs your
# ruling on whether this transient failure counts") passed it. `tfc_is_label_handoff` judges that ONE sentence (the text after the
# label colon), apart from the `?` cues and from CL4. One phrase only: `your ruling` after a verb of waiting, or on/about/as to
# whether|if|which. Measured on 2026-10-26 over 10,695 local label-ending messages: this phrase fired once (the incident) and never
# wrongly; the wider "your call" fired 19 times, 12 of them operator-class, so it is NOT a cue here. The next miss in a label sentence
# adds no cue: it opens the other ADR-084 remedy (judging a Decision-for-you list that carries no question mark), never a synonym.
# NEG is a negator within two words before the verb: "this is not awaiting your ruling" is a status line, "no need for your ruling" is not a request.
# The ledger hash for this cue covers the normalised text AFTER the label colon with the emphasis markers * and _ removed.
TFC_LABEL_PHRASE_ERE='\b(needs|needed|awaiting|awaits|requires|pending|waiting (on|for)) your ruling\b|\byour ruling (on|about|as to) (whether|if|which)\b'
TFC_LABEL_NEG_ERE='(\b(not|no longer|never|without|nothing|nobody|no one|none|previously|already)\b|n'"'"'t) ([a-z]+ ){0,2}(needs?|needed|awaiting|awaits?|pending|requires?|waiting (on|for)) your ruling|\bno need for your ruling\b'

# ASK group (2026-10-14, Ruled by CTO agent): the DISPOSITION of items a brief already named. A brief that says "ask the
# operator" about whether leftover roadmap items run as a new pipeline or are recorded as not fixed is a technical routing
# call, not a scope ask. Both halves (ROUTE and RECORD) must sit in the SAME '?' segment, inside the weak-cue block, so
# the operator-vocabulary veto and the permission exemption apply; TFC_ASK_VETO_RE (drop, defer, scope) additionally
# leaves a genuine scope ask to the operator. Named TFC_ASK_*, never RULING_*_RE (suite row L2 forbids a RULING_*_RE
# definition in the HOOK; the lib is the one definition site by convention).
# No ownership arm: "who should own the remaining items, Alice or Bob?" is an assignment ask and must stay allowed.
# RESIDUAL (stated in the pre-ask hook header): ownership-only and scope-limited phrasings, a split across two sentences,
# halves only in option labels, and permission-shaped questions are not caught; the skill text covers them. More than
# three TFC_ASK_* patterns, or a second paraphrase miss, means stop widening (ADR-084 addendum).
TFC_ASK_ROUTE_RE='(\b(as|in|via|into) (a |an )?(new|separate|fresh) (pipeline|one-shot|one shot)\b|\b(start|open|file|spin up)[a-z]* (a |an )?(new|separate|fresh) (pipeline|one-shot|one shot)\b)'
TFC_ASK_RECORD_RE='\b(record|note|mark|log|document|list|leave)[a-z]* [^?.;]{0,30}\b(not fixed|unfixed|not addressed|not done|known gaps?)\b'
TFC_ASK_VETO_RE='\b(drop(s|ped|ping)?|defer(s|red|ring)?|de-?scop[a-z]*|scope)\b'

# CLOSING-ONLY permission shapes (Ruled by CTO agent, 2026-10-12 review): an authorization request that the shared
# RULING_PERM_RE (pinned by the pre-ask suite, never edited for a closing-only reason) does not name. Each member binds
# the permission words to an ACTION verb, because bare `can i`, `should i`, `go ahead` or `proceed` are technical-fork
# shapes too ("should we go ahead with approach A or B", "can i proceed with approach A or B"): `go ahead`/`proceed` count only when followed by `and`/`to` plus an action verb. `should i` alone and every `we` form stay OUT on purpose.
TFC_CLOSING_PERM_RE='\b(can|shall) i (now |just )?(go ahead and |proceed (and|to) )?(merge|deploy|ship|release|rotate|flip|arm|delete|revoke|apply|push)\b|\bshould i go ahead and (merge|deploy|ship|release|rotate|flip|arm|delete|revoke|apply|push)\b'

tfc_self_check() {
  [[ -n "${_TFC_COMPLETE-}" ]] || return 1
  # An EMPTY ask regex matches every line (ROUTE/RECORD would deny, VETO would veto), so a lib that lost one is parse doubt.
  [[ -n "${TFC_ASK_ROUTE_RE-}" && -n "${TFC_ASK_RECORD_RE-}" && -n "${TFC_ASK_VETO_RE-}" ]] || return 1
  # Same reason for CL4: an empty ERE matches every sentence, so the hook would block every closing.
  [[ -n "${TFC_CL4_SELF_ERE-}" && -n "${TFC_CL4_PHRASE_ERE-}" && -n "${TFC_CL4_CANDIDATE_ERE-}" && -n "${TFC_CL4_NOUN_RE-}" && -n "${TFC_CL4_AUTH_RE-}" ]] || return 1
  # Same reason for the label arm: an empty phrase ERE would match every Blocked:/Paused: sentence, an empty negation ERE would veto none.
  [[ -n "${TFC_LABEL_PHRASE_ERE-}" && -n "${TFC_LABEL_NEG_ERE-}" ]] || return 1
  declare -f tfc_is_handoff >/dev/null 2>&1 || return 1
  declare -f tfc_is_label_handoff >/dev/null 2>&1 || return 1
  declare -f tfc_is_fork >/dev/null 2>&1 || return 1
  return 0
}

tfc_is_fork() {
  local unit="${1-}" groups="${2-}" closing=0 ask=0 hit="" asked ends seg
  # shellcheck disable=SC2034  # TFC_HIT is the function's output channel, read by the sourcing hook
  TFC_HIT=""
  case "$groups" in
    shared) ;;
    shared+closing) closing=1 ;;
    shared+ask) ask=1 ;;
    *) return 2 ;;
  esac
  [[ -n "$unit" ]] || return 1

  if [[ "$closing" -eq 1 ]] && grep -qE "$TFC_CLOSING_EXTRA_RE" <<<"$unit"; then
    return 1
  fi

  # WEAK cues (strictness + evidence noun, status flip + ADR word, approach A|B + technical noun) read
  # the INTERROGATIVE sentences only, so a unit with no `?` has none and a declarative sentence never
  # fires them. The operator-vocabulary veto reads the whole unit. Extraction is linear: awk splits on
  # `?` and keeps, per segment, the text after the last sentence boundary ("! " or ". "; " vs. " is
  # rewritten to " vs " first). A regex with a nested quantifier here cost ~13 s on a 32 KB question.
  if [[ "$unit" == *"?"* ]] && ! grep -qE "$RULING_OPVOCAB_RE" <<<"$unit"; then
    ends=0; [[ "$unit" == *"?" ]] && ends=1
    asked="$(printf '%s' "$unit" | awk -v ends="$ends" 'BEGIN { RS = "?"; ORS = "" }
      function emit(t) { gsub(/ vs\. /, " vs ", t); sub(/^.*(!|\. )/, "", t); print t "? " }
      NR > 1 { emit(prev) }
      { prev = $0 }
      END { if (ends) emit(prev) }')"
    if grep -qE "$RULING_STRICT_RE" <<<"$asked" && grep -qE "$RULING_EVID_NOUN_RE" <<<"$asked"; then hit="strict"; fi
    if [[ -z "$hit" ]] && grep -qE "$RULING_STATUS_RE" <<<"$asked" && grep -qE "$RULING_ADR_RE" <<<"$asked"; then hit="status"; fi
    if [[ -z "$hit" ]] && grep -qE "$RULING_AB_RE" <<<"$asked" && grep -qE "$RULING_TECH_RE" <<<"$asked"; then hit="ab"; fi
    if [[ -z "$hit" && "$ask" -eq 1 ]]; then
      # Per SEGMENT, not over the concatenation: two unrelated questions must not combine into one disposition ask. One
      # linear pipeline over the newline-split segments: a loop would fork a grep per `?` (about 1.6 ms each, 34 s for 20,000
      # of them), and the model controls that count. Read through a command substitution (no `grep -q`, so no SIGPIPE under
      # pipefail); `|| true` keeps it safe for a caller that runs with errexit.
      seg="$(printf '%s\n' "${asked//\? /$'\n'}" | grep -E "$TFC_ASK_ROUTE_RE" | grep -E "$TFC_ASK_RECORD_RE" | grep -vE "$TFC_ASK_VETO_RE" || true)"
      [[ -z "$seg" ]] || hit="ask"
    fi
  fi
  # STRONG cues (bar, adopting...accepted, sufficiency): technical on their own, no `?` needed. The
  # sufficiency cue alone yields to a money phrase.
  if [[ -z "$hit" ]] && grep -qE "$RULING_BAR_RE" <<<"$unit"; then hit="bar"; fi
  if [[ -z "$hit" ]] && grep -qE "$RULING_SUFF_RE" <<<"$unit" && ! grep -qE "$RULING_MONEY_RE" <<<"$unit"; then hit="suff"; fi

  # CLOSING cues: the unit must be a question, and BUSINESS (never ACTION) silences them.
  if [[ -z "$hit" && "$closing" -eq 1 && "$unit" == *"?"* ]] && ! grep -qE "$TFC_BUSINESS_RE" <<<"$unit"; then
    if grep -qE "$TFC_CL1_RE" <<<"$unit" && ! grep -qE "$RULING_MONEY_RE" <<<"$unit"; then hit="cl1"; fi
    if [[ -z "$hit" ]] && grep -qE "$TFC_CL2A_RE" <<<"$unit"; then hit="cl2a"; fi
    if [[ -z "$hit" ]] && grep -qE "$TFC_CL2B_RE" <<<"$unit"; then hit="cl2b"; fi
    if [[ -z "$hit" ]] && grep -qE "$TFC_CL3_ORDER_RE" <<<"$unit" && grep -qE "$TFC_CL3_NOUN_RE" <<<"$unit"; then hit="cl3"; fi
  fi

  [[ -n "$hit" ]] || return 1
  # The exemption: a PERMISSION shape ("may i", "ok to", "approve", "ack-destroy") reads the SAME unit
  # as the cues and applies to every cue, so an authorization is never blocked on one co-occurring word.
  grep -qE "$RULING_PERM_RE" <<<"$unit" && return 1
  [[ "$closing" -eq 1 ]] && grep -qE "$TFC_CLOSING_PERM_RE" <<<"$unit" && return 1
  # shellcheck disable=SC2034  # read by the sourcing hook
  TFC_HIT="$hit"
  return 0
}

# tfc_is_handoff <sentence>  exit 0 = a declarative hand-off of a technical step to the operator (CL4), 1 = pass.
# <sentence> is ONE sentence, already lowercased and single-spaced. Sets TFC_HIT=cl4 on a hit. Same call-in-current-shell
# rule as tfc_is_fork. Order of vetoes: closing EXTRA, BUSINESS, authorization verbs; then the two permission exemptions.
tfc_is_handoff() {
  local unit="${1-}" self=0 phrase=0
  # shellcheck disable=SC2034  # TFC_HIT is the function's output channel, read by the sourcing hook
  TFC_HIT=""
  [[ -n "$unit" ]] || return 1
  grep -qE "$TFC_CLOSING_EXTRA_RE" <<<"$unit" && return 1
  grep -qE "$TFC_BUSINESS_RE" <<<"$unit" && return 1
  grep -qE "$TFC_CL4_AUTH_RE" <<<"$unit" && return 1
  grep -qE "$TFC_CL4_SELF_ERE" <<<"$unit" && self=1
  grep -qE "$TFC_CL4_PHRASE_ERE" <<<"$unit" && phrase=1
  if (( self == 0 )); then
    (( phrase == 1 )) || return 1
    grep -qE "$TFC_CL4_NOUN_RE" <<<"$unit" || return 1
  fi
  grep -qE "$RULING_PERM_RE" <<<"$unit" && return 1
  grep -qE "$TFC_CLOSING_PERM_RE" <<<"$unit" && return 1
  # shellcheck disable=SC2034  # read by the sourcing hook
  TFC_HIT="cl4"
  return 0
}

# tfc_is_label_handoff <sentence>  exit 0 = the body of a final Paused:/Blocked: label itself hands a technical ruling to the operator, 1 = pass.
# <sentence> is the text AFTER the label colon, already lowercased and single-spaced. Sets TFC_HIT=label on a hit. Same call-in-current-shell rule
# as tfc_is_fork. The phrase gate comes first; then the same vetoes as the CL4 function (closing EXTRA, BUSINESS, authorization verbs, the two
# permission shapes) and a negation veto. Each veto is its own physical line against the one variable `sentence`, so each has its own mutation row.
tfc_is_label_handoff() {
  local sentence="${1-}"
  # shellcheck disable=SC2034  # TFC_HIT is the function's output channel, read by the sourcing hook
  TFC_HIT=""
  [[ -n "$sentence" ]] || return 1
  grep -qE "$TFC_LABEL_PHRASE_ERE" <<<"$sentence" || return 1
  grep -qE "$TFC_CLOSING_EXTRA_RE" <<<"$sentence" && return 1
  grep -qE "$TFC_BUSINESS_RE" <<<"$sentence" && return 1
  grep -qE "$TFC_CL4_AUTH_RE" <<<"$sentence" && return 1
  grep -qE "$RULING_PERM_RE" <<<"$sentence" && return 1
  grep -qE "$TFC_CLOSING_PERM_RE" <<<"$sentence" && return 1
  grep -qE '\b(deleting|deleted|deletion|cancell?ed|cancell?ing|deploying|deployed|deployment|merging|merged|revoking|revoked|rotating|rotated|wiping|wiped|shipped|shipping|released|releasing|pushed|pushing|reverted|reverting|migrating|migrated|restarted|restarting|applied|applying)\b' <<<"$sentence" && return 1
  grep -qE "$TFC_LABEL_NEG_ERE" <<<"$sentence" && return 1
  # shellcheck disable=SC2034  # read by the sourcing hook
  TFC_HIT="label"
  return 0
}

# MUST stay the very last statement: tfc_self_check reads it to prove the file was sourced completely.
_TFC_COMPLETE=1
