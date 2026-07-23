#!/usr/bin/env bash

# Tests for the #6049 drift-proof chain that keeps bot synthetic check-runs in
# lockstep with the CI Required ruleset.
#
# Run: bash plugins/soleur/test/required-checks-canonical-parity.test.sh
#
# Three guards, all file-vs-file and deterministic (no GitHub API):
#
#   1. PARITY: the CI-Required subset of scripts/required-checks.txt (the SSOT
#      the bot action derives CHECK_NAMES from) equals — as a SET, both ⊆ and ⊇
#      — the `integration_id == 15368` contexts of the canonical ruleset JSON.
#      Computed via `jq select(.integration_id==15368)`, NOT a `CodeQL` string
#      literal, so a future second GHAS/non-15368 required check is handled
#      structurally instead of silently breaking this test.
#   2. COMPOSITE→SSOT: the action derives CHECK_NAMES from required-checks.txt
#      (a `grep`), so a future re-hardcode of the array reintroduces the exact
#      drift #6049 fixed and this test catches it (the action is exempt from
#      lint-bot-synthetic-completeness.sh by construction).
#   3. PIN-PARITY: the gitleaks version + SHA256 pin is identical across all
#      three install sites (secret-scan.yml, ci.yml test-scripts, and the
#      action) — a silent divergence would scan the bot diff with a different
#      engine than the required `gitleaks scan` job.
#
# The CLA contexts {cla-check, cla-evidence} live in required-checks.txt AND now
# have their own canonical JSON (scripts/ci-cla-required-ruleset-canonical-
# required-status-checks.json). They are excluded from the CI-parity checks (they
# are a DIFFERENT ruleset) via CLA_EXCLUDE, which is now DERIVED from that CLA
# canonical (not a hardcoded named set) — so a 3rd CLA context flows through
# automatically once the canonical is updated.
#
# CLA drift is now guarded on all three dimensions (#6061), closing the former
# "entirely unguarded" gap:
#   - canonical JSONs (bypass + required-status-checks) mirror the create-script;
#   - daily live↔canonical coverage via the cron-ruleset-bypass-audit Inngest fn
#     (enforcement + bypass_actors + required_status_checks, per-ruleset step);
#   - file-vs-file: Test 7 below (SSOT CLA subset == CLA canonical) + the
#     canonical↔create-script sync gates in tests/scripts/test-audit-ruleset-bypass.sh.
# Test 7 keeps required-checks.txt and the CLA canonical in lockstep: the bot
# composite action synthesizes a green check-run for every name in required-
# checks.txt including cla-check/cla-evidence, so a 3rd CLA context mirrored into
# the canonical but NOT into required-checks.txt would deadlock bot PRs.
#
# Refs: #6049, #6061

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# Pin C collation so `sort` and `comm` agree on byte order — without this,
# locale-aware `sort` interleaves upper/lowercase (`Bash…` vs `allowlist…`) and
# `comm` (byte order) rejects the input as "not in sorted order".
export LC_ALL=C

REPO_ROOT="$SCRIPT_DIR/../../.."
CONFIG_FILE="$REPO_ROOT/scripts/required-checks.txt"
CANONICAL="$REPO_ROOT/scripts/ci-required-ruleset-canonical-required-status-checks.json"
ACTION_YML="$REPO_ROOT/.github/actions/bot-pr-with-synthetic-checks/action.yml"
SECRET_SCAN_YML="$REPO_ROOT/.github/workflows/secret-scan.yml"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
CLA_CANONICAL="$REPO_ROOT/scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"

# CLA exclusion for the CI-parity checks, DERIVED from the CLA canonical (#6061)
# — the CLA contexts belong to a different ruleset and must not be misattributed
# as CI drift. Deriving (vs a hardcoded named set) means a 3rd CLA context is
# handled structurally. GUARD: `mapfile`/`while-read` under `set -euo pipefail`
# does NOT reap a jq failure inside process substitution, so an empty derive
# would silently exclude NOTHING and misread CLA leakage as CI drift — the
# `>= 2` non-empty guard is the real protection.
assert_file_exists "$CLA_CANONICAL" "CLA RSC canonical exists"
CLA_EXCLUDE=()
while IFS= read -r c; do CLA_EXCLUDE+=("$c"); done < <(jq -e -r '.[].context' "$CLA_CANONICAL")
(( ${#CLA_EXCLUDE[@]} >= 2 )) || { echo "FAIL: CLA_EXCLUDE derived < 2 contexts (jq failure or empty canonical)"; exit 1; }

echo "=== required-checks ↔ canonical parity (#6049) ==="
echo ""

# --- Shared parsers -------------------------------------------------------

# Parse required-checks.txt with the SAME leading-`#`-only comment rule the
# lint and the action use, then drop the CLA set. Emits one CI-Required check
# name per line. Kept in sync with scripts/lint-bot-synthetic-completeness.sh.
parse_ci_required() {
  local file="$1" line c skip
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "$line" == \"*\" ]]; then
      line="${line#\"}"
      line="${line%\"}"
    fi
    [[ -z "$line" ]] && continue
    skip=false
    for c in "${CLA_EXCLUDE[@]}"; do
      [[ "$line" == "$c" ]] && { skip=true; break; }
    done
    $skip && continue
    printf '%s\n' "$line"
  done < "$file"
}

# Emit the canonical JSON's `integration_id == 15368` contexts, one per line.
canonical_15368() {
  jq -r '.[] | select(.integration_id == 15368) | .context' "$1"
}

# Given a config file and a canonical JSON, print two blocks separated by a
# `---ONLY-IN-CANONICAL---` sentinel: names only in the config (⊆ violations)
# then names only in canonical (⊇ violations). Both empty == perfect parity.
diff_sets() {
  local cfg="$1" canon="$2" a b
  a=$(parse_ci_required "$cfg" | sort -u)
  b=$(canonical_15368 "$canon" | sort -u)
  comm -23 <(printf '%s\n' "$a") <(printf '%s\n' "$b")
  printf '%s\n' "---ONLY-IN-CANONICAL---"
  comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b")
}

only_in_config() { sed -n "1,/^---ONLY-IN-CANONICAL---$/p" <<< "$1" | sed '/^---ONLY-IN-CANONICAL---$/d'; }
only_in_canon()  { sed -n "/^---ONLY-IN-CANONICAL---$/,\$p" <<< "$1" | sed '/^---ONLY-IN-CANONICAL---$/d'; }

# Parse ONLY the CLA Required ruleset section of required-checks.txt (for Test 7).
# The section start is EXACT-anchored on `^#…CLA Required ruleset$` — a loose
# `CLA Required.*ruleset` match would hit the line-7 header comment
# (`#   - "CLA Required" ruleset: cla-check`) and slurp the whole CI section.
# The end is bounded on the next `^#…ruleset$` header OR EOF, so a future section
# appended after CLA is not slurped. Applies the same leading-`#`-only comment
# rule + quote-strip, but deliberately does NOT inherit the CLA_EXCLUDE filter —
# Test 7 WANTS the CLA lines, and a cloned parse_ci_required would exclude them
# and pass vacuously.
parse_cla_section() {
  local file="$1" line
  awk '
    /^#[[:space:]]*CLA Required ruleset[[:space:]]*$/ { in_section=1; next }
    in_section && /^#[[:space:]]*[A-Za-z].*ruleset[[:space:]]*$/ { in_section=0 }
    in_section { print }
  ' "$file" | while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "$line" == \"*\" ]]; then
      line="${line#\"}"
      line="${line%\"}"
    fi
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done
}

# --- Test 1: real files are in perfect parity (both directions) -----------

echo "Test 1: required-checks.txt CI-subset == canonical 15368 contexts (⊆ and ⊇)"
assert_file_exists "$CONFIG_FILE" "required-checks.txt exists"
assert_file_exists "$CANONICAL" "canonical JSON exists"

real_diff=$(diff_sets "$CONFIG_FILE" "$CANONICAL")
extra_in_config=$(only_in_config "$real_diff" | sed '/^$/d')
missing_from_config=$(only_in_canon "$real_diff" | sed '/^$/d')

assert_eq "" "$extra_in_config" "(1a) no CI name in required-checks.txt absent from canonical-15368 (⊆)"
assert_eq "" "$missing_from_config" "(1b) no canonical-15368 context missing from required-checks.txt (⊇)"

# Sanity: the set is non-empty (a both-empty parse would pass vacuously).
n_ci=$(parse_ci_required "$CONFIG_FILE" | wc -l | tr -d ' ')
n_canon=$(canonical_15368 "$CANONICAL" | wc -l | tr -d ' ')
if [[ "$n_ci" -ge 16 && "$n_canon" -ge 16 ]]; then
  echo "  PASS: (1c) non-vacuous — $n_ci CI names, $n_canon canonical-15368 contexts"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (1c) suspiciously small set — n_ci=$n_ci n_canon=$n_canon"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 2: mutation — extra canonical context is caught (⊇ violation) ----

echo "Test 2: adding a canonical-15368 context not in required-checks.txt FAILS (⊇)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
jq '. + [{"context": "z-fake-context", "integration_id": 15368}]' "$CANONICAL" > "$TMP/canon-extra.json"
mut_diff=$(diff_sets "$CONFIG_FILE" "$TMP/canon-extra.json")
mut_missing=$(only_in_canon "$mut_diff" | sed '/^$/d')
assert_contains "$mut_missing" "z-fake-context" "(2) fake canonical context surfaces as a ⊇ violation"
echo ""

# --- Test 3: mutation — a dropped required-checks name is caught (⊇) --------
# Dropping a name FROM required-checks.txt that canonical still has is a ⊇
# violation (canonical ⊄ config): the name surfaces in `only_in_canon`.

echo "Test 3: removing a name from required-checks.txt FAILS (⊇)"
# Drop 'adr-ordinals' from a config copy; it must then surface as canonical-only.
grep -v '^adr-ordinals$' "$CONFIG_FILE" > "$TMP/cfg-drop.txt"
drop_diff=$(diff_sets "$TMP/cfg-drop.txt" "$CANONICAL")
drop_missing=$(only_in_canon "$drop_diff" | sed '/^$/d')
assert_contains "$drop_missing" "adr-ordinals" "(3) dropped name surfaces as a ⊇ violation (canonical has it, config doesn't)"
echo ""

# --- Test 3b: mutation — an EXTRA required-checks name is caught (⊆) --------
# Negative control for the `only_in_config` / `comm -23` slice: Tests 2 & 3
# both land in `only_in_canon`, so without this the ⊆-detection path is only
# ever asserted empty (Test 1a) and a broken slice would pass vacuously.

echo "Test 3b: adding a name to required-checks.txt not in canonical FAILS (⊆)"
{ cat "$CONFIG_FILE"; printf '\nz-config-only-fake\n'; } > "$TMP/cfg-extra.txt"
extra_diff=$(diff_sets "$TMP/cfg-extra.txt" "$CANONICAL")
extra_present=$(only_in_config "$extra_diff" | sed '/^$/d')
assert_contains "$extra_present" "z-config-only-fake" "(3b) config-only name surfaces as a ⊆ violation (config has it, canonical doesn't)"
echo ""

# --- Test 4: composite→SSOT guard (future re-hardcode caught) ---------------
# The action is exempt from lint-bot-synthetic-completeness.sh by construction,
# so this is its ONLY synchronous protection. Assert the SSOT is actually READ
# (a loop `done < "$REQUIRED_CHECKS_FILE"` + the exact assignment) — a bare
# `grep required-checks.txt` matches the comment block too, so a re-hardcode
# that deletes the read-loop but keeps the comments would pass a mention-grep.

echo "Test 4: action.yml derives CHECK_NAMES from scripts/required-checks.txt"
assert_file_exists "$ACTION_YML" "action.yml exists"
if grep -qE 'REQUIRED_CHECKS_FILE=.*required-checks\.txt' "$ACTION_YML"; then
  echo "  PASS: (4a) action.yml assigns REQUIRED_CHECKS_FILE=scripts/required-checks.txt"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (4a) action.yml does NOT assign REQUIRED_CHECKS_FILE to required-checks.txt"
  FAIL=$((FAIL + 1))
fi
if grep -qE 'done[[:space:]]*<[[:space:]]*"\$REQUIRED_CHECKS_FILE"' "$ACTION_YML"; then
  echo "  PASS: (4b) action.yml READS the SSOT in a loop (done < \$REQUIRED_CHECKS_FILE)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (4b) action.yml does NOT read the SSOT in a loop — CHECK_NAMES may be re-hardcoded"
  FAIL=$((FAIL + 1))
fi
# Negative guard: no hardcoded CHECK_NAMES array literal (any first element, not
# just `test`) — matches `CHECK_NAMES=(` followed by a non-`)` token.
if grep -qE 'CHECK_NAMES=\([[:space:]]*[^)[:space:]]' "$ACTION_YML"; then
  echo "  FAIL: (4c) action.yml hardcodes a non-empty CHECK_NAMES=(...) array"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: (4c) no hardcoded non-empty CHECK_NAMES=(...) array in action.yml"
  PASS=$((PASS + 1))
fi
echo ""

# --- Test 5: gitleaks pin-parity across all three install sites -------------

echo "Test 5: gitleaks version + SHA256 pin is identical across all 3 sites"
extract_version() {
  grep -oE 'GITLEAKS_VERSION["]?[[:space:]]*[:=][[:space:]]*"?[0-9]+\.[0-9]+\.[0-9]+' "$1" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
extract_sha() {
  grep -oE 'GITLEAKS_SHA256["]?[[:space:]]*[:=][[:space:]]*"?[0-9a-f]{64}' "$1" \
    | grep -oE '[0-9a-f]{64}' | head -1
}

for f in "$SECRET_SCAN_YML" "$CI_YML" "$ACTION_YML"; do
  assert_file_exists "$f" "pin site exists: ${f##*/}"
done

ss_v=$(extract_version "$SECRET_SCAN_YML"); ss_s=$(extract_sha "$SECRET_SCAN_YML")
ci_v=$(extract_version "$CI_YML");          ci_s=$(extract_sha "$CI_YML")
ac_v=$(extract_version "$ACTION_YML");       ac_s=$(extract_sha "$ACTION_YML")

# Non-empty guard first — a missing pin would make two empties compare equal.
if [[ -n "$ss_v" && -n "$ss_s" && -n "$ci_v" && -n "$ci_s" && -n "$ac_v" && -n "$ac_s" ]]; then
  echo "  PASS: (5a) all three sites declare a gitleaks version + SHA256 pin"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (5a) a gitleaks pin is missing — ss=[$ss_v/$ss_s] ci=[$ci_v/$ci_s] action=[$ac_v/$ac_s]"
  FAIL=$((FAIL + 1))
fi
assert_eq "$ss_v" "$ci_v" "(5b) secret-scan.yml version == ci.yml version"
assert_eq "$ss_v" "$ac_v" "(5c) secret-scan.yml version == action version"
assert_eq "$ss_s" "$ci_s" "(5d) secret-scan.yml SHA256 == ci.yml SHA256"
assert_eq "$ss_s" "$ac_s" "(5e) secret-scan.yml SHA256 == action SHA256"
echo ""

# --- Test 6: parser logic-parity across all three copies --------------------
# The leading-`#`-only required-checks.txt parser is replicated in three files:
# the lint, the ACTION run block (the copy that actually posts checks in CI, and
# is exercised by no behavioral test), and parse_ci_required above. A revert of
# any copy to the truncating inline `${var%%#*}` comment strip would re-introduce
# the #6049 stall on `waiver discipline (issue:#NNN trailer)` silently. Pin the
# comment-rule invariant across all three: leading-`#` present, `%%#*` absent.

echo "Test 6: all 3 required-checks parsers use leading-#-only (no #-truncation)"
PARSER_FILES=(
  "$ACTION_YML"
  "$REPO_ROOT/scripts/lint-bot-synthetic-completeness.sh"
  "${BASH_SOURCE[0]}"
)
for f in "${PARSER_FILES[@]}"; do
  base="${f##*/}"
  if grep -qE '=~[[:space:]]+\^\[\[:space:\]\]\*#' "$f"; then
    echo "  PASS: (6) $base uses the leading-#-only comment rule"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: (6) $base is missing the leading-#-only comment rule"
    FAIL=$((FAIL + 1))
  fi
  # Negative: the truncating `${line...}` / `${rcline...}` inline comment strip
  # must not return in CODE. Filter full-line comments first — every parser file
  # (and this test) documents the old form in prose, which a bare grep would
  # false-match (the grep-over-own-comments trap).
  if grep -vE '^[[:space:]]*#' "$f" | grep -qE '\$\{(line|rcline)%%#'; then
    echo "  FAIL: (6) $base contains a truncating inline #-strip in code — re-introduces #6049"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: (6) $base has no truncating #-strip on the parse variable"
    PASS=$((PASS + 1))
  fi
done
echo ""

# --- Test 7: SSOT CLA subset == CLA canonical (⊆ and ⊇, non-vacuous) [#6061] --
# The bot composite action synthesizes a green check-run for EVERY name in
# required-checks.txt including the CLA contexts, so required-checks.txt and the
# CLA canonical must stay in lockstep: a 3rd CLA context in the canonical but not
# in required-checks.txt → no synthetic posted → bot PR deadlocks.

echo "Test 7: required-checks.txt CLA-subset == CLA canonical contexts (⊆ and ⊇) [#6061]"
cla_ssot=$(parse_cla_section "$CONFIG_FILE" | sort -u)
cla_canon=$(jq -r '.[].context' "$CLA_CANONICAL" | sort -u)
cla_extra=$(comm -23 <(printf '%s\n' "$cla_ssot") <(printf '%s\n' "$cla_canon") | sed '/^$/d')
cla_missing=$(comm -13 <(printf '%s\n' "$cla_ssot") <(printf '%s\n' "$cla_canon") | sed '/^$/d')

assert_eq "" "$cla_extra" "(7a) no CLA name in required-checks.txt absent from CLA canonical (⊆)"
assert_eq "" "$cla_missing" "(7b) no CLA canonical context missing from required-checks.txt (⊇)"

# Non-vacuous: a both-empty parse (broken anchor) would pass 7a/7b vacuously.
n_cla_ssot=$(printf '%s\n' "$cla_ssot" | sed '/^$/d' | wc -l | tr -d ' ')
n_cla_canon=$(printf '%s\n' "$cla_canon" | sed '/^$/d' | wc -l | tr -d ' ')
if [[ "$n_cla_ssot" -ge 2 && "$n_cla_canon" -ge 2 ]]; then
  echo "  PASS: (7c) non-vacuous — $n_cla_ssot CLA SSOT names, $n_cla_canon CLA canonical contexts"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (7c) suspiciously small CLA set — n_ssot=$n_cla_ssot n_canon=$n_cla_canon"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 8: credential-path green is EARNED, not fabricated (#6882/ADR-139) --
#
# `credential-path-guard` is a required 15368 context, so the composite action
# posts an unconditional green synthetic check-run for it on every bot PR. That
# is sound ONLY because the action reproduces the scan over its own staged paths
# first (the same earned-green pattern as the real gitleaks run).
#
# It canNOT rely on the FABRICATED-NOT-EARNED / unreachability argument used by
# `rule-body-lint` (#6103) and `sentry-destroy-required` (#6589): those guard
# surfaces sit OUTSIDE the action's ALLOWED_PATHS, whereas
# lint-credential-path-literals.py scans tracked *.md under plugins/ and
# knowledge-base/ — which INCLUDES knowledge-base/project/weakness-digest.md,
# one of exactly two paths the action is allowed to write. ALLOWED_PATHS ∩
# SCAN_DIRS is NON-empty, so deleting the preflight would fabricate a pass over
# a reachable surface. This test is the enforcement teeth for that invariant.
#
# Anchors are syntactic (`^\s*if ! python3 …`), never a bare script name — the
# action.yml comment block names the script too, and a mention-grep would pass
# against a deleted preflight. The reproduction lives INLINE in the same Phase-4
# `run:` block as the gitleaks / lint-fixture-content arms, matching their
# `if ! <cmd>; then ::error::; exit 1; fi` shape.

echo "Test 8: action.yml EARNS the credential-path green (#6882 / ADR-139)"
# `|| true` is load-bearing: this file runs under `set -euo pipefail`, so a
# no-match grep inside a command substitution aborts the WHOLE suite before the
# FAIL branch can print (and an early `head -1` close can SIGPIPE grep to 141).
# The RED state must report a clean failure, not kill the runner.
preflight_line=$(grep -nE '^[[:space:]]*if ! python3 scripts/lint-credential-path-literals\.py "\$\{PATHS\[@\]\}"; then' "$ACTION_YML" | head -1 | cut -d: -f1 || true)
postrun_line=$(grep -nE '^[[:space:]]*gh api "repos/\$\{REPO\}/check-runs"' "$ACTION_YML" | head -1 | cut -d: -f1 || true)

if [[ -n "$preflight_line" ]]; then
  echo "  PASS: (8a) action.yml runs lint-credential-path-literals.py over \"\${PATHS[@]}\" (line $preflight_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8a) action.yml does NOT reproduce the credential-path scan over its staged paths."
  echo "        Without it the synthetic green for 'credential-path-guard' is FABRICATED over a"
  echo "        REACHABLE surface (weakness-digest.md). See ADR-139 + scripts/required-checks.txt."
  FAIL=$((FAIL + 1))
fi

# Non-vacuity: (8b) is meaningless if the check-run POST anchor stops resolving.
if [[ -n "$postrun_line" ]]; then
  echo "  PASS: (8c) non-vacuous — check-run POST anchor resolves (line $postrun_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8c) could not locate the check-run POST — (8b) ordering check would be vacuous"
  FAIL=$((FAIL + 1))
fi

if [[ -n "$preflight_line" && -n "$postrun_line" && "$preflight_line" -lt "$postrun_line" ]]; then
  echo "  PASS: (8b) preflight runs BEFORE the synthetic check-run is posted ($preflight_line < $postrun_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8b) preflight does not precede the synthetic check-run POST (preflight=$preflight_line post=$postrun_line)"
  FAIL=$((FAIL + 1))
fi
echo ""

print_results
