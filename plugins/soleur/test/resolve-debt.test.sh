#!/usr/bin/env bash
# Tests for /soleur:resolve-debt skill (resolve-debt.py).
# Run: bash plugins/soleur/test/resolve-debt.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCRIPT="$REPO_ROOT/plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/resolve-debt"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "=== resolve-debt ==="
echo ""

assert_file_exists "$SCRIPT" "T0: script file exists"

# ---------------------------------------------------------------------------
# T10 — --help exits 0 with usage block
# ---------------------------------------------------------------------------
echo ""
echo "--- T10: --help ---"
out=$(python3 "$SCRIPT" --help 2>&1)
rc=$?
assert_eq "0" "$rc" "T10: --help exits 0"
assert_contains "$out" "--list" "T10: usage mentions --list"
assert_contains "$out" "--no-verify" "T10: usage mentions --no-verify"

# ---------------------------------------------------------------------------
# T3 — --list on empty ledger
# ---------------------------------------------------------------------------
echo ""
echo "--- T3: --list empty-ledger ---"
set +e
out=$(python3 "$SCRIPT" --list --ledger "$FIXTURE_DIR/empty-ledger" 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "T3: --list empty exits 0"
assert_contains "$out" "No open debt entries" "T3: empty-state message"

# ---------------------------------------------------------------------------
# T2 — --list against typical fixture
# ---------------------------------------------------------------------------
echo ""
echo "--- T2: --list typical fixture ---"
out=$(python3 "$SCRIPT" --list --ledger "$FIXTURE_DIR/typical" 2>&1)
rc=$?
assert_eq "0" "$rc" "T2: --list typical exits 0"
# 3 open + 1 resolved → 3 rows
assert_contains "$out" "legacy-schema-fixture" "T2: lists legacy-schema entry"
assert_contains "$out" "current-schema-fixture" "T2: lists current-schema entry"
assert_contains "$out" "low-severity-fixture" "T2: lists low-severity entry"
# Resolved entry is filtered out
if echo "$out" | grep -q "already-resolved-fixture"; then
  echo "  FAIL: T2: --list must filter out status: resolved entries"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: T2: --list filters out resolved entries"
  PASS=$((PASS + 1))
fi

# Severity sort order: high (legacy) before medium (current) before low
high_line=$(echo "$out" | grep -n "legacy-schema-fixture" | head -1 | cut -d: -f1)
med_line=$(echo "$out" | grep -n "current-schema-fixture" | head -1 | cut -d: -f1)
low_line=$(echo "$out" | grep -n "low-severity-fixture" | head -1 | cut -d: -f1)
if [[ -n "$high_line" && -n "$med_line" && -n "$low_line" \
      && "$high_line" -lt "$med_line" && "$med_line" -lt "$low_line" ]]; then
  echo "  PASS: T2: severity sort order high > medium > low"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T2: severity sort order wrong (high=$high_line med=$med_line low=$low_line)"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# T7 — malformed-frontmatter sibling does not crash --list
# ---------------------------------------------------------------------------
echo ""
echo "--- T7: malformed frontmatter sibling ---"
set +e
out=$(python3 "$SCRIPT" --list --ledger "$FIXTURE_DIR/with-malformed" 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "T7: --list with malformed sibling exits 0 (no crash)"
assert_contains "$out" "good-entry" "T7: still lists the good entry"
assert_contains "$out" "malformed-frontmatter" "T7: stderr warning names the malformed file"

# ---------------------------------------------------------------------------
# T4 — interactive happy path with --no-verify (no gh stub needed)
# ---------------------------------------------------------------------------
echo ""
echo "--- T4: interactive happy path (resolved + linked_issue) ---"
WORK_DIR="$TMP_ROOT/t4"
cp -r "$FIXTURE_DIR/typical" "$WORK_DIR"
# Pick the legacy-schema entry (idx 1 after severity sort: high first)
out=$(printf "1\nresolved\n2723\n" | python3 "$SCRIPT" --no-verify --ledger "$WORK_DIR" 2>&1)
rc=$?
assert_eq "0" "$rc" "T4: interactive happy path exits 0"
# Verify the file was mutated
mutated_file="$WORK_DIR/2026-02-12-legacy-schema-fixture.md"
if grep -q "^status: resolved$" "$mutated_file"; then
  echo "  PASS: T4: status: resolved written"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T4: status: resolved not written"
  FAIL=$((FAIL + 1))
fi
if grep -q "^linked_issue: 2723$" "$mutated_file"; then
  echo "  PASS: T4: linked_issue: 2723 written (integer, no quotes)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T4: linked_issue: 2723 not written"
  FAIL=$((FAIL + 1))
fi
# Other keys preserved (legacy schema)
if grep -q "^module: plugins/soleur$" "$mutated_file" \
   && grep -q "^problem_type: best_practice$" "$mutated_file" \
   && grep -q "^component: skills$" "$mutated_file"; then
  echo "  PASS: T4: legacy-schema keys preserved"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T4: legacy-schema keys lost"
  FAIL=$((FAIL + 1))
fi
# Body unchanged
orig_body_hash=$(awk '/^---$/{c++; next} c==2' "$FIXTURE_DIR/typical/2026-02-12-legacy-schema-fixture.md" | md5sum | cut -d' ' -f1)
new_body_hash=$(awk '/^---$/{c++; next} c==2' "$mutated_file" | md5sum | cut -d' ' -f1)
assert_eq "$orig_body_hash" "$new_body_hash" "T4: body MD5 unchanged after mutation"
# Stderr undo hint
assert_contains "$out" "git checkout -- " "T4: stderr undo hint present"
assert_contains "$out" "No auto-commit by design" "T4: stderr no-auto-commit message"

# ---------------------------------------------------------------------------
# T5 — interactive rejects non-integer linked_issue
# ---------------------------------------------------------------------------
echo ""
echo "--- T5: interactive rejects bad linked_issue ---"
WORK_DIR="$TMP_ROOT/t5"
cp -r "$FIXTURE_DIR/typical" "$WORK_DIR"
# 3 bad attempts → exit 2; no file mutation
set +e
out=$(printf "1\nresolved\nnot-a-number\n12.5\n\$(rm -rf /)\n" | python3 "$SCRIPT" --no-verify --ledger "$WORK_DIR" 2>&1)
rc=$?
set -e
assert_eq "2" "$rc" "T5: 3 bad linked_issue attempts → exit 2"
# File must NOT have been mutated
unmutated_file="$WORK_DIR/2026-02-12-legacy-schema-fixture.md"
if grep -q "^status: resolved$" "$unmutated_file"; then
  echo "  FAIL: T5: file mutated despite all attempts rejected"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: T5: file unchanged after all attempts rejected"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# T6 — gh issue view failure → stderr names failure + --no-verify hint + exit 1
# ---------------------------------------------------------------------------
echo ""
echo "--- T6: gh issue view failure ---"
WORK_DIR="$TMP_ROOT/t6"
cp -r "$FIXTURE_DIR/typical" "$WORK_DIR"
STUB_DIR="$TMP_ROOT/t6-bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Simulate `gh issue view <N>` failure (404 / network / etc.).
echo "gh: issue not found" >&2
exit 1
STUB
chmod +x "$STUB_DIR/gh"
set +e
out=$(PATH="$STUB_DIR:$PATH" printf "1\nresolved\n9999999\n" | PATH="$STUB_DIR:$PATH" python3 "$SCRIPT" --ledger "$WORK_DIR" 2>&1)
rc=$?
set -e
assert_eq "1" "$rc" "T6: gh failure → exit 1"
assert_contains "$out" "gh issue view failed" "T6: stderr names the failure"
assert_contains "$out" "--no-verify" "T6: stderr suggests --no-verify"
# File must NOT have been mutated
if grep -q "^status: resolved$" "$WORK_DIR/2026-02-12-legacy-schema-fixture.md"; then
  echo "  FAIL: T6: file mutated despite gh failure"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: T6: file unchanged when gh fails"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# T8 — dual-schema round-trip: current schema closes correctly
# ---------------------------------------------------------------------------
echo ""
echo "--- T8: current-schema close round-trip ---"
WORK_DIR="$TMP_ROOT/t8"
cp -r "$FIXTURE_DIR/typical" "$WORK_DIR"
# After severity sort: high=legacy(1), medium=current(2), low=low(3). Pick idx 2.
out=$(printf "2\nwont-fix\n\n" | python3 "$SCRIPT" --no-verify --ledger "$WORK_DIR" 2>&1)
rc=$?
assert_eq "0" "$rc" "T8: wont-fix close exits 0"
mutated_file="$WORK_DIR/2026-03-03-current-schema-fixture.md"
if grep -q "^status: wont-fix$" "$mutated_file"; then
  echo "  PASS: T8: status: wont-fix written"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T8: status: wont-fix not written"
  FAIL=$((FAIL + 1))
fi
# wont-fix → linked_issue is optional (we sent empty input). Must NOT add an empty linked_issue line.
if grep -q "^linked_issue:" "$mutated_file"; then
  echo "  FAIL: T8: linked_issue line added despite empty input for wont-fix"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: T8: no linked_issue line for wont-fix with empty input"
  PASS=$((PASS + 1))
fi
# Current-schema keys preserved
if grep -q "^title: Current schema fixture$" "$mutated_file" \
   && grep -q "^category: technical-debt$" "$mutated_file"; then
  echo "  PASS: T8: current-schema keys preserved"
  PASS=$((PASS + 1))
else
  echo "  FAIL: T8: current-schema keys lost"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# T-quit — operator types 'q' → exit 0, no mutation
# ---------------------------------------------------------------------------
echo ""
echo "--- T-quit: q quits cleanly ---"
WORK_DIR="$TMP_ROOT/tq"
cp -r "$FIXTURE_DIR/typical" "$WORK_DIR"
set +e
out=$(printf "q\n" | python3 "$SCRIPT" --no-verify --ledger "$WORK_DIR" 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "T-quit: q exits 0"
if grep -q "^status: resolved$" "$WORK_DIR/2026-02-12-legacy-schema-fixture.md"; then
  echo "  FAIL: T-quit: file mutated despite quit"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: T-quit: no mutation on quit"
  PASS=$((PASS + 1))
fi

print_results
