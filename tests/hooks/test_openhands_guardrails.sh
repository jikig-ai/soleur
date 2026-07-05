#!/usr/bin/env bash
# Smoke test for the OpenHands guardrails mirror (.openhands/hooks/guardrails.sh).
#
# The Claude hook (.claude/hooks/guardrails.sh) is exhaustively covered by
# guardrails.test.sh; the OpenHands port is a hand-written mirror with a
# DIFFERENT protocol (exit 2 + {"decision":"deny","reason":…}), an inlined
# cwd-resolution preamble, and a cross-tree source of the shared freeze-lock.sh.
# None of that was exercised by any suite before #5988's review. This smoke test
# locks the safety-critical behavior of the mirror: protected-delete deny,
# non-protected allow, variable/wrapper-form deny, and the freeze edit-lock over
# the file_editor tool — so a break in the deny() wiring or the cross-tree source
# path fails CI instead of silently disarming the OpenHands guard.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.openhands/hooks/guardrails.sh"
FREEZE_HELPER="$REPO_ROOT/.claude/hooks/lib/freeze-lock.sh"

pass=0; fail=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

# Run the hook, echo "<exit>:<decision-or-none>".
run() {
  local payload="$1" cwd="$2" home="${3:-$HOME}" froot="${4:-}" out rc dec
  out="$(cd "$cwd" 2>/dev/null && printf '%s' "$payload" \
    | HOME="$home" FREEZE_LOCK_REPO_ROOT="$froot" bash "$HOOK" 2>/dev/null)"; rc=$?
  if [[ -z "${out//[[:space:]]/}" ]]; then dec="<none>"; else
    dec="$(echo "$out" | jq -r '.decision // "<none>"' 2>/dev/null || echo "<jqfail>")"; fi
  echo "${rc}:${dec}"
}
mk_term() { jq -nc --arg c "$1" --arg d "$2" '{tool_input:{command:$c}, working_dir:$d}'; }
mk_edit() { jq -nc --arg p "$1" '{tool_input:{path:$p}}'; }

check() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then pass=$((pass+1)); echo "[ok] $label → $got"
  else fail=$((fail+1)); echo "[FAIL] $label — want $want got $got" >&2; fi
}

AD="$(mktemp -d)"; git init -q "$AD/repo"; mkdir -p "$AD/repo/node_modules" "$AD/other/.git"
ADHOME="$(mktemp -d)"

# Delete guard — protected targets deny (exit 2), non-protected allow (exit 0).
check "delete: repo root denies"        "2:deny"   "$(run "$(mk_term "rm -rf $AD/repo" "$AD/repo")" "$AD/repo")"
check "delete: .git-bearing dir denies" "2:deny"   "$(run "$(mk_term "rm -rf $AD/other" "$AD")" "$AD")"
check "delete: node_modules allows"     "0:<none>" "$(run "$(mk_term "rm -rf node_modules" "$AD/repo")" "$AD/repo")"
check "delete: literal \$HOME denies"    "2:deny"   "$(run "$(mk_term 'rm -rf $HOME' "$AD/repo")" "$AD/repo" "$ADHOME")"
check "delete: /bin/rm repo root denies" "2:deny"   "$(run "$(mk_term "/bin/rm -rf $AD/repo" "$AD/repo")" "$AD/repo")"

# Terminal sentinel still fires (freeze/delete additions do not shadow it).
# require-milestone fires unconditionally on `gh issue create` without
# --milestone (the OpenHands block-stash gate, by contrast, is cwd-gated to
# .worktrees paths — a pre-existing port difference — so it is not a portable
# non-shadow probe here).
check "terminal: gh issue create no-milestone denies" "2:deny" \
  "$(run "$(mk_term 'gh issue create --title x --body y' "$AD/repo")" "$AD/repo")"
check "terminal: benign ls allows"      "0:<none>" "$(run "$(mk_term 'ls -la' "$AD/repo")" "$AD/repo")"

# Freeze edit-lock over file_editor (path). Activate via the shared CLI.
FZ="$(mktemp -d)"; mkdir -p "$FZ/apps" "$FZ/other"
FREEZE_LOCK_REPO_ROOT="$FZ" bash "$FREEZE_HELPER" set "$FZ/apps" >/dev/null 2>&1
check "freeze: edit outside prefix denies" "2:deny"   "$(run "$(mk_edit "$FZ/other/x.ts")" "$FZ" "$HOME" "$FZ")"
check "freeze: edit inside prefix allows"  "0:<none>" "$(run "$(mk_edit "$FZ/apps/x.ts")" "$FZ" "$HOME" "$FZ")"

rm -rf "$AD" "$ADHOME" "$FZ"

echo
echo "=== openhands-guardrails: $pass passed, $fail failed ==="
[[ $fail -eq 0 ]] || exit 1
