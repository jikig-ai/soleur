#!/usr/bin/env bash
# Local fixture tests for the reusable-release.yml LATEST_TAG filter (#4082).
#
# Three groups:
#   1. YAML shape gates — structural assertions on `.github/workflows/reusable-release.yml`.
#      RED before fix (workflow still uses `head -1`); GREEN after.
#   2. Pipeline behavior — runs the canonical pipeline inline against a
#      synthetic tag corpus and asserts the correct winner per prefix,
#      including the empty-corpus case under `-eo pipefail`.
#   3. Regex-metachar prefix safety — verifies the workflow's
#      `TAG_PREFIX_RE` escape closes the over-match hole for future prefixes
#      containing regex metacharacters.

set -uo pipefail
# Pin locale so `sort -V` collation is deterministic across runners.
export LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "$0")/../../.." && pwd)
WORKFLOW="$SCRIPT_DIR/.github/workflows/reusable-release.yml"
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }

PASS=0
FAIL=0

check_yaml_token() {
  # Args: <name> <fixed-string-pattern>
  # Uses grep -F so YAML continuation backslashes and shell metacharacters
  # in the pattern are matched literally, not as regex. Structural tokens
  # are checked independently so a cosmetic line-break or indentation
  # change does not break the gate.
  local name="$1" needle="$2"
  if grep -F -q -- "$needle" "$WORKFLOW"; then
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$name]: workflow does not contain literal token: $needle"
    echo "  Hint: \`grep -n 'LATEST_TAG=' $WORKFLOW\` to inspect the current shape."
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Group 1: YAML structural gates (AC4).
# Each token asserts one load-bearing piece of the fix independently.
# ---------------------------------------------------------------------------
check_yaml_token 'yaml-shape:prefix-escape-step' 'TAG_PREFIX_RE=$(printf'
check_yaml_token 'yaml-shape:anchored-regex'     '"^${TAG_PREFIX_RE}[0-9]+\.[0-9]+\.[0-9]+$"'
check_yaml_token 'yaml-shape:grep-m1'            'grep -m1 -E'
check_yaml_token 'yaml-shape:pipefail-guard'     '[ $? -eq 1 ]'

# ---------------------------------------------------------------------------
# Group 2: pipeline-behavior cases. Synthesized corpus only (no real tags).
# `sort -V -r` substitutes for `git tag --sort=-version:refname`; the two
# agree on plain `vX.Y.Z` shapes, which is all the anchored regex admits.
# (Pre-release / suffix shapes are rejected upstream by the regex, so any
# divergence between `sort -V` and `version:refname` on those shapes does
# not affect the gate.)
# ---------------------------------------------------------------------------
CORPUS=$'vinngest-v1.0.0\nv3.101.5\nv3.99.0\nv2.0.0\nweb-v0.94.7\nweb-v0.1.0\ntelegram-v0.1.28\ntelegram-v0.0.1'

escape_prefix_re() {
  # Mirror of the workflow's `TAG_PREFIX_RE` sed expression. Test runs the
  # same escape so behavior parity is checked rather than reimplemented.
  printf '%s' "$1" | sed 's/[][\.^$*+?(){}|/]/\\&/g'
}

run_pipeline() {
  # Args: <tag_prefix> <corpus>
  # Stdout: winner of the canonical filter pipeline (or empty on no-match).
  local prefix="$1" corpus="$2" prefix_re
  prefix_re=$(escape_prefix_re "$prefix")
  printf '%s\n' "$corpus" \
    | grep -E "^${prefix}" \
    | sort -V -r \
    | { grep -m1 -E "^${prefix_re}[0-9]+\.[0-9]+\.[0-9]+$" || [ $? -eq 1 ]; }
}

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS [$name]: got '$actual'"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$name]: expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# AC1 — plugin track (bare `v` prefix) excludes vinngest-v1.0.0
assert_eq "ac1-plugin"   "v3.101.5"        "$(run_pipeline 'v' "$CORPUS")"

# AC2 — web-platform track unaffected
assert_eq "ac2-web"      "web-v0.94.7"     "$(run_pipeline 'web-v' "$CORPUS")"

# AC3 — telegram-bridge track unaffected
assert_eq "ac3-telegram" "telegram-v0.1.28" "$(run_pipeline 'telegram-v' "$CORPUS")"

# AC7 — empty corpus / no-match must NOT abort step under -eo pipefail
EMPTY_CORPUS=$'someother-tag\nnot-a-version'
assert_eq "ac7-empty-fallback" "" "$(run_pipeline 'v' "$EMPTY_CORPUS")"

# AC7 (continued) — verify the pipeline truly survives `set -eo pipefail` on
# no-match. Run it in a subshell with the strict shell flags GitHub Actions
# uses by default; if the pipefail guard were missing, the subshell would
# exit non-zero.
if bash --noprofile --norc -eo pipefail -c '
    set -eo pipefail
    LATEST=$(printf "vinngest-v1.0.0\n" | sort -V -r \
      | { grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$" || [ $? -eq 1 ]; })
    [ -z "$LATEST" ]
'; then
  echo "PASS [ac7-pipefail-safe]: empty match does not abort under -eo pipefail"
  PASS=$((PASS + 1))
else
  echo "FAIL [ac7-pipefail-safe]: pipeline aborted under -eo pipefail (missing pipefail guard?)"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Group 3: regex-metachar prefix safety.
# Proves the `TAG_PREFIX_RE` escape rejects an attacker-shaped tag that an
# UNESCAPED prefix would accept. Locks in the security-defense-in-depth
# guard for any future prefix containing `.`, `+`, `*`, etc.
# ---------------------------------------------------------------------------
# A prefix `a.b-` is interpreted as `a<any>b-` if unescaped: a tag
# `aXb-1.0.0` would match. With the escape, only literal `a.b-1.0.0`
# (and friends) match.
METACHAR_CORPUS=$'aXb-1.0.0\na.b-1.0.0\na.b-0.9.0'
assert_eq "ac-metachar-prefix-escape-rejects" "a.b-1.0.0" "$(run_pipeline 'a.b-' "$METACHAR_CORPUS")"

# Sanity check the bug-without-escape branch: when the attacker tag is the
# sole candidate, an UNESCAPED regex `^a.b-[0-9]+\.[0-9]+\.[0-9]+$` matches
# `aXb-1.0.0` because the unescaped `.` is a regex wildcard. With escaping,
# the same regex rejects it. This locks in the security property: the
# escape is what stops a tag like `aXb-1.0.0` from being accepted as a
# valid `a.b-` release.
UNESCAPED_RESULT=$(printf 'aXb-1.0.0\n' | sort -V -r \
  | { grep -m1 -E "^a.b-[0-9]+\.[0-9]+\.[0-9]+$" || [ $? -eq 1 ]; })
if [[ "$UNESCAPED_RESULT" == "aXb-1.0.0" ]]; then
  echo "PASS [ac-metachar-unescaped-would-overmatch]: unescaped regex accepts attacker tag (escape is load-bearing)"
  PASS=$((PASS + 1))
else
  echo "FAIL [ac-metachar-unescaped-would-overmatch]: expected 'aXb-1.0.0', got '$UNESCAPED_RESULT'"
  FAIL=$((FAIL + 1))
fi

# Symmetric check via run_pipeline (which applies the escape): the same
# attacker-only corpus must NOT yield a winner.
ESCAPED_RESULT=$(run_pipeline 'a.b-' $'aXb-1.0.0')
assert_eq "ac-metachar-escaped-rejects-attacker" "" "$ESCAPED_RESULT"

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]]
