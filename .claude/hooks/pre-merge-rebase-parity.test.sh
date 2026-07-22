#!/usr/bin/env bash
# Review-evidence gate PARITY across both hook copies (#6724).
#
# WHY THIS EXISTS
#
# `.claude/hooks/pre-merge-rebase.sh` and `.openhands/hooks/pre-merge-rebase.sh`
# implement the same merge gate for two harness ecosystems. Every other suite
# binds HOOK to the `.claude` copy, so the openhands copy had NO coverage at all
# and its divergence was structurally undetectable. That is not hypothetical:
#
#   * its Signal 2 matched only the legacy "refactor: add code review findings"
#     subject and had never gained the `review: ` fix-inline convention, so the
#     gate was silently weaker on that host for a long time; and
#   * its command matcher was missing the `\s--\s` alternative, so the
#     `with_lock ... -- gh pr merge` wrapped form bypassed the hook ENTIRELY.
#
# Both were found by review of #6727 and fixed. This suite is what stops them
# recurring. It deliberately tests only the shared gate contract, not the
# `.claude` copy's extra machinery (incident emission, lock acquisition,
# headless routing), which the openhands port does not have.
#
# PROTOCOL DIFFERENCE — the two copies deny differently, and the assertions
# below normalise it rather than assuming one shape:
#   .claude     input .cwd          -> exit 0, {"hookSpecificOutput":{"permissionDecision":"deny"}}
#   .openhands  input .working_dir  -> exit 2, {"decision":"deny"}
#
# Run via:  bash .claude/hooks/pre-merge-rebase-parity.test.sh
# Auto-discovered by scripts/test-all.sh via the `.claude/hooks/*.test.sh` glob
# in the `scripts` shard, which ci.yml runs — so this gates in CI.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_HOOK="$SCRIPT_DIR/pre-merge-rebase.sh"
OPENHANDS_HOOK="$REPO_ROOT/.openhands/hooks/pre-merge-rebase.sh"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq missing";  exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

for h in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  [[ -f "$h" ]] || { echo "FAIL: hook copy missing: $h"; exit 1; }
done

# denied <hook> <work_dir> <command> -> "yes" | "no"
# Normalises the two protocols. Sends BOTH input keys so one payload drives
# either copy.
denied() {
  local hook="$1" work="$2" cmd="$3" payload out
  payload=$(jq -nc --arg c "$work" --arg x "$cmd" \
    '{tool_input: {command: $x}, cwd: $c, working_dir: $c}')
  # Exit code is deliberately ignored: the two copies use different codes for
  # the same verdict (.claude exits 0 with a deny payload, .openhands exits 2).
  # The decision field is the shared contract.
  out=$(printf '%s' "$payload" | "$hook" 2>/dev/null) || true
  if jq -e '(.hookSpecificOutput.permissionDecision // .decision) == "deny"' >/dev/null 2>&1 <<<"$out"; then
    echo "yes"
  else
    echo "no"
  fi
}

# build_repo <dir> <mode>
#   unreviewed  — branch does real work, no review of any kind (gate MUST deny)
#   reviewed    — branch carries a Reviewed-By-Soleur trailer (gate MUST allow)
#   main-only   — evidence exists but only on MAIN, pre-fork (gate MUST deny)
build_repo() {
  local work="$1" mode="$2" origin="$3"
  mkdir -p "$work"
  git -C "$work" init -q
  git -C "$work" symbolic-ref HEAD refs/heads/main
  git -C "$work" config user.email t@t
  git -C "$work" config user.name t
  git -C "$work" config commit.gpgsign false
  echo base > "$work/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit -q -m init

  if [[ "$mode" == "main-only" ]]; then
    mkdir -p "$work/todos"
    echo "code-review" > "$work/todos/legacy.md"
    git -C "$work" add todos/legacy.md
    git -C "$work" commit -q -m "chore: long-lived review todo on main"
    git -C "$work" commit -q --allow-empty -m "review: findings from an older branch"
  fi

  git init -q --bare -b main "$origin"
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin HEAD:main
  git -C "$work" fetch -q origin

  git -C "$work" checkout -q -b feat-parity
  echo feature > "$work/feature.txt"
  git -C "$work" add feature.txt
  git -C "$work" commit -q -m "feat: work"

  if [[ "$mode" == "reviewed" ]]; then
    git -C "$work" commit -q --allow-empty -m "chore: post-review checkpoint

Reviewed-By-Soleur: soleur:review"
  fi
}

echo "=== pre-merge-rebase gate parity (.claude vs .openhands) ==="
echo ""

TMP=$(mktemp -d -t pmr-parity.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The three gate outcomes both copies must agree on.
i=0
for case_spec in \
  "unreviewed|yes|no review evidence -> DENY" \
  "reviewed|no|Reviewed-By-Soleur trailer -> ALLOW" \
  "main-only|yes|evidence only on MAIN (the #6724 vacuity) -> DENY" \
  ; do
  mode="${case_spec%%|*}"; rest="${case_spec#*|}"
  want="${rest%%|*}"; label="${rest#*|}"
  for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
    i=$((i + 1))
    work="$TMP/w$i"
    build_repo "$work" "$mode" "$TMP/o$i.git"
    got=$(denied "$hook" "$work" "gh pr merge 900 --squash")
    name="$(basename "$(dirname "$(dirname "$hook")")")"
    if [[ "$got" == "$want" ]]; then
      pass "[$name] $label"
    else
      fail "[$name] $label — expected denied=$want, got denied=$got"
    fi
  done
done

echo ""
echo "T-M: the wrapped form must be intercepted by BOTH copies"
# `bash session-state.sh with_lock merge-main 600 -- gh pr merge ...` was NOT
# matched by the openhands copy, so the whole hook exited before any check ran.
# An unreviewed branch under the wrapped form must still deny.
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  i=$((i + 1))
  work="$TMP/w$i"
  build_repo "$work" "unreviewed" "$TMP/o$i.git"
  got=$(denied "$hook" "$work" "bash session-state.sh with_lock merge-main 600 -- gh pr merge 901 --squash")
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if [[ "$got" == "yes" ]]; then
    pass "[$name] wrapped 'with_lock ... -- gh pr merge' is intercepted"
  else
    fail "[$name] wrapped form BYPASSED the gate — the \\s--\\s matcher alternative is missing"
  fi
done

echo ""
echo "T-S: both copies carry the same Signal 2 matcher"
# Source-level parity for the alternation itself. The behavioural cases above
# cannot distinguish "matches the legacy subject only" from "matches both" when
# the fixture happens to use the trailer.
#
# Anchored on the CALL SHAPE, not the bare tokens. A first draft of this block
# grepped for `review: ` as a substring and SURVIVED the mutation it exists to
# catch: reverting the openhands copy to the legacy-only matcher left the phrase
# `review: ` sitting in an explanatory COMMENT, which satisfied the grep. Same
# class this PR fixes elsewhere — a body-grep sees comments too, so assert on
# something a comment cannot produce.
SIG2_RE='grep -E "\^\[a-f0-9\]\+ \(refactor: add code review findings\|review: \)"'
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if grep -qE "$SIG2_RE" "$hook"; then
    pass "[$name] Signal 2 uses the anchored two-pattern alternation"
  else
    fail "[$name] Signal 2 drift — expected the anchored alternation matching BOTH the legacy subject and 'review: '"
  fi
done
# The trailer lookup must be present in both, anchored on the git format string
# rather than the bare key (which appears in prose in both files).
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if grep -qF -- "trailers:key=Reviewed-By-Soleur,valueonly" "$hook"; then
    pass "[$name] trailer lookup present"
  else
    fail "[$name] trailer lookup missing — a zero-finding review cannot satisfy this copy"
  fi
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
