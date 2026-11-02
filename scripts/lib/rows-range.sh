# shellcheck shell=bash
# rows-range.sh — the shared `--rows A-B` arm-split preamble (#11647, S2).
#
# THE CONTRACT. A battery that is too long for one suite registration splits
# into `-<letter>` arms, each carrying a `--rows A-B` flag over the battery's
# declared gated sites. Every gated call site routes through `in_range` in
# file order — skipped sites still reach the gate so the sequence counter
# always reaches the declared total regardless of which arm runs — and the
# end-of-file gate reconciles reach against dispatch.
#
# This file exists because the preamble used to live as four near-copies with
# three real semantic variants (repeat-flag handling, ordinal enforcement,
# counter names, bounds-check placement). The extraction normalizes to the
# 3-of-4 shape: a REPEATED --rows refuses exit 2 (the tiling extractor would
# otherwise assert a coverage the battery ignores — the coverage hole
# lint-orphan's repeat-refusal comment named), bounds check is post-loop
# gated on the flag having been seen, and counters are _site_seq/EXECUTED.
#
# API (source this file, then):
#
#   rows_parse_args "$@"
#       Parse argv. Reads the caller's file-scope DECLARED_TOTAL — which stays
#       declared in each battery file (the totality guard reads it through
#       _DECL_READ_RE and DECL-PREFIX-READER pins the literal decl line
#       byte-for-byte). Sets ROWS_LO, ROWS_HI (0 = unset = all declared),
#       _seen_rows_flag, and zeroes _site_seq/EXECUTED/_ROWS_MARK. Every
#       refusal is ERROR: + exit 2 — malformed spec, repeated flag, unknown
#       argument, out-of-bounds range.
#
#   in_range [ordinal]
#       Call once per gated site, in file order. Increments _site_seq; when
#       the optional ordinal argument is passed it must equal _site_seq or the
#       call is FATAL(harness) exit 2 (a duplicated or reordered call site
#       would silently re-map the registered ranges). In range — ROWS_HI == 0
#       means all — increments EXECUTED and returns 0; out of range returns 1.
#       Under `set -u` a bare `in_range` call is legal (the ordinal is read
#       through ${1-}).
#
#   rows_gate_floor
#       EOF reconciliation, common to every battery: _site_seq must equal the
#       declared total (a site added or removed without bumping the decl and
#       re-splitting the ranges FATALs), EXECUTED must equal the in-range
#       count (unflagged → all declared, else HI-LO+1) and be >= 1 (a range
#       covering no declared site is vacuous). All FATAL + exit 2 — shape
#       accounting, not verdicts. Battery-specific extras stay battery-side
#       (verdict conservation, census counts, per-driver run sums,
#       unconditional-assertion floors). When the battery declares the S4
#       knobs below, also floors every DISPATCHED block's case count.
#
# OPTIONAL KNOBS (set before rows_parse_args / in_range):
#
#   ROWS_UNIT          — the noun error text uses for the gated thing:
#                        "rows" (default), "sites", "blocks".
#   ROWS_COUNT_VAR     — name of a file-global integer counter that in_range
#                        snapshots at every gate call; the difference between
#                        successive marks attributes the ticks between them to
#                        the block that ran them.
#   ROWS_BLOCK_CASES   — an indexed array, one declared MINIMUM per gated
#                        ordinal (index = ordinal-1); rows_gate_floor FATALs
#                        exit 2 naming the ordinal on any dispatched block
#                        whose marked delta is below its declared floor. `>=`
#                        floors, never `==` — loop-driven blocks declare their
#                        structural minimum so legitimate case growth cannot
#                        false-fire.
#
# CENSUS CONSTRAINTS — load-bearing, do not relax:
#
#   * This file must never carry a line-start `DECLARED_TOTAL=` spelling —
#     the Direction-2 census (scripts-shard-totality.test.sh _DECL_COUNT_RE)
#     is repo-wide and would count it as a --rows contract no tiling arm
#     reaches. The lib READS the caller's variable; it never declares one.
#   * This file must never carry a `--rows <digits>-<digits>` literal outside
#     a comment — the Direction-1 literal census counts that pattern across
#     test-all.sh + every shell file in scripts/lib and requires the count to
#     equal the extracted registrations. Prose spells `--rows A-B` (A-B is
#     non-digit and invisible to the census regex).
#
# Owned globals: ROWS_LO, ROWS_HI, _seen_rows_flag, _site_seq, EXECUTED,
# _ROWS_MARK, _ROWS_* internals. Bash 3.2-safe: no namerefs, no mapfile, no
# `declare -A`, no `[[ -v ]]` — the counters are plain integers and the mark
# array is indexed.

rows_parse_args() {
  ROWS_LO=1
  ROWS_HI=0          # 0 = unset, meaning "all declared"
  _seen_rows_flag=0
  _site_seq=0
  EXECUTED=0
  _ROWS_MARK=()
  if [[ -z "${DECLARED_TOTAL:-}" || ! "$DECLARED_TOTAL" =~ ^[0123456789]+$ ]]; then
    echo "ERROR(harness): a positive-integer DECLARED_TOTAL must be declared before rows_parse_args runs — each battery pins its own declared count; the lib only reads it" >&2
    exit 2
  fi
  DECLARED_TOTAL=$((10#$DECLARED_TOTAL))   # 10# pins decimal: a 0N declaration is octal-ambiguous to arithmetic, which would silently skip the gate
  if (( DECLARED_TOTAL < 1 )); then
    echo "ERROR(harness): a positive-integer DECLARED_TOTAL must be declared before rows_parse_args runs — each battery pins its own declared count; the lib only reads it" >&2
    exit 2
  fi
  while (( $# )); do
    case "$1" in
      --rows)
        shift
        if [[ ! "${1:-}" =~ ^[0123456789]{1,9}-[0123456789]{1,9}$ ]]; then
          echo "ERROR: --rows requires a decimal range A-B (got '${1:-<missing>}')" >&2
          exit 2
        fi
        if (( _seen_rows_flag == 1 )); then
          echo "ERROR: --rows given twice — a range must be stated once (the tiling extractor would then assert a coverage the battery ignores)" >&2
          exit 2
        fi
        _seen_rows_flag=1
        ROWS_LO=$((10#${1%-*})); ROWS_HI=$((10#${1#*-}))
        ;;
      *)
        echo "ERROR: unknown argument '$1' (usage: $0 [--rows A-B])" >&2
        exit 2
        ;;
    esac
    shift
  done
  # Unconditional bounds, gated on the flag having been given: 1 <= A <= B <=
  # the declared total. The no-flag state ROWS_HI=0 is unreachable as a flag
  # value because HI >= LO >= 1, so a passed "0-0"/"N-0" can never silently
  # decode into "all".
  if (( _seen_rows_flag == 1 )) \
     && ! (( 1 <= ROWS_LO && ROWS_LO <= ROWS_HI && ROWS_HI <= DECLARED_TOTAL )); then
    echo "ERROR: --rows ${ROWS_LO}-${ROWS_HI} is out of bounds: need 1 <= A <= B <= ${DECLARED_TOTAL} declared ${ROWS_UNIT:-rows}." >&2
    exit 2
  fi
}

in_range() {
  local _ord="${1-}"
  _site_seq=$(( _site_seq + 1 ))
  if [[ -n "$_ord" && ! "$_ord" =~ ^[0123456789]+$ ]]; then
    echo "FATAL(harness): in_range ordinal '${_ord}' is not a non-negative integer — the ordinal form pins a gated site to its declared position" >&2
    exit 2
  fi
  [[ -n "$_ord" ]] && _ord=$((10#${_ord}))
  if [[ -n "$_ord" ]] && (( _ord != _site_seq )); then
    echo "FATAL(harness): row ${_ord} reached the range gate as site ${_site_seq} — a duplicated or reordered call site would silently re-map the registered ranges" >&2
    exit 2
  fi
  # S4: snapshot the caller's counter at this gate so rows_gate_floor can
  # floor each dispatched block's marked delta individually. Skipped blocks
  # mark too — a skipped block's delta is zero and is never floored.
  if [[ -z "${ROWS_COUNT_VAR:-}" && "$(declare -p ROWS_BLOCK_CASES 2>/dev/null)" == "declare -a "* ]]; then
    printf 'FATAL: ROWS_BLOCK_CASES is declared but ROWS_COUNT_VAR is unset — a floor map without its counter silently disables the per-block floor\n' >&2
    exit 2
  fi
  if [[ -n "${ROWS_COUNT_VAR:-}" ]]; then
    _ROWS_MARK[_site_seq]="${!ROWS_COUNT_VAR:-0}"
  fi
  if (( ROWS_HI == 0 )) || (( ROWS_LO <= _site_seq && _site_seq <= ROWS_HI )); then
    EXECUTED=$(( EXECUTED + 1 ))
    return 0
  fi
  return 1
}

rows_gate_floor() {
  local _expected _i _lo _hi _actual _declared
  if (( _site_seq != DECLARED_TOTAL )); then
    printf 'FATAL: range gate — %d gated %s reached in_range, expected %d — a gated site was added or deleted without bumping the declared total and re-splitting the registered --rows ranges\n' \
      "$_site_seq" "${ROWS_UNIT:-rows}" "$DECLARED_TOTAL" >&2
    exit 2
  fi
  if (( ROWS_HI == 0 )); then
    _expected=$DECLARED_TOTAL
  else
    _expected=$(( ROWS_HI - ROWS_LO + 1 ))
  fi
  if (( EXECUTED != _expected || EXECUTED < 1 )); then
    printf 'FATAL: range accounting — %d %s executed, expected %d in range %s-%s. The battery did not run its declared range to completion.\n' \
      "$EXECUTED" "${ROWS_UNIT:-rows}" "$_expected" "$ROWS_LO" "$ROWS_HI" >&2
    exit 2
  fi
  # S4 — per-block declared case floors. ROWS_COUNT_VAR names the counter
  # in_range snapshots — its ticks MUST live inside the dispatched blocks
  # (an unconditional tick lands in the next block's delta and can mask a
  # hollow); ROWS_BLOCK_CASES carries one declared minimum per
  # gated ordinal. Only DISPATCHED blocks are floored: a skipped block's
  # zero delta is legitimate on the other arms.
  if [[ -n "${ROWS_COUNT_VAR:-}" ]]; then
    if [[ "$(declare -p ROWS_BLOCK_CASES 2>/dev/null)" != "declare -a "* ]]; then
      printf 'FATAL: ROWS_COUNT_VAR is set but ROWS_BLOCK_CASES is not a declared indexed array — the per-block floor map must be spelled out beside the declared total\n' >&2
      exit 2
    fi
    if (( ${#ROWS_BLOCK_CASES[@]} != DECLARED_TOTAL )); then
      printf 'FATAL: ROWS_BLOCK_CASES carries %d declared minimum(s) but the declared total is %d — the block-case map must cover every gated ordinal\n' \
        "${#ROWS_BLOCK_CASES[@]}" "$DECLARED_TOTAL" >&2
      exit 2
    fi
    for (( _i = 1; _i <= _site_seq; _i++ )); do
      (( ROWS_HI == 0 )) || (( ROWS_LO <= _i && _i <= ROWS_HI )) || continue
      _lo="${_ROWS_MARK[_i]:-0}"
      if (( _i < _site_seq )); then
        _hi="${_ROWS_MARK[$((_i + 1))]:-0}"
      else
        _hi="${!ROWS_COUNT_VAR:-0}"
      fi
      _actual=$(( _hi - _lo ))
      _declared="${ROWS_BLOCK_CASES[$((_i - 1))]:-}"
      if ! [[ "$_declared" =~ ^[0-9]+$ ]]; then
        printf 'FATAL: ROWS_BLOCK_CASES[%d] is unset or non-numeric — the floor map must cover every ordinal 1..DECLARED_TOTAL\n' "$((_i - 1))" >&2
        exit 2
      fi
      if (( _actual < _declared )); then
        printf 'FATAL: block %d emitted %d case(s), declared minimum %d — the block was hollowed below its declared floor and a sibling cannot subsidize it\n' \
          "$_i" "$_actual" "$_declared" >&2
        exit 2
      fi
    done
  fi
}
