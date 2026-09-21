#!/usr/bin/env bash
# Battery for scripts/lint-squash-ci-directives.sh.
#
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only). The directive
# tokens below are assembled from parts at runtime so that THIS FILE does not itself
# carry a literal CI-skip token — the lint under test scans commit messages, and a
# test file committed with the literal would be the defect it exists to catch.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
LINT="$ROOT/scripts/lint-squash-ci-directives.sh"
[[ -x "$LINT" || -r "$LINT" ]] || { printf 'FAIL: lint not found at %s\n' "$LINT" >&2; exit 1; }

passes=0; fails=0; asserted=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()  { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
ck()  { asserted=$((asserted + 1)); }

# Assemble the tokens from parts so this file carries no literal directive.
OB='['; CB=']'; SK='skip'; CI='ci'; NO='no'; ACT='actions'; ST='***'; NCI='NO_CI'
T_SKIP_CI="${OB}${SK} ${CI}${CB}"
T_CI_SKIP="${OB}${CI} ${SK}${CB}"
T_NO_CI="${OB}${NO} ${CI}${CB}"
T_SKIP_ACTIONS="${OB}${SK} ${ACT}${CB}"
T_ACTIONS_SKIP="${OB}${ACT} ${SK}${CB}"
T_NO_CI_STARS="${ST}${NCI}${ST}"

run_text() { # run_text <file-content> -> sets RC and OUT
  local content="$1" f="$TMP/case.$RANDOM.txt"
  printf '%s\n' "$content" > "$f"
  OUT="$(bash "$LINT" --text-file "$f" 2>&1)"; RC=$?
}

expect_fail() { # expect_fail <label> <content>
  ck; run_text "$2"
  if [[ "$RC" -eq 1 ]] && grep -q '^FAIL ' <<<"$OUT"; then ok "$1 -> refused (rc=1)";
  else bad "$1 -> expected rc=1 with a FAIL line, got rc=$RC :: $(head -2 <<<"$OUT" | tr '\n' ' ')"; fi
}

expect_pass() { # expect_pass <label> <content>
  ck; run_text "$2"
  if [[ "$RC" -eq 0 ]]; then ok "$1 -> accepted (rc=0)";
  else bad "$1 -> expected rc=0, got rc=$RC :: $(head -2 <<<"$OUT" | tr '\n' ' ')"; fi
}

printf '=== every canonical token is refused ===\n'
expect_fail "token skip-ci"      "feat: a change${T_SKIP_CI}"
expect_fail "token ci-skip"      "feat: a change ${T_CI_SKIP}"
expect_fail "token no-ci"        "feat: a change ${T_NO_CI}"
expect_fail "token skip-actions" "feat: a change ${T_SKIP_ACTIONS}"
expect_fail "token actions-skip" "feat: a change ${T_ACTIONS_SKIP}"
expect_fail "token NO_CI stars"  "feat: a change ${T_NO_CI_STARS}"

printf '=== the #8405 shape: token buried deep in prose, mid-line ===\n'
BURIED="fix(x): something
$(for i in $(seq 1 40); do printf 'filler line %s explaining an unrelated diagnosis\n' "$i"; done)
Not caused by my commits (no ${T_SKIP_CI} in any message), not the workflow file.
$(for i in $(seq 1 40); do printf 'more filler %s\n' "$i"; done)"
expect_fail "buried at line ~42 of a long body" "$BURIED"

printf '=== legitimate prose that must stay writable ===\n'
expect_pass "hyphenated skip-ci"        "fix: describe the skip-ci family without tripping the gate"
expect_pass "named as a class"          "docs: the CI-skip directives suppress push-triggered workflows"
expect_pass "ordinary commit"           "feat(kb): add a glossary and a rejected-concepts record"
expect_pass "bracketed but not a token" "chore: [skip formatting] is not a CI directive"
expect_pass "ci mentioned bare"         "ci: make the required test context blocking"

printf '=== argument handling ===\n'
ck; OUT="$(bash "$LINT" --text-file "$TMP/definitely-absent.txt" 2>&1)"; RC=$?
if [[ "$RC" -eq 2 ]]; then ok "unreadable --text-file -> rc=2 (cannot-evaluate, not a pass)";
else bad "unreadable --text-file -> expected rc=2, got rc=$RC"; fi

ck; OUT="$(bash "$LINT" --bogus-flag 2>&1)"; RC=$?
if [[ "$RC" -eq 2 ]]; then ok "unknown flag -> rc=2";
else bad "unknown flag -> expected rc=2, got rc=$RC"; fi

ck; OUT="$(bash "$LINT" --base refs/heads/definitely-no-such-ref-8405 2>&1)"; RC=$?
if [[ "$RC" -eq 2 ]] && grep -q 'not found' <<<"$OUT"; then
  ok "missing base ref -> rc=2 and says the commit surface was NOT scanned"
else bad "missing base ref -> expected rc=2 naming the unscanned surface, got rc=$RC :: $(head -2 <<<"$OUT" | tr '\n' ' ')"; fi

printf '=== the lint reports WHERE, not just THAT ===\n'
ck; run_text "feat: x${T_SKIP_CI}"
if grep -q 'text-file:' <<<"$OUT"; then ok "finding names its surface";
else bad "finding does not name its surface :: $(head -2 <<<"$OUT" | tr '\n' ' ')"; fi

ck; run_text "feat: x${T_SKIP_CI}"
if grep -qE 'REMEDY|Escape it|skip-ci' <<<"$OUT"; then ok "refusal carries an escaping remedy, not just a ban";
else bad "refusal lacks the remedy block"; fi

printf '=== token set does not drift from lint-bot-synthetic-statuses.sh ===\n'
ck
A="$(grep -oE "\\\\\[\(skip ci[^']*" "$LINT" | head -1)"
B="$(grep -oE "\\\\\[\(skip ci[^']*" "$ROOT/scripts/lint-bot-synthetic-statuses.sh" | head -1)"
if [[ -n "$A" && -n "$B" && "$A" == "$B" ]]; then
  ok "DRIFT: both lints carry a byte-identical token regex"
elif [[ -z "$A" || -z "$B" ]]; then
  bad "DRIFT: could not extract the regex from one or both lints (A='${A:0:30}' B='${B:0:30}') — the comparison is vacuous, fix the extraction"
else
  bad "DRIFT: token regexes differ — GitHub honours one set, so they must match. A='$A' B='$B'"
fi

printf '=== NEGATIVE CONTROL: the battery can actually fail ===\n'
# Drives the expect_pass PREDICATE against a fixture that must not pass, proving the
# accept path is not unconditionally true. Run in a subshell so the control's own
# verdict does not pollute the counters; only its rc is read.
ck
CTRL_RC="$( ( run_text "x${T_SKIP_CI}"; printf '%s' "$RC" ) )"
if [[ "$CTRL_RC" == "1" ]]; then ok "control: a token-bearing fixture does NOT pass (rc=1)";
else bad "control: a token-bearing fixture returned rc=$CTRL_RC — the accept path is vacuous"; fi

# ADR-193 anti-vacuity floor. MIN_ASSERTIONS is derived, and the substitution that
# a mutation would make (emptying the counter) leaves the fallback in place.
# 7 refusals + 5 acceptances + 3 argument cases + 2 message-shape + 1 drift + 1 control.
EXPECTED_ASSERTIONS=19
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: executed %s assertion(s), floor is %s — the battery shrank.\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\nlint-squash-ci-directives.test.sh: %s passed, %s failed, %s assertion(s) executed (floor %s)\n' \
  "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS"
[[ "$fails" -eq 0 ]] || exit 1
exit 0
