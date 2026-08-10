#!/usr/bin/env bash
# Are this branch's knowledge-base artifacts archived, or still at their live paths?
#
# WHY THIS EXISTS
# ---------------
# `compound`'s automatic consolidation is the ONLY mechanism that durably archives a
# feature's spec dir and plan: it does `git mv` + commit on the feature branch, so the
# move rides the PR into main.
#
# `cleanup-merged` does NOT. Its archive step is scoped to legacy pre-#2815 worktrees
# (specs at the bare root), guards on a directory that does not exist for the modern
# layout, runs BEFORE it updates main, and — even when it does run — is a plain `mv`
# that produces no commit. See ship/SKILL.md Phase 7 Step 4.
#
# So if compound's consolidation is skipped or deferred, archival does not happen at
# all, and completing it later costs a follow-up PR. That is not hypothetical: PR #7373
# shipped with its spec dir and plan unarchived for exactly this reason (the phases were
# driven by hand and the consolidation never fired), and PR #7240 shipped the same way
# on the strength of a since-corrected claim that cleanup-merged would collect it.
#
# Prose did not prevent either. This is the mechanical check.
#
# USAGE
#   bash scripts/check-kb-artifacts-archived.sh            # current branch
#   bash scripts/check-kb-artifacts-archived.sh <branch>   # explicit
#
# EXIT
#   0  clean — nothing at a live path (or not a feature branch, or opted out)
#   1  live-path artifacts found; each is named on stderr
#   2  usage / environment error
#
# CARVE-OUT
#   `decision-challenges.md` may legitimately remain at its live path until ship Phase 6
#   step 2.5 has rendered it into the PR body (ADR-084). If it is the ONLY survivor the
#   check passes and says so — archiving it belongs to the same pass that renders it.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "check-kb-artifacts-archived: not inside a git work tree" >&2; exit 2; }
cd "$REPO_ROOT" || exit 2

BRANCH="${1:-}"
if [[ -z "$BRANCH" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo "check-kb-artifacts-archived: cannot resolve branch" >&2; exit 2; }
fi

# Fail-open on anything that is not a feature/fix branch: main, detached HEAD, release
# branches, and ad-hoc branches have no per-feature artifact convention to enforce.
case "$BRANCH" in
  feat-*|feat/*|fix-*|fix/*) ;;
  *) echo "check-kb-artifacts-archived: '$BRANCH' is not a feature branch — skipping."; exit 0 ;;
esac

# Slug = branch minus the workflow prefix. Mirrors compound's consolidation discovery.
SLUG="${BRANCH#feat-}"; SLUG="${SLUG#feat/}"; SLUG="${SLUG#fix-}"; SLUG="${SLUG#fix/}"

LIVE=()
CARVED=()

# 1) Spec directory at its live path.
SPEC_DIR="knowledge-base/project/specs/$BRANCH"
if [[ -d "$SPEC_DIR" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$(basename "$f")" == "decision-challenges.md" ]]; then
      CARVED+=("$f")
    else
      LIVE+=("$f")
    fi
  done < <(find "$SPEC_DIR" -type f 2>/dev/null)
fi

# 2) Plans / brainstorms this branch INTRODUCED, still at a live path.
#
#    Primary signal is the branch's own diff, NOT a slug glob. Plans are named by topic
#    and date while branches are named by feature, so the two routinely do not share a
#    substring — measured: branch `feat-one-shot-worktree-create-lease` (slug
#    `one-shot-worktree-create-lease`) vs plan
#    `2026-08-09-fix-worktree-create-acquires-lease-plan.md`, which share no common
#    substring the glob can key on. A slug-only check silently passed that plan, i.e. it
#    would have caught two thirds of the very PR it was written for.
seen_plan=""
BASE=$(git merge-base HEAD origin/main 2>/dev/null || true)
if [[ -n "$BASE" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in */archive/*) continue ;; esac
    [[ -f "$f" ]] || continue          # moved/deleted since: already archived
    LIVE+=("$f"); seen_plan="${seen_plan}|${f}"
  done < <(git diff --name-only --diff-filter=A "$BASE"..HEAD \
             -- knowledge-base/project/plans knowledge-base/project/brainstorms 2>/dev/null)
fi

#    Fallback slug glob: catches an artifact this branch did not add but still owns
#    (e.g. a plan authored on an earlier branch and carried forward). Deduped against
#    the diff-derived set above.
for dir in knowledge-base/project/plans knowledge-base/project/brainstorms; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' f; do
    case "$f" in */archive/*) continue ;; esac
    case "$seen_plan" in *"|$f") continue ;; *"|$f"*) continue ;; esac
    LIVE+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f -name "*${SLUG}*" -print0 2>/dev/null)
done

if (( ${#LIVE[@]} == 0 )); then
  if (( ${#CARVED[@]} > 0 )); then
    echo "check-kb-artifacts-archived: OK — only the Phase-6 carve-out remains (${CARVED[*]})."
  else
    echo "check-kb-artifacts-archived: OK — no live-path artifacts for '$BRANCH'."
  fi
  exit 0
fi

{
  echo "check-kb-artifacts-archived: ${#LIVE[@]} knowledge-base artifact(s) still at a LIVE path for '$BRANCH':"
  for f in "${LIVE[@]}"; do echo "    $f"; done
  echo
  echo "  cleanup-merged will NOT archive these after merge — compound's consolidation is the"
  echo "  only mechanism that commits the move, and it has not run on this branch."
  echo
  echo "  Fix (in THIS PR, so the move rides the merge):"
  echo "    bash \${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/archive-kb/scripts/archive-kb.sh"
  echo "  or archive by hand:"
  echo "    TS=\$(date -u +%Y%m%d-%H%M%S)"
  echo "    git mv $SPEC_DIR knowledge-base/project/specs/archive/\${TS}-$BRANCH"
  echo "    git mv <plan> knowledge-base/project/plans/archive/\${TS}-<plan-basename>"
  echo
  echo "  Deliberately keeping them live? Add to the PR body:"
  echo "    <!-- gate-override: kb-archival --> <one-line reason>"
} >&2
exit 1
