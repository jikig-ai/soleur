# Learning: a count and a ruling copied from the brief contradicted the paragraph they sat in

## Problem

PR #11434 appended one 55-line docs-only addendum to ADR-282 (Hetzner sources read, CTO and CLO rulings, owner-side asks). Every number in it was re-measured and every quote re-fetched, and it still went to the review panel with one P1 and eight P2 findings. All of them sat in sentences the author carried over from the invoking brief or from a ruling, not in the measured table:

- "The five sources the 2026-10-23 addendum lists as unread". That addendum lists four; the table has five rows because the provider documentation was read as two artifacts. The Result paragraph repeated "five sources". Three seats found it.
- "A header-only copy stays permitted on the 2026-10-15 conditions", copied from the CLO ruling into a paragraph that, two sentences earlier, said R2 is not an EU provider. Those conditions require a separate EU bucket, so the paragraph contradicted itself. The history seat rated it P1.
- A plan premise row said section 6.4 of the data-protection disclosure "does not name R2". It has a dedicated R2 bullet; only the generic CDN bullet omits it. The ADR text avoided the claim, the committed plan stated it as a verified premise.
- "no entry names Volumes" in a changelog row (the changelog names Volumes about 14 times; only the project-deletion entries do not), "ends 'Last updated 27 October 2021'" (the date ends the general terms, a US-only special-terms block follows), "the only closure text found" (the same row quotes two more clauses). Each was a summary sentence stronger than the row it summarised.

## Solution

Fixed inline in two commits (`b6a06c2d94`, `39eda56311`). The header-only sentence was restored as the CLO gave it, with the R2 consequence added as a labelled drafter's reading rather than a CLO sentence. The count became "four sources, five rows", the Result paragraph said "rows", and the plan row was corrected from the file.

## Key Insight

The measured part of a docs addendum gets checked because it is a table of figures. The connective sentences (an intro count, a Result paragraph, a carried-over ruling) read as bookkeeping and are written from the brief. When a ruling is copied into a paragraph, read it against the facts stated beside it in the same paragraph. When a summary sentence quantifies ("none of the five", "the only", "no entry"), count its operand from the artifact it summarises. A consequence you derive from two ruled facts is a third claim: label it as yours.

## Session Errors

1. **Plan-write hook denied a draft that quoted a Doppler command line from `flag_set`** (forwarded from the planning phase). Recovery: cite the function by name and effect. Prevention: already enforced by the hook; the plan recorded the rule for the work phase.
2. **"Five sources" carried from the brief, not counted from the 2026-10-23 addendum.** Recovery: reworded to four sources, five rows. Prevention: count any operand a summary sentence quantifies from the artifact it names before writing it.
3. **CLO sentence copied beside a premise it contradicts.** Recovery: restored the ruling, labelled the consequence. Prevention: read a copied ruling against the facts in the same paragraph.
4. **Plan premise stated a legal-disclosure fact (6.4 "does not name R2") without reading the section.** Recovery: corrected from the file at review. Prevention: grep the section before writing a "does not name X" premise.
5. **Summary sentences stronger than their table rows** (changelog "no entry", T&C date, "only closure text"). Recovery: scoped each to what the row shows. Prevention: for each universal or exclusive word in a summary, name the grep that would falsify it.
6. **Owner-side follow-ups classified owner-side with no browser attempt.** The Playwright servers failed to connect this session. Recovery: the addendum says "no browser attempt was made" and bases the classification on the console having no members API and the support question being sent from the account. Prevention: record tool-instability evidence at classification time (`hr-never-label-any-step-as-manual-without`).
7. **A 120 s foreground limit moved the local check batch to the background.** Recovery: waited on the batch's own end marker. Prevention: run the import-rehearsal suite in the background from the start.

Tags: category: workflow-issues, module: adr-282, docs-addendum, claim-verification
