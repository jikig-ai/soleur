#!/usr/bin/env bash
# Parity pin for the rule-line-shape regex `^- .*\[id: `, replicated across the
# frontmatter over-strip guards in THREE languages. #6794 added the TS copy;
# this asserts every copy still matches the linter's authoritative definition so
# a drift in any one fails the build — the #6461 mission: mechanical parity, not
# hand-maintained "keep the regexes identical" prose. (The strip.{sh,py,ts}
# triplet is pinned separately by frontmatter-strip.test.sh.)
#
# Fixed-string (`grep -F`), CODE-anchored assertions: each canonical form embeds
# enough of its language construct that a nearby COMMENT mentioning the pattern
# cannot satisfy it (the comment-false-match trap, cq-assert-anchor-not-bare-token).
# If a copy's pattern drifts, its `grep -F` returns 0 and the test fails loudly.
# Auto-discovered by scripts/test-all.sh's `scripts/lib/*.test.sh` glob.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="$ROOT/scripts/lint-agents-rule-budget.py"
TS="$ROOT/apps/web-platform/server/inngest/functions/cron-compound-promote.ts"
SH="$ROOT/.claude/hooks/session-rules-loader.sh"
IDS="$ROOT/scripts/lint-rule-ids.py"
BODIES="$ROOT/scripts/lint-rule-bodies.py"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# (file, canonical code-anchored fixed string, min occurrences)
check() {
  local label="$1" file="$2" needle="$3" min="$4"
  [[ -f "$file" ]] || { fail "$label: file missing ($file) — update this parity test"; return; }
  local n; n=$(grep -Fc -- "$needle" "$file")
  if [[ "$n" -ge "$min" ]]; then
    pass "$label: canonical rule-line regex present (${n}x)"
  else
    fail "$label: expected >=${min} occurrence(s) of the canonical rule-line regex, found ${n} — regex drifted?"
  fi
}

# Authority (the linter's compiled pattern).
check "linter (py)" "$PY" '_RULE_LINE_RE = re.compile(r"^- .*\[id: ")' 1
# Runtime promoter over-strip guard (#6794 — the copy this suite exists to pin).
check "cron (ts)"   "$TS" 'RULE_LINE_RE = /^- .*\[id: /' 1
# Session-rules loader over-strip + rule-count grep sites (>=3 occurrences).
check "loader (sh)" "$SH" "E '^- .*\[id: '" 3


# --- POINTER_LINE_RE parity (added by ADR-150 review) ------------------------
# lint-rule-ids.py CLASSIFIES a line as a pointer; lint-rule-bodies.py EXCLUDES
# the same shape from the body map. They must agree, or a line is a body to one
# gate and a pointer to the other.
#
# This became invisible-on-drift at ADR-150. The old shape ended in a mandatory
# ` → (core|docs-only|rest)` arrow, so a one-sided edit almost always broke a
# visible fixture. With the arrow gone the two definitions are a bare shared
# string, and a one-sided tightening (e.g. dropping the optional-tags group)
# would silently reclassify real rules with no fixture to notice.
POINTER_RE_CANON='POINTER_LINE_RE = re.compile(r"^- \[id: [a-z0-9-]+\](?:\s+\[[^\]]+\])*\s*$")'
check "pointer shape (lint-rule-ids.py)"    "$IDS"    "$POINTER_RE_CANON" 1
check "pointer shape (lint-rule-bodies.py)" "$BODIES" "$POINTER_RE_CANON" 1

echo
echo "Total: $((PASS+FAIL))  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
