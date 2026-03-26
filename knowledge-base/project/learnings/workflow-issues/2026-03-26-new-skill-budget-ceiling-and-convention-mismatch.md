---
module: plugins/soleur
date: 2026-03-26
problem_type: workflow_issue
component: tooling
symptoms:
  - "Pre-commit hook fails with Budget exceeded 1838/1800 words when adding new skill"
  - "SKILL.md built with XML structure per reference doc but all sibling skills use markdown headings"
  - "Background domain leader agents output files not found at expected paths during brainstorm"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [skill-budget, convention-mismatch, new-skill-workflow]
---

# Learning: Adding a new skill at the description word budget ceiling

## Problem

When adding the `/soleur:qa` skill (#1146), three workflow issues arose:

1. **Budget ceiling:** The cumulative skill description word count was already at ~1800/1800. Even a minimal 11-word description for the new skill pushed it over. The pre-commit hook (`plugin-component-test`) rejected every commit attempt. Required trimming the `triage` skill description (48 words -> 27 words) to make room.

2. **Convention mismatch:** The `skill-structure.md` reference doc (from skill-creator) prescribes pure XML structure for SKILL.md bodies (`<objective>`, `<quick_start>`, `<success_criteria>`). But examining actual skills in the codebase (`compound`, `deploy`, `ship`, `test-browser`, `reproduce-bug`), all use markdown headings. The SpecFlow analysis recommended XML, and the plan was written assuming XML. The correct convention was determined by reading existing code, not reference docs.

3. **Background agent output timing:** CTO, CPO, and CMO assessments were spawned as background agents during brainstorm Phase 0.5. Their output wasn't accessible when needed (file paths didn't match expected locations). Brainstorm document was written with "Pending assessment" placeholders and updated later when agents completed.

## Solution

1. **Budget:** Before adding a new skill, run `bun test plugins/soleur/test/components.test.ts` to check remaining headroom. If at ceiling, identify the top word-count offenders and trim one before adding the new skill. The `triage` description was verbose (48 words with redundant detail) and could be trimmed to 27 words without losing routing quality.

2. **Convention:** Always check 3-4 sibling skill SKILL.md files for actual structure conventions before implementing. Reference docs may prescribe aspirational conventions that haven't been adopted yet. The codebase is the source of truth for conventions, not reference documentation.

3. **Background agents:** When spawning domain leader assessments as background agents, write the brainstorm document with explicit "Pending" markers and update after agents complete. Don't block the brainstorm workflow waiting for assessments.

## Key Insight

When a codebase has both reference documentation and actual code, the actual code wins for convention decisions. Reference docs describe the ideal; the codebase reflects what's actually enforced. A new skill that follows the reference doc but not the codebase convention will look inconsistent with every peer.

For the budget: the 1,800-word ceiling means every new skill must "earn" its description words by being concise or by trimming an existing verbose description. This is a healthy constraint — it forces routing-focused descriptions rather than feature lists.

## Session Errors

1. **Skill description budget exceeded on first 3 commit attempts** — Recovery: Trimmed QA description from 38 words to 11 words, then trimmed triage description from 48 to 27 words to create headroom. **Prevention:** Run `bun test plugins/soleur/test/components.test.ts` before first commit to detect budget pressure early.

2. **Markdown lint failures (MD032) on plan file** — Recovery: Added blank lines before lists in 7 locations. **Prevention:** Run `markdownlint` on plan files before committing, or use the Edit tool to ensure blank lines before all list starts.

3. **Background domain leader agent outputs inaccessible during brainstorm** — Recovery: Wrote brainstorm with "Pending" placeholders, updated later. **Prevention:** For time-sensitive brainstorm documents, either wait for background agents or design the document to be updated incrementally.

4. **XML vs markdown convention mismatch** — Recovery: Checked actual sibling skills and used markdown headings. **Prevention:** Always read 2-3 sibling implementations before following reference documentation conventions.

## Tags

category: workflow-issues
module: plugins/soleur
