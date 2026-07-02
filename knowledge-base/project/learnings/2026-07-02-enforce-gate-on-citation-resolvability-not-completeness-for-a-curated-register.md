---
date: 2026-07-02
category: workflow-patterns
tags: [ci-gate, enforcement, curated-register, drift-analyzer, signal-choice, plan-review, domain-model]
issue: 5871
---

# For a curated register, gate on citation-*resolvability*, not documentation *completeness*

## Context

Planning #5871 (enforcement gates for the domain-model register). The #5754 analyzer's `drift` mode
exits 1 on `stale_n>0 OR undoc_n>0` and reports two counts: **stale register citations** (the register
cites a file/symbol that no longer resolves) and **undocumented source facts** (a table with
RLS/constraints not named in the register). The obvious design — "block when `drift` exits 1" — is wrong.

## What plan-time verification revealed

The register is a **curated subset** (~6 entities + ~11 business rules), NOT a complete table catalogue.
So the "undocumented source facts" scan flags **~50+ real tables the register omits by design**. A
blocking gate keyed on that count (or the raw exit code) would red-wall *every* migration PR and demand
documenting every table — contradicting the register's curation intent (ADR-076 item 5).

Worse, a pre-existing analyzer bug (a `public.` schema-qualifier mis-capture) had **collapsed all public
tables into one `public` token**, masking the scale. Running the analyzer and correcting the capture
during planning un-masked the ~50 — which is what exposed that "undocumented facts" is the wrong signal.

## Takeaway

When enforcing a **curated** register/catalogue/allowlist, split the analyzer's signals by *type*, not by
exit code:

- **Citation-resolvability** ("what the register cites must still exist") is **high-signal and
  ratchet-safe** — it's 0 on a healthy register and only a genuine break makes it non-zero. Gate on this.
- **Completeness** ("everything in the source should be in the register") is **inherently noisy** for a
  curated subset — it flags ~every un-curated item. Keep it **advisory** (a "consider documenting via the
  human-in-loop tool" pointer), never a blocker.

Parse the specific sub-count from the report (line-anchored: `^## Stale register citations \(N\)`), do not
gate on the aggregate exit code. This also means the blocking gate is clean on `main` today, so it can
ship blocking directly with no advisory-first soak apparatus (which two plan-review reviewers correctly
flagged as ceremony once the signal was 0).

## Corollary

The 5-agent plan-review panel (DHH + Kieran + code-simplicity + spec-flow) earned its keep here: spec-flow
caught the exit-1-ambiguity and the empty-diff-cache fail-open; Kieran caught the unanchored stale-count
grep (multiline-capture bug); DHH + code-simplicity independently cut a theatre gate (plan-time flag) and
the advisory-first apparatus. See plan
`knowledge-base/project/plans/2026-07-02-feat-domain-model-register-gates-plan.md`; pairs with the
brainstorm-phase learning `2026-07-02-run-the-analyzer-during-brainstorm-before-designing-a-blocking-gate.md`.
