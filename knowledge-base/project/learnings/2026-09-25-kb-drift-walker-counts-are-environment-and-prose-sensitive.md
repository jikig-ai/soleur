---
title: "kb-drift-walker counts are environment- and prose-sensitive: quote a delta, never an absolute"
date: 2026-09-25
category: workflow-issues
module: knowledge-base
tags: [kb-drift-walker, archive-kb, acceptance-criteria, measurement]
related: [8842, 5274, 7400]
---

# Learning: kb-drift-walker counts are environment- and prose-sensitive

## Problem

PR #8842 (a rename-only KB archive) carried an AC quoting absolute `scripts/kb-drift-walker.sh`
counts: `broken_link <= 128, broken_anchor <= 120`. It failed twice for reasons unrelated to the change:

1. The PR's own plan contained the literal `` `](x.md)` `` inside inline code. The walker's link
   extractor does not skip code spans or fences, so the plan itself added one broken link (128 -> 129).
2. The anchor baseline depends on the environment. One learning anchors into
   `node_modules/@11ty/eleventy/src/TemplateFileSlug.js:33`, which resolves only where `node_modules`
   is installed: 120 in a hydrated worktree, 121 in a clean tree (merge-base, `origin/main` and the PR
   head all read 121 under `git archive` + `KB_DRIFT_FIXTURE_ROOT`).

## Solution

- Reworded the plan to "markdown links" (no link syntax in prose). The count went back to 128.
- Restated the AC as a delta: counts must not rise against the merge-base measured in the same
  environment.
- To get a clean-tree baseline without the ~2-minute dependency install that `git worktree add`
  triggers, export the tree and point the walker at it:
  `d=$(mktemp -d /var/tmp/kbw.XXXXXX); git archive <sha> | tar -x -C "$d"; KB_DRIFT_FIXTURE_ROOT="$d" bash scripts/kb-drift-walker.sh | jq -c .counts`.

## Key Insight

Any AC that quotes an absolute count from a whole-repo scanner claims two things it does not control:
the environment the scanner runs in, and the bytes the PR itself adds. Write a delta against the
merge-base, measured in one environment, and keep the scanner's own trigger syntax out of the prose.

## Session Errors

1. **A Bash call included `git stash list`, and the stash hook blocked the whole call.** Recovery: re-ran without it. **Prevention:** already hook-enforced (`guardrails:block-stash-in-worktrees`); never probe the stash in a worktree.
2. **`git worktree add` for a base measurement exceeded the 120 s foreground timeout** (the checkout installs dependencies). Recovery: it finished in the background. **Prevention:** use `git archive` + `KB_DRIFT_FIXTURE_ROOT` for read-only base measurements (above).
3. **The plan's inline-code `` `](x.md)` `` counted as a broken link.** Recovery: reworded. **Prevention:** plan-sharp-edges bullet (routed in this PR): no markdown-link syntax in plan prose, and walker ACs as deltas.
4. **The AC6 anchor ceiling of 120 was environment-dependent.** Recovery: added a correction note restating it as a delta. **Prevention:** same bullet.
5. **The minimal-mode plan omitted `priority`, `domain`, `brand_survival_threshold` and `requires_cpo_signoff` frontmatter.** Recovery: added at review. **Prevention:** one-off; plan Stage-2 finalization already lists them.
6. **Issue #8847 inherited "changes money" from #8776's template sentence while stating a per-rehearsal cost.** Recovery: `gh issue edit`. **Prevention:** re-check every sentence copied from a sibling artifact against the new subject (compound Phase 0.5 inherited-framing bullet).

## Tags
category: workflow-issues
module: knowledge-base
