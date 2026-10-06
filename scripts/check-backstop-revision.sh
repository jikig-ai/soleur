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
# value must STRICTLY INCREASE vs merge-base. A re-set to the same value fails
# and so does a DECREASE — the resolver orders installed copies by `>`, so a
# lower marker merges green while the change is undeliverable to every host.
#
# The watched set is the hook plus the lib file it sources opportunistically
# (lib/log-rotation.sh — part of the executed protection tree but not a
# separate marker carrier: a lib-only edit must still bump the hook's marker).
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
# The marker's carrier — the value compared below is always read from this
# file. WATCHED also covers the sourced lib: a behavioural change there is
# part of the executed protection tree, so it must ride a hook marker bump
# (the lib carries no marker of its own).
WATCHED_PATHS=(
  .claude/hooks/memory-backstop.sh
  .claude/hooks/lib/log-rotation.sh
)
# GITHUB_BASE_REF is ambient on pull_request runs; merge_group and local runs
# fall back to main — the same base the enforce job diffs against.
BASE_REF="${GITHUB_BASE_REF:-main}"

# Refname-shape whitelist BEFORE any git call sees it: a base ref is a branch
# name, and the fetch below deliberately spells the FULL refspec rather than
# passing "$BASE_REF" as a positional — a dash-leading branch name is a VALID
# ref (check-ref-format accepts refs/heads/--x) and would parse as an option
# to git fetch (PR #9241 security review). The literal refs/heads/ prefix in
# the refspec makes option confusion impossible.
if [[ ! "$BASE_REF" =~ ^[A-Za-z0-9/_.-]+$ ]]; then
  echo "::error::unusual GITHUB_BASE_REF '${BASE_REF}' — refusing to feed it to git." >&2
  exit 1
fi

# The three-dot merge-base diff needs the base reachable locally, and a
# shallow fetch can leave the merge-base unreachable — the same reason the
# enforce job fetches its BASE_REF first (pr-quality-guards.yml). --no-tags:
# this script only needs commits; fetching tags would put a same-repo write
# surface on the tag namespace in the battery-tag census.
git fetch --quiet --no-tags origin "+refs/heads/${BASE_REF}:refs/remotes/origin/${BASE_REF}"
mb=$(git merge-base "origin/${BASE_REF}" HEAD)

changed_files=$(git diff --name-only "${mb}...HEAD")
# Here-string, not a pipe: `producer | grep -q` fails open under pipefail when
# the producer still has unwritten data at grep's early exit (#6992).
watched_hit=""
for wp in "${WATCHED_PATHS[@]}"; do
  if grep -Fxq "$wp" <<<"$changed_files"; then watched_hit="$wp"; break; fi
done
if [[ -z "$watched_hit" ]]; then
  echo "NO-OP: no watched file (${WATCHED_PATHS[*]}) in the merge-base diff — revision-bump gate declines by design."
  exit 0
fi

# The per-file diff is captured to a TEMPFILE before any grep sees it: the
# `git diff ... | grep -q` shape misfires under set -e + pipe-buffering (grep
# -q exits on first match, the producer eats SIGPIPE, pipefail reports the
# pipeline as failed) — the #3550 tempfile-shape learning. The explicit
# template keeps `mktemp` portable to BSD (bare `mktemp` is GNU-only).
DIFF_TMP=$(mktemp "${TMPDIR:-/tmp}/backstop-revision.XXXXXXXX")
trap 'rm -f "$DIFF_TMP"' EXIT
git diff "${mb}...HEAD" -- "$HOOK_PATH" > "$DIFF_TMP"

# Effective marker value on each side, extracted exactly the way the resolver
# reads it: the first LINE-ANCHORED `BACKSTOP_REVISION=<digits>` match in the
# file — grep, never `source` (a candidate's text is unverified code, ADR-156
# posture). The anchor matches candidate_revision() in
# memory-backstop-resolve.sh — the canonical parse — so a `#`-prefixed decoy
# line cannot satisfy this gate while failing the resolver. Comparing VALUES,
# not line presence, is what makes a same-value re-set RED.
rev_at() { # <rev>:<path> -> first BACKSTOP_REVISION value; empty when absent
  grep -oEm1 '^[[:space:]]*(readonly[[:space:]]+)?BACKSTOP_REVISION=[0-9]+' < <(git show "$1" 2>/dev/null) \
    | cut -d= -f2 || true
}
old_rev=$(rev_at "${mb}:${HOOK_PATH}")
new_rev=$(rev_at "HEAD:${HOOK_PATH}")

if [ -z "$new_rev" ]; then
  echo "::error::${HOOK_PATH} is in the PR diff but carries no BACKSTOP_REVISION=<n> marker at HEAD." >&2
  echo "  (marker stripped, or the file was deleted — the resolver cannot order a markerless copy)" >&2
  grep -nE 'BACKSTOP_REVISION' "$DIFF_TMP" >&2 || true
  exit 1
fi

# Strictly-greater, not merely different: the resolver orders by `>`, so a
# DECREASED marker merges green yet can never win resolution anywhere — the
# same undeliverable outcome as no bump (review finding, PR #9241).
if [ -n "$old_rev" ] && [ "$new_rev" -le "$old_rev" ]; then
  echo "::error::${HOOK_PATH} changed but BACKSTOP_REVISION is ${new_rev} — not above merge-base ${mb}'s ${old_rev}." >&2
  echo "  Bump BACKSTOP_REVISION ABOVE the base value in the hook: the resolver orders installed" >&2
  echo "  copies by it, so a same-or-lower change is undeliverable to stale-checkout sessions" >&2
  echo "  (#9239, Guard 1)." >&2
  exit 1
fi

echo "BACKSTOP_REVISION bump verified: ${old_rev:-<none>} -> ${new_rev} for ${HOOK_PATH}."
