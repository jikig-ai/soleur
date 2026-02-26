# Learning: Version bump must run after compound in all workflow paths

## Problem
Version bump and compound had inconsistent ordering across workflow paths. In ship standalone, compound ran first (Phase 2) and version bump later (Phase 4) -- correct. But in one-shot, a second compound at step 6 ran after ship had already done version bump and push, orphaning route-to-definition edits. Ship's pre-push compound gate (Phase 7) could also trigger compound after version bump.

## Solution
1. Reordered ship phases: tests (Phase 4) -> version bump (Phase 5) -> checklist (Phase 6)
2. Removed pre-push compound gate from ship Phase 7 (redundant with Phase 2's enforcement)
3. Added version-bump-recheck (step 6.5) to one-shot after second compound
4. Added constitution principle codifying the ordering invariant

## Key Insight
Version bump is a sealing operation -- it must be the last file mutation before push. Compound's route-to-definition phase can edit plugin files without committing them, so any version bump that runs before compound will miss those edits. The fix is positional: ensure version bump always follows compound, and add a recheck when compound runs again later in the pipeline.

## Tags
category: architecture
module: ship, one-shot, compound
