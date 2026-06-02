#!/usr/bin/env bash

# #3274 — Regression guard: the brand-workshop flow must commit the .pen design
# source to the worktree branch immediately after the first save (before the
# review/iteration loop), so a destructive open_document wipe is recoverable via
# `git checkout`. The committed source must live under the canonical
# knowledge-base/product/design/ path (audit-reachable), never an app tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORKSHOP="$REPO_ROOT/plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md"

echo "=== brand-workshop .pen commit-after-save guard ==="
echo ""

assert_file_exists "$WORKSHOP" "brand-workshop reference exists"

# AC5 — commit-after-first-save instruction for the .pen is present.
set +e
grep -qiE "git add.*\.pen|commit.*\.pen|commit the .pen" "$WORKSHOP"
rc=$?
set -e
assert_eq "0" "$rc" "workshop commits the .pen source after first save"

# Recover-from-wipe rationale references #3274 / open_document / recover.
set +e
grep -qiE "recover-from-wipe|git checkout -- |#3274" "$WORKSHOP"
rc=$?
set -e
assert_eq "0" "$rc" "commit instruction names the recover-from-wipe rationale"

# AC6 — committed .pen must be under the canonical path; rationale is audit
# reachability, NOT gitignore.
set +e
grep -q "knowledge-base/product/design/" "$WORKSHOP"
rc=$?
set -e
assert_eq "0" "$rc" "committed .pen pinned to canonical knowledge-base/product/design/"

set +e
grep -qiE "audit reach|ux-audit" "$WORKSHOP"
rc=$?
set -e
assert_eq "0" "$rc" "rationale cites audit reachability"

# The new commit instruction must not justify itself with gitignore (AC6 — the
# .pen files are not gitignored anywhere in this repo).
set +e
grep -qi "gitignored" "$WORKSHOP"
rc=$?
set -e
assert_eq "1" "$rc" "commit rationale does not claim the .pen is gitignored"

print_results
