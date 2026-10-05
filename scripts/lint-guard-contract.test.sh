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
if grep -qF 'scanned 1 plan file(s), 1 with a Guard Contract, 1 guard entry' <<<"$combined"; then
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
# TS-11 (S-4/g7): the sweep must FAIL when it dispatched over nothing. A gate
# that examined zero inputs must never report success — the fourth instance from
# the originating evidence, which this gate reproduced.
# ---------------------------------------------------------------------------
D11="$WORK/ts11"; mkdir -p "$D11/knowledge-base/project/plans" || exit 2
assert_case "TS-11 sweep over zero plan files fails (own-dispatch floor)" 1 "scanned 0" "$D11"

# ---------------------------------------------------------------------------
# TS-12 (S-5): a plan in a SUBDIRECTORY of plans/ must be swept. One such plan
# exists in the repo today and was never checked. archive/ stays excluded.
# ---------------------------------------------------------------------------
D12="$WORK/ts12"; mk_plan_dir "$D12" || exit 2
write_plan "$D12/knowledge-base/project/plans/ok-plan.md" compliant_guard 1 "good"
write_plan "$D12/knowledge-base/project/plans/feat-x/plan.md" no_assembly
assert_case "TS-12 plan in a subdirectory is swept" 1 "Assembly" "$D12"

# ---------------------------------------------------------------------------
# TS-13 (S-1/A5): heading variants must not silently exempt a whole file.
# ---------------------------------------------------------------------------
D13="$WORK/ts13"; mk_plan_dir "$D13" || exit 2
{
  printf -- '---\ntitle: "x"\nbranch: b\n---\n\n## Overview\n\nx\n\n## Guard Contract (3 guards)\n'
  no_assembly
} > "$D13/knowledge-base/project/plans/head-plan.md"
assert_case "TS-13 heading with trailing text is still a Guard Contract" 1 "Assembly" "$D13"

# ---------------------------------------------------------------------------
# TS-14 (S-3/A6): a SECOND Guard Contract section must also be checked.
# ---------------------------------------------------------------------------
second_section() {
  compliant_guard 1 "good"
  printf '\n## Something Else\n\nprose\n\n## Guard Contract\n'
  no_assembly
}
D14="$WORK/ts14"; mk_plan_dir "$D14" || exit 2
write_plan "$D14/knowledge-base/project/plans/two-plan.md" second_section
assert_case "TS-14 a second Guard Contract section is checked too" 1 "Assembly" "$D14"

# ---------------------------------------------------------------------------
# TS-15 (S-2/D1): the matrix floor must be satisfied by the MUTATION MATRIX, not
# by any table in the entry. An Assembly-as-table with NO matrix passed before.
# ---------------------------------------------------------------------------
table_assembly_no_matrix() {
  cat <<'EOF'

### Guard 1 — table assembly, no matrix

**Property.** Something holds everywhere.

**Assembly.** The property quantifies over:

| file | why |
|---|---|
| a.sh | one |
| b.sh | two |
| c.sh | three |
EOF
}
D15="$WORK/ts15"; mk_plan_dir "$D15" || exit 2
write_plan "$D15/knowledge-base/project/plans/tbl-plan.md" table_assembly_no_matrix
assert_case "TS-15 an unrelated table does not satisfy the matrix floor" 1 "mutation" "$D15"

# ---------------------------------------------------------------------------
# TS-16 (C1): a placeholder plus any trailing prose must still be a placeholder.
# ---------------------------------------------------------------------------
tbd_with_prose() {
  cat <<'EOF'

### Guard 1 — placeholder plus prose

**Property.** Something holds everywhere.

**Assembly.** TBD

See the design doc for the real enumeration.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
| 3 | c | RED |
EOF
}
D16="$WORK/ts16"; mk_plan_dir "$D16" || exit 2
write_plan "$D16/knowledge-base/project/plans/prose-plan.md" tbd_with_prose
assert_case "TS-16 placeholder followed by prose is still a placeholder" 1 "placeholder" "$D16"

# ---------------------------------------------------------------------------
# TS-17 (H-1/C2): a field name outside [A-Za-z ] must still terminate the
# preceding field, or the Assembly swallows it and TBD goes undetected.
# ---------------------------------------------------------------------------
paren_field() {
  cat <<'EOF'

### Guard 1 — paren field name

**Property.** Something holds everywhere.

**Assembly.** TBD

**Mutation matrix (3 rows):**

| # | Mutation | Expected |
|---|---|---|
| 1 | a | RED |
| 2 | b | RED |
| 3 | c | RED |
EOF
}
D17="$WORK/ts17"; mk_plan_dir "$D17" || exit 2
write_plan "$D17/knowledge-base/project/plans/paren-plan.md" paren_field
assert_case "TS-17 a parenthesised next-field still terminates the Assembly" 1 "placeholder" "$D17"

# ---------------------------------------------------------------------------
# TS-18 (H-4/B1): a mis-levelled `#### Guard` must FAIL loudly, not fold into
# its predecessor (where its rows also inflated the predecessor's matrix count).
# ---------------------------------------------------------------------------
mislevelled() {
  compliant_guard 1 "good"
  cat <<'EOF'

#### Guard 2 — wrong level

**Property.** Something else.
EOF
}
D18="$WORK/ts18"; mk_plan_dir "$D18" || exit 2
write_plan "$D18/knowledge-base/project/plans/lvl-plan.md" mislevelled
assert_case "TS-18 a mis-levelled Guard heading fails loudly" 1 "heading level" "$D18"

# ---------------------------------------------------------------------------
# TS-19 (M-1/D3): a template pasted into a fenced block must not parse as a
# real, passing entry.
# ---------------------------------------------------------------------------
fenced_template() {
  printf '\nSee the template:\n\n```markdown\n'
  compliant_guard 1 "template example"
  printf '```\n'
}
D19="$WORK/ts19"; mk_plan_dir "$D19" || exit 2
write_plan "$D19/knowledge-base/project/plans/fence-plan.md" fenced_template
assert_case "TS-19 a fenced template block is not a real guard entry" 1 "no guard entries" "$D19"

# ---------------------------------------------------------------------------
# TS-20 (M-7): an unreadable target is an INFRA fault (exit 2), never a finding.
# ---------------------------------------------------------------------------
D20="$WORK/ts20"; mkdir -p "$D20" || exit 2
assert_case "TS-20 a missing explicit path exits 2, not 1" 2 "" "$D20" "nope.md"

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

  # POSITIVE CONTROL: the mutant must still BE the linter — it must run and
  # still emit its own summary line on a compliant fixture. Without this a
  # mutant destroyed by the deletion reports PASS (python3 on an empty file
  # exits 0).
  local ctl
  ctl="$(cd "$D1" && python3 "$mutant" --repo-root "$D1" 2>&1)"
  if ! grep -qF 'lint-guard-contract: scanned' <<<"$ctl"; then
    fail "$label" "mutant is not a working program (no summary on the compliant control): $(printf '%s' "$ctl" | head -2 | tr '\n' ' ')"
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

mb_case "MB-5 deleting the own-dispatch floor makes TS-11 pass"      dispatchfloor "$D11"
mb_case "MB-6 deleting the heading-level check makes TS-18 pass"     level      "$D18"
# MB-7 is SEMANTIC, not a deletion: removing the scope check leaves `span` None
# and crashes, which is a broken mutant rather than a weaker one. Reverting to
# the ORIGINAL entry-wide counting is the mutation that matters — it is the
# defect this fix removed, and it must make TS-15 pass again.
MUT7="$WORK/mutant-entrywide.py"
cp "$PRISTINE" "$MUT7" || { echo "harness: cp failed" >&2; exit 2; }
python3 - "$MUT7" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
needle = '    span = field_span(entry_lines, "Mutation matrix")\n    if span is None:\n        return 0\n'
assert s.count(needle) == 1, "MB-7 anchor drifted"
s = s.replace(needle, '    span = "\\n".join(entry_lines)\n', 1)
p.write_text(s)
PYEOF
if diff -q "$PRISTINE" "$MUT7" >/dev/null 2>&1; then
  fail "MB-7 entry-wide mutation" "mutation did not land"
else
  _c="$(cd "$D1" && python3 "$MUT7" --repo-root "$D1" 2>&1)"
  if ! grep -qF 'lint-guard-contract: scanned' <<<"$_c"; then
    fail "MB-7 reverting to entry-wide counting makes TS-15 pass" "mutant is not a working program"
  else
    _m7out=""; _m7rc=0
    set +e
    _m7out="$(cd "$D15" && python3 "$MUT7" --repo-root "$D15" 2>&1)"; _m7rc=$?
    set -e
    if [[ "$_m7rc" == "0" ]]; then
      pass "MB-7 reverting to entry-wide counting re-opens TS-15"
    else
      fail "MB-7 reverting to entry-wide counting re-opens TS-15" "mutant still failed (rc=$_m7rc): $(printf '%s' "$_m7out" | head -2 | tr '\n' ' ')"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# TS-21: positive control on THIS harness's own accounting. A `fail()` rewritten
# to increment PASS keeps the count floor satisfied and reports a clean run —
# the exact "0 passed, 0 failed, exit 0" defect the SUT's docstring cites as
# originating evidence. The floor counts DISPATCH; this checks DISCRIMINATION.
# ---------------------------------------------------------------------------
_accounting_live() {
  local p0=$PASS f0=$FAIL t0=$TOTAL ok=1
  pass "__control__" >/dev/null
  fail "__control__" "control" >/dev/null
  [[ "$PASS"  -eq $((p0 + 1)) ]] || ok=0
  [[ "$FAIL"  -eq $((f0 + 1)) ]] || ok=0
  [[ "$TOTAL" -eq $((t0 + 2)) ]] || ok=0
  PASS=$p0; FAIL=$f0; TOTAL=$t0
  [[ "$ok" -eq 1 ]]
}
if _accounting_live; then
  pass "TS-21 harness accounting is live (pass/fail move their own counters)"
else
  echo "FAIL: TS-21 harness accounting is broken — pass()/fail() do not move their counters" >&2
  exit 1
fi

# Matrix row 5 (all-members, not first-member) is a FIXTURE-space proof, not a
# code-deletion one: TS-6 fails iff the checker quantifies over every entry. A
# code mutation for it would require an artificial `check_all` seam — dead
# production code existing only to be deleted — so the fixture carries it.

# ---------------------------------------------------------------------------
# Anti-vacuity floor on THIS harness's own dispatch. A neutered pass()/fail()
# printing "0 passed, 0 failed" and exiting 0 is the exact defect this whole PR
# exists to prevent — so the suite refuses to report success on an empty run.
# ---------------------------------------------------------------------------
EXPECTED_MIN=28
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "lint-guard-contract: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
