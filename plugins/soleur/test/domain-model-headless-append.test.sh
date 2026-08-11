#!/usr/bin/env bash
# domain-model-headless-append.test.sh — the safety properties that make
# auto-appending safe without an operator (#7332, plan Phase 2.2).
#
# WHY AUTO-APPEND IS SAFE HERE, AND ONLY HERE. The interactivity was never in this
# script — `write-row` is already a non-interactive primitive. It lived in sync.md's
# per-row AskUserQuestion gate, which headless mode auto-skips, so run 1 wrote zero
# rows. The headless branch appends candidates directly, and that is defensible for
# exactly one reason: `## Auto-inferred (unreviewed)` IS the staging area for
# unreviewed content. Appending there is not auto-approving a business rule —
# promotion to a curated `BR-*` id remains a deliberate human edit. That distinction
# is the whole reason the section exists, and it is why this can be automated when a
# per-row approval gate cannot.
#
# Because no human now reads each row before it lands, every safety property
# write_row already had becomes load-bearing rather than advisory. Each one gets a
# red-when-broken test here (plan AC9). All fixtures synthesized
# (cq-test-fixtures-synthesized-only) — the "secret" below is a shape, not a value.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DRIFT="$REPO_ROOT/plugins/soleur/scripts/domain-model-drift.sh"
SYNC_MD="$REPO_ROOT/plugins/soleur/commands/sync.md"

echo "=== domain-model headless append — preserved safety properties ==="
echo ""

assert_file_exists "$DRIFT" "domain-model-drift.sh exists"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

export TMPDIR="${TMPDIR:-/var/tmp}"
WORK="$(mktemp -d -t dmappend.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
REG="$REPO/knowledge-base/engineering/architecture/domain-model.md"
mkdir -p "$(dirname "$REG")" || { echo "FATAL: mkdir failed"; exit 2; }
bash "$DRIFT" init --repo "$REPO" --register "$REG" >/dev/null 2>&1 \
  || { echo "FATAL: init failed — cannot build the fixture"; exit 2; }

slurp() { [[ -s "$1" ]] && cat "$1" || echo "<file-absent>"; }

# Append a curated row by hand so we can prove the curated table is never touched.
python3 - "$REG" <<'PY' || { echo "FATAL: fixture seed failed"; exit 2; }
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "| ID | Rule | Statement | Source |\n|---|---|---|---|\n"
assert anchor in s, "curated table header not found in seeded register"
row = "| BR-TEST-1 | Curated rule | A hand-curated statement. | synthesized |\n"
open(p, "w").write(s.replace(anchor, anchor + row, 1))
PY

curated_block() { awk '/^## Business Rules/,/^## Auto-inferred/' "$REG"; }
CURATED_BEFORE="$(curated_block)"

wr() { # wr <anchor> <statement> -> exit code
  local rc=0
  bash "$DRIFT" write-row --repo "$REPO" --register "$REG" \
    --anchor "$1" --statement "$2" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# --- property 1: fail-closed secret-shape refusal ---------------------------
# A synthesized token SHAPE (split across concatenation so no contiguous literal
# exists in source — GitHub push protection scans for the real shape).
SECRET_SHAPE="ghp_""0123456789abcdefghijABCDEFGHIJ0123"
RC="$(wr "secret-anchor" "Statement carrying $SECRET_SHAPE inline.")"
assert_eq "3" "$RC" "secret-shaped content is refused fail-closed (exit 3)"
if grep -qF "$SECRET_SHAPE" "$REG"; then
  echo "  FAIL: the secret-shaped value was written to the register"; FAIL=$((FAIL + 1))
else
  echo "  PASS: nothing was written when the secret scan tripped"; PASS=$((PASS + 1))
fi

# --- property 2: content-anchor dedup is a no-op ----------------------------
RC="$(wr "dedup-anchor" "First statement.")"
assert_eq "0" "$RC" "first write of an anchor succeeds"
COUNT_1="$(grep -cF "dedup-anchor" "$REG" || true)"
RC="$(wr "dedup-anchor" "Second statement, different text.")"
assert_eq "0" "$RC" "re-proposing a known anchor exits 0 (no-op, not an error)"
COUNT_2="$(grep -cF "dedup-anchor" "$REG" || true)"
assert_eq "$COUNT_1" "$COUNT_2" "re-running does not duplicate the row — reruns are idempotent"
if grep -qF "Second statement, different text." "$REG"; then
  echo "  FAIL: dedup let a second statement through for a known anchor"; FAIL=$((FAIL + 1))
else
  echo "  PASS: the duplicate anchor's new statement was NOT appended"; PASS=$((PASS + 1))
fi

# --- property 3: appends land ONLY under Auto-inferred ----------------------
RC="$(wr "placement-anchor" "Placement check statement.")"
assert_eq "0" "$RC" "placement row writes"
CURATED_AFTER="$(curated_block)"
assert_eq "$CURATED_BEFORE" "$CURATED_AFTER" \
  "the curated '## Business Rules' table is byte-identical before and after appends"

# --- property 4: never mints a BR-* id --------------------------------------
# The anchor is column 1, exactly where curated BR-NNN ids live, so a candidate
# whose anchor starts with `BR-` must be neutralized rather than written verbatim.
RC="$(wr "BR-FORGED-9" "Attempts to look like a curated rule.")"
assert_eq "0" "$RC" "a BR--prefixed anchor is accepted but neutralized"
FORGED="$(grep -cE '^\| BR-FORGED-9 ' "$REG" || true)"
assert_eq "0" "$FORGED" "no row is minted with a literal BR-* id in column 1"

# --- property 5: a forged heading cannot break out of the table -------------
RC="$(wr "## Injected Heading" "Attempts to open a new section.")"
INJECTED="$(grep -cE '^## Injected Heading' "$REG" || true)"
assert_eq "0" "$INJECTED" "a '##'-prefixed anchor cannot forge a real heading"

# --- property 6: a newline in a field is rejected outright ------------------
RC="$(wr "multi
line" "Statement.")"
if [[ "$RC" -ne 0 ]]; then
  echo "  PASS: a newline in the anchor is rejected"; PASS=$((PASS + 1))
else
  echo "  FAIL: a newline in the anchor was accepted"; FAIL=$((FAIL + 1))
fi

# --- property 7: the register still has exactly one Auto-inferred heading ---
# write_row's own TOCTOU guard aborts unless this is exactly 1; if any append
# above had corrupted the structure, every later run would hard-fail.
HN="$(grep -cE '^## Auto-inferred \(unreviewed\)' "$REG" || true)"
assert_eq "1" "$HN" "the register still has exactly one Auto-inferred heading after all appends"

# --- prefix-anchor dedup false positive -------------------------------------
# `grep -qF "$ANCHOR"` matched a SUBSTRING anywhere in the file, so an anchor that is
# a PREFIX of an existing one was silently swallowed: with `t.p10` already written, a
# genuinely new `t.p1` deduped to a no-op and exited 0. Under the headless path that
# drops real candidates on every sync with no diagnostic. Reproduced before the fix.
PFX_RC=0
bash "$DRIFT" write-row --repo "$WORK" --register "$REG" \
  --anchor "m.sql > t.p10" --statement "ten" >/dev/null 2>&1 || PFX_RC=$?
assert_eq "0" "$PFX_RC" "prefix dedup: the longer anchor writes"
PFX2_RC=0
bash "$DRIFT" write-row --repo "$WORK" --register "$REG" \
  --anchor "m.sql > t.p1" --statement "one" >/dev/null 2>&1 || PFX2_RC=$?
assert_eq "0" "$PFX2_RC" "prefix dedup: the shorter anchor also writes"
assert_eq "1" "$(grep -c 'm.sql > t.p1 |' "$REG" 2>/dev/null || true)" \
  "prefix dedup: 't.p1' is NOT swallowed by the existing 't.p10'"

# A genuine duplicate must still be a no-op — the fix must not disable dedup.
DUP_BEFORE="$(grep -c 'm.sql > t.p1 |' "$REG" 2>/dev/null || true)"
bash "$DRIFT" write-row --repo "$WORK" --register "$REG" \
  --anchor "m.sql > t.p1" --statement "one" >/dev/null 2>&1 || true
assert_eq "$DUP_BEFORE" "$(grep -c 'm.sql > t.p1 |' "$REG" 2>/dev/null || true)" \
  "prefix dedup: a TRUE duplicate is still a no-op"

# --- CR is a control char the comment claimed was stripped and was not --------
# The escaper's comment said "ALL C0 control chars (except tab, newline)", but the
# range `\000-\010\013\014\016-\037` omitted \015 (CR). A bare CR is a line
# terminator in CRLF-normalising viewers and in JSON log surfaces, so it could break
# a markdown table cell out of its row.
bash "$DRIFT" write-row --repo "$WORK" --register "$REG" \
  --anchor "cr-anchor" --statement "$(printf 'a\rBR-999 forged')" >/dev/null 2>&1 || true
assert_eq "0" "$(grep -c $'\r' "$REG" 2>/dev/null || true)" \
  "CR is stripped from the written row (the comment's claim is now true)"
# Tab must SURVIVE — it is deliberately excluded from the strip set.
bash "$DRIFT" write-row --repo "$WORK" --register "$REG" \
  --anchor "tab-anchor" --statement "$(printf 'a\tb')" >/dev/null 2>&1 || true
if grep -qF "tab-anchor" "$REG"; then
  echo "  PASS: a tab in the statement does not prevent the row landing"
  PASS=$((PASS + 1))
else
  echo "  FAIL: the tab-bearing row did not land"
  FAIL=$((FAIL + 1))
fi

# --- section placement on a register `init` did NOT create ------------------
# Every fixture above is built by `init`, which always emits `## Business Rules`
# BEFORE `## Auto-inferred`. That ordering is what makes the naive insert correct,
# so the suite was structurally incapable of seeing the defect below — the fixture
# set had a direction, and only one.
#
# A customer's hand-authored register may order the sections either way. With
# Auto-inferred FIRST, the original awk inserted at the first `^|---` at-or-after
# the heading with no check that the separator belonged to that section, so the
# candidate row landed in the CURATED table and write-row exited 0. Unattended,
# on every headless sync.
# THE DISCRIMINATING SHAPE. Auto-inferred must carry NO table separator of its own,
# so that the first `^|---` at-or-after its heading belongs to the CURATED table.
# A fixture where both sections have tables is handled identically by the broken and
# the fixed implementation — my first attempt used that shape and the mutation
# survived, which is the fixture-direction trap this very suite exists to document.
ORDER_REG="$WORK/reversed-order.md"
cat > "$ORDER_REG" <<'REVERSED'
# Register

## Auto-inferred (unreviewed)

_No candidates yet._

## Business Rules

| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-001 | tenancy | Users only read their own rows | mig 001 |
REVERSED

ORDER_RC=0
bash "$DRIFT" write-row --repo "$WORK" --register "$ORDER_REG" \
  --anchor "037_worm.sql > audit.founder_id" \
  --statement "founder_id is anonymised on erasure." >/dev/null 2>&1 || ORDER_RC=$?
# Refusing is the correct outcome: there is no Auto-inferred table to append to, and
# the only other `^|---` belongs to the operator's curated rules.
assert_eq "2" "$ORDER_RC" "curated-table trap: write-row REFUSES rather than appending"

if grep -qE '^\| 037_worm' "$ORDER_REG"; then
  echo "  FAIL: curated-table trap: the candidate row was written into the register"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: curated-table trap: no candidate row reached the file"
  PASS=$((PASS + 1))
fi
assert_eq "1" "$(grep -c '^| BR-001 ' "$ORDER_REG" 2>/dev/null || true)" \
  "curated-table trap: the curated BR-001 row is untouched"

# The positive counterpart — same reversed ordering, but Auto-inferred DOES have its
# own table. The row must land there, above the curated section.
ORDER2_REG="$WORK/reversed-order-with-table.md"
cat > "$ORDER2_REG" <<'REVERSED2'
# Register

## Auto-inferred (unreviewed)

| Anchor | Candidate statement |
|---|---|

## Business Rules

| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-001 | tenancy | Users only read their own rows | mig 001 |
REVERSED2

ORDER2_RC=0
bash "$DRIFT" write-row --repo "$WORK" --register "$ORDER2_REG" \
  --anchor "038_x.sql > audit.other" --statement "Other statement." >/dev/null 2>&1 || ORDER2_RC=$?
assert_eq "0" "$ORDER2_RC" "reversed order WITH a table: write-row succeeds"
O_AI="$(grep -n '^## Auto-inferred' "$ORDER2_REG" 2>/dev/null | head -1 | cut -d: -f1 || true)"
O_BR="$(grep -n '^## Business Rules' "$ORDER2_REG" 2>/dev/null | head -1 | cut -d: -f1 || true)"
O_ROW="$(grep -nF '038_x.sql' "$ORDER2_REG" 2>/dev/null | head -1 | cut -d: -f1 || true)"
if [[ -n "$O_ROW" && -n "$O_AI" && -n "$O_BR" && "$O_ROW" -gt "$O_AI" && "$O_ROW" -lt "$O_BR" ]]; then
  echo "  PASS: reversed order WITH a table: row lands inside Auto-inferred, above the curated table"
  PASS=$((PASS + 1))
else
  echo "  FAIL: reversed order WITH a table: row at ${O_ROW:-none} outside Auto-inferred (${O_AI:-?}..${O_BR:-?})"
  FAIL=$((FAIL + 1))
fi

# --- a register with NO Auto-inferred heading must abort LOUDLY -------------
# `hn="$(grep -c …)"` is an assignment whose status is the substitution's, and
# `grep -c` exits 1 on zero matches — so under `set -e` this died BEFORE its own
# `die` could print: exit 1, empty stderr, and 1 is not in write-row's documented
# 0/2/3 contract. Every pre-existing register lacking the heading appended nothing,
# silently, on every sync.
NOHEAD_REG="$WORK/no-heading.md"
printf '# Register\n\n## Business Rules\n\n| ID | Rule |\n|---|---|\n' > "$NOHEAD_REG"
NOHEAD_ERR="$WORK/no-heading.err"
NOHEAD_RC=0
bash "$DRIFT" write-row --repo "$WORK" --register "$NOHEAD_REG" \
  --anchor a --statement b >/dev/null 2>"$NOHEAD_ERR" || NOHEAD_RC=$?
assert_eq "2" "$NOHEAD_RC" "missing Auto-inferred heading: aborts with the documented rc=2, not a bare 1"
if [[ -s "$NOHEAD_ERR" ]] && grep -q 'Auto-inferred' "$NOHEAD_ERR"; then
  echo "  PASS: missing Auto-inferred heading: the abort MESSAGE names the cause"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing Auto-inferred heading: stderr was empty or did not name the cause"
  FAIL=$((FAIL + 1))
fi

# --- 2.3: the terminal-area contract is reconciled, not contradicted --------
# grep, not assert_contains on the whole body — a failed substring assertion over
# a 600-line file dumps the entire file into the log and buries every other result.
if grep -qE '^##### `all`-dispatch path' "$SYNC_MD"; then
  echo "  PASS: sync.md documents a distinct all-dispatch path for domain-model"; PASS=$((PASS + 1))
else
  echo "  FAIL: sync.md has no distinct all-dispatch path section for domain-model"; FAIL=$((FAIL + 1))
fi
if grep -qE '^##### Standalone contract' "$SYNC_MD"; then
  echo "  PASS: the standalone terminal contract is still stated explicitly"; PASS=$((PASS + 1))
else
  echo "  FAIL: the standalone terminal contract was dropped, not reconciled"; FAIL=$((FAIL + 1))
fi
if grep -qE 'domain-model-drift\.sh init' "$SYNC_MD"; then
  echo "  PASS: the all-dispatch path bootstraps the register via init"; PASS=$((PASS + 1))
else
  echo "  FAIL: the all-dispatch path does not call init — it dies on a fresh repo"; FAIL=$((FAIL + 1))
fi
if grep -qE '^If `<sync_area>` is empty or `all`.*EXCEPT `rule-prune` AND `domain-model`' "$SYNC_MD"; then
  echo "  FAIL: domain-model is still in the all-dispatch exclusion list (plan AC6)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: domain-model no longer appears in the all-dispatch exclusion list (AC6)"; PASS=$((PASS + 1))
fi

print_results
