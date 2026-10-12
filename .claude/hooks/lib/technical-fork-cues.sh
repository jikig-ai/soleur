#!/usr/bin/env bash
# Shared cue vocabulary and verdict function for the two hooks that enforce
# `hr-technical-fork-is-not-an-operator-question` on a carrier a model controls:
#   pre-ask-technical-fork-gate.sh      (an AskUserQuestion tool call; group `shared`)
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
# group adds three cues and a narrower veto; the pre-ask hook is NOT widened (group `shared` only).
#
# ON A WRONGFUL BLOCK (a closing message stopped that carried a real operator question):
#   1. Find the closing in the local session transcript by the ledger row's sha256 of the unit.
#   2. Narrow the CLOSING cue in this file (a tighter shape, or a word in TFC_CLOSING_EXTRA_RE) and
#      add a must-PASS fixture to pre-closing-technical-fork-gate.test.sh; raise MIN_CASES and the
#      V1 literal together. That touches no other file.
#   3. A BUSINESS word is NEVER the fix: it changes the pinned RULING_OPVOCAB_RE literal and would
#      silence the pre-ask hook too. guard-vacuity-floor and the shard manifest need no change.
#
# CONTRACT
#   tfc_is_fork <unit> <groups>   exit 0 = technical fork (block), 1 = pass, 2 = bad arguments.
#       <unit> is ONE sentence, ALREADY lowercased and single-spaced by the caller. <groups> is
#       `shared` or `shared+closing`; anything else is exit 2 so a typo can never silently mean
#       "shared only". Prints nothing; sets the global TFC_HIT to the matching cue name. It MUST be
#       called in the current shell (never inside $(...)), or TFC_HIT is lost. No size cap lives
#       here: the pre-ask suite pins DENY on 30-60 KB questions, and the closing hook bounds what
#       it feeds this function itself.
#   tfc_self_check                exit 0 only if every cue variable is non-empty and tfc_is_fork is
#       defined. An EMPTY cue regex matches every line, so a consumer that sources a truncated lib
#       must treat a failed self-check as parse doubt and fail OPEN, never judge with it.
#
# PURE BY CONSTRUCTION: no set options, no emit_incident, no .claude/ or CLAUDE_PROJECT_DIR paths, no
# repo-specific nouns (so graduating the pair to the plugin is a move, not a rewrite). Linear regexes
# only (bounded gaps); no eval.

[[ -n "${_TFC_LOADED:-}" ]] && return 0
_TFC_LOADED=1

# ---- SHARED group: moved byte-identical from pre-ask-technical-fork-gate.sh ---------------------
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
# needed. Narrowed on purpose (never widened): CL2a needs an object, CL2b needs a technical noun.
TFC_CL1_RE='\b(is|are) [^?]{0,60}\b(evidence|census|inventory|coverage|audit|baseline|gate|proof)\b[^?]{0,60}\b(enough|sufficient|adequate)\b'
TFC_CL2A_RE='\b(what|which)( is|'"'"'s| are| would be)? (the )?(right|best|correct|proper|cleanest) (design|architecture|mechanism|approach) (for|to|of|when)\b'
TFC_CL2B_RE='\bdo you want (a|an|the) ([a-z -]{0,20} )?(migration|rotation|storage|credential|schema|pipeline|rollout|cutover)[a-z -]{0,20}(design|architecture)\b'
TFC_CL3_ORDER_RE='\b(in what|what|which) (order|sequence)\b'
TFC_CL3_NOUN_RE='\b(credentials?|tokens?|secrets?|keys?|configs?|configuration|storage|migrations?|cutover|pipelines?|schema|hosts?|rotat[a-z]*)\b'
TFC_BUSINESS_RE='\b('"${TFC_BUSINESS_WORDS}"')\b'
# A seed list tuned by the false-positive sample; applies to EVERY cue in the closing group (SHARED
# ones included) and to no cue in the pre-ask group.
TFC_CLOSING_EXTRA_RE='\b(prioriti[sz]\w*|publish\w*|announce\w*|auditors?|accountants?|lawyers?|investors?|customers?|features?|roadmap|milestones?)\b'

tfc_self_check() {
  local v
  for v in RULING_STRICT_RE RULING_EVID_NOUN_RE RULING_BAR_RE RULING_SUFF_RE RULING_STATUS_RE \
           RULING_ADR_RE RULING_AB_RE RULING_TECH_RE RULING_PERM_RE RULING_OPVOCAB_RE RULING_MONEY_RE \
           TFC_BUSINESS_WORDS TFC_ACTION_WORDS TFC_CL1_RE TFC_CL2A_RE TFC_CL2B_RE TFC_CL3_ORDER_RE \
           TFC_CL3_NOUN_RE TFC_BUSINESS_RE TFC_CLOSING_EXTRA_RE; do
    [[ -n "${!v-}" ]] || return 1
  done
  declare -f tfc_is_fork >/dev/null 2>&1 || return 1
  return 0
}

tfc_is_fork() {
  local unit="${1-}" groups="${2-}" closing=0 hit="" asked ends
  TFC_HIT=""
  case "$groups" in
    shared) ;;
    shared+closing) closing=1 ;;
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
  TFC_HIT="$hit"
  return 0
}
