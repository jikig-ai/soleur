#!/usr/bin/env bash

# Tests for plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh.
# Run: bash plugins/soleur/test/vendor-drift-classify.test.sh
#
# The classifier reads a unified diff on stdin and (optionally) takes a SHA
# pair (`<old-sha> <new-sha>`) for rollback detection plus `--archived` /
# `--renamed` flags for the upstream-disambiguation cases routed in by the
# drift workflow's `gh api repos/<o>/<r>` step.
#
# Exit codes (priority order — first match wins):
#   11 LICENSE diff           (path contains LICENSE)
#   15 upstream rollback      (new-sha is ancestor of old-sha)
#   12 upstream archived      (--archived flag)
#   16 upstream renamed       (--renamed flag)
#   10 security-relevant      (regex hit on diff body)
#   13 batched / prose only   (non-empty diff, no security signal)
#    0 no-op                  (empty / whitespace-only diff)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
CLASSIFY="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh"
FIX="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== vendor-drift-classify tests ==="
echo ""

assert_file_exists "$CLASSIFY" "vendor-drift-classify.sh exists"
assert_file_exists "$FIX/upstream-fields-art9-add.diff" "art9-add fixture exists"
assert_file_exists "$FIX/upstream-prose-typo.diff" "prose-typo fixture exists"
assert_file_exists "$FIX/upstream-rollback.diff" "rollback fixture exists"
assert_file_exists "$FIX/upstream-license-edit.diff" "license-edit fixture exists"
assert_file_exists "$FIX/upstream-empty.diff" "empty fixture exists"

run_classify() {
  set +e
  bash "$CLASSIFY" "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

# --- TS1: empty diff → exit 0 ---
echo "TS1: empty diff → exit 0 (no-op)"
RC=$(run_classify < "$FIX/upstream-empty.diff")
assert_eq "0" "$RC" "exit 0 on empty diff"
echo ""

# --- TS2: whitespace-only diff → exit 0 ---
echo "TS2: whitespace-only diff → exit 0 (no-op)"
RC=$( (printf '   \n\n\t\n') | bash "$CLASSIFY" >/dev/null 2>&1; echo $? || true )
assert_eq "0" "$RC" "exit 0 on whitespace-only diff"
echo ""

# --- TS3: art9-add → exit 10 (security-relevant) ---
echo "TS3: art9-add → exit 10 (security-relevant: Art. 9 row added)"
RC=$(run_classify < "$FIX/upstream-fields-art9-add.diff")
assert_eq "10" "$RC" "exit 10 on Art. 9 row addition"
echo ""

# --- TS4: prose-typo → exit 13 (batched) ---
echo "TS4: prose-typo → exit 13 (no security regex match, but content changed)"
RC=$(run_classify < "$FIX/upstream-prose-typo.diff")
assert_eq "13" "$RC" "exit 13 on prose-only edit"
echo ""

# --- TS5: LICENSE edit → exit 11 ---
echo "TS5: LICENSE edit → exit 11 (license-changed)"
RC=$(run_classify < "$FIX/upstream-license-edit.diff")
assert_eq "11" "$RC" "exit 11 on LICENSE diff"
echo ""

# --- TS6: --archived flag → exit 12 ---
echo "TS6: --archived flag → exit 12"
RC=$( (printf '') | bash "$CLASSIFY" --archived >/dev/null 2>&1; echo $? || true )
assert_eq "12" "$RC" "exit 12 with --archived (overrides empty-diff exit 0)"
echo ""

# --- TS7: --renamed flag → exit 16 ---
echo "TS7: --renamed flag → exit 16"
RC=$( (printf '') | bash "$CLASSIFY" --renamed >/dev/null 2>&1; echo $? || true )
assert_eq "16" "$RC" "exit 16 with --renamed"
echo ""

# --- TS8: rollback (new SHA is ancestor of old SHA) → exit 15 ---
# Build a throwaway git repo with two real commits so the classifier's
# `git merge-base --is-ancestor` check works regardless of the surrounding
# repo's clone shape. Previously this relied on `git rev-parse HEAD~1`
# against the test runner's checkout, which fails on shallow clones in CI
# (per test-design review #3521 — fragile-to-fetch-depth class).
TMPREPO=$(mktemp -d -t classify-rollback-XXXXXXXX)
trap 'rm -rf "$TMPREPO"' EXIT
(
  cd "$TMPREPO"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test
  echo a > f
  git add f
  git commit -q -m "first"
  echo b >> f
  git add f
  git commit -q -m "second"
) >/dev/null
OLD_SHA=$(git -C "$TMPREPO" rev-parse HEAD)
NEW_SHA=$(git -C "$TMPREPO" rev-parse HEAD~1)
# Run the classifier with GIT_DIR pointed at the tmp repo so its
# merge-base call resolves the synthetic ancestry.
run_classify_in() {
  local repo="$1"; shift
  (cd "$repo" && bash "$CLASSIFY" "$@" >/dev/null 2>&1; echo $?)
}
echo "TS8: rollback SHA pair → exit 15"
RC=$(run_classify_in "$TMPREPO" "$OLD_SHA" "$NEW_SHA" < "$FIX/upstream-rollback.diff")
assert_eq "15" "$RC" "exit 15 when new-sha is ancestor of old-sha (rollback)"
echo ""

# --- TS9: rollback flag takes precedence over security-regex content ---
# Even if the diff body contains an Art. 9 addition, a rollback SHA pair
# should classify as 15. Order matters; tests the priority chain.
echo "TS9: rollback precedence — wins over security-regex content"
RC=$(run_classify_in "$TMPREPO" "$OLD_SHA" "$NEW_SHA" < "$FIX/upstream-fields-art9-add.diff")
assert_eq "15" "$RC" "exit 15 even when diff body would otherwise be exit 10"
echo ""

# --- TS10: archived flag wins over diff content ---
echo "TS10: --archived precedence — wins over security-regex content"
RC=$( bash "$CLASSIFY" --archived < "$FIX/upstream-fields-art9-add.diff" >/dev/null 2>&1; echo $? || true )
assert_eq "12" "$RC" "exit 12 with --archived even when diff body is security-relevant"
echo ""

# --- TS11: forward-fast (new is descendant, NOT ancestor) → falls through ---
# Pass `<old-sha=HEAD~1> <new-sha=HEAD>` — new is descendant of old, NOT a
# rollback. The classifier must fall through to diff content, not exit 15.
echo "TS11: forward-fast (new is descendant) → falls through to diff classifier"
RC=$(run_classify_in "$TMPREPO" "$NEW_SHA" "$OLD_SHA" < "$FIX/upstream-fields-art9-add.diff")
assert_eq "10" "$RC" "exit 10 (not 15) when new commit is descendant of pinned"
echo ""

# --- The shape cron-content-vendor-drift.ts ACTUALLY emits (#7710) -----------
#
# This is the binding test for the wiring, and it exists because the one that
# shipped first was a source-grep — `expect(src).toMatch(/aggDiffParts\.push\(/)`
# — whose NAME was "populates aggDiffParts: the classifier must receive the
# diff" and which could not witness a single word of that claim. It passed
# against a `path\told\tnew` triple, which begins with a path and therefore
# matches NEITHER the license anchor `^(\+\+\+|---) [ab]/…LICENSE` NOR the
# security anchors `^\+`. Exits 10, 11 and 15 were structurally unreachable and
# every drift fell to check 5's bare non-empty test — exit 13, the auto-PR route
# with `mergeMode: "direct"`, which is restricted to 13 precisely to keep
# attacker-controlled upstream bytes from landing via the weekly bot.
#
# So: drive the REAL script with the REAL shape, and assert the exit code.

emitted_fragment() {
  # Mirrors the handler: `--- a/<path>`, `+++ b/<path>`, every body line `+`.
  local path="$1"; shift
  printf -- '--- a/%s\n+++ b/%s\n' "$path" "$path"
  local line
  for line in "$@"; do printf -- '+%s\n' "$line"; done
}

RC=$(emitted_fragment "pii-detector/layers/frontend.md" \
      "Some ordinary prose line." \
      "Controllers MUST record the Art. 9 basis." | run_classify)
assert_eq "10" "$RC" "emitted shape: an Art. 9 line in the body reaches the SECURITY exit"

RC=$(emitted_fragment "LICENSE" "MIT License" | run_classify)
assert_eq "11" "$RC" "emitted shape: a LICENSE path reaches the LICENSE exit"

# NOT a `layers/` path: the security regex's last alternative is
# `^\+\+\+ b/.*/layers/`, so the HEADER alone makes any file under a `layers/`
# directory security-relevant regardless of body. Six of the eight registered
# upstream files live there (`notice-frontmatter.sh upstream-files`), so under
# the corrected shape most corpus drift now routes to the GUARDED exit 10
# rather than the auto-PR exit 13. That is a real behavioural change and it is
# the safe direction; the two non-`layers/` files are what keep 13 reachable.
RC=$(emitted_fragment "pii-detector/patterns/fields.md" \
      "a purely cosmetic wording change" | run_classify)
assert_eq "13" "$RC" "emitted shape: ordinary prose outside layers/ still batches"

RC=$(emitted_fragment "pii-detector/layers/frontend.md" \
      "a purely cosmetic wording change" | run_classify)
assert_eq "10" "$RC" "emitted shape: a layers/ path is security-relevant by header alone"

# The regression control. The superseded TSV must NOT reach a guarded exit —
# if this ever returns 10 or 11 the anchors have changed and the comment above
# is stale.
RC=$(printf 'pii-detector/layers/frontend.md\tabc123\tdef456\n' | run_classify)
assert_eq "13" "$RC" "control: the superseded TSV shape falls through to batched (why it was unsafe)"

RC=$(printf -- '--- a/x.md\n+++ b/x.md\n+[CRITICAL] drifted content unreadable — classify conservatively\n' | run_classify)
assert_eq "10" "$RC" "unreadable-body marker forces the guarded route, never the auto-PR one"

print_results
