# CMO Ship Content Gate Improvement

**Date:** 2026-03-29
**Status:** Approved
**Issue:** TBD

## What We're Building

Two workflow improvements to ensure the CMO reliably evaluates shipped features for content planning and amplification:

1. **Fix A — Phase 5.5 multi-signal trigger with LLM evaluation**: Replace the file-path-only trigger in `/ship` Phase 5.5 with a multi-signal pre-filter plus LLM semantic assessment by the CMO agent.
2. **Fix B — Plan domain assessment**: Add Phase 0.5 domain assessment (CPO + CMO minimum) to the `/plan` skill when brainstorm was skipped.

## Why This Approach

PR #1256 (PWA installability) shipped as a Phase 1 milestone feature without any content consideration. The CMO content-opportunity gate in `/ship` Phase 5.5 did not fire because:

- **Trigger gap**: The gate only checks if the PR touches `knowledge-base/product/research/` or `knowledge-base/marketing/`. PWA only touched `apps/web-platform/` files. The gate explicitly skips "code-only PRs" — but PWA is a user-facing feature delivered entirely as code.
- **Brainstorm skip**: PWA went straight to `/plan`, bypassing the brainstorm Phase 0.5 domain assessment where CMO would have been consulted. The AGENTS.md rule "CPO and CMO at minimum in brainstorm" is unenforceable when brainstorm is skipped.

The CMO agent and all marketing skills work correctly. The trigger logic is the broken component.

## Key Decisions

### Decision 1: Multi-signal pre-filter + LLM evaluation for Phase 5.5

The current gate asks "Did the PR touch marketing files?" The correct question is "Does this PR ship something content-worthy?" — and that question requires LLM judgment, not regex.

**Trigger flow:**

1. **Fast-path triggers** (existing, kept): PR touches `knowledge-base/product/research/`, `knowledge-base/marketing/`, or adds new workflow patterns. Fire CMO immediately.
2. **Structural pre-filter** (new): Check for any of:
   - `semver:minor` or `semver:major` label
   - PR title matches `feat:` or `feat(*):` pattern
   - PR closes a milestone issue (via `gh pr view --json closingIssuesReferences`)
   - If none present: skip CMO gate
3. **LLM semantic evaluation** (new): If any structural signal present, spawn CMO agent with PR diff summary + title + linked issue body. CMO assesses content-worthiness and either produces actionable output (content brief + content-strategy.md update) or explicitly says "no content opportunity."
4. **Remove** the blanket "skip for code-only PRs" exclusion. Replace with: "Skip for `semver:patch` PRs with `fix:` titles that do not close a milestone issue and have no file-path triggers."

**Why not always fire CMO on every PR?** Pre-filtering with structural signals avoids burning tokens and adding latency on routine patch-level bug fixes.

### Decision 2: Domain assessment in /plan as defense-in-depth

When `/plan` runs without a preceding brainstorm document, it should run the same Phase 0.5 domain assessment from the brainstorm skill (CPO + CMO at minimum). This ensures domain leaders are consulted even when the workflow enters through `/plan` rather than `/brainstorm`.

**Detection**: The plan skill checks for a brainstorm document in `knowledge-base/project/brainstorms/` matching the feature name or linked issue. If none found, domain assessment runs before plan generation.

### Decision 3: CMO gate produces immediate output, not a queue

When the CMO gate fires and identifies a content opportunity, it updates `content-strategy.md` and creates distribution content immediately — not a "scheduled for later" queue. This is consistent with the existing mandatory content-strategy update (PR #1177) and avoids creating deferred work items that never get executed.

## Open Questions

None — design is approved.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** The CMO confirmed that PWA has high content potential (announcement, engineering blog post, positioning update) that was entirely missed. The root cause is the file-path-only trigger in Phase 5.5. The CMO recommends multi-signal detection with semantic assessment, capacity-aware content briefs (one article, not a comprehensive plan), and verification of existing content state before recommending new content. All needed agents (CMO, growth-strategist, copywriter, content-writer, social-distribute) already exist — no capability gaps.
