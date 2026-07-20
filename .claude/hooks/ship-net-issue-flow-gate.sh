#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge` when the PR is
# net-positive on the issue queue (NET > 0) with no override.
#
# Mechanical twin of ship/SKILL.md §"Net-Issue-Flow Gate (blocking)". Closes the
# bypass class where the agent skips /ship Phase 5.5 and goes straight to
# `gh pr ready` / `gh pr merge`.
#
# Why: the net-issue-flow surface ran ADVISORY for three months and was
# trivially skipped. Measured over the 7 days to 2026-07-20: 269 issues filed
# against 132 merged PRs, 125 closed, queue +144/week to 1,024 open. An
# advisory display of that asymmetry does not correct it.
#
# ALL counting logic lives in plugins/soleur/skills/ship/scripts/net-issue-flow.sh.
# This hook delegates and translates the exit code — it does NOT re-implement
# the query. Two implementations of the same threshold would drift, and the
# drifting copy would be the one that runs.
#
# Corpus note (deliberate): the override marker is read from the PR BODY ONLY.
# This hook does NOT expand linked `specs/**.md` files into its corpus, unlike
# the soak-followthrough precedent. Inheriting that would let the gate find its
# own override marker inside committed evidence/spec files and silently
# self-override — invisible to the acceptance criteria.
#
# Command matching (2.3): `gh pr (ready|merge)` — deliberately WIDER than the
# soak gate's `merge\s+.*--auto`, which misses `--squash` (merge queue) and
# `--admin`. Both are real merge surfaces.
#
# Early-exit ordering (2.3b) — each early exit is a bypass path, so the order is
# load-bearing:
#   1. command does not match          -> exit 0 (not our surface)
#   2. env override                    -> exit 0 (deliberate, announced)
#   3. gate script missing/not exec    -> exit 0 (fail-open: infra, not policy)
#   4. delegated script exit != 1      -> exit 0 (pass or transient fail-open)
#   5. delegated script exit == 1      -> DENY
# The hook cds into the payload .cwd (when absolute and existing) before
# delegating, matching every sibling ship gate. The delegated script resolves
# the PR from the process cwd, so skipping this makes the gate silently
# fail-open whenever the session cwd is not the PR's worktree.
#
# Fail-open conditions (exit 0 silently or with a note):
#   - command is not `gh pr ready` / `gh pr merge`
#   - SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1
#   - gate script absent, not executable, or times out
#   - gh unauthenticated / no PR yet (the script itself fails open)
#
# Fail-closed condition (deny + emit_incident):
#   - the delegated script exits 1 (NET > 0, no override marker in the PR body)

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Strip commit bodies/heredocs so a commit message *documenting* the command is
# not mistaken for one (#5192).
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi

if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge)(\s|$|&&|\|\||;)'; then
  exit 0
fi

if [[ "${SOLEUR_SKIP_NET_ISSUE_FLOW_GATE:-}" == "1" ]]; then
  exit 0
fi

# The SCRIPT PATH resolves from the project dir (it is the same checkout
# regardless of which worktree the command runs in). The WORKING DIRECTORY must
# still be the payload .cwd: the delegated script resolves the PR via
# `gh pr view` and `gh issue list`, both of which read the repo/branch from the
# process cwd. Resolving only the script path and inheriting the hook process's
# cwd is a real bypass — a session started in the main checkout that then runs
# `gh pr merge` against a feature worktree would resolve NO PR, fail open, and
# never block. That is the exact class this gate exists to close, so it is not
# left to convention: the suite asserts .cwd is honored.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
GATE="$PROJECT_DIR/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
[[ -x "$GATE" ]] || exit 0

if [[ "$WORK_DIR" == /* ]] && [[ -d "$WORK_DIR" ]]; then
  cd "$WORK_DIR" 2>/dev/null || exit 0
fi

OUT="$(timeout 8 bash "$GATE" 2>&1)"
RC=$?

[[ "$RC" -eq 1 ]] || exit 0

REASON="Net-issue-flow gate: BLOCKED — this PR files more issues than it closes.

${OUT}

Every PR must close at least as many issues as it files. Filing is free;
closing is expensive, and the queue grows by roughly the difference. The
measured rate to 2026-07-20 was 2.04 filed per merged PR against 0.95 closed —
a queue growing +144/week.

Resolve via one of:
  (a) Fix inline — fold the filed work into THIS PR. The cost-of-filing
      auto-flip (<=100 lines AND <=4 files) already covers most findings.
  (b) Close something — if a filed issue supersedes an open one, close it and
      add the 'Closes #N' keyword to the PR body.
  (c) Override (legitimate architectural-pivot deferral) — add
      '<!-- gate-override: net-issue-flow -->' plus a one-line justification
      per filed issue to the PR body, or run with
      SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.

See ship/SKILL.md section 'Net-Issue-Flow Gate (blocking)'."

emit_incident net-issue-flow deny "blocked net-positive PR at gh pr ready/merge" 2>/dev/null || true

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
