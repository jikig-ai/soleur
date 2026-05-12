# Learning: public legal-doc Last-Updated annotations must avoid PR/issue numbers

## Problem

The Eleventy-mirror `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` historically used Last-Updated body annotations that embedded GitHub workflow tokens (e.g., `forward-port per #3666`, `cleanup per #3671 of forward-port #3666`). The canonical sibling at `docs/legal/data-protection-disclosure.md` consistently used plain-English annotations referencing section numbers (e.g., `added per-message usage jsonb to Section 2.3(i)`).

External readers of the public mirror (DPOs, regulators, careful users) cannot resolve `#3666`/`#3671` outside the GitHub repo. The asymmetry was caught at multi-agent review time on PR closing #3671 (code-quality-analyst F1: "Last-Updated annotation leaks PR/issue jargon").

## Solution

For Last-Updated body annotations on any public-facing legal doc OR its Eleventy mirror:

- Describe **what** changed (the section + content) and **where the property still lives** (cross-reference by `§N.M`).
- Do NOT embed PR numbers, issue numbers, or commit SHAs in body text. Workflow provenance belongs in `git log`, not the rendered doc.
- When a mirror's prior annotation precedent included PR numbers (as #3669 did with `#3666`), reset to the canonical style — do not perpetuate.

Canonical-style example (PR #3671):

> May 12, 2026 (trimmed Section 4.2 Resend row Legal Basis column to remove misplaced push-subscription consent clause; push-subscription consent basis remains correctly disclosed in §2.3(j))

## Key Insight

Workflow-management metadata (PR/issue numbers) leaks into public surfaces when authors copy the prior annotation's *style* rather than its *constraint*. Style copying chains drift forward; the predecessor PR #3669's `forward-ported per #3666` annotation was internally fine because the reader was an engineer reviewing the forward-port, but it set the wrong precedent for the next PR (#3671), which inherited the `#NNNN` shape into a now-public mirror. Asymmetry between canonical and mirror is itself a review signal: the two sibling files should produce visually-identical body annotations modulo Eleventy frontmatter.

## Session Errors

- **PR-vs-issue routing in /soleur:go**: `gh pr view 3671` failed because #3671 is an issue, not a PR. Recovery: pivoted to `gh issue view` and prompted the user with a route choice. Prevention: `/soleur:go`'s bare-number classifier could fall back to `gh issue view` when `gh pr view` fails before raising — surfaced as a minor workflow polish opportunity, not a hard rule.

## Tags

category: documentation-quality
module: legal-docs
related: [knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md, knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md]
