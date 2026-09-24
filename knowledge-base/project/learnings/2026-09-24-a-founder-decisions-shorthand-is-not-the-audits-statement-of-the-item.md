---
title: "A founder decision's shorthand is not the audit's statement of the item"
date: 2026-09-24
category: workflow-patterns
module: competitive-analysis
tags: [audit-record, founder-decisions, inherited-claims, docs-review]
---

# Learning: a founder decision's shorthand is not the audit's statement of the item

## Problem

PR #8648 wrote the founder's 2026-09-23 decisions into the mattpocock/skills audit record
(`knowledge-base/product/competitive-intelligence.md`). The brief was accurate in substance but
compressed. Three of its phrasings, copied as written, would have left the record contradicting
itself or its sources:

- The writing-trio decline: "its 'leading words' idea already shipped". The first draft turned
  this into "their one transferable idea, leading words, already shipped". But the audit's own
  §2 names the idea as the leading word **and** grounding, and only the first shipped
  (`skill-creator/references/authoring-levers.md` §Leading words).
- The justification for not adding declines to `rejected/`: "ADR-234 excludes redundancy findings
  and refused mechanisms". ADR-234 excludes redundancy findings ("built is not rejected") and does
  not exclude mechanism refusals. The no-list README also says the record is "deliberately not
  called a register".
- "#8505 is stale on the open-issues line". It was, and so was `#8497`. The brief named one stale
  entry and the line had two.

## Solution

- Plan phase: every claim in the brief was re-derived. Issue states were checked with
  `gh issue view N --json state`. ADR-234 was checked against its file. PR #8647 was checked
  against `git show --stat e5a725a5e1` and the "Bundle 6" paragraph in `plugins/soleur/NOTICE`.
- Review phase: the code-quality seat compared each added sentence against the file's own dated
  sections and the no-list README. The simplicity seat flagged "Not adopted" clauses that repeated
  NOTICE one line above a pointer to it.

## Key Insight

A decision record is shorthand for something an audit already stated in full. Before writing a
disposition ("declined because it already shipped", "bundled", "superseded"), re-read the audit
row the item came from and write the disposition against that statement. Any sentence copied
from a brief should be checked against the artifact the brief summarises.

## Session Errors

1. **The previous one-shot run was killed by an API session limit early in the pipeline.**
   Recovery: resumed from `git log origin/main..HEAD`. Only the init commit existed, so planning
   ran fresh. **Prevention:** none needed. The resume path (check commits, then re-run the missing
   steps) worked as designed.
2. **The brief's ADR-234 claim was only half right** ("excludes refused mechanisms").
   Recovery: the plan's reconciliation table corrected it, and review corrected the "register"
   wording. **Prevention:** routed to `competitive-analysis/references/peer-plugin-audit.md`
   §Output routing. Write dispositions against the audit's own statement, and note that ADR-234
   holds refused product concepts.
3. **The brief named one stale issue (#8505) where the line had two (#8497 too).** Recovery: the
   plan ran `gh issue view` on every number on the line. **Prevention:** the brief already said to
   re-check every number, and that instruction is what caught it. No new rule.
4. **Plan-authoring lint and AC slips: MD038 code spans, nested backticks, and an AC4 grep that
   also matched the dated §4 rows.** Recovery: all fixed before commit. **Prevention:** existing
   markdown lint plus the deepen pass's anchor-uniqueness checks.
5. **The first draft overclaimed "one transferable idea, leading words" and repeated NOTICE's
   not-adopted clauses.** Recovery: review P2 fixes in commit fd933624ad. **Prevention:** the
   routed peer-plugin-audit bullet above.
6. **`test-all.sh --print-affected-set` took more than 120 s on a contended box (two sibling
   full-gate runs) and was moved to the background.** Recovery: read its output after it
   finished. For a docs-only diff, ran the KB-index suites directly. **Prevention:** one-off.
   Check `--capacity` first on a busy box.

## Tags

category: workflow-patterns
module: competitive-analysis
