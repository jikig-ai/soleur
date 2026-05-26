#!/usr/bin/env bash
# sentinel-pr.sh — automated Phase 8 sentinel PRs (closes #3908).
#
# Verifies the live cla-evidence sidecar end-to-end by opening one or two
# synthetic PRs and polling `inspect-evidence.sh by-pr <N>` against R2 for
# the resulting evidence record. Modes:
#   human   — opens a "human signer" sentinel (operator's GitHub identity).
#             The upstream CLA action fires on PR-open and writes the
#             evidence record to R2; the sidecar polls inspect-evidence.sh.
#   bypass  — opens a sentinel labeled `bypass-allowlist` so the action's
#             allowlist-bypass path fires; the sidecar writes the bypass
#             record under allowlist/.
#   both    — runs human then bypass.
#
# Each sentinel:
#   1. Touches a single docs-only marker file under
#      apps/cla-evidence/.sentinel-markers/<mode>-<ts>.md (low blast radius;
#      directory is for synthetic sentinel markers, distinct from real
#      learnings under knowledge-base/project/learnings/).
#   2. Pushes a branch + opens a PR labeled `cla-sentinel` (+ `bypass-allowlist`
#      for bypass mode). The CI workflow `cla-evidence.yml` runs and writes
#      to R2 in the normal flow.
#   3. Polls `inspect-evidence.sh by-pr <N>` for up to 5 minutes (30 retries
#      at 10s intervals). Exit code 0 = record found; non-zero = timeout
#      (rc=2) or schema mismatch (rc=3) — the latter short-circuits the
#      poll loop, since inspect-evidence.sh exits 3 only on a genuine
#      schema_version regression that polling cannot resolve.
#   4. Auto-closes the PR with --delete-branch to avoid history pollution.
#
# Pre-flight: creates the `cla-sentinel` label if missing (idempotent via
# `--force`). The `bypass-allowlist` label is expected to exist (configured
# by the upstream contributor-assistant action). Also enforces a clean
# working tree and `cd`s to the repo root so the branch-creation block
# does not leak uncommitted changes from the caller's cwd.
#
# Dry-run: `SENTINEL_DRY_RUN=1 sentinel-pr.sh <mode>` stubs `gh pr create`
# and `inspect-evidence.sh by-pr` for testing.
#
# Exit codes:
#   0  — all requested sentinels passed
#   2  — at least one inspect-evidence poll timed out
#   3  — pre-flight failure (gh not authed, label create failed, dirty
#        working tree, schema_version regression in inspect-evidence.sh)
#   64 — usage error

set -euo pipefail

usage() {
  cat >&2 <<USAGE
Usage:
  sentinel-pr.sh {human|bypass|both}
  SENTINEL_DRY_RUN=1 sentinel-pr.sh {human|bypass|both}
USAGE
  exit 64
}

mode="${1:-}"
case "$mode" in
  human|bypass|both) ;;
  "") usage ;;
  *)  echo "::error::unknown mode: $mode" >&2; usage ;;
esac
# Defense-in-depth against future enum widening — the case above already
# constrains $mode, this regex catches refactors that relax the case.
[[ "$mode" =~ ^(human|bypass|both)$ ]] || { echo "::error::internal: mode passed case but failed regex check" >&2; exit 64; }

DRY_RUN="${SENTINEL_DRY_RUN:-0}"
REPO="${SENTINEL_REPO:-jikig-ai/soleur}"
BASE_BRANCH="${SENTINEL_BASE_BRANCH:-main}"
POLL_RETRIES="${SENTINEL_POLL_RETRIES:-30}"
POLL_INTERVAL="${SENTINEL_POLL_INTERVAL:-10}"

# All progress logs go to stderr so $(open_sentinel ...) captures only the
# PR number on stdout. red is already stderr-only; green/yellow are routed
# to stderr to make the function's return channel safe by construction.
red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$*" >&2; }
yellow() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
step()   { printf '\n→ %s\n' "$*" >&2; }

# ─────────────────────────────────────────────────────────────────────────
# Pre-flight: gh auth + cwd + clean tree + label creation
# ─────────────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" != "1" ]]; then
  command -v gh >/dev/null || { red "missing gh on PATH"; exit 3; }
  command -v git >/dev/null || { red "missing git on PATH"; exit 3; }
  gh auth status >/dev/null 2>&1 || { red "gh not authenticated"; exit 3; }

  # cd to repo root so branch creation is deterministic regardless of caller cwd.
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { red "not inside a git repository"; exit 3; }
  cd "$repo_root"

  # Require clean working tree — branch creation + commit + push would
  # otherwise carry over uncommitted operator state.
  if [[ -n "$(git status --porcelain)" ]]; then
    red "working tree not clean; sentinel-pr.sh requires a clean state to open synthetic PRs"
    exit 3
  fi

  gh label create cla-sentinel \
    --description "Synthetic PR opened by sentinel-pr.sh to verify cla-evidence end-to-end" \
    --color "0E8A16" \
    --force \
    --repo "$REPO" >/dev/null 2>&1 \
    || { red "failed to create/refresh cla-sentinel label"; exit 3; }

  # Capture starting HEAD so we can restore on EXIT even if a step fails.
  START_REF=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse HEAD)
  trap 'git checkout -q "$START_REF" 2>/dev/null || true' EXIT
fi

# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

# poll_inspect <pr-number> — returns 0 if the record lands within the poll
# window, 2 on timeout, 3 on schema_version regression (inspect-evidence
# exits 3 deterministically; polling cannot resolve it). In dry-run mode,
# succeeds on the first call.
poll_inspect() {
  local pr="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    green "  [dry-run] inspect-evidence.sh by-pr $pr → OK"
    return 0
  fi
  local i rc
  for ((i = 1; i <= POLL_RETRIES; i++)); do
    set +e
    bash "$(dirname "${BASH_SOURCE[0]}")/inspect-evidence.sh" by-pr "$pr" >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      green "  inspect-evidence.sh by-pr $pr → OK (after $i tries)"
      return 0
    fi
    if [[ "$rc" -eq 3 ]]; then
      red "  inspect-evidence.sh reported schema_version regression (exit 3); polling cannot resolve"
      return 3
    fi
    sleep "$POLL_INTERVAL"
  done
  red "  inspect-evidence.sh by-pr $pr timed out after $((POLL_RETRIES * POLL_INTERVAL))s"
  return 2
}

# open_sentinel <mode> — opens a sentinel PR; prints its number on stdout.
# In dry-run mode, prints a fake PR number 999999.
open_sentinel() {
  local m="$1"
  local ts marker_path branch pr_num labels
  ts=$(date -u +%Y%m%d%H%M%S)
  marker_path="apps/cla-evidence/.sentinel-markers/${m}-${ts}.md"
  branch="cla-sentinel/${m}-${ts}"
  labels="cla-sentinel"
  [[ "$m" == "bypass" ]] && labels="cla-sentinel,bypass-allowlist"

  if [[ "$DRY_RUN" == "1" ]]; then
    green "  [dry-run] would open $m sentinel PR (branch=$branch labels=$labels)"
    echo 999999
    return 0
  fi

  # On any failure between branch-push and PR-number capture, attempt
  # best-effort cleanup of orphan branch and any partially-created PR.
  local cleanup_branch="$branch"
  trap '_cleanup_partial_sentinel "$cleanup_branch"' ERR

  # Write a small marker file with provenance info so the PR has a single
  # tracked file; auto-closed after R2 verification.
  mkdir -p "$(dirname "$marker_path")"
  cat > "$marker_path" <<EOF
# cla-sentinel marker: $m / $ts

Auto-generated by \`apps/cla-evidence/scripts/sentinel-pr.sh\`.
Verifies the cla-evidence sidecar writes to R2 for this synthetic PR.
PR will auto-close after R2 verification.
EOF

  git checkout -b "$branch" "origin/${BASE_BRANCH}" >/dev/null 2>&1
  git add "$marker_path"
  git commit -m "chore(cla-evidence): ${m} sentinel ${ts}" >/dev/null
  git push -u origin "$branch" >/dev/null 2>&1
  pr_num=$(gh pr create \
    --repo "$REPO" \
    --base "$BASE_BRANCH" \
    --head "$branch" \
    --title "chore(cla-evidence): ${m} sentinel ${ts}" \
    --body "Sentinel PR (mode=${m}) for cla-evidence #3908. Auto-closes after R2 verification." \
    --label "$labels" \
    | awk -F/ '/pull\// {print $NF; exit}')
  trap - ERR
  if [[ -z "$pr_num" ]]; then
    _cleanup_partial_sentinel "$branch"
    red "gh pr create returned no PR number"
    return 3
  fi
  echo "$pr_num"
}

# _cleanup_partial_sentinel <branch> — best-effort orphan cleanup. Called
# on ERR trap inside open_sentinel and explicitly on PR-number parse fail.
_cleanup_partial_sentinel() {
  local b="$1" pr
  # Close any PR that already opened against this branch.
  pr=$(gh pr list --repo "$REPO" --head "$b" --json number --jq '.[0].number' 2>/dev/null)
  if [[ -n "$pr" ]]; then
    gh pr close "$pr" --repo "$REPO" --delete-branch --comment "Sentinel partial-open cleanup." >/dev/null 2>&1 || true
  else
    # No PR exists; try to delete the remote branch directly.
    git push origin --delete "$b" >/dev/null 2>&1 || true
  fi
}

# close_sentinel <pr-number>
close_sentinel() {
  local pr="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    green "  [dry-run] gh pr close $pr --delete-branch"
    return 0
  fi
  gh pr close "$pr" --repo "$REPO" --delete-branch --comment "Sentinel verification complete; closing." >/dev/null 2>&1 \
    || yellow "  gh pr close $pr returned non-zero (already closed?)"
}

# run_sentinel <mode>
run_sentinel() {
  local m="$1" pr rc=0
  step "Sentinel: $m"
  pr=$(open_sentinel "$m") || return $?
  green "  opened PR #$pr"
  poll_inspect "$pr" || rc=$?
  close_sentinel "$pr"
  return "$rc"
}

# ─────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────
overall=0
case "$mode" in
  human)  run_sentinel human  || overall=$? ;;
  bypass) run_sentinel bypass || overall=$? ;;
  both)
    run_sentinel human  || overall=$?
    run_sentinel bypass || overall=$?
    ;;
  *) overall=64 ;;
esac

if [[ "$overall" -eq 0 ]]; then
  green ""
  green "sentinel-pr.sh: all requested sentinels verified."
else
  red ""
  red "sentinel-pr.sh: at least one sentinel failed (rc=$overall)."
fi
exit "$overall"
