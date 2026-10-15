# Learning: a sampled list was restated as a universal claim in the audit's own summary

## Problem

The GitHub Code Quality baseline (`knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`) states in "Method and limits" that its file lists are first-page samples classified by path and not reviewed. Two lines further down, "Reading" said `py/file-not-closed` was "all outside product code" and that the findings "are lint-class". Both are claims about the full 36 and 169 findings, but only 12 files of the first were seen and the incompatible-type comparisons were never triaged. Three of four review seats flagged it independently. The class key also contradicted two rows (a hook under S, `apps/web-platform/infra` files under R although the key defined P as `apps/web-platform`).

## Solution

Scope each claim to what was observed ("every sampled location"), mark untriaged findings as untriaged, make the class key say where its boundaries sit, and state that only per-rule totals are complete. Cite ADR-276 Decision 6 for scope and the S5 row for cost; note that the raw census output was not saved.

## Key Insight

When a document opens with a limits section, every later summary sentence has to be written inside those limits. The limit is read once, and the summary is what people quote. Before committing an audit, list its summary claims and check each against the sample it rests on.

## Session Errors

- **Universal claims drawn from a first-page sample** — Recovery: scoped to "sampled" in review round 1 — Prevention: when drafting "Reading" or "Summary" sections from a partial export, restate the scope in the same sentence (the review seats caught it; no hook can).
- **Class key and row placement disagreed (hook as S, infra scripts as R under a P key)** — Recovery: key rewritten, rows moved, counts re-summed to 9 files for `py/empty-except` — Prevention: after defining a classification key, grep every row against its path prefix once.

## Tags
category: workflow-issues
module: knowledge-base/audits
