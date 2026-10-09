# Learning: a status-flip amendment must not call a stand-in the approval it stands in for

## Problem

PR #9876 flipped ADR-276 `proposed` to `adopting` and ADR-270 `adopting` to `accepted` on the operator's chat
direction. ADR-276's Status section requires the CTO's approval as a review comment on a PR that edits the line. The
first draft of the amendment said the chat direction "is cited here as the CTO approval the Status section requires",
and the next paragraph said "a chat direction is not that comment". The new Stage-status bullet also said "S3 (#9728)
may now be merged" with no caveat. Two review seats (code-quality, git-history) and the security seat each flagged it;
no gate could, because the text is prose.

A second miss: ADR-270 was accepted ahead of its canary, and the amendment named only one superseded sentence. The
lead paragraph, the canary heading, an Item 4 sentence and the canary runbook heading in `infra/github/README.md` all
still read as if the flip were pending.

## Solution

- Word a stand-in as a stand-in: "stands in for the approval, pending the confirmation described next", then say in
  plain words that the required approval is OWED and not yet given.
- Do not let a sibling line (a status-table bullet) assert the downstream effect (a later stage may now merge) that
  depends on the missing approval; state the dependency or leave the effect to the amendment.
- When a status is set ahead of its stated precondition, list every surface the old status still governs BY ANCHOR
  TEXT (lead paragraph, headings, "stays X until" sentences, runbook headings), and add a pointer line at any
  non-ADR doc a reader may open alone.
- Cite evidence that exists outside the file (a PASS recorded on a tracker issue) rather than listing the item as
  unmeasured; both directions of misreport mislead a later reader.

## Key Insight

A governance record is read by someone who never saw the chat. Every sentence must be true of the file's state on its
own: "cited as the approval" and "is not the approval" cannot both stand, and the honest one is the second.

## Session Errors

- **Self-contradicting approval wording in the first draft of the ADR-276 amendment** — Recovery: reworded to
  "stands in for ... pending", approval stated as owed — Prevention: for any authority flip resting on a substitute
  for a required approval, grep the draft for the word "approval" and read each hit against the precondition text
  before commit.
- **Stale surfaces left by an ahead-of-precondition flip (README heading, lead paragraph, canary heading)** —
  Recovery: named by anchor in the amendment, pointer added to the README — Prevention: sweep the repo for the old
  status word as a SUBJECT (grep `ADR-270` near `adopting`), not only the files in the diff.
- **A trailing `grep -c` returning 0 made a batched check command exit 1** — Recovery: re-read each suite's own
  verdict line — Prevention: put the verdict-bearing command last or write `RC=$?` after each (already covered by the
  work skill's wrapper rule); one-off.
- **Plan-review panel and deepen fan-out skipped as disproportionate for a docs-only flip** — deliberate, recorded in
  session-state; the review phase caught the wording defects the panel would have.

Tags: category: logic-errors; module: architecture-decisions
