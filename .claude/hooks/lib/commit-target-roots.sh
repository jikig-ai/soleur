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
# WHAT IT COLLECTS (CTR_TARGETS): every literal path named by `cd` / `pushd`, `git -C`, and
# `env -C|--chdir`. It is a UNION, not a simulation of the shell's cwd: scanning one repo too
# many only adds a deny, scanning one too few is the incident. WHAT IT REFUSES (CTR_BAD):
# any target that cannot be read statically — an expansion ($VAR, $(..), backticks), `~`,
# `cd -`, a glob, GIT_DIR / GIT_WORK_TREE / --git-dir / --work-tree (which move the
# repository without naming it), and a shell runner or eval whose script operand carries an
# expansion (the commit may be hiding in the variable). The caller DENIES on a bad target;
# it never skips.
#
# OUTPUT VARIABLES (set by ctr_collect):
#   CTR_TARGETS      literal target paths, in order of appearance
#   CTR_BAD          one reason string per target that could not be determined
#   CTR_COMMIT_SEEN  1 when a `git ... commit` record exists, or when a runner operand with
#                    an expansion may hide one; else 0
#   CTR_LEX_STATE    ok | unavailable (perl / lexer missing, lexer error, truncated stream)
#   CTR_LEX_WHY      the cause when unavailable
# ctr_resolve_roots then maps CTR_TARGETS to git toplevels in CTR_ROOTS.
#
# PORTABILITY: bash 3.2 (stock macOS /bin/bash): no mapfile, no declare -n, no associative
# arrays; an empty array is read as ${a[@]+"${a[@]}"} so `set -u` does not trip on it; $HOME
# is read as ${HOME-}. Functions never exit the caller and never rely on errexit.

_ctr_here="${BASH_SOURCE[0]%/*}"
[ "$_ctr_here" = "${BASH_SOURCE[0]}" ] && _ctr_here=.
# Resolved from THIS file's own location, never from $PWD: a hostile or merely different
# working directory must not be able to substitute the lexer.
CTR_LEXER="$_ctr_here/../../../plugins/soleur/hooks/lib/shell-argv.pl"

CTR_TARGETS=()
CTR_BAD=()
CTR_ROOTS=()
CTR_COMMIT_SEEN=0
CTR_LEX_STATE=ok
CTR_LEX_WHY=""
_CTR_W=()
_CTR_F=()

# ctr_wants_lex <command> — cheap pre-filter: true when the text contains a token that can
# change which directory a commit lands in. Over-matching is safe (it only runs the lexer);
# UNDER-matching is the incident, so test/hook rows pin that every form the walker handles
# matches. A command that matches nothing here never spawns perl and takes the legacy path.
ctr_wants_lex() {
  local c="$1" re='(^|[^[:alnum:]_./-])(cd|pushd|env|e[v]al|bash|sh|zsh|dash|ksh)([^[:alnum:]_.-]|$)'
  case "$c" in
    *GIT_DIR*|*GIT_WORK_TREE*|*--git-dir*|*--work-tree*) return 0 ;;
  esac
  [[ "$c" =~ $re ]] && return 0
  [[ "$c" =~ git[[:space:]]+- ]] && return 0
  return 1
}

_ctr_unavail() { CTR_LEX_STATE=unavailable; CTR_LEX_WHY="$1"; }
_ctr_bad() { CTR_BAD+=("$1"); }

# _ctr_add_path <text> <flags> — record a path operand as a literal target, or as bad.
_ctr_add_path() {
  local w="$1" fl="$2"
  case "$fl" in
    *x*) _ctr_bad "the path '$w' contains an expansion"; return 0 ;;
  esac
  case "$w" in
    -) _ctr_bad "'cd -' goes to a directory the walker cannot see"; return 0 ;;
    '~'*) _ctr_bad "the path '$w' uses ~ (not expanded here)"; return 0 ;;
    *'*'*|*'?'*|*'['*|*'{'*) _ctr_bad "the path '$w' contains a glob or brace pattern"; return 0 ;;
  esac
  [ -n "$w" ] || return 0
  CTR_TARGETS+=("$w")
}
_ctr_add_idx() { _ctr_add_path "${_CTR_W[$1]}" "${_CTR_F[$1]}"; }

# _ctr_walk — read one argv record (_CTR_W words, _CTR_F flags) and update the CTR_* state.
_ctr_walk() {
  local n="${#_CTR_W[@]}" i=0 j w nm cmd
  # Leading NAME=value assignments and command wrappers. The lexer leaves both in argv.
  while [ "$i" -lt "$n" ]; do
    w="${_CTR_W[$i]}"
    case "$w" in
      GIT_DIR=*|GIT_WORK_TREE=*)
        _ctr_bad "the command sets ${w%%=*}= (the repository is not named by a path)"
        i=$((i + 1)); continue ;;
      [A-Za-z_]*=*)
        nm="${w%%=*}"
        case "$nm" in *[!A-Za-z0-9_]*) break ;; esac
        i=$((i + 1)); continue ;;
      env)
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          w="${_CTR_W[$i]}"
          case "$w" in
            -C|--chdir)
              if [ $((i + 1)) -lt "$n" ]; then _ctr_add_idx $((i + 1)); else _ctr_bad "env $w has no operand"; fi
              i=$((i + 2)) ;;
            --chdir=*) _ctr_add_path "${w#--chdir=}" "${_CTR_F[$i]}"; i=$((i + 1)) ;;
            -S*|--split-string*) _ctr_bad "env -S splits a string the walker cannot read"; i=$((i + 1)) ;;
            -u|--unset) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        continue ;;
      command|builtin|exec|nohup|time)
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case "${_CTR_W[$i]}" in -*) i=$((i + 1)) ;; *) break ;; esac
        done
        continue ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 0

  cmd="${_CTR_W[$i]}"; cmd="${cmd##*/}"
  case "$cmd" in
    cd|pushd)
      i=$((i + 1))
      while [ "$i" -lt "$n" ]; do
        case "${_CTR_W[$i]}" in
          --) i=$((i + 1)); break ;;
          -L|-P|-e|-@) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      if [ "$i" -ge "$n" ]; then
        if [ "$cmd" = cd ]; then
          if [ -n "${HOME-}" ]; then _ctr_add_path "$HOME" "-"; else _ctr_bad "cd with no operand and HOME is unset"; fi
        else
          _ctr_bad "pushd with no operand swaps the directory stack"
        fi
      else
        case "$cmd:${_CTR_W[$i]}" in
          pushd:[+-][0-9]*) _ctr_bad "pushd ${_CTR_W[$i]} rotates the directory stack" ;;
          *) _ctr_add_idx "$i" ;;
        esac
      fi ;;
    git)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"
        case "$w" in
          -C)
            if [ $((j + 1)) -lt "$n" ]; then _ctr_add_idx $((j + 1)); else _ctr_bad "git -C has no operand"; fi
            j=$((j + 2)) ;;
          -c) j=$((j + 2)) ;;
          --git-dir|--work-tree) _ctr_bad "git $w redirects the repository without a path the walker may trust"; j=$((j + 2)) ;;
          --git-dir=*|--work-tree=*) _ctr_bad "git ${w%%=*} redirects the repository without a path the walker may trust"; j=$((j + 1)) ;;
          -*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      # The first non-option word is the subcommand; a -C AFTER it (commit -C HEAD) is the
      # subcommand's own option, never a global one, because this loop stopped at it.
      if [ "$j" -lt "$n" ] && [ "${_CTR_W[$j]}" = commit ]; then CTR_COMMIT_SEEN=1; fi ;;
    bash|sh|zsh|dash|ksh)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"
        case "$w" in
          -c|-[A-Za-z]*c)
            # A script operand that is an expansion is a command the lexer cannot read.
            if [ $((j + 1)) -lt "$n" ]; then
              case "${_CTR_F[$((j + 1))]}" in
                *x*) _ctr_bad "$cmd -c runs a script held in an expansion"; CTR_COMMIT_SEEN=1 ;;
              esac
            fi
            break ;;
          -*) j=$((j + 1)) ;;
          *) break ;;
        esac
      done ;;
    # Spelled e[v]al: this arm only MATCHES the word in argv, nothing here ever runs it.
    e[v]al)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case "${_CTR_F[$j]}" in
          *x*) _ctr_bad "the interpreter-builtin runs a string held in an expansion"; CTR_COMMIT_SEEN=1; break ;;
        esac
        j=$((j + 1))
      done ;;
  esac
  return 0
}

# ctr_collect <command> — lex and walk the command. Always returns 0; read CTR_LEX_STATE.
# The lexer's stdout is NUL-framed (see the OUTPUT CONTRACT in shell-argv.pl): parsed BY
# COUNT, and the closing OK field is the ONLY success signal — bash command substitution
# cannot carry NUL, so the lexer's exit status is not recoverable here.
ctr_collect() {
  local cmd="$1" fld i n argc k tag
  local f=()
  CTR_TARGETS=(); CTR_BAD=(); CTR_COMMIT_SEEN=0; CTR_LEX_STATE=ok; CTR_LEX_WHY=""
  if ! command -v perl >/dev/null 2>&1; then _ctr_unavail "perl is not installed (the command lexer needs it)"; return 0; fi
  if [ ! -r "$CTR_LEXER" ]; then _ctr_unavail "the command lexer is missing at $CTR_LEXER"; return 0; fi
  # The `|| true` keeps a lexer exit status (2 = unparseable, 3 = a bound tripped) from
  # aborting a caller that runs under `set -e`; failure is read from the stream instead.
  while IFS= read -r -d '' fld; do f+=("$fld"); done < <(printf '%s' "$cmd" | perl "$CTR_LEXER" 2>/dev/null || true)
  n=${#f[@]}; i=0
  if [ "$n" -eq 0 ]; then _ctr_unavail "the command lexer produced no output"; return 0; fi
  while :; do
    if [ "$i" -ge "$n" ]; then _ctr_unavail "the command lexer output was truncated"; return 0; fi
    tag="${f[$i]}"
    case "$tag" in
      OK)
        if [ $((i + 1)) -ne "$n" ]; then _ctr_unavail "the command lexer wrote data after its OK field"; fi
        return 0 ;;
      C)
        if [ $((i + 2)) -ge "$n" ]; then _ctr_unavail "the command lexer output was truncated"; return 0; fi
        argc="${f[$((i + 2))]}"
        case "$argc" in ''|*[!0-9]*) _ctr_unavail "the command lexer wrote a bad word count"; return 0 ;; esac
        if [ "${#argc}" -gt 6 ] || [ "$argc" -lt 1 ] || [ $((i + 3 + 2 * argc)) -gt "$n" ]; then
          _ctr_unavail "the command lexer output was truncated"; return 0
        fi
        _CTR_W=(); _CTR_F=()
        k=0
        while [ "$k" -lt "$argc" ]; do
          _CTR_F+=("${f[$((i + 3 + 2 * k))]}")
          _CTR_W+=("${f[$((i + 4 + 2 * k))]}")
          k=$((k + 1))
        done
        _ctr_walk
        i=$((i + 3 + 2 * argc)) ;;
      *)
        _ctr_unavail "the command could not be parsed (lexer field '$tag')"; return 0 ;;
    esac
  done
}

# ctr_resolve_roots — map CTR_TARGETS to git toplevels in CTR_ROOTS (unique). An absolute
# target stands alone; a relative one is joined against each base in {the hook's $PWD, the
# payload cwd (HOOK_CWD), every earlier directory}, because `cd a && cd b` composes. A target
# that does not exist or is not inside a work tree is dropped: it cannot stage anything.
# GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE are stripped from the probes, since an inherited
# GIT_DIR outranks `git -C` and would send the probe to the wrong repository.
ctr_resolve_roots() {
  local t base cand top r dup d
  local cands=() seen=()
  CTR_ROOTS=()
  for t in ${CTR_TARGETS[@]+"${CTR_TARGETS[@]}"}; do
    cands=()
    case "$t" in
      /*) cands+=("$t") ;;
      *)
        for base in "$PWD" "${HOOK_CWD-}" ${seen[@]+"${seen[@]}"}; do
          if [ -n "$base" ]; then cands+=("$base/$t"); fi
        done ;;
    esac
    for cand in ${cands[@]+"${cands[@]}"}; do
      [ -d "$cand" ] || continue
      dup=0
      for d in ${seen[@]+"${seen[@]}"}; do if [ "$d" = "$cand" ]; then dup=1; fi; done
      if [ "$dup" -eq 0 ]; then seen+=("$cand"); fi
      top=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$cand" rev-parse --show-toplevel 2>/dev/null) || continue
      [ -n "$top" ] || continue
      dup=0
      for r in ${CTR_ROOTS[@]+"${CTR_ROOTS[@]}"}; do if [ "$r" = "$top" ]; then dup=1; fi; done
      if [ "$dup" -eq 0 ]; then CTR_ROOTS+=("$top"); fi
    done
  done
  return 0
}
