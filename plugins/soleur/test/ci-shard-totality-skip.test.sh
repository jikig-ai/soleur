#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard — the shard-totality-mutations skip gate cannot skip a diff the battery could be sensitive to
# (#9729, ADR-276 S4 PR A).
#
# PROPERTY. `shard-totality-mutations` in .github/workflows/ci.yml skips its battery step only when
# scripts/ci-shard-totality-classify.sh emits `false`, which it does only on `pull_request` with a
# non-empty changed-file list in which EVERY row is status M/A and a markdown file under
# `knowledge-base/` or at the repo root. Everything else (a shell/py/ts file anywhere, including under
# knowledge-base/, which the battery's census can enumerate as a declarer; a deletion, rename, copy,
# typechange; any other event; an empty or unresolvable diff) emits `true` and runs the battery.
#
# ASSEMBLY. (a) the shipped classifier, executed over fixture `git diff --name-status` rows on stdin —
# never a re-implemented mirror; (b) ci.yml wiring anchors scoped to the shard-totality-mutations job
# section: the classify step precedes the battery step, the battery step is gated on the verdict, the
# verdict is validated and emitted, the checkout is full-history on a pull_request (an EXECUTED
# check on the ternary: a sweep for falsy-middle shapes, not an evaluation), and the job carries no job-level if:/needs: beyond the
# two pinned by scripts/ci-push-dedupe.test.sh and scripts/ci-draft-light.test.sh.
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/ci-shard-totality-classify.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

# Instrument self-test (ADR-193): both helpers must move their counter, and the floor below reports
# through printf + exit, never through the helpers it guards.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)" >/dev/null
fail "instrument self-test (expected, subtracted)" >/dev/null
if [ "$PASS" -ne $((_p0 + 1)) ] || [ "$FAIL" -ne $((_f0 + 1)) ]; then
  printf 'FATAL: pass()/fail() did not each move their counter\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0

expect_verdict() { # <desc> <true|false> <event> <stdin-rows>
  local desc="$1" expected="$2" event="$3" rows="$4" actual rc
  actual="$(printf '%s' "$rows" | bash "$CLASSIFIER" "$event" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc (want=$expected got='${actual}' rc=$rc)"
  fi
}

echo "── classifier artifact"
if [ -x "$CLASSIFIER" ]; then
  pass "classifier exists and is executable"
else
  fail "classifier missing/not executable: $CLASSIFIER"
  echo; echo "Guard: $PASS passed, $FAIL failed"
  exit 1
fi

echo "── decision matrix (pull_request)"
expect_verdict "kb markdown only skips"                  false pull_request $'M\tknowledge-base/project/learnings/x.md\n'
expect_verdict "kb markdown added + root md skips"       false pull_request $'A\tknowledge-base/a.md\nM\tREADME.md\n'
expect_verdict "bare path (no status) treated as M"      false pull_request $'knowledge-base/a.md\n'
expect_verdict "kb shell file runs (census declarer)"    true  pull_request $'M\tknowledge-base/x.sh\n'
expect_verdict "kb non-md (json) runs"                   true  pull_request $'M\tknowledge-base/x.json\n'
expect_verdict "kb python file runs"                     true  pull_request $'M\tknowledge-base/x.py\n'
expect_verdict "runner edit runs"                        true  pull_request $'M\tscripts/test-all.sh\n'
expect_verdict "ci.yml edit runs"                        true  pull_request $'M\t.github/workflows/ci.yml\n'
expect_verdict "shard legs tsv edit runs"                true  pull_request $'M\tscripts/suite-shard-legs.tsv\n'
expect_verdict "mixed kb md + app path runs"             true  pull_request $'M\tknowledge-base/a.md\nM\tapps/web-platform/x.ts\n'
expect_verdict "deleted kb md runs"                      true  pull_request $'D\tknowledge-base/a.md\n'
expect_verdict "renamed kb md runs"                      true  pull_request $'R100\tknowledge-base/a.md\tknowledge-base/b.md\n'
expect_verdict "copied kb md runs"                       true  pull_request $'C\tknowledge-base/a.md\tknowledge-base/b.md\n'
expect_verdict "typechange runs"                         true  pull_request $'T\tknowledge-base/a.md\n'
expect_verdict "unmerged runs"                           true  pull_request $'U\tknowledge-base/a.md\n'
expect_verdict "empty changeset runs"                    true  pull_request ''
expect_verdict "subdir md outside kb runs"               true  pull_request $'M\tplugins/soleur/README.md\n'
expect_verdict "knowledge-base-evil prefix runs"         true  pull_request $'M\tknowledge-base-evil/x.md\n'
expect_verdict "C-quoted path runs"                      true  pull_request $'M\t"knowledge-base/x\\ny.md"\n'
expect_verdict "second row after a compliant first runs" true  pull_request $'M\tknowledge-base/a.md\nM\tscripts/test-all.sh\n'
# A final row with no trailing newline must still be read (the `|| [ -n "$line" ]` limb); dropping it would skip the battery.
expect_verdict "final row without trailing newline runs"  true  pull_request $'M\tknowledge-base/a.md\nM\tscripts/x.sh'
expect_verdict "markdown suffix then more runs"          true  pull_request $'M\tknowledge-base/x.md.sh\n'
expect_verdict "single-slash .md is NOT root-md safe"    true  pull_request $'M\tapps/README.md\n'
expect_verdict "docs/legal md runs (not allowlisted)"    true  pull_request $'M\tdocs/legal/x.md\n'
expect_verdict "bare knowledge-base path runs"           true  pull_request $'M\tknowledge-base\n'
expect_verdict "classifier self-edit runs"               true  pull_request $'M\tscripts/ci-shard-totality-classify.sh\n'
expect_verdict "own suite self-edit runs"                true  pull_request $'M\tplugins/soleur/test/ci-shard-totality-skip.test.sh\n'

echo "── non-PR events always run"
expect_verdict "push runs"                               true  push             $'M\tknowledge-base/a.md\n'
expect_verdict "merge_group runs"                        true  merge_group      $'M\tknowledge-base/a.md\n'
expect_verdict "workflow_dispatch runs"                  true  workflow_dispatch $'M\tknowledge-base/a.md\n'
expect_verdict "enum-failed verdict emits true"          true  --enum-failed    ''

echo "── broken usage exits non-zero"
if bash "$CLASSIFIER" </dev/null >/dev/null 2>&1; then fail "missing event arg exits non-zero"; else pass "missing event arg exits non-zero"; fi
if bash "$CLASSIFIER" bogus_event </dev/null >/dev/null 2>&1; then fail "unknown event exits non-zero"; else pass "unknown event exits non-zero"; fi

echo "── ci.yml wiring (shard-totality-mutations job section)"
section="$(awk '/^  shard-totality-mutations:/{f=1} f && !/^  shard-totality-mutations:/ && /^  [a-zA-Z0-9_-]+:/{exit} f{print}' "$CI_YML")"
in_section() { printf '%s\n' "$section" | grep -cF -e "$2" >/dev/null && pass "$1" || fail "$1 (missing in section: $2)"; }

if printf '%s\n' "$section" | grep -cE '^[[:space:]]+id: detect[[:space:]]*$' >/dev/null; then pass "classify step id: detect (line-anchored)"; else fail "classify step id: detect missing"; fi
in_section "classifier invoked from the workflow"        "scripts/ci-shard-totality-classify.sh"
in_section "base-ref classifier judged, not the PR's"    'git show "origin/${GITHUB_BASE_REF}:scripts/ci-shard-totality-classify.sh"'
in_section "diff range is the PR merge-base"             'git diff --name-status "origin/${GITHUB_BASE_REF}...HEAD"'
in_section "invalid verdict is a red job"                '::error::shard-totality classifier emitted invalid verdict'
in_section "verdict emitted to GITHUB_OUTPUT"            'applicable=$APPLICABLE" >> "$GITHUB_OUTPUT'
in_section "enum-failure fallback is a literal true"     'APPLICABLE=true'
in_section "git stderr is captured, not discarded"       'GIT_ERR'

if grep -qE '2> *(/dev/null|&-)|&>' < <(grep -E 'git (diff|show)' <<<"$section"); then
  fail "a git diff/show in the classify step discards stderr (the e2e enum-failed cause was invisible for that reason)"
else
  pass "no git diff/show line discards stderr"
fi

detect_step="$(printf '%s\n' "$section" | awk '/^      - name: Classify shard-totality applicability/{f=1; print; next} f && /^      - /{exit} f{print}')"
if [ -n "$detect_step" ] && ! printf '%s\n' "$detect_step" | grep -cE '^\s+if:' >/dev/null; then
  pass "classify step carries no if: (verdict always populated)"
else
  fail "classify step is conditional or not found"
fi

battery_step="$(printf '%s\n' "$section" | awk '/^      - name: Guard 1 — shard-totality mutation battery/{f=1; print; next} f && /^      - /{exit} f{print}')"
if grep -qxE "        if: steps\.detect\.outputs\.applicable != 'false'" <<<"$battery_step"; then
  pass "the battery step itself carries the fail-closed gate (!= 'false')"
else
  fail "the battery step lacks its own 'if: steps.detect.outputs.applicable != false' line"
fi
skip_step="$(printf '%s\n' "$section" | awk '/^      - name: Record shard-totality skip verdict/{f=1; print; next} f && /^      - /{exit} f{print}')"
if grep -qxE "        if: steps\.detect\.outputs\.applicable == 'false'" <<<"$skip_step"; then
  pass "the skip-verdict step is gated on == 'false'"
else
  fail "the skip-verdict step lacks its == 'false' gate"
fi

# The classifier's allowlist arms are the security boundary: pin them lexically and by count (fixtures cannot enumerate widenings).
grep -qF 'knowledge-base/*.md) ;;' "$CLASSIFIER" && pass "allowlist arm: knowledge-base/*.md" || fail "allowlist arm knowledge-base/*.md missing/widened"
grep -qF '*.md)' "$CLASSIFIER" && pass "allowlist arm: root *.md" || fail "allowlist arm *.md missing"
path_arms="$(awk '/^  case "\$path" in/,/^  esac/' "$CLASSIFIER" | grep -cE '^ {4}[^ ]' || true)"
if [ "$path_arms" -eq 3 ]; then pass "path-case arm count is exactly 3"; else fail "path-case arm count is $path_arms, want 3 (allowlist widened or catch-all lost?)"; fi

classify_line="$(printf '%s\n' "$section" | grep -n 'ci-shard-totality-classify' | head -1 | cut -d: -f1)"
battery_line="$(printf '%s\n' "$section" | grep -n 'scripts-shard-totality-mutations.sh --rows' | head -1 | cut -d: -f1)"
if [ -n "$classify_line" ] && [ -n "$battery_line" ] && [ "$classify_line" -lt "$battery_line" ]; then
  pass "classify step precedes the battery step"
else
  fail "ordering (classify=${classify_line:-none} battery=${battery_line:-none})"
fi

# EXECUTED evaluation of the checkout ternary. A text pin on the spelling certified `&& 0 || 1` for weeks while
# the expression evaluated to 1 (0 is falsy in an Actions expression, so `A && 0 || 1` is always 1) and e2e's
# classify step ran on a depth-1 clone. Model the evaluation rather than the spelling: an `A && B || C` whose B is
# falsy (0, false, '', null) collapses to C, so any such shape is forbidden anywhere in a workflow.
falsy_hits="$(grep -rnE '&&[[:space:]]*(0|false|null|'"''"'|"")[[:space:]]*\|\|' "$REPO_ROOT/.github/workflows" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ -z "$falsy_hits" ]; then
  pass "no falsy-middle ternary (A && 0 || C) in any workflow"
else
  fail "falsy-middle ternary found (always evaluates to the right operand): $falsy_hits"
fi
e2e_section="$(awk '/^  e2e:/{f=1} f && !/^  e2e:/ && /^  [a-zA-Z0-9_-]+:/{exit} f{print}' "$CI_YML")"
if grep -qF "fetch-depth: \${{ github.event_name == 'pull_request' && '0' || '1' }}" <<<"$e2e_section"; then
  pass "e2e checkout depth ternary yields the truthy string '0' on pull_request"
else
  fail "e2e fetch-depth ternary is not the quoted-'0' form"
fi

total=$((PASS + FAIL))
if [ "$total" -lt 52 ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, want >=52\n' "$total" >&2
  exit 1
fi
echo
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
