#!/usr/bin/env bash
# Unit tests for ship-cmo-content-gate.sh.

set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-cmo-content-gate.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Mock gh
BINDIR="$TMPDIR/bin"
mkdir -p "$BINDIR"
cat > "$BINDIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"pr view 123 --json title --jq .title"* ]]; then
  echo "${MOCK_PR_TITLE:-feat: add shiny thing}"
elif [[ "$*" == *"pr view --json number --jq .number"* ]]; then
  echo "123"
else
  echo ""
fi
EOF
chmod +x "$BINDIR/gh"

# Create a dummy git repo in TMPDIR
WORKDIR="$TMPDIR/repo"
mkdir -p "$WORKDIR"
git -C "$WORKDIR" init -q -b main
git -C "$WORKDIR" config user.email "test@example.com"
git -C "$WORKDIR" config user.name "Test User"
touch "$WORKDIR/file.txt"
git -C "$WORKDIR" add file.txt
git -C "$WORKDIR" commit -q -m "initial commit"
git -C "$WORKDIR" checkout -q -b feat-branch

run_hook() {
  local cmd="$1" pr_title="$2" skip_env="${3:-0}" extra_commit_msg="${4:-}"
  if [[ -n "$extra_commit_msg" ]]; then
    git -C "$WORKDIR" commit --allow-empty -q -m "$extra_commit_msg"
  fi
  PATH="$BINDIR:$PATH" MOCK_PR_TITLE="$pr_title" SOLEUR_SKIP_CMO_CONTENT_GATE="$skip_env" \
    bash "$HOOK" <<EOF
{"tool_name": "Bash", "tool_input": {"command": "$cmd"}, "cwd": "$WORKDIR"}
EOF
}

echo "=== Test ship-cmo-content-gate.sh ==="

# 1. Irrelevant command -> exit 0 / empty
res=$(run_hook "git status" "feat: something")
assert_eq "non-merge command passes silently" "" "$res"

# 2. Fix PR -> passes silently
res=$(run_hook "gh pr merge 123 --squash" "fix: a bug")
assert_eq "fix PR passes silently" "" "$res"

# 3. Feat PR without CMO disposition -> deny
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability")
decision=$(echo "$res" | jq -r .decision 2>/dev/null || echo "")
assert_eq "feat PR without CMO disposition is denied" "deny" "$decision"

# 4. Feat PR with SOLEUR_SKIP_CMO_CONTENT_GATE=1 -> pass
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability" "1")
assert_eq "feat PR with skip override passes" "" "$res"

# 5. Feat PR with trailer -> pass
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability" "0" "$(printf 'cmo: review\n\nReviewed-By-CMO: skip (internal only)')")
assert_eq "feat PR with Reviewed-By-CMO trailer passes" "" "$res"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
