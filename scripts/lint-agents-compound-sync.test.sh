#!/usr/bin/env bash
# Tests for scripts/lint-agents-compound-sync.sh.
#
# Issue: #6461. The guard asserts that every restatement of the AGENTS
# always-loaded byte budget agrees with the authority
# (scripts/lint-agents-rule-budget.py). Cases:
#   T1: fixture tree fully in sync                        -> exit 0   [pin]
#   T2: B_ALWAYS_REJECT bumped in the linter only         -> exit 1, names EVERY
#                                                            out-of-sync site in
#                                                            one run (accumulate)
#   T3: cron TS constant changed alone                    -> exit 1, names the
#                                                            file, expected/found,
#                                                            AND the unit
#   T4: threshold removed from AGENTS.docs.md (empty)     -> exit 1, fail-closed
#   T5: a target file renamed/absent                      -> exit 1, diagnostic
#                                                            names the path
#   T6: compound/SKILL.md invocation deleted, or a
#       threshold literal re-added to step 8              -> exit 1  (FR4b)
#   T7: rule-threshold sentinel de-synced                 -> exit 1  [pin]
#   T8: PER_RULE_CAP bumped alone   -> every PER_RULE_CAP site named  [coverage]
#   T9: B_ALWAYS_WARN bumped alone  -> every WARN site named          [coverage]
#
# Isolation: each case builds a throwaway tree under a single trap-owned root
# (see new_root below) and points the guard at it via LINT_AGENTS_SYNC_ROOT.
# Nothing here touches the real repo.
#
# Sizing note: the guard is a table-driven loop, so exercising several sites of
# the SAME symbol is one code path with different array data and proves little
# beyond the first. What does need one case per symbol is TABLE COVERAGE -- and
# that is not a hypothetical. During implementation, a mutation battery showed
# all three PER_RULE_CAP rows could be deleted from SITES with the suite fully
# green: the loop was well tested, its coverage was not. That is the same defect
# the guard exists to catch (a restatement site silently outside it), reproduced
# one level up. T2/T8/T9 give each authority symbol a coverage case, and T1 pins
# the row count so a SWAPPED row is caught too.
#
# So: one in-sync pin (+ count), three coverage cases (one per symbol), one
# single-site drift asserting the diagnostic's shape, two fail-closed cases,
# three self-guard cases, one pre-existing-behaviour pin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-agents-compound-sync.sh"

# Single owning trap for every fixture tree this suite allocates (ADR-129).
# Cases carve subdirectories out of this root rather than each calling
# `mktemp -d` unowned, so a mid-suite death cannot leak trees.
TMPROOT="$(mktemp -d -t lint-agents-compound-sync-test.XXXXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT
new_root() { mktemp -d "$TMPROOT/case.XXXXXX"; }

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

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit=$expected actual exit=$actual"
  fi
}

# Substring assertion via bash [[ == ]] on a variable -- deliberately NOT
# `printf ... | grep -q`, which under `set -o pipefail` can exit 141 (SIGPIPE)
# when grep closes the pipe on an early match, making a NEGATIVE assertion pass
# vacuously.
assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "needle: $needle | haystack: ${haystack:0:600}"
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "unexpected needle present: $needle"
  fi
}

# -----------------------------------------------------------------------------
# Fixture: a minimal tree where every site agrees with the authority.
# Values differ from the real repo's on purpose -- a test that hardcodes
# production numbers stops testing the guard and starts testing the tree.
# -----------------------------------------------------------------------------
FIX_WARN=31000
FIX_REJECT=34000
FIX_CAP=700

make_fixture_tree() {
  local root="$1"
  mkdir -p "$root/scripts" \
           "$root/apps/web-platform/server/inngest/functions" \
           "$root/plugins/soleur/skills/plan" \
           "$root/plugins/soleur/skills/compound" \
           "$root/plugins/soleur/scripts" \
           "$root/knowledge-base/engineering/operations/runbooks"

  cat > "$root/scripts/lint-agents-rule-budget.py" <<EOF
#!/usr/bin/env python3
B_ALWAYS_WARN = ${FIX_WARN}
B_ALWAYS_REJECT = ${FIX_REJECT}
PER_RULE_CAP = ${FIX_CAP}
EOF

  cat > "$root/apps/web-platform/server/inngest/functions/cron-compound-promote.ts" <<EOF
const MAX_ALWAYS_LOADED_BYTES = ${FIX_REJECT};
const PROPOSE_ALWAYS_LOADED_BUDGET = ${FIX_WARN};
EOF

  cat > "$root/scripts/compound-promote.sh" <<EOF
#!/usr/bin/env bash
ALWAYS_LOADED_CAP=${FIX_REJECT}
PROPOSE_ALWAYS_LOADED_BUDGET=${FIX_WARN}
EOF

  cat > "$root/AGENTS.docs.md" <<EOF
# Docs sidecar

- Budget: <= ${FIX_WARN} warn / <= ${FIX_REJECT} critical. Rules cap at ~${FIX_CAP} bytes. <!-- rule-threshold: 115 -->
EOF

  cat > "$root/plugins/soleur/skills/plan/SKILL.md" <<EOF
# plan

Measure against the ${FIX_REJECT}-byte critical cap, in addition to the per-rule ${FIX_CAP}-byte cap.
EOF

  cat > "$root/plugins/soleur/scripts/grok-fidelity-gate.sh" <<EOF
#!/usr/bin/env bash
echo "==> AGENTS rule-budget lint (B_ALWAYS <= ${FIX_REJECT})"
EOF

  cat > "$root/knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md" <<EOF
# runbook

warn at \`B_ALWAYS >= ${FIX_WARN}\`, reject above \`${FIX_REJECT}\`.
EOF

  make_compound_skill "$root"
}

# compound/SKILL.md carries two FR4b invariants: the linter invocation string
# (including the load-bearing 2>&1) and the absence of threshold literals in
# step 8's tier-decision region.
make_compound_skill() {
  local root="$1"
  cat > "$root/plugins/soleur/skills/compound/SKILL.md" <<EOF
# compound

8. **Rule budget count.** Run the linter and quote its verdict.

   \`\`\`bash
   cd "\$(git rev-parse --show-toplevel)" && \\
     python3 scripts/lint-agents-rule-budget.py \\
       AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1
   \`\`\`

   The \`2>&1\` above is load-bearing: [WARN] and [REJECT] go to stderr.

   - If \`A > 115\`: advisory. <!-- rule-threshold: 115 -->
   - If \`L > ${FIX_CAP}\`: cap per-rule length at ~${FIX_CAP} by moving context out.

   B_TOTAL is informational only -- end of region.

   \`\`\`bash
   if bash ./scripts/rule-metrics-aggregate.sh >/dev/null 2>&1; then :; fi
   \`\`\`
EOF
}

run_guard() {
  local root="$1" out rc=0
  out=$(LINT_AGENTS_SYNC_ROOT="$root" bash "$SUT" 2>&1) || rc=$?
  GUARD_OUT="$out"
  GUARD_RC="$rc"
}

# -----------------------------------------------------------------------------
# T1 -- in-sync tree passes. Positive control for every negative case below:
# if this reds, the fixture is broken and the other cases prove nothing.
# -----------------------------------------------------------------------------
t1_in_sync_passes() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  run_guard "$root"
  assert_exit "T1 in-sync fixture exits 0" "0" "$GUARD_RC"
  # No site-COUNT pin here. It cannot catch a row being SWAPPED (one removed, one
  # added leaves the count unchanged), and a dropped row is already caught by
  # T2/T8/T9, which name every file per authority symbol -- a dropped row means
  # its file stops appearing in the bump output. A bare count pin would only add
  # a maintenance tax that reds on every legitimate row addition while asserting
  # a "catches swaps" property it does not have (this PR's own defect class).
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T2 -- authority bumped alone. Every consumer is now stale, and a single run
# must name ALL of them (accumulate-then-report, FR4b). A first-failure-exit
# guard reports one site and hides the rest, which is the failure mode that let
# #6461 sit undetected across five artifacts.
# -----------------------------------------------------------------------------
t2_linter_only_bump_names_every_site() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  sed -i "s/^B_ALWAYS_REJECT = .*/B_ALWAYS_REJECT = 99000/" "$root/scripts/lint-agents-rule-budget.py"
  run_guard "$root"

  assert_exit "T2 linter-only bump exits non-zero" "1" "$GUARD_RC"
  assert_contains "T2 names the cron TS site" \
    "cron-compound-promote.ts" "$GUARD_OUT"
  assert_contains "T2 names the compound-promote.sh site" \
    "compound-promote.sh" "$GUARD_OUT"
  assert_contains "T2 names the AGENTS.docs.md site" \
    "AGENTS.docs.md" "$GUARD_OUT"
  assert_contains "T2 names the plan/SKILL.md site" \
    "plan/SKILL.md" "$GUARD_OUT"
  assert_contains "T2 names the grok-fidelity-gate.sh site" \
    "grok-fidelity-gate.sh" "$GUARD_OUT"
  assert_contains "T2 names the runbook site" \
    "compound-promote-runbook.md" "$GUARD_OUT"
  assert_contains "T2 reports the expected value" "99000" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T3 -- one consumer drifts. Diagnostic must carry file + expected + found AND
# the measurement unit: the guard compares constants, not measurement bases, so
# a green guard over an unstated unit silently certifies a raw-vs-stripped
# comparison. Naming the unit is what keeps the suspicion alive.
# -----------------------------------------------------------------------------
t3_single_site_drift_names_unit() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  sed -i "s/^const MAX_ALWAYS_LOADED_BYTES = .*/const MAX_ALWAYS_LOADED_BYTES = 12345;/" \
    "$root/apps/web-platform/server/inngest/functions/cron-compound-promote.ts"
  run_guard "$root"

  assert_exit "T3 single-site drift exits non-zero" "1" "$GUARD_RC"
  assert_contains "T3 names the file" "cron-compound-promote.ts" "$GUARD_OUT"
  assert_contains "T3 reports found value"    "12345"      "$GUARD_OUT"
  assert_contains "T3 reports expected value" "$FIX_REJECT" "$GUARD_OUT"
  assert_contains "T3 states the measurement unit" "frontmatter-stripped" "$GUARD_OUT"
  # An unrelated in-sync site must NOT be reported as drifted.
  assert_not_contains "T3 does not falsely report plan/SKILL.md" \
    "plan/SKILL.md" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T4 -- extraction returns empty. Fail-closed: a pattern that matches nothing
# makes the guard vacuous, which is strictly worse than no guard because it
# retires the suspicion.
# -----------------------------------------------------------------------------
t4_empty_extraction_fails_closed() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  cat > "$root/AGENTS.docs.md" <<'EOF'
# Docs sidecar

- Budget guidance with every threshold removed. <!-- rule-threshold: 115 -->
EOF
  run_guard "$root"

  assert_exit "T4 empty extraction exits non-zero" "1" "$GUARD_RC"
  assert_contains "T4 names the file with the unextractable pattern" \
    "AGENTS.docs.md" "$GUARD_OUT"
  assert_contains "T4 says the extraction was empty" "no match" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T5 -- a target file is renamed/absent. Must produce a diagnostic naming the
# missing path, not a bare `grep: No such file or directory`.
# -----------------------------------------------------------------------------
t5_missing_file_fails_closed() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  rm -f "$root/scripts/compound-promote.sh"
  run_guard "$root"

  assert_exit "T5 missing target exits non-zero" "1" "$GUARD_RC"
  assert_contains "T5 names the missing path" \
    "scripts/compound-promote.sh" "$GUARD_OUT"
  assert_contains "T5 says the file is missing" "missing" "$GUARD_OUT"
  assert_not_contains "T5 is not a bare grep error" \
    "No such file or directory" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T6 -- FR4b: the originating file must not exit the sync graph. Once step 8
# stops restating literals, one-time PR-time greps are snapshots, not
# invariants. Both halves are asserted: the invocation must survive, and a
# re-added literal must be caught.
# -----------------------------------------------------------------------------
t6a_deleted_invocation_is_caught() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  # Strip the whole invocation line, keeping everything else intact.
  sed -i '/lint-agents-rule-budget\.py/d' \
    "$root/plugins/soleur/skills/compound/SKILL.md"
  run_guard "$root"

  assert_exit "T6a deleted linter invocation exits non-zero" "1" "$GUARD_RC"
  assert_contains "T6a names compound/SKILL.md" "compound/SKILL.md" "$GUARD_OUT"
  rm -rf "$root"
}

t6b_dropped_stderr_redirect_is_caught() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  # Drop the load-bearing 2>&1 from the INVOCATION only. The fixture
  # deliberately keeps two decoys the real SKILL.md also has -- a prose sentence
  # mentioning `2>&1` and an unrelated fenced block using `>/dev/null 2>&1` --
  # because a file-wide `grep -q '2>&1'` passes on both of those and was
  # verified vacuous against the real file. Only a check anchored on the
  # invocation's own code block can fail here.
  sed -i 's/ 2>&1$//' "$root/plugins/soleur/skills/compound/SKILL.md"
  local remaining
  remaining=$(grep -c '2>&1' "$root/plugins/soleur/skills/compound/SKILL.md")
  # Fixture self-check: if the decoys are gone, this case would pass for the
  # wrong reason and prove nothing.
  if (( remaining < 2 )); then
    fail "T6b fixture invariant" "expected >=2 decoy 2>&1 to survive, found $remaining"
  else
    pass "T6b fixture keeps $remaining decoy 2>&1 occurrences"
  fi
  run_guard "$root"

  assert_exit "T6b dropped 2>&1 exits non-zero" "1" "$GUARD_RC"
  rm -rf "$root"
}

t6c_readded_threshold_literal_is_caught() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  # Re-add exactly the kind of prose that went stale in #6461, inside step 8's
  # tier-decision region.
  sed -i 's|B_TOTAL is informational only -- end of region.|always-loaded total: B_ALWAYS bytes (warn > 18000 / critical > 22000)|' \
    "$root/plugins/soleur/skills/compound/SKILL.md"
  run_guard "$root"

  assert_exit "T6c re-added threshold literal exits non-zero" "1" "$GUARD_RC"
  assert_contains "T6c names compound/SKILL.md" "compound/SKILL.md" "$GUARD_OUT"
  rm -rf "$root"
}

# T6d -- the 2b(ii) shape pattern must catch a threshold re-added in ANY
# plausible notation, not just the bare-5-digit form T6c uses. Review found `23K`
# (uppercase) and `23 000` (spaced) evading a lowercase-comma-only pattern; this
# case pins that the widened pattern catches each. Proving BREADTH is what the
# suite previously only CLAIMED in a comment (the claimed-but-unasserted-coverage
# anti-pattern -- the same defect class this guard exists to prevent).
t6d_readded_literal_any_notation_is_caught() {
  local notation
  for notation in '23K' '18k' '23 000' '23_000' '23,000'; do
    local root; root="$(new_root)"
    make_fixture_tree "$root"
    sed -i "s|B_TOTAL is informational only -- end of region.|reject above ${notation}|" \
      "$root/plugins/soleur/skills/compound/SKILL.md"
    run_guard "$root"
    assert_exit "T6d re-added literal '${notation}' exits non-zero" "1" "$GUARD_RC"
    rm -rf "$root"
  done
}

# -----------------------------------------------------------------------------
# T7 -- pre-existing behaviour pin: the rule-threshold sentinel must stay in
# sync between the AGENTS sidecar and compound/SKILL.md. Extending the guard
# must not regress what it already did.
# -----------------------------------------------------------------------------
t7_sentinel_desync_still_caught() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  sed -i 's/rule-threshold: 115/rule-threshold: 999/' \
    "$root/plugins/soleur/skills/compound/SKILL.md"
  run_guard "$root"

  assert_exit "T7 sentinel de-sync exits non-zero" "1" "$GUARD_RC"
  assert_contains "T7 reports the sentinel mismatch" "rule-threshold" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T10 / T11 -- AUTHORITY fail-closed. T4/T5 pin the fail-closed behaviour for the
# SITE files, but the guard's single most important input -- the authority
# lint-agents-rule-budget.py, from which every expected value is extracted -- was
# unpinned. If the authority is missing or its constants are renamed, EXPECT_* go
# empty, the SITES loop is SKIPPED, and zero sites are checked. Only the err()
# calls at the authority branch (plus the CHECKED backstop) keep that fail-closed;
# these cases prove a fail-open there is loud, so a future refactor that neuters
# either guard reds the suite.
# -----------------------------------------------------------------------------
t10_missing_authority_fails_closed() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  rm -f "$root/scripts/lint-agents-rule-budget.py"
  run_guard "$root"

  assert_exit "T10 missing authority exits non-zero" "1" "$GUARD_RC"
  assert_contains "T10 names the authority" "byte-budget authority" "$GUARD_OUT"
  # The success line must NOT print with zero sites verified (P3 hardening).
  assert_not_contains "T10 does not falsely report OK" \
    "sync: OK" "$GUARD_OUT"
  rm -rf "$root"
}

t11_vacuous_authority_extraction_fails_closed() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  # Rename the authority constants so extraction goes vacuous while the file
  # still exists -- the harder half of the fail-closed contract.
  sed -i 's/^B_ALWAYS_WARN =/B_ALWAYS_WARN_RENAMED =/;
          s/^B_ALWAYS_REJECT =/B_ALWAYS_REJECT_RENAMED =/;
          s/^PER_RULE_CAP =/PER_RULE_CAP_RENAMED =/' \
    "$root/scripts/lint-agents-rule-budget.py"
  run_guard "$root"

  assert_exit "T11 vacuous authority extraction exits non-zero" "1" "$GUARD_RC"
  assert_contains "T11 says the extraction was vacuous" "vacuous" "$GUARD_OUT"
  assert_not_contains "T11 does not falsely report OK" \
    "sync: OK" "$GUARD_OUT"
  rm -rf "$root"
}

# -----------------------------------------------------------------------------
# T8 / T9 -- SITES table COVERAGE, one case per authority symbol.
#
# T2 alone was not enough: it bumps B_ALWAYS_REJECT, so it only exercises the
# REJECT rows. A mutation battery run during implementation showed that all
# three PER_RULE_CAP rows could be DELETED from SITES with the suite still fully
# green -- the exact defect this guard exists to prevent (a restatement site
# silently outside the guard), reproduced inside the guard's own test suite.
#
# Bumping each symbol alone and asserting EVERY file that restates it gets named
# is what makes a dropped row loud.
# -----------------------------------------------------------------------------
t8_per_rule_cap_covers_every_site() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  sed -i "s/^PER_RULE_CAP = .*/PER_RULE_CAP = 999/" "$root/scripts/lint-agents-rule-budget.py"
  run_guard "$root"

  assert_exit "T8 PER_RULE_CAP bump exits non-zero" "1" "$GUARD_RC"
  assert_contains "T8 covers AGENTS.docs.md"        "AGENTS.docs.md"    "$GUARD_OUT"
  assert_contains "T8 covers plan/SKILL.md"         "plan/SKILL.md"     "$GUARD_OUT"
  assert_contains "T8 covers compound/SKILL.md"     "compound/SKILL.md" "$GUARD_OUT"
  rm -rf "$root"
}

t9_warn_covers_every_site() {
  local root; root="$(new_root)"
  make_fixture_tree "$root"
  sed -i "s/^B_ALWAYS_WARN = .*/B_ALWAYS_WARN = 29000/" "$root/scripts/lint-agents-rule-budget.py"
  run_guard "$root"

  assert_exit "T9 B_ALWAYS_WARN bump exits non-zero" "1" "$GUARD_RC"
  assert_contains "T9 covers the cron TS propose site" \
    "cron-compound-promote.ts" "$GUARD_OUT"
  assert_contains "T9 covers the compound-promote.sh propose site" \
    "compound-promote.sh" "$GUARD_OUT"
  assert_contains "T9 covers AGENTS.docs.md warn" "AGENTS.docs.md" "$GUARD_OUT"
  assert_contains "T9 covers the runbook warn site" \
    "compound-promote-runbook.md" "$GUARD_OUT"
  rm -rf "$root"
}

t1_in_sync_passes
t2_linter_only_bump_names_every_site
t8_per_rule_cap_covers_every_site
t9_warn_covers_every_site
t3_single_site_drift_names_unit
t4_empty_extraction_fails_closed
t5_missing_file_fails_closed
t6a_deleted_invocation_is_caught
t6b_dropped_stderr_redirect_is_caught
t6c_readded_threshold_literal_is_caught
t6d_readded_literal_any_notation_is_caught
t7_sentinel_desync_still_caught
t10_missing_authority_fails_closed
t11_vacuous_authority_extraction_fails_closed

# Catastrophic-drop backstop: if a refactor silently drops the case invocations
# at the bottom of this file, an empty/near-empty run must not report success.
# Deliberately a loose FLOOR, not the exact count -- an exact pin would just be a
# maintenance tax that reds on every legitimately-added assertion. The real
# per-case coverage lives in T1-T9; this only catches a wholesale drop.
if (( TOTAL < 30 )); then
  echo "FAIL: suite ran only $TOTAL assertions -- expected a floor of 30 (cases dropped?)"
  exit 1
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
