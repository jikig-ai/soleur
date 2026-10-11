#!/usr/bin/env bash
# shellcheck shell=bash
#
# vitest-related.sh <unit|bundle> — narrow-or-full vitest dispatch (#9815).
#
# On local affected-shaped runs the runner computes the diff's changed files
# under apps/web-platform/ and passes them through as WEBPLAT_RELATED
# (newline-separated, APP-RELATIVE paths, never exported — the var travels on
# the suite registration's `env` prefix). This wrapper then runs
# `vitest related <files> --run --project <p>` instead of the full project.
#
# Every empty-candidate path falls back to TODAY'S full invocation:
#   - WEBPLAT_RELATED empty  → full (caller declined narrowing: CI, --full,
#     enumerate, degraded fallback, undecidable diff, or a meta diff)
#   - `No test files found`  → full (zero is "no coverage", never "green" —
#     the affected gate's zero-selected refusal class, one level down)
#   - nonzero related rc     → propagates AS-IS with no fallback re-run
#     (a red is a verdict, not a coverage gap)
#
# bundle: repo-wide always runs FULL (its subject is the repository — it can
# never be narrowed), then component narrows-or-falls-back. Both halves run in
# every shape and both receipts land; a repo-wide red does NOT skip component
# (an `&&` would hide coverage inside the suite).
#
# Receipts (greppable, WEIGHT_DRIFT/AFFECTED_* convention):
#   VITEST_RELATED<TAB>project=<p><TAB>inputs=<n><TAB>outcome=related|full-zero|full-empty|full-repo-wide
#
# The related argv is app-relative ("files should be relative to root
# folder" — vitest docs); --run is load-bearing (related defaults to watch);
# --shard + related is never combined (narrowing is local-only and shard is
# unset there) so VITEST_SHARD forwards only to the full invocation.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

MODE="${1:-}"
case "$MODE" in
  unit|bundle) ;;
  *) echo "usage: vitest-related.sh <unit|bundle>" >&2; exit 2 ;;
esac

VITEST="node_modules/.bin/vitest"

# full_project <project> — today's exact invocation, with the shard forward.
full_project() {
  local _p="$1"
  npm run test:ci -- --project "$_p" ${VITEST_SHARD:+--shard="$VITEST_SHARD"} 2>&1
}

# narrow_or_full <project> — related on a non-empty list, full on empty or
# zero-resolution; rc propagates.
narrow_or_full() {
  local _p="$1"
  if [[ -z "${WEBPLAT_RELATED:-}" ]]; then
    printf 'VITEST_RELATED\tproject=%s\tinputs=0\toutcome=full-empty\n' "$_p"
    full_project "$_p"
    return
  fi
  local -a _files=() _l
  while IFS= read -r _l; do
    [[ -n "$_l" ]] && _files+=("$_l")
  done <<<"${WEBPLAT_RELATED:-}"
  local _cap
  _cap="$(mktemp)"
  "$VITEST" related "${_files[@]+"${_files[@]}"}" --run --project "$_p" 2>&1 | tee "$_cap"
  local _rc="${PIPESTATUS[0]}"
  if [[ "$_rc" != 0 ]]; then
    rm -f "$_cap"
    printf 'VITEST_RELATED\tproject=%s\tinputs=%s\toutcome=related\n' "$_p" "${#_files[@]}"
    return "$_rc"
  fi
  if grep -qF 'No test files found' "$_cap"; then
    rm -f "$_cap"
    printf 'VITEST_RELATED\tproject=%s\tinputs=%s\toutcome=full-zero\n' "$_p" "${#_files[@]}"
    full_project "$_p"
    return
  fi
  rm -f "$_cap"
  printf 'VITEST_RELATED\tproject=%s\tinputs=%s\toutcome=related\n' "$_p" "${#_files[@]}"
  return 0
}

case "$MODE" in
  unit)
    narrow_or_full unit
    exit $?
    ;;
  bundle)
    printf 'VITEST_RELATED\tproject=repo-wide\tinputs=0\toutcome=full-repo-wide\n'
    full_project repo-wide
    _rw_rc=$?
    narrow_or_full component
    _comp_rc=$?
    (( _rw_rc != 0 )) && exit "$_rw_rc"
    exit "$_comp_rc"
    ;;
esac
