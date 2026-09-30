#!/usr/bin/env bash
# Sentinel: BACKSTOP_REVISION bump on memory-backstop hook changes (Guard 1,
# #9239).
#
# .claude/hooks/memory-backstop.sh is dispatched through a resolver shim
# (.claude/hooks/memory-backstop-resolve.sh) that orders candidate copies —
# the checkout, the managed path ${XDG_DATA_HOME:-~/.local/share}/soleur/hooks/,
# and both plugin caches — by the hook's BACKSTOP_REVISION marker. That marker
# is the ONLY ordering signal, and bumping it is human discipline: an un-bumped
# behavioral change never wins resolution over a same-or-newer installed copy,
# so the fix merges on main while stale-checkout sessions keep running the old
# protection. This gate makes a missing bump a required-check failure.
#
# Contract (knowledge-base/project/plans/2026-09-29-fix-backstop-hook-version-resolution-plan.md,
# Guard 1): when the merge-base diff touches the hook, the BACKSTOP_REVISION
# value must DIFFER vs merge-base. A re-set to the SAME value fails too — the
# resolver compares integers, not diff lines, so a no-op re-write of the line
# is no bump at all.
#
# pr-quality-guards.yml invokes this unconditionally — deliberately NO path
# filter on the step, so a deleted filter can never darken the gate. When the
# hook is untouched the script prints an explicit NO-OP verdict and exits 0.
#
# Fails closed: exit 1 on any check trip. Stdout/stderr name the failing
# condition so CI logs surface the specific drift.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

HOOK_PATH=.claude/hooks/memory-backstop.sh
# GITHUB_BASE_REF is ambient on pull_request runs; merge_group and local runs
# fall back to main — the same base the enforce job diffs against.
BASE_REF="${GITHUB_BASE_REF:-main}"

# The three-dot merge-base diff needs the base reachable locally, and a
# shallow fetch can leave the merge-base unreachable — the same reason the
# enforce job fetches its BASE_REF first (pr-quality-guards.yml).
git fetch --quiet --no-tags origin "$BASE_REF"
mb=$(git merge-base "origin/${BASE_REF}" HEAD)

changed_files=$(git diff --name-only "${mb}...HEAD")
# Here-string, not a pipe: `producer | grep -q` fails open under pipefail when
# the producer still has unwritten data at grep's early exit (#6992).
if ! grep -Fxq "$HOOK_PATH" <<<"$changed_files"; then
  echo "NO-OP: ${HOOK_PATH} absent from the merge-base diff — revision-bump gate declines by design."
  exit 0
fi

# The per-file diff is captured to a TEMPFILE before any grep sees it: the
# `git diff ... | grep -q` shape misfires under set -e + pipe-buffering (grep
# -q exits on first match, the producer eats SIGPIPE, pipefail reports the
# pipeline as failed) — the #3550 tempfile-shape learning.
DIFF_TMP=$(mktemp)
trap 'rm -f "$DIFF_TMP"' EXIT
git diff "${mb}...HEAD" -- "$HOOK_PATH" > "$DIFF_TMP"

# Effective marker value on each side, extracted exactly the way the resolver
# reads it: the first `BACKSTOP_REVISION=<digits>` match in the file — grep,
# never `source` (a candidate's text is unverified code, ADR-156 posture).
# Comparing VALUES, not line presence, is what makes a same-value re-set RED.
rev_at() { # <rev>:<path> -> first BACKSTOP_REVISION value; empty when absent
  git show "$1" 2>/dev/null | grep -oEm1 'BACKSTOP_REVISION=[0-9]+' | cut -d= -f2 || true
}
old_rev=$(rev_at "${mb}:${HOOK_PATH}")
new_rev=$(rev_at "HEAD:${HOOK_PATH}")

if [ -z "$new_rev" ]; then
  echo "::error::${HOOK_PATH} is in the PR diff but carries no BACKSTOP_REVISION=<n> marker at HEAD." >&2
  echo "  (marker stripped, or the file was deleted — the resolver cannot order a markerless copy)" >&2
  grep -nE 'BACKSTOP_REVISION' "$DIFF_TMP" >&2 || true
  exit 1
fi

if [ "$new_rev" = "$old_rev" ]; then
  echo "::error::${HOOK_PATH} changed but BACKSTOP_REVISION is still ${new_rev} — unchanged vs merge-base ${mb}." >&2
  echo "  Bump BACKSTOP_REVISION in the hook: the resolver orders installed copies by it, so an" >&2
  echo "  un-bumped change is undeliverable to stale-checkout sessions (#9239, Guard 1)." >&2
  exit 1
fi

echo "BACKSTOP_REVISION bump verified: ${old_rev:-<none>} -> ${new_rev} for ${HOOK_PATH}."
