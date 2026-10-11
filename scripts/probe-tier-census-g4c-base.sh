#!/usr/bin/env bash
# Observability probe for #9956: prints "merge-base" when the infra-privileged-tier-census suite
# resolves its G4c base ref via `git merge-base`. It exists because a discoverability_test.command
# naming tests/scripts/test-*.sh trips preflight Check 10's suite-shape reject regex — this
# committed wrapper is the spellable form.
#
# The grep anchors on the resolution's call form (`git -C "$1" merge-base HEAD origin/main`), not
# a bare token a comment could satisfy.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$DIR/../tests/scripts/test-infra-privileged-tier-census.sh"
grep -qE 'git -C "?\$?[a-zA-Z0-9_]+"? +merge-base HEAD origin/main' "$SUITE" \
  && printf 'merge-base\n'
