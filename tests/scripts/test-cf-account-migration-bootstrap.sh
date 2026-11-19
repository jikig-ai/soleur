#!/usr/bin/env bash
# test-cf-account-migration-bootstrap.sh — runs the #12931 Doppler bootstrap's own suite
# (bootstrap.test.sh beside the generated bootstrap.sh in the #12931 spec directory, CTO ruling D11).
#
# Why a locator and not a direct run_suite line: archive-kb moves the spec directory to
# specs/archive/<ts>-feat-one-shot-12931-cf-account-migration/, which would break a hard-coded path
# in scripts/test-all.sh; the glob below finds the suite before and after the move. Exactly one
# match is required: zero or several is a harness error (exit 2), never a pass.
set -uo pipefail
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)" || { echo "HARNESS: not in a git work tree" >&2; exit 2; }
mapfile -t found < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard --full-name \
  '*feat-one-shot-12931-cf-account-migration/bootstrap.test.sh')
if [[ "${#found[@]}" -ne 1 ]]; then
  printf 'HARNESS: expected exactly one #12931 bootstrap.test.sh, found %s\n' "${#found[@]}" >&2
  exit 2
fi
exec bash "${REPO_ROOT}/${found[0]}" "$@"
