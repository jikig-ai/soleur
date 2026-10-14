#!/usr/bin/env bash
# SYNTHESIZED FIXTURE — never executed, never registered as a suite. It exists only to be READ
# by scripts/battery-tag-authorship.test.sh, and only when a mutation row lifts its entry from
# that guard's FIXTURE_EXCLUSION.
#
# It carries ONE unsuppressed, undeclared tag-authoring command: exactly the false negative the
# guard exists to prevent. Two guard components are pinned by it, each of which was measured
# SURVIVING a mutation before this file existed:
#   - VERB_RE's `fetch|pull` alternation. Dropping it took occurrences 41 -> 13 with the guard
#     still GREEN over a live unsuppressed fetch.
#   - _suppresses' FIRST conjunct (the `--no-tags` requirement). Dropping it graded this line
#     SUPPRESSED despite it carrying no suppression at all.
#
# It lives in its OWN file, not beside the other fixtures, because FIXTURE_EXCLUSION is keyed by
# PATH: fixtures sharing a file become visible together, and a row that needs this one visible
# would then also expose the others and redden for a reason it is not testing.
_battery_tag_fixture_bare_fetch() {
  git fetch origin main
}
