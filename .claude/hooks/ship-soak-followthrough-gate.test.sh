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

# ADR-129 rule (c): ONE owning trap for every tempfile this suite allocates.
# Per-case sandboxes are children of this root, so a case that dies mid-assertion
# cannot leak — /tmp is a machine-global tmpfs shared with sibling worktrees.
HIC_TMPROOT="$(mktemp -d -t ssfgroot.XXXXXXXX)"
trap 'rm -rf "$HIC_TMPROOT"' EXIT

# A git fixture with an explicit branch: CI-on-main masks branch-dependent
# sibling gates (#5192), so the branch is set rather than inherited.
mk_repo() {
  local d; d="$(mktemp -d -p "$HIC_TMPROOT")"
  git -C "$d" init -q -b feat-fixture
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}

# A `gh` stub keeps the gate off the network. Default: report no PR, which is
# the hook's documented "cannot read PR body" fail-open branch.
mk_gh_stub() {
  local d="$1" mode="${2:-nopr}"
  mkdir -p "$d/stub"
  # The stub VALIDATES argv rather than answering unconditionally. A fake that
  # dispatches on nothing puts the fixture seam ABOVE the code under test: it
  # cannot detect the gate querying the WRONG thing, so a change from `gh pr
  # view` to some other subcommand would keep the suite green. `exit 64` on an
  # unrecognised invocation makes a wrong query a loud failure.
  # (.claude/hooks/stub-argv-fidelity.test.sh enforces this class repo-wide.)
  cat > "$d/stub/gh" <<'STUB'
#!/usr/bin/env bash
ARGS="$*"
case "$1" in
  pr|issue) ;;
  *) echo "gh-stub: unexpected subcommand: $ARGS" >&2; exit 64 ;;
esac
case "$ARGS" in
  *view*) ;;
  *) echo "gh-stub: expected a 'view' read, got: $ARGS" >&2; exit 64 ;;
esac

# `issue view` answers describe an OPEN, entirely UNENROLLED tracker — the state
# that makes the gate deny. Any ref reaching this branch therefore denies, which
# is what lets the closing-target cases below prove the fix by their verdict
# alone: if the filter stopped working, the ref would arrive here and flip the
# expected allow into a deny.
if [[ "$1" == "issue" ]]; then
  # Emit the --jq-PROJECTED scalar, not the raw JSON envelope: the gate reads
  # these through `--jq .state` / `--jq '[.labels[].name]|join(",")'`, so a stub
  # answering `{"state":"OPEN"}` yields a $state that never equals OPEN and the
  # tracker is skipped as closed — turning the deny-path control green-by-accident.
  case "$ARGS" in
    *--json\ state*)  printf '%s\n' 'OPEN' ;;
    *--json\ labels*) printf '%s\n' '' ;;
    *--json\ body*)   printf '%s\n' '' ;;
    *) echo "gh-stub: unexpected issue read: $ARGS" >&2; exit 64 ;;
  esac
  exit 0
fi

case "${MODE:-nopr}" in
  nopr)   exit 1 ;;                                            # no PR readable
  nosoak) printf '%s\n' '{"body":"ordinary PR body with no soak signal"}' ;;
  # Soak signal + the SAME issue named as both the closing target and a `Ref`.
  # This is PR #7426's shape: the plan discussed `Ref #7409` inside a rejected
  # counterfactual while the PR closes #7409.
  soakcloses) printf '%s\n' '{"body":"Closes #7409\n\nPost-deploy soak: none. Ref #7409 would apply only under the split we rejected."}' ;;
  # Control: a genuine third-party tracker alongside the closing target. The
  # closing target drops out; #9999 must NOT, or the fix has disabled the gate
  # rather than narrowed it.
  soakother) printf '%s\n' '{"body":"Closes #7409\n\nPost-deploy soak holds. Ref #9999 tracks the soak."}' ;;
  *)      echo "gh-stub: unknown MODE=${MODE:-}" >&2; exit 64 ;;
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

# --- closing target is never an enrollable soak tracker (PR #7426) ----------
# The carve-out is reasoned at issue level but was implemented at mention level,
# so one `Ref #N` re-added the PR's own `Closes` target and restored the #7278
# deadlock. These two cases pin the ISSUE-level reading. They are a matched
# pair on purpose: the first alone would also pass if the filter dropped every
# ref, which would silently disable the gate.
check "closing target named by BOTH Closes and Ref → allows" "<none>" \
  "$(decision_of 'gh pr ready' "$REPO" soakcloses)"
check "third-party unenrolled tracker still DENIES (fix narrows, not disables)" "deny" \
  "$(decision_of 'gh pr ready' "$REPO" soakother)"

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
