#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # the single-quoted `$HOME`/`~` strings are LITERAL patterns matched against lexer text, never expanded
# PreToolUse hook on Bash: a narrow destructive-command guard for the Soleur plugin (W2, #9601, ADR-274).
# The kill switch below is the first executable statement; the rest follows the order under MECHANISM.
[[ "${SOLEUR_DISABLE_DESTRUCTIVE_GUARD-}" == "1" ]] && exit 0
#
# PROPERTY. A Bash tool call whose command, after lexing and wrapper unwrapping, runs a command in the
# decision set below receives `ask` (the harness shows the person the reason and waits) or `deny`, never an
# implicit allow, in every spelling bash reads as that command (within the scope stated under NOT DECIDED);
# a command in the same family outside the set receives no decision (no output, exit 0); an envelope the
# hook cannot read receives `ask`. The hook is a seatbelt against an unambiguous infrastructure destroy, a
# rewrite or deletion of a default branch on a remote, and a recursive delete of / or the home directory.
# It is not a security boundary.
#
# WHAT IT DECIDES (Bash tool calls only). Each simple command is judged after lexing: a command inside
# `bash|sh|zsh|dash|ksh -c`, `eval`, `$(...)`, backticks, `<(...)` and every list operator counts as its own
# simple command, and the recorded argv, never the raw text, is what is judged (so `echo "terraform
# destroy"`, a heredoc body and `git commit -m "rm -rf /"` are not commands).
#   deny  rm with a recursive flag (-r, -R, -rf, --recursive, any cluster or spelling, flags before or after
#         the targets) whose target is /, an ancestor of the home directory, the home directory (~, $HOME,
#         ${HOME}, a relative path resolving there) or the contents of those (/*, ~/*, and a bare * or ./*
#         when the working directory is home or an ancestor). A trailing slash or a glob suffix follows a
#         symlink; a bare symlink name does not (`rm -rf link` only unlinks it).
#   ask   rm with a recursive flag whose target is the working directory or an ancestor of it (.. , ../.. ,
#         an absolute path above it; `.` alone is not asked because rm refuses it).
#   ask   terraform|tofu destroy, and terraform|tofu apply -destroy (global options such as -chdir= skipped).
#   ask   git push that force-pushes (-f, --force, --force-with-lease[=..], --force-if-includes, a +refspec,
#         in any short-flag cluster, or --force with --all/--mirror) or deletes (--delete, -d, :ref) a
#         default branch. Default branches are the union of `git symbolic-ref --short
#         refs/remotes/<named remote>/HEAD` (read LOCALLY, no network), `main` and `master`; the value-taking
#         flags -o, --push-option, --repo, --receive-pack and `git -C <dir>` are parsed so positions and the
#         repository path are right.
#   ask   an unresolvable `cd`/`pushd` (a variable, `-`) followed in the same command by a recursive rm or
#         by a force/delete git push: the working directory the later command sees is unknown.
#   A literal `cd`/`pushd` earlier in the same command moves the simulated working directory for the later
#   commands (`cd ~ && rm -rf ./*` is a delete of home).
#   Wrappers are unwrapped with a small option table: sudo doas env command (not -v/-V) nohup time timeout
#   nice; xargs is NOT unwrapped; and the rule table is retried on the words after a `--`, which covers
#   `doppler run --`, `aws-vault exec <profile> --` and `op run --`. An absolute-path binary matches by
#   basename (/bin/rm).
#
# NOT DECIDED (stated, not implied). Obfuscation: a variable-built command name, glob or brace expansion of
# a command name (r[m], r{m,}), `xargs rm`, `find -delete`, zsh-only expansions (=rm); a script written and
# then run; a piped SQL string; `drop database`/`dropdb`; MCP delete tools; any non-Bash tool (including
# Devin's `exec`: the raw tool_name must be Bash); Doppler secret writes and deletes; a plain `terraform
# apply`; `kubectl delete`; `pulumi destroy`; `terragrunt destroy`; `git push --mirror` without --force; and an
# unresolvable $VAR target. User-facing statement: the guard does not cover a plain `terraform apply`, secret
# writes, SQL or non-Bash tools, and is not a substitute for scoped credentials. Residuals of the shared
# lexer: it lexes an identical `bash -c`/`eval` string once, so the working-directory simulation cannot tell
# two identical inner strings under different `cd`s apart; a `cd` inside a subshell or a $(...) is treated as
# sticky for the later commands (over-asks, never under-asks); a quoted fragment inside a tilde word
# (`~/"x"`) carries the quoted flag, so the word is read as literal unless it is exactly `~/` or `~/*`
# (those two are read as home even when quoted: a directory literally named `~` is the cost).
#
# DECISION PRECEDENCE across hooks (ADR-264, measured): deny > defer > ask > allow, so another hook's allow
# cannot turn this hook's ask into a silent run. The guard judges the ORIGINAL command it receives, not
# another hook's `updatedInput` (PreToolUse hooks of one event run independently on the same input).
#
# ASK AND DENY SEMANTICS (measured, phase-0-measurements.md 1.2): `ask` holds under bypassPermissions and
# against an allow rule; under `claude -p` it blocks the call with the reason shown, so a headless run
# degrades to a block, never an allow. On a `deny` the person sees only a collapsed "Ran 1 shell command"
# unless a top-level `systemMessage` is set, so every deny also carries `systemMessage` with the same full
# reason (the escape hatch and the issues URL included); an ask does not need it.
#
# FAILURE POSTURE (D6; a stated narrowing of ADR-157's `.claude` row, with reasons). An envelope jq rejects, a
# non-string .tool_input.command, empty stdin, a lexer parse failure (exit 2: unbalanced quote, unterminated
# substitution, NUL byte) and a lexer bound trip (exit 3: depth, budget, alarm, crash) all ASK; the parse
# reasons say "could not parse this command; it was not recognised as destructive" and never quote a command
# the hook did not match. A missing or unusable `jq` does not ask on every call (that would make the plugin
# unusable without jq): the hook scans the RAW envelope for its own narrow patterns (recursive rm of / ~ or
# $HOME, `destroy`, `push` with a force flag or +), tolerating JSON-escaped whitespace; a hit asks (output
# hand-built with a fixed reason naming jq, plus a stderr notice naming jq), a miss exits 0. A missing or
# broken `perl` with a working jq scans the jq-decoded command the same way (stderr notice naming perl). It
# never DENIES on a dependency failure (the repair is itself a Bash call). A miss on the raw scan is a stated,
# tested fail-open (the raw-scan-miss residual ADR-165 accepts for its `.openhands` row; ADR-274 records why
# this hook asks on a hit where that row denies, and why its `.claude` row, which asks on every call, is narrowed).
#
# KILL SWITCH (D5). SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 (exactly 1; empty, 0 and anything else leave the
# guard on) exits 0 with no output, before any dependency probe. It is read from the harness process
# environment, so setting it needs a session restart. It can ALSO be set from a settings-level `env` block
# (settings.json "env"), which no Bash guard sees and which an agent that can edit a settings file can use:
# this is a seatbelt, not a boundary. Hosted sessions disable it through AGENT_ENV_OVERRIDES (D8).
#
# MECHANISM AND ORDER. Kill switch; read stdin; the zero-spawn prefilter; the raw tool_name (captured before
# lib/hook-tool-kind.sh normalizes it, so Devin's `exec` is not decided); dependency probes by RESULT, not by
# `command -v` (a jq that is present and exits non-zero fails like an absent one; probed only on failure, so
# the happy path pays nothing); jq extraction (the command goes through `jq -j` straight into the lexer so
# NULs and newlines survive; the small fields use a separate jq call); lib/shell-argv.pl; the rule table; the
# decision. The prefilter skips the lexer only when the command's raw JSON text has NONE of the keywords rm,
# destroy, push, eval and none of backslash, single quote, double quote, $, a backtick or `<<` (a heredoc
# whose delimiter word is missing is the one unparseable command spelled with none of the others, and the
# lexer path asks on it, so the skip must not hide it). It reads the
# command string only (the text after "command":" up to the first double quote), because the envelope's other
# fields can spell a keyword (permission_mode, a cwd of .../web-platform), and a double quote inside the
# command is always JSON-escaped with a backslash, so the backslash test is what sees it. It also requires a
# `{...}`-shaped envelope with a string "command" so garbage and a non-string command reach the jq path and
# ask. Every skipped class is one the lexer path would also allow; every boundary character has a must-ASK row.
#
# DEPENDENCIES. bash (3.2 or later), jq, perl >= 5.10 with core pragmas only (the lexer), git (read-only,
# local `symbolic-ref`, only for a force/delete push), POSIX utilities. No `eval`, ever (ADR-156: hook stdin
# is model-controlled). The hook reads stdin and writes stdout and stderr; it writes no file and sends
# nothing off the machine.
#
# PORTABILITY (bash 3.2 and POSIX only). No bash-4 builtin, associative array or case-conversion expansion,
# and no GNU-only flag of the path, stream-edit, date or stat utilities. Lexer frames are read with
# `read -d ''` (a $(...) would strip the NULs); the decision is made from the `OK\0` terminator, never from
# an exit status lost across a process substitution; every empty-array expansion is guarded for `set -u`.
# Path resolution has no canonicalising utility: the physical parent is `cd -P <dir> && pwd -P` plus the
# literal basename; for a nonexistent target the longest existing prefix is resolved and the rest normalized
# lexically; HOME is compared in both its literal and physical forms. Inherited GIT_* variables are stripped
# BY PREFIX before any git call (a lefthook-exported GIT_DIR must not redirect it). The working directory is
# the envelope's .cwd, then CLAUDE_PROJECT_DIR, then PWD.
set -uo pipefail
# No pathname expansion: unquoted splits below must never glob.
set -f
export LC_ALL=C
unset CDPATH

ISSUES_URL='https://github.com/jikig-ai/soleur/issues'
REASON_TAIL=" Stop and tell the person what you were about to run and why. Do not retry this command and do not rephrase it to get around the guard. If no person is available to answer, end the task and report it as blocked. The person can run the command themselves in their own terminal, outside the agent, or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 set in their own shell. If this was flagged wrongly, report it at ${ISSUES_URL}"
FALLBACK_REASON="guard-output-fallback: the destructive-command guard could not build its decision output and is asking instead of allowing. Stop and tell the person. Do not retry this command. If no person is available, end the task and report it as blocked. The person can run it in their own terminal or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1. Report a wrong flag at ${ISSUES_URL}"

# ---- output ---------------------------------------------------------------------------------------
# emit <ask|deny> <reason>: the full envelope (a bare decision without hookEventName is silently ignored),
# built with jq; a hand-built fixed string when jq fails. A deny also carries systemMessage.
emit() {
  local out=""
  out="$(jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}
     + (if $d == "deny" then {systemMessage: $r} else {} end)' 2>/dev/null)" || out=""
  if [[ -z "$out" ]]; then emit_fixed "$1" "$FALLBACK_REASON"; return; fi
  printf '%s\n' "$out"
}
# emit_fixed <ask|deny> <fixed reason without quotes or backslashes>: no jq, no interpolation of input text.
emit_fixed() {
  if [[ "$1" == deny ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' "$2" "$2"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$2"
  fi
}

# lead_for <rule id>: the one-sentence statement of what the rule matched.
lead_for() {
  case "$1" in
    recursive-delete-home) LEAD="this command recursively deletes the filesystem root, an ancestor of the home directory, the home directory, or everything inside one of them." ;;
    recursive-delete-workdir) LEAD="this command recursively deletes the working directory or one of its ancestors." ;;
    infra-destroy) LEAD="this command runs terraform or tofu destroy (or apply -destroy), which tears down infrastructure." ;;
    default-branch-force-push) LEAD="this command force-pushes over, or deletes, a default branch on a remote." ;;
    unresolved-cd-before-destructive) LEAD="a cd or pushd that cannot be resolved (a variable, or -) comes before a recursive delete or a force push in the same command, so the directory it acts on cannot be checked." ;;
    *) LEAD="this command matched a destructive-command rule." ;;
  esac
}

ask_parse() { # <cause text>: a command the lexer could not read
  emit ask "command-not-parsed: the destructive-command guard could not parse this command; it was not recognised as destructive, and the guard asks rather than guess (${1}).${REASON_TAIL}"
  exit 0
}
ask_envelope() { # <cause text>
  emit ask "envelope-unreadable: the destructive-command guard could not read this tool call (${1}), and it asks rather than allow what it cannot read.${REASON_TAIL}"
  exit 0
}

# ---- the narrow raw/decoded scan used by the degraded paths (D6) -----------------------------------
# One anchored pattern per case, each tested on ONE segment (a list is split on ; & | and newlines first),
# never independent greps ANDed over the whole text.
SC_B='(^|[^[:alnum:]_.-])'
RE_RM_WORD="${SC_B}rm[[:space:]]"
RE_RM_REC='[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([^[:alnum:]_-]|$)'
RE_RM_TGT='(^|[^[:alnum:]_./~$-])((/+\*?)|((~|\$HOME|\$\{HOME\})(/+\*?)?))([^[:alnum:]_./~$*-]|$)'
RE_TF_DESTROY="${SC_B}(terraform|tofu)[[:space:]]([^[:space:]].*[[:space:]])?destroy([^[:alnum:]_.-]|\$)"
RE_TF_APPLY="${SC_B}(terraform|tofu)[[:space:]]([^[:space:]].*[[:space:]])?apply[[:space:]]([^[:space:]].*[[:space:]])?-{1,2}destroy([^[:alnum:]_.-]|\$)"
RE_GIT_PUSH="${SC_B}git[[:space:]]([^[:space:]].*[[:space:]])?push[[:space:]]([^[:space:]].*[[:space:]])?(-[a-zA-Z]*f[a-zA-Z]*|--force[^[:space:]]*|\\+[^[:space:]+])"
SCAN_SEG=""
# scan_narrow <text>: 0 on a hit (SCAN_SEG = the matched segment), 1 on a miss.
scan_narrow() {
  local seg IFS=$';&|\n'
  for seg in $1; do
    if [[ "$seg" =~ $RE_RM_WORD && "$seg" =~ $RE_RM_REC && "$seg" =~ $RE_RM_TGT ]]; then SCAN_SEG="$seg"; return 0; fi
    if [[ "$seg" =~ $RE_TF_DESTROY || "$seg" =~ $RE_TF_APPLY ]]; then SCAN_SEG="$seg"; return 0; fi
    if [[ "$seg" =~ $RE_GIT_PUSH ]]; then SCAN_SEG="$seg"; return 0; fi
  done
  return 1
}

# ---- 1. read stdin ---------------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null)" || INPUT=""
case "$INPUT" in
  *[![:space:]]*) : ;;
  *) ask_envelope "stdin was empty" ;;
esac

# ---- 2. the zero-spawn prefilter (D7) --------------------------------------------------------------
# Skip the lexer only for a `{...}` envelope with a STRING command that has no keyword and no boundary
# character. See the header: only the command's own raw JSON text is scanned.
PF_LEAD="${INPUT#"${INPUT%%[![:space:]]*}"}"
PF_TAIL="${INPUT%"${INPUT##*[![:space:]]}"}"
PF_CMD_RE='"command"[[:space:]]*:[[:space:]]*"'
if [[ "${PF_LEAD:0:1}" == "{" && "${PF_TAIL: -1}" == "}" && "$INPUT" =~ $PF_CMD_RE ]]; then
  PF_MARK="${BASH_REMATCH[0]}"
  PF_REST="${INPUT#*"$PF_MARK"}"
  PF_CMD="${PF_REST%%\"*}"
  case "$PF_CMD" in
    *rm*|*destroy*|*push*|*eval*|*'<<'*|*[\\\'\"\$\`]*) : ;;
    *) exit 0 ;;
  esac
fi

# ---- 3. the lexer path -----------------------------------------------------------------------------
HOOK_SRC="${BASH_SOURCE[0]}"
HOOK_DIR="${HOOK_SRC%/*}"; [[ "$HOOK_DIR" == "$HOOK_SRC" ]] && HOOK_DIR=.
LEXER="$HOOK_DIR/lib/shell-argv.pl"

# Canonical kind map (#8205): the shim degrades to raw-name passthrough when the lib is absent. The RAW
# tool_name is captured before the map normalizes it, so Devin's `exec` (kind Bash) is NOT decided here (D2).
# shellcheck source=plugins/soleur/hooks/lib/hook-tool-kind.sh
. "$HOOK_DIR/lib/hook-tool-kind.sh" 2>/dev/null || true
if ! type hook_tool_kind >/dev/null 2>&1; then
  hook_tool_kind() { printf '%s\n' "${1-}"; }
  echo "WARN: hook-tool-kind.sh missing - kind gates degrade to raw-name passthrough" >&2
fi

JQ_FIELDS='if type != "object" then "invalid" else
  ((.tool_name // "" | if type == "string" then . else "" end | gsub("[\\n\\r]"; " ")),
   (.cwd // "" | if type == "string" then . else "" end | gsub("[\\n\\r]"; " ")),
   (try (.tool_input.command | type) catch "invalid"))
end'

degrade_jq() {
  echo "soleur destructive-command-guard: jq is missing or unusable on this machine; scanning the raw tool input with the guard's own narrow patterns instead of parsing it (install jq for full coverage)" >&2
  local raw="$INPUT"
  raw="${raw//\\n/;}"; raw="${raw//\\u000[aA]/;}"; raw="${raw//\\u000[dD]/;}"
  raw="${raw//\\t/ }"; raw="${raw//\\r/ }"; raw="${raw//\\u0009/ }"; raw="${raw//\\u0020/ }"
  if scan_narrow "$raw"; then
    emit_fixed ask "guard-degraded-jq-missing: jq is missing or unusable on this machine, so the destructive-command guard scanned the raw tool input instead of parsing it, and this call looks destructive (a recursive delete of / or home, a destroy, or a force push). Stop and tell the person. Do not retry this command or rephrase it. If no person is available, end the task and report it as blocked. The person can run it in their own terminal, or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1, or install jq. Report a wrong flag at ${ISSUES_URL}"
  fi
  exit 0
}

JQ_RC=0
FIELDS="$(printf '%s' "$INPUT" | jq -r "$JQ_FIELDS" 2>/dev/null)" || JQ_RC=$?
if [[ "$JQ_RC" -ne 0 ]]; then
  # Probe by RESULT: a working jq that rejected this envelope is a bad envelope (ask); anything else is a
  # missing or unusable jq (raw scan).
  JQ_PROBE="$(printf '{"a":1}' | jq -r '.a' 2>/dev/null)" || JQ_PROBE=""
  [[ "$JQ_PROBE" == 1 ]] && ask_envelope "the envelope is not valid JSON"
  degrade_jq
fi
[[ "$FIELDS" == invalid ]] && ask_envelope "the envelope is not a JSON object"
RAW_TOOL="${FIELDS%%$'\n'*}"; FIELDS_REST="${FIELDS#*$'\n'}"
CWD_IN="${FIELDS_REST%%$'\n'*}"; CMD_TYPE="${FIELDS_REST#*$'\n'}"
# Only a Bash call is decided. A missing tool_name is read as Bash (fail toward deciding); the registered
# matcher is ^Bash$, so a real call always carries it.
if [[ -n "$RAW_TOOL" ]]; then
  [[ "$RAW_TOOL" == Bash && "$(hook_tool_kind "$RAW_TOOL")" == Bash ]] || exit 0
fi
[[ "$CMD_TYPE" == string ]] || ask_envelope "tool_input.command is not a string"

# ---- 4. lex ----------------------------------------------------------------------------------------
# Frames: C \0 ctx \0 argc \0 (flags \0 arg \0){argc} ... then OK \0 (or E \0 cause \0 on failure).
W_TXT=(); W_FLG=(); REC_OFF=(); REC_N=()
SAW_OK=0; SAW_E=""; LEX_BAD=0
LEX_ST=0; LEX_LEFT=0; LEX_KIND=0; NW=0
while IFS= read -r -d '' F; do
  case "$LEX_ST" in
    0) case "$F" in C) LEX_ST=1 ;; OK) SAW_OK=1 ;; E) LEX_ST=9 ;; *) LEX_BAD=1 ;; esac ;;
    1) LEX_ST=2 ;;                                   # the ctx field
    2) if [[ "$F" =~ ^[1-9][0-9]{0,6}$ ]]; then
         REC_OFF[${#REC_OFF[@]}]="$NW"; REC_N[${#REC_N[@]}]="$F"; LEX_LEFT=$((F * 2)); LEX_KIND=0; LEX_ST=3
       else LEX_BAD=1; LEX_ST=0; fi ;;
    3) if [[ "$LEX_KIND" -eq 0 ]]; then W_FLG[${#W_FLG[@]}]="$F"; LEX_KIND=1
       else W_TXT[${#W_TXT[@]}]="$F"; LEX_KIND=0; NW=$((NW + 1)); fi
       LEX_LEFT=$((LEX_LEFT - 1)); [[ "$LEX_LEFT" -le 0 ]] && LEX_ST=0 ;;
    9) SAW_E="$F"; LEX_ST=0 ;;
  esac
done < <({ printf '%s' "$INPUT" | jq -j '.tool_input.command' | perl "$LEXER"; } 2>/dev/null)

if [[ "$SAW_OK" -ne 1 ]]; then
  if [[ -n "$SAW_E" ]]; then ask_parse "lexer ${SAW_E}"; fi
  # No OK and no E: the lexer was killed, crashed, or perl is missing/unusable. Probe by RESULT.
  PERL_PROBE="$(perl -e 'print "ok"' 2>/dev/null)" || PERL_PROBE=""
  if [[ "$PERL_PROBE" != ok || ! -r "$LEXER" ]]; then
    echo "soleur destructive-command-guard: perl (or its lexer) is missing or unusable on this machine; scanning the decoded command with the guard's own narrow patterns instead of lexing it (install perl for full coverage)" >&2
    DEC_CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)" || DEC_CMD=""
    if scan_narrow "$DEC_CMD"; then
      emit ask "guard-degraded-perl-missing: perl is missing or unusable on this machine, so the destructive-command guard scanned the decoded command with its narrow patterns instead of lexing it, and this call looks destructive. Matched segment: ${SCAN_SEG:0:200}.${REASON_TAIL}"
    fi
    exit 0
  fi
  ask_parse "the lexer produced no result"
fi
[[ "$LEX_BAD" -eq 1 ]] && ask_parse "the lexer output was malformed"

# ---- 5. the rule table -----------------------------------------------------------------------------
BEST_RANK=0; BEST_RULE=""; BEST_QUOTE=""
REC_RANK=0; REC_RULE=""
note() { # <rank 1|2> <rule id>
  if (( $1 > REC_RANK )); then REC_RANK="$1"; REC_RULE="$2"; fi
}

SIMCWD=""; CWD_READY=0; UNRES=0
HL=""; HP=""; HOME_READY=0
GIT_SCRUBBED=0
AV=(); AF=(); DA_T=(); DA_F=()
EW=""; EW_Q=0; RP=""; LN=""; WJ=-1

# lex_norm <abs path> -> LN: collapse // . .. lexically.
lex_norm() {
  local IFS=/ part i n=0
  local -a stack=()
  for part in $1; do
    case "$part" in
      ''|.) : ;;
      ..) if (( n > 0 )); then n=$((n - 1)); unset "stack[$n]"; fi ;;
      *) stack[n]="$part"; n=$((n + 1)) ;;
    esac
  done
  LN=""
  for ((i = 0; i < n; i++)); do LN="$LN/${stack[$i]}"; done
  [[ -n "$LN" ]] || LN=/
}

phys_cd() { # <dir>: the physical path of an existing directory, else nothing
  [[ -n "$1" ]] || return 1
  ( cd -P -- "$1" 2>/dev/null && pwd -P )
}

# resolve_phys <abs path> <follow 0|1> -> RP (empty = no decision: rm refuses `.`)
# follow=1: the path itself is resolved through symlinks (a trailing slash or a glob suffix); follow=0: a
# bare final name stays literal (`rm -rf link` only unlinks the link).
resolve_phys() {
  local p="$1" follow="$2" last dir r rest probe
  RP=""
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  if [[ "$p" == / ]]; then RP=/; return 0; fi
  last="${p##*/}"
  if [[ "$follow" == 0 && "$last" == . ]]; then return 1; fi
  if [[ "$follow" == 1 || "$last" == .. ]]; then
    r="$(phys_cd "$p")"
    if [[ -n "$r" ]]; then RP="$r"; return 0; fi
  fi
  dir="${p%/*}"; [[ -z "$dir" ]] && dir=/
  r="$(phys_cd "$dir")"
  if [[ -n "$r" ]]; then
    lex_norm "${r%/}/$last"; RP="$LN"; return 0
  fi
  # the parent does not exist either: resolve the longest existing prefix, normalize the rest lexically
  rest="$last"; probe="$dir"
  while :; do
    r="$(phys_cd "$probe")"
    [[ -n "$r" ]] && break
    rest="${probe##*/}/$rest"; probe="${probe%/*}"
    [[ -z "$probe" ]] && probe=/
    if [[ "$probe" == / ]]; then r=/; break; fi
  done
  lex_norm "${r%/}/$rest"; RP="$LN"
  return 0
}

anc_or_eq() { # <a> <b>: a is /, equals b, or is an ancestor of b
  local a="$1" b="$2"
  while [[ "$a" == */ && "$a" != / ]]; do a="${a%/}"; done
  while [[ "$b" == */ && "$b" != / ]]; do b="${b%/}"; done
  [[ -z "$a" ]] && a=/
  [[ -z "$b" ]] && b=/
  [[ "$a" == / || "$b" == "$a" || "$b" == "$a"/* ]]
}

cwd_ready() {
  [[ "$CWD_READY" -eq 1 ]] && return 0
  CWD_READY=1
  local base="${CWD_IN:-${CLAUDE_PROJECT_DIR:-${PWD:-/}}}"
  [[ "$base" == /* ]] || base="${PWD:-/}/$base"
  resolve_phys "$base" 1 || RP="$base"
  SIMCWD="$RP"
}

home_ready() {
  [[ "$HOME_READY" -eq 1 ]] && return 0
  HOME_READY=1
  local h="${HOME:-}"
  if [[ "$h" != /* ]]; then HL="/nonexistent-home-unset"; HP="$HL"; return 0; fi
  lex_norm "$h"; HL="$LN"
  resolve_phys "$h" 1 || RP="$HL"
  HP="$RP"
}

scrub_git_env() {
  [[ "$GIT_SCRUBBED" -eq 1 ]] && return 0
  GIT_SCRUBBED=1
  local v
  while IFS= read -r v; do
    case "$v" in GIT_*) unset "$v" ;; esac
  done < <(compgen -e)
  export GIT_TERMINAL_PROMPT=0
}
git_ro() { # <repo dir> <args...>: read-only, local only
  local repo="$1"; shift
  scrub_git_env
  git -C "$repo" "$@" 2>/dev/null </dev/null
}

is_assign() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]]; }

# expand_word <text> <flags> -> EW, EW_Q; returns 1 when the word cannot be resolved (a variable target is
# no decision). Tilde: only an unquoted leading ~ or ~/ (plus the quoted `~/` and `~/*` forms, see header);
# $HOME ${HOME} $PWD ${PWD} when expanded; any other expansion is unresolvable.
expand_word() {
  local t="$1" fl="$2" xd=0 qd=0 P
  EW=""; EW_Q=0
  case "$fl" in *q*) qd=1 ;; esac
  case "$fl" in *x*) xd=1 ;; esac
  EW_Q="$qd"
  if (( qd == 0 )) || [[ "$t" == '~/' || "$t" == '~/*' ]]; then
    case "$t" in
      '~'|'~/'*) [[ -n "${HOME:-}" ]] || return 1; P='~'; t="$HOME${t#"$P"}" ;;
      '~'*) return 1 ;;
    esac
  fi
  if (( xd )); then
    case "$t" in
      '$HOME'|'$HOME/'*) [[ -n "${HOME:-}" ]] || return 1; P='$HOME'; t="$HOME${t#"$P"}" ;;
      '${HOME}'|'${HOME}/'*) [[ -n "${HOME:-}" ]] || return 1; P='${HOME}'; t="$HOME${t#"$P"}" ;;
      '$PWD'|'$PWD/'*) cwd_ready; P='$PWD'; t="$SIMCWD${t#"$P"}" ;;
      '${PWD}'|'${PWD}/'*) cwd_ready; P='${PWD}'; t="$SIMCWD${t#"$P"}" ;;
    esac
    case "$t" in *'$'*|*'`'*|*'<('*|*'>('*) return 1 ;; esac
  fi
  [[ -n "$t" ]] || return 1
  EW="$t"
  return 0
}

rule_rm() {
  local -a a=("${AV[@]}") fl=("${AF[@]}") tix=()
  local n=${#a[@]} k x name rec=0 end=0 glob follow T D
  for ((k = 1; k < n; k++)); do
    x="${a[$k]}"
    if (( end )); then tix[${#tix[@]}]="$k"
    elif [[ "$x" == -- ]]; then end=1
    elif [[ "$x" == --* ]]; then
      name="${x#--}"
      if [[ -n "$name" && "recursive" == "$name"* ]]; then rec=1; fi
    elif [[ "$x" == -?* ]]; then
      case "${x:1}" in *[rR]*) rec=1 ;; esac
    else tix[${#tix[@]}]="$k"; fi
  done
  (( rec )) || return 0
  cwd_ready; home_ready
  if (( UNRES )); then note 1 unresolved-cd-before-destructive; fi
  for k in ${tix[@]+"${tix[@]}"}; do
    expand_word "${a[$k]}" "${fl[$k]}" || continue
    T="$EW"; glob=0; follow=0
    if [[ "$T" == '*' && "$EW_Q" -eq 0 ]]; then glob=1; follow=1; D="$SIMCWD"
    elif [[ "$T" == */'*' ]]; then glob=1; follow=1; D="${T%/\*}"; [[ -z "$D" ]] && D=/
    elif [[ "$T" == */ ]]; then
      follow=1; D="$T"
      x="$D"; while [[ "$x" == */ && "$x" != / ]]; do x="${x%/}"; done
      [[ "$x" != / && "${x##*/}" == . ]] && continue
    else D="$T"; fi
    [[ "$D" == /* ]] || D="$SIMCWD/$D"
    resolve_phys "$D" "$follow" || continue
    [[ -n "$RP" ]] || continue
    if anc_or_eq "$RP" "$HL" || anc_or_eq "$RP" "$HP"; then note 2 recursive-delete-home
    elif (( glob == 0 )) && anc_or_eq "$RP" "$SIMCWD"; then note 1 recursive-delete-workdir; fi
  done
}

rule_tf() {
  local -a a=("${AV[@]}")
  local n=${#a[@]} i=1 sub x
  while (( i < n )) && [[ "${a[$i]}" == -* ]]; do i=$((i + 1)); done
  (( i < n )) || return 0
  sub="${a[$i]}"
  if [[ "$sub" == destroy ]]; then note 1 infra-destroy; return 0; fi
  if [[ "$sub" == apply ]]; then
    for ((i = i + 1; i < n; i++)); do
      x="${a[$i]}"
      case "$x" in -destroy|--destroy|-destroy=true|--destroy=true) note 1 infra-destroy; return 0 ;; esac
    done
  fi
}

rule_git() {
  local -a a=("${AV[@]}") pos=() refs=() D_DST=() D_F=() D_DEL=()
  local n=${#a[@]} i=1 j k c x name end=0 repo cur head remote named
  local force=0 del=0 allf=0 mirror=0 repoopt=0 risk=0 r f dele src dst
  cwd_ready; repo="$SIMCWD"
  while (( i < n )); do
    case "${a[$i]}" in
      -C) if (( i + 1 < n )); then
            case "${a[$((i + 1))]}" in /*) repo="${a[$((i + 1))]}" ;; *) repo="$repo/${a[$((i + 1))]}" ;; esac
          fi
          i=$((i + 2)) ;;
      -c|--git-dir|--work-tree|--namespace|--super-prefix|--exec-path) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [[ "${a[$i]:-}" == push ]] || return 0
  j=$((i + 1))
  while (( j < n )); do
    x="${a[$j]}"
    if (( end )); then pos[${#pos[@]}]="$x"
    elif [[ "$x" == -- ]]; then end=1
    elif [[ "$x" == --* ]]; then
      name="${x%%=*}"
      case "$name" in
        --force*) force=1 ;;
        --de|--del|--dele|--delet|--delete) del=1 ;;
        --all) allf=1 ;;
        --mirror) mirror=1 ;;
        --repo) repoopt=1; [[ "$x" == *=* ]] || j=$((j + 1)) ;;
        --push-option|--receive-pack|--exec) [[ "$x" == *=* ]] || j=$((j + 1)) ;;
      esac
    elif [[ "$x" == -?* ]]; then
      for ((k = 1; k < ${#x}; k++)); do
        c="${x:$k:1}"
        case "$c" in
          f) force=1 ;;
          d) del=1 ;;
          o) [[ "$k" -eq $((${#x} - 1)) ]] && j=$((j + 1)); break ;;
        esac
      done
    else pos[${#pos[@]}]="$x"; fi
    j=$((j + 1))
  done
  remote=""
  if (( repoopt )); then
    for x in ${pos[@]+"${pos[@]}"}; do refs[${#refs[@]}]="$x"; done
  else
    if (( ${#pos[@]} > 0 )); then remote="${pos[0]}"; fi
    for ((k = 1; k < ${#pos[@]}; k++)); do refs[${#refs[@]}]="${pos[$k]}"; done
  fi
  named="${remote:-origin}"
  # The destinations, flagged: +refspec / +dst (force) and :dst (delete) are risky on their own.
  for r in ${refs[@]+"${refs[@]}"}; do
    f=0; dele=0
    if [[ "$r" == +* ]]; then f=1; r="${r#+}"; fi
    if [[ "$r" == *:* ]]; then
      src="${r%%:*}"; dst="${r#*:}"
      if [[ "$dst" == +* ]]; then f=1; dst="${dst#+}"; fi
      [[ -z "$src" ]] && dele=1
    else
      dst="$r"
    fi
    (( f || dele )) && risk=1
    D_DST[${#D_DST[@]}]="$dst"; D_F[${#D_F[@]}]="$f"; D_DEL[${#D_DEL[@]}]="$dele"
  done
  (( force || del )) && risk=1
  (( risk )) || return 0
  # The directory the push acts on depends on the working directory: an unresolvable cd decides it here.
  if (( UNRES )); then note 1 unresolved-cd-before-destructive; return 0; fi
  if (( (allf || mirror) && force )); then note 1 default-branch-force-push; return 0; fi
  head=""; cur=""; local have_head=0 have_cur=0
  local -a defaults=(main master)
  for ((k = 0; k < ${#D_DST[@]}; k++)); do
    dst="${D_DST[$k]}"
    if [[ "$dst" == HEAD ]]; then
      if (( ! have_cur )); then cur="$(git_ro "$repo" symbolic-ref --short HEAD)"; have_cur=1; fi
      dst="$cur"
    fi
    dst="${dst#refs/heads/}"
    [[ -n "$dst" ]] || continue
    if (( force || D_F[k] || del || D_DEL[k] )); then
      if [[ "$dst" == main || "$dst" == master ]]; then note 1 default-branch-force-push; return 0; fi
      if (( ! have_head )); then
        head="$(git_ro "$repo" symbolic-ref --short "refs/remotes/$named/HEAD")"; have_head=1
        head="${head#"$named"/}"
        [[ -n "$head" ]] && defaults[${#defaults[@]}]="$head"
      fi
      for x in "${defaults[@]}"; do
        if [[ "$dst" == "$x" ]]; then note 1 default-branch-force-push; return 0; fi
      done
    fi
  done
  # No refspec at all: the push goes to the current branch (the upstream default).
  if (( ${#D_DST[@]} == 0 && allf == 0 && mirror == 0 && force )); then
    cur="$(git_ro "$repo" symbolic-ref --short HEAD)"
    if [[ -n "$cur" ]]; then
      head="$(git_ro "$repo" symbolic-ref --short "refs/remotes/$named/HEAD")"; head="${head#"$named"/}"
      if [[ "$cur" == main || "$cur" == master || ( -n "$head" && "$cur" == "$head" ) ]]; then
        note 1 default-branch-force-push; return 0
      fi
    fi
  fi
}

# wrap_skip <name> <index of name in t> -> WJ: the index of the wrapped command's first word, or -1 when
# the wrapper is a look-up only (`command -v`). Reads t[] and n of the caller (dynamic scope, by design).
wrap_skip() {
  local name="$1" j=$(($2 + 1)) a
  WJ=-1
  case "$name" in
    sudo)
      while (( j < n )) && [[ "${t[$j]}" == -* && "${t[$j]}" != - ]]; do
        a="${t[$j]}"; j=$((j + 1))
        [[ "$a" == -- ]] && break
        case "$a" in
          -u|-g|-h|-p|-C|-r|-t|-T|-U|-D|-R|--user|--group|--host|--prompt|--chdir|--chroot|--role|--type) j=$((j + 1)) ;;
        esac
      done
      while (( j < n )) && is_assign "${t[$j]}"; do j=$((j + 1)); done ;;
    doas)
      while (( j < n )) && [[ "${t[$j]}" == -* && "${t[$j]}" != - ]]; do
        a="${t[$j]}"; j=$((j + 1))
        [[ "$a" == -- ]] && break
        case "$a" in -u|-C) j=$((j + 1)) ;; esac
      done ;;
    env)
      while (( j < n )); do
        a="${t[$j]}"
        if [[ "$a" == -- ]]; then j=$((j + 1)); break
        elif [[ "$a" == -u || "$a" == --unset || "$a" == -C || "$a" == --chdir ]]; then j=$((j + 2))
        elif [[ "$a" == -* && "$a" != - ]]; then j=$((j + 1))
        elif is_assign "$a"; then j=$((j + 1))
        else break; fi
      done ;;
    timeout)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in -s|-k|--signal|--kill-after) j=$((j + 1)) ;; esac
      done
      j=$((j + 1)) ;;
    nice)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in -n|--adjustment) j=$((j + 1)) ;; esac
      done ;;
    command)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in --) break ;; -v|-V|-[a-zA-Z]*[vV]*) return 0 ;; esac
      done ;;
    nohup|-p) : ;;
  esac
  WJ="$j"
}

# decide_argv <depth>: the rule table over DA_T/DA_F (the words of one simple command), retried on the
# command a wrapper hides and on the words after every `--`.
decide_argv() {
  local depth="$1" n i k name
  (( depth > 8 )) && return 0
  local -a t=("${DA_T[@]}") f=("${DA_F[@]}")
  n=${#t[@]}; i=0
  while (( i < n )) && is_assign "${t[$i]}"; do i=$((i + 1)); done
  if (( i < n )); then
    name="${t[$i]##*/}"
    AV=("${t[@]:$i}"); AF=("${f[@]:$i}")
    case "$name" in
      rm) rule_rm ;;
      terraform|tofu) rule_tf ;;
      git) rule_git ;;
      sudo|doas|env|command|nohup|timeout|nice|-p)
        wrap_skip "$name" "$i"
        if (( WJ >= 0 && WJ < n )); then
          DA_T=("${t[@]:$WJ}"); DA_F=("${f[@]:$WJ}")
          decide_argv $((depth + 1))
        fi ;;
    esac
  fi
  for ((k = 0; k + 1 < n; k++)); do
    if [[ "${t[$k]}" == -- ]]; then
      DA_T=("${t[@]:$((k + 1))}"); DA_F=("${f[@]:$((k + 1))}")
      decide_argv $((depth + 1))
    fi
  done
}

# apply_cd: a literal cd/pushd moves the simulated working directory; an unresolvable one sets UNRES.
apply_cd() { # reads DA_T/DA_F of the current record (its first non-assignment word is cd/pushd/popd)
  local -a t=("${DA_T[@]}") f=("${DA_F[@]}")
  local n=${#t[@]} i=0 j target="" tf="-" have=0
  while (( i < n )) && is_assign "${t[$i]}"; do i=$((i + 1)); done
  cwd_ready
  if [[ "${t[$i]}" == popd ]]; then UNRES=1; return 0; fi
  j=$((i + 1))
  while (( j < n )); do
    if [[ "${t[$j]}" == -- ]]; then j=$((j + 1)); break; fi
    [[ "${t[$j]}" == -* && "${t[$j]}" != - ]] || break
    j=$((j + 1))
  done
  if (( j < n )); then target="${t[$j]}"; tf="${f[$j]}"; have=1; fi
  if (( ! have )); then
    if [[ -n "${HOME:-}" ]]; then target="$HOME"; else UNRES=1; return 0; fi
    tf="-"
  fi
  if [[ "$target" == - ]]; then UNRES=1; return 0; fi
  if ! expand_word "$target" "$tf"; then UNRES=1; return 0; fi
  target="$EW"
  [[ "$target" == /* ]] || target="$SIMCWD/$target"
  if resolve_phys "$target" 1 && [[ -n "$RP" ]]; then SIMCWD="$RP"; UNRES=0; else UNRES=1; fi
}

NREC=${#REC_N[@]}
for ((r = 0; r < NREC; r++)); do
  DA_T=("${W_TXT[@]:${REC_OFF[$r]}:${REC_N[$r]}}")
  DA_F=("${W_FLG[@]:${REC_OFF[$r]}:${REC_N[$r]}}")
  REC_RANK=0; REC_RULE=""
  decide_argv 0
  if (( REC_RANK > BEST_RANK )); then
    BEST_RANK="$REC_RANK"; BEST_RULE="$REC_RULE"; REC_TXT="${DA_T[*]}"; BEST_QUOTE="${REC_TXT:0:200}"
    (( ${#REC_TXT} > 200 )) && BEST_QUOTE="${BEST_QUOTE}..."
    (( BEST_RANK == 2 )) && break
  fi
  # the cd effect of this record, for the commands after it
  CI=0
  while (( CI < ${#DA_T[@]} )) && is_assign "${DA_T[$CI]}"; do CI=$((CI + 1)); done
  if (( CI < ${#DA_T[@]} )); then
    case "${DA_T[$CI]}" in cd|pushd|popd) apply_cd ;; esac
  fi
done

# ---- 6. the decision -------------------------------------------------------------------------------
(( BEST_RANK == 0 )) && exit 0
lead_for "$BEST_RULE"
REASON="${BEST_RULE}: ${LEAD} Matched command: [${BEST_QUOTE}].${REASON_TAIL}"
if (( BEST_RANK == 2 )); then emit deny "$REASON"; else emit ask "$REASON"; fi
exit 0
