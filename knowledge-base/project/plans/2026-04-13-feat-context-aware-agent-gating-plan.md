---
title: "feat: Context-Aware Agent Gating for Token Optimization"
type: feat
date: 2026-04-13
---

# Context-Aware Agent Gating for Token Optimization

## Overview

Add a binary code/non-code classification gate to the review skill so that non-code PRs (docs, config, CI) spawn 4 agents instead of 8. Source code PRs continue to spawn all 8 agents unchanged.

## Problem Statement / Motivation

Soleur is hitting Claude Code usage limits faster than expected. The root cause is cumulative agent sprawl: 60+ agents all use `model: inherit` (Opus), and the review pipeline spawns 8 agents unconditionally regardless of what changed. A docs-only PR triggers performance-oracle and data-integrity-guardian — agents whose expertise is irrelevant to markdown changes.

## Proposed Solution

### Binary Classification Gate

Add a classification step to the review skill that runs `git diff --name-only` and applies a single LLM judgment: **does this PR contain source code changes?**

| Category | Detection | Agents | Count |
|---|---|---|---|
| **Non-code** | All changed files are docs, config, CI, markdown, or skill/agent definitions — no source code (`.ts`, `.js`, `.rb`, `.py`, `.go`, `.rs`, etc.) | git-history-analyzer, pattern-recognition-specialist, security-sentinel, code-quality-analyst | 4 |
| **Code** | Any source code file is present in the diff | All 8 agents | 8 |

**Why security-sentinel stays in non-code:** Markdown can contain executable code examples, CI workflows can expose secrets, and config files can introduce vulnerabilities. Security review is relevant for any change type.

**Conditional agents (9-14) are unaffected.** The classification gate only controls the 8 always-on agents (lines 63-78 of review SKILL.md). The existing conditional agents block (Rails reviewers, migration experts, test-design-reviewer, semgrep — lines 80-151) retains its independent triggers. Both gates run independently.

**Override mechanism:** Check both `$ARGUMENTS` for "deep review" / "full review" phrases AND `gh pr view --json body,title` for the same phrases. If detected in either location, skip classification and spawn all 8 agents.

**File:** `plugins/soleur/skills/review/SKILL.md:63-78`

## Technical Considerations

**Architecture impact:** One SKILL.md file edited. No new files, agents, or infrastructure. All changes are to LLM-evaluated prose.

**Existing pattern:** Ship skill Phase 5.5 (`plugins/soleur/skills/ship/SKILL.md:285-349`) already uses `git diff --name-only origin/main...HEAD` for conditional gating. This replicates that pattern.

**Risk: Miscategorization.** A PR might contain files that look like non-code but have code implications. Mitigation: LLM judgment (not regex) evaluates the file list, so it can identify non-obvious implications. Security-sentinel is included in the non-code set as an additional safety net. The "deep review" override provides a manual safety valve.

## Acceptance Criteria

- [ ] Non-code PRs (docs, config, CI only) spawn 4 agents instead of 8
- [ ] Source code PRs still spawn all 8 agents (no regression)
- [ ] "deep review" override in args or PR body forces full pipeline
- [ ] Conditional agents block (9-14) is unaffected by the gate

## Test Scenarios

- Given a PR that only changes `*.md` files, when `/soleur:review` runs, then 4 agents spawn
- Given a PR that changes `apps/web-platform/src/**/*.ts`, when review runs, then all 8 agents spawn
- Given a PR with both `.md` and `.ts` changes, when review runs, then all 8 agents spawn (any source file = full set)
- Given a PR with only `.md` changes but "deep review" in the PR body, when review runs, then all 8 agents spawn

## Domain Review

**Domains relevant:** Engineering, Product, Finance, Marketing (carried forward from brainstorm 2026-04-13)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Reducing fan-out is the right plugin-level lever. Binary gate is the simplest effective approach.

### Product (CPO)

**Status:** reviewed
**Assessment:** No user-facing impact. Invisible infrastructure optimization.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Review pipeline is the highest-impact target. 50% reduction in agent spawning for non-code PRs.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Infrastructure, not a marketing moment. Ship quietly.

## Deferred Items

| Item | Rationale | Tracking |
|---|---|---|
| Granular category table (6 categories) | Reviewers unanimously called this overengineered. Binary gate captures 80%+ of value. | Revisit if binary gate proves insufficient |
| Brainstorm file-path signals | Existing semantic gating is already effective (plan's own assessment) | File issue if domain mis-routing observed |
| Work skill tier capping | No data behind the 50-line heuristic. Existing 3-task threshold works. | File issue if fan-out waste is observed |
| Agent merging (git-history + pattern-recognition) | Structural fan-out reduction. Out of scope. | Track as separate optimization |

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-13-token-optimization-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-advisor-strategy/spec.md`
- Ship skill gating pattern: `plugins/soleur/skills/ship/SKILL.md:285-349`
- Review skill always-on agents: `plugins/soleur/skills/review/SKILL.md:63-78`
- Review skill conditional agents: `plugins/soleur/skills/review/SKILL.md:80-151`
- Learning: LLM judgment for gating: `knowledge-base/project/learnings/2026-03-03-tier-0-lifecycle-parallelism-design.md`
- Learning: merge before splitting: `knowledge-base/project/learnings/2026-03-05-producer-consumer-merge-for-subagent-limits.md`
- Issue: #2032 (context-aware agent gating)
- Issue: #2030 (advisor strategy, deferred)
