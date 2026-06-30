#!/usr/bin/env bash
# All-9-legal-docs SHA-pin guard + T&C mirror-drift guard.
#
# File name is preserved (was T&C-only originally) because the CI job
# context `tc-document-sha-guard` is pinned as a Terraform-managed
# required-status-check at infra/github/ruleset-ci-required.tf per ADR-032;
# renaming the job/script atomically requires a paired terraform apply that
# is out of scope for this PR. See plan §OQ1 (knowledge-base/project/plans/
# 2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md).
#
# Per-doc invariants for every canonical at docs/legal/*.md:
#   1. (terms-and-conditions only) Canonical and Eleventy mirror have
#      identical normalised prose bodies after the doc-agnostic collapse
#      pipeline. Body-equivalence enforcement for the 8 non-T&C docs is
#      intentionally deferred — those docs have pre-existing benign drift
#      (link autolink form, horizontal-rule layout, agent-count phrasing)
#      that needs a one-off remediation PR before the gate can fire.
#   2. The corresponding SHA literal is present in the appropriate file:
#      - terms-and-conditions: TC_DOCUMENT_SHA in
#        apps/web-platform/lib/legal/tc-version.ts (load-bearing — written
#        to the WORM consent ledger at app/api/accept-terms/route.ts).
#      - other 8 docs: LEGAL_DOC_SHAS["<key>"] in
#        apps/web-platform/lib/legal/legal-doc-shas.ts (drift-only).
#   3. The literal equals sha256(canonical doc). For T&C only, the same PR
#      may bump TC_VERSION as a bypass (existing bump-policy contract).
#
# Plus T&C seed-script TC_VERSION parity (Step 2.5 from the original
# script — preserved verbatim, T&C-specific).
#
# Failures are accumulated and printed in one pass so the operator can fix
# every doc in a single edit cycle instead of running-fail-fixing N times.

set -euo pipefail

LITERAL_FILE_TC=apps/web-platform/lib/legal/tc-version.ts
LITERAL_FILE_OTHERS=apps/web-platform/lib/legal/legal-doc-shas.ts
CANONICAL_DIR=docs/legal
MIRROR_DIR=plugins/soleur/docs/pages/legal

# Sentinel (tripwire, NOT the actual gate). When a legal doc is added or
# removed, bump this in lockstep with LEGAL_DOC_SHAS / docs/legal/. A
# filesystem-glob hit count that disagrees emits a ::warning:: and
# continues — the per-doc invariants below catch the wrong-deletion case.
# A vitest harness (apps/web-platform/test/legal-doc-shas-guard.test.ts)
# asserts EXPECTED_COUNT == |LEGAL_DOC_SHAS| + 1 so this constant cannot
# silently drift from the TS map.
EXPECTED_COUNT=9

# ----------------------------------------------------------------------
# Enumerate canonical docs via filesystem glob.
# ----------------------------------------------------------------------

shopt -s nullglob
CANONICAL_DOCS=()
for f in "$CANONICAL_DIR"/*.md; do
  CANONICAL_DOCS+=("$(basename "$f" .md)")
done

if [ "${#CANONICAL_DOCS[@]}" -ne "$EXPECTED_COUNT" ]; then
  echo "::warning::${CANONICAL_DIR}/ glob returned ${#CANONICAL_DOCS[@]} docs; expected ${EXPECTED_COUNT}. Update EXPECTED_COUNT in $(basename "$0") if intentional." >&2
fi

# Verify literal source files present before per-doc loop.
for lit in "$LITERAL_FILE_TC" "$LITERAL_FILE_OTHERS"; do
  if [ ! -f "$lit" ]; then
    echo "::error::SHA literal source missing: $lit" >&2
    exit 1
  fi
done

# ----------------------------------------------------------------------
# Normalisation helpers (T&C body-equivalence step only).
# ----------------------------------------------------------------------

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

# ----------------------------------------------------------------------
# SHA literal extractors (bash regex on whole-file content).
# ----------------------------------------------------------------------

# Read the TC_DOCUMENT_SHA literal from tc-version.ts. The value may sit on
# the line after the `=` so we slurp the file and use [[:space:]]* across
# newlines.
extract_tc_document_sha() {
  local content
  content=$(< "$1")
  local pat='TC_DOCUMENT_SHA[[:space:]]*=[[:space:]]*"([0-9a-f]{64})"'
  if [[ "$content" =~ $pat ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# Read LEGAL_DOC_SHAS["<key>"] from legal-doc-shas.ts. Entries are
# typically formatted as a two-line key/value pair (key on one line,
# value indented on the next), hence [[:space:]]* across newlines.
extract_legal_doc_sha() {
  local content
  content=$(< "$1")
  local key="$2"
  local pat="\"${key}\"[[:space:]]*:[[:space:]]*\"([0-9a-f]{64})\""
  if [[ "$content" =~ $pat ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

# ----------------------------------------------------------------------
# Per-doc loop.
# ----------------------------------------------------------------------

BODY_EQUIVALENCE_DOCS=("terms-and-conditions")
# data-protection-disclosure: guard infrastructure ready (test at legal-doc-shas-guard.test.ts
# proves detection); activation deferred until PR #4455-introduced drift is resolved.
# Add "data-protection-disclosure" to the array once the mirror is re-synced.

FAILED=0
FAILURES=()

for doc in "${CANONICAL_DOCS[@]}"; do
  canonical_path="$CANONICAL_DIR/$doc.md"
  mirror_path="$MIRROR_DIR/$doc.md"

  if [ ! -f "$canonical_path" ]; then
    echo "::error::canonical legal doc missing: $canonical_path" >&2
    FAILED=$((FAILED+1)); FAILURES+=("$doc: canonical missing"); continue
  fi
  if [ ! -f "$mirror_path" ]; then
    echo "::error::Eleventy mirror missing for $doc: $mirror_path" >&2
    FAILED=$((FAILED+1)); FAILURES+=("$doc: mirror missing"); continue
  fi

  # Step 1: normalized body equivalence vs Eleventy mirror (opt-in per BODY_EQUIVALENCE_DOCS).
  if printf '%s\n' "${BODY_EQUIVALENCE_DOCS[@]}" | grep -Fxq "$doc"; then
    canon_body_sha=$(normalize_canonical "$canonical_path" | collapse | sha256sum | awk '{print $1}')
    mirror_body_sha=$(normalize_plugin "$mirror_path" | collapse | sha256sum | awk '{print $1}')

    if [ "$canon_body_sha" != "$mirror_body_sha" ]; then
      echo "::error::$doc body drift: canonical and plugin mirror diverge after normalisation." >&2
      echo "    canonical=$canonical_path" >&2
      echo "    mirror=$mirror_path" >&2
      echo "    canonical_body_sha=$canon_body_sha" >&2
      echo "    mirror_body_sha=$mirror_body_sha" >&2
      echo "    Diff (canonical → mirror):" >&2
      diff <(normalize_canonical "$canonical_path" | collapse) <(normalize_plugin "$mirror_path" | collapse) | head -40 >&2 || true
      FAILED=$((FAILED+1)); FAILURES+=("$doc: body drift"); continue
    fi
  fi

  # Step 2: SHA literal exists in the appropriate source file.
  if [ "$doc" = "terms-and-conditions" ]; then
    literal_sha=$(extract_tc_document_sha "$LITERAL_FILE_TC")
  else
    literal_sha=$(extract_legal_doc_sha "$LITERAL_FILE_OTHERS" "$doc")
  fi

  if [ -z "$literal_sha" ]; then
    if [ "$doc" = "terms-and-conditions" ]; then
      echo "::error::TC_DOCUMENT_SHA literal not found in $LITERAL_FILE_TC" >&2
      echo "    Expected: export const TC_DOCUMENT_SHA = \"<64-char-lowercase-hex>\";" >&2
    else
      echo "::error::LEGAL_DOC_SHAS literal for \"$doc\" not found in $LITERAL_FILE_OTHERS" >&2
      echo "    Expected: \"$doc\": \"<64-char-lowercase-hex>\"" >&2
    fi
    FAILED=$((FAILED+1)); FAILURES+=("$doc: literal missing"); continue
  fi

  # Step 3: canonical SHA matches literal (T&C: with TC_VERSION-bump bypass).
  canonical_sha=$(sha256sum "$canonical_path" | awk '{print $1}')

  if [ "$canonical_sha" = "$literal_sha" ]; then
    continue
  fi

  if [ "$doc" = "terms-and-conditions" ]; then
    # Bypass: same PR bumped TC_VERSION. Resolve the diff base from
    # GITHUB_BASE_REF on pull_request (origin/<ref>) or MERGE_GROUP_BASE_SHA on
    # a merge_group event (github.base_ref is empty there; the candidate base is
    # an ancestor SHA in the fetch-depth:0 checkout). Without the merge_group
    # fallback the bypass silently no-ops on the queue ref and false-fails a
    # legit stale-SHA + TC_VERSION-bump PR. #5780.
    bypass_base=""
    if [ -n "${GITHUB_BASE_REF:-}" ]; then
      bypass_base="origin/${GITHUB_BASE_REF}"
    elif [ -n "${MERGE_GROUP_BASE_SHA:-}" ]; then
      bypass_base="${MERGE_GROUP_BASE_SHA}"
    fi
    if [ -n "$bypass_base" ]; then
      if git diff --unified=0 "${bypass_base}...HEAD" -- "$LITERAL_FILE_TC" \
           | grep -qE '^[+-]export const TC_VERSION'; then
        echo "T&C document SHA changed AND TC_VERSION was bumped — accepted." >&2
        continue
      fi
    fi
    echo "::error::T&C document content changed but TC_DOCUMENT_SHA literal is stale and TC_VERSION was not bumped." >&2
    echo "    canonical_sha=$canonical_sha" >&2
    echo "    literal_sha=$literal_sha" >&2
    echo "    file=$LITERAL_FILE_TC" >&2
    echo "    Remediation:" >&2
    echo "      1. Run: sha256sum $canonical_path" >&2
    echo "      2. Paste the value into TC_DOCUMENT_SHA in $LITERAL_FILE_TC" >&2
    echo "      3. If the change is material/clarifying per the bump-policy rubric" >&2
    echo "         (knowledge-base/legal/tc-version-bump-policy.md), bump TC_VERSION." >&2
    echo "      4. Commit all three in the same PR." >&2
    FAILED=$((FAILED+1)); FAILURES+=("$doc: literal stale (no TC_VERSION bump)")
  else
    echo "::error::legal doc \"$doc\" content changed but LEGAL_DOC_SHAS[\"$doc\"] is stale." >&2
    echo "    canonical_sha=$canonical_sha" >&2
    echo "    literal_sha=$literal_sha" >&2
    echo "    file=$LITERAL_FILE_OTHERS" >&2
    echo "    Remediation:" >&2
    echo "      1. Run: sha256sum $canonical_path" >&2
    echo "      2. Paste the value into LEGAL_DOC_SHAS[\"$doc\"] in $LITERAL_FILE_OTHERS" >&2
    echo "      3. Classify the edit per knowledge-base/legal/tc-version-bump-policy.md (§ Non-T&C legal docs)" >&2
    echo "         and document the Tier in the PR body." >&2
    echo "      4. Commit both in the same PR." >&2
    FAILED=$((FAILED+1)); FAILURES+=("$doc: literal stale")
  fi
done

# ----------------------------------------------------------------------
# Step 2.5: T&C seed-script TC_VERSION parity (preserved verbatim).
# ----------------------------------------------------------------------
#
# seed-dev-users.sh and seed-qa-user.sh hardcode TC_VERSION="…" so QA
# users can log in past the T&C gate after a fresh re-seed. If the
# canonical lib/legal/tc-version.ts is bumped but the seed scripts are
# not, QA users get the middleware redirect-to-/accept-terms loop on
# their next sign-in — silent failure shape that only surfaces during
# QA cycles, often days after the bump.

CANONICAL_TC_VERSION=$(grep -oE 'TC_VERSION[[:space:]]*=[[:space:]]*"[^"]+"' "$LITERAL_FILE_TC" \
                       | head -n 1 \
                       | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$CANONICAL_TC_VERSION" ]; then
  echo "::error::TC_VERSION literal not found in $LITERAL_FILE_TC" >&2
  FAILED=$((FAILED+1)); FAILURES+=("terms-and-conditions: TC_VERSION missing")
fi

SEED_SCRIPTS=(
  "apps/web-platform/scripts/seed-dev-users.sh"
  "apps/web-platform/scripts/seed-qa-user.sh"
)

if [ -n "$CANONICAL_TC_VERSION" ]; then
  for seed in "${SEED_SCRIPTS[@]}"; do
    if [ ! -f "$seed" ]; then
      # Seed script absent in this checkout (e.g., docs-only branch) — skip.
      continue
    fi
    SEED_VERSION=$(grep -oE '^TC_VERSION="[^"]+"' "$seed" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$SEED_VERSION" ]; then
      echo "::error::$seed missing TC_VERSION=\"…\" literal" >&2
      FAILED=$((FAILED+1)); FAILURES+=("$(basename "$seed"): TC_VERSION missing")
      continue
    fi
    if [ "$SEED_VERSION" != "$CANONICAL_TC_VERSION" ]; then
      echo "::error::$seed TC_VERSION=$SEED_VERSION drifted from canonical $CANONICAL_TC_VERSION ($LITERAL_FILE_TC)" >&2
      echo "    Remediation: update the TC_VERSION literal in the seed script to match." >&2
      FAILED=$((FAILED+1)); FAILURES+=("$(basename "$seed"): TC_VERSION drift")
    fi
  done
fi

# ----------------------------------------------------------------------
# Aggregate exit.
# ----------------------------------------------------------------------

if [ "$FAILED" -gt 0 ]; then
  echo "::error::$FAILED legal-doc SHA guard check(s) failed:" >&2
  for f in "${FAILURES[@]}"; do
    echo "    - $f" >&2
  done
  exit 1
fi

exit 0
