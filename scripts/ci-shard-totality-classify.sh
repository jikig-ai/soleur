#!/usr/bin/env bash
# ci-shard-totality-classify.sh — is this change-set worth running the shard-totality mutation battery for? (#9729)
#
# Usage:
#   <git-diff --raw rows> | ci-shard-totality-classify.sh <event-name>
#   ci-shard-totality-classify.sh --enum-failed
#
# Output: a single line, `true` (run the battery) or `false` (skip it).
#
# CONTRACT — fail-closed allowlist, never a denylist of "subject" paths. The battery mutates the runner, the
# shard tables and ci.yml and then runs guard suites over a census of `git ls-files`, so its subject set is open
# ended (a new declarer under any tree can matter). Skipping is therefore allowed for exactly one shape:
#   * `pull_request`, a non-empty changed-file list, and EVERY row is a well-formed `git diff --raw` row
#     (`:OLDMODE NEWMODE OLDSHA NEWSHA STATUS<TAB>path`, lower-case hex) of status A (old mode 000000) or M (old mode
#     100644) with new mode 100644, AND its path is a markdown file under `knowledge-base/` or at the repository root.
#     A markdown file declares no suite and is read by no census.
# Everything else runs: any other path (a `.sh`/`.py`/`.ts`/`.json` anywhere, including under `knowledge-base/`,
# where the census enumerates declarers), a deletion, rename, copy, typechange or unmerged row, a C-quoted path,
# an empty list, and every event other than `pull_request` (a push or a merge_group candidate is the full-battery
# authority, ADR-276). `--enum-failed` is the verdict the calling step uses when `git diff` itself failed: it emits
# `true`. Missing or unknown argv exits NON-ZERO so a broken classifier reds the job instead of fabricating a skip.
#
# MODE GATE (#10416). `--name-status` carried no file mode, so an added symlink or an exec-bit flip on a `.md` read as
# markdown. The battery's census reads `*.sh`/`*.bash` AND shebang files, so an executable `.md` can be a subject and the
# old "accepted here" exposure was wrong for exec-bit rows. Only (A, 000000 -> 100644) and (M, 100644 -> 100644) may skip;
# 100755, 120000, 160000, a mode-changing M and an A with a non-null old mode all emit `true`. This is deliberately
# STRICTER than the PR B driver's allowlist in scripts/ci-pr-selection.sh (which also admits 100755): the driver has later
# stages, a classifier skip has none. A row that does not match the raw-row grammar (legacy `--name-status`, a bare path, a
# rename's second path, upper-case hex) emits `true`; the legacy "bare path is modified" rule is gone. Revisit before any
# widening of a doc-only allowlist, or if this skip is ever used for a context other than a non-required job.
#
# The row-parse block below is duplicated byte for byte in scripts/ci-e2e-classify.sh (CI runs each classifier from a
# base-ref `git show` copy where scripts/lib does not exist, so there is no shared helper);
# plugins/soleur/test/ci-shard-totality-skip.test.sh pins the parity.
#
# Reproduce a verdict locally (CI judges by the BASE ref's copy of this file, so a PR cannot weaken the gate it is judged by):
#   git diff --raw --no-color --no-ext-diff origin/main...HEAD | bash scripts/ci-shard-totality-classify.sh pull_request
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
    knowledge-base/*.md) ;;
    *.md)
      case "$path" in */*) emit true ;; esac ;;   # *.md only safe at repo root
    *) emit true ;;
  esac
done

[ "$saw_any" -eq 1 ] || emit true
emit false
