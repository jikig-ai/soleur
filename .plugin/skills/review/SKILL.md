---
name: review
description: "Perform exhaustive code reviews using multi-agent analysis, deep thinking, and structured severity assessment. Spawns parallel reviewer agents and creates GitHub issues for findings."
triggers:
- review
- code review
- review PR
- review changes
- review branch
---

# Code Review

Perform exhaustive code reviews using multi-agent analysis, deep thinking, and Git worktrees for deep local inspection.

**Process knowledge:** Read `.plugin/skills/review/references/` files for the GitHub issue creation flow and E2E testing procedures.

## Prerequisites

- Git repository with GitHub CLI (`gh`) installed and authenticated
- Clean main/master branch
- Proper permissions to create worktrees and access the repository

## Review Target

If the user has not provided a review target (PR number, URL, file path, or branch), ask: "What would you like me to review? Please provide a PR number, GitHub URL, file path, or leave empty for the current branch."

## Main Tasks

### 0. Setup

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

### 1. Determine Review Target and Setup (ALWAYS FIRST)

1. Determine review type: PR number (numeric), GitHub URL, file path (.md), or empty (current branch)
2. Check current git branch
3. If ALREADY on the target branch → proceed with analysis
4. If DIFFERENT branch → offer to use worktree for isolated review
5. Fetch PR metadata using `gh pr view --json` for title, body, files, linked issues
6. Set up language-specific analysis tools
7. Make sure you are on the branch being reviewed

### 2. Parallel Agent Review

Use the `delegate` tool to run ALL or most of these agents simultaneously:

```
spawn: ["git-history", "patterns", "architecture", "security", "performance", "data-integrity", "agent-native", "code-quality"]
delegate:
  git-history: "Analyze git history patterns for this PR: {PR content}"
  patterns: "Identify patterns and anti-patterns in this PR: {PR content}"
  architecture: "Review architecture decisions in this PR: {PR content}"
  security: "Scan for security vulnerabilities in this PR: {PR content}"
  performance: "Check for performance issues in this PR: {PR content}"
  data-integrity: "Review data integrity concerns in this PR: {PR content}"
  agent-native: "Verify new features are agent-accessible in this PR: {PR content}"
  code-quality: "Detect code smells and produce refactoring roadmap for this PR: {PR content}"
```

### 3. Conditional Agents (Run if applicable)

Check the PR files list and project structure to determine if these apply:

**If project is a Rails app (Gemfile AND config/routes.rb exist):**

Use `delegate` to spawn Rails review agents:

- `kieran-rails-reviewer` — Rails conventions and quality bar
- `dhh-rails-reviewer` — Rails philosophy and anti-patterns

**If PR contains database migrations (`db/migrate/*.rb`) or data backfills:**

- `data-migration-expert` — validates ID mappings, checks for swapped values
- `deployment-verification-agent` — creates Go/No-Go deployment checklist

**If PR contains test files:**

- `test-design-reviewer` — scores test quality against Farley's 8 properties

**If semgrep CLI is installed and PR modifies source code:**

- `semgrep-sast` — deterministic SAST scanning for known vulnerability patterns

### 4. Rate Limit Fallback

After all agents complete, check outputs:

- **If ALL agents returned empty or rate-limit errors:** Perform an inline review covering security, architecture, performance, and simplicity.
- **If ANY agent returned substantive output:** Proceed normally with available results.

### 5. Deep Dive Phases

For each phase, spend maximum cognitive effort. Think step by step. Question assumptions.

#### Stakeholder Perspective Analysis

Evaluate from each stakeholder's perspective:

1. **Developer** — How easy to understand and modify? Are APIs intuitive? Can I test this?
2. **Operations** — How to deploy safely? What metrics and logs are available?
3. **End User** — Is the feature intuitive? Are error messages helpful?
4. **Security Team** — What's the attack surface? Compliance requirements?
5. **Business** — What's the ROI? Legal/compliance risks?

#### Scenario Exploration

- Happy path: Normal operation with valid inputs
- Invalid inputs: Null, empty, malformed data
- Boundary conditions: Min/max values, empty collections
- Concurrent access: Race conditions, deadlocks
- Scale testing: 10x, 100x, 1000x normal load
- Network issues: Timeouts, partial failures
- Security attacks: Injection, overflow, DoS
- Cascading failures: Downstream service issues

### 6. Simplification Review

Use `delegate` to spawn the simplicity reviewer:

```
spawn: ["simplicity"]
delegate:
  simplicity: "Review this code for unnecessary complexity and simplification opportunities: {PR content}"
```

### 7. Findings Synthesis and GitHub Issue Creation

**ALL findings MUST be stored as GitHub issues via `gh issue create`.** Create issues immediately after synthesis — do NOT present findings for user approval first.

#### Step 1: Synthesize All Findings

- Collect findings from all agents
- Categorize by type: security, performance, architecture, quality
- Assign severity: CRITICAL (P1), IMPORTANT (P2), NICE-TO-HAVE (P3)
- Remove duplicates
- Estimate effort (Small/Medium/Large)

#### Step 2: Create GitHub Issues

Create issues for ALL findings immediately using `gh issue create` with `--body-file`.

**Read `.plugin/skills/review/references/review-todo-structure.md` now** for the complete GitHub issue creation flow: label prerequisite, issue body template, `--body-file` pattern, label/milestone selection, duplicate detection, error handling, and batch strategy.

#### Step 3: Summary Report

After creating all issues, present:

```markdown
## Code Review Complete

**Review Target:** PR #XXXX - [PR Title]
**Branch:** [branch-name]

### Findings Summary

- **Total Findings:** [X]
- **P1 CRITICAL:** [count] - BLOCKS MERGE
- **P2 IMPORTANT:** [count] - Should Fix
- **P3 NICE-TO-HAVE:** [count] - Enhancements

### Created GitHub Issues

**P1 - Critical (BLOCKS MERGE):**
- #NNN - review: {description}

**P2 - Important:**
- #NNN - review: {description}

**P3 - Nice-to-Have:**
- #NNN - review: {description}

### Review Agents Used
- [agent list]

### Next Steps
1. Address P1 findings (CRITICAL — must fix before merge)
2. View all: `gh issue list --label code-review`
```

### Severity Breakdown

**P1 (Critical — Blocks Merge):** Security vulnerabilities, data corruption risks, breaking changes, critical architectural issues.

**P2 (Important — Should Fix):** Performance issues, significant architectural concerns, major code quality problems.

**P3 (Nice-to-Have):** Minor improvements, code cleanup, optimization opportunities, documentation updates.

### 8. End-to-End Testing (Optional)

**Read `.plugin/skills/review/references/review-e2e-testing.md` now** for project type detection, testing offers, and subagent procedures for browser and Xcode testing.

### Sharp Edges

- Review agent suggestions that modify workflow `if` conditions or event filters must be smoke-tested against the full user journey before shipping — agents optimize locally and can break flows they don't fully model.
- Any **P1 (CRITICAL)** findings must be addressed before merging the PR.
