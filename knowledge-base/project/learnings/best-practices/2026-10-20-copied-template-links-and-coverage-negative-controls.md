---
module: plugins/soleur/skills/plan
date: 2026-10-20
problem_type: best_practice
component: development_workflow
symptoms:
  - "a docs-only feature needed a ruling on where new prescriptive content lives (reference doc vs slim skill vs capped SKILL.md)"
  - "a markdown link inside a fenced template block is copied verbatim into generated plans, where a './' relative link resolves nowhere"
  - "the claim 'existing census covers the new reference file' was only evidence after a negative control made the census go red"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: low
tags: [plugin-root, template-links, reference-doc, negative-control, coverage-claim, cto-ruling]
synced_to: [plan]
---

# Learning: links in template-copied text use `${CLAUDE_PLUGIN_ROOT}`-form, and a coverage claim needs a negative control

## Problem

Issue #10401 asked to ship the differential-migration-testing technique to
plugin users. The diff was docs-only — one new reference doc plus three
identical pointer sentences — but it carried three design rulings that will
recur for any future "teach the plugin a technique" feature: where the content
lives, what link form a pointer inside copied template text must use, and how
to prove an existing guard already covers a new artifact.

## Solution

All three were settled by CTO ruling during `soleur:deepen-plan`
(`decision-challenges.md`, 2026-10-20):

1. **Reference doc, not a slim skill.** The content landed at
   `plugins/soleur/skills/plan/references/differential-migration-testing.md`
   (~200 lines) with the sole pointer being one identical conditional sentence
   inside each of the three `## Test Scenarios` blocks of
   `plan-issue-templates.md`. A new skill costs registration plus description
   budget for zero added property; a reference doc is the first
   minimalism-ladder rung that holds. A secondary constraint made the choice
   forced rather than merely preferred: every capped SKILL.md lacked headroom
   (`work` 118 B already ~claimed by in-flight #10400, `plan` 34 B,
   `review` 0 B), while `plan-issue-templates.md` is read unconditionally at
   plan Step 4 and satisfies the `components.test.ts` reachability census at
   zero capped bytes.
2. **`${CLAUDE_PLUGIN_ROOT}`-form links inside fenced template blocks.** The
   pointer sentence links as
   `[differential-migration-testing.md](${CLAUDE_PLUGIN_ROOT}/skills/plan/references/differential-migration-testing.md)`
   because the template text is copied verbatim into generated plans — a `./`
   or repo-relative link resolves nowhere in the generated artifact, while the
   root-prefixed path resolves to the user's plugin install. These were the
   first markdown links in `plan-issue-templates.md`; the convention is
   established in prose surfaces (`commands/go.md`, `drain-prs`,
   `merge-pr`, `one-shot` SKILL.mds) but this was the first application to
   copy-through template text.
3. **"No new drift pin" is a coverage claim — prove it with a negative
   control.** Rather than adding a fresh pin for the new file, the plan
   asserted the existing harness-parity census plus template-pin suites cover
   reachability. Task 3.4 verified the claim: on a scratch copy, remove the
   three pointer lines and confirm the census goes red naming
   `plan/references/differential-migration-testing.md`. A suite asserted to
   cover an artifact is evidence only after removing the artifact makes it
   fail.

## Session Errors

**Gap-grep omission of `reproduce-bug/SKILL.md:90` (plan phase, forwarded via session-state.md)**

- **Recovery:** `soleur:deepen-plan` enumerated all four `differential` grep
  hits repo-wide (`parse-form-a.awk`, `reproduce-bug/SKILL.md`,
  `review/SKILL.md`, `plan-sharp-edges.md`), recorded why none teach the
  migration apparatus, and the new doc now names `reproduce-bug`'s
  differential loop as the shipped sibling for the single-version bug case.
- **Prevention:** A gap-analysis grep must enumerate every hit and decide each
  in the plan's own prose — a claim of the form "no shipped artifact teaches
  X" is itself a sweep over the whole corpus, so list the hits and the
  adjacent-but-different sense each carries (the same enumerate-and-decide
  discipline the sweep-corpus rules codify).

**5 MD038 markdownlint errors (plan phase, forwarded via session-state.md)**

- **Recovery:** Fixed inline (spaces inside code-span markers) before commit.
- **Prevention:** None needed — the linter caught them; run
  `npx markdownlint-cli2 <file>` on any authored or edited markdown before
  committing, as tasks 1.2/2.2 already prescribed.

## Key Insight

Two conventions generalize past this PR:

- **Placement follows the budget, not just the topic.** When choosing a home
  for new prescriptive content, check the capped-byte headroom of every
  candidate pointer surface first — an uncapped `references/` file read
  unconditionally by its parent skill can be the only surface that satisfies
  the reachability census at zero capped cost, which collapses "reference doc
  vs slim skill vs SKILL.md edit" into a forced answer.
- **Copied text and coverage claims share one shape: the artifact lands
  somewhere the author never opens.** A link inside template text must be
  written for the *destination* context (the generated plan on a user machine,
  hence `${CLAUDE_PLUGIN_ROOT}`-form), and a claim that "existing suite X
  covers artifact Y" must be tested at the *detector* (delete Y on a scratch
  copy, confirm X reds naming it) — not asserted from the suite's presence.

## Tags

category: best_practice
module: plugins/soleur/skills/plan

## Related Issues

- Issue #10401 / PR #10727 (this branch); epic #10397.
- See also: `knowledge-base/project/learnings/test-failures/2026-10-04-a-forced-test-condition-needs-a-negative-control-and-proc-status-is-read-once.md` — same detector-side principle for forced test conditions.
- See also: `knowledge-base/project/learnings/best-practices/2026-07-08-plugin-root-migration-ac-grep-scope-and-anchor-preservation.md` (superseded banner → ADR-179) — the canonical `${CLAUDE_PLUGIN_ROOT}` form for *shell anchors*; this learning extends the same root-prefixed form to markdown links inside copy-through template text.
