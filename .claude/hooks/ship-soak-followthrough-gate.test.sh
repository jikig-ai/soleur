#!/usr/bin/env bash
# Sibling suite for ship-soak-followthrough-gate.sh.
#
# Written for #7164: this hook was one of two in-scope hooks with NO sibling
# suite, so nothing asserted its characteristic behaviour and a break in its
# wiring would have been silent.
#
# COVERAGE IS PARTIAL AND SAID SO OUT LOUD. The deny path needs a real PR body
# carrying a soak signal plus a resolvable open tracker, which means a
# multi-response `gh` stub. What is covered here:
#   - the trigger predicate (which commands the gate intercepts at all)
#   - every documented FAIL-OPEN branch, driven through a `gh` stub
#   - the #7164 envelope contract
# The deny path itself remains covered by ship/SKILL.md's gate and the agent, as
# the hook header already states. Degrading that to "fail-open, as expected"
# silently would be the failure mode this file exists to avoid.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-soak-followthrough-gate.sh"

PASS=0; FAIL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

# A git fixture with an explicit branch: CI-on-main masks branch-dependent
# sibling gates (#5192), so the branch is set rather than inherited.
mk_repo() {
  local d; d="$(mktemp -d -t ssfg.XXXXXXXX)"
  git -C "$d" init -q -b feat-fixture
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}

# A `gh` stub keeps the gate off the network. Default: report no PR, which is
# the hook's documented "cannot read PR body" fail-open branch.
mk_gh_stub() {
  local d="$1" mode="${2:-nopr}"
  mkdir -p "$d/stub"
  cat > "$d/stub/gh" <<STUB
#!/usr/bin/env bash
case "\$MODE" in
  nopr)   exit 1 ;;
  nosoak) echo '{"body":"ordinary PR body with no soak signal"}' ;;
  *)      exit 1 ;;
esac
STUB
  chmod +x "$d/stub/gh"
  echo "$d/stub"
}

decision_of() { # <command-string> <repo> <gh-mode>
  local cmd="$1" repo="$2" mode="${3:-nopr}" stub out
  stub="$(mk_gh_stub "$repo" "$mode")"
  out="$(cd "$repo" && jq -nc --arg c "$cmd" --arg d "$repo" \
          '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' \
        | PATH="$stub:$PATH" MODE="$mode" INCIDENTS_REPO_ROOT="$repo" bash "$HOOK" 2>/dev/null)"
  [[ -z "${out//[[:space:]]/}" ]] && { echo "<none>"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}
check() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS: $label → $got"
  else FAIL=$((FAIL+1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"; fi
}

REPO="$(mk_repo)"

# --- trigger predicate: what the gate intercepts at all ---------------------
check "unrelated command allows"           "<none>" "$(decision_of 'ls -la' "$REPO")"
check "git commit allows (not a merge)"    "<none>" "$(decision_of 'git commit -m x' "$REPO")"
check "gh pr merge WITHOUT --auto allows"  "<none>" "$(decision_of 'gh pr merge 1 --squash' "$REPO")"

# --- documented fail-open branches -----------------------------------------
check "gh pr ready, no PR readable → fail-open" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" nopr)"
check "gh pr merge --auto, no PR readable → fail-open" "<none>" \
  "$(decision_of 'gh pr merge 1 --squash --auto' "$REPO" nopr)"
check "PR body carries no soak signal → fail-open" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" nosoak)"

# --- #7164 envelope contract ------------------------------------------------
# An ARRAY tool_input.command rendered across lines, matched the trigger regex
# nowhere, and slipped the gate. This hook is not the designated ask responder,
# so it stays silent on stdout — but it must record the fault rather than
# exiting 0 as if it had seen an ordinary non-merge command.
arr="$(jq -nc --arg d "$REPO" '{tool_name:"Bash", tool_input:{command:["gh","pr","ready"]}, cwd:$d}')"
out="$(cd "$REPO" && printf '%s' "$arr" | INCIDENTS_REPO_ROOT="$REPO" bash "$HOOK" 2>/dev/null)"
check "ARRAY command: no decision emitted (non-responder)" "" "${out//[[:space:]]/}"

if [[ -f "$REPO/.claude/.rule-incidents.jsonl" ]] \
   && grep -q 'hook-input-' "$REPO/.claude/.rule-incidents.jsonl" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS: ARRAY command records a hook-input fault (no silent disarm)"
else
  FAIL=$((FAIL+1)); echo "FAIL: ARRAY command disarmed the gate with no record"
fi

rm -rf "$REPO"

echo
echo "=== ship-soak-followthrough-gate: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
