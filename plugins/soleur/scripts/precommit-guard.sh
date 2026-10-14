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

# Detection is per pipeline segment: a `git commit` can hide anywhere in a
# chain — `git add && git commit`, `cd repo; git commit`, `printf msg |
# git commit -F -`, `LEFTHOOK=0 git commit`. Split COMMAND on the chain
# operators (&&, ||, ;, |, newline), then judge each segment.
#
# Known lexical limits (documented, not silently missed): subshell/eval forms
# like `bash -c 'git commit'`, `$(git commit)`, `( git commit )`, quoted
# `-C`/`cd` paths containing spaces, `git -c <cfg> commit` side effects beyond
# detection, and commits created without `git commit` (merge/pull/cherry-pick/
# rebase/continue) are out of this guard's declared scope — commit-on-main ONLY.
COMMIT_RE='^[[:space:]]*([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+[[:space:]]+)*((sudo|command|nice|env|xargs)[[:space:]]+)?([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+[[:space:]]+)*git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--git-dir[[:space:]]+[^[:space:]]+|-[A-Za-z]))*[[:space:]]+commit([[:space:]]|$)'

last_cd=""
while IFS= read -r seg; do
  # Track the dir the chain has cd'd into — it applies to later segments.
  cd_hit="$(grep -oE '(^|[[:space:]])cd[[:space:]]+[^[:space:]]+' <<<"$seg" | tail -n 1 | sed -E 's/.*cd[[:space:]]+//' || true)"
  [[ -n "$cd_hit" ]] && last_cd="$cd_hit"

  grep -qE "$COMMIT_RE" <<<"$seg" || continue

  # Resolve the repo THIS segment commits into. Priority: the -C / --git-dir
  # attached to the commit's own git invocation, then a GIT_DIR env-assignment
  # prefix (LEFTHOOK=0-style prefixes are the reason env-assignments are scanned
  # at all — dropping GIT_DIR would resolve the wrong repo); then the chain's
  # most recent cd; then --cwd; then ambient $PWD.
  target="" git_dir=""
  if grep -qoE -- '--git-dir[=[:space:]][^[:space:]]+' <<<"$seg"; then
    git_dir="$(grep -oE -- '--git-dir[=[:space:]][^[:space:]]+' <<<"$seg" | tail -n 1 | sed -E 's/^--git-dir[=[:space:]]+//' || true)"
  elif grep -qoE -- '(^|[[:space:]])GIT_DIR=[^[:space:]]+' <<<"$seg"; then
    git_dir="$(grep -oE -- '(^|[[:space:]])GIT_DIR=[^[:space:]]+' <<<"$seg" | tail -n 1 | sed -E 's/.*GIT_DIR=//' || true)"
  else
    git_c="$(grep -oE -- '-C[[:space:]]+[^[:space:]]+' <<<"$seg" | tail -n 1 | sed -E 's/^-C[[:space:]]+//' || true)"
    [[ -n "$git_c" ]] && target="$git_c"
  fi
  if [[ -z "$target" && -z "$git_dir" ]]; then
    for cand in "$last_cd" "$CWD" "$PWD"; do
      [[ -n "$cand" && -d "$cand" ]] && target="$cand" && break
    done
  fi

  if [[ -n "$git_dir" ]]; then
    BRANCH="$(git --git-dir="$git_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  elif [[ -n "$target" && -d "$target" ]]; then
    BRANCH="$(git -C "$target" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  else
    continue # nowhere to resolve — nothing to refuse on
  fi
  if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    printf 'BLOCKED: Committing directly to %s is not allowed. Create a feature branch first.\n' "$BRANCH" >&2
    exit 1
  fi
done < <(printf '%s\n' "$COMMAND" | sed -E 's/&&|\|\||[;|]/\n/g')

exit 0
