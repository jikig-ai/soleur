#!/usr/bin/env bash
# Observability probe for #9956: prints "merge-base" when the infra-privileged-tier-census suite
# resolves its G4c base ref via `git merge-base`. It exists because a discoverability_test.command
# naming tests/scripts/test-*.sh trips the deepen-plan §4.7 Step 3 suite-shape reject (#8412) —
# this committed wrapper is the spellable form.
#
# The grep anchors on the resolution's call form (`git -C "$1" merge-base HEAD
# refs/remotes/origin/main`), and line-leading comments are stripped first so a commented-out
# call cannot satisfy it (a trailing comment or string payload could — observability probe,
# not a gate).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$DIR/../tests/scripts/test-infra-privileged-tier-census.sh"
# The command substitution is load-bearing: `grep -q` exits on the first match, and upstream
# grep then dies of SIGPIPE — under pipefail the pipeline reports 141 even on a real match.
_code="$(grep -vE '^[[:space:]]*#' "$SUITE")"
if grep -qE 'git -C "?\$?[a-zA-Z0-9_]+"? +merge-base HEAD refs/remotes/origin/main' <<<"$_code"; then
  printf 'merge-base\n'
  exit 0
fi
printf 'FAIL: no live `git merge-base HEAD refs/remotes/origin/main` call found in %s\n' "$SUITE" >&2
exit 1
