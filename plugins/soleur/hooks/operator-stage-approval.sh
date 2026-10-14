#!/usr/bin/env bash
# PreToolUse hook: turn the HARNESS approval prompt into the human acknowledgement
# of a generated operator script's production write (ADR-264).
#
# WHAT IT DOES. A staged operator script write is
#     bash <script> --stage <name> --apply --plan-digest <d> [--rotate-token]
# When the agent issues exactly that, this hook (1) recognises the script by its
# CONTENT (the `SOLEUR-GENERATED-OPERATOR-SCRIPT v2` header line, never a
# basename), (2) mints a one-time receipt bound to the digest of THAT command on
# the human's machine, (3) rewrites the command to carry the receipt's nonce as an
# environment prefix immediately before `bash`, and (4) answers `ask`, so the
# harness shows the human the rewritten command plus the stage's plain-language
# impact and rollback and waits for their decision. The script recomputes the
# digest, finds the record, consumes it before its first write, and unsets the
# nonce before any child runs. See the "Approval receipts" section of plugins/soleur/scripts/lib/operator-script.sh for the record format.
#
# WHAT IT NEVER DOES (each is a mutation row of the hook suite):
#   - execute the script it fingerprints. The v2 header is agent-writable, so
#     running `--list` from here would hand the agent code execution outside its
#     sandbox; the stage lines are read statically with grep.
#   - mint for anything but ONE simple command: `[cd <dir> &&] bash <script> ...`
#     with no pipe, `;`, trailing `&&`, redirect, substitution or glob. The human
#     approves one exact string; a compound one would approve more than they read.
#   - mint under bypassPermissions / dontAsk / auto, or when the permission mode is
#     unknown. Interactive-vs-headless is decided by CLAUDE_CODE_ENTRYPOINT: `cli`,
#     `claude-vscode`, `claude-desktop` and `claude-desktop-3p` are interactive
#     (they show a prompt a person answers); `sdk-cli` and anything else is
#     headless. ONLY `cli` and `sdk-cli` were measured (Claude Code 2.1.287,
#     .claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md "Operator stage approval"); the
#     other three names are an allowlist taken on trust and recorded as unmeasured
#     in ADR-264. An undeterminable mode emits `defer`, never allow.
#   - mint on a headless invocation. It answers `defer` and the run waits; a person
#     resumes the session interactively (`claude --resume`), the hook runs again
#     under an interactive entrypoint, and the person is asked at the prompt. There
#     is no environment variable, settings key or file that stands in for that
#     answer (an earlier draft had a resume marker in the resumed process's
#     environment; a settings-level `env` block can set it without a person, so it
#     was removed).
#   - let an input that already carries the nonce variable name through (deny), or
#     let a Bash/Monitor command or a Write/Edit path touch the receipt
#     directory (deny; reliable only for the path tools — string matching on a shell
#     command is a speed bump, not a wall).
#   - break an unrelated call. A call that is not a candidate returns at once with
#     no jq dependency; only a candidate fails closed (a deny envelope) when jq is
#     missing, so a missing jq on a founder machine cannot deny every Bash call.
#
# HONEST THRESHOLD: the receipt is a same-user file; this resists an agent that
# follows instructions, not one that deliberately forges a record (ADR-264).
#
# DECISION PRECEDENCE across hooks (measured on 2.1.287, ADR-264): deny > defer > ask
# > allow. This hook answers deny, defer or ask and never allow, so another hook's
# allow cannot turn a prompt into a silent run.
#
# ADR-162 AMENDMENT: this hook is the second named PreToolUse rewriter and, unlike
# the grep rewriter, emits a permission decision alongside updatedInput (`ask`) and
# FAILS CLOSED for a candidate. It never
# composes with another rewriter on the same call: the accepted command form is a
# single simple command, so grep-rewrite.sh's predicate does not match it.

set -uo pipefail
# No pathname expansion: the command text is split into words below and must never glob.
set -f
# Byte semantics: `${s:i:1}` is O(1) per character in the C locale and the tokenizer
# offsets (used to splice the nonce) are then byte offsets in both directions.
export LC_ALL=C

[[ "${SOLEUR_DISABLE_OPERATOR_STAGE_APPROVAL_HOOK:-0}" == "1" ]] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat)"

trace() {
  [[ -n "${SOLEUR_OPERATOR_STAGE_APPROVAL_TRACE:-}" ]] || return 0
  printf '%s\n' "$1" >> "$SOLEUR_OPERATOR_STAGE_APPROVAL_TRACE" 2>/dev/null || true
}

# --- prefilter (R4): no jq, no parsing, nothing that can fail for a normal call ----
# The receipt directory, spelled exactly as soleur_approval_dir spells it (a test pins
# the two together): the path arm below must work without the library.
approvals_fragment="state/soleur/approvals"
APPROVALS_DIR="${XDG_STATE_HOME:-${HOME:-/nonexistent}/.local/state}/soleur/approvals"
candidate=0
case "$INPUT" in
  *--apply*|*SOLEUR_APPROVAL_NONCE*|*"$approvals_fragment"*) candidate=1 ;;
esac
# The write path tools are checked on their CANONICALIZED path (a traversal or a symlink can
# spell the receipt directory without the fragment), so they are candidates whenever jq can
# parse them. A missing jq makes them a no-op here, never a deny: denying every Write on a
# machine without jq would brick the session, and the path arm is the lesser of the two risks.
# Read is not a candidate: a record is named sha256(nonce) and holds only a digest, a
# timestamp and a session id, so reading one yields nothing a forger needs.
if [[ "$INPUT" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"(Write|Edit|MultiEdit|NotebookEdit)\" ]]; then
  if command -v jq >/dev/null 2>&1; then candidate=1; fi
fi
if [[ "$candidate" -eq 0 ]]; then
  trace "ran verdict=noop reason=not-candidate"
  exit 0
fi

emit_deny() { # <fixed reason> — no jq, no interpolation of agent-controlled text
  trace "ran verdict=deny reason=$2"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

command -v jq >/dev/null 2>&1 || emit_deny "Soleur's operator-stage approval check needs jq and it is not installed, so this command was refused. Install jq and ask again." "no-jq"

# ONE jq call for the four scalar fields (none can hold a newline once sanitised).
JQ_OUT="$(printf '%s' "$INPUT" | jq -r '(.tool_name // ""), (.permission_mode // ""), (.session_id // "unknown"), (.cwd // "") | gsub("[\\n\\r]"; " ")' 2>/dev/null)" || JQ_OUT=""
# Split on newlines with parameter expansion (no fork, and no `read`: the prompt census
# in operator-script.test.sh Guard 4 treats every `read` under plugins/soleur as a prompt).
TOOL="${JQ_OUT%%$'\n'*}"; JQ_REST="${JQ_OUT#*$'\n'}"
MODE="${JQ_REST%%$'\n'*}"; JQ_REST="${JQ_REST#*$'\n'}"
SESSION="${JQ_REST%%$'\n'*}"; CWD_IN="${JQ_REST#*$'\n'}"
MODE="${MODE//[^A-Za-z]/}"
[[ -n "$SESSION" ]] || SESSION="unknown"

# canonical_path <path> — absolute, `..` and `.` collapsed, symlinks resolved when
# the target exists (the parent when it does not), so a traversal spelling of the
# receipt directory is still recognised.
canonical_path() {
  local p="$1" d b
  [[ "$p" == /* ]] || p="${CWD_IN:-$PWD}/${p}"
  if readlink -m -- "$p" 2>/dev/null; then return 0; fi
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s' "$p"; return 0; }
  b="$(basename "$p")"
  printf '%s/%s' "$d" "$b"
}

under_approvals_dir() {
  local c; c="$(canonical_path "$1")"
  local root; root="$(canonical_path "$APPROVALS_DIR")"
  [[ "$c" == "$root" || "$c" == "$root"/* ]]
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    P="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // ""' 2>/dev/null)" || P=""
    if [[ -n "$P" ]] && under_approvals_dir "$P"; then
      emit_deny "That path holds Soleur approval receipts, which only the approval prompt may create. Nothing was changed." "receipt-dir-path"
    fi
    trace "ran verdict=noop reason=path-not-receipt-dir"
    exit 0
    ;;
  Bash|Monitor) ;;
  *) trace "ran verdict=noop reason=tool-not-handled"; exit 0 ;;
esac

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)" || COMMAND=""

# A nonce already present in what the agent submitted is never honoured: the nonce
# is bearer-only and enters a command through this hook and nowhere else.
case "$COMMAND" in
  *SOLEUR_APPROVAL_NONCE*)
    emit_deny "That command carries an approval token. Approval tokens are added by Soleur's approval prompt, never typed into a command. Nothing was changed." "nonce-in-input" ;;
esac
case "$COMMAND" in
  *"$approvals_fragment"*|*"$APPROVALS_DIR"*)
    emit_deny "That command touches Soleur's approval receipts, which only the approval prompt may create or read. Nothing was changed." "receipt-dir-command" ;;
esac
if [[ "$TOOL" == "Monitor" ]]; then
  trace "ran verdict=noop reason=monitor-clean"
  exit 0
fi
case "$COMMAND" in
  *--apply*) ;;
  *) trace "ran verdict=noop reason=no-apply"; exit 0 ;;
esac

# --- tokenizer for ONE simple command ---------------------------------------------
# Fills TOK[] (the words, quotes removed), TOKOFF[] (each word's byte offset in the
# original string) and TOKOP[] (1 for an unquoted `&&`). Returns 1 on any shell
# syntax beyond words, quotes and a standalone `&&`.
tokenize() {
  local s="$1" i=0 n c cur="" intok=0 q="" start=0 prev
  n=${#s}
  TOK=(); TOKOFF=(); TOKOP=()
  while (( i < n )); do
    c="${s:i:1}"
    if [[ -n "$q" ]]; then
      if [[ "$c" == "$q" ]]; then
        q=""
      elif [[ "$q" == '"' && ( "$c" == '$' || "$c" == '`' || "$c" == '\' ) ]]; then
        return 1
      else
        cur+="$c"
      fi
    else
      case "$c" in
        "'"|'"')
          q="$c"
          if (( ! intok )); then intok=1; start=$i; fi ;;
        ' '|$'\t')
          if (( intok )); then
            TOK[${#TOK[@]}]="$cur"; TOKOFF[${#TOKOFF[@]}]="$start"; TOKOP[${#TOKOP[@]}]=0
            cur=""; intok=0
          fi ;;
        '&')
          prev=""; (( i > 0 )) && prev="${s:i-1:1}"
          [[ "${s:i+1:1}" == "&" && ( "${s:i+2:1}" == " " || -z "${s:i+2:1}" ) && ( $i -eq 0 || "$prev" == " " ) && $intok -eq 0 ]] || return 1
          TOK[${#TOK[@]}]="&&"; TOKOFF[${#TOKOFF[@]}]="$i"; TOKOP[${#TOKOP[@]}]=1
          i=$((i + 1)) ;;
        ';'|'|'|'<'|'>'|'('|')'|'$'|'`'|'\'|$'\n'|$'\r'|'!'|'*'|'?'|'['|']'|'{'|'}'|'~'|'#')
          return 1 ;;
        *)
          if (( ! intok )); then intok=1; start=$i; fi
          cur+="$c" ;;
      esac
    fi
    i=$((i + 1))
  done
  [[ -z "$q" ]] || return 1
  if (( intok )); then
    TOK[${#TOK[@]}]="$cur"; TOKOFF[${#TOKOFF[@]}]="$start"; TOKOP[${#TOKOP[@]}]=0
  fi
  return 0
}

ACCEPTED_FORM="bash <script> --stage <name> --apply --plan-digest <digest> [--rotate-token], as ONE simple command (optionally preceded by cd <dir> &&), with no pipe, semicolon, redirect, substitution or other command"

is_v2_script() { # <file>
  [[ -f "$1" ]] || return 1
  [[ "$(sed -n '2p' "$1" 2>/dev/null)" == "# SOLEUR-GENERATED-OPERATOR-SCRIPT v2" ]]
}

# loose_v2_mention: does the command text name an existing v2 generated script at
# all (for a command that did NOT parse as one simple command)?
loose_v2_mention() {
  local w base
  for w in $COMMAND; do
    w="${w//\'/}"; w="${w//\"/}"
    [[ "$w" == *.sh ]] || continue
    [[ "$w" == /* ]] || w="${CWD_IN:-$PWD}/${w}"
    if is_v2_script "$w"; then return 0; fi
  done
  return 1
}

# A command this long is not one the person could read and approve as a single exact
# line, and the tokenizer is character-at-a-time. Treat it as not-simple.
TOKENIZED=1
if (( ${#COMMAND} > 4096 )); then TOKENIZED=0; else tokenize "$COMMAND" || TOKENIZED=0; fi
if (( ! TOKENIZED )); then
  if loose_v2_mention; then
    emit_deny "That is a staged Soleur operator-script apply in a form Soleur cannot ask the person about. Issue it as ${ACCEPTED_FORM}. Nothing was changed." "compound-command"
  fi
  trace "ran verdict=noop reason=not-simple-and-no-v2-script"
  exit 0
fi

# Strip an optional leading `cd <dir> &&`.
base=0
CD_DIR=""
if (( ${#TOK[@]} >= 3 )) && [[ "${TOK[0]}" == "cd" && "${TOKOP[2]}" == "1" ]]; then
  CD_DIR="${TOK[1]}"; base=3
fi
for ((k = 0; k < ${#TOK[@]}; k++)); do
  if [[ "${TOKOP[k]}" == "1" ]] && (( k != 2 || base != 3 )); then
    if loose_v2_mention; then
      emit_deny "That is a staged Soleur operator-script apply in a form Soleur cannot ask the person about. Issue it as ${ACCEPTED_FORM}. Nothing was changed." "compound-command"
    fi
    trace "ran verdict=noop reason=extra-and-no-v2-script"
    exit 0
  fi
done

if (( ${#TOK[@]} - base < 2 )) || [[ "${TOK[base]}" != "bash" ]]; then
  if loose_v2_mention; then
    emit_deny "That is a staged Soleur operator-script apply in a form Soleur cannot ask the person about. Issue it as ${ACCEPTED_FORM}. Nothing was changed." "not-bash-form"
  fi
  trace "ran verdict=noop reason=not-bash-form"
  exit 0
fi

SCRIPT_ARG="${TOK[base+1]}"
BASH_OFFSET="${TOKOFF[base]}"
BASE_DIR="${CWD_IN:-$PWD}"
if [[ -n "$CD_DIR" ]]; then
  [[ "$CD_DIR" == /* ]] && BASE_DIR="$CD_DIR" || BASE_DIR="${BASE_DIR}/${CD_DIR}"
fi
SCRIPT_PATH="$SCRIPT_ARG"
[[ "$SCRIPT_PATH" == /* ]] || SCRIPT_PATH="${BASE_DIR}/${SCRIPT_PATH}"

if ! is_v2_script "$SCRIPT_PATH"; then
  trace "ran verdict=noop reason=not-v2-script"
  exit 0
fi

# The library is the ONE home of the receipt algorithm (mint here, verify there). It is
# sourced only now, for a real v2 apply: every other call (the path arm above, a
# non-script command) must work when the library is absent.
# shellcheck source=../scripts/lib/operator-script.sh disable=SC1091
if ! source "${HOOK_DIR}/../scripts/lib/operator-script.sh" >/dev/null 2>&1; then
  emit_deny "Soleur's operator-stage approval library is missing, so this command was refused. Update the Soleur plugin." "lib-missing"
fi
REAL="$(soleur_approval_realpath "$SCRIPT_PATH")"

ARGS=()
for ((k = base + 2; k < ${#TOK[@]}; k++)); do ARGS[${#ARGS[@]}]="${TOK[k]}"; done

STAGE=""; DIGEST=""; APPLY=0
k=0
while (( k < ${#ARGS[@]} )); do
  case "${ARGS[k]}" in
    --stage) STAGE="${ARGS[k+1]:-}"; k=$((k + 2)) ;;
    --plan-digest) DIGEST="${ARGS[k+1]:-}"; k=$((k + 2)) ;;
    --apply) APPLY=1; k=$((k + 1)) ;;
    --rotate-token) k=$((k + 1)) ;;
    *) emit_deny "That staged Soleur operator-script command has an argument Soleur will not ask about (${#ARGS[@]} arguments, one not recognised). Issue it as ${ACCEPTED_FORM}. Nothing was changed." "unknown-arg" ;;
  esac
done
if (( APPLY == 0 )); then
  trace "ran verdict=noop reason=no-apply-flag-after-parse"
  exit 0
fi
[[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]] || emit_deny "A staged Soleur operator-script apply needs the plan digest the plan printed. Run the stage without --apply first, then issue the apply command exactly as printed. Nothing was changed." "no-digest"

# Exact first-field match (never a regex built from the agent's stage name: a `.` in it
# would select a different stage's line). First declaration wins, as in the library.
STAGE_LINE=""
if [[ -n "$STAGE" ]]; then
  STAGE_LINE="$(grep -a '^# SOLEUR-STAGE ' "$REAL" 2>/dev/null | sed 's/^# SOLEUR-STAGE //' | awk -F'|' -v s="$STAGE" '$1 == s { print; exit }')" || STAGE_LINE=""
fi
[[ -n "$STAGE_LINE" ]] || emit_deny "That stage is not declared by the script, so Soleur will not ask about it. Run --list to see the stages. Nothing was changed." "unknown-stage"
STAGE_CLASS="$(printf '%s' "$STAGE_LINE" | cut -d'|' -f2)"
IMPACT="$(printf '%s' "$STAGE_LINE" | cut -d'|' -f3)"
ROLLBACK="$(printf '%s' "$STAGE_LINE" | cut -d'|' -f4)"
if [[ "$STAGE_CLASS" != "write" ]]; then
  # A read stage takes no --apply. Refusing it here (instead of letting the call
  # through unasked) keeps `--apply` meaning one thing: a write the person approved.
  emit_deny "That stage is declared read-only, so it takes no --apply. Run it without --apply. Nothing was changed." "apply-on-read-stage"
fi

BINDING="$(soleur_approval_binding_digest "$REAL" "$STAGE" "${ARGS[@]}")"

# --- mode ---------------------------------------------------------------------------
case "$MODE" in
  default|acceptEdits|plan) ;;
  *) emit_deny "Approvals are switched off or cannot be asked in this session (permission mode '${MODE:-unknown}'), so Soleur will not make this production change. Switch to the normal permission mode and ask again. Nothing was changed." "mode-${MODE:-unknown}" ;;
esac

# The impact and rollback sentences are read from the SCRIPT FILE, which the agent can
# edit, so the prompt says so. Control characters are dropped and each sentence is
# capped: the text can mislead a person, it cannot spoof the prompt's own framing.
clean() { printf '%s' "$1" | tr -d '\000-\037\177' | cut -c1-500; }
IMPACT="$(clean "$IMPACT")"; ROLLBACK="$(clean "$ROLLBACK")"
REASON="Soleur is about to run stage '${STAGE}' of a generated operator script and change production. The script describes what it does as: ${IMPACT} It describes how to undo it as: ${ROLLBACK} (Both sentences come from the script file and are not verified by Soleur.) Approving runs exactly the command shown."
# The Bash tool shows a `description` the AGENT wrote next to the command in the
# prompt. It is replaced, so the person reads Soleur's words and not the agent's.
DESC="Soleur approval: production change, stage '${STAGE}' of a generated operator script"
emit_envelope() { # <decision> <reason> [with-update <nonce>]
  local nonce="${4:-}" new
  if [[ -n "$nonce" ]]; then
    # The nonce goes immediately BEFORE `bash`, not before the whole string, so the
    # `cd <dir> && bash ...` form hands it to the script and not to `cd`.
    new="${COMMAND:0:BASH_OFFSET}SOLEUR_APPROVAL_NONCE=${nonce} ${COMMAND:BASH_OFFSET}"
    printf '%s' "$INPUT" | jq -c --arg d "$1" --arg r "$2" --arg n "$new" --arg desc "$DESC" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r,updatedInput:(.tool_input|.command=$n|.description=$desc)}}'
  else
    printf '%s' "$INPUT" | jq -c --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  fi
}

INTERACTIVE=0
case "${CLAUDE_CODE_ENTRYPOINT:-}" in
  cli|claude-vscode|claude-desktop|claude-desktop-3p) INTERACTIVE=1 ;;
esac

if (( INTERACTIVE )); then
  NONCE="$(soleur_approval_mint "$BINDING" "$SESSION")" || NONCE=""
  [[ -n "$NONCE" ]] || emit_deny "Soleur could not set up a safe place for the approval receipt on this machine, so it will not make this production change. Nothing was changed." "mint-failed"
  trace "ran verdict=ask reason=interactive-mint stage=${STAGE}"
  emit_envelope ask "$REASON" with-update "$NONCE"
  exit 0
fi

# Headless: never mint. The run waits (`defer`) and a person resumes the session
# interactively, where this hook runs again and asks.
trace "ran verdict=defer reason=headless stage=${STAGE}"
emit_envelope defer "A production change is waiting for a person's approval: stage '${STAGE}' of a generated operator script. The script describes what it does as: ${IMPACT} It describes how to undo it as: ${ROLLBACK} Resume this session interactively (claude --resume) and the person will be asked at the prompt to approve exactly this command. Nothing has been changed."
exit 0
