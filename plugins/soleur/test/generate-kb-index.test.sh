#!/usr/bin/env bash

# Tests for facet extraction behavior in scripts/generate-kb-index.sh.
# Run: bash plugins/soleur/test/generate-kb-index.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# CASES counts assertions DISPATCHED, incremented at the CALL SITE and never
# inside a verdict helper. That placement is the whole substance of the
# accounting-conservation check at the bottom of this file: a counter that moves
# inside assert_eq()/assert_indexed() moves WITH the verdict, so neutering those
# helpers drops the row and its count together and PASS+FAIL == CASES still
# holds under the exact fault it exists to catch.
#
# Never increment inside `$( )` — a subshell discards it. `$((` is arithmetic
# and is fine; `$(` is command substitution and is not.
CASES=0

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Overridable so the mutation battery can point at a scratch copy of the script
# without mutating the working tree. Default is the real script.
GEN_SCRIPT="${GEN_SCRIPT:-$REPO_ROOT/scripts/generate-kb-index.sh}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/kb-facets"

echo "=== generate-kb-index facet extraction ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Build a synthetic KB root that mirrors the real directory layout
# (knowledge-base/project/learnings/*.md). The generator accepts an explicit
# KB_DIR env var so tests can point at this synthetic root.
setup_kb() {
  local kb="$TMPDIR_BASE/kb-$1"
  mkdir -p "$kb/project/learnings"
  shift
  for fixture in "$@"; do
    cp "$FIXTURE_DIR/$fixture" "$kb/project/learnings/"
  done
  echo "$kb"
}

run_generator() {
  local kb="$1"
  KB_DIR="$kb" bash "$GEN_SCRIPT" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# TS1 — Inline form (`tags: [a, b, c]`) extracts three separate entries
# ---------------------------------------------------------------------------
echo "--- TS1: inline form extraction ---"
kb=$(setup_kb ts1 inline.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
CASES=$((CASES + 1)); assert_contains "$tags_out" "eager-loading" "inline: eager-loading present"
CASES=$((CASES + 1)); assert_contains "$tags_out" "n+1" "inline: n+1 present (literal, not regex)"
CASES=$((CASES + 1)); assert_contains "$tags_out" "performance" "inline: performance present"
cats_out=$(cat "$kb/kb-categories.txt")
CASES=$((CASES + 1)); assert_eq "performance-issues" "$cats_out" "inline: single category emitted"

# ---------------------------------------------------------------------------
# TS2 — Block form extracts same content as inline
# ---------------------------------------------------------------------------
echo ""
echo "--- TS2: block form extraction ---"
kb=$(setup_kb ts2 block.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
CASES=$((CASES + 1)); assert_contains "$tags_out" "eager-loading" "block: eager-loading present"
CASES=$((CASES + 1)); assert_contains "$tags_out" "n+1" "block: n+1 present"
CASES=$((CASES + 1)); assert_contains "$tags_out" "performance" "block: performance present"
cats_out=$(cat "$kb/kb-categories.txt")
CASES=$((CASES + 1)); assert_eq "performance-issues" "$cats_out" "block: single category emitted"

# ---------------------------------------------------------------------------
# TS3 — Malformed fixtures skipped silently (no crash, exit 0)
# ---------------------------------------------------------------------------
echo ""
echo "--- TS3: malformed frontmatter handling ---"
kb=$(setup_kb ts3 no-frontmatter.md missing-tags.md empty-tags.md)
# Must not crash — generator exits 0 even with all-malformed input
CASES=$((CASES + 1))
if KB_DIR="$kb" bash "$GEN_SCRIPT" >/dev/null 2>&1; then
  echo "  PASS: generator exits 0 with malformed-only corpus"
  PASS=$((PASS + 1))
else
  echo "  FAIL: generator crashed on malformed corpus"
  FAIL=$((FAIL + 1))
fi
CASES=$((CASES + 1)); assert_file_exists "$kb/kb-tags.txt" "malformed: kb-tags.txt still emitted (empty ok)"
CASES=$((CASES + 1)); assert_file_exists "$kb/kb-categories.txt" "malformed: kb-categories.txt still emitted"
# no-frontmatter.md tags like "should-not-appear" must not leak
tags_out=$(cat "$kb/kb-tags.txt")
CASES=$((CASES + 1))
if ! grep -q 'should-not-appear' "$kb/kb-tags.txt"; then
  echo "  PASS: body-text tags do not leak into artifact"
  PASS=$((PASS + 1))
else
  echo "  FAIL: body-text tags leaked: $tags_out"
  FAIL=$((FAIL + 1))
fi
# empty-tags.md must not emit a literal "[]" string
CASES=$((CASES + 1))
if ! grep -q '^\[\]$' "$kb/kb-tags.txt"; then
  echo "  PASS: empty tags array does not emit literal []"
  PASS=$((PASS + 1))
else
  echo "  FAIL: empty tags emitted as []"
  FAIL=$((FAIL + 1))
fi
# missing-tags.md still emits its category
cats_out=$(cat "$kb/kb-categories.txt")
CASES=$((CASES + 1)); assert_contains "$cats_out" "workflow" "malformed: category from missing-tags fixture still captured"

# ---------------------------------------------------------------------------
# TS4 — Case-fold dedup produces single entry
# ---------------------------------------------------------------------------
echo ""
echo "--- TS4: case-fold dedup ---"
kb=$(setup_kb ts4 mixed-case.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
eager_count=$(grep -c '^eager-loading$' "$kb/kb-tags.txt" || true)
CASES=$((CASES + 1)); assert_eq "1" "$eager_count" "mixed-case: three variants collapse to single entry"
# Category should lowercase as well
cats_out=$(cat "$kb/kb-categories.txt")
CASES=$((CASES + 1)); assert_eq "performance-issues" "$cats_out" "mixed-case: category lowercased"

# ---------------------------------------------------------------------------
# TS5 — Missing artifact fallback (documented behavior in kb-search SKILL)
# ---------------------------------------------------------------------------
# The generator itself always emits artifacts when run, so TS5 asserts a
# sibling invariant: removing the artifact and re-running regenerates it
# deterministically. This gives kb-search a trivial "run the generator"
# recovery path, which is what the SKILL-level error message tells agents.
echo ""
echo "--- TS5: missing artifact regenerates deterministically ---"
kb=$(setup_kb ts5 inline.md)
run_generator "$kb"
first_sum=$(sha256sum "$kb/kb-tags.txt" | awk '{print $1}')
rm "$kb/kb-tags.txt" "$kb/kb-categories.txt"
CASES=$((CASES + 1)); assert_file_not_exists "$kb/kb-tags.txt" "TS5: artifact removed"
run_generator "$kb"
CASES=$((CASES + 1)); assert_file_exists "$kb/kb-tags.txt" "TS5: artifact regenerated"
second_sum=$(sha256sum "$kb/kb-tags.txt" | awk '{print $1}')
CASES=$((CASES + 1)); assert_eq "$first_sum" "$second_sum" "TS5: regeneration is deterministic"

# ---------------------------------------------------------------------------
# TR6 — Best-effort extraction on dirty values, graceful skip of junk
# ---------------------------------------------------------------------------
echo ""
echo "--- TR6: dirty tag values tolerated, clean siblings still captured ---"
kb=$(setup_kb dirty dirty.md)
run_generator "$kb"
tags_out=$(cat "$kb/kb-tags.txt")
CASES=$((CASES + 1)); assert_contains "$tags_out" "clean-tag" "dirty: clean sibling tag still captured"
cats_out=$(cat "$kb/kb-categories.txt")
CASES=$((CASES + 1)); assert_contains "$cats_out" "messy-category" "dirty: category still emitted (lowercased)"

# ---------------------------------------------------------------------------
# Artifact invariants — sorted, unique, lowercase, no blank lines
# ---------------------------------------------------------------------------
echo ""
echo "--- Invariants: sorted + unique + lowercase ---"
kb=$(setup_kb inv inline.md block.md mixed-case.md)
run_generator "$kb"
# Sorted (LC_ALL=C sort should be idempotent)
CASES=$((CASES + 1))
if diff <(cat "$kb/kb-tags.txt") <(LC_ALL=C sort -u "$kb/kb-tags.txt") >/dev/null; then
  echo "  PASS: kb-tags.txt sorted + unique"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt not sorted or not unique"
  FAIL=$((FAIL + 1))
fi
# Lowercase only
CASES=$((CASES + 1))
if ! grep -qE '[A-Z]' "$kb/kb-tags.txt"; then
  echo "  PASS: kb-tags.txt lowercase only"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt contains uppercase"
  FAIL=$((FAIL + 1))
fi
# No blank lines
CASES=$((CASES + 1))
if ! grep -qE '^$' "$kb/kb-tags.txt"; then
  echo "  PASS: kb-tags.txt no blank lines"
  PASS=$((PASS + 1))
else
  echo "  FAIL: kb-tags.txt contains blank lines"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# TS7 — spec-directory allowlist (#7399)
#
# A spec directory contributes spec.md and tasks.md; every other flat file in
# it is branch-lifetime working state and is not indexed. Fixtures are derived
# from shapes that exist in the real corpus, not from the predicate — the
# reverted archival gate's fixtures were derived from its own implementation,
# which is why its coverage holes clustered exactly where it was wrong.
# ---------------------------------------------------------------------------
echo ""
echo "--- TS7: spec-directory allowlist ---"

# Build a synthetic KB mirroring the real layout. Every file gets a title so a
# missing row cannot be blamed on title extraction.
setup_kb_specs() {
  local kb="$TMPDIR_BASE/kb-specs"
  local p
  for p in \
    "project/specs/feat-x/spec.md" \
    "project/specs/feat-x/tasks.md" \
    "project/specs/feat-x/session-state.md" \
    "project/specs/feat-x/decision-challenges.md" \
    "project/specs/feat-x/phase0-evidence.md" \
    "project/specs/feat-x/ac-walk.md" \
    "project/specs/fix-y/spec.md" \
    "project/specs/fix-y/tasks.md" \
    "project/specs/fix-y/session-state.md" \
    "project/specs/review-workflow-hardening/spec.md" \
    "project/specs/review-workflow-hardening/session-state.md" \
    "project/specs/archive/20260101-000000-feat-old/spec.md" \
    "project/plans/feat-q/plan.md" \
    "project/plans/2026-01-01-feat-r-plan.md" \
    "product/specs/feat-w/session-state.md" \
    "project/specs/feat-z/case-studies/01-durable.md" \
    "engineering/INDEX.md" \
    "engineering/note.md" \
  ; do
    mkdir -p "$kb/$(dirname "$p")"
    printf -- '---\ntitle: "fixture %s"\n---\n\nbody\n' "$p" > "$kb/$p"
  done
  # Non-markdown asset outside specs/: only `-name '*.md'` keeps it out.
  mkdir -p "$kb/engineering"
  printf 'not markdown\n' > "$kb/engineering/diagram.png"
  echo "$kb"
}

# Assert on the LINK TARGET, not a bare path — a fixture title contains the
# path string, so a bare grep would match the title and pass vacuously.
assert_indexed() {
  local kb="$1" rel="$2" label="$3"
  if grep -qF -- "]($rel)" "$kb/INDEX.md"; then
    echo "  PASS: $label"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected link target $rel in INDEX.md)"; FAIL=$((FAIL + 1))
  fi
}

# A drop-assertion with no existence precondition is vacuous: "correctly
# dropped" and "never created" are the same observation, so deleting the
# fixture that gives the assertion meaning is invisible. Deleting a KEEP
# fixture reds; without this guard, deleting a DROP fixture does not.
assert_not_indexed() {
  local kb="$1" rel="$2" label="$3"
  if [[ ! -e "$kb/$rel" ]]; then
    echo "  FAIL: $label (fixture $rel absent from corpus — assertion would be vacuous)"
    FAIL=$((FAIL + 1)); return
  fi
  if grep -qF -- "]($rel)" "$kb/INDEX.md"; then
    echo "  FAIL: $label (unexpected link target $rel in INDEX.md)"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"; PASS=$((PASS + 1))
  fi
}

# Self-test the two bespoke helpers. Both are used 18 times below and neither
# is otherwise verified, so the whole TS7 verdict rests on two unguarded greps.
# Neutering either to an unconditional PASS is invisible without this.
#
# The composite verdict is scored by the CALLER, not in here. This function
# records two RETAINED verdicts and two RESCINDED probes, so it must not be a
# place where a case counter and a verdict counter both move: a function that
# moves both makes the conservation identity a tautology (ADR-193 Decision #2).
# It therefore publishes its three tallies and lets the call site decide.
selftest_helpers() {
  local d="$TMPDIR_BASE/helper-selftest"
  mkdir -p "$d/present"
  printf -- '- [t](present/x.md)\n' > "$d/INDEX.md"
  : > "$d/present/x.md"
  : > "$d/absent-from-index.md"
  local p0=$PASS f0=$FAIL
  # Two RETAINED verdicts — counted here, at their call sites.
  CASES=$((CASES + 1)); assert_indexed     "$d" "present/x.md"          "selftest: indexed row detected"
  CASES=$((CASES + 1)); assert_not_indexed "$d" "absent-from-index.md"  "selftest: missing row detected"
  # Both above must PASS; now prove each helper can FAIL. These two are PROBES,
  # not assertions: their verdicts are deliberately rescinded three lines below,
  # so counting them would break conservation by construction.
  local p1=$PASS f1=$FAIL
  assert_indexed     "$d" "absent-from-index.md"  "selftest(expect-fail): assert_indexed on missing row"
  assert_not_indexed "$d" "present/x.md"          "selftest(expect-fail): assert_not_indexed on present row"
  st_ok_hits=$((p1 - p0)); st_false_reds=$((f1 - f0)); st_caught=$((FAIL - f1))
  # Undo the two deliberate failures. The call site scores the self-test itself.
  FAIL=$f1
}

selftest_helpers
# The correct-input pair must produce 2 passes and 0 failures; the wrong-input
# pair must produce 2 failures. Anything else means a helper cannot distinguish
# present from absent in one direction or the other.
CASES=$((CASES + 1))
if [[ "$st_ok_hits" -eq 2 && "$st_false_reds" -eq 0 && "$st_caught" -eq 2 ]]; then
  echo "  PASS: helper self-test (both helpers detect present AND absent)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: helper self-test (pass=$st_ok_hits expected 2, false_fail=$st_false_reds expected 0, caught=$st_caught expected 2)"
  FAIL=$((FAIL + 1))
fi

kb=$(setup_kb_specs)
run_generator "$kb"

# Fixture sanity: if the generator emitted nothing, every assert_not_indexed
# below would pass vacuously. Fail loudly instead.
CASES=$((CASES + 1))
if ! grep -q '^- \[' "$kb/INDEX.md"; then
  echo "  FAIL: fixture corpus produced no INDEX.md rows — TS7 would be vacuous"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: fixture corpus produced INDEX.md rows (non-vacuity guard)"
  PASS=$((PASS + 1))
fi

# F1 / F14 — a spec dir contributes spec.md AND tasks.md
CASES=$((CASES + 1)); assert_indexed     "$kb" "project/specs/feat-x/spec.md"  "F1: spec.md indexed"
CASES=$((CASES + 1)); assert_indexed     "$kb" "project/specs/feat-x/tasks.md" "F14: tasks.md indexed"

# F2 / F3 / F10 — flat working state is dropped, whatever it is named
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/feat-x/session-state.md"      "F2: session-state.md dropped"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/feat-x/phase0-evidence.md"    "F3: phase0-evidence.md dropped (long tail)"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/feat-x/ac-walk.md"            "F3: ac-walk.md dropped (long tail)"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/feat-x/decision-challenges.md" "F10: decision-challenges.md dropped from index"

# F16 — a deliberate SUBDIRECTORY inside a spec dir is durable content, not
# branch-lifetime scratch, and stays indexed. This is what keeps the rule FLAT;
# without the fourth predicate arm the exclusion is depth-unbounded.
CASES=$((CASES + 1)); assert_indexed "$kb" "project/specs/feat-z/case-studies/01-durable.md" "F16: nested spec-dir content indexed (rule is flat-scoped)"

# F4 — prefix-independence: fix-* behaves exactly like feat-*
CASES=$((CASES + 1)); assert_indexed     "$kb" "project/specs/fix-y/spec.md"          "F4: fix-* spec.md indexed"
CASES=$((CASES + 1)); assert_indexed     "$kb" "project/specs/fix-y/tasks.md"         "F4: fix-* tasks.md indexed"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/fix-y/session-state.md" "F4: fix-* session-state.md dropped"

# F5 — bare-named spec dir. The dropped sibling is load-bearing: without it
# this fixture is indexed before and after and discriminates no mutation.
CASES=$((CASES + 1)); assert_indexed     "$kb" "project/specs/review-workflow-hardening/spec.md"          "F5: bare-named dir spec.md indexed"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/review-workflow-hardening/session-state.md" "F5: bare-named dir session-state.md dropped"

# F9 — pre-existing archive exclusion must not regress
CASES=$((CASES + 1)); assert_not_indexed "$kb" "project/specs/archive/20260101-000000-feat-old/spec.md" "F9: archived spec.md still dropped"

# F7 / F8 — plans are untouched, including the nested shape that broke the
# reverted gate's -maxdepth 1
CASES=$((CASES + 1)); assert_indexed "$kb" "project/plans/feat-q/plan.md"              "F7: nested plan indexed"
CASES=$((CASES + 1)); assert_indexed "$kb" "project/plans/2026-01-01-feat-r-plan.md"   "F8: flat plan indexed"

# F13 — only project/specs/ is special. Loosening the anchor to */specs/*
# would drop this row.
CASES=$((CASES + 1)); assert_indexed "$kb" "product/specs/feat-w/session-state.md" "F13: product/specs/ is not project/specs/"

# F11 / F12 — pre-existing arms adjacent to the edit
CASES=$((CASES + 1)); assert_not_indexed "$kb" "engineering/INDEX.md"   "F11: INDEX.md never indexes itself"
CASES=$((CASES + 1)); assert_not_indexed "$kb" "engineering/diagram.png" "F12: non-markdown dropped"
CASES=$((CASES + 1)); assert_indexed     "$kb" "engineering/note.md"     "F12: sibling markdown still indexed"

# F15 — a trailing slash on KB_DIR must not change the output. Interpolating
# $KB_DIR into the -path patterns silently disabled the whole exclusion.
cp "$kb/INDEX.md" "$TMPDIR_BASE/index-noslash.md"
KB_DIR="$kb/" bash "$GEN_SCRIPT" >/dev/null 2>&1
CASES=$((CASES + 1))
if diff -q "$TMPDIR_BASE/index-noslash.md" "$kb/INDEX.md" >/dev/null 2>&1; then
  echo "  PASS: F15: trailing-slash KB_DIR produces identical output"
  PASS=$((PASS + 1))
else
  echo "  FAIL: F15: trailing-slash KB_DIR changed the output"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# TS8 — facet determinism UNDER CONTENTION
#
# TS5 already asserts "regenerates deterministically", but on a 1-3 file
# fixture: one awk batch, far under a 4 KB stdio flush, so it can never
# reproduce the interleaving it appears to cover. This corpus is deliberately
# large enough to span multiple `xargs -n100` batches and several flush
# boundaries, which is what makes re-adding `-P` to the facet walk detectable.
# ---------------------------------------------------------------------------
echo ""
echo "--- TS8: facet determinism under contention ---"

kb_big="$TMPDIR_BASE/kb-contention"
mkdir -p "$kb_big/project/learnings"
i=0
while [ "$i" -lt 260 ]; do
  printf -- '---\ntitle: "contention fixture %s"\ntags: [contention-tag-%s, shared-tag, another-shared-tag]\ncategory: contention-category-%s\n---\n\nbody\n' \
    "$i" "$i" "$((i % 7))" > "$kb_big/project/learnings/contention-$i.md"
  i=$((i + 1))
done

KB_DIR="$kb_big" bash "$GEN_SCRIPT" >/dev/null 2>&1
tags_a=$(cat "$kb_big/kb-tags.txt"); cats_a=$(cat "$kb_big/kb-categories.txt")
KB_DIR="$kb_big" bash "$GEN_SCRIPT" >/dev/null 2>&1
tags_b=$(cat "$kb_big/kb-tags.txt"); cats_b=$(cat "$kb_big/kb-categories.txt")

CASES=$((CASES + 1))
if [[ "$tags_a" == "$tags_b" && "$cats_a" == "$cats_b" ]]; then
  echo "  PASS: facet artifacts stable across runs on a multi-batch corpus"
  PASS=$((PASS + 1))
else
  echo "  FAIL: facet artifacts differ between two runs on identical input (write race)"
  FAIL=$((FAIL + 1))
fi

# Torn lines are the race's signature: a spliced value that is not a real tag.
# Every emitted tag must be one this fixture actually declares.
CASES=$((CASES + 1))
if printf '%s\n' "$tags_a" | grep -qvE '^(contention-tag-[0-9]+|shared-tag|another-shared-tag)$'; then
  echo "  FAIL: kb-tags.txt contains a value no fixture declares (torn line)"
  printf '%s\n' "$tags_a" | grep -vE '^(contention-tag-[0-9]+|shared-tag|another-shared-tag)$' | head -3 | sed 's/^/        /'
  FAIL=$((FAIL + 1))
else
  echo "  PASS: every emitted tag is a declared value (no torn lines)"
  PASS=$((PASS + 1))
fi

# Non-vacuity: the corpus must actually be big enough to contend.
tag_bytes=$(printf '%s' "$tags_a" | wc -c)
CASES=$((CASES + 1))
if [[ "$tag_bytes" -lt 4096 ]]; then
  echo "  FAIL: TS8 corpus emits only ${tag_bytes}B of tags — under one flush boundary, cannot detect the race"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: TS8 corpus spans multiple flush boundaries (${tag_bytes}B of tags)"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# TS9 — prose/predicate parity
#
# The allowlisted names are load-bearing in the script AND in five prose
# surfaces. Nothing mechanically links them: add `component.md` to the
# predicate tomorrow and every prose file becomes silently false while this
# suite stays green. Same shape ADR-084 already drift-guards via
# components.test.ts (DOC_REL / CONSUMERS / LINK_RE).
#
# The expected set is DERIVED from the script, not restated here — a restated
# copy would be a tautology that moves with the thing it checks.
# ---------------------------------------------------------------------------
echo ""
echo "--- TS9: prose names the same files the predicate allows ---"

# Extract from the predicate group only (the `-o -name '...'` arms).
#
# `|| true` is load-bearing, not defensive noise: `grep` exits 1 on no match and
# this file runs under `set -euo pipefail`, so without it a broken extraction
# kills the whole suite BEFORE the empty-check below can report why — the
# fail-closed branch would be unreachable, which is the opposite of fail-closed.
allowed=$( { sed -n "/-not -path '\*\/project\/specs\/\*'/,/\\\\)/p" "$GEN_SCRIPT" \
  | grep -oE "\-name '[^']+'" | sed "s/-name '//; s/'//" | LC_ALL=C sort -u; } || true )

CASES=$((CASES + 1))
if [[ -z "$allowed" ]]; then
  echo "  FAIL: TS9 could not extract the allowlist from the predicate (extraction is broken, not the prose)"
  FAIL=$((FAIL + 1))
elif [[ "$allowed" != "$(printf 'spec.md\ntasks.md')" ]]; then
  echo "  FAIL: TS9 extracted an unexpected allowlist:"; printf '%s\n' "$allowed" | sed 's/^/        /'
  echo "        If the predicate legitimately changed, update every prose surface below, then this expectation."
  FAIL=$((FAIL + 1))
else
  echo "  PASS: predicate allowlist extracted = spec.md, tasks.md"
  PASS=$((PASS + 1))
fi

for doc in \
  "$REPO_ROOT/plugins/soleur/skills/spec-templates/SKILL.md" \
  "$REPO_ROOT/plugins/soleur/skills/brainstorm/SKILL.md" \
  "$REPO_ROOT/plugins/soleur/agents/engineering/research/learnings-researcher.md" \
  "$REPO_ROOT/.openhands/skills/learnings-researcher/SKILL.md" \
  "$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-174-kb-index-exclusion-supersedes-per-feature-archival.md"
do
  label="prose parity: $(basename "$(dirname "$doc")")/$(basename "$doc")"
  # One verdict per iteration, on either branch — counted before the branch.
  CASES=$((CASES + 1))
  if [[ ! -f "$doc" ]]; then
    echo "  FAIL: $label (file missing — a consumer moved or was renamed)"; FAIL=$((FAIL + 1)); continue
  fi
  missing=""
  while IFS= read -r name; do
    grep -qF -- "$name" "$doc" || missing="$missing $name"
  done <<< "$allowed"
  if [[ -n "$missing" ]]; then
    echo "  FAIL: $label does not name:$missing"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"; PASS=$((PASS + 1))
  fi
done

# ---------------------------------------------------------------------------
# Anti-vacuity floor.
#
# Without this, deleting the whole TS7 block exits 0 with "ALL TESTS PASSED" —
# 21 assertions vanish and nothing notices, because the only merge gate is
# FAIL==0. A floor (never -eq, which makes every added assertion a spurious
# failure) makes silent removal loud. Derived from a green run; raise it in
# lockstep when assertions are added.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never by bumping FAIL. A floor
# that reports itself by incrementing FAIL increments the same counter the exit
# status reads, so neutering the assertion machinery silences the rows AND the
# floor that exists to notice the silence — the suite prints a total and exits 0.
# A floor enforced through the suspect cannot witness the suspect.
# ---------------------------------------------------------------------------
MIN_ASSERTIONS=57
total_assertions=$((PASS + FAIL))
if [[ "$total_assertions" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$total_assertions" "$MIN_ASSERTIONS" >&2
  printf '        (assertions were removed, or a block exited early without running)\n' >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions dispatched) ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Accounting conservation.
#
# The arm that actually catches a neutered verdict helper. The floor above
# catches "no assertions RAN"; it cannot catch "assertions ran and their
# verdicts were DISCARDED", because CASES keeps its full value when assert_eq()
# or assert_indexed() is stubbed to a no-op. Every dispatched assertion records
# exactly one verdict, so PASS+FAIL MUST equal CASES. Reported directly for the
# same reason as the floor.
# ---------------------------------------------------------------------------
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' \
    "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was dispatched but its verdict was not recorded — that is what a neutered assert helper looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions dispatched) ==="
  exit 1
fi

print_results
