#!/usr/bin/env bash
# PreToolUse hook: block `gh pr merge` when a branch commit body OR the PR body
# contains a PROSE-EMBEDDED GitHub auto-close keyword + #N (e.g. "the sweeper
# closes #5887", "I'll close #5955 after the pipeline") that would auto-close an
# issue you did not intend to close on merge.
#
# Source rule: knowledge-base/project/learnings/2026-06-29-auto-closes-meta-content-
#   in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md
#   + 2026-07-03-chain-of-latent-defects-clearing-a-wedge-exposes-a-cascade.md
#   (auto-close-prose hit TWICE via hand-rolled `gh pr merge`).
#
# Why this hook exists (the gap it closes): `/ship` Phase 6 runs
# `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` at PR-creation time, but
# a HAND-ROLLED / auto `gh pr merge` (bypassing /ship) has no equivalent check.
# This hook makes the guard merge-path-independent, mirroring how
# pre-merge-rebase.sh already intercepts `gh pr merge`.
#
# Precision (why it does NOT block legitimate closes): an intentional `Closes #N`
# on its own line (the conventional form /ship PRs use) is ALLOWED. Only a
# close-keyword that appears AFTER prose on its line — the accidental vector —
# denies. So normal fix-PRs that mean to close their issue merge unimpeded.
#
# Fail-open: any infrastructure error (bad payload, missing git, scan failure)
# exits 0 (allow). A hook must never wedge a merge on its own bug.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
# strip_command_bodies (blank quoted/heredoc bodies so a commit MESSAGE that
# documents "gh pr merge" is not mis-detected as a merge — same #4600/#5192
# canonical helper pre-merge-rebase.sh uses).
if [[ -f "$_LIB_DIR/incidents.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/incidents.sh"
else
  strip_command_bodies() { cat; }
fi
export SOLEUR_HOOK_NAME="pre-merge-auto-close-scan"

INPUT=$(cat)
# `|| true`: jq exits non-zero on malformed/empty stdin under pipefail; degrade
# to "" (no detection → clean allow) rather than aborting.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' || true)
SCAN=$(printf '%s' "$CMD" | strip_command_bodies || printf '%s' "$CMD")

# Only intercept `gh pr merge` (incl. the `… -- gh pr merge` wrapped form).
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""' || true)
[[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] || exit 0
git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" && "$BRANCH" != "HEAD" ]] || exit 0

# Ack escape hatch: SOLEUR_ACK_AUTOCLOSE=1 means the operator has confirmed the
# embedded close is intentional (rare — a prose sentence that really should
# close). Mirrors the ack-env pattern used by sibling gates.
[[ "${SOLEUR_ACK_AUTOCLOSE:-}" == "1" ]] && exit 0

# Build the scan corpus: the branch commit bodies (feed the squash commit) AND
# the PR body (the other squash-message source, repo-config-dependent). Both are
# best-effort; a failure to read either must not block the merge.
SCAN_FILE=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$SCAN_FILE"' EXIT
git -C "$WORK_DIR" log origin/main..HEAD --format=%B 2>/dev/null >>"$SCAN_FILE" || true
# PR body, bounded so a slow/absent network never stalls the merge.
timeout 8 gh pr view --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')" \
  "$BRANCH" --json body --jq '.body' 2>/dev/null >>"$SCAN_FILE" || true
[[ -s "$SCAN_FILE" ]] || exit 0

# Reuse the canonical scanner (single-sources GitHub's keyword set + locale pin),
# then keep only PROSE-EMBEDDED matches: lines whose close-keyword is NOT the
# start-of-line directive (a standalone `Closes #N` / `- Fixes #N` is intentional).
SCANNER="$WORK_DIR/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
[[ -x "$SCANNER" || -f "$SCANNER" ]] || exit 0
DIRECTIVE='^[0-9]+:[[:space:]]*([-*>][[:space:]]*)*(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)'
EMBEDDED=$(bash "$SCANNER" "$SCAN_FILE" 2>/dev/null | grep -viE "$DIRECTIVE" || true)

[[ -n "$EMBEDDED" ]] || exit 0

REASON="BLOCKED: a commit/PR body has a prose-embedded auto-close keyword that will auto-close an issue on merge (GitHub's parser is markdown- and position-blind):

$(printf '%s\n' "$EMBEDDED" | sed 's/^/  /')

Fix: reword the sentence to remove the close-keyword + #N adjacency — e.g. 'auto-resolves issue #N' or 'the sweeper will close issue #N' (no bare 'close(s)/fix(es)/resolve(s) #N'). A standalone 'Closes #N' line is fine and is NOT flagged. If this close is genuinely intended, re-run with SOLEUR_ACK_AUTOCLOSE=1."

jq -n --arg r "$REASON" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
