#!/usr/bin/env bash
# property-harness.sh -- seeded generated-input (property-style) harness for .test.sh
# suites. Source it; do not run it.
#
# The repo's shell corpus is example-based: each case asserts one hand-picked input.
# This library adds the missing oracle class -- a seeded generator loop that hunts
# for counterexamples across an input domain the author enumerates, with a replay
# story for every failure it finds. It is the shell-side sibling of fast-check
# (apps/web-platform devDependency; see
# knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md
# for the third-test-class decision) -- kept dependency-free because a sourced
# repo lib cannot take an npm dep.
#
# API (call prop_init FIRST -- every function reads the state it binds):
#
#   prop_init <label>
#     Bind the run: PROP_SEED=<n> replays a stream, unset draws a fresh seed from
#     the ambient $RANDOM stream and pins RANDOM to it; PROP_RUNS=<n> overrides the
#     default 100 case budget. Prints PROP_SEED=<seed> runs=<n> label=<label> so a
#     failure line alone cannot answer "which stream produced this". Both env
#     knobs must match ^[0-9]+$ -- an unvalidated numeric seam fails open (see
#     #7537: a non-numeric MIN_AGE_S signalled a 2s-old process while every
#     counter reported clean).
#
#   prop_iter
#     Bump PROP_ITER -- call once at the head of each generated case so PROP_FAIL
#     lines name the case index. Returns the new value in $PROP_ITER (no subshell;
#     see "why no echo-form" below).
#
#   prop_rand <n> <outvar>
#     $RANDOM-uniform draw in [0, n). n must match ^[0-9]+$ and be >= 1. Result
#     lands in <outvar> via printf -v -- NEVER in a command substitution (see
#     below). Modulo bias exists for n not dividing 32768; test-input generation
#     does not need cryptographic uniformity, only reproducible coverage.
#
#   prop_pick <outvar> <item>...
#     Choose one positional argument uniformly and land it in <outvar>.
#
#   prop_fail <label> <detail>
#     Print `PROP_FAIL <label> seed=<s> iter=<i> <detail>` to stderr, bump
#     PROP_FAILS, and return 1. Under the caller's `set -e` that aborts the suite
#     red at the counterexample -- the finding IS the exit. A suite that wants to
#     keep sweeping catches it (`prop_fail ... || true`) and asserts
#     PROP_FAILS == 0 before exiting.
#
#   prop_pass <label> <runs>
#     Print `PROP_PASS <label> runs=<runs> seed=<s>`. The run count is the
#     anti-vacuity receipt -- a suite that ran zero cases must never reach this
#     line (assert PROP_ITER >= PROP_RUNS_ACTIVE first).
#
# Replay: PROP_SEED=<seed-from-failure> re-runs the identical stream. Streams are
# bash-version-specific ($RANDOM's generator is implementation-defined), so a
# seed recorded on CI replays on the same platform, not cross-arch -- pin the
# shrunken counterexample as a named case instead of relying on cross-host seeds
# (see property-harness.md).
#
# WHY NO ECHO-FORM (prop_rand / prop_pick take <outvar>, they do not print):
# `x=$(prop_pick ...)` forks a subshell. On bash >= 5 the draw still advances the
# parent's stream, but on bash 3.2 (macOS default -- the portability floor for
# scripts/lib/) a subshell reads the SAME stream position the parent had at fork,
# so every loop iteration returns the identical value: the generator degenerates
# to a one-case suite that always passes. printf -v runs in-process on both.
#
# Bash 3.2-safe: no declare -A, no namerefs, no arrays beyond positional params.
#
# Direct-execution guard + double-source guard + LC_ALL=C pin mirror
# scripts/lib/legal-normalise.sh conventions exactly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "property-harness.sh is a library and must be sourced, not executed:" >&2
  echo "  . \"\$(git rev-parse --show-toplevel)/scripts/lib/property-harness.sh\"" >&2
  exit 64
fi

if [[ -n "${_SOLEUR_PROPERTY_HARNESS_SOURCED:-}" ]]; then
  return 0
fi
_SOLEUR_PROPERTY_HARNESS_SOURCED=1

# Locale pin: generators compose fixed alphabets and callers diff output text;
# collation drifting between hosts would make a recorded seed non-replayable.
export LC_ALL=C

prop_init() {
  PROP_LABEL="${1:?prop_init needs a label}"
  PROP_RUNS_ACTIVE="${PROP_RUNS:-100}"
  case "$PROP_RUNS_ACTIVE" in
    ''|*[!0-9]*)
      echo "property-harness: PROP_RUNS must be a non-negative integer (got: ${PROP_RUNS_ACTIVE})" >&2
      return 2
      ;;
  esac
  if [[ -n "${PROP_SEED:-}" ]]; then
    PROP_SEED_ACTIVE="$PROP_SEED"
  else
    PROP_SEED_ACTIVE=$RANDOM
  fi
  case "$PROP_SEED_ACTIVE" in
    ''|*[!0-9]*)
      echo "property-harness: PROP_SEED must be a non-negative integer (got: ${PROP_SEED_ACTIVE})" >&2
      return 2
      ;;
  esac
  RANDOM=$PROP_SEED_ACTIVE
  PROP_ITER=0
  PROP_FAILS=0
  printf 'PROP_SEED=%s runs=%s label=%s\n' "$PROP_SEED_ACTIVE" "$PROP_RUNS_ACTIVE" "$PROP_LABEL"
}

prop_iter() {
  PROP_ITER=$((PROP_ITER + 1))
}

prop_rand() {
  local _n="${1:?prop_rand needs a bound}" _out="${2:?prop_rand needs an outvar}"
  case "$_n" in
    ''|*[!0-9]*)
      echo "property-harness: prop_rand bound must be a non-negative integer (got: ${_n})" >&2
      return 2
      ;;
  esac
  if (( _n < 1 )); then
    echo "property-harness: prop_rand bound must be >= 1 (got: ${_n})" >&2
    return 2
  fi
  printf -v "$_out" '%s' $(( RANDOM % _n ))
}

prop_pick() {
  local _out="${1:?prop_pick needs an outvar}"
  shift
  if (( $# < 1 )); then
    echo "property-harness: prop_pick needs at least one item" >&2
    return 2
  fi
  local _i=$(( RANDOM % $# ))
  # Walk positionals instead of ${!i} indirect expansion: portable on bash 3.2
  # with no eval. $# >= 1 guaranteed above, so $1 is set after the shifts.
  while (( _i > 0 )); do shift; _i=$(( _i - 1 )); done
  printf -v "$_out" '%s' "$1"
}

prop_fail() {
  local _label="${1:?prop_fail needs a label}" _detail="${2:-}"
  PROP_FAILS=$(( ${PROP_FAILS:-0} + 1 ))
  printf 'PROP_FAIL %s seed=%s iter=%s %s\n' \
    "$_label" "${PROP_SEED_ACTIVE:-unset}" "${PROP_ITER:-unset}" "$_detail" >&2
  return 1
}

prop_pass() {
  local _label="${1:?prop_pass needs a label}" _runs="${2:?prop_pass needs a run count}"
  printf 'PROP_PASS %s runs=%s seed=%s\n' "$_label" "$_runs" "${PROP_SEED_ACTIVE:-unset}"
}
