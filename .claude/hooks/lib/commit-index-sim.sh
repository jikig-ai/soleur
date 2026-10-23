# shellcheck shell=bash
# shellcheck disable=SC2034  # the CIS_* results are read by the sourcing hook
# commit-index-sim.sh — build the index a Bash command's OWN staging will leave behind, so a scan can read it
# BEFORE the command runs (#10696).
# The contract, the deny causes and the named residuals are indexed in ADR-296.
#
# THE DEFECT THIS EXISTS FOR. git-commit-secret-scan.sh scanned the index before the command it guards had
# run, so `git add -A && git commit`, `git commit -a` and `git commit -- <path>` were scanned against an index
# that did not yet hold the content the commit records. This library copies the real index to a temp file,
# replays the command's staging onto the COPY, and exports the copy (plus a quarantined object directory) so
# any git or gitleaks child reads the would-be index. The real index, the real object store, the real git
# directory and the working tree are never written.
#
# POLICY-FREE BY DESIGN (so the brand-hex gate, #10793, can reuse construction without inheriting the secret-
# scan policy). This file never denies, never allows, never emits a ledger row, never runs gitleaks. It builds,
# and it says how it went; the CALLER maps the codes to a decision.
#
# CONTRACT
#   cis_plan <payload-cwd>            pure over the CTR_* facts (commit-target-roots.sh), called ONCE per command before
#                                     any cis_build. Sets CIS_MODE (exact | superset), CIS_WHY (why the superset, else
#                                     empty) and, for exact, CIS_DIR (the directory the replay runs in) and CIS_TOP (the
#                                     git toplevel of CIS_DIR: the ONE root the replay is valid for; CTO row 33).
#                                     With exact, a caller simulates only the root whose toplevel is CIS_TOP and scans
#                                     every other root (a fallback-only root the command cannot stage into) against its
#                                     real index; with superset it builds every root. cis_build needs the plan: without
#                                     one it fails closed (CIS_WHY not-planned).
#   cis_build <root> <cwd> <workdir>  prepare, export, replay, commit step. Returns EXACTLY 0 (built), 10
#                                     (built, after a trusted pathspec-missing error: the exact replay hit a path
#                                     that does not exist yet and the superset was built instead) or 20 (failure;
#                                     any other non-zero maps to 20; CIS_WHY names the cause, CIS_ERR holds a
#                                     SANITISED first error line). On 0 and 10 the three variables are exported
#                                     and CIS_ACTIVE=1; on 20 they are restored and <workdir> is removed.
#                                     <workdir> must exist and be private (the caller makes it, mode 700).
#   cis_export / cis_unexport         export / restore GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY and
#                                     GIT_ALTERNATE_OBJECT_DIRECTORIES, restoring a prior value or unsetting it
#                                     (unset and empty are different), and set / clear CIS_ACTIVE so the flag
#                                     cannot outlive the export window.
#   CIS_ENV=(NAME=value ...)          the same three assignments, so a consumer that is not a shell function
#                                     can run:  env "${CIS_ENV[@]}" git diff --cached
#   cis_clock_start / cis_remaining   one total deadline for the whole simulation across roots, INCLUDING the
#                                     scan the caller runs inside the window. 30 s, tracked with $SECONDS. A
#                                     consumer that never started the clock has no time left (fail closed).
#   cis_bound_argv                    CIS_BOUND_ARGV=(perl -e "$CIS_BOUND_PL" <seconds left>): a prefix that runs
#                                     its command in its own process group and, when the time is up, TERMs then
#                                     KILLs the whole group and exits 124 (the child's own status otherwise).
#                                     Returns 1 when no time is left. perl is on every host that gets this far
#                                     (the lexer needs it), so there is no fallback tool ladder.
#   cis_pins_build <root>             CIS_PINS=(-c ... ): the pin arguments every git call that reads or writes the
#                                     simulated index must carry (below).
#   CIS_API=1                         the contract version a caller can test before it trusts this file.
#
# DOCUMENTED INPUTS (read, never written): the CTR_* staging facts, _CTR_TEXT (the command text) and
# CIS_DEADLINE_SECONDS.
#
# CIS_DEADLINE_SECONDS is a TEST-ONLY knob and can only LOWER the ceiling: a plain non-negative integer below 30
# becomes the limit; anything else (a larger number, a negative or non-number) is ignored; 0 means no time remains,
# so the first call fails. It
# cannot raise the ceiling, so a hostile value can only cause a deny, never an allow. (Decision-challenges row 37.)
#
# THE REPLAY. Exact replay runs the command's own add records, in text order, as `git -C <dir> add <validated
# options> -- <paths>` and then the commit's own flags (`-a`/`-p` -> add -u; a pathspec -> add -u -- <literal
# paths>, then add -u, then add -A only if both fail). It is used only when ALL of these hold: every add record exact; nothing opaque; no loop or function in the text; and the directory is
# PROVEN: (i) the command names no cd / pushd / -C and the payload cwd is an absolute existing directory, or
# (ii) every add record and the commit carry the same absolute existing -C, or (iii) `cd <abs>` is the first
# record followed only by &&-joined git records. Everything else uses the SUPERSET: `git add -A`, plus
# `git add -f -- <literal words>` for any force-add record (a non-literal force-add fails: CIS_WHY
# force-nonliteral). A replay failure is classified by git's own words, under LC_ALL=C: rc 128 and a first line
# matching `fatal: pathspec '...' did not match any files` is the trusted pathspec-missing error (a path that does
# not exist cannot be scanned: a failure, CIS_WHY pathspec-missing, never an allow); ANY other failure (timeout,
# ENOSPC, another exit 128) abandons the exact replay and rebuilds from a FRESH copy with the superset. A failed
# superset is a failure (return 20), never an allow.
#
# EVERY replay git call carries the same pins (CTO rows 18 and 28): `-c core.fsmonitor=false -c
# core.untrackedCache=false -c core.splitIndex=false -c core.hooksPath=/dev/null`, plus `-c filter.<n>.clean= -c
# filter.<n>.process= -c filter.<n>.smudge= -c filter.<n>.required=false` for each configured filter, LC_ALL=C and
# GIT_OPTIONAL_LOCKS=0, and the verb is always the literal `add` (an alias cannot hijack it). The replay forwards
# NOTHING from the command except validated options and paths. `git add` on a temp index would otherwise run
# configured clean filters and the repository's hooks at hook time, write a sharedindex.* into the REAL git
# directory under core.splitIndex, start an fsmonitor daemon, and (with a dirty submodule) rewrite the submodule's
# real index. The sim therefore scans the RAW bytes: a clean filter or Git LFS may record bytes the sim never saw
# (a named residual). What the sim does NOT guarantee: it may refresh the mtime of an existing real loose object
# or shared index when the content it adds is already present. Content, directory listing and index bytes of the
# real repository do not change. The read-only prepare calls (rev-parse, config) are not pinned and not bounded:
# they write nothing and run no filter.
#
# RULES THIS FILE FOLLOWS: it calls no mktemp (the caller allocates the temp directory and owns its trap), sets no
# trap, never calls `exit` (one exception: the canonical assert_fixture_dir guard below `exit 2`s on an empty or
# relative directory, which is a BLOCKING hook error, so it fails closed, and cannot fire on a workdir this file
# has just made absolute), and is never called inside `$(...)` (a call there loses the exports). Every fallible
# step is checked explicitly and returns a code, and that holds under BOTH errexit regimes: called bare under the
# hook's `set -e`, a failing command would exit 1 (which the harness treats as non-blocking); called on the left
# of `||` or inside an `if`, errexit is OFF for the whole function, so an unchecked failure would CONTINUE with a
# half-built state. bash 3.2: no mapfile, no declare -n, no associative arrays; an empty array is read as
# ${a[@]+"${a[@]}"}. It needs git, perl, cp, mkdir, rm, tr and chmod-free POSIX tools.
#
# THE COPY KEEPS THE INDEX'S MTIME (`cp -p`). git decides whether a file is "racily clean" by comparing an entry's
# mtime with the mtime of the index FILE; a plain cp stamps the copy "now", so a file edited in the same second
# as the entry was written and to the same size would be trusted as unchanged and `add -u` would skip it (measured
# on a freshly built fixture: the simulated index held the old blob).

CIS_ACTIVE=0
CIS_MODE=""
CIS_WHY=""
CIS_ERR=""
CIS_DIR=""
CIS_ENV=()
CIS_API=1
CIS_TOP=""
CIS_REMAINING=0
CIS_BOUND_ARGV=()
CIS_PINS=()
_CIS_T0=""
_CIS_PLANNED=0
_CIS_PLAN_MODE=superset; _CIS_PLAN_WHY=""; _CIS_PLAN_DIR=""
_CIS_LIMIT=30
_CIS_ERRF=""
_CIS_RC=0
_CIS_EXPORTED=0
_CIS_HAD_IDX=0; _CIS_OLD_IDX=""
_CIS_HAD_OBJ=0; _CIS_OLD_OBJ=""
_CIS_HAD_ALT=0; _CIS_OLD_ALT=""
_CIS_WD=""
_CIS_ROOT=""
_CIS_PCWD=""
_CIS_REAL_IDX=""

# The canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh; asserted by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh), called before every recursive remove and every write
# under the workdir so an empty or relative path can never retarget it at the caller's directory. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# ---- the clock and the bound --------------------------------------------------------------------

# The bound (CTO row 30): one fork/waitpid/kill program for every host. A perl `alarm` + exec does NOT stop gitleaks
# (a Go program: measured, still running 30 s after a 2 s alarm), and `timeout` is absent on a stock macOS. The
# child runs in its own process group so the TERM (then KILL, 2 s later) reaches its grandchildren too.
read -r -d '' CIS_BOUND_PL <<'PL' || true
my $t = shift; my $p = fork(); defined $p or exit 125;
if (!$p) { setpgrp(0,0); exec @ARGV or exit 127 }
$SIG{ALRM} = sub { kill 'TERM', -$p; select(undef,undef,undef,2); kill 'KILL', -$p; waitpid($p,0); exit 124 };
alarm $t; waitpid($p,0); alarm 0;
exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
PL

cis_clock_start() {
  local v
  _CIS_LIMIT=30
  # lower-only, and only for a plain non-negative integer (read as decimal: `08` is 8, not a bad octal that would
  # abort the arithmetic below under the hook's errexit): anything else is ignored.
  v="${CIS_DEADLINE_SECONDS-}"
  case "$v" in
    ''|*[!0-9]*) : ;;
    *) if [ "${#v}" -le 9 ]; then v=$((10#$v)); if [ "$v" -lt "$_CIS_LIMIT" ]; then _CIS_LIMIT=$v; fi; fi ;;
  esac
  _CIS_T0=$SECONDS
  return 0
}

# cis_remaining — CIS_REMAINING = whole seconds left (<= 0: none; also when the clock was never started).
cis_remaining() {
  if [ -z "$_CIS_T0" ]; then CIS_REMAINING=0; return 0; fi
  CIS_REMAINING=$((_CIS_LIMIT - (SECONDS - _CIS_T0)))
  return 0
}

# cis_bound_argv — CIS_BOUND_ARGV for the time left; returns 1 when none is left.
cis_bound_argv() {
  cis_remaining
  CIS_BOUND_ARGV=()
  if [ "$CIS_REMAINING" -le 0 ]; then return 1; fi
  CIS_BOUND_ARGV=(perl -e "$CIS_BOUND_PL" "$CIS_REMAINING")
  return 0
}

# _cis_git_run <git args...> — one pinned, bounded git call. stdout is dropped; stderr goes to $_CIS_ERRF.
# Returns git's status (124: the bound expired). Call it in an `if`.
_cis_git_run() {
  local rc=0
  if ! cis_bound_argv; then
    _CIS_RC=124
    assert_fixture_dir "$_CIS_ERRF"
    : > "$_CIS_ERRF"
    return 124
  fi
  LC_ALL=C GIT_OPTIONAL_LOCKS=0 "${CIS_BOUND_ARGV[@]}" git "$@" >/dev/null 2>"$_CIS_ERRF" || rc=$?
  _CIS_RC=$rc
  return "$rc"
}

# ---- the exported window ------------------------------------------------------------------------

cis_export() {  # <index file> <objects dir> <alternate objects dirs>
  if [ "$_CIS_EXPORTED" -eq 0 ]; then
    if [ "${GIT_INDEX_FILE+x}" ]; then _CIS_HAD_IDX=1; _CIS_OLD_IDX="$GIT_INDEX_FILE"; else _CIS_HAD_IDX=0; _CIS_OLD_IDX=""; fi
    if [ "${GIT_OBJECT_DIRECTORY+x}" ]; then _CIS_HAD_OBJ=1; _CIS_OLD_OBJ="$GIT_OBJECT_DIRECTORY"; else _CIS_HAD_OBJ=0; _CIS_OLD_OBJ=""; fi
    if [ "${GIT_ALTERNATE_OBJECT_DIRECTORIES+x}" ]; then _CIS_HAD_ALT=1; _CIS_OLD_ALT="$GIT_ALTERNATE_OBJECT_DIRECTORIES"; else _CIS_HAD_ALT=0; _CIS_OLD_ALT=""; fi
  fi
  export GIT_INDEX_FILE="$1" GIT_OBJECT_DIRECTORY="$2" GIT_ALTERNATE_OBJECT_DIRECTORIES="$3"
  CIS_ENV=("GIT_INDEX_FILE=$1" "GIT_OBJECT_DIRECTORY=$2" "GIT_ALTERNATE_OBJECT_DIRECTORIES=$3")
  _CIS_EXPORTED=1
  CIS_ACTIVE=1
  return 0
}

cis_unexport() {
  if [ "$_CIS_EXPORTED" -eq 1 ]; then
    if [ "$_CIS_HAD_IDX" -eq 1 ]; then export GIT_INDEX_FILE="$_CIS_OLD_IDX"; else unset GIT_INDEX_FILE; fi
    if [ "$_CIS_HAD_OBJ" -eq 1 ]; then export GIT_OBJECT_DIRECTORY="$_CIS_OLD_OBJ"; else unset GIT_OBJECT_DIRECTORY; fi
    if [ "$_CIS_HAD_ALT" -eq 1 ]; then export GIT_ALTERNATE_OBJECT_DIRECTORIES="$_CIS_OLD_ALT"; else unset GIT_ALTERNATE_OBJECT_DIRECTORIES; fi
  fi
  _CIS_EXPORTED=0
  CIS_ACTIVE=0
  return 0
}

# ---- the plan ------------------------------------------------------------------------------------

# _cis_abs_dir <path> — an absolute path naming an existing directory.
_cis_abs_dir() {
  case "$1" in /*) ;; *) return 1 ;; esac
  [ -d "$1" ] || return 1
  return 0
}

# cis_plan <payload-cwd> — exact only when every condition holds; the first that fails names the cause. The result is
# kept for every later cis_build of the same command.
cis_plan() {
  _cis_plan_decide "${1-}"
  _CIS_PLAN_MODE="$CIS_MODE"; _CIS_PLAN_WHY="$CIS_WHY"; _CIS_PLAN_DIR="$CIS_DIR"; _CIS_PLANNED=1
  return 0
}

_cis_plan_decide() {
  local pcwd="${1-}" i n own t0 nt any_own=0 all_t0=1
  CIS_MODE=superset; CIS_WHY=""; CIS_DIR=""; CIS_TOP=""
  if [ "${CTR_STAGE_OPAQUE:-0}" -eq 1 ]; then CIS_WHY=opaque; return 0; fi
  if _ctr_has_loop "${_CTR_TEXT-}"; then CIS_WHY=loop; return 0; fi
  nt="${#CTR_TARGETS[@]}"
  t0="${CTR_TARGETS[0]-}"
  n="${#CTR_ADD_EXACT[@]}"; i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${CTR_ADD_EXACT[$i]}" != 1 ]; then CIS_WHY=inexact-word; return 0; fi
    own="${CTR_ADD_OWNC[$i]}"
    if [ "$own" != "-" ]; then any_own=1; fi
    if [ "$own" != "$t0" ]; then all_t0=0; fi
    i=$((i + 1))
  done
  # (i) nothing in the command moves the directory and the payload cwd is a real absolute directory
  if [ "$nt" -eq 0 ] && [ "$any_own" -eq 0 ] && [ -z "${CTR_COMMIT_OWN_C-}" ] && _cis_abs_dir "$pcwd"; then
    _cis_plan_exact "$pcwd"; return 0
  fi
  if [ "$nt" -eq 1 ] && _cis_abs_dir "$t0"; then
    # (ii) every add record and the commit carry the same absolute -C
    if [ -n "${CTR_COMMIT_OWN_C-}" ] && [ "$CTR_COMMIT_OWN_C" = "$t0" ] && [ "$all_t0" -eq 1 ]; then
      _cis_plan_exact "$t0"; return 0
    fi
    # (iii) `cd <abs>` first, && joined, nothing else
    if [ "${CTR_STAGE_CD_FIRST:-0}" -eq 1 ] && [ "$any_own" -eq 0 ] && [ -z "${CTR_COMMIT_OWN_C-}" ]; then
      _cis_plan_exact "$t0"; return 0
    fi
  fi
  CIS_WHY=unproven-dir
  return 0
}

# _cis_plan_exact <dir> — the proven directory, and the toplevel the replay is valid for. A directory that is in no
# work tree cannot be replayed in: the superset.
_cis_plan_exact() {
  CIS_TOP=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || CIS_TOP=""
  if [ -z "$CIS_TOP" ]; then CIS_WHY=dir-not-root; return 0; fi
  CIS_MODE=exact; CIS_DIR="$1"
  return 0
}

# ---- build ---------------------------------------------------------------------------------------

# _cis_err_line — CIS_ERR = the first line of $_CIS_ERRF reduced to printable ASCII (every control character, U+0085,
# U+2028/2029 and bidi override is a non-ASCII byte and is dropped), capped at 200 characters. Git's own words go into
# the deny text, never into the ledger.
_cis_err_line() {
  local line=""
  CIS_ERR=""
  if [ -s "$_CIS_ERRF" ]; then
    IFS= read -r line < "$_CIS_ERRF" || true
    line=$(printf '%s' "$line" | LC_ALL=C tr -cd '\040-\176') || line=""
    CIS_ERR="${line:0:200}"
  fi
  return 0
}

# _cis_fail <why> — restore the environment, remove the workdir, report. Always returns 20 to the caller's
# `return`.
_cis_fail() {
  CIS_WHY="$1"
  cis_unexport
  if [ -n "$_CIS_WD" ] && [ "$_CIS_WD" != / ] && [ -d "$_CIS_WD" ]; then
    assert_fixture_dir "$_CIS_WD"
    rm -rf "$_CIS_WD" 2>/dev/null || true
  fi
  return 0
}

# _cis_fresh — a pristine copy of the real index and an empty quarantine, for a rebuild.
_cis_fresh() {
  assert_fixture_dir "$_CIS_WD"
  rm -rf "$_CIS_WD/objs" "$_CIS_WD/index" 2>/dev/null || return 1
  mkdir -m 700 "$_CIS_WD/objs" || return 1
  if [ -f "$_CIS_REAL_IDX" ]; then cp -p "$_CIS_REAL_IDX" "$_CIS_WD/index" 2>"$_CIS_ERRF" || return 1; fi
  return 0
}

# cis_pins_build <root> — CIS_PINS: the pin arguments, including one neutralisation per configured filter.
cis_pins_build() {
  local line k name seen=" "
  CIS_PINS=(-c core.fsmonitor=false -c core.untrackedCache=false -c core.splitIndex=false -c core.hooksPath=/dev/null)
  while IFS= read -r line; do
    k="${line%% *}"
    name="${k%.*}"
    case "$seen" in *" $name "*) continue ;; esac
    seen="$seen$name "
    CIS_PINS+=(-c "$name.clean=" -c "$name.process=" -c "$name.smudge=" -c "$name.required=false")
  done < <(git -C "${1:?}" config --get-regexp '^filter\..*\.(clean|process|smudge|required)$' 2>/dev/null || true)
  return 0
}

# _cis_add <git add args...> in <dir>: one pinned, bounded add on the sim index.
_cis_add() {  # <dir> <args...>
  local d="$1"; shift
  _cis_git_run "${CIS_PINS[@]}" -C "$d" add "$@"
}

# _cis_split_record <record index> — _CIS_OPTS and _CIS_PATHS of one add record (words before `--` that start with
# `-` are options; everything else is a path).
_cis_split_record() {
  local off="${CTR_ADD_OFF[$1]}" nw="${CTR_ADD_NW[$1]}" k=1 dd=0 w
  _CIS_OPTS=(); _CIS_PATHS=()
  while [ "$k" -lt "$nw" ]; do
    w="${CTR_ADD_ARGV[$((off + k))]}"
    if [ "$dd" -eq 1 ]; then _CIS_PATHS+=("$w")
    elif [ "$w" = -- ]; then dd=1
    else
      case "$w" in -*) _CIS_OPTS+=("$w") ;; *) _CIS_PATHS+=("$w") ;; esac
    fi
    k=$((k + 1))
  done
  return 0
}

# _cis_force_dir <record index> — the directory a force-add record's relative paths resolve against, and only when
# the command PROVES it: the record's own absolute -C, the first-cd target, or (nothing in the command moves the
# directory) the payload cwd. It must be inside the root being built, or the paths would be read from another repo.
_cis_force_dir() {
  local own="${CTR_ADD_OWNC[$1]}" nt="${#CTR_TARGETS[@]}" t0="${CTR_TARGETS[0]-}" top
  _CIS_FD=""
  if [ "$own" != "-" ]; then
    _cis_abs_dir "$own" || return 1
    _CIS_FD="$own"
  elif [ "$nt" -eq 1 ] && [ "${CTR_STAGE_CD_FIRST:-0}" -eq 1 ] && _cis_abs_dir "$t0"; then
    _CIS_FD="$t0"
  elif [ "$nt" -eq 0 ] && _cis_abs_dir "$_CIS_PCWD"; then
    _CIS_FD="$_CIS_PCWD"
  else
    return 1
  fi
  top=$(git -C "$_CIS_FD" rev-parse --show-toplevel 2>/dev/null) || return 1
  if [ "$top" != "$_CIS_ROOT" ]; then return 1; fi
  return 0
}

# _cis_fail_run — a pinned git call failed: name the cause (a bound that fired is a timeout) and keep git's line.
_cis_fail_run() {
  if _cis_is_timeout "$_CIS_RC"; then CIS_WHY=sim-timeout; else CIS_WHY="$1"; fi
  _cis_err_line
  return 0
}

# _cis_superset — fresh copy, `add -A` from the root, then `add -f -- <literal words>` for every force-add record,
# each in the directory that record PROVES (an unprovable one, or one with no literal path word, fails). Returns 0,
# or 1 with CIS_WHY / CIS_ERR set.
_cis_superset() {
  local n="${#CTR_ADD_FORCE[@]}" i=0
  if ! _cis_fresh; then CIS_WHY=fresh-failed; _cis_err_line; return 1; fi
  if ! _cis_add "$_CIS_ROOT" -A; then _cis_fail_run superset-failed; return 1; fi
  while [ "$i" -lt "$n" ]; do
    if [ "${CTR_ADD_FORCE[$i]}" = 1 ]; then
      _cis_split_record "$i"
      if [ "${CTR_ADD_LIT[$i]}" != 1 ] || [ "${#_CIS_PATHS[@]}" -eq 0 ]; then CIS_WHY=force-nonliteral; CIS_ERR=""; return 1; fi
      if ! _cis_force_dir "$i"; then CIS_WHY=force-unproven-dir; CIS_ERR=""; return 1; fi
      if ! _cis_add "$_CIS_FD" -f -- "${_CIS_PATHS[@]}"; then _cis_fail_run superset-failed; return 1; fi
    fi
    i=$((i + 1))
  done
  CIS_MODE=superset
  return 0
}

# _cis_replay — the exact replay of every add record (in text order), then the commit's own flags. Returns 0 (built),
# 10 (a trusted pathspec-missing error: git said so, in a directory the command proves) or 11 (any other failure: the
# caller rebuilds from a fresh copy with the superset). The commit step ALWAYS runs: a dry-run `add -n -A` stages
# nothing, and `add <path> && git commit -a` still records every tracked change.
_cis_replay() {
  local n="${#CTR_ADD_EXACT[@]}" i=0 rc line a
  while [ "$i" -lt "$n" ]; do
    _cis_split_record "$i"
    if [ "${#_CIS_PATHS[@]}" -gt 0 ]; then a=(add ${_CIS_OPTS[@]+"${_CIS_OPTS[@]}"} -- "${_CIS_PATHS[@]}"); else a=(add ${_CIS_OPTS[@]+"${_CIS_OPTS[@]}"}); fi
    if ! _cis_git_run "${CIS_PINS[@]}" -C "$CIS_DIR" "${a[@]}"; then
      rc=$_CIS_RC
      line=""
      IFS= read -r line < "$_CIS_ERRF" || true
      if [ "$rc" -eq 128 ]; then
        case "$line" in
          "fatal: pathspec '"*"' did not match any files") return 10 ;;
        esac
      fi
      return 11
    fi
    i=$((i + 1))
  done
  if [ "${CTR_COMMIT_ALL:-0}" -eq 1 ]; then
    if ! _cis_add "$CIS_DIR" -u; then return 11; fi
  elif [ "${_CTR_PATHSMODE:-0}" -eq 1 ] || [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then
    # the pathspec ladder: add -u -- <literal paths>, then add -u; either failing sends the caller to the superset
    if [ "${CTR_COMMIT_PATHS_LITERAL:-1}" -eq 1 ] && [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ] && _cis_add "$CIS_DIR" -u -- "${CTR_COMMIT_PATHS[@]}"; then
      return 0
    fi
    if ! _cis_add "$CIS_DIR" -u; then return 11; fi
  fi
  return 0
}

cis_build() {
  local root="$1" pcwd="${2-}" wd="${3-}" idx objs top r=0 why err
  CIS_ERR=""; CIS_WHY=""; CIS_MODE=superset; CIS_DIR=""
  _CIS_WD=""; _CIS_ROOT="$root"; _CIS_PCWD="$pcwd"
  # the plan is made once per command by the caller; without one nothing may be assumed
  if [ "$_CIS_PLANNED" -ne 1 ]; then CIS_WHY=not-planned; return 20; fi
  if [ -z "$wd" ] || [ ! -d "$wd" ]; then CIS_WHY=prepare-failed; return 20; fi
  case "$wd" in /*) ;; *) wd="$PWD/$wd" ;; esac
  _CIS_WD="$wd"
  _CIS_ERRF="$wd/err"
  assert_fixture_dir "$_CIS_ERRF"
  if ! : > "$_CIS_ERRF" 2>/dev/null; then _cis_fail prepare-failed; return 20; fi
  cis_remaining
  if [ "$CIS_REMAINING" -le 0 ]; then _cis_fail sim-timeout; return 20; fi

  CIS_MODE="$_CIS_PLAN_MODE"; CIS_WHY="$_CIS_PLAN_WHY"; CIS_DIR="$_CIS_PLAN_DIR"

  idx=$(git -C "$root" rev-parse --git-path index 2>/dev/null) || idx=""
  objs=$(git -C "$root" rev-parse --git-path objects 2>/dev/null) || objs=""
  if [ -z "$idx" ] || [ -z "$objs" ]; then _cis_fail prepare-failed; return 20; fi
  case "$idx" in /*) ;; *) idx="$root/$idx" ;; esac
  case "$objs" in /*) ;; *) objs="$root/$objs" ;; esac
  # GIT_ALTERNATE_OBJECT_DIRECTORIES is colon separated: a path holding one cannot be named in it.
  case "$objs" in *:*) _cis_fail colon-path; return 20 ;; esac
  _CIS_REAL_IDX="$idx"
  # An exact replay is only valid where the replay directory belongs to this root.
  if [ "$CIS_MODE" = exact ]; then
    top=$(git -C "$CIS_DIR" rev-parse --show-toplevel 2>/dev/null) || top=""
    if [ "$top" != "$root" ]; then CIS_MODE=superset; CIS_WHY=dir-not-root; CIS_DIR=""; fi
  fi
  cis_pins_build "$root"
  if ! mkdir -m 700 "$wd/objs" 2>/dev/null; then _cis_fail prepare-failed; return 20; fi
  assert_fixture_dir "$wd"
  if [ -f "$idx" ]; then
    if ! cp -p "$idx" "$wd/index" 2>"$_CIS_ERRF"; then
      _cis_err_line; err="$CIS_ERR"; _cis_fail copy-failed; CIS_ERR="$err"; return 20
    fi
  fi
  cis_export "$wd/index" "$wd/objs" "$objs"

  if [ "$CIS_MODE" = exact ]; then
    _cis_replay || r=$?
    case "$r" in
      0) return 0 ;;
      10)
        # git said the path does not exist in the proven directory: it cannot be scanned, so this is a failure
        # (create it in an earlier call, or fix the spelling), never an allow.
        _cis_err_line; err="$CIS_ERR"; _cis_fail pathspec-missing; CIS_ERR="$err"; return 20 ;;
      *) CIS_WHY=replay-failed ;;
    esac
  fi
  # the superset: planned, or a fall-back from a replay that could not be trusted
  if ! _cis_superset; then
    why="$CIS_WHY"; err="$CIS_ERR"
    _cis_fail "$why"; CIS_ERR="$err"
    return 20
  fi
  return 0
}
