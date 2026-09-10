#!/usr/bin/env bash
# End-to-end test: each deny branch in the hook scripts emits a jsonl
# incident line with the expected rule_id. Drives the hooks by piping
# synthetic tool-input JSON to stdin, the same contract claude-code-action
# uses (see .github/workflows/test-pretooluse-hooks.yml).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pass=0; fail=0

# Per-session test isolation, through the shell fixture chokepoint (#7849).
#
# What stood here was `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE` plus hand-spelled
# GIT_CEILING_DIRECTORIES / GIT_CONFIG_{GLOBAL,SYSTEM} exports. That unset covered three of
# the NINE variables that redirect where git reads and writes, and a partial scrub greps
# identically to a full one -- which is precisely why the six-variable gap survived. Sourcing
# the chokepoint ARMS the fail-loud tripwire instead: an inherited git-location environment
# now ABORTS naming this file, rather than being half-cleaned in silence. `git_fixture_env`
# supplies the ceiling, the config hermeticity and a synthesized identity from one list.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

# Isolate the jsonl file per run so we don't contaminate dev telemetry.
WORK=$(mktemp -d)
# HOME carries no GIT_ prefix, so the chokepoint's sweep leaves it alone. It stays neutralized
# here because the hooks under test read it for non-git purposes too.
export HOME="$WORK"
trap 'rm -rf "$WORK"' EXIT

# $WORK is itself a fixture -- the mirrored repo layout below is what the copied hooks resolve
# against -- so it gets the same constructed environment every other fixture here gets.
git_fixture_env "$WORK" || {
  echo "FATAL: test_hook_emissions: git_fixture_env refused the run root $WORK" >&2
  exit 1
}

# LEDGER RECONCILIATION (#7853), paired with the conversion above and NOT separable from it.
# Sourcing the chokepoint brings this suite inside the incident-sandbox redirect, so the rows
# its hooks emit stop landing under $WORK. This suite ASSERTS on those rows, so it reads them
# back from the sandbox the helper exports. Sourced AFTER the trap above so the helper COMPOSES
# with it rather than being clobbered by it.
# shellcheck source=../../.claude/hooks/lib/test-incident-sandbox.sh
source "$REPO_ROOT/.claude/hooks/lib/test-incident-sandbox.sh"
# Mirror the repo layout so BASH_SOURCE resolution inside the hooks lands
# in $WORK instead of the real repo.
mkdir -p "$WORK/.claude/hooks/lib" "$WORK/scripts/lib"
cp "$REPO_ROOT/.claude/hooks/lib/incidents.sh" "$WORK/.claude/hooks/lib/"
cp "$REPO_ROOT/.claude/hooks/lib/freeze-lock.sh" "$WORK/.claude/hooks/lib/"
# hook-input.sh is a HARD dependency of every hook copied below (#7164): they
# source it fail-hard and refuse to run without it. Omitting it here made all
# 19 emission assertions fail with an empty ledger — correctly, because the
# hooks detected their own missing helper and declined to decide rather than
# passing through silently. Keep this in step with the hooks' dependencies.
cp "$REPO_ROOT/.claude/hooks/lib/hook-input.sh" "$WORK/.claude/hooks/lib/"
cp "$REPO_ROOT/.claude/hooks/guardrails.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/pencil-open-guard.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/worktree-write-guard.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/scripts/lib/rule-metrics-constants.sh" "$WORK/scripts/lib/"
chmod +x "$WORK/.claude/hooks/"*.sh

# The sink is the sandbox, not the mirrored layout: see the reconciliation note above.
FILE="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"

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

# Deny-payload check: assert hook stdout carries permissionDecision=deny.
# Distinct from _check (which verifies incident JSONL emission) — this tests
# the stdout response claude-code-action reads to make its block decision.
# Catches silent breakage where emit_incident fires but the deny jq block is
# missing or malformed. See issue #3135.
_check_deny_payload() {
  local label="$1" command="$2"
  local input payload
  input=$(jq -nc --arg cmd "$command" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
  payload=$(echo "$input" | bash "$WORK/.claude/hooks/guardrails.sh" 2>/dev/null || true)
  if echo "$payload" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "[ok] $label → permissionDecision=deny"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label — stdout missing permissionDecision=deny" >&2
    echo "  stdout: $payload" >&2
  fi
  : > "$FILE"
}

# Build a fake git repo we can point commands at via .cwd. Committed on
# branch `main` so commit-on-main cases fire. All commits inside $WORK.
#
# It no longer ECHOES the path, and callers no longer wrap it in `$( )`. `git_fixture_env`
# exports into the shell that calls it, and a command substitution runs in a subshell -- the
# fixture would have been built correctly while every later `git -C "$path"` in the parent ran
# outside the constructed environment. Called as a plain function, the exports land where the
# rest of the suite can see them.
_build_fake_main_repo() {
  local path="$1"
  : "${path:?fixture dir is empty; git -C <empty> would retarget this write}"
  mkdir -p "$path"
  git_fixture_env "$path" || {
    echo "FATAL: test_hook_emissions: git_fixture_env refused fixture $path" >&2
    exit 1
  }
  git -C "$path" init -q -b main
  git -C "$path" -c user.email=t@test -c user.name=t commit --allow-empty -q -m init
}

# --- guardrails: block-stash-in-worktrees (unconditional — CWD is irrelevant)
# The guard blocks git stash regardless of working directory. The .cwd field
# below is a no-op for this check; it is kept only for payload completeness.
# Cases enumerate every alternation branch in the regex
# `(^|&&|\|\||;)\s*git\s+stash` plus the cleanup sub-command, a dedicated
# ;-primary case (proved independently, not masked by ^ firing first in the
# &&-chain case), the exact issue #3135 repro, and a negative case.
mkdir -p "$WORK/.worktrees/fake/inner"
echo '{"tool_name":"Bash","tool_input":{"command":"git stash"},"cwd":"'"$WORK/.worktrees/fake/inner"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash (bare)" "hr-never-git-stash-in-worktrees"

echo '{"tool_name":"Bash","tool_input":{"command":"git stash pop"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash pop" "hr-never-git-stash-in-worktrees"

echo '{"tool_name":"Bash","tool_input":{"command":"git stash && bun test plugins/soleur/test/components.test.ts 2>&1 | head -n 20 ; git stash pop"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash (&& chain — PR #2683 pattern)" "hr-never-git-stash-in-worktrees"

# ; as primary trigger — test 3 above hides whether ; works because ^ fires
# first. This command has no leading git stash, so only ; can match.
echo '{"tool_name":"Bash","tool_input":{"command":"true; git stash pop"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash (; primary — not masked by ^)" "hr-never-git-stash-in-worktrees"

# Issue #3135 repro: && chain followed by piped grep with | inside the pattern.
# Verifies the hook fires when the command string contains many unrelated | chars.
echo '{"tool_name":"Bash","tool_input":{"command":"git stash && bash plugins/soleur/test/schedule-skill-once.test.sh 2>&1 | grep -E \"FAIL|Passed|Failed\" | tail -5; echo \"---restoring---\"; git stash pop"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash (&& + piped grep — issue #3135 repro)" "hr-never-git-stash-in-worktrees"

echo '{"tool_name":"Bash","tool_input":{"command":"git diff --quiet || git stash"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash (|| chain)" "hr-never-git-stash-in-worktrees"

# Subcommand coverage: `git stash list` (and any other stash subcommand) must
# also fire — the regex matches `git\s+stash` followed by anything. Salvaged
# from the parallel-suite alternative in #3941 (closed as superseded by the
# canonical-suite extensions in #3870 + #3970); kept here to lock in that
# read-only stash subcommands aren't an over-fire exception.
echo '{"tool_name":"Bash","tool_input":{"command":"git stash list"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash list (subcommand)" "hr-never-git-stash-in-worktrees"

# Negative: substrings that are not `git\s+stash` must not over-fire. Mirrors
# the _check_silent companions on block-commit-on-main and block-delete-branch.
echo '{"tool_name":"Bash","tool_input":{"command":"echo gitstash; rg stash"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check_silent "guardrails: stash substrings (no over-fire)" "hr-never-git-stash-in-worktrees"

# Deny-payload smoke test (issue #3135): verify the hook stdout returns the
# deny payload that claude-code-action reads to block the tool call. The
# existing cases above only verify incident JSONL emission; this case confirms
# the jq deny block is also present in stdout — catching silent bypass where
# telemetry fires but Claude Code never receives the block signal.
_check_deny_payload "guardrails: git stash deny-payload (issue #3135)" "git stash"

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

# --- guardrails: block-recursive-delete (hardened ownership proof, #5988)
# A .git-bearing target resolves onto a checkout → deny + emit the new id.
mkdir -p "$WORK/nuke-target/.git"
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf '"$WORK"'/nuke-target"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: rm -rf .git-bearing checkout" "guardrails-block-recursive-delete"
# Negative: an ordinary non-protected dir does NOT emit the recursive-delete id.
mkdir -p "$WORK/scratch-xyz"
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf '"$WORK"'/scratch-xyz"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check_silent "guardrails: rm -rf non-protected dir (no over-fire)" "guardrails-block-recursive-delete"

# --- guardrails: freeze-edit-lock (Write|Edit branch, #5988)
# A valid active freeze + an Edit outside the prefix → deny + emit the id.
# Freeze root resolves three dirs up from lib/ ($WORK), so write the state file
# directly at $WORK/.claude/.freeze-lock.
printf '%s\n' "$WORK/allowed" > "$WORK/.claude/.freeze-lock"
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORK"'/elsewhere/foo.ts"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: freeze edit outside prefix" "guardrails-freeze-edit-lock"
# Negative: an Edit INSIDE the prefix does NOT emit the freeze id.
echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORK"'/allowed/foo.ts"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check_silent "guardrails: freeze edit inside prefix (no fire)" "guardrails-freeze-edit-lock"
rm -f "$WORK/.claude/.freeze-lock"

# --- guardrails: require-milestone
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: require-milestone" "guardrails-require-milestone"

# --- guardrails: block-commit-on-main (direct, via .cwd) ------------------
# Regression guard for resolve_command_cwd helper (proves the guard still
# fires when the only CWD signal is the hook input's .cwd field).
MAIN_REPO="$WORK/main-repo-direct"
_build_fake_main_repo "$MAIN_REPO"
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
FEAT_REPO="$WORK/feat-repo"
_build_fake_main_repo "$FEAT_REPO"
: "${FEAT_REPO:?fixture dir is empty; git -C <empty> would retarget this write}"
git -C "$FEAT_REPO" checkout -q -b feat/foo
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"'"$FEAT_REPO"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check_silent "guardrails: block-commit-on-main (feature branch)" "guardrails-block-commit-on-main"

# --- guardrails: block-conflict-markers -----------------------------------
# Stage a file with conflict markers. Use printf instead of a heredoc so
# the literal markers in the test source don't themselves trip any local
# pre-commit grep. The guard inspects `git diff --cached`.
CONFLICT_REPO="$WORK/main-repo-conflict"
_build_fake_main_repo "$CONFLICT_REPO"
: "${CONFLICT_REPO:?fixture dir is empty; git -C <empty> would retarget this write}"
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
PEN_REPO="$WORK/pen-repo"
_build_fake_main_repo "$PEN_REPO"
echo "stub" > "$PEN_REPO/foo.pen"  # untracked
echo '{"tool_input":{"filePath":"'"$PEN_REPO/foo.pen"'"}}' \
  | bash "$WORK/.claude/hooks/pencil-open-guard.sh" >/dev/null 2>&1 || true
_check "pencil-open-guard: untracked .pen" "cq-before-calling-mcp-pencil-open-document"

# --- worktree-write-guard (write to main root while worktrees exist) ------
# The guard uses `git rev-parse --git-common-dir` to find the main root
# and checks for `.worktrees/<anything>` presence via ls -A. We run the
# hook from inside a repo under $WORK that contains a populated
# .worktrees/ directory.
WTG_REPO="$WORK/wtg-repo"
_build_fake_main_repo "$WTG_REPO"
mkdir -p "$WTG_REPO/.worktrees/active/stuff"
( cd "$WTG_REPO" \
  && echo '{"tool_input":{"file_path":"'"$WTG_REPO/file.txt"'"}}' \
     | bash "$WORK/.claude/hooks/worktree-write-guard.sh" >/dev/null 2>&1 || true )
_check "worktree-write-guard: write to main while worktrees exist" "guardrails-worktree-write-guard"

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
