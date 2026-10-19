#!/usr/bin/env bash
# go.sh — Go adapter for affected-tests.sh (#9307 PR2). Sourced, not executed.
#
# Detection: go.mod. Selection: the changed packages PLUS the reverse-dependency
# closure — a leaf package alone is the false-narrow shape Guard 1 row 9 names —
# computed from `go list` import edges (Imports + TestImports + XTestImports).
# Run: `go test -p <width>` on the selected set; `./...` when full. A run whose
# every package reports `[no test files]` is vacuous — never a pass.
#
# External binaries: find, grep, sort, comm, go.

if [[ "${_SOLEUR_AFFECTED_GO_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_AFFECTED_GO_LOADED=1

affected_go_detect() {
  [[ -f go.mod ]]
}

affected_go_tool() {
  if command -v go >/dev/null 2>&1 \
     && affected_timeout 15 go version >/dev/null 2>&1; then
    ADP_TOOL=(go)
    return 0
  fi
  ADP_TOOL=()
  return 4
}

affected_go_total() {
  affected_find_files count '*_test.go' | grep -c . || true
}

# Print the selected package set: changed packages plus their reverse-dependency
# closure. Output via stdout (one ImportPath per line); rc 1 when the module
# graph cannot be listed at all (caller then falls back to ./...).
affected_go_closure() {
  local -a changed_dirs=() changed_pkgs=()
  local f d p
  for f in ${AFFECTED_CHANGED[@]+"${AFFECTED_CHANGED[@]}"}; do
    case "$f" in
      *.go) [[ -f "$f" ]] || continue
            d="${f%/*}"; [[ "$d" == "$f" ]] && d="."
            changed_dirs+=("./$d") ;;
    esac
  done
  if (( ${#changed_dirs[@]} == 0 )); then
    return 1
  fi
  # while-read, never `for d in $(…)`: a directory whose name contains a space
  # must not be split into two bogus operands.
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    # Bounded like every other probe — a `go list` that blocks on module
    # resolution must not park the gate (affected_timeout: timeout→gtimeout→
    # watchdog). The same bound covers the ./... graph walk below.
    p="$(affected_timeout 60 "${ADP_TOOL[@]}" list -e -f '{{.ImportPath}}' "$d" 2>/dev/null || true)"
    [[ -n "$p" && "$p" != -* ]] && changed_pkgs+=("$p")
  done < <(printf '%s\n' "${changed_dirs[@]}" | sort -u)
  if (( ${#changed_pkgs[@]} == 0 )); then
    return 1
  fi

  # Forward edges: pkg -> packages it imports (test imports included — a test
  # file importing the changed package is how the change is observed).
  local graph
  graph="$(affected_timeout 60 "${ADP_TOOL[@]}" list -e -f '{{.ImportPath}}|{{join .Imports " "}}|{{join .TestImports " "}}|{{join .XTestImports " "}}' ./... 2>/dev/null)" \
    || return 1
  [[ -n "$graph" ]] || return 1

  # BFS over the reverse edges. Bash 3.2 (no assoc arrays): the selected set is
  # a space-delimited string; each pass adds every package that imports a
  # selected one. Termination is guaranteed by a bound of total packages.
  local sel=" $(printf '%s ' "${changed_pkgs[@]}")" grew=1 guard=0
  local line pkg deps dep
  while (( grew && guard < 10000 )); do
    grew=0
    guard=$((guard + 1))
    while IFS= read -r line; do
      pkg="${line%%|*}"
      [[ "$sel" == *" $pkg "* ]] && continue
      deps="${line#*|}"
      local found=0
      for dep in ${deps//|/ }; do
        if [[ "$sel" == *" $dep "* ]]; then found=1; break; fi
      done
      if (( found )); then
        sel+="$pkg "
        grew=1
      fi
    done <<<"$graph"
  done
  # A guard-trip means the closure was still growing at the bound — returning
  # the TRUNCATED set would be a silent false-narrow. Refuse the selection;
  # the caller treats rc 1 as unlistable and falls back to ./... (coverage-
  # favoring).
  if (( grew && guard >= 10000 )); then
    return 1
  fi
  printf '%s' "$sel" | tr ' ' '\n' | grep -v '^$' | sort -u
  return 0
}

# affected_go_run <selected|full> <width>. Sets ADP_RAN/ADP_OF/ADP_VACUOUS.
affected_go_run() {
  local mode="$1" width="$2"
  ADP_VACUOUS=0
  ADP_OF="$(affected_go_total)"
  local -a cmd=("${ADP_TOOL[@]}" test -p "$width")
  local log rc=0
  affected_mktemp go || return 4; log="$AFFECTED_TMP"

  if [[ "$mode" == selected ]]; then
    local pkgs
    pkgs="$(affected_go_closure)" || pkgs=""
    if [[ -z "$pkgs" ]]; then
      rm -f "$log"
      ADP_VACUOUS=1
      ADP_RAN=0
      return 5
    fi
    local -a plist=()
    local p
    while IFS= read -r p; do [[ -n "$p" ]] && plist+=("$p"); done <<<"$pkgs"
    cmd+=("${plist[@]}")
  else
    cmd+=(./...)
  fi

  affected_bound "${cmd[@]}" >"$log" 2>&1 || rc=$?
  cat "$log"

  # Every package answering `[no test files]` is a vacuous run: the diff was
  # real code and go executed nothing that could fail on it.
  if ! grep -qE '^(ok|FAIL|--- )' "$log"; then
    ADP_VACUOUS=1
    rm -f "$log"
    ADP_RAN=0
    return 5
  fi
  # ran must be in the same units as of= — test FILES, not packages: count the
  # *_test.go files under each reported package's directory. Packages outside
  # the module prefix are skipped; an under-count biases ran DOWN (honest).
  local modpfx="" pkg dir cnt=0
  modpfx="$(sed -n 's/^module[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' go.mod 2>/dev/null | head -n 1 || true)"
  while IFS= read -r pkg; do
    [[ -n "$modpfx" && "$pkg" == "$modpfx"* ]] || continue
    dir="${pkg#"$modpfx"}"; dir="${dir#/}"
    [[ -z "$dir" ]] && dir="."
    [[ -d "$dir" ]] || continue
    cnt=$((cnt + $(find "$dir" -maxdepth 1 -type f -name '*_test.go' 2>/dev/null | wc -l || true)))
  done < <(grep -oE '^(ok|FAIL)[[:space:]]+[^[:space:]]+' "$log" | awk '{print $2}' | sort -u || true)
  ADP_RAN="$cnt"
  rm -f "$log"
  return "$rc"
}
