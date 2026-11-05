---
title: "A ruled correction needs back-propagation to every artifact in the same diff"
date: 2026-11-04
category: workflow-patterns
issue: 11711
---

# A ruled correction needs back-propagation to every artifact in the same diff

## What happened

On PR #12105 (docs-only audit/census deliverable), a CTO ruling corrected "four Terraform roots" to three. The ruling landed in `decision-challenges.md` and the new census artifact said "three roots" — but the **plan file and session-state.md kept the pre-correction wording**, creating three same-PR contradictions. Three of four review seats each found an instance of it. The class generalized: a fabricated step-name anchor, a stale "endpoint does not expose" claim contradicting the artifact's own measurement, and unannotated TSV-derived counts all shared the same shape — **upstream artifacts were never re-read against downstream corrections**.

## The fix

One targeted fix round: all stale claims rewritten to the corrected record, provenance labeled, anchors converted to `file › symbol` form.

## The pattern

- When a ruling corrects a fact, grep the SAME DIFF for the wrong phrasing — `git diff origin/main...HEAD` scoped, not just the file the ruling amended. The plan, session-state, tasks and deliverables are one evidentiary unit; reviewers read them as such.
- "Imprecise, count and split exact" rulings are the worst kind: every file carrying the imprecise form is technically wrong while looking plausible, and each seat reports it at a different severity.
- Cheap guard that would have caught it: `grep -n 'four' knowledge-base/project/{plans,specs}/<branch>/*` after recording any numeric/enumeration ruling.

## Evidence

- `decision-challenges.md` Item 6 vs plan:49/158/247 + session-state:13 on PR #12105 — three seats (pattern P1, code-quality P2, history P1) each found a different copy.
