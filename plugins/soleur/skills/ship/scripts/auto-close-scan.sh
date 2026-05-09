#!/usr/bin/env bash
# Scan a PR title or body file for GitHub auto-close keyword + #N references.
#
# Usage: bash auto-close-scan.sh <body-file>
#
# Output contract (stdout): one line per match, in `<line-number>:<matched-text>`
# form (the `grep -n` line-prefix format). Agent consumers can parse line
# numbers via `awk -F: '{print $1}'` and the matched substring via
# `cut -d: -f2-`. Empty stdout = no matches. The format is asserted by TS7 of
# `plugins/soleur/test/auto-close-scanner.test.sh` — change with care.
#
# Exit code: 0 always (fail-soft per #3407 — auto-close keywords are sometimes
# intentional, e.g. `Closes #N` on its own line. The caller decides whether to
# block or warn.) Note: deliberately NOT `set -e` because `grep` exits 1 on
# no-match; the trailing `|| true` handles that path.
#
# GitHub's auto-close keyword set (verified against
# https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue):
#   close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved
# Issue-reference forms recognized: `#N` and `GH-N` (cross-repo shorthand).
# `OWNER/REPO#N` and full URLs are out of scope (rare in practice).
#
# The parser is markdown-blind: matches inside checkboxes, code blocks,
# blockquotes, and prose all auto-close. PR #3185 was closed twice in three
# days by the same trap (#3200 via title, #3402 via body checkbox).

set -uo pipefail

# Locale-pin: `\b` word-boundary semantics shift across locales. GHA runners
# default to C.UTF-8 which is fine, but pinning makes the scanner deterministic
# everywhere it runs (local pre-creation scan in /ship, CI workflow, future
# homedir invocations).
export LC_ALL=C

BODY_FILE="${1:?body file path required}"

if [[ ! -f "$BODY_FILE" ]]; then
  echo "auto-close-scan: file not found: $BODY_FILE" >&2
  exit 0
fi

PATTERN='\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)\b'

grep -niE "$PATTERN" "$BODY_FILE" || true
exit 0
