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
# The CLA contexts {cla-check, cla-evidence} live in required-checks.txt but
# have no canonical JSON (only scripts/create-cla-required-ruleset.sh), so they
# are excluded by an EXPLICIT named set below. A 3rd CLA context requires
# updating CLA_EXCLUDE here.
#
# KNOWN GAP (entirely unguarded, not merely async): unlike the CI Required set —
# whose live↔canonical drift the daily Inngest cron-ruleset-bypass-audit catches
# next-day — the CLA Required ruleset has NEITHER a canonical JSON NOR audit-cron
# coverage. A live drift there (e.g. a 3rd required CLA context) is caught by no
# synchronous test AND no daily cron; the action would silently omit it and the
# bot PR would deadlock. Deferred hardening: mint a ci-cla-required-ruleset
# canonical JSON + extend the audit drift loop. Tracked in #6061.
#
# Refs: #6049

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

# Explicit CLA exclusion — no canonical JSON mirror exists for the CLA ruleset.
CLA_EXCLUDE=("cla-check" "cla-evidence")

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

print_results
