#!/usr/bin/env bash
# js.sh — JS/TS adapter for affected-tests.sh (#9307 PR2). Sourced, not executed.
#
# Detection: package.json / bunfig.toml / pnpm-workspace.yaml.
# Selector: `vitest related <files> --run` — `related` is a SUBCOMMAND, not a
# `--related` flag (verified at vitest 4.1.11, #9815) — or jest
# `--findRelatedTests <files>`; a repo without either falls back to its own
# `scripts.test` for the full command.
# Vacuous runs ("No test files found" / jest "No tests found" / passWithNoTests)
# are a NON-VACUOUS-check failure, never a pass.
#
# External binaries: find, grep, node (probe only), npx, npm, pnpm, yarn, bun,
# vitest, jest (via the resolved exec prefix).

if [[ "${_SOLEUR_AFFECTED_JS_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_AFFECTED_JS_LOADED=1

affected_js_detect() {
  [[ -f package.json || -f bunfig.toml || -f pnpm-workspace.yaml ]]
}

affected_js_pm() {
  if [[ -f pnpm-lock.yaml ]]; then echo pnpm
  elif [[ -f yarn.lock ]]; then echo yarn
  elif [[ -f bun.lockb || -f bun.lock || -f bunfig.toml ]]; then echo bun
  else echo npm; fi
}

# Resolve an executable prefix for a tool into ADP_TOOL (an argv array).
# Probe order: node_modules/.bin, the detected package manager's exec, npx
# --no-install, a bare PATH entry. A RESOLVABLE name is not a RUNNABLE one —
# every candidate must pass a bounded `--version` probe (the #8266 class: an
# unpinned mise shim resolves and exits non-zero on every call).
#
# rc: 0 resolved | 2 no test tool configured for this repo | 4 toolchain missing
affected_js_tool() {
  local pm tool=""
  ADP_TOOL=()
  ADP_TOOL_KIND=""
  pm="$(affected_js_pm)"
  if compgen -G 'vitest.config.*' >/dev/null 2>&1 \
     || { [[ -f package.json ]] && grep -q '"vitest"' package.json; }; then
    tool=vitest
  elif compgen -G 'jest.config.*' >/dev/null 2>&1 \
     || { [[ -f package.json ]] && grep -q '"jest"' package.json; }; then
    tool=jest
  elif [[ -f package.json ]] && grep -q '"test"[[:space:]]*:' package.json; then
    # No selector-capable runner; the repo's own scripts.test is the only
    # command. It can only run FULL — selection has no native form here.
    case "$pm" in
      pnpm) ADP_TOOL=(pnpm test) ;;
      yarn) ADP_TOOL=(yarn test) ;;
      bun)  ADP_TOOL=(bun test) ;;
      *)    ADP_TOOL=(npm test) ;;
    esac
    for b in "${ADP_TOOL[0]}"; do
      command -v "$b" >/dev/null 2>&1 || { ADP_TOOL=(); return 4; }
    done
    ADP_TOOL_KIND=script
    return 0
  else
    return 2
  fi

  if [[ -x "node_modules/.bin/$tool" ]]; then
    ADP_TOOL=("node_modules/.bin/$tool")
  else
    case "$pm" in
      pnpm) command -v pnpm >/dev/null 2>&1 && ADP_TOOL=(pnpm exec "$tool") ;;
      yarn) command -v yarn >/dev/null 2>&1 && ADP_TOOL=(yarn "$tool") ;;
      bun)  command -v bun  >/dev/null 2>&1 && ADP_TOOL=(bun x "$tool") ;;
    esac
    if (( ${#ADP_TOOL[@]} == 0 )) && command -v npx >/dev/null 2>&1; then
      ADP_TOOL=(npx --no-install "$tool")
    fi
    if (( ${#ADP_TOOL[@]} == 0 )) && command -v "$tool" >/dev/null 2>&1; then
      ADP_TOOL=("$tool")
    fi
  fi
  if (( ${#ADP_TOOL[@]} == 0 )); then
    return 4
  fi
  # RESOLVABLE IS NOT RUNNABLE — probe, bounded.
  if ! affected_timeout 15 "${ADP_TOOL[@]}" --version >/dev/null 2>&1; then
    ADP_TOOL=()
    return 4
  fi
  ADP_TOOL_KIND="$tool"
  return 0
}

# Total test files discoverable in the repo (spec/test conventions + __tests__).
affected_js_total() {
  affected_find_files count '*.test.*' '*.spec.*' | grep -c .
}

# Count the test files a runner reported running, from its own summary line.
affected_js_parse_ran() { # $1 = log file; prints count or -
  local log="$1" n=""
  if [[ "$ADP_TOOL_KIND" == vitest ]]; then
    # `  Test Files  2 passed | 1 failed (3)` — the parenthesised TOTAL.
    n="$(grep -oE 'Test Files.*\(([0-9]+)\)' "$log" 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)"
  elif [[ "$ADP_TOOL_KIND" == jest ]]; then
    # `Test Suites: 1 failed, 2 passed, 3 total`
    n="$(grep -oE 'Test Suites:.*[0-9]+ total' "$log" 2>/dev/null | grep -oE '[0-9]+ total' | grep -oE '[0-9]+' | tail -n 1)"
  fi
  printf '%s\n' "${n:--}"
}

# affected_js_run <selected|full> — runs the resolved tool. Sets ADP_RAN,
# ADP_OF, ADP_VACUOUS. rc: 0 pass | 1 fail | 5 vacuous | 124 budget-expired |
# other runner rc.
affected_js_run() {
  local mode="$1" width="$2"
  ADP_VACUOUS=0
  ADP_ESCALATED_FULL=0   # set when a selected run silently became a full one
  ADP_OF="$(affected_js_total)"
  local -a cmd=()
  local log rc=0 ran="-"
  log="$(mktemp "${TMPDIR:-/tmp}/affected-js.XXXXXX")"

  if [[ "$mode" == selected && "$ADP_TOOL_KIND" == vitest ]]; then
    local -a files=()
    local f
    for f in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
      [[ -f "$f" ]] && files+=("$f")
    done
    if (( ${#files[@]} == 0 )); then
      rm -f "$log"
      ADP_VACUOUS=1
      ADP_RAN=0
      return 5
    fi
    cmd=("${ADP_TOOL[@]}" related "${files[@]}" --run "--maxWorkers=${width}")
  elif [[ "$mode" == selected && "$ADP_TOOL_KIND" == jest ]]; then
    local -a files=()
    local f
    for f in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
      [[ -f "$f" ]] && files+=("$f")
    done
    if (( ${#files[@]} == 0 )); then
      rm -f "$log"
      ADP_VACUOUS=1
      ADP_RAN=0
      return 5
    fi
    cmd=("${ADP_TOOL[@]}" --findRelatedTests "${files[@]}" "--maxWorkers=${width}")
  else
    # full, or selected on a tool with no native selector (scripts.test). The
    # escalation is reported so the gate's marker can say mode=full
    # reason=no-selector — a full run must never masquerade as a selection.
    if [[ "$mode" == selected ]]; then
      ADP_ESCALATED_FULL=1
      echo "affected-tests: stack=js has no native selector (scripts.test only) — running the full command (reason=no-selector)." >&2
    fi
    case "$ADP_TOOL_KIND" in
      vitest) cmd=("${ADP_TOOL[@]}" run "--maxWorkers=${width}") ;;
      jest)   cmd=("${ADP_TOOL[@]}" "--maxWorkers=${width}") ;;
      *)      cmd=("${ADP_TOOL[@]}") ;;
    esac
  fi

  affected_bound "${cmd[@]}" >"$log" 2>&1 || rc=$?
  cat "$log"

  # Vacuous verdicts come from the runner's OWN words, not its rc — vitest's
  # passWithNoTests exits 0 over zero files, and jest finds none under rc 1.
  if grep -qE 'No test files found|No tests found|no tests found' "$log"; then
    ADP_VACUOUS=1
    rm -f "$log"
    ADP_RAN=0
    return 5
  fi
  ran="$(affected_js_parse_ran "$log")"
  rm -f "$log"
  ADP_RAN="$ran"
  return "$rc"
}
