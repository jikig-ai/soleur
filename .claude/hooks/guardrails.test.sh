#!/usr/bin/env bash
# Fixture-based tests for guardrails.sh — scoped to the require-milestone gate.
# Asserts gh issue create against OUR repo requires --milestone, while creation
# against an EXTERNAL repo (different owner) is exempt (their milestone sets
# differ; the backlog-hygiene rule applies only to our own issues).
#
# Isolation: the hook is invoked via stdin with synthetic Bash tool payloads;
# no real gh call is made. INCIDENTS_REPO_ROOT redirects emit_incident writes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/guardrails.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

mk_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Returns the permissionDecision or "<none>" when the hook emits no JSON (allow).
# Runs the hook from the non-git $tmp CWD (not the test process CWD). This
# isolates the require-milestone / block-stash gates under test from the
# ORTHOGONAL, branch-dependent block-commit-on-main gate: a `git commit`-based
# fixture (AC1/AC3/AC4) resolves its branch from the hook's CWD, so on the
# `main` branch (post-merge CI) block-commit-on-main denies the commit and masks
# the gate the fixture is actually exercising. A non-git CWD makes branch
# resolution empty → block-commit-on-main no-ops → the fixture is branch- and
# environment-independent (passes identically on a feature branch and on main).
# See #5192 — these fixtures passed on a feature-branch worktree but failed on
# main-CI until this isolation landed.
decision_of() {
  local cmd="$1" tmp; tmp="$(mktemp -d)"
  local out
  out="$(cd "$tmp" && mk_payload "$cmd" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)"
  rm -rf "$tmp"
  # An allow is empty hook output (no JSON emitted); normalize to "<none>".
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert() {
  local label="$1" want="$2" cmd="$3"
  TOTAL=$((TOTAL + 1))
  local got; got="$(decision_of "$cmd")"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# Our repo (implicit) without --milestone → deny.
assert "implicit repo, no milestone denies" "deny" \
  'gh issue create --title "x" --body "y"'

# Our repo (implicit) with --milestone → allow.
assert "implicit repo, with milestone allows" "<none>" \
  'gh issue create --title "x" --body "y" --milestone "Post-MVP / Later"'

# Explicit OUR repo without --milestone → deny (still gated).
assert "explicit jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo jikig-ai/soleur --title "x" --body "y"'

# External repo without --milestone → allow (exempt: different owner).
assert "external repo, no milestone allows" "<none>" \
  'gh issue create --repo highagency/pencil-desktop-releases --title "x" --body-file /tmp/b.md'

# External repo with --repo=owner/name form → allow.
assert "external repo (=form), no milestone allows" "<none>" \
  'gh issue create --repo=highagency/pencil-desktop-releases --title "x"'

# QUOTED our repo without --milestone → deny (quote-aware: must not be read as external).
assert "quoted jikig-ai repo, no milestone denies" "deny" \
  'gh issue create --repo "jikig-ai/soleur" --title x'

# Embedded --repo string inside a quoted --body, no real --repo → deny (no bypass).
assert "embedded --repo in body, no milestone denies" "deny" \
  'gh issue create --title real --body "see --repo evil/x for context"'

# -R short form targeting OUR repo while an embedded external string sits in title → deny.
assert "short -R our repo wins over embedded external denies" "deny" \
  'gh issue create --title "--repo evil/x" -R jikig-ai/soleur'

# Genuine external via short -R form, no milestone → allow.
assert "external via -R short form allows" "<none>" \
  'gh issue create -R highagency/pencil-desktop-releases --title x'

# ---------------------------------------------------------------------------
# #5192 — commit-body / heredoc false-positive fixes (require-milestone + stash)
# A `git commit` whose MESSAGE documents a trigger phrase must NOT be blocked:
# the strip blanks quoted/heredoc bodies before the detection grep. Real bare
# invocations stay gated.
# ---------------------------------------------------------------------------

# AC1 — commit-body `gh issue create` at a line-start (no --milestone in body)
# is NOT blocked. Pre-fix this denied (the exact #5085 foot-gun).
assert "AC1 commit-body gh issue create allows (FP fixed)" "<none>" \
  $'git add . && git commit -m "fix the digest\ngh issue create for the operator-digest feature\n"'

# AC3 — commit-body `git stash` is NOT blocked …
assert "AC3 commit-body git stash allows (FP fixed)" "<none>" \
  $'git commit -m "doc\ngit stash is banned in worktrees\n"'
# … but a real `git stash` STILL denies.
assert "AC3 real git stash still denies" "deny" \
  'git stash'

# AC4 — bare heredoc (`-F - <<EOF … EOF`) body is NOT blocked …
assert "AC4 bare-heredoc gh issue create allows (FP fixed)" "<none>" \
  $'git commit -F - <<EOF\nnote\ngh issue create for the digest\nEOF\n'
# … but a real chained `gh issue create` AFTER the closing EOF STILL denies
# (no --milestone, implicit our repo): proves the post-terminator preservation.
assert "AC4 real create after heredoc still denies" "deny" \
  $'git commit -F - <<EOF\nbody\nEOF\n && gh issue create --title x --body y'

# Sweep (#5192) — block-delete-branch is also phrase-class. A commit body
# documenting `gh pr merge --delete-branch` must NOT be blocked (pre-fix it
# denied whenever >1 worktree exists). Note: the gate's deny is worktree-count-
# gated, so a real-invocation deny is not asserted here (untestable in a single-
# worktree CI checkout); the strip non-vacuity below proves detection survives.
assert "sweep commit-body gh pr merge --delete-branch allows (FP fixed)" "<none>" \
  $'git commit -m "doc\ngh pr merge --delete-branch orphans worktrees\n"'

# Non-vacuity: the strip preserves a REAL invocation's flags so the
# delete-branch detection still fires (only quoted bodies are blanked).
# shellcheck source=lib/incidents.sh
source "$SCRIPT_DIR/lib/incidents.sh" 2>/dev/null || true
TOTAL=$((TOTAL + 1))
if strip_command_bodies 'gh pr merge 7 --squash --delete-branch' \
     | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  PASS=$((PASS + 1)); echo "PASS: strip preserves real --delete-branch (detection non-vacuous)"
else
  FAIL=$((FAIL + 1)); echo "FAIL: strip dropped real --delete-branch flags"
fi

# ===========================================================================
# #5988 — hardened recursive-delete ownership proof (b) + freeze edit-lock (a)
# ===========================================================================

# Build an Edit-tool payload (file_path, no command).
mk_edit_payload() {
  local path="$1"
  jq -nc --arg p "$path" '{tool_name:"Edit", tool_input:{file_path:$p}}'
}

# Run the hook with a given payload from a given CWD, redirecting incident +
# freeze state to $root. Echoes the permissionDecision or "<none>".
run_decision() {
  local payload="$1" cwd="$2" root="$3"
  local out
  out="$(cd "$cwd" 2>/dev/null && printf '%s' "$payload" \
    | INCIDENTS_REPO_ROOT="$root" FREEZE_LOCK_REPO_ROOT="$root" bash "$HOOK" 2>/dev/null)"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

assert_run() {
  local label="$1" want="$2" payload="$3" cwd="$4" root="$5"
  TOTAL=$((TOTAL + 1))
  local got; got="$(run_decision "$payload" "$cwd" "$root")"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label → $got"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"
  fi
}

# --- Delete guard: protected targets deny; non-protected allow -------------
DG="$(mktemp -d)"; git init -q "$DG/repo"
mkdir -p "$DG/other/.git" "$DG/scratch-abc123"
ln -s "$DG/repo" "$DG/link"

# repo root (resolved via git worktree list from the command cwd) → deny
assert_run "delete: repo root denies" "deny" \
  "$(mk_payload "rm -rf $DG/repo")" "$DG/repo" "$DG"
# symlink resolving onto a .git-bearing checkout → deny
assert_run "delete: symlink-to-repo-root denies" "deny" \
  "$(mk_payload "rm -rf $DG/link")" "$DG/repo" "$DG"
# arbitrary .git-bearing dir (not the cwd repo) → deny
assert_run "delete: .git-bearing dir denies" "deny" \
  "$(mk_payload "rm -rf $DG/other")" "$DG" "$DG"
# filesystem root → deny (constant protected)
assert_run "delete: / denies" "deny" \
  "$(mk_payload "rm -rf /")" "$DG" "$DG"
# \$HOME → deny (constant protected)
assert_run "delete: \$HOME denies" "deny" \
  "$(mk_payload "rm -rf $HOME")" "$DG" "$DG"
# non-protected scratch dir → allow (default-allow-except-protected; the staging
# ALLOW needs no marker today — a non-protected target is already permitted)
assert_run "delete: non-protected scratch allows" "<none>" \
  "$(mk_payload "rm -rf $DG/scratch-abc123")" "$DG" "$DG"
# ordinary build artifact → allow (guard must not brick normal cleanup)
assert_run "delete: node_modules allows" "<none>" \
  "$(mk_payload "rm -rf $DG/repo/node_modules")" "$DG/repo" "$DG"
rm -rf "$DG"

# --- Freeze edit-lock ------------------------------------------------------
FZ="$(mktemp -d)"
mkdir -p "$FZ/apps" "$FZ/other"
# Activate a VALID freeze via the CLI (writes a realpath-canonical prefix).
FREEZE_LOCK_REPO_ROOT="$FZ" bash "$SCRIPT_DIR/lib/freeze-lock.sh" set "$FZ/apps" >/dev/null 2>&1

# Edit inside the allowed prefix → allow
assert_run "freeze: edit inside prefix allows" "<none>" \
  "$(mk_edit_payload "$FZ/apps/foo.ts")" "$FZ" "$FZ"
# Edit outside the allowed prefix → deny
assert_run "freeze: edit outside prefix denies" "deny" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"

# Malformed freeze state (two lines) → fail-open (edit allowed)
printf '%s\n%s\n' "$FZ/apps" "$FZ/extra" > "$FZ/.claude/.freeze-lock"
assert_run "freeze: malformed state fails open (edit allows)" "<none>" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"

# Absent freeze state → edit allowed
rm -f "$FZ/.claude/.freeze-lock"
assert_run "freeze: absent state allows edit" "<none>" \
  "$(mk_edit_payload "$FZ/other/bar.ts")" "$FZ" "$FZ"
rm -rf "$FZ"

# --- TR3: freeze ACTIVE must NOT shadow the Bash sentinels -----------------
TR="$(mktemp -d)"
FREEZE_LOCK_REPO_ROOT="$TR" bash "$SCRIPT_DIR/lib/freeze-lock.sh" set "$TR/apps" >/dev/null 2>&1
# rm -rf on a worktree path → still denied by the narrow sentinel
assert_run "TR3: freeze active, rm -rf .worktrees still denies" "deny" \
  "$(mk_payload 'rm -rf ./.worktrees/foo')" "$TR" "$TR"
# gh issue create without --milestone → still denied by require-milestone
assert_run "TR3: freeze active, gh issue create no-milestone still denies" "deny" \
  "$(mk_payload 'gh issue create --title x --body y')" "$TR" "$TR"
# git stash → still denied by block-stash
assert_run "TR3: freeze active, git stash still denies" "deny" \
  "$(mk_payload 'git stash')" "$TR" "$TR"
# benign Bash command → allowed (freeze never applies to Bash)
assert_run "TR3: freeze active, benign Bash allows" "<none>" \
  "$(mk_payload 'ls -la')" "$TR" "$TR"
rm -rf "$TR"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
