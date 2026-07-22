#!/usr/bin/env bash
# ship-incident-pir-gate.sh — the /ship Phase 5.5 Incident-PIR signal scan (#6813).
#
# Reads a PR/plan haystack on stdin. Exit 0 + prints "INCIDENT-SIGNAL: yes" when
# the text looks like a PRODUCTION-INCIDENT fix (a past-tense outage signal AND a
# production signal); exit 1 (no output) otherwise. The script OWNS the regexes,
# so ship/SKILL.md and the test invoke it directly and drift is impossible —
# replacing the old pattern of scraping the regex literals out of Markdown prose
# (which also carried an `A && B && echo` `set -e` foot-gun the script now avoids
# by owning its own exit semantics).
#
# Why the old regex fired on every `single-user incident` plan (#6813):
#   1. bare `incident` matched the `brand_survival_threshold: single-user incident`
#      frontmatter label present in EVERY such plan;
#   2. no word boundary, so `incident` matched inside `incidental`;
#   3. no hypothetical exclusion, so a `## User-Brand Impact` section describing
#      what breaks *if this lands broken* read as an outage report.
# This gate strips the threshold label + hypothetical framing first, then matches
# only PAST-TENSE / report vocabulary.
set -uo pipefail

# Past-tense / report outage vocabulary. NO bare `incident` (it matches the
# threshold literal and `incidental`); word-boundaried; requires a signal that
# something HAPPENED, since a PIR is owed for an event, not a hypothetical.
OUTAGE_RE='(incident report|post-?incident|post-?mortem|outage|went down|was down|took down|brought down|stopped working|silently (broke|broken|failing)|regression in prod|users? (could not|were unable to)|shipped broken|ran broken|failed in prod(uction)?|broke prod(uction)?)'
PROD_RE='(prod|production|deployed|live|app\.soleur\.ai|tenant-zero|customer)'

# Strip the threshold declaration (frontmatter key + the bold User-Brand-Impact
# label) and the hypothetical/conditional framing lines, so trigger 3 does not
# read a plan's own metadata or its "if this lands broken" section as an incident.
haystack="$(cat | grep -vaiE '^brand_survival_threshold:|Brand-survival threshold:|If this lands broken|If this leaks|if this lands|would break|could break')"

# Herestrings (no pipe) — a piped `grep -q` under pipefail can SIGPIPE on an
# early match and invert the result; a herestring cannot.
if grep -qiE "$OUTAGE_RE" <<<"$haystack" && grep -qiE "$PROD_RE" <<<"$haystack"; then
  echo "INCIDENT-SIGNAL: yes"
  exit 0
fi
exit 1
