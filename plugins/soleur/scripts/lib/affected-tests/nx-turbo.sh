#!/usr/bin/env bash
# nx-turbo.sh — nx/turborepo adapter for affected-tests.sh (#9307 PR2). Sourced,
# not executed. Detected FIRST in the adapter order: a workspace scheduler's
# affected graph subsumes per-package JS selection.
#
# Selection: `nx affected -t test --base=<base> --parallel=<w>` /
# `turbo run test --filter=...[<base>] --concurrency=<w>` — both compute the
# dependency-closure themselves, which is what makes them the preferred arm.
# A zero-task affected run is vacuous and falls back to the full workspace run
# (`nx run-many -t test --all` / `turbo run test`).
#
# External binaries: grep, node (probe only), npx, nx, turbo.

if [[ "${_SOLEUR_AFFECTED_NXT_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_AFFECTED_NXT_LOADED=1

affected_nxt_detect() {
  [[ -f nx.json || -f turbo.json ]]
}

# rc: 0 resolved | 4 toolchain missing. Sets ADP_TOOL (argv prefix) and
# ADP_TOOL_KIND (nx|turbo).
affected_nxt_tool() {
  local tool
  if [[ -f nx.json ]]; then tool=nx; else tool=turbo; fi
  if [[ -x "node_modules/.bin/$tool" ]]; then
    ADP_TOOL=("node_modules/.bin/$tool")
  elif command -v "$tool" >/dev/null 2>&1; then
    ADP_TOOL=("$tool")
  elif command -v npx >/dev/null 2>&1; then
    ADP_TOOL=(npx --no-install "$tool")
  else
    ADP_TOOL=()
    return 4
  fi
  if ! affected_timeout 20 "${ADP_TOOL[@]}" --version >/dev/null 2>&1; then
    ADP_TOOL=()
    return 4
  fi
  ADP_TOOL_KIND="$tool"
  return 0
}

# affected_nxt_run <selected|full> <width> <base>
affected_nxt_run() {
  local mode="$1" width="$2" base="$3"
  ADP_VACUOUS=0
  # Project graph totals are scheduler-owned; `-` is the honest count.
  ADP_OF="-"
  local -a cmd=()
  local log rc=0
  affected_mktemp nxt; log="$AFFECTED_TMP"

  if [[ "$ADP_TOOL_KIND" == nx ]]; then
    if [[ "$mode" == selected ]]; then
      cmd=("${ADP_TOOL[@]}" affected -t test --base="$base" --parallel="$width")
    else
      cmd=("${ADP_TOOL[@]}" run-many -t test --all --parallel="$width")
    fi
  else
    if [[ "$mode" == selected ]]; then
      # `...[<base>]` = packages changed since <base> plus everything that
      # depends on them.
      cmd=("${ADP_TOOL[@]}" run test "--filter=...[$base]" --concurrency="$width")
    else
      cmd=("${ADP_TOOL[@]}" run test --concurrency="$width")
    fi
  fi

  affected_bound "${cmd[@]}" >"$log" 2>&1 || rc=$?
  cat "$log"

  # Vacuous verdicts from the scheduler's own words: an affected run that
  # reached zero tasks executed nothing. The `0 tasks` alternative must not
  # match inside a larger count — `10 tasks` is a real run, not a vacuous one.
  if grep -qiE '(^|[^0-9])0 tasks|no tasks were executed|ran target test for 0 projects|No projects' "$log"; then
    ADP_VACUOUS=1
    rm -f "$log"
    ADP_RAN=0
    return 5
  fi
  ADP_RAN="$(grep -oE 'for [0-9]+ project|[0-9]+ (tasks|successful|cached)' "$log" \
    | grep -oE '[0-9]+' | head -n 1 || true)"
  [[ -n "$ADP_RAN" ]] || ADP_RAN="-"
  # A NUMERIC zero is vacuous the same as a phrase match: `Tasks: 0 successful`
  # / `ran target test for 0 projects`-adjacent spellings the phrase grep above
  # doesn't cover still mean the scheduler executed nothing.
  if [[ "$ADP_RAN" =~ ^[0-9]+$ ]] && (( ADP_RAN == 0 )); then
    ADP_VACUOUS=1
    rm -f "$log"
    ADP_RAN=0
    return 5
  fi
  rm -f "$log"
  return "$rc"
}
