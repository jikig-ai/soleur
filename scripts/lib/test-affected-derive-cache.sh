# shellcheck shell=bash
# test-affected-derive-cache.sh — per-record cross-run cache for the affected pre-pass derive (#9812).
#
# WHY. The `_aff_stream` walk pays one `_affected_classify` per registration (~585 records, ~150s
# measured on a contended host — the dominant cost of the local fast tier). A classify is a pure
# function of (label, argv, the derive code, and the file contents + existence probes it consults),
# so its OUTPUT can be cached across runs and validated cheaply: re-hash the files it read and re-run
# the probes it made; any drift re-derives that record only. `_diff_touches` still runs fresh per
# record — this caches selection METADATA (class + edge set), never verdicts (the twice-rejected
# suite-result memo shape, #7454 / #9804 Proposal 2).
#
# ADVISORY-ONLY. Every failure path — absent dir, unreadable/corrupt/malformed record, schema
# mismatch, unwritable filesystem, missing git — falls back to a fresh `_affected_classify` for that
# record and exits 0. `SOLEUR_AFFECTED_DERIVE_CACHE=0` disables reads and writes entirely.
#
# RECORD LAYOUT (one file per record, tab-delimited fields, atomic tmp-then-mv write):
#   schema <v>            — must equal _ADC_SCHEMA (belt: dir name + key already carry it)
#   worktree <path>       — the repo root that wrote it; a moved/renamed worktree refuses (belt)
#   cwd <path>            — the PWD at write time; records are cwd-relative, refuse a mismatch
#   label <label>         — paranoia check (the key already covers it)
#   class <class>         — _AC_CLASS verbatim (incl. unclassified)
#   suite_file <path|->   — _AC_SUITE_FILE verbatim (contract parity; the walk does not read it)
#   edge <edge>           — one per _AC_EDGES element, order preserved (anchored ^ form included)
#   read <path> <blobid>  — every file the derive consulted, with its hash-object --no-filters id
#   probe <k> <rc> <path> — every existence probe (k ∈ e/f/d), rc 0 = existed at derive time
#   end                   — trailer; a truncated record never carries it, so a cut file can never
#                         serve a PARTIAL edge set as a hit
#
# The recording state (_ADC_REC, _ADC_REC_PROBES, _ADC_REC_READS and the two shadow sets) is written
# by the runner's _affected_probe/_affected_rec_read, which live INSIDE the runner's derive span so
# the extraction harness carries them.
#
# Bash 3.2-safe: no declare -A/declare -n; eval-by-name for array indirection; no sha256sum/date -d/
# readlink -f — `git hash-object` is already a runner dependency.

# --- state -------------------------------------------------------------------------------------------
_ADC_SCHEMA="v1"
# Cache root resolved lazily on first wrapper call: <repo-root>/.soleur/cache/affected-derive/v1/.
# `.soleur/` is the repo's gitignored local-state root (.gitignore "Local state") and is per-worktree
# by construction — sibling worktrees never share records; the `worktree` field is the belt on top
# for a renamed/moved worktree.
_ADC_READY=-1        # -1 unresolved, 0 unusable (degrade), 1 usable
_ADC_ROOT=""
_ADC_DIR=""
_ADC_DIRREADY=0      # mkdir+chmod hoisted to once per process
_ADC_CODEHASH=""     # blob id of the derive-code preimage (the four files below)
_ADC_PRUNED=0        # the 30-day find sweep runs once per process, on first successful store
_ADC_NOTE=0          # at most one stderr degrade note per process
_ADC_HITS=0
_ADC_MISSES=0        # no usable record (absent/unparseable/schema/wt/label mismatch) -> fresh derive
_ADC_DERIVED=0       # record parsed but INPUT validation failed (read-hash or probe drift) -> re-derived

# Recording state — consulted by the runner's _affected_probe/_affected_rec_read while _ADC_REC=1.
# Declared here AND guarded with :- at the use site so the runner's probe wrapper works when this
# lib was never sourced (degrade-never-block, the _AFF_LIB class of contract).
_ADC_REC=0
_ADC_REC_PROBES=()
_ADC_REC_READS=()
_ADC_REC_PSET=$'\n'
_ADC_REC_RSET=$'\n'

# The derive code these records were computed by. An edit to any of them changes every record's key.
_ADC_CODEFILES=(
  scripts/test-all.sh
  scripts/lib/test-affected-paths.sh
  scripts/lib/test-relevance-paths.sh
  scripts/lib/test-affected-derive-cache.sh
)

# --- plumbing ----------------------------------------------------------------------------------------
# git calls scrub the env exactly like _aff_rd_hash: suites and hooks can export GIT_DIR/
# GIT_WORK_TREE, and a bare `git` would then operate on the WRONG repository.
_adc_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG -u GIT_CONFIG_COUNT \
      -u GIT_CONFIG_PARAMETERS -u GIT_EXTERNAL_DIFF -u GIT_DIFF_OPTS \
    git -C "$_ADC_ROOT" "$@" 2>/dev/null
}

# One degrade note per process, never a nonzero exit — the designed loudness ceiling.
_adc_note() {
  if (( _ADC_NOTE == 0 )); then
    printf '[affected-cache] %s; continuing with plain derive\n' "$1" >&2
    _ADC_NOTE=1
  fi
  return 0
}

# First-call setup: resolve the repo root, hash the derive code. Any failure leaves _ADC_READY=0 and
# the wrapper degrades to plain classify for the rest of the process — advisory, never a gate.
_adc_init() {
  if (( _ADC_READY != -1 )); then
    (( _ADC_READY == 1 ))
    return
  fi
  _ADC_READY=0
  local _r
  _r="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git rev-parse --show-toplevel 2>/dev/null)" || _r=""
  if [[ -z "$_r" || ! -d "$_r" ]]; then
    _adc_note "no repo root — cache off"
    return 1
  fi
  _ADC_ROOT="$_r"
  _ADC_DIR="$_r/.soleur/cache/affected-derive/$_ADC_SCHEMA"
  local _h="" _cf _missing=0
  for _cf in "${_ADC_CODEFILES[@]}"; do
    [[ -f "$_ADC_ROOT/$_cf" ]] || _missing=1
  done
  if (( _missing == 0 )); then
    # The runner's preimage is its EXTRACTED derive span — the same content anchors the derive
    # suites pin (_AC_CLASS="" to _affected_derive's close, plus the _affected_classify body). A
    # whole-file hash would flush all ~586 records on every unrelated runner edit (the repo's
    # most-touched file); the libs' edge declarations and the cache lib itself stay whole-file
    # because their content IS the input set. Anchor drift extracts empty and falls back to the
    # whole file — a flush, never a stale serve. Residual: helpers outside the span
    # (_affected_in_list, _affected_emit_receipt) don't flush on edit — receipt mode never caches,
    # and the in-list helper is a two-line membership test.
    local _span
    _span="$( {
      awk '/^_AC_CLASS=""$/ && !s {s=1} s {print} s && /^_affected_derive\(\) \{/ {d=1} d && /^\}$/ {exit}' "$_ADC_ROOT/scripts/test-all.sh"
      awk '/^_affected_classify\(\) \{/ {s=1} s {print} s && /^\}$/ {exit}' "$_ADC_ROOT/scripts/test-all.sh"
    } 2>/dev/null )"
    [[ -n "$_span" ]] || _span="$(cat "$_ADC_ROOT/scripts/test-all.sh" 2>/dev/null)"
    local _libfiles=( "${_ADC_CODEFILES[@]:1}" )
    _h="$( { printf '%s\n' "$_span"; cat "${_libfiles[@]/#/$_ADC_ROOT/}" 2>/dev/null; } | _adc_git hash-object --stdin )" || _h=""
  fi
  if [[ -z "$_h" ]]; then
    _adc_note "derive-code hash unavailable — cache off"
    return 1
  fi
  _ADC_CODEHASH="$_h"
  _ADC_READY=1
  return 0
}

# Key material: schema + code hash + label + length-prefixed argv. Length-prefixing removes the
# "a b"-vs-"a","b" ambiguity a delimiter-joined string would carry.
_adc_key() { # <label> <argv...> -> hex key on stdout
  local _label="$1"; shift
  local _a
  {
    printf 'schema=%s\ncode=%s\nbash=%s\nloc=%s\nlabel=%s\nargc=%d\n' \
      "$_ADC_SCHEMA" "$_ADC_CODEHASH" "$BASH_VERSION" "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" "$_label" "$#"
    for _a in "$@"; do
      printf 'argv %d:%s\n' "${#_a}" "$_a"
    done
  } | _adc_git hash-object --stdin
}

# Parse + validate + replay a record. Returns 0 on a HIT with _AC_* populated, 1 on a STRUCTURAL
# reject (unparseable, wrong schema/worktree/label, truncated — counted as a miss), 2 on an
# INPUT-DRIFT reject (a recorded read's hash changed or a recorded probe flipped — the record was
# well-formed but the world moved; counted as a re-derive).
_adc_lookup() { # <key> <label>
  local _rec="$_ADC_DIR/$1.rec" _label="$2"
  [[ -f "$_rec" ]] || return 1
  local _tag _a _b _c
  local _r_schema="" _r_wt="" _r_cwd="" _r_label="" _r_class="" _r_sf="-" _r_end=""
  local _edges=() _reads_p=() _reads_h=() _probes_k=() _probes_rc=() _probes_p=()
  while IFS=$'\t' read -r _tag _a _b _c; do
    # Content after the trailer is malformed (trailing garbage or a second appended record).
    if [[ -n "$_r_end" && -n "$_tag" ]]; then return 1; fi
    case "$_tag" in
      schema)     _r_schema="$_a" ;;
      worktree)   _r_wt="$_a" ;;
      cwd)        _r_cwd="$_a" ;;
      label)      _r_label="$_a" ;;
      class)      _r_class="$_a" ;;
      suite_file) _r_sf="$_a" ;;
      edge)       _edges+=("$_a") ;;
      read)       _reads_p+=("$_a"); _reads_h+=("$_b") ;;
      probe)      _probes_k+=("$_a"); _probes_rc+=("$_b"); _probes_p+=("$_c") ;;
      end)        _r_end=1 ;;
      "")         : ;;                     # trailing blank line
      *)          return 1 ;;              # unknown tag: malformed — miss, never trust
    esac
  done < "$_rec"
  [[ -n "$_r_end" ]] || return 1           # truncated record: never serve a partial parse as a hit
  [[ "$_r_schema" == "$_ADC_SCHEMA" ]] || return 1
  [[ "$_r_wt" == "$_ADC_ROOT" ]] || return 1
  [[ "$_r_cwd" == "$PWD" ]] || return 1    # recorded paths are cwd-relative
  [[ "$_r_label" == "$_label" ]] || return 1
  [[ -n "$_r_class" ]] || return 1
  # Re-hash every recorded read in ONE fork; a count mismatch under-matches (CR/NL-smuggled path)
  # and any id drift means the file changed. Either way: miss, re-derive.
  if (( ${#_reads_p[@]} > 0 )); then
    local _out _h _n=0
    _out="$(printf '%s\n' "${_reads_p[@]}" | _adc_git hash-object --no-filters --stdin-paths)" || return 2
    while IFS= read -r _h; do
      (( _n < ${#_reads_h[@]} )) || return 2
      [[ "$_h" == "${_reads_h[$_n]}" ]] || return 2
      _n=$((_n + 1))
    done <<< "$_out"
    (( _n == ${#_reads_p[@]} )) || return 2
  fi
  # Re-run every recorded probe; a flipped outcome (a file created where a miss was recorded, or a
  # delete where a hit was) invalidates the record.
  local _i _prc
  for (( _i=0; _i<${#_probes_p[@]}; _i++ )); do
    _prc=2
    case "${_probes_k[$_i]}" in
      e) [[ -e "${_probes_p[$_i]}" ]] && _prc=0 || _prc=1 ;;
      f) [[ -f "${_probes_p[$_i]}" ]] && _prc=0 || _prc=1 ;;
      d) [[ -d "${_probes_p[$_i]}" ]] && _prc=0 || _prc=1 ;;
      *) return 1 ;;
    esac
    [[ "$_prc" == "${_probes_rc[$_i]}" ]] || return 2
  done
  # Replay: class + ordered edges verbatim, shadow set rebuilt through the same newline-bracketed
  # idiom _affected_resolve_edges uses, suite_file restored (never left stale from a prior record).
  _AC_CLASS="$_r_class"
  _AC_EDGES=()
  local _e _nl=$'\n'
  _AC_ESET="$_nl"
  for _e in ${_edges[@]+"${_edges[@]}"}; do
    case "$_e" in *"$_nl"*) continue ;; esac
    _AC_EDGES+=("$_e")
    _AC_ESET+="${_e}${_nl}"
  done
  case "$_r_sf" in -|"") _AC_SUITE_FILE="" ;; *) _AC_SUITE_FILE="$_r_sf" ;; esac
  return 0
}

# Write the record for the just-computed _AC_* state + the _ADC_REC_* instrumentation. Every
# failure is silent-advisory: the derived result already stands, the cache simply stays cold.
_adc_store() { # <label> <key>
  local _label="$1" _key="$2"
  local _rec="$_ADC_DIR/$_key.rec" _tmp="$_ADC_DIR/.$_key.tmp.$$"
  local _p
  # A path carrying a tab or newline would misparse on read — refuse the whole record rather than
  # write a subset (an under-recorded input set would serve a stale hit later). A symlinked read
  # hashes the LINK TEXT via --stdin-paths, not the target's bytes — a target-content change would
  # escape invalidation, so those records are refused too.
  for _p in ${_AC_EDGES[@]+"${_AC_EDGES[@]}"} ${_ADC_REC_READS[@]+"${_ADC_REC_READS[@]}"}; do
    case "$_p" in *$'\t'*|*$'\n'*) return 0 ;; esac
    [[ -L "$_p" ]] && return 0
  done
  for _p in ${_ADC_REC_PROBES[@]+"${_ADC_REC_PROBES[@]}"}; do
    case "$_p" in *$'\n'*) return 0 ;; esac
    # The entry is kind<TAB>rc<TAB>path — a tab inside the PATH would misparse on read.
    local _pp_rest="${_p#*$'\t'}"
    case "${_pp_rest#*$'\t'}" in *$'\t'*) return 0 ;; esac
  done
  # Writability first, once per process: hashing below is wasted work when the dir won't take
  # the file, and mkdir+chmod per record is ~1200 hoisted forks across a cold pass.
  if (( _ADC_DIRREADY == 0 )); then
    if ! mkdir -p "$_ADC_DIR" 2>/dev/null; then
      _adc_note "cache dir unwritable ($_ADC_DIR)"
      return 0
    fi
    chmod 700 "$_ADC_DIR" 2>/dev/null || true
    _ADC_DIRREADY=1
  fi
  # Hash the read set in one fork — the same command the validator re-runs. TOCTOU: the derive
  # read these bytes before this hash runs, so a mid-flight edit mints a self-consistent stale
  # record until the file changes again — bounded to the per-record window; hashing at read time
  # would cost the per-file forks the design exists to avoid.
  local _rhashes=""
  if (( ${#_ADC_REC_READS[@]} > 0 )); then
    _rhashes="$(printf '%s\n' "${_ADC_REC_READS[@]}" | _adc_git hash-object --no-filters --stdin-paths)" || return 0
    # A short hash output would mint a record that under-records its inputs — refuse it.
    local _rh_n
    _rh_n=$(printf '%s\n' "$_rhashes" | wc -l | tr -d ' ')
    (( _rh_n == ${#_ADC_REC_READS[@]} )) || return 0
  fi
  {
    printf 'schema\t%s\n' "$_ADC_SCHEMA"
    printf 'worktree\t%s\n' "$_ADC_ROOT"
    printf 'cwd\t%s\n' "$PWD"
    printf 'label\t%s\n' "$_label"
    printf 'class\t%s\n' "$_AC_CLASS"
    printf 'suite_file\t%s\n' "${_AC_SUITE_FILE:--}"
    for _p in ${_AC_EDGES[@]+"${_AC_EDGES[@]}"}; do
      printf 'edge\t%s\n' "$_p"
    done
    local _i=0
    while IFS= read -r _h && (( _i < ${#_ADC_REC_READS[@]} )); do
      printf 'read\t%s\t%s\n' "${_ADC_REC_READS[$_i]}" "$_h"
      _i=$((_i + 1))
    done <<< "$_rhashes"
    for _p in ${_ADC_REC_PROBES[@]+"${_ADC_REC_PROBES[@]}"}; do
      printf 'probe\t%s\n' "$_p"
    done
    printf 'end\n'
  } > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; _adc_note "record write failed"; return 0; }
  chmod 600 "$_tmp" 2>/dev/null || true
  mv "$_tmp" "$_rec" 2>/dev/null || { rm -f "$_tmp"; _adc_note "record commit failed"; return 0; }
  # Bounded churn, once per process: sweep the schema root (old vN/ dirs too, so a schema bump
  # doesn't leave unreachable records behind) — records stale by 30 days, and tmp orphans from
  # killed runs by 1 day (younger ones could be a live sibling's in-flight write).
  if (( _ADC_PRUNED == 0 )); then
    _ADC_PRUNED=1
    find "${_ADC_DIR%/*}" -name '*.rec' -mtime +30 -delete -o -name '.*.tmp.*' -mtime +0 -delete 2>/dev/null || true
  fi
  return 0
}

# The walk-facing wrapper: cache-aware stand-in for _affected_classify. Same output contract —
# _AC_CLASS / _AC_EDGES / _AC_ESET / _AC_SUITE_FILE — either replayed from a validated record or
# freshly derived and stored. The runner calls this ONLY on the selection-walk arm (TEST_GROUP=all,
# _PRINT_AFFECTED=0); receipt mode derives fresh because its edge set is deliberately partial.
_affected_classify_cached() { # <label> <argv...>
  local _label="$1"; shift
  # Belt guard mirroring the dispatch contract: a future call site outside the all-group
  # selection walk must not mint records a different context replays (group-scoped class
  # values and receipt-mode partial edge sets are not cacheable shapes).
  if [[ "${SOLEUR_AFFECTED_DERIVE_CACHE:-1}" == "0" ]] \
    || [[ "${TEST_GROUP:-all}" != "all" ]] || (( ${_PRINT_AFFECTED:-0} == 1 )) \
    || ! _adc_init; then
    _affected_classify "$_label" "$@"
    return
  fi
  local _key="" _lk=0
  _key="$(_adc_key "$_label" "$@")" || _key=""
  if [[ -n "$_key" && -f "$_ADC_DIR/$_key.rec" ]]; then
    if _adc_lookup "$_key" "$_label"; then
      _ADC_HITS=$((_ADC_HITS + 1))
      return 0
    else
      _lk=$?
    fi
    if (( _lk == 2 )); then
      _ADC_DERIVED=$((_ADC_DERIVED + 1))
    else
      _ADC_MISSES=$((_ADC_MISSES + 1))
    fi
  else
    _ADC_MISSES=$((_ADC_MISSES + 1))
  fi
  _ADC_REC=1
  _ADC_REC_PROBES=()
  _ADC_REC_READS=()
  _ADC_REC_PSET=$'\n'
  _ADC_REC_RSET=$'\n'
  _affected_classify "$_label" "$@"
  _ADC_REC=0
  if [[ -n "$_key" ]]; then
    _adc_store "$_label" "$_key"
  fi
  return 0
}
