#!/usr/bin/env bash
# PreToolUse hook for file_editor tool.
# Blocks file writes to the main repo checkout when worktrees exist.
# OpenHands port of .claude/hooks/worktree-write-guard.sh.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Input: HookEvent JSON on stdin with tool_input.path and working_dir.
# OpenHands file_editor uses "path" (not "file_path" like Claude Code).
#
# Corresponding prose rules: see .claude/hooks/worktree-write-guard.sh

set -euo pipefail

INPUT=$(cat)

# One constant, defined once. The reason text is agent-facing and was
# previously duplicated per extraction, in two different lengths, so how much
# the agent was told depended on which extraction happened to fail first.
#
# It names an action the AGENT CAN TAKE. The earlier wording ("re-send a
# well-formed envelope") named one it cannot: the agent authors tool_input
# values, while the runtime assembles the envelope, the working_dir and the
# JSON framing. The parity suite's own fixture puts the offending byte in
# working_dir, so on that payload the old text asked the agent to fix
# something it does not produce - and guardrails.sh is registered on BOTH
# matchers, so it would deny every tool the agent has, with no way forward.
UNPARSEABLE_REASON="BLOCKED: the tool-call envelope did not parse (ADR-156/ADR-162), so this hook's guards did not run and the call is refused rather than silently permitted. The usual cause is a byte in one of your tool arguments that cannot be encoded as JSON text - most often a lone surrogate from non-UTF-8 file content. Re-send with that value base64- or hex-encoded, or with the offending bytes dropped. If none of your arguments carry such a value the envelope was malformed in transport, which you did not author; re-sending unchanged may succeed."

# --- reason-class split (ADR-162) ----------------------------------------
# jq MISSING fails OPEN, loudly: ADR-157:115 rejects fail-closed because the
# repair for a broken PATH or a missing jq is itself a tool call that would also
# be denied, and that bites harder here — this harness has no `ask`, no operator
# escalation and no kill switch. A document jq REJECTS is a different class and
# DENIES via the extraction failure branches below. Before this split, any
# document jq rejected killed the script under `set -euo pipefail` with no deny,
# no decision JSON and no incident row, leaving the outcome to depend on how the
# runtime treats a non-0/2 exit code — an invariant this repo does not define.
if ! command -v jq >/dev/null 2>&1; then
  echo "[worktree-write-guard] jq missing — envelope unparseable, guards did NOT run for this call" >&2
  # FAIL OPEN, but not unconditionally. Failing open on this class is required
  # (ADR-157 §Alternatives Considered, "Fail closed": the repair for a broken
  # PATH or a missing jq is itself a tool call a deny would also block) — but an
  # UNCONDITIONAL open turns "delete jq" into a one-call disarm of every guard
  # in this file. So before proceeding, match the RAW document against the
  # narrow set of patterns whose guards are the reason this hook exists. The
  # repair commands themselves (apt-get install jq, export PATH=..., ln -s)
  # match none of these, so the recovery path stays open. Deliberately
  # over-broad in the other direction: on a branch that only runs when the
  # parser is gone, a false deny is the correct error.
  if grep -qE 'rm[[:space:]]+-[a-zA-Z]*[rf]|git[[:space:]]+stash|--delete-branch|git[[:space:]]+commit' <<<"$INPUT"; then
    printf '{"decision":"deny","reason":"BLOCKED: jq is unavailable, so the tool-call envelope cannot be parsed and this hook'"'"'s guards did not run — and the raw envelope matches a protected pattern. Repair jq first (install it, or fix PATH), then re-send."}\n'
    exit 2
  fi
  exit 0
fi

# --- ADR-156 (mirror): the HookEvent envelope is MODEL-CONTROLLED ------------
# This port never called eval, so it never had the #7164 code execution. It DID
# have the evasion half, and this file is a WIRED BLOCKING guard
# (.openhands/hooks.json, file_editor matcher). Measured on this branch before
# the guard below existed: a string `.tool_input.path` into the main checkout
# denied with exit 2, while the SAME target as a one-element ARRAY exited 0 —
# `jq -r` renders it across lines, the `$GIT_ROOT*` prefix test below fails to
# match, and the write sails through.
#
# Its .claude twin was migrated in this PR; this file was missed because the
# scope was written as "the two mirrors" when hooks.json wires THREE blocking
# ones. Caught by code-simplicity-reviewer, reproduced before fixing.
#
# Scoped NARROW, matching the sibling mirrors: fires only when the document
# PARSES and a contracted field is the wrong TYPE, so a transport failure keeps
# the pre-existing behaviour. No `ask` exists in this protocol, so an anomalous
# shape denies — no legitimate caller sends a non-string, and a deny is
# recoverable where a silent bypass is not.
WWG_ENVELOPE_SHAPE=$(printf '%s' "$INPUT" | jq -r '
  # NB the // operator is deliberately absent: in jq it is a FALSY-alternative,
  # so a JSON false would be rewritten to "" and pass the type check below
  # (measured on the .claude side before this was fixed). Only null defaults.
  if (type == "object")
     and ((.tool_input? | type) as $t | $t == "null" or $t == "object")
     and ((if (.tool_input | has("path")) and (.tool_input.path != null) then .tool_input.path else .tool_input.file_path end | if . == null then "" else . end) | type == "string")
     and ((.working_dir? | if . == null then "" else . end) | type == "string")
  then "ok" else "nonstring" end' 2>/dev/null) || WWG_ENVELOPE_SHAPE="unparseable"
# `internal` — the shape program itself failed (a broken program, a jq version
# change, OOM) while the simpler extractions above succeeded. This was a
# TOTALLY SILENT fail-open: the fallback assigned "unparseable" and nothing
# branched on it, so an ARRAY command disarmed every guard below with no
# stdout, no stderr and no record — measured. Fail open (same
# self-referential-repair rationale as jq_missing) but LOUDLY.
if [[ "$WWG_ENVELOPE_SHAPE" != "ok" && "$WWG_ENVELOPE_SHAPE" != "nonstring" ]]; then
  echo "[worktree-write-guard] envelope shape program failed ($WWG_ENVELOPE_SHAPE) — guards did NOT run for this call" >&2
fi
if [[ "$WWG_ENVELOPE_SHAPE" == "nonstring" ]]; then
  jq -n '{"decision":"deny","reason":"BLOCKED: the tool-call envelope carries a non-string field (e.g. an ARRAY tool_input.path). Hook stdin is model-controlled and untrusted (ADR-156); a non-string is never coerced, because the coerced value matches no path test and would bypass this guard. Re-send the path as a string."}'
  exit 2
fi

# OpenHands file_editor uses "path"; fall back to "file_path" for compatibility
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // .tool_input.file_path // ""' 2>/dev/null) \
  || { jq -n --arg r "$UNPARSEABLE_REASON" '{"decision":"deny","reason":$r}'; exit 2; }

[[ -z "$FILE_PATH" ]] && exit 0

# Get the main repo root (not the worktree root).
GIT_ROOT=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || exit 0)

# If file path is not under the repo root, allow it
[[ "$FILE_PATH" != "$GIT_ROOT"* ]] && exit 0

# If file path is inside a worktree, allow it
[[ "$FILE_PATH" == *"/.worktrees/"* ]] && exit 0

# Allow writes to .claude/ and .openhands/ directories
RELATIVE_PATH="${FILE_PATH#"$GIT_ROOT"/}"
[[ "$RELATIVE_PATH" == .claude/* ]] && exit 0
[[ "$RELATIVE_PATH" == .openhands/* ]] && exit 0

# Check if any worktrees exist
WORKTREE_DIR="$GIT_ROOT/.worktrees"
if [[ -d "$WORKTREE_DIR" ]] && [[ -n "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
  WORKTREE_NAMES=$(ls "$WORKTREE_DIR" 2>/dev/null | head -3 | tr '\n' ', ' | sed 's/,$//')
  jq -n --arg names "$WORKTREE_NAMES" --arg path "$GIT_ROOT/.worktrees/<name>/$RELATIVE_PATH" \
    '{"decision":"deny","reason":("BLOCKED: Writing to main repo checkout while worktrees exist (" + $names + "). Write to the worktree path instead: " + $path)}'
  exit 2
fi

exit 0
