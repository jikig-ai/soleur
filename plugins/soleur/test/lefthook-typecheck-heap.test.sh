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
assert_eq "1" "$(printf '%s' "$run" | grep -c -- '--max-old-space-size=[0-9]')" "the typecheck run line sets a numeric --max-old-space-size"
if [ -n "$heap" ] && [ "$heap" -ge 4096 ] && [ "$heap" -le 12288 ]; then
  assert_eq "bounded" "bounded" "the heap bound ($heap MB) is raised above the ~2 GB default and still bounded"
else
  assert_eq "4096..12288" "${heap:-unset}" "the heap bound is raised above the ~2 GB default and still bounded"
fi
assert_contains "$run" './node_modules/.bin/tsc --noEmit' "the pinned tsc binary is the one that runs"
assert_contains "$run" 'NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }' "an existing NODE_OPTIONS is extended, not replaced"
assert_eq "0" "$(printf '%s' "$run" | grep -c 'npx tsc' || true)" "no unpinned npx tsc (the #7927 defect class)"
print_results 5
