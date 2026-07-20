#!/usr/bin/env bash
# Headless-visibility tests for pre-merge-rebase.sh.
#
# Verifies the 4 stderr emission sites (lines 110, 137, 147, 153) route
# through headless_or_stderr so warnings are visible under `claude --bg`.
#
# Run via:  bash .claude/hooks/pre-merge-rebase-headless.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq missing";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

# Build a minimal work repo with review evidence so we get past the
# review-evidence gate and reach the detached-HEAD warn at line 110.
#
# Since #6724 the todos/ signal is scoped to `origin/main..HEAD`, so this needs
# a real origin and the evidence must live on a commit that is NOT already on
# origin/main. The previous shape committed todos/ directly onto main and then
# detached there, which under branch scoping is correctly read as "no evidence
# unique to this branch" — the gate would deny and the detached-HEAD warn under
# test would never be reached.
make_repo() {
  local work="$1" origin="$2"
  git -C "$work" init -q
  git -C "$work" symbolic-ref HEAD refs/heads/main
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" config commit.gpgsign false
  echo base > "$work/base.txt"
  git -C "$work" add base.txt
  git -C "$work" commit -q -m base

  # Local bare origin: the hook fetches origin/main, and a local remote keeps
  # that offline-safe.
  git init -q --bare -b main "$origin"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main
  git -C "$work" fetch -q origin

  # Review evidence on a commit ahead of origin/main.
  git -C "$work" checkout -q -b feat-headless
  mkdir -p "$work/todos"
  echo "code-review" > "$work/todos/sample.md"
  git -C "$work" add todos/sample.md
  git -C "$work" commit -q -m "review findings"

  # Detach HEAD so the line-110 warn fires.
  git -C "$work" checkout -q --detach
}

merge_payload() {
  local cwd="$1"
  # `gh pr merge` is the only command the hook intercepts; the early-exit
  # filter at the top would short-circuit anything else.
  jq -nc --arg c "$cwd" '{tool_input: {command: "gh pr merge --auto --squash"}, cwd: $c}'
}

# ---------------------------------------------------------------------------
# T1: Headless — no TTY on stderr + CLAUDECODE=1 → stderr silent, log written
# ---------------------------------------------------------------------------
echo "T1: headless route → log file, stderr silent"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/work"
INCIDENTS="$TMP/incidents"
mkdir -p "$WORK" "$INCIDENTS"
make_repo "$WORK" "$TMP/origin.git"

STDERR_OUT="$TMP/stderr.out"
STDOUT_OUT="$TMP/stdout.out"
LOG_ROOT="$TMP/log-root"
mkdir -p "$LOG_ROOT"

# Run the hook with: no TTY on fd 2 (redirect to file), CLAUDECODE=1 set,
# SOLEUR_SESSION_STATE_ROOT points to our log-root so logs land in $LOG_ROOT/logs/.
export CLAUDECODE=1
export SOLEUR_SESSION_STATE_ROOT="$LOG_ROOT"
export INCIDENTS_REPO_ROOT="$INCIDENTS"
merge_payload "$WORK" | "$HOOK" >"$STDOUT_OUT" 2>"$STDERR_OUT" || true
unset CLAUDECODE SOLEUR_SESSION_STATE_ROOT INCIDENTS_REPO_ROOT

# Collected into a variable rather than piped into `grep -q .`, for two reasons
# under this file's `set -uo pipefail`:
#   * `grep -q` closes the pipe on its FIRST match, so the upstream `xargs`/`grep`
#     takes SIGPIPE (141) and pipefail propagates that non-zero — the assertion
#     then reads as "no match" precisely when the match came early. A latent
#     false-negative that only shows up once a log grows.
#   * `-print0`/`-0` keeps filenames with spaces or newlines intact (SC2038);
#     `-r` stops grep reading stdin when find returns nothing, which would
#     otherwise hang.
DETACHED_HITS=$(find "$LOG_ROOT/logs" -name '*.log' -print0 2>/dev/null \
  | xargs -0 -r grep -l "Detached HEAD" 2>/dev/null || true)

if [[ -s "$STDERR_OUT" ]]; then
  fail "T1: stderr non-empty under headless (got: $(cat "$STDERR_OUT"))"
elif [[ -z "$DETACHED_HITS" ]]; then
  fail "T1: log file does not mention 'Detached HEAD' (logs: $(ls -la "$LOG_ROOT/logs" 2>/dev/null))"
else
  pass "T1: headless captured to log, stderr silent"
fi

# Foreground branch (TTY stderr → stderr emission) is covered by
# session-state.test.sh T8 against headless_or_stderr directly; not
# re-tested here because `script -q -c` cannot consistently create a pty
# under non-interactive harnesses (e.g., agent-shell, CI).

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
