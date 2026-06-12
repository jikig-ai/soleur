#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh issue create --label follow-through` when
# the proposed body lacks a valid `<!-- soleur:followthrough -->` directive.
#
# Source rules: `/ship` Phase 7 Step 3.5.E (the parser self-test) +
# `wg-pm-class-followthrough-for-operator-dogfood`. Converts the agent
# honor-system rule into a mechanical gate at the `gh issue create` boundary.
#
# The hook rejects when ANY of:
#   - body lacks the `<!-- soleur:followthrough` opening marker
#   - body lacks the closing `-->`
#   - parsed `script=` is empty OR doesn't resolve to an existing executable
#     file under `scripts/followthroughs/` (path-traversal-safe via realpath)
#   - parsed `earliest=` is empty OR doesn't parse via `date -u -d`
#
# Why it exists: PR #4226's ship Phase 7 Step 3.5 created three follow-through
# issues (#4244, #4245, #4246) — NONE with a directive. The sweeper had nothing
# to evaluate, and the issues would have rotted open. Surfaced at the workflow
# audit immediately after merge. See knowledge-base learning
# `2026-05-21-followthrough-directive-enforcement.md`.
#
# Contract-inherited PreToolUse(Bash) input shape:
#   .tool_input.command  (string)
#   .cwd                 (string)
#
# Fail-open conditions (exit 0 silently):
#   - not a `gh issue create` call
#   - command doesn't reference the `follow-through` label
#   - input lacks .cwd or path is not an absolute existing directory
#   - cannot extract body (no --body / --body-file / file unreadable)
#
# Fail-closed conditions (deny + emit_incident):
#   - body lacks directive OR directive fails parser self-test

set -eo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Match `gh issue create` (anchored at start of pipeline OR after &&/||/;).
# The same word-boundary form used by ship-unpushed-commits-gate.sh.
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh issue create` is not mistaken for one (#5192).
# Only the TRIGGER grep moves to $SCAN; the --body/--body-file extraction below
# stays on $CMD so a REAL create's quoted body is still read (its flags live
# outside the stripped span).
SCAN=$(strip_command_bodies "$CMD")
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create(\s|$)'; then
  exit 0
fi

# Only fire when the create includes the `follow-through` label. We accept
# either `--label follow-through` (single use) or `--label "follow-through"`
# (quoted) — both shapes appear in /ship Phase 7 Step 3.5.
if ! echo "$CMD" | grep -qE -- '--label[[:space:]]+["'"'"']?follow-through(["'"'"']|[[:space:]]|$)'; then
  exit 0
fi

# Validate WORK_DIR: required for body-file resolution.
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

# Extract the body. /ship's Phase 7 Step 3.5 always uses --body-file with a
# /tmp path; older inline-call sites may use --body "<heredoc>". Handle both.
# `|| true`: under `set -eo pipefail` a no-match grep exits non-zero and would
# abort the hook (fail-open) for any inline-`--body` create. Mirrors the
# BODY_INLINE guard below.
BODY_FILE=$(echo "$CMD" | grep -oE -- '--body-file[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $2}' || true)
BODY_INLINE=""
if [[ -z "$BODY_FILE" ]]; then
  # --body "<string>" or --body '<string>' or --body $'<string>'. Pull
  # everything after --body that's quoted; bash's word-splitting in the
  # caller's shell has already collapsed whitespace, so we work with the
  # exact bytes the hook received from jq @sh.
  # Use perl for greedy regex; sed -E can't do non-greedy across newlines.
  BODY_INLINE=$(echo "$CMD" | perl -0777 -ne 'if (/--body[[:space:]]+(["'"'"'])(.+?)(?<!\\)\1/s) { print $2; }' || true)
fi

# Resolve to a real file we can read.
PARSED_BODY=""
if [[ -n "$BODY_FILE" ]]; then
  # Resolve relative-to-WORK_DIR for safety.
  if [[ "$BODY_FILE" != /* ]]; then
    BODY_FILE="${WORK_DIR}/${BODY_FILE}"
  fi
  if [[ ! -f "$BODY_FILE" ]] || [[ ! -r "$BODY_FILE" ]]; then
    # File doesn't exist at hook time → caller bug, not our class. Fail open.
    exit 0
  fi
  PARSED_BODY=$(cat "$BODY_FILE")
elif [[ -n "$BODY_INLINE" ]]; then
  PARSED_BODY="$BODY_INLINE"
else
  # No --body or --body-file → no body to validate. `gh issue create` will
  # prompt interactively, which won't happen under the Bash tool anyway.
  exit 0
fi

# === Directive presence + parser self-test ===

# Open marker. Mirrors scripts/sweep-followthroughs.sh's awk pattern at
# the `^<!-- *soleur:followthrough` anchor.
if ! printf '%s' "$PARSED_BODY" | grep -qE '^[[:space:]]*<!-- *soleur:followthrough'; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through issues MUST embed the soleur:foll" "$CMD"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: `gh issue create --label follow-through` requires a `<!-- soleur:followthrough script=... earliest=... [secrets=...] -->` directive in the issue body. Without it the daily sweeper has nothing to evaluate against and the issue will rot open. See `/ship` Phase 7 Step 3.5.A-F and `plugins/soleur/skills/ship/references/followthrough-stub-template.sh` for the canonical pattern."
    }
  }'
  exit 0
fi

# Closing marker on the same/subsequent line.
if ! printf '%s' "$PARSED_BODY" | grep -qE -- '-->'; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through directive MUST include closing -" "$CMD"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: `<!-- soleur:followthrough ...` directive is missing its closing `-->`. The awk parser at scripts/sweep-followthroughs.sh expects both markers."
    }
  }'
  exit 0
fi

# Extract script= and earliest= using the same awk parser the sweeper uses.
# Inlined here so the hook is self-contained (no source dependency on a
# repo file that may move). If you change the parser, mirror BOTH places.
PARSED=$(printf '%s' "$PARSED_BODY" | awk '
  BEGIN { in_dir = 0; closing = 0; fence = 0 }
  /^```/ { fence = !fence; next }
  fence { next }
  /^[[:space:]]*<!-- *soleur:followthrough/ { in_dir = 1 }
  /-->/ && in_dir { closing = 1 }
  in_dir {
    gsub(/^[[:space:]]*<!-- *soleur:followthrough/, "")
    gsub(/-->/, "")
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
      if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
    }
  }
  closing { in_dir = 0; closing = 0 }
')

SCRIPT_REL=$(printf '%s\n' "$PARSED" | awk '/^script /{print $2; exit}')
EARLIEST=$(printf '%s\n' "$PARSED" | awk '/^earliest /{print $2; exit}')

if [[ -z "$SCRIPT_REL" ]]; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through directive MUST set script=<path>" "$CMD"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: directive parsed but `script=` is empty. Provide `script=scripts/followthroughs/<feature>-<issue>.sh` per /ship Phase 7 Step 3.5.A."
    }
  }'
  exit 0
fi

if [[ -z "$EARLIEST" ]]; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through directive MUST set earliest=<UTC>" "$CMD"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: directive parsed but `earliest=` is empty. Set `earliest=YYYY-MM-DDTHH:MM:SSZ` per /ship Phase 7 Step 3.5.D — the sweeper uses this to gate first evaluation."
    }
  }'
  exit 0
fi

# Path-traversal guard: realpath under WORK_DIR/scripts/followthroughs/.
# Same logic as /ship Phase 7 Step 3.5.E. A path using `..` traversal that
# escapes the followthroughs root after canonicalization is rejected.
SCRIPT_ABS=$(realpath -m "${WORK_DIR}/${SCRIPT_REL}" 2>/dev/null || echo "")
SCRIPTS_ROOT_ABS=$(realpath -m "${WORK_DIR}/scripts/followthroughs" 2>/dev/null || echo "")
if [[ -z "$SCRIPT_ABS" ]] || [[ -z "$SCRIPTS_ROOT_ABS" ]] || [[ "$SCRIPT_ABS" != "$SCRIPTS_ROOT_ABS"/* ]]; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through script path must resolve under sc" "$CMD"
  jq -n --arg s "$SCRIPT_REL" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: directive `script=" + $s + "` does not resolve under `scripts/followthroughs/`. Use `script=scripts/followthroughs/<feature>-<issue>.sh` so the sweeper can locate the verification script.")
    }
  }'
  exit 0
fi

# Script must exist + be executable. The script existence check catches
# the most common failure: the agent composes the directive but forgets to
# scaffold the stub. (PR #4178 was filed in this exact failure shape and
# rotted open for 24h before retrofit.)
if [[ ! -f "$SCRIPT_ABS" ]]; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through script does not exist on disk; s" "$CMD"
  jq -n --arg s "$SCRIPT_REL" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: directive references `" + $s + "` but the file does not exist. Scaffold the stub via `cp plugins/soleur/skills/ship/references/followthrough-stub-template.sh " + $s + "` and customize before filing the issue.")
    }
  }'
  exit 0
fi
if [[ ! -x "$SCRIPT_ABS" ]]; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through script is not executable; chmod " "$CMD"
  jq -n --arg s "$SCRIPT_REL" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: script `" + $s + "` is not executable. Run `chmod +x " + $s + "` before filing.")
    }
  }'
  exit 0
fi

# Validate `earliest` parses via `date -u -d`. The sweeper uses the same
# command at iso_to_epoch — keeping the validator in sync.
if ! date -u -d "$EARLIEST" +%s >/dev/null 2>&1; then
  emit_incident "wg-pm-class-followthrough-for-operator-dogfood" deny \
    "Follow-through earliest= must parse via date -u" "$CMD"
  jq -n --arg e "$EARLIEST" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: `earliest=" + $e + "` does not parse. Use ISO-8601 UTC, e.g. `earliest=2026-05-22T15:00:00Z`.")
    }
  }'
  exit 0
fi

# All checks passed.
exit 0
