# Learning: Concurrent PR merges can produce duplicate object properties undetected by git

## Problem

Two security PRs (#903 and #904) both added `settingSources: []` to the same object literal in `apps/web-platform/server/agent-runner.ts`, but at different line positions (191 vs 198). Git's three-way merge merged both cleanly because the insertions were non-overlapping. TypeScript rejected the result with TS2300 ("An object literal cannot have multiple properties with the same name"), breaking the CI build on main.

## Solution

Removed the second `settingSources: []` occurrence (line 198), keeping the first (line 191) which includes the defense-in-depth comment explaining the security rationale.

## Key Insight

Git's merge algorithm has a structural blind spot for "semantic conflicts": when two branches add the same property to an object literal at different positions, git merges cleanly because there is no line-level overlap. The code is textually valid but semantically broken. This failure mode is specific to concurrent PRs touching the same config/options block -- especially common when security hardening PRs run in parallel, since they tend to add overlapping defensive properties.

**Primary defense:** GitHub merge queues serialize merges and run CI on each candidate merge commit, catching this class of error before landing. Without a merge queue, coordinate concurrent PRs targeting the same config block by sequencing merges or rebasing after each lands.

## Tags

category: build-errors
module: web-platform/agent-runner
