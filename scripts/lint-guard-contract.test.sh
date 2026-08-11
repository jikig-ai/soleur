#!/usr/bin/env bash
# Tests for scripts/lint-guard-contract.py — the mechanical gate behind the
# plan-time Guard Contract (plan/SKILL.md §2.12, deepen-plan §4.11).
#
# The class this exists to catch: a guard whose WINDOW, CHOKEPOINT or IDENTIFIER
# SET is narrower than the property it names. The plan-time countermeasure is to
# force the author to enumerate the ASSEMBLY (structural) rather than the current
# members (which drift), plus a mutation matrix derived from the design.
#
# Two kinds of proof:
#   1. TS-N fixture cases: exit code AND the exact FAIL-message needle.
#   2. MB-N mutation battery: copy the SUT, delete the marked branch, assert the
#      SAME fixture that FAILed at baseline now PASSes — proving the branch is
#      load-bearing rather than decorative. Diffed PER-CASE against a pristine
#      backup with `diff -q`, never against HEAD.
#
# Every fixture is SYNTHESIZED under mktemp (cq-test-fixtures-synthesized-only).
#
# Exit contract of the SUT: 0 PASS/skip, 1 FAIL, 2 argument/IO error.

set -euo pipefail

# A DIRECT invocation of this suite (the inner loop while editing the SUT)
# inherits a bare /tmp — a machine-global 4 GiB tmpfs shared with sibling
# worktrees. test-all.sh already defaults this; do it here too so the verdicts
# are not a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-guard-contract.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

WORK="$(mktemp -d)" || { echo "harness: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# mk_plan_dir <dir> — an empty plans/ tree.
mk_plan_dir() {
  mkdir -p "$1/knowledge-base/project/plans" || return 1
}

# A fully-compliant guard entry. $1 = guard ordinal, $2 = name.
compliant_guard() {
  cat <<EOF

### Guard $1 — $2

**Property.** Every rename that reaches the sink is checked against the allowlist.

**Assembly.** The property quantifies over:

- Every pair emitted by the scan at \`thing.sh:70-71\` — the sole chokepoint.
- The \`ALLOW_RES\` array produced by the parser — the sole allowlist source.
- The guard's own dispatch and its wiring in \`scripts/test-all.sh\`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the source check | RED |
| 2 | Point source and target at different sets | RED |
| 3 | Neuter the dispatch to always exit 0 | RED |
EOF
}

# write_plan <path> <body-producer...> — frontmatter + Overview + body.
write_plan() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")" || return 1
  {
    echo "---"
    echo "title: \"fixture plan\""
    echo "branch: feat-fixture"
    echo "---"
    echo
    echo "## Overview"
    echo
    echo "Synthesized fixture."
    echo
    echo "## Guard Contract"
    "$@"
  } > "$path"
}

# run_sut <dir> [args...] — echoes "rc=<n>" then combined output.
run_sut() {
  local dir="$1"; shift
  local out rc
  set +e
  out="$(cd "$dir" && python3 "$SUT" --repo-root "$dir" "$@" 2>&1)"
  rc=$?
  set -e
  printf 'rc=%s\n%s\n' "$rc" "$out"
}

# assert_case <label> <expected-rc> <needle> <dir> [args...]
assert_case() {
  local label="$1" want_rc="$2" needle="$3" dir="$4"; shift 4
  local combined rc body
  combined="$(run_sut "$dir" "$@")"
  rc="${combined%%$'\n'*}"; rc="${rc#rc=}"
  body="${combined#*$'\n'}"
  if [[ "$rc" != "$want_rc" ]]; then
    fail "$label" "expected rc=$want_rc got rc=$rc; output: $(printf '%s' "$body" | head -5 | tr '\n' ' ')"
    return
  fi
  if [[ -n "$needle" ]] && ! grep -qF -- "$needle" <<<"$body"; then
    fail "$label" "rc ok but needle '$needle' absent; output: $(printf '%s' "$body" | head -5 | tr '\n' ' ')"
    return
  fi
  pass "$label"
}

# ---------------------------------------------------------------------------
# TS-0: the SUT exists and is runnable
# ---------------------------------------------------------------------------
if [[ ! -f "$SUT" ]]; then
  echo "FAIL: TS-0 SUT missing at $SUT"
  echo "RED as expected before implementation."
  exit 1
fi

# ---------------------------------------------------------------------------
# TS-1: a fully-compliant plan PASSes
# ---------------------------------------------------------------------------
D1="$WORK/ts1"; mk_plan_dir "$D1" || { echo "harness: setup failed" >&2; exit 2; }
write_plan "$D1/knowledge-base/project/plans/2026-08-11-ok-plan.md" compliant_guard 1 "the good one"
assert_case "TS-1 compliant plan passes" 0 "" "$D1"

# ---------------------------------------------------------------------------
# TS-2: a plan with NO Guard Contract section is skipped (not failed)
# ---------------------------------------------------------------------------
D2="$WORK/ts2"; mk_plan_dir "$D2" || exit 2
cat > "$D2/knowledge-base/project/plans/2026-08-11-noguard-plan.md" <<'EOF'
---
title: "no guards here"
branch: feat-fixture
---

## Overview

A plan with no guard-shaped deliverable.
EOF
assert_case "TS-2 plan without Guard Contract is skipped" 0 "" "$D2"

# ---------------------------------------------------------------------------
# TS-3 (mutation row 1): ASSEMBLY missing -> RED
# ---------------------------------------------------------------------------
no_assembly() {
  cat <<'EOF'

### Guard 1 — missing assembly

**Property.** Something holds everywhere.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
| 3 | c | RED |
EOF
}
D3="$WORK/ts3"; mk_plan_dir "$D3" || exit 2
write_plan "$D3/knowledge-base/project/plans/2026-08-11-noasm-plan.md" no_assembly
assert_case "TS-3 missing Assembly fails" 1 "Assembly" "$D3"

# ---------------------------------------------------------------------------
# TS-4 (mutation row 2): mutation matrix with only 2 rows -> RED
# ---------------------------------------------------------------------------
two_rows() {
  cat <<'EOF'

### Guard 1 — too few mutations

**Property.** Something holds everywhere.

**Assembly.** Every call site in `a.sh`, plus the dispatch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
EOF
}
D4="$WORK/ts4"; mk_plan_dir "$D4" || exit 2
write_plan "$D4/knowledge-base/project/plans/2026-08-11-tworow-plan.md" two_rows
assert_case "TS-4 mutation matrix under 3 rows fails" 1 "mutation" "$D4"

# ---------------------------------------------------------------------------
# TS-5 (mutation row 3): ASSEMBLY is a placeholder -> RED
# ---------------------------------------------------------------------------
tbd_assembly() {
  cat <<'EOF'

### Guard 1 — placeholder assembly

**Property.** Something holds everywhere.

**Assembly.** TBD

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
| 3 | c | RED |
EOF
}
D5="$WORK/ts5"; mk_plan_dir "$D5" || exit 2
write_plan "$D5/knowledge-base/project/plans/2026-08-11-tbd-plan.md" tbd_assembly
assert_case "TS-5 placeholder Assembly fails" 1 "placeholder" "$D5"

# ---------------------------------------------------------------------------
# TS-6 (mutation row 5): SECOND guard non-compliant while FIRST is compliant.
# This is the first-member-degradation class: a guard that quantifies over only
# the first entry passes here while the property is violated.
# ---------------------------------------------------------------------------
first_ok_second_bad() {
  compliant_guard 1 "the good one"
  cat <<'EOF'

### Guard 2 — the bad one

**Property.** Something else holds.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
| 3 | c | RED |
EOF
}
D6="$WORK/ts6"; mk_plan_dir "$D6" || exit 2
write_plan "$D6/knowledge-base/project/plans/2026-08-11-second-plan.md" first_ok_second_bad
assert_case "TS-6 non-compliant SECOND guard fails (all-members, not first-member)" 1 "Guard 2" "$D6"

# ---------------------------------------------------------------------------
# TS-7: `## Guard Contract` present but ZERO guard entries -> RED.
# A section heading with no entries must not read as compliance.
# ---------------------------------------------------------------------------
empty_section() { printf '\nNo guards enumerated here.\n'; }
D7="$WORK/ts7"; mk_plan_dir "$D7" || exit 2
write_plan "$D7/knowledge-base/project/plans/2026-08-11-empty-plan.md" empty_section
assert_case "TS-7 Guard Contract with zero entries fails" 1 "no guard entries" "$D7"

# ---------------------------------------------------------------------------
# TS-8 (mutation row 4 precursor): the SUT reports its own dispatch count, and
# a sweep that checked ZERO guard entries across a tree that HAS a Guard
# Contract must not exit 0 silently. Covered by TS-7; here we assert the
# positive dispatch line exists so MB-4 has something to neuter.
# ---------------------------------------------------------------------------
combined="$(run_sut "$D1")"
if grep -qE 'checked [0-9]+ plan|guard entr' <<<"$combined"; then
  pass "TS-8 SUT reports a dispatch count"
else
  fail "TS-8 SUT reports a dispatch count" "no count line in: $(printf '%s' "$combined" | head -3 | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# TS-9: archive/ is excluded by construction (non-recursive sweep).
# A non-compliant plan under plans/archive/ must NOT fail the sweep.
# ---------------------------------------------------------------------------
D9="$WORK/ts9"; mk_plan_dir "$D9" || exit 2
write_plan "$D9/knowledge-base/project/plans/2026-08-11-ok-plan.md" compliant_guard 1 "good"
write_plan "$D9/knowledge-base/project/plans/archive/20260101-old-plan.md" no_assembly
assert_case "TS-9 plans/archive is excluded from the sweep" 0 "" "$D9"

# ---------------------------------------------------------------------------
# TS-10: explicit path argument checks that file even outside plans/.
# ---------------------------------------------------------------------------
D10="$WORK/ts10"; mkdir -p "$D10/elsewhere" || exit 2
write_plan "$D10/elsewhere/thing.md" no_assembly
assert_case "TS-10 explicit path argument is honored" 1 "Assembly" "$D10" "elsewhere/thing.md"

# ---------------------------------------------------------------------------
# MB — mutation battery. Copy the SUT, delete a marked branch, assert the
# fixture that FAILed at baseline now PASSes. Each mutation is proven landed
# with `diff -q` against a PRISTINE BACKUP (never against HEAD).
# ---------------------------------------------------------------------------
PRISTINE="$WORK/pristine-lint.py"
cp "$SUT" "$PRISTINE" || { echo "harness: cp failed" >&2; exit 2; }

# mb_case <label> <marker> <fixture-dir> [args...]
# Deletes every line carrying `# MUT:<marker>` from a copy of the SUT and
# asserts the previously-FAILing fixture now exits 0.
mb_case() {
  local label="$1" marker="$2" dir="$3"; shift 3
  local mutant="$WORK/mutant-$marker.py"
  cp "$PRISTINE" "$mutant" || { fail "$label" "cp failed"; return; }
  grep -v "# MUT:${marker}\b" "$mutant" > "$mutant.new" 2>/dev/null || true
  mv "$mutant.new" "$mutant"

  # Prove the mutation actually landed, against the pristine backup.
  if diff -q "$PRISTINE" "$mutant" >/dev/null 2>&1; then
    fail "$label" "mutation marker '$marker' matched nothing — the branch is unmarked or the marker drifted"
    return
  fi

  local out rc
  set +e
  out="$(cd "$dir" && python3 "$mutant" --repo-root "$dir" "$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "mutant still failed (rc=$rc) — the fixture may not isolate this branch: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  fi
}

mb_case "MB-1 deleting the Assembly check makes TS-3 pass"        assembly "$D3"
mb_case "MB-2 deleting the matrix-floor check makes TS-4 pass"    matrix   "$D4"
mb_case "MB-3 deleting the placeholder check makes TS-5 pass"     placeholder "$D5"
mb_case "MB-4 deleting the zero-entry floor makes TS-7 pass"      floor    "$D7"

# Matrix row 5 (all-members, not first-member) is a FIXTURE-space proof, not a
# code-deletion one: TS-6 fails iff the checker quantifies over every entry. A
# code mutation for it would require an artificial `check_all` seam — dead
# production code existing only to be deleted — so the fixture carries it.

# ---------------------------------------------------------------------------
# Anti-vacuity floor on THIS harness's own dispatch. A neutered pass()/fail()
# printing "0 passed, 0 failed" and exiting 0 is the exact defect this whole PR
# exists to prevent — so the suite refuses to report success on an empty run.
# ---------------------------------------------------------------------------
EXPECTED_MIN=14
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "lint-guard-contract: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
