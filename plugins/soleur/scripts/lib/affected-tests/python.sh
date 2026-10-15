#!/usr/bin/env bash
# python.sh — pytest adapter for affected-tests.sh (#9307 PR2). Sourced, not
# executed.
#
# Detection: pyproject.toml / pytest.ini / tox.ini / setup.cfg.
# Selection: pytest has no native affected selector — changed TEST files run
# directly; a diff touching non-test source falls back to pytest-testmon when
# importable, else the full suite. `-n <width>` only when pytest-xdist is
# importable, else serial with the reason printed. pytest's rc 5 (no tests
# collected) is a NON-VACUOUS check — it is never a pass.
#
# External binaries: find, grep, python3, pytest (whichever the probe resolves).

if [[ "${_SOLEUR_AFFECTED_PY_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_AFFECTED_PY_LOADED=1

affected_py_detect() {
  # A manifest alone is a Python-PROJECT marker, not a pytest-SUITE marker — a
  # library's bare pyproject.toml must not claim the stack. Require a pytest
  # signal: pytest.ini is one by name; the other manifests must mention pytest;
  # with no manifest signal, test_*.py/*_test.py files are the fallback evidence.
  local m
  for m in pyproject.toml pytest.ini tox.ini setup.cfg; do
    [[ -f "$m" ]] || continue
    [[ "$m" == pytest.ini ]] && return 0
    grep -qiE 'pytest' "$m" 2>/dev/null && return 0
  done
  affected_find_files any 'test_*.py' '*_test.py' | grep -q .
}

# Resolve the pytest invocation into ADP_TOOL (argv). A direct `pytest` binary
# wins over `python3 -m pytest` because a venv-provided pytest is the repo's
# pinned one; `python3 -m pytest` covers repos where only the module exists.
# rc: 0 resolved | 4 toolchain missing.
affected_py_tool() {
  if command -v pytest >/dev/null 2>&1 \
     && affected_timeout 15 pytest --version >/dev/null 2>&1; then
    ADP_TOOL=(pytest)
    return 0
  fi
  # -I: isolated mode — a repo's cwd on sys.path would execute repo-controlled
  # code (a pytest.py or sitecustomize.py in the tree) during a mere probe.
  if command -v python3 >/dev/null 2>&1 \
     && affected_timeout 15 python3 -I -c 'import pytest' >/dev/null 2>&1; then
    ADP_TOOL=(python3 -m pytest)
    return 0
  fi
  ADP_TOOL=()
  return 4
}

affected_py_total() {
  affected_find_files count 'test_*.py' '*_test.py' | grep -c . || true
}

# The interpreter backing the resolved ADP_TOOL: a `python3 -m pytest` tool
# answers to python3; a `pytest` entry point answers to ITS shebang interpreter
# — a venv-pinned pytest must probe the venv's environment, not the system's.
# Falls back to python3 when the shebang resolves to no python at all (a
# compiled or shell-wrapped pytest).
affected_py_interpreter() {
  if [[ "${ADP_TOOL[*]}" == "python3 -m pytest" ]]; then
    command -v python3 2>/dev/null
    return 0
  fi
  local bin sheb interp=""
  bin="$(command -v "${ADP_TOOL[0]:-pytest}" 2>/dev/null || true)"
  if [[ -n "$bin" && -f "$bin" ]]; then
    sheb="$(head -n 1 "$bin" 2>/dev/null)"
    case "$sheb" in
      '#!'*)
        sheb="${sheb#\#!}"
        # `read -ra`, never `set -- $sheb`: unquoted word-splitting also GLOBS,
        # and clobbering the function's positional params is a side effect.
        local -a sheb_argv=()
        read -ra sheb_argv <<<"$sheb"   # "/usr/bin/env python3" | "/venv/bin/python -E"
        if [[ "${sheb_argv[0]##*/}" == env && -n "${sheb_argv[1]:-}" ]]; then
          interp="${sheb_argv[1]}"
        else
          interp="${sheb_argv[0]:-}"
        fi
        case "${interp##*/}" in python*|py) ;; *) interp="" ;; esac
        ;;
    esac
  fi
  [[ -n "$interp" ]] || interp="$(command -v python3 2>/dev/null || true)"
  printf '%s\n' "$interp"
}

# Append parallelism flags to ADP_TOOL-derived argv when xdist is importable;
# print the serial reason when it is not (P4: the operator sees what ran).
affected_py_width() {
  local width="$1" pybin
  pybin="$(affected_py_interpreter)"
  if [[ -n "$pybin" ]] && affected_timeout 15 "$pybin" -I -c 'import xdist' >/dev/null 2>&1; then
    printf -- '-n %s' "$width"
  else
    echo "pytest-xdist not importable — running serially" >&2
    printf ''
  fi
}

# affected_py_run <selected|full> <width>. Sets ADP_RAN/ADP_OF/ADP_VACUOUS.
# rc: 0 pass | 1 fail | 5 vacuous (collected nothing) | 124 budget | other.
affected_py_run() {
  local mode="$1" width="$2"
  ADP_VACUOUS=0
  ADP_OF="$(affected_py_total)"
  local -a cmd=("${ADP_TOOL[@]}")
  local -a width_args=()
  local -a test_files=()
  local f non_test=0 testmon=0
  local w
  w="$(affected_py_width "$width")"
  # shellcheck disable=SC2206  # `affected_py_width` emits flag words only
  [[ -n "$w" ]] && width_args=($w)
  local log rc=0
  affected_mktemp py; log="$AFFECTED_TMP"

  if [[ "$mode" == selected ]]; then
    # Partition the changed set: changed test files run directly; the presence
    # of non-test sources requires coverage pytest cannot compute natively.
    for f in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
      [[ -f "$f" ]] || continue
      case "${f##*/}" in
        test_*.py|*_test.py) test_files+=("$f") ;;
        *.py) non_test=1 ;;
      esac
    done
    local pybin_t
    pybin_t="$(affected_py_interpreter)"
    if [[ -n "$pybin_t" ]] \
       && affected_timeout 15 "$pybin_t" -I -c 'import pytest_testmon' >/dev/null 2>&1; then
      testmon=1
    fi
    if (( testmon )); then
      # testmon selects tests whose coverage the diff touches — it needs a
      # recorded baseline (.testmondata) and widens safely when absent.
      cmd+=("--testmon" ${width_args[@]+"${width_args[@]}"})
    elif (( non_test )) || (( ${#test_files[@]} == 0 )); then
      # A source diff with no testmon, or a diff with no runnable pytest file:
      # coverage-favoring — the full suite is the only honest selection.
      rm -f "$log"
      ADP_VACUOUS=1
      ADP_RAN=0
      return 5
    else
      cmd+=("${test_files[@]}" ${width_args[@]+"${width_args[@]}"})
    fi
  fi
  # full mode (or the selected testmon arm) uses cmd as built above; a bare
  # `full` runs the whole suite.
  if [[ "$mode" == full ]]; then
    cmd=("${ADP_TOOL[@]}" ${width_args[@]+"${width_args[@]}"})
  fi

  affected_bound "${cmd[@]}" >"$log" 2>&1 || rc=$?
  cat "$log"

  # pytest rc 5 = "no tests collected" — a vacuous verdict, never a pass.
  if (( rc == 5 )) || grep -qE 'no tests ran|collected 0 items' "$log"; then
    ADP_VACUOUS=1
    rm -f "$log"
    ADP_RAN=0
    return 5
  fi
  # ran is in FILE units to match of= (the repo test-file census). pytest's
  # `collected N items` counts test ITEMS — a different unit, and under testmon
  # `collected N / M deselected` the pre-slash figure even overstates. So: the
  # file-diff arm ran exactly the files it passed pytest; full ran the whole
  # census; under testmon no honest file count is derivable → `-`.
  if [[ "$mode" == full ]]; then
    ADP_RAN="$ADP_OF"
  elif (( testmon )); then
    ADP_RAN="-"
  else
    ADP_RAN="${#test_files[@]}"
  fi
  rm -f "$log"
  return "$rc"
}
