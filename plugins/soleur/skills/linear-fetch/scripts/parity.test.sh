#!/usr/bin/env bash
# Cross-artifact parity test for the load-bearing redaction rail.
#
# The plan's User-Brand Impact section names a 2-layer defense (in-skill
# redaction + CI grep) "with no shared bypass." That guarantee depends on
# both files covering the SAME set of CDN hostnames. This test asserts
# the property: for each canonical hostname, both the redaction script
# and the CI workflow must contain a reference to it.
#
# Without this test, the only enforcement is the "Sharp Edges" SKILL.md
# note that says "update both sites." Reviewer agents flagged the bare-
# convention approach as schema-drift-prone (learning
# 2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md).
#
# Update CANONICAL_HOSTS below when LINEAR_CDN_PATTERNS gains a new
# hostname — the test will then enforce that the workflow grew the
# matching pattern in the same PR.
#
# Run via:  bash plugins/soleur/skills/linear-fetch/scripts/parity.test.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
REDACTOR="$SCRIPT_DIR/redact-linear-urls.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/pr-quality-guards.yml"

# Canonical hostname set the redactor and CI grep both must cover.
# When a new hostname (e.g., cdn.linear.app) is added to LINEAR_CDN_PATTERNS,
# add it here AND ensure the workflow's pii-grep regex covers it.
CANONICAL_HOSTS=("uploads.linear.app")

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Build a case-insensitive bracket pattern for a lowercase hostname.
# Example: "uploads.linear.app" -> "[Uu][Pp][Ll][Oo][Aa][Dd][Ss]\.[Ll][Ii][Nn][Ee][Aa][Rr]\.[Aa][Pp][Pp]"
case_bracket_pattern() {
  local host="$1"
  local out=""
  local i c upper
  for ((i = 0; i < ${#host}; i++)); do
    c="${host:$i:1}"
    if [[ "$c" == "." ]]; then
      # The redactor file stores hostnames inside a bash $'...' ANSI-C
      # string, so a literal `.` in the regex is escaped as `\\.` (two
      # backslashes followed by a dot — bash's ANSI-C parser collapses
      # this to one backslash + dot at runtime). We grep the on-disk
      # representation, so we need the double-backslash form here.
      out+='\\.'
    else
      upper="${c^^}"
      out+="[${upper}${c}]"
    fi
  done
  printf '%s' "$out"
}

# Files exist sanity check.
[[ -r "$REDACTOR" ]] || { echo "ERROR: redactor not readable at $REDACTOR" >&2; exit 2; }
[[ -r "$WORKFLOW" ]] || { echo "ERROR: workflow not readable at $WORKFLOW" >&2; exit 2; }

for host in "${CANONICAL_HOSTS[@]}"; do
  echo "Host: $host"

  # Redactor encodes hostnames as [Cc][Hh]... bracketed case-insensitive
  # sequences. Build the expected pattern and grep for it.
  case_pat=$(case_bracket_pattern "$host")
  if grep -qF "$case_pat" "$REDACTOR"; then
    pass "redactor LINEAR_CDN_PATTERNS covers $host (matched: $case_pat)"
  else
    fail "redactor missing $host — expected to find literal '$case_pat'"
  fi

  # Workflow uses `grep -iE` so the literal lowercase form is what appears
  # in the regex. (Other prose mentions in comments don't affect the gate's
  # behavior but do satisfy this presence-check, which is fine — the test's
  # job is to assert co-presence, not exhaustive line-by-line equivalence.)
  if grep -qF "$host" "$WORKFLOW"; then
    pass "workflow references $host"
  else
    fail "workflow does NOT reference $host — pii-grep would not catch leaks of this host"
  fi
done

# Test 2: no orphan host in the workflow (a hostname appearing in the
# workflow's actual regex but NOT in CANONICAL_HOSTS would indicate the
# parity test itself is stale). Heuristic: extract `[a-z0-9-]+\.linear\.app`
# literals from the workflow's gate steps and assert each is in
# CANONICAL_HOSTS.
echo
echo "Workflow orphan-host check"
workflow_hosts=$(grep -oE '[a-z0-9-]+\\\.linear\\\.app' "$WORKFLOW" | sed -E 's/\\\././g' | sort -u || true)
canonical_set=$(printf '%s\n' "${CANONICAL_HOSTS[@]}" | sort -u)
orphan=""
while IFS= read -r wh; do
  [[ -z "$wh" ]] && continue
  if ! printf '%s\n' "$canonical_set" | grep -qFx "$wh"; then
    orphan+="$wh "
  fi
done <<< "$workflow_hosts"
if [[ -z "${orphan// /}" ]]; then
  pass "no orphan hosts in workflow"
else
  fail "workflow references hosts not in CANONICAL_HOSTS: $orphan"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
