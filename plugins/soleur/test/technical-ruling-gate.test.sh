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
ln="$(grep -n 'T2 second row' "$FIXTURES/no-class.md" | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: bad-class - " "$TMP/last.err" || true)" "row1: the failure names the second row by its file line"
# Row 2 remedy text names the CTO spawn and the two-attempt cap.
run "$GATE" "$FIXTURES/unruled-technical.md"
assert_eq "1" "$(grep -cE 'soleur:engineering:cto.*two' "$TMP/last.err" || true)" "row2: remedy names the CTO and the two-attempt cap"
# Every table is scanned: the failing row sits in the SECOND table (a first-table-only scanner passes).
run "$GATE" "$FIXTURES/second-table.md"
ln="$(grep -n 'B second writer technical row' "$FIXTURES/second-table.md" | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: unruled-technical - " "$TMP/last.err" || true)" "second table: the unruled row of the later table is examined, by its file line"

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

for f in header-drift header-lower fence-unclosed empty-first; do
  run "$GATE" "$FIXTURES/$f.md"
  assert_eq "2" "$(last_rc)" "$f is exit 2 (could not measure), never a quiet WARN"
done
for f in fence-tilde fence-indent crlf ws-row escaped-pipe case-mixed later-unrelated-table; do
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
TRG_BRANCH=feat-nothing run "$GATE" --branch
assert_eq "0" "$(last_rc)" "--branch with no artifact anywhere is exit 0"
assert_eq "1" "$(grep -cF '[PASS] no decision-challenges artifact' "$TMP/last.out" || true)" "--branch absent artifact prints the PASS line"
unset TRG_SPECS_ROOT

echo "=== Arm 3: contract (producer/consumer and parity) ==="
# Extract the first fenced block after the '## 7. Canonical example' heading.
extract_example() {
  awk '/^## 7\. Canonical example/{on=1; next} on && /^```/{ if(inb){exit} inb=1; next } on && inb{print}' "$1"
}
extract_example "$REFERENCE" > "$TMP/example.md"
assert_eq "1" "$([[ -s "$TMP/example.md" ]] && echo 1 || echo 0)" "the reference carries a canonical example block"
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
cp "$REFERENCE" "$TMP/ref-mut.md"; sed -i 's/ | brand`/`/;s/`money | scope | priority | schedule | irreversible | production-mutating | legal-risk | brand`/`money | scope | priority | schedule | irreversible | production-mutating | legal-risk`/' "$TMP/ref-mut.md"
if parity_ok "$GATE" "$TMP/ref-mut.md" "$RULES"; then
  echo "  FAIL: row7: a category removed from the reference alone was not caught"; FAIL=$((FAIL + 1))
else
  echo "  PASS: row7: a category removed from the reference alone reddens parity"; PASS=$((PASS + 1))
fi
cp "$RULES" "$TMP/rules-mut.md"; sed -i "/\[id: $RULE_ID\]/s/brand/colour/Ig" "$TMP/rules-mut.md"
if parity_ok "$GATE" "$REFERENCE" "$TMP/rules-mut.md"; then
  echo "  FAIL: row7: the word brand dropped from the rule body was not caught"; FAIL=$((FAIL + 1))
else
  echo "  PASS: row7: dropping brand from the rule body reddens parity"; PASS=$((PASS + 1))
fi

cp "$RULES" "$TMP/rules-mut2.md"; sed -i "/\[id: $RULE_ID\]/s/legal-risk/legal/Ig" "$TMP/rules-mut2.md"
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
killed() { # <name> <script> <want-rc> <fixture-args...>: the mutant's verdict must DIFFER from the pinned one
  local name="$1" script="$2" pinned_rc="$3"; shift 3
  run "$script" "$@"
  if [[ "$(last_rc)" != "$pinned_rc" ]]; then
    echo "  PASS: mutant $name killed (rc $(last_rc), pinned $pinned_rc)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: mutant $name SURVIVED (rc still $pinned_rc)"; FAIL=$((FAIL + 1))
  fi
}
killed_count() { # <name> <script> <reason> <want-count> <fixture>: the mutant must change how many findings carry the reason
  local name="$1" script="$2" reason="$3" want="$4" fixture="$5" got
  run "$script" "$fixture"
  got="$(grep -cE "^\[FAIL\] .*: ${reason} - " "$TMP/last.err" || true)"
  if [[ "$got" != "$want" ]]; then
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
# row3: the row scanner finds nothing.
mutate zero-rows 's/^  # mut:scan$/  : > "$rows_file" # mut:scan/' && \
  killed zero-rows "$MUT/gate.zero-rows.sh" 0 "$FIXTURES/pass-mixed.md"
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
mutate label-plural 's/\(decision\|ruling\)s\? needed/(decision|ruling) needed/' && \
  killed label-plural "$MUT/gate.label-plural.sh" 1 "$FIXTURES/label-plural.md"
mutate label-alt 's/\|decision needed from the owner//' && \
  killed label-alt "$MUT/gate.label-alt.sh" 1 "$FIXTURES/label-alt.md"
mutate no-tilde 's/\(`\+\|~\+\)/(`+)/g' && \
  killed no-tilde "$MUT/gate.no-tilde.sh" 0 "$FIXTURES/fence-tilde.md"
mutate fence-indent '/# mut:fence/ s/\/\^ \{0,3\}\(/\/^(/' && \
  killed fence-indent "$MUT/gate.fence-indent.sh" 0 "$FIXTURES/fence-indent.md"
mutate fence-any-char 's/c == fc && n >= fn && //' && \
  killed fence-any-char "$MUT/gate.fence-any-char.sh" 1 "$FIXTURES/fence-mixed.md"
mutate no-state-reset 's/^    \{ end_table\(\) \}$/    { }/' && \
  killed no-state-reset "$MUT/gate.no-state-reset.sh" 0 "$FIXTURES/later-unrelated-table.md"
mutate no-crlf 's/^    \{ sub\(\/\\r\$\/, ""\) \}$/    { }/' && \
  killed no-crlf "$MUT/gate.no-crlf.sh" 0 "$FIXTURES/crlf.md"
mutate no-rtrim 's/ sub\(\/\[ \\t\]\+\$\/, "", line\);//' && \
  killed no-rtrim "$MUT/gate.no-rtrim.sh" 0 "$FIXTURES/ws-row.md"
mutate no-unclosed 's/if \(f\) print "@UNCLOSED"//' && \
  killed no-unclosed "$MUT/gate.no-unclosed.sh" 2 "$FIXTURES/fence-unclosed.md"
mutate no-badheader 's/print "@BADHEADER"; next/next/' && \
  killed no-badheader "$MUT/gate.no-badheader.sh" 2 "$FIXTURES/header-drift.md"
mutate no-empty 's/print "@EMPTY"//' && \
  killed no-empty "$MUT/gate.no-empty.sh" 2 "$FIXTURES/empty-first.md"
mutate branch-slash 's|safe="\$\{branch//\\//-\}"|safe="$branch"|' && \
  { TRG_BRANCH=feat/foo-bar TRG_SPECS_ROOT="$SPECS" killed branch-slash "$MUT/gate.branch-slash.sh" 1 --branch; }
mutate pr-body-empty 's/^    \[\[ -s "\$f" \]\] .*$/    :/' && \
  killed pr-body-empty "$MUT/gate.pr-body-empty.sh" 2 --pr-body "$TMP/empty-body.md"
mutate no-cap 's/^  \(\( n > 255 \)\) && n=255$/  :/' && \
  killed no-cap "$MUT/gate.no-cap.sh" 1 --pr-body "$TMP/wrap.md"
mutate no-ambig 's/^    \(\( \$\{#matches\[@\]\} == 1 \)\) .*$/    :/' && \
  { TRG_BRANCH=feat-baz-qux TRG_SPECS_ROOT="$SPECS" killed no-ambig "$MUT/gate.no-ambig.sh" 2 --branch; }

echo "=== Floor: the SUT wrote an execution marker per examined row ==="
n_rows="$(wc -l < "$EXEC_LOG" | tr -d ' ')"
if (( n_rows >= 40 )); then
  echo "  PASS: SUT execution markers $n_rows >= 40"; PASS=$((PASS + 1))
else
  echo "  FAIL: SUT execution markers $n_rows < 40 -- the cases above did not drive the script"; FAIL=$((FAIL + 1))
fi

print_results 176
