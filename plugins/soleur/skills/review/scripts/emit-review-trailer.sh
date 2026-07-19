#!/usr/bin/env bash
# Emit the machine-readable "a review actually ran on this branch" signal (#6724).
#
# WHY THIS IS A SCRIPT AND NOT A PROSE INSTRUCTION
#
# The pre-existing convention was a sentence in review/SKILL.md telling the
# agent to commit review artifacts. Its measured compliance is zero on
# zero-finding branches, because the same skill explicitly says:
#
#   "If there are no local changes, skip the commit (this is the expected
#    case — review's primary output is GitHub issues, which are remote-only)."
#
# So the cleanest branches — the ones where review found nothing — produce no
# local evidence at all. Every downstream review-evidence gate then reads
# "review never ran" and denies the merge, with no escape hatch. That is the
# P0 this script exists to close, and it is why `--allow-empty` below is
# load-bearing rather than a convenience: without it, a zero-finding review
# makes no commit, emits no trailer, and deadlocks exactly the branches that
# had nothing wrong with them.
#
# The trailer is emitted by a script rather than described in prose because a
# described `git commit` line is advisory and a script invocation is not.
#
# Usage:
#   emit-review-trailer.sh [--findings <n>] [--summary <text>]
#
# Exit codes:
#   0  trailer committed and verified parseable
#   0  skipped (on main/master, or evidence already present for this branch)
#   1  commit succeeded but the trailer does not parse — see VERIFY below
#   2  usage / environment error
set -euo pipefail

TRAILER_KEY="Reviewed-By-Soleur"
FINDINGS=""
SUMMARY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) FINDINGS="${2:?--findings needs a value}"; shift 2 ;;
    --summary)  SUMMARY="${2:?--summary needs a value}";  shift 2 ;;
    -h|--help)  sed -n '1,32p' "$0"; exit 0 ;;
    *) echo "emit-review-trailer: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "emit-review-trailer: not a git repository" >&2
  exit 2
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$BRANCH" ]]; then
  echo "emit-review-trailer: could not resolve branch" >&2
  exit 2
fi

# Never emit on main/master or in detached HEAD. The gate skips those cases
# too, so a commit here would be pure noise on the trunk's history.
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "HEAD" ]]; then
  echo "emit-review-trailer: on '$BRANCH' — nothing to mark, skipping."
  exit 0
fi

# Resolve the branch's base ref explicitly. `origin/main..HEAD` is the right
# scope in the real repo, but silently degrades to an ERROR — and therefore to
# an empty result — anywhere that ref is absent (throwaway fixtures, clones
# with a different default branch, detached CI checkouts). An empty result
# reads identically to "no trailer yet", so the idempotence check below would
# fail open and stack a duplicate empty commit on every invocation. Falling
# back to the whole of HEAD is the conservative direction: it can only ever
# suppress an extra commit, never emit a spurious one.
BASE_REF=""
for cand in origin/main origin/master main master; do
  if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then BASE_REF="$cand"; break; fi
done
if [[ -n "$BASE_REF" ]] && [[ "$(git rev-parse "$BASE_REF")" != "$(git rev-parse HEAD)" ]]; then
  SCOPE="${BASE_REF}..HEAD"
else
  SCOPE="HEAD"
fi

# Idempotence: if this branch already carries the trailer, a second review pass
# should not stack duplicate empty commits. Scoped to commits unique to the
# branch, for the same reason the gate is (see below).
if git log "$SCOPE" --format='%(trailers:key='"$TRAILER_KEY"',valueonly)' 2>/dev/null \
     | grep -q '[^[:space:]]'; then
  echo "emit-review-trailer: branch already carries a $TRAILER_KEY trailer (scope: $SCOPE) — skipping."
  exit 0
fi

if [[ -z "$SUMMARY" ]]; then
  if [[ "$FINDINGS" == "0" ]]; then
    SUMMARY="no findings"
  elif [[ -n "$FINDINGS" ]]; then
    SUMMARY="$FINDINGS finding(s) triaged"
  else
    SUMMARY="review complete"
  fi
fi

# The subject deliberately matches the legacy Signal 2 regex (`review: `) so
# this commit is recognised by gates that predate the trailer and have not been
# updated yet. The trailer is the durable signal; the subject is the fallback.
#
# The final paragraph is trailers ONLY. Git parses just the last contiguous
# block of `Token: value` lines, so a stray `Refs #6724.` there would silently
# void every trailer below it — including this one. Issue references therefore
# stay in the body prose above.
COMMIT_MSG=$(printf '%s\n\n%s\n\n%s: soleur:review\n' \
  "review: ${SUMMARY}" \
  "Machine-readable evidence that soleur:review ran on this branch (see issue 6724). Empty by design: a review that finds nothing still needs to prove it ran." \
  "$TRAILER_KEY")

if ! git commit --allow-empty -q -m "$COMMIT_MSG"; then
  echo "emit-review-trailer: git commit failed" >&2
  exit 2
fi

# VERIFY: a trailer that does not parse is worse than no trailer — it looks
# like evidence to a human reading the log and is invisible to the gate that
# actually consumes it. This repo has shipped that exact defect before, so the
# script refuses to report success on an unparseable trailer.
PARSED=$(git log -1 --format='%(trailers:key='"$TRAILER_KEY"',valueonly)' | tr -d '[:space:]')
if [[ -z "$PARSED" ]]; then
  echo "emit-review-trailer: FAILED — commit landed but '$TRAILER_KEY' does not parse." >&2
  echo "  The final paragraph of the commit message must contain ONLY 'Token: value' lines." >&2
  echo "  Inspect with: git interpret-trailers --parse < <(git log -1 --format=%B)" >&2
  exit 1
fi

echo "emit-review-trailer: emitted $TRAILER_KEY on '$BRANCH' ($(git rev-parse --short HEAD))"
