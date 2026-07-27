#!/usr/bin/env bash
# Drift guard for #6992: no policy-gate hook may feed a producer into `grep -q`
# through a pipe.
#
# Under `set -o pipefail` that shape reports FAILURE on a SUCCESSFUL match once
# the producer still has unwritten data when grep exits — and because these
# hooks are shaped `<match> && deny` or `if ! <match>; then <skip>`, the
# dominant failure direction is FAIL OPEN: the gate silently permits what it
# exists to block. Measured at 0 denies in 30 runs on a 128 KB plan body whose
# first line was an operator-SSH step.
#
# Use instead:
#   grep -q PATTERN <<<"$var"                              # no pipe, no SIGPIPE
#   [ "$(producer | grep -c PATTERN || true)" -gt 0 ]      # -c reads all input
#
# Scope note: this asserts ZERO, not "no growth beyond a baseline". A baseline
# allowlist that grandfathers existing entries asserts nothing on day one. The
# hooks tree was taken to zero in #6992, so zero is the enforceable invariant.
# scripts/ and plugins/ are NOT in scope yet — tracked in #7005.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

# Match a pipe feeding grep with a -q anywhere in its flag cluster (-q, -qE,
# -qiE, -qF, -qs...). Anchored on the pipe + grep + q so a comment that merely
# mentions the words cannot match.
PATTERN='\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'

hits="$(git grep -nE "$PATTERN" -- '.claude/hooks/*.sh' '.claude/hooks/lib/*.sh' \
  | grep -vE '\.test\.sh' || true)"

if [[ -n "$hits" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in policy-gate hooks (#6992 regression)"
  echo "$hits" | sed 's/^/  /'
  echo
  echo "  Rewrite as a herestring, or as grep -c compared against 0."
else
  echo "PASS: no pipe-into-grep-q in .claude/hooks/ non-test code"
fi

# Non-vacuity: the pattern must actually match the shape it forbids. Without
# this, a typo in PATTERN would make the guard pass forever on any input.
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
printf 'echo "$x" | grep -qE '"'"'p'"'"'\n' > "$probe/bad.sh"
printf 'grep -qE '"'"'p'"'"' <<<"$x"\n' > "$probe/good.sh"

if grep -qE "$PATTERN" "$probe/bad.sh" && ! grep -qE "$PATTERN" "$probe/good.sh"; then
  echo "PASS: guard pattern matches the forbidden shape and not the fixed shape"
else
  FAIL=1
  echo "FAIL: guard pattern is broken — it cannot distinguish the two shapes"
  echo "  matches forbidden shape: $(grep -cE "$PATTERN" "$probe/bad.sh" || true) (want 1)"
  echo "  matches fixed shape:     $(grep -cE "$PATTERN" "$probe/good.sh" || true) (want 0)"
fi

exit "$FAIL"
