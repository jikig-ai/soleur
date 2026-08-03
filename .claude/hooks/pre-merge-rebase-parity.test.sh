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
#
# Compared as a FIXED string (grep -qF), not an ERE. The matcher now contains
# `(`, `)`, `[`, `^`, `*`, `?` and a literal backslash for the optional
# conventional-commit scope; hand-escaping all of that into a regex-matching-a-
# regex is where the assertion silently rots. -F also makes the parity check
# exact — byte-for-byte, which is what "both copies carry the same matcher"
# means — and matches the trailer-lookup check below. A comment cannot produce
# the full `grep -E "..."` call, so the anti-drift property above is preserved.
SIG2_CALL='grep -E "^[a-f0-9]+ (refactor: add code review findings|review(\([^)]*\))?: )"'
for hook in "$CLAUDE_HOOK" "$OPENHANDS_HOOK"; do
  name="$(basename "$(dirname "$(dirname "$hook")")")"
  if grep -qF -- "$SIG2_CALL" "$hook"; then
    pass "[$name] Signal 2 uses the anchored two-pattern alternation"
  else
    fail "[$name] Signal 2 drift — expected the anchored alternation matching the legacy subject and 'review: ' with an optional (scope)"
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


# ===========================================================================
# ENVELOPE PARITY — the trust boundary, not just the merge gate (#7173).
# ===========================================================================
# The three cases below make the two harnesses' ENVELOPE handling executable.
# Until now the divergence was documented in prose and asserted nowhere, which
# is the same structural blindness the merge-gate half of this file exists to
# fix — this file's own header records that silent divergence has happened
# twice already.
#
# The two protocols differ by design and the cases assert the DIFFERENCE, not a
# false symmetry:
#
#   reason class      .claude                    .openhands
#   ----------------  -------------------------  --------------------------
#   nonstring         ask   (ADR-157)            deny  (no `ask` exists here)
#   unparseable       ask                        deny
#   jq_missing        ask, printf envelope       fail OPEN, loudly
#   absent tool_input parses cleanly             parses cleanly
#
# The `unparseable` row is written against MEASURED behaviour. An earlier draft
# of this case asserted the mirror "falls through" on an unparseable envelope
# and would have PASSED while asserting the opposite of the truth: the mirror's
# own `unparseable` branch is unreachable (it requires the shape program to fail
# on a document the simpler extractions already parsed), and before #7173 a
# malformed document did not fall through at all — it aborted the script at rc 5
# with no decision. Asserting "no deny on stdout" would have been satisfied by
# that abort. It is asserted as a deny because that is what the mirror now does.
#
# `envelope_verdict` deliberately does NOT normalise the two protocols the way
# `denied` above does: which harness denies and which asks IS the property.
envelope_verdict() { # <hook> <payload> -> deny|ask|none|<other>
  local hook="$1" payload="$2" out
  out=$(printf '%s' "$payload" | "$hook" 2>/dev/null) || true
  jq -r '(.hookSpecificOutput.permissionDecision // .decision // "none")' 2>/dev/null <<<"$out" \
    || echo "none"
}

CLAUDE_GUARD="$SCRIPT_DIR/guardrails.sh"
OPENHANDS_GUARD="$REPO_ROOT/.openhands/hooks/guardrails.sh"

# A lone high surrogate in a SIBLING field. The command itself stays a clean,
# fully-armed `rm -rf $HOME` — so this is not a malformed-command case, it is a
# case where the guard cannot read an envelope that carries a live command.
# OpenHands is Python: json.dumps re-emits \ud800, so the document is valid to
# its parser and invalid to jq.
SURROGATE_PAYLOAD="$(python3 -c 'import sys; sys.stdout.write("{\"working_dir\":\"\\ud800\",\"cwd\":\"/tmp\",\"tool_input\":{\"command\":\"rm -rf $HOME\"}}")' 2>/dev/null)"

if [[ -z "$SURROGATE_PAYLOAD" ]]; then
  echo "  SKIP: python3 missing — unparseable-envelope parity case"
else
  v="$(envelope_verdict "$CLAUDE_GUARD" "$SURROGATE_PAYLOAD")"
  [[ "$v" == "ask" ]] && pass "[.claude] unparseable envelope ASKS (ADR-157)" \
                      || fail "[.claude] unparseable envelope: want ask, got $v"
  v="$(envelope_verdict "$OPENHANDS_GUARD" "$SURROGATE_PAYLOAD")"
  [[ "$v" == "deny" ]] && pass "[.openhands] unparseable envelope DENIES (no ask in this protocol)" \
                       || fail "[.openhands] unparseable envelope: want deny, got $v — before #7173 this aborted at rc 5 with NO decision at all"
fi

# Non-string: the original ADR-156 signature. Both must refuse to coerce; they
# refuse with different verbs.
NONSTRING_PAYLOAD='{"working_dir":"/tmp","cwd":"/tmp","tool_input":{"command":["git","stash"]}}'
v="$(envelope_verdict "$CLAUDE_GUARD" "$NONSTRING_PAYLOAD")"
[[ "$v" == "ask" ]] && pass "[.claude] non-string command ASKS" \
                    || fail "[.claude] non-string command: want ask, got $v"
v="$(envelope_verdict "$OPENHANDS_GUARD" "$NONSTRING_PAYLOAD")"
[[ "$v" == "deny" ]] && pass "[.openhands] non-string command DENIES" \
                     || fail "[.openhands] non-string command: want deny, got $v"

# Absent / null tool_input. This is the case NEITHER of the two divergence
# classes above would catch, and the mirror got it wrong in the AVAILABILITY
# direction: its type conjunct read `$t == null` where jq's `type` returns the
# STRING "null", so the comparison was unsatisfiable and every payload with an
# absent or null tool_input was DENIED — on a harness with no `ask` and no
# recovery path, while .claude parsed the same payloads cleanly.
for payload in '{"working_dir":"/tmp","cwd":"/tmp"}' '{"working_dir":"/tmp","cwd":"/tmp","tool_input":null}'; do
  label="$([[ "$payload" == *tool_input* ]] && echo "null" || echo "absent")"
  v="$(envelope_verdict "$CLAUDE_GUARD" "$payload")"
  [[ "$v" != "deny" ]] && pass "[.claude] $label tool_input is not denied ($v)" \
                       || fail "[.claude] $label tool_input was DENIED — absence is legitimate"
  v="$(envelope_verdict "$OPENHANDS_GUARD" "$payload")"
  [[ "$v" != "deny" ]] && pass "[.openhands] $label tool_input is not denied ($v)" \
                       || fail "[.openhands] $label tool_input was DENIED — the unsatisfiable \$t == null conjunct is back"
done

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
