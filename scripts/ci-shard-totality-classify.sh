#!/usr/bin/env bash
# ci-shard-totality-classify.sh — is this change-set worth running the shard-totality mutation battery for? (#9729)
#
# Usage:
#   <git-diff --name-status rows> | ci-shard-totality-classify.sh <event-name>
#   ci-shard-totality-classify.sh --enum-failed
#
# Output: a single line, `true` (run the battery) or `false` (skip it).
#
# CONTRACT — fail-closed allowlist, never a denylist of "subject" paths. The battery mutates the runner, the
# shard tables and ci.yml and then runs guard suites over a census of `git ls-files`, so its subject set is open
# ended (a new declarer under any tree can matter). Skipping is therefore allowed for exactly one shape:
#   * `pull_request`, a non-empty changed-file list, and EVERY row is status M (modified) or A (added) AND its path
#     is a markdown file under `knowledge-base/` or at the repository root. A markdown file declares no suite and is
#     read by no census.
# Everything else runs: any other path (a `.sh`/`.py`/`.ts`/`.json` anywhere, including under `knowledge-base/`,
# where the census enumerates declarers), a deletion, rename, copy, typechange or unmerged row, a C-quoted path,
# an empty list, and every event other than `pull_request` (a push or a merge_group candidate is the full-battery
# authority, ADR-276). `--enum-failed` is the verdict the calling step uses when `git diff` itself failed: it emits
# `true`. Missing or unknown argv exits NON-ZERO so a broken classifier reds the job instead of fabricating a skip.
#
# Modelled on scripts/ci-e2e-classify.sh (#8450); the allowlist is deliberately narrower (markdown only), because
# knowledge-base/ also holds scripts the battery's census can see.
set -uo pipefail

emit() { printf '%s\n' "$1"; exit 0; }

event="${1:-}"
[ $# -ge 1 ] || { echo "usage: ci-shard-totality-classify.sh <event-name>|--enum-failed" >&2; exit 2; }

case "$event" in
  --enum-failed) emit true ;;
  pull_request) ;;
  push|merge_group|workflow_dispatch|workflow_run|schedule|release|workflow_call)
    emit true ;;
  *)
    echo "ci-shard-totality-classify: unknown event '$event' — refusing to guess" >&2
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
    knowledge-base/*.md) ;;
    *.md)
      case "$path" in */*) emit true ;; esac ;;   # *.md only safe at repo root
    *) emit true ;;
  esac
done

[ "$saw_any" -eq 1 ] || emit true
emit false
