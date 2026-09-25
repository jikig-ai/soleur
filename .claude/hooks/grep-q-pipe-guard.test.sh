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
# #8664 added the zot-pull mutation battery and the guard it mutates:
#   apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh
#   apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
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

# Without git the `git grep … || true` sweeps below read as "no hits" and pass (#8616).
command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

# Match a pipe feeding a grep that can stop at its first match: -q or -m in any
# flag cluster (-q, -qE, -F -q, -m1, ...) or the long forms --quiet, --silent,
# --max-count. Anchored on the pipe + grep so a comment that merely mentions the
# words cannot match. A pipe that ends one line with the grep on the next is not
# seen (a declared gap), nor is `| head` (the #8664 files keep 19 one-line
# `| head -1` sites whose producers are single short writes).
PATTERN='\|[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)'
# A piped awk whose program exits on the same line. A multi-line awk program is
# not seen by a line search; #8664's splitter shape is held by the battery's
# g1b-mustpass-padded-pull-item row and its positive control instead.
PATTERN_AWK_EXIT='\|[[:space:]]*awk[^|]*[^[:alnum:]_]exit([^[:alnum:]_]|$)'

# A second, hand-ported harness hook tree was in this pathspec from #7173 until
# it was retired in ADR-245 / #8306; its glob is gone with the tree. The scope
# rule is unchanged — growth happens by naming a file or a directory taken to
# zero, never by widening a glob.
hits="$(git grep -nE "$PATTERN" -- '.claude/hooks/*.sh' '.claude/hooks/lib/*.sh' \
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
FILES_7024=(
  'tests/scripts/test-sentry-full-root-apply.sh'
  'plugins/soleur/skills/compound/test/phase-16.test.sh'
)
hits_7024="$(git grep -nE "$PATTERN" -- "${FILES_7024[@]}" \
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

# The zot-pull mutation battery and the guard it mutates, taken to zero in #8664 (a piped
# early-exit scorer mis-scored killed rows under load). This pass pins the grep spelling and a
# single-line piped `awk … exit`; the multi-line splitter shape is held by the battery's padded
# row. Same comment filter as the #7024 pass; no opt-out marker.
FILES_8664=(
  'apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh'
  'apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh'
)
# Every pinned file must be tracked: a git grep over a renamed or deleted path returns nothing,
# which would switch its pin off without a word. The member count is pinned for the same reason.
missing_pins=""
for f in "${FILES_7024[@]}" "${FILES_8664[@]}"; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || missing_pins="$missing_pins $f"
done
if [[ -n "$missing_pins" ]] || (( ${#FILES_7024[@]} != 2 || ${#FILES_8664[@]} != 2 )); then
  FAIL=1
  echo "FAIL: a pinned file is not tracked, or a pin list lost a member, so its pin covers nothing:${missing_pins:- (member count changed)}"
  echo "  If a file was renamed, update FILES_7024/FILES_8664 in this file to the new path; do not delete the entry."
fi
hits_8664="$(git grep -nE "$PATTERN|$PATTERN_AWK_EXIT" -- "${FILES_8664[@]}" \
  | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
# The battery's scorer self-test is the deterministic backstop for its scorer; deleting it would
# leave only this line search. Pin that it is still there.
if ! grep -qF 'failed_on "$SELFTEST_LOG" SELFTEST-TARGET' "${FILES_8664[0]}"; then
  FAIL=1
  echo "FAIL: the #8664 scorer self-test is gone from ${FILES_8664[0]}"
fi

if [[ -n "$hits_8664" ]]; then
  FAIL=1
  echo "FAIL: pipe-into-grep-q found in a file #8664 took to zero"
  echo "$hits_8664" | sed 's/^/  /'
  echo
  echo "  Capture into a variable and match in bash, or use a herestring."
else
  echo "PASS: grep-q-zero-8664-pass (zot-pull battery and its guard)"
fi

# Non-vacuity: the pattern must actually match the shape it forbids. Without
# this, a typo in PATTERN would make the guard pass forever on any input.
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
printf 'echo "$x" | grep -qE '"'"'p'"'"'\n' > "$probe/bad.sh"
printf 'echo "$x" | grep -F -q p\n' > "$probe/bad2.sh"
printf 'echo "$x" | grep --quiet p\n' > "$probe/bad3.sh"
printf 'echo "$x" | awk '"'"'/p/ { exit }'"'"'\n' > "$probe/bad4.sh"
printf 'grep -qE '"'"'p'"'"' <<<"$x"\n' > "$probe/good.sh"

if grep -qE "$PATTERN" "$probe/bad.sh" && grep -qE "$PATTERN" "$probe/bad2.sh" \
  && grep -qE "$PATTERN" "$probe/bad3.sh" && grep -qE "$PATTERN_AWK_EXIT" "$probe/bad4.sh" \
  && ! grep -qE "$PATTERN" "$probe/good.sh"; then
  echo "PASS: guard pattern matches the forbidden shape and not the fixed shape"
else
  FAIL=1
  echo "FAIL: guard pattern is broken — it cannot distinguish the two shapes"
  echo "  matches forbidden shape: $(grep -cE "$PATTERN" "$probe/bad.sh" || true) (want 1)"
  echo "  matches fixed shape:     $(grep -cE "$PATTERN" "$probe/good.sh" || true) (want 0)"
fi

exit "$FAIL"
