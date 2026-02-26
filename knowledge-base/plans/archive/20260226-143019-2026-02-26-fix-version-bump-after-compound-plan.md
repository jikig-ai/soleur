---
title: "fix: Move version bump after compound in ship and merge-pr skills"
type: fix
date: 2026-02-26
version_bump: PATCH
---

# fix: Move version bump after compound in ship and merge-pr skills

## Enhancement Summary

**Deepened on:** 2026-02-26
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Acceptance Criteria, Test Scenarios)
**Research sources:** compound-capture Step 8 (route-to-definition), compound SKILL.md, merge-pr-skill-design-lessons learning, ship/one-shot/work skill analysis

### Key Improvements
1. Identified the exact mechanism: compound-capture Step 8 (route-to-definition) stages plugin file edits without committing them
2. Simplified the solution to moving only version bump within ship skill -- no one-shot restructuring needed
3. Discovered that compound-capture explicitly says "Do NOT commit or version-bump" for route-to-definition edits, meaning they rely on a subsequent version bump step to pick them up

### New Considerations Discovered
- The compound-capture skill's auto-consolidation (Step F) commits `knowledge-base/` changes, NOT plugin file changes
- Route-to-definition edits are staged but uncommitted -- they wait for the normal workflow completion protocol
- The one-shot double-compound is intentional but its second run's route-to-definition edits are never version-bumped

## Overview

The version bump step should run after compound has completed, not before. Compound's route-to-definition phase (compound-capture Step 8) can edit files under `plugins/soleur/` (skill SKILL.md files, agent definition files, command files). These staged edits must be included in the version bump's diff check. Currently, when ship runs compound in Phase 2 and version bump in Phase 4, this ordering works. But when one-shot runs compound again at step 6 (after ship has already done the version bump), the second compound's route-to-definition edits are never captured by any version bump.

## Problem Statement

### How compound modifies plugin files

Compound has three mutation phases:

1. **Constitution promotion** (compound SKILL.md line 142-158): Edits `knowledge-base/overview/constitution.md`. NOT under `plugins/soleur/` -- irrelevant to version bump.

2. **Route-to-definition** (compound-capture Step 8, compound SKILL.md line 161-173): Edits skill, agent, or command definition files under `plugins/soleur/`. Explicitly does NOT commit: "Do NOT commit or version-bump -- the edits are staged for the normal workflow completion protocol" (compound-capture line 308). These staged edits rely on a subsequent commit+version-bump step.

3. **Auto-consolidation** (compound SKILL.md line 192-204): Commits `knowledge-base/` archival moves. Does NOT touch `plugins/soleur/`.

The version-bump-relevant mutation is #2: route-to-definition. It stages plugin file edits and expects the caller to handle the commit and version bump.

### Where the ordering breaks

**Path A: Ship standalone (correct ordering)**
```
Phase 2 compound -> route-to-definition stages plugin edits
Phase 3.5 merge main
Phase 4 version bump -> diff includes staged edits -> bump happens
Phase 7 push
```
This path works. Version bump sees compound's staged edits.

**Path B: One-shot pipeline (broken ordering)**
```
Step 3 work -> delegates to ship:
  ship Phase 2 compound #1 -> route-to-definition stages edits
  ship Phase 4 version bump -> captures compound #1 edits
  ship Phase 7 push + PR
Step 4 review -> may find issues
Step 5 resolve-todo -> may fix issues
Step 6 compound #2 -> route-to-definition stages NEW plugin edits
Step 7 test-browser
Step 8 feature-video
```
Problem: Compound #2's route-to-definition edits at step 6 are staged AFTER ship already did version bump and push at Phase 4/7. These edits are orphaned -- no version bump picks them up, and they may not even be committed.

**Path C: Ship with compound skipped (broken ordering)**
```
Phase 2 compound -> user skips (no artifacts)
Phase 4 version bump -> bumps based on current diff
Phase 7 pre-push gate -> catches unarchived artifacts -> runs compound
  compound route-to-definition stages plugin edits
  BUT version bump already ran in Phase 4
Phase 7 continues push -> version bump is stale
```
Problem: The pre-push compound gate in Phase 7 can produce route-to-definition edits after version bump already committed.

### Research Insights

**From merge-pr-skill-design-lessons (Issue 4):**
> "Compound is always a pre-condition of the commit, never a post-condition. The sequence is fixed: review -> compound -> commit -> push -> CI -> merge."

This established principle addresses compound's placement relative to commit/push. The missing corollary is: **version bump must also come after compound**, since compound can stage plugin file edits that affect the version bump decision.

**From compound-capture Step 8 line 308:**
> "Do NOT commit or version-bump -- the edits are staged for the normal workflow completion protocol."

This explicitly defers version-bump responsibility to the caller. If the caller (ship) has already done the version bump before compound ran, the contract is violated.

## Proposed Solution

The fix is surgical: move the version bump phase in the ship skill to run after compound has fully completed, and ensure no workflow path allows version bump to run before compound's route-to-definition edits are staged.

### Change 1: Ship skill -- move version bump after tests

In `plugins/soleur/skills/ship/SKILL.md`, reorder phases:

**Current order:**
```
Phase 1: Validate artifacts
Phase 2: Capture learnings (compound)
Phase 3: Verify documentation
Phase 3.5: Merge main
Phase 4: Version bump          <-- runs here
Phase 5: Final checklist
Phase 6: Tests
Phase 7: Push and PR
```

**New order:**
```
Phase 1: Validate artifacts
Phase 2: Capture learnings (compound)
Phase 3: Verify documentation
Phase 3.5: Merge main
Phase 4: Tests                 <-- renumbered from Phase 6
Phase 5: Version bump          <-- moved after tests, renumbered
Phase 6: Final checklist       <-- renumbered from Phase 5
Phase 7: Push and PR
```

Rationale: Version bump is the last mutation before push. Tests run on the pre-bump code (which is fine -- the version bump only touches metadata files). The final checklist summarizes the state including the version bump. This ordering makes version bump the absolute last file mutation before push, guaranteeing compound's route-to-definition edits are captured.

**Why move version bump AFTER tests, not just after compound?** Tests might reveal issues that need fixing. Those fixes could touch plugin files. By placing version bump after tests, we capture everything: compound edits, test-fix edits, documentation edits. The principle is: version bump is a sealing operation that snapshots the final state.

### Change 2: Ship skill -- remove pre-push compound re-check

The current Phase 7 has a "Pre-Push Gate: Verify /compound completed" section that checks for unarchived artifacts and can trigger compound. This is now redundant: compound ran in Phase 2, and the pre-push gate creates exactly the broken ordering (Path C above) where compound runs after version bump.

Remove the pre-push compound gate from Phase 7. Phase 2 is the single point where compound runs. If compound was skipped in Phase 2, the user made a conscious choice -- do not re-gate at push time.

**Edge case: What if compound was skipped but should not have been?** The Phase 2 compound check already enforces that unarchived artifacts CANNOT be skipped ("Do NOT offer Skip"). The skip option only exists for the "no artifacts" case, which means there is nothing for compound to consolidate. The pre-push re-check was defense-in-depth for a scenario that Phase 2 already prevents.

### Change 3: One-shot skill -- add version bump after step 6

In `plugins/soleur/skills/one-shot/SKILL.md`, add a version bump step after compound (step 6) to capture any route-to-definition edits from the second compound run:

**Current steps 3-9:**
```
3. work (delegates to ship, which does version bump)
4. review
5. resolve-todo-parallel
6. compound
7. test-browser
8. feature-video
9. DONE
```

**New steps 3-10:**
```
3. work (delegates to ship -- ship still does version bump for its compound run)
4. review
5. resolve-todo-parallel
6. compound
6.5 version-bump-recheck: If step 6 compound produced staged changes under plugins/soleur/,
    re-run version bump logic (re-read plugin.json, re-bump, update triad + sync targets).
    If no new plugin changes, skip.
7. test-browser
8. feature-video
9. push (with amend or new commit for version bump changes)
10. DONE
```

Wait -- this is getting complicated. Let me reconsider.

**Simpler approach for one-shot:** The one-shot skill currently has ship doing the full lifecycle including push and PR. The second compound at step 6 happens AFTER ship has already pushed. This means the second compound's edits would require another push.

The cleaner fix: **have ship NOT push when invoked from one-shot**. Instead, one-shot handles push/PR as its own final step after all mutations (including the second compound) are done.

But skills cannot invoke each other programmatically or pass flags. Ship always does push+PR in Phase 7.

**Cleanest approach: Restructure one-shot to not use ship for push/PR.** One-shot should:
1. Run work (which delegates to ship)
2. Ship runs through version bump but STOPS before push (which it cannot -- ship is a single skill invocation)

This reveals a design tension. Let me simplify further.

### Revised Change 3: One-shot skill -- move compound before work/ship

The simplest fix for one-shot: move compound to run BEFORE work/ship, so ship's version bump captures all compound edits:

**New steps:**
```
3. work (delegates to ship)
4. review
5. resolve-todo-parallel
6. compound           <-- captures learnings from review + resolve-todo
7. merge-pr           <-- handles version bump, push, PR, CI, merge, cleanup
8. test-browser
9. feature-video
10. DONE
```

Wait, this does not work either. Compound at step 6 would run AFTER ship has already pushed at step 3.

**The real issue:** One-shot conflates "ship" (which includes push+PR) with "version bump" (which is one step inside ship). The fix requires either:

(a) Splitting ship so version bump + push are separate from the pre-push validation, OR
(b) Having one-shot not use ship at all, and instead inline the relevant ship phases

Option (a) violates the single-skill-file principle.

Option (b): **One-shot should use `work` for implementation only (Phases 1-3), then handle the remaining lifecycle steps directly.** The work skill can be told to stop before invoking ship.

Actually, reading the work skill more carefully (lines 272-290), it says "Delegate to the `/ship` skill, which enforces the complete shipping checklist" as Phase 4. This is the handoff point.

**The actual simplest fix:** Modify the work skill's Phase 4 to delegate to ship WITHOUT the push/PR phases. Ship runs Phases 0-6 (everything up to and including version bump + tests). Then one-shot handles the remaining steps (compound, version bump re-check, push, PR) in its own sequencing.

But again, skills cannot be parameterized.

### Final simplified approach

After analyzing all the paths, the minimal change set is:

1. **Ship skill**: Move version bump after tests (Change 1). Remove pre-push compound gate (Change 2). This fixes Path A and Path C.

2. **One-shot skill**: After step 6 (compound), add a conditional step: "If compound produced staged changes under `plugins/soleur/`, commit them with a version bump. Re-read `plugin.json`, determine if the version needs re-bumping (e.g., compound added a route-to-definition edit to a skill file), update the triad, commit, and push." This fixes Path B.

3. **No changes to merge-pr, compound, or work skills.**

## Acceptance Criteria

- [x] In ship skill, version bump phase (now Phase 5) runs after tests (now Phase 4) and after compound (Phase 2)
- [x] Ship skill Phase 7 no longer has a pre-push compound re-check gate
- [x] One-shot skill has a version-bump-recheck step after step 6 compound
- [x] merge-pr skill remains unchanged (compound is pre-condition, version bump is Phase 4)
- [x] Constitution principle updated to codify: version bump must follow compound in all workflow paths
- [x] No path exists where version bump runs, then compound produces additional plugin file changes that are unaccounted for

## Test Scenarios

- Given a feature that modifies plugin files, when ship runs compound in Phase 2 and compound's route-to-definition edits a skill file, then the version bump in Phase 5 includes that edit in its diff check
- Given one-shot runs compound at step 6 after ship has already version-bumped, when compound edits a skill definition file via route-to-definition, then the version-bump-recheck at step 6.5 detects the new plugin change and re-bumps
- Given a user runs ship and compound produces no route-to-definition edits, when version bump runs, then it behaves identically to today (no regression)
- Given ship runs with no unarchived artifacts and user skips compound, when push happens, then no pre-push compound gate blocks (gate removed)
- Given ship runs with unarchived artifacts, then compound in Phase 2 is mandatory (skip not offered), and version bump in Phase 5 captures all resulting edits

## Non-goals

- Changing the compound or compound-capture skill itself (the "Do NOT commit or version-bump" contract in compound-capture Step 8 is correct)
- Changing the merge-pr skill (ordering is already correct there)
- Adding automated tests for the workflow ordering (these are skill instruction files, not executable code)
- Restructuring the work skill's delegation to ship

## Files to Modify

1. `plugins/soleur/skills/ship/SKILL.md` -- move version bump (Phase 4 -> Phase 5, after tests), remove pre-push compound gate from Phase 7, renumber phases
2. `plugins/soleur/skills/one-shot/SKILL.md` -- add step 6.5 version-bump-recheck after compound
3. `plugins/soleur/skills/work/SKILL.md` -- update the inline description of ship's phases (lines 280-290) to reflect new ordering
4. `knowledge-base/overview/constitution.md` -- add principle: "Version bump must run after compound in all workflow paths; it is a sealing operation that snapshots the final state before push"

## Edge Cases

### Compound produces no route-to-definition edits
Most common case. Version bump runs identically to today. No regression.

### Compound produces route-to-definition edits but no version bump was needed
If the branch had no plugin file changes before compound, but compound's route-to-definition added one, the version bump step must now detect that a PATCH bump is needed. The existing `git diff --name-only origin/main...HEAD -- plugins/soleur/` check handles this correctly because it runs against HEAD (which includes compound's staged-then-committed edits).

### One-shot compound #2 produces edits after ship already pushed
The version-bump-recheck at step 6.5 creates a new commit. The subsequent `git push` in step 7 (test-browser) or before feature-video would need to push this commit. Add an explicit push step after the version-bump-recheck.

### Tests fail after compound but before version bump
Tests run in Phase 4 (new numbering). If they fail, ship stops. Version bump never runs. This is correct -- no version bump on broken code.

## References

- `plugins/soleur/skills/ship/SKILL.md:60-84` -- current Phase 2 (compound) logic
- `plugins/soleur/skills/ship/SKILL.md:125-162` -- current Phase 4 (version bump) logic
- `plugins/soleur/skills/ship/SKILL.md:216-230` -- current Phase 7 pre-push compound gate
- `plugins/soleur/skills/one-shot/SKILL.md:84-93` -- steps 3-9 ordering
- `plugins/soleur/skills/compound-capture/SKILL.md:259-308` -- Step 8 route-to-definition ("Do NOT commit or version-bump")
- `plugins/soleur/skills/compound/SKILL.md:142-173` -- constitution promotion and route-to-definition
- `knowledge-base/learnings/2026-02-12-review-compound-before-commit-workflow.md` -- "the commit is the gate, not the PR"
- `knowledge-base/learnings/2026-02-22-merge-pr-skill-design-lessons.md` -- Issue 4: compound after CI creates infinite loop
- Constitution line 63 -- compound before commit, compound produces commits
