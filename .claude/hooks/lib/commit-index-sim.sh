# shellcheck shell=bash
# shellcheck disable=SC2034  # the CIS_* results are read by the sourcing hook
# commit-index-sim.sh — build the index a Bash command's OWN staging will leave behind, so a scan can read it
# BEFORE the command runs (#10696).
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
#   cis_plan <payload-cwd>            pure over the CTR_* facts (commit-target-roots.sh) plus CIS_ROOT_COUNT.
#                                     Sets CIS_MODE (exact | superset), CIS_WHY (why the superset, else empty)
#                                     and, for exact, CIS_DIR (the directory the replay runs in).
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
#                                     scan the caller runs inside the window. 30 s, tracked with $SECONDS.
#   cis_bound_init                    picks the bound: timeout, gtimeout, or `perl -e 'alarm N; exec @ARGV'`;
#                                     CIS_BOUND_KIND is none when no tool exists (the caller must DENY).
#
# DOCUMENTED INPUTS (read, never written): the CTR_* staging facts, _CTR_TEXT (the command text), CIS_ROOT_COUNT
# (how many repositories the caller scans; the replay is exact only for exactly one), and CIS_DEADLINE_SECONDS.
#
# CIS_DEADLINE_SECONDS is a TEST-ONLY knob and can only LOWER the ceiling: a value of ^[0-9]{1,9}$ becomes
# min(30, value); anything else is ignored; 0 means no time remains, so the first call fails. It cannot raise
# the ceiling, so a hostile value can only cause a deny, never an allow.
#
# THE REPLAY. Exact replay runs the command's own add records, in text order, as `git -C <dir> add <validated
# options> -- <paths>` and then the commit's own flags (`-a`/`-p` -> add -u; a pathspec -> add -u -- <literal
# paths>, then add -u, then add -A only if both fail). It is used only when ALL of these hold: exactly one
# scanned root; every add record exact; nothing opaque; no loop or function in the text; and the directory is
# PROVEN: (i) the command names no cd / pushd / -C and the payload cwd is an absolute existing directory, or
# (ii) every add record and the commit carry the same absolute existing -C, or (iii) `cd <abs>` is the first
# record followed only by &&-joined git records. Everything else uses the SUPERSET: `git add -A`, plus
# `git add -f -- <literal words>` for any force-add record (a non-literal force-add fails: CIS_WHY
# force-nonliteral). A replay failure is classified by git's own words, under LC_ALL=C: rc 128 and a first line
# matching `fatal: pathspec '...' did not match any files` is the trusted pathspec-missing error (return 10);
# ANY other failure (timeout, ENOSPC, another exit 128) abandons the exact replay and rebuilds from a FRESH copy
# with the superset. A failed superset is a failure (return 20), never an allow.
#
# EVERY replay git call carries the same pins (CTO row 18): `-c core.fsmonitor=false -c core.untrackedCache=false
# -c core.splitIndex=false`, plus `-c filter.<n>.clean= -c filter.<n>.process= -c filter.<n>.smudge= -c
# filter.<n>.required=false` for each configured filter, LC_ALL=C, and the verb is always the literal `add`
# (an alias cannot hijack it). The replay forwards NOTHING from the command except validated options and paths.
# `git add` on a temp index would otherwise run configured clean filters at hook time, write a sharedindex.* into
# the REAL git directory under core.splitIndex, and start an fsmonitor daemon. The sim therefore scans the RAW
# bytes: a clean filter or Git LFS may record bytes the sim never saw (a named residual). The read-only prepare
# calls (rev-parse, config) are not pinned and not bounded: they write nothing and run no filter.
#
# RULES THIS FILE FOLLOWS (a hook that dies here fails OPEN): it calls no mktemp (the caller allocates the
# temp directory and owns its trap), sets no trap, never calls `exit` (one exception: the canonical
# assert_fixture_dir guard below `exit 2`s on an empty or relative directory, which is a BLOCKING hook error, so it
# fails closed, and cannot fire on a workdir this file has just made absolute), and is never called inside `$(...)` (a
# call there loses the exports). Every step ends in `|| return` / an explicit check, because a bare failing
# command under the hook's `set -e` exits 1, which the harness treats as non-blocking. bash 3.2: no mapfile,
# no declare -n, no associative arrays; an empty array is read as ${a[@]+"${a[@]}"}. It needs `cp`, `mkdir`,
# `rm`, `date`, and one of timeout / gtimeout / perl.
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
CIS_ROOT_COUNT=1
CIS_REMAINING=0
CIS_BOUND_KIND=""
CIS_DEADLINE_EPOCH=""
_CIS_T0=""
_CIS_LIMIT=30
_CIS_PINS=()
_CIS_ERRF=""
_CIS_RC=0
_CIS_ALL_RAN=0
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

cis_clock_start() {
  local v="${CIS_DEADLINE_SECONDS-}" now
  _CIS_LIMIT=30
  case "$v" in
    ''|*[!0-9]*) : ;;
    *)
      if [ "${#v}" -le 9 ]; then
        v=$((10#$v))
        if [ "$v" -lt 30 ]; then _CIS_LIMIT=$v; fi
      fi ;;
  esac
  _CIS_T0=$SECONDS
  CIS_DEADLINE_EPOCH=""
  if now=$(date +%s 2>/dev/null); then
    case "$now" in ''|*[!0-9]*) : ;; *) CIS_DEADLINE_EPOCH=$((now + _CIS_LIMIT)) ;; esac
  fi
  return 0
}

# cis_remaining — CIS_REMAINING = whole seconds left (<= 0: none).
cis_remaining() {
  if [ -z "$_CIS_T0" ]; then cis_clock_start; fi
  CIS_REMAINING=$((_CIS_LIMIT - (SECONDS - _CIS_T0)))
  return 0
}

cis_bound_init() {
  if command -v timeout >/dev/null 2>&1; then CIS_BOUND_KIND=timeout
  elif command -v gtimeout >/dev/null 2>&1; then CIS_BOUND_KIND=gtimeout
  elif command -v perl >/dev/null 2>&1; then CIS_BOUND_KIND=perl
  else CIS_BOUND_KIND=none
  fi
  return 0
}

# _cis_git_run <git args...> — one pinned, bounded git call. stdout is dropped; stderr goes to $_CIS_ERRF.
# Returns git's status (124 / 137 / 142: the bound expired). Call it in an `if`.
_cis_git_run() {
  local rc=0
  cis_remaining
  if [ "$CIS_REMAINING" -le 0 ]; then
    _CIS_RC=124
    assert_fixture_dir "$_CIS_ERRF"
    : > "$_CIS_ERRF"
    return 124
  fi
  case "$CIS_BOUND_KIND" in
    timeout) LC_ALL=C timeout -k 2 "$CIS_REMAINING" git "$@" >/dev/null 2>"$_CIS_ERRF" || rc=$? ;;
    gtimeout) LC_ALL=C gtimeout -k 2 "$CIS_REMAINING" git "$@" >/dev/null 2>"$_CIS_ERRF" || rc=$? ;;
    perl) LC_ALL=C perl -e 'alarm shift; exec @ARGV' "$CIS_REMAINING" git "$@" >/dev/null 2>"$_CIS_ERRF" || rc=$? ;;
    *) rc=125 ;;
  esac
  _CIS_RC=$rc
  return "$rc"
}

# _cis_is_timeout <rc>
_cis_is_timeout() { case "$1" in 124|137|142) return 0 ;; esac; return 1; }

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

# cis_plan <payload-cwd> — exact only when every condition holds; the first that fails names the cause.
cis_plan() {
  local pcwd="${1-}" m ex own t0 nt any_own=0
  CIS_MODE=superset; CIS_WHY=""; CIS_DIR=""
  if [ "${CTR_STAGE_OPAQUE:-0}" -eq 1 ]; then CIS_WHY=opaque; return 0; fi
  if [ "${CIS_ROOT_COUNT:-1}" -ne 1 ]; then CIS_WHY=roots; return 0; fi
  case "${_CTR_TEXT-}" in
    *'for '*|*'while '*|*'until '*|*'select '*|*'()'*|*'function '*) CIS_WHY=loop; return 0 ;;
  esac
  for m in ${CTR_ADD_META[@]+"${CTR_ADD_META[@]}"}; do
    ex="${m#*:}"; ex="${ex%%:*}"
    if [ "$ex" != 1 ]; then CIS_WHY=inexact-word; return 0; fi
    own="${m#*:*:*:*:*:}"
    if [ "$own" != "-" ]; then any_own=1; fi
  done
  nt="${#CTR_TARGETS[@]}"
  t0="${CTR_TARGETS[0]-}"
  # (i) nothing in the command moves the directory and the payload cwd is a real absolute directory
  if [ "$nt" -eq 0 ] && [ "$any_own" -eq 0 ] && [ -z "${CTR_COMMIT_OWN_C-}" ] && _cis_abs_dir "$pcwd"; then
    CIS_MODE=exact; CIS_DIR="$pcwd"; return 0
  fi
  if [ "$nt" -eq 1 ] && _cis_abs_dir "$t0"; then
    # (ii) every add record and the commit carry the same absolute -C
    if [ -n "${CTR_COMMIT_OWN_C-}" ] && [ "$CTR_COMMIT_OWN_C" = "$t0" ]; then
      ex=1
      for m in ${CTR_ADD_META[@]+"${CTR_ADD_META[@]}"}; do
        own="${m#*:*:*:*:*:}"
        if [ "$own" != "$t0" ]; then ex=0; fi
      done
      if [ "$ex" -eq 1 ]; then CIS_MODE=exact; CIS_DIR="$t0"; return 0; fi
    fi
    # (iii) `cd <abs>` first, && joined, nothing else
    if [ "${CTR_STAGE_CD_FIRST:-0}" -eq 1 ] && [ "$any_own" -eq 0 ] && [ -z "${CTR_COMMIT_OWN_C-}" ]; then
      CIS_MODE=exact; CIS_DIR="$t0"; return 0
    fi
  fi
  CIS_WHY=unproven-dir
  return 0
}

# ---- build ---------------------------------------------------------------------------------------

# _cis_err_line — CIS_ERR = the first line of $_CIS_ERRF with control characters and U+2028 / U+2029 removed,
# capped at 200 characters. Git's own words go into the deny text, never into the ledger.
_cis_err_line() {
  local line=""
  CIS_ERR=""
  if [ -s "$_CIS_ERRF" ]; then
    IFS= read -r line < "$_CIS_ERRF" || true
    line="${line//$'\xe2\x80\xa8'/}"
    line="${line//$'\xe2\x80\xa9'/}"
    line=$(printf '%s' "$line" | LC_ALL=C tr -d '\000-\037\177') || line=""
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

# _cis_pins_build <root> — the pin arguments, including one neutralisation per configured filter.
_cis_pins_build() {
  local line k name seen=" "
  _CIS_PINS=(-c core.fsmonitor=false -c core.untrackedCache=false -c core.splitIndex=false)
  while IFS= read -r line; do
    k="${line%% *}"
    name="${k%.*}"
    case "$seen" in *" $name "*) continue ;; esac
    seen="$seen$name "
    _CIS_PINS+=(-c "$name.clean=" -c "$name.process=" -c "$name.smudge=" -c "$name.required=false")
  done < <(git -C "${1:?}" config --get-regexp '^filter\..*\.(clean|process|smudge|required)$' 2>/dev/null || true)
  return 0
}

# _cis_add <git add args...> in <dir>: one pinned, bounded add on the sim index.
_cis_add() {  # <dir> <args...>
  local d="$1"; shift
  _cis_git_run "${_CIS_PINS[@]}" -C "$d" add "$@"
}

# _cis_superset — fresh copy, `add -A` from the root, then `add -f -- <literal words>` for every force-add
# record. Returns 0, or 1 with CIS_WHY / CIS_ERR set.
_cis_superset() {
  local m i=0 off=0 nw force lit k w fd dd paths rc=0
  if ! _cis_fresh; then CIS_WHY=copy-failed; _cis_err_line; return 1; fi
  if ! _cis_add "$_CIS_ROOT" -A; then
    rc=$_CIS_RC
    if _cis_is_timeout "$rc"; then CIS_WHY=sim-timeout; else CIS_WHY=superset-failed; fi
    _cis_err_line; return 1
  fi
  _CIS_ALL_RAN=1
  fd="$_CIS_ROOT"; if _cis_abs_dir "$_CIS_PCWD"; then fd="$_CIS_PCWD"; fi
  for m in ${CTR_ADD_META[@]+"${CTR_ADD_META[@]}"}; do
    force="${m#*:*:}"; force="${force%%:*}"
    lit="${m#*:*:*:}"; lit="${lit%%:*}"
    nw="${m#*:*:*:*:}"; nw="${nw%%:*}"
    if [ "$force" = 1 ]; then
      if [ "$lit" != 1 ]; then CIS_WHY="force-nonliteral"; CIS_ERR=""; return 1; fi
      paths=(); dd=0; k=1
      while [ "$k" -lt "$nw" ]; do
        w="${CTR_ADD_ARGV[$((off + k))]}"
        if [ "$dd" -eq 1 ]; then paths+=("$w")
        elif [ "$w" = -- ]; then dd=1
        else case "$w" in -*) : ;; *) paths+=("$w") ;; esac
        fi
        k=$((k + 1))
      done
      if [ "${#paths[@]}" -gt 0 ]; then
        if ! _cis_add "$fd" -f -- "${paths[@]}"; then
          rc=$_CIS_RC
          if _cis_is_timeout "$rc"; then CIS_WHY=sim-timeout; else CIS_WHY=superset-failed; fi
          _cis_err_line; return 1
        fi
      fi
    fi
    off=$((off + nw)); i=$((i + 1))
  done
  CIS_MODE=superset
  return 0
}

# _cis_replay — the exact replay of every add record, then the commit step. Returns 0 (built), 10 (a trusted
# pathspec-missing error: the caller builds the superset instead) or 11 (any other failure: ditto, from a fresh copy).
_cis_replay() {
  local m off=0 nw k w dd opts paths rc line a has_all_opt
  for m in ${CTR_ADD_META[@]+"${CTR_ADD_META[@]}"}; do
    nw="${m#*:*:*:*:}"; nw="${nw%%:*}"
    opts=(); paths=(); dd=0; has_all_opt=0; k=1
    while [ "$k" -lt "$nw" ]; do
      w="${CTR_ADD_ARGV[$((off + k))]}"
      if [ "$dd" -eq 1 ]; then paths+=("$w")
      elif [ "$w" = -- ]; then dd=1
      else
        case "$w" in
          -*)
            opts+=("$w")
            case "$w" in -A|--all|-[!-]*A*) has_all_opt=1 ;; esac ;;
          *) paths+=("$w") ;;
        esac
      fi
      k=$((k + 1))
    done
    if [ "${#paths[@]}" -gt 0 ]; then a=(add ${opts[@]+"${opts[@]}"} -- "${paths[@]}"); else a=(add ${opts[@]+"${opts[@]}"}); fi
    if ! _cis_git_run "${_CIS_PINS[@]}" -C "$CIS_DIR" "${a[@]}"; then
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
    # `add -A` with no pathspec is the whole tree: the commit step has nothing left to add
    if [ "$has_all_opt" -eq 1 ] && [ "${#paths[@]}" -eq 0 ]; then _CIS_ALL_RAN=1; fi
    off=$((off + nw))
  done
  if ! _cis_commit_step; then return 11; fi
  return 0
}

# _cis_commit_step — the commit's own flags, unless add -A already ran. Returns non-zero when a step failed.
_cis_commit_step() {
  if [ "$_CIS_ALL_RAN" -eq 1 ]; then return 0; fi
  if [ "${CTR_COMMIT_ALL:-0}" -eq 1 ]; then
    if _cis_add "$CIS_DIR" -u; then return 0; fi
    return 1
  fi
  if [ "${_CTR_PATHSMODE:-0}" -eq 1 ] || [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then
    if [ "${CTR_COMMIT_PATHS_LITERAL:-1}" -eq 1 ] && [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then
      if _cis_add "$CIS_DIR" -u -- "${CTR_COMMIT_PATHS[@]}"; then return 0; fi
    fi
    if _cis_add "$CIS_DIR" -u; then return 0; fi
    return 1
  fi
  return 0
}

cis_build() {
  local root="$1" pcwd="${2-}" wd="${3-}" idx objs top r=0 rc=0 why err
  CIS_ERR=""; CIS_WHY=""; CIS_MODE=superset; CIS_DIR=""
  _CIS_ALL_RAN=0; _CIS_WD=""; _CIS_ROOT="$root"; _CIS_PCWD="$pcwd"
  if [ -z "$wd" ] || [ ! -d "$wd" ]; then CIS_WHY=prepare-failed; return 20; fi
  case "$wd" in /*) ;; *) wd="$PWD/$wd" ;; esac
  _CIS_WD="$wd"
  _CIS_ERRF="$wd/err"
  assert_fixture_dir "$_CIS_ERRF"
  if ! : > "$_CIS_ERRF" 2>/dev/null; then _cis_fail prepare-failed; return 20; fi
  cis_bound_init
  if [ "$CIS_BOUND_KIND" = none ]; then _cis_fail no-bound; return 20; fi
  cis_remaining
  if [ "$CIS_REMAINING" -le 0 ]; then _cis_fail sim-timeout; return 20; fi

  cis_plan "$pcwd"

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
  _cis_pins_build "$root"
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
      10) CIS_WHY=pathspec-missing; rc=10 ;;
      *) CIS_WHY=replay-failed ;;
    esac
  fi
  # the superset: planned, or a fall-back from a replay that could not be trusted
  if ! _cis_superset; then
    why="$CIS_WHY"; err="$CIS_ERR"
    _cis_fail "$why"; CIS_ERR="$err"
    return 20
  fi
  return "$rc"
}
