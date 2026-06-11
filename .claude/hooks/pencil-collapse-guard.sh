#!/usr/bin/env bash
# PostToolUse hook: auto-recover a tracked .pen file that mcp__pencil__open_document
# silently collapsed to empty document state.
#
# Rule: After mcp__pencil__open_document returns, if the on-disk .pen at filePath
#   is git-tracked AND has collapsed to the unambiguous empty-document shape
#   ({"version":"...","children":[]}) while its committed HEAD blob is non-empty,
#   restore the file from git HEAD and surface a loud system message.
#   [id: cq-pencil-collapse-auto-recover]
#   [hook-enforced: pencil-collapse-guard.sh].
#
# Why: open_document can silently truncate a non-empty .pen to empty state while
#   returning a success string (issue #3274; recurred 2026-06-02 on a committed
#   file, recovered by hand). The PreToolUse pencil-open-guard.sh only DENIES
#   untracked .pen (no recovery path); the ux-design-lead / brand-workshop prose
#   HARD-GATEs (PR #4855) rely on agent discipline. This hook is the deterministic
#   backstop for the tracked case. The root-cause fix is upstream (#4859 Part B).
#
# Safety contract (brand-survival threshold: single-user incident):
#   - PostToolUse cannot block — the destructive write already happened; the hook
#     can only recover + warn.
#   - `set -uo pipefail` (NO `-e`): the hook must NEVER abort mid-flight and leave
#     a half-written file. Every error/ambiguity path is `exit 0` with NO write.
#   - Collapse detection is conservative: restore ONLY on the unambiguous empty
#     -document shape. A guard that clobbers good work with stale HEAD is strictly
#     worse than the bug it fixes.
set -uo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat 2>/dev/null) || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.filePath // ""' 2>/dev/null) || exit 0

# No filePath → nothing to recover.
[[ -z "$FILE_PATH" ]] && exit 0
# File must exist on disk to be inspected.
[[ -f "$FILE_PATH" ]] || exit 0
# Refuse symlinks: both the read (cat) and the restore write would follow the
# link, letting a tracked-by-path .pen symlink redirect the write outside the
# repo. The recovery target must be a regular file.
[[ -L "$FILE_PATH" ]] && exit 0

# Resolve to absolute path for git checks (mirror pencil-open-guard.sh).
if [[ ! "$FILE_PATH" = /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Find the git repo root for this file; outside any repo → fail-open.
REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || echo "")
[[ -z "$REPO_ROOT" ]] && exit 0

# Path relative to repo root for git ls-files / git show.
REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$FILE_PATH" 2>/dev/null || echo "")
[[ -z "$REL_PATH" ]] && exit 0

# Tracked check — untracked .pen has no recovery anchor (PreToolUse denies these
# at open time; this is defense-in-depth). Fail-open if untracked.
git -C "$REPO_ROOT" ls-files --error-unmatch "$REL_PATH" >/dev/null 2>&1 || exit 0

# _is_collapsed <content> — returns 0 (true) ONLY for an unambiguous empty
# document. Conservative by design: restore must never clobber an unfamiliar
# but valid shape.
#   - empty / whitespace-only file → collapsed (a 0-byte .pen is never valid).
#   - the documented shape: a JSON object with a `children` key that is a
#     zero-length array ({"version":"...","children":[]}).
# Anything else — parse failure, non-object, a different top-level container
# (no `children` key), or a non-empty `children` — is treated as healthy.
_is_collapsed() {
  local content="$1"
  [[ -z "${content//[[:space:]]/}" ]] && return 0
  printf '%s' "$content" | jq -e \
    'type == "object" and has("children") and (.children | type == "array") and (.children | length == 0)' \
    >/dev/null 2>&1
}

# On-disk content must be collapsed; otherwise healthy → no-op (AC3).
DISK_CONTENT=$(cat "$FILE_PATH" 2>/dev/null || echo "")
_is_collapsed "$DISK_CONTENT" || exit 0

# Committed blob must be NON-empty; if HEAD is also empty (legitimate scaffold)
# or git show errors, there is nothing safe to restore → no-op (AC4).
HEAD_CONTENT=$(git -C "$REPO_ROOT" show "HEAD:$REL_PATH" 2>/dev/null) || exit 0
if _is_collapsed "$HEAD_CONTENT"; then
  exit 0
fi

# Restore from HEAD (byte-identical to the committed blob). Write to a temp file
# in the same directory and atomically `mv` into place ONLY on git-show success —
# a bare `> "$FILE_PATH"` truncates the target before git runs, so a failed show
# would leave a 0-byte file (strictly worse than the collapsed state).
tmp_restore=$(mktemp "$(dirname "$FILE_PATH")/.pen-restore.XXXXXX" 2>/dev/null) || exit 0
if git -C "$REPO_ROOT" show "HEAD:$REL_PATH" > "$tmp_restore" 2>/dev/null; then
  mv -f "$tmp_restore" "$FILE_PATH" 2>/dev/null || { rm -f "$tmp_restore" 2>/dev/null; exit 0; }
else
  rm -f "$tmp_restore" 2>/dev/null
  exit 0
fi

# Loud telemetry + system message — the restore is a noteworthy event.
emit_incident "cq-pencil-collapse-auto-recover" warn \
  "Auto-recover a tracked .pen collapsed to empty doc " "$REL_PATH" PostToolUse

# PostToolUse system-message surface is hookSpecificOutput.additionalContext.
# If the jq line-build fails, fall back to a loud stderr line (still exit 0).
if ! jq -n --arg f "$REL_PATH" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("AUTO-RESTORED: open_document silently truncated tracked .pen file " + $f + " to empty document state. Restored it from git HEAD. Do NOT re-run open_document on this file without snapshotting — this is the #4859 collapse class.")}}' 2>/dev/null; then
  echo "pencil-collapse-guard: AUTO-RESTORED $REL_PATH from git HEAD (open_document collapse)" >&2
fi

exit 0
