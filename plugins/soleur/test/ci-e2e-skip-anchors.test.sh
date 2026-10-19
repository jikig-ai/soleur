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
#       the REAL artifact over fixture `git diff --raw` rows on stdin,
#       never a re-implemented mirror;
#   (b) grep-anchored wiring assertions on ci.yml itself — the classify step
#       (`id: detect`) precedes the heavy steps inside the `e2e` job, the
#       checkout is `fetch-depth: 0` (shallow clone = unresolvable diff =
#       must emit true, which is the fail-closed direction), every heavy step
#       carries `if: steps.detect.outputs.applicable == 'true'`, and the
#       skip-verdict step exists. A dropped wiring line reds even when the
#       classifier is correct.
#
# Stdin contract: `git diff --raw` rows — `:OLDMODE NEWMODE OLDSHA NEWSHA STATUS<TAB>path`
# (renames and copies carry a second TAB-separated path and fail the grammar). The skip
# is mode-aware (#10416): status A needs old mode 000000 and new mode 100644, status M
# needs 100644 on both sides, so a symlink, gitlink or exec-bit `.md` runs the job. Any
# other status (deletions, renames, copies, type changes, unmerged) and any row that is
# not a well-formed raw row (legacy name-status, a bare path, uppercase hex) emits
# `true`: an unresolvable or mutating changeset is indistinguishable from unsafe.
# `--enum-failed` as argv[1] is the enumeration-failure verdict path the
# workflow step falls back to when `git diff` itself fails.
#
# SELF-EVALUATION (review, #8472): on `pull_request` the workflow judges the
# diff by the BASE ref's copy of the classifier
# (`git show "origin/${GITHUB_BASE_REF}:scripts/ci-e2e-classify.sh"`), never
# the PR's own — a PR cannot weaken the gate it is judged by, and a PR that
# widens the allowlist is judged by the OLD rules. This suite still executes
# the worktree artifact so the shipped semantics are what gets pinned.
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

# raw_row <status> <old-mode> <new-mode> <path> — one `git diff --raw` row (default abbreviation: 7-hex object names).
# A rename/copy passes a path holding a TAB. Rows print with a trailing newline; join several as "$(mrow a; mrow b)".
raw_row() { printf ':%s %s 1111111 2222222 %s\t%s\n' "$2" "$3" "$1" "$4"; }
mrow() { raw_row M 100644 100644 "$1"; }
arow() { raw_row A 000000 100644 "$1"; }

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
expect_verdict "app-affecting path runs e2e"            true  pull_request "$(mrow apps/web-platform/x.ts)"
expect_verdict "pure kb + root-md diff skips"           false pull_request "$(mrow knowledge-base/project/specs/x.md; mrow README.md)"
expect_verdict "docs/legal is NOT safe (pinned SHAs)"   true  pull_request "$(mrow docs/legal/foo.md)"
expect_verdict "mixed allowlist + app path runs"        true  pull_request "$(mrow knowledge-base/a.md; mrow apps/web-platform/x.ts)"
expect_verdict "deleted-file-only diff runs"            true  pull_request "$(raw_row D 100644 000000 knowledge-base/a.md)"
expect_verdict "typechange is NOT safe (kind mutates)"  true  pull_request "$(raw_row T 100644 120000 knowledge-base/a.md)"
expect_verdict "renamed file runs"                      true  pull_request "$(raw_row R100 100644 100644 $'knowledge-base/a.md\tknowledge-base/b.md')"
expect_verdict "added allowlisted file skips"           false pull_request "$(arow knowledge-base/a.md)"
expect_verdict "empty changeset runs"                   true  pull_request ''
expect_verdict "subdir .md is NOT root-md safe"         true  pull_request "$(mrow plugins/soleur/README.md)"
expect_verdict "workflow edit itself runs"              true  pull_request "$(mrow .github/workflows/ci.yml)"
expect_verdict "bare path (no status column) fails closed" true pull_request $'knowledge-base/a.md\nREADME.md\n'
expect_verdict "unmerged status runs"                   true  pull_request "$(raw_row U 000000 000000 knowledge-base/a.md)"
# Single-slash markdown outside the tree: the inner root-md guard must treat ANY slash as non-root (a `*/*/*` edit would not).
expect_verdict "single-slash .md is NOT root-md safe"    true  pull_request "$(mrow apps/README.md)"

echo "── Guard 1: hostile-input + self-evaluation axes"
# Copy status is the same unsafe class as rename: a copied-in app file must run.
expect_verdict "copy status runs"                       true  pull_request "$(raw_row C100 100644 100644 $'knowledge-base/a.md\tknowledge-base/b.md')"
# Prefix without the literal slash is NOT knowledge-base/**.
expect_verdict "knowledge-base-evil is NOT allowlisted" true  pull_request "$(mrow knowledge-base-evil/x.md)"
# A bare `knowledge-base` file (no trailing slash) is not under the tree.
expect_verdict "bare knowledge-base path runs"          true  pull_request "$(mrow knowledge-base)"
# git C-quotes control characters in diff output; the quoted row must
# fail every allowlist arm (smuggled newline/tab payloads are unreachable).
expect_verdict "C-quoted path runs"                     true  pull_request "$(mrow '"knowledge-base/x\ny.ts"')"
# The row-grammar `^`/`$` anchors: a status-M row with a second tab field, and a row with junk before the colon, must not
# be read as a well-formed row by prefix/suffix (a rename row alone cannot pin them: the STATUS guard masks it).
expect_verdict "extra tab field after the path runs"    true  pull_request "$(raw_row M 100644 100644 $'README.md\tx.ts')"
expect_verdict "junk before the row colon runs"         true  pull_request "junk$(mrow README.md)"
# Editing the gate machinery itself always runs the gate — the rows below make
# that an enforced invariant, not an accident of the current allowlist.
expect_verdict "classifier edit runs e2e"               true  pull_request "$(mrow scripts/ci-e2e-classify.sh)"
expect_verdict "this guard's own edit runs e2e"         true  pull_request "$(mrow plugins/soleur/test/ci-e2e-skip-anchors.test.sh)"
expect_verdict "sweeper edit runs e2e"                  true  pull_request "$(mrow scripts/sweep-followthroughs.sh)"
expect_verdict "soak-probe edit runs e2e"               true  pull_request "$(mrow scripts/followthroughs/actions-queue-tail-8450.sh)"

echo "── Guard 1: file-mode axis (#10416) — a symlink, gitlink or exec-bit .md is not markdown"
expect_verdict "added symlinked .md runs"               true  pull_request "$(raw_row A 000000 120000 knowledge-base/x.md)"
expect_verdict "added executable .md runs"              true  pull_request "$(raw_row A 000000 100755 knowledge-base/x.md)"
expect_verdict "added gitlink runs"                     true  pull_request "$(raw_row A 000000 160000 knowledge-base/x.md)"
expect_verdict "exec-bit flip on root .md runs"         true  pull_request "$(raw_row M 100644 100755 README.md)"
expect_verdict "exec-bit removal on kb .md runs"        true  pull_request "$(raw_row M 100755 100644 knowledge-base/x.md)"
expect_verdict "modify of an existing symlink runs"     true  pull_request "$(raw_row M 120000 120000 knowledge-base/x.md)"
expect_verdict "A row with a non-null old mode runs"    true  pull_request "$(raw_row A 100644 100644 knowledge-base/x.md)"
expect_verdict "M99 (unknown status) runs"              true  pull_request "$(raw_row M99 100644 100644 knowledge-base/x.md)"
expect_verdict "compliant first row, symlink second, runs" true pull_request "$(arow knowledge-base/a.md; raw_row A 000000 120000 knowledge-base/b.md)"
expect_verdict "symlink first row, compliant second, runs" true pull_request "$(raw_row A 000000 120000 knowledge-base/b.md; arow knowledge-base/a.md)"
expect_verdict "legacy name-status row fails closed"    true  pull_request $'M\tknowledge-base/a.md\n'
expect_verdict "uppercase-hex raw row fails closed"     true  pull_request $':100644 100644 ABCDEF1 2222222 M\tknowledge-base/a.md\n'
expect_verdict "raw row with a space for the tab fails closed" true pull_request $':100644 100644 1111111 2222222 M knowledge-base/a.md\n'
expect_verdict "raw row with an empty path fails closed" true  pull_request $':100644 100644 1111111 2222222 M\t\n'
expect_verdict "plain 100644 kb .md added+modified skips" false pull_request "$(arow knowledge-base/a/b/c.md; mrow README.md)"
expect_verdict "path with spaces still skips"           false pull_request "$(arow 'knowledge-base/with space/a b.md')"
expect_verdict "40-hex (--no-abbrev) raw row skips"     false pull_request "$(printf ':100644 100644 %040d %040d M\tknowledge-base/a.md\n' 1 2)"

echo "── Guard 1: non-PR events always run"
expect_verdict "push event runs"                        true  push          "$(mrow knowledge-base/a.md)"
expect_verdict "merge_group event runs"                 true  merge_group   "$(mrow knowledge-base/a.md)"
expect_verdict "workflow_dispatch runs"                 true  workflow_dispatch "$(mrow knowledge-base/a.md)"

echo "── Guard 1: failure polarity"
# Enumeration failure is a distinct argv verdict path: emits true, exits 0.
expect_verdict "enum-failure verdict emits true"        true  --enum-failed ''
expect_rc_nonzero "missing event arg exits non-zero"
expect_rc_nonzero "unknown event arg exits non-zero"    bogus_event

echo "── Guard 1: allowlist arms pinned lexically"
# The arm SET is the security boundary: fixtures pin the deny side
# (docs/**, subdir .md, .github/**) but cannot enumerate every future
# widening. Pin the two allowlist patterns verbatim so `knowledge-base/*`
# -> `knowledge-base*` or a new `*.txt` arm cannot ship silently.
grep -qF 'knowledge-base/*)' "$CLASSIFIER" \
  && { PASS=$((PASS + 1)); echo "ok   allowlist arm: knowledge-base/*"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL allowlist arm knowledge-base/* missing/widened"; }
grep -qF '*.md)' "$CLASSIFIER" \
  && { PASS=$((PASS + 1)); echo "ok   allowlist arm: root *.md"; } \
  || { FAIL=$((FAIL + 1)); echo "FAIL allowlist arm *.md missing/widened"; }
# The path case has exactly 3 top-level arms (knowledge-base/*, *.md, and the
# `*) emit true` catch-all). A NEW allowlist arm is the widening shape fixtures
# cannot enumerate; deleting the catch-all turns unlisted paths into emit-false.
path_arms="$(awk '/^  case "\$path" in/,/^  esac/' "$CLASSIFIER" | grep -cE '^ {4}[^ ]' || true)"
if [ "$path_arms" -eq 3 ]; then
  PASS=$((PASS + 1)); echo "ok   path-case arm count is exactly 3"
else
  FAIL=$((FAIL + 1)); echo "FAIL path-case arm count is $path_arms, want 3 (allowlist widened or catch-all lost?)"
fi

echo "── Guard 1: ci.yml wiring anchors"
# Section-scoped, not whole-file: needles like `fetch-depth: 0` appear a dozen
# times outside the e2e job, so a whole-file grep is pre-satisfied and pins
# nothing (the anchor would stay green if the e2e copy were deleted).
# The terminator tolerates digits/underscores — a future `e2e_v2:`/`deploy2:`
# job key must still end the section.
e2e_section="$(awk '/^  e2e:/{f=1} f && !/^  e2e:/ && /^  [a-zA-Z0-9_-]+:/{exit} f{print}' "$CI_YML")"

anchor_in_e2e() { # <desc> <fixed-string> — must appear INSIDE the e2e job.
  local desc="$1" needle="$2"
  if printf '%s\n' "$e2e_section" | grep -cF >/dev/null -e "$needle"; then
    PASS=$((PASS + 1)); echo "ok   $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc (missing in e2e job section: $needle)"
  fi
}

# Boundary-anchored, not substring: `id: detector` must NOT satisfy this —
# `steps.detect.outputs.applicable` would resolve empty and e2e green-skips
# on every PR with every assertion green (demonstrated in review).
if printf '%s\n' "$e2e_section" | grep -cE >/dev/null '^[[:space:]]+id: detect[[:space:]]*$'; then
  PASS=$((PASS + 1)); echo "ok   e2e classify step id: detect (line-anchored)"
else
  FAIL=$((FAIL + 1)); echo "FAIL e2e classify step id: detect missing/renamed"
fi
anchor_in_e2e "classifier invoked from workflow"        "scripts/ci-e2e-classify.sh"
# The classifier the PR is judged by is the BASE ref's copy — losing this line
# re-opens the self-evaluation hole (a PR shipping `emit false` for itself).
anchor_in_e2e "base-ref classifier judged, not the PR's" 'git show "origin/${GITHUB_BASE_REF}:scripts/ci-e2e-classify.sh"'
# The `0` is a quoted STRING: `A && 0 || 1` evaluates to 1 in an Actions expression (0 is falsy), which made this
# checkout depth-1 on every PR and sent every PR down the enum-failed fallback (#9729). The unquoted spelling this
# row used to pin certified the bug; plugins/soleur/test/ci-shard-totality-skip.test.sh sweeps every workflow for it.
anchor_in_e2e "full-history checkout for PR diff"       "github.event_name == 'pull_request' && '0' || '1'"
anchor_absent "no falsy-zero checkout ternary (&& 0 ||)" "&& 0 || 1 }}"
# git's stderr is kept so a fallback names its cause; a line that sends it to /dev/null re-opens the invisible-cause hole.
if grep -qE '2> *(/dev/null|&-)|&>' < <(grep -E 'git (diff|show)' <<<"$e2e_section"); then
  FAIL=$((FAIL + 1)); echo "FAIL a git diff/show in the e2e classify step discards stderr"
else
  PASS=$((PASS + 1)); echo "ok   no git diff/show line in the e2e classify step discards stderr"
fi
anchor_in_e2e "classify fallback prints the git stderr"  'git stderr: ['

# The diff range is load-bearing: a narrowed spec (HEAD~1, fixed base) hides
# app changes in earlier commits of a multi-commit PR.
anchor_in_e2e "diff range is the PR merge-base, as raw rows" 'git diff --raw --no-color --no-ext-diff --ignore-submodules=none "origin/${GITHUB_BASE_REF}...HEAD" 2>>"$GIT_ERR")"'
# The verdict-validation case converts a malformed verdict into a red job —
# without it a classifier emitting garbage yields `applicable=`, every
# `== 'true'` gate AND the `== 'false'` verdict step are false, and the job
# greens having executed nothing.
anchor_in_e2e "invalid verdict is a red job"            '::error::classifier emitted invalid verdict'
anchor_in_e2e "verdict whitelisted true|false"          'case "$APPLICABLE" in'
# The output emit is the single most dangerous line to lose: without it every
# `== 'true'` gate is false and e2e green-skips on every PR.
anchor_in_e2e "verdict emitted to GITHUB_OUTPUT"        'applicable=$APPLICABLE" >> "$GITHUB_OUTPUT'
anchor_in_e2e "skip verdict surfaced"                   "e2e skipped"
# The fallback is a LITERAL true: running the PR's own checked-out classifier with --enum-failed would let a PR that edits that
# script turn the fallback into `false` (review of #10098).
anchor_in_e2e "enum-failure fallback is a literal true"  'APPLICABLE=true'
anchor_absent "no trigger-level paths: on e2e/CI"       "paths-ignore"

# A job-level `if:`/`needs:` on `e2e` makes the required check conclude
# `skipped` → posts GREEN — the #5585 shape ADR-032:811 records as explicitly
# rejected. And an `if:` on the classify STEP is worse: `applicable` resolves
# empty, every gate and the verdict step evaluate false, job greens doing
# nothing. Neither is pinned by presence anchors — assert absence.
# ONE carve-out (ADR-276 S2, #9512): the push-dedupe elision. `e2e` may carry exactly `needs: [push-dedupe]` and
# exactly the canonical condition below, nothing else. That is not the #5585 shape: push-dedupe cannot needs-skip
# `e2e` by failing (the condition opens with the status function !cancelled(), so a failed or skipped need still runs
# the job), it is skipped off the push event, and the elision needs a green identical-SHA merge_group run (whether a
# required context is evaluated on a direct push to main is not settled from the repo, so the defense rests on the
# proof, not on that premise). scripts/ci-push-dedupe.test.sh evaluates the condition over the event x output truth table.
E2E_ELIDE_NEEDS="needs: [push-dedupe]"
E2E_ELIDE_IF="if: \${{ !cancelled() && (github.event_name == 'merge_group' || github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}"
if printf '%s\n' "$e2e_section" | awk -v en="    $E2E_ELIDE_NEEDS" -v ei="    $E2E_ELIDE_IF" '/^    steps:/{exit} /^    (if|needs):/{ if ($0 != en && $0 != ei) bad=1 } END{exit bad}'; then
  PASS=$((PASS + 1)); echo "ok   e2e job carries no job-level if:/needs: other than the push-dedupe elision pair"
else
  FAIL=$((FAIL + 1)); echo "FAIL e2e job has a job-level if:/needs: (skipped required check posts green)"
fi
detect_step="$(printf '%s\n' "$e2e_section" | awk '
  /^      - name: Classify e2e applicability/{f=1}
  f && /^      - / && !/Classify e2e applicability/{exit}
  f{print}')"
if [ -n "$detect_step" ] && ! printf '%s\n' "$detect_step" | grep -cE >/dev/null '^\s+if:'; then
  PASS=$((PASS + 1)); echo "ok   classify step carries no if: (verdict always populated)"
else
  FAIL=$((FAIL + 1)); echo "FAIL classify step is conditional or not found (empty verdict green-skips the job)"
fi

# Every heavy step carries the gate — count, not presence: dropping the `if:`
# from a subset of steps (e.g. leaving `Run E2E tests` ungated) must red.
gate_count="$(printf '%s\n' "$e2e_section" | grep -c "steps.detect.outputs.applicable == 'true'")"
if [ "$gate_count" -eq 4 ]; then
  PASS=$((PASS + 1)); echo "ok   all 4 heavy/upload steps gated on applicable"
else
  FAIL=$((FAIL + 1)); echo "FAIL applicable gate count is $gate_count, want 4"
fi
# Complement: a heavy step added WITHOUT an `if:` keeps gate_count at 4 while
# running on every PR. Exactly one `run:` step may carry no `if:` at all — the
# classify step itself. (The skip-verdict step's `if:` is on 'false'; deleting
# it also reds here.)
ungated_runs="$(printf '%s\n' "$e2e_section" | awk '
  /^      - / { if (seen && run && !gate) n++; seen=1; run=0; gate=0; next }
  seen && /^        run:/ { run=1 }
  seen && /^        if:/ { gate=1 }
  END { if (seen && run && !gate) n++; print n+0 }')"
if [ "$ungated_runs" -eq 1 ]; then
  PASS=$((PASS + 1)); echo "ok   only the classify step runs unconditioned"
else
  FAIL=$((FAIL + 1)); echo "FAIL $ungated_runs unconditional run: steps in e2e (want 1: classify only)"
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

# Anti-vacuity floor: deleting every assertion invocation must not exit 0
# ("0 passed, 0 failed" is not a green suite). Reports directly and exits
# (ADR-193): a floor routed through fail()/FAIL++ is disarmed by the same
# neutered machinery it exists to catch.
total=$((PASS + FAIL))
if [ "$total" -lt 70 ]; then
  echo "[FATAL] assertion floor: only $total assertions ran, want >=70" >&2
  exit 1
fi

echo
echo "Guard 1: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
