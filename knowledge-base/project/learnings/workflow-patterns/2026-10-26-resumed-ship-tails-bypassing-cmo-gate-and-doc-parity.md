---
title: "Resumed ship tails bypassing Phase 5.5 CMO content gates and documentation omissions"
date: 2026-10-26
category: workflow-patterns
issue: 10362
pr: 10362
synced_to: [ship, components-test]
tags: [ship-gate, cmo-content-gate, documentation-parity, fail-closed-hook, harness-manifest]
---

# Learning: Resumed ship tails bypassing Phase 5.5 CMO content gates and documentation omissions

## Problem

When shipping PR #10362 (adding Google Antigravity CLI support), two workflow omissions occurred:
1. **The CMO Content-Opportunity Gate was skipped**: PR #10362 had title `feat(harness): add Antigravity CLI (agy) support`, which triggers the Phase 5.5 CMO Content-Opportunity Gate (`hr-before-shipping-ship-phase-5-5-runs`). However, because the PR was resumed mid-flow to fix CI failures and then merged directly via `gh pr merge --squash --auto`, the agent bypassed `/ship` Phase 5.5. Because the rule was only marked `[skill-enforced: ship Phase 5.5]` without a PreToolUse hook, nothing intercepted the direct `gh pr merge` call.
2. **Public-facing documentation was omitted**: The code, manifests, and test suites for the new harness shipped to production, but `README.md` and `plugins/soleur/docs/pages/getting-started.njk` (`soleur.ai/getting-started/`) were not updated to list the new harness or include it in the comparison table.

## Root Cause

1. **Prose-only gate enforcement at tool boundaries**: Gates specified only as procedural prose in `SKILL.md` are easily bypassed during manual ship tails, interruptions, or CLI retries. Sibling gates (`ship-operator-step-gate.sh`, `ship-unpushed-commits-gate.sh`) intercept `gh pr ready` and `gh pr merge` as PreToolUse hooks, but the CMO content gate lacked a hook twin.
2. **Missing regression/parity assertions**: `components.test.ts` thoroughly tested harness unique skill names and manifest discovery, but lacked an assertion that every supported harness in `lib/harness.ts` has matching documentation in `README.md` and `getting-started.njk`.

## Resolution

1. **Fail-closed PreToolUse Hook**: Implemented `.claude/hooks/ship-cmo-content-gate.sh` wired in `.claude/settings.json`, `.devin/config.json`, and `.claude/hooks/devin-dispositions.tsv`. Any `gh pr ready` or `gh pr merge` on a `^feat\b` PR is blocked unless the branch touches marketing/blog paths, carries a `Reviewed-By-CMO:` trailer, or sets `SOLEUR_SKIP_CMO_CONTENT_GATE=1`.
2. **Automated Documentation Parity Tests**: Added tests in `plugins/soleur/test/components.test.ts` asserting that every supported harness is documented in `README.md` and present in `getting-started.njk` (both in prose and as a comparison table column).
3. **Remediated Documentation and Content**: Updated `README.md`, `getting-started.njk`, and drafted the release blog post (`plugins/soleur/docs/blog/2026-10-26-run-your-ai-company-on-google-antigravity.md`).
