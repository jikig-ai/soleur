---
title: "My supersession pointer named the wrong bracket, and both my sweep anchors matched a sibling"
date: 2026-09-18
category: workflow-patterns
tags: [legal-records, append-only, article-30, adr, review, anchors, betterstack]
issue: 8309
pr: 8319
---

# My supersession pointer named the wrong bracket, and both my sweep anchors matched a sibling

## Problem

PR #8319 dated five Art. 30 register cells `Superseded` after the #7960 follow-through
PASSed, flipped ADR-211 to `accepted`, and narrowed a CLO attestation's open limb. Every
gate was green — 11 acceptance criteria, `lint-legal-registers.sh`, `markdownlint`,
`lint-infra-no-human-steps.py`, the C4 freshness and parity suites, and nine targeted test
files. Three of five review seats independently reported the same defect anyway.

The five entries opened `the INERT posture recorded immediately above is SPENT`. That is
true in three cells. In PA-8 §(g) the entry is appended at the cell's end in date order, so
roughly nineteen later-dated brackets sit between the inert sentence and the new one and
"immediately above" points at a 2026-09-15 Devin-matcher bracket ~30 kB away; in the Better
Stack vendor row it points at a 2026-09-08 bracket about a different control. On a statutory
register whose whole amendment contract is *quote, never edit*, a supersession pointer that
names the wrong bracket is a correctness defect, not a style nit — the reader is told which
sentence is spent and shown a different one.

## Root cause

The canonical entry was written once and pasted five times, which is correct for the parts
that must be identical (so a grep finds five identical records) and wrong for the one clause
that is a **locator**. A locator is a claim about each cell's local layout, and the layout
differs per cell precisely because the plan's own §(g) instruction says to append at the
cell's END rather than adjacent to the sentence being superseded. The plan noticed the
tension — it paraphrases the opener as "recorded above" when justifying that placement — and
the implemented text kept `immediately` anyway.

## Solution

`the INERT posture recorded above in this cell is SPENT`. One word removed; true in all five
cells; still greppable as one canonical string. §(g) additionally takes the plural
("sentences"), because that cell carries the inert posture twice.

## Key insight

**In a copied record, the clause that is a LOCATOR is the one that cannot be copied.** Shared
head/tail text buys greppability and is right for everything that states a fact about the
world. A phrase like "immediately above", "the preceding row", "see the sentence below" states
a fact about *this* cell's layout, so it is a different claim in every cell it lands in, and
appending in date order is exactly what makes it false. Ask of every pasted clause: *is this a
claim about the subject, or about where the reader is standing?*

## Related

- `2026-08-06-i-deleted-the-measurement-that-was-my-own-evidence.md` — a dated record is append-only
- `2026-07-21-i-marked-one-block-and-not-its-twin-in-the-file-whose-purpose-was-removing-that-defect.md` — sweep by claim, not by file

## Session Errors

1. **Better Stack `--since` rejected the `T…Z` ISO form.** `--since 2026-09-18T13:50:00Z`
   returned `Code: 53. DB::Exception: Cannot convert string '2026-09-18T13:50:00Z' to type
   DateTime64(6, 'UTC')` behind an opaque `curl: (22) … 400`. Recovery: the space-separated
   form (`--since "2026-09-18 13:50:00"`). **Prevention:** the script's usage block says
   `--since <Nh|Nm|ISO>`, which is true of only one ISO spelling — say which. Fixed in this
   PR.

2. **The plan's prescribed register-entry tail left odd bold parity.** `…merge-time state.]**`
   closes a bracket after the bold span, so each edited line gained an odd number of `**`
   and `markdownlint` MD037 fired on PRE-EXISTING bracket joins elsewhere in the line
   (`…]** **[…`), rejecting the commit. Recovery: the #7455 precedent shape
   `**The superseded sentence … state.**]`. **Prevention:** when appending to a line that
   already chains `**[…]**` brackets, count `**` before committing — an even count per line
   is the invariant, and an existing sibling entry is the shape to copy.

3. **A sweep anchor matched a sibling row.** `| **(c) Categories of personal data** |` is the
   lead of every processing activity's (c) row, not just PA-8's. The write was assertion-guarded
   so nothing landed. **Prevention:** key a row anchor on lead AND a row-unique substring, and
   assert exactly one hit.

4. **A review-fix anchor matched 6 occurrences, not 5.** `recorded immediately above is SPENT`
   also appears in the pre-existing 2026-08-13 (#7455) entry — the very entry whose shape this
   PR was copying. The `assert count == N` aborted before any write. **Prevention:** anchor on
   the full canonical head, not the fragment being changed; when a PR copies a precedent, the
   precedent is the likeliest false match for any sweep over the copy.

5. **The Phase 2 exit gate was REFUSED (`rc=4`).** A sibling full-gate run was in flight in
   `feat-8231-parallel-test-all-next`. Recovery: the documented substitute — suites derived
   from `git grep -l <changed-file-basename>` across `*.test.sh` / `*.test.ts`, all rc=0.
   One-off; the substitute path is already the prescribed behaviour.

6. **Forwarded from `session-state.md`** (planning subagent, pre-compaction): the plan
   initially reproduced `lint-infra-no-human-steps.py`'s own trigger tokens and failed that
   lint on itself; two AC greps used backslash-escaped backticks (a GNU-grep buffer anchor,
   not a literal); one deepen-agent claim ("the delivery field first shipped in #7274") was
   falsified by `git log -S` (#6290). All three were self-caught and fixed in-phase.
