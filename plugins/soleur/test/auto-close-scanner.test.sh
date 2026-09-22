#!/usr/bin/env bash

# Tests for plugins/soleur/skills/ship/scripts/auto-close-scan.sh.
# Run: bash plugins/soleur/test/auto-close-scanner.test.sh
#
# The scanner detects GitHub auto-close keyword + #N references anywhere in PR
# title or body. GitHub's parser is markdown-blind — checkboxes, code blocks,
# and prose all auto-close. The scanner exists because two PRs (#3200, #3402)
# fell into the same trap within one session, the second while writing a
# learning file about the first (#3407).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
SCANNER="$REPO_ROOT/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
FIXTURES="$SCRIPT_DIR/fixtures/auto-close-scanner"

echo "=== auto-close-scanner tests ==="
echo ""

assert_file_exists "$SCANNER" "auto-close-scan.sh exists"
assert_file_exists "$FIXTURES/checkbox-trigger.txt" "checkbox-trigger fixture exists"
assert_file_exists "$FIXTURES/prose-trigger.txt"    "prose-trigger fixture exists"
assert_file_exists "$FIXTURES/safe-ref.txt"         "safe-ref fixture exists"
assert_file_exists "$FIXTURES/code-block-trigger.txt" "code-block-trigger fixture exists"
assert_file_exists "$FIXTURES/gh-form-trigger.txt"  "gh-form-trigger fixture exists"

if [[ ! -x "$SCANNER" && -f "$SCANNER" ]]; then
  chmod +x "$SCANNER"
fi

run_scan() {
  bash "$SCANNER" "$1" 2>/dev/null || true
}

count_lines() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    printf '%s\n' "$1" | wc -l | tr -d ' '
  fi
}

# --- TS1: checkbox trigger (the #3402 trap) ---
echo "TS1: '- [ ] Post-merge: close #3185' inside a checkbox triggers a match"
OUT=$(run_scan "$FIXTURES/checkbox-trigger.txt")
assert_eq "1" "$(count_lines "$OUT")" "checkbox-trigger produces exactly 1 match"
echo ""

# --- TS2: prose trigger ---
echo "TS2: 'will fix #1234' in prose triggers a match"
OUT=$(run_scan "$FIXTURES/prose-trigger.txt")
assert_eq "1" "$(count_lines "$OUT")" "prose-trigger produces exactly 1 match"
echo ""

# --- TS3: safe ref does NOT trigger ---
echo "TS3: 'Ref #N' and bare 'Closes' do not trigger"
OUT=$(run_scan "$FIXTURES/safe-ref.txt")
assert_eq "0" "$(count_lines "$OUT")" "safe-ref produces zero matches"
echo ""

# --- TS4: code-block trigger (markdown-blindness) ---
echo "TS4: 'Resolved #5678' inside a code fence still triggers (markdown is invisible to the parser)"
OUT=$(run_scan "$FIXTURES/code-block-trigger.txt")
assert_eq "1" "$(count_lines "$OUT")" "code-block-trigger produces exactly 1 match"
echo ""

# --- TS5: GH-N form ---
echo "TS5: 'close GH-4567' triggers a match (cross-repo form)"
OUT=$(run_scan "$FIXTURES/gh-form-trigger.txt")
assert_eq "1" "$(count_lines "$OUT")" "gh-form-trigger produces exactly 1 match"
echo ""

# --- TS6: case-insensitive (uppercase keyword still triggers) ---
echo "TS6: case-insensitive matching"
TMP_UPPER=$(mktemp); printf 'CLOSE #99 in shouty caps\n' > "$TMP_UPPER"
OUT=$(run_scan "$TMP_UPPER")
rm -f "$TMP_UPPER"
assert_eq "1" "$(count_lines "$OUT")" "uppercase 'CLOSE #99' triggers a match"
echo ""

# --- TS6b: complete keyword matrix (all 9 GitHub auto-close keywords) ---
# Closes the test-coverage gap surfaced by code-quality review F1: the regex
# claims to cover close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved
# but only 4 of the 9 are exercised by the named fixtures (close via TS6,
# fix via TS2 prose, resolved via TS4 code-block, GH-N via TS5). A future
# regex narrowing (e.g., dropping `[sd]?` to ship a "simpler" pattern) would
# pass the original 4-keyword set silently.
echo "TS6b: every GitHub auto-close keyword (close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved) triggers"
for kw in close closes closed fix fixes fixed resolve resolves resolved; do
  TMP_KW=$(mktemp); printf 'will %s #99 in prose\n' "$kw" > "$TMP_KW"
  OUT=$(run_scan "$TMP_KW")
  rm -f "$TMP_KW"
  assert_eq "1" "$(count_lines "$OUT")" "keyword '$kw' produces exactly 1 match"
done
echo ""

# --- TS7: line-number prefix in output ---
echo "TS7: scanner output is in 'lineno:matched-text' format for caller attribution"
OUT=$(run_scan "$FIXTURES/checkbox-trigger.txt")
if printf '%s\n' "$OUT" | grep -qE '^[0-9]+:'; then
  echo "  PASS: each match line is prefixed with 'lineno:'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: output should have 'lineno:matched-text' format; got: $OUT"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS8: scanner exits 0 even on match (fail-soft per #3407) ---
echo "TS8: scanner exits 0 even when matches found (fail-soft)"
bash "$SCANNER" "$FIXTURES/checkbox-trigger.txt" >/dev/null 2>&1
assert_eq "0" "$?" "scanner exit code is 0 on match (fail-soft, surfaces via stdout)"
echo ""

# --- TS9: negation-blind — a NEGATED keyword still matches (the #5564 trap) ---
# GitHub's auto-close parser ignores negation: "Does not close #N" closes #N.
# This is the exact commit-message line that closed #5463 prematurely via #5564.
# The scanner MUST flag it (catching the trap the human reader's eye glosses over).
echo "TS9: negation-blind — 'Does not close #5463' (the #5564 commit-message trap) still matches"
TMP_NEG=$(mktemp)
printf 'Smoke-tests the harness end-to-end.\nDoes not close #5463 (flip tracked separately).\n' > "$TMP_NEG"
OUT=$(run_scan "$TMP_NEG")
rm -f "$TMP_NEG"
assert_eq "1" "$(count_lines "$OUT")" "negated 'Does not close #5463' produces exactly 1 match"
echo ""

# --- TS10–TS13: split matches (the #8514 trap) ---
# GitHub treats the newline between keyword and reference as whitespace: a commit
# body wrapped as "...would auto-close" / "#8285, so..." closed #8285 on the
# squash-merge of #8514. One scratch dir; the trap also runs the helper's own
# sandbox cleanup, which a bare `trap ... EXIT` here would otherwise replace.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"; declare -F _soleur_sb_cleanup >/dev/null && _soleur_sb_cleanup' EXIT
F="$SCRATCH/in.txt"
scan_str() { printf '%b' "$1" > "$F"; run_scan "$F"; }

echo "TS10: the #8514 text, keyword on line 3 — exact record at the KEYWORD's line"
OUT=$(scan_str 'Summary.\n\nCorrects Guard 3: a probe that can exit 0 would auto-close\n#8285, so the probe is notify-only.\n')
assert_eq "3:Corrects Guard 3: a probe that can exit 0 would auto-close #8285, so the probe is notify-only." "$OUT" \
  "split match: one record, keyword line number, both lines joined by one space"
echo ""

echo "TS10b: every keyword, split across lines, #N and indented GH-N"
for kw in close closes closed fix fixes fixed resolve resolves resolved; do
  OUT=$(scan_str "will ${kw}\n#99 x\n")
  assert_eq "1:will ${kw} #99 x" "$OUT" "split '${kw}' / '#99' produces exactly its record"
  OUT=$(scan_str "WILL ${kw^^}\n   GH-42 in the parser.\n")
  assert_eq "1:WILL ${kw^^} GH-42 in the parser." "$OUT" "split upper-case '${kw}' / indented GH-42"
done
echo ""

echo "TS11: whitespace shapes GitHub still closes on"
OUT=$(scan_str 'would close   \n#12 x\n')
assert_eq "1:would close #12 x" "$OUT" "trailing spaces after the keyword"
OUT=$(scan_str 'would close\r\n#12 x\r\n')
assert_eq "1:would close #12 x" "$OUT" "CRLF input: matched, and no CR in the record"
OUT=$(scan_str 'Closes #7 now\r\n')
assert_eq "1:Closes #7 now" "$OUT" "CRLF same-line input: no CR in the record"
OUT=$(scan_str 'would close\n\n  \n#12 x\n')
assert_eq "1:would close #12 x" "$OUT" "blank and whitespace-only lines between keyword and reference"
OUT=$(scan_str 'would close\n#12')
assert_eq "1:would close #12" "$OUT" "last line without a trailing newline"
echo ""

echo "TS12: split negatives, one shape each"
for neg in 'the sweeper will close\nthe tracker, see #8285 above.\n' \
           'prefix-disclose\n#12 is a heading.\n' \
           'close_\n#12 x\n' \
           'my_close\n#12 x\n' \
           'close\n#12abc\n' \
           'close\n# Heading\n' \
           'close\nGH-x\n' \
           'Fixes the parser and\n#12 x\n' \
           'will close\nsome prose\n#12 x\n'; do
  OUT=$(scan_str "$neg")
  assert_eq "0" "$(count_lines "$OUT")" "no match: $(printf '%s' "$neg" | head -c 40)"
done
echo ""

echo "TS13: records come out in ascending line order, same-line and split interleaved"
OUT=$(scan_str 'Fixes #1 and would close\n#2 later\nfixes\n\n#3\nCloses #4\n')
EXPECTED=$'1:Fixes #1 and would close\n1:Fixes #1 and would close #2 later\n3:fixes #3\n6:Closes #4'
assert_eq "$EXPECTED" "$OUT" "same-line + split records, ascending, both kept for line 1"
echo ""

print_results 58
