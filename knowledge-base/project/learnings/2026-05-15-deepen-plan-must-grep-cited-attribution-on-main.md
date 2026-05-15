---
title: deepen-plan must verify git-history attribution claims, not just PR/issue state
date: 2026-05-15
tags: [plan, deepen-plan, git-history, citation-verification, multi-agent-review]
component: plugins/soleur/skills/deepen-plan
related_pr: 3850
related_issue: 2749
---

# deepen-plan must verify git-history attribution claims against `main`, not just PR/issue state

## Problem

The plan body for PR #3850 (procedural verification of `peer-plugin-audit` against `travisvn/awesome-claude-skills`) contained a Sharp Edge that asserted:

> The seeding-corpus audit (`alirezarezvani/claude-skills` from PR #2734) was **reverted at merge time** (commit `e91e7bf6` per PR #2734 body: "dropped the tier seeding"). The current `competitive-intelligence.md` contains no `claude-skills` row.

Both clauses were factually wrong:

1. The `alirezarezvani/claude-skills` row was added by the **2026-04-18 monthly CI scan PR `#2697`** (not PR #2734) and was still present on `main` (line 56 of `knowledge-base/product/competitive-intelligence.md` at plan time, with 8 grep hits for `claude-skills` across the file).
2. Commit `e91e7bf6` was internal to PR #2734's branch (`git rev-parse e91e7bf6` → fatal) and dropped a *parallel* "Skill Library" tier seed from that branch — it did NOT remove the alirezarezvani row, which had landed via #2697 a week earlier.

The drift was caught by the `git-history-analyzer` review agent at the post-implementation review phase, then corrected inline in commit `7fd5738c`. No production impact (the actual deliverable — the advisory entry under Tier 3 — was correct because the procedure's `Non-audit outcome` branch is independent of prior file state). But the plan was misleading and would have polluted future searches against `claude-skills` provenance.

## Root Cause

`deepen-plan`'s "live citation verifications" stage ran a strong battery against PR/issue state and target-repo state:

- `gh pr view 2734 --json state` → MERGED ✓
- `gh issue view 2749 --json state` → OPEN ✓
- `gh repo view travisvn/awesome-claude-skills --json licenseInfo,stargazerCount` ✓
- `gh api repos/.../git/trees/HEAD?recursive=1` ✓

But it did NOT probe the **prior-PR git-history attribution claims** baked into the plan's Sharp Edges:

- It did not run `git log --oneline -- knowledge-base/product/competitive-intelligence.md` to check whether the cited "reverted at merge" claim matched actual file history.
- It did not run `git rev-parse e91e7bf6` to verify the cited commit hash was reachable from `main`.
- It did not `git show main:knowledge-base/product/competitive-intelligence.md | grep claude-skills` to verify the "current file contains no claude-skills row" claim.

Result: PR/issue STATE was verified; ATTRIBUTION (which PR added what; which commit reverted what; what's currently on main) was not.

## Solution

Extend `deepen-plan`'s citation-verification battery with a **git-history attribution probe** for any Sharp Edge or Research Reconciliation row that:

- Cites a specific commit hash → run `git rev-parse <hash>` and `git log --oneline <hash> -1`. If unreachable from `main` (`git merge-base --is-ancestor <hash> main` returns non-zero), flag the citation.
- Asserts a file currently contains/lacks specific content → run `git show main:<file> | grep -E '<pattern>'` and reconcile with the claim. Disagreement = flag.
- Attributes a file change to a specific PR ("PR #N added/removed X") → run `gh pr view N --json files` and confirm the file is in the list. Mismatch = flag.

These probes are O(seconds) each and use the same `gh`/`git` toolset already in scope.

## Routing

Edit `plugins/soleur/skills/deepen-plan/SKILL.md` (or the relevant references file) to add a Sharp Edge under its citation-verification phase:

> **Probe attribution claims, not just state.** When a Sharp Edge or Research Reconciliation row cites a commit hash, an "X was reverted/added by PR #N" attribution, or a "file currently contains/lacks Y" claim, run a corresponding `git rev-parse` / `git show main:<file> | grep` / `gh pr view <N> --json files` probe and reconcile against the claim. PR/issue STATE checks (`gh pr view --json state`) do NOT cover ATTRIBUTION claims; the latter are a separate failure surface that surfaces only at post-implementation review (caught here by `git-history-analyzer` for PR #3850). See `knowledge-base/project/learnings/2026-05-15-deepen-plan-must-grep-cited-attribution-on-main.md`.

## Session Errors

1. **Plan citation drift (PR #2734 / e91e7bf6 / "no claude-skills row").** Caught at multi-agent review (git-history-analyzer). **Recovery:** corrected inline in commit `7fd5738c`. **Prevention:** see Routing above — extend `deepen-plan` citation battery with attribution probes.
2. **Plan subagent initially wrote artifacts to bare-root mirror via absolute paths instead of worktree.** Already hook-enforced by `hr-when-in-a-worktree-never-read-from-bare`. **Recovery:** caught at `git add` pathspec mismatch, `mv`'d files, committed. **Prevention:** none additional; the hard rule already governs.
3. **Pre-existing test flake** — `plugins/soleur/test/marketing-content-drift.test.ts` beforeAll exceeds 5s default timeout under batched-test contention; passes standalone with 120s. Not caused by this PR (markdown-only diff). **Prevention:** raise the file's `beforeAll` timeout to ≥30s OR pre-warm the Eleventy build in `globalSetup`. Not in scope for this PR.
4. **Procedure smell — `last_reviewed` overstates scope on non-audit log entries.** `peer-plugin-audit.md:204` prescribes bumping both `last_updated` AND `last_reviewed` even for the `Non-audit outcome` branch (which appends a single advisory entry without re-reviewing the Tier 0/3 matrices). **Recovery:** kept the bump per procedure literal; documented the smell in commit + PR body for procedure refinement. **Prevention:** procedure refinement candidate — split the Output Routing instructions to distinguish full-audit vs. non-audit-outcome behavior.
