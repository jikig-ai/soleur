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
#      four install files (secret-scan.yml, ci.yml, main-health-monitor.yml, and
#      the action) — a silent divergence would scan the bot diff with a different
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
# Owning trap installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every direct run (#8659). The
# `:-` guard keeps it a no-op if the suite exits before allocating the scratch dir
# (e.g. the git-location tripwire's exit 97 inside the source line itself).
trap '[[ -z "${TMP:-}" ]] || rm -rf "$TMP"' EXIT
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
# 4th gitleaks install site (#7307). main-health-monitor.yml runs TEST_GROUP=all,
# so it needs the same gitleaks the gitleaks suites FAIL without under CI=true (#8266:
# they skip per arm and any skip fails under CI); an unregistered
# copy drifts silently and makes the monitor scan with a different gitleaks than CI.
MHM_YML="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
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
if [[ "$n_ci" -ge 11 && "$n_canon" -ge 11 ]]; then
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
jq '. + [{"context": "z-fake-context", "integration_id": 15368}]' "$CANONICAL" > "$TMP/canon-extra.json"
mut_diff=$(diff_sets "$CONFIG_FILE" "$TMP/canon-extra.json")
mut_missing=$(only_in_canon "$mut_diff" | sed '/^$/d')
assert_contains "$mut_missing" "z-fake-context" "(2) fake canonical context surfaces as a ⊇ violation"
echo ""

# --- Test 3: mutation — a dropped required-checks name is caught (⊇) --------
# Dropping a name FROM required-checks.txt that canonical still has is a ⊇
# violation (canonical ⊄ config): the name surfaces in `only_in_canon`.

echo "Test 3: removing a name from required-checks.txt FAILS (⊇)"
# Drop 'guards-ruleset' from a config copy; it must then surface as canonical-only.
grep -v '^guards-ruleset$' "$CONFIG_FILE" > "$TMP/cfg-drop.txt"
drop_diff=$(diff_sets "$TMP/cfg-drop.txt" "$CANONICAL")
drop_missing=$(only_in_canon "$drop_diff" | sed '/^$/d')
assert_contains "$drop_missing" "guards-ruleset" "(3) dropped name surfaces as a ⊇ violation (canonical has it, config doesn't)"
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

# --- Test 5: gitleaks pin-parity across all four install files --------------

echo "Test 5: gitleaks version + SHA256 pin is identical across all 4 sites"
extract_version() {
  grep -oE 'GITLEAKS_VERSION["]?[[:space:]]*[:=][[:space:]]*"?[0-9]+\.[0-9]+\.[0-9]+' "$1" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
extract_sha() {
  grep -oE 'GITLEAKS_SHA256["]?[[:space:]]*[:=][[:space:]]*"?[0-9a-f]{64}' "$1" \
    | grep -oE '[0-9a-f]{64}' | head -1
}
# IN-FILE duplicates are a parity surface too. `test-scripts-heavy` clones the
# gitleaks env block inside ci.yml, so the same pin now lives twice in one file —
# and the `head -1` extractors above would never see the second copy diverge.
extract_versions_all() {
  grep -oE 'GITLEAKS_VERSION["]?[[:space:]]*[:=][[:space:]]*"?[0-9]+\.[0-9]+\.[0-9]+' "$1" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u
}
extract_shas_all() {
  grep -oE 'GITLEAKS_SHA256["]?[[:space:]]*[:=][[:space:]]*"?[0-9a-f]{64}' "$1" \
    | grep -oE '[0-9a-f]{64}' | sort -u
}

for f in "$SECRET_SCAN_YML" "$CI_YML" "$ACTION_YML" "$MHM_YML"; do
  assert_file_exists "$f" "pin site exists: ${f##*/}"
done

ss_v=$(extract_version "$SECRET_SCAN_YML"); ss_s=$(extract_sha "$SECRET_SCAN_YML")
ci_v=$(extract_version "$CI_YML");          ci_s=$(extract_sha "$CI_YML")
ac_v=$(extract_version "$ACTION_YML");       ac_s=$(extract_sha "$ACTION_YML")
mhm_v=$(extract_version "$MHM_YML");         mhm_s=$(extract_sha "$MHM_YML")

# Non-empty guard first — a missing pin would make two empties compare equal.
if [[ -n "$ss_v" && -n "$ss_s" && -n "$ci_v" && -n "$ci_s" && -n "$ac_v" && -n "$ac_s" && -n "$mhm_v" && -n "$mhm_s" ]]; then
  echo "  PASS: (5a) all four sites declare a gitleaks version + SHA256 pin"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (5a) a gitleaks pin is missing — ss=[$ss_v/$ss_s] ci=[$ci_v/$ci_s] action=[$ac_v/$ac_s] mhm=[$mhm_v/$mhm_s]"
  FAIL=$((FAIL + 1))
fi
assert_eq "$ss_v" "$ci_v" "(5b) secret-scan.yml version == ci.yml version"
assert_eq "$ss_v" "$ac_v" "(5c) secret-scan.yml version == action version"
assert_eq "$ss_s" "$ci_s" "(5d) secret-scan.yml SHA256 == ci.yml SHA256"
assert_eq "$ss_s" "$ac_s" "(5e) secret-scan.yml SHA256 == action SHA256"
assert_eq "$ss_v" "$mhm_v" "(5f) secret-scan.yml version == main-health-monitor version"
assert_eq "$ss_s" "$mhm_s" "(5g) secret-scan.yml SHA256 == main-health-monitor SHA256"

# (5g2/5g3) Every in-file declaration of the pin must agree — a file that says
# the same thing twice must say it ONCE. ci.yml now carries the gitleaks env in
# both test-scripts jobs; a bump that edits only the first copy stays green
# under 5b-5g while the heavy leg runs a different binary.
for f in "$SECRET_SCAN_YML" "$CI_YML" "$ACTION_YML" "$MHM_YML"; do
  _nv="$(extract_versions_all "$f" | grep -c . || true)"
  _ns="$(extract_shas_all "$f" | grep -c . || true)"
  assert_eq "1" "$_nv" "(5g2) ${f##*/} declares exactly one distinct gitleaks version"
  assert_eq "1" "$_ns" "(5g3) ${f##*/} declares exactly one distinct gitleaks SHA256"
done

# (5h/5i) The OPERATOR-FACING remediation strings carry the same version. These are
# a 5th and 6th declaration site the four-workflow comparison above cannot see: both
# GL_REMEDIATION literals tell a developer which gitleaks to install, and on a bump
# they go stale silently while 5a-5g stay green. The suites that assert "8.24.2" are
# no backstop — they would red, and the cheapest fix is to bump the TEST literal,
# leaving the remediation pointing at a version CI no longer uses.
extract_remediation_version() {
  grep -oE 'GL_REMEDIATION="[^"]*gitleaks [0-9]+\.[0-9]+\.[0-9]+' "$1" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
HOOK_SCAN="$REPO_ROOT/.claude/hooks/git-commit-secret-scan.sh"
PRD_SCAN="$REPO_ROOT/plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh"
hook_rv=$(extract_remediation_version "$HOOK_SCAN")
prd_rv=$(extract_remediation_version "$PRD_SCAN")
if [[ -n "$hook_rv" && -n "$prd_rv" ]]; then
  echo "  PASS: (5h) both GL_REMEDIATION strings declare a gitleaks version"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (5h) a GL_REMEDIATION version is missing or unparseable — hook=[$hook_rv] prd=[$prd_rv]"
  FAIL=$((FAIL + 1))
fi
assert_eq "$ss_v" "$hook_rv" "(5i) secret-scan.yml version == git-commit-secret-scan.sh remediation"
assert_eq "$ss_v" "$prd_rv"  "(5j) secret-scan.yml version == code-to-prd.sh remediation"
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
  if grep -vE '^[[:space:]]*#' "$f" | grep -cE >/dev/null '\$\{(line|rcline)%%#'; then
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
# The EARLIEST outward/irreversible side-effect the preflight must precede is the
# branch push (the local `git checkout -b` above it is not outward). Anchoring on
# `git push` rather than the far-downstream check-run POST catches a reorder that
# pushes the bot branch BEFORE scanning it (test-design review of PR #6883). The
# check-run POST anchor is retained below as an independent, weaker upper bound.
# Since #9454 (ADR-285) the push is `git_remote push ...` (the App token as a per-command header) and
# the check-run POST is `gh_gate api ...` (the workflow token); the bare spellings stay accepted.
sideeffect_line=$(grep -nE '^[[:space:]]*(git push |git_remote push )' "$ACTION_YML" | head -1 | cut -d: -f1 || true)
postrun_line=$(grep -nE '^[[:space:]]*(gh|gh_gate) api "repos/\$\{REPO\}/check-runs"' "$ACTION_YML" | head -1 | cut -d: -f1 || true)

if [[ -n "$preflight_line" ]]; then
  echo "  PASS: (8a) action.yml runs lint-credential-path-literals.py over \"\${PATHS[@]}\" (line $preflight_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8a) action.yml does NOT reproduce the credential-path scan over its staged paths."
  echo "        Without it the synthetic green for 'credential-path-guard' is FABRICATED over a"
  echo "        REACHABLE surface (weakness-digest.md). See ADR-139 + scripts/required-checks.txt."
  FAIL=$((FAIL + 1))
fi

# (8d) ENFORCEMENT LEG — the then-body must actually fail the step. Presence +
# ordering of the `if !` line (8a/8b) is satisfied by an INERT guard whose body
# was neutralized (`exit 1` → `:` / `true`, or the body deleted) — the scan then
# runs, prints its ::error::, and falls through to push+PR+synthetic anyway. Walk
# from the `if` line to the FIRST closing `fi` and require a non-zero `exit` in
# between. Without this, a one-token mutation defangs the gate while 8a/8b stay
# green (test-design review of PR #6883). `awk` exits 0 regardless; `|| true`
# keeps the substitution safe under `set -euo pipefail`.
enforce_exit=""
if [[ -n "$preflight_line" ]]; then
  enforce_exit=$(awk -v s="$preflight_line" '
    NR > s && /^[[:space:]]*fi[[:space:]]*$/ { exit }
    NR > s && /^[[:space:]]*exit[[:space:]]+[1-9]/ { print "yes"; exit }
  ' "$ACTION_YML" || true)
fi
if [[ "$enforce_exit" == "yes" ]]; then
  echo "  PASS: (8d) the credential-path then-body exits non-zero (guard is enforcing, not inert)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8d) the credential-path then-body does NOT exit non-zero before its closing 'fi'."
  echo "        The scan runs but does not fail the step — a bot PR with a credential path in"
  echo "        weakness-digest.md would push + post a fabricated green. See ADR-139."
  FAIL=$((FAIL + 1))
fi

# Non-vacuity: (8b) is meaningless if the git-push anchor stops resolving.
if [[ -n "$sideeffect_line" ]]; then
  echo "  PASS: (8c) non-vacuous — git-push side-effect anchor resolves (line $sideeffect_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8c) could not locate the branch push — (8b) ordering check would be vacuous"
  FAIL=$((FAIL + 1))
fi

if [[ -n "$preflight_line" && -n "$sideeffect_line" && "$preflight_line" -lt "$sideeffect_line" ]]; then
  echo "  PASS: (8b) preflight runs BEFORE the branch is pushed ($preflight_line < $sideeffect_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8b) preflight does not precede the branch push (preflight=$preflight_line push=$sideeffect_line)"
  FAIL=$((FAIL + 1))
fi

# (8e) Defense-in-depth upper bound: preflight also precedes the synthetic
# check-run POST. Weaker than 8b (a reorder between push and POST still passes)
# but pins the far end of the ordering invariant independently.
if [[ -n "$preflight_line" && -n "$postrun_line" && "$preflight_line" -lt "$postrun_line" ]]; then
  echo "  PASS: (8e) preflight also precedes the synthetic check-run POST ($preflight_line < $postrun_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (8e) preflight does not precede the synthetic check-run POST (preflight=$preflight_line post=$postrun_line)"
  FAIL=$((FAIL + 1))
fi

# --- Test 9: waiver-discipline green is EARNED, not fabricated (#12276) ------
#
# `waiver-discipline` is a member of the required `secret-guards` context, so
# the composite action posts an unconditional green synthetic for it on every
# bot PR. The pre-fold justification argued unreachability: the only file a bot
# PR may write, knowledge-base/project/weakness-digest.md, contains no
# `gitleaks:allow` token. But that file is emitted verbatim by
# weakness-miner.sh — the argument was a claim about a GENERATOR's current
# output format, not a bound on the format. The action now mirrors the member's
# own predicate over the staged diff, so the green is earned whatever the
# digest's format becomes.
#
# Same anchor discipline as Test 8: the presence anchor is syntactic
# (`^\s*violations=$(git diff --cached`), never a bare token — the arm's own
# comment names `gitleaks:allow`, and a mention-grep would pass against a
# deleted arm. The enforcement leg walks the `if [[ -n ... ]]` line to its `fi`
# requiring a non-zero exit, same defang class as (8d).

echo "Test 9: action.yml EARNS the waiver-discipline green (#12276)"
waiver_scan_line=$(grep -nE '^[[:space:]]*violations=\$\(git diff --cached --unified=0' "$ACTION_YML" | head -1 | cut -d: -f1 || true)
waiver_gate_line=$(grep -nE '^[[:space:]]*if \[\[ -n "\$violations" \]\]; then' "$ACTION_YML" | head -1 | cut -d: -f1 || true)

if [[ -n "$waiver_scan_line" && -n "$waiver_gate_line" ]]; then
  echo "  PASS: (9a) action.yml reproduces the waiver-discipline scan over the staged diff (scan=$waiver_scan_line gate=$waiver_gate_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (9a) action.yml does NOT reproduce the waiver-discipline scan/gate."
  echo "        Without it the synthetic green for 'waiver discipline (issue:#NNN trailer)' is"
  echo "        unearned — defensible only by an argument about a generated file's format. See #12276."
  FAIL=$((FAIL + 1))
fi

# (9b) the predicate must actually mirror the member's: the trailer grep
# `issue:#[0-9]+` inside the pipeline is the discriminating stage — without it
# any gitleaks:allow mention trips the arm (a false-positive gate), and the
# member would still red what the synthetic greened.
waiver_pred=$(awk -v s="$waiver_scan_line" 'NR > s && /issue:#\[0-9\]/ { print "yes"; exit } NR > s && /\|\| true\)/ { exit }' "$ACTION_YML" || true)
if [[ "$waiver_pred" == "yes" ]]; then
  echo "  PASS: (9b) the staged-diff pipeline carries the issue:#NNN trailer predicate"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (9b) the staged-diff pipeline lacks the issue:#NNN trailer predicate."
  echo "        A bare gitleaks:allow grep does not mirror the member's trailer requirement."
  FAIL=$((FAIL + 1))
fi

# (9c) ENFORCEMENT LEG — the then-body must fail the step, same defang class as (8d).
waiver_enforce=""
if [[ -n "$waiver_gate_line" ]]; then
  waiver_enforce=$(awk -v s="$waiver_gate_line" '
    NR > s && /^[[:space:]]*fi[[:space:]]*$/ { exit }
    NR > s && /^[[:space:]]*exit[[:space:]]+[1-9]/ { print "yes"; exit }
  ' "$ACTION_YML" || true)
fi
if [[ "$waiver_enforce" == "yes" ]]; then
  echo "  PASS: (9c) the waiver-discipline then-body exits non-zero (guard is enforcing, not inert)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (9c) the waiver-discipline then-body does NOT exit non-zero before its closing 'fi'."
  FAIL=$((FAIL + 1))
fi

# (9d) ordering — the scan must precede the branch push (anchors resolved in Test 8).
if [[ -n "$waiver_scan_line" && -n "$sideeffect_line" && "$waiver_scan_line" -lt "$sideeffect_line" ]]; then
  echo "  PASS: (9d) waiver scan runs BEFORE the branch is pushed ($waiver_scan_line < $sideeffect_line)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (9d) waiver scan does not precede the branch push (scan=$waiver_scan_line push=$sideeffect_line)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Test 10: pinned release-download curls carry --fail/--retry 5/--retry-all-errors
#
# Every `curl` that downloads a pinned gitleaks or actionlint release in a workflow
# or composite action must carry `--fail`, `--retry 5` and `--retry-all-errors` as
# exact tokens on the logical command (continuation lines joined, whole-line `#`
# comments dropped). `-f`/`-fsSL` does NOT satisfy `--fail` (the owner named the long
# flag), and `--retry 50` / `--fail-with-body` / a bare `--retry-all-errors` do not
# satisfy the others. Flags in a comment or an `echo` line near the curl are not on it.
# The retry budget is about 31 s: this survives a blip, not a multi-hour outage.
#
# scan_curl_flags prints one line per matching curl: FILE|LINE|KIND|OK or
# FILE|LINE|KIND|MISSING <flags>, and exits 1 if any command is missing a flag.
# POSIX awk only (the runner may have mawk): no gensub, IGNORECASE or {n} intervals.
scan_curl_flags() {
  local f scan_rc=0
  for f in "$@"; do
    awk -v file="$f" '
      # Quote-aware: a `#`, `;`, `|` or `&` inside a quoted string (a header value, a URL query) is data, not shell syntax.
      # \047 is a single quote (the whole program is single-quoted for bash).
      function open_quote(s,   i, n, c, q) {
        n = length(s); q = ""
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (q == "") {
            if (c == "\\") i++
            else if (c == "\"" || c == "\047") q = c
          } else if (q == "\"" && c == "\\") i++
          else if (c == q) q = ""
        }
        return q
      }
      function strip_comment(s, q0,   i, n, c, q, p) {
        n = length(s); q = q0; p = " "
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (q == "") {
            if (c == "\\") { i++; p = "x"; continue }
            if (c == "\"" || c == "\047") q = c
            else if (c == "#" && (p == " " || p == "\t")) return substr(s, 1, i - 1)
          } else if (q == "\"" && c == "\\") i++
          else if (c == q) q = ""
          p = c
        }
        return s
      }
      function split_cmds(s, out,   i, n, c, q, p, k, cur, nx) {
        n = length(s); q = ""; k = 0; cur = ""; p = ""
        for (i = 1; i <= n; i++) {
          c = substr(s, i, 1)
          if (q != "") {
            cur = cur c
            if (q == "\"" && c == "\\") { i++; cur = cur substr(s, i, 1) }
            else if (c == q) q = ""
            p = c; continue
          }
          if (c == "\\") { cur = cur c substr(s, i + 1, 1); i++; p = "x"; continue }
          if (c == "\"" || c == "\047") { q = c; cur = cur c; p = c; continue }
          if (c == ";" || c == "|" || c == "&") {
            nx = substr(s, i + 1, 1)
            if (c == "&" && (p == ">" || nx == ">")) { cur = cur c; p = c; continue }   # 2>&1 and &> are redirections
            out[++k] = cur; cur = ""; p = c; continue
          }
          cur = cur c; p = c
        }
        out[++k] = cur
        return k
      }
      function finish(   kind, miss, n, i, seg, parts) {
        n = split_cmds(buf, parts)
        for (i = 1; i <= n; i++) {
          seg = parts[i]
          if (seg !~ /(^|[[:space:]("`])curl[[:space:]]/) continue
          kind = ""
          if (index(seg, "gitleaks/gitleaks/releases/download")) kind = "gitleaks"
          else if (index(seg, "rhysd/actionlint/releases/download")) kind = "actionlint"
          if (kind == "") continue
          miss = ""
          if (seg !~ /(^|[[:space:]])--fail([[:space:]]|$)/) miss = miss " --fail"
          if (seg !~ /(^|[[:space:]])--retry[[:space:]]+5([[:space:]]|$)/) miss = miss " --retry-5"
          if (seg !~ /(^|[[:space:]])--retry-all-errors([[:space:]]|$)/) miss = miss " --retry-all-errors"
          if (miss != "") bad = 1
          printf "%s|%d|%s|%s\n", file, start, kind, (miss == "" ? "OK" : "MISSING" miss)
        }
        buf = ""
      }
      # A line inside a quoted string that began on an earlier continuation line is data, even if it starts with `#`.
      /^[[:space:]]*#/ { if (buf == "" || open_quote(buf) == "") next }
      {
        if (buf == "") start = NR
        phys = $0
        phys = strip_comment(phys, (buf == "" ? "" : open_quote(buf)))   # a trailing comment (a `#` outside quotes) is not part of the command
        if (phys ~ /\\$/) { sub(/\\$/, " ", phys); buf = buf " " phys; next }
        buf = buf " " phys
        finish()
      }
      END { if (buf != "") finish(); exit bad }
    ' "$f" || scan_rc=1
  done
  return "$scan_rc"
}

# strip_flag_once SRC DST FLAG: copy SRC to DST, removing the first occurrence of FLAG
# (with its leading space) from the line directly above a gitleaks/actionlint download
# URL line, i.e. from the curl command line of that download, never from another curl.
strip_flag_once() {
  awk -v flag=" $3" '
    { l[NR] = $0 }
    END {
      for (i = 1; i < NR; i++) {
        if (!done && l[i+1] ~ /releases\/download\/v\$\{(GITLEAKS|ACTIONLINT)_VERSION\}/ && (p = index(l[i], flag))) {
          l[i] = substr(l[i], 1, p - 1) substr(l[i], p + length(flag))
          done = 1
        }
      }
      for (i = 1; i <= NR; i++) print l[i]
    }
  ' "$1" > "$2"
}

echo "Test 10: gitleaks/actionlint release-download curls carry --fail --retry 5 --retry-all-errors"
# collect_curl_scan_files ROOT: every workflow and composite-action file the scan covers (.yml and .yaml), one per line.
collect_curl_scan_files() {
  local root="$1" a=()
  shopt -s nullglob
  a=("$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml "$root"/.github/actions/*/action.yml "$root"/.github/actions/*/action.yaml)
  shopt -u nullglob
  if [[ ${#a[@]} -gt 0 ]]; then printf '%s\n' "${a[@]}"; fi
}
mapfile -t CURL_SCAN_FILES < <(collect_curl_scan_files "$REPO_ROOT")

scan_rc=0
scan_out=$(scan_curl_flags "${CURL_SCAN_FILES[@]}") || scan_rc=$?
n_gl=$(printf '%s\n' "$scan_out" | grep -c '|gitleaks|' || true)
n_al=$(printf '%s\n' "$scan_out" | grep -c '|actionlint|' || true)
n_bad=$(printf '%s\n' "$scan_out" | grep -c '|MISSING' || true)
# Independent raw count: NON-comment lines carrying the variable-form URL fragment
# (the literal-version URL in a secret-scan.yml comment must not be counted).
# Counts EVERY line carrying the variable-form URL, comment or not: a `#` inside a quoted header (even one that starts a
# continuation line) must not hide a URL from this cross-check. A commented-out variable-form URL would make this
# disagree loudly, which is the cheap direction to fail.
n_raw=$({ grep -h -E 'releases/download/v\$\{(GITLEAKS|ACTIONLINT)_VERSION\}' "${CURL_SCAN_FILES[@]}" || true; } | wc -l | tr -d ' ')

assert_eq "0" "$n_bad" "(10a) no gitleaks/actionlint download curl is missing a hardening flag"
if [[ "$n_bad" -ne 0 ]]; then printf '%s\n' "$scan_out" | grep '|MISSING' | sed 's/^/        /'; fi
assert_eq "0" "$scan_rc" "(10b) scanner exits 0 on the real tree"
if [[ "$n_gl" -ge 7 ]]; then
  echo "  PASS: (10c) non-vacuous — $n_gl gitleaks download curls scanned (floor 7)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (10c) only $n_gl gitleaks download curls scanned (floor 7)"
  FAIL=$((FAIL + 1))
fi
if [[ "$n_al" -ge 1 ]]; then
  echo "  PASS: (10d) non-vacuous — $n_al actionlint download curls scanned (floor 1)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: (10d) only $n_al actionlint download curls scanned (floor 1)"
  FAIL=$((FAIL + 1))
fi
assert_eq "$n_raw" "$((n_gl + n_al))" "(10e) scanner count == independent raw count of non-comment download URL lines"

# (10f) mutation self-test: removing ONE flag from the curl line of the first download in a
# temp copy of each scanned file must make the scanner FAIL it and name the missing flag.
# A mutation that changed nothing (cmp equal) fails the arm instead of passing vacuously.
for f in "${CURL_SCAN_FILES[@]}"; do
  grep -qE 'releases/download/v\$\{(GITLEAKS|ACTIONLINT)_VERSION\}' "$f" || continue
  base="${f##*/}"
  [[ "$base" == "action.yml" ]] && base="bot-pr-action.yml"
  for flag in --fail "--retry 5" --retry-all-errors; do
    mut="$TMP/mut-${base}-${flag// /_}"
    strip_flag_once "$f" "$mut" "$flag"
    if cmp -s "$f" "$mut"; then
      echo "  FAIL: (10f) mutation of '$flag' in $base changed nothing (flag absent on the curl line)"
      FAIL=$((FAIL + 1))
      continue
    fi
    m_rc=0
    m_out=$(scan_curl_flags "$mut") || m_rc=$?
    if [[ "$m_rc" -ne 0 && "$m_out" == *"|MISSING"* ]]; then
      echo "  PASS: (10f) scanner FAILS $base with '$flag' stripped"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: (10f) scanner did not flag $base with '$flag' stripped (rc=$m_rc)"
      FAIL=$((FAIL + 1))
    fi
  done
done

# (10g) synthesized fixtures. Must-PASS: flags in a different order, `-sSL` before them,
# the output file given via `-o` after them.
cat > "$TMP/curl-pass.yml" <<'YML'
      run: |
        curl -sSL --retry-all-errors --retry 5 --fail -o gitleaks.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
        echo "${GITLEAKS_SHA256}  gitleaks.tgz" | sha256sum -c -
YML
p_rc=0; p_out=$(scan_curl_flags "$TMP/curl-pass.yml") || p_rc=$?
assert_eq "0" "$p_rc" "(10g) flags in a different order still PASS"
assert_contains "$p_out" "|gitleaks|OK" "(10g) the reordered command is counted as one gitleaks curl"

# Must-FAIL fixtures, one defect each.
neg_check() {  # neg_check NAME EXPECTED-MISSING-FLAG  (fixture body on stdin)
  local name="$1" want="$2" nrc=0 nout
  cat > "$TMP/neg-$name.yml"
  nout=$(scan_curl_flags "$TMP/neg-$name.yml") || nrc=$?
  if [[ "$nrc" -ne 0 && "$nout" == *"|MISSING"*"$want"* ]]; then
    echo "  PASS: (10h) $name is rejected (missing$want)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: (10h) $name was not rejected for $want (rc=$nrc out=$nout)"
    FAIL=$((FAIL + 1))
  fi
}
neg_check short-f " --fail" <<'YML'
        curl -fsSL --retry 5 --retry-all-errors -o gitleaks.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check fail-with-body " --fail" <<'YML'
        curl --fail-with-body --retry 5 --retry-all-errors -sSLo a.tgz \
          "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
YML
neg_check retry-50 " --retry-5" <<'YML'
        curl --fail --retry 50 --retry-all-errors -sSLo a.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check flags-in-comment-and-echo " --fail" <<'YML'
        # curl --fail --retry 5 --retry-all-errors
        echo "--fail --retry 5 --retry-all-errors"
        curl -sSLo a.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check flags-in-trailing-comment " --fail" <<'YML'
        curl -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" # --fail --retry 5 --retry-all-errors
YML
neg_check flags-in-chained-echo " --fail" <<'YML'
        curl -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" && echo --fail --retry 5 --retry-all-errors
YML
neg_check hardened-curl-masks-second-on-one-line " --retry-all-errors" <<'YML'
        curl --fail --retry 5 --retry-all-errors -sSLo a.tgz "https://example.invalid/x"; curl --fail --retry 5 -sSLo b.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check standalone-f-with-retry " --fail" <<'YML'
        curl -f --retry 5 --retry-all-errors -sSLo a.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check second-copy-unhardened " --retry-all-errors" <<'YML'
        curl --fail --retry 5 --retry-all-errors -sSLo a.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
        curl --fail --retry 5 -sSLo b.tgz \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
# Quote-awareness and command-boundary fixtures. A `#` or `;` inside a quoted header is data, so the curl is still seen
# (and rejected); a `|` or `&` ends the command, so flags on the far side of it are not on the curl.
neg_check quoted-hash-in-header " --fail" <<'YML'
        curl -sSL -H "X: a #b" -o a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check semicolon-in-header " --fail" <<'YML'
        curl -sSL -H "X: a;b" -o a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
neg_check flags-after-pipe " --fail" <<'YML'
        curl -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" | tee --fail --retry 5 --retry-all-errors
YML
neg_check flags-after-background-amp " --fail" <<'YML'
        curl -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" & echo --fail --retry 5 --retry-all-errors
YML
neg_check command-substitution " --fail" <<'YML'
        x=$(curl -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz")
YML
neg_check hash-line-inside-continued-quote " --fail" <<'YML'
        curl -sSL -H "X: a \
          #b" -o a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
YML
cat > "$TMP/curl-pass-query.yml" <<'YML'
        curl --fail --retry 5 --retry-all-errors -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz?a=1;b=2&c=3"
YML
q_rc=0; q_out=$(scan_curl_flags "$TMP/curl-pass-query.yml") || q_rc=$?
assert_eq "0" "$q_rc" "(10i) a quoted URL query containing ; and & is not split"
assert_contains "$q_out" "|gitleaks|OK" "(10i) the quoted-query command is counted as one gitleaks curl"
cat > "$TMP/curl-pass-redirect.yml" <<'YML'
        curl --fail --retry 5 --retry-all-errors -sSLo a.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" 2>&1 | cat
YML
r_rc=0; r_out=$(scan_curl_flags "$TMP/curl-pass-redirect.yml") || r_rc=$?
assert_eq "0" "$r_rc" "(10i) a 2>&1 redirection is not a command boundary"
assert_contains "$r_out" "|gitleaks|OK" "(10i) the redirected command is counted as one gitleaks curl"

# (10j) the file collector covers .yml AND .yaml in both locations (a .yaml-only copy of the install would otherwise go unscanned).
mkdir -p "$TMP/tree/.github/workflows" "$TMP/tree/.github/actions/x" "$TMP/tree/.github/actions/y"
: > "$TMP/tree/.github/workflows/a.yml"; : > "$TMP/tree/.github/workflows/b.yaml"
: > "$TMP/tree/.github/actions/x/action.yml"; : > "$TMP/tree/.github/actions/y/action.yaml"
tree_out=$(collect_curl_scan_files "$TMP/tree")
assert_eq "4" "$(printf '%s\n' "$tree_out" | grep -c . || true)" "(10j) the collector finds .yml and .yaml workflows and composite actions"
assert_contains "$tree_out" "workflows/b.yaml" "(10j) a .yaml workflow is collected"
assert_contains "$tree_out" "actions/y/action.yaml" "(10j) a .yaml composite action is collected"
# Independent of the collector: the same set found with find must equal what the real scan covered.
n_find=$({ find "$REPO_ROOT/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \); find "$REPO_ROOT/.github/actions" -mindepth 2 -maxdepth 2 -type f \( -name action.yml -o -name action.yaml \); } | wc -l | tr -d ' ')
assert_eq "$n_find" "${#CURL_SCAN_FILES[@]}" "(10j) the real scan covers every workflow and action file find sees"
echo ""

# --- Test 11: the lint-cve-safe-status part of the synthetic greens is EARNED (#12348) --
#
# scripts/lint-cve-safe-status.py scans every tracked KB index entry as the guards-ruleset
# member `cve-safe-status`, and ALLOWED_PATHS (weakness-digest.md) sits inside that surface, so
# the synthetic greens the action posts are sound only if the action runs the lint over its
# own staged paths first, and stops when the lint fails.
#
# t11_exec (CTO rulings E4, V1, V5, X2-X5) parses the action with PyYAML and takes the single
# composite step whose run body holds `git add --`. It requires one non-comment line in that
# body naming the lint, no `if:`, `shell: bash`, and an `env:` of `${{ inputs.* }}` and
# `${{ github.repository }}` only. It runs the body from its first line through the line
# before the first line after the arm that names a push (`git push ` or `git_remote push ` at
# line start), plus a sentinel line, under the step's own shell, with the inputs and the
# modeled runner env set and PATH holding only the stubs below. A stub refuses any argv it
# does not model, and `command_not_found_handle` refuses a command with no stub; both write a
# STUB-MISS record, which is RED. Every row runs twice. With the lint stub exiting 1, OK means:
# nothing refused, rc 1, the sentinel not reached, `git add` once with the fixture PATHS, and
# the lint once with argv `-I scripts/lint-cve-safe-status.py --paths <those PATHS>`. With it
# exiting 0 (the positive control), the same with rc 0, the sentinel reached and one commit.
# So Test 11 grades what the step does between its first line and that push line. A new
# command in the span fails closed until a stub models it; that is the intended cost.
#
# t11_text keeps the older textual anchors (a unique syntactic arm, an `exit [1-9]` before its
# `fi`, placement after `git add` and before the push and the check-run POST, and a
# block-opener heuristic between `git add` and the arm) as diagnostics. A mutant is reported
# when either layer is RED; the rows in T11_EXEC_KILLS must be RED in the execution layer alone.
#
# Residuals, stated permanently (CTO ruling Q-end). A finding that is a new spelling inside one
# of them is "covered by R<n>", not a fix item.
#   S0    Tests 11 and 12 guard the gates' shape against drift. They do not prove the gates
#         hold against an edit written to beat them: the workflow, the action, the lint and
#         this test are all reviewed files.
#   R11-1 Only the span above is executed. The push, anything after it, and which commit the
#         check-run POST names are not. An earlier line after the arm that spells a push ends
#         the span there.
#   R11-2 Only the modeled runner env is exercised. Any branch on host, filesystem, tool or
#         environment state the harness does not model (for example a `.git` dir, a tracked
#         file, `command -v` of a tool, a runner path, HOSTNAME or image variables, or an
#         unseeded or differently valued RUNNER_*/GITHUB_* name) runs differently on a runner.
#   R11-3 Stubs intercept by PATH lookup only. A command reached by an absolute path or another
#         route around PATH is not seen.
#   R11-4 The text layer is a heuristic diagnostic, not a proof.
echo "Test 11: action.yml EARNS the lint-cve-safe-status part of the synthetic greens (#12348)"
t11_text() {
  local f="$1" arm narm add push post enforce depth
  arm=$(grep -nE '^[[:space:]]*if ! python3 -I scripts/lint-cve-safe-status\.py --paths "\$\{PATHS\[@\]\}"; then[[:space:]]*$' "$f" | head -1 | cut -d: -f1 || true)
  narm=$(grep -cE '^[[:space:]]*[^#[:space:]].*scripts/lint-cve-safe-status\.py' "$f" || true)
  add=$(grep -nE '^[[:space:]]*git add -- "\$\{PATHS\[@\]\}"[[:space:]]*$' "$f" | head -1 | cut -d: -f1 || true)
  push=$(grep -nE '^[[:space:]]*(git push |git_remote push )' "$f" | head -1 | cut -d: -f1 || true)
  post=$(grep -nE '^[[:space:]]*(gh|gh_gate) api "repos/\$\{REPO\}/check-runs"' "$f" | head -1 | cut -d: -f1 || true)
  [[ -n "$arm" ]] || { echo "RED:no-arm"; return 0; }
  [[ "$narm" == "1" ]] || { echo "RED:arm-not-unique:$narm"; return 0; }
  [[ -n "$add" && -n "$push" && -n "$post" ]] || { echo "RED:no-side-effect-anchor"; return 0; }
  (( add < arm )) || { echo "RED:before-add"; return 0; }
  depth=$(awk -v a="$add" -v b="$arm" '
    NR > a && NR < b && !/^[[:space:]]*#/ {
      if ($0 ~ /<</) h = 1
      if ($0 ~ /^[[:space:]]*(if|for|while|until|case|function)([[:space:]]|$)/ || $0 ~ /\{[[:space:]]*(#.*)?$/) d++
      if ($0 ~ /^[[:space:]]*(fi|done|esac)([[:space:]]*;?[[:space:]]*$|[[:space:]]+#)/ || $0 ~ /^[[:space:]]*\}/) d--
    }
    END { if (h) print "heredoc"; else print d + 0 }
  ' "$f" || true)
  [[ "$depth" == "0" ]] || { echo "RED:opener-heuristic:$depth"; return 0; }
  enforce=$(awk -v s="$arm" '
    NR > s && /^[[:space:]]*fi[[:space:]]*$/ { exit }
    NR > s && /^[[:space:]]*exit[[:space:]]+[1-9]/ { print "yes"; exit }
  ' "$f" || true)
  [[ "$enforce" == "yes" ]] || { echo "RED:inert-body"; return 0; }
  (( arm < push )) || { echo "RED:after-push"; return 0; }
  (( arm < post )) || { echo "RED:after-post"; return 0; }
  echo "OK"
}

# The stubs. PATH inside the region is $T11_BIN alone, so an external command with no stub
# here is "command not found" (rc 127), which is RED too. Helpers and the real tools some
# stubs delegate to are baked in as absolute paths; nothing the region runs reaches them.
T11_DIR="$TMP/t11"; T11_BIN="$T11_DIR/bin"; T11_LIB="$T11_DIR/lib"
mkdir -p "$T11_BIN" "$T11_LIB" "$T11_DIR/runs"
T11_BASH=$(type -P bash)
{
  printf 'T11_REAL_TR=%q\nT11_REAL_GREP=%q\nT11_REAL_MKTEMP=%q\nT11_REAL_CP=%q\nT11_LIB=%q\n' \
    "$(type -P tr)" "$(type -P grep)" "$(type -P mktemp)" "$(type -P cp)" "$T11_LIB"
  cat <<'T11COMMON'
st="${T11_STATE:?}"
t11_log() { printf '%s\0' "$NAME" "$@" >> "$st/calls"; printf '\036' >> "$st/calls"; }
t11_miss() {
  { printf 'STUB-MISS: %s' "$NAME"; printf ' %q' "$@"; printf '\n'; } >> "$st/miss"
  echo "t11 stub refused: $NAME $*" >&2
  exit 64
}
t11_added() { [[ -e "$st/added" ]]; }
t11_dir() { [[ -s "$st/mktemp_dir" ]] || t11_miss "$@"; D=$(<"$st/mktemp_dir"); }
t11_log "$@"
T11COMMON
} > "$T11_LIB/common.sh"
t11_stub() {  # t11_stub NAME DEST < body
  { printf '#!%s\nset -u\nNAME=%q\n. %q\n' "$T11_BASH" "$1" "$T11_LIB/common.sh"; cat; } > "$2"
  chmod +x "$2"
}
t11_stub git "$T11_BIN/git" <<'T11STUB'
case "${1-}" in
  config)
    t11_added && t11_miss "$@"
    [[ $# -eq 3 && ( "$2" == user.name || "$2" == user.email ) ]] || t11_miss "$@"
    exit 0 ;;
  add)
    t11_added && t11_miss "$@"
    [[ $# -ge 3 && "$2" == "--" ]] || t11_miss "$@"
    : > "$st/added"; exit 0 ;;
  diff)
    t11_added || t11_miss "$@"
    [[ -e "$st/ls_remote" ]] && t11_miss "$@"
    [[ "${2-}" == --cached ]] || t11_miss "$@"
    [[ $# -eq 3 && "$3" == --quiet ]] && exit 1
    [[ $# -ge 4 && "$3" == --unified=0 && "$4" == -- ]] || t11_miss "$@"
    exit 0 ;;
  # After the arm, in this order and once each: the branch probe, the branch cut, the commit.
  ls-remote)
    t11_added && [[ ! -e "$st/ls_remote" ]] || t11_miss "$@"
    [[ $# -eq 5 && "$2" == --exit-code && "$3" == --heads && "$4" == origin \
      && "$5" == "refs/heads/$(<"$st/branch")" ]] || t11_miss "$@"
    : > "$st/ls_remote"; exit 2 ;;
  checkout)
    [[ -e "$st/ls_remote" && ! -e "$st/checked_out" ]] || t11_miss "$@"
    [[ $# -eq 3 && "$2" == -b && "$3" == "$(<"$st/branch")" ]] || t11_miss "$@"
    : > "$st/checked_out"; exit 0 ;;
  commit)
    [[ -e "$st/checked_out" && ! -e "$st/committed" ]] || t11_miss "$@"
    [[ $# -eq 3 && "$2" == -m && "$3" == "$(<"$st/commit_msg")" ]] || t11_miss "$@"
    : > "$st/committed"; exit 0 ;;
esac
t11_miss "$@"
T11STUB
t11_stub date "$T11_BIN/date" <<'T11STUB'
[[ $# -eq 2 && "$1" == -u && "$2" == +%Y-%m-%d ]] || t11_miss "$@"
printf '%s\n' "$(<"$st/date")"
T11STUB
t11_stub base64 "$T11_BIN/base64" <<'T11STUB'
# Only the extra-header encoding: `printf … | base64 -w0`, stdin consumed, a fixture word out.
[[ $# -eq 1 && "$1" == -w0 ]] || t11_miss "$@"
IFS= read -r -d '' t11_in || true
printf 't11fixtureheader'
T11STUB
t11_stub python3 "$T11_BIN/python3" <<'T11STUB'
case "${1-}" in
  -I)
    [[ $# -ge 4 && "$2" == scripts/lint-cve-safe-status.py && "$3" == --paths ]] || t11_miss "$@"
    exit "$(<"$st/cve_rc")" ;;
  scripts/lint-credential-path-literals.py)
    [[ $# -ge 2 ]] || t11_miss "$@"
    exit 0 ;;
esac
t11_miss "$@"
T11STUB
t11_stub node "$T11_BIN/node" <<'T11STUB'
[[ $# -ge 2 && "$1" == apps/web-platform/scripts/lint-fixture-content.mjs ]] && exit 0
t11_miss "$@"
T11STUB
t11_stub mktemp "$T11_BIN/mktemp" <<'T11STUB'
[[ $# -eq 1 && "$1" == -d && ! -e "$st/mktemp_dir" ]] || t11_miss "$@"
d=$("$T11_REAL_MKTEMP" -d "$st/tmp.XXXXXX") || exit 1
printf '%s\n' "$d" > "$st/mktemp_dir"
printf '%s\n' "$d"
T11STUB
t11_stub curl "$T11_BIN/curl" <<'T11STUB'
t11_dir "$@"
[[ $# -eq 7 && "$1" == --fail && "$2" == --retry && "$3" == 5 && "$4" == --retry-all-errors \
  && "$5" == -sSLo && "$6" == "$D/gitleaks.tgz" \
  && "$7" == https://github.com/gitleaks/gitleaks/releases/download/v*/gitleaks_*_linux_x64.tar.gz ]] || t11_miss "$@"
printf 't11 fixture tarball\n' > "$D/gitleaks.tgz"
T11STUB
t11_stub sha256sum "$T11_BIN/sha256sum" <<'T11STUB'
t11_dir "$@"
[[ $# -eq 2 && "$1" == -c && "$2" == - ]] || t11_miss "$@"
IFS= read -r line || t11_miss "$@"
[[ "$line" =~ ^[0-9a-f]{64}\ \ (.*)$ && "${BASH_REMATCH[1]}" == "$D/gitleaks.tgz" ]] || t11_miss "$@" "<stdin:$line>"
T11STUB
t11_stub tar "$T11_BIN/tar" <<'T11STUB'
t11_dir "$@"
[[ $# -eq 5 && "$1" == -xzf && "$2" == "$D/gitleaks.tgz" && "$3" == -C && "$4" == "$D" && "$5" == gitleaks ]] || t11_miss "$@"
"$T11_REAL_CP" "$T11_LIB/gitleaks" "$D/gitleaks"
T11STUB
t11_stub chmod "$T11_BIN/chmod" <<'T11STUB'
t11_dir "$@"
[[ $# -eq 2 && "$1" == +x && "$2" == "$D/gitleaks" ]] || t11_miss "$@"
T11STUB
t11_stub gitleaks "$T11_LIB/gitleaks" <<'T11STUB'
t11_added || t11_miss "$@"
[[ "$*" == "git --pre-commit --staged --redact --no-banner --exit-code 1" ]] || t11_miss "$@"
T11STUB
t11_stub tr "$T11_BIN/tr" <<'T11STUB'
[[ $# -eq 2 && "$1" == "[:upper:]" && "$2" == "[:lower:]" ]] || t11_miss "$@"
exec "$T11_REAL_TR" "$@"
T11STUB
t11_stub grep "$T11_BIN/grep" <<'T11STUB'
# Only the stdin filters of the waiver-discipline pipeline: one flag, one pattern, no file.
[[ $# -eq 2 && ( "$1" == -E || "$1" == -v || "$1" == -vE ) ]] || t11_miss "$@"
exec "$T11_REAL_GREP" "$@"
T11STUB

t11_exec() {  # t11_exec CVE_RC FILE... : prints one verdict line (OK|RED:<why>) per FILE
  python3 - "$T11_BIN" "$T11_DIR/runs" "$T11_BASH" "$@" <<'T11PY'
import os, re, subprocess, sys, tempfile
import yaml
stubs, runs, bash, cve_rc = sys.argv[1:5]
want_rc = int(cve_rc)
DIGEST = "knowledge-base/project/weakness-digest.md"
# Twice, so `${PATHS[0]}` cannot pass for `${PATHS[@]}`; the blank line exercises the parser.
INPUTS = {"add-paths": DIGEST + "\n\n" + DIGEST + "\n", "branch-prefix": "t11/fixture-",
          "commit-message": "t11 fixture", "pr-title-prefix": "t11 fixture",
          "pr-body": "t11 fixture body", "change-summary": "t11 fixture",
          "pr-token": "fixture-pr-token", "gh-token": "fixture-gate-token",
          "draft": "false", "skip-auto-merge": "false", "labels": ""}
STAGED = [DIGEST, DIGEST]
FIXTURE_DATE = "2000-01-01"
BRANCH = INPUTS["branch-prefix"] + FIXTURE_DATE
def verdict(src):
    try:
        doc = yaml.safe_load(open(src, encoding="utf-8"))
        steps = doc["runs"]["steps"]
    except Exception as e:
        return "yaml:%s" % type(e).__name__
    hold = [s for s in steps if isinstance(s, dict) and isinstance(s.get("run"), str)
            and re.search(r"(?m)^\s*git add --", s["run"])]
    if len(hold) != 1:
        return "add-step-count:%d" % len(hold)
    step = hold[0]
    if "if" in step:
        return "add-step-has-if"
    if step.get("shell") != "bash":
        return "add-step-shell:%s" % step.get("shell")
    env = {"PATH": stubs, "GITHUB_REF": "refs/heads/main"}
    for k, v in (step.get("env") or {}).items():
        m = re.fullmatch(r"\$\{\{ inputs\.([a-z-]+) \}\}", str(v))
        if m and m.group(1) in INPUTS:
            env[k] = INPUTS[m.group(1)]
        elif v == "${{ github.repository }}":
            env[k] = "t11-owner/t11-repo"
        else:
            return "env-unmodeled:%s" % k
    body = step["run"].split("\n")
    arm = [i for i, l in enumerate(body) if re.match(r"^\s*[^#\s].*scripts/lint-cve-safe-status\.py", l)]
    if len(arm) != 1:
        return "arm-in-add-step:%d" % len(arm)
    a = arm[0]
    ind = re.match(r"^(\s*)", body[a]).group(1)
    fi = next((i for i in range(a + 1, len(body)) if body[i].rstrip() == ind + "fi"), None)
    if fi is None:
        return "arm-has-no-fi"
    # The cut runs through the last line before the first branch push after the arm (today
    # the `git commit -m "$COMMIT_MESSAGE"` line), so the step's post-arm staging is executed.
    push = next((i for i in range(fi + 1, len(body)) if re.match(r"^\s*(git push |git_remote push )", body[i])), None)
    if push is None:
        return "no-push-after-arm"
    work = tempfile.mkdtemp(dir=runs)
    st, cwd = os.path.join(work, "state"), os.path.join(work, "repo")
    rtmp = os.path.join(work, "runner-temp")
    for d in (st, rtmp, os.path.join(cwd, "knowledge-base", "project")):
        os.makedirs(d)
    open(os.path.join(cwd, DIGEST), "w").write("# t11 fixture digest\n")
    for name, val in (("cve_rc", cve_rc), ("date", FIXTURE_DATE), ("branch", BRANCH),
                      ("commit_msg", INPUTS["commit-message"])):
        open(os.path.join(st, name), "w").write(val)
    region = os.path.join(st, "region.sh")
    # A command with no stub is refused like an unmodeled argv: a STUB-MISS naming it, rc 127.
    cnf = ["command_not_found_handle() { printf 'STUB-MISS: no stub for %s\\n' \"$1\" >> \"$T11_STATE/miss\"; return 127; }"]
    open(region, "w").write("\n".join(cnf + body[:push] + ['printf "reached\\n" > "$T11_STATE/sentinel"']) + "\n")
    # The modeled runner env (V1): what every hosted runner sets, so a construct that branches
    # on one of these runs here as it would in production.
    env.update({"T11_STATE": st, "HOME": os.path.join(work, "home"), "CI": "true",
                "GITHUB_ACTIONS": "true", "RUNNER_OS": "Linux", "RUNNER_TEMP": rtmp,
                "GITHUB_WORKSPACE": cwd, "GITHUB_EVENT_NAME": "schedule",
                "GITHUB_REPOSITORY": "t11-owner/t11-repo"})
    try:
        p = subprocess.run([bash, "--noprofile", "--norc", "-eo", "pipefail", region], cwd=cwd, env=env,
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    except subprocess.TimeoutExpired:
        return "region-timeout"
    def read(name):
        try:
            return open(os.path.join(st, name), encoding="utf-8", errors="replace").read()
        except FileNotFoundError:
            return ""
    miss = read("miss")
    if miss:
        return "stub-refused:" + miss.split("\n")[0].replace(" ", "_")[:120]
    if p.returncode != want_rc:
        return "rc:%d" % p.returncode
    if os.path.exists(os.path.join(st, "sentinel")) != (want_rc == 0):
        return "sentinel-reached" if want_rc else "sentinel-not-reached"
    calls = [r.split("\0")[:-1] for r in read("calls").split("\x1e") if r]
    adds = [i for i, r in enumerate(calls) if r[:2] == ["git", "add"]]
    if len(adds) != 1 or calls[adds[0]][3:] != STAGED:
        return "staged:%d" % len(adds)
    cves = [i for i, r in enumerate(calls) if r[:3] == ["python3", "-I", "scripts/lint-cve-safe-status.py"]]
    if len(cves) != 1:
        return "lint-calls:%d" % len(cves)
    if calls[cves[0]][3:] != ["--paths"] + calls[adds[0]][3:]:
        return "lint-argv"
    commits = [i for i, r in enumerate(calls) if r[:2] == ["git", "commit"]]
    if len(commits) != (0 if want_rc else 1):
        return "commits:%d" % len(commits)
    return None
for src in sys.argv[5:]:
    why = verdict(src)
    print("OK" if why is None else "RED:" + why)
T11PY
}
# (11a) the live action passes both layers.
assert_eq "OK" "$(t11_text "$ACTION_YML")" "(11a) text diagnostics: a unique syntactic arm after git add, enforcing, before push and POST"
assert_eq "OK" "$(t11_exec 1 "$ACTION_YML")" "(11a) executed region: python3 -I ran the lint once over the staged PATHS, its exit 1 stopped the step (rc 1, sentinel unreached)"
# (11c) positive control: with the lint stub passing, the same region runs to the sentinel.
assert_eq "OK" "$(t11_exec 0 "$ACTION_YML")" "(11c) positive control: lint stub exits 0, the region reaches the sentinel with rc 0, the same lint argv and one commit"
# (11b) the mutants, each on a temp copy; a mutant that fails to land (or is not valid YAML) is itself a failure.
t11_mutate() {  # t11_mutate KIND... : writes $T11_DIR/KIND.yml for each KIND that lands, prints why for each that does not
  python3 - "$ACTION_YML" "$T11_DIR" "$@" <<'T11PY'
import os, re, sys
import yaml
src, outdir, kinds = sys.argv[1], sys.argv[2], sys.argv[3:]
text = open(src, encoding="utf-8").read()
def mutant(kind):
    lines = text.split("\n")
    start = [i for i, l in enumerate(lines) if re.match(r'^\s*if ! python3 -I scripts/lint-cve-safe-status\.py ', l)]
    if len(start) != 1:
        return "arm anchor found %d times" % len(start)
    a = start[0]
    b = next(i for i in range(a + 1, len(lines)) if re.match(r"^\s*fi\s*$", lines[i]))
    arm = lines[a:b + 1]
    ind = re.match(r"^(\s*)", lines[a]).group(1)
    c = a
    while c > 0 and lines[c - 1].lstrip().startswith("#"):
        c -= 1
    adds = [i for i, l in enumerate(lines) if re.match(r'^\s*git add -- "\$\{PATHS\[@\]\}"\s*$', l)]
    if len(adds) != 1:
        return "git add anchor found %d times" % len(adds)
    add = adds[0]
    ex = next(i for i in range(a, b) if re.match(r"^\s*exit 1\s*$", lines[i]))
    def wrap(opener, closer):
        return lines[:a] + [ind + opener] + arm + [ind + closer] + lines[b + 1:]
    if kind == "comment-only":
        out = lines[:a] + lines[b + 1:]
    elif kind == "delete":
        out = lines[:c] + lines[b + 1:]
    elif kind == "reorder":
        rest = lines[:a] + lines[b + 1:]
        p = next(i for i, l in enumerate(rest) if re.match(r"^\s*(git push |git_remote push )", l))
        out = rest[:p + 1] + arm + rest[p + 1:]
    elif kind == "swallow-or-true":
        out = lines[:a] + [lines[a].replace('"${PATHS[@]}"; then', '"${PATHS[@]}" || true; then')] + lines[a + 1:]
    elif kind == "swallow-inert-body":
        out = lines[:a] + [re.sub(r"exit 1", "true", l) for l in arm] + lines[b + 1:]
    elif kind == "args-single":
        out = lines[:a] + [lines[a].replace('"${PATHS[@]}"', '"${PATHS[0]}"')] + lines[a + 1:]
    elif kind == "drop-isolate":
        out = lines[:a] + [lines[a].replace("python3 -I scripts/", "python3 scripts/")] + lines[a + 1:]
    elif kind == "args-no-flag":
        out = lines[:a] + [lines[a].replace(' --paths "${PATHS[@]}"', ' "${PATHS[@]}"')] + lines[a + 1:]
    elif kind == "before-add":
        rest = lines[:a] + lines[b + 1:]
        out = rest[:add] + arm + rest[add:]
    elif kind == "wrap-if-false":
        out = wrap("if false; then", "fi")
    elif kind == "uncalled-function":
        out = wrap("t11_never_called() {", "}")
    elif kind in ("and-brace", "function-keyword", "brace-comment", "false-and-brace"):
        out = wrap({"and-brace": "true && {", "function-keyword": "function t11_never_called {",
                    "brace-comment": "t11_never_called() { # never invoked",
                    "false-and-brace": "false && {"}[kind], "}")
    elif kind == "heredoc":
        out = wrap(": <<'T11EOF'", "T11EOF")
    elif kind == "subshell-or-true":
        out = wrap("(", ") || true")
    elif kind == "quoted-noop":
        out = wrap(": '", "'")
    elif kind == "true-or":
        out = lines[:a] + [lines[a].replace("if ! python3", "if ! true || ! python3")] + lines[a + 1:]
    elif kind == "true-or-continuation":
        out = lines[:ex] + [ind + "  true || \\"] + lines[ex:]
    elif kind == "paths-rebound":
        out = lines[:a] + [ind + 'PATHS=("knowledge-base/README.md")'] + lines[a:]
    elif kind == "shadow-before-arm":
        out = lines[:a] + [ind + "python3() { :; }"] + lines[a:]
    elif kind == "shadow-above-add":
        out = lines[:add] + [ind + "python3() { :; }"] + lines[add:]
    elif kind == "env-cond-shadow-ci":
        # V1: a shadow that applies only where CI is set (every runner), placed before the arm.
        out = lines[:a] + [ind + '[ -n "${CI:-}" ] && python3() { :; }'] + lines[a:]
    elif kind == "env-cond-shadow-gha":
        # V1: the same keyed on GITHUB_ACTIONS, as an if-block above `git add`.
        out = lines[:add] + [ind + 'if [ "${GITHUB_ACTIONS:-}" = true ]; then python3() { :; }; fi'] + lines[add:]
    elif kind == "re-add-after-arm":
        # V5: change a staged file after the lint passed it, then stage it again.
        out = (lines[:b + 1] + [ind + "printf 't11 unscanned\\n' >> \"${PATHS[0]}\"",
                                ind + 'git add -- "${PATHS[@]}"'] + lines[b + 1:])
    elif kind == "commit-am":
        # V5: a commit that stages tracked changes on its own.
        cm = [i for i, l in enumerate(lines) if l.strip() == 'git commit -m "$COMMIT_MESSAGE"']
        if len(cm) != 1:
            return "git commit anchor found %d times" % len(cm)
        out = list(lines)
        out[cm[0]] = lines[cm[0]].replace("git commit -m", "git commit -am")
    elif kind == "reset-between":
        out = (lines[:a] + [ind + 'git reset -q -- "${PATHS[@]}"'] + arm
               + [ind + 'git add -- "${PATHS[@]}"'] + lines[b + 1:])
    elif kind == "own-step-if-false":
        # Close the run block before the arm, give the arm its own never-run step, resume the rest.
        k = "    "
        out = (lines[:c] + [k + "- name: t11 split arm", k + "  if: ${{ false }}", k + "  shell: bash",
                            k + "  run: |"] + lines[c:b + 1]
               + [k + "- name: t11 split rest", k + "  shell: bash", k + "  run: |"] + lines[b + 1:])
    elif kind == "step-if":
        n = next(i for i, l in enumerate(lines) if l.startswith("    - name: Commit, open bot PR"))
        out = lines[:n + 1] + ["      if: ${{ github.event_name == 'never' }}"] + lines[n + 1:]
    elif kind == "step-shell-sh":
        out = [l.replace("      shell: bash", "      shell: sh", 1) if l == "      shell: bash" else l for l in lines]
    else:
        return "unknown mutant"
    result = "\n".join(out)
    if result == text:
        return "did not change the file"
    try:
        yaml.safe_load(result)
    except yaml.YAMLError as e:
        return "not valid YAML: " + str(e).split(chr(10))[0]
    open(os.path.join(outdir, kind + ".yml"), "w", encoding="utf-8").write(result)
    return None
for kind in kinds:
    try:
        why = mutant(kind)
    except (StopIteration, ValueError) as e:
        why = "anchor missing: %r" % e
    if why:
        print("t11: mutant %s did not land: %s" % (kind, why), file=sys.stderr)
T11PY
}
# Rows whose kill must come from the execution layer alone: the ten measured bypass shapes
# (test-design NF1 x1-x10, with the python3 shadow placed both before the arm and above
# `git add`), the two runner-env-conditional shadows (V1), the two post-arm staging shapes
# (V5), the dropped `-I` (X2), plus every other mutant that changes what the region does. Each
# landed mutant runs twice, with the lint stub exiting 1 and then 0; its execution verdict is
# the first RED of the two (exec1/exec0), so a change after the arm is graded by the run that
# reaches it. swallow-or-true (`if ! python3 … || true; then`) is not in the list: it parses as
# `(! python3 …) || true`, so the step exits 1 whatever the lint says (a stalled bot, never a
# fabricated green; exec0 reports it as rc:1).
# T11_CONTROLS are safe rewrites of the arm, not bypasses: true-or (`if ! true || ! python3 …`)
# and and-brace (`true && { <arm> }`) still run the lint and stop on its exit 1. Both execution
# runs must be OK, so the harness is shown not to false-red on safe syntax; the text layer's
# verdict on them is printed and not graded.
T11_CONTROLS=" true-or and-brace "
T11_EXEC_KILLS=" drop-isolate subshell-or-true false-and-brace function-keyword heredoc quoted-noop own-step-if-false true-or-continuation paths-rebound shadow-before-arm shadow-above-add reset-between comment-only delete reorder swallow-inert-body args-single args-no-flag before-add wrap-if-false uncalled-function brace-comment step-if step-shell-sh env-cond-shadow-ci env-cond-shadow-gha re-add-after-arm commit-am "
T11_KINDS=(comment-only reorder delete swallow-or-true swallow-inert-body args-single args-no-flag drop-isolate before-add
  wrap-if-false uncalled-function true-or and-brace function-keyword brace-comment heredoc
  subshell-or-true false-and-brace quoted-noop own-step-if-false true-or-continuation paths-rebound
  shadow-before-arm shadow-above-add reset-between step-if step-shell-sh
  env-cond-shadow-ci env-cond-shadow-gha re-add-after-arm commit-am)
t11_mutate "${T11_KINDS[@]}"
T11_FILES=()
for t11_kind in "${T11_KINDS[@]}"; do
  if [[ -s "$T11_DIR/$t11_kind.yml" ]]; then T11_FILES+=("$T11_DIR/$t11_kind.yml"); else T11_FILES+=(""); fi
done
# One interpreter for every landed mutant's execution verdict (the per-row cost is the region run).
T11_LANDED=(); for f in "${T11_FILES[@]}"; do [[ -n "$f" ]] && T11_LANDED+=("$f"); done
T11_EXEC_OUT=(); T11_EXEC0_OUT=()
if (( ${#T11_LANDED[@]} > 0 )); then
  mapfile -t T11_EXEC_OUT < <(t11_exec 1 "${T11_LANDED[@]}")
  mapfile -t T11_EXEC0_OUT < <(t11_exec 0 "${T11_LANDED[@]}")
fi
t11_j=0
for t11_i in "${!T11_KINDS[@]}"; do
  t11_kind="${T11_KINDS[$t11_i]}"
  if [[ -z "${T11_FILES[$t11_i]}" ]]; then
    echo "  FAIL: (11b) mutant $t11_kind did not land"
    FAIL=$((FAIL + 1)); continue
  fi
  t11_e1="${T11_EXEC_OUT[$t11_j]:-MISSING}"; t11_e0="${T11_EXEC0_OUT[$t11_j]:-MISSING}"; t11_j=$((t11_j + 1))
  # Only a RED:<why> line counts as a kill; OK, or a MISSING verdict, never does.
  if [[ "$t11_e1" == RED:* ]]; then t11_ev="exec1 $t11_e1"; elif [[ "$t11_e0" == RED:* ]]; then t11_ev="exec0 $t11_e0"
  else t11_ev="not-red(exec1 $t11_e1, exec0 $t11_e0)"; fi
  t11_tv=$(t11_text "${T11_FILES[$t11_i]}")
  if [[ "$T11_CONTROLS" == *" $t11_kind "* ]]; then
    if [[ "$t11_e1" == OK && "$t11_e0" == OK ]]; then
      echo "  PASS: (11d) control $t11_kind runs OK in both execution runs (text $t11_tv, not graded)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: (11d) control $t11_kind is not OK in both execution runs (exec1 $t11_e1, exec0 $t11_e0)"
      FAIL=$((FAIL + 1))
    fi
  elif [[ "$T11_EXEC_KILLS" == *" $t11_kind "* && "$t11_ev" == not-red* ]]; then
    echo "  FAIL: (11b) mutant $t11_kind survived the execution layer ($t11_ev; text $t11_tv)"
    FAIL=$((FAIL + 1))
  elif [[ "$t11_tv" == RED:* || "$t11_ev" != not-red* ]]; then
    echo "  PASS: (11b) mutant $t11_kind is reported ($t11_ev; text $t11_tv)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: (11b) mutant $t11_kind survived Test 11 ($t11_ev; text $t11_tv)"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# --- Test 12: the `guards-ruleset` member `cve-safe-status` is a full, enforcing scan (#12348) --
#
# The oracle lane skips the `test` sweep on KB-markdown-only diffs, so this ci.yml member
# is the gate that always runs (CTO ruling D1). Every check reads a real YAML parse (PyYAML,
# with a loader that refuses duplicate keys anywhere in the file, because PyYAML would
# otherwise keep the last one silently): exactly one step with this id in the whole file,
# inside the guards-ruleset job; its keys are EXACTLY id/if/name/run; its `if` is
# `${{ !cancelled() }}` and its `run` EQUALS `python3 -I scripts/lint-cve-safe-status.py`. It is
# the job's second step, and the first is exactly the SHA-pinned checkout (keys uses/with,
# `actions/checkout@<40-hex sha>`, `with` exactly fetch-depth 0 and persist-credentials false),
# so no step runs before it that could change its environment (CTO ruling X3). The job has no
# `container:` and no `services:`. Neither the job nor the workflow sets an `env:` key named
# LINT_CVE_SAFE_STATUS_*, GIT_*, PATH, BASH_ENV, ENV, PYTHON* or LD_*, or a `defaults.run` the
# step would inherit. The job text has no sparse-checkout, and its aggregate has exactly one
# member line reading this step's conclusion and outcome.
#
# Residuals (CTO ruling Q-end; S0 above applies here too):
#   R12-1 The member is pinned as the first step after the SHA-pinned checkout. The runner
#         image, `runs-on` and the checkout action's own code are trusted, not checked.
#   R12-2 The env refusal is the named key list above. Other names are not refused, and `-I`
#         makes the interpreter ignore PYTHON* variables, user site-packages and the script
#         directory, but not a modified interpreter or stdlib on the image.
echo "Test 12: ci.yml guards-ruleset runs lint-cve-safe-status as an enforcing full scan (#12348)"
T12_DIR="$TMP/t12"; mkdir -p "$T12_DIR"
t12_py() {  # t12_py MODE SRC [KIND DST]: MODE=verdict prints OK|RED:<why>; MODE=mutate writes DST
  python3 - "$@" <<'T12PY'
import re, sys
import yaml
mode, src = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
lines = text.split("\n")
RUN = "python3 -I scripts/lint-cve-safe-status.py"
IF = "${{ !cancelled() }}"
SEAM = re.compile(r"^(LINT_CVE_SAFE_STATUS_|GIT_|PYTHON|LD_)|^(PATH|BASH_ENV|ENV)$")
CHECKOUT_USES = re.compile(r"actions/checkout@[0-9a-f]{40}")
CHECKOUT_WITH = {"fetch-depth": 0, "persist-credentials": False}
FAST = getattr(yaml, "CSafeLoader", yaml.SafeLoader)  # libyaml parser when present; same constructors
class StrictLoader(FAST):
    pass
def strict_mapping(loader, node, deep=False):
    out = {}
    for kn, vn in node.value:
        k = loader.construct_object(kn, deep=deep)
        if k in out:
            raise ValueError("duplicate-key:%s@%d" % (k, kn.start_mark.line + 1))
        out[k] = loader.construct_object(vn, deep=deep)
    return out
StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, strict_mapping)
def job_bounds(ls):
    s = [i for i, l in enumerate(ls) if re.match(r"^  guards-ruleset:\s*$", l)]
    if len(s) != 1:
        return None
    e = next((i for i in range(s[0] + 1, len(ls)) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", ls[i])), len(ls))
    return s[0], e
def step_bounds(ls, a, e):
    ids = [i for i in range(a, e) if re.match(r"^\s*- id: cve-safe-status\s*$", ls[i])]
    if len(ids) != 1:
        return None
    i = ids[0]
    ind = len(ls[i]) - len(ls[i].lstrip())
    j = i + 1
    while j < e and not (ls[j].strip() and (len(ls[j]) - len(ls[j].lstrip())) <= ind):
        j += 1
    return i, j
def verdict():
    try:
        doc = yaml.load(text, Loader=StrictLoader)
    except ValueError as e:
        return str(e)
    jobs = doc.get("jobs") or {}
    if "guards-ruleset" not in jobs:
        return "no-guards-ruleset-job"
    hits = [(name, s) for name, j in jobs.items() for s in (j.get("steps") or [])
            if isinstance(s, dict) and s.get("id") == "cve-safe-status"]
    if len(hits) != 1:
        return "step-count:%d" % len(hits)
    name, step = hits[0]
    if name != "guards-ruleset":
        return "step-outside-job"
    if sorted(step) != ["id", "if", "name", "run"]:
        return "step-keys:" + ",".join(sorted(step))
    if step["if"] != IF:
        return "if-not-uncancelled"
    if step["run"] != RUN:
        return "run-argv"
    job = jobs["guards-ruleset"]
    for key in ("container", "services"):
        if key in job:
            return "job-" + key
    steps = job.get("steps") or []
    at = next(k for k, s in enumerate(steps) if isinstance(s, dict) and s.get("id") == "cve-safe-status")
    if at != 1:
        return "member-is-step-%d-not-2" % (at + 1)
    co = steps[0]
    if not (isinstance(co, dict) and sorted(co) == ["uses", "with"]
            and CHECKOUT_USES.fullmatch(str(co["uses"])) and co["with"] == CHECKOUT_WITH):
        return "step-before-member-not-the-pinned-checkout"
    for where, holder in (("workflow", doc), ("job", job)):
        seams = [k for k in (holder.get("env") or {}) if SEAM.match(str(k))]
        if seams:
            return "%s-env-seam:%s" % (where, ",".join(seams))
        if "run" in (holder.get("defaults") or {}):
            return "%s-defaults-run" % where
    jb = job_bounds(lines)
    if jb is None:
        return "no-guards-ruleset-job-text"
    a, e = jb
    jt = [l for l in lines[a:e] if not l.lstrip().startswith("#")]
    if any("sparse-checkout" in l for l in jt):
        return "sparse-checkout"
    member = "member cve-safe-status '*' 'cve-safe-status' '${{ steps.cve-safe-status.conclusion }}' '${{ steps.cve-safe-status.outcome }}' || failed=1"
    if sum(1 for l in jt if l.strip() == member) != 1:
        return "aggregate-member"
    return None
if mode == "verdict":
    why = verdict()
    print("OK" if why is None else "RED:" + why)
    sys.exit(0)
kind, dst = sys.argv[3], sys.argv[4]
a, e = job_bounds(lines)
i, j = step_bounds(lines, a, e)
step = lines[i:j]
run_i = next(k for k in range(i, j) if lines[k].strip().startswith("run:"))
if_i = next(k for k in range(i, j) if lines[k].strip().startswith("if:"))
ind = lines[if_i].split("if:")[0]
out = list(lines)
if kind == "delete-step":
    out = lines[:i] + lines[j:]
elif kind == "run-paths":
    out[run_i] = lines[run_i] + " --paths knowledge-base/README.md"
elif kind == "run-help":
    out[run_i] = lines[run_i] + " --help"
elif kind == "run-or-true":
    out[run_i] = lines[run_i] + " || true"
elif kind == "if-pr-only":
    out[if_i] = lines[if_i].replace(IF, "${{ github.event_name == 'pull_request' }}")
elif kind in ("continue-on-error", "shell-override", "working-directory", "timeout-minutes", "duplicate-if"):
    extra = {"continue-on-error": "continue-on-error: true", "shell-override": "shell: true {0}",
             "working-directory": "working-directory: knowledge-base/project",
             "timeout-minutes": "timeout-minutes: 0", "duplicate-if": "if: ${{ false }}"}[kind]
    out = lines[:j] + [ind + extra] + lines[j:]
elif kind == "decoy-if-env":
    out = (lines[:if_i] + [ind + "if: ${{ false }}"] + lines[if_i + 1:j]
           + [ind + "env:", ind + "  T12_DECOY: |", ind + "    " + "if: " + IF] + lines[j:])
elif kind in ("job-env-seam", "job-env-path", "job-env-pythonpath"):
    k = next(k for k in range(a, e) if lines[k] == "    env:")
    extra = {"job-env-seam": 'LINT_CVE_SAFE_STATUS_MIN_FILES: "0"', "job-env-path": "PATH: /tmp/t12-bin:/usr/bin:/bin",
             "job-env-pythonpath": "PYTHONPATH: scripts/t12-fixture"}[kind]
    out = lines[:k + 1] + ["      " + extra] + lines[k + 1:]
elif kind == "job-container":
    k = next(k for k in range(a, e) if lines[k].startswith("    runs-on:"))
    out = lines[:k + 1] + ["    container: t12-fixture-image"] + lines[k + 1:]
elif kind == "drop-isolate":
    out[run_i] = lines[run_i].replace("python3 -I scripts/", "python3 scripts/")
elif kind == "workflow-env-seam":
    k = next(k for k, l in enumerate(lines) if l == "jobs:")
    out = lines[:k] + ["env:", "  GIT_DIR: /dev/null"] + lines[k:]
elif kind == "job-defaults-shell":
    k = next(k for k in range(a, e) if lines[k].startswith("    runs-on:"))
    out = lines[:k + 1] + ["    defaults:", "      run:", "        shell: true {0}"] + lines[k + 1:]
elif kind == "prior-step-inserted":
    # A step between the checkout and the member, here one that puts a directory first on PATH.
    dash = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
    out = lines[:i] + [dash + "- name: t12 prior step", ind + "run: |",
                       ind + "  mkdir -p \"$RUNNER_TEMP/t12-bin\"",
                       ind + "  echo \"$RUNNER_TEMP/t12-bin\" >> \"$GITHUB_PATH\""] + lines[i:]
elif kind == "delete-member":
    out = [l for l in lines if not l.strip().startswith("member cve-safe-status ")]
elif kind == "sparse-checkout":
    out = lines[:i] + [lines[i].replace("- id: cve-safe-status", "- uses: actions/checkout@v4"), ind + "with: { sparse-checkout: scripts }"] + lines[i:]
elif kind == "move-out-of-job":
    # into the LAST job of the file (guards-ruleset is not last: guards-advisory follows it)
    rest = lines[:i] + lines[j:]
    while rest and not rest[-1].strip():
        rest.pop()
    out = rest + step + [""]
else:
    sys.exit("t12: unknown mutant " + kind)
res = "\n".join(out)
if res == text:
    sys.exit("t12: mutant %s did not change the file" % kind)
try:
    yaml.load(res, Loader=FAST)  # plain PyYAML: every mutant, the duplicate-key one included, must parse
except yaml.YAMLError as e:
    sys.exit("t12: mutant %s is not valid YAML: %s" % (kind, str(e).split(chr(10))[0]))
open(dst, "w", encoding="utf-8").write(res)
T12PY
}
assert_eq "OK" "$(t12_py verdict "$CI_YML")" "(12a) the live ci.yml guards-ruleset job runs lint-cve-safe-status as an uncancelled, enforcing, no-argument full scan with an aggregate member line"
for t12_kind in delete-step run-paths run-help run-or-true if-pr-only continue-on-error shell-override delete-member sparse-checkout move-out-of-job \
    decoy-if-env working-directory timeout-minutes duplicate-if job-env-seam workflow-env-seam job-defaults-shell \
    prior-step-inserted job-env-path job-env-pythonpath job-container drop-isolate; do
  if t12_py mutate "$CI_YML" "$t12_kind" "$T12_DIR/$t12_kind.yml"; then
    t12_v=$(t12_py verdict "$T12_DIR/$t12_kind.yml")
    if [[ "$t12_v" == RED:* ]]; then
      echo "  PASS: (12b) mutant $t12_kind is reported ($t12_v)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: (12b) mutant $t12_kind survived Test 12 (verdict $t12_v)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: (12b) mutant $t12_kind did not land"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

print_results 152
