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
# The vocabulary is deliberately in TWO groups. The first is a USER-FACING outage
# ("users could not", "went down"). The second is a DELIVERY outage: nothing the
# user can see is down, but shipping is stopped — releases blocked, production
# pinned N versions behind. That is still a production incident and still owes a
# PIR, and none of the user-facing verbs describe it. **Why:** #7242 — every
# `Web Platform Release` failed for four hours and production sat three releases
# behind, and this gate returned "no incident signal" on the PR that fixed it,
# because the report says "failed at the zot-mirror bridge" and "pinned three
# releases behind" rather than "failed in production". The gate that exists to
# stop an incident shipping without its learning missed a textbook one.
OUTAGE_RE='(incident report|post-?incident|post-?mortem|outage|went down|was down|took down|brought down|stopped working|silently (broke|broken|failing)|regression in prod|users? (could not|were unable to)|shipped broken|ran broken|failed in prod(uction)?|broke prod(uction)?|releases? behind|(releases?|deploys?|deployments?) (was|were) blocked|blocked (every|all) (release|deploy))'
# `prod` is boundary-guarded — this is the SAME substring class the header above
# documents fixing for `incident`/`incidental`, left unfixed one line below it.
# Measured on the PR that found it: bare `prod` matched 14 times in the haystack
# and NOT ONCE as the word `prod` or `production` — every hit was `producer`,
# `produced`, `product`, `reproduced`. Plans are dense with all four ("the session
# that produced these six items", "a producer/consumer pair"), so the production
# conjunct was satisfied by essentially every plan, and the whole gate reduced to
# its outage half. A `post-mortem` reference to a LOCAL test-runner retrospective
# then demanded a PIR for an event that never happened.
#
# NO `\b` — the host grep is ugrep, where `\b` is not a word boundary in ERE and
# silently matches nothing, which would delete the alternative rather than bound
# it. `[^a-zA-Z]` is spelled with both cases explicitly because these greps run
# under `-i`, where a bare `[^a-z]` is implementation-defined.
#
# `prod(uction)?` keeps `production` matching (every positive fixture relies on
# that exact word); the trailing guard is what rejects `produc*`.
#
# `live` is guarded on BOTH sides, and fixing only `prod` would have been the
# same soundness-for-completeness swap this gate keeps re-learning: unguarded,
# `live` matches `lives` on the right ("the parser lives in a real file" is
# ordinary prose here) and `delivery`/`delivered`/`deliverables` on the left.
# Standalone `live` stays a production token — only the substrings are rejected.
PROD_RE='(prod(uction)?([^a-zA-Z]|$)|deployed|([^a-zA-Z]|^)live([^a-zA-Z]|$)|app\.soleur\.ai|tenant-zero|customer)'

# The ONLY discriminator between "a plan citing a closed incident as precedent" and "a plan
# reporting an unreported outage" inside a hypothetical paragraph — the two are otherwise
# textually identical, so this is a whitelist, not a decision procedure.
# Vocabulary is MEASURED, not imagined: across the 4116 lines that fall inside a stripped
# paragraph in all 1548 plans, `already happened` hits 4x and `not hypothetical` 1x; every other
# phrasing tried (`this happened`, `did happen`, `has happened`, `actually happened|occurred|
# fired`) hit ZERO. `already occurred` is kept as the one unmeasured near-miss of the measured
# winner. Adding an alternative requires a corpus hit or a fixture — the same bar as OUTAGE_RE.
# Every fail-open found in the wild adds a phrase HERE and a fixture; do NOT widen or narrow the
# paragraph rule instead. **Why:** #7801 R3.
ACTUALITY_RE='already (happened|occurred)|not hypothetical'

# Strip, in order:
#   1. fenced code blocks (``` … ```) — regexes/config/SQL quoted in a plan are
#      DATA, not an incident report (a plan that documents this very gate quotes
#      `OUTAGE_RE='(outage|incident|…)'`);
#   2. inline `code` spans — same reason, for backticked tokens;
#   3. the threshold declaration (frontmatter key + the bold User-Brand-Impact
#      label) and the hypothetical/conditional framing lines, so trigger 3 does
#      not read a plan's own metadata or its "if this lands broken" section as
#      an incident. The strip is PARAGRAPH-scoped, not line-scoped (#7801): the
#      label line opens a window that runs to the next block boundary, because
#      #6813 removed the framing LINE and left the sentences after it in the
#      same paragraph, so a plan CITING a past closed incident as design
#      precedent still read as an outage report. Three boundaries close the
#      window — a blank line, a heading, a new list item; tables and
#      blockquotes deliberately do NOT (an accepted residual, named so the
#      omission stays a decision). An actuality idiom (ACTUALITY_RE) re-opens
#      it: once a paragraph says the event HAPPENED, the rest of it is a
#      report. The strip is LEXICAL and cannot decide precedent-citation from
#      self-report — a real outage phrased without an actuality idiom inside
#      the paragraph is swallowed, pinned as a characterization fixture rather
#      than left undocumented;
#   4. the `Network-Outage Deep-Dive determination` HEADING (deepen-plan Phase
#      4.5, recorded per `hr-ssh-diagnosis-verify-firewall` so an N/A skip is
#      auditable). This is a plan-TEMPLATE section name, not an outage claim —
#      and since nearly every plan carries some prod word, matching the word
#      `Outage` inside it made the gate fire on any plan that recorded the
#      determination, including ones whose body says the checklist is "not
#      applicable rather than unverified". Same structural-artifact shape as
#      (3): only the heading LINE is stripped, so a real outage claim inside
#      that section still signals. **Why:** #7003.
# Residual (accepted): a plan whose SUBJECT is incident detection still discusses
# outages in prose and may signal — that is fail-toward-PIR over-production the
# operator hand-adjudicates, not the #6813 false-positive class (which was every
# ordinary `single-user incident` plan tripping on the threshold label alone).
# shellcheck disable=SC2016  # the sed backticks are literal (inline-code strip), no expansion wanted
#      Same class, second instance (#6665): "network-outage" is the NAME of the
#      plan-skill Phase 1.4 gate, and every plan that documents it firing writes
#      the phrase — so the bare `outage` alternative matched a gate name, not an
#      event, on a CI-perf PR with no production incident. Gate NAMES are stripped
#      below (not added to a negative lookahead) so the token cannot reach
#      OUTAGE_RE at all; this is the same shape as the threshold-label strip.
# shellcheck disable=SC2016  # the sed backticks are literal (inline-code strip), no expansion wanted
# The assignment is GUARDED (#7801). A broken strip stage would otherwise empty
# the haystack, exit 1, and read as a clean no-signal — byte-identical to "this
# PR is fine" on a surface where nothing is watching: this gate ships to a
# customer's own CLI (observability layer 7), where there is no CI run to notice
# an awk that does not accept the program. So a pipeline FAILURE fires.
#
# The terminal `grep -v` needs the `|| [ $? -eq 1 ]` arm because grep exits 1
# when it selects NO lines, which is the ordinary outcome for an empty PR body
# or one whose every line is filtered. Measured: without the arm the guard fires
# on empty stdin and reports an incident for a PR with no text at all. Exit 2 (a
# real grep error) still propagates. The plan prescribed the bare guard; the
# premise was checked against `cat` and does not hold for `grep -v`.
if ! haystack="$(cat \
  | awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; print ""; next} !f{print}' \
  | sed 's/`[^`]*`//g' \
  | sed -E 's/[Nn]etwork-[Oo]utage//g' \
  | awk -v ACTUALITY_RE="$ACTUALITY_RE" 'BEGIN{skip=0}
       # --- ORDER IS THE DESIGN (#7801). Boundaries reset; the trigger opens; the re-admit closes.
       # A block boundary always prints and can never be eaten as paragraph body, so these come first.
       # The hash rule requires a space or EOL after the run of `#` — a bare /^[[:space:]]*#/ treats a
       # `#6691` continuation line as a heading and lets the outage claim after it through, which
       # defeats this fix on a reflow of its own target class (R7). Tables and blockquotes are NOT
       # boundaries: an accepted residual, listed here so the omission is deliberate, not forgotten.
       /^[[:space:]]*$/                                 {skip=0; print; next}
       /^[[:space:]]*#+([[:space:]]|$)/                 {skip=0; print; next}
       # The label line. ANCHORED, and ABOVE the list-item rule so a bulleted label is consumed
       # rather than read as a new block. The anchor bounds a STATEFUL rule: unanchored, one
       # subordinate clause silences a whole paragraph. This trigger list is a deliberate SUBSET of
       # the line-scoped `grep -vaiE` below (no `would break`/`could break`: those are mid-sentence
       # conditionals, and paragraph-scoping them would swallow arbitrary prose).
       tolower($0) ~ /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?[*_]*if this (lands|leaks)/ {skip=1; next}
       # A NEW list item is a NEW markdown block. (A nested sub-bullet also resets — deliberate,
       # and the fail-toward-fire direction.)
       /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)/ {skip=0; print; next}
       # Once a paragraph says the event HAPPENED, the rest of it is an incident report.
       tolower($0) ~ ACTUALITY_RE                       {skip=0; print; next}
       # --- Rules below run only inside a skip window. Do NOT append past this line: it is dead code.
       skip                                             {next}
                                                        {print}' \
  | { grep -vaiE '^brand_survival_threshold:|Brand-survival threshold:|If this lands broken|If this leaks|if this lands|would break|could break|Network-Outage Deep-Dive' || [ "$?" -eq 1 ]; })"; then
  echo "INCIDENT-SIGNAL: yes"
  echo "ship-incident-pir-gate: strip pipeline failed — failing toward PIR (#7801)" >&2
  exit 0
fi

# Herestrings (no pipe) — a piped `grep -q` under pipefail can SIGPIPE on an
# early match and invert the result; a herestring cannot.
if grep -qiE "$OUTAGE_RE" <<<"$haystack" && grep -qiE "$PROD_RE" <<<"$haystack"; then
  echo "INCIDENT-SIGNAL: yes"
  exit 0
fi
exit 1
