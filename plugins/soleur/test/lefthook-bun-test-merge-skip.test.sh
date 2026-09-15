#!/usr/bin/env bash
# Pins lefthook.yml's `bun-test` stanza: `skip: [merge]` sits on that ONE command (not the hook),
# its glob is unchanged, and no other pre-commit command carries a skip (#7941 Thread 3). The plan's
# AC11 was a one-shot in-session assertion; this makes it a standing guard.
set -euo pipefail
SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./test-helpers.sh
source "$SUITE_DIR/test-helpers.sh"
REPO_ROOT="$(cd -P "$SUITE_DIR/../../.." && pwd -P)"

out="$(python3 - "$REPO_ROOT/lefthook.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
c = d["pre-commit"]["commands"]
bt = c["bun-test"]
print("skip=" + ",".join(bt.get("skip") or []))
print("glob=" + str(bt.get("glob")))
print("run=" + str(bt.get("run")))
print("skippers=" + ",".join(sorted(k for k, v in c.items() if isinstance(v, dict) and "skip" in v)))
print("hook_skip=" + str("skip" in d["pre-commit"]))
PY
)"
get() { printf '%s\n' "$out" | sed -n "s/^$1=//p"; }
assert_eq "merge" "$(get skip)" "bun-test skip is exactly [merge]"
assert_eq '*.{ts,tsx,js,jsx}' "$(get glob)" "bun-test glob is unchanged"
assert_eq "SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh" "$(get run)" "bun-test run still carries the ADR-196 hatch"
assert_eq "bun-test" "$(get skippers)" "bun-test is the only pre-commit command with a skip"
assert_eq "False" "$(get hook_skip)" "the skip is on the command, not the pre-commit hook"
print_results 5
