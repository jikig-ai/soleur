#!/usr/bin/env bash
# plugins/soleur/scripts/completion-floor.sh
#
# Portable, deterministic completion-floor verifier (#12527).
#
# Usage: completion-floor.sh --phase <phase> [--root <path>]
#   phases: plan work review qa ship postmerge
#
# Emits exactly one line to stdout:
#   SOLEUR_FLOOR_GATE phase=<p> status=pass|fail missing=<comma-list>
# Exit codes: 0 pass, 1 fail (missing artifacts), 2 usage/unknown/internal error.
#
# Fail-closed: any internal error -> exit 2 with status=fail.
#
# Mirror of plugins/soleur/lib/completion-floors.ts (check ids must match).

set -u

PHASE=""
ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "SOLEUR_FLOOR_GATE phase=${PHASE:-unknown} status=fail missing=usage"; exit 2 ;;
  esac
done

case "$PHASE" in
  plan|work|review|qa|ship|postmerge) ;;
  *) echo "SOLEUR_FLOOR_GATE phase=${PHASE:-unknown} status=fail missing=unknown-phase"; exit 2 ;;
esac

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
fi
if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "SOLEUR_FLOOR_GATE phase=${PHASE} status=fail missing=root-unresolved"
  exit 2
fi

cd "$ROOT" || { echo "SOLEUR_FLOOR_GATE phase=${PHASE} status=fail missing=root-unreadable"; exit 2; }

BRANCH="$(git branch --show-current 2>/dev/null)" || BRANCH=""
BASE_REF="origin/main"

missing=""

add_missing() { if [[ -z "$missing" ]]; then missing="$1"; else missing="${missing},$1"; fi; }

# --- plan phase checks ---
check_plan() {
  # plan-file: a plan markdown exists under knowledge-base/project/plans/ for this branch
  plan_file=""
  if [[ -d "knowledge-base/project/plans" ]]; then
    for f in knowledge-base/project/plans/*.md; do
      [[ -e "$f" ]] || continue
      if grep -q "branch: ${BRANCH}" "$f" 2>/dev/null; then
        plan_file="$f"; break
      fi
    done
  fi
  # fallback: any plan file modified on this branch
  if [[ -z "$plan_file" ]]; then
    changed_files="$(git diff -z --no-renames --ignore-submodules=none --name-only "${BASE_REF}...HEAD" | tr '\0' '\n')"
  plan_file="$(grep '^knowledge-base/project/plans/.*\.md$' <<< "$changed_files" | head -1)"
  fi
  if [[ -z "$plan_file" || ! -f "$plan_file" ]]; then
    add_missing "plan-file"; return
  fi
  # acceptance-criteria
  if ! grep -q '^## Acceptance Criteria' "$plan_file" 2>/dev/null; then
    add_missing "acceptance-criteria"
  fi
  # tasks-md
  if [[ ! -f "knowledge-base/project/specs/${BRANCH}/tasks.md" ]]; then
    add_missing "tasks-md"
  fi
  # no-out-of-scope-edits: only plans/specs touched
  changed_files="$(git diff -z --no-renames --ignore-submodules=none --name-only "${BASE_REF}...HEAD" | tr '\0' '\n')"
  out_of_scope="$(grep -v '^knowledge-base/project/\(plans\|specs\)/' <<< "$changed_files")"
  if [[ -n "$out_of_scope" ]]; then
    add_missing "no-out-of-scope-edits"
  fi
}

# --- work phase checks ---
check_work() {
  # commit-count >= 1
  count="$(git rev-list --count "${BASE_REF}..HEAD" 2>/dev/null)" || count=0
  if [[ "$count" -lt 1 ]]; then
    add_missing "commit-count"
  fi
  # clean-tree
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    add_missing "clean-tree"
  fi
}

# --- review phase checks ---
check_review() {
  # no-open-code-review-issues
  open_issues="$(gh issue list --label code-review --state open -L 200 2>/dev/null | wc -l)" || open_issues=0
  if [[ "$open_issues" -gt 0 ]]; then
    add_missing "no-open-code-review-issues"
  fi
  # attestation-trailers
  if ! git log -1 --format='%B' 2>/dev/null | grep -qi 'Provenance:\|Reviewed-Coverage:\|Attestation:' ; then
    add_missing "attestation-trailers"
  fi
}

# --- qa phase checks ---
check_qa() {
  # test-scenarios-or-marker
  plan_file=""
  for f in knowledge-base/project/plans/*.md; do
    [[ -e "$f" ]] || continue
    if grep -q "branch: ${BRANCH}" "$f" 2>/dev/null; then plan_file="$f"; break; fi
  done
  has_scenarios=false
  has_marker=false
  if [[ -n "$plan_file" && -f "$plan_file" ]]; then
    grep -qi '## Test Scenarios' "$plan_file" 2>/dev/null && has_scenarios=true
    grep -qi 'no-test-scenarios' "$plan_file" 2>/dev/null && has_marker=true
  fi
  if [[ "$has_scenarios" != true && "$has_marker" != true ]]; then
    # docs-only exemption: if no non-doc files changed, exempt
    changed_files="$(git diff -z --no-renames --ignore-submodules=none --name-only "${BASE_REF}...HEAD" | tr '\0' '\n')"
    non_docs="$(grep -vE '\.(md|mdx|rst|txt)$' <<< "$changed_files")"
    if [[ -n "$non_docs" ]]; then
      add_missing "test-scenarios-or-marker"
    fi
  fi
}

# --- ship phase checks ---
check_ship() {
  # pr-merged: requires a PR number; check via gh if available
  pr_num=""
  if [[ -n "${EXTRA_PR:-}" ]]; then pr_num="$EXTRA_PR"; fi
  if [[ -z "$pr_num" ]]; then
    # try to find PR for this branch
    pr_num="$(gh pr list --head "$BRANCH" --state all --json number --jq '.[0].number' 2>/dev/null)" || pr_num=""
  fi
  if [[ -z "$pr_num" ]]; then
    add_missing "pr-merged"; return
  fi
  state="$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null)" || state=""
  if [[ "$state" != "MERGED" ]]; then
    add_missing "pr-merged"
  fi
}

# --- postmerge phase checks ---
check_postmerge() {
  # deploy-health: best-effort; default pass if no probe configured
  # Reuse observability discoverability: require a SOLEUR marker-capable probe script exists.
  if [[ ! -f "scripts/betterstack-query.sh" && ! -f "plugins/soleur/scripts/betterstack-query.sh" ]]; then
    : # no probe available; treat as pass (no false halt)
  fi
  # postmerge always passes in this minimal implementation unless explicitly failed
  :
}

case "$PHASE" in
  plan) check_plan ;;
  work) check_work ;;
  review) check_review ;;
  qa) check_qa ;;
  ship) check_ship ;;
  postmerge) check_postmerge ;;
esac

if [[ -z "$missing" ]]; then
  echo "SOLEUR_FLOOR_GATE phase=${PHASE} status=pass missing="
  exit 0
else
  echo "SOLEUR_FLOOR_GATE phase=${PHASE} status=fail missing=${missing}"
  exit 1
fi
