# Learning: a string-correction PR hedged one line and left the lines that print under the same condition

## Problem

PR #11841 (#11667 item 2b) corrected operator-facing strings in `apply-web-platform-infra.yml` after the restore engine started exiting 6 for unclassified read faults. The plan-time edit set was reviewed by four plan reviewers and three CTO rounds, and still shipped three P2s to review, none caught by a test:

1. **Heading hedged, body not.** The recut summary heading became "may be EMPTY" because the refill flag is set BEFORE the apply and the summary step is `if: always()` (so it can print when nothing was destroyed). The next body line still said "The fresh volume is luksFormatted and empty". Heading and body print under the SAME condition; only one was hedged.
2. **A retry claim written without reading the runbook branch the arm points to.** The exit-5 arm gained "retrying unchanged will not clear it". The runbook's measured `htpasswd_push_matches=true` branch says the remedy IS a re-run. The census had covered the strings being REMOVED, not the claim the NEW sentence adds.
3. **A pin that checked tokens, not the clause.** The RED check for the exit-6 arm matched two bare substrings (`unverified`, `do not deploy`) on one line. Review mutants "the store is not unverified: it is safe to deploy now" and "the store is verified; ignore the old unverified warning and the old do not deploy rule" both gave 0 FAIL.

Also: an exit-6 repeat had no off-ramp in the arm (a deterministic `CONTENTMISMATCH`/`LAYERFORMAT` is where runbook row 6 sends the operator to a `crane validate --remote` discriminator).

## Solution

CTO rulings (five rows, `decision-challenges.md` "Review round A..E"): row-pointer off-ramp and "re-run this job by hand" (+53 B); body hedge "If the store was rebuilt, ..." (+26 B); exit-5 retry claim deleted (-42 B); redundant comment line dropped (-86 B); W9 pins the clauses `store unverified` and `do not deploy until a re-run exits 0` case-insensitively, full-message control needles, and a must-PASS `reword6` control (floor 94). Net: workflow 489,568 B, 112 B under `origin/main`, inside a standing "net-negative" constraint that had to fund every addition.

## Key Insight

For a string-correction PR, build the edit set from the PRINT CONDITION, not from the sentence: list every line that prints when the corrected line prints (same step, same `if:`, same flag) and decide each; and for every claim a NEW sentence adds, read the document the sentence points at and find the branch that contradicts it. Both are the "correct the subject, not the phrasing" rule applied to the claim you are WRITING rather than the one you are deleting. A pin on a safety claim must match the clause, with one must-PASS rewording and one contradiction mutant, or it certifies the spelling.

## Session Errors

- **Ruling class outside the closed list (`operator (authorization)`).** Recovery: rewritten to `production-mutating`; gate re-run. **Prevention:** the ruling gate already enforces it; the planning brief's class list should name the closed set.
- **Stale hand-off byte figure (488,896 vs 489,680).** Recovery: `wc -c` at start, corrected in the brief. **Prevention:** existing rule "plan-quoted numbers are preconditions to re-measure"; held.
- **R1/E5 claims asserted at plan time without the sibling-line / runbook-branch check.** Recovery: review round, CTO rulings B and C. **Prevention:** see Key Insight; the existing coverage is review/SKILL.md "I widened the sentence and left its clauses behind" (#7881) and "every correction I shipped needed correcting" (#8296); no new rule, since the corpus already carries both and a third restatement would only add weight.
- **Bare-token RED pin.** Recovery: clause-anchored needles plus `reword6`. **Prevention:** existing cq-assert-anchor-not-bare-token; held at review by the test-design seat's mutants.
- **Collision pre-check matched my own PR; hand-rolled greps and a two-revision `rev-parse`.** One-offs, no recurrence vector.

## Cost note (reported honestly)

A -49 B net string edit ran: a planning subagent (~370k tokens, three CTO rounds), an 8-seat review panel (git-history, pattern, architecture, security, code-quality, test-design, structural, simplicity), a CTO review round, and a 4-seat fix round. Cause: the diff contains a `.sh` file, so the classifier says `code` (8 seats), and the "verbatim prose-plan" exception fails its condition (d) because the workflow is a production-apply path. The panel was not wasted (3 P2s, 0 P1; the test-design seat's mutants and the git-history seat's runbook cross-check each found a real defect), but a workflow edit that changes only `echo` text and `#` comments has a narrower honest seat set than 8, and nothing in the classifier expresses that.

## Tags
category: workflow-issues
module: apply-web-platform-infra, registry-restore, review
