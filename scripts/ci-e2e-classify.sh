#!/usr/bin/env bash
# ci-e2e-classify.sh — is this change-set worth running the e2e job for? (#8450)
#
# Usage:
#   <git-diff --raw rows> | ci-e2e-classify.sh <event-name>
#   ci-e2e-classify.sh --enum-failed
#
# Output: a single line, `true` (run the heavy e2e steps) or `false` (skip them).
#
# CONTRACT — fail-closed allowlist, not a denylist:
#   * `pull_request` emits `false` ONLY when the changed-file list is non-empty
#     and EVERY row is a well-formed `git diff --raw` row
#     (`:OLDMODE NEWMODE OLDSHA NEWSHA STATUS<TAB>path`, lower-case hex) that
#     passes the mode gate below AND names an allowlisted path:
#       - `knowledge-base/**`        (docs/plans/specs/learnings — no app code)
#       - root-level `*.md`          (a path containing `/` is NOT root-level)
#   * MODE GATE (#10416). `--name-status` carried no file mode, so an added
#     symlink, a gitlink or an exec-bit flip on a `.md` read as markdown. Only
#     two shapes may skip: status A with old mode 000000 and new mode 100644,
#     and status M with old and new mode both 100644. Every other mode and
#     status (100755, 120000, 160000, a mode-changing M, an A with a non-null
#     old mode) emits `true`. This is deliberately STRICTER than the PR B
#     driver's allowlist in scripts/ci-pr-selection.sh, which also admits
#     100755: the driver has later stages, a classifier skip has none, and the
#     shard-totality battery's census reads shebang files, so an executable
#     `.md` can be a subject. Revisit before any widening of a doc-only
#     allowlist, or if this skip is ever used for a context other than `e2e`
#     or a non-required job.
#   * `docs/**` is deliberately NOT safe: the repo-root `docs/` tree is only
#     `docs/legal/**`, which is app-coupled via the pinned document SHA-256s in
#     apps/web-platform/lib/legal/legal-doc-shas.ts.
#   * Only statuses M (modified) and A (added) may skip. Every other status —
#     deletion D, rename R, copy C, typechange T (a file's KIND changed, e.g.
#     file→symlink), unmerged U, … — emits `true`: an unresolvable or
#     mutating changeset is indistinguishable from unsafe. A row that does
#     not match the raw-row grammar (legacy `--name-status`, a bare path, a
#     rename's second path, upper-case hex) also emits `true`: the legacy
#     "bare path is modified" rule is gone.
#   * Any event other than `pull_request` (push, merge_group,
#     workflow_dispatch, …) emits `true` unconditionally — only a PR diff has
#     a trustworthy base.
#   * `--enum-failed` is the verdict the calling step uses when `git diff`
#     itself failed: emits `true`, exit 0.
#   * Empty input emits `true`.
#   * Missing/unknown argv exits NON-ZERO — a genuinely broken classifier reds
#     the required e2e job rather than fabricating a green skip.
#
# The row-parse block below is duplicated byte for byte in
# scripts/ci-shard-totality-classify.sh (CI runs each classifier from a base-ref
# `git show` copy where scripts/lib does not exist, so there is no shared
# helper); plugins/soleur/test/ci-shard-totality-skip.test.sh pins the parity.
# Reproduce a verdict locally:
#   git diff --raw --no-color --no-ext-diff origin/main...HEAD | bash scripts/ci-e2e-classify.sh pull_request
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

  # BEGIN mode-aware-row-parse
  tab=$'\t'
  row_re="^:([0-7]{6}) ([0-7]{6}) [0-9a-f]+ [0-9a-f]+ ([A-Z][0-9]*)${tab}([^${tab}]+)$"
  [[ "$line" =~ $row_re ]] || emit true                        # GUARD:ROW-GRAMMAR
  om="${BASH_REMATCH[1]}"; nm="${BASH_REMATCH[2]}"; status="${BASH_REMATCH[3]}"; path="${BASH_REMATCH[4]}"
  case "$status" in
    A) [ "$om" = 000000 ] || emit true ;;                      # GUARD:MODE-OLD-ADD
    M) [ "$om" = 100644 ] || emit true ;;                      # GUARD:MODE-OLD-MOD
    *) emit true ;;                                            # GUARD:STATUS
  esac
  [ "$nm" = 100644 ] || emit true                              # GUARD:MODE-NEW
  # END mode-aware-row-parse

  case "$path" in
    knowledge-base/*) ;;
    *.md)
      case "$path" in */*) emit true ;; esac ;;   # *.md only safe at repo root
    *) emit true ;;
  esac
done

[ "$saw_any" -eq 1 ] || emit true
emit false
