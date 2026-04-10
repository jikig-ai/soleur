---
title: "fix: CPO domain leader operates on stale milestone data"
type: fix
date: 2026-04-10
deepened: 2026-04-10
---

# fix: CPO domain leader operates on stale milestone data

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 3 (Proposed Solution, Edge Cases, Context)
**Research sources:** 4 institutional learnings, constitution.md convention audit, cross-agent pattern analysis

### Key Improvements

1. Added `gh api --paginate` / `jq` sharp edge from constitution.md line 29 -- milestones query should drop `--paginate` (repos rarely exceed 30 milestones) to avoid the concatenated-array footgun in agent context
2. Incorporated pattern from `domain-leader-false-status-assertions-20260323` learning -- the CPO fix is the upstream complement to the existing per-issue `gh issue view` verification already present on all 8 domain leaders
3. Added edge case: the "Roadmap consistency check" bullet already says `gh api repos/{owner}/{repo}/milestones` but the instruction ordering makes it advisory; the fix must restructure the bullet, not just add a new one, to avoid duplication
4. Added note from `agent-prompt-sharp-edges-only` learning -- keep the CPO agent changes surgical (reorder + add conflict rule), do not add general API usage docs

## Overview

The CPO domain leader agent reads the roadmap.md "Current State" section to assess phase status, but this section is a frozen snapshot that becomes stale when milestones close. During brainstorm for #1871, the CPO asserted Phase 1 had 7 unfinished P1 items and 0 beta users when Phase 1 and Phase 2 were already closed. This is a recurrence of the stale-data pattern from `knowledge-base/project/learnings/2026-03-25-domain-assessments-contain-stale-codebase-claims.md`.

Three coordinated fixes: (1) make the CPO agent query the GitHub API first and trust it over the file, (2) add a workflow gate to AGENTS.md requiring roadmap.md Current State updates when milestones close, (3) update the stale Current State section to reflect reality now.

## Problem Statement

The CPO agent's "Roadmap consistency check" instruction (line 22 of `plugins/soleur/agents/product/cpo.md`) says to "cross-reference against GitHub milestones" but this is advisory -- the agent reads roadmap.md first, and the frozen Current State snapshot anchors its assessment before any API check runs. The existing learning (#1142) fixed the downstream (plan reviewers catch stale claims) but not the upstream (CPO reads stale data in the first place).

**Root causes:**

1. **Stale snapshot in roadmap.md**: The `## Current State (2026-04-03)` section is load-bearing (CPO reads it to determine phase status) but never updated when milestones close. Phase 1 and 2 have been closed for weeks but the section was only updated to reflect this on 2026-04-03. It still says "Phase 1.5 is open" in the CPO's context.
2. **Weak ordering in CPO agent**: The Assess phase reads roadmap.md first (file-based), then has an advisory instruction to cross-reference with GitHub milestones. The file context anchors the agent's understanding before the API check runs, so the API check is effectively a no-op.
3. **No enforcement on milestone closure**: AGENTS.md has a workflow gate for "moving issues between milestones" but NOT for closing milestones entirely. When a phase milestone is closed, nothing enforces updating roadmap.md Current State.

## Proposed Solution

### Part 1: CPO Agent Fix (`plugins/soleur/agents/product/cpo.md`)

Restructure the Assess phase to query the API FIRST:

1. **Restructure the existing "Roadmap consistency check" bullet** (line 22) into two parts: (a) an API-first query at the TOP of the Assess section, and (b) a reconciliation step later. Do NOT add a new bullet that duplicates the existing one -- the existing bullet already mentions `gh api repos/{owner}/{repo}/milestones` but is positioned too late and is advisory rather than authoritative.
2. **Drop `--paginate`** from the milestones query. Repos rarely exceed 30 milestones (GitHub's default page size). Using `--paginate` introduces the concatenated-array footgun documented in constitution.md line 29 (`[...][...]` breaks shell variable assignment). The agent runs this in a Bash tool call, not a pipeline -- simpler is safer.
3. **Add conflict resolution rule**: "If the API result conflicts with the roadmap.md Current State section, trust the API -- the file may be stale. Flag the staleness as an inconsistency finding in the assessment output."
4. **Keep changes surgical** per the `agent-prompt-sharp-edges-only` learning -- add only the ordering constraint and conflict resolution rule. Do not add API usage documentation or general best practices.

**File to edit:** `plugins/soleur/agents/product/cpo.md` (lines 16-24, Assess section)

**Current Assess section structure (simplified):**

```markdown
### 1. Assess
- Check business-validation.md
- Check brand-guide.md
- Check GitHub issue state (if referenced)
- Cross-reference brand vs validation
- Check spec files
- Roadmap consistency check (advisory cross-reference)  ← line 22, runs LAST
- Determine maturity stage
- Report structured table
```

**Proposed Assess section structure:**

```markdown
### 1. Assess
- **Milestone status (authoritative):** Query gh api milestones (open + closed) FIRST
- Check business-validation.md
- Check brand-guide.md
- Check GitHub issue state (if referenced)
- Cross-reference brand vs validation
- Check spec files
- **Roadmap reconciliation:** (replaces old "Roadmap consistency check")
  Read roadmap.md, compare against API results. Trust API when they conflict,
  flag staleness as finding.
- Determine maturity stage
- Report structured table (include milestone data from API, not from file)
```

**Implementation note:** The existing "Roadmap consistency check" bullet (line 22) is being SPLIT and MOVED, not just supplemented. Remove the old bullet entirely and replace with the two new bullets in their respective positions. This avoids having two bullets that both mention `gh api milestones` with conflicting authority levels.

### Part 2: AGENTS.md Workflow Gate

Add a new bullet to `## Workflow Gates` in `AGENTS.md`:

```markdown
- When closing a phase milestone (`gh api -X PATCH milestones/<N> -f state=closed`), update the `## Current State` section of `knowledge-base/product/roadmap.md` in the same commit. The Current State section is load-bearing -- domain leader agents (particularly CPO) read it to assess phase status. A closed milestone with an outdated Current State produces stale assessments. **Why:** In #1878, the CPO assessed Phase 1 as having 7 unfinished P1 items because the Current State section had not been updated after Phase 1 and Phase 2 were closed.
```

**Placement:** After the existing "When moving GitHub issues between milestones" gate (line 29 of AGENTS.md) -- they are logically related.

### Part 3: Update roadmap.md Current State

Update the `## Current State (2026-04-03)` section to reflect current reality based on the GitHub API:

**Current (stale):**

```markdown
## Current State (2026-04-03)

| Dimension | Status |
|-----------|--------|
| Phase 1 (Close the Loop) | Complete. Milestone closed. All 15 issues closed. |
| Phase 2 (Secure for Beta) | Complete. Milestone closed. All 20 issues closed (including #1375). |
| Phase 3 (Make it Sticky) | In progress. 11 open, 2 closed. |
| Phase 4 (Validate + Scale) | Not started. 18 open, 9 closed. |
| Phase 5 (Desktop Native App) | Defined. 5 issues created (#1423-#1429). Trigger-gated on user demand. |
| Post-MVP / Later | 56 open, 75 closed. |
| Beta users | 0 |
| Pricing gates passed | 0 of 5 |
```

**Updated (from API as of 2026-04-10):**

```markdown
## Current State (2026-04-10)

| Dimension | Status |
|-----------|--------|
| Phase 1 (Close the Loop) | Complete. Milestone closed. 0 open, 15 closed. |
| Phase 2 (Secure for Beta) | Complete. Milestone closed. 0 open, 20 closed. |
| Phase 3 (Make it Sticky) | In progress. 12 open, 27 closed. |
| Phase 4 (Validate + Scale) | Not started. 16 open, 11 closed. |
| Phase 5 (Desktop Native App) | Defined. 5 open, 0 closed. Trigger-gated on user demand. |
| Post-MVP / Later | 73 open, 265 closed. |
| Beta users | 0 |
| Pricing gates passed | 0 of 5 |
```

Also update the `last_updated` frontmatter field to `2026-04-10`.

## Acceptance Criteria

- [ ] CPO agent runs `gh api milestones` (both open and closed states) BEFORE any roadmap.md reads or phase status assertions
- [ ] CPO agent instruction explicitly states: trust API over file when they conflict, flag staleness
- [ ] CPO agent does NOT use `--paginate` on milestones query (avoids concatenated-array footgun per constitution.md line 29)
- [ ] The old "Roadmap consistency check" bullet is REPLACED (not duplicated) -- only one instruction references `gh api milestones`
- [ ] AGENTS.md has a workflow gate requiring roadmap.md Current State update when closing milestones
- [ ] roadmap.md Current State section date updated to 2026-04-10
- [ ] roadmap.md Current State numbers match current GitHub API output (re-queried at implementation time, not copied from plan)
- [ ] roadmap.md `last_updated` frontmatter updated to 2026-04-10

## Test Scenarios

- Given the CPO agent Assess section, when reading the instructions, then the milestone API query appears BEFORE any roadmap.md file reads
- Given a stale roadmap.md Current State section that says Phase 1 is in progress, when the API returns Phase 1 as closed, then the CPO flags the inconsistency and reports Phase 1 as closed
- Given AGENTS.md, when searching for "closing a phase milestone", then a workflow gate bullet is found requiring Current State update
- Given roadmap.md, when reading the Current State section, then the date is 2026-04-10 and Phase 3 shows 12 open, 27 closed (matching API)

## Edge Cases

1. **Duplicate milestone API instructions:** The existing "Roadmap consistency check" bullet (line 22) already contains `gh api repos/{owner}/{repo}/milestones`. If the implementer adds a NEW bullet at the top of Assess without removing the old one, the agent will have two instructions to query milestones -- one authoritative (top) and one advisory (old position). The old bullet MUST be removed and replaced, not supplemented.

2. **`--paginate` footgun for agent context:** Constitution.md line 29 requires `jq -s 'add // []'` when using `--paginate` with array endpoints. Since agents run `gh api` in Bash tool calls (not piped through jq), using `--paginate` would produce broken JSON if multiple pages exist. Drop `--paginate` entirely -- milestones endpoints are bounded by the number of phases (currently 6), well under the 30-per-page default.

3. **Stale numbers in the Current State update:** The milestone counts (12 open/27 closed for Phase 3, etc.) were captured from the API at plan creation time (2026-04-10). By the time implementation runs, these numbers may have changed. The implementer should re-query the API during implementation and use the live numbers, not the plan's snapshot.

4. **Other domain leaders reading roadmap.md:** Only the CPO has the "Roadmap consistency check" instruction. Other domain leaders (CTO, CMO, CLO, etc.) do not read roadmap.md for phase status -- they only verify individual issue state via `gh issue view`. This fix is correctly scoped to CPO only. If other leaders start reading roadmap.md in the future, the same API-first pattern should be applied.

5. **Workflow gate scope:** The new AGENTS.md gate covers "closing a phase milestone" but milestones can also become stale when issues are moved between milestones (already covered by existing gate) or when issue counts change significantly. The Current State section should ideally be updated on any milestone state change, but the gate intentionally targets the highest-impact event (closure) to avoid over-engineering. The weekly CPO review cadence (roadmap.md line 366) provides a backstop for incremental drift.

## Context

### Related Learnings

1. `knowledge-base/project/learnings/2026-03-25-domain-assessments-contain-stale-codebase-claims.md` -- Previous fix was downstream (plan reviewers catch stale claims). This fix is upstream (prevent stale data from reaching the CPO in the first place).

2. `knowledge-base/project/learnings/workflow-issues/domain-leader-false-status-assertions-20260323.md` -- All 8 domain leaders were updated with `gh issue view` verification for individual issues. This fix extends the same API-first pattern to milestone-level status for the CPO specifically.

3. `knowledge-base/project/learnings/2026-04-03-milestone-roadmap-integrity-audit.md` -- Established the bidirectional enforcement principle (issues->milestones AND milestones->issues). This fix adds a third direction: milestones->roadmap Current State.

4. `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` -- Agent prompts should contain only what the model would get wrong without them. The CPO agent changes should be minimal: reorder, add conflict rule, remove duplication. Do not add API documentation.

### Files to Modify

1. `plugins/soleur/agents/product/cpo.md` -- Restructure Assess section
2. `AGENTS.md` -- Add workflow gate for milestone closure
3. `knowledge-base/product/roadmap.md` -- Update Current State section

### Existing Safeguards (preserved)

- AGENTS.md already has "When moving GitHub issues between milestones, update roadmap.md" gate (line 29) -- this fix adds the complementary "when closing milestones" gate
- CPO already has "Roadmap consistency check" instruction (line 22) -- this fix reorders it and makes the API authoritative

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting agent prompts and documentation only.

## References

- Issue: [#1878](https://github.com/jikig-ai/soleur/issues/1878)
- Related brainstorm trigger: [#1871](https://github.com/jikig-ai/soleur/issues/1871)
- Learning: `knowledge-base/project/learnings/2026-03-25-domain-assessments-contain-stale-codebase-claims.md`
