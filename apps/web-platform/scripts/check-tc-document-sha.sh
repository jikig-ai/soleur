#!/usr/bin/env bash
# T&C document SHA + mirror drift guardrail.
#
# Three invariants:
#   1. The canonical doc (docs/legal/terms-and-conditions.md) and the
#      plugin docs-site mirror (plugins/soleur/docs/pages/legal/...) have
#      the same NORMALISED prose body. Normalisation strips Eleventy
#      frontmatter, page-hero/content section scaffolding, link form
#      (`.md` vs `/legal/<name>/`), template-var expressions
#      ({{ stats.agents }} etc.), and the top-level "# Terms & Conditions"
#      heading. Either side rendering with a different agent count or a
#      template-var refactor stays equal; a body content drift fails.
#   2. apps/web-platform/lib/legal/tc-version.ts declares a 64-char
#      hex literal TC_DOCUMENT_SHA.
#   3. TC_DOCUMENT_SHA equals sha256(canonical doc) unless the same PR
#      also bumped TC_VERSION (bump-policy: a SHA change implies the
#      operator inspected the diff and either decided "this is
#      cosmetic, no version bump needed" — in which case CI fails
#      and they must edit the literal explicitly — OR "this is
#      material/clarifying" and they bumped TC_VERSION).
#
# feat-oauth-tc-consent-3205 (PR #3853). See plan Phase 6.

set -euo pipefail

CANONICAL=docs/legal/terms-and-conditions.md
MIRROR=plugins/soleur/docs/pages/legal/terms-and-conditions.md
LITERAL_FILE=apps/web-platform/lib/legal/tc-version.ts

if [ ! -f "$CANONICAL" ]; then
  echo "::error::canonical T&C doc missing: $CANONICAL" >&2
  exit 1
fi
if [ ! -f "$MIRROR" ]; then
  echo "::error::plugin T&C mirror missing: $MIRROR" >&2
  exit 1
fi
if [ ! -f "$LITERAL_FILE" ]; then
  echo "::error::tc-version.ts missing: $LITERAL_FILE" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Step 1: normalised body equality (mirror drift)
# ----------------------------------------------------------------------

# Strip frontmatter (everything from start through second `---` line) +
# top-level "# Terms & Conditions" heading from canonical.
normalize_canonical() {
  awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$1" \
    | sed -E '/^# Terms & Conditions[[:space:]]*$/d'
}

# Strip frontmatter + Eleventy page-hero / content section scaffolding
# + template-var expressions from the plugin mirror. Normalise link
# forms to the canonical `.md` shape so both sides compare equal.
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
# www.soleur.ai display variant so neither side wins on presentation.
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
    s|\(individual-cla\.md\)|(LINK_CLA_IND)|g
    s|\(/legal/individual-cla/\)|(LINK_CLA_IND)|g
    s|\(corporate-cla\.md\)|(LINK_CLA_CORP)|g
    s|\(/legal/corporate-cla/\)|(LINK_CLA_CORP)|g
    s|\(acceptable-use-policy\.md\)|(LINK_AUP)|g
    s|\(/legal/acceptable-use-policy/\)|(LINK_AUP)|g
    s|\(cookie-policy\.md\)|(LINK_COOKIE)|g
    s|\(/legal/cookie-policy/\)|(LINK_COOKIE)|g
    s|\(data-protection-disclosure\.md\)|(LINK_DPD)|g
    s|\(/legal/data-protection-disclosure/\)|(LINK_DPD)|g
    s|\(https://soleur\.ai\)|(LINK_HOME)|g
    s|\(https://www\.soleur\.ai\)|(LINK_HOME)|g
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

CANON_BODY_SHA=$(normalize_canonical "$CANONICAL" | collapse | sha256sum | awk '{print $1}')
MIRROR_BODY_SHA=$(normalize_plugin "$MIRROR" | collapse | sha256sum | awk '{print $1}')

if [ "$CANON_BODY_SHA" != "$MIRROR_BODY_SHA" ]; then
  echo "::error::T&C body drift: canonical and plugin mirror diverge after normalisation." >&2
  echo "    canonical=$CANONICAL" >&2
  echo "    mirror=$MIRROR" >&2
  echo "    canonical_body_sha=$CANON_BODY_SHA" >&2
  echo "    mirror_body_sha=$MIRROR_BODY_SHA" >&2
  echo "    Diff (canonical → mirror):" >&2
  diff <(normalize_canonical "$CANONICAL" | collapse) <(normalize_plugin "$MIRROR" | collapse) | head -40 >&2 || true
  exit 1
fi

# ----------------------------------------------------------------------
# Step 2: TC_DOCUMENT_SHA literal exists + valid form
# ----------------------------------------------------------------------

LITERAL_SHA=$(tr -d '\n' < "$LITERAL_FILE" \
              | grep -oE 'TC_DOCUMENT_SHA[^"]*"[0-9a-f]{64}"' \
              | grep -oE '[0-9a-f]{64}' \
              | head -n 1 || true)

if [ -z "$LITERAL_SHA" ]; then
  echo "::error::TC_DOCUMENT_SHA literal not found in $LITERAL_FILE" >&2
  echo "    Expected: export const TC_DOCUMENT_SHA = \"<64-char-lowercase-hex>\";" >&2
  exit 1
fi

# ----------------------------------------------------------------------
# Step 3: canonical SHA matches the literal (unless TC_VERSION was bumped)
# ----------------------------------------------------------------------

CANON_RAW_SHA=$(sha256sum "$CANONICAL" | awk '{print $1}')

if [ "$CANON_RAW_SHA" = "$LITERAL_SHA" ]; then
  exit 0
fi

# Mismatch — allow only if the same PR bumped TC_VERSION (line touching
# `export const TC_VERSION` in $LITERAL_FILE).
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  if git diff --unified=0 "origin/${GITHUB_BASE_REF}...HEAD" -- "$LITERAL_FILE" \
       | grep -qE '^[+-]export const TC_VERSION'; then
    echo "T&C document SHA changed AND TC_VERSION was bumped — accepted." >&2
    exit 0
  fi
fi

echo "::error::T&C document content changed but TC_DOCUMENT_SHA literal is stale and TC_VERSION was not bumped." >&2
echo "    canonical_sha=$CANON_RAW_SHA" >&2
echo "    literal_sha=$LITERAL_SHA" >&2
echo "    file=$LITERAL_FILE" >&2
echo "    Remediation:" >&2
echo "      1. Run: sha256sum $CANONICAL" >&2
echo "      2. Paste the value into TC_DOCUMENT_SHA in $LITERAL_FILE" >&2
echo "      3. If the change is material/clarifying per the bump-policy rubric" >&2
echo "         (knowledge-base/legal/tc-version-bump-policy.md), bump TC_VERSION." >&2
echo "      4. Commit all three in the same PR." >&2
exit 1
