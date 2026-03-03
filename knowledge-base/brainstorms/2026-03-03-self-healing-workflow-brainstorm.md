# Self-Healing Workflow with Session-Level Learning Loops

**Date:** 2026-03-03
**Issue:** #397
**Branch:** feat-self-healing-workflow
**PR:** #416

## What We're Building

A two-layer automated learning loop that detects workflow deviations and systemic patterns, then proposes enforcement mechanisms (hooks > prose rules) and rule retirement — closing the feedback loop that is currently manual.

**Layer 1 — Deviation Scanner (in-session):** A new subagent in compound's parallel fan-out that compares session actions against AGENTS.md/constitution.md rules and proposes PreToolUse hooks or constitution amendments for each deviation found.

**Layer 2 — Weekly CI Sweep:** A scheduled GitHub Action that reads the full learnings corpus, identifies recurring patterns (3+ similar issues), and creates auto-PRs proposing new hooks, constitution updates, and rule retirement.

## Why This Approach

The existing compound skill already captures learnings and routes them to definition files — but the promotion from learning to enforcement is human-gated and single-session scoped. The project's proven pattern is that documentation-only rules get violated until hooks enforce them mechanically. This approach automates the promotion pipeline while keeping humans in the loop at the PR review stage.

Key evidence from learnings research:
- 4 PreToolUse hooks exist, each added after a prose rule failed to prevent the violation it described
- Session boundaries are the weakest link — end-of-session steps get skipped (learning: stale-worktrees-accumulate)
- AGENTS.md has a measurable 10-22% reasoning token cost per rule (ETH Zurich, Feb 2026)
- Prose instructions in SKILL.md bypass hook enforcement entirely (learning: stash-to-checkpoint)
- 194 rules in constitution.md with no retirement mechanism

## Key Decisions

1. **Transcript access:** Claude Code doesn't expose session transcripts. The in-session layer analyzes deviations while context is still in the LLM window. The CI layer operates on committed artifacts (learnings files).

2. **Output priority:** For each deviation found, propose a PreToolUse hook first. Only fall back to prose rules when hooks can't cover the violation. Follows the proven enforcement hierarchy: hooks > skill instructions > prose rules.

3. **CI sweep output:** Full auto-PR. The sweep generates PRs for hooks, constitution updates, AND rule retirement. Human gate is the PR review, not the proposal step.

4. **Rule retirement triggers:** Two triggers — (a) hook supersedes a prose rule (immediate, deterministic), (b) zero violations across 20+ sessions of learnings (organic obsolescence).

5. **CI frequency:** Weekly cron schedule. Enough data to spot patterns (~3-5 new learnings/week), infrequent enough to avoid PR noise.

6. **Architecture:** Extend compound's existing parallel subagent fan-out (not a new skill). CI sweep is a new GitHub Actions workflow using claude-code-action.

## Open Questions

- How to measure "zero violations in 20+ sessions"? Need a violation tracking schema in learnings frontmatter, or a separate violations log.
- Should the deviation scanner also check for contradictory rules (issue step 3)? Or leave contradiction detection to the CI sweep which has the full corpus?
- What's the approval threshold for auto-PRs? Should hook PRs require different review scrutiny than rule retirement PRs?
- How to handle the chicken-and-egg: the deviation scanner needs AGENTS.md rules to exist to detect deviations, but the goal is to generate those rules from deviations?

## CTO Assessment Summary

- **Transcript access:** HIGH risk — blocking for "post-session" framing. In-session analysis is the viable path.
- **Rule bloat:** HIGH risk — 194 rules already, automated additions without retirement = unbounded growth. Mitigated by hooks-first + retirement.
- **Blast radius:** HIGH risk for AGENTS.md (loaded every turn). Mitigated by PR-based flow — no direct edits.
- **Integration complexity:** LOW — compound's parallel subagent architecture provides a clean extension point.
- **Recommended:** Option 1 (enhance compound) for in-session + Option 2 (CI sweep) for cross-session.

## Learnings Research Insights

14 relevant learnings informed this brainstorm:
- Hook enforcement beats documentation (worktree-enforcement-pretooluse-hook)
- Compound is a pre-commit gate, not post-CI (review-compound-before-commit-workflow)
- AGENTS.md gotchas-only principle (lean-agents-md-gotchas-only)
- Session boundaries as failure points (stale-worktrees-accumulate-across-sessions)
- Dead rules from conditional enforcement (worktree-not-enforced-for-new-work)
- Context compaction breaks error forwarding (context-compaction-command-optimization)
- Prose instructions bypass hooks (test-fix-loop-stash-to-checkpoint-commits)
- Semantic assessment over keyword matching (domain-leader-pattern-and-llm-detection)
