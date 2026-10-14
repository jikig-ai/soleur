#!/usr/bin/env bash
# domain-model-init.test.sh — RED-first gate for `domain-model-drift.sh init`.
#
# WHY THIS SUBCOMMAND EXISTS. Folding `domain-model` into `all` dispatch is a
# one-line edit that cannot work: drift and write-row both `realpath -e` the
# register (:161, :240) and die when it does not resolve, and a new customer has
# no knowledge-base/engineering/architecture/domain-model.md. Nothing bootstraps
# it. `init` is the ONE command allowed to create that file.
#
# The guards at :161/:240 stay UNCHANGED and this suite asserts it. They are
# correct for drift and write-row, which must never operate on a path they cannot
# resolve — relaxing them to make `all` work would trade a startup failure for a
# silent write to the wrong place.
#
# The load-bearing case is `init` -> `write-row` end to end: a register that has
# the right headings but no table separator is a file write-row refuses to touch
# ("could not locate the Auto-inferred table separator"), so asserting headings
# alone would pass while the bootstrap remained useless.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DRIFT="$REPO_ROOT/plugins/soleur/scripts/domain-model-drift.sh"

echo "=== domain-model-drift.sh init ==="
echo ""

assert_file_exists "$DRIFT" "domain-model-drift.sh exists"
if [[ "$FAIL" -gt 0 ]]; then print_results; fi

export TMPDIR="${TMPDIR:-/var/tmp}"
WORK="$(mktemp -d -t dminit.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT

REG_REL="knowledge-base/engineering/architecture/domain-model.md"
mkdir -p "$WORK/repo/knowledge-base/engineering/architecture" || { echo "FATAL: mkdir failed"; exit 2; }
REPO="$WORK/repo"
REG="$REPO/$REG_REL"

# Exit codes are captured explicitly: under `set -e` a non-zero command inside a
# command substitution aborts the assignment before any assertion can print.
run_init() { local rc=0; bash "$DRIFT" init --repo "$REPO" --register "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

# Reading a file that the code under test failed to create must not abort the
# suite — `VAR="$(cat missing)"` is non-zero and `set -e` kills the whole run,
# hiding every assertion below it. Guard the read and let the assertions decide.
slurp() { [[ -s "$1" ]] && cat "$1" || echo "<file-absent>"; }
# `grep -c` prints the count AND exits 1 when it is zero, so `|| echo 0` would emit a
# SECOND zero and the capture becomes "0\n0" — an assertion comparing against "0"
# then fails with a malformed "actual". `|| true` keeps grep's own printed zero.
count_re() { [[ -s "$1" ]] && { grep -cE "$2" "$1" || true; } || echo 0; }

# --- 2.1 bootstrap ----------------------------------------------------------
RC="$(run_init "$REG")"
assert_eq "0" "$RC" "init exits 0 on an absent register"
assert_file_exists "$REG" "init creates the register"

HEADINGS_BR="$(count_re "$REG" '^## Business Rules')"
HEADINGS_AI="$(count_re "$REG" '^## Auto-inferred \(unreviewed\)')"
assert_eq "1" "$HEADINGS_BR" "seeds exactly one '## Business Rules' heading"
# write_row hard-fails unless this count is exactly 1 (its TOCTOU re-read).
assert_eq "1" "$HEADINGS_AI" "seeds exactly one '## Auto-inferred (unreviewed)' heading"

# --- idempotence ------------------------------------------------------------
BEFORE="$(slurp "$REG")"
RC2="$(run_init "$REG")"
AFTER="$(slurp "$REG")"
assert_eq "0" "$RC2" "re-running init is a no-op exit 0"
assert_eq "$BEFORE" "$AFTER" "re-running init leaves the register byte-identical"

# --- the real proof: a freshly init'd register ACCEPTS a write-row ----------
# Headings alone are not enough — write_row aborts without the table separator.
WR_RC=0
bash "$DRIFT" write-row --repo "$REPO" --register "$REG" \
  --anchor "test-anchor-7332" --statement "Synthesized candidate statement." >/dev/null 2>&1 || WR_RC=$?
assert_eq "0" "$WR_RC" "write-row succeeds against a freshly init'd register"
assert_contains "$(slurp "$REG")" "test-anchor-7332" "the appended row actually lands in the file"

# The row must land under Auto-inferred, never in the curated table.
AI_LINE="$(grep -n '^## Auto-inferred' "$REG" 2>/dev/null | cut -d: -f1 || true)"; AI_LINE="${AI_LINE:-0}"
ROW_LINE="$(grep -n 'test-anchor-7332' "$REG" 2>/dev/null | head -1 | cut -d: -f1 || true)"; ROW_LINE="${ROW_LINE:-0}"
if [[ "$ROW_LINE" -gt "$AI_LINE" ]]; then
  echo "  PASS: appended row sits BELOW the Auto-inferred heading"; PASS=$((PASS + 1))
else
  echo "  FAIL: appended row landed above the Auto-inferred heading (line $ROW_LINE vs $AI_LINE)"; FAIL=$((FAIL + 1))
fi

# --- idempotence that actually bites ----------------------------------------
# The earlier byte-identical check above CANNOT distinguish "init no-ops" from
# "init rewrites the template with identical bytes" — a freshly-seeded register
# re-seeds to the same content, so a mutation removing the early return survives
# it. The case that matters is DATA LOSS: once a row has been appended, a
# non-idempotent init would clobber it. `all` dispatch calls init on every run,
# so this is the difference between a bootstrap and a silent wipe.
RC3="$(run_init "$REG")"
assert_eq "0" "$RC3" "init over a POPULATED register still exits 0"
assert_contains "$(slurp "$REG")" "test-anchor-7332" \
  "init over a POPULATED register does not clobber the appended row"

# --- the guards at :161 / :240 stay unchanged -------------------------------
MISSING="$REPO/knowledge-base/engineering/architecture/does-not-exist.md"

D_RC=0
bash "$DRIFT" drift --repo "$REPO" --register "$MISSING" >/dev/null 2>&1 || D_RC=$?
if [[ "$D_RC" -ne 0 ]]; then
  echo "  PASS: drift still dies on an unresolvable register (guard :161 unchanged)"; PASS=$((PASS + 1))
else
  echo "  FAIL: drift accepted an unresolvable register — the :161 guard was relaxed"; FAIL=$((FAIL + 1))
fi

W_RC=0
bash "$DRIFT" write-row --repo "$REPO" --register "$MISSING" \
  --anchor a --statement b >/dev/null 2>&1 || W_RC=$?
if [[ "$W_RC" -ne 0 ]]; then
  echo "  PASS: write-row still dies on an unresolvable register (guard :240 unchanged)"; PASS=$((PASS + 1))
else
  echo "  FAIL: write-row accepted an unresolvable register — the :240 guard was relaxed"; FAIL=$((FAIL + 1))
fi

# Source-level assertion so a future refactor cannot quietly drop them.
GUARDS="$(grep -c 'realpath -e -- "\$reg"' "$DRIFT" || true)"
assert_eq "2" "$GUARDS" "both register realpath -e guards are still present in source"

# --- path confinement parity ------------------------------------------------
# init creates files, so it needs at LEAST the confinement drift/write-row have.
OUT_RC=0
bash "$DRIFT" init --repo "$REPO" --register "$WORK/outside-the-repo.md" >/dev/null 2>&1 || OUT_RC=$?
if [[ "$OUT_RC" -ne 0 ]]; then
  echo "  PASS: init refuses a register outside --repo"; PASS=$((PASS + 1))
else
  echo "  FAIL: init created a register outside --repo (confinement gap)"; FAIL=$((FAIL + 1))
fi
assert_file_not_exists "$WORK/outside-the-repo.md" "no file was created outside the repo"

print_results
