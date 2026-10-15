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
  [[ -f pyproject.toml || -f pytest.ini || -f tox.ini || -f setup.cfg ]]
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
  if command -v python3 >/dev/null 2>&1 \
     && affected_timeout 15 python3 -c 'import pytest' >/dev/null 2>&1; then
    ADP_TOOL=(python3 -m pytest)
    return 0
  fi
  ADP_TOOL=()
  return 4
}

affected_py_total() {
  find . \
    \( -name .git -o -name node_modules -o -name .venv -o -name venv \
       -o -name .tox -o -name __pycache__ -o -name dist -o -name build \) -prune \
    -o -type f \( -name 'test_*.py' -o -name '*_test.py' \) -print 2>/dev/null \
    | grep -c .
}

# Append parallelism flags to ADP_TOOL-derived argv when xdist is importable;
# print the serial reason when it is not (P4: the operator sees what ran).
affected_py_width() {
  local width="$1" pybin
  pybin="$(command -v python3 2>/dev/null || true)"
  if [[ -n "$pybin" ]] && affected_timeout 15 python3 -c 'import xdist' >/dev/null 2>&1; then
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
  local w
  w="$(affected_py_width "$width")"
  # shellcheck disable=SC2206  # `affected_py_width` emits flag words only
  [[ -n "$w" ]] && width_args=($w)
  local log rc=0
  log="$(mktemp "${TMPDIR:-/tmp}/affected-py.XXXXXX")"

  if [[ "$mode" == selected ]]; then
    # Partition the changed set: changed test files run directly; the presence
    # of non-test sources requires coverage pytest cannot compute natively.
    local -a test_files=()
    local f non_test=0 testmon=0
    for f in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
      [[ -f "$f" ]] || continue
      case "${f##*/}" in
        test_*.py|*_test.py) test_files+=("$f") ;;
        *.py) non_test=1 ;;
      esac
    done
    if command -v python3 >/dev/null 2>&1 \
       && affected_timeout 15 python3 -c 'import pytest_testmon' >/dev/null 2>&1; then
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
  # `collected N items` is pytest's own count of what it selected.
  ADP_RAN="$(grep -oE 'collected [0-9]+ item' "$log" | grep -oE '[0-9]+' | tail -n 1)"
  [[ -n "$ADP_RAN" ]] || ADP_RAN="-"
  rm -f "$log"
  return "$rc"
}
