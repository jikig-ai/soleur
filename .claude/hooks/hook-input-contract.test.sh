#!/usr/bin/env bash
# Contract tests for the PreToolUse hook input boundary (issue #7164).
#
# ADR-155 — hook stdin is model-controlled and untrusted; a hook must not depend
#           on an upstream invariant it cannot verify.
# ADR-156 — a hook that cannot fully parse its input ASKS. It never continues
#           silently and it never denies.
#
# Two of these assertions were authored and observed RED against the unmodified
# tree BEFORE the helper existed (plan Phase 2):
#
#   A1 idiom ban        — any `eval` under .claude/hooks/** and .openhands/hooks/**
#   A2 guard-still-armed — an array payload encoding a guarded command must ask
#
# A2 is the one that catches a coerce-and-continue fix. Coercing a non-string
# with `tojson` closes the RCE and leaves every anchored guard evaded:
# ["git","stash"] does not match the stash guard's regex, so the hook would
# allow. Authoring A2 after the migration is the failure mode the hooks README
# documents for stub-argv-fidelity — a test that could never be seen fail.
#
# Pure bash + jq. The test-scripts CI shard has no bun and no node.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

ok()   { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: $1"; shift; local l; for l in "$@"; do echo "  $l"; done; }
want() { # <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1 → $3"; else bad "$1" "want: $2" "got:  $3"; fi
}

# --- the 20 in-scope hooks -------------------------------------------------
EVAL10=(
  cla-signed-author-gate context-reviewed-gate follow-through-directive-gate
  guardrails prod-write-defer-gate ship-net-issue-flow-gate
  ship-operator-step-gate ship-runbook-ssh-gate ship-soak-followthrough-gate
  ship-unpushed-commits-gate
)
SIBLING8=(
  background-poll-prefer-monitor brand-hex-commit-gate
  doppler-secrets-delete-redirect git-commit-secret-scan
  kb-domain-allowlist-guard no-memory-write
  pre-merge-auto-close-scan pre-merge-rebase
)
WRITE2=( worktree-write-guard iac-plan-write-guard )
INSCOPE20=( "${EVAL10[@]}" "${SIBLING8[@]}" "${WRITE2[@]}" )

# Emit the hook's permissionDecision, or "<none>" when it allows (no JSON).
# Runs from a NON-GIT temp CWD so the orthogonal, branch-dependent
# block-commit-on-main gate resolves an empty branch and no-ops. Without this,
# these fixtures pass on a feature worktree and fail on main-CI (#5192).
decision_for() { # <hook-basename> <payload-json>
  local hook="$1" payload="$2" tmp out
  tmp="$(mktemp -d -t hic.XXXXXXXX)"
  out="$(cd "$tmp" && printf '%s' "$payload" \
        | INCIDENTS_REPO_ROOT="$tmp" bash "$SCRIPT_DIR/$hook.sh" 2>/dev/null)"
  rm -rf "$tmp"
  if [[ -z "${out//[[:space:]]/}" ]]; then echo "<none>"; return; fi
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}

# ===========================================================================
# A1 — idiom ban: ANY eval, not one spelling.
# ===========================================================================
# A ban pinned to `eval "$(` misses `eval $(…)`, `eval "$V"` and `eval "${x}"`.
# Full-line comments are stripped first: hook headers legitimately discuss the
# word "eval" in prose, and a body-grep sees comments too (cq-assert-anchor-not-
# bare-token). Everything else is scanned for `eval` in COMMAND-WORD position.
#
# Allow-list: the two fd-close lines in lib/session-state.sh, BY EXACT STRING.
# `eval "exec ${fd}>&-"` is the only portable way to close a dynamic fd in bash.
EVAL_ALLOW='eval "exec ${fd}>&-" 2>/dev/null || true'

a1_idiom_ban() {
  local offenders=() f line n stripped
  while IFS= read -r f; do
    [[ "$f" == *.test.sh ]] && continue
    stripped="$(sed 's/^[[:space:]]*#.*$//' "$f")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      n="${line%%:*}"; line="${line#*:}"
      local trimmed="${line#"${line%%[![:space:]]*}"}"
      if [[ "$trimmed" == "$EVAL_ALLOW" && "$f" == */lib/session-state.sh ]]; then
        continue
      fi
      offenders+=("${f#"$REPO_ROOT/"}:$n: $trimmed")
    done < <(printf '%s\n' "$stripped" | grep -nE '(^|[^[:alnum:]_])eval([[:space:]]|$)' || true)
  done < <(find "$REPO_ROOT/.claude/hooks" "$REPO_ROOT/.openhands/hooks" -name '*.sh' -type f 2>/dev/null | sort)

  if (( ${#offenders[@]} == 0 )); then
    ok "A1 no eval under .claude/hooks/** or .openhands/hooks/** (2 fd-close lines allow-listed)"
  else
    bad "A1 eval found in ${#offenders[@]} place(s) — hook stdin is untrusted (ADR-155)" "${offenders[@]}"
  fi
}

# ===========================================================================
# A2 — guard-still-armed: an ARRAY payload encoding a guarded command must ask.
# ===========================================================================
# RED on main today: jq @sh renders ["git","stash"] as COMMAND='git' 'stash',
# so `git` is an env-assignment prefix to the command `stash`, COMMAND is never
# set in the hook's own shell, `: "${COMMAND:=}"` defaults it empty, and the
# stash guard sees nothing. The hook ALLOWS the very command it exists to block.
#
# This assertion is also what rejects a `tojson` coercion fix: the coerced
# string ["git","stash"] matches no anchored guard regex either.
a2_guard_still_armed() {
  local payload got
  payload="$(jq -nc '{tool_name:"Bash", tool_input:{command:["git","stash"]}}')"
  got="$(decision_for guardrails "$payload")"
  want "A2 guardrails: array-encoded 'git stash' asks (never allow)" "ask" "$got"

  # The string form must still deny — proves the guard itself is intact and A2
  # is not passing because the hook broke outright (positive control).
  payload="$(jq -nc '{tool_name:"Bash", tool_input:{command:"git stash"}}')"
  got="$(decision_for guardrails "$payload")"
  want "A2 control: string 'git stash' still denies" "deny" "$got"
}

a1_idiom_ban
a2_guard_still_armed

echo
echo "=== hook-input-contract: $PASS/$TOTAL pass ==="
[[ "$FAIL" -eq 0 ]] || exit 1
