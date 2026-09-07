#!/usr/bin/env bash
# PreToolUse hook on Bash.
# Blocks `pkill -f <pat>` / `pgrep -f <pat>` when <pat> also appears ELSEWHERE in
# the same submitted command — i.e. the pattern matches the text of the thing
# doing the matching.
#
# Source class: "a scan whose corpus includes the scanner's own text."
# `pkill -f` matches an unanchored regex against the WHOLE JOINED command line of
# every process, and the invoking shell, its wrappers, and any sibling watcher
# spawned as `bash -c '…<pat>…'` all carry <pat> in their argv. pkill excludes
# only its OWN pid — not its parent, not its siblings.
#
# Why a hook and not another learning: this class is documented in ~31 learning
# files across four months, in work/SKILL.md and git-worktree/SKILL.md, and the
# sanctioned replacement already ships as plugins/soleur/scripts/lib/proc.sh
# (list_runs / kill_mine, which resolve ownership via /proc/<pid>/cwd and exclude
# self + ancestry). It kept recurring because the command is typed from memory.
# Prose has had four months and ~31 attempts; this is the mechanical gate.
# Measured on PR #7888: the narrowing `pkill -f '^bash .*<script>\.sh'` does NOT
# fix it — `^` anchors at the start of the joined cmdline, not an argv slot, so a
# `bash -c '…<script>.sh…'` watcher still matches.
#
# Detection:
#   tool_name == Bash
#   AND the command uses `pkill -f` or `pgrep -f`
#
# UNCONDITIONAL for `-f`, and that is the point. The Bash tool runs each command
# as `bash -c '<the whole command>'`, so the invoking wrapper's OWN argv contains
# the pattern by construction — verified from this session's `ps` output. `-f`
# matches against the full command line of every process, and pkill/pgrep exclude
# only their own pid, never the parent. So a `-f` pattern ALWAYS matches at least
# the shell that issued it, plus any sibling watcher carrying it. There is no
# "safe" pattern to allow-list, which is why an "appears elsewhere in the command"
# heuristic (the first draft of this hook) missed the literal incident case:
#   until ! pgrep -f "run-registered-suites"; do sleep 5; done
# where the pattern appears ONLY inside the pgrep invocation and the collision is
# with the wrapper.
#
# Escape hatches that remain open, so this is a redirect and not a wall:
#   * `pgrep`/`pkill` WITHOUT `-f` match the process NAME only — no self-match.
#   * a PID captured at spawn (`cmd & pid=$!`) names the process exactly.
#   * proc.sh list_runs / kill_mine resolve ownership via /proc/<pid>/cwd.
#
# Fail-open by construction: any parse failure exits 0 with no decision.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$TOOL" == "Bash" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$CMD" ]] && exit 0

# Does the command use pkill/pgrep with -f? Match the flag in any bundled form
# (-f, -af, -fl) and as a separate token.
# HERESTRING, deliberately (#6992 / #7024, enforced by
# .claude/hooks/grep-q-pipe-guard.test.sh). `grep -q` exits on its first match,
# so a piped producer can die on SIGPIPE — and in a policy gate that reads as
# "no match", i.e. fail-OPEN. A herestring has no producer to kill.
if ! grep -qE "\b(pkill|pgrep)\b[^|;&]*[[:space:]]-[a-zA-Z]*f" <<<"$CMD" 2>/dev/null; then
  exit 0
fi

TOOL_USED="$(grep -oE '\b(pkill|pgrep)\b' <<<"$CMD" 2>/dev/null | head -1 || echo "pkill")"

reason="BLOCKED: \`${TOOL_USED} -f\` is self-matching here. \`-f\` matches the pattern against the FULL COMMAND LINE of every process, and the Bash tool runs your command as \`bash -c '<the whole command>'\` — so the invoking wrapper's own argv contains your pattern. pkill/pgrep exclude only their own pid, never the parent or a sibling watcher.

Narrowing the pattern does NOT fix it: \`^\` anchors at the start of the joined command line, not at an argv slot, so \`^bash .*foo\\.sh\` still matches a \`bash -c '…foo.sh…'\` watcher (measured, PR #7888).

Use one of:
  source plugins/soleur/scripts/lib/proc.sh
  list_runs                 # enumerate first, decide second
  kill_mine                 # only this worktree's own runs (ownership via /proc/<pid>/cwd)

  cmd & pid=\$!; kill \"\$pid\"    # a captured PID names the process exactly
  ${TOOL_USED} <name>                 # without -f, matches the process NAME only"

jq -nc --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null

exit 0
