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
# shell's cwd. WHAT IT REFUSES (CTR_BAD): an inline git alias definition (-c alias.*,
# --config-env=alias.*, GIT_CONFIG_KEY_n or GIT_CONFIG_PARAMETERS carrying one, or one set earlier in the command by export,
# a bare assignment or `git config alias.x v`), which also counts as a commit record because an alias can hide a commit
# (CTO row 49); a string operand of a launcher or interpreter that spells a git commit; any target that cannot be read statically — an
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
#   CTR_ROOT_ERR     the first git error (not "not a git repository") ctr_resolve_roots met probing a target: a
#                    repository git cannot read; the caller denies it
#   CTR_LEX_STATE    ok | unavailable (perl / lexer missing, lexer error, truncated stream)
#   CTR_LEX_WHY      the cause when unavailable
#   CTR_LEX_KIND     tooling | parse | bound — which repair applies when unavailable
#   CTR_LEXER        path of the lexer (resolved from this file's own location)
# ctr_resolve_roots then maps CTR_TARGETS to git toplevels in CTR_ROOTS.
#
# STAGING FACTS (#10696, ADR-301). The same walk also records what the command's OWN staging verbs and commit
# flags will put in the index, so the caller can scan the index the commit WILL record, not the one
# that exists before the command runs (commit-index-sim.sh builds that index from these facts):
#   CTR_STAGE_API            1 (a consumer can test the library has the staging facts)
#   CTR_COMMIT_STAGES        1 when the command stages anything: an add/stage record, an opaque or refused
#                            stage, or a commit flag (-a -p -o -i --all --only --include a pathspec)
#   CTR_STAGE_OPAQUE         1 when staging happens that the walker cannot replay (a stage-unknown verb:
#                            apply update-index checkout cherry-pick merge revert stash am read-tree
#                            restore pull switch rebase submodule sparse-checkout mergetool subtree svn quiltimport lfs;
#                            an expansion command
#                            or brace/glob/tilde word or subcommand; a dashed git-<verb>; a staging verb among
#                            the words of a non-git command, or a string operand of a listed launcher or interpreter
#                            that carries the word git (su -c, ssh, flock -c, sg -c, script -c, fish -c, watch, runuser
#                            -c, parallel, csh/tcsh -c, tmux, screen, python -c, perl -e, node -e, ruby -e, php -r, awk;
#                            CTO row 50); an unknown short commit option, a bundle longer than 64
#                            characters, or an unknown or abbreviated `commit --long` option;
#                            --interactive / --pathspec-from-file) -> the caller uses the superset
#   CTR_STAGE_UNSIMULABLE    1 for `update-index --add|--cacheinfo|--index-info` and `apply --index|--cached|
#                            --3way`: they put content in the index from OUTSIDE the working tree -> DENY
#   CTR_STAGE_REFUSE(_WHY)   1 when a staging record (add / stage, or a commit that stages) carries something
#                            that makes git execute configuration or read other files: -c / --config-env keys
#                            core. filter. diff. attr. include. includeif. add. apply. submodule.,
#                            --namespace, --attr-source; an environment name outside the allowlist (LC_* LANG
#                            LANGUAGE TZ TERM NO_COLOR CI GIT_AUTHOR_* GIT_COMMITTER_* GIT_EDITOR GIT_PAGER
#                            GIT_TERMINAL_PROMPT, and by exact name HUSKY HUSKY_SKIP_HOOKS LEFTHOOK LEFTHOOK_EXCLUDE
#                            SKIP PRE_COMMIT_ALLOW_NO_CONFIG) as a prefix, after `env`, or exported / unset / assigned
#                            earlier in the command (a bare assignment only when the name is exported here or
#                            is a GIT_* name), `set -a` / `set -o allexport` / `shopt -so allexport`; `env -i|-u|-`,
#                            `exec -c`; sudo doas su runuser chroot nsenter setpriv bwrap systemd-run unshare -> DENY.
#                            An inline ALIAS definition is not a staging-record key: it is a CTR_BAD (above), on ANY
#                            git record, staging or not (CTO row 49).
#   CTR_ADD_EXACT / _FORCE / _LIT / _NW / _OFF / _OWNC   six parallel arrays, one entry per add/stage record
#                            (OFF = the record's first word in CTR_ADD_ARGV, NW = how many words), and
#                            CTR_ADD_ARGV: every record's words, verb first, appended. exact=0 when any word is
#                            non-literal, an option is outside the allowlist, a pathspec-semantics or -c
#                            global option precedes the verb, or the record was reached through a launcher
#                            outside the pass-through allowlist (rtk timeout nice sudo env command exec
#                            flock). lit=1 when every word is literal (the force-add can be re-run by word).
#   CTR_COMMIT_ALL           1 for -a -p --all --patch (add -u covers them); --no-all / --no-patch clear it
#   CTR_COMMIT_PATHS(_LITERAL)  the commit's pathspec words; literal = no expansion, quoting or glob
#   CTR_COMMIT_OWN_C         the commit's own `git -C <dir>` word (empty when none)
#   CTR_STAGE_CD_FIRST       1 for `cd <dir> && git ... && git ...` and nothing else (no ; || ( { | pushd in the UNQUOTED
#                            text; inside double quotes only a live expansion counts: CTO row 54)
# The test suite carries its own ctr_stage_dump (a canonical text form of these facts); production never prints them.
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
CTR_ROOT_ERR=""
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

# Staging facts (see the header). One reset initialises them at library top level AND in ctr_collect: the
# lexer-skipped plain-commit path never calls ctr_collect, and an unset variable under the hook's `set -u`
# would abort it, which fails OPEN.
_ctr_reset_stage() {
  CTR_STAGE_API=1
  CTR_COMMIT_STAGES=0
  CTR_STAGE_OPAQUE=0
  CTR_STAGE_REFUSE=0
  CTR_STAGE_REFUSE_WHY=""
  CTR_STAGE_UNSIMULABLE=0
  CTR_ADD_EXACT=(); CTR_ADD_FORCE=(); CTR_ADD_LIT=(); CTR_ADD_NW=(); CTR_ADD_OFF=(); CTR_ADD_OWNC=()
  CTR_ADD_ARGV=()
  CTR_COMMIT_ALL=0
  CTR_COMMIT_PATHS=()
  CTR_COMMIT_PATHS_LITERAL=1
  CTR_COMMIT_OWN_C=""
  CTR_STAGE_CD_FIRST=0
  _CTR_PATHSMODE=0
  _CTR_REC_NONEXACT=0
  _CTR_REC_ENVBAD=""
  _CTR_REC_ALIAS=0
  _CTR_CMD_ALIAS=0
  _CTR_CMD_ENVBAD=""
  _CTR_CF_STAGES=0
  _CTR_NREC=0
  _CTR_FIRST_IS_CD=0
  _CTR_FIRST_NW=0
  _CTR_CD_N=0
  _CTR_UQ=""
  _CTR_CD_BAD=0
  _CTR_COMMIT_N=0
  return 0
}
_ctr_reset_stage

# The staging verbs the walker knows: add/stage are replayed; the rest change the index in ways it cannot replay.
# ONE list, used by the pre-filter, the subcommand switch and the unknown-option scan.
_CTR_STAGE_VERBS=" add stage apply update-index checkout cherry-pick merge revert stash am read-tree restore pull switch rebase submodule sparse-checkout mergetool subtree svn quiltimport lfs "
_ctr_is_stage_verb() {
  case "$_CTR_STAGE_VERBS" in *" $1 "*) return 0 ;; esac
  return 1
}

# ctr_wants_lex <command> — the pre-filter of the PERL-LESS path only, and a POSITIVE allowlist (CTO row 46): false
# (no lexer needed) only when the whole command is ONE simple `git commit` with plain flags (-m "<text without $,
# backtick or backslash>", -m <bare word>, -F <file>, --amend, --no-edit, -v, -s, --signoff, --no-verify, -n, -q),
# no pathspec, no separator and no quoted flag. Everything else needs the lexer, and on a host without perl that is
# a `tooling` deny (the repair: install perl, or run git add in one call and the commit in the next). Where perl
# exists the hook lexes every strict commit and never asks. A denylist of staging-looking text would be open-world
# (a quoted verb, `git-add`, `$a add` all slip through it); the false-deny cost of the allowlist falls only on
# minimal containers. A command longer than 16384 characters always wants the lexer (the regex is not bounded).
ctr_wants_lex() {
  local c="$1" flag msg bare file re
  [ "${#c}" -gt 16384 ] && return 0
  flag='-n|-q|-v|-s|--no-verify|--signoff|--amend|--no-edit|--quiet|--verbose'
  msg='-m[[:space:]]+("[^"$`\\]*"|'"'"'[^'"'"']*'"'"')'
  bare='-m[[:space:]]+[A-Za-z0-9_.,:/@%+=-]+'
  file='-F[[:space:]]+[A-Za-z0-9_./-]+'
  re="^[[:space:]]*git[[:space:]]+commit([[:space:]]+(${flag}|${msg}|${bare}|${file}))*[[:space:]]*\$"
  [[ "$c" =~ $re ]] && return 1
  return 0
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

# _ctr_str_stage_verb <string> — a string operand (`su -c "git add -A"`) that names a staging verb or a dashed git-<verb>
# as one of its words. Over-matches on purpose (`ssh host "make add"`): the cost is the superset.
_ctr_str_stage_verb() {
  local t="$1" v hit=1 noglob=0
  # an operand over 8 KB is not read word by word (the loop below is linear in it): opaque, the safe direction
  if [ "${#t}" -gt 8192 ]; then return 0; fi
  case "$-" in *f*) noglob=1 ;; esac
  t="${t//[;&|()<>\`\"\']/ }"
  set -f
  for v in $t; do
    if _ctr_is_stage_verb "$v"; then hit=0; break; fi
  done
  if [ "$noglob" -eq 0 ]; then set +f; fi
  return "$hit"
}

# _ctr_env_ok <NAME> — an environment variable a staging command may set without changing what `git add` reads (CTO
# row 23). Anything else (HOME, PATH, XDG_*, GIT_CONFIG_*, GIT_ATTR_*, GIT_EXTERNAL_DIFF, ...) can point git at other
# configuration, attributes, hooks or an index, which the replay cannot reproduce.
_ctr_env_ok() {
  case "$1" in
    LC_*|LANG|LANGUAGE|TZ|TERM|NO_COLOR|CI|GIT_AUTHOR_*|GIT_COMMITTER_*|GIT_EDITOR|GIT_PAGER|GIT_TERMINAL_PROMPT) return 0 ;;
    HUSKY|HUSKY_SKIP_HOOKS|LEFTHOOK|LEFTHOOK_EXCLUDE|SKIP|PRE_COMMIT_ALLOW_NO_CONFIG) return 0 ;;
  esac
  return 1
}

# _ctr_env_live <NAME> — a bare `NAME=value` reaches git's environment: the name is already exported here (the hook runs
# in the environment the shell it guards inherits) or begins with GIT_.
_ctr_env_live() {
  local d
  case "$1" in GIT_*) return 0 ;; esac
  d=$(declare -p "$1" 2>/dev/null) || return 1
  [[ "$d" =~ ^declare\ -[a-zA-Z]*x ]]
}

# _ctr_env_poison_rec <what> — the CURRENT RECORD runs with an environment the replay cannot reproduce. Only a staging
# record (add / stage, or a commit that stages) refuses on it; the first reason wins.
_ctr_env_poison_rec() {
  if [ -z "$_CTR_REC_ENVBAD" ]; then _CTR_REC_ENVBAD="$1"; fi
  return 0
}

# _ctr_env_poison_cmd <what> — an earlier record (export / unset / a bare assignment) changed the shell's environment
# for every later record. It refuses only when the command stages at all, once the whole stream is read.
_ctr_env_poison_cmd() {
  if [ -z "$_CTR_CMD_ENVBAD" ]; then _CTR_CMD_ENVBAD="$1"; fi
  return 0
}

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
  case "${1%%=*}" in
    [Cc][Oo][Rr][Ee].[Ww][Oo][Rr][Kk][Tt][Rr][Ee][Ee]|[Cc][Oo][Rr][Ee].[Bb][Aa][Rr][Ee]) return 0 ;;
  esac
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
      --u*=*) _ctr_env_poison_rec "env --unset removes variables from the staging command's environment"; k=$((k + 1)) ;;
      --u*) _ctr_env_poison_rec "env --unset removes variables from the staging command's environment"; k=$((k + 2)) ;;
      --i*) _ctr_env_poison_rec "env --ignore-environment empties the staging command's environment"; k=$((k + 1)) ;;
      --argv0) k=$((k + 2)) ;;
      --*) k=$((k + 1)) ;;
      -) _ctr_env_poison_rec "env - empties the staging command's environment"; k=$((k + 1)) ;;
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
            i) _ctr_env_poison_rec "env -i empties the staging command's environment" ;;
            u) _ctr_env_poison_rec "env -u removes variables from the staging command's environment"; [ -z "$rest" ] && k=$((k + 1)); break ;;
            a|P) [ -z "$rest" ] && k=$((k + 1)); break ;;
          esac
          s="$rest"
        done ;;
      *=*)
        if _ctr_is_gitenv "$w"; then _ctr_bad "the command sets ${w%%=*}= (the repository is not named by a path)"; fi
        if _ctr_assign_alias "$w"; then _CTR_REC_ALIAS=1; fi
        _ctr_env_ok "${w%%=*}" || _ctr_env_poison_rec "the staging command sets ${w%%=*} in its environment (git may read a hook, editor, config, attributes or index from it)"
        k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  [ "$k" -lt "$n" ] && _ctr_walk_from "$k"
  return 0
}

# _ctr_word_literal <word> <flags> — the word is a literal the replay may pass to git unchanged: no
# expansion (flag x), no control byte, and no glob / brace / tilde character UNLESS the word was quoted.
_ctr_word_literal() {
  case "$2" in *x*) return 1 ;; esac
  case "$1" in *[[:cntrl:]]*) return 1 ;; esac
  case "$2" in *q*) return 0 ;; esac
  case "$1" in *'*'*|*'?'*|*'['*|*'{'*|*'~'*) return 1 ;; esac
  return 0
}

# _ctr_path_literal <word> <flags> — stricter, for a commit pathspec the ladder re-runs as `add -u -- <paths>`:
# a quoted word is not literal either (CTO row 3: lexer flag x or q, or a glob / brace / tilde character).
_ctr_path_literal() {
  case "$2" in *x*|*q*) return 1 ;; esac
  case "$1" in *[[:cntrl:]]*|*'*'*|*'?'*|*'['*|*'{'*|*'~'*) return 1 ;; esac
  return 0
}

# _ctr_cfg_refuses <key[=value]> — a git config key that makes `git add` EXECUTE configuration (a filter, an
# fsmonitor command, a diff driver, an include) or read attributes / files from somewhere else (CTO row 17). An alias key is
# NOT here: _ctr_alias_key refuses it on any git record (row 40).
_ctr_cfg_refuses() {
  case "${1%%=*}" in
    [Cc][Oo][Rr][Ee].*|[Ff][Ii][Ll][Tt][Ee][Rr].*|[Dd][Ii][Ff][Ff].*|[Aa][Tt][Tt][Rr].*|[Ii][Nn][Cc][Ll][Uu][Dd][Ee].*|[Ii][Nn][Cc][Ll][Uu][Dd][Ee][Ii][Ff].*|[Aa][Dd][Dd].*|[Aa][Pp][Pp][Ll][Yy].*|[Ss][Uu][Bb][Mm][Oo][Dd][Uu][Ll][Ee].*) return 0 ;;
  esac
  return 1
}

# _ctr_alias_key <key[=value]> — an inline alias definition: the aliased name can run any staging under a word the
# walker does not read (CTO row 40).
_ctr_alias_key() {
  case "${1%%=*}" in [Aa][Ll][Ii][Aa][Ss].*) return 0 ;; esac
  return 1
}

# _ctr_assign_alias <NAME=value> — an environment assignment that defines a git alias (CTO row 49): GIT_CONFIG_KEY_<n> whose
# value is an alias key, or GIT_CONFIG_PARAMETERS carrying one. GIT_CONFIG_COUNT / _VALUE_n / _NOSYSTEM / _GLOBAL are not.
_ctr_assign_alias() {
  local n="${1%%=*}" v="${1#*=}"
  case "$n" in
    GIT_CONFIG_KEY_*) _ctr_alias_key "$v" && return 0 ;;
    GIT_CONFIG_PARAMETERS) case "$v" in *[Aa][Ll][Ii][Aa][Ss].*) return 0 ;; esac ;;
  esac
  return 1
}

# _ctr_alias_found <what> — a git alias is being defined inline or earlier in this command: an aliased name can run a
# commit or any staging under a word the walker does not read, with or without a visible commit record, so the commit is
# refused as undeterminable (ctr_collect's caller denies a CTR_BAD) and the staging is opaque.
_ctr_alias_found() {
  _ctr_bad "$1 defines a git alias (-c alias.*, --config-env=alias.*, a GIT_CONFIG_* variable, or an earlier git config alias.*), and an aliased name can run a commit or any staging under a word the hook does not read"
  _ctr_mark_commit
  CTR_STAGE_OPAQUE=1
  return 0
}

# _ctr_config_write_alias <idx-of-config-word> — `git config alias.x value` (a write: two non-option words, no read flag)
# defines an alias for every later git call of the same command: _CTR_CMD_ALIAS makes the next git record refuse.
_ctr_config_write_alias() {
  local k=$(($1 + 1)) n="${#_CTR_W[@]}" w name="" nv=0 rd=0
  while [ "$k" -lt "$n" ]; do
    w="${_CTR_W[$k]}"
    case "$w" in
      --get|--get-all|--get-regexp|--get-urlmatch|-l|--list|--unset|--unset-all|--remove-section|--rename-section|-e|--edit) rd=1 ;;
      -f|--file|--blob|--type|--default|--comment) k=$((k + 1)) ;;
      -*) : ;;
      *) nv=$((nv + 1)); if [ "$nv" -eq 1 ]; then name="$w"; fi ;;
    esac
    k=$((k + 1))
  done
  if [ "$rd" -eq 0 ] && [ "$nv" -ge 2 ] && _ctr_alias_key "$name"; then _CTR_CMD_ALIAS=1; fi
  return 0
}

# _ctr_refuse <why> — the first reason wins.
_ctr_refuse() {
  CTR_STAGE_REFUSE=1
  if [ -z "$CTR_STAGE_REFUSE_WHY" ]; then CTR_STAGE_REFUSE_WHY="$1"; fi
  return 0
}

# _ctr_stage_add <idx-of-verb> — record one `add` / `stage` record: scalar facts in the CTR_ADD_* arrays and the
# record's words (verb first) in CTR_ADD_ARGV (no in-band delimiter). Reads its caller's locals (g_nonexact
# g_ownc g_ncs g_refuse), which _ctr_git_walk sets while it reads git's global options.
_ctr_stage_add() {
  local j="$1" n="${#_CTR_W[@]}" k w fl exact=1 lit=1 force=0 dd=0 s ch
  if [ "$g_nonexact" -eq 1 ] || [ "$_CTR_REC_NONEXACT" -eq 1 ] || [ "$g_ncs" -gt 1 ]; then exact=0; fi
  k=$((j + 1))
  while [ "$k" -lt "$n" ]; do
    w="${_CTR_W[$k]}"; fl="${_CTR_F[$k]}"
    if ! _ctr_word_literal "$w" "$fl"; then exact=0; lit=0; fi
    # Options are checked on EVERY word before `--`, including words after the pathspec, per character for
    # a short bundle. The allowlist is the options whose replay adds exactly what the command adds.
    if [ "$dd" -eq 0 ]; then
      case "$w" in
        --) dd=1 ;;
        --force) force=1 ;;
        --f|--fo|--for|--forc) force=1; exact=0 ;;
        --all|--update|--verbose|--dry-run) : ;;
        # Benign long options keep the words literal; EVERY other long option (an unknown one, or an abbreviation git accepts
        # such as --pathspec-fr or --pathspec-from-fil, which takes its file as the NEXT word) makes the record non-literal:
        # a force-add of words the hook cannot read is a deny, never a guess.
        --chmod=*|--sparse|--ignore-errors|--ignore-missing|--refresh|--no-warn-embedded-repo|--renormalize|--intent-to-add|--no-all|--ignore-removal|--no-ignore-removal) exact=0 ;;
        --*) exact=0; lit=0 ;;
        -) exact=0 ;;
        -?*)
          s="${w#-}"
          if [ "${#s}" -gt 64 ]; then
            # over the cap: not read per character, so a force letter anywhere in it is assumed (the superset re-adds
            # the literal words with -f; over-scanning is the safe direction)
            exact=0; case "$s" in *f*) force=1 ;; esac; s=""
          fi
          while [ -n "$s" ]; do
            ch="${s:0:1}"; s="${s:1}"
            case "$ch" in
              f) force=1 ;;
              A|u|v|n) : ;;
              *) exact=0 ;;
            esac
          done ;;
      esac
    fi
    k=$((k + 1))
  done
  CTR_ADD_EXACT+=("$exact"); CTR_ADD_FORCE+=("$force"); CTR_ADD_LIT+=("$lit"); CTR_ADD_NW+=("$((n - j))")
  CTR_ADD_OFF+=("${#CTR_ADD_ARGV[@]}"); CTR_ADD_OWNC+=("$g_ownc")
  k=$j
  while [ "$k" -lt "$n" ]; do CTR_ADD_ARGV+=("${_CTR_W[$k]}"); k=$((k + 1)); done
  if [ -n "$g_refuse" ]; then
    _ctr_refuse "$g_refuse"
  elif [ -n "$_CTR_REC_ENVBAD" ]; then
    _ctr_refuse "$_CTR_REC_ENVBAD"
  fi
  return 0
}

# _ctr_commit_flags <idx-of-commit-word> — what the commit's own flags stage. Short bundles are read character
# by character; m F C c t take the rest of the word as their operand, or the next word if nothing is attached
# (so `-malpha` is a message, not -a); S and u take only an attached remainder and end the bundle. A short option
# character outside the known set (a p o i m F C c t S u s n v q e z h) makes the stage opaque, and so does a bundle
# whose first 64 characters do not end it (CTO rows 22 and 35: unknown means superset, and the scan is bounded).
# Long options are an EXACT table: the staging ones, and the benign ones from `git commit -h`; anything else,
# including a unique-prefix abbreviation git would accept, makes the stage opaque (superset). `--` starts the
# pathspec and a bare word is a path. _CTR_CF_STAGES = this commit record stages something by itself.
_ctr_commit_flags() {
  local j="$1" n="${#_CTR_W[@]}" k w fl s ch rest dd=0 pm=0 st=0 ci len
  _CTR_CF_STAGES=0
  k=$((j + 1))
  while [ "$k" -lt "$n" ]; do
    w="${_CTR_W[$k]}"; fl="${_CTR_F[$k]}"
    if [ "$dd" -eq 1 ]; then
      _ctr_commit_path "$w" "$fl"; k=$((k + 1)); continue
    fi
    case "$w" in
      --) dd=1; pm=1; k=$((k + 1)) ;;
      --all|--patch) CTR_COMMIT_ALL=1; st=1; k=$((k + 1)) ;;
      --no-all|--no-patch) CTR_COMMIT_ALL=0; k=$((k + 1)) ;;
      --only|--include) pm=1; k=$((k + 1)) ;;
      --no-only|--no-include) pm=0; k=$((k + 1)) ;;
      --interactive|--pathspec-from-file|--pathspec-from-file=*|--pathspec-file-nul) CTR_STAGE_OPAQUE=1; st=1; k=$((k + 1)) ;;
      --message|--file|--author|--date|--reuse-message|--reedit-message|--fixup|--squash|--trailer|--template|--cleanup|--unified|--inter-hunk-context)
        k=$((k + 2)) ;;
      --message=*|--file=*|--author=*|--date=*|--reuse-message=*|--reedit-message=*|--fixup=*|--squash=*|--trailer=*|--template=*|--cleanup=*|--unified=*|--inter-hunk-context=*|--untracked-files=*|--gpg-sign=*)
        k=$((k + 1)) ;;
      --amend|--no-edit|--edit|--signoff|--no-verify|--verbose|--quiet|--dry-run|--short|--branch|--porcelain|--long|--null|--allow-empty|--allow-empty-message|--reset-author|--status|--no-status|--no-post-rewrite|--untracked-files|--gpg-sign|--no-gpg-sign|--no-signoff|--no-reset-author)
        k=$((k + 1)) ;;
      --*) CTR_STAGE_OPAQUE=1; st=1; k=$((k + 1)) ;;
      -?*)
        s="${w#-}"; k=$((k + 1)); ci=0; len="${#s}"
        while [ "$ci" -lt "$len" ]; do
          if [ "$ci" -ge 64 ]; then CTR_STAGE_OPAQUE=1; st=1; break; fi
          ch="${s:$ci:1}"
          case "$ch" in
            a|p) CTR_COMMIT_ALL=1; st=1 ;;
            o|i) pm=1 ;;
            m|F|C|c|t) if [ "$((ci + 1))" -ge "$len" ]; then k=$((k + 1)); fi; break ;;
            S|u) break ;;
            s|n|v|q|e|z|h) : ;;
            *) CTR_STAGE_OPAQUE=1; st=1 ;;
          esac
          ci=$((ci + 1))
        done ;;
      *) pm=1; _ctr_commit_path "$w" "$fl"; k=$((k + 1)) ;;
    esac
  done
  if [ "$pm" -eq 1 ]; then _CTR_PATHSMODE=1; st=1; fi
  if [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then st=1; fi
  _CTR_CF_STAGES=$st
  return 0
}

# _ctr_commit_refuse <g_refuse> — row 24: a commit record that stages is refused when it carries a config key the replay
# cannot honour, or an environment it cannot reproduce. A commit that stages nothing is untouched.
_ctr_commit_refuse() {
  if [ "$_CTR_CF_STAGES" -ne 1 ]; then return 0; fi
  if [ -n "$1" ]; then _ctr_refuse "$1"
  elif [ -n "$_CTR_REC_ENVBAD" ]; then _ctr_refuse "$_CTR_REC_ENVBAD"
  fi
  return 0
}

_ctr_commit_path() {
  CTR_COMMIT_PATHS+=("$1")
  if ! _ctr_path_literal "$1" "$2"; then CTR_COMMIT_PATHS_LITERAL=0; fi
  return 0
}

# _ctr_note_commit_c <-C word or -> — the commit's own -C; two commits that disagree make it unprovable.
_ctr_note_commit_c() {
  local c="$1"
  [ "$c" = "-" ] && c=""
  if [ "$_CTR_COMMIT_N" -eq 0 ]; then CTR_COMMIT_OWN_C="$c"
  elif [ "$CTR_COMMIT_OWN_C" != "$c" ]; then CTR_COMMIT_OWN_C="<several>"
  fi
  _CTR_COMMIT_N=$((_CTR_COMMIT_N + 1))
  return 0
}

# _ctr_unsim_check <idx-of-verb> — `update-index --add|--cacheinfo|--index-info` and `apply --index|--cached|--3way`
# put content in the index that comes from OUTSIDE the working tree (a given object id, a patch): no replay and no
# `add -A` of the working tree can scan it, so the caller DENIES (CTO row 26). Abbreviations git accepts are matched
# by their unique prefix. Every other form of either verb stays opaque (superset).
_ctr_unsim_check() {
  local k=$(($1 + 1)) n="${#_CTR_W[@]}" verb="${_CTR_W[$1]}" w s ch
  while [ "$k" -lt "$n" ]; do
    w="${_CTR_W[$k]}"
    if [ "$verb" = update-index ]; then
      case "$w" in --ad*|--cac*|--ind*) CTR_STAGE_UNSIMULABLE=1 ;; esac
    else
      case "$w" in
        --ca*|--ind*|--3*) CTR_STAGE_UNSIMULABLE=1 ;;
        -[!-]*)
          # a short bundle (`-v3`, `-3v`): the 3 is --3way unless an earlier p / C took the rest as its operand
          s="${w#-}"
          while [ -n "$s" ]; do
            ch="${s:0:1}"; s="${s:1}"
            case "$ch" in 3) CTR_STAGE_UNSIMULABLE=1; break ;; p|C) break ;; esac
          done ;;
      esac
    fi
    k=$((k + 1))
  done
  return 0
}

# _ctr_git_walk <idx-of-git-word> — git's global options, then the subcommand.
_ctr_git_walk() {
  local j=$(($1 + 1)) n="${#_CTR_W[@]}" w unknown=0 sub m q v
  local g_nonexact=0 g_refuse="" g_ownc="-" g_ncs=0 g_alias=0
  while [ "$j" -lt "$n" ]; do
    w="${_CTR_W[$j]}"
    case "$w" in
      -C)
        if [ $((j + 1)) -lt "$n" ]; then
          _ctr_add_idx $((j + 1))
          g_ncs=$((g_ncs + 1)); g_ownc="${_CTR_W[$((j + 1))]}"
          if [ "$g_ncs" -gt 1 ]; then g_ownc="<several>"; fi
          if ! _ctr_word_literal "$g_ownc" "${_CTR_F[$((j + 1))]}"; then g_nonexact=1; fi
        else _ctr_bad "git -C has no operand"; fi
        j=$((j + 2)) ;;
      -c|--config-env)
        g_nonexact=1
        if [ $((j + 1)) -lt "$n" ] && _ctr_alias_key "${_CTR_W[$((j + 1))]}"; then g_alias=1; fi
        if [ $((j + 1)) -lt "$n" ] && _ctr_cfg_moves_worktree "${_CTR_W[$((j + 1))]}"; then
          _ctr_bad "git $w ${_CTR_W[$((j + 1))]%%=*} moves the work tree without a path the walker may trust"
        fi
        if [ $((j + 1)) -lt "$n" ] && _ctr_cfg_refuses "${_CTR_W[$((j + 1))]}"; then
          g_refuse="git $w ${_CTR_W[$((j + 1))]%%=*} changes how git add reads and filters files, so it cannot be replayed safely"
        fi
        j=$((j + 2)) ;;
      --config-env=*)
        g_nonexact=1
        if _ctr_alias_key "${w#--config-env=}"; then g_alias=1; fi
        if _ctr_cfg_moves_worktree "${w#--config-env=}"; then
          _ctr_bad "git --config-env ${w#--config-env=} moves the work tree without a path the walker may trust"
        fi
        if _ctr_cfg_refuses "${w#--config-env=}"; then
          g_refuse="git --config-env ${w#--config-env=} changes how git add reads and filters files, so it cannot be replayed safely"
        fi
        j=$((j + 1)) ;;
      --git-dir|--work-tree) _ctr_bad "git $w redirects the repository without a path the walker may trust"; j=$((j + 2)) ;;
      --git-dir=*|--work-tree=*) _ctr_bad "git ${w%%=*} redirects the repository without a path the walker may trust"; j=$((j + 1)) ;;
      --namespace|--attr-source)
        g_nonexact=1; g_refuse="git $w changes which refs or attributes git add uses, so it cannot be replayed safely"; j=$((j + 2)) ;;
      --namespace=*|--attr-source=*)
        g_nonexact=1; g_refuse="git ${w%%=*} changes which refs or attributes git add uses, so it cannot be replayed safely"; j=$((j + 1)) ;;
      --super-prefix) j=$((j + 2)) ;;
      --literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs) g_nonexact=1; j=$((j + 1)) ;;
      --no-pager|--paginate|-p|-P|--bare|--no-replace-objects|--no-optional-locks|--no-advice|--no-lazy-fetch|--exec-path|--exec-path=*|-v|--version|-h|--help)
        j=$((j + 1)) ;;
      -*) unknown=1; g_nonexact=1; j=$((j + 1)) ;;
      *) break ;;
    esac
  done
  # An inline alias definition on ANY git record (a -c / --config-env key, a GIT_CONFIG_KEY_n / GIT_CONFIG_PARAMETERS
  # prefix, or one set earlier in the command: export, a bare assignment, `git config alias.x v`), staging or not, is
  # refused: an aliased name can run a commit or any staging under a word the walker does not read (CTO rows 40 and 49).
  if [ "$g_alias" -eq 1 ] || [ "$_CTR_REC_ALIAS" -eq 1 ] || [ "$_CTR_CMD_ALIAS" -eq 1 ]; then
    _ctr_alias_found "this git call"
  fi
  # The first non-option word is the subcommand; a -C AFTER it (commit -C HEAD) is the
  # subcommand's own option, never a global one, because this loop stopped at it.
  if [ "$j" -lt "$n" ]; then
    sub="${_CTR_W[$j]}"
    # An expanded, glob, brace or tilde subcommand (`git "$S" ...`, `git ad{d,} -A`) may be any staging verb: the superset.
    _ctr_word_literal "$sub" "${_CTR_F[$j]}" || CTR_STAGE_OPAQUE=1
    if [ "$sub" = config ]; then _ctr_config_write_alias "$j"; fi
    case "$sub" in
      commit) _ctr_mark_commit; _ctr_commit_flags "$j"; _ctr_note_commit_c "$g_ownc"; _ctr_commit_refuse "$g_refuse" ;;
      add|stage) _ctr_stage_add "$j" ;;
      # rm and mv act on the WORKING TREE and add no new blob content: recognised, ignored, never replayed.
      rm|mv) : ;;
      submodule) _CTR_CREATOR=1; CTR_STAGE_OPAQUE=1 ;;
      worktree|clone|init) _CTR_CREATOR=1 ;;
      update-index|apply) CTR_STAGE_OPAQUE=1; _ctr_unsim_check "$j" ;;
      *)
        # Verbs that change the index in ways the walker cannot replay: the caller scans the superset.
        if _ctr_is_stage_verb "$sub"; then CTR_STAGE_OPAQUE=1; fi
        # An option the walker does not know may have swallowed the real subcommand as its
        # operand; if a `commit` word follows, treat it as a commit rather than guess.
        if [ "$unknown" -eq 1 ]; then
          m=$((j + 1))
          q=$j
          for v in "${_CTR_W[@]:$j}"; do
            if _ctr_is_stage_verb "$v"; then CTR_STAGE_OPAQUE=1; fi
            case "$v" in update-index|apply) _ctr_unsim_check "$q" ;; esac
            q=$((q + 1))
          done
          while [ "$m" -lt "$n" ]; do
            if [ "${_CTR_W[$m]}" = commit ]; then
              # The option's operand hid the subcommand, so option words after it were never
              # read either: collect the -C operands that precede the commit word.
              q=$((j + 1))
              while [ "$q" -lt "$m" ]; do
                if [ "${_CTR_W[$q]}" = -C ] && [ $((q + 1)) -lt "$m" ]; then _ctr_add_idx $((q + 1)); fi
                q=$((q + 1))
              done
              _ctr_mark_commit; _ctr_commit_flags "$m"; _ctr_note_commit_c "-"; _ctr_commit_refuse "$g_refuse"; break
            fi
            m=$((m + 1))
          done
        fi ;;
    esac
  fi
  return 0
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
  local i="$1" n="${#_CTR_W[@]}" j w b k hits h envbad="" so sm sa
  # Leading NAME=value assignments (NAME+=value too).
  while [ "$i" -lt "$n" ]; do
    w="${_CTR_W[$i]}"
    case "$w" in
      [A-Za-z_]*=*)
        k="${w%%=*}"; k="${k%+}"
        case "$k" in *[!A-Za-z0-9_]*) break ;; esac
        if _ctr_is_gitenv "$w"; then _ctr_bad "the command sets $k= (the repository is not named by a path)"; fi
        if ! _ctr_env_ok "$k" && [ -z "$envbad" ]; then envbad="$k"; fi
        if _ctr_assign_alias "$w"; then _CTR_REC_ALIAS=1; fi
        i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  # a bare assignment of an alias-defining name (`GIT_CONFIG_KEY_0=alias.ci; export ...`) reaches every later git record
  if [ "$i" -ge "$n" ] && [ "$_CTR_REC_ALIAS" -eq 1 ]; then _CTR_CMD_ALIAS=1; fi
  if [ -n "$envbad" ]; then
    if [ "$i" -lt "$n" ]; then
      _ctr_env_poison_rec "the staging command sets $envbad in its environment (git may read a hook, editor, config, attributes or index from it)"
    elif _ctr_env_live "$envbad"; then
      # a bare assignment (`HOME=/x; git add`) changes the environment of every later record when the name is one git
      # can see: already exported (HOME, PATH, XDG_*), or a GIT_* name. A plain shell variable (`F=a.txt; git add $F`)
      # is not in git's environment and is left alone.
      _ctr_env_poison_cmd "the command sets $envbad in the shell's environment before it stages (git may read a hook, editor, config, attributes or index from it)"
    fi
  fi
  [ "$i" -lt "$n" ] || return 0

  # A command word that is itself an expansion ("$GIT" -C x commit) cannot be read.
  case "${_CTR_F[$i]}" in
    *x*)
      # a dashed git-<verb> hidden in the expansion (`$(git --exec-path)/git-add`) is a staging verb too
      case "${_CTR_W[$i]}" in *git-*) CTR_STAGE_OPAQUE=1 ;; esac
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        if _ctr_is_stage_verb "${_CTR_W[$j]}"; then CTR_STAGE_OPAQUE=1; fi
        j=$((j + 1))
      done
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
    # The dashed forms (`git-commit`, `git-add`) run the same programs without the `git` word (CTO row 22): a
    # commit is a commit, and any other dashed verb is a staging verb the walker does not replay.
    git-commit) _ctr_mark_commit; _ctr_commit_flags "$i"; _ctr_note_commit_c "-"; _ctr_commit_refuse "" ;;
    git-*) CTR_STAGE_OPAQUE=1 ;;
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
    export|declare|typeset|readonly|local|unset)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"
        if _ctr_is_gitenv "$w"; then _ctr_bad "$b ${w%%=*}= moves the repository without a path the walker may trust"; fi
        if _ctr_assign_alias "$w"; then _CTR_CMD_ALIAS=1; fi
        # a name outside the allowlist changes what a later `git add` reads (CTO row 23); options are skipped
        case "$w" in
          -*) : ;;
          *)
            k="${w%%=*}"; k="${k%+}"
            case "$k" in
              ''|*[!A-Za-z0-9_]*) : ;;
              *) _ctr_env_ok "$k" || _ctr_env_poison_cmd "the command changes $k in the shell's environment before it stages (git may read a hook, editor, config, attributes or index from it)" ;;
            esac ;;
        esac
        j=$((j + 1))
      done ;;
    # `set -a` / `set -o allexport` exports every later assignment, so a following bare `XDG_CONFIG_HOME=x` reaches git
    # (CTO row 41); treated like an export of an outside name.
    set)
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"
        case "$w" in
          -[!-]*)
            case "${w#-}" in *a*) _ctr_env_poison_cmd "the command runs set -a, which exports every later assignment (git may read a hook, editor, config, attributes or index from it)" ;; esac
            case "${w#-}" in *o) j=$((j + 1)); case "${_CTR_W[$j]-}" in allexport) _ctr_env_poison_cmd "the command runs set -o allexport, which exports every later assignment (git may read a hook, editor, config, attributes or index from it)" ;; esac ;; esac ;;
        esac
        j=$((j + 1))
      done ;;
    # `shopt -so allexport` / `shopt -o -s allexport` is `set -a` (the -o switches shopt to the set -o option names)
    shopt)
      j=$((i + 1)); so=0; sm=0; sa=0
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"
        case "$w" in
          -[!-]*) case "${w#-}" in *s*) sm=1 ;; esac; case "${w#-}" in *o*) so=1 ;; esac ;;
          allexport) sa=1 ;;
        esac
        j=$((j + 1))
      done
      if [ "$so" -eq 1 ] && [ "$sa" -eq 1 ] && [ "$sm" -eq 1 ]; then
        _ctr_env_poison_cmd "the command runs shopt -s -o allexport, which exports every later assignment (git may read a hook, editor, config, attributes or index from it)"
      fi ;;
    mkdir|mv|cp|ln|install|rsync|tar|unzip) _CTR_CREATOR=1 ;;
    *)
      # Not a command the walker models: it may be a launcher (timeout, sudo, nice, xargs,
      # rtk, flock, setsid, exec, command, builtin, ...). Look through it for EVERY later
      # command word (the first may be an operand: `sudo -u git git ...`), and honour a
      # launcher's own chdir option (sudo -D, --chdir, --working-directory) on the way.
      # A staging record reached through anything but the pass-through allowlist is not replayed exactly.
      case "$b" in rtk|timeout|nice|sudo|command|exec|flock) : ;; *) _CTR_REC_NONEXACT=1 ;; esac
      # A launcher that changes the user, root, namespace or environment runs git with configuration the replay cannot
      # reproduce (CTO rows 23 and 41): a staging record behind one is refused ("stage in its own call"). `exec -c`
      # empties the environment like `env -i`.
      if [ "$b" = exec ]; then
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do
          case "${_CTR_W[$j]}" in
            --*) : ;;
            -*) case "${_CTR_W[$j]#-}" in *c*) _ctr_env_poison_rec "the staging command runs through exec -c, which empties its environment" ;; esac ;;
            *) break ;;
          esac
          j=$((j + 1))
        done
      fi
      case "$b" in
        sudo|doas|su|runuser|setpriv|bwrap|systemd-run) _ctr_env_poison_rec "the staging command runs through $b, which changes the user, root or environment git reads its configuration from" ;;
        chroot|nsenter|unshare)
          # one arm for the root / namespace launchers: the environment is changed AND a git behind them is a commit the walker
          # cannot place
          _ctr_env_poison_rec "the staging command runs through $b, which changes the user, root or environment git reads its configuration from"
          j=$((i + 1))
          while [ "$j" -lt "$n" ]; do
            if [ "${_CTR_W[$j]##*/}" = git ]; then
              _ctr_bad "$b changes the root or namespace the commit runs in"; _ctr_mark_commit; break
            fi
            j=$((j + 1))
          done ;;
      esac
      case "$b" in
        su|flock|ssh|watch|script|runuser|parallel|fish|ash|sg|csh|tcsh|tmux|screen|python|python2|python3|perl|node|nodejs|ruby|php|lua|awk|gawk|mawk)
          # These take a program or a command as a STRING operand. One that carries the word git is opaque (CTO row 50: the
          # superset; matching literal verbs is defeated by quoting and variables). It is also refused when the string, with
          # quotes, backslashes and $ taken out, says `commit` as well (`su -c "git add -A && git commit"`, `git com''mit`). A
          # plain `ssh host "git pull"` is opaque but is no commit: it is denied only when a commit record follows or precedes
          # it, by the same superset every other opaque staging gets.
          j=$((i + 1))
          while [ "$j" -lt "$n" ]; do
            w="${_CTR_W[$j]}"
            case "$w" in
              *git*)
                CTR_STAGE_OPAQUE=1
                k="${w//[\'\"\\$]/}"
                case "$k" in
                  *commit*) _ctr_bad "$b runs a command string the walker cannot read"; _ctr_mark_commit; break ;;
                esac ;;
              *) if _ctr_str_stage_verb "$w"; then CTR_STAGE_OPAQUE=1; fi ;;
            esac
            j=$((j + 1))
          done ;;
      esac
      hits=(); j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        w="${_CTR_W[$j]}"; case "$w" in */*) w="${w##*/}" ;; esac
        case "$w" in
          git|cd|pushd|env|bash|sh|zsh|dash|ksh|e[v]al|export|declare|typeset|readonly|local)
            if [ "${#hits[@]}" -ge 8 ]; then
              _ctr_bad "more than 8 command words behind an unmodelled launcher"; _ctr_mark_commit; break
            fi
            hits+=("$j") ;;
        esac
        j=$((j + 1))
      done
      if [ "${#hits[@]}" -eq 0 ]; then
        # No git, cd, env or shell word behind this command, but a staging verb among its words (`make add`,
        # `npm add`, `cargo add`): it may stage through a program the walker cannot read, so the superset (CTO row 22).
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do
          if _ctr_is_stage_verb "${_CTR_W[$j]}"; then CTR_STAGE_OPAQUE=1; break; fi
          j=$((j + 1))
        done
      fi
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

# _ctr_rec_note — per-record facts, taken before the record is walked: reset the launcher / env state and
# keep what the cd-first shape needs (the first record is `cd <one word>`; every other record is a git).
_ctr_rec_note() {
  local i=0 n="${#_CTR_W[@]}" w k b=""
  _CTR_REC_NONEXACT=0; _CTR_REC_ENVBAD=""; _CTR_REC_ALIAS=0
  while [ "$i" -lt "$n" ]; do
    w="${_CTR_W[$i]}"
    case "$w" in
      [A-Za-z_]*=*) k="${w%%=*}"; case "$k" in *[!A-Za-z0-9_]*) break ;; esac; i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$i" -lt "$n" ]; then b="${_CTR_W[$i]##*/}"; fi
  _CTR_NREC=$((_CTR_NREC + 1))
  if [ "$_CTR_NREC" -eq 1 ]; then
    if [ "$b" = cd ] && [ "$i" -eq 0 ]; then _CTR_FIRST_IS_CD=1; _CTR_FIRST_NW=$n; fi
  elif [ "$b" != git ]; then
    _CTR_CD_BAD=1
  fi
  if [ "$b" = cd ]; then _CTR_CD_N=$((_CTR_CD_N + 1)); fi
  return 0
}

# _ctr_stage_finish <command> — the derived facts, once the whole stream parsed.
_ctr_stage_finish() {
  local cmd="$1" t
  if [ "${#CTR_ADD_EXACT[@]}" -gt 0 ] || [ "$CTR_STAGE_OPAQUE" -eq 1 ] || [ "$CTR_STAGE_REFUSE" -eq 1 ] \
     || [ "$CTR_COMMIT_ALL" -eq 1 ] || [ "$_CTR_PATHSMODE" -eq 1 ] || [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then
    CTR_COMMIT_STAGES=1
    # an export / unset / bare assignment earlier in the command changed the environment of the staging that follows
    if [ -n "$_CTR_CMD_ENVBAD" ]; then _ctr_refuse "$_CTR_CMD_ENVBAD"; fi
  fi
  # `cd <abs> && git ... && git ...` and nothing else: a ; || | ( { pushd popd or substitution in the UNQUOTED text defeats
  # the proof (a subshell or a failing cd would not move the commit). Quoted text is judged by what it can DO (CTO row 54):
  # inside single quotes nothing is live; inside double quotes only an expansion ($name, ${, $(, a backtick) is, so a commit
  # message such as "fix(x): y" or one with a newline keeps the proof. Past 4096 characters, or 64 quoted regions, the proof is not granted.
  if [ "$_CTR_FIRST_IS_CD" -eq 1 ] && [ "$_CTR_FIRST_NW" -eq 2 ] && [ "$_CTR_CD_N" -eq 1 ] && [ "$_CTR_CD_BAD" -eq 0 ] \
     && [ "${#cmd}" -le 4096 ] && _ctr_unquoted "$cmd"; then
    t="${_CTR_UQ//&&/}"
    case "$t" in
      *';'*|*'|'*|*'&'*|*'('*|*')'*|*'{'*|*'}'*|*'`'*|*'$'*|*pushd*|*popd*|*$'\n'*) : ;;
      *) CTR_STAGE_CD_FIRST=1 ;;
    esac
  fi
  return 0
}

# _ctr_unquoted <command text> — _CTR_UQ = the text with every quoted region removed; returns 1 (the proof is lost) when
# a double-quoted region carries a live expansion or the quoting is not balanced. In a double-quoted region a backslash
# escapes the next character, so `\$x` is inert.
_ctr_unquoted() {
  local t="$1" dq nq=0
  local re_head='^(([^'"'"'"\\]|\\.)*)' re_sq="^'([^']*)'" re_dq='^"(([^"\\]|\\.)*)"'
  _CTR_UQ=""
  while [ -n "$t" ]; do
    # each region re-reads the rest of the text: past 64 regions the proof is simply not granted
    nq=$((nq + 1)); if [ "$nq" -gt 64 ]; then return 1; fi
    [[ "$t" =~ $re_head ]] || return 1
    _CTR_UQ="$_CTR_UQ${BASH_REMATCH[1]}"; t="${t:${#BASH_REMATCH[0]}}"
    [ -n "$t" ] || break
    if [[ "$t" =~ $re_sq ]]; then
      t="${t:${#BASH_REMATCH[0]}}"
    elif [[ "$t" =~ $re_dq ]]; then
      dq="${BASH_REMATCH[1]}"; t="${t:${#BASH_REMATCH[0]}}"
      dq="${dq//\\?/}"
      case "$dq" in
        *'$('*|*'${'*|*'`'*|*'$'[A-Za-z_0-9@*#?!$-]*) return 1 ;;
      esac
    else
      return 1
    fi
  done
  return 0
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
  _ctr_reset_stage
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
        _ctr_stage_finish "$cmd"
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
        _ctr_rec_note
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
  CTR_ROOTS=(); CTR_ROOT_ERR=""
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
      top=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR LC_ALL=C git -C "$cand" rev-parse --show-toplevel 2>&1) || {
        # a failure other than "not a repository" is a repository git cannot read (a bad config value): the caller denies it
        case "$top" in
          *"not a git repository"*|*"must be run in a work tree"*) : ;;
          *) if [ -z "$CTR_ROOT_ERR" ]; then CTR_ROOT_ERR="${top%%$'\n'*}"; fi ;;
        esac
        continue
      }
      top="${top##*$'\n'}"
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
