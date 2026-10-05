#!/usr/bin/env bash
# legal-normalise.sh -- THE normaliser for the legal corpus. Source it; do not run it.
#
# Provides three functions, extracted verbatim from check-tc-document-sha.sh so that
# every consumer measures the corpus the same way:
#
#   normalize_canonical <path>   strip frontmatter + the top-level heading   (docs/legal/*.md)
#   normalize_plugin    <path>   strip frontmatter + Eleventy page scaffolding
#                                (plugins/soleur/docs/pages/legal/*.md)
#   collapse                     stdin -> stdout; cross-normalise link forms, template
#                                vars, and blank-line runs so the two surfaces are
#                                comparable
#
# WHY A SHARED LIBRARY. #7387 adds a mirror-drift ratchet that must measure drift the
# same way the SHA guard does. A second implementation is a second thing to drift, and
# the two would disagree silently -- each green, in different directions. One definition
# site, two consumers; scripts/lib/legal-normalise.test.sh asserts the count is exactly 1
# and pins the pre-extraction output hashes for all nine document pairs.
#
# CONSUMERS
#   apps/web-platform/scripts/check-tc-document-sha.sh   (SHA pinning + T&C body equivalence)
#   scripts/lint-legal-mirror-drift-baseline.sh          (drift ratchet)

# --- Direct-execution guard -------------------------------------------------------------
# This file is a library, not a program. Executed directly it would define three functions
# into a shell that immediately exits -- doing nothing, successfully. A silent exit 0 from
# something invoked as a check is the failure mode the whole #7387 work-stream exists to
# remove, so refuse loudly instead.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "legal-normalise.sh is a library and must be sourced, not executed:" >&2
  echo "  . \"\$(git rev-parse --show-toplevel)/scripts/lib/legal-normalise.sh\"" >&2
  exit 64
fi

# --- Double-source guard ----------------------------------------------------------------
# A single process may source this via more than one path (a gate that sources it directly
# and also invokes a helper that does). Re-defining the functions is harmless today, but a
# future stateful addition would not be, and a guard added later is a guard that arrives
# after the bug.
if [[ -n "${_SOLEUR_LEGAL_NORMALISE_SOURCED:-}" ]]; then
  return 0
fi
_SOLEUR_LEGAL_NORMALISE_SOURCED=1

# --- Locale pin -------------------------------------------------------------------------
# Character classes and collation are locale-dependent, so an unpinned locale makes the
# normalised bytes -- and therefore every hash derived from them -- a function of the
# runner's environment rather than of the corpus. Gate 2 compares hashes computed against
# two different checkouts; if the locale can move, drift becomes unfalsifiable.
export LC_ALL=C

# Strip frontmatter (everything from start through second `---` line) +
# the first top-level heading from canonical.
normalize_canonical() {
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1" \
    | sed -E '/^# [A-Z][^#]*[[:space:]]*$/d'
}

# Strip frontmatter + Eleventy page-hero / content section scaffolding
# + template-var expressions from the plugin mirror.
normalize_plugin() {
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1" \
    | sed -E '
        /^<section[^>]*>[[:space:]]*$/d
        /^<\/section>[[:space:]]*$/d
        /^[[:space:]]*<div[^>]*>[[:space:]]*$/d
        /^[[:space:]]*<\/div>[[:space:]]*$/d
        /^[[:space:]]*<h1>[^<]*<\/h1>[[:space:]]*$/d
        /^[[:space:]]*<p>Effective[^<]*<\/p>[[:space:]]*$/d
      '
}

# Cross-normalise link forms + template vars + the soleur.ai vs
# www.soleur.ai display variant.
collapse() {
  sed -E '
    s|\(privacy-policy\.md\)|(LINK_PRIVACY)|g
    s|\(/legal/privacy-policy/\)|(LINK_PRIVACY)|g
    s|\(gdpr-policy\.md\)|(LINK_GDPR)|g
    s|\(/legal/gdpr-policy/\)|(LINK_GDPR)|g
    s|\(disclaimer\.md\)|(LINK_DISCLAIMER)|g
    s|\(\./disclaimer\.md\)|(LINK_DISCLAIMER)|g
    s|\(/legal/disclaimer/\)|(LINK_DISCLAIMER)|g
    s|\(\./privacy-policy\.md\)|(LINK_PRIVACY)|g
    s|\(\./gdpr-policy\.md\)|(LINK_GDPR)|g
    s|\(individual-cla\.md\)|(LINK_CLA_IND)|g
    s|\(\./individual-cla\.md\)|(LINK_CLA_IND)|g
    s|\(/legal/individual-cla/\)|(LINK_CLA_IND)|g
    s|\(corporate-cla\.md\)|(LINK_CLA_CORP)|g
    s|\(\./corporate-cla\.md\)|(LINK_CLA_CORP)|g
    s|\(/legal/corporate-cla/\)|(LINK_CLA_CORP)|g
    s|\(acceptable-use-policy\.md\)|(LINK_AUP)|g
    s|\(\./acceptable-use-policy\.md\)|(LINK_AUP)|g
    s|\(/legal/acceptable-use-policy/\)|(LINK_AUP)|g
    s|\(cookie-policy\.md\)|(LINK_COOKIE)|g
    s|\(\./cookie-policy\.md\)|(LINK_COOKIE)|g
    s|\(/legal/cookie-policy/\)|(LINK_COOKIE)|g
    s|\(data-protection-disclosure\.md\)|(LINK_DPD)|g
    s|\(\./data-protection-disclosure\.md\)|(LINK_DPD)|g
    s|\(/legal/data-protection-disclosure/\)|(LINK_DPD)|g
    s|\(terms-and-conditions\.md\)|(LINK_TC)|g
    s|\(\./terms-and-conditions\.md\)|(LINK_TC)|g
    s|\(/legal/terms-and-conditions/\)|(LINK_TC)|g
    s|\(https://soleur\.ai\)|(LINK_HOME)|g
    s|\(https://www\.soleur\.ai\)|(LINK_HOME)|g
    s|\[https://soleur\.ai\]|[LINK_HOME_TEXT]|g
    s|\[https://www\.soleur\.ai\]|[LINK_HOME_TEXT]|g
    s/[0-9]+ AI agents/__AGENT_COUNT__ AI agents/g
    s/\{\{ stats\.agents \}\} AI agents/__AGENT_COUNT__ AI agents/g
    s/[0-9]+ skills/__SKILL_COUNT__ skills/g
    s/\{\{ stats\.skills \}\} skills/__SKILL_COUNT__ skills/g
    s/across [a-z]+ domains/across __DEPT_COUNT__ domains/g
    s/across \{\{ stats\.departments \}\} domains/across __DEPT_COUNT__ domains/g
    s/\(Engineering, Legal, Marketing, Operations, Product\)/(__DEPT_LIST__)/g
    s/\(\{\{ agents\.departmentList \}\}\)/(__DEPT_LIST__)/g
  ' \
  | awk 'BEGIN{blank=0} { if (NF==0) { blank=1; next } if (blank) { print ""; blank=0 } print }' \
  | awk 'BEGIN{seen=0} {if(!seen && NF==0) next; seen=1; print}'
}
