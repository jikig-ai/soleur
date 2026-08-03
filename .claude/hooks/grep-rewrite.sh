#!/usr/bin/env bash
# PreToolUse hook for Bash. Neutralizes the ugrep `grep` shim by PREPENDING a
# `grep()` shell-function redefinition to the command. The command itself is
# left BYTE-IDENTICAL.
#
# Issue #7165. ADR-160 (PreToolUse hooks may rewrite tool input).
# Source learning: knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md
#
# WHY
# ---
# Claude Code's shell snapshot installs a bash FUNCTION named `grep` that
# re-execs the `claude` binary with argv[0]=ugrep. For patterns whose cost
# depends on literal reachability, ugrep built a DFA that reached 9.5 GB RSS
# against a single 21 kB file and froze a 31 GB desktop, killing six sessions.
#
# THE MECHANIC — why a prefix and not a parser
# --------------------------------------------
# v1 of this design found `grep` tokens in the command string and spliced
# `command grep` over them. A 5-agent panel reproduced SEVEN concrete failures
# in that mechanic, four of which corrupt commands that work today (quoted data
# carrying the word grep, `git grep`, `pgrep`, `xargs grep`, brace expansion,
# heredoc bodies, byte-vs-character offset desync).
#
# This version emits:
#
#     grep(){ ...command grep... }; <original command, untouched>
#
# and lets BASH resolve the name at execution time. Nothing is parsed, so
# nothing can be mis-parsed. The two forms v1 declared unfixable — `G=grep; $G`
# and `eval "grep ..."` — are solved for free, because they too resolve the name
# through the shell.
#
# This is why the `grep`-substring gate below is allowed to be SLOPPY. A false
# positive costs one inert function definition; it can never corrupt a command.
# That property is the entire point of this design.
#
# THE PAYLOAD SHAPE — measured, not assumed
# -----------------------------------------
# `updatedInput` REPLACES `tool_input` wholesale; it does NOT merge. Measured
# 2026-08-03 in an isolated `claude -p` (see UPDATED-INPUT-PAYLOAD-SHAPE.md): a
# hook emitting `updatedInput: {"command": ...}` against a call carrying
# `run_in_background: true`, `timeout: 45000` and a `description` dropped all
# three, and the command ran in the FOREGROUND. So the envelope is built from
# the WHOLE `tool_input` with only `.command` replaced.
#
# `permissionDecision` is NEVER emitted, at any depth. Emitting `allow` here
# would bypass the permission system for every Bash call carrying a `grep`
# substring — roughly half of them. A sibling hook's `deny` still wins over this
# hook's `updatedInput` (measured); that ordering is relied upon, not defeated.
#
# FAIL-OPEN BY CONSTRUCTION
# -------------------------
# This hook runs on 100% of Bash calls, not just the ~50% carrying grep. A
# PreToolUse hook exiting non-zero BLOCKS the call, so every exit path here is
# `exit 0` and `set -e` is deliberately absent. The worst failure this hook can
# produce is "no rewrite happened".

# --- AC12: kill switch, FIRST executable statement -------------------------
# Before `cat`, before sourcing, before any subprocess. This is the rollback
# lever for a hook on the hot path of every Bash call; it must not itself
# depend on anything that could be what is broken.
# Convention matches SOLEUR_DISABLE_HOOK_INPUT_ASK / _SESSION_STATE / _AGENT_TOKEN_TEE.
[[ "${SOLEUR_DISABLE_GREP_REWRITE:-}" == "1" ]] && exit 0

# -u and pipefail, never -e: see FAIL-OPEN above.
set -uo pipefail

# ${BASH_SOURCE[0]%/*} rather than $(cd "$(dirname …)" && pwd): the nested
# command substitution cost TWO forks on 100% of Bash calls for a value the
# parameter expansion yields with none.
SGR_DIR="${BASH_SOURCE[0]%/*}"

# The idempotency sentinel (AC11) is the loop variable's NAME, not a comment.
# The prefix is a single `;`-joined line, so a `#` comment inside it would
# comment out the original command that follows — the one corruption this
# design is built to make impossible. A distinctive identifier costs no tokens
# and cannot be commented out.
#
# NB it contains the substring `grep`, so the idempotency check MUST run before
# the grep-substring gate below, or a re-entrant call would fall through it.
SGR_SENTINEL='_soleur_grep_rw'

# --- The injected prefix ---------------------------------------------------
# Single-quoted: every `"$@"` and `"$_soleur_grep_rw"` must reach the emitted
# command LITERALLY, unexpanded. There is no apostrophe anywhere inside it.
#
# Arm list: all 12 bypass arms of the live shim, mirrored BYTE-EXACT (verified
# 2026-08-03 against ~/.claude/shell-snapshots). A command using any of them
# receives `command grep "$@"` with NO injected flags — exactly what it
# receives today.
#
# Non-bypass arm: the shim passes
#   -G --ignore-files --hidden -I --exclude-dir={.git,.svn,.hg,.bzr,.jj,.sl}
# Of those, `-G` is GNU grep's default (BRE) and `--hidden` is a ugrep flag for
# behavior GNU grep already has, so both are dropped as no-ops. `--ignore-files`
# (ugrep's .gitignore support) has no GNU grep equivalent.
#
# There are TWO semantic deltas, not one (an earlier draft of this comment said
# one, and review measured it false):
#   1. .gitignore is no longer honoured.
#   2. node_modules/dist/.next are excluded UNCONDITIONALLY — including in a repo
#      that COMMITS them, where ugrep would have searched them. Routine for a
#      published npm package shipping dist/.
#
# And this is a NET SLOWDOWN vs today, not a speedup. Three-arm measurement on
# this repo (101,110 files, 87,988 under node_modules), interleaved:
#   today  (ugrep --ignore-files)      243 ms
#   new    (GNU grep + 3 excludes)     548 ms   <- 2.25x REGRESSION
#   new    (without the 3 excludes)  3,179 ms
# At an IDENTICAL file set GNU grep is 4.0x slower than ugrep, so the dominant
# term is the single-threaded-engine swap, not the .gitignore loss. The excludes
# are what keep the regression bounded; they do not buy parity. Accepted: this
# trade buys elimination of the 9.5 GB DFA blowup, and both arms are sub-second.
# See ADR-160 §Accepted divergences.
SGR_PREFIX='grep(){ local _soleur_grep_rw; for _soleur_grep_rw in "$@"; do case "$_soleur_grep_rw" in -*-filter*|-*-pager*|-*-view*|-*-format-open*|-*-config*|---*|-@*|-*-save-config*|-[Zz]*|-[!-]*[Zz]*|--null|--null-data) command grep "$@"; return;; esac; done; command grep -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next "$@"; }; '

# --- Lazy telemetry --------------------------------------------------------
# incidents.sh is ~18 kB and this hook is on the hot path of every Bash call
# (AC17: p95 < 50 ms). It is sourced ONLY on the paths that actually emit —
# never on the happy path.
sgr_emit() { # <rule_id> <event> <prefix> <cmd> <kind>
  if ! declare -f emit_incident >/dev/null 2>&1; then
    # shellcheck source=lib/incidents.sh
    source "$SGR_DIR/lib/incidents.sh" 2>/dev/null || return 0
  fi
  declare -f emit_incident >/dev/null 2>&1 || return 0
  emit_incident "$1" "$2" "$3" "$4" "PreToolUse" "${5:-rule_event}"
}

# --- Input -----------------------------------------------------------------
# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined; the hook then dies at the call site, prints nothing and exits
# non-zero. For a DENY hook that is #7164 defect 2; for this hook it would
# BLOCK the tool call. Neither is acceptable.
source "$SGR_DIR/lib/hook-input.sh"

# This hook runs `set -uo pipefail` WITHOUT -e, so a missing helper would make
# hook_parse_input return 127, `!` would invert that to true, and the reporting
# helpers would be 127 too — reaching `exit 0` with no row. Assert explicitly.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[grep-rewrite] hook-input helper missing — no rewrite for this call" >&2
  exit 0
fi

INPUT=$(cat)

# ADR-156: hook stdin is model-controlled and untrusted. ADR-157: a hook that
# cannot parse its input never continues SILENTLY.
#
# It also never asks HERE: `hook_input_should_ask` is true only for the
# designated responder (guardrails), and this hook is a REWRITER, not a guard.
# A failed parse costs a missing optimization, not a missing safety check, so
# escalating would spend an operator prompt on a non-event. The fault is still
# recorded by hook_input_report as `hook-input-<reason>` carrying
# `hook=grep-rewrite`.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "grep-rewrite"
  exit 0
fi

# The settings matcher is `Bash`, but a matcher is an upstream invariant this
# hook cannot verify (ADR-156). An absent tool_name is tolerated so the suite's
# minimal fixtures stay legible.
[[ -z "$HOOK_TOOL_NAME" || "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0

CMD="$HOOK_CMD"
[[ -z "$CMD" ]] && exit 0

# --- AC11: idempotency / fixed point ---------------------------------------
# Re-entrancy was measured NOT to happen (one PreToolUse invocation per call,
# 2026-08-03), so this is defense in depth against a future runtime that does
# re-submit — and against a command that legitimately carries our own output.
case "$CMD" in *"$SGR_SENTINEL"*) exit 0 ;; esac

# --- The deliberately sloppy gate ------------------------------------------
# `git grep`, `pgrep`, `ripgrep`, and the literal word inside quoted data all
# match here and all receive an inert function definition they never call.
# That is correct and intended: see THE MECHANIC above.
case "$CMD" in *grep*) ;; *) exit 0 ;; esac

# --- Dark-launch / observe-only mode ---------------------------------------
# Emits what it WOULD do and returns no envelope. Used for the corpus replay
# soak (wg-dark-launch-deploy-gates) and available as a diagnostic.
if [[ "${SOLEUR_GREP_REWRITE_OBSERVE:-}" == "1" ]]; then
  sgr_emit "grep-rewrite-would-rewrite" "info" \
    "grep shim neutralized by prefixed function redefinition" "$CMD"
  exit 0
fi

# --- Emit ------------------------------------------------------------------
# Built from the WHOLE `.tool_input` because updatedInput REPLACES it (measured;
# see THE PAYLOAD SHAPE above). `hookEventName` MUST ride in the same object or
# Claude Code silently ignores the envelope and the original command runs —
# a test asserting only the updatedInput value would pass while nothing applied
# (DEFER-DECISION-PAYLOAD-SHAPE.md).
# --arg carries the 453-byte CONSTANT prefix, never the command. Passing
# prefix+command as one argv entry hit Linux MAX_ARG_STRLEN (32 * PAGE_SIZE =
# 131072): bisected to the byte, 453 + 130,619 = 131,072, so every command at or
# above 130,619 bytes silently failed to rewrite. Concatenating INSIDE jq makes
# the limit structurally unreachable — verified byte-exact at 200 kB.
#
# This also makes the `[[ -z "$CMD" ]]` guard above load-bearing for a second
# reason: `$pre + .command` raises on a null .command, where the old form would
# instead FABRICATE a tool_input object containing a grep() definition and no
# user command. Do not reorder that guard below this emit.
OUT=$(printf '%s' "$INPUT" \
  | jq -c --arg pre "$SGR_PREFIX" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input | .command = ($pre + .command))}}' \
      2>/dev/null) || OUT=""

# jq's EXIT CODE is not sufficient: a jq that exits 0 while emitting non-JSON
# would otherwise be printed verbatim as an envelope. Measured — a stub that
# passed through the parse call and emitted garbage on this one made the hook
# print `not json at all` on stdout. Validate the bytes, not the status.
if [[ -n "$OUT" ]] && ! printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; then
  OUT=""
fi

if [[ -z "$OUT" ]]; then
  # The parse succeeded but the envelope could not be built. Distinct from a
  # hook-input fault, and the only failure mode this hook owns outright.
  sgr_emit "grep-rewrite-disarm" "warn" \
    "grep-rewrite could not build updatedInput; command left unmodified" "" \
    "hook_self_fault"
  exit 0
fi

printf '%s\n' "$OUT"
exit 0
