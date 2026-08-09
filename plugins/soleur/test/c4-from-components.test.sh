#!/usr/bin/env bash
# c4-from-components.test.sh — end-to-end gate for the /soleur:sync C4 producer.
#
# The unit suite (c4-from-components.test.ts) covers the pure logic. This suite
# covers what only a real run can: the artifact set actually written to disk, the
# refuse-to-overwrite contract against a real hand-edited file, determinism across
# two consecutive runs, and — the one that matters — plan AC2, that the
# relationship-count gate is observed BOTH red and green by the same producer.
# A gate that has never been seen red is not a gate.
#
# Renders with the pinned likec4@1.50.0, same as c4-model-freshness.test.sh: the
# `test-scripts` CI shard installs it globally and `npx -y` fetches it locally on
# first run. When the CLI is genuinely unreachable the producer degrades cleanly
# (status=degraded reason=likec4-unavailable), which this suite treats as a SKIP
# rather than a failure — an offline runner must not red the build, but it must
# also not silently report coverage it did not obtain.
#
# All fixtures are synthesized (cq-test-fixtures-synthesized-only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PRODUCER="$REPO_ROOT/plugins/soleur/scripts/generate-c4-from-components.ts"
FIXTURES="$SCRIPT_DIR/fixtures/component-docs"
DIAGRAMS="knowledge-base/engineering/architecture/diagrams"
GEN="$DIAGRAMS/generated-components.c4"

echo "=== C4 producer end-to-end ==="
echo ""

assert_file_exists "$PRODUCER" "producer wrapper exists"

if [[ "$FAIL" -gt 0 ]]; then
  print_results
fi

# Scratch lives under TMPDIR (defaulted to /var/tmp): /tmp is a machine-global
# 4 GiB tmpfs shared with sibling worktrees, and a setup failure here must ABORT
# rather than let a later case run against the previous case's tree.
export TMPDIR="${TMPDIR:-/var/tmp}"
WORK="$(mktemp -d -t c4e2e.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# seed <name> <fixture-dir>  — build a throwaway repo root from a fixture corpus.
seed() {
  local root="$WORK/$1"
  mkdir -p "$root/knowledge-base/project/components" || { echo "FATAL: mkdir failed"; exit 2; }
  cp "$FIXTURES/$2"/*.md "$root/knowledge-base/project/components/" \
    || { echo "FATAL: fixture copy failed for $2"; exit 2; }
  echo "$root"
}

# `|| true` is load-bearing. The producer exits 1 on a source fault, and under
# `set -e` a non-zero command inside a command substitution aborts the assignment
# BEFORE any assertion runs — the suite would die silently mid-file instead of
# reporting a failure. Cases that care about the exit code capture it explicitly.
run_producer() { bun "$PRODUCER" "$1" 2>&1 || true; }

# --- AC2 (green arm): a corpus that DOES declare dependencies ----------------
OK_ROOT="$(seed ok frontmatter-form)"
OK_OUT="$(run_producer "$OK_ROOT")"

if [[ "$OK_OUT" == *"reason=likec4-unavailable"* ]]; then
  echo "  SKIP: likec4 CLI unreachable — end-to-end render arms not exercised"
  echo "        (the producer degraded cleanly, which is the designed behaviour)"
  SKIPPED=$((SKIPPED + 1))
  print_results
fi

assert_contains "$OK_OUT" "status=ok" "AC2 green arm: declared deps render as ok"
assert_contains "$OK_OUT" "relationships=3" "AC2 green arm: all three edges survive to the model"

# --- AC2 (red arm): Soleur's OWN prose form ---------------------------------
# The corpus the plan exists to catch: elements render, output validates, exit is
# 0 — and the diagram is disconnected boxes. Same producer, same run, opposite
# verdict. This is the assertion that makes the gate real.
PROSE_ROOT="$(seed prose prose-form)"
PROSE_OUT="$(run_producer "$PROSE_ROOT")"
assert_contains "$PROSE_OUT" "status=degraded" "AC2 red arm: prose-only corpus reports DEGRADED"
assert_contains "$PROSE_OUT" "relationships=0" "AC2 red arm: marker carries relationships=0"
assert_contains "$PROSE_OUT" "elements=3" "AC2 red arm: degraded is NOT an empty model — elements still rendered"

# --- Phase 1.5: the viewer needs more than three .c4 files ------------------
assert_file_exists "$OK_ROOT/$GEN" "emits generated-components.c4"
assert_file_exists "$OK_ROOT/$DIAGRAMS/model.likec4.json" "emits model.likec4.json (viewer returns MODEL_NOT_BUILT without it)"
assert_file_exists "$OK_ROOT/$DIAGRAMS/c4-model.md" "emits the c4-model.md view page"

VIEW_PAGE_BODY="$(cat "$OK_ROOT/$DIAGRAMS/c4-model.md")"
assert_contains "$VIEW_PAGE_BODY" '```likec4-view' "view page carries a likec4-view fence (the viewer renders nothing without one)"

# --- Phase 1.4 / AC3: never clobber a hand edit -----------------------------
# Anchor on a sentinel only the hand-authored file can carry, not on the absence
# of the generated one — the producer writes several files and a bare
# "file changed" check would pass for the wrong reason.
HAND_ROOT="$(seed hand frontmatter-form)"
mkdir -p "$HAND_ROOT/$DIAGRAMS" || { echo "FATAL: mkdir failed"; exit 2; }
# The hand-edited file must still be a RENDERABLE model. A stub with no elements
# renders empty, which is a legitimate `failed` verdict — and would make this case
# pass for the wrong reason (the run aborting, not the file being protected).
cat > "$HAND_ROOT/$GEN" <<'HANDEDIT' || { echo "FATAL: seed write failed"; exit 2; }
model {
  // HAND_EDITED_SENTINEL_7332 operator corrected this edge by hand
  apiGateway = component "Api Gateway" {
    description "Corrected by hand"
  }
  authService = component "Auth Service" {
    description "Corrected by hand"
  }
  apiGateway -> authService "corrected edge"
}
HANDEDIT

HAND_OUT="$(run_producer "$HAND_ROOT")"
HAND_BODY="$(cat "$HAND_ROOT/$GEN")"
assert_contains "$HAND_BODY" "HAND_EDITED_SENTINEL_7332" "AC3: hand-edited .c4 survives the run byte-for-byte"
assert_contains "$HAND_OUT" "skipped=1" "AC3: the skip is REPORTED in the marker, not silent"

# --- Determinism: an unchanged KB must not emit a diff forever --------------
DET_ROOT="$(seed det frontmatter-form)"
run_producer "$DET_ROOT" >/dev/null
FIRST="$(cat "$DET_ROOT/$GEN")"
run_producer "$DET_ROOT" >/dev/null
SECOND="$(cat "$DET_ROOT/$GEN")"
assert_eq "$FIRST" "$SECOND" "two consecutive runs produce a byte-identical .c4"

# --- Deprecated filter, end to end ------------------------------------------
DEP_ROOT="$(seed dep mixed-deprecated)"
run_producer "$DEP_ROOT" >/dev/null
DEP_BODY="$(cat "$DEP_ROOT/$GEN")"
if [[ "$DEP_BODY" == *"legacyWorker"* ]]; then
  echo "  FAIL: deprecated component leaked into the generated model"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: deprecated component is filtered out of the generated model"
  PASS=$((PASS + 1))
fi

print_results
