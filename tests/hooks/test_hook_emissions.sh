#!/usr/bin/env bash
# End-to-end test: each deny branch in the hook scripts emits a jsonl
# incident line with the expected rule_id. Drives the hooks by piping
# synthetic tool-input JSON to stdin, the same contract claude-code-action
# uses (see .github/workflows/test-pretooluse-hooks.yml).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pass=0; fail=0

# Per-session test isolation:
# - Any fixture running `git init` inside $WORK escapes to the parent
#   worktree unless GIT_{DIR,INDEX_FILE,WORK_TREE} are unset AND
#   GIT_CEILING_DIRECTORIES is set to $WORK. See learning
#   2026-03-24-git-ceiling-directories-test-isolation.md.
# - HOME / GIT_CONFIG_{GLOBAL,SYSTEM} neutralized so a local user's
#   ~/.gitconfig (e.g. `[init] defaultBranch = master`) doesn't break
#   the `git init -b main` fixture.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE

# Isolate the jsonl file per run so we don't contaminate dev telemetry.
WORK=$(mktemp -d)
export GIT_CEILING_DIRECTORIES="$WORK"
export HOME="$WORK"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
trap 'rm -rf "$WORK"' EXIT
# Mirror the repo layout so BASH_SOURCE resolution inside the hooks lands
# in $WORK instead of the real repo.
mkdir -p "$WORK/.claude/hooks/lib" "$WORK/scripts/lib"
cp "$REPO_ROOT/.claude/hooks/lib/incidents.sh" "$WORK/.claude/hooks/lib/"
cp "$REPO_ROOT/.claude/hooks/guardrails.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/pencil-open-guard.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/worktree-write-guard.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/scripts/lib/rule-metrics-constants.sh" "$WORK/scripts/lib/"
chmod +x "$WORK/.claude/hooks/"*.sh

FILE="$WORK/.claude/.rule-incidents.jsonl"

_check() {
  local label="$1" rid="$2"
  # Assert both rule_id AND schema field on the most recent emission.
  if [[ -s "$FILE" ]] \
      && jq -e --arg r "$rid" 'select(.rule_id == $r)' < "$FILE" >/dev/null 2>&1 \
      && jq -e --arg r "$rid" 'select(.rule_id == $r and .schema == 1)' < "$FILE" >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "[ok] $label → emitted $rid (schema=1)"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label (expected rule_id=$rid, schema=1)" >&2
    echo "  file contents:" >&2
    cat "$FILE" >&2 || true
  fi
  : > "$FILE"  # reset between cases
}

# Negative-space check: assert NO emission for rule_id <rid>. Proves the
# guard fires only on triggering input — without this pair, a buggy
# "always emit on --delete-branch" guard would pass the positive case.
_check_silent() {
  local label="$1" rid="$2"
  if [[ ! -s "$FILE" ]] || ! jq -e --arg r "$rid" 'select(.rule_id == $r)' < "$FILE" >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "[ok] $label → no $rid emission (silent as expected)"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label (unexpected $rid emission)" >&2
    echo "  file contents:" >&2
    cat "$FILE" >&2 || true
  fi
  : > "$FILE"
}

# Build a fake git repo we can point commands at via .cwd. Committed on
# branch `main` so commit-on-main cases fire. All commits inside $WORK.
_build_fake_main_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" -c user.email=t@test -c user.name=t commit --allow-empty -q -m init
  echo "$path"
}

# --- guardrails: block-stash-in-worktrees (uses real CWD → must be a worktree path)
# We fabricate a worktree-like path under $WORK and call the hook with .cwd set.
mkdir -p "$WORK/.worktrees/fake/inner"
echo '{"tool_name":"Bash","tool_input":{"command":"git stash"},"cwd":"'"$WORK/.worktrees/fake/inner"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash in worktree" "hr-never-git-stash-in-worktrees"

# --- guardrails: bypass preflight (--no-verify should emit without blocking)
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: --no-verify bypass preflight" "cq-never-skip-hooks"

# --- guardrails: bypass preflight (LEFTHOOK=0)
echo '{"tool_name":"Bash","tool_input":{"command":"LEFTHOOK=0 git commit -m foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: LEFTHOOK=0 bypass preflight" "cq-when-lefthook-hangs-in-a-worktree-60s"

# --- guardrails: rm -rf worktrees
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf .worktrees/foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: rm -rf worktrees" "guardrails-block-rm-rf-worktrees"

# --- guardrails: require-milestone
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: require-milestone" "guardrails-require-milestone"

# --- guardrails: block-commit-on-main (direct, via .cwd) ------------------
# Regression guard for resolve_command_cwd helper (proves the guard still
# fires when the only CWD signal is the hook input's .cwd field).
MAIN_REPO=$(_build_fake_main_repo "$WORK/main-repo-direct")
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"'"$MAIN_REPO"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: block-commit-on-main (direct)" "guardrails-block-commit-on-main"

# --- guardrails: block-commit-on-main (chained) ---------------------------
# Regression guard against re-anchoring the commit-on-main regex with `^`
# only, which would silently miss "git add foo && git commit -m x". See
# learning 2026-02-24-guardrails-chained-commit-bypass.md.
echo '{"tool_name":"Bash","tool_input":{"command":"git add foo && git commit -m x"},"cwd":"'"$MAIN_REPO"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: block-commit-on-main (chained)" "guardrails-block-commit-on-main"

# --- guardrails: block-commit-on-main (negative: feature branch) -----------
# Prove the guard does NOT fire when HEAD is a feature branch. A bug that
# degenerated to "always emit on git commit" would pass the two positive
# cases above; this case fails it.
FEAT_REPO=$(_build_fake_main_repo "$WORK/feat-repo")
git -C "$FEAT_REPO" checkout -q -b feat/foo
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"'"$FEAT_REPO"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check_silent "guardrails: block-commit-on-main (feature branch)" "guardrails-block-commit-on-main"

# --- guardrails: block-conflict-markers -----------------------------------
# Stage a file with conflict markers. Use printf instead of a heredoc so
# the literal markers in the test source don't themselves trip any local
# pre-commit grep. The guard inspects `git diff --cached`.
CONFLICT_REPO=$(_build_fake_main_repo "$WORK/main-repo-conflict")
# Move to a feature branch so commit-on-main doesn't fire first.
git -C "$CONFLICT_REPO" checkout -q -b feat/conflict
printf '%s\n' '<<<<<<< HEAD' 'a' '=======' 'b' '>>>>>>> other' > "$CONFLICT_REPO/file.txt"
git -C "$CONFLICT_REPO" add file.txt
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"'"$CONFLICT_REPO"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: block-conflict-markers" "guardrails-block-conflict-markers"

# --- guardrails: block-delete-branch (--delete-branch + >1 worktree) ------
# The guard counts `git worktree list` output — we stub PATH with a fake
# git that prints two lines. This avoids adding a real worktree that would
# confuse GIT_CEILING_DIRECTORIES on teardown.
STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/git" <<'STUBGIT'
#!/usr/bin/env bash
if [[ "$1 $2" == "worktree list" ]]; then
  echo "/tmp/main 0000000 [main]"
  echo "/tmp/feat 0000001 [feat]"
  exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
STUBGIT
chmod +x "$STUB_BIN/git"
PATH="$STUB_BIN:$PATH" \
  bash "$WORK/.claude/hooks/guardrails.sh" <<<'{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1 --delete-branch --squash"}}' \
  >/dev/null 2>&1 || true
_check "guardrails: block-delete-branch" "guardrails-block-delete-branch"

# --- guardrails: block-delete-branch (negative: single worktree) ----------
# Stub `git worktree list` to one line; guard must NOT fire.
STUB_BIN_ONE="$WORK/stub-bin-one"
mkdir -p "$STUB_BIN_ONE"
cat > "$STUB_BIN_ONE/git" <<'STUBGIT'
#!/usr/bin/env bash
if [[ "$1 $2" == "worktree list" ]]; then
  echo "/tmp/main 0000000 [main]"
  exit 0
fi
exec /usr/bin/env -i PATH=/usr/bin:/bin git "$@"
STUBGIT
chmod +x "$STUB_BIN_ONE/git"
PATH="$STUB_BIN_ONE:$PATH" \
  bash "$WORK/.claude/hooks/guardrails.sh" <<<'{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1 --delete-branch --squash"}}' \
  >/dev/null 2>&1 || true
_check_silent "guardrails: block-delete-branch (single worktree)" "guardrails-block-delete-branch"

# --- pencil-open-guard (untracked .pen) -----------------------------------
PEN_REPO=$(_build_fake_main_repo "$WORK/pen-repo")
echo "stub" > "$PEN_REPO/foo.pen"  # untracked
echo '{"tool_input":{"filePath":"'"$PEN_REPO/foo.pen"'"}}' \
  | bash "$WORK/.claude/hooks/pencil-open-guard.sh" >/dev/null 2>&1 || true
_check "pencil-open-guard: untracked .pen" "cq-before-calling-mcp-pencil-open-document"

# --- worktree-write-guard (write to main root while worktrees exist) ------
# The guard uses `git rev-parse --git-common-dir` to find the main root
# and checks for `.worktrees/<anything>` presence via ls -A. We run the
# hook from inside a repo under $WORK that contains a populated
# .worktrees/ directory.
WTG_REPO=$(_build_fake_main_repo "$WORK/wtg-repo")
mkdir -p "$WTG_REPO/.worktrees/active/stuff"
( cd "$WTG_REPO" \
  && echo '{"tool_input":{"file_path":"'"$WTG_REPO/file.txt"'"}}' \
     | bash "$WORK/.claude/hooks/worktree-write-guard.sh" >/dev/null 2>&1 || true )
_check "worktree-write-guard: write to main while worktrees exist" "guardrails-worktree-write-guard"

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
