#!/usr/bin/env bash
# Local fixture tests for the reusable-release.yml LATEST_TAG filter (#4082).
#
# Two checks:
#   1. YAML shape gate — asserts the workflow contains the canonical
#      `grep -m1 -E "^${TAG_PREFIX}[0-9]+\.[0-9]+\.[0-9]+$" || true` post-filter.
#      RED before fix (workflow still uses `head -1`); GREEN after.
#   2. Pipeline behavior — runs the canonical pipeline inline against a
#      synthetic tag corpus and asserts the correct winner per prefix,
#      including the empty-corpus case under `-eo pipefail`.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/../../.." && pwd)
WORKFLOW="$SCRIPT_DIR/.github/workflows/reusable-release.yml"
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Check 1: YAML contains the canonical anchored-regex post-filter (AC4).
# ---------------------------------------------------------------------------
if grep -qE 'grep -m1 -E "\^\$\{TAG_PREFIX\}\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+\$"' "$WORKFLOW"; then
  echo "PASS [yaml-shape]: reusable-release.yml contains canonical anchored-regex filter"
  PASS=$((PASS + 1))
else
  echo "FAIL [yaml-shape]: reusable-release.yml does not contain canonical 'grep -m1 -E \"^\${TAG_PREFIX}[0-9]+\\.[0-9]+\\.[0-9]+\$\"' filter"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Check 2: pipeline-behavior cases. Synthesized corpus only (no real tags).
# `sort -V -r` substitutes `git tag --sort=-version:refname` for the test;
# git's `version:refname` and GNU `sort -V` agree on plain `vX.Y.Z` shapes.
# ---------------------------------------------------------------------------
CORPUS=$'vinngest-v1.0.0\nv3.101.5\nv3.99.0\nv2.0.0\nweb-v0.94.7\nweb-v0.1.0\ntelegram-v0.1.28\ntelegram-v0.0.1'

run_pipeline() {
  # Args: <tag_prefix> <corpus>
  # Returns: stdout of the canonical filter pipeline, exit code preserved.
  local prefix="$1" corpus="$2"
  printf '%s\n' "$corpus" \
    | grep -E "^${prefix}" \
    | sort -V -r \
    | grep -m1 -E "^${prefix}[0-9]+\.[0-9]+\.[0-9]+$" \
    || true
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
EMPTY_RESULT=$(run_pipeline 'v' "$EMPTY_CORPUS")
assert_eq "ac7-empty-fallback" "" "$EMPTY_RESULT"

# AC7 (continued) — verify the pipeline truly survives `set -eo pipefail` on
# no-match. Run it in a subshell with the strict shell flags GitHub Actions
# uses by default; if `|| true` were missing, the subshell would exit 1.
if bash --noprofile --norc -eo pipefail -c '
    set -eo pipefail
    LATEST=$(printf "vinngest-v1.0.0\n" | sort -V -r | grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$" || true)
    [ -z "$LATEST" ]
'; then
  echo "PASS [ac7-pipefail-safe]: empty match does not abort under -eo pipefail"
  PASS=$((PASS + 1))
else
  echo "FAIL [ac7-pipefail-safe]: pipeline aborted under -eo pipefail (missing || true?)"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
