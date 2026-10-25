---
title: Counsel review — pattern layer legal text (PR #10970, Ref #8293)
status: CLO-agent-ruled; amendments applied; no re-review (Soleur-as-tenant-zero v1)
date: 2026-10-25
reviewer: soleur:legal:clo (agent), after soleur:legal:legal-compliance-auditor seats in two review rounds
brand_survival_threshold: single-user incident
---

# Counsel review: pattern layer legal text

*Draft material for internal attestation. It is not legal advice and does not replace counsel review of the DPIA memo's own re-evaluation triggers.*

## Scope

Records the binding `soleur:legal:clo` ruling on the legal and data-protection text changed by PR #10970:

- `knowledge-base/legal/article-30-register.md` (PA-31 (c) correction, PA-31 (f) retention marker)
- `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md` (2026-10-24 addendum and 2026-10-25 correction)
- `knowledge-base/legal/compliance-posture.md` (pointer comment)
- ADR-299, `compound-promote-runbook.md`, `betterstack-log-query.md` and the pattern-page template (data-protection sentences only)

Every implementation claim was cross-checked by the auditor seats against `compound-promote-patterns.ts`, `compound-promote-ledger.ts` and `cron-compound-promote.ts`; their drift tables are in the PR's review record.

## Ruling (HEAD 3d8306a91e)

| Question | Ruling |
|---|---|
| Ledger bound: DPIA "author qualifier, not expected" vs Art. 30 "bounded to the App's own PRs" | UPHOLD: consistent and sufficient |
| Names and un-`@`-prefixed handles are not machine-screened | UPHOLD: no stronger authoring rule is required; revisit at the first name or handle observed |
| "Runtime screen" bullet supersedes the "same prefilter" sentence | UPHOLD |
| "The raw value is not logged" | AMEND: handler sinks only; the trigger event persists in the Inngest event store |
| Test pinning the "names are not screened" negative | DEFER: a test that pins a gap fails the day the screen improves |
| In-place rewrite of a never-merged dated record | UPHOLD, conditioned on the merge wording below |
| "drops the item" for an aliased directory | AMEND: an aliased patterns directory empties the arm; an aliased learnings root drops every evidence file |
| `compliance-posture.md` pointer | AMEND: new dated comment, `last_updated` bumped |
| Merge condition on the corrections | AMEND: both corrections are conditioned on the merge of the pattern-layer PR |
| PA-31 (f) retention marker | Complete and correct |

Verdict as returned: `CLO: AMEND-REQUIRED`.

## Amendments applied

All four amendments were applied verbatim in `099293dbf6` (the ruling's pasted sentences). No further CLO pass was run on the amended text; the auditor seats' second-round findings were all closed before the ruling.

## Residuals

- Names and bare handles remain a curation control only (stated in Art. 30 (c), the DPIA correction, ADR-299 and the template).
- Pattern pages are a permanent surface in a public repository and its forks; no erasure routine is implementable (PA-32 (f)).
- PA-32 (f) states "2 forks"; a live read shows 5. That text predates this PR and is outside its diff.
