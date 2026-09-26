---
title: "Tasks: archive #8710 pin-redeploy and #5274 dirty-journal KB artifacts"
branch: feat-one-shot-archive-8710-5274-plans
plan: knowledge-base/project/plans/2026-09-25-chore-archive-8710-5274-kb-artifacts-plan.md
lane: cross-domain
---

# Tasks

## 1. Setup

- [x] 1.1 Confirm that all 4 source paths still exist on the worktree tip, and that #8211's plan and spec are untouched.

## 2. Core Implementation

- [x] 2.1 Run `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh <slug>` for each of the 4 slugs
      in the plan. Always pass a slug: a run without one would archive this PR's own spec dir.
- [x] 2.2 Commit with `chore(archive-kb): archive #8710 pin-redeploy and #5274 dirty-journal KB artifacts`.
- [x] 2.3 Comment on #8776 with the archived path of its `decision-challenges.md`.
- [x] 2.4 File the missing DC-1 `action-required` issue for PR #8711, citing the archived path (filed as #8847).

## 3. Testing / Verification

- [x] 3.1 AC1 diff-scope: 8 R100 renames plus this PR's own plan and spec artifacts only.
- [x] 3.2 AC2/AC3: the source paths are gone, the pathspec count is 8, and #8211's artifacts are still live.
- [x] 3.3 AC4: the inbound-reference sweep (excluding archive/, *.json, and this PR's own artifacts)
      returns only the discoverability-test comment.
- [x] 3.4 AC5: `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts -t G1` passes.
- [x] 3.5 AC6: `bash scripts/kb-drift-walker.sh | jq -c .counts` reports at most 128 broken links and at most 120 broken anchors.
- [ ] 3.6 AC8: the PR #8842 body contains `Ref #5274` and no closing keyword; #5274 is still OPEN.
- [ ] 3.7 AC9: every required check passes by name on the exact head SHA. Resolve any `PROMOTED_FILES` conflict as a union.
