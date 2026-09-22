#!/usr/bin/env bash
# ci-e2e-classify.sh — is this change-set worth running the e2e job for? (#8450)
#
# Usage:
#   <git-diff --name-status rows> | ci-e2e-classify.sh <event-name>
#   ci-e2e-classify.sh --enum-failed
#
# Output: a single line, `true` (run the heavy e2e steps) or `false` (skip them).
#
# CONTRACT — fail-closed allowlist, not a denylist:
#   * `pull_request` emits `false` ONLY when the changed-file list is non-empty
#     and EVERY row is allowlisted:
#       - `knowledge-base/**`        (docs/plans/specs/learnings — no app code)
#       - root-level `*.md`          (a path containing `/` is NOT root-level)
#   * `docs/**` is deliberately NOT safe: the repo-root `docs/` tree is only
#     `docs/legal/**`, which is app-coupled via the pinned document SHA-256s in
#     apps/web-platform/lib/legal/legal-doc-shas.ts.
#   * Only statuses M (modified) and A (added) may skip. Every other status —
#     deletion D, rename R, copy C, typechange T (a file's KIND changed, e.g.
#     file→symlink), unmerged U, … — emits `true`: an unresolvable or
#     mutating changeset is indistinguishable from unsafe. Bare path-only
#     lines (no status column) are treated as modified.
#   * Any event other than `pull_request` (push, merge_group,
#     workflow_dispatch, …) emits `true` unconditionally — only a PR diff has
#     a trustworthy base.
#   * `--enum-failed` is the verdict the calling step uses when `git diff`
#     itself failed: emits `true`, exit 0.
#   * Empty input emits `true`.
#   * Missing/unknown argv exits NON-ZERO — a genuinely broken classifier reds
#     the required e2e job rather than fabricating a green skip.
set -uo pipefail

emit() { printf '%s\n' "$1"; exit 0; }

event="${1:-}"
[ $# -ge 1 ] || { echo "usage: ci-e2e-classify.sh <event-name>|--enum-failed" >&2; exit 2; }

case "$event" in
  --enum-failed) emit true ;;
  pull_request) ;;
  push|merge_group|workflow_dispatch|workflow_run|schedule|release|workflow_call)
    emit true ;;
  *)
    echo "ci-e2e-classify: unknown event '$event' — refusing to guess" >&2
    exit 2 ;;
esac

saw_any=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  saw_any=1

  if [[ "$line" == *[[:space:]]* ]]; then
    status="${line%%[[:space:]]*}"
    rest="${line#"$status"}"
    path="${rest#"${rest%%[![:space:]]*}"}"   # lstrip whitespace
  else
    status="M"                               # bare path — treated as modified
    path="$line"
  fi

  case "$status" in
    M|A) ;;
    *) emit true ;;                          # D/R/C/T/U/… — mutating or unresolvable
  esac

  case "$path" in
    knowledge-base/*) ;;
    *.md)
      case "$path" in */*) emit true ;; esac ;;   # *.md only safe at repo root
    *) emit true ;;
  esac
done

[ "$saw_any" -eq 1 ] || emit true
emit false
