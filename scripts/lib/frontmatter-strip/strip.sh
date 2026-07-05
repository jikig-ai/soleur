#!/usr/bin/env bash
# frontmatter-strip contract — bash implementation (perl-backed, byte-exact).
#
# Canonical contract lives in SPEC.md; strip.py is the byte-identical Python
# twin. `scripts/lib/frontmatter-strip.test.sh` feeds shared fixtures to BOTH
# and asserts parity — the mechanical replacement for "keep two regexes
# identical by hand" (issue #5999, ADR-085).
#
# Sourced by .claude/hooks/session-rules-loader.sh (defines `strip_frontmatter`);
# also runnable as a filter: `bash strip.sh < file`.
#
# Behavior: iff the input BEGINS with the exact line `---` (i.e. starts with
# `---\n`), delete from the start through the next line that is exactly `---`
# (inclusive of that line's trailing newline); everything after is byte-
# verbatim. If the opening `---` has NO matching closing `---`, the ENTIRE input
# is consumed (empty output) — the malformed/over-strip signal the loader + lint
# guards detect via a rule-line-count drop. No leading `---\n` → unchanged.
strip_frontmatter() {
  perl -0777 -pe 's/\A---\n(?:.*?\n---\n|.*\z)//s' 2>/dev/null
}

# When executed directly (not sourced), act as a stdin→stdout filter.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  strip_frontmatter
fi
