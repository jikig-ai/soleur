---
title: Plan skill must reconcile spec claims against codebase reality before phasing
date: 2026-04-15
category: best-practices
module: plan-skill
tags: [planning, spec-quality, workflow]
source_session: plan for #2345 KB chat sidebar
---

# Plan skill must reconcile spec claims against codebase reality

## Problem

A spec written during brainstorm can make infrastructure claims that don't match the codebase. In the #2345 KB chat sidebar session, the spec claimed three pieces of infrastructure existed that did not:

- **TR8 Analytics**: "emit via the existing analytics layer" — no frontend analytics abstraction existed; Plausible was server-side-only.
- **TR10 Feature flags**: "gate behind feature flag `kb_chat_sidebar`" — no FF system at all.
- **FR2 Conversation lookup**: "resolves or creates a conversation keyed by `context.path`" — no lookup API and no `context_path` column on `conversations`.

Without reconciliation, the plan inherits the spec's incorrect assumptions. Phase estimates are wrong, scope expands during implementation, and reviewers catch the divergence late.

## Solution

**Every plan produced by the `/soleur:plan` skill must include a "Research Reconciliation" section that lists each spec claim alongside the codebase reality and the plan's response.** Format as a 3-column table (spec claim / reality / plan response). Write it between "Overview" and "Implementation Phases."

The reconciliation reads from the existing Phase 1 `repo-research-analyst` output — the analyst already surfaces "gap callouts" (see its inventory output for #2345). The plan just needs to translate those callouts into explicit reconciliation rows so they cannot be ignored by later phases or reviewers.

Concretely, the plan skill's Phase 1.7 ("Consolidate Research") should require an explicit pass where each TR/FR claim in the spec is matched against the research findings and either (a) confirmed in-sync, or (b) listed in Research Reconciliation.

## Key Insight

**Specs capture desired outcomes, not current state.** The plan is the first artifact that must ground those outcomes in the actual codebase. Skipping this step silently promotes spec fiction into implementation reality — by the time the implementer discovers the gap, the plan's phase structure is already wrong.

The `repo-research-analyst` agent has been producing "gap callouts" for months; the gap is not the research, it is the **consolidation step** that turns research into a named section the plan author and reviewers must engage with.

## Prevention

1. Update the `/soleur:plan` skill Phase 1.7 to require a Research Reconciliation section whenever `repo-research-analyst` returns any "Gap callouts" or equivalent mismatches.
2. The reconciliation section must be formatted as a table so reviewers can spot-check each claim.
3. Make the section a plan-review checkpoint — code-simplicity and architecture reviewers should scan for unreconciled TR/FR claims.

## Session Errors

1. **Markdownlint MD046 fenced-vs-indented error** on first commit of the
   plan. Ordered-list items used `1.1`, `2.3` style numbering with 4-space
   indented continuation lines; markdownlint treated the continuations
   as implicit indented code blocks. The final resume-prompt fenced
   block then violated MD046's consistency rule. **Recovery:** converted
   the resume-prompt fence to indented style (4-space prefix). **Prevention:**
   when a plan uses `N.M` pseudo-numbered headings with 4-space continuation,
   favor indented code blocks throughout (or use real Markdown lists with
   2-space continuation). Add a note to the plan skill's output formatting
   guide.
2. **`git add <spec-dir>/` missed `wireframes/` subdirectory on first try.**
   The spec directory existed with only `spec.md` and `wireframes.pen`
   tracked; the `wireframes/` PNG subdirectory was created by `ux-design-lead`
   and didn't auto-stage. **Recovery:** re-ran with `git add -f knowledge-base/project/specs/feat-kb-chat-sidebar/wireframes/`.
   **Prevention:** after any agent that writes to the filesystem (Pencil
   exports, image generators), run `git status -uall <dir>` before the
   first `git add` to surface untracked files the parent-directory add
   would otherwise miss due to `.gitignore` patterns or path quirks.

## Related

- Plan: `knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md` (see "Research Reconciliation — Spec vs. Codebase" table).
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-15-kb-chat-sidebar-brainstorm.md`.
- Spec: `knowledge-base/project/specs/feat-kb-chat-sidebar/spec.md`.
