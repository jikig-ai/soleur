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
# WHAT THIS TRAILER DOES AND DOES NOT MEAN (ADR-127)
#
# It is a BOOLEAN: "a review ran on this branch". It is NOT an attestation that
# the merged tree is the tree that was reviewed. Reviewing early and then
# pushing further commits leaves the trailer in range and the gate passes.
#
# That is deliberate, not an oversight. The consuming gate is a three-signal
# OR in which every leg is a boolean — the legacy `review: ` subject pattern is
# checked BEFORE this trailer, and Signal 3 (a labelled GitHub issue) cannot be
# bound to a tree at all. Content-binding this one leg would therefore close
# nothing: `git commit --allow-empty -m "review: x"` still satisfies the gate.
# Making the binding real means deleting the legacy patterns (stranding every
# branch reviewed before this shipped) and re-architecting Signal 3 — a much
# larger change, landing a re-review treadmill on a gate already denying most
# open PRs. Gates that block constantly get bypassed; that is how #6724 was
# created.
#
# Threat model: agent forgetfulness on a trusted single-operator repo. These
# hooks live in the operator's own checkout and are editable by the same agent
# they constrain, so there is no enforcement boundary to build on. A boolean is
# the honest instrument for that.
#
# `Reviewed-Commit:` below records the reviewed sha WITHOUT any consumer reading
# it, so the forensic data exists if the threat model ever changes (external
# contributors merging without operator review) and enforcement becomes
# warranted. Adding the field later would be the expensive part; enforcing a
# field already present is cheap.
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

usage() {
  cat <<'EOF'
Usage: emit-review-trailer.sh [--findings <n>] [--summary <text>]

Commits an empty commit carrying the Reviewed-By-Soleur: trailer, the
machine-readable proof that soleur:review ran on this branch (#6724).

Exit codes:
  0  trailer committed and verified parseable
  0  skipped (on main/master, or evidence already present for this branch)
  1  commit succeeded but the trailer does not parse
  2  usage / environment error
EOF
}

TRAILER_KEY="Reviewed-By-Soleur"
FINDINGS=""
SUMMARY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) FINDINGS="${2:?--findings needs a value}"; shift 2 ;;
    --summary)  SUMMARY="${2:?--summary needs a value}";  shift 2 ;;
    -h|--help)  usage; exit 0 ;;
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
#
# `Reviewed-Commit:` records the sha under review. NO consumer reads it — see
# the ADR-127 note in the header. It is recorded now because adding a field
# later, once the key is in main's permanent history and read by three
# consumers, is the expensive part; enforcing a field already present is cheap.
REVIEWED_SHA=$(git rev-parse HEAD)
COMMIT_MSG=$(printf '%s\n\n%s\n\n%s: soleur:review\n%s: %s\n' \
  "review: ${SUMMARY}" \
  "Records that soleur:review ran on this branch (see issue 6724). Empty by design: a review that finds nothing still needs to prove it ran. This is a boolean, not an attestation that the merged tree is the reviewed tree — see ADR-127." \
  "$TRAILER_KEY" \
  "Reviewed-Commit" "$REVIEWED_SHA")

# `--allow-empty` does NOT mean "empty" — it commits the INDEX, so anything
# staged is silently absorbed into a commit whose subject reads
# "review: no findings". That is reachable: review's step 2 stages artifacts and
# its commit is conditional, while step 3 runs unconditionally right after.
# Refuse rather than absorb; the caller can commit or unstage and re-run.
if ! git diff --cached --quiet 2>/dev/null; then
  echo "emit-review-trailer: refusing to run with staged changes." >&2
  echo "  --allow-empty commits the index, so these would be silently absorbed" >&2
  echo "  into a commit subjected 'review: ${SUMMARY}':" >&2
  git diff --cached --name-only 2>/dev/null | sed 's/^/    /' >&2
  echo "  Commit or unstage them first, then re-run." >&2
  exit 2
fi

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
