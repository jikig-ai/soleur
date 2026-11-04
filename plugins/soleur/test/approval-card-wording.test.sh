#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # A && B || C is the assertion idiom; the grep patterns are single-quoted on purpose
# PR-A of #12011 (founder approval cards): pins the wording contract in
# plugins/soleur/skills/brainstorm-techniques/references/approval-card.md.
#
# What it proves: the two fixed messages are present word for word and labelled; the "which message applies" table has its five
# situations IN ORDER (classification before session, first match wins) and each row names the message it prints; the no-default
# and recorded-as-Yes rules sit in section 1; `tty-ack` is the only method label the verifier accepts; the card avoids the
# assurance words; and standing-delegation.md points at the card. Reads files only: no network, no scratch directories.
set -uo pipefail

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
set +e

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
REFS="$REPO_ROOT/plugins/soleur/skills/brainstorm-techniques/references"
CARD="$REFS/approval-card.md"
SD="$REFS/standing-delegation.md"
VERIFIER="$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh"

# --- instrument self-test: the assertion helper must be able to FAIL --------------------------------
( assert_contains "abc" "zz-no-such-text-zz" "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_contains cannot fail -- dispatch is neutered\n' >&2; exit 2; }
FAIL=0; PASS=0

for f in "$CARD" "$SD" "$VERIFIER"; do
  [[ -s "$f" ]] || { echo "  FAIL: missing or empty: $f"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }
done

SEC1="$(awk '/^## 1\./ { on = 1; next } /^## 2\./ { on = 0 } on' "$CARD")"
SEC2="$(awk '/^## 2\./ { on = 1; next } /^## 3\./ { on = 0 } on' "$CARD")"
CARD_FLAT="$(tr '\n' ' ' < "$CARD" | tr -s ' ')"
SEC1_FLAT="$(printf '%s' "$SEC1" | tr '\n' ' ' | tr -s ' ')"
SEC2_FLAT="$(printf '%s' "$SEC2" | tr '\n' ' ' | tr -s ' ')"

echo "=== The two fixed messages, word for word and labelled ==="
BROWSER='This needs your answer in the Soleur app: <link>. Nothing was done. I will carry on with anything that does not depend on it.'
NOAPPR='This needs approval from you in a browser and no approver is set up. Nothing was done.'
assert_eq "1" "$(grep -cFx -- "$BROWSER" "$CARD")" "the browser-hold message appears exactly once, word for word"
assert_eq "1" "$(grep -cFx -- "$NOAPPR" "$CARD")" "the no-approver message appears exactly once, word for word"
assert_eq "Browser hold:" "$(grep -B3 -Fx -- "$BROWSER" "$CARD" | head -1)" "the browser-hold message sits under its label"
assert_eq "No approver set up:" "$(grep -B3 -Fx -- "$NOAPPR" "$CARD" | head -1)" "the no-approver message sits under its label"
assert_eq "0" "$(printf '%s\n%s\n' "$BROWSER" "$NOAPPR" | grep -ciE '#[0-9]|\.md|/|--|https?:')" "the two messages hold no issue number, path, flag or address"

echo "=== Section 1: the shape of the card and the no-default rules ==="
assert_contains "$SEC1_FLAT" "Pressing Enter on its own does nothing" "section 1 says Enter alone does nothing"
assert_contains "$SEC1_FLAT" "Please type the whole word: yes, no or changes." "section 1 refuses a single letter with the whole-word sentence"
assert_contains "$SEC1_FLAT" "in any letter case" "section 1 accepts the whole word in any letter case"
assert_contains "$SEC1_FLAT" "\`yes\` is recorded as \`Yes\`" "section 1 says yes is recorded as Yes"
assert_contains "$SEC1_FLAT" "it was not re-checked against your account" "section 1 prints the plain strength caveat after a yes"
assert_contains "$SEC1_FLAT" "The terminal session reported a typed yes" "section 1 reports what the session was told, not who typed"
assert_contains "$SEC1_FLAT" "\`no\` and \`changes\` record nothing" "section 1 says no and changes record nothing"
assert_contains "$SEC1_FLAT" "What would you like changed?" "changes asks what to change"
FIRST="$(printf '%s\n' "$SEC1" | grep -n 'What will happen, in business terms, first' | head -1 | cut -d: -f1)"
THIRD="$(printf '%s\n' "$SEC1" | grep -n 'The three choices, typed in words' | head -1 | cut -d: -f1)"
assert_eq "1" "$([[ -n "$FIRST" && -n "$THIRD" && "$FIRST" -lt "$THIRD" ]] && echo 1 || echo 0)" "the consequence item comes before the choices item"

echo "=== The decision table: five situations, in order, each names its outcome ==="
ROWS="$(printf '%s\n' "$SEC2" | awk '/^\| The step/ { t = 1; next } t && /^\|---/ { next } t && /^\|/ { print } t && !/^\|/ { t = 0 }')"
assert_eq "5" "$(printf '%s\n' "$ROWS" | grep -c '^|')" "the table has exactly five situation rows"
row_field() { printf '%s\n' "$ROWS" | sed -n "${1}p" | awk -F'|' -v n="$2" '{ gsub(/^ +| +$/, "", $n); print $n }'; }
ORDER_OK=1
i=0
for want in "Legal, irreversible or money-moving, and the founder has" "Legal, irreversible or money-moving, otherwise" "Reversible and delegable" "Reversible and delegable" "Anything else"; do
  i=$((i + 1)); [[ "$(row_field "$i" 2)" == "$want"* ]] || ORDER_OK=0
done
assert_eq "1" "$ORDER_OK" "the five rows start with the expected step classes, in that order"
assert_contains "$(row_field 1 4)" "browser-hold message" "row 1 (legal with a web approver) prints the browser-hold message"
assert_contains "$(row_field 2 4)" "no-approver message" "row 2 (legal otherwise) prints the no-approver message"
assert_contains "$(row_field 3 4)" "Asks nothing" "row 3 (nobody can answer) asks nothing"
assert_contains "$(row_field 4 4)" "tty-ack" "row 4 (person at a terminal) records tty-ack"
assert_contains "$(row_field 5 4)" "no-approver message" "row 5 (anything else) prints the no-approver message"
assert_contains "$(row_field 1 3)" "headless included" "row 1 applies in headless sessions too"
assert_contains "$(row_field 2 3)" "headless included" "row 2 applies in headless sessions too"
assert_contains "$SEC2_FLAT" "Piped, scripted or unknown input counts as nobody can answer" "section 2 defines how a person typing is detected"
assert_contains "$SEC2_FLAT" "never answered at \`tty-ack\` strength" "legal, irreversible and money steps are never answered at tty-ack strength"

echo "=== The method label: one accepted value, in step with the verifier ==="
assert_contains "$CARD_FLAT" "\`tty-ack\` is the only value a delegation comment may carry" "the card names tty-ack as the only comment label"
assert_contains "$CARD_FLAT" "never passes \`--method\` and never writes a \`Yes\`" "a session with nobody to answer never records the label or a Yes"
assert_eq "2" "$(grep -c '= tty-ack' "$VERIFIER")" "the verifier accepts the label at exactly two sites (verify and render). Pinned on purpose: a third accepted value must be added to the card and to the Method row in standing-delegation.md in the same change"

echo "=== Assurance wording stays out of the card ==="
assert_eq "0" "$(grep -ciE 'verified|reviewed|legally binding|audit-ready|compliant|proven|certified|guaranteed' "$CARD")" "approval-card.md carries none of the barred assurance words"

echo "=== The card is reachable from the delegation reference ==="
assert_eq "1" "$(grep -cF '(${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/approval-card.md)' "$SD")" "standing-delegation.md links approval-card.md exactly once, through the loader token (a CWD-relative link fails the plugin-root anchoring test)"
assert_contains "$(cat "$SD")" "[--method tty-ack]" "the render sentence shows the optional method flag"
assert_contains "$(grep -E '^\| Method \|' "$SD")" "method-unknown" "the Method row names the method-unknown reason"
assert_contains "$(grep -F '| `method-unknown` |' "$SD")" "I have not used it" "method-unknown has a plain sentence"

print_results 33
