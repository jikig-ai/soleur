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
#         ${HOME}, a relative path resolving there) or the contents of those: /*, ~/*, and any target whose
#         every component after the glob-free root is only glob syntax (/** /*/* /*/ /? /[a-z]* ~/**), and a
#         bare * ** or ./* when the working directory is home or an ancestor. A component that mixes literal
#         text with a glob (~/*/node_modules, /home/*/x, /*.log, ~/.*) is another set of files and is not
#         decided. `~+` is the working directory; with HOME unset or empty `~` is the passwd entry's home
#         (the same lookup bash makes) and `$HOME/` is `/`. A trailing slash or a glob suffix follows a
#         symlink; a bare symlink name does not (`rm -rf link` only unlinks it).
#   ask   rm with a recursive flag whose target is the working directory or an ancestor of it (.. , ../.. ,
#         an absolute path above it; `.` alone is not asked because rm refuses it). The working directory is
#         BOTH the envelope's cwd and the one a literal cd/pushd earlier in the command moved to.
#   ask   terraform|tofu destroy, and terraform|tofu apply -destroy (global options such as -chdir= skipped;
#         -destroy=<value> is a destroy unless the value is one of 0 f F false FALSE False, the Go bool "off").
#   ask   git push that force-pushes (-f, --force, --force-with-lease[=..], --force-if-includes, a +refspec,
#         in any short-flag cluster, --force with --all/--mirror or their unique abbreviations --al, --m...) or
#         deletes (--delete, -d, :ref) a default branch; a destination spelled heads/main or refs/heads/main, a
#         glob destination (refs/heads/*:refs/heads/*) and the matching refspec `:` count under a force flag.
#         Default branches are the union of `git symbolic-ref --short
#         refs/remotes/<named remote>/HEAD` (read LOCALLY, no network), `main` and `master`; the value-taking
#         flags -o, --push-option, --repo, --receive-pack, `git -C <dir>` and the global options that take a
#         separate word (-c, --config-env, --git-dir, --work-tree, --namespace, --attr-source) are parsed so
#         positions and the repository path are right. A `git -c alias.p=push p ...` alias is NOT DECIDED.
#   ask   an unresolvable `cd`/`pushd` (a variable, `-`) followed in the same command by a recursive rm or
#         by a force/delete git push: the working directory the later command sees is unknown.
#   A literal `cd`/`pushd` earlier in the same command (also behind `command` or `builtin`) moves the
#   simulated working directory for the later commands (`cd ~ && rm -rf ./*` is a delete of home).
#   Wrappers are unwrapped with a small option table: sudo doas env command (not -v/-V) nohup time timeout
#   nice; xargs is NOT unwrapped. `time` is a wrapper as a command word (/usr/bin/time, `command time`, `env
#   time`); as a reserved word it is the lexer's, which drops it, and the first word `-p` then recovers
#   `time -p rm ...` (a pseudo-wrapper). A short-option cluster whose last letter takes a value shifts one more
#   word (sudo -nu root, env -iu X, timeout -vk 5 10). The rule table is retried on the words after a `--`,
#   which covers `doppler run --`, `aws-vault exec <profile> --` and `op run --`. An absolute-path binary
#   matches by basename (/bin/rm) and command names are compared in lower case (RM, Git, Terraform; the fold
#   starts no process). A wrapper's chdir option (env -C DIR, env --chdir=DIR, sudo -D DIR, sudo --chdir=DIR)
#   moves the simulated working directory for the command it runs, and for that command only; a directory the
#   guard cannot resolve (a variable) is an unresolved cd.
#   ask   env -S, --split-string (any abbreviation) or a cluster with S (rule id `unparsed-wrapper`): the string
#         it splits into a command is not analysed.
#   ask   more than 8 nested wrappers or `--` separators (rule id `wrapper-depth`): what they run cannot be checked.
#   ask   a command too large to check (rule id `bound`): a tool call over 256 KiB (checked before anything reads
#         it), more than MAX_RECORDS simple commands, more than MAX_WORDS words, a target path with more than
#         MAX_DEPTH components, a segment over 64 KiB in a degraded scan, or the DEADLINE_S wall clock reached.
#         What was read before the limit is still judged: a deny wins; an ask-class match keeps its own reason
#         with the bound sentence appended; with nothing matched the ask is the bare `bound` one.
#   ask   the lexer returned no command for text that names something the guard decides on (rule id `lexer-empty`:
#         a lexer that silently dropped a command it should have judged). Judged on the text, full-line comments
#         (first non-blank character #) skipped and a later # not treated as a comment: (1) a whole-word token,
#         with the line split at blanks and shell metacharacters, that is rm, destroy, push, terraform, tofu, git
#         or eval in any case; (2) when the line has a quote, backslash, backtick or a $ that is not a plain
#         variable name, the line with those characters removed (r""m, 'r'm, ev""al) contains one of them. A
#         blank or comment-only command, and a bare redirect to a file that merely contains one (`> terraform.log`,
#         `> out.log`), is allowed.
#
# NOT DECIDED (stated, not implied). Obfuscation: a variable-built command name, glob or brace expansion of
# a command name (r[m], r{m,}), brace expansion of a target (`/{bin,usr}`), `xargs rm`, `find -delete` and
# `find -exec rm`, `rsync --delete`, other interpreters and tools (python shutil.rmtree), zsh-only expansions
# (=rm); wrappers outside the table (exec, builtin, setsid, ionice, stdbuf, flock, nsenter, chroot, `su -c`,
# `sudo -s '...'`, coproc); strings run later (trap strings, function bodies, aliases including `git -c
# alias.x=push`); shells fed on stdin (heredocs, here-strings, a pipe into bash or sh) and `source <(...)`; a
# runner name in another case (`BASH -c ...`, the lexer is case-sensitive there); a script written and then run;
# a piped SQL string; `drop database`/`dropdb`; MCP delete tools; any non-Bash tool (including Devin's
# `exec`: the raw tool_name must be Bash); Doppler secret writes and deletes; a plain `terraform apply`;
# `kubectl delete`; `pulumi destroy`; `terragrunt destroy`; `git push --mirror` without --force; and an
# unresolvable $VAR target.
#
# USER-FACING STATEMENT (the plugin README carries this sentence, word for word; the suite pins both copies):
# User-facing statement: The guard does not cover a plain `terraform apply`, secret writes, SQL, non-Bash tools,
# `terragrunt` or `pulumi` destroy, or indirect command forms (scripts or heredocs fed to a shell, wrappers it
# does not unwrap, obfuscated command names), and is not a substitute for scoped credentials.
#
# RESIDUALS of the shared lexer: it lexes an identical `bash -c`/`eval` string once, so the working-directory
# simulation cannot tell two identical inner strings under different `cd`s apart; a `cd` inside a subshell or a $(...) is treated as
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
# reason (the escape hatch and the issues URL included); an ask does not need it. The prompt of an ask shows the
# whole reason to the person, so an ask opens with a sentence written for that person (see REASONS below).
#
# FAILURE POSTURE (D6; a stated narrowing of ADR-157's `.claude` row, with reasons). An envelope jq rejects, a
# non-string .tool_input.command, empty stdin, a lexer parse failure (exit 2: unbalanced quote, unterminated
# substitution, NUL byte) and a lexer bound trip (exit 3: depth, budget, alarm, crash) all ASK; the parse
# reasons say "could not parse this command; it was not recognised as destructive" and never quote a command
# the hook did not match; a command too large to check (`bound`) and a lexer that returns nothing for real text
# (`lexer-empty`) ask too.
#
# REASONS. An ask opens with a sentence for the person at the prompt ("The guard paused this command and is
# asking you. It has not run yet and runs only if you approve."), then the rule id, a one-sentence lead and the
# quoted command, then the agent's instructions under "If you are the agent: This command was NOT run." A deny
# opens with "This command was NOT run." (the person reads a block, not a prompt). The agent's tail follows the
# cause: a matched destructive command says stop, do not retry, do not rephrase; a lexer parse failure (exit 2)
# says fix the quoting or heredoc and send it again; a lexer that gave out (depth, budget, alarm, crash) and a
# command too large to check say simplify or split; an unreadable envelope says the fault is in the tool call, so
# stop and tell the person; env -S and too many wrappers say write the command out so the guard can check it.
# Every ask and deny carries the escape hatch and the issues URL. The quoted command has credentials masked:
# NAME=value, --name=value and -var name=value with a key, tok, secret, pass, pw, cred, auth or bearer name; the
# word after --token, --password, --passwd, --secret, --api-key, --auth or --bearer; the text after
# `Authorization:` or `Bearer `; URL userinfo. That is a coverage choice, not a boundary. When jq cannot build the
# output (emit_fallback) the decision and the rule id are kept: a plain body goes out as it is, a body that quotes
# the command gets a fixed `guard-output-fallback` text, and a deny stays a deny.
#
# DEGRADED MODES. A missing or unusable `jq` does not ask on every call (that would make the plugin
# unusable without jq): the hook scans the RAW envelope for its own narrow patterns (recursive rm of / ~ or
# $HOME, `destroy`, `push` with a force flag or +), tolerating JSON-escaped whitespace; a hit asks (output
# hand-built with a fixed reason naming jq, plus a stderr notice naming jq), a miss exits 0. A missing or
# broken `perl` with a working jq scans the jq-decoded command the same way (stderr notice naming perl). Both
# scans stop with a `bound` ask at a segment over 64 KiB or at the deadline. It never DENIES on a dependency
# failure (the repair is itself a Bash call). A miss on the raw scan is a stated, tested fail-open (the
# raw-scan-miss residual ADR-165 accepted for its `.openhands` row, a mirror ADR-245 has since retired; ADR-274
# records why this hook asks on a hit where that row denied, and why its `.claude` row, which asks on every
# call, is narrowed).
#
# KILL SWITCH (D5). SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 (exactly 1; empty, 0 and anything else leave the
# guard on) exits 0 with no output, before any dependency probe. It is read from the harness process
# environment, so setting it needs a session restart. It can ALSO be set from a settings-level `env` block
# (settings.json "env"), which no Bash guard sees and which an agent that can edit a settings file can use:
# this is a seatbelt, not a boundary. Hosted sessions disable it through AGENT_ENV_OVERRIDES (D8).
#
# MECHANISM AND ORDER. Kill switch; read stdin; a tool call over 256 KiB asks `bound` at once; the zero-spawn
# prefilter; the raw tool_name (it must be exactly Bash, so Devin's `exec` is not decided); dependency probes by
# RESULT, not by `command -v` (a jq that is present and exits non-zero fails like an absent one; probed only on
# failure, so the happy path pays nothing); jq extraction (the command goes through `jq -j` straight into the lexer so
# NULs and newlines survive; the small fields use a separate jq call); lib/shell-argv.pl; the rule table; the
# decision. The prefilter skips the lexer only when the envelope holds exactly one `"command"` text, no backslash
# followed by u (a key spelled `"\u0063ommand"` is the key command to jq and not the text `"command"`), and that
# command's raw JSON text has NONE of the keywords rm (also as RM, Rm, rM), destroy, push, eval and none of
# backslash, single quote, double quote, $, a backtick, `<(`, `>(` or `<<`. It reads the command string only (the
# text after "command":" up to the first double quote), because the envelope's other fields can spell a keyword
# (permission_mode, a cwd of .../web-platform), and a double quote inside the command is always JSON-escaped with a
# backslash, so the backslash test is what sees it. It also requires a `{...}`-shaped envelope with a string
# "command" so garbage and a non-string command reach the jq path and ask. WHAT THE SKIP IS AND IS NOT: it is not
# "everything skipped is also allowed by the lexer path" (an unterminated `<(` or backtick is skipped by a
# keyword-only test yet asks on the lexer path, which is why those are boundary characters and why `<(`/`>(`
# were added after a differential fuzz found 79 such commands, all unterminated process substitutions). It is
# "nothing skipped can be a D1 command": every command in the decision set spells rm, destroy or push as a plain
# substring, and every other spelling of those (a quote, escape, expansion or runner) carries a boundary
# character; so the lexer path could only ever add a parse-failure or wrapper-depth ask to a skipped command, never a
# destructive-command decision.
# Every boundary character has a must-ASK row.
#
# DEPENDENCIES. bash (3.2 or later), jq, perl >= 5.10 with core pragmas only (the lexer), git (read-only,
# local `symbolic-ref`, only for a force/delete push), POSIX utilities. No `eval`, ever (ADR-156: hook stdin
# is model-controlled). The hook reads stdin and writes stdout and stderr; it writes no file (no here-string,
# which bash before 5.1 backs with a temporary file) and sends nothing off the machine.
#
# PORTABILITY (bash 3.2 and POSIX only). No bash-4 builtin, associative array or case-conversion expansion,
# and no GNU-only flag of the path, stream-edit, date or stat utilities. Lexer frames are read with
# `read -d ''` (a $(...) would strip the NULs); the decision is made from the `OK\0` terminator, never from
# an exit status lost across a process substitution. Empty-array expansions under `set -u` are guarded
# (`${x[@]+"${x[@]}"}`) wherever an array can be empty; the unguarded ones (`"${AV[@]}"`, `"${DA_T[@]}"`,
# `"${keep_t[@]}"`, `"${t[@]:...}"`, `"${defaults[@]}"`) are non-empty by invariant: a lexer record has argc >= 1
# and every slice or copy is taken only after an index < n check. What was run on bash 3.2.57 itself (docker bash:3.2
# with the host's jq, perl and git): the whole hook over a 30-command corpus (wrapper chains and case folding, env -C and
# sudo -D, lexer-empty redirects, redaction shapes, env -S, wrapper depth, a bound ask, a deep path), and the decisions and
# reason text were identical to bash 5.3. Not run on 3.2: the clock-trip and partial-record paths, the degraded (jq- or
# perl-less) scans and the output fallback. The suites run under the host bash.
# Path resolution has no canonicalising utility: one subshell finds the longest existing prefix of a directory
# (`cd -P`, then `pwd -P`) and the rest is normalized lexically, with the literal basename; HOME is compared in both its literal and physical forms. Inherited GIT_* variables are stripped
# BY PREFIX before any git call (a lefthook-exported GIT_DIR must not redirect it). The working directory is
# the envelope's .cwd, then CLAUDE_PROJECT_DIR, then PWD.
set -uo pipefail
# No pathname expansion: unquoted splits below must never glob.
set -f
export LC_ALL=C
unset CDPATH

# BOUNDS on the bash side (the harness kills this hook at hooks.json `timeout: 10`, and a killed hook is not a
# decision). The wall clock is `SECONDS`, reset here: it ticks on whole-second boundaries, so DEADLINE_S=6 trips
# between 5 and 6 s after this line, comfortably inside the 10 s budget. MAX_RECORDS caps the simple commands the
# rule table judges. MAX_WORDS caps the words of the whole command; its job is to bound the TIME one record takes to read
# (the frame-read loop costs about 120 us a word under load), not what the rule table can judge. MAX_DEPTH caps the
# components of a path the guard resolves, MAX_ENVELOPE the tool call and SCAN_MAX_SEG a degraded-scan segment. A command
# beyond any of them, or one that runs out of time, asks with rule id `bound` unless a deny was found in what was read
# (BOUND_SOFT: a trip while reading or resolving does not stop the judging of the rest). The lexer has its own 2 s alarm;
# these bound everything after it.
SECONDS=0
DEADLINE_S=6
MAX_RECORDS=2000
MAX_WORDS=20000
MAX_DEPTH=128
MAX_ENVELOPE=262144   # 256 KiB: a larger tool call asks `bound` before anything reads it (the prefilter and the raw scans are not linear)
SCAN_MAX_SEG=65536    # 64 KiB: the longest segment the raw/decoded scans will try their patterns on
BOUND_WHY=""
BOUND_SOFT=""

ISSUES_URL='https://github.com/jikig-ai/soleur/issues'
# A reason has two readers: the person at the prompt (an ask) and the agent. A body written as `<head><AMARK><tail>` is composed by
# compose() below: the tail is the agent's instructions. An ask opens with a sentence for the person and puts the agent's part under
# "If you are the agent:"; a deny (and its systemMessage) opens with the not-run sentence, as the person only reads a block.
AMARK=$'\001'
ASK_LEAD="The guard paused this command and is asking you. It has not run yet and runs only if you approve."
PERSON_TAIL=" The person can run the command themselves in their own terminal, outside the agent, or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1 set in their own shell. If this was flagged wrongly, report it at ${ISSUES_URL}"
# a matched destructive command: stop, do not retry, do not rephrase
REASON_TAIL="${AMARK} Stop and tell the person what you were about to run and why. Do not retry this command and do not rephrase it to get around the guard. If no person is available to answer, end the task and report it as blocked.${PERSON_TAIL}"
# a command too large to check, or a lexer that gave out (depth, budget, alarm, crash): simplify or split
BOUND_TAIL="${AMARK} Split it into smaller commands and send them one at a time; if you cannot, stop and report the task as blocked.${PERSON_TAIL}"
# a quoting or heredoc problem in the command (lexer exit 2) is repaired and resent
PARSE_TAIL="${AMARK} If this is a valid command you meant to run, fix its quoting or heredoc and send it again; if you cannot, stop and report the task as blocked.${PERSON_TAIL}"
# an envelope the hook cannot read is a fault in the tool call, not in the command
ENVELOPE_TAIL="${AMARK} This is a fault in the tool call the harness sent, not a problem with the command: stop and tell the person what happened instead of rewriting the command.${PERSON_TAIL}"
# env -S and too many wrappers hide the command: write it out so it can be checked
WRAPPER_TAIL="${AMARK} If this is a command you meant to run, write it out without env -S (or with fewer nested wrappers) so the guard can check it, and send it again; if you cannot, stop and tell the person what you were about to run.${PERSON_TAIL}"

# ---- output ---------------------------------------------------------------------------------------
# compose <ask|deny> <body> -> COMPOSED: the reason text (see AMARK).
COMPOSED=""
compose() {
  local head="${2%%"$AMARK"*}" tail=""
  [[ "$2" == *"$AMARK"* ]] && tail="${2#*"$AMARK"}"
  if [[ "$1" == deny ]]; then COMPOSED="This command was NOT run. ${head}${tail}"
  else COMPOSED="${ASK_LEAD} ${head} If you are the agent: This command was NOT run.${tail}"; fi
}
# emit <ask|deny> <body>: the full envelope (a bare decision without hookEventName is silently ignored), built with jq; when jq
# cannot build it, emit_fallback. A deny also carries systemMessage.
emit() {
  local out="" reason
  compose "$1" "$2"; reason="$COMPOSED"
  out="$(jq -nc --arg d "$1" --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}
     + (if $d == "deny" then {systemMessage: $r} else {} end)' 2>/dev/null)" || out=""
  if [[ -z "$out" ]]; then emit_fallback "$1" "$2"; return; fi
  printf '%s\n' "$out"
}
# emit_fixed <ask|deny> <body without quotes, backslashes or control characters>: no jq, no interpolation of input text.
emit_fixed() {
  compose "$1" "$2"
  if [[ "$1" == deny ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' "$COMPOSED" "$COMPOSED"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$COMPOSED"
  fi
}
# emit_fallback <ask|deny> <body>: jq could not build the output. A body of our own text (printable ASCII, no quote or backslash) goes
# out as it is, so the rule id, the lead and the tail survive. A body that quotes the command (it holds a quote, a backslash or a
# control character) gets a fixed text that keeps the rule id and the decision: a deny stays a deny and says it is blocked.
emit_fallback() {
  local fid="${2%%:*}"
  case "$fid" in ""|*[!a-z0-9-]*) fid=unknown ;; esac
  compose "$1" "$2"
  case "$COMPOSED" in
    *[![:print:]]*|*[\"\\]*)
      if [[ "$1" == deny ]]; then
        emit_fixed deny "guard-output-fallback: the destructive-command guard matched rule ${fid} and blocked this command, but jq could not build the full message that quotes it. ${AMARK} Stop and tell the person. Do not retry this command. If no person is available, end the task and report it as blocked. The person can run it in their own terminal or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1. Report a wrong flag at ${ISSUES_URL}"
      else
        emit_fixed ask "guard-output-fallback: the destructive-command guard matched rule ${fid}, but jq could not build the full message that quotes the command, so it is asking instead of allowing. ${AMARK} Stop and tell the person. Do not retry this command. If no person is available, end the task and report it as blocked. The person can run it in their own terminal or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1. Report a wrong flag at ${ISSUES_URL}"
      fi ;;
    *) emit_fixed "$1" "$2" ;;
  esac
}

# lead_for <rule id>: the one-sentence statement of what the rule matched.
lead_for() {
  case "$1" in
    recursive-delete-home) LEAD="this command recursively deletes the filesystem root, an ancestor of the home directory, the home directory, or everything inside one of them." ;;
    recursive-delete-workdir) LEAD="this command recursively deletes the working directory or one of its ancestors." ;;
    infra-destroy) LEAD="this command runs terraform or tofu destroy (or apply -destroy), which tears down infrastructure." ;;
    default-branch-force-push) LEAD="this command force-pushes over, or deletes, a default branch on a remote." ;;
    wrapper-depth) LEAD="this command nests more than 8 wrappers (sudo, env, timeout, ...) or -- separators, more than the guard unwraps, so the command it finally runs cannot be checked." ;;
    unparsed-wrapper) LEAD="this command runs env -S (--split-string), which splits a string into the command to run, and the guard does not analyse that string." ;;
    unresolved-cd-before-destructive) LEAD="a cd or pushd that cannot be resolved (a variable, or -) comes before a recursive delete or a force push in the same command, so the directory it acts on cannot be checked." ;;
    *) LEAD="this command matched a destructive-command rule." ;;
  esac
}

# ---- redaction: the matched command goes into the reason, the transcript and (on a deny) the systemMessage -------
# A word that carries a credential is masked BEFORE the text is joined and cut to 200 characters (so a cut can never
# leave half of one). Masked: (1) NAME=value, --name=value and -var name=value where NAME holds key, tok, secret, pass, pw (so pwd
# too), cred, auth or bearer in any case (the whole value, spaces included, because the lexer's word is one argument); (2) the word
# AFTER --token, --password, --passwd, --secret, --api-key, --auth or --bearer (unless it is itself a flag); (3) the text after
# `Authorization:` or `Bearer ` inside a word (an -H header, `-c http.extraheader=Authorization: Basic x`); (4) URL userinfo
# (`://user:pass@` keeps the user, a password may hold / or @; `://token@` masks it). Only the emit path calls this, one word at a
# time with bash regexes under nocasematch, so it costs no process. The names are a coverage choice, not a boundary: a
# credential in a word with none of these names (or a bare value) is not masked.
RE_SECRET_ASSIGN='^(([A-Za-z0-9_.-]*=)?-{0,2}[A-Za-z0-9_.-]*(key|tok|secret|pass|pw|cred|auth|bearer)[A-Za-z0-9_.-]*=)'
RE_URL_PW='^(.*://[^/@[:space:]:]*:)[^[:space:]]*(@[^@[:space:]]*)$'
RE_URL_USER='^(.*://)[^/@[:space:]:]+(@.*)$'
RE_AUTH_HDR='^(.*authorization:[[:space:]]*)(.+)$'
RE_BEARER='^(.*bearer[[:space:]]+)(.+)$'
RE_FLAG_NEXT='^--(token|password|passwd|secret|api-key|auth|bearer)$'
RW=""; RW_NEXT=0
redact_word() { # <word> -> RW; RW_NEXT (1 = the word after a credential flag) carries across words: the caller resets it per command
  local w="$1" had=0 mask=0
  if (( RW_NEXT )) && [[ "$w" != -* ]]; then RW="<redacted>"; RW_NEXT=0; return; fi
  shopt -q nocasematch && had=1
  shopt -s nocasematch
  if [[ "$w" =~ $RE_SECRET_ASSIGN ]]; then w="${BASH_REMATCH[1]}<redacted>"
  elif [[ "$w" =~ $RE_URL_PW ]]; then w="${BASH_REMATCH[1]}<redacted>${BASH_REMATCH[2]}"
  elif [[ "$w" =~ $RE_URL_USER ]]; then w="${BASH_REMATCH[1]}<redacted>${BASH_REMATCH[2]}"
  elif [[ "$w" =~ $RE_AUTH_HDR ]]; then w="${BASH_REMATCH[1]}<redacted>"
  elif [[ "$w" =~ $RE_BEARER ]]; then w="${BASH_REMATCH[1]}<redacted>"
  elif [[ "$w" =~ $RE_FLAG_NEXT ]]; then mask=1
  fi
  (( had )) || shopt -u nocasematch
  RW_NEXT="$mask"
  RW="$w"
}
# redact_text <text> -> RTXT: the same, over the blank-separated words of raw text (the perl-less scan has text, not words). A word
# that opens with a quote is taken with the words after it up to the one that closes it, and the quotes are dropped, so a quoted
# name=value is read as the word the shell would have made of it. Whole words only, and it stops after the 200 shown characters.
RTXT=""
redact_text() {
  local IFS=$' \t\n' w q i=0 n out=""
  local -a ws
  # shellcheck disable=SC2206  # the split on blanks is the point (no pathname expansion: set -f)
  ws=($1); n=${#ws[@]}
  while (( i < n )); do
    (( ${#out} > 200 )) && break
    w="${ws[$i]}"; i=$((i + 1)); q=""
    case "$w" in \'*|\"*) q="${w:0:1}"; w="${w#"$q"}" ;; esac
    if [[ -n "$q" ]]; then
      while [[ "$w" != *"$q" ]] && (( i < n )); do w="$w ${ws[$i]}"; i=$((i + 1)); done
      w="${w%"$q"}"
    fi
    redact_word "$w"; out="${out:+$out }$RW"
  done
  RTXT="$out"
}

ask_parse() { # <cause text>: a command the lexer could not read. Only a parse failure (exit 2) is repaired by fixing the quoting;
  # a lexer that gave out (depth, budget, alarm, crash, no result, malformed output) wants a simpler or smaller command.
  local tail="$BOUND_TAIL"
  [[ "$1" == "lexer exit2" ]] && tail="$PARSE_TAIL"
  emit ask "command-not-parsed: the destructive-command guard could not parse this command; it was not recognised as destructive, and the guard asks rather than guess (${1}).${tail}"
  exit 0
}
ask_lexer_empty() {
  emit ask "lexer-empty: the destructive-command guard's lexer returned no command for this input, which mentions a word the guard decides on (rm, destroy, push, terraform, tofu, git or eval); it was not recognised as destructive, and the guard asks rather than guess.${PARSE_TAIL}"
  exit 0
}
ask_bound() { # <why>: a command too large to check in full
  emit ask "bound: the destructive-command guard stopped checking this command because it is too large to check in full (${1}); it was not recognised as destructive, and the guard asks rather than guess.${BOUND_TAIL}"
  exit 0
}
ask_envelope() { # <cause text>
  emit ask "envelope-unreadable: the destructive-command guard could not read this tool call (${1}), and it asks rather than allow what it cannot read.${ENVELOPE_TAIL}"
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
# scan_narrow <text>: 0 on a hit (SCAN_SEG = the matched segment), 1 on a miss, 2 when a bound tripped (SCAN_WHY): a segment
# longer than SCAN_MAX_SEG (the patterns are not linear in a segment's length) or the clock reached DEADLINE_S.
SCAN_WHY=""
scan_narrow() {
  local seg IFS=$';&|\n'
  for seg in $1; do
    if (( ${#seg} > SCAN_MAX_SEG )); then SCAN_WHY="a command segment longer than 64 KiB"; return 2; fi
    if (( SECONDS >= DEADLINE_S )); then SCAN_WHY="the ${DEADLINE_S} s time limit was reached while scanning"; return 2; fi
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

# An oversize tool call asks before anything reads it (the prefilter below and the raw scans are not linear in its size).
if (( ${#INPUT} > MAX_ENVELOPE )); then ask_bound "the tool call is larger than 256 KiB"; fi

# ---- 2. the zero-spawn prefilter (D7) --------------------------------------------------------------
# Skip the lexer only for a `{...}` envelope with a STRING command that has no keyword and no boundary
# character. See the header: only the command's own raw JSON text is scanned.
PF_LEAD="${INPUT#"${INPUT%%[![:space:]]*}"}"
PF_TAIL="${INPUT%"${INPUT##*[![:space:]]}"}"
PF_CMD_RE='"command"[[:space:]]*:[[:space:]]*"'
# Exactly one `"command"` text in the whole envelope, or the prefilter does not decide: it reads the FIRST key
# while jq reads .tool_input.command, so a decoy key before the real one (nested, in an array, at the top level, or
# a duplicate) must go to jq. Nine characters are the text `"command"`. A key can also be spelled with a \u escape
# (`"\u0063ommand"` is the key command to jq and not the text `"command"` to the count), so an envelope that holds a
# backslash followed by u anywhere goes to jq.
PF_ONCE="${INPUT//\"command\"/}"
if [[ "${PF_LEAD:0:1}" == "{" && "${PF_TAIL: -1}" == "}" && $(( ${#INPUT} - ${#PF_ONCE} )) -eq 9 && "$INPUT" != *'\u'* && "$INPUT" =~ $PF_CMD_RE ]]; then
  PF_MARK="${BASH_REMATCH[0]}"
  PF_REST="${INPUT#*"$PF_MARK"}"
  PF_CMD="${PF_REST%%\"*}"
  case "$PF_CMD" in
    *rm*|*destroy*|*push*|*eval*|*Rm*|*RM*|*rM*|*'<('*|*'>('*|*'<<'*|*[\\\'\"\$\`]*) : ;;
    *) exit 0 ;;
  esac
fi

# ---- 3. the lexer path -----------------------------------------------------------------------------
HOOK_SRC="${BASH_SOURCE[0]}"
HOOK_DIR="${HOOK_SRC%/*}"; [[ "$HOOK_DIR" == "$HOOK_SRC" ]] && HOOK_DIR=.
LEXER="$HOOK_DIR/lib/shell-argv.pl"

# (no regex function: a jq built without regex support must still read the envelope; newlines and carriage returns become blanks so the
# three fields stay three lines)
JQ_FIELDS='if type != "object" then "invalid" else
  ((.tool_name // "" | if type == "string" then . else "" end | split("\n") | join(" ") | split("\r") | join(" ")),
   (.cwd // "" | if type == "string" then . else "" end | split("\n") | join(" ") | split("\r") | join(" ")),
   (try (.tool_input.command | type) catch "invalid"))
end'

degrade_jq() {
  echo "soleur destructive-command-guard: jq is missing or unusable on this machine; scanning the raw tool input with the guard's own narrow patterns instead of parsing it (install jq for full coverage)" >&2
  local raw="$INPUT"
  raw="${raw//\\n/;}"; raw="${raw//\\u000[aA]/;}"; raw="${raw//\\u000[dD]/;}"
  raw="${raw//\\t/ }"; raw="${raw//\\r/ }"; raw="${raw//\\u0009/ }"; raw="${raw//\\u0020/ }"
  scan_narrow "$raw"; SCAN_RC=$?
  [[ "$SCAN_RC" -eq 2 ]] && ask_bound "$SCAN_WHY"
  if [[ "$SCAN_RC" -eq 0 ]]; then
    emit_fixed ask "guard-degraded-jq-missing: jq is missing or unusable on this machine, so the destructive-command guard scanned the raw tool input instead of parsing it, and this call looks destructive (a recursive delete of / or home, a destroy, or a force push).${AMARK} Stop and tell the person. Do not retry this command or rephrase it. If no person is available, end the task and report it as blocked. The person can run it in their own terminal, or start the session with SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1, or install jq. Report a wrong flag at ${ISSUES_URL}"
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
# Only a Bash call is decided, by the RAW name (Devin's `exec` is not decided: D2). A missing tool_name is read as Bash (fail toward deciding); the registered
# matcher is ^Bash$, so a real call always carries it.
if [[ -n "$RAW_TOOL" ]]; then
  [[ "$RAW_TOOL" == Bash ]] || exit 0
fi
[[ "$CMD_TYPE" == string ]] || ask_envelope "tool_input.command is not a string"

# ---- 4. lex ----------------------------------------------------------------------------------------
# Frames: C \0 ctx \0 argc \0 (flags \0 arg \0){argc} ... then OK \0 (or E \0 cause \0 on failure).
W_TXT=(); W_FLG=(); REC_OFF=(); REC_N=()
SAW_OK=0; SAW_E=""; LEX_BAD=0; BOUND_READ=0
LEX_ST=0; LEX_LEFT=0; LEX_KIND=0; NW=0; FRN=0
while IFS= read -r -d '' F; do
  # a clock check every 1024 frames, so one huge record is bounded too (the per-record check below sees only record starts)
  FRN=$((FRN + 1))
  if (( (FRN & 1023) == 0 && SECONDS >= DEADLINE_S )); then
    BOUND_SOFT="the ${DEADLINE_S} s time limit was reached while reading the lexer output"; BOUND_READ=1
    if (( LEX_ST == 3 )); then
      # a record cut mid-way keeps the words it has: they are judged; with none complete it is dropped (its words are not all there)
      LEX_DONE=$((NW - REC_OFF[${#REC_OFF[@]} - 1]))
      if (( LEX_DONE > 0 )); then REC_N[${#REC_N[@]} - 1]="$LEX_DONE"
      else unset 'REC_OFF[${#REC_OFF[@]} - 1]' 'REC_N[${#REC_N[@]} - 1]'; fi
    fi
    break
  fi
  case "$LEX_ST" in
    0) case "$F" in C) LEX_ST=1 ;; OK) SAW_OK=1 ;; E) LEX_ST=9 ;; *) LEX_BAD=1 ;; esac ;;
    1) LEX_ST=2 ;;                                   # the ctx field
    2) if [[ "$F" =~ ^[1-9][0-9]{0,6}$ ]]; then
         if (( ${#REC_N[@]} >= MAX_RECORDS )); then BOUND_SOFT="more than ${MAX_RECORDS} simple commands"; break; fi
         if (( NW + F > MAX_WORDS )); then BOUND_SOFT="more than ${MAX_WORDS} words"; break; fi
         if (( SECONDS >= DEADLINE_S )); then BOUND_SOFT="the ${DEADLINE_S} s time limit was reached while reading the lexer output"; BOUND_READ=1; break; fi
         REC_OFF[${#REC_OFF[@]}]="$NW"; REC_N[${#REC_N[@]}]="$F"; LEX_LEFT=$((F * 2)); LEX_KIND=0; LEX_ST=3
       else LEX_BAD=1; LEX_ST=0; fi ;;
    3) if [[ "$LEX_KIND" -eq 0 ]]; then W_FLG[${#W_FLG[@]}]="$F"; LEX_KIND=1
       else W_TXT[${#W_TXT[@]}]="$F"; LEX_KIND=0; NW=$((NW + 1)); fi
       LEX_LEFT=$((LEX_LEFT - 1)); [[ "$LEX_LEFT" -le 0 ]] && LEX_ST=0 ;;
    9) SAW_E="$F"; LEX_ST=0 ;;
  esac
done < <({ printf '%s' "$INPUT" | jq -j '.tool_input.command' | perl "$LEXER"; } 2>/dev/null)

# A read-time trip (a record or word cap, or the clock: BOUND_SOFT) does not discard the records already read: the rule table
# judges them, and the decision below is a deny if one matched, else a bound ask. After a clock trip the judging gets 2 more
# seconds (the harness kills the hook at 10 s).
[[ "$BOUND_READ" -eq 1 ]] && DEADLINE_S=$((DEADLINE_S + 2))
if [[ "$SAW_OK" -ne 1 && -z "$BOUND_SOFT" ]]; then
  if [[ -n "$SAW_E" ]]; then ask_parse "lexer ${SAW_E}"; fi
  # No OK and no E: the lexer was killed, crashed, or perl is missing/unusable. Probe by RESULT.
  PERL_PROBE="$(perl -e 'print "ok"' 2>/dev/null)" || PERL_PROBE=""
  if [[ "$PERL_PROBE" != ok || ! -r "$LEXER" ]]; then
    echo "soleur destructive-command-guard: perl (or its lexer) is missing or unusable on this machine; scanning the decoded command with the guard's own narrow patterns instead of lexing it (install perl for full coverage)" >&2
    DEC_CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)" || DEC_CMD=""
    scan_narrow "$DEC_CMD"; SCAN_RC=$?
    [[ "$SCAN_RC" -eq 2 ]] && ask_bound "$SCAN_WHY"
    if [[ "$SCAN_RC" -eq 0 ]]; then
      redact_text "$SCAN_SEG"
      emit ask "guard-degraded-perl-missing: perl is missing or unusable on this machine, so the destructive-command guard scanned the decoded command with its narrow patterns instead of lexing it, and this call looks destructive. Matched segment: ${RTXT:0:200}.${REASON_TAIL}"
    fi
    exit 0
  fi
  ask_parse "the lexer produced no result"
fi
[[ "$LEX_BAD" -eq 1 ]] && ask_parse "the lexer output was malformed"
# OK with no record is the right answer for a blank or comment-only command and for a command whose text names nothing the
# guard decides on (a bare redirect, `> out.log`): there is nothing here for the guard to judge. A lexer that returned nothing
# for text that DOES name something the guard decides on has silently dropped its input, and asks. The test is on the text, in
# two parts: (1) a whole-word token (the line split on blanks and shell metacharacters) that is rm, destroy, push, terraform, tofu,
# git or eval in any case, so a file NAME that merely contains one (terraform.log, format.log, rm.txt) is not a hit; and (2)
# when the line has a quote, a backslash, a backtick or a $ that is not a plain variable name, the line read again with those
# characters removed (r""m, 'r'm, r\m, $'r''m', ev""al) contains one of them as a substring. A line whose first non-blank character
# is # is a comment and is skipped; a # later in a line is not a comment ("a #b" is a quoted string), so nothing after it is
# dropped. No process and no here-string (bash before 5.1 writes a temporary file for <<<).
RE_DOLLAR_X='\$([^A-Za-z0-9_]|$)'
lexer_empty_hit() { # <command text>: 0 when the text mentions what the guard decides on
  local rest="$1" ln j w had=0 hit=1 fin=0
  shopt -q nocasematch && had=1
  shopt -s nocasematch
  while :; do
    case "$rest" in
      *$'\n'*) ln="${rest%%$'\n'*}"; rest="${rest#*$'\n'}" ;;
      *) ln="$rest"; rest=""; fin=1 ;;
    esac
    ln="${ln#"${ln%%[![:space:]]*}"}"
    if [[ -n "$ln" && "$ln" != '#'* ]]; then
      j="${ln//[;&|()<>\$\"\'\`\\]/ }"
      for w in $j; do
        case "$w" in rm|destroy|push|terraform|tofu|git|eval) hit=0; break 2 ;; esac
      done
      if [[ "$ln" == *[\'\"\\\`]* || "$ln" =~ $RE_DOLLAR_X ]]; then
        j="${ln//[\'\"\\\`\$]/}"
        # (`terraform` contains `rm`, so `*rm*` already covers it; this order differs from the prefilter's on purpose: the mutation suite anchors on the prefilter's pattern run, which must stay unique in this file)
        case "$j" in *git*|*tofu*|*eval*|*destroy*|*push*|*rm*) hit=0; break ;; esac
      fi
    fi
    (( fin )) && break
  done
  (( had )) || shopt -u nocasematch
  return "$hit"
}
if [[ "${#REC_N[@]}" -eq 0 && -z "$BOUND_SOFT" ]]; then
  LX_CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)" || ask_lexer_empty
  if lexer_empty_hit "$LX_CMD"; then ask_lexer_empty; fi
fi

# ---- 5. the rule table -----------------------------------------------------------------------------
BEST_RANK=0; BEST_RULE=""; BEST_QUOTE=""
REC_RANK=0; REC_RULE=""
note() { # <rank 1|2> <rule id>
  if (( $1 > REC_RANK )); then REC_RANK="$1"; REC_RULE="$2"; fi
}

SIMCWD=""; ORIGCWD=""; CWD_READY=0; UNRES=0; EH=""; EH_READY=0
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

# resolve_phys <abs path> <follow 0|1> -> RP (empty = no decision: rm refuses `.`)
# follow=1: the path itself is resolved through symlinks (a trailing slash or a glob suffix); follow=0: a
# bare final name stays literal (`rm -rf link` only unlinks the link). A path with more than MAX_DEPTH components
# sets BOUND_SOFT and returns 1 (nothing about that path was resolved); the rest of the command is still judged, so a
# deny elsewhere in it wins, and the decision asks `bound` when nothing denied.
#
# phys_walk <abs dir> -> WK WP: ONE subshell finds the longest existing prefix of the directory (WP, physical) and how
# many trailing components it had to drop to get there (WK; 0 = the directory itself exists). The answer is cached per
# directory (a long target list shares its parents) in a table capped at PW_MAX entries, so a lookup is a short scan;
# only this final per-directory answer is cached, never a probe of a prefix.
PW_K=(); PW_V=()
PW_MAX=256
phys_walk() {
  local k n=${#PW_K[@]} out
  for ((k = 0; k < n; k++)); do
    if [[ "${PW_K[$k]}" == "$1" ]]; then out="${PW_V[$k]}"; WK="${out%%$'\n'*}"; WP="${out#*$'\n'}"; return 0; fi
  done
  out="$( cd / && q="$1" && c=0 && while ! cd -P -- "$q" 2>/dev/null; do c=$((c + 1)); q="${q%/*}"; [[ -z "$q" ]] && q=/; (( c > MAX_DEPTH + 2 )) && break; done; printf '%s\n' "$c"; pwd -P )" || out=""
  WK="${out%%$'\n'*}"; WP="${out#*$'\n'}"
  [[ "$WK" =~ ^[0-9]+$ ]] || { WK=0; WP=""; }
  if (( n < PW_MAX )); then PW_K[n]="$1"; PW_V[n]="$WK"$'\n'"$WP"; fi
}

resolve_phys() {
  local p="$1" follow="$2" last dir rest probe slashes k
  RP=""
  while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
  if [[ "$p" == / ]]; then RP=/; return 0; fi
  slashes="${p//[!\/]/}"
  if (( ${#slashes} > MAX_DEPTH )); then BOUND_SOFT="a path with more than ${MAX_DEPTH} components"; return 1; fi
  last="${p##*/}"
  if [[ "$follow" == 0 && "$last" == . ]]; then return 1; fi
  dir="${p%/*}"; [[ -z "$dir" ]] && dir=/
  if [[ "$follow" == 1 || "$last" == .. ]]; then
    # the path itself first; when it is missing the same walk already knows its parent (one component fewer)
    phys_walk "$p"
    if (( WK == 0 )) && [[ -n "$WP" ]]; then RP="$WP"; return 0; fi
    k=$((WK - 1)); [[ "$k" -lt 0 ]] && k=0
  else
    phys_walk "$dir"
    k="$WK"
  fi
  [[ -n "$WP" ]] || { WP=/; }
  rest="$last"; probe="$dir"
  while (( k > 0 )); do
    rest="${probe##*/}/$rest"; probe="${probe%/*}"; [[ -z "$probe" ]] && probe=/
    k=$((k - 1))
  done
  lex_norm "${WP%/}/$rest"; RP="$LN"
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
  SIMCWD="$RP"; ORIGCWD="$RP"
}

# eff_home -> EH: HOME when it is set, else the directory bash itself would use for ~ (the passwd entry), else
# empty. The lookup is one subshell, and only when HOME is empty or unset.
eff_home() {
  [[ "$EH_READY" -eq 1 ]] && return 0
  EH_READY=1
  if [[ -n "${HOME:-}" ]]; then EH="$HOME"; else EH="$( ( unset HOME; cd ~ 2>/dev/null && pwd -P ) 2>/dev/null )"; fi
}

home_ready() {
  [[ "$HOME_READY" -eq 1 ]] && return 0
  HOME_READY=1
  eff_home
  local h="$EH"
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
      '~'|'~/'*) eff_home; [[ -n "$EH" ]] || return 1; P='~'; t="$EH${t#"$P"}" ;;
      '~+'|'~+/'*) cwd_ready; P='~+'; t="$SIMCWD${t#"$P"}" ;;
      '~'*) return 1 ;;
    esac
  fi
  if (( xd )); then
    case "$t" in
      '$HOME'|'$HOME/'*) P='$HOME'; t="${HOME:-}${t#"$P"}" ;;  # an unset HOME expands to nothing: $HOME/* is /*
      '${HOME}'|'${HOME}/'*) P='${HOME}'; t="${HOME:-}${t#"$P"}" ;;
      '$PWD'|'$PWD/'*) cwd_ready; P='$PWD'; t="$SIMCWD${t#"$P"}" ;;
      '${PWD}'|'${PWD}/'*) cwd_ready; P='${PWD}'; t="$SIMCWD${t#"$P"}" ;;
    esac
    case "$t" in *'$'*|*'`'*|*'<('*|*'>('*) return 1 ;; esac
  fi
  [[ -n "$t" ]] || return 1
  EW="$t"
  return 0
}

# glob_contents <text> <quoted 0|1> -> GD: 0 when the target names the CONTENTS of a directory, i.e. every path
# component after the glob-free root is only glob syntax (`*`, `**`, `?`, `[a-z]`, in any run): /** /*/* /*/ /?
# /[a-z]* ~/** and a bare * or ./*. A component that mixes literal text with a glob (`*.log`, `.*`, `node_modules`
# after a `*`) is a different set of files and is not matched. A quoted target is a glob only in the old
# trailing-/* spelling (see the header: `~/*` is read as home even when quoted).
RE_GLOB_ONLY='^(\*|\?|\[[^]]+\])+$'
glob_contents() {
  local t="$1" qd="$2" comp="" root="" seen=0 IFS=/ lead=""
  GD=""
  if (( qd )); then
    if [[ "$t" == */'*' ]]; then GD="${t%/\*}"; [[ -z "$GD" ]] && GD=/; return 0; fi
    return 1
  fi
  [[ "$t" == /* ]] && lead=/
  for comp in $t; do
    if (( seen )); then
      [[ -z "$comp" ]] && continue
      [[ "$comp" =~ $RE_GLOB_ONLY ]] || return 1
    elif [[ "$comp" =~ $RE_GLOB_ONLY ]]; then seen=1
    else
      case "$comp" in *'*'*|*'?'*|*'['*) return 1 ;; esac
      [[ -n "$comp" ]] && root="${root:+$root/}$comp"
    fi
  done
  (( seen )) || return 1
  if [[ -n "$lead" ]]; then GD="/$root"; else GD="${root:-.}"; fi
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
    if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the targets of rm"; return 0; fi
    expand_word "${a[$k]}" "${fl[$k]}" || continue
    T="$EW"; glob=0; follow=0
    if glob_contents "$T" "$EW_Q"; then glob=1; follow=1; D="$GD"
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
    elif (( glob == 0 )) && { anc_or_eq "$RP" "$SIMCWD" || anc_or_eq "$RP" "$ORIGCWD"; }; then note 1 recursive-delete-workdir; fi
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
      case "$x" in
        -destroy|--destroy) note 1 infra-destroy; return 0 ;;
        -destroy=*|--destroy=*)  # a Go bool: 0 f F false FALSE False turn it off, every other value is on (or an error)
          case "${x#*=}" in 0|f|F|false|FALSE|False) : ;; *) note 1 infra-destroy; return 0 ;; esac ;;
      esac
    done
  fi
}

rule_git() {
  local -a a=("${AV[@]}") pos=() refs=() D_DST=() D_F=() D_DEL=()
  local n=${#a[@]} i=1 j k c x name end=0 repo cur head remote named
  local force=0 del=0 allf=0 mirror=0 repoopt=0 risk=0 r f dele src dst mt=0 mtf=0
  cwd_ready; repo="$SIMCWD"
  while (( i < n )); do
    if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the options of git"; return 0; fi
    case "${a[$i]}" in
      -C) if (( i + 1 < n )); then
            case "${a[$((i + 1))]}" in /*) repo="${a[$((i + 1))]}" ;; *) repo="$repo/${a[$((i + 1))]}" ;; esac
          fi
          i=$((i + 2)) ;;
      # the separate-argument forms take the next word; `--opt=value` and every other flag take none
      -c|--config-env|--git-dir|--work-tree|--namespace|--super-prefix|--attr-source) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [[ "${a[$i]:-}" == push ]] || return 0
  j=$((i + 1))
  while (( j < n )); do
    if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the flags of git push"; return 0; fi
    x="${a[$j]}"
    if (( end )); then pos[${#pos[@]}]="$x"
    elif [[ "$x" == -- ]]; then end=1
    elif [[ "$x" == --* ]]; then
      name="${x%%=*}"
      case "$name" in
        --force*) force=1 ;;
        --de|--del|--dele|--delet|--delete) del=1 ;;
        --al|--all) allf=1 ;;                                  # --al is the shortest unique abbreviation (--a is ambiguous)
        --m|--mi|--mir|--mirr|--mirro|--mirror) mirror=1 ;;
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
    if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the refs of git push"; return 0; fi
    f=0; dele=0
    if [[ "$r" == +* ]]; then f=1; r="${r#+}"; fi
    if [[ "$r" == : ]]; then
      mt=1; (( f )) && mtf=1  # the matching refspec: every branch both sides have
      dst=""
    elif [[ "$r" == *:* ]]; then
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
  if (( mt && (force || mtf) )); then note 1 default-branch-force-push; return 0; fi
  head=""; cur=""; local have_head=0 have_cur=0
  local -a defaults=(main master)
  for ((k = 0; k < ${#D_DST[@]}; k++)); do
    if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the destinations of git push"; return 0; fi
    dst="${D_DST[$k]}"
    if [[ "$dst" == HEAD ]]; then
      if (( ! have_cur )); then cur="$(git_ro "$repo" symbolic-ref --short HEAD)"; have_cur=1; fi
      dst="$cur"
    fi
    dst="${dst#refs/heads/}"; dst="${dst#heads/}"
    [[ -n "$dst" ]] || continue
    if (( force || D_F[k] || del || D_DEL[k] )); then
      # a destination with glob syntax can name a default branch (refs/heads/*:refs/heads/*)
      case "$dst" in *'*'*|*'?'*|*'['*) note 1 default-branch-force-push; return 0 ;; esac
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

# short_val <value-taking letters> <option word>: 0 when a short-option cluster (-nHu) ENDS in a value-taking
# letter, so that option's value is the NEXT word. A value-taking letter earlier in the cluster takes the rest of
# the word as its value (-uroot), which needs no extra word.
short_val() {
  local letters="$1" w="$2" k c
  for ((k = 1; k < ${#w}; k++)); do
    c="${w:$k:1}"
    case "$letters" in *"$c"*) (( k == ${#w} - 1 )); return ;; esac
  done
  return 1
}

# short_first_val <value-taking letters> <option word> -> SFV SFV_REST: the first value-taking letter of a short-option cluster and
# what follows it in the word (empty = the value is the NEXT word; non-empty = the value is attached: -D/tmp).
SFV=""; SFV_REST=""
short_first_val() {
  local letters="$1" w="$2" k c
  SFV=""; SFV_REST=""
  for ((k = 1; k < ${#w}; k++)); do
    c="${w:$k:1}"
    case "$letters" in *"$c"*) SFV="$c"; SFV_REST="${w:$((k + 1))}"; return 0 ;; esac
  done
  return 1
}

# A wrapper's chdir option (env -C DIR, --chdir DIR; sudo -D DIR, --chdir DIR) is reported in WCD (the directory word), WCDF (its
# lexer flags) and WCD_SET: the wrapped command runs there, and decide_walk judges it with the simulated working directory moved.
WCD=""; WCDF="-"; WCD_SET=0

# wrap_skip <name> <index of name in t> -> WJ: the index of the wrapped command's first word, or -1 when
# the wrapper is a look-up only (`command -v`) or its payload is a string the guard does not analyse (env -S).
# Reads t[] and n of the caller (dynamic scope, by design).
wrap_skip() {
  local name="$1" j=$(($2 + 1)) a lname k c eat split
  WJ=-1
  case "$name" in
    sudo)
      while (( j < n )) && [[ "${t[$j]}" == -* && "${t[$j]}" != - ]]; do
        a="${t[$j]}"; k=$j; j=$((j + 1))
        [[ "$a" == -- ]] && break
        case "$a" in
          --chdir) WCD="${t[$j]:-}"; WCDF="${f[$j]:--}"; WCD_SET=1; j=$((j + 1)) ;;
          --chdir=*) WCD="${a#--chdir=}"; WCDF="${f[$k]:--}"; WCD_SET=1 ;;
          --user|--group|--host|--prompt|--chroot|--role|--type|--close-from|--command-timeout|--other-user) j=$((j + 1)) ;;
          --*) : ;;
          *) if short_first_val ughpCTUDRrt "$a"; then
               if [[ -z "$SFV_REST" ]]; then
                 [[ "$SFV" == D ]] && { WCD="${t[$j]:-}"; WCDF="${f[$j]:--}"; WCD_SET=1; }
                 j=$((j + 1))
               else
                 [[ "$SFV" == D ]] && { WCD="$SFV_REST"; WCDF="${f[$k]:--}"; WCD_SET=1; }
               fi
             fi ;;
        esac
      done
      while (( j < n )) && is_assign "${t[$j]}"; do j=$((j + 1)); done ;;
    doas)
      while (( j < n )) && [[ "${t[$j]}" == -* && "${t[$j]}" != - ]]; do
        a="${t[$j]}"; j=$((j + 1))
        [[ "$a" == -- ]] && break
        if short_val uC "$a"; then j=$((j + 1)); fi
      done ;;
    env)
      while (( j < n )); do
        a="${t[$j]}"
        if [[ "$a" == -- ]]; then j=$((j + 1)); break
        elif [[ "$a" == - ]]; then j=$((j + 1))
        elif [[ "$a" == --* ]]; then
          lname="${a%%=*}"; lname="${lname#--}"
          if [[ -n "$lname" && "split-string" == "$lname"* ]]; then note 1 unparsed-wrapper; return 0; fi
          if [[ -n "$lname" && "chdir" == "$lname"* ]]; then
            if [[ "$a" == *=* ]]; then WCD="${a#*=}"; WCDF="${f[$j]:--}"; WCD_SET=1
            else WCD="${t[$((j + 1))]:-}"; WCDF="${f[$((j + 1))]:--}"; WCD_SET=1; fi
          fi
          j=$((j + 1))
          # a value-taking long option with its value in the next word: --unset X, --chdir D, --argv0 A
          if [[ "$a" != *=* && -n "$lname" ]] && { [[ "unset" == "$lname"* ]] || [[ "chdir" == "$lname"* ]] || [[ "argv0" == "$lname"* ]]; }; then j=$((j + 1)); fi
        elif [[ "$a" == -?* ]]; then
          eat=0; split=0
          for ((k = 1; k < ${#a}; k++)); do
            c="${a:$k:1}"
            case "$c" in
              S) split=1; break ;;
              u|C|P|a)
                if (( k == ${#a} - 1 )); then
                  eat=1
                  [[ "$c" == C ]] && { WCD="${t[$((j + 1))]:-}"; WCDF="${f[$((j + 1))]:--}"; WCD_SET=1; }
                else
                  [[ "$c" == C ]] && { WCD="${a:$((k + 1))}"; WCDF="${f[$j]:--}"; WCD_SET=1; }
                fi
                break ;;
            esac
          done
          if (( split )); then note 1 unparsed-wrapper; return 0; fi
          j=$((j + 1 + eat))
        elif is_assign "$a"; then j=$((j + 1))
        else break; fi
      done ;;
    timeout)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in
          --signal|--kill-after) j=$((j + 1)) ;;
          --*) : ;;
          *) if short_val sk "$a"; then j=$((j + 1)); fi ;;
        esac
      done
      j=$((j + 1)) ;;
    nice)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in
          --adjustment) j=$((j + 1)) ;;
          --*) : ;;
          *) if short_val n "$a"; then j=$((j + 1)); fi ;;
        esac
      done ;;
    time)  # the external time(1) (/usr/bin/time, `command time`, `env time`); the reserved word is the lexer's
      while (( j < n )) && [[ "${t[$j]}" == -* && "${t[$j]}" != - ]]; do
        a="${t[$j]}"; j=$((j + 1))
        [[ "$a" == -- ]] && break
        case "$a" in
          --format|--output) j=$((j + 1)) ;;
          --*) : ;;
          *) if short_val fo "$a"; then j=$((j + 1)); fi ;;
        esac
      done ;;
    command)
      while (( j < n )) && [[ "${t[$j]}" == -* ]]; do
        a="${t[$j]}"; j=$((j + 1))
        case "$a" in --) break ;; -v|-V|-[a-zA-Z]*[vV]*) return 0 ;; esac
      done ;;
    nohup|-p) : ;;  # `-p` is `time -p`: the lexer drops the reserved word `time` and leaves -p as the first word
  esac
  WJ="$j"
}

# fold_name <name> -> FN: the command name in lower case when it is one the table knows, else the name as it is. No process is
# started (a `tr` per record cost 3 ms each and, with no `tr` on the PATH, silently allowed RM): the case statement runs under
# nocasematch, which is restored.
FN=""
fold_name() {
  local had=0
  FN="$1"
  shopt -q nocasematch && had=1
  shopt -s nocasematch
  case "$1" in
    rm) FN="rm" ;; terraform) FN="terraform" ;; tofu) FN="tofu" ;; git) FN="git" ;;
    sudo) FN="sudo" ;; doas) FN="doas" ;; env) FN="env" ;; command) FN="command" ;; nohup) FN="nohup" ;;
    time) FN="time" ;; timeout) FN="timeout" ;; nice) FN="nice" ;;
  esac
  (( had )) || shopt -u nocasematch
}

# walk_in_dir <dir> <flags> <depth>: decide_walk with the simulated working directory moved to a wrapper's chdir directory, for the
# wrapped command only (the directory and the unresolved-cd state are put back). A directory that cannot be resolved (a variable, an
# empty word) is an unresolved cd, as for a literal `cd "$X"`.
walk_in_dir() {
  local d="$1" dflag="$2" saved_cwd saved_unres="$UNRES" ok=0
  cwd_ready; saved_cwd="$SIMCWD"
  if [[ -n "$d" ]] && expand_word "$d" "$dflag"; then
    d="$EW"; [[ "$d" == /* ]] || d="$SIMCWD/$d"
    if resolve_phys "$d" 1 && [[ -n "$RP" ]]; then SIMCWD="$RP"; ok=1; fi
  fi
  (( ok )) || UNRES=1
  decide_walk "$3"
  SIMCWD="$saved_cwd"; UNRES="$saved_unres"
}

# decide_walk <depth>: the rule table over DA_T/DA_F (the words of one simple command), retried on the
# command a wrapper hides and on the words after the first `--`. It hands the words it recurses on to itself
# through DA_T/DA_F, so it CLOBBERS them: callers use decide_argv, which puts them back.
decide_walk() {
  local depth="$1" n i k name wcd wcdf wset
  if (( depth > 8 )); then note 1 wrapper-depth; return 0; fi
  if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking a command"; return 0; fi
  local -a t=("${DA_T[@]}") f=("${DA_F[@]}")
  n=${#t[@]}; i=0
  while (( i < n )) && is_assign "${t[$i]}"; do i=$((i + 1)); done
  if (( i < n )); then
    name="${t[$i]##*/}"
    # command names are compared in lower case: a case-insensitive filesystem runs RM as rm
    case "$name" in *[A-Z]*) fold_name "$name"; name="$FN" ;; esac
    AV=("${t[@]:$i}"); AF=("${f[@]:$i}")
    case "$name" in
      rm) rule_rm ;;
      terraform|tofu) rule_tf ;;
      git) rule_git ;;
      sudo|doas|env|command|nohup|time|timeout|nice|-p)  # `-p`: see wrap_skip
        WCD_SET=0; WCD=""
        wrap_skip "$name" "$i"
        wcd="$WCD"; wcdf="$WCDF"; wset="$WCD_SET"
        if (( WJ >= 0 && WJ < n )); then
          DA_T=("${t[@]:$WJ}"); DA_F=("${f[@]:$WJ}")
          if (( wset )); then walk_in_dir "$wcd" "$wcdf" $((depth + 1)); else decide_walk $((depth + 1)); fi
        fi ;;
    esac
  fi
  for ((k = 0; k + 1 < n; k++)); do
    if [[ "${t[$k]}" == -- ]]; then
      DA_T=("${t[@]:$((k + 1))}"); DA_F=("${f[@]:$((k + 1))}")
      decide_walk $((depth + 1))
      break  # the recursion retries every later `--` itself; looping on would repeat that work exponentially
    fi
  done
}

# decide_argv: judge the words in DA_T/DA_F and leave both exactly as found: the main loop reads them again for
# the quoted text and for the cd effect. A record always has at least one word (the lexer's argc is >= 1), so the
# copies below are never empty-array expansions.
decide_argv() {
  local -a keep_t=("${DA_T[@]}") keep_f=("${DA_F[@]}")
  decide_walk "$1"
  DA_T=("${keep_t[@]}"); DA_F=("${keep_f[@]}")
}

# cd_index: CI = the index in DA_T of a cd/pushd/popd that IS the command (after assignments and a leading
# `command` or `builtin`, which do not change what cd does), else -1.
cd_index() {
  local n=${#DA_T[@]}
  CI=0
  while (( CI < n )) && is_assign "${DA_T[$CI]}"; do CI=$((CI + 1)); done
  while (( CI < n )); do
    case "${DA_T[$CI]}" in
      command|builtin) CI=$((CI + 1)); [[ "${DA_T[$CI]:-}" == -p || "${DA_T[$CI]:-}" == -- ]] && CI=$((CI + 1)) ;;
      *) break ;;
    esac
  done
  if (( CI < n )); then
    case "${DA_T[$CI]}" in cd|pushd|popd) return 0 ;; esac
  fi
  CI=-1
  return 1
}

# apply_cd: a literal cd/pushd moves the simulated working directory; an unresolvable one sets UNRES.
apply_cd() { # reads DA_T/DA_F of the current record; CI (from cd_index) is the index of its cd/pushd/popd word
  local -a t=("${DA_T[@]}") f=("${DA_F[@]}")
  local n=${#t[@]} i=$CI j target="" tf="-" have=0
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
  if (( SECONDS >= DEADLINE_S )); then BOUND_WHY="the ${DEADLINE_S} s time limit was reached while checking the commands"; break; fi
  # one record's words by index: an array slice is O(offset) in bash and made the loop quadratic
  RO="${REC_OFF[$r]}"; RC="${REC_N[$r]}"; DA_T=(); DA_F=()
  for ((RQ = 0; RQ < RC; RQ++)); do DA_T[RQ]="${W_TXT[RO + RQ]}"; DA_F[RQ]="${W_FLG[RO + RQ]}"; done
  REC_RANK=0; REC_RULE=""
  decide_argv 0
  if (( REC_RANK > BEST_RANK )); then
    BEST_RANK="$REC_RANK"; BEST_RULE="$REC_RULE"
    REC_TXT=""; RW_NEXT=0
    for ((RQ = 0; RQ < ${#DA_T[@]} && ${#REC_TXT} <= 200; RQ++)); do redact_word "${DA_T[RQ]}"; REC_TXT="${REC_TXT:+$REC_TXT }$RW"; done
    BEST_QUOTE="${REC_TXT:0:200}"
    (( ${#REC_TXT} > 200 )) && BEST_QUOTE="${BEST_QUOTE}..."
    (( BEST_RANK == 2 )) && break
  fi
  [[ -n "$BOUND_WHY" ]] && break
  # the cd effect of this record, for the commands after it
  if cd_index; then apply_cd; fi
done

# ---- 6. the decision -------------------------------------------------------------------------------
# a bound trip (record or word cap, or the deadline) is an ask unless a deny was already found
[[ -z "$BOUND_WHY" ]] && BOUND_WHY="$BOUND_SOFT"
# A bound with nothing matched is a bare `bound` ask. A bound AFTER an ask-class match keeps that rule's reason (the command WAS
# recognised) with the bound sentence appended: the person sees what matched and that the rest was not checked.
BOUND_NOTE=""
if [[ -n "$BOUND_WHY" && "$BEST_RANK" -lt 2 ]]; then
  (( BEST_RANK == 0 )) && ask_bound "$BOUND_WHY"
  BOUND_NOTE=" The guard also stopped checking the rest of this command because it is too large to check in full (${BOUND_WHY}), so other parts of it were not checked."
fi
(( BEST_RANK == 0 )) && exit 0
lead_for "$BEST_RULE"
# env -S and too many wrappers hide the command: the repair is to write it out; every other match is a stop
TAIL="$REASON_TAIL"
case "$BEST_RULE" in unparsed-wrapper|wrapper-depth) TAIL="$WRAPPER_TAIL" ;; esac
REASON="${BEST_RULE}: ${LEAD} Matched command: [${BEST_QUOTE}].${BOUND_NOTE}${TAIL}"
if (( BEST_RANK == 2 )); then emit deny "$REASON"; else emit ask "$REASON"; fi
exit 0
