#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 — the e2e skip gate cannot certify an app-affecting diff (#8450).
#
# PROPERTY. `e2e` in .github/workflows/ci.yml skips its heavy steps only when
# scripts/ci-e2e-classify.sh emits `false`, which it does only on
# `pull_request` with a non-empty changed-file list consisting SOLELY of
# allowlisted paths (`knowledge-base/**`, root-level `*.md`). A skipped
# required check still posts GREEN (the #5585 skipped-to-green-is-a-certification
# rule), so this guard is the security contract: any path outside the
# allowlist — including `docs/**`, which is only `docs/legal/**` and is
# app-coupled via the pinned SHA-256s in
# apps/web-platform/lib/legal/legal-doc-shas.ts — MUST emit `true`.
#
# ASSEMBLY. Two chokepoints, both tested here:
#   (a) the shipped classifier scripts/ci-e2e-classify.sh — the test executes
#       the REAL artifact over fixture `git diff --name-status` rows on stdin,
#       never a re-implemented mirror;
#   (b) grep-anchored wiring assertions on ci.yml itself — the classify step
#       (`id: detect`) precedes the heavy steps inside the `e2e` job, the
#       checkout is `fetch-depth: 0` (shallow clone = unresolvable diff =
#       must emit true, which is the fail-closed direction), every heavy step
#       carries `if: steps.detect.outputs.applicable == 'true'`, and the
#       skip-verdict step exists. A dropped wiring line reds even when the
#       classifier is correct.
#
# Stdin contract (pinned by the plan): `git diff --name-status` rows —
# `STATUS<TAB>path` (renames carry a second TAB-separated path). A bare path
# with no status column is treated as modified. Any status other than M/A/T
# (deletions, renames, copies, type changes, unmerged) emits `true`: an
# unresolvable or mutating changeset is indistinguishable from unsafe.
# `--enum-failed` as argv[1] is the enumeration-failure verdict path the
# workflow step falls back to when `git diff` itself fails.
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`),
# `test-scripts` shard. No network, no git fixture repos — stdin fixtures only.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

CLASSIFIER="$REPO_ROOT/scripts/ci-e2e-classify.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

PASS=0
FAIL=0

# expect_verdict <desc> <expected true|false> <event-arg> <stdin-rows>
expect_verdict() {
  local desc="$1" expected="$2" event="$3" rows="$4"
  local actual rc
  actual="$(printf '%s' "$rows" | bash "$CLASSIFIER" "$event" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "ok   $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc (want=$expected got='${actual}' rc=$rc)"
  fi
}

# expect_rc_nonzero <desc> <argv...> — genuinely broken usage must exit non-zero
# so a broken classifier reds the required job instead of fabricating a skip.
expect_rc_nonzero() {
  local desc="$1"; shift
  if bash "$CLASSIFIER" "$@" </dev/null >/dev/null 2>&1; then
    FAIL=$((FAIL + 1)); echo "FAIL $desc (expected non-zero exit)"
  else
    PASS=$((PASS + 1)); echo "ok   $desc"
  fi
}

# anchor <desc> <fixed-string> — wiring grep on ci.yml (inside the e2e job).
anchor() {
  local desc="$1" needle="$2"
  if grep -qF -e "$needle" "$CI_YML"; then
    PASS=$((PASS + 1)); echo "ok   $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc (missing in ci.yml: $needle)"
  fi
}

# anchor_absent <desc> <fixed-string> — a FORBIDDEN string must not appear in
# the e2e job's gating surface.
anchor_absent() {
  local desc="$1" needle="$2"
  if grep -qF -e "$needle" "$CI_YML"; then
    FAIL=$((FAIL + 1)); echo "FAIL $desc (forbidden string present: $needle)"
  else
    PASS=$((PASS + 1)); echo "ok   $desc"
  fi
}

echo "── Guard 1: classifier artifact"
if [ -x "$CLASSIFIER" ]; then
  PASS=$((PASS + 1)); echo "ok   classifier exists and is executable"
else
  FAIL=$((FAIL + 1)); echo "FAIL classifier missing/not executable: $CLASSIFIER"
  echo; echo "Guard 1: $PASS passed, $FAIL failed"
  exit 1
fi

echo "── Guard 1: decision matrix (pull_request)"
expect_verdict "app-affecting path runs e2e"            true  pull_request $'M\tapps/web-platform/x.ts\n'
expect_verdict "pure kb + root-md diff skips"           false pull_request $'M\tknowledge-base/project/specs/x.md\nM\tREADME.md\n'
expect_verdict "docs/legal is NOT safe (pinned SHAs)"   true  pull_request $'M\tdocs/legal/foo.md\n'
expect_verdict "mixed allowlist + app path runs"        true  pull_request $'M\tknowledge-base/a.md\nM\tapps/web-platform/x.ts\n'
expect_verdict "deleted-file-only diff runs"            true  pull_request $'D\tknowledge-base/a.md\n'
expect_verdict "typechange is NOT safe (kind mutates)"  true  pull_request $'T\tknowledge-base/a.md\n'
expect_verdict "renamed file runs"                      true  pull_request $'R100\tknowledge-base/a.md\tknowledge-base/b.md\n'
expect_verdict "added allowlisted file skips"           false pull_request $'A\tknowledge-base/a.md\n'
expect_verdict "empty changeset runs"                   true  pull_request ''
expect_verdict "subdir .md is NOT root-md safe"         true  pull_request $'M\tplugins/soleur/README.md\n'
expect_verdict "workflow edit itself runs"              true  pull_request $'M\t.github/workflows/ci.yml\n'
expect_verdict "bare path (no status) treated as M"     false pull_request $'knowledge-base/a.md\nREADME.md\n'
expect_verdict "unmerged status runs"                   true  pull_request $'U\tknowledge-base/a.md\n'

echo "── Guard 1: non-PR events always run"
expect_verdict "push event runs"                        true  push          $'M\tknowledge-base/a.md\n'
expect_verdict "merge_group event runs"                 true  merge_group   $'M\tknowledge-base/a.md\n'
expect_verdict "workflow_dispatch runs"                 true  workflow_dispatch $'M\tknowledge-base/a.md\n'

echo "── Guard 1: failure polarity"
# Enumeration failure is a distinct argv verdict path: emits true, exits 0.
expect_verdict "enum-failure verdict emits true"        true  --enum-failed ''
expect_rc_nonzero "missing event arg exits non-zero"
expect_rc_nonzero "unknown event arg exits non-zero"    bogus_event

echo "── Guard 1: ci.yml wiring anchors"
# Section-scoped, not whole-file: needles like `fetch-depth: 0` appear a dozen
# times outside the e2e job, so a whole-file grep is pre-satisfied and pins
# nothing (the anchor would stay green if the e2e copy were deleted).
e2e_section="$(awk '/^  e2e:/{f=1} f{print} /^  [a-z-]+:/ && f && !/^  e2e:/{exit}' "$CI_YML")"

anchor_in_e2e() { # <desc> <fixed-string> — must appear INSIDE the e2e job.
  local desc="$1" needle="$2"
  if printf '%s\n' "$e2e_section" | grep -qF -e "$needle"; then
    PASS=$((PASS + 1)); echo "ok   $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc (missing in e2e job section: $needle)"
  fi
}

anchor_in_e2e "e2e classify step id: detect"            "id: detect"
anchor_in_e2e "classifier invoked from workflow"        "scripts/ci-e2e-classify.sh"
anchor_in_e2e "full-history checkout for PR diff"       "github.event_name == 'pull_request' && 0 || 1"
# The diff range is load-bearing: a narrowed spec (HEAD~1, fixed base) hides
# app changes in earlier commits of a multi-commit PR.
anchor_in_e2e "diff range is the PR merge-base"         'git diff --name-status "origin/${GITHUB_BASE_REF}...HEAD"'
# The output emit is the single most dangerous line to lose: without it every
# `== 'true'` gate is false and e2e green-skips on every PR.
anchor_in_e2e "verdict emitted to GITHUB_OUTPUT"        'applicable=$APPLICABLE" >> "$GITHUB_OUTPUT'
anchor_in_e2e "skip verdict surfaced"                   "e2e skipped"
anchor_in_e2e "enum-failure fallback wired"             "--enum-failed"
anchor_absent "no trigger-level paths: on e2e/CI"       "paths-ignore"

# Every heavy step carries the gate — count, not presence: dropping the `if:`
# from a subset of steps (e.g. leaving `Run E2E tests` ungated) must red.
gate_count="$(printf '%s\n' "$e2e_section" | grep -c "steps.detect.outputs.applicable == 'true'")"
if [ "$gate_count" -eq 4 ]; then
  PASS=$((PASS + 1)); echo "ok   all 4 heavy/upload steps gated on applicable"
else
  FAIL=$((FAIL + 1)); echo "FAIL applicable gate count is $gate_count, want 4"
fi

# The classify step must precede the heavy steps. Positional check: the
# classifier invocation line must appear before the first `npm ci` inside the
# e2e job section.
detect_line="$(printf '%s\n' "$e2e_section" | grep -n 'ci-e2e-classify' | head -1 | cut -d: -f1)"
first_npm="$(printf '%s\n' "$e2e_section" | grep -n 'npm ci' | head -1 | cut -d: -f1)"
if [ -n "$detect_line" ] && [ -n "$first_npm" ] && [ "$detect_line" -lt "$first_npm" ]; then
  PASS=$((PASS + 1)); echo "ok   classify step precedes heavy steps"
else
  FAIL=$((FAIL + 1)); echo "FAIL classify step ordering (detect_line=${detect_line:-none} npm_line=${first_npm:-none})"
fi

echo
echo "Guard 1: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
