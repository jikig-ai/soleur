#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # A && B || C is the assertion idiom; the grep patterns are single-quoted on purpose
# PR-A of #12011 (founder approval cards): pins the wording contract in
# plugins/soleur/skills/brainstorm-techniques/references/approval-card.md.
#
# What it proves: the two fixed messages are present word for word; the "which message applies" table has one row per
# situation and each row names the message it prints; the no-default rules are stated; `tty-ack` is the only method label
# and the card says it never makes a check lighter; the card and the messages avoid the assurance words the web copy is also
# barred from; and standing-delegation.md points at the card. Reads files only: no network, no scratch directories.
set -uo pipefail

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
set +e

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
REFS="$REPO_ROOT/plugins/soleur/skills/brainstorm-techniques/references"
CARD="$REFS/approval-card.md"
SD="$REFS/standing-delegation.md"
# prose wraps across lines, so phrase checks read the card with line breaks squashed to single spaces
CARD_FLAT="$(tr '\n' ' ' < "$CARD" | tr -s ' ')"

# --- instrument self-test: the row helper must be able to FAIL --------------------------------------
row_has() { # <text identifying the table row> <text that row must contain> <message>
  local row
  row="$(grep -F -- "$1" "$CARD" | grep -F '|' | head -1)"
  assert_contains "$row" "$2" "$3"
}
( row_has "zz-no-such-row-zz" "x" "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: row_has cannot fail -- dispatch is neutered\n' >&2; exit 2; }
FAIL=0; PASS=0

[[ -s "$CARD" ]] || { echo "  FAIL: approval-card.md is missing or empty"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }
[[ -s "$SD" ]] || { echo "  FAIL: standing-delegation.md is missing"; FAIL=$((FAIL + 1)); print_results 1; exit 1; }

echo "=== The two fixed messages, word for word ==="
BROWSER='This needs your answer in the Soleur app: <link>. Nothing was done. I will carry on with anything that does not depend on it.'
NOAPPR='This needs approval from you in a browser and no approver is set up. Nothing was done.'
grep -Fxq -- "$BROWSER" "$CARD" && { echo "  PASS: the browser-hold message is present word for word"; PASS=$((PASS + 1)); } \
  || { echo "  FAIL: the browser-hold message is missing or changed"; FAIL=$((FAIL + 1)); }
grep -Fxq -- "$NOAPPR" "$CARD" && { echo "  PASS: the no-approver message is present word for word"; PASS=$((PASS + 1)); } \
  || { echo "  FAIL: the no-approver message is missing or changed"; FAIL=$((FAIL + 1)); }
assert_eq "1" "$(grep -cFx -- "$BROWSER" "$CARD")" "the browser-hold message appears exactly once"
assert_eq "1" "$(grep -cFx -- "$NOAPPR" "$CARD")" "the no-approver message appears exactly once"

echo "=== The no-default rules ==="
assert_contains "$CARD_FLAT" "Pressing Enter on its own does nothing" "the card says Enter alone does nothing"
assert_contains "$CARD_FLAT" "Please type the whole word: yes, no or changes." "a single letter is refused with the whole-word sentence"
assert_contains "$CARD_FLAT" "\`changes\` records nothing" "changes records nothing"
assert_contains "$CARD_FLAT" "What would you like changed?" "changes asks what to change"
assert_contains "$CARD_FLAT" "Show them after the consequence, never before it." "the consequence comes before the choices"

echo "=== The decision table: one row per situation, each names its message ==="
row_has "Reversible and delegable" "tty-ack" "a person at a terminal on a reversible step records the tty-ack label"
row_has "Reversible and delegable" "Shows the card" "a person at a terminal on a reversible step gets the card"
row_has "Headless or cloud" "Asks nothing" "a headless or cloud session asks nothing"
row_has "Headless or cloud" "hold stands" "a headless or cloud session leaves the hold standing"
row_has "the founder has a web account" "browser-hold message" "a founder with a web account gets the browser-hold message"
row_has "the founder has a web account" "carries on with work that does not depend" "the browser-hold row lets unrelated work continue"
row_has "no approver is set up" "no-approver message" "no approver set up gets the no-approver message"
row_has "no approver is set up" "does nothing" "no approver set up does nothing"
assert_eq "4" "$(grep -cE '^\| (A person is typing|Headless or cloud|Any session)' "$CARD")" "the table has exactly four situation rows"

echo "=== The method label ==="
assert_contains "$CARD_FLAT" "\`tty-ack\` is the only value a delegation comment may carry" "tty-ack is the only comment label"
assert_contains "$CARD_FLAT" "never makes any check lighter" "the label never makes a check lighter"
assert_contains "$CARD_FLAT" "a comment that claims it is refused" "a comment claiming web-session is refused"
assert_eq "1" "$(grep -ciE 'Legal, irreversible and money-moving steps are never answered at .tty-ack. strength' "$CARD")" "legal, irreversible and money steps are never answered at tty-ack strength"

echo "=== Assurance wording stays out of the card and its messages ==="
assert_eq "0" "$(grep -ciE 'verified|reviewed|legally binding|audit-ready|compliant' "$CARD")" "approval-card.md carries none of the barred assurance words"
assert_eq "0" "$(printf '%s\n%s\n' "$BROWSER" "$NOAPPR" | grep -ciE '#[0-9]|\.md|/|--|https?:')" "the two messages hold no issue number, path, flag or address"

echo "=== The card is reachable from the delegation reference ==="
assert_eq "1" "$(grep -cF '(./approval-card.md)' "$SD")" "standing-delegation.md links approval-card.md exactly once"
assert_contains "$(cat "$SD")" "--method tty-ack" "standing-delegation.md says the calling skill passes --method tty-ack"
assert_contains "$(grep -E '^\| Method \|' "$SD")" "method-unknown" "the Method row names the method-unknown reason"
assert_contains "$(grep -F '| `method-unknown` |' "$SD")" "I have not used it" "method-unknown has a plain sentence"

print_results 28
