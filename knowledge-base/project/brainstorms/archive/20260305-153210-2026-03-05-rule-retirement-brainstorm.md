# Rule Retirement Brainstorm

**Date:** 2026-03-05
**Issue:** #422
**Branch:** feat-rule-retirement

## What We're Building

A two-layer system to control governance rule growth and prevent context window bloat:

1. **Scheduled Rule Layer Audit (GitHub Action)** -- Bi-weekly CI job that cross-references all governance layers (constitution.md, AGENTS.md, PreToolUse hooks, agent descriptions, skill instructions) to detect duplicated rules and hook-superseded prose. Creates a GitHub issue with findings and a PR with proposed tier migrations.

2. **Compound Rule Budget Gate** -- Extension to compound's Deviation Analyst (Phase 1.5) that warns when governance layers exceed token budgets or contain cross-layer duplication. Auto-files a GitHub issue for tracked follow-up. Warn-only, never blocks compound.

## Why This Approach

**Problem:** Rules accumulate across 5 governance layers without deduplication. Constitution.md (197 rules) and AGENTS.md (22 rules) are loaded every turn, costing 10-22% extra reasoning tokens. The same rule can appear as a hook, a prose rule, an agent description, and a skill instruction simultaneously.

**Prior art:** Three plan reviewers rejected full automation (Layer 2 of self-healing workflow) on 2026-03-03 as premature. What changed: the concern is not "automate retirement" but "control context budget." The scheduled audit is a lightweight script, not the full CI sweep that was rejected. The compound gate is a warning, not a blocking gate.

**Approach rationale:**

- Scheduled audit catches drift before it compounds (bi-weekly)
- Compound gate catches duplication at the source (per-session)
- Neither requires session counting infrastructure or cross-session aggregation
- Both produce GitHub issues for human review -- no silent autonomous retirement

## Key Decisions

1. **Two complementary mechanisms, not one.** CI audit for periodic cleanup; compound gate for prevention. Neither alone is sufficient.

2. **Bi-weekly schedule for CI audit.** Weekly is too noisy for current scale; monthly lets drift accumulate.

3. **CI audit creates both issue and PR.** Issue for visibility and discussion; PR for reviewable proposed changes.

4. **Compound gate is warn-only.** Shows budget stats and duplication alerts but does not block. Auto-files a GitHub issue so findings aren't lost.

5. **Five enforcement tiers (cheapest to most expensive):**
   - Tier 1: PreToolUse hook (zero context cost, mechanical enforcement)
   - Tier 2: AGENTS.md (always loaded, sharp edges only)
   - Tier 3: constitution.md (always loaded, conventions and judgment)
   - Tier 4: Agent descriptions (loaded on agent reference)
   - Tier 5: Skill instructions (loaded on skill invocation)

   Each rule should live at the cheapest tier that provides adequate enforcement. Duplication across tiers is the antipattern this system detects.

6. **Hook-superseded rules migrate, not delete.** A prose rule enforced by a hook migrates from AGENTS.md (Tier 2) to constitution.md (Tier 3) with a `[hook-enforced]` annotation, or to an appendix. This preserves defense-in-depth documentation without per-turn context cost.

7. **No manifest file (yet).** The rule-manifest.yaml from Approach C is deferred. The audit script parses governance files directly. If scale demands structured metadata later, the manifest can be added incrementally.

## Open Questions

1. **Token budget thresholds.** What rule count or token count triggers the compound warning? Current: 197 constitution + 22 AGENTS.md. Proposal: warn above 200 total always-loaded rules.

2. **Audit script language.** Shell script for portability in GitHub Actions, or Ruby/Python for easier parsing? Shell + jq likely sufficient given the structured format of constitution.md.

3. **PR generation scope.** Should the CI audit PR only propose tier migrations (moving rules between layers) or also propose rule deletions (removing genuinely obsolete rules)?

4. **Hook fragility.** Learnings document 3 guardrail regex bugs. Should the audit verify hook test coverage in `test-pretooluse-hooks.yml` before proposing migration of a hook-backed rule?

5. **Trigger B (zero-violation decay) from original issue.** Still deferred -- requires session counting infrastructure. Revisit when/if compound starts writing structured session reports.
