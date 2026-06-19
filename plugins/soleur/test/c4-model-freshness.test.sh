#!/usr/bin/env bash
# c4-model-freshness.test.sh — CI freshness gate for the compiled LikeC4 model.
#
# Asserts the committed knowledge-base/engineering/architecture/diagrams/
# model.likec4.json is byte-identical to a fresh render of the .c4 sources with
# the pinned likec4@1.50.0 CLI. This is the merge-contract backstop to the
# c4-model-regenerate pre-commit hook (which is bypassable with --no-verify):
# if any .c4 edit landed without regenerating the artifact, this test FAILS and
# tells the author exactly how to fix it.
#
# Auto-discovered by the `scripts` group glob in scripts/test-all.sh and run in
# the `test-scripts` CI shard, which installs likec4@1.50.0 (see
# .github/workflows/ci.yml, mirroring the gitleaks-install precedent). Renders
# via scripts/regenerate-c4-model.sh --out <temp> so the render + validate logic
# is IDENTICAL to the hook's — they can never disagree on what "fresh" means.
#
# Locally (no global likec4), `npx -y likec4@1.50.0` downloads the pinned CLI on
# first run; CI's global install makes it instant.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REGEN="$REPO_ROOT/scripts/regenerate-c4-model.sh"
COMMITTED="$REPO_ROOT/knowledge-base/engineering/architecture/diagrams/model.likec4.json"

echo "=== C4 model freshness (model.likec4.json vs .c4 sources) ==="
echo ""

assert_file_exists "$REGEN" "regenerate-c4-model.sh exists"
assert_file_exists "$COMMITTED" "committed model.likec4.json exists"

if [[ "$FAIL" -gt 0 ]]; then
  print_results
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FRESH="$TMP/fresh.likec4.json"

# Render + validate via the shared primitive (off-tree, never touches the tree).
# A non-zero exit here means the .c4 SOURCE is broken (the script refuses to
# render an empty/invalid model) — surface that distinctly from drift.
if ! bash "$REGEN" --out "$FRESH" >"$TMP/regen.log" 2>&1; then
  echo "  FAIL: regenerate-c4-model.sh could not produce a valid model from the .c4 sources" >&2
  sed 's/^/    /' "$TMP/regen.log" >&2
  FAIL=$((FAIL + 1))
  print_results
fi

# Byte-diff the fresh render against the committed artifact. likec4 export is
# deterministic, so an in-sync tree renders byte-identical output.
if cmp -s "$FRESH" "$COMMITTED"; then
  echo "  PASS: committed model.likec4.json is in sync with the .c4 sources"
  PASS=$((PASS + 1))
else
  echo "  FAIL: model.likec4.json is STALE — it does not match a fresh render of the .c4 sources." >&2
  echo "        Run: bash scripts/regenerate-c4-model.sh   (then commit the updated model.likec4.json)" >&2
  echo "        Fresh render: $(jq '.elements | length' "$FRESH") elements / $(jq '.relations | length' "$FRESH") relations" >&2
  echo "        Committed:    $(jq '.elements | length' "$COMMITTED") elements / $(jq '.relations | length' "$COMMITTED") relations" >&2
  # Pinpoint the drift (esp. a label/property change where counts match): the
  # byte-level cmp above is the gate; this key-sorted jq diff is diagnostic only.
  echo "        First differing keys (fresh vs committed):" >&2
  diff <(jq -S . "$FRESH") <(jq -S . "$COMMITTED") | head -20 | sed 's/^/          /' >&2 || true
  FAIL=$((FAIL + 1))
fi

print_results
