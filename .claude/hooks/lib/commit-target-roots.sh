# shellcheck shell=bash
# shellcheck disable=SC2034  # the CTR_* results are read by the sourcing hook
# commit-target-roots.sh — which repositories does a `git commit` command target? (#10609)
#
# THE DEFECT THIS EXISTS FOR. git-commit-secret-scan.sh resolved its repository from the
# hook PROCESS cwd. When the session is anchored at a core.bare=true root that has no
# .gitleaks.toml, `cd <worktree> && git commit` was never scanned (the incident ledger
# row "bypass .gitleaks.toml absent", 2026-10-19). The commit's real target is named in
# the command text, so this library reads it from there — WITHOUT running any of it.
#
# HOW. The command text is untrusted. It is piped (printf '%s', never interpolated into
# program text) to the repository's hardened shell lexer, plugins/soleur/hooks/lib/
# shell-argv.pl, which answers "which simple commands would bash execute, and what is each
# one's argv?" with quoting, substitutions, heredocs and `bash -c` already modelled. A thin
# walker below reads those argv records. No eval, no xargs, no command substitution of the
# text, no `sed` over it.
#
# THE WALKER IS CLOSED-WORLD ON WHAT IT RECOGNISES AND OPEN-WORLD ON WHAT IT IGNORES, so it
# is built to over-recognise: a record whose first word is not one it knows is searched for
# a later `git` / `cd` / `env` / shell-runner / `eval` word (so `timeout 5 git -C W commit`,
# `sudo git ...`, `xargs git ...`, `rtk git ...` and any other launcher are seen through
# without a wrapper table that must be kept complete), and an unrecognised git option
# followed by a `commit` word counts as a commit. Scanning one repository too many only adds
# a deny; scanning one too few is the incident.
#
# WHAT IT COLLECTS (CTR_TARGETS): every literal path named by `cd` / `pushd`, `git -C`,
# `env -C|--chdir` and a launcher's `-D|--chdir`. It is a UNION, not a simulation of the
# shell's cwd. WHAT IT REFUSES (CTR_BAD): any target that cannot be read statically — an
# expansion ($VAR, $(..), backticks), `~`, `cd -`, a glob, more than _CTR_MAX_TARGETS
# targets, GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / GIT_COMMON_DIR (inline, after `env`, or
# via export/declare), `git --git-dir|--work-tree` and `-c core.worktree=` (which move the
# repository without naming it), a missing target in a command that also creates paths, and
# a shell runner or eval whose script operand carries an expansion (the commit may be hiding
# in the variable). The caller DENIES on a bad target; it never skips. In a STRAIGHT-LINE command
# list a refusal that comes AFTER the last commit record cannot change that commit's target and
# is dropped; a command with a loop or a function keeps every refusal (its text order is not its
# run order).
#
# OUTPUT VARIABLES (set by ctr_collect):
#   CTR_TARGETS      literal target paths, in order of appearance (no duplicates)
#   CTR_BAD          one reason string per target that could not be determined
#   CTR_COMMIT_SEEN  1 when a `git ... commit` record exists, or when a runner operand with
#                    an expansion may hide one; else 0
#   CTR_LEX_STATE    ok | unavailable (perl / lexer missing, lexer error, truncated stream)
#   CTR_LEX_WHY      the cause when unavailable
#   CTR_LEX_KIND     tooling | parse | bound — which repair applies when unavailable
#   CTR_LEXER        path of the lexer (resolved from this file's own location)
# ctr_resolve_roots then maps CTR_TARGETS to git toplevels in CTR_ROOTS.
#
# PORTABILITY: bash 3.2 (stock macOS /bin/bash): no mapfile, no declare -n, no associative
# arrays; an empty array is read as ${a[@]+"${a[@]}"} so `set -u` does not trip on it; $HOME
# is read as ${HOME-}. Functions never exit the caller and never rely on errexit.

# Resolved from THIS file's own location (BASH_SOURCE), never from the working directory:
# the hook is invoked by its full path, and a different cwd must not substitute the lexer.
CTR_LEXER="${BASH_SOURCE[0]%/*}/../../../plugins/soleur/hooks/lib/shell-argv.pl"

_CTR_MAX_TARGETS=32

CTR_TARGETS=()
CTR_BAD=()
CTR_ROOTS=()
CTR_COMMIT_SEEN=0
CTR_LEX_STATE=ok
CTR_LEX_WHY=""
CTR_LEX_KIND=""
_CTR_W=()
_CTR_F=()
_CTR_BAD_MARK=0
_CTR_CREATOR=0
_CTR_CAPPED=0
_CTR_DEPTH=0
_CTR_TGT_AT_COMMIT=0
_CTR_TEXT=""
_CTR_MAX_DEPTH=32
_CTR_STEPS=0
_CTR_MAX_STEPS=500
_CTR_LAUNCHED=0

# ctr_wants_lex <command> — cheap pre-filter for the STRICT-match path (`git commit` with
# nothing between the words): true when the text contains a token that can change which
# directory a commit lands in, so a plain `git commit -m x` never spawns perl. Over-matching
# is safe (it only runs the lexer); UNDER-matching is the incident, so the suite pins that
# every form the walker handles matches. A loose-only match (`git -C x commit`, a wrapper,
# quoting) does not consult this: it always runs the lexer.
ctr_wants_lex() {
  local c="$1" re='(^|[^[:alnum:]_.-])(cd|pushd|env|e[v]al|bash|sh|zsh|dash|ksh|sudo|doas|chroot|nsenter|export|declare|typeset)([^[:alnum:]_.-]|$)'
  case "$c" in
    *GIT_DIR*|*GIT_WORK_TREE*|*GIT_INDEX_FILE*|*GIT_COMMON_DIR*|*--git-dir*|*--work-tree*|*core.worktree*|*--chdir*|*--wd*|*--working-directory*) return 0 ;;
  esac
  [[ "$c" =~ $re ]] && return 0
  [[ "$c" =~ git[[:space:]]+- ]] && return 0
  return 1
}

_ctr_unavail() { CTR_LEX_STATE=unavailable; CTR_LEX_KIND="$1"; CTR_LEX_WHY="$2"; }
_ctr_bad() { CTR_BAD+=("$1"); }
_ctr_mark_commit() { CTR_COMMIT_SEEN=1; _CTR_BAD_MARK=${#CTR_BAD[@]}; _CTR_TGT_AT_COMMIT=${#CTR_TARGETS[@]}; }

# _ctr_add_path <text> <flags> — record a path operand as a literal target, or as bad.
_ctr_add_path() {
  local w="$1" fl="$2" t
  case "$fl" in
    *x*) _ctr_bad "the path '$w' contains an expansion"; return 0 ;;
  esac
  case "$w" in
    -) _ctr_bad "'cd -' goes to a directory the walker cannot see"; return 0 ;;
    '~'*) _ctr_bad "the path '$w' uses ~ (not expanded here)"; return 0 ;;
    *'*'*|*'?'*|*'['*|*'{'*) _ctr_bad "the path '$w' contains a glob or brace pattern"; return 0 ;;
  esac
  [ -n "$w" ] || return 0
  for t in ${CTR_TARGETS[@]+"${CTR_TARGETS[@]}"}; do [ "$t" = "$w" ] && return 0; done
  if [ "${#CTR_TARGETS[@]}" -ge "$_CTR_MAX_TARGETS" ]; then
    # One refusal for the whole overflow, not one per extra target.
    if [ "$_CTR_CAPPED" -eq 0 ]; then _CTR_CAPPED=1; _ctr_bad "more than $_CTR_MAX_TARGETS distinct directory targets"; fi
    return 0
  fi
  CTR_TARGETS+=("$w")
}
_ctr_add_idx() { _ctr_add_path "${_CTR_W[$1]}" "${_CTR_F[$1]}"; }

# _ctr_is_gitenv <word> — a repository-location variable assignment.
_ctr_is_gitenv() {
  case "$1" in
    GIT_DIR=*|GIT_WORK_TREE=*|GIT_INDEX_FILE=*|GIT_COMMON_DIR=*) return 0 ;;
  esac
  return 1
}

# _ctr_cfg_moves_worktree <key[=value]> — a git config key that relocates the work tree (git
# config keys are case-insensitive).
_ctr_cfg_moves_worktree() {
  local k="${1%%=*}"
  k=$(printf '%s' "$k" | tr '[:upper:]' '[:lower:]')
  case "$k" in core.worktree|core.bare) return 0 ;; esac
  return 1
}

# _ctr_env_walk <idx-of-env-word> — parse GNU env's options (bundled short options, abbreviated
# long options, attached or separate operands), collect -C|--chdir as targets, then walk the
# command env runs.
_ctr_env_walk() {
  local k=$(($1 + 1)) n="${#_CTR_W[@]}" w s ch rest
  while [ "$k" -lt "$n" ]; do
    w="${_CTR_W[$k]}"
    case "$w" in
      --) k=$((k + 1)); break ;;
      --chdir=*|--chd=*|--chdi=*|--ch=*|--cd=*|--c=*) _ctr_add_path "${w#*=}" "${_CTR_F[$k]}"; k=$((k + 1)) ;;
      --chdir|--chd|--chdi|--ch|--cd|--c)
        if [ $((k + 1)) -lt "$n" ]; then _ctr_add_idx $((k + 1)); else _ctr_bad "env $w has no operand"; fi
        k=$((k + 2)) ;;
      --s|--sp|--spl|--spli|--split*) _ctr_bad "env --split-string runs a string the walker cannot read"; _ctr_mark_commit; k=$((k + 1)) ;;
      --unset|--argv0) k=$((k + 2)) ;;
      --*) k=$((k + 1)) ;;
      -?*)
        s="${w#-}"; k=$((k + 1))
        while [ -n "$s" ]; do
          ch="${s:0:1}"; rest="${s:1}"
          case "$ch" in
            C)
              if [ -n "$rest" ]; then _ctr_add_path "$rest" "${_CTR_F[$((k - 1))]}"
              elif [ "$k" -lt "$n" ]; then _ctr_add_idx "$k"; k=$((k + 1))
              else _ctr_bad "env -C has no operand"; fi
              break ;;
            S) _ctr_bad "env -S runs a string the walker cannot read"; _ctr_mark_commit; break ;;
            u|a|P) [ -z "$rest" ] && k=$((k + 1)); break ;;
          esac
          s="$rest"
        done ;;
      *=*)
        if _ctr_is_gitenv "$w"; then _ctr_bad "the command sets ${w%%=*}= (the repository is not named by a path)"; fi
        k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  [ "$k" -lt "$n" ] && _ctr_walk_from "$k"
  return 0
}

# _ctr_git_walk <idx-of-git-word> — git's global options, then the subcommand.
_ctr_git_walk() {
  local j=$(($1 + 1)) n="${#_CTR_W[@]}" w unknown=0 sub m q
  while [ "$j" -lt "$n" ]; do
    w="${_CTR_W[$j]}"
    case "$w" in
      -C)
        if [ $((j + 1)) -lt "$n" ]; then _ctr_add_idx $((j + 1)); else _ctr_bad "git -C has no operand"; fi
        j=$((j + 2)) ;;
      -c|--config-env)
        if [ $((j + 1)) -lt "$n" ] && _ctr_cfg_moves_worktree "${_CTR_W[$((j + 1))]}"; then
          _ctr_bad "git $w ${_CTR_W[$((j + 1))]%%=*} moves the work tree without a path the walker may trust"
        fi
        j=$((j + 2)) ;;
      --config-env=*)
        if _ctr_cfg_moves_worktree "${w#--config-env=}"; then
          _ctr_bad "git --config-env ${w#--config-env=} moves the work tree without a path the walker may trust"
        fi
        j=$((j + 1)) ;;
      --git-dir|--work-tree) _ctr_bad "git $w redirects the repository without a path the walker may trust"; j=$((j + 2)) ;;
      --git-dir=*|--work-tree=*) _ctr_bad "git ${w%%=*} redirects the repository without a path the walker may trust"; j=$((j + 1)) ;;
      --namespace|--attr-source|--super-prefix) j=$((j + 2)) ;;
      --no-pager|--paginate|-p|-P|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-advice|--no-lazy-fetch|--exec-path|--exec-path=*|-v|--version|-h|--help)
        j=$((j + 1)) ;;
      -*) unknown=1; j=$((j + 1)) ;;
      *) break ;;
    esac
  done
  # The first non-option word is the subcommand; a -C AFTER it (commit -C HEAD) is the
  # subcommand's own option, never a global one, because this loop stopped at it.
  if [ "$j" -lt "$n" ]; then
    sub="${_CTR_W[$j]}"
    case "$sub" in
      commit) _ctr_mark_commit ;;
      worktree|clone|init|submodule) _CTR_CREATOR=1 ;;
      *)
        # An option the walker does not know may have swallowed the real subcommand as its
        # operand; if a `commit` word follows, treat it as a commit rather than guess.
        if [ "$unknown" -eq 1 ]; then
          m=$((j + 1))
          while [ "$m" -lt "$n" ]; do
            if [ "${_CTR_W[$m]}" = commit ]; then
              # The option's operand hid the subcommand, so option words after it were never
              # read either: collect the -C operands that precede the commit word.
              q=$((j + 1))
              while [ "$q" -lt "$m" ]; do
                if [ "${_CTR_W[$q]}" = -C ] && [ $((q + 1)) -lt "$m" ]; then _ctr_add_idx $((q + 1)); fi
                q=$((q + 1))
              done
              _ctr_mark_commit; break
            fi
            m=$((m + 1))
          done
        fi ;;
    esac
  fi
}

# _ctr_runner_walk <idx-of-shell-word> — `bash -c SCRIPT`: a literal script was already
# re-lexed by the lexer; a script held in an expansion hides a possible commit; a shell given
# no script operand reads one from stdin (heredoc, here-string, pipe or redirect), which the
# lexer treats as data. The stdin refusal applies only when the shell is the command word
# itself: a `bash` that is merely an ARGUMENT of an unmodelled command (`which bash | head`,
# `echo run bash`) is not a shell being run.
_ctr_runner_walk() {
  local j=$(($1 + 1)) n="${#_CTR_W[@]}" w mode=stdin sflag=0
  while [ "$j" -lt "$n" ]; do
    w="${_CTR_W[$j]}"
    case "$w" in
      --) if [ "$sflag" -eq 1 ]; then mode=stdin; else mode=operand; fi; break ;;
      --version|--help|-h) mode=operand; break ;;
      -o|+o|-O|+O|--rcfile|--init-file) j=$((j + 2)) ;;
      --*|+?*) j=$((j + 1)) ;;
      -[!-]*)
        case "$w" in
          *c*)
            mode=c
            if [ $((j + 1)) -lt "$n" ]; then
              case "${_CTR_F[$((j + 1))]}" in
                *x*) _ctr_bad "a shell runs a script held in an expansion"; _ctr_mark_commit ;;
              esac
            fi
            break ;;
          *s*) sflag=1 ;;
        esac
        j=$((j + 1)) ;;
      '<('*) mode=stdin; break ;;  # bash < <(cmd): the lexer leaves the substitution as a word
      *) if [ "$sflag" -eq 1 ]; then mode=stdin; else mode=operand; fi; break ;;
    esac
  done
  if [ "$mode" = stdin ] && [ "$_CTR_LAUNCHED" -eq 0 ]; then
    case "$_CTR_TEXT" in
      *'<'*|*'|'*) _ctr_bad "a shell reads its script from stdin (heredoc, here-string, redirect or pipe)"; _ctr_mark_commit ;;
    esac
  fi
}

# _ctr_walk_from <idx> — read one argv record from word <idx> and update the CTR_* state.
# Nesting is bounded (a chain of `env env env ...` recurses once per word, and a deep bash
# recursion crashes the hook, which lets the tool call proceed): past the bound the command is
# refused as unreadable.
_ctr_walk_from() {
  _CTR_DEPTH=$((_CTR_DEPTH + 1)); _CTR_STEPS=$((_CTR_STEPS + 1))
  if [ "$_CTR_DEPTH" -gt "$_CTR_MAX_DEPTH" ]; then
    if [ "$_CTR_DEPTH" -eq $((_CTR_MAX_DEPTH + 1)) ]; then
      _ctr_bad "the command nests launchers deeper than $_CTR_MAX_DEPTH levels"; _ctr_mark_commit
    fi
  elif [ "$_CTR_STEPS" -gt "$_CTR_MAX_STEPS" ]; then
    # Depth alone does not bound the WORK: a launcher word between env words branches at
    # every level. A hook that outlives its timeout lets the tool call proceed.
    if [ "$_CTR_STEPS" -eq $((_CTR_MAX_STEPS + 1)) ]; then
      _ctr_bad "one command record needs more than $_CTR_MAX_STEPS walker steps (nested launchers)"; _ctr_mark_commit
    fi
  else
    _ctr_walk_body "$1"
  fi
  _CTR_DEPTH=$((_CTR_DEPTH - 1))
}

_ctr_walk_body() {
  local i="$1" n="${#_CTR_W[@]}" j w b k hits h
  # Leading NAME=value assignments.
  while [ "$i" -lt "$n" ]; do
    w="${_CTR_W[$i]}"
    case "$w" in
      [A-Za-z_]*=*)
        k="${w%%=*}"
        case "$k" in *[!A-Za-z0-9_]*) break ;; esac
        if _ctr_is_gitenv "$w"; then _ctr_bad "the command sets $k= (the repository is not named by a path)"; fi
        i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0

  # A command word that is itself an expansion ("$GIT" -C x commit) cannot be read.
  case "${_CTR_F[$i]}" in
    *x*)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        if [ "${_CTR_W[$j]}" = commit ]; then _ctr_bad "the command word is an expansion"; _ctr_mark_commit; break; fi
        j=$((j + 1))
      done
      return 0 ;;
  esac

  b="${_CTR_W[$i]##*/}"
  case "$b" in
    cd|pushd)
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do
        case "${_CTR_W[$i]}" in
          --) i=$((i + 1)); break ;;
          -n|-[LPe@]|-[LPe@][LPe@]*) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      if [ "$i" -ge "$n" ]; then
        if [ "$b" = cd ]; then
          if [ -n "${HOME-}" ]; then _ctr_add_path "$HOME" "-"; else _ctr_bad "cd with no operand and HOME is unset"; fi
        else
          _ctr_bad "pushd with no operand swaps the directory stack"
        fi
      else
        case "$b:${_CTR_W[$i]}" in
          pushd:[+-][0-9]*) _ctr_bad "pushd ${_CTR_W[$i]} rotates the directory stack" ;;
          *) _ctr_add_idx "$i" ;;
        esac
      fi ;;
    env) _ctr_env_walk "$i" ;;
    git) _ctr_git_walk "$i" ;;
    bash|sh|zsh|dash|ksh) _ctr_runner_walk "$i" ;;
    # Spelled e[v]al: this arm only MATCHES the word in argv, nothing here ever runs it.
    e[v]al)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case "${_CTR_F[$j]}" in
          *x*) _ctr_bad "the interpreter-builtin runs a string held in an expansion"; _ctr_mark_commit; break ;;
        esac
        j=$((j + 1))
      done ;;
    export|declare|typeset|readonly|local)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        if _ctr_is_gitenv "${_CTR_W[$j]}"; then _ctr_bad "$b ${_CTR_W[$j]%%=*}= moves the repository without a path the walker may trust"; fi
        j=$((j + 1))
      done ;;
    mkdir|mv|cp|ln|install|rsync|tar|unzip) _CTR_CREATOR=1 ;;
    *)
      # Not a command the walker models: it may be a launcher (timeout, sudo, nice, xargs,
      # rtk, flock, setsid, exec, command, builtin, ...). Look through it for EVERY later
      # command word (the first may be an operand: `sudo -u git git ...`), and honour a
      # launcher's own chdir option (sudo -D, --chdir, --working-directory) on the way.
      case "$b" in
        chroot|nsenter|unshare)
          j=$((i + 1))
          while [ "$j" -lt "$n" ]; do
            if [ "${_CTR_W[$j]##*/}" = git ]; then
              _ctr_bad "$b changes the root or namespace the commit runs in"; _ctr_mark_commit; break
            fi
            j=$((j + 1))
          done ;;
        su|flock|ssh|watch|script|runuser|parallel|fish|ash)
          # These take the command as ONE string operand.
          j=$((i + 1))
          while [ "$j" -lt "$n" ]; do
            case "${_CTR_W[$j]}" in
              *git*[[:space:]]*commit*) _ctr_bad "$b runs a command string the walker cannot read"; _ctr_mark_commit; break ;;
            esac
            j=$((j + 1))
          done ;;
      esac
      hits=(); j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case "${_CTR_W[$j]##*/}" in
          git|cd|pushd|env|bash|sh|zsh|dash|ksh|e[v]al|export|declare|typeset|readonly|local)
            if [ "${#hits[@]}" -ge 8 ]; then
              _ctr_bad "more than 8 command words behind an unmodelled launcher"; _ctr_mark_commit; break
            fi
            hits+=("$j") ;;
        esac
        j=$((j + 1))
      done
      if [ "${#hits[@]}" -gt 0 ]; then
        k="${hits[$((${#hits[@]} - 1))]}"
        j=$((i + 1))
        while [ "$j" -lt "$k" ]; do
          w="${_CTR_W[$j]}"
          case "$w" in
            -D|--chdir|--wd|--working-directory) if [ $((j + 1)) -lt "$k" ]; then _ctr_add_idx $((j + 1)); fi ;;
            --chdir=*|--wd=*|--working-directory=*) _ctr_add_path "${w#*=}" "${_CTR_F[$j]}" ;;
            -D/*) _ctr_add_path "${w#-D}" "${_CTR_F[$j]}" ;;
          esac
          j=$((j + 1))
        done
        for h in "${hits[@]}"; do
          _CTR_LAUNCHED=$((_CTR_LAUNCHED + 1)); _ctr_walk_from "$h"; _CTR_LAUNCHED=$((_CTR_LAUNCHED - 1))
        done
      fi ;;
  esac
  return 0
}

# _ctr_has_loop <command> — the text contains a loop or a function definition, where the text
# order of the commands is not their run order (a commit before a `cd \"$d\"` in a loop body
# runs again after it). Over-matching only keeps a refusal.
_ctr_has_loop() {
  case "$1" in
    *'for '*|*'while '*|*'until '*|*'select '*|*'()'*|*'function '*) return 0 ;;
  esac
  return 1
}

# ctr_collect <command> — lex and walk the command. Always returns 0; read CTR_LEX_STATE.
# The lexer's stdout is NUL-framed (see the OUTPUT CONTRACT in shell-argv.pl): parsed BY
# COUNT, and the closing OK field is the ONLY success signal — a `$(...)` capture drops NUL
# bytes, so the lexer's exit status is not read from here; the OK / E fields carry the
# verdict (a stream with neither is "could not parse").
ctr_collect() {
  local cmd="$1" fld i n argc k tag
  local f=()
  CTR_TARGETS=(); CTR_BAD=(); CTR_COMMIT_SEEN=0; CTR_LEX_STATE=ok; CTR_LEX_WHY=""; CTR_LEX_KIND=""
  _CTR_BAD_MARK=0; _CTR_CREATOR=0; _CTR_CAPPED=0; _CTR_DEPTH=0; _CTR_TGT_AT_COMMIT=0; _CTR_TEXT="$cmd"
  if ! command -v perl >/dev/null 2>&1; then _ctr_unavail tooling "perl is not installed, and the command lexer needs it"; return 0; fi
  if [ ! -r "$CTR_LEXER" ]; then _ctr_unavail tooling "the command lexer is missing at $CTR_LEXER"; return 0; fi
  # The `|| true` is inside the process substitution so a lexer exit status (2 = unparseable,
  # 3 = a bound tripped) is absorbed there; failure is read from the stream instead.
  while IFS= read -r -d '' fld; do f+=("$fld"); done < <(printf '%s' "$cmd" | perl "$CTR_LEXER" 2>/dev/null || true)
  n=${#f[@]}; i=0
  if [ "$n" -eq 0 ]; then _ctr_unavail tooling "the command lexer produced no output"; return 0; fi
  while :; do
    if [ "$i" -ge "$n" ]; then _ctr_unavail parse "the command lexer output was truncated"; return 0; fi
    tag="${f[$i]}"
    case "$tag" in
      OK)
        if [ $((i + 1)) -ne "$n" ]; then _ctr_unavail parse "the command lexer wrote data after its OK field"; return 0; fi
        # A refusal after the last commit record cannot change that commit's target.
        if [ "$CTR_COMMIT_SEEN" -eq 1 ] && [ "$_CTR_BAD_MARK" -lt "${#CTR_BAD[@]}" ] && ! _ctr_has_loop "$cmd"; then
          if [ "$_CTR_BAD_MARK" -eq 0 ]; then CTR_BAD=(); else CTR_BAD=("${CTR_BAD[@]:0:$_CTR_BAD_MARK}"); fi
        fi
        return 0 ;;
      C)
        if [ $((i + 2)) -ge "$n" ]; then _ctr_unavail parse "the command lexer output was truncated"; return 0; fi
        argc="${f[$((i + 2))]}"
        case "$argc" in ''|0*|*[!0-9]*) _ctr_unavail parse "the command lexer wrote a bad word count"; return 0 ;; esac
        if [ "${#argc}" -gt 6 ] || [ $((i + 3 + 2 * argc)) -gt "$n" ]; then
          _ctr_unavail parse "the command lexer output was truncated"; return 0
        fi
        _CTR_W=(); _CTR_F=()
        k=0
        while [ "$k" -lt "$argc" ]; do
          _CTR_F+=("${f[$((i + 3 + 2 * k))]}")
          _CTR_W+=("${f[$((i + 4 + 2 * k))]}")
          k=$((k + 1))
        done
        _CTR_STEPS=0; _CTR_LAUNCHED=0
        _ctr_walk_from 0
        i=$((i + 3 + 2 * argc)) ;;
      E)
        # The lexer's own failure frame: E <cause>. depth / budget / alarm are bounds.
        _ctr_unavail bound "the command is too large or too deeply nested to analyse (lexer cause '${f[$((i + 1))]:-unknown}')"
        case "${f[$((i + 1))]:-}" in
          exit2) CTR_LEX_KIND=parse; CTR_LEX_WHY="the command is not parseable shell (unbalanced quote, unterminated substitution or heredoc)" ;;
          crash) CTR_LEX_KIND=tooling; CTR_LEX_WHY="the command lexer crashed" ;;
        esac
        return 0 ;;
      *)
        _ctr_unavail parse "the command could not be parsed (lexer field '$tag')"; return 0 ;;
    esac
  done
}

# ctr_resolve_roots — map CTR_TARGETS to git toplevels in CTR_ROOTS (unique). An absolute
# target stands alone; a relative one is joined against the hook's $PWD, the payload cwd
# (HOOK_CWD) and the last three directories already resolved, because `cd a && cd b`
# composes. Each distinct directory is probed once. A target that exists but is not inside a
# work tree is dropped (a commit there cannot stage anything). A target that does not exist
# is dropped too — unless the same command creates paths (mkdir, git worktree add, clone,
# ...), in which case it is refused, because it may exist by the time the commit runs.
# GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE are stripped from the probes, since an inherited
# GIT_DIR outranks `git -C` and would send the probe to the wrong repository.
ctr_resolve_roots() {
  local t base cand top r dup d found s k ti=-1
  local cands=() seen=() bases=()
  CTR_ROOTS=()
  for t in ${CTR_TARGETS[@]+"${CTR_TARGETS[@]}"}; do
    ti=$((ti + 1))
    cands=()
    case "$t" in
      /*) cands+=("$t") ;;
      *)
        bases=("$PWD" "${HOOK_CWD-}")
        s=${#seen[@]}; k=0; [ "$s" -gt 3 ] && k=$((s - 3))
        while [ "$k" -lt "$s" ]; do bases+=("${seen[$k]}"); k=$((k + 1)); done
        for base in "${bases[@]}"; do
          if [ -n "$base" ]; then cands+=("$base/$t"); fi
        done ;;
    esac
    found=0
    for cand in ${cands[@]+"${cands[@]}"}; do
      [ -d "$cand" ] || continue
      found=1
      dup=0
      for d in ${seen[@]+"${seen[@]}"}; do if [ "$d" = "$cand" ]; then dup=1; fi; done
      [ "$dup" -eq 1 ] && continue
      seen+=("$cand")
      top=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR git -C "$cand" rev-parse --show-toplevel 2>/dev/null) || continue
      [ -n "$top" ] || continue
      dup=0
      for r in ${CTR_ROOTS[@]+"${CTR_ROOTS[@]}"}; do if [ "$r" = "$top" ]; then dup=1; fi; done
      if [ "$dup" -eq 0 ]; then CTR_ROOTS+=("$top"); fi
    done
    # A target named after the last commit record cannot be that commit's target.
    if [ "$found" -eq 0 ] && [ "$_CTR_CREATOR" -eq 1 ] && { [ "$CTR_COMMIT_SEEN" -eq 0 ] || [ "$ti" -lt "$_CTR_TGT_AT_COMMIT" ] || _ctr_has_loop "$_CTR_TEXT"; }; then
      _ctr_bad "the target '$t' does not exist yet and this command creates paths"
    fi
  done
  return 0
}
