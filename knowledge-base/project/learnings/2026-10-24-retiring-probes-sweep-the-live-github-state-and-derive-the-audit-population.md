# Learning: retiring probes — sweep live GitHub state, and derive (never hand-list) the audited population

## Problem
G1 PR-4a deleted four followthrough probes of closed trackers plus their guard rows (880 -> 825 bearer-sweep rows). Everything repo-side was green after the first pass, yet a 5-seat review found that (a) a closed *promotion* tracker (#9888) still carried a `soleur:followthrough` directive naming a deleted script, inside the sweeper's 14-day closed lookback; (b) the HMAC audit population (`HM5_FILES`) was a hand-written list that had already left one manifest probe unaudited and could be swapped without moving the row count; (c) the plan-quoted floor values (S4_GUARD_FLOOR 72, PJ_TRIPLES 287) were wrong against the measured tree (74 and 289, later 286).

## Solution
- Check the live GitHub state (closed `follow-through` issues in the lookback window) for directives naming each deleted script; remove the label post-merge (CTO ruling), documented in `followthrough-convention.md` §Retiring a probe.
- Derive `HM5_FILES` from `HMAC_MANIFEST` and add a census that the files holding the canonical HMAC program equal the audited set; count the facets driven per file.
- Set floors to the measured count (plan AC4 / ruling F3), not to the plan's estimate.
- `regenerate-shard-manifest.py --incremental` drags in rows from other PRs' unregistered suites: inspect its diff and hand-delete the single row when the regeneration is wider than the deletion.

## Key Insight
A retirement sweep indexed by the repo's file list cannot see state that lives in GitHub, and a hand-listed audit population is a second declaration site that silently drifts. Derive the population from the manifest and pin it from both sides.

## Session Errors
1. **Linear-ID regex matched "PR-4" in "PR-4a"** — Recovery: judged it a pipeline slice name and skipped the lookup. Prevention: one-shot Step 0a could also ignore `PR-<n>` slice names (G1 uses PR-1..PR-4); one-off, not filed.
2. **Manifest regenerator widened the diff with two unrelated rows** — Recovery: reverted, hand-deleted the one row in all four files. Prevention: diff a regenerator's output against the intended deletion before accepting.
3. **Plan-quoted counts (floor 72, triples 287) were wrong against the tree** — Recovery: re-measured (74, 289). Prevention: already covered by the "plan-quoted numbers are preconditions" work-skill rule.
4. **`git commit` with an expanded `$SBX` path was blocked by the commit-target hook** — Recovery: literal absolute paths. Prevention: use literal paths (or `git -C /abs`) in the same command.
5. **`rm -rf` on a sandbox I had `git init`ed was blocked as a protected checkout** — Recovery: `scripts/soleur-sandbox.sh rm`. Prevention: remove sandboxes only through the allocator's `rm`.
6. **Two `Ruled by CTO agent` rows failed the ruling-gate shape** (text between the date and the colon) — Recovery: reshaped. Prevention: write the row as `Ruled by CTO agent, <date>: <decision> - <rationale>` verbatim.
7. **Edited `grep-q-pipe-guard.test.sh` while a bearer-sweep run was in flight** — Recovery: the run stayed green and was re-run afterwards. Prevention: do not edit files an in-flight suite reads (already documented in work/SKILL.md).

## Tags
category: workflow-patterns
module: followthroughs, test-argv-bearer-sweep, G1
