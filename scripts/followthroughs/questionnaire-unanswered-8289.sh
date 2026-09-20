#!/usr/bin/env bash
# (#8289) Is the founder still waiting on an answer, past the date they themselves asked for it?
#
# WHY THIS SIGNAL AND NOT A USAGE COUNT. `soleur:questionnaire-generate` writes a document the
# founder sends to an accountant, a lawyer, an auditor, an insurer, a bank or a landlord. The thing
# that goes wrong is not that the skill is unused — it is that a question went out, the reply never
# came, and the decision it was blocking quietly stayed blocked. Nobody notices, because the person
# waiting is the one person who is not going to audit a directory.
#
# The deadline is not invented here. `needed_by` is the date the founder stated in their own words
# during the interview, so this probe measures the founder's declared expectation rather than a
# proxy somebody chose for them. A probe that picked its own window would be nagging about a
# schedule the founder never agreed to.
#
# WHY IT NEEDS NO POSITIVE CONTROL. A count over a store cannot tell "nobody used it" from "the
# counter is broken". Here the subject's having run is INTRINSIC to the signal: a file exists in
# that directory only because the skill emitted one. So the absence of files is reported as
# CANNOT ESTABLISH, never as a pass.
#
# REPORTER IS NOT THE SUBJECT (#6737, ADR-126). This runs on the follow-through sweeper and never
# from inside the skill it measures.
#
# ── THIS PROBE NAMES NO ONE, AND NAMES NO ASK ───────────────────────────────
# `scripts/sweep-followthroughs.sh` captures this script's output and republishes it into a public
# issue comment on every sweep. So it reports COUNTS and nothing else. A filename here would carry
# the recipient's role and the topic of the ask into the comment thread — "founder asked a lawyer
# about X" is a fact about the business, and the exit code plus a number is enough for the operator
# to go and look. The directory's own contents are a separate surface with its own discipline
# (knowledge-base/project/questionnaires/README.md); what this file controls is the sweeper comment.
#
# ── EXIT CONTRACT — NOTIFY-ONLY ──────────────────────────────────────────────
#   0  NEVER TAKEN. Exit 0 is the sweeper's CLOSE verb. Whether to chase an accountant is a
#      judgement about a relationship, and no probe has earned the authority to declare it settled.
#   1  NEVER TAKEN. Exit 1 is the sweeper's FAIL verb AND its reopen trigger on a closed tracker.
#      "The reply has not arrived yet" is not a failure of anything.
#   2  NOT YET — the measurement was made; nothing is past its own needed_by.
#   3  CANNOT ESTABLISH — the measurement could not be made (no directory, no questionnaire yet,
#      or an entry whose frontmatter cannot be read).
#   5  ACTION REQUIRED — at least one answer the founder is waiting on is overdue. Go look.
#   64 usage.
#
# WHY 2 AND 5 ARE DIFFERENT CODES. The sweeper renders `TRANSIENT (exit $rc, <date>)` in the comment
# HEADING and folds the body behind a `<details>`. The exit code is the only thing the operator sees
# without expanding, so one code for both outcomes posts a byte-identical heading every day forever,
# including on the day the answer stopped coming.
#
# WHY NO `set -e`. `-e` would hand this file a path to exit 1 — a code its contract says it must
# never take — reachable by adding any future unguarded command. Every failure path below is
# explicitly guarded and ends on a code this file chose.
set -uo pipefail

# No credentials are read, no network call is made, and the directive carries no `secrets=` clause,
# so there is nothing for an xtrace to leak here.

QDIR_REL="knowledge-base/project/questionnaires"

cannot_establish() {
  printf 'CANNOT ESTABLISH: %s\n' "$1"
  exit 3
}

usage() {
  printf 'usage: %s\n' "${0##*/}"
  printf '  (no args)  report whether any emitted questionnaire is past its own needed_by\n'
  exit 64
}

[[ $# -eq 0 ]] || usage

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"
[[ -n "$REPO_ROOT" ]] \
  || cannot_establish "the repository root could not be resolved from this script's own location. Operator: no action — engineering fault, file it."

QDIR="$REPO_ROOT/$QDIR_REL"
[[ -d "$QDIR" ]] \
  || cannot_establish "${QDIR_REL} does not exist in this checkout, so no questionnaire can be read. Operator: no action — engineering fault, file it."

# The dated-slug pattern is the entry test, and it is mechanical rather than advisory: the
# directory's own README.md would otherwise be swept up and reported as an unanswered question.
shopt -s nullglob
entries=()
for f in "$QDIR"/*.md; do
  base="${f##*/}"
  [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$ ]] || continue
  entries+=("$f")
done

if (( ${#entries[@]} == 0 )); then
  cannot_establish "no questionnaire has been emitted yet — ${QDIR_REL} holds no dated entry. This is NOT a pass: the skill may simply not have been reached. Operator: no action."
fi

# Read ONE frontmatter field. Bounded to the leading `---` block, and it prints the value only for
# the key asked for, so no other frontmatter content can reach a variable and from there the
# sweeper's comment.
fm_field() {
  awk -v want="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    {
      i = index($0, ":")
      if (i > 0) {
        key = substr($0, 1, i - 1)
        val = substr($0, i + 1)
        gsub(/^[ \t]+|[ \t]+$/, "", key)
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (key == want) { print val; exit }
      }
    }
  ' "$1" 2>/dev/null
}

TODAY="$(date -u +%Y-%m-%d 2>/dev/null)"
[[ "$TODAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || cannot_establish "today's date could not be read as a plain ISO day. Operator: no action — engineering fault, file it."
TODAY_S="$(date -u -d "${TODAY}T00:00:00Z" +%s 2>/dev/null)"
[[ "$TODAY_S" =~ ^[0-9]+$ ]] \
  || cannot_establish "today's date could not be converted to a timestamp. Operator: no action — engineering fault, file it."

n_total=0
n_sent=0
n_overdue=0
n_bad=0

for f in "${entries[@]}"; do
  n_total=$((n_total + 1))
  status="$(fm_field "$f" status)"
  needed="$(fm_field "$f" needed_by)"

  # Malformedness is a COUNTED PREDICATE, never a caught exception carrying the value that caused
  # it: `date -u -d "$bad"` prints `date: invalid date '<value>'`, and that value would land in a
  # public comment. Every read below is guarded and nothing echoes file content.
  # THREE states, and `draft` is the one that keeps this sweep honest. This skill EMITS a document;
  # the founder sends it later, by hand, from their own mail client. An emitted file therefore claims
  # nothing about whether it was sent, and an earlier revision emitted `status: sent` at write time —
  # so an unsent draft became an ACTION REQUIRED on its own `needed_by`, reporting an overdue answer
  # to a question nobody had asked. `draft` is a valid, readable state that is simply not yet
  # awaiting a reply: it must not count as malformed (that would be a CANNOT ESTABLISH) and must not
  # count as overdue (that would be the false alarm).
  case "$status" in
    draft | sent | answered) ;;
    *) n_bad=$((n_bad + 1)); continue ;;
  esac
  [[ "$needed" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { n_bad=$((n_bad + 1)); continue; }

  needed_s="$(date -u -d "${needed}T00:00:00Z" +%s 2>/dev/null)"
  [[ "$needed_s" =~ ^[0-9]+$ ]] || { n_bad=$((n_bad + 1)); continue; }

  # Only `sent` starts the clock. `draft` has not been sent and `answered` has come back.
  [[ "$status" == "sent" ]] || continue
  n_sent=$((n_sent + 1))
  if (( needed_s < TODAY_S )); then
    n_overdue=$((n_overdue + 1))
  fi
done

# An unreadable entry is refused rather than skipped: reporting "1 overdue" while silently failing to
# evaluate a second entry is the never-notice this exit contract exists to remove.
#
# BUT THE UNREADABLE COUNT IS A CAVEAT, NEVER A SUBSTITUTE, and the order below is the whole of that
# distinction. An earlier revision evaluated `n_bad` FIRST and exited 3 from inside it, so a single
# entry with a capitalised `status: Sent` — which the `case` arm does not match — replaced a real
# overdue ask instead of qualifying it. Measured: two entries, one genuinely overdue and one merely
# mis-capitalised, reported `CANNOT ESTABLISH` at rc=3 and the ACTION line was absent from the output
# ENTIRELY, not merely demoted. `scripts/sweep-followthroughs.sh` maps rc to the heading an operator
# reads without expanding the `<details>` block (2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED), so
# the overdue ask disappeared from the only line most readers see. That is the same shape as the arm's
# own comment, inverted: the masking entry was the one that could not be evaluated, and the thing it
# masked was the actionable signal.
#
# So: ACTION wins whenever there is one, the unreadable count rides along as a named caveat, and
# CANNOT ESTABLISH is the verdict only when there is nothing actionable to report. Both facts always
# reach the operator; what changes is which one sets the heading.
bad_caveat=""
if (( n_bad > 0 )); then
  bad_caveat="CAVEAT: ${n_bad} of ${n_total} entr(ies) carry no readable status/needed_by pair and were NOT evaluated, so this count is a floor. Operator: correct the frontmatter in ${QDIR_REL} (status must be sent or answered, lower-case; needed_by must be YYYY-MM-DD)."
fi

if (( n_overdue > 0 )); then
  printf 'ACTION: %s questionnaire(s) are still marked sent past their own needed_by (%s still open, %s total entries, as of %s).\n' \
    "$n_overdue" "$n_sent" "$n_total" "$TODAY"
  printf 'The founder set that date themselves and the answer has not come back. This is NOT authority to chase anyone — whether to follow up, re-send or drop the question is the founder call.\n'
  printf 'Operator: open %s and look at the entries still marked sent. When a reply lands, paste it under ## Answers and set status to answered.\n' "$QDIR_REL"
  [[ -n "$bad_caveat" ]] && printf '%s\n' "$bad_caveat"
  exit 5
fi

# Nothing actionable. NOW an unevaluable entry is the most informative thing there is to say, because
# the "none overdue" it would otherwise report is a claim the run did not establish.
if (( n_bad > 0 )); then
  cannot_establish "${n_bad} of ${n_total} entr(ies) carry no readable status/needed_by pair, so the deadline test cannot be evaluated for them and no overdue ask was found among the rest. Operator: correct the frontmatter in ${QDIR_REL} (status must be sent or answered, lower-case; needed_by must be YYYY-MM-DD)."
fi

# All three counts are carried. "no entries open", "none overdue" and "everything answered" are
# different facts with different remedies, and one number cannot tell them apart.
printf 'NOT YET: %s questionnaire(s) checked as of %s; %s still marked sent, %s past their own needed_by.\n' \
  "$n_total" "$TODAY" "$n_sent" "$n_overdue"
exit 2
