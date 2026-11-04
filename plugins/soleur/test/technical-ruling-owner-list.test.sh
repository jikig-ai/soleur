#!/usr/bin/env bash
# Suite for the unscoped-owner-list lint in plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh
# (`--pr-body <file>` and its alias `--report <file>`; hard rule hr-technical-fork-is-not-an-operator-question).
#
# Property: under a heading that asks something of the owner ("Needs you", "Owner review items", ...) every
# list item carries `(operator: <category>)`, names no agent-owned step (a CxO sign-off), and carries no
# `Ruled by CTO|CLO agent` text. A technical item or an agent step listed there is routed to the owner by
# mistake; the lint is the check that closing reports and PR bodies written by hand (a stop at draft, a resume)
# otherwise never meet.
#
# Arms:
#   1. cases      -- one fixture per verdict, each run through BOTH --pr-body and --report: exit code, the
#                    reason token on stderr and the exact finding count.
#   2. lines      -- a finding names the file line of the item, not the heading.
#   3. usage      -- --report with no file, a missing file, an empty file: exit 2, never a PASS; an awk that fails
#                    or is missing is exit 2, never a pass; a file named x=1 is read as a file.
#   3b. headings  -- one row per heading alternative and syntax variant of OWNER_HEAD_RE, plus headings that must not match.
#   4. mutations  -- each mutant of the gate (markers `# mut:owner-list*`, mutated on a sandbox copy) must flip
#                    a named fixture's verdict; the unmutated control runs first and is green.
#   5. floor      -- an assertion-count floor, reported with printf and exit.
#
# Separate from technical-ruling-gate.test.sh on purpose: that suite's pass-count floor stays untouched.
# Writes only under `mktemp -d` (preflight Check 10 runs suites with the repository read-only).
# The EXIT trap is installed BEFORE test-helpers.sh is sourced, so the helpers' own trap composes.

set -euo pipefail
export LC_ALL=C

TMP="$(mktemp -d -t trg-owner-list.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
assert_fixture_dir "$TMP"

REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"
GATE="$REPO_ROOT/plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh"
FIXTURES="$SUITE_DIR/fixtures/technical-ruling-gate"

# run <script> <args...>: capture rc/out/err into $TMP/last.{rc,out,err}. rc is read on its own line.
run() {
  local script="$1"; shift
  set +e
  bash "$script" "$@" >"$TMP/last.out" 2>"$TMP/last.err" </dev/null
  rc=$?
  set -e
  echo "$rc" > "$TMP/last.rc"
}
last_rc() { cat "$TMP/last.rc"; }
# count_reason <reason>: number of [FAIL] findings with that reason token on the last run's stderr.
count_reason() { grep -cE "^\[FAIL\] .*: ${1} - " "$TMP/last.err" || true; }

assert_verdict_line() {
  local msg="$1"
  if grep -qE '^\[PASS\] ' "$TMP/last.out" || grep -qE '^\[FAIL\] ' "$TMP/last.err"; then
    echo "  PASS: $msg (verdict line present)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (no [PASS]/[FAIL] line)"; FAIL=$((FAIL + 1))
  fi
}

# Instrument self-test: the dispatch helpers must be able to FAIL. A helper that always passes keeps the
# floor intact (it counts), so the floor alone cannot see it.
( FAIL=0; assert_eq a b "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_eq cannot fail -- dispatch is neutered\n' >&2; exit 2; }
( FAIL=0; : > "$TMP/last.out"; : > "$TMP/last.err"; assert_verdict_line "control" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: assert_verdict_line cannot fail -- dispatch is neutered\n' >&2; exit 2; }
( : > "$TMP/last.err"; [[ "$(count_reason owner-list-untagged)" == 0 ]] ) \
  || { printf 'FATAL: count_reason cannot read zero\n' >&2; exit 2; }
( printf '[FAIL] f:1: owner-list-untagged - x\n' > "$TMP/last.err"; [[ "$(count_reason owner-list-untagged)" == 1 ]] ) \
  || { printf 'FATAL: count_reason cannot read one\n' >&2; exit 2; }
: > "$TMP/last.err"

[[ -f "$GATE" ]] || { echo "  FAIL: gate script missing: $GATE"; FAIL=$((FAIL + 1)); print_results 0; exit 1; }

echo "=== Control: the unmutated gate on a compliant owner list ==="
run "$GATE" --report "$FIXTURES/owner-list-tagged.md"
assert_eq "0" "$(last_rc)" "owner-list-tagged.md via --report exits 0"
assert_verdict_line "owner-list-tagged.md"
assert_eq "1" "$(grep -cF 'no unscoped owner list' "$TMP/last.out" || true)" "the PASS line says no unscoped owner list"

echo "=== Arm 1: cases, each through --pr-body AND --report ==="
# name | fixture | want-rc | reason | want-count | reasons that must be absent (comma list or -)
CASES="$TMP/cases.txt"
cat > "$CASES" <<'EOF'
the real offending shape (untagged items, a ruled item)|owner-list-review-items.md|1|owner-list-untagged|4|agent-owned-step
the real offending shape keeps its ruled item|owner-list-review-items.md|1|owner-list-ruled|1|-
needs-you list with untagged items|owner-list-needs-you-untagged.md|1|owner-list-untagged|2|agent-owned-step,owner-list-ruled
tagged needs-you list|owner-list-tagged.md|0|-|0|-
a CPO sign-off is an agent step even when tagged|owner-list-cpo.md|1|agent-owned-step|1|owner-list-untagged,owner-list-ruled
a Ruled by CTO agent item is not an owner item|owner-list-ruled.md|1|owner-list-ruled|1|owner-list-untagged,agent-owned-step
the list inside code fences is not examined|owner-list-fenced.md|0|-|0|-
an unclosed fence is exit 2|owner-list-unclosed.md|2|-|0|-
an ordinary section after the owner list is not examined|owner-list-sibling.md|0|-|0|-
a bold-only heading opens an owner list|owner-list-bold-heading.md|1|owner-list-untagged|1|-
a bold-only heading with a colon, tagged|owner-list-bold-tagged.md|0|-|0|-
a sub-heading stays inside the owner list|owner-list-subheading.md|1|owner-list-untagged|1|-
a tag written only inside a code span does not count|owner-list-inline-code.md|1|owner-list-untagged|1|-
the corrected report shape|owner-list-corrected.md|0|-|0|-
a + bullet is a list item|owner-list-plus-bullets.md|1|owner-list-untagged|1|-
Nothing and None bullets are no item|owner-list-nothing.md|0|-|0|-
a long None-led item is still an item|owner-list-nothing-smuggle.md|1|owner-list-untagged|1|-
bold-only labels close a section opened by a heading|owner-list-bold-closes.md|0|-|0|-
a thematic break closes the section|owner-list-hr-closes.md|0|-|0|-
every tag must be valid|owner-list-multi-tag.md|1|owner-list-untagged|1|-
agent sign-off spellings and gaps|owner-list-agents-roles.md|1|agent-owned-step|8|owner-list-untagged
non-roles and far gaps are not agent steps|owner-list-agents-clean.md|0|-|0|-
nested untagged items are items|owner-list-nested.md|1|owner-list-untagged|2|-
a bold heading with the colon outside|owner-list-colon-bold.md|1|owner-list-untagged|1|-
a fence closed by a longer fence|owner-list-longer-fence.md|0|-|0|-
a fence indented four spaces is text and fails closed|owner-list-indented-fence.md|1|owner-list-untagged|1|-
a heading without the space after the hashes|owner-list-hash-nospace.md|1|owner-list-untagged|1|-
a hash line without a space does not close the section|owner-list-hash-noclose.md|1|owner-list-untagged|1|-
an invalid category is no tag|owner-list-bogus-category.md|1|owner-list-untagged|1|-
a hyphenated heading|owner-list-hyphen.md|1|owner-list-untagged|1|-
a Blocked heading|owner-list-blocked.md|1|owner-list-untagged|1|-
a Waiting on operator heading|owner-list-waiting.md|1|owner-list-untagged|1|-
an Action required heading|owner-list-action-required.md|1|owner-list-untagged|1|-
a heading that only starts like an owner heading|owner-list-boundary.md|0|-|0|-
EOF
while IFS='|' read -r name fixture want_rc reason want_n absent; do
  [[ -n "$name" ]] || continue
  for mode in --pr-body --report; do
    run "$GATE" "$mode" "$FIXTURES/$fixture"
    assert_eq "$want_rc" "$(last_rc)" "$mode $name: rc"
    case "$want_rc" in
      0) assert_verdict_line "$mode $name"
         assert_eq "0" "$(grep -cE '^\[FAIL\] ' "$TMP/last.err" || true)" "$mode $name: no [FAIL] line" ;;
      1) assert_verdict_line "$mode $name"
         assert_eq "$want_n" "$(count_reason "$reason")" "$mode $name: $reason findings" ;;
      2) assert_eq "1" "$(grep -cE '^\[ERROR\] ' "$TMP/last.err" || true)" "$mode $name: an [ERROR] line, never a PASS"
         assert_eq "0" "$(grep -cF '[PASS]' "$TMP/last.out" || true)" "$mode $name: no [PASS] line" ;;
    esac
    if [[ "$absent" != "-" ]]; then
      for r in ${absent//,/ }; do
        assert_eq "0" "$(count_reason "$r")" "$mode $name: no $r finding"
      done
    fi
  done
done < "$CASES"

echo "=== Arm 1b: the failure line carries its remedy ==="
run "$GATE" --report "$FIXTURES/owner-list-needs-you-untagged.md"
assert_eq "2" "$(grep -cE '^\[FAIL\] .*: owner-list-untagged - tag it \(operator: <category>\), or route it to the CTO/CPO \(technical-ruling-delegation\.md\), or move it under Model Dissents' "$TMP/last.err" || true)" "the remedy names the tag, the CTO/CPO route and Model Dissents"

echo "=== Arm 1c: the lint composes with the label and pending lints ==="
run "$GATE" --report "$FIXTURES/pr-body-label-bare.md"
assert_eq "1" "$(last_rc)" "--report still fails an unscoped owner-decision label"
assert_eq "1" "$(grep -cE '^\[FAIL\] .*: owner-label-unscoped - ' "$TMP/last.err" || true)" "--report reports the label finding"
run "$GATE" --report "$FIXTURES/pr-body-pending.md"
assert_eq "1" "$(last_rc)" "--report still fails a pending - assumed placeholder"
run "$GATE" --report "$FIXTURES/pr-body-clean.md"
assert_eq "0" "$(last_rc)" "--report passes a body with no owner list"
run "$GATE" --pr-body "$FIXTURES/pr-body-label-scoped.md"
assert_eq "0" "$(last_rc)" "--pr-body still passes a scoped label"

echo "=== Arm 2: a finding names the file line of the item ==="
run "$GATE" --report "$FIXTURES/owner-list-review-items.md"
ln="$({ grep -n 'Write-capable tokens' "$FIXTURES/owner-list-review-items.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: owner-list-untagged - " "$TMP/last.err" || true)" "item 1 of the offending shape is named by its file line"
ln="$({ grep -n 'CPO sign-off' "$FIXTURES/owner-list-review-items.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: owner-list-untagged - " "$TMP/last.err" || true)" "the untagged CPO sign-off item is named by its file line"
ln="$({ grep -n 'Ruled by CTO agent' "$FIXTURES/owner-list-review-items.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: owner-list-ruled - " "$TMP/last.err" || true)" "the ruled item is named by its file line"
run "$GATE" --report "$FIXTURES/owner-list-bold-heading.md"
ln="$({ grep -n 'Pick between' "$FIXTURES/owner-list-bold-heading.md" || true; } | head -1 | cut -d: -f1)"
assert_eq "1" "$(grep -cE "^\[FAIL\] .*:${ln}: owner-list-untagged - " "$TMP/last.err" || true)" "a bold-heading list finding names the item line"

echo "=== Arm 2b: crlf, bom and the finding cap ==="
sed 's/$/\r/' "$FIXTURES/owner-list-needs-you-untagged.md" > "$TMP/crlf.md"
run "$GATE" --report "$TMP/crlf.md"
assert_eq "2" "$(count_reason owner-list-untagged)" "a CRLF report is read the same way"
{ printf '\357\273\277'; cat "$FIXTURES/owner-list-needs-you-untagged.md"; } > "$TMP/bom.md"
run "$GATE" --report "$TMP/bom.md"
assert_eq "2" "$(count_reason owner-list-untagged)" "a report with a BOM is read the same way"
printf '**Needs you**\r\n\r\n- a untagged item\r\n' > "$TMP/crlf-bold.md"
run "$GATE" --report "$TMP/crlf-bold.md"
assert_eq "1" "$(count_reason owner-list-untagged)" "a CRLF bold-only heading is recognised (the \\r is stripped)"
printf '## Needs you\r\n\r\n- arm it (operator: scope)\r\n' > "$TMP/crlf-tagged.md"
run "$GATE" --report "$TMP/crlf-tagged.md"
assert_eq "0" "$(last_rc)" "a CRLF tagged item passes"
printf '\357\273\277## Needs you\n\n- a untagged item\n' > "$TMP/bom-first.md"
run "$GATE" --report "$TMP/bom-first.md"
assert_eq "1" "$(count_reason owner-list-untagged)" "a BOM in front of the owner heading on line 1 is stripped"
for cap_n in 256 512; do
  { printf '## Needs you\n\n'; awk -v n="$cap_n" 'BEGIN { for (i = 0; i < n; i++) print "- untagged item " i }'; } > "$TMP/n$cap_n.md"
  run "$GATE" --report "$TMP/n$cap_n.md"
  assert_eq "1" "$(last_rc)" "exactly $cap_n untagged items is still exit 1 (the count does not wrap to 0)"
done
printf '## Needs you\n\n- Arm and merge it (operator: production-mutating)\n' > "$TMP/inline.md"
run "$GATE" --report "$TMP/inline.md"
assert_eq "0" "$(last_rc)" "a one-item tagged list written inline passes"
printf '## Needs you\n\nNothing needs you right now.\n' > "$TMP/none.md"
run "$GATE" --report "$TMP/none.md"
assert_eq "0" "$(last_rc)" "the plain no-items sentence passes"
printf '### 3. Needs you\n\n* a star bullet\n' > "$TMP/numbered-head.md"
run "$GATE" --report "$TMP/numbered-head.md"
assert_eq "1" "$(last_rc)" "a numbered heading and a star bullet are still recognised"
printf '## Needs you\n\n1) a paren item\n' > "$TMP/paren.md"
run "$GATE" --report "$TMP/paren.md"
assert_eq "1" "$(last_rc)" "a 1) numbered item is a list item"
printf '## Needs you\n\n- Sign off needed (operator: brand)\n- Awaiting sign-off from the CTO (operator: scope)\n- cmo-review pending (operator: brand)\n' > "$TMP/agents.md"
run "$GATE" --report "$TMP/agents.md"
assert_eq "2" "$(count_reason agent-owned-step)" "sign-off from the CTO and a CMO review are agent steps; a bare sign-off is not"

echo "=== Arm 3: usage and unmeasurable input ==="
run "$GATE" --report
assert_eq "2" "$(last_rc)" "--report with no file is exit 2"
run "$GATE" --report "$TMP/no-such-report.md"
assert_eq "2" "$(last_rc)" "--report on a missing file is exit 2"
: > "$TMP/empty.md"
run "$GATE" --report "$TMP/empty.md"
assert_eq "2" "$(last_rc)" "--report on an empty file is exit 2, never a PASS"
printf ' \n\n  \n' > "$TMP/ws.md"
run "$GATE" --report "$TMP/ws.md"
assert_eq "2" "$(last_rc)" "--report on a whitespace-only file is exit 2"
run "$GATE" --report "$FIXTURES"
assert_eq "2" "$(last_rc)" "--report on a directory is exit 2"

echo "=== Arm 3b: one row per OWNER_HEAD_RE alternative and per heading syntax ==="
# Every row is written as a heading line above one untagged item and must give exit 1 with one owner-list-untagged finding.
HEADS="$TMP/heads.txt"
cat > "$HEADS" <<'EOF'
## Needs you
## Needs your decision
## Owner review items (read these first)
## Owner reviews
## Owner decisions
## Owner items
## Owner-side
## Owner side questions
## Open owner items
## Pending owner review
## Decisions for you
## Decision for you
## Your calls
## Your call
## Questions for you
## Question for you
## Waiting on you
## Waiting for you
## For the owner
## What I need from you
## Owner actions
## Owner action items
## Owner steps
## Owner to-do
## Action required
## Actions required
## Action needed
## For you
## For your review
## For your decision
## Manual steps
## Manual step
## Operator steps
## Operator actions
## Operator items
## Human action
## Human actions
## Founder to-do
## Founder todo
## Founder actions
## Blocked on you
## Blocked
## Blocked by CI
## Awaiting your go
## Awaiting your approval
## Awaiting owner
## Needs input
## Needs owner
## Needs operator
## Needs-you
## Needs_you
## Owner_review_items
## Decisions needed
## Your decision
## What you need to do
## Waiting on
## Waiting for
## Waiting on operator
## Waiting for operator
# Needs you
### Needs you
##### Needs you
##Needs you
## **Needs you**
## Needs you:
## Needs you ##
## 3. Needs you
## 2) Needs you
## NEEDS YOU
## `Needs you`
   ## Needs you
**Needs you**
**Needs you:**
**Needs you**:
__Needs you__
__Needs you__:
*Needs you*
_Needs you_
**Owner actions**
**Blocked**
**Waiting on operator**
**Action required**
EOF
while IFS= read -r hl; do
  [[ -n "$hl" ]] || continue
  printf '%s\n\n- an untagged item\n' "$hl" > "$TMP/head-row.md"
  run "$GATE" --report "$TMP/head-row.md"
  assert_eq "1" "$(last_rc)" "heading [$hl]: an untagged item under it is exit 1"
  assert_eq "1" "$(count_reason owner-list-untagged)" "heading [$hl]: one owner-list-untagged finding"
done < "$HEADS"
NEG="$TMP/neg-heads.txt"
cat > "$NEG" <<'EOF'
## Summary
## Verification
## What the review found and fixed
## Rulings
## Model Dissents
## Next steps
## Test plan
## Notes
## What changed
## For your information
## Open questions
## Needs review
## Blockers
## Owner
## Waiting
## Directors
**Test plan**
**Notes:**
EOF
while IFS= read -r hl; do
  [[ -n "$hl" ]] || continue
  printf '%s\n\n- an untagged item\n' "$hl" > "$TMP/head-row.md"
  run "$GATE" --report "$TMP/head-row.md"
  assert_eq "0" "$(last_rc)" "heading [$hl] is not an owner list: an untagged item under it passes"
done < "$NEG"

echo "=== Arm 3c: an awk that fails or is missing is exit 2, never a pass; a file named x=1 is a file ==="
SHIM="$TMP/shim"; mkdir -p "$SHIM"
printf '#!/bin/sh\nexit 2\n' > "$SHIM/awk"; chmod +x "$SHIM/awk"
PATH="$SHIM:$PATH" run "$GATE" --report "$FIXTURES/owner-list-tagged.md"
assert_eq "2" "$(last_rc)" "a failing awk on a compliant report is exit 2, not a PASS"
assert_eq "0" "$(grep -cF '[PASS]' "$TMP/last.out" || true)" "a failing awk prints no PASS line"
PATH="$SHIM:$PATH" run "$GATE" --pr-body "$FIXTURES/owner-list-review-items.md"
assert_eq "2" "$(last_rc)" "a failing awk on an offending body is exit 2 via --pr-body too"
NOAWK="$TMP/noawk"; mkdir -p "$NOAWK"
for tool in bash dirname grep mktemp rm cat head tr sed cut wc date timeout; do
  tp="$(command -v "$tool" || true)"; [[ -n "$tp" ]] && ln -s "$tp" "$NOAWK/$tool"
done
PATH="$NOAWK" run "$GATE" --report "$FIXTURES/owner-list-tagged.md"
assert_eq "2" "$(last_rc)" "no awk on PATH is exit 2, not a PASS"
mkdir -p "$TMP/opdir"; cp "$FIXTURES/owner-list-needs-you-untagged.md" "$TMP/opdir/x=1"
cd "$TMP/opdir"
run "$GATE" --report x=1
cd "$SUITE_DIR"
assert_eq "2" "$(count_reason owner-list-untagged)" "a report named x=1 is read as a file, not taken as an awk assignment"

echo "=== Arm 4: mutations (control first, then one mutant per marker) ==="
MUT="$TMP/mut"; mkdir -p "$MUT"
pristine="$MUT/gate.pristine.sh"; cp "$GATE" "$pristine"
grep -q 'mut:owner-list' "$pristine" || { echo "  FAIL: the gate carries no mut:owner-list marker"; FAIL=$((FAIL + 1)); }
mutate() { # <name> <sed-script>: write $MUT/gate.<name>.sh and prove the mutation LANDED against the pristine copy
  local name="$1" expr="$2" out="$MUT/gate.$1.sh"
  sed -E "$expr" "$pristine" > "$out"
  if cmp -s "$pristine" "$out"; then
    echo "  FAIL: mutation $name did not land"; FAIL=$((FAIL + 1)); return 1
  fi
  echo "  PASS: mutation $name landed"; PASS=$((PASS + 1))
}
mutant_crashed() { [[ "$(last_rc)" == 127 ]] || grep -qE 'unbound variable|syntax error|command not found|awk: ' "$TMP/last.err"; }
killed() { # <name> <script> <pinned-rc> <args...>: the pristine script must give the pinned rc, the mutant another WITHOUT crashing
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
killed_count() { # <name> <script> <reason> <want-count> <args...>: pristine shows the count, the mutant changes it without crashing
  local name="$1" script="$2" reason="$3" want="$4" got; shift 4
  run "$pristine" "$@"
  got="$(count_reason "$reason")"
  if [[ "$got" != "$want" ]]; then
    echo "  FAIL: $name: the pristine script shows $got $reason findings, not the pinned $want"; FAIL=$((FAIL + 1)); return
  fi
  run "$script" "$@"
  got="$(count_reason "$reason")"
  if mutant_crashed; then
    echo "  FAIL: mutant $name CRASHED; a crash is not a kill"; FAIL=$((FAIL + 1))
  elif [[ "$got" != "$want" ]]; then
    echo "  PASS: mutant $name killed ($got $reason findings, pinned $want)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: mutant $name SURVIVED ($got $reason findings, same as pinned)"; FAIL=$((FAIL + 1))
  fi
}

run "$pristine" --report "$FIXTURES/owner-list-tagged.md"
assert_eq "0" "$(last_rc)" "mutation control: the pristine copy is green on a compliant list"
run "$pristine" --report "$FIXTURES/owner-list-needs-you-untagged.md"
assert_eq "1" "$(last_rc)" "mutation control: the pristine copy is red on an untagged list"
# Instrument controls for the arm itself: each decider must be able to say SURVIVED / not-landed.
( FAIL=0; killed ctrl "$pristine" 0 --report "$FIXTURES/owner-list-tagged.md" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: killed cannot report a survivor\n' >&2; exit 2; }
( FAIL=0; killed_count ctrl "$pristine" owner-list-untagged 0 --report "$FIXTURES/owner-list-tagged.md" >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: killed_count cannot report a survivor\n' >&2; exit 2; }
( FAIL=0; mutate ctrl 's/zz-no-such-text-zz/y/' >/dev/null; [[ $FAIL -eq 1 ]] ) \
  || { printf 'FATAL: mutate cannot report a mutation that did not land\n' >&2; exit 2; }

# The tag check: with it disabled an untagged list passes.
mutate tag-check 's/^.*# mut:owner-list$/      if (0) print NR "\\towner-list-untagged" # mut:owner-list/' && \
  killed_count tag-check "$MUT/gate.tag-check.sh" owner-list-untagged 2 --report "$FIXTURES/owner-list-needs-you-untagged.md"
# The agent-step check (AGENT_STEP_RE use): with it disabled a tagged CPO sign-off passes.
mutate agent-step 's/^.*# mut:owner-list-agent$/      if (0) print NR "\\tagent-owned-step" # mut:owner-list-agent/' && \
  killed agent-step "$MUT/gate.agent-step.sh" 1 --report "$FIXTURES/owner-list-cpo.md"
# The same through --pr-body, so the alias cannot hide a path-specific wiring.
killed agent-step-pr-body "$MUT/gate.agent-step.sh" 1 --pr-body "$FIXTURES/owner-list-cpo.md"
# The ruled check.
mutate ruled 's/^.*# mut:owner-list-ruled$/      if (0) print NR "\\towner-list-ruled" # mut:owner-list-ruled/' && \
  killed ruled "$MUT/gate.ruled.sh" 1 --report "$FIXTURES/owner-list-ruled.md"
# Section close: a section that never closes swallows the sibling section's bullets.
mutate no-close 's/^.*# mut:owner-list-close$/      if (0) insec = 0 # mut:owner-list-close/' && \
  killed no-close "$MUT/gate.no-close.sh" 0 --report "$FIXTURES/owner-list-sibling.md"
# Sub-headings: a deeper heading must not end the section.
mutate sub-heading 's/^.*# mut:owner-list-sub$/      if (0) next # mut:owner-list-sub/' && \
  killed sub-heading "$MUT/gate.sub-heading.sh" 1 --report "$FIXTURES/owner-list-subheading.md"
# Bold-only headings.
mutate no-bold 's|^.*# mut:owner-list-bold$|    raw ~ /^ ? ? ?#+[ \\t]/ { # mut:owner-list-bold|' && \
  killed no-bold "$MUT/gate.no-bold.sh" 1 --report "$FIXTURES/owner-list-bold-heading.md"
# Fences: a fenced owner list must not be examined.
mutate no-fence 's/^.*# mut:owner-list-fence$/    { f = 0 } # mut:owner-list-fence/' && \
  killed no-fence "$MUT/gate.no-fence.sh" 0 --report "$FIXTURES/owner-list-fenced.md"
# Code spans: a tag inside a code span must not count.
mutate keep-code 's/^.*# mut:owner-list-code$/    { raw = tolower($0); t = raw } # mut:owner-list-code/' && \
  killed keep-code "$MUT/gate.keep-code.sh" 1 --report "$FIXTURES/owner-list-inline-code.md"
# The heading regex: with it emptied no heading is recognised.
mutate head-re "s/^OWNER_HEAD_RE=.*/OWNER_HEAD_RE='^zzz-never'/" && \
  killed head-re "$MUT/gate.head-re.sh" 1 --report "$FIXTURES/owner-list-review-items.md"
# The wiring: the call dropped from the mode.
mutate no-call 's/^.*check_owner_lists "\$f" "\$f".*# mut:owner-list-call$/    : # mut:owner-list-call/' && \
  { killed no-call "$MUT/gate.no-call.sh" 1 --pr-body "$FIXTURES/owner-list-review-items.md"; }
# The alias: --report removed from the case pattern.
mutate no-alias 's/^  --pr-body\|--report\).*# mut:owner-list-alias$/  --pr-body) # mut:owner-list-alias/' && \
  killed no-alias "$MUT/gate.no-alias.sh" 1 --report "$FIXTURES/owner-list-review-items.md"

# The new guards of the review-fix round, each proven on its own fixture.
mutate plus 's/\(\[-\*\+\]\|/([-*]|/g' && \
  killed plus "$MUT/gate.plus.sh" 1 --report "$FIXTURES/owner-list-plus-bullets.md"
mutate none 's/^.*# mut:owner-list-none$/      if (0) next # mut:owner-list-none/' && \
  killed none "$MUT/gate.none.sh" 0 --report "$FIXTURES/owner-list-nothing.md"
mutate hr 's/^.*# mut:owner-list-hr$/    t ~ \/zz-no-hr-zz\/ { insec = 0; next } # mut:owner-list-hr/' && \
  killed hr "$MUT/gate.hr.sh" 0 --report "$FIXTURES/owner-list-hr-closes.md"
mutate bold-close 's/ && lvl != 9\) next # mut:owner-list-sub/) next # mut:owner-list-sub/' && \
  killed bold-close "$MUT/gate.bold-close.sh" 0 --report "$FIXTURES/owner-list-bold-closes.md"
mutate alltags 's/tagged = \(nv > 0 && nv == na\)/tagged = (nv > 0)/' && \
  killed alltags "$MUT/gate.alltags.sh" 1 --report "$FIXTURES/owner-list-multi-tag.md"
mutate cats-any 's/-v cats="\$CATS_RE"/-v cats=".+"/' && \
  killed cats-any "$MUT/gate.cats-any.sh" 1 --report "$FIXTURES/owner-list-bogus-category.md"
mutate cr 's/^.*# mut:owner-list-cr$/    { } # mut:owner-list-cr/' && \
  killed cr "$MUT/gate.cr.sh" 1 --report "$TMP/crlf-bold.md"
mutate bom 's/^.*# mut:owner-list-bom$/    NR == 1 { } # mut:owner-list-bom/' && \
  killed bom "$MUT/gate.bom.sh" 1 --report "$TMP/bom-first.md"
mutate cap 's/^  \(\( n > 255 \)\) && n=255 # mut:owner-list-cap$/  : # mut:owner-list-cap/' && \
  { killed cap-256 "$MUT/gate.cap.sh" 1 --report "$TMP/n256.md"; killed cap-512 "$MUT/gate.cap.sh" 1 --report "$TMP/n512.md"; }
mutate awk-status 's/^.*# mut:owner-list-awk-status$/  : # mut:owner-list-awk-status/' && \
  { PATH="$SHIM:$PATH" killed awk-status "$MUT/gate.awk-status.sh" 2 --report "$FIXTURES/owner-list-tagged.md"; }
mutate operand "s|^  ' < \"\\\$1\" # mut:owner-list-operand\$|  ' \"\$1\" # mut:owner-list-operand|" && \
  { cd "$TMP/opdir"; killed operand "$MUT/gate.operand.sh" 1 --report x=1; cd "$SUITE_DIR"; }
mutate fence-close 's/len >= flen && /len == flen \&\& /' && \
  killed fence-close "$MUT/gate.fence-close.sh" 0 --report "$FIXTURES/owner-list-longer-fence.md"
mutate agent-no-coo-cfo '/^AGENT_STEP_RE=/ s/\|coo\|cfo//g' && \
  killed_count agent-no-coo-cfo "$MUT/gate.agent-no-coo-cfo.sh" agent-owned-step 8 --report "$FIXTURES/owner-list-agents-roles.md"
mutate agent-no-approv '/^AGENT_STEP_RE=/ s/\|approv//g' && \
  killed_count agent-no-approv "$MUT/gate.agent-no-approv.sh" agent-owned-step 8 --report "$FIXTURES/owner-list-agents-roles.md"
mutate agent-hyphen-only '/^AGENT_STEP_RE=/ s/sign\[ -\]\?off/sign-?off/g' && \
  killed_count agent-hyphen-only "$MUT/gate.agent-hyphen-only.sh" agent-owned-step 8 --report "$FIXTURES/owner-list-agents-roles.md"
mutate agent-role-first-only '/^AGENT_STEP_RE=/ s/\|\(sign\[ -\]\?off\|approv\|review\)\[\^\.;\]\*\[\^a-z\].*$/'"'"'/' && \
  killed_count agent-role-first-only "$MUT/gate.agent-role-first-only.sh" agent-owned-step 8 --report "$FIXTURES/owner-list-agents-roles.md"
mutate agent-no-word-start 's/if \(i > 1 && substr\(s, i - 1, 1\) ~ \/\[a-z0-9\]\/\) continue/if (0) continue/' && \
  killed agent-no-word-start "$MUT/gate.agent-no-word-start.sh" 0 --report "$FIXTURES/owner-list-agents-clean.md"
mutate head-no-blocked '/^OWNER_HEAD_RE=/ s/\|blocked\)/)/' && \
  killed head-no-blocked "$MUT/gate.head-no-blocked.sh" 1 --report "$FIXTURES/owner-list-blocked.md"
mutate head-no-waiting '/^OWNER_HEAD_RE=/ s/waiting \(on\|for\)\|//' && \
  killed head-no-waiting "$MUT/gate.head-no-waiting.sh" 1 --report "$FIXTURES/owner-list-waiting.md"
mutate head-no-action '/^OWNER_HEAD_RE=/ s/actions\? \(required\|needed\|items\?\)\|//' && \
  killed head-no-action "$MUT/gate.head-no-action.sh" 1 --report "$FIXTURES/owner-list-action-required.md"
mutate head-no-boundary '/^OWNER_HEAD_RE=/ s/\(\[\^a-z0-9\]\|\$\)'"'"'$/'"'"'/' && \
  killed head-no-boundary "$MUT/gate.head-no-boundary.sh" 0 --report "$FIXTURES/owner-list-boundary.md"
mutate no-norm 's/gsub\(\/\[\*`:_-\]\/, " ", h\)/gsub(\/[*`:]\/, " ", h)/' && \
  killed no-norm "$MUT/gate.no-norm.sh" 1 --report "$FIXTURES/owner-list-hyphen.md"
mutate hash-space 's/raw ~ \/\^ \? \? \?#\+\/ \|\|/raw ~ \/^ ? ? ?#+[ \\t]\/ ||/' && \
  killed hash-space "$MUT/gate.hash-space.sh" 1 --report "$FIXTURES/owner-list-hash-nospace.md"
mutate weak 's/^.*# mut:owner-list-weak$/      if (0) next # mut:owner-list-weak/' && \
  killed weak "$MUT/gate.weak.sh" 1 --report "$FIXTURES/owner-list-hash-noclose.md"

echo "=== Arm 5: assertion-count floor ==="
ran=$((PASS + FAIL))
FLOOR=511
printf 'owner-list suite: %d assertions ran (floor %d)\n' "$ran" "$FLOOR"
if (( ran < FLOOR )); then
  printf 'FATAL: only %d assertions ran, the floor is %d -- the dispatch was neutered or arms were skipped\n' "$ran" "$FLOOR" >&2
  exit 1
fi
print_results "$FLOOR"
