#!/usr/bin/env bash
# Deterministic unit test for extract-block.cjs + gen-skill-prompt.cjs (no live LLM).
# Asserts:
#   AC4 round-trip — regenerating each target's projected prompt from the source
#                    block equals the committed projection byte-for-byte.
#   extractBlock throws loudly when a marker is missing (fail-closed).
#   extractBlock returns the trimmed text strictly between the markers.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../../.." && pwd)"
EXTRACT="$SKILL_DIR/scripts/extract-block.cjs"
GEN="$SKILL_DIR/scripts/gen-skill-prompt.cjs"
REGISTRY="$SKILL_DIR/gated-skills.json"
fails=0

pass() { echo "ok   [$1]"; }
fail() { echo "FAIL [$1]: $2"; fails=$((fails + 1)); }

# --- AC4 round-trip: generated projection == committed projection (per registry target) ---
# Target loop is derived from gated-skills.json (target + projected_prompt_path) rather than
# a hardcoded list, so a newly-registered gated classifier is round-trip-covered automatically.
# projected_prompt_path is repo-root-relative (e.g. plugins/soleur/skills/eval-harness/prompts/go-skill.txt).
roundtrips=0
while IFS=$'\t' read -r target projected; do
  [[ -z "$target" ]] && continue
  committed="$REPO_ROOT/$projected"
  if diff -u <(node "$GEN" "$target" --stdout) "$committed" >/tmp/eval-gate-roundtrip.diff 2>&1; then
    pass "round-trip $target == committed projection"
  else
    fail "round-trip $target" "generated projection differs from committed $committed (run: node scripts/gen-skill-prompt.cjs $target)"
    cat /tmp/eval-gate-roundtrip.diff
  fi
  roundtrips=$((roundtrips + 1))
done < <(node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).forEach(e=>process.stdout.write(e.target+"\t"+e.projected_prompt_path+"\n"))' "$REGISTRY")

# Minimum-cardinality guard: a registry-derived loop silently exits 0 with ZERO coverage if the
# registry is empty / unreadable / the node one-liner emits nothing. Fail loud instead.
if [[ "$roundtrips" -lt 1 ]]; then
  fail "registry round-trip coverage" "0 round-trip targets executed — empty/unreadable $REGISTRY would otherwise pass with no coverage"
fi

# --- extractBlock returns trimmed text between markers ---
got=$(node -e '
  const { extractBlock } = require(process.argv[1]);
  const src = "pre\n<!-- eval-gate:block:x:start -->\n  HELLO  \n<!-- eval-gate:block:x:end -->\npost";
  process.stdout.write(extractBlock(src, "<!-- eval-gate:block:x:start -->", "<!-- eval-gate:block:x:end -->"));
' "$EXTRACT")
if [[ "$got" == "HELLO" ]]; then
  pass "extractBlock trims block text"
else
  fail "extractBlock trims block text" "got '$got' (want 'HELLO')"
fi

# --- extractBlock throws loudly on a missing marker (fail-closed) ---
if node -e '
  const { extractBlock } = require(process.argv[1]);
  extractBlock("no markers here", "<!-- eval-gate:block:x:start -->", "<!-- eval-gate:block:x:end -->");
' "$EXTRACT" 2>/dev/null; then
  fail "extractBlock missing-marker throws" "did not throw on a missing start marker"
else
  pass "extractBlock missing-marker throws (fail-closed)"
fi

# --- CLI exits non-zero with stderr when a marker is missing ---
tmp="$(mktemp)"
printf 'this file has no sentinels\n' > "$tmp"
if node "$EXTRACT" "$tmp" go-routing 2>/tmp/eval-gate-cli.err; then
  fail "extract-block CLI missing-marker exit" "CLI exited 0 on a file without markers"
else
  if grep -q "marker not found" /tmp/eval-gate-cli.err; then
    pass "extract-block CLI missing-marker exits non-zero with clear stderr"
  else
    fail "extract-block CLI missing-marker stderr" "stderr lacked a clear message: $(cat /tmp/eval-gate-cli.err)"
  fi
fi
rm -f "$tmp"

if [[ "$fails" -gt 0 ]]; then
  echo "extract-block: $fails assertion(s) failed"
  exit 1
fi
echo "extract-block: all assertions passed"
