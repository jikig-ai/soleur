#!/usr/bin/env bash
# Guard 1 mutation battery for scripts/plugin-delivery-canary.sh (#7490).
#
# The canary answers ONE question: does a FRESH install of the published plugin
# materialise the complete, correct, CURRENT content of `plugins/soleur`? The
# historical defect delivered 64 skill directories where 96 were expected while
# every metadata field read correct, so a false GREEN is the failure mode this
# battery exists to prevent — every row below is a shape that a plausible
# implementation reports as green.
#
# THE BATTERY DRIVES THE REAL SCRIPT. Every row invokes
# scripts/plugin-delivery-canary.sh as a subprocess through its documented
# `CANARY_*` seam, pointed at a synthesized fixture tree, with no network and no
# credentials. Nothing below re-implements the canary's logic in a heredoc: a
# fixture that re-declares the good idiom only asserts that a known-good snippet
# is known-good, and would stay green through any mutation of the script.
#
# TMPDIR default mirrors scripts/test-all.sh: a DIRECT invocation of this suite
# (the inner loop while editing the canary) would otherwise inherit the bare
# /tmp tmpfs, and a full-tmpfs sandbox turns setup failures into confident wrong
# verdicts rather than missing ones.
# `canary_run $(seam ...)` at every call site below is intentionally UNQUOTED:
# `seam` emits one KEY=VAL per line and they must word-split into separate `env`
# operands. Quoting would pass the whole block as ONE argument, so every fixture
# variable would be unset and each case would silently exercise the NETWORK path
# instead of the fixture — a suite that still passes while testing nothing it
# claims to. Declared at file scope because SC2046 fires at the call sites, not
# at seam's definition, so a directive above the function covers none of them.
# shellcheck disable=SC2046

export TMPDIR="${TMPDIR:-/var/tmp}"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY="$REPO_ROOT/scripts/plugin-delivery-canary.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/scheduled-marketplace-drift.yml"

# Two internally consistent commits. Neither is real: the fixtures never touch
# the network, so a real sha would only invite a reader to believe one was
# fetched (cq-test-fixtures-synthesized-only).
SHA_CURRENT="1111111111111111111111111111111111111111"
SHA_OLD="2222222222222222222222222222222222222222"
SHA_MOVED="3333333333333333333333333333333333333333"

passes=0
fails=0
cases=0

pass() { passes=$((passes + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '[FAIL] %s\n' "$1"; }

[[ -x "$CANARY" ]] || { echo "FATAL: $CANARY is missing or not executable" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Fixture builder. Layout:
#   <root>/ref   the reference tree — what the repo "serves" at the pinned commit
#   <root>/del   the delivered tree — what the install "materialised"
#
# FOUR members, deliberately. Row 3 needs a SECOND file in LC_ALL=C sort order
# whose corruption is only visible to a loop that does not stop at the first
# member, and a two-file fixture makes "second" and "last" the same position.
# Sorted order is: a/one.md, a/two.md, b/three.sh, top.json
# ---------------------------------------------------------------------------
FIXTURE_FILES=(a/one.md a/two.md b/three.sh top.json)

# ONE owning trap for every fixture this suite allocates (ADR-129). Registering
# inside new_fixture would not work: it is called in a command substitution, so
# an array append there happens in a SUBSHELL and is discarded — the same
# subshell-loses-state shape that makes `x=$(fn)` drop everything but stdout.
# Allocating a single parent up front and nesting each fixture under it gives
# the trap one thing to own, and the per-case `rm -rf` calls below still work.
SUITE_TMP="$(mktemp -d "${TMPDIR}/delivery-canary-suite.XXXXXXXX")" || {
  echo "FATAL: mktemp failed — cannot build the suite sandbox" >&2
  exit 2
}
cleanup_suite() {
  if [[ -n "${SUITE_TMP:-}" && -d "$SUITE_TMP" ]]; then rm -rf "$SUITE_TMP" || true; fi
  return 0
}
trap cleanup_suite EXIT

new_fixture() {
  local root f d
  root="$(mktemp -d "${SUITE_TMP}/delivery-canary-test.XXXXXXXX")" || {
    echo "FATAL: mktemp failed — cannot build fixture sandbox" >&2
    exit 2
  }
  for f in "${FIXTURE_FILES[@]}"; do
    d="$(dirname "$f")"
    mkdir -p "$root/ref/$d" "$root/del/$d" || {
      echo "FATAL: mkdir failed for $f under $root" >&2; exit 2; }
    printf 'the tracked content of %s\n' "$f" > "$root/ref/$f" || {
      echo "FATAL: write failed for $root/ref/$f" >&2; exit 2; }
    cp -- "$root/ref/$f" "$root/del/$f" || {
      echo "FATAL: cp failed for $f" >&2; exit 2; }
  done
  printf '%s' "$root"
}

# ---------------------------------------------------------------------------
# Invocation helpers. `canary_run` merges stderr so the conjunct breakdown and
# the verdict are assertable; `canary_stdout` keeps them apart so the STDOUT
# CONTRACT the workflow parses can be asserted on its own.
# ---------------------------------------------------------------------------
OUT=""
RC=0

canary_run() { # <KEY=VAL...>
  set +e
  OUT="$(env "$@" bash "$CANARY" 2>&1)"
  RC=$?
  set -e
}

# Runs the canary with its CWD inside a given directory. materialize_reference
# derives the repository root from the PROCESS CWD (`git rev-parse --show-toplevel`),
# so the git-archive transport cannot be exercised through the env seam alone. The
# subshell keeps the cd from leaking into the rest of the suite.
canary_run_in() { # <dir> <KEY=VAL...>
  local dir="$1"; shift
  set +e
  OUT="$( cd "$dir" && env "$@" bash "$CANARY" 2>&1 )"
  RC=$?
  set -e
}

canary_stdout() { # <KEY=VAL...>
  set +e
  OUT="$(env "$@" bash "$CANARY" 2>/dev/null)"
  RC=$?
  set -e
}

# Standard seam for a fixture-driven run. `CANARY_CLI` is pointed at a path that
# cannot exist so that any code path which falls through to a real install fails
# loudly here rather than reaching for the network from a test.
seam() { # <root> <delivered-sha> <main-head> [recheck]
  printf '%s\n' \
    "CANARY_DELIVERED_ROOT=$1/del" \
    "CANARY_REFERENCE_DIR=$1/ref" \
    "CANARY_DELIVERED_SHA=$2" \
    "CANARY_MAIN_HEAD=$3" \
    "CANARY_MAIN_HEAD_RECHECK=${4:-}" \
    "CANARY_CLI=/nonexistent/claude-binary"
}

# assert_eq <name> <expected> <actual>
assert_eq() {
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# assert_has <name> <pattern> — pattern is an ERE matched against $OUT.
# NEVER `producer | grep -q PATTERN`: under `set -o pipefail` an early match
# closes the pipe, the producer takes SIGPIPE 141, and the pipeline reports
# failure even though grep MATCHED. A herestring has no producer to kill.
assert_has() {
  cases=$((cases + 1))
  if grep -qE -- "$2" <<<"$OUT"; then pass "$1"; else fail "$1 (no line matched /$2/)"; fi
}

assert_lacks() {
  cases=$((cases + 1))
  if grep -qE -- "$2" <<<"$OUT"; then fail "$1 (a line matched /$2/ and none should)"; else pass "$1"; fi
}

conjuncts() { sed -n 's/^canary-conjuncts| //p' <<<"$OUT"; }
counts()    { sed -n 's/^canary-counts| //p' <<<"$OUT"; }

# ---------------------------------------------------------------------------
# POSITIVE CONTROL. Without it every RED below could be red for a reason that
# has nothing to do with the mutation it is supposed to detect.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "control: an intact delivery exits 0"           "0" "$RC"
assert_eq   "control: all three conjuncts are green"        "completeness=green integrity=green freshness=green" "$(conjuncts)"
assert_eq   "control: every fixture member was compared"    "compared=4 expected=4" "$(counts)"
assert_has  "control: the zero-findings line is emitted"    '^canary-finding\| every delivery assertion holds at 1111111111111111111111111111111111111111$'
assert_lacks "control: no finding token is emitted"         '^canary-finding\| (content_mismatch|incomplete_delivery|stale_delivery|install_failed|installpath_unresolved|reference_unreadable|cli_unavailable):'
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 1 — the install is skipped, so installPath resolves to nothing.
# compared=0 must FAIL. A canary that exits 0 having compared nothing reports
# "no differences" and "nothing was verified" with the same bytes, and only one
# of those is green.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
printf '{"version":1,"plugins":{}}\n' > "$r/installed_plugins.json"
canary_run "CANARY_INSTALLED_PLUGINS=$r/installed_plugins.json" \
           "CANARY_REFERENCE_DIR=$r/ref" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary"
assert_eq   "row1: an unresolved installPath exits 1"       "1" "$RC"
assert_has  "row1: the finding is installpath_unresolved"   '^canary-finding\| installpath_unresolved: '
assert_eq   "row1: the counts line is still printed"        "compared=0 expected=0" "$(counts)"
assert_has  "row1: compared=0 is itself a finding"          '^canary-finding\| incomplete_delivery: compared=0'
assert_lacks "row1: it never claims the assertions hold"    '^canary-finding\| every delivery assertion holds'

# The same shape when the recorded installPath points at a directory that is not
# there — the CLI wrote a record, the tree did not land.
jq -n --arg p "$r/never-installed" '{version:1,plugins:{"soleur@soleur-marketplace":[{scope:"user",projectPath:"",installPath:$p,version:"0d6443960662-31fddb37",installedAt:"2020-01-01T00:00:00.000Z",lastUpdated:"2020-01-01T00:00:00.000Z",gitCommitSha:"1111111111111111111111111111111111111111"}]}}' \
  > "$r/installed_plugins.json"
canary_run "CANARY_INSTALLED_PLUGINS=$r/installed_plugins.json" \
           "CANARY_REFERENCE_DIR=$r/ref" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary"
assert_eq   "row1: a dangling installPath exits 1"          "1" "$RC"
assert_has  "row1: a dangling installPath is named"         '^canary-finding\| installpath_unresolved: .*is not a directory'
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 2 — one delivered file removed, EVERY remaining file byte-identical.
# This is the under-delivery shape, and it is exactly what a subset comparison
# ("check that these known paths are present and correct") cannot see: every
# member of the subset is present and perfect.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
rm -f "$r/del/b/three.sh"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row2: a missing delivered file exits 1"        "1" "$RC"
assert_has  "row2: the finding is incomplete_delivery"      '^canary-finding\| incomplete_delivery: 1 path\(s\) served by .* were not delivered: b/three\.sh'
assert_eq   "row2: completeness is the red conjunct"        "completeness=red integrity=green freshness=green" "$(conjuncts)"
assert_eq   "row2: the cardinality gap is visible"          "compared=3 expected=4" "$(counts)"
assert_has  "row2: compared!=expected is itself a finding"  '^canary-finding\| incomplete_delivery: compared=3 disagrees with expected=4'
rm -rf "$r"

# A delivered file the reference does NOT serve is the same conjunct failing in
# the other direction. A one-directional comparison calls this green.
r="$(new_fixture)"
printf 'smuggled\n' > "$r/del/extra.txt"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row2b: an unexpected delivered file exits 1"   "1" "$RC"
assert_has  "row2b: the extra path is named"                '^canary-finding\| incomplete_delivery: 1 delivered path\(s\) are not served by .*extra\.txt'
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 3 — the SECOND file in sort order is corrupted, the first is identical.
# A loop that stops at the first member, or that short-circuits on the first
# match, reports green here.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
printf 'tampered bytes\n' > "$r/del/a/two.md"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row3: second-member corruption exits 1"        "1" "$RC"
assert_has  "row3: the corrupt member is named"             "^canary-finding\| content_mismatch: 'a/two\.md' delivered=[0-9a-f]{12} reference=[0-9a-f]{12}$"
assert_lacks "row3: the intact first member is not named"   "^canary-finding\| content_mismatch: 'a/one\.md'"
assert_eq   "row3: integrity is the red conjunct"           "completeness=green integrity=red freshness=green" "$(conjuncts)"
assert_eq   "row3: every member was still compared"         "compared=4 expected=4" "$(counts)"

# The loop must not stop AT the mismatch either: corrupt two members and both
# must be named. One finding for two corrupt files is a loop that breaks.
printf 'tampered bytes\n' > "$r/del/top.json"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row3: two corrupt members yield two findings"  "2" \
  "$(grep -cE "^canary-finding\| content_mismatch: " <<<"$OUT" || true)"
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 4 — THE METADATA BOUNDARY. The install record is PERFECT: the recorded
# `gitCommitSha` equals `main` HEAD and the recorded `version` is a well-formed
# compound. Only the bytes are wrong. Any verdict that a metadata field can
# satisfy reads green here.
#
# The boundary is over FIELDS, not files: `claude plugin list --json` is a
# projection of this same record, so a canary that "reads the CLI instead" has
# not escaped the metadata, only laundered it.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
printf 'tampered bytes\n' > "$r/del/a/one.md"
mk_record() { # <gitCommitSha> <version>
  jq -n --arg p "$r/del" --arg s "$1" --arg v "$2" \
    '{version:1,plugins:{"soleur@soleur-marketplace":[{scope:"user",projectPath:"",installPath:$p,version:$v,installedAt:"2020-01-01T00:00:00.000Z",lastUpdated:"2020-01-01T00:00:00.000Z",gitCommitSha:$s}]}}' \
    > "$r/installed_plugins.json" || { echo "FATAL: could not write the install record" >&2; exit 2; }
}

mk_record "$SHA_CURRENT" "0d6443960662-31fddb37"
canary_run "CANARY_INSTALLED_PLUGINS=$r/installed_plugins.json" \
           "CANARY_REFERENCE_DIR=$r/ref" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary"
assert_eq   "row4: perfect metadata does not rescue bad bytes" "1" "$RC"
assert_has  "row4: the verdict is a content_mismatch"       "^canary-finding\| content_mismatch: 'a/one\.md'"
assert_eq   "row4: freshness is green, integrity is not"    "completeness=green integrity=red freshness=green" "$(conjuncts)"

# INDEPENDENCE PROBE. Same wrong bytes, a DIFFERENT `version` string. If the
# verdict moved, some part of it was a function of the version — which is noise:
# the 8-char half of the measured compound is constant across different
# delivered commits, so it identifies nothing about content.
first_out="$OUT"
mk_record "$SHA_CURRENT" "ffffffffffff-31fddb37"
canary_run "CANARY_INSTALLED_PLUGINS=$r/installed_plugins.json" \
           "CANARY_REFERENCE_DIR=$r/ref" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary"
cases=$((cases + 1))
if [[ "$(grep -cE '^canary-finding\| content_mismatch: ' <<<"$first_out" || true)" == \
      "$(grep -cE '^canary-finding\| content_mismatch: ' <<<"$OUT" || true)" && "$RC" -eq 1 ]]; then
  pass "row4: the verdict is invariant under a change of \`version\`"
else
  fail "row4: changing \`version\` moved the verdict — a metadata field is participating"
fi
rm -rf "$r"

# STATIC COMPANION to row 4. The integrity verdict must be computed from
# DIGESTS. Anchored on the comparison syntax the script has to carry, not on the
# bare token `version` — which appears in this script's own header prose and in
# a fixture JSON literal, so a bare-token grep would pass on a comment.
cases=$((cases + 1))
if grep -qE -- '\[\[ "\$d_ref" != "\$d_del" \]\]' "$CANARY" \
   && grep -qE -- 'finding content_mismatch' "$CANARY"; then
  pass "row4/static: content_mismatch is raised from a digest comparison"
else
  fail "row4/static: no digest comparison guards content_mismatch"
fi

# ---------------------------------------------------------------------------
# ROW 5 — the delivered commit is OLDER but internally consistent: the tree it
# serves is exactly the tree that landed. Freshness must go red ALONE, with
# completeness and integrity green. That is what proves the three conjuncts are
# independently observable rather than a single collapsed predicate — a guard
# that ANDs them into one boolean cannot produce this reading.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
canary_run $(seam "$r" "$SHA_OLD" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row5: a stale delivery exits 1"                "1" "$RC"
assert_eq   "row5: ONLY freshness is red"                   "completeness=green integrity=green freshness=red" "$(conjuncts)"
assert_has  "row5: the finding is stale_delivery"           '^canary-finding\| stale_delivery: delivered commit 222222222222 != .* main HEAD 111111111111'
assert_lacks "row5: no content finding is manufactured"     '^canary-finding\| content_mismatch:'
assert_eq   "row5: the full tree was still compared"        "compared=4 expected=4" "$(counts)"

# The ONE sanctioned exception: `main` HEAD moved between the install and the
# read. That explains the difference without any claim about delivery, so it is
# a DISTINCT outcome — reporting it as staleness would alarm on every PR that
# merges while the canary runs.
canary_run $(seam "$r" "$SHA_OLD" "$SHA_CURRENT" "$SHA_MOVED")
assert_eq   "row5: a mid-run merge is not an alarm"         "0" "$RC"
assert_has  "row5: the mid-run merge is a distinct outcome" '^canary-verdict\| head-moved-during-run$'
assert_lacks "row5: a mid-run merge is not stale_delivery"  '^canary-finding\| stale_delivery:'

# NEGATIVE CONTROL for that exception. A head that did NOT move must not be
# excused — otherwise the exception swallows the whole conjunct.
canary_run $(seam "$r" "$SHA_OLD" "$SHA_CURRENT" "$SHA_CURRENT")
assert_has  "row5: a stable head is still stale"            '^canary-verdict\| findings'
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 6 — the reference fetch fails to return the reference. An empty body and
# an HTML error page are both what raw.githubusercontent answers with when it
# cannot serve a path. Neither is a content verdict, and "we compared nothing,
# therefore nothing differed" is the failure this row exists to prevent.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
: > "$r/ref/b/three.sh"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row6: an empty reference body exits 1"         "1" "$RC"
assert_has  "row6: an empty body is reference_unreadable"   "^canary-finding\| reference_unreadable: reference for 'b/three\.sh' returned an empty body"
assert_lacks "row6: an empty body is not a content verdict" "^canary-finding\| content_mismatch: 'b/three\.sh'"

printf '<!DOCTYPE html>\n<html><head><title>404</title></head><body>Not Found</body></html>\n' > "$r/ref/b/three.sh"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row6: an HTML error page exits 1"              "1" "$RC"
assert_has  "row6: an HTML page is reference_unreadable"    "^canary-finding\| reference_unreadable: reference for 'b/three\.sh' returned an HTML document"
assert_lacks "row6: an HTML page is not a content verdict"  "^canary-finding\| content_mismatch: 'b/three\.sh'"

# Losing the LISTING is the more dangerous half: without it there is no set to
# compare against, and the tempting fallback is "compare the paths we can see",
# which is a subset comparison and structurally blind to row 2.
canary_run "CANARY_DELIVERED_ROOT=$r/del" "CANARY_REFERENCE_DIR=$r/nope" \
           "CANARY_DELIVERED_SHA=$SHA_CURRENT" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary"
assert_eq   "row6: an unavailable listing exits 1"          "1" "$RC"
assert_has  "row6: completeness is declared UNAVAILABLE"    'completeness=unavailable'
assert_has  "row6: the UNAVAILABLE conjunct is named"       '^canary-finding\| reference_unreadable: reference listing .* COMPLETENESS conjunct is UNAVAILABLE'
assert_eq   "row6: it fails closed at compared=0"           "compared=0 expected=0" "$(counts)"
rm -rf "$r"

# EMPTINESS NEGATIVE CONTROL. `plugins/soleur` tracks genuinely zero-byte files
# (.gitkeep / .nojekyll markers). If an empty reference body were
# unconditionally unreadable, the canary would alarm on every single run and be
# switched off — which is how a guard dies. Both sides empty must be green.
r="$(new_fixture)"
: > "$r/ref/top.json"
: > "$r/del/top.json"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "row6/control: a genuinely empty file is green" "0" "$RC"
assert_eq   "row6/control: it is still counted"             "compared=4 expected=4" "$(counts)"
rm -rf "$r"

# ---------------------------------------------------------------------------
# ROW 7 — STATIC WIRING. A guard the workflow never reaches is not a guard.
#
# The predicate is deliberately tolerant of formatting: it anchors on the script
# path appearing in a COMMAND POSITION inside a `run:` block, never on a job
# name, a step id, or an indentation level.
#
# THREE THINGS IT REFUSES TO COUNT AS WIRING, all of which are live in this
# workflow right now, and all of which a bare-token grep accepts — which would
# report the wiring present after the invoking step was deleted
# (cq-assert-anchor-not-bare-token):
#   - a YAML or shell COMMENT naming the script;
#   - a MARKDOWN CODE-SPAN naming the script, which is how the drift issue's
#     remediation text tells an operator what to run. That mention sits inside a
#     `run:` block and on a non-comment line, so nothing structural separates it
#     from the real call — only the backticks do;
#   - a mention that is not in a command position.
# Backtick spans are stripped rather than matched because this repo spells
# command substitution `$(...)`; a backtick here is prose, escaped or not.
#
# ROW 8 of the matrix — that the workflow ALARMS on the canary's verdict rather
# than merely invoking it — is asserted in scripts/marketplace-drift-check.test.sh,
# which extracts and re-executes the workflow's steps hermetically. It is
# deliberately not duplicated here.
# ---------------------------------------------------------------------------
workflow_invokes_canary() { # <workflow-file> -> 0 when wired
  local wf="$1"
  [[ -r "$wf" ]] || return 1
  awk '
    function indent(s) { match(s, /[^ ]/); return RSTART }
    # A `run:` key opens a shell block. Matching the key rather than a fixed
    # indentation is what keeps this tolerant of the step being re-nested.
    function invocation(line,   l) {
      l = line
      if (l ~ /^[[:space:]]*#/) return 0
      gsub(/\\`[^`]*\\`/, "", l)      # escaped code-span inside a quoted string
      gsub(/`[^`]*`/, "", l)          # bare code-span
      return (l ~ /(^|[[:space:]]|[;&|(])((ba)?sh[[:space:]]+|\.\/)?scripts\/plugin-delivery-canary\.sh([[:space:]]|$|[;&|)>"])/)
    }
    /^[[:space:]]*(-[[:space:]]+)?run:/ {
      inrun = 1; ind = indent($0)
      if (invocation($0)) found = 1
      next
    }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) next
      if (indent($0) <= ind) inrun = 0
    }
    inrun && invocation($0) { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$wf"
}

# Synthesized positive control for the predicate itself.
r="$(mktemp -d "${TMPDIR}/canary-wiring.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cat > "$r/wired.yml" <<'YAML'
jobs:
  canary:
    steps:
      - name: Assert the published channel delivers this repo's plugin
        run: |
          set -uo pipefail
          raw="$(bash scripts/plugin-delivery-canary.sh 2>/dev/null)"
          echo "$raw"
      - name: Something else
        run: echo done
YAML
cases=$((cases + 1))
if workflow_invokes_canary "$r/wired.yml"; then
  pass "row7/control: the predicate sees a wired workflow"
else
  fail "row7/control: the predicate cannot see a wired workflow — every row7 RED below is meaningless"
fi

# The mutation: the step that invokes the script is removed.
cat > "$r/unwired.yml" <<'YAML'
jobs:
  canary:
    steps:
      - name: Something else
        run: echo done
YAML
cases=$((cases + 1))
if workflow_invokes_canary "$r/unwired.yml"; then
  fail "row7: an unwired workflow was reported as wired"
else
  pass "row7: removing the invoking step is detected"
fi

# The bare-token trap: the path appears, but only inside a comment.
cat > "$r/commented.yml" <<'YAML'
jobs:
  canary:
    steps:
      # Historically this job ran scripts/plugin-delivery-canary.sh here.
      - name: Something else
        run: |
          # scripts/plugin-delivery-canary.sh used to be invoked on this line
          echo done
YAML
cases=$((cases + 1))
if workflow_invokes_canary "$r/commented.yml"; then
  fail "row7: a commented-out invocation was accepted as wiring"
else
  pass "row7: a commented-out invocation is not wiring"
fi

# The code-span trap, transcribed from the shape the live workflow actually
# carries: the drift issue's remediation text names the command for an operator
# to run. It sits inside a `run:` block on a non-comment line, so only the
# backticks separate it from a real call — and a workflow whose ONLY mention of
# the canary is that sentence is a workflow that never runs it.
cat > "$r/prose-only.yml" <<'YAML'
jobs:
  drift-check:
    steps:
      - name: File the drift issue
        run: |
          REM="Re-run the canary locally:"
          REM="${REM}"$'\n'"   \`bash scripts/plugin-delivery-canary.sh\`"
          printf '%s\n' "$REM"
YAML
cases=$((cases + 1))
if workflow_invokes_canary "$r/prose-only.yml"; then
  fail "row7: a remediation code-span was accepted as wiring"
else
  pass "row7: a remediation code-span is not wiring"
fi

# ...and the same file WITH a real invocation added must read as wired, so the
# stripping above cannot be passing by blinding the predicate entirely.
cat > "$r/prose-plus-real.yml" <<'YAML'
jobs:
  canary:
    steps:
      - name: Assert delivery
        run: |
          raw="$(bash scripts/plugin-delivery-canary.sh 2>/dev/null)"
          REM="${REM}"$'\n'"   \`bash scripts/plugin-delivery-canary.sh\`"
          printf '%s\n' "$raw"
YAML
cases=$((cases + 1))
if workflow_invokes_canary "$r/prose-plus-real.yml"; then
  pass "row7: a real invocation alongside a code-span still reads as wired"
else
  fail "row7: stripping code-spans blinded the predicate to a real invocation"
fi
rm -rf "$r"

# The live assertion.
cases=$((cases + 1))
if workflow_invokes_canary "$WORKFLOW"; then
  pass "row7: $(basename "$WORKFLOW") invokes scripts/plugin-delivery-canary.sh"
else
  fail "row7: $(basename "$WORKFLOW") does not invoke scripts/plugin-delivery-canary.sh in any run: block"
fi

# ---------------------------------------------------------------------------
# ACQUISITION FAILURES. Both are outcomes the workflow has to be able to tell
# apart from a delivery defect, and both are reachable without a network.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
canary_run "CANARY_CLI=/nonexistent/claude-binary" "CANARY_REFERENCE_DIR=$r/ref" \
           "CANARY_MAIN_HEAD=$SHA_CURRENT"
assert_eq   "acquisition: a missing CLI exits 1"            "1" "$RC"
assert_has  "acquisition: the finding is cli_unavailable"   '^canary-finding\| cli_unavailable: '
assert_lacks "acquisition: a missing CLI is not a mismatch" '^canary-finding\| content_mismatch:'

# A CLI that exists but fails. `install_failed` and `cli_unavailable` are
# different diagnoses: one says the channel is broken, the other says the canary
# could not ask.
cat > "$r/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "simulated marketplace failure" >&2
exit 1
SH
chmod +x "$r/fake-claude" || { echo "FATAL: chmod failed on the CLI stub" >&2; exit 2; }
canary_run "CANARY_CLI=$r/fake-claude" "CANARY_REFERENCE_DIR=$r/ref" \
           "CANARY_MAIN_HEAD=$SHA_CURRENT"
assert_eq   "acquisition: a failing install exits 1"        "1" "$RC"
assert_has  "acquisition: the finding is install_failed"    '^canary-finding\| install_failed: '
rm -rf "$r"

# ---------------------------------------------------------------------------
# EXCLUSIONS. The delivered-vs-tracked delta is capped and every excused path
# must match a DECLARED glob. An uncapped allowance is where 32 missing skill
# directories would hide.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
cases=$((cases + 1))
if grep -qE -- '^EXCLUSION_CAP=[0-9]+$' "$CANARY"; then
  pass "exclusions: a numeric cap is declared"
else
  fail "exclusions: no declared EXCLUSION_CAP"
fi

# The list started EMPTY and an earlier version of this assertion required it to
# STAY empty. That was too strong: it also forbade recording a path that has been
# measured and individually justified, which is the only sanctioned way an entry
# is ever supposed to appear. `.in_use/*` is the first — a lock directory the CLI
# writes INTO the install path (observed member `.in_use/143463`, the name a pid),
# so it is delivered-MORE and can never exist in the reference.
#
# The property actually worth guarding is not "no entries" but "no entry broad
# enough to swallow an under-delivery". A catch-all would let 32 missing skill
# directories through while every count still reconciled, which is the exact
# blindness this guard exists to prevent. So: bounded by the cap, and no entry may
# be a bare wildcard or match at the tree root.
cases=$((cases + 1))
excl_count="$(awk '/^DEFAULT_EXCLUSIONS=\(/{f=1;next} f&&/^\)/{exit} f&&/^[[:space:]]*'"'"'/{n++} END{print n+0}' "$CANARY")"
excl_cap="$(sed -n 's/^EXCLUSION_CAP=\([0-9]*\)$/\1/p' "$CANARY" | head -1)"
if [[ "${excl_count:-0}" -le "${excl_cap:-0}" ]]; then
  pass "exclusions: the default list ($excl_count) is within the declared cap ($excl_cap)"
else
  fail "exclusions: the default list ($excl_count) exceeds the declared cap ($excl_cap)"
fi

cases=$((cases + 1))
if awk '/^DEFAULT_EXCLUSIONS=\(/{f=1;next} f&&/^\)/{exit} f' "$CANARY" \
     | grep -qE "^[[:space:]]*'(\*|\*\*|\*/\*|\*\*/\*)'"; then
  fail "exclusions: a catch-all glob is declared — it would swallow an under-delivery"
else
  pass "exclusions: no catch-all glob is declared"
fi

# Excusing more paths than the cap allows must itself be a finding, even when
# the delivery is otherwise perfect.
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT") "CANARY_EXCLUDE=a/*:b/*:top.json"
assert_eq   "exclusions: breaching the cap exits 1"         "1" "$RC"
assert_has  "exclusions: the cap breach is named"           '^canary-finding\| incomplete_delivery: exclusion cap breached: [0-9]+ paths excused, cap is 4'
rm -rf "$r"

# ---------------------------------------------------------------------------
# SYMLINKS. `plugins/soleur` tracks four mode-120000 entries. The repository
# serves them as blobs whose content is the TARGET TEXT, so following the link
# would compare the linked file's bytes against the link's bytes and report a
# mismatch on a tree that is correct.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
ln -s "a/one.md" "$r/ref/link.md" || { echo "FATAL: could not create the ref symlink" >&2; exit 2; }
ln -s "a/one.md" "$r/del/link.md" || { echo "FATAL: could not create the del symlink" >&2; exit 2; }
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "symlink: a matching link is green"             "0" "$RC"
assert_eq   "symlink: the link is a counted member"         "compared=5 expected=5" "$(counts)"

ln -sfn "b/three.sh" "$r/del/link.md" || { echo "FATAL: could not repoint the symlink" >&2; exit 2; }
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "symlink: a repointed link is a mismatch"       "1" "$RC"
assert_has  "symlink: the repointed link is named"          "^canary-finding\| content_mismatch: 'link\.md'"
rm -rf "$r"

# ---------------------------------------------------------------------------
# STDOUT CONTRACT. The workflow parses stdout with two `sed -n 's/^prefix| //p'`
# extractions and counts findings by counting LINES. Anything else on stdout, or
# any finding that spans two lines, silently changes the count it reports.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
canary_stdout $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "contract: stdout carries only the two families" "0" \
  "$(grep -cvE '^(canary-finding\| |canary-counts\| )' <<<"$OUT" || true)"
assert_eq   "contract: exactly one counts line"             "1" \
  "$(grep -cE '^canary-counts\| ' <<<"$OUT" || true)"

# Untrusted bytes reach these lines from a fetched reference. A path carrying
# the `##[` workflow-command prefix must be rewritten, or a delivered filename
# could forge a workflow command in the runner's log.
printf 'smuggled\n' > "$r/del/##[error]evil.txt"
canary_stdout $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_has  "contract: the workflow-command prefix is rewritten" '#-\[error\]evil\.txt'
assert_lacks "contract: the raw ##[ prefix never reaches stdout" '##\['
assert_eq   "contract: every finding is exactly one line"   "0" \
  "$(grep -cvE '^(canary-finding\| |canary-counts\| )' <<<"$OUT" || true)"
rm -rf "$r"

# ---------------------------------------------------------------------------
# THE NETWORK TRANSPORT, exercised HERMETICALLY through a curl shim.
#
# Every row above drives the canary through CANARY_REFERENCE_DIR, which replaces
# the whole transport. That leaves the transport itself untested — and the
# transport is where the reference LISTING is parsed and where the reference is
# PINNED. A first pass of this battery had exactly that hole: a mutation that
# accepted a TRUNCATED trees response as a complete listing survived the entire
# suite, because no fixture ever reached the branch that rejects it. A truncated
# tree is valid JSON that lists FEWER paths than exist, so accepting one hands
# completeness a short reference list and every missing file reads as
# "correctly absent" — the under-delivery defect, re-created inside the guard.
#
# The shim answers the three URLs the canary knows how to ask for and LOGS every
# one, which is also what makes the pin observable: it serves raw content only
# under the sha it was told to expect, so a canary that fetched from `main`
# instead of the delivered commit gets 404s rather than a quiet pass.
# ---------------------------------------------------------------------------
mk_curl_shim() { # <dir>
  mkdir -p "$1/bin" || { echo "FATAL: mkdir failed for the curl shim" >&2; exit 2; }
  cat > "$1/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) shift 2 ;;
    http://*|https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >> "$SHIM_LOG"
src=""
case "$url" in
  *"/git/trees/"*)  src="$SHIM_TREES" ;;
  *"/commits/main") src="$SHIM_HEAD" ;;
  *"raw.githubusercontent.com"*)
    # Serves ONLY under the expected pin. A fetch built from any other sha
    # fails to strip this prefix and lands on a path that does not exist.
    rel="${url#*"/${SHIM_PIN}/plugins/soleur/"}"
    src="$SHIM_RAW/$rel" ;;
esac
code=200
if [[ -n "$src" && -f "$src" ]]; then
  [[ -n "$out" ]] && cp -- "$src" "$out"
else
  code=404
  [[ -n "$out" ]] && printf '<!DOCTYPE html>\n<html><body>404: Not Found</body></html>\n' > "$out"
fi
printf '%s' "$code"
exit 0
SH
  chmod +x "$1/bin/curl" || { echo "FATAL: chmod failed on the curl shim" >&2; exit 2; }
}

# A trees response carrying the fixture's paths plus entries that MUST be
# filtered out: a sibling top-level file, a path outside the plugin subtree, and
# a `tree` (directory) entry, which the API returns alongside blobs.
mk_trees() { # <outfile> <truncated:true|false> <relpath...>
  local out="$1" trunc="$2"; shift 2
  jq -n --argjson t "$trunc" --args '
    { truncated: $t,
      tree: ( [ $ARGS.positional[] | {path: ("plugins/soleur/" + .), mode: "100644", type: "blob"} ]
              + [ {path: "README.md", mode: "100644", type: "blob"},
                  {path: "apps/web-platform/src/x.ts", mode: "100644", type: "blob"},
                  {path: "plugins/soleur/a", mode: "040000", type: "tree"} ] ) }
  ' -- "$@" > "$out" || { echo "FATAL: could not build the trees fixture" >&2; exit 2; }
}

r="$(new_fixture)"
mk_curl_shim "$r"
mk_trees "$r/trees.json" false "${FIXTURE_FILES[@]}"
jq -n --arg s "$SHA_CURRENT" '{sha: $s}' > "$r/head.json" \
  || { echo "FATAL: could not build the head fixture" >&2; exit 2; }

net_seam() { # <trees-file> <pin>
  printf '%s\n' \
    "PATH=$r/bin:$PATH" \
    "SHIM_LOG=$r/curl.log" \
    "SHIM_TREES=$1" \
    "SHIM_HEAD=$r/head.json" \
    "SHIM_RAW=$r/ref" \
    "SHIM_PIN=$2" \
    "CANARY_DELIVERED_ROOT=$r/del" \
    "CANARY_CLI=/nonexistent/claude-binary"
}

# N1 — the whole transport, end to end. `expected=4` is the assertion that the
# trees listing was filtered to the plugin subtree and stripped of its prefix:
# an unfiltered listing would expect 7.
: > "$r/curl.log"
canary_run $(net_seam "$r/trees.json" "$SHA_CURRENT") "CANARY_DELIVERED_SHA=$SHA_CURRENT"
assert_eq   "net: the trees-API path verifies an intact delivery" "0" "$RC"
assert_eq   "net: the listing is filtered to the plugin subtree"  "compared=4 expected=4" "$(counts)"
assert_eq   "net: all three conjuncts are green"                  "completeness=green integrity=green freshness=green" "$(conjuncts)"

# N2 — THE PIN. The delivered commit is OLDER than `main` HEAD and the shim
# serves raw content only under that older commit. Freshness must go red while
# integrity stays green, and NO fetch may carry the newer sha: a reference
# resolved against `main` would turn every merge landing mid-run into a wall of
# manufactured content mismatches.
: > "$r/curl.log"
canary_run $(net_seam "$r/trees.json" "$SHA_OLD") "CANARY_DELIVERED_SHA=$SHA_OLD"
assert_eq   "net/pin: only freshness is red"                "completeness=green integrity=green freshness=red" "$(conjuncts)"
assert_eq   "net/pin: every raw fetch used the delivered commit" "4" \
  "$(grep -cE "^https://raw\.githubusercontent\.com/jikig-ai/soleur/${SHA_OLD}/plugins/soleur/" "$r/curl.log" || true)"
assert_eq   "net/pin: no raw fetch used main HEAD"          "0" \
  "$(grep -cE "^https://raw\.githubusercontent\.com/[^ ]*/${SHA_CURRENT}/" "$r/curl.log" || true)"
assert_eq   "net/pin: the trees listing used the delivered commit too" "1" \
  "$(grep -cE "/git/trees/${SHA_OLD}\?recursive=1$" "$r/curl.log" || true)"

# N3 — A TRUNCATED listing. Valid JSON, parses cleanly, lists fewer paths than
# exist. It must be refused, not consumed.
mk_trees "$r/trees-truncated.json" true "${FIXTURE_FILES[@]}"
canary_run $(net_seam "$r/trees-truncated.json" "$SHA_CURRENT") "CANARY_DELIVERED_SHA=$SHA_CURRENT"
assert_eq   "net: a truncated listing exits 1"              "1" "$RC"
assert_has  "net: a truncated listing is UNAVAILABLE"       'completeness=unavailable'
assert_has  "net: the truncated listing is a reference_unreadable" '^canary-finding\| reference_unreadable: reference listing '
assert_eq   "net: a truncated listing fails closed"         "compared=0 expected=0" "$(counts)"

# N4 — the listing endpoint is unreachable or rate-limited (the shim answers
# 404 for a file it cannot find). Same refusal, different cause.
canary_run $(net_seam "$r/trees-missing.json" "$SHA_CURRENT") "CANARY_DELIVERED_SHA=$SHA_CURRENT"
assert_eq   "net: an unreachable listing exits 1"           "1" "$RC"
assert_has  "net: an unreachable listing is UNAVAILABLE"    'completeness=unavailable'

# N5 — a single reference file 404s while the listing is fine. That is a
# transport failure on one member, not a content verdict on it.
mv -- "$r/ref/b/three.sh" "$r/ref/b/three.sh.hidden" \
  || { echo "FATAL: could not hide the reference file" >&2; exit 2; }
canary_run $(net_seam "$r/trees.json" "$SHA_CURRENT") "CANARY_DELIVERED_SHA=$SHA_CURRENT"
assert_eq   "net: a 404 on one member exits 1"              "1" "$RC"
assert_has  "net: a 404 member is reference_unreadable"     "^canary-finding\| reference_unreadable: .*'b/three\.sh'"
assert_lacks "net: a 404 member is not a content_mismatch"  "^canary-finding\| content_mismatch: 'b/three\.sh'"
rm -rf "$r"

# ---------------------------------------------------------------------------
# The finding vocabulary is a CLOSED SET, and the workflow's issue body groups
# by it. A token that no code path can emit is a token the alarm can never
# explain; a token missing from the script is a finding with nowhere to land.
# ---------------------------------------------------------------------------
for tok in content_mismatch incomplete_delivery stale_delivery install_failed \
           installpath_unresolved reference_unreadable cli_unavailable; do
  cases=$((cases + 1))
  if grep -qE -- "^ *finding ${tok} " "$CANARY"; then
    pass "vocabulary: '${tok}' is raised by a real code path"
  else
    fail "vocabulary: '${tok}' appears in no finding call"
  fi
done

# ---------------------------------------------------------------------------
# The canary's own --self-test must hold, and must hold with no network and no
# credentials — that is the property that lets it run in a sandbox.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
set +e
st_out="$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN \
  bash "$CANARY" --self-test 2>&1)"
st_rc=$?
set -e
if [[ "$st_rc" -eq 0 ]] && grep -qE -- '^SELF-TEST OK: [0-9]+ assertions exercised, 0 unexpected$' <<<"$st_out"; then
  pass "--self-test passes unauthenticated and prints the contracted line"
else
  fail "--self-test failed (rc=$st_rc): $st_out"
fi

# ---------------------------------------------------------------------------
# THE INSTALL INVOCATION ITSELF. Every case above points CANARY_CLI at a path
# that cannot exist, which is correct for keeping fixtures off the network — and
# it means none of them ever EXECUTES the env wrapper the real install runs
# under. That blind spot shipped a live defect: the wrapper listed its `-u`
# options AFTER its NAME=VALUE assignments, so `env` stopped parsing options at
# the first assignment, treated `-u` as the command to run, and died with
# `env: '-u': No such file or directory` before the CLI was ever reached. The
# canary reported `install_failed` — i.e. it blamed the delivery channel for a
# defect in its own invocation — through 98 green assertions.
#
# This drives the real install path with a fake CLI that records the environment
# it was handed. The assertion is deliberately about the WRAPPER, not about a
# successful install: if `env` dies, the fake never runs and the record is
# absent, which is the only signal needed to kill the class.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
mkdir -p "$r/bin" || { echo "FATAL: mkdir failed" >&2; exit 2; }
REC="$r/cli-invocation.txt"
cat > "$r/bin/fake-claude" <<FAKE
#!/usr/bin/env bash
# Records the environment the canary handed us, then fails so the run stops here.
{
  echo "ARGS=\$*"
  echo "HOME=\${HOME:-<unset>}"
  echo "PREFER_HTTPS=\${CLAUDE_CODE_PLUGIN_PREFER_HTTPS:-<unset>}"
  echo "ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-<unset>}"
  echo "ANTHROPIC_AUTH_TOKEN=\${ANTHROPIC_AUTH_TOKEN:-<unset>}"
  echo "CLAUDE_CODE_OAUTH_TOKEN=\${CLAUDE_CODE_OAUTH_TOKEN:-<unset>}"
} >> "$REC"
exit 1
FAKE
chmod +x "$r/bin/fake-claude" || { echo "FATAL: chmod failed" >&2; exit 2; }

# Export decoy credentials so "unset" is a real observation rather than an
# artefact of them being absent from this shell in the first place.
set +e
env ANTHROPIC_API_KEY=decoy-key \
    ANTHROPIC_AUTH_TOKEN=decoy-token \
    CLAUDE_CODE_OAUTH_TOKEN=decoy-oauth \
    "CANARY_CLI=$r/bin/fake-claude" \
    bash "$CANARY" >/dev/null 2>&1
set -e

cases=$((cases + 1))
if [[ -s "$REC" ]]; then
  pass "the install path actually EXECUTES the CLI (the env wrapper is well-formed)"
else
  fail "the CLI was never invoked — the env wrapper died before reaching it (the 'env: -u' class)"
fi

cases=$((cases + 1))
if grep -qE '^HOME=.*/home$' "$REC" 2>/dev/null; then
  pass "the CLI runs against the canary's scratch HOME"
else
  fail "HOME was not pointed at the scratch home: $(grep -E '^HOME=' "$REC" 2>/dev/null | head -1)"
fi

for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN; do
  cases=$((cases + 1))
  if grep -qxF "${v}=<unset>" "$REC" 2>/dev/null; then
    pass "credential ${v} is cleared for the install (decoy did not leak through)"
  else
    fail "credential ${v} reached the CLI: $(grep -E "^${v}=" "$REC" 2>/dev/null | head -1)"
  fi
done

cases=$((cases + 1))
if grep -qE '^ARGS=plugin marketplace add ' "$REC" 2>/dev/null; then
  pass "the first CLI call is the marketplace add"
else
  fail "unexpected first CLI call: $(grep -E '^ARGS=' "$REC" 2>/dev/null | head -1)"
fi

# ---------------------------------------------------------------------------
# EXCLUSION DIRECTION. The three assertions above quantify over the exclusion
# list's SHAPE (cap declared, within cap, no catch-all). None quantifies over its
# EFFECT, and review demonstrated that gap is total: adding one REAL tracked path
# to the list passed all three while masking that exact file going missing —
# stripping it from both sides removes it from the EXPECTED set, so a file the
# channel never delivered reconciles as correctly-absent.
# ---------------------------------------------------------------------------
r="$(new_fixture)"
rm -f "$r/del/a/two.md"                     # the channel fails to deliver it
canary_run "CANARY_DELIVERED_ROOT=$r/del" "CANARY_REFERENCE_DIR=$r/ref" \
           "CANARY_DELIVERED_SHA=$SHA_CURRENT" "CANARY_MAIN_HEAD=$SHA_CURRENT" \
           "CANARY_CLI=/nonexistent/claude-binary" "CANARY_EXCLUDE=a/two.md"
assert_eq   "exclusion-direction: excusing a SERVED path exits 1"   "1" "$RC"
assert_has  "exclusion-direction: the finding names the served path" '^canary-finding\| incomplete_delivery: exclusion matches 1 path\(s\) the repository SERVES'
assert_lacks "exclusion-direction: it never claims the assertions hold" '^canary-finding\| every delivery assertion holds'
rm -rf "$r"

# Direction control: an exclusion for a path the delivery has and the reference
# does NOT (the real `.in_use/<pid>` shape) must still be excused, or the fix
# above would have closed the hole by making every exclusion useless.
r="$(new_fixture)"
mkdir -p "$r/del/.in_use" && printf 'x' > "$r/del/.in_use/143463"
canary_run $(seam "$r" "$SHA_CURRENT" "$SHA_CURRENT")
assert_eq   "exclusion-direction control: a delivered-MORE path is excused" "0" "$RC"
assert_has  "exclusion-direction control: the run is clean"                 '^canary-finding\| every delivery assertion holds'
rm -rf "$r"

# ---------------------------------------------------------------------------
# materialize_reference() — the git-archive transport.
#
# WHY THIS WAS UNREACHABLE. `seam()` sets CANARY_REFERENCE_DIR on EVERY row above,
# and reference_list() only calls materialize_reference when that variable is
# empty. So the whole fetch-if-missing -> git archive -> tar -x chain — the
# transport chosen after three were measured, and the one every integrity verdict
# now depends on — was never executed by this battery. Worse, a broken
# materialize_reference does not fail: reference_list falls through to the
# api.github.com trees transport, which was MEASURED non-viable (~890 sequential
# requests, unfinished at 30 min against a 15 min job budget). A silent downgrade
# to it is indistinguishable from success until the job times out.
#
# These rows drop CANARY_REFERENCE_DIR and run the canary with its CWD inside a
# SYNTHESIZED git repository (cq-test-fixtures-synthesized-only — nothing is
# cloned, and the shas are whatever the fixture's own commits produce).
#
# NETWORK, STATED ACCURATELY. The fixture repo has no remote, so `git fetch` fails
# by construction. That argument does NOT extend to the trees-API fallback: `REPO`
# is hardcoded in the canary with no env seam, so rows B and C DO reach
# api.github.com and take their `reference_unreadable` from a 404 rather than from
# an unreachable network. An earlier revision of this comment claimed both failed
# by construction; review measured otherwise. The canary's curls now carry
# `--max-time`, so a stalled endpoint fails the row instead of hanging the job —
# but these two rows are network-touching, and a future `CANARY_REPO` seam should
# be taken so they are not.
# ---------------------------------------------------------------------------
new_git_fixture() { # -> prints <root>; <root>/repo is a git repo holding plugins/soleur
  local root f d
  root="$(mktemp -d "${SUITE_TMP}/canary-git.XXXXXXXX")" || {
    echo "FATAL: mktemp failed" >&2; exit 2; }
  mkdir -p "$root/repo/${PLUGIN_SUBDIR_LIT}" || { echo "FATAL: mkdir failed" >&2; exit 2; }
  for f in "${FIXTURE_FILES[@]}"; do
    d="$(dirname "$f")"
    mkdir -p "$root/repo/${PLUGIN_SUBDIR_LIT}/$d" || exit 2
    printf 'the tracked content of %s\n' "$f" > "$root/repo/${PLUGIN_SUBDIR_LIT}/$f" || exit 2
  done
  git -C "$root/repo" init -q 2>/dev/null || { echo "FATAL: git init failed" >&2; exit 2; }
  git -C "$root/repo" config user.email t@example.invalid
  git -C "$root/repo" config user.name "fixture"
  git -C "$root/repo" add -A >/dev/null 2>&1
  git -C "$root/repo" commit -qm "fixture" >/dev/null 2>&1 || { echo "FATAL: commit failed" >&2; exit 2; }
  # The delivered tree is a byte-identical copy, so a clean run proves the
  # materialized reference was actually used for the comparison.
  mkdir -p "$root/del" && cp -R "$root/repo/${PLUGIN_SUBDIR_LIT}/." "$root/del/" || exit 2
  printf '%s' "$root"
}
PLUGIN_SUBDIR_LIT="plugins/soleur"

# Row A — the sha IS in the checkout. materialize_reference must produce the
# reference from git objects, with no network, and the run must come out clean.
r="$(new_git_fixture)"
sha="$(git -C "$r/repo" rev-parse HEAD)"
canary_run_in "$r/repo" CANARY_DELIVERED_ROOT="$r/del" \
           CANARY_DELIVERED_SHA="$sha" \
           CANARY_MAIN_HEAD="$sha" \
           CANARY_CLI=/nonexistent/claude-binary
assert_eq  "materialize: a sha present in the checkout yields a clean run" "0" "$RC"
assert_eq  "materialize: every fixture member was compared from the git-archive reference" \
           "compared=4 expected=4" "$(counts)"
assert_has "materialize: integrity is asserted against the materialized tree" \
           '^canary-conjuncts\| .*integrity=green'

# Row B — the sha is NOT in the checkout and cannot be fetched (no remote). The
# transport must fail CLOSED with a named finding. The forbidden outcome is a
# clean run: that would mean the integrity conjunct was declared green while the
# reference it compares against could not be formed.
r2="$(new_git_fixture)"
absent_sha="4444444444444444444444444444444444444444"
canary_run_in "$r2/repo" CANARY_DELIVERED_ROOT="$r2/del" \
           CANARY_DELIVERED_SHA="$absent_sha" \
           CANARY_MAIN_HEAD="$absent_sha" \
           CANARY_CLI=/nonexistent/claude-binary
assert_eq    "materialize: an unmaterializable reference does not exit 0" "1" "$RC"
assert_has   "materialize: it is REPORTED as a transport failure, not inferred from delivery" \
             '^canary-finding\| reference_unreadable'
assert_lacks "materialize: it never claims the delivery assertions hold" \
             '^canary-finding\| every delivery assertion holds'
assert_lacks "materialize: integrity is not declared green without a reference" \
             '^canary-conjuncts\| .*integrity=green'
# Row C — the sha RESOLVES but the commit does not contain the plugin subdir.
# `git archive <sha> -- plugins/soleur` then succeeds and extracts NOTHING, so the
# destination exists while the subdir inside it does not. Rows A and B both miss
# this: A's archive is complete, and B never reaches the archive at all. Found by
# mutating away `[[ -d "$dest/${PLUGIN_SUBDIR}" ]] || return 1` and observing that
# the suite stayed green — an uncovered mutant in the arm written to cover this
# function. Without the check, list_tree runs against a directory that is not
# there and the comparison proceeds against an empty reference, which is the
# under-delivery shape the whole canary exists to refuse.
r3="$(mktemp -d "${SUITE_TMP}/canary-git-nosubdir.XXXXXXXX")"
mkdir -p "$r3/repo/unrelated" "$r3/del"
printf 'not the plugin\n' > "$r3/repo/unrelated/file.txt"
printf 'the tracked content of a/one.md\n' > "$r3/del/placeholder"
git -C "$r3/repo" init -q 2>/dev/null
git -C "$r3/repo" config user.email t@example.invalid
git -C "$r3/repo" config user.name "fixture"
git -C "$r3/repo" add -A >/dev/null 2>&1
git -C "$r3/repo" commit -qm "no plugin subdir" >/dev/null 2>&1
nosub_sha="$(git -C "$r3/repo" rev-parse HEAD)"
canary_run_in "$r3/repo" CANARY_DELIVERED_ROOT="$r3/del" \
           CANARY_DELIVERED_SHA="$nosub_sha" \
           CANARY_MAIN_HEAD="$nosub_sha" \
           CANARY_CLI=/nonexistent/claude-binary
assert_eq    "materialize: a commit lacking the plugin subdir does not exit 0" "1" "$RC"
assert_lacks "materialize: it never claims the delivery assertions hold on an empty reference" \
             '^canary-finding\| every delivery assertion holds'
assert_lacks "materialize: integrity is not green against a subdir that was never extracted" \
             '^canary-conjuncts\| .*integrity=green'
rm -rf "$r" "$r2" "$r3"

# ---------------------------------------------------------------------------
# Minimum-cardinality vacuity guard. If the fixture builder or the seam silently
# stopped producing cases, every row above would vanish and this suite would
# exit 0 having asserted nothing.
# ---------------------------------------------------------------------------
#
# THE FLOOR DOES NOT ROUTE THROUGH `fail`, AND THAT IS THE WHOLE POINT.
# It used to, and that put the detector inside the blast radius of the fault it
# detects: `fail` increments `fails`, and the exit status below reads `fails`, so
# neutering `fail` (redefining it, breaking its arithmetic, losing it to an editing
# slip) silences every row above AND this floor, and the suite prints a total and
# exits 0. A floor enforced through the suspect cannot witness the suspect. Report
# and exit DIRECTLY. Proven by scripts/guard-vacuity-floor.test.sh, which neuters
# `fail` and asserts the floor still exits non-zero.
if [[ "$cases" -lt 121 ]]; then
  printf '\n[FATAL] vacuity guard: only %d assertions ran; expected >= 121.\n' "$cases" >&2
  printf 'Either assertions were deleted or short-circuited, or the floor needs a deliberate bump.\n' >&2
  printf 'Total: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
  exit 1
fi

# ACCOUNTING CONSERVATION — the arm that actually catches a neutered `fail()`.
# The floor above catches "no assertions RAN". It cannot catch "assertions ran and
# their verdicts were discarded", because `cases` is incremented by the assert
# HELPERS and never by `fail` — so stubbing `fail` to a no-op leaves `cases` at its
# full value, the floor is satisfied, and the suite exits 0 with real failures
# silenced. Measured during review: `fail() { :; }` plus a genuine defect printed
# `45 passed, 0 failed (48 assertions)` and RC=0.
#
# Every assertion must record exactly one verdict, so passes+fails MUST equal cases.
# Reported directly, never through `fail`, for the same reason as the floor.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d) — an assertion was counted but its verdict was not recorded. That is what a neutered pass()/fail() looks like.\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi

printf '\nTotal: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$cases"
[[ "$fails" -eq 0 ]]
