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
#
# #7024 added the two files it took to zero, so they cannot regress:
#   tests/scripts/test-sentry-full-root-apply.sh
#   plugins/soleur/skills/compound/test/phase-16.test.sh
# The REST of scripts/ and plugins/ is still out of scope — ~800 sites repo-wide,
# tracked in #7005. #7024 was a slice of that corpus, not a peer of it.
#
# THE PATHSPEC CANNOT SIMPLY BE WIDENED TO scripts/ OR plugins/. This pattern matches
# COMMENTS as well as code — it is a text search, not a parse — so a wider sweep starts
# matching prose that merely NAMES the forbidden shape, including this file's own
# non-vacuity probe below and the learning file that documents the bug. Zero is
# enforceable here precisely because the pathspec is narrow and each member was taken to
# zero deliberately. Growth happens by adding a named file, never by widening a glob.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Applied to EVERY hook suite, not just ones whose hook is a sibling .sh:
# security_reminder_hook is a .py, so pairing by filename missed it and it
# kept writing the real ledger. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

# Match a pipe feeding grep with a -q anywhere in its flag cluster (-q, -qE,
# -qiE, -qF, -qs...). Anchored on the pipe + grep + q so a comment that merely
# mentions the words cannot match.
PATTERN='\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'

# `.openhands/hooks/*.sh` added by #7173. It is the SIBLING HARNESS of the tree
# above and it was never in this pathspec, so the class this guard exists to
# stop was live there the whole time it was enforced here — 20 sites, including
# the recursive-delete ownership proof. Measured before the fix, with the real
# grep pinned and `yes | grep -q y` returning 141 as a positive control: a
# `rm -rf $HOME` padded past the 64 KiB pipe buffer returned rc 0 with no
# decision at 131 KB and 526 KB, and denied at 8 KB. The producer takes SIGPIPE,
# `pipefail` promotes it, the `if` reads false, and the guard is skipped.
#
# Added as a NAMED directory taken to zero in the same change, which is the
# growth rule in the scope note above — not a speculative glob widening. The
# `.test.sh` exclusion below applies to it identically.
hits="$(git grep -nE "$PATTERN" -- '.claude/hooks/*.sh' '.claude/hooks/lib/*.sh' \
  '.openhands/hooks/*.sh' \
  | grep -vE '\.test\.sh' || true)"

# The two files #7024 took to zero. Named individually, NOT via a glob — see the scope
# note above. They are .test.sh files, which the exclusion filter above deliberately drops
# from the hooks sweep, so they are matched in their own pass.
#
# TWO FILTERS, AND BOTH ARE THE SAME LESSON THIS GUARD IS ABOUT.
#
#   1. COMMENT LINES ARE STRIPPED. The pattern is a text search, so it matches prose that
#      merely NAMES the shape — and these two files necessarily document it at length. The
#      sibling `_strip_comments` in test-sentry-full-root-apply.sh exists for exactly this
#      reason (cq-assert-anchor-not-bare-token): anchor on the executable construct, never
#      on a token a comment can also produce. Written without this, the guard false-FAILs
#      on the very explanation of the bug it enforces.
#
#   2. AN EXPLICIT PER-LINE OPT-OUT. test-sentry-full-root-apply.sh's T4 arm has to USE the
#      forbidden shape: it is the synthetic reproduction of the SIGPIPE mechanism, plus the
#      `yes | grep -q y` positive control that proves the environment can exhibit SIGPIPE
#      at all. A test that demonstrates a bug must be allowed to contain it. The marker is
#      per-LINE and must be typed out, so it cannot be applied by accident or by a glob.
ALLOW_MARKER='#[[:space:]]*sigpipe-demo:[[:space:]]*intentional'
hits_7024="$(git grep -nE "$PATTERN" -- \
  'tests/scripts/test-sentry-full-root-apply.sh' \
  'plugins/soleur/skills/compound/test/phase-16.test.sh' \
  | grep -vE ':[0-9]+:[[:space:]]*#' \
  | grep -vE "$ALLOW_MARKER" || true)"

if [[ -n "$hits" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in policy-gate hooks (#6992 regression)"
  echo "$hits" | sed 's/^/  /'
  echo
  echo "  Rewrite as a herestring, or as grep -c compared against 0."
else
  echo "PASS: no pipe-into-grep-q in .claude/hooks/ non-test code"
fi

if [[ -n "$hits_7024" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in a file #7024 took to zero"
  echo "$hits_7024" | sed 's/^/  /'
  echo
  echo "  Rewrite as a herestring, or as grep -c compared against 0."
else
  echo "PASS: no pipe-into-grep-q in the two files #7024 took to zero"
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
