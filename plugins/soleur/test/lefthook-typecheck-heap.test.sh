#!/usr/bin/env bash
# Pins lefthook.yml's `web-platform-typecheck` stanza: tsc runs under a bounded, raised Node heap so a
# large staged set on a loaded machine does not die with "JavaScript heap out of memory" and block the
# commit (#9384). The bound is explicit (a number, not `unlimited`), the pinned binary is still the one
# that runs, and an operator-supplied NODE_OPTIONS is extended rather than replaced.
set -euo pipefail
SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"

run="$(python3 - "$REPO_ROOT/lefthook.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(d["pre-commit"]["commands"]["web-platform-typecheck"]["run"])
PY
)"
heap="$(printf '%s' "$run" | sed -n 's/.*--max-old-space-size=\([0-9][0-9]*\).*/\1/p')"
# Adjacency, not substrings: the bound must be an env prefix of the SAME simple command that runs tsc.
# A `;`-separated assignment is never exported to the child and a bound placed after tsc never reaches it,
# yet both would satisfy a bare substring check (review mutants semicolon_form / bound_after_tsc).
# (a glob, not a regex: `${`, `:+` and `$` are all live ERE metacharacters in the literal being matched)
adjacent=no
[[ "$run" == *'&& NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--max-old-space-size='"$heap"'" ./node_modules/.bin/tsc --noEmit' ]] && adjacent=yes
assert_eq "yes" "$adjacent" "the bound is an env prefix of the command that runs the pinned tsc, at the end of the run line"
if [ -n "$heap" ] && [ "$heap" -ge 4096 ] && [ "$heap" -le 12288 ]; then
  assert_eq "bounded" "bounded" "the heap bound ($heap MB) is raised above the default and still bounded"
else
  assert_eq "4096..12288" "${heap:-unset}" "the heap bound is raised above the default and still bounded"
fi
assert_eq "1" "$(printf '%s' "$run" | grep -cF '[ -x node_modules/.bin/tsc ] || {' || true)" "the missing-tsc guard is still ahead of the run"
assert_contains "$run" 'exit 2' "the missing-tsc guard still exits 2"
assert_eq "0" "$(printf '%s' "$run" | grep -c 'npx tsc' || true)" "no unpinned npx tsc (the #7927 defect class)"
print_results 5
