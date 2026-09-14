#!/usr/bin/env bash
# precommit-guard.sh — refuse `git commit` on main/master, without hook execution.
#
# Canonical source for the commit-on-main check (Soleur Cloud Mode, FR5).
# Plugin command hooks are documented cloud-capable for most events, but a
# skill cannot rely on hook execution in a not-local session — and user repos
# consuming via requiredPlugins have no .claude/hooks at all. work/ship/one-shot
# invoke this script directly so the refusal is structural in both worlds.
#
# Scope: commit-on-main ONLY. The DONE-marker stop-gate is not extractable —
# it reads hook-stdin transcript data a standalone script cannot see; it stays
# prose + the plugin Stop hook.
#
# Self-contained by design: no jq, no lib vendoring (.claude/hooks/lib paths
# resolve relative to the repo, which is wrong when this script runs from the
# plugin install cache), no emit_incident — callers log their own incidents.
#
# Usage:
#   precommit-guard.sh "COMMAND"        check a shell command string
#   precommit-guard.sh --cwd DIR        also check DIR's branch (a `cd DIR &&`
#                                       or `git -C DIR` inside COMMAND wins)
#
# Exit 0 = allowed (not a commit, or not on main/master).
# Exit 1 = refused — reason on stderr.
# Exit 2 = usage error.

set -euo pipefail

COMMAND=""
CWD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) CWD="${2:-}"; shift 2 ;;
    -*) echo "precommit-guard.sh: unknown flag: $1" >&2; exit 2 ;;
    *) COMMAND="$1"; shift ;;
  esac
done

# Fast path: not a git commit invocation. Match at start OR after a chain
# operator (&&, ||, ;) — "git add && git commit" must be caught, and a commit
# that mentions "git commit" in its message body still IS a commit, so the raw
# command (not a body-stripped view) is the right scan target.
if ! grep -qE '(^|&&|\|\||;)[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit' <<<"$COMMAND"; then
  exit 0
fi

# Resolve which repo the commit targets. Order:
#   1. `git -C <dir>` inside the command
#   2. a `cd <dir>` segment earlier in the chain
#   3. --cwd (the caller's session directory)
#   4. this script's own cwd
TARGET=""
git_c="$(grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]&|;]+' <<<"$COMMAND" | head -n 1 | sed -E 's/^git[[:space:]]+-C[[:space:]]+//' || true)"
cd_dir="$(grep -oE '(^|&&|\|\||;)[[:space:]]*cd[[:space:]]+[^[:space:]&|;]+' <<<"$COMMAND" | head -n 1 | sed -E 's/.*cd[[:space:]]+//' || true)"
for cand in "$git_c" "$cd_dir" "$CWD" "$PWD"; do
  [[ -n "$cand" && -d "$cand" ]] && TARGET="$cand" && break
done
[[ -n "$TARGET" ]] || exit 0 # nowhere to resolve — nothing to refuse on

BRANCH="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  printf 'BLOCKED: Committing directly to %s is not allowed. Create a feature branch first.\n' "$BRANCH" >&2
  exit 1
fi
exit 0
