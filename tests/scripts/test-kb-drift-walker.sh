#!/usr/bin/env bash
# Tests for scripts/kb-drift-walker.sh — PR-H (#3244) AC4.
# Asserts EXACTLY 3 broken-link findings + EXACTLY 2 broken-anchor findings
# against a synthesized fixture tree.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$REPO_ROOT/scripts/kb-drift-walker.sh"
pass=0; fail=0

# --- fixture synthesis -----------------------------------------------------
# Per cq-test-fixtures-synthesized-only: build the fixture tree in a temp
# dir with explicit, named broken/healthy controls. No copies from $REPO_ROOT
# (would couple the test to real KB content).

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/knowledge-base/project/learnings"
mkdir -p "$FIXTURE/knowledge-base/legal"
mkdir -p "$FIXTURE/knowledge-base/operations/runbooks"
mkdir -p "$FIXTURE/apps/web-platform/lib"

# --- healthy controls (5) --------------------------------------------------
# Real existing target files referenced from real markdown source files.
echo "stub content" > "$FIXTURE/knowledge-base/legal/exists-1.md"
echo "stub content" > "$FIXTURE/knowledge-base/legal/exists-2.md"
echo "stub content" > "$FIXTURE/knowledge-base/operations/runbooks/exists-3.md"
echo "code body" > "$FIXTURE/apps/web-platform/lib/exists-4.ts"
echo "code body" > "$FIXTURE/apps/web-platform/lib/exists-5.ts"

cat > "$FIXTURE/knowledge-base/legal/healthy.md" <<'EOF'
See [exists-1](exists-1.md) and [exists-2](exists-2.md) and
[runbook](../operations/runbooks/exists-3.md). Code anchor:
`apps/web-platform/lib/exists-4.ts:1` and apps/web-platform/lib/exists-5.ts:1.
EOF

# --- broken links (3) ------------------------------------------------------
cat > "$FIXTURE/knowledge-base/legal/three-broken-links.md" <<'EOF'
[broken1](does-not-exist-1.md)
[broken2](does-not-exist-2.md)
[broken3](../operations/runbooks/missing-runbook.md)
EOF

# --- broken anchors (2) ----------------------------------------------------
cat > "$FIXTURE/AGENTS.core.md" <<'EOF'
- [id: hr-fake-rule-1] -> see scripts/ghost-1.sh:42 for details
EOF
cat > "$FIXTURE/knowledge-base/project/learnings/has-broken-anchor.md" <<'EOF'
- See apps/web-platform/lib/missing.ts:100 — drift target
EOF

# AGENTS.md index referring to the existing core file.
cat > "$FIXTURE/AGENTS.md" <<'EOF'
# Index — see AGENTS.core.md for bodies
EOF

# --- run + assert ---------------------------------------------------------
run_walker() {
  KB_DRIFT_FIXTURE_ROOT="$FIXTURE" bash "$SUT" 2>/dev/null
}

OUT="$(run_walker)"

# Extract counts via grep (avoid `jq` dep, mirror walker's no-jq stance).
got_broken_link=$(printf '%s' "$OUT" | grep -oE '"broken_link":[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "MISSING")
got_broken_anchor=$(printf '%s' "$OUT" | grep -oE '"broken_anchor":[0-9]+' | head -1 | grep -oE '[0-9]+' || echo "MISSING")

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label (got $got)"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label: want=$want got=$got" >&2
    echo "       --- walker stdout ---" >&2
    echo "$OUT" >&2
  fi
}

assert_eq "exactly 3 broken-link findings (AC4)" "3" "$got_broken_link"
assert_eq "exactly 2 broken-anchor findings (AC4)" "2" "$got_broken_anchor"

# JSON shape check: every finding has the 4 required fields.
fields_missing=$(printf '%s' "$OUT" | grep -oE '"kind":"[^"]+","source_path":"[^"]+","target":"[^"]+","source_ref":"(link|anchor)-[0-9a-f]{16}"' | wc -l | tr -d '[:space:]')
assert_eq "5 findings each carry kind/source_path/target/source_ref shape" "5" "$fields_missing"

# Negative: healthy controls do NOT appear in findings.
if printf '%s' "$OUT" | grep -q "exists-1.md\|exists-2.md\|exists-4.ts:1"; then
  fail=$((fail + 1))
  echo "[FAIL] healthy fixtures appeared in findings (should not)" >&2
else
  pass=$((pass + 1))
  echo "[ok] healthy fixtures excluded"
fi

# --- summary --------------------------------------------------------------
echo
echo "kb-drift-walker test summary: $pass pass / $fail fail"
[[ $fail -eq 0 ]]
