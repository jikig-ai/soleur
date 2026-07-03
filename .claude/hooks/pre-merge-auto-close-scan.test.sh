#!/usr/bin/env bash
# Fixture tests for pre-merge-auto-close-scan.sh. Each test builds a tmp git repo
# (with an origin/main ref + feature commits), composes a PreToolUse(Bash) input,
# pipes it to the hook, and asserts the permissionDecision.
#
# Isolation pattern mirrors follow-through-directive-gate.test.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-auto-close-scan.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCANNER="$REPO_ROOT/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"

PASS=0; FAIL=0; TOTAL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }
[[ -f "$SCANNER" ]] || { echo "SKIP: auto-close-scan.sh not found"; exit 0; }

# Build a tmp WORK_DIR: a git repo on a feature branch with an origin/main ref,
# the scanner copied in, and a gh stub on PATH returning $PR_BODY. Args:
#   $1 = commit body (last feature commit), $2 = PR body (for the gh stub)
make_work_dir() {
  local body="$1" pr_body="$2" tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q -b feat-x
  git -C "$tmp" config user.email t@t; git -C "$tmp" config user.name t
  git -C "$tmp" commit -q --allow-empty -m "base"
  git -C "$tmp" update-ref refs/remotes/origin/main HEAD            # origin/main = base
  git -C "$tmp" remote add origin "git@github.com:acme/repo.git"
  git -C "$tmp" commit -q --allow-empty -m "$body"                  # feature commit
  mkdir -p "$tmp/plugins/soleur/skills/ship/scripts"
  cp "$SCANNER" "$tmp/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
  # gh stub: `gh pr view … --json body --jq .body` prints $pr_body.
  mkdir -p "$tmp/.binstub"
  cat > "$tmp/.binstub/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$pr_body"
EOF
  chmod +x "$tmp/.binstub/gh"
  echo "$tmp"
}

make_input() { jq -n --arg cmd "$1" --arg cwd "$2" \
  '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}'; }

# run_case <name> <expect: deny|allow> <cmd> <commit-body> <pr-body> [ack]
run_case() {
  local name="$1" expect="$2" cmd="$3" body="$4" pr="$5" ack="${6:-}"
  TOTAL=$((TOTAL+1))
  local wd out decision
  wd="$(make_work_dir "$body" "$pr")"
  out="$(make_input "$cmd" "$wd" | PATH="$wd/.binstub:$PATH" ${ack:+SOLEUR_ACK_AUTOCLOSE=1} bash "$HOOK" 2>/dev/null || true)"
  decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  [[ -n "$decision" ]] || decision="allow"   # empty hook output = allow (jq on empty input yields nothing)
  rm -rf "$wd"
  if [[ "$decision" == "$expect" ]]; then
    PASS=$((PASS+1)); echo "PASS: $name ($decision)"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $name — expected $expect, got $decision"
  fi
}

# --- prose-embedded close in the COMMIT body → DENY (the #5887 vector) ---
run_case "commit prose-embedded closes → deny" deny \
  "gh pr merge 1 --squash --auto" $'fix: thing\n\nthe follow-through sweeper closes #5887 post-merge.' ""

# --- prose-embedded close in the PR BODY → DENY (the #5955 vector, via gh stub) ---
run_case "PR-body prose-embedded close → deny" deny \
  "gh pr merge 1 --squash" "fix: thing" "I'll close #5955 after the pipeline confirms green."

# --- standalone Closes #N (intentional, own line) → ALLOW ---
run_case "standalone Closes line → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nCloses #5887' ""

# --- bullet '- Fixes #N' (intentional) → ALLOW ---
run_case "bullet Fixes line → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\n- Fixes #5887' ""

# --- Ref #N (no close keyword) → ALLOW ---
run_case "Ref only → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nRef #5887, #5877' ""

# --- non-merge command → ALLOW (early exit) ---
run_case "non-merge command → allow" allow \
  "git status --short" $'fix: thing\n\nsweeper closes #5887' ""

# --- ack env set → ALLOW despite embedded close ---
run_case "ack env overrides → allow" allow \
  "gh pr merge 1 --squash" $'fix: thing\n\nsweeper closes #5887' "" ack

# --- gh pr merge documented inside a commit -m string is NOT a merge → ALLOW ---
# (embedded close IS in the body: if strip_command_bodies fails and the quoted
#  "gh pr merge" is mis-detected as a merge, the body's embedded close would DENY —
#  so allow here proves the strip works.)
run_case "gh pr merge in quoted string → allow" allow \
  "git commit -m 'do not hand-roll gh pr merge here'" $'base\n\nsweeper closes #5887' ""

echo ""
echo "=== $PASS/$TOTAL passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
