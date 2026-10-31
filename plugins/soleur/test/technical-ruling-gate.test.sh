#!/usr/bin/env bash
# Suite for plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh -- the /ship Phase 5.5
# Technical-Ruling Gate (hard rule hr-technical-fork-is-not-an-operator-question).
#
# Arms:
#   1. cases      -- table-driven: one fixture per row of the Guard 1 matrix in the plan, asserting
#                    the exit code AND the reason token on stderr.
#   2. shapes     -- must-PASS inputs that are not the canonical fixture: the four free-form item
#                    shapes real artifacts use, an operator row with category legal-risk, a CLO
#                    ruling, a taste row, an artifact absent entirely.
#   3. contract   -- producer/consumer: the canonical example table in
#                    technical-ruling-delegation.md is fed to the gate, and a spelling drift in the
#                    reference alone reddens it. Category parity: script == reference == rule body.
#   4. mutations  -- each mutant of the script (marker lines `# mut:<name>`) must change a verdict
#                    the cases above pin; the unmutated control runs first and must be green.
#   5. archive    -- an artifact moved under specs/archive/ is still examined.
#
# Writes only under `mktemp -d` (preflight Check 10 runs suites with the repository read-only).
# The EXIT trap is installed BEFORE test-helpers.sh is sourced, so the helpers' own trap composes.

set -euo pipefail
export LC_ALL=C

TMP="$(mktemp -d -t trg-suite.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
assert_fixture_dir "$TMP"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh"
FIXTURES="$SUITE_DIR/fixtures/technical-ruling-gate"
REFERENCE="$REPO_ROOT/plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md"
RULES="$REPO_ROOT/AGENTS.rules.md"
RULE_ID='hr-technical-fork-is-not-an-operator-question'

sed_inplace() { local f="${*: -1}" t; t="$(mktemp)" || return 2; [[ "$f" == /* ]] || return 2; sed "${@:1:$#-1}" "$f" > "$t" && cat "$t" > "$f"; rm -f "$t"; }
EXEC_LOG="$TMP/exec.log"
: > "$EXEC_LOG"

# run <script> <args...>: capture rc/out/err into $TMP/last.{rc,out,err}. rc is read on its own line.
run() {
  local script="$1"; shift
  set +e
  TRG_EXEC_LOG="$EXEC_LOG" bash "$script" "$@" >"$TMP/last.out" 2>"$TMP/last.err"
  echo "$?" > "$TMP/last.rc"
  set -e
}
last_rc() { cat "$TMP/last.rc"; }

# Verdict-line guard: every exit 0/1 must carry a [PASS]/[FAIL] line (a script that died elsewhere
# does not).
assert_verdict_line() {
  local msg="$1"
  if grep -qE '^\[PASS\] ' "$TMP/last.out" || grep -qE '^\[FAIL\] ' "$TMP/last.err"; then
    echo "  PASS: $msg (verdict line present)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (no [PASS]/[FAIL] line)"; FAIL=$((FAIL + 1))
  fi
}
assert_reason() {
  local reason="$1" msg="$2"
  if grep -qE "^\[FAIL\] .*: ${reason} - " "$TMP/last.err"; then
    echo "  PASS: $msg (reason $reason)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (reason $reason absent)"; sed 's/^/    | /' "$TMP/last.err"; FAIL=$((FAIL + 1))
  fi
}

# Instrument self-test: the dispatch helpers must be able to FAIL. A helper that always passes keeps
# the floor intact (it counts), so the floor alone cannot see it.
( assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }
( : > "$TMP/last.out"; : > "$TMP/last.err"; assert_verdict_line "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_verdict_line cannot fail -- dispatch is neutered\n' >&2; exit 2; }

( : > "$TMP/last.out"; : > "$TMP/last.err"; assert_reason "no-such-reason" "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_reason cannot fail -- dispatch is neutered\n' >&2; exit 2; }

[[ -f "$GATE" ]] || { echo "  FAIL: gate script missing: $GATE"; FAIL=$((FAIL + 1)); print_results 0; exit 1; }

echo "=== Control: the unmutated gate on the compliant fixture ==="
run "$GATE" "$FIXTURES/pass-mixed.md"
assert_eq "0" "$(last_rc)" "pass-mixed.md exits 0"
assert_verdict_line "pass-mixed.md"

echo "=== Arm 1: cases (Guard 1 matrix rows) ==="
# name | fixture | rc | reason
while IFS='|' read -r name fixture want_rc reason; do
  [[ -n "$name" ]] || continue
  run "$GATE" "$FIXTURES/$fixture"
  assert_eq "$want_rc" "$(last_rc)" "$name: $fixture rc"
  if [[ "$want_rc" == "1" ]]; then
    assert_verdict_line "$name"
    assert_reason "$reason" "$name"
  fi
done <<'EOF'
row1 blank class on row 2|no-class.md|1|bad-class
row2a blank ruling|unruled-technical.md|1|unruled-technical
row2b pending ruling|pending-technical.md|1|unruled-technical
row4 bare operator and invented category|bad-category.md|1|bad-category
pending bare or variant|pending-bare.md|1|bad-ruling-shape
four-cell row|arity.md|1|bad-class
operator row without an action|operator-empty.md|1|bad-ruling-shape
ruling shape variants|shape-variants.md|1|bad-ruling-shape
label with an invented category|label-vibes.md|1|owner-label-unscoped
label plural spelling|label-plural.md|1|owner-label-unscoped
label alternative spelling|label-alt.md|1|owner-label-unscoped
fence closed by a different char must not hide a row|fence-mixed.md|1|unruled-technical
bom first line is examined|bom-unruled.md|1|unruled-technical
row5 owner label unscoped in the artifact|owner-label-unscoped.md|1|owner-label-unscoped
row9 ruling shape|bad-ruling-shape.md|1|bad-ruling-shape
pending prose|pending-prose.md|1|unruled-technical
second table|second-table.md|1|unruled-technical
EOF

# Row 4 names BOTH spellings, row 9 BOTH shapes: count the FAIL lines.
run "$GATE" "$FIXTURES/bad-category.md"
assert_eq "2" "$(grep -cE '^\[FAIL\] .*: bad-category - ' "$TMP/last.err" || true)" "row4: both bare operator and operator (vibes) flagged"
run "$GATE" "$FIXTURES/bad-ruling-shape.md"
assert_eq "2" "$(grep -cE '^\[FAIL\] .*: bad-ruling-shape - ' "$TMP/last.err" || true)" "row9: both malformed ruling cells flagged"
# Row 1: the failing row is row 2 (a check that stops at the first row is the defect).
run "$GATE" "$FIXTURES/no-class.md"
ln="$({ grep -n 'T2 second row' "$FIXTURES/no-class.md" || true; } | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: bad-class - " "$TMP/last.err" || true)" "row1: the failure names the second row by its file line"
# Row 2 remedy text names the CTO spawn and the two-attempt cap.
run "$GATE" "$FIXTURES/unruled-technical.md"
assert_eq "1" "$(grep -cE 'soleur:engineering:cto.*two' "$TMP/last.err" || true)" "row2: remedy names the CTO and the two-attempt cap"
# Every table is scanned: the failing row sits in the SECOND table (a first-table-only scanner passes).
run "$GATE" "$FIXTURES/second-table.md"
ln="$({ grep -n 'B second writer technical row' "$FIXTURES/second-table.md" || true; } | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: unruled-technical - " "$TMP/last.err" || true)" "second table: the unruled row of the later table is examined, by its file line"

run "$GATE" "$FIXTURES/shape-dates.md"
assert_eq "4" "$(grep -cE '^\[FAIL\] .*: bad-ruling-shape - ' "$TMP/last.err" || true)" "each of year, month, day and an empty decision is flagged on its own row"
# Finding line numbers are file lines (the label and the pending lints too).
run "$GATE" "$FIXTURES/owner-label-unscoped.md"
ln="$({ grep -n 'Owner decision needed' "$FIXTURES/owner-label-unscoped.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: owner-label-unscoped - " "$TMP/last.err" || true)" "a label finding names its file line"
run "$GATE" "$FIXTURES/pending-prose.md"
ln="$({ grep -n 'pending - assumed' "$FIXTURES/pending-prose.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: unruled-technical - " "$TMP/last.err" || true)" "a pending finding names its file line"
run "$GATE" "$FIXTURES/pending-bare.md"
assert_eq "3" "$(grep -cE '^\[FAIL\] .*: bad-ruling-shape - ' "$TMP/last.err" || true)" "a bare pending and both spelling variants are each their own finding"
run "$GATE" "$FIXTURES/shape-variants.md"
assert_eq "3" "$(grep -cE '^\[FAIL\] .*: bad-ruling-shape - ' "$TMP/last.err" || true)" "wrong agent, short date and unanchored ruling are each flagged"

echo "=== Rows 3 and 11: a table that exists but was not examined is exit 2; no table is a warning ==="
run "$GATE" "$FIXTURES/empty-table.md"
assert_eq "2" "$(last_rc)" "row3: a table with no data rows is exit 2"
assert_eq "1" "$(grep -cF '0 rows examined' "$TMP/last.err" || true)" "row3: the message says 0 rows examined"
run "$GATE" "$FIXTURES/fenced-table-only.md"
assert_eq "0" "$(last_rc)" "row11: a table only inside a fence never counts (its bad row is ignored)"
assert_eq "1" "$(grep -cF '[WARN]' "$TMP/last.out" || true)" "row11: a fence-only artifact is a WARN, not a PASS"
run "$GATE" "$FIXTURES/no-table.md"
assert_eq "0" "$(last_rc)" "an artifact with no table is exit 0"
assert_eq "1" "$(grep -cF '[WARN]' "$TMP/last.out" || true)" "an artifact with no table prints [WARN]"
run "$GATE" "$TMP/does-not-exist.md"
assert_eq "2" "$(last_rc)" "an explicit path that does not exist is exit 2"
run "$GATE" "$FIXTURES"
assert_eq "2" "$(last_rc)" "a directory is exit 2"
run "$GATE"
assert_eq "2" "$(last_rc)" "no arguments is exit 2"

for f in header-drift header-lower fence-unclosed empty-first empty ws-only stray-blank stray-nolead; do
  run "$GATE" "$FIXTURES/$f.md"
  assert_eq "2" "$(last_rc)" "$f is exit 2 (could not measure), never a quiet WARN"
done
for f in fence-tilde fence-indent crlf ws-row escaped-pipe case-mixed later-unrelated-table bom unrelated-data-row fence-short-close fence-info-close table-in-tilde table-in-indent; do
  run "$GATE" "$FIXTURES/$f.md"
  assert_eq "0" "$(last_rc)" "$f exits 0"
  assert_verdict_line "$f"
done
run "$GATE" "$FIXTURES/later-unrelated-table.md"
assert_eq "1" "$(grep -cF '[PASS]' "$TMP/last.out" || true)" "an unrelated later table is not scanned as Decision Classes rows"

echo "=== Row 6: PR body mode ==="
run "$GATE" --pr-body "$FIXTURES/pr-body-label-bare.md"
assert_eq "1" "$(last_rc)" "row6: the label without (operator: <category>) is exit 1"
assert_reason "owner-label-unscoped" "row6"
run "$GATE" --pr-body "$FIXTURES/pr-body-label-fenced.md"
assert_eq "0" "$(last_rc)" "row6: the same label inside a fence passes"
run "$GATE" --pr-body "$FIXTURES/pr-body-label-scoped.md"
assert_eq "0" "$(last_rc)" "the label carried by (operator: <category>) passes"
run "$GATE" --pr-body "$FIXTURES/pr-body-clean.md"
assert_eq "0" "$(last_rc)" "a body with no label passes"
assert_verdict_line "pr-body-clean"
run "$GATE" --pr-body "$TMP/no-such-body.md"
assert_eq "2" "$(last_rc)" "--pr-body on a missing file is exit 2"
: > "$TMP/empty-body.md"
run "$GATE" --pr-body "$TMP/empty-body.md"
assert_eq "2" "$(last_rc)" "--pr-body on an EMPTY body (a failed fetch) is exit 2, never a PASS"
run "$GATE" --pr-body "$FIXTURES/pr-body-pending.md"
assert_eq "1" "$(last_rc)" "--pr-body fails a surviving pending - assumed placeholder"
printf ' \n\n  \n' > "$TMP/ws-body.md"
run "$GATE" --pr-body "$TMP/ws-body.md"
assert_eq "2" "$(last_rc)" "--pr-body on a whitespace-only body (the newline gh writes for an empty body) is exit 2"
run "$GATE" --pr-body "$FIXTURES/pr-body-unclosed.md"
assert_eq "2" "$(last_rc)" "--pr-body with an unclosed fence is exit 2, never a PASS"
run "$GATE" --pr-body "$FIXTURES/pr-body-inline-code.md"
assert_eq "0" "$(last_rc)" "--pr-body may quote the label and the placeholder inside inline code"
run "$GATE" --pr-body "$FIXTURES/pr-body-label-spellings.md"
assert_eq "3" "$(grep -cE '^\[FAIL\] .*: owner-label-unscoped - ' "$TMP/last.err" || true)" "spacing, verb and word-order variants of the label are each caught"
run "$GATE" --pr-body "$FIXTURES/pr-body-pending-spaced.md"
assert_eq "1" "$(last_rc)" "a spaced or en-dash pending placeholder in a PR body is exit 1"
awk 'BEGIN { for (i = 0; i < 256; i++) print "Owner decision needed: x" }' > "$TMP/wrap.md"
run "$GATE" --pr-body "$TMP/wrap.md"
assert_eq "1" "$(last_rc)" "exactly 256 unscoped labels is still exit 1 (the count does not wrap)"

echo "=== Arm 2: must-PASS shapes ==="
for f in operator-legal shape-numbered taste; do
  run "$GATE" "$FIXTURES/$f.md"
  assert_eq "0" "$(last_rc)" "$f exits 0"
  assert_verdict_line "$f"
done

echo "=== Arm 5: archive lookup and the absent artifact (--branch) ==="
SPECS="$TMP/specs"; mkdir -p "$SPECS/feat-x" "$SPECS/archive/20260101-feat-y" "$SPECS/archive/20260101-feat-z" "$SPECS/feat-empty"
cp "$FIXTURES/pass-mixed.md" "$SPECS/feat-x/decision-challenges.md"
cp "$FIXTURES/no-class.md" "$SPECS/archive/20260101-feat-y/decision-challenges.md"
cp "$FIXTURES/pass-mixed.md" "$SPECS/archive/20260101-feat-z/decision-challenges.md"
export TRG_SPECS_ROOT="$SPECS"
TRG_BRANCH=feat-x run "$GATE" --branch
assert_eq "0" "$(last_rc)" "--branch finds the live artifact and passes"
TRG_BRANCH=feat-y run "$GATE" --branch
assert_eq "1" "$(last_rc)" "row12: an archived artifact with a bad table is still examined (exit 1)"
TRG_BRANCH=feat-z run "$GATE" --branch
assert_eq "0" "$(last_rc)" "row12: an archived compliant artifact passes"
mkdir -p "$SPECS/feat-foo-bar" "$SPECS/archive/2026-02-05-baz-qux" "$SPECS/archive/2026-03-01-baz-qux"
cp "$FIXTURES/no-class.md" "$SPECS/feat-foo-bar/decision-challenges.md"
cp "$FIXTURES/pass-mixed.md" "$SPECS/archive/2026-02-05-baz-qux/decision-challenges.md"
cp "$FIXTURES/pass-mixed.md" "$SPECS/archive/2026-03-01-baz-qux/decision-challenges.md"
TRG_BRANCH=feat/foo-bar run "$GATE" --branch
assert_eq "1" "$(last_rc)" "a slashed branch resolves to its dash-named spec directory (and its bad row is found)"
TRG_BRANCH=feat-baz-qux run "$GATE" --branch
assert_eq "2" "$(last_rc)" "two archive directories for one branch is exit 2 (ambiguous), never silently the last"
mkdir -p "$TMP/nogit"
set +e; (cd "$TMP/nogit" && env -u TRG_BRANCH -u TRG_SPECS_ROOT GIT_CEILING_DIRECTORIES="$TMP" bash "$GATE" --branch) >"$TMP/last.out" 2>"$TMP/last.err"; echo "$?" > "$TMP/last.rc"; set -e
assert_eq "2" "$(last_rc)" "--branch outside a git repository is exit 2, never a PASS"
mkdir -p "$SPECS/archive/2026-01-01-redis-cache" "$SPECS/archive/20260101-000000-feat-technical-ruling-gate"
cp "$FIXTURES/no-class.md" "$SPECS/archive/2026-01-01-redis-cache/decision-challenges.md"
cp "$FIXTURES/no-class.md" "$SPECS/archive/20260101-000000-feat-technical-ruling-gate/decision-challenges.md"
TRG_BRANCH=feat-cache run "$GATE" --branch
assert_eq "0" "$(last_rc)" "a short slug never suffix-matches another feature's longer archive name (feat-cache vs redis-cache)"
TRG_BRANCH=fix-gate run "$GATE" --branch
assert_eq "0" "$(last_rc)" "a timestamped archive for another branch is not matched by a short slug"
TRG_BRANCH=HEAD run "$GATE" --branch
assert_eq "2" "$(last_rc)" "a detached HEAD is exit 2"
TRG_BRANCH="head" run "$GATE" --branch
assert_eq "0" "$(last_rc)" "a real branch named head (any case) is a branch, not a detached HEAD"
TRG_BRANCH=feat-nothing run "$GATE" --branch
assert_eq "0" "$(last_rc)" "--branch with no artifact anywhere is exit 0"
assert_eq "1" "$(grep -cF '[PASS] no decision-challenges artifact' "$TMP/last.out" || true)" "--branch absent artifact prints the PASS line"
unset TRG_SPECS_ROOT

echo "=== Arm 3: contract (producer/consumer and parity) ==="
# Extract the first fenced block after the '## 7. Canonical example' heading.
extract_example() {
  awk '/^## 7\. Canonical example/{on=1; next} on && /^```/{ if(inb){exit} inb=1; next } on && inb{print}' "$1"
}
extract_example "$REFERENCE" > "$TMP/example-full.md"
assert_eq "1" "$([[ -s "$TMP/example-full.md" ]] && echo 1 || echo 0)" "the reference carries a canonical example block"
# The delegation row needs a live verifier; Arm 6 feeds the FULL example (with a stubbed gh). Offline, it is filtered out.
grep -v 'Authorized by delegation' "$TMP/example-full.md" > "$TMP/example.md" || true
run "$GATE" "$TMP/example.md"
assert_eq "0" "$(last_rc)" "row8: the reference's canonical example passes the gate"
sed 's/| technical |/| technicl |/' "$TMP/example.md" > "$TMP/example-broken.md"
run "$GATE" "$TMP/example-broken.md"
assert_eq "1" "$(last_rc)" "row8: a Class spelling drift in the reference alone reddens the gate"

# category parity: script CATEGORIES == reference backticked list == rule-body root words.
script_cats() { sed -nE 's/^CATEGORIES="([^"]*)".*/\1/p' "$1" | tr ' ' '\n' | sort; }
ref_cats() { grep -m1 -E '^`money \|' "$1" | tr -d '`' | tr '|' '\n' | tr -d ' ' | sort; }
rule_line() { grep -F "[id: $RULE_ID]" "$1" | head -1; }
rule_roots_ok() {
  local line="$1" root
  for root in money scope priorit schedul irreversible production legal-risk brand; do
    grep -qiF -- "$root" <<<"$line" || { echo "missing:$root"; return 1; }
  done
}
parity_ok() { # <script> <reference> <rules>
  [[ "$(script_cats "$1")" == "$(ref_cats "$2")" ]] || return 1
  [[ -n "$(script_cats "$1")" ]] || return 1
  rule_roots_ok "$(rule_line "$3")" >/dev/null || return 1
}
if parity_ok "$GATE" "$REFERENCE" "$RULES"; then
  echo "  PASS: row7: script, reference and rule body agree on the operator categories"; PASS=$((PASS + 1))
else
  echo "  FAIL: row7: category parity broken"; FAIL=$((FAIL + 1))
fi
cp "$REFERENCE" "$TMP/ref-mut.md"; sed_inplace 's/ | brand`/`/;s/`money | scope | priority | schedule | irreversible | production-mutating | legal-risk | brand`/`money | scope | priority | schedule | irreversible | production-mutating | legal-risk`/' "$TMP/ref-mut.md"
if parity_ok "$GATE" "$TMP/ref-mut.md" "$RULES"; then
  echo "  FAIL: row7: a category removed from the reference alone was not caught"; FAIL=$((FAIL + 1))
else
  echo "  PASS: row7: a category removed from the reference alone reddens parity"; PASS=$((PASS + 1))
fi
cp "$RULES" "$TMP/rules-mut.md"; sed "/\[id: $RULE_ID\]/s/brand/colour/Ig" "$TMP/rules-mut.md" > "$TMP/rules-mut.md.new" && mv "$TMP/rules-mut.md.new" "$TMP/rules-mut.md"
if parity_ok "$GATE" "$REFERENCE" "$TMP/rules-mut.md"; then
  echo "  FAIL: row7: the word brand dropped from the rule body was not caught"; FAIL=$((FAIL + 1))
else
  echo "  PASS: row7: dropping brand from the rule body reddens parity"; PASS=$((PASS + 1))
fi

cp "$RULES" "$TMP/rules-mut2.md"; sed_inplace "/\[id: $RULE_ID\]/s/legal-risk/legal/Ig" "$TMP/rules-mut2.md"
if parity_ok "$GATE" "$REFERENCE" "$TMP/rules-mut2.md"; then
  echo "  FAIL: row7: legal-risk dropped from the rule body was not caught"; FAIL=$((FAIL + 1))
else
  echo "  PASS: row7: dropping legal-risk from the rule body reddens parity"; PASS=$((PASS + 1))
fi

echo "=== Arm 4: mutations (control first, then one mutant per marker) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"
pristine="$MUT/gate.pristine.sh"; cp "$GATE" "$pristine"
mutate() { # <name> <sed-script>: write $MUT/gate.<name>.sh and prove the mutation LANDED
  local name="$1" expr="$2" out="$MUT/gate.$1.sh"
  sed -E "$expr" "$pristine" > "$out"
  if cmp -s "$pristine" "$out"; then
    echo "  FAIL: mutation $name did not land"; FAIL=$((FAIL + 1)); return 1
  fi
  echo "  PASS: mutation $name landed"; PASS=$((PASS + 1))
}
mutant_crashed() { [[ "$(last_rc)" == 127 ]] || grep -qE 'unbound variable|syntax error|command not found' "$TMP/last.err"; }
killed() { # <name> <script> <pinned-rc> <args...>: the pristine script must give the pinned rc, and the mutant must give another WITHOUT crashing
  local name="$1" script="$2" pinned_rc="$3"; shift 3
  run "$pristine" "$@"
  if [[ "$(last_rc)" != "$pinned_rc" ]]; then
    echo "  FAIL: $name: the pristine script gives rc $(last_rc), not the pinned $pinned_rc"; FAIL=$((FAIL + 1)); return
  fi
  run "$script" "$@"
  if mutant_crashed; then
    echo "  FAIL: mutant $name CRASHED (rc $(last_rc)); a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$(last_rc)" != "$pinned_rc" ]]; then
    echo "  PASS: mutant $name killed (rc $(last_rc), pinned $pinned_rc)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: mutant $name SURVIVED (rc still $pinned_rc)"; FAIL=$((FAIL + 1))
  fi
}
killed_count() { # <name> <script> <reason> <want-count> <fixture>: pristine must show the count, the mutant must change it without crashing
  local name="$1" script="$2" reason="$3" want="$4" fixture="$5" got
  run "$pristine" "$fixture"
  got="$(grep -cE "^\[FAIL\] .*: ${reason} - " "$TMP/last.err" || true)"
  if [[ "$got" != "$want" ]]; then
    echo "  FAIL: $name: the pristine script shows $got $reason findings, not the pinned $want"; FAIL=$((FAIL + 1)); return
  fi
  run "$script" "$fixture"
  got="$(grep -cE "^\[FAIL\] .*: ${reason} - " "$TMP/last.err" || true)"
  if mutant_crashed; then
    echo "  FAIL: mutant $name CRASHED; a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$got" != "$want" ]]; then
    echo "  PASS: mutant $name killed ($got $reason findings, pinned $want)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: mutant $name SURVIVED ($got $reason findings, same as pinned)"; FAIL=$((FAIL + 1))
  fi
}
run "$pristine" "$FIXTURES/pass-mixed.md"
assert_eq "0" "$(last_rc)" "mutation control: the pristine copy is green"
# Instrument controls for the arm itself: each decider must be able to say SURVIVED / not-landed.
( killed ctrl "$pristine" 0 "$FIXTURES/pass-mixed.md" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: killed cannot report a survivor\n' >&2; exit 2; }
( killed_count ctrl "$pristine" bad-class 0 "$FIXTURES/pass-mixed.md" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: killed_count cannot report a survivor\n' >&2; exit 2; }
( mutate ctrl 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: mutate cannot report a mutation that did not land\n' >&2; exit 2; }

# row1: stop after the first row.
mutate stop-first 's/^(.*idx=.*) # mut:count$/\1; break # mut:count/' && \
  killed stop-first "$MUT/gate.stop-first.sh" 1 "$FIXTURES/no-class.md"
# row2: the unruled-technical branch disabled.
mutate no-unruled 's/^is_unruled\(\).*# mut:unruled$/is_unruled() { return 1; } # mut:unruled/' && \
  killed_count no-unruled "$MUT/gate.no-unruled.sh" unruled-technical 1 "$FIXTURES/unruled-technical.md"
# row4: accept any operator category.
mutate any-category 's/^cat_ok\(\).*# mut:cat$/cat_ok() { return 0; } # mut:cat/' && \
  killed_count any-category "$MUT/gate.any-category.sh" bad-category 2 "$FIXTURES/bad-category.md"
# row6: stop honouring fences in the label scan.
mutate no-fence-strip 's/^.*# mut:fence$/    { f = 0 } # mut:fence/' && \
  killed no-fence-strip "$MUT/gate.no-fence-strip.sh" 0 --pr-body "$FIXTURES/pr-body-label-fenced.md"
# row7: remove a category from the script only.
mutate drop-category 's/^CATEGORIES="([^"]*) brand"/CATEGORIES="\1"/' && \
  { if parity_ok "$MUT/gate.drop-category.sh" "$REFERENCE" "$RULES"; then echo "  FAIL: mutant drop-category SURVIVED the parity case"; FAIL=$((FAIL + 1)); else echo "  PASS: mutant drop-category killed by parity"; PASS=$((PASS + 1)); fi; }
# row9: stop checking the ruling shape.
mutate no-shape 's/^shape_ok\(\).*# mut:shape$/shape_ok() { return 0; } # mut:shape/' && \
  killed no-shape "$MUT/gate.no-shape.sh" 1 "$FIXTURES/bad-ruling-shape.md"
# pending placeholder lint disabled.
mutate no-pending 's/^(  done < )<\(unfenced_match "\$file" "\$PENDING_RE"\) # mut:pending$/\1\/dev\/null # mut:pending/' && \
  killed_count no-pending "$MUT/gate.no-pending.sh" unruled-technical 1 "$FIXTURES/pending-technical.md"
# row11: honour fenced tables.
mutate fenced-ok 's/^.*# mut:fence-table$/    { f = 0 } # mut:fence-table/' && \
  killed fenced-ok "$MUT/gate.fenced-ok.sh" 0 "$FIXTURES/fenced-table-only.md"

# The mutants below pin each input shape and each check the test-design review found unpinned.
mutate arity 's/\$\{#pipes\} -ne 2/${#pipes} -lt 0/' && \
  killed arity "$MUT/gate.arity.sh" 1 "$FIXTURES/arity.md"
mutate op-empty 's/elif \[\[ -z "\$c3" \]\]; then/elif false; then/' && \
  killed op-empty "$MUT/gate.op-empty.sh" 1 "$FIXTURES/operator-empty.md"
mutate shape-loose "s/^RULING_RE=.*/RULING_RE='Ruled by [A-Z]+ agent, [0-9]+-[0-9]+-[0-9]+: .+'/" && \
  killed_count shape-loose "$MUT/gate.shape-loose.sh" bad-ruling-shape 3 "$FIXTURES/shape-variants.md"
mutate pending-glob 's/== "pending - assumed"\*/== pending*/' && \
  killed_count pending-glob "$MUT/gate.pending-glob.sh" bad-ruling-shape 3 "$FIXTURES/pending-bare.md"
mutate label-cat 's/\\\(operator:\\ \(\$CATS_RE\)\\\)/operator/' && \
  killed label-cat "$MUT/gate.label-cat.sh" 1 "$FIXTURES/label-vibes.md"
mutate label-plural 's/\(decision\|ruling\)s\?\[ /(decision|ruling)[ /' && \
  killed label-plural "$MUT/gate.label-plural.sh" 1 "$FIXTURES/label-plural.md"
mutate label-alt 's/\|decision\[ \\t\]\+needed\[ \\t\]\+from\[ \\t\]\+the\[ \\t\]\+owner//' && \
  killed label-alt "$MUT/gate.label-alt.sh" 1 "$FIXTURES/label-alt.md"
mutate no-tilde '/# mut:fence$/ s/\|~~~\+//' && \
  killed no-tilde "$MUT/gate.no-tilde.sh" 0 "$FIXTURES/fence-tilde.md"
mutate fence-indent '/# mut:fence$/ s/\^ \? \? \?/^/' && \
  killed fence-indent "$MUT/gate.fence-indent.sh" 0 "$FIXTURES/fence-indent.md"
mutate fence-any-char 's/c == fc && n >= fn && //' && \
  killed fence-any-char "$MUT/gate.fence-any-char.sh" 1 "$FIXTURES/fence-mixed.md"
mutate no-state-reset 's/^    \{ end_table\(\) \}$/    { }/' && \
  killed no-state-reset "$MUT/gate.no-state-reset.sh" 0 "$FIXTURES/later-unrelated-table.md"
mutate no-crlf 's/^    \{ sub\(\/\\r\$\/, \"\"\); if .*$/    { }/' && \
  killed no-crlf "$MUT/gate.no-crlf.sh" 0 "$FIXTURES/crlf.md"
mutate no-rtrim 's/ sub\(\/\[ \\t\]\+\$\/, "", line\);//' && \
  killed no-rtrim "$MUT/gate.no-rtrim.sh" 0 "$FIXTURES/ws-row.md"
mutate no-unclosed 's/if \(f\) print "@UNCLOSED"//' && \
  killed no-unclosed "$MUT/gate.no-unclosed.sh" 2 "$FIXTURES/fence-unclosed.md"
mutate no-badheader 's/print "@BADHEADER";//' && \
  killed no-badheader "$MUT/gate.no-badheader.sh" 2 "$FIXTURES/header-drift.md"
mutate badheader-eager 's/\{ hdr_pending = 1; next \}/{ print "@BADHEADER"; next }/' && \
  killed badheader-eager "$MUT/gate.badheader-eager.sh" 0 "$FIXTURES/unrelated-data-row.md"
mutate no-empty 's/print "@EMPTY"//' && \
  killed no-empty "$MUT/gate.no-empty.sh" 2 "$FIXTURES/empty-first.md"
mutate branch-slash 's|safe="\$\{branch//\\//-\}"|safe="$branch"|' && \
  { TRG_BRANCH=feat/foo-bar TRG_SPECS_ROOT="$SPECS" killed branch-slash "$MUT/gate.branch-slash.sh" 1 --branch; }
mutate pr-body-empty 's/^    if ! \{ \[\[ -s "\$f" \]\] && .*; \}; then$/    if false; then/' && \
  killed pr-body-empty "$MUT/gate.pr-body-empty.sh" 2 --pr-body "$TMP/empty-body.md"
mutate no-cap 's/^  \(\( n > 255 \)\) && n=255$/  :/' && \
  killed no-cap "$MUT/gate.no-cap.sh" 1 --pr-body "$TMP/wrap.md"
mutate no-ambig 's/^    \(\( \$\{#matches\[@\]\} == 1 \)\) .*$/    :/' && \
  { TRG_BRANCH=feat-baz-qux TRG_SPECS_ROOT="$SPECS" killed no-ambig "$MUT/gate.no-ambig.sh" 2 --branch; }

# Pass-2 mutants: each pins a gap the second review round found.
mutate stray 's/print "@STRAY"/x = 1/' && \
  killed stray "$MUT/gate.stray.sh" 2 "$FIXTURES/stray-blank.md"
mutate empty-artifact "s/^  grep -q '\[\^\[:space:\]\]' \"\\\$file\" .*\$/  :/" && \
  killed empty-artifact "$MUT/gate.empty-artifact.sh" 2 "$FIXTURES/empty.md"
mutate branch-head 's/ && \[ "\$branch" != HEAD \]//' && \
  { TRG_BRANCH=HEAD TRG_SPECS_ROOT="$SPECS" killed branch-head "$MUT/gate.branch-head.sh" 2 --branch; }
mutate archive-suffix 's/archive\/\$pre-"\$nm"/archive\/*-"$nm"/' && \
  { TRG_BRANCH=feat-cache TRG_SPECS_ROOT="$SPECS" killed archive-suffix "$MUT/gate.archive-suffix.sh" 0 --branch; }
mutate pr-unclosed 's/^    \(\( UNCLOSED_SEEN \)\) .*$/    :/' && \
  killed pr-unclosed "$MUT/gate.pr-unclosed.sh" 2 --pr-body "$FIXTURES/pr-body-unclosed.md"
mutate ws-body 's/ && grep -q .\[\^\[:space:\]\]. "\$f"; \}; then/; }; then/' && \
  killed ws-body "$MUT/gate.ws-body.sh" 2 --pr-body "$TMP/ws-body.md"
mutate no-inline-code 's/gsub\(\/`\[\^`\]\*`\/, "", line\);//' && \
  killed no-inline-code "$MUT/gate.no-inline-code.sh" 0 --pr-body "$FIXTURES/pr-body-inline-code.md"
mutate no-bom 's/; if \(NR == 1\) sub\(\/\^\\357\\273\\277\/, ""\)//g' && \
  killed no-bom "$MUT/gate.no-bom.sh" 1 "$FIXTURES/bom-unruled.md"
mutate date-year 's/\[0-9\]\{4\}-\[0-9\]\{2\}-\[0-9\]\{2\}: /[0-9]+-[0-9]{2}-[0-9]{2}: /' && \
  killed_count date-year "$MUT/gate.date-year.sh" bad-ruling-shape 4 "$FIXTURES/shape-dates.md"
mutate date-month 's/\[0-9\]\{4\}-\[0-9\]\{2\}-\[0-9\]\{2\}: /[0-9]{4}-[0-9]+-[0-9]{2}: /' && \
  killed_count date-month "$MUT/gate.date-month.sh" bad-ruling-shape 4 "$FIXTURES/shape-dates.md"
mutate date-day 's/\[0-9\]\{4\}-\[0-9\]\{2\}-\[0-9\]\{2\}: /[0-9]{4}-[0-9]{2}-[0-9]+: /' && \
  killed_count date-day "$MUT/gate.date-day.sh" bad-ruling-shape 4 "$FIXTURES/shape-dates.md"
mutate empty-decision "s/\]\{2\}: \.\+'\$/]{2}:.*'/" && \
  killed_count empty-decision "$MUT/gate.empty-decision.sh" bad-ruling-shape 4 "$FIXTURES/shape-dates.md"
mutate fence-short 's/ && n >= fn//g' && \
  killed fence-short "$MUT/gate.fence-short.sh" 0 "$FIXTURES/fence-short-close.md"
mutate fence-info 's/ && tok ~ \/\^\(`\+\|~\+\)\[ \\t\]\*\$\///g' && \
  killed fence-info "$MUT/gate.fence-info.sh" 0 "$FIXTURES/fence-info-close.md"
mutate tilde-table '/# mut:fence-table$/ s/\|~~~\+//' && \
  killed tilde-table "$MUT/gate.tilde-table.sh" 0 "$FIXTURES/table-in-tilde.md"
mutate indent-table '/# mut:fence-table$/ s/\^ \? \? \?/^/' && \
  killed indent-table "$MUT/gate.indent-table.sh" 0 "$FIXTURES/table-in-indent.md"

echo "=== Arm 6: the delegation arm (Guard 2) ==="
DFX="$REPO_ROOT/plugins/soleur/test/fixtures/standing-delegation"
DBIN="$TMP/dbin"; mkdir -p "$DBIN"
[[ -f "$DFX/gh-stub.sh" && -f "$DFX/delegation-valid.md" && -f "$DFX/envelope-valid.md" ]] || { echo "FATAL: delegation fixtures missing" >&2; exit 2; }
cp "$DFX/gh-stub.sh" "$DBIN/gh-base"; chmod +x "$DBIN/gh-base"
# The shared stub is read-only here and does not know the epic comment listing the receipt check reads: a wrapper answers
# `api repos/<o>/<r>/issues/<n>/comments --paginate` from receipts-<n>.json and hands every other argv to the shared stub.
# `eat-stdin` makes it drain (and count) whatever stdin it inherited, to prove no call can swallow the gate's row loop.
cat > "$DBIN/gh" <<'WRAP'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -f "$d/eat-stdin" ]; then n="$(cat | wc -c | tr -d ' ')"; echo "$n" >> "$d/stdin-bytes"; fi
if [ "${1:-}" = api ] && [ "$#" -eq 3 ] && [ "$3" = --paginate ]; then
  echo "$*" >> "$d/calls.log"
  case "$2" in
    repos/*/*/issues/*/comments)
      p="${2%/comments}"; n="${p##*/}"
      case "$(cat "$d/mode-comments" 2>/dev/null)" in net) echo "error connecting to api.github.com" >&2; exit 1 ;; esac
      if [ -f "$d/receipts-$n.json" ]; then cat "$d/receipts-$n.json"; else echo '[]'; fi
      exit 0 ;;
  esac
  echo "STUB-MISS $*" >> "$d/calls.log"; echo "gh wrapper: unsupported argv: $*" >&2; exit 64
fi
exec "$here/gh-base" "$@"
WRAP
chmod +x "$DBIN/gh"
# Fake SUT clock (#11578): an argv-strict `date` stub serves the suite-pinned instant to every
# `date` consumer reachable under run_d's stubbed PATH -- the gate's two `-u +%Y-%m-%dT%H:%M:%SZ`
# reads (gate receipt_check + ran check), the verifier's strict-mode `-u +%s`, and the verifier
# render path's `-u +%Y-%m-%d`. Each argv is logged to dcalls.log for the dispatch floor below;
# ANY other argv exits 64 so a new call shape fails in the open. Real `date` is never exec'd --
# a passthrough is a bypass that re-opens the midnight flake the pin exists to close.
assert_fixture_dir "$DBIN"
cat > "$DBIN/date" <<'STUB'
#!/usr/bin/env bash
here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
printf '%s\n' "$*" >> "$here/dcalls.log"
case "$*" in
  "-u +%Y-%m-%dT%H:%M:%SZ") [ -s "$here/clock" ] || { echo "date stub: no pinned clock" >&2; exit 64; }; cat "$here/clock" ;;
  "-u +%s") [ -s "$here/clock.epoch" ] || { echo "date stub: no pinned epoch" >&2; exit 64; }; cat "$here/clock.epoch" ;;
  "-u +%Y-%m-%d") [ -s "$here/clock" ] || { echo "date stub: no pinned clock" >&2; exit 64; }; p="$(cat "$here/clock")"; printf '%s\n' "${p%%T*}" ;;
  *) echo "date stub: unexpected argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$DBIN/date"
DURL1="https://github.com/example-org/example-repo/issues/77#issuecomment-1001"
DURL2="https://github.com/example-org/example-repo/issues/77#issuecomment-1002"
DREPO="$TMP/drepo"; mkdir -p "$DREPO"
sed -e "s|@URL@|$DURL1|g" "$DFX/envelope-valid.md" > "$DREPO/env-valid.md"
sed -e "s|@URL@|$DURL2|g" "$DFX/envelope-valid.md" > "$DREPO/env-valid-2.md"
( git_fixture_env "$DREPO" && git -C "$DREPO" init -q && git -C "$DREPO" add -A && git -C "$DREPO" commit -q -m "fixture envelopes" ) >/dev/null 2>&1 \
  || { echo "FATAL: delegation fixture repository not built" >&2; exit 2; }
DTODAY="$(date -u +%Y-%m-%d)"; DNOW="${DTODAY}T00:00:00Z"
DEXP="$(jq -rn --arg d "$DTODAY" '($d + "T00:00:00Z" | fromdateiso8601) + 864000 | strftime("%Y-%m-%d")')"
# Pin the stub clock to noon of the fixture day (#11578). Noon sits strictly after every
# "present" fixture instant (DNOW T00:00, T00:07) and strictly before every `dts +n` (n>=1), so
# fixture instants and the gate's `now` share one source of truth (DTODAY) and a UTC-midnight
# crossing mid-suite can never move a `dts 1` receipt onto the wrong side of "future" — the
# flake class is eliminated, not narrowed. `DPATH` (mkbin_t) cases carry the SAME stub: the
# reduced dir gets a copy of $DBIN/date plus `clock`/`clock.epoch` symlinks back to $DBIN, so a
# future-dependent fixture under DPATH is pinned too — the pin reaches every exec arm that can
# pair a stubbed-gh delegation path with a clock. The only ambient arms left are `run` (static
# $FIXTURES/ shape inputs, no delegation rows, no `date` reach) and direct `bash "$GATE"`
# subshells; the AMBF floor below refuses a timestamp-bearing fixture outside a pinned-PATH
# exec. dclock_at repins the instant; any case that repins must restore DNOON afterwards,
# unconditionally (never &&-chained — a failed assert must not skip the restore and poison
# every later case).
DNOON="${DTODAY}T12:00:00Z"
dclock_at() { # <iso>: pin the stub clock; writes the ISO instant and its epoch; fails loudly on an unparseable instant
  assert_fixture_dir "$DBIN"
  local e
  e="$(jq -rn --arg p "$1" '$p | fromdateiso8601')" || { echo "FATAL: dclock_at: unparseable instant: $1" >&2; exit 2; }
  printf '%s\n' "$1" > "$DBIN/clock"
  printf '%s\n' "$e" > "$DBIN/clock.epoch"
}
dclock_at "$DNOON"
DSC=0
dscn() { # fresh stub state: comment 1001 valid, comment 1002 edited (invalid), both on open epic 77 by an admin
  DSC=$((DSC + 1)); STUB_DIR="$TMP/dscn$DSC"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo "example-org/example-repo" > "$STUB_DIR/repo.txt"
  sed -e "s/@EXPIRY@/$DEXP/" -e "s/@DATE@/$DTODAY/" "$DFX/delegation-valid.md" > "$STUB_DIR/body.md"
  local id upd
  for id in 1001 1002; do
    upd="$DNOW"; [[ "$id" == 1002 ]] && upd="${DTODAY}T00:07:00Z"
    jq -n --rawfile body "$STUB_DIR/body.md" --arg c "$DNOW" --arg u "$upd" --argjson id "$id" \
      --arg iu "https://api.github.com/repos/example-org/example-repo/issues/77" \
      '{id:$id, body:$body, user:{login:"owner-user", type:"User"}, author_association:"MEMBER", created_at:$c, updated_at:$u, issue_url:$iu}' > "$STUB_DIR/comment-$id.json"
  done
  echo '{"permission":"admin"}' > "$STUB_DIR/perm-owner-user.json"
  echo '{"number":77,"state":"open"}' > "$STUB_DIR/issue-77.json"
}
mkd() { # <name> <fixture>: fixture with placeholders filled -> $DF
  mkdir -p "$TMP/df"; DF="$TMP/df/$1.md"
  sed -e "s|@URL2@|$DURL2|g" -e "s|@ENV2@|env-valid-2.md|g" -e "s|@URL@|$DURL1|g" -e "s|@ENV@|env-valid.md|g" "$FIXTURES/$2" > "$DF"
}
DLOG="$TMP/dexec.log"
run_d() { # <script> <args...>: runs from the fixture repository with the stub gh first on PATH
  local script="$1"; shift
  : > "$DLOG"
  set +e
  ( cd "$DREPO" && git_fixture_env "$DREPO" && TRG_EXEC_LOG="$DLOG" PATH="${DPATH:-$DBIN:$PATH}" bash "$script" "$@" ) >"$TMP/last.out" 2>"$TMP/last.err"
  echo "$?" > "$TMP/last.rc"
  set -e
}
dlog_count() { grep -c '^delegation ' "$DLOG" || true; }
no_miss() { if grep -q 'STUB-MISS' "$STUB_DIR/calls.log" 2>/dev/null; then echo "  FAIL: $1: gh stub refused an argv"; FAIL=$((FAIL + 1)); else echo "  PASS: $1: no stub miss"; PASS=$((PASS + 1)); fi; }

dscn; mkd valid deleg-valid.md; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "FR4: a valid delegation row on operator (production-mutating) passes"
assert_verdict_line "valid delegation"
assert_eq "1" "$(grep -c '^SOLEUR_RULE_APPLIED rule=hr-menu-option-ack-not-prod-write-auth note=delegation-verified$' "$TMP/last.out" || true)" "the arm announces that a delegation was verified"
assert_eq "1" "$(dlog_count)" "the arm logged one examined delegation row"
no_miss "valid delegation"

dscn; mkd invalid deleg-valid.md; sed 's/-1001/-1002/g;s/env-valid.md/env-valid-2.md/' "$DF" > "$TMP/df/invalid2.md"; run_d "$GATE" "$TMP/df/invalid2.md"
assert_eq "1" "$(last_rc)" "an edited delegation is exit 1"
assert_reason "delegation-invalid" "edited delegation"
assert_eq "1" "$(grep -c 'delegation-invalid - .*changed after it was recorded' "$TMP/last.err" || true)" "the finding carries the verifier's plain reason"
no_miss "edited delegation"

dscn; echo 404 > "$STUB_DIR/mode-comment-1001"; mkd gone deleg-valid.md; run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "an unreadable (deleted) delegation link is exit 2, never a pass"
assert_eq "1" "$(grep -c 'delegation-unverifiable - ' "$TMP/last.err" || true)" "the finding is delegation-unverifiable"
dscn; echo net > "$STUB_DIR/mode-repo"; mkd net deleg-valid.md; run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "an API failure while verifying is exit 2"

dscn; mkd money deleg-wrong-class.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "row shape on operator (money) is refused"
assert_reason "bad-ruling-shape" "delegation on operator (money)"
assert_eq "0" "$(dlog_count)" "a refused class is never verified"
dscn; mkd tech deleg-technical-class.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "row shape on a technical row is refused"
assert_reason "bad-ruling-shape" "delegation on a technical row"
dscn; mkd shape deleg-bad-shape.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "malformed delegation rulings are exit 1"
assert_eq "3" "$(grep -cE '^\[FAIL\] .*: bad-ruling-shape - ' "$TMP/last.err" || true)" "no envelope, no link and a non-comment link are each flagged"

dscn; mkd two deleg-two-rows.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "first row valid, second invalid: exit 1 (stopping at the first row is the defect)"
assert_eq "1" "$(grep -cE '^\[FAIL\] .*: delegation-invalid - ' "$TMP/last.err" || true)" "exactly the second row is flagged"
assert_eq "2" "$(dlog_count)" "both delegation rows were examined"
dscn; mkd both deleg-both-valid.md; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "two valid delegation rows pass (an envelope anchored by title included)"

dscn; sed -e "s|https://github.com/example-org/example-repo/issues/77#issuecomment-1001|$DURL1|g" -e 's|knowledge-base\(/project/specs/example/envelope.md\)|env-valid.md|g' "$TMP/example-full.md" > "$TMP/df/example-d.md"
assert_eq "1" "$(grep -c 'Authorized by delegation' "$TMP/df/example-d.md" || true)" "the canonical example carries one delegation row"
run_d "$GATE" "$TMP/df/example-d.md"
assert_eq "0" "$(last_rc)" "FR4: the reference's canonical example (delegation row included) passes the gate against a stubbed verifier"
assert_eq "1" "$(dlog_count)" "the canonical example's delegation row was examined"

dscn; mkd stray deleg-stray.md; run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "a delegation row outside the table (after a blank line) is exit 2, never read as a ruling"
assert_eq "0" "$(dlog_count)" "a stray row is never verified"
dscn; mkd plain deleg-plain.md; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "H2: a plain operator (production-mutating) row with no delegation still passes; prose naming the phrase is inert"
assert_eq "0" "$(dlog_count)" "no delegation row, no verifier call"
assert_verdict_line "plain production-mutating row"

echo "=== Arm 6e: what the call carries, closed epics, case variants (testdesign F2) ==="
sha_of() { # <stdin>: sha256 of the bytes on stdin
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}
SHA_ENV1="$(git -C "$DREPO" show HEAD:env-valid.md | sha_of)"
dts() { jq -rn --arg d "$DTODAY" --argjson n "$1" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%dT%H:%M:%SZ")'; }
mkdr() { # <name> <ran-iso> [fixture]: the delegation fixture with ", ran <iso>" on its delegation row(s); the result is $DF
  mkd "$1" "${3:-deleg-valid.md}"; sed "s/\(envelope [A-Za-z0-9_.#@ -]*[A-Za-z0-9_.#-]\) |\$/\1, ran $2 |/" "$DF" > "$TMP/df/$1-ran.md"; DF="$TMP/df/$1-ran.md"
}
RID=9000
rcpt() { # <delegation-url> <envelope> <sha> <result> <author_association>: append a receipt comment to the epic's comment list
  local body
  body="$(printf '<!-- soleur-delegated-act v1 delegation=%s envelope=%s sha256=%s result=%s run=none -->\nMerged the change under your standing approval; it is live and healthy.' "$1" "$2" "$3" "$4")"
  RID=$((RID + 1))
  jq -n --arg b "$body" --arg a "$5" --arg c "${RCPT_CREATED:-$DNOW}" --arg u "${RCPT_UPDATED:-${RCPT_CREATED:-$DNOW}}" --arg t "${RCPT_TYPE:-User}" --argjson id "$RID" \
    '{id: $id, body: $b, created_at: $c, updated_at: $u, user: {login: "owner-user", type: $t}} + (if $a == "ABSENT" then {} else {author_association: $a} end)' >> "$STUB_DIR/rcpt.lines"
  jq -s . "$STUB_DIR/rcpt.lines" > "$STUB_DIR/receipts-77.json"
}
AT="$DNOW"
ncalls() { { cat "$STUB_DIR/calls.log" 2>/dev/null || true; } | grep -c -e "$1" || true; }

dscn; echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; mkd tx1 deleg-valid.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "TX1: a row WITHOUT ran is a pre-act authorization: a closed epic is delegation-invalid (strict verify)"
assert_reason "delegation-invalid" "TX1 closed epic, no ran"
dscn; echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr tx1b "$AT"; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "TX1b: a row WITH ran is audited at that time: a closed epic is forgiven when the act ran while it was open"
assert_eq "1" "$(grep -c '^SOLEUR_RULE_APPLIED rule=hr-menu-option-ack-not-prod-write-auth note=delegation-verified$' "$TMP/last.out" || true)" "TX1c: the arm announces the verified delegation"
no_miss "TX1b"
dscn; mkd tx3 deleg-valid.md; sed 's/env-valid\.md/env-nonexistent.md/' "$DF" > "$TMP/df/tx3b.md"; run_d "$GATE" "$TMP/df/tx3b.md"
assert_eq "1" "$(last_rc)" "TX3: an envelope path that is not in the repository is delegation-invalid (the call carries --envelope)"
assert_reason "delegation-invalid" "TX3 missing envelope"
dscn; mkd tx3c deleg-valid.md; sed 's/env-valid\.md/env-untracked.md/' "$DF" > "$TMP/df/tx3d.md"; cp "$DREPO/env-valid.md" "$DREPO/env-untracked.md"; run_d "$GATE" "$TMP/df/tx3d.md"; rm -f "$DREPO/env-untracked.md"
assert_eq "1" "$(last_rc)" "TX3b: an envelope file that was never committed is delegation-invalid"
dscn; mkd tx4 deleg-valid.md; sed 's/| operator (production-mutating) |/| Operator (Production-Mutating) |/' "$DF" > "$TMP/df/tx4b.md"; run_d "$GATE" "$TMP/df/tx4b.md"
assert_eq "1" "$(last_rc)" "TX4: the class of a delegation row is matched exactly: Operator (Production-Mutating) is refused"
assert_reason "bad-ruling-shape" "TX4 class case variant"
assert_eq "0" "$(dlog_count)" "TX4b: a refused class is never verified"
dscn; mkd tx5 deleg-valid.md; sed 's/Authorized by delegation/authorized BY delegation/' "$DF" > "$TMP/df/tx5b.md"; run_d "$GATE" "$TMP/df/tx5b.md"
assert_eq "1" "$(last_rc)" "TX5: the phrase is matched exactly: authorized BY delegation is refused, never read as a plain operator row"
assert_reason "bad-ruling-shape" "TX5 phrase case variant"
dscn; mkd tx6 deleg-valid.md; sed 's/envelope env-valid\.md |/envelope env-valid.md, ran yesterday |/' "$DF" > "$TMP/df/tx6b.md"; run_d "$GATE" "$TMP/df/tx6b.md"
assert_eq "1" "$(last_rc)" "TX6: a ran value that is not an ISO 8601 UTC time is bad-ruling-shape"
assert_reason "bad-ruling-shape" "TX6 ran shape"
dscn; mkd tx7 deleg-valid.md; sed 's/envelope env-valid\.md |/envelope env-valid.md, ran 2026-1-5T00:00:00Z |/' "$DF" > "$TMP/df/tx7b.md"; run_d "$GATE" "$TMP/df/tx7b.md"
assert_eq "1" "$(last_rc)" "TX7: a short date in ran is bad-ruling-shape"
dscn; mkd tx8 deleg-valid.md; sed 's/envelope env-valid\.md |/envelope env-valid.md, ran 2026-01-05T00:00:00Z extra |/' "$DF" > "$TMP/df/tx8b.md"; run_d "$GATE" "$TMP/df/tx8b.md"
assert_eq "1" "$(last_rc)" "TX8: trailing text after the ran time is bad-ruling-shape"

echo "=== Arm 6f: the audit time is enforced, strictly for a row without ran (R3) ==="
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr ax1 "$(dts -1)"; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "AX1: a row whose act ran BEFORE the delegation existed is delegation-invalid"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr ax2 "$(dts 11)"; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "AX2: a row whose act ran AFTER the delegation expired is delegation-invalid"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr ax3 "$AT" deleg-valid.md; sed 's/-1001/-1002/g;s/env-valid.md/env-valid-2.md/' "$DF" > "$TMP/df/ax3b.md"; run_d "$GATE" "$TMP/df/ax3b.md"
assert_eq "1" "$(last_rc)" "AX3: an edited delegation is invalid in audit mode too"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr ax4 "$AT"; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "AX4: a ran row at a time inside the window passes with a matching receipt"
assert_eq "1" "$(ncalls '^api repos/example-org/example-repo/issues/77/comments --paginate$')" "AX4b: the epic's comments were read once, with the paginating form"

echo "=== Arm 6g: the execution receipt (R3): exists, attributable, matches ==="
rx() { # <name> <expect-rc> <expect-reason or -> : the stub state is already built; builds the ran row and runs the gate
  mkdr "$1" "$AT"; run_d "$GATE" "$DF"
  assert_eq "$2" "$(last_rc)" "$1: rc"
  if [[ "$3" != "-" ]]; then assert_reason "$3" "$1"; fi
  no_miss "$1"
}
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER;           rx RX0 0 -
dscn;                                                              rx RX1 2 receipt-missing
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" rolled-back OWNER;    rx RX1b 0 -
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok COLLABORATOR;      rx RX1c 0 -
dscn; rcpt "$DURL1" other-envelope.md "$SHA_ENV1" ok MEMBER;       rx RX2 2 receipt-mismatch
dscn; rcpt "$DURL1" env-valid.md "$(printf '%064d' 1)" ok MEMBER;  rx RX3 2 receipt-mismatch
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" failed MEMBER;        rx RX4 2 receipt-mismatch
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok NONE;              rx RX5 2 receipt-mismatch
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok CONTRIBUTOR;       rx RX5b 2 receipt-mismatch
dscn; rcpt "$DURL2" env-valid.md "$SHA_ENV1" ok MEMBER;            rx RX6 2 receipt-missing
dscn; echo net > "$STUB_DIR/mode-comments";                        rx RX7 2 receipt-unreadable
dscn; echo 'not json' > "$STUB_DIR/receipts-77.json";              rx RX8 2 receipt-unreadable
dscn; echo '{"a":1}' > "$STUB_DIR/receipts-77.json";               rx RX8b 2 receipt-unreadable
dscn; jq -n '[{id:1,body:"unrelated chatter",author_association:"MEMBER",created_at:"x",updated_at:"x",user:{type:"User"}}]' > "$STUB_DIR/receipts-77.json"
printf '%s\n' "$(jq -n --arg b "$(printf '<!-- soleur-delegated-act v1 delegation=%s envelope=env-valid.md sha256=%s result=ok run=none -->\nok.' "$DURL1" "$SHA_ENV1")" '[{id:2,body:$b,author_association:"MEMBER",created_at:"'$DNOW'",updated_at:"'$DNOW'",user:{type:"User"}}]')" >> "$STUB_DIR/receipts-77.json"
rx RX9 0 -
dscn; jq -n --arg b "$(printf 'hello\n<!-- soleur-delegated-act v1 delegation=%s envelope=env-valid.md sha256=%s result=ok run=none -->\nok.' "$DURL1" "$SHA_ENV1")" '[{id:2,body:$b,author_association:"MEMBER",created_at:"'$DNOW'",updated_at:"'$DNOW'",user:{type:"User"}}]' > "$STUB_DIR/receipts-77.json"; rx RX10 2 receipt-missing
dscn; jq -n --arg b "$(printf '<!-- soleur-delegated-act v1 delegation=%s envelope=env-valid.md sha256=%s result=ok run=none --> trailing\nok.' "$DURL1" "$SHA_ENV1")" '[{id:2,body:$b,author_association:"MEMBER",created_at:"'$DNOW'",updated_at:"'$DNOW'",user:{type:"User"}}]' > "$STUB_DIR/receipts-77.json"; rx RX11 2 receipt-missing
dscn; rcpt "$DURL1" env-valid.md "$(printf '%s' "$SHA_ENV1" | tr 'a-f' 'A-F')" ok MEMBER; rx RX12 2 receipt-missing
dscn; jq -n --arg b "$(printf '<!-- soleur-delegated-act v1 delegation=%s envelope=env-valid.md sha256=%s result=ok run=none -->\r\nok.' "$DURL1" "$SHA_ENV1")" '[{id:2,body:$b,author_association:"OWNER",created_at:"'$DNOW'",updated_at:"'$DNOW'",user:{type:"User"}}]' > "$STUB_DIR/receipts-77.json"; rx RX13 0 -
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkd rx14 deleg-valid.md; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "RX14: a row without ran needs no receipt"
assert_eq "0" "$(ncalls 'issues/77/comments')" "RX14b: and the epic's comments are not read for it"
dscn; echo '{"number":77,"state":"open"}' > "$STUB_DIR/issue-77.json"; mkdr rx15 "$AT"
assert_eq "1" "$([ "$(grep -c 'ran ' "$DF")" -ge 1 ] && echo 1 || echo 0)" "RX15: the ran fixture carries a ran value (instrument)"

echo "=== Arm 6g2: the receipt is bound to the delegation's life, to now, to its author and to ONE row ==="
RCT() { RCPT_CREATED="$1" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; }
dscn; RCT "$(dts -1)";                                              rx RW1 2 receipt-mismatch
dscn; RCT "$(dts 1)";                                               rx RW3 2 receipt-mismatch
dscn; RCPT_UPDATED="${DTODAY}T00:07:00Z" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; rx RW4 2 receipt-mismatch
dscn; RCPT_TYPE=Bot rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok COLLABORATOR; rx RW5 2 receipt-mismatch
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok ABSENT;             rx RX16 2 receipt-mismatch
dscn; rcpt "${DURL1}9" env-valid.md "$SHA_ENV1" ok MEMBER;           rx RX17 2 receipt-missing
dscn; rcpt "$DURL1" "env-valid.md#extra" "$SHA_ENV1" ok MEMBER;      rx RX18 2 receipt-mismatch
dscn; RCT "$DNOW";                                                  rx RW0 0 -
dscn_past() { # a delegation recorded 20 days ago whose expiry day was 5 days ago (the act ran in between)
  dscn
  local c e d; c="$(dts -20)"; e="$(dts -5)"; e="${e%%T*}"; d="${c%%T*}"
  sed -e "s/@EXPIRY@/$e/" -e "s/@DATE@/$d/" "$DFX/delegation-valid.md" > "$STUB_DIR/body.md"
  jq -n --rawfile body "$STUB_DIR/body.md" --arg c "$c" --arg iu "https://api.github.com/repos/example-org/example-repo/issues/77" \
    '{id:1001, body:$body, user:{login:"owner-user", type:"User"}, author_association:"MEMBER", created_at:$c, updated_at:$c, issue_url:$iu}' > "$STUB_DIR/comment-1001.json"
}
dscn_past; RCT "$(dts -6)"; mkdr rwp1 "$(dts -6)"; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "RWP1: a receipt written on the day of the act passes even though the delegation has expired since"
dscn_past; RCT "$(dts -1)"; mkdr rwp2 "$(dts -6)"; run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "RWP2: a receipt written AFTER the delegation's expiry day ended is receipt-mismatch (it cannot vouch for an in-window act)"
assert_reason "receipt-mismatch" "RWP2"
dscn; RCT "$DNOW"; mkdr ax5 "$(dts 5)"; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "AX5: a ran time in the future is delegation-invalid (an act cannot have run yet), even inside the delegation's window"
assert_reason "delegation-invalid" "AX5"
assert_eq "0" "$(ncalls 'issues/comments/1001')" "AX5b: it is refused before any verifier call"

# CLK (Guard 1 bypass detector): under a yesterday pin a `ran` of $DNOW reads as FUTURE, so the
# pristine gate refuses delegation-invalid (rc 1) before any verifier call -- a verdict only a
# live stub can produce. A bypassed or missing stub reads the real clock: the same fixture then
# reads ran-in-past and the row fails receipt-missing (rc 2). This case reddens on ANY calendar
# day, so the pin cannot rot silently. The noon pin is restored unconditionally below (never
# &&-chained -- a failed assert must not skip the restore and poison every later case).
dclock_at "$(dts -1)"
dscn; mkdr clk "$AT"; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "CLK: under a yesterday pin, ran=$DNOW is delegation-invalid (the stub is load-bearing)"
assert_reason "delegation-invalid" "CLK yesterday pin"
assert_eq "0" "$(ncalls 'issues/comments/1001')" "CLKb: the refusal lands before any verifier call"
dclock_at "$DNOON"
assert_eq "$(jq -rn --arg p "$(cat "$DBIN/clock")" '$p | fromdateiso8601')" "$(cat "$DBIN/clock.epoch")" "CLK2: clock and clock.epoch stay consistent after a repin"
assert_eq "$(cat "$DBIN/clock.epoch")" "$("$DBIN/date" -u +%s)" "CLK3: the stub serves clock.epoch on -u +%s (a partial passthrough cannot hide)"
assert_eq "${DNOON%%T*}" "$("$DBIN/date" -u +%Y-%m-%d)" "CLK4: the stub serves the pin's day on -u +%Y-%m-%d"

echo "=== Arm 6g3: a receipt is written AFTER the act it vouches for (verification V8) ==="
dscn_past; RCPT_CREATED="$(dts -10)" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr rv8 "$(dts -6)"; run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "RV8: a receipt created before the ran time (but inside the delegation's life) is receipt-mismatch"
assert_reason "receipt-mismatch" "RV8"
dscn_past; RCPT_CREATED="$(dts -6)" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr rv8b "$(dts -6)"; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "RV8b: a receipt created at the ran instant passes"
dscn_past; RCPT_CREATED="$(dts -5)" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr rv8c "$(dts -6)"; run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "RV8c: a receipt created after the ran time passes"

echo "=== Arm 6g4: a time-limit tool is required (timeout OR gtimeout), and its absence is a plain refusal (verification V9a) ==="
mkbin_t() { # <dir> <tools to leave out...>: reduced PATH with the gate's tools, the stub wrapper and its base stub
  local d="$1" t o p; shift; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d"
  for t in bash git jq awk sed tr cut grep cat head tail wc mktemp rm dirname basename cmp date sort uniq env sleep timeout expr tee touch mkdir ln cp mv ls id uname xargs true false find stat sha256sum shasum openssl od readlink realpath; do
    for o in "$@"; do [[ "$t" == "$o" ]] && continue 2; done
    p="$(command -v "$t" 2>/dev/null)"; [[ "$p" == /* && -x "$p" ]] && ln -sf "$p" "$d/$t"
  done
  cp "$DBIN/gh" "$d/gh"; cp "$DBIN/gh-base" "$d/gh-base"
  # The same pin, not the real clock (#11578): the reduced PATH serves the suite clock via the
  # stub plus live symlinks to $DBIN's pin files, so a future-dependent fixture under a DPATH
  # case cannot silently bypass the pin (its dispatches log to $d/dcalls.log, not $DBIN's).
  ln -sf "$DBIN/date" "$d/date"; ln -sf "$DBIN/clock" "$d/clock"; ln -sf "$DBIN/clock.epoch" "$d/clock.epoch"
}
mkbin_t "$TMP/tbin-none" timeout
mkbin_t "$TMP/tbin-g" timeout; ln -sf "$(command -v timeout)" "$TMP/tbin-g/gtimeout"
mkbin_t "$TMP/tbin-ok"
dscn; mkd tq0 deleg-valid.md; DPATH="$TMP/tbin-ok" run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "TQ0: the reduced PATH itself passes a valid row (instrument control)"
dscn; mkd tq1 deleg-valid.md; DPATH="$TMP/tbin-none" run_d "$GATE" "$DF"
assert_eq "2" "$(last_rc)" "TQ1: with neither timeout nor gtimeout a delegation row is exit 2, never an unbounded call"
assert_reason "delegation-unverifiable" "TQ1"
assert_eq "1" "$(grep -c 'time limit tool' "$TMP/last.err" || true)" "TQ1b: and the reason is named in plain words"
assert_eq "0" "$(ncalls 'issues/comments/1001')" "TQ1c: nothing was read from GitHub"
dscn; mkd tq2 deleg-valid.md; DPATH="$TMP/tbin-g" run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "TQ2: gtimeout alone is enough (macOS with coreutils)"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr tq3 "$AT"; DPATH="$TMP/tbin-g" run_d "$GATE" "$DF"
assert_eq "0" "$(last_rc)" "TQ3: gtimeout alone also bounds the receipt read (a ran row passes)"

echo "=== Arm 6h: one verifier call per (delegation, envelope, time), one receipt read per epic ==="
cat > "$TMP/df/memo-same.md" <<EOF
# Decision challenges - two rows, one delegation and one envelope (synthesized)

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| O1 first merge | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md, ran $AT |
| O2 second merge | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md, ran $AT |
EOF
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-same.md"
assert_eq "2" "$(last_rc)" "MX1: two rows that need the SAME receipt: the second finds none left (one receipt satisfies one row)"
assert_eq "1" "$(grep -cE '^\[FAIL\] .*: receipt-missing - ' "$TMP/last.err" || true)" "MX1a: exactly one row, the second, is receipt-missing"
assert_eq "2" "$(dlog_count)" "MX1b: both rows were examined"
assert_eq "1" "$(ncalls 'issues/comments/1001')" "MX1c: the delegation comment was read once"
assert_eq "1" "$(ncalls 'issues/77/comments')" "MX1d: the epic's comments were read once"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-same.md"
assert_eq "0" "$(last_rc)" "MX1e: with one receipt per row both rows pass"
cat > "$TMP/df/memo-mixed.md" <<EOF
# Decision challenges - an audited row, then a strict row, same delegation and envelope (synthesized)

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| O1 the act that ran | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md, ran $AT |
| O2 the next act, not yet run | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md |
EOF
dscn; echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-mixed.md"
assert_eq "1" "$(last_rc)" "MX3: a strict row after an audited row of the same delegation and envelope never inherits the audited verdict (closed epic: exit 1)"
assert_eq "1" "$(grep -cE '^\[FAIL\] .*: delegation-invalid - ' "$TMP/last.err" || true)" "MX3b: exactly the strict row is delegation-invalid"
assert_eq "2" "$(ncalls 'issues/comments/1001')" "MX3c: the two audit times were verified separately"
cat > "$TMP/df/memo-env.md" <<EOF
# Decision challenges - two rows, two envelope addresses (synthesized)

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| O1 first merge | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md, ran $AT |
| O2 second merge | operator (production-mutating) | Authorized by delegation $DURL1, envelope env-valid.md#first merge, ran $AT |
EOF
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; rcpt "$DURL1" "env-valid.md#first merge" "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-env.md"
assert_eq "0" "$(last_rc)" "MX2: two envelope addresses of one delegation pass with a receipt each"
assert_eq "2" "$(ncalls 'issues/comments/1001')" "MX2b: a different envelope address is verified separately"
assert_eq "1" "$(ncalls 'issues/77/comments')" "MX2c: but the epic's comments are still read once"

echo "=== Arm 6i: no call can swallow the gate's own row loop (stdin is closed) ==="
dscn; touch "$STUB_DIR/eat-stdin"; mkd si1 deleg-two-rows.md; run_d "$GATE" "$DF"
assert_eq "1" "$(last_rc)" "SI1: a gh that drains stdin does not hide the second delegation row (valid, then edited: exit 1)"
assert_eq "2" "$(dlog_count)" "SI1b: both rows were examined"
dscn; touch "$STUB_DIR/eat-stdin"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; rcpt "$DURL1" "env-valid.md#first merge" "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-env.md"
assert_eq "0" "$(last_rc)" "SI2: the receipt read does not swallow the second ran row either"
assert_eq "2" "$(dlog_count)" "SI2b: both ran rows were examined"
assert_eq "1" "$([ "$(wc -l < "$STUB_DIR/stdin-bytes" | tr -d ' ')" -ge 4 ] && echo 1 || echo 0)" "SI2c: and there were gh calls to see an empty stdin"
assert_eq "0" "$(grep -vcx 0 "$STUB_DIR/stdin-bytes")" "SI2d: every gh call saw an empty stdin"

echo "=== Arm 6j: the verifier's rc and first line must agree (a fake verifier in a mirrored tree) ==="
mkdir -p "$TMP/dm/fakeg/skills/ship/scripts" "$TMP/dm/fakeg/scripts"; cp "$GATE" "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh"
cat > "$TMP/dm/fakeg/scripts/delegation-verify.sh" <<'FAKEV'
#!/usr/bin/env bash
cat >/dev/null
[ -z "${FAKE_V_SLEEP-}" ] || exec sleep "$FAKE_V_SLEEP"
[ -z "${FAKE_V_OUT-}" ] || printf '%b' "$FAKE_V_OUT"
exit "${FAKE_V_RC:-0}"
FAKEV
fakeg() { # <out> <rc> <fixture>
  dscn; mkd fg "$3"; export FAKE_V_OUT="$1" FAKE_V_RC="$2"
  run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; unset FAKE_V_OUT FAKE_V_RC
}
fakeg 'delegation: valid reason=ok\n' 0 deleg-valid.md
assert_eq "0" "$(last_rc)" "FG1: rc 0 with a valid first line passes (instrument control)"
fakeg 'delegation: invalid reason=expired\n' 0 deleg-valid.md
assert_eq "2" "$(last_rc)" "FG2: rc 0 with an invalid first line is exit 2: the gate reads both, never the rc alone"
assert_reason "delegation-unverifiable" "FG2"
fakeg '' 0 deleg-valid.md
assert_eq "2" "$(last_rc)" "FG3: a verifier that prints nothing is exit 2"
fakeg 'delegation: valid reason=ok\n' 1 deleg-valid.md
assert_eq "1" "$(last_rc)" "FG4: rc 1 is delegation-invalid whatever else it printed"
dscn; mkdr fg5 "$AT"; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0; run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; unset FAKE_V_OUT FAKE_V_RC
assert_eq "2" "$(last_rc)" "FG5: a ran row whose verifier reports no fingerprint is exit 2"
assert_reason "receipt-unreadable" "FG5"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr fg6 "$AT"; export FAKE_V_OUT='delegation: valid reason=ok\nverified-envelope-sha256: '"$SHA_ENV1"'\n' FAKE_V_RC=0; run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; unset FAKE_V_OUT FAKE_V_RC
assert_eq "2" "$(last_rc)" "FG6: a ran row whose verifier reports no delegation dates is exit 2 (the receipt window cannot be checked)"
assert_reason "receipt-unreadable" "FG6"
dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr fg7 "$AT"; export FAKE_V_OUT='delegation: valid reason=ok\nverified-created-at: '"$DNOW"'\nverified-expiry: '"$DEXP"'\nverified-envelope-sha256: '"$SHA_ENV1"'\n' FAKE_V_RC=0; run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; unset FAKE_V_OUT FAKE_V_RC
assert_eq "0" "$(last_rc)" "FG7: with fingerprint and dates the fake verifier's ran row passes (instrument control for FG6)"
if command -v timeout >/dev/null 2>&1; then
  dscn; mkd vt deleg-valid.md; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0 FAKE_V_SLEEP=8 TRG_VERIFY_TIMEOUT=2
  t0=$SECONDS; run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; el=$((SECONDS - t0)); unset FAKE_V_OUT FAKE_V_RC FAKE_V_SLEEP TRG_VERIFY_TIMEOUT
  assert_eq "2" "$(last_rc)" "VT1: a verifier that never answers is exit 2, never a pass (testdesign N15)"
  assert_eq "1" "$(grep -c 'delegation-unverifiable - ' "$TMP/last.err" || true)" "VT1b: the finding is delegation-unverifiable"
  assert_eq "1" "$([ "$el" -lt 6 ] && echo 1 || echo 0)" "VT1c: it was cut off at the shortened limit (took ${el}s, not the 8s the fake sleeps)"
fi

echo "=== Arm 6b: archived artifacts are checked for shape only (no network) ==="
dscn; echo net > "$STUB_DIR/mode-repo"; mkd arch deleg-valid.md
DSPECS="$TMP/dspecs"; mkdir -p "$DSPECS/archive/20260101-feat-dz"; cp "$DF" "$DSPECS/archive/20260101-feat-dz/decision-challenges.md"
export TRG_SPECS_ROOT="$DSPECS"; TRG_BRANCH=feat-dz run_d "$GATE" --branch; unset TRG_SPECS_ROOT
assert_eq "0" "$(last_rc)" "an archived artifact with a well-shaped delegation row passes without verification"
assert_eq "0" "$(cat "$STUB_DIR/calls.log" 2>/dev/null | wc -l | tr -d ' ')" "the archive lookup made no gh call"
assert_eq "1" "$(grep -c 'shape only and are NOT verified' "$TMP/last.err" || true)" "AR1: the archive note says delegation rows are shape-checked only and NOT verified"
assert_eq "1" "$(grep -c '^\[PASS\] .*archived: 1 delegation rows were checked for shape only and were NOT verified' "$TMP/last.out" || true)" "AR2: the PASS line says so too, with the count"
dscn; echo net > "$STUB_DIR/mode-repo"; mkdr archran "$AT"; cp "$DF" "$DSPECS/archive/20260101-feat-dz/decision-challenges.md"
export TRG_SPECS_ROOT="$DSPECS"; TRG_BRANCH=feat-dz run_d "$GATE" --branch; unset TRG_SPECS_ROOT
assert_eq "0" "$(last_rc)" "AR3: an archived artifact with a ran row passes on shape, with no receipt read either"
assert_eq "0" "$(cat "$STUB_DIR/calls.log" 2>/dev/null | wc -l | tr -d ' ')" "AR3b: and no gh call was made"
cp "$TMP/example.md" "$DSPECS/archive/20260101-feat-dz/decision-challenges.md"
export TRG_SPECS_ROOT="$DSPECS"; TRG_BRANCH=feat-dz run_d "$GATE" --branch; unset TRG_SPECS_ROOT
assert_eq "1" "$(grep -c '^\[PASS\] [^ ]*: [0-9]* rows examined$' "$TMP/last.out" || true)" "AR4: an archived artifact with no delegation row keeps the plain PASS line"
dscn; mkd archbad deleg-bad-shape.md; cp "$DF" "$DSPECS/archive/20260101-feat-dz/decision-challenges.md"
export TRG_SPECS_ROOT="$DSPECS"; TRG_BRANCH=feat-dz run_d "$GATE" --branch; unset TRG_SPECS_ROOT
assert_eq "1" "$(last_rc)" "an archived artifact with a malformed delegation row still fails"

echo "=== Arm 6c: a missing verifier is exit 2 ==="
mkdir -p "$TMP/dm/lonely/skills/ship/scripts"; cp "$GATE" "$TMP/dm/lonely/skills/ship/scripts/technical-ruling-gate.sh"
dscn; mkd lonely deleg-valid.md; run_d "$TMP/dm/lonely/skills/ship/scripts/technical-ruling-gate.sh" "$DF"
assert_eq "2" "$(last_rc)" "no verifier next to the gate: exit 2, never a pass"

echo "=== Arm 6d: mutations of the delegation arm (mirrored tree so the verifier resolves) ==="
mutate_d() { # <name> <sed -E expr>
  local d="$TMP/dm/$1"; mkdir -p "$d/skills/ship/scripts" "$d/scripts"
  cp "$REPO_ROOT/plugins/soleur/scripts/delegation-verify.sh" "$d/scripts/"
  sed -E "$2" "$GATE" > "$d/skills/ship/scripts/technical-ruling-gate.sh"
  if cmp -s "$GATE" "$d/skills/ship/scripts/technical-ruling-gate.sh"; then
    echo "  FAIL: mutation $1 did not land"; FAIL=$((FAIL + 1)); return 1
  fi
  echo "  PASS: mutation $1 landed"; PASS=$((PASS + 1))
}
dnoop() { echo "s/^.*# mut:$1\$/: # mut:$1/"; }
killed_d() { # <name> <pinned-rc> <logged-delegation-rows-or--> <gate args...>; the scenario is already built
  local name="$1" pinned="$2" want_log="$3"; shift 3
  run_d "$GATE" "$@"
  if [[ "$(last_rc)" != "$pinned" ]]; then echo "  FAIL: $name: the pristine gate gives rc $(last_rc), not the pinned $pinned"; FAIL=$((FAIL + 1)); return; fi
  if [[ "$want_log" != "-" && "$(dlog_count)" != "$want_log" ]]; then echo "  FAIL: $name: the pristine gate logged $(dlog_count) delegation rows, not $want_log"; FAIL=$((FAIL + 1)); return; fi
  run_d "$TMP/dm/$name/skills/ship/scripts/technical-ruling-gate.sh" "$@"
  if mutant_crashed; then echo "  FAIL: mutant $name CRASHED (rc $(last_rc)); a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$(last_rc)" != "$pinned" || ( "$want_log" != "-" && "$(dlog_count)" != "$want_log" ) ]]; then echo "  PASS: mutant $name killed (rc $(last_rc), delegation rows logged $(dlog_count))"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant $name SURVIVED"; FAIL=$((FAIL + 1)); fi
}
# 1 the verifier's answer is ignored
mutate_d deleg-call 's/; dv_rc=\$\? # mut:deleg-call/; dv_rc=0 # mut:deleg-call/' && { dscn; mkd mi deleg-valid.md; sed 's/-1001/-1002/g;s/env-valid.md/env-valid-2.md/' "$DF" > "$TMP/df/mi2.md"; killed_d deleg-call 1 - "$TMP/df/mi2.md"; }
# 2 the exec-log line is the dispatch floor
mutate_d deleg-log "$(dnoop deleg-log)" && { dscn; mkd ml deleg-valid.md; killed_d deleg-log 0 1 "$DF"; }
# 3 stopping at the first delegation row
mutate_d deleg-all 's/; continue; fi # mut:deleg-all/; break; fi # mut:deleg-all/' && { dscn; mkd mt deleg-two-rows.md; killed_d deleg-all 1 2 "$DF"; }
# 4 the class conjunct
mutate_d deleg-class "$(dnoop deleg-class)" && { dscn; mkd mc deleg-wrong-class.md; killed_d deleg-class 1 - "$DF"; }
# 5 unverifiable mapped to a pass
mutate_d deleg-unv "$(dnoop deleg-unv)" && { dscn; echo 404 > "$STUB_DIR/mode-comment-1001"; mkd mu deleg-valid.md; killed_d deleg-unv 2 - "$DF"; }
# 6 a delegation row outside a table is honoured
mutate_d stray-deleg '/# mut:stray-deleg$/ s/print "@STRAY"/x = 1/' && { dscn; mkd ms deleg-stray.md; killed_d stray-deleg 2 - "$DF"; }

# 7 R3: the audit time and the audit mode are what a row with ran is verified at
mutate_d deleg-audit 's/ --audit --at "\$dran"//' && { dscn; echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr m7 "$AT"; killed_d deleg-audit 0 - "$DF"; }
mutate_d deleg-at 's/ --at "\$dran"//' && { dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr m8 "$(dts -1)"; killed_d deleg-at 1 - "$DF"; }
# 8 the envelope is part of the call
mutate_d deleg-env 's/ --envelope "\$dpath"//' && { dscn; mkd m9 deleg-valid.md; sed 's/env-valid\.md/env-nonexistent.md/' "$DF" > "$TMP/df/m9b.md"; killed_d deleg-env 1 - "$TMP/df/m9b.md"; }
# 9 stdin is closed on the verifier call and on the receipt read
# (the real verifier never reads stdin, so the fake one that drains it stands in, in both trees)
mutate_d stdin-verify 's# </dev/null >"\$work_dir/dv\.\$n\.out"# >"$work_dir/dv.$n.out"#' && {
  cp "$TMP/dm/fakeg/scripts/delegation-verify.sh" "$TMP/dm/stdin-verify/scripts/delegation-verify.sh"
  dscn; mkd m10 deleg-two-rows.md; export FAKE_V_OUT='delegation: valid reason=ok\n' FAKE_V_RC=0
  run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; pl="$(dlog_count)"
  run_d "$TMP/dm/stdin-verify/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; ml="$(dlog_count)"; unset FAKE_V_OUT FAKE_V_RC
  if [[ "$pl" == 2 && "$ml" != 2 ]]; then echo "  PASS: mutant stdin-verify killed (rows examined $pl -> $ml)"; PASS=$((PASS + 1)); else echo "  FAIL: mutant stdin-verify SURVIVED (rows examined $pl -> $ml)"; FAIL=$((FAIL + 1)); fi
}
mutate_d stdin-receipt 's#2>/dev/null </dev/null \\$#2>/dev/null \\#' && { dscn; touch "$STUB_DIR/eat-stdin"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; rcpt "$DURL1" "env-valid.md#first merge" "$SHA_ENV1" ok MEMBER; killed_d stdin-receipt 0 2 "$TMP/df/memo-env.md"; }
# 10 the class and phrase are matched exactly
mutate_d case-off "$(dnoop case-off)" && { dscn; mkd m11 deleg-valid.md; sed 's/| operator (production-mutating) |/| Operator (Production-Mutating) |/' "$DF" > "$TMP/df/m11b.md"; killed_d case-off 1 - "$TMP/df/m11b.md"; }
# 11 each part of a receipt must match (a perfect receipt that differs in ONE part)
mrcpt() { # <mutant> <delegation> <envelope> <sha> <result> <assoc>
  dscn; rcpt "$2" "$3" "$4" "$5" "$6"; mkdr "m-$1" "$AT"; killed_d "$1" 2 - "$DF"
}
mutate_d receipt-deleg "$(dnoop receipt-deleg)" && mrcpt receipt-deleg "$DURL2" env-valid.md "$SHA_ENV1" ok MEMBER
mutate_d receipt-env "$(dnoop receipt-env)" && mrcpt receipt-env "$DURL1" other-envelope.md "$SHA_ENV1" ok MEMBER
mutate_d receipt-sha "$(dnoop receipt-sha)" && mrcpt receipt-sha "$DURL1" env-valid.md "$(printf '%064d' 1)" ok MEMBER
mutate_d receipt-result "$(dnoop receipt-result)" && mrcpt receipt-result "$DURL1" env-valid.md "$SHA_ENV1" failed MEMBER
mutate_d receipt-author "$(dnoop receipt-author)" && mrcpt receipt-author "$DURL1" env-valid.md "$SHA_ENV1" ok NONE
# 12 the verifier's first line is read as well as its rc (a fake verifier installed in the mutant's tree)
mutate_d deleg-line "$(dnoop deleg-line)" && {
  cp "$TMP/dm/fakeg/scripts/delegation-verify.sh" "$TMP/dm/deleg-line/scripts/delegation-verify.sh"
  dscn; mkd m12 deleg-valid.md; export FAKE_V_OUT='delegation: invalid reason=expired\n' FAKE_V_RC=0
  run_d "$TMP/dm/fakeg/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; pr="$(last_rc)"
  run_d "$TMP/dm/deleg-line/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; mr="$(last_rc)"; unset FAKE_V_OUT FAKE_V_RC
  if [[ "$pr" == 2 && "$mr" != 2 ]]; then echo "  PASS: mutant deleg-line killed (pristine rc $pr, mutant rc $mr)"; PASS=$((PASS + 1)); else echo "  FAIL: mutant deleg-line SURVIVED or the control moved (pristine $pr, mutant $mr)"; FAIL=$((FAIL + 1)); fi
}
# 13 memoisation: the same (delegation, envelope, time) is verified once and the epic is read once
mutate_d memo 's/^memo_find\(\) \{.*# mut:memo$/memo_find() { return 0; } # mut:memo/' && {
  dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; run_d "$GATE" "$TMP/df/memo-same.md"; pv="$(ncalls 'issues/comments/1001')"; pe="$(ncalls 'issues/77/comments')"
  dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; run_d "$TMP/dm/memo/skills/ship/scripts/technical-ruling-gate.sh" "$TMP/df/memo-same.md"; mv_="$(ncalls 'issues/comments/1001')"; me="$(ncalls 'issues/77/comments')"
  if mutant_crashed; then echo "  FAIL: mutant memo CRASHED"; FAIL=$((FAIL + 1))
  elif [[ "$pv" == 1 && "$pe" == 1 && "$mv_" == 2 && "$me" == 2 ]]; then echo "  PASS: mutant memo killed (verifier calls $pv -> $mv_, epic reads $pe -> $me)"; PASS=$((PASS + 1))
  else echo "  FAIL: mutant memo SURVIVED (verifier calls $pv -> $mv_, epic reads $pe -> $me)"; FAIL=$((FAIL + 1)); fi
}

mutate_d receipt-before-ran "$(dnoop receipt-before-ran)" && { dscn_past; RCPT_CREATED="$(dts -10)" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr m24 "$(dts -6)"; killed_d receipt-before-ran 2 - "$DF"; }
mutate_d need-timeout "$(dnoop need-timeout)" && {
  dscn; mkd m25 deleg-valid.md; DPATH="$TMP/tbin-none"
  run_d "$GATE" "$DF"; pw="$(grep -c 'time limit tool (timeout or gtimeout)' "$TMP/last.err" || true)"
  run_d "$TMP/dm/need-timeout/skills/ship/scripts/technical-ruling-gate.sh" "$DF"; mw="$(grep -c 'time limit tool (timeout or gtimeout)' "$TMP/last.err" || true)"; unset DPATH
  if [[ "$pw" == 1 && "$mw" == 0 ]]; then echo "  PASS: mutant need-timeout killed (the gate's own refusal $pw -> $mw; the verifier's tool-missing would still exit 2)"; PASS=$((PASS + 1)); else echo "  FAIL: mutant need-timeout SURVIVED ($pw -> $mw)"; FAIL=$((FAIL + 1)); fi
}
mutate_d gtimeout 's/command -v gtimeout/command -v gtimeout-zz/' && { dscn; mkd m26 deleg-valid.md; DPATH="$TMP/tbin-g"; killed_d gtimeout 0 - "$DF"; unset DPATH; }
# 14 R3 receipt binding and the audit-time memo key
mutate_d memo-key 's/key="\$durl\|\$dpath\|\$dran"/key="$durl|$dpath"/' && { dscn; echo '{"number":77,"state":"closed"}' > "$STUB_DIR/issue-77.json"; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; killed_d memo-key 1 2 "$TMP/df/memo-mixed.md"; }
mutate_d ran-future "$(dnoop ran-future)" && { dscn; RCT "$DNOW"; mkdr m15 "$(dts 5)"; killed_d ran-future 1 - "$DF"; }
mutate_d receipt-future "$(dnoop receipt-future)" && { dscn; RCT "$(dts 1)"; mkdr m17 "$AT"; killed_d receipt-future 2 - "$DF"; }
mutate_d receipt-expiry "$(dnoop receipt-expiry)" && { dscn_past; RCT "$(dts -1)"; mkdr m18 "$(dts -6)"; killed_d receipt-expiry 2 - "$DF"; }
mutate_d receipt-edited "$(dnoop receipt-edited)" && { dscn; RCPT_UPDATED="${DTODAY}T00:07:00Z" rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr m19 "$AT"; killed_d receipt-edited 2 - "$DF"; }
mutate_d receipt-bot "$(dnoop receipt-bot)" && { dscn; RCPT_TYPE=Bot rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok COLLABORATOR; mkdr m20 "$AT"; killed_d receipt-bot 2 - "$DF"; }
mutate_d receipt-consume "$(dnoop receipt-consume)" && { dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok MEMBER; killed_d receipt-consume 2 2 "$TMP/df/memo-same.md"; }
mutate_d receipt-assoc-default 's/\(\.author_association \/\/ "ABSENT"\)/(.author_association \/\/ "MEMBER")/' && { dscn; rcpt "$DURL1" env-valid.md "$SHA_ENV1" ok ABSENT; mkdr m21 "$AT"; killed_d receipt-assoc-default 2 - "$DF"; }
mutate_d receipt-deleg-prefix 's/== "\$durl" \]\] \|\| continue/== "$durl"* ]] || continue/' && { dscn; rcpt "${DURL1}9" env-valid.md "$SHA_ENV1" ok MEMBER; mkdr m22 "$AT"; killed_d receipt-deleg-prefix 2 - "$DF"; }
mutate_d receipt-env-prefix 's/== "\$env" \]\] \|\| continue/== "$env"* ]] || continue/' && { dscn; rcpt "$DURL1" "env-valid.md#extra" "$SHA_ENV1" ok MEMBER; mkdr m23 "$AT"; killed_d receipt-env-prefix 2 - "$DF"; }

echo "=== Arm 6k: the verdict helpers are under controls (testdesign F4) ==="
no_miss_ctl() { # no_miss must go red on a STUB-MISS log and stay green on a clean one
  mkdir -p "$TMP/ctl-nm1" "$TMP/ctl-nm2"; printf 'STUB-MISS api x\n' > "$TMP/ctl-nm1/calls.log"; printf 'api repos/o/r/issues/1\n' > "$TMP/ctl-nm2/calls.log"
  ( b=$FAIL; STUB_DIR="$TMP/ctl-nm1"; no_miss ctl >/dev/null; [[ $FAIL -eq $((b + 1)) ]] ) || return 1
  ( b=$FAIL; STUB_DIR="$TMP/ctl-nm2"; no_miss ctl >/dev/null; [[ $FAIL -eq $b ]] ) || return 1
}
no_miss_ctl || { printf 'FATAL: no_miss cannot tell a refused argv from a clean log\n' >&2; exit 2; }
write_audit() { # <calls.log files...>: lines that are neither a read shape nor a known stub shape
  cat "$@" 2>/dev/null | grep -vcE '^(api repos/[A-Za-z0-9_./-]+( --paginate)?|repo view --json nameWithOwner --jq \.nameWithOwner)$' || true
}
printf 'api -X POST repos/o/r/issues/1/comments\nissue comment 5\n' > "$TMP/ctl-nm1/audit.log"
[[ "$(write_audit "$TMP/ctl-nm1/audit.log")" == 2 ]] || { printf 'FATAL: the zero-write audit cannot see a write verb\n' >&2; exit 2; }
assert_eq "0" "$(write_audit "$TMP"/dscn*/calls.log)" "ZW1: no gh call in any delegation scenario was anything but a read (testdesign N9)"
assert_eq "0" "$(cat "$TMP"/dscn*/calls.log | grep -c 'STUB-MISS' || true)" "ZW2: and no scenario hit a refused argv"
( echo 127 > "$TMP/last.rc"; : > "$TMP/last.err"; mutant_crashed ) \
  || { printf 'FATAL: mutant_crashed cannot see rc 127\n' >&2; exit 2; }
( echo 0 > "$TMP/last.rc"; echo 'x.sh: line 3: v: unbound variable' > "$TMP/last.err"; mutant_crashed ) \
  || { printf 'FATAL: mutant_crashed cannot see an unbound variable\n' >&2; exit 2; }
( echo 1 > "$TMP/last.rc"; : > "$TMP/last.err"; mutant_crashed ) \
  && { printf 'FATAL: mutant_crashed reports a clean rc 1 as a crash\n' >&2; exit 2; }
mutate_d ctl 's/^# The \/ship Phase 5\.5/# The \/ship phase 5.5/' >/dev/null
dscn; mkd kc deleg-valid.md
( b=$FAIL; killed_d ctl 0 1 "$DF" >/dev/null; [[ $FAIL -gt $b ]] ) \
  || { printf 'FATAL: killed_d cannot report a survivor -- a mutant that changes nothing would be graded as killed\n' >&2; exit 2; }
mutate_d crashctl 's/^set -uo pipefail$/set -uo pipefail; if then/' >/dev/null
( out="$(killed_d crashctl 0 1 "$DF")"; [[ "$out" == *CRASHED* ]] ) \
  || { printf 'FATAL: killed_d cannot report a crashing mutant -- a crash would be graded as a kill\n' >&2; exit 2; }
echo "  PASS: the crash detector and the survivor detector can fail"; PASS=$((PASS + 1))

echo "=== Floor: the SUT wrote an execution marker per examined row ==="
n_rows="$(wc -l < "$EXEC_LOG" | tr -d ' ')"
# Zero-slack floors, committed from a green run: re-measure and raise them when rows are added; a lower number is a deleted row.
if (( n_rows >= 222 )); then
  echo "  PASS: SUT execution markers $n_rows >= 222"; PASS=$((PASS + 1))
else
  echo "  FAIL: SUT execution markers $n_rows < 222 -- the cases above did not drive the script"; FAIL=$((FAIL + 1))
fi

# Date-stub dispatch floor (Guard 1): every `date` argv the SUT dispatched under run_d's PATH is
# logged. The count is a zero-slack floor committed from a measured green run (raise it when a
# consumer is added); a stub never invoked reads 0 and cannot pass vacuously, and a passthrough
# bypass is already red via CLK. The argv set is closed: a fifth shape exits 64 in the open, so a
# matching count carrying foreign argv cannot sneak past.
dc_n=0
if [ -f "$DBIN/dcalls.log" ]; then dc_n="$(wc -l < "$DBIN/dcalls.log" | tr -d ' ')"; fi
# The VT1 arm is `command -v timeout`-gated: on a gtimeout-only host it skips and 2 dispatches
# never happen, so the committed floor steps down rather than false-fail a correct suite.
dc_floor=330; command -v timeout >/dev/null 2>&1 || dc_floor=328
if (( dc_n >= dc_floor )); then
  echo "  PASS: date-stub dispatches $dc_n >= $dc_floor"; PASS=$((PASS + 1))
else
  echo "  FAIL: date-stub dispatches $dc_n < $dc_floor -- the pin was bypassed or a consumer stopped calling date"; FAIL=$((FAIL + 1))
fi
dc_bad="$(grep -vcE '^-u \+%Y-%m-%dT%H:%M:%SZ$|^-u \+%s$|^-u \+%Y-%m-%d$' "$DBIN/dcalls.log" 2>/dev/null || true)"
assert_eq "0" "$dc_bad" "CLKF: every dispatched date argv is one of the three sanctioned shapes"

# Ambient-arm sweep (Guard 1 completeness): a timestamp-bearing fixture (`mkdr`/`rcpt`/`RCT`)
# exec'd outside a pinned-PATH arm is the #11578 bomb reborn -- `run` and direct `bash "$GATE"`
# subshells see the real clock. A fixture token must pair (same or next line) with a
# pinned-PATH exec (`run_d`/`killed_d`/`mutate_d`/`rx`) or an instrument assertion; function
# definitions (`()`) and comments are excluded, and `\b` keeps `mrcpt`/`RCPT_*` out.
amb_n=0
while IFS= read -r hit; do
  hn="${hit%%:*}"
  sed -n "${hn},$((hn + 1))p" "$0" | grep -qE '\b(run_d|killed_d|mutate_d|assert_eq|assert_reason|rx)\b' || amb_n=$((amb_n + 1))
done < <(grep -nE '\b(mkdr|rcpt|RCT) ' "$0" | grep -vE ':[[:space:]]*#|\(\)')
assert_eq "0" "$amb_n" "AMBF: every timestamp-bearing fixture pairs with a pinned-PATH exec or an instrument assertion"

# 502 = 493 prior assertions + CLK rc/reason/verifier-call + CLK2/CLK3/CLK4 + dispatch/argv floors + AMBF.
print_results 502
