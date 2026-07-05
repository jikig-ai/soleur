#!/usr/bin/env bash
# context-reviewed-gate.sh — PreToolUse(Bash) audit tripwire for `last_reviewed`.
#
# Issue: #5999. ADR-086 (freshness-last-reviewed-source-fix-and-audit-tripwire).
#
# WHAT THIS IS: a DETECTIVE audit tripwire, NOT a preventive integrity guarantee.
# When a commit made through the Claude Code Bash tool REMOVES or CHANGES a
# `last_reviewed:` line in a `*.md` file, this gate requires the commit message
# to carry an explicit `Context-Reviewed:` trailer declaring that a human review
# actually happened. Undeclared attempts are DENIED and logged to the local
# incident ledger. The trailer is self-attestable — an automated writer that
# knows the convention can emit `Context-Reviewed: all` and pass — so this gate
# RELOCATES the honor-system boundary to a single greppable, incident-logged
# point; it does not prove human review. It is bypassed by commits outside the
# Bash tool (Warp / IDE / CI / Inngest) and by non-canonical key spellings. The
# real integrity comes from the source-level fixes to the known automated
# writers (see ADR-086 §Phase 4); this gate is the tripwire for future/unknown
# LOCAL agent bumps.
#
# Contract (PreToolUse(Bash)): reads `.tool_input.command` + `.cwd` on stdin.
#
# Fire (deny) ONLY when ALL hold:
#   1. the command is a real `git commit` (bodies/heredocs stripped first so a
#      message documenting `git commit` does not self-trigger — #5192);
#   2. the commit's `*.md` delta (staged, UNION working-tree for -a/-am/-o/
#      pathspec — closes the `git commit -am` default-path bypass) REMOVES or
#      CHANGES a `last_reviewed:` line (a pure net-new ADDITION — only `+`, no
#      `-` — is EXEMPT: no trailer-fatigue, no self-trip on first adoption);
#   3. no `Context-Reviewed:` trailer is present in ANY message source
#      (multi -m, -am, --message=, -F/--file).
#
# Fail-open split:
#   * benign  (not a commit / no `*.md` delta / no removed-or-changed
#     `last_reviewed`) → silent `exit 0`.
#   * error   (unresolvable cwd on a real commit, -F file unreadable) →
#     `emit_incident … warn … hook_self_fault` then `exit 0` (NEVER bricks a
#     commit; distinct from benign so the fault is visible in the ledger).
#
# Mirrors follow-through-directive-gate.sh (the PreToolUse(Bash) precedent) for
# strip_command_bodies / resolve_command_cwd / emit_incident usage.

set -eo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "")"' 2>/dev/null || echo 'CMD=""')"
: "${CMD:=}"

# 1. Trigger only on a real `git commit`. Strip commit bodies/heredocs so a
#    message that merely documents `git commit` is not mistaken for one (#5192).
#    `[^&|;]*` keeps the git↔commit span inside a single command segment so
#    `git add . && git commit` still resolves to the real `git commit`.
SCAN=$(strip_command_bodies "$CMD")
if ! echo "$SCAN" | grep -qE '\bgit\b[^&|;]*\bcommit\b'; then
  exit 0
fi

# 2. Resolve the target repo (handles `git -C X` / `cd X && git commit`), not
#    bare `.cwd`. Unresolvable on a real commit → error fail-open + incident.
WORK_DIR=$(resolve_command_cwd "$CMD" "$INPUT")
if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
  emit_incident "context-reviewed-hook-self-fault" warn \
    "context-reviewed-gate: unresolvable cwd on git commit" "$CMD" PreToolUse hook_self_fault
  exit 0
fi

# 3. Compute the `last_reviewed` delta. Staged (--cached) always; UNION the
#    working-tree delta when the commit is working-tree-inclusive — `-a`/`-am`
#    (short cluster containing `a`), `--all`, `-o`/`--only`, or an explicit
#    `*.md` pathspec — because those commit content NOT in the index. This is
#    the P0-2 fix: `git commit -am` (the default agent path) otherwise bypassed
#    the `--cached`-only detection with no incident.
DELTA=$(git -C "$WORK_DIR" diff --cached -U0 -- '*.md' 2>/dev/null || true)
if echo "$SCAN" | grep -qE '(^|[[:space:]])-[A-Za-z]*a[A-Za-z]*([[:space:]]|=|$)|(^|[[:space:]])--all([[:space:]]|=|$)|(^|[[:space:]])(-[A-Za-z]*o[A-Za-z]*|--only)([[:space:]]|=|$)' \
   || echo "$SCAN" | grep -qE '\bcommit\b[^&|;]*[[:space:]][^-][^[:space:]]*\.md([[:space:]]|$)'; then
  DELTA+=$'\n'
  DELTA+=$(git -C "$WORK_DIR" diff -U0 -- '*.md' 2>/dev/null || true)
fi

# 4. Fire only on a REMOVED or CHANGED `last_reviewed` line. A re-bump shows
#    `-old`/`+new`; a deletion shows `-old`; a net-new adoption shows only
#    `+new` (no `-` line) and is EXEMPT. Widened for quoting / space-before-
#    colon / case (grep -E: `[[:space:]]`, not `\s`). The `--- a/<file>` diff
#    header starts with `-` but carries no `last_reviewed` token, so it never
#    false-matches.
if ! echo "$DELTA" | grep -qE '^-.*["'"'"']?[Ll]ast_[Rr]eviewed["'"'"']?[[:space:]]*:'; then
  exit 0
fi

# 5. Extract the commit message from ALL sources so a trailer in any of them is
#    honored: every -m/--message/--message= value (multi-`-m` concatenated), the
#    combined `-am` message arg, and -F/--file contents. An -F file unreadable
#    at hook time on a real last_reviewed commit → error fail-open + incident.
MSG=$(printf '%s' "$CMD" | perl -0777 -ne '
  my @m;
  while (/(?:^|\s)(?:-[A-Za-z]*m|--message)(?:=|\s+)("(?:[^"\\]|\\.)*"|'"'"'(?:[^'"'"'\\]|\\.)*'"'"'|[^\s]+)/g) {
    my $v=$1; $v=~s/^["'"'"']//; $v=~s/["'"'"']$//; push @m,$v;
  }
  print join("\n",@m);
' 2>/dev/null || true)

BODY_FILE=$(printf '%s' "$CMD" | grep -oE -- '(^|[[:space:]])(-F|--file)[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}' || true)
if [[ -n "$BODY_FILE" ]]; then
  [[ "$BODY_FILE" != /* ]] && BODY_FILE="$WORK_DIR/$BODY_FILE"
  if [[ -r "$BODY_FILE" ]]; then
    MSG+=$'\n'
    MSG+=$(cat "$BODY_FILE" 2>/dev/null || true)
  else
    emit_incident "context-reviewed-hook-self-fault" warn \
      "context-reviewed-gate: -F message file unreadable on commit" "$CMD" PreToolUse hook_self_fault
    exit 0
  fi
fi

# 6. Trailer present → allow (attributable). Absent → deny + incident.
if printf '%s' "$MSG" | grep -qE 'Context-Reviewed:[[:space:]]*(all|[^[:space:]]+)'; then
  exit 0
fi

emit_incident "context-reviewed-gate" deny \
  "last_reviewed change committed without a Context-Reviewed trailer" "$CMD"
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "BLOCKED: this commit removes or changes a `last_reviewed:` line in a Markdown file but carries no `Context-Reviewed:` trailer. `last_reviewed` is a cooperative freshness signal (ADR-086) — an undeclared bump silently ages the review clock so downstream staleness checks read false confidence. If a human review actually happened, add a final commit-message paragraph declaring it: `Context-Reviewed: all` (or `Context-Reviewed: <path>`). If this is an automated reconcile that did NOT review the doc, bump `last_updated` instead and leave `last_reviewed` unchanged. This gate is a detective audit tripwire, not a wall; the attempt has been logged to the local incident ledger."
  }
}'
exit 0
