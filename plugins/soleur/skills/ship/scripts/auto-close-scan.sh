#!/usr/bin/env bash
# Scan a PR title or body file for GitHub auto-close keyword + #N references.
#
# Usage: bash auto-close-scan.sh <body-file>
#
# Output contract (stdout): one line per match, in `<line-number>:<matched-text>`
# form, in ascending line order. Agent consumers can parse line numbers via
# `awk -F: '{print $1}'` and the text via `cut -d: -f2-`. Empty stdout = no
# matches. The format is asserted by TS7 of
# `plugins/soleur/test/auto-close-scanner.test.sh` — change with care.
#
# A SPLIT match (keyword ending line N, reference starting the next non-blank
# line) is reported at N with the two lines joined by one space, so its text is
# NOT a substring of the file: fix it by rewording line N, not by rewrapping.
# One line can appear twice (a same-line match plus a split match). CRs are
# stripped, so CRLF input yields clean records.
#
# Exit code: 0 always (fail-soft per #3407 — auto-close keywords are sometimes
# intentional, e.g. `Closes #N` on its own line. The caller decides whether to
# block or warn.) A scan that cannot run says so on stderr; stdout stays empty.
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

set -u

# Locale-pin: `[[:alnum:]_]` and `tolower()` depend on the locale.
export LC_ALL=C

BODY_FILE="${1:?body file path required}"

if [[ ! -f "$BODY_FILE" ]]; then
  echo "auto-close-scan: file not found: $BODY_FILE" >&2
  exit 0
fi

# The keyword and reference vocabularies, stated ONCE. The pre-merge hook's
# parity test (.claude/hooks/pre-merge-auto-close-scan.test.sh) reads KW from
# this line, so keep it a single-quoted literal.
KW='close[sd]?|fix(es|ed)?|resolve[sd]?'
REF='#[0-9]+|gh-[0-9]+'

# One pass. GitHub treats ANY whitespace between keyword and reference as a
# separator, newlines included: #8514's squash commit wrapped "...would
# auto-close" / "#8285, so..." and closed #8285, which a line-at-a-time grep
# cannot see. Input is read by redirect so a path like `a=b` is never taken for an
# awk assignment. Word boundaries are `[^[:alnum:]_]` classes (grep's `\b`), and
# matching is on a lowercased copy while the ORIGINAL text is printed.
awk -v kw="$KW" -v ref="$REF" '
  BEGIN {
    b = "(^|[^[:alnum:]_])"; e = "([^[:alnum:]_]|$)"
    same = b "(" kw ")[[:space:]]+(" ref ")" e
    tail = b "(" kw ")[[:space:]]*$"
    head = "^[[:space:]]*(" ref ")" e
  }
  {
    gsub(/\r/, "")
    if ($0 ~ /^[[:space:]]*$/) next
    line = $0; low = tolower(line)
    if (pend_nr && low ~ head) {
      t = line; sub(/^[[:space:]]+/, "", t)
      print pend_nr ":" pend " " t
    }
    if (low ~ same) print NR ":" line
    if (low ~ tail) { pend = line; sub(/[[:space:]]+$/, "", pend); pend_nr = NR }
    else pend_nr = 0
  }
' < "$BODY_FILE" || echo "auto-close-scan: scan failed (awk rc=$?): $BODY_FILE" >&2
exit 0
