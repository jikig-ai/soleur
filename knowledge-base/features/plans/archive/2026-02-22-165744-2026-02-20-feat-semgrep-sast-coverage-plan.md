---
title: Layer semgrep alongside security-sentinel for SAST coverage
type: feat
date: 2026-02-20
issue: "#163"
version-bump: MINOR
---

# Layer semgrep alongside security-sentinel for SAST coverage

## Overview

Add a semgrep-based SAST agent to the review workflow, running alongside security-sentinel as a conditional agent. security-sentinel handles LLM-driven architectural security review; semgrep handles deterministic rule-based static analysis (hardcoded secrets, SQL injection patterns, insecure function calls).

## Problem Statement

security-sentinel uses LLM heuristics (grep + reasoning) to find architectural security issues. It excels at business logic flaws, authorization patterns, and OWASP compliance reasoning. But it misses the low-level pattern-matching catches that dedicated SAST tools find -- known vulnerability signatures, CWE matches, taint analysis across call chains.

## Proposed Solution

Create a new conditional review agent (`semgrep-sast`) that wraps the `semgrep` CLI. Add it to the `<conditional_agents>` block in `commands/soleur/review.md`. The agent checks if semgrep is installed, runs it on changed files, and formats findings inline.

### Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Trigger condition | `which semgrep` succeeds | If installed, user wants it. No complex heuristics needed. |
| CLI not installed | Warn and skip | Constitution: degrade gracefully, don't abort. |
| Scan scope | Changed files only (PR diff) | Review is about PR changes, not full-repo audit. |
| Default rulesets | `semgrep --config=auto` | Auto-detects language, applies security rules. Zero config. |
| Output format | Agent formats findings like other review agents | Consistency. Agent is LLM that receives semgrep JSON and structures it. |
| Timeout | Bash default (2 min) | Sufficient for PR-scoped scans. |
| Error handling | Warn and continue | Semgrep failure must not block the review. |
| Documentation | Agent description + README table | Follows existing pattern. |
| Deduplication | No | Review synthesis already consolidates. Each agent reports independently. |
| OSS vs Cloud | OSS CLI only | No auth, no MCP server, no registry dependency. |
| Inline-only enforcement | Agent prompt instruction | Constitution requires no persisted security aggregation. |

### Non-Goals

- Installing semgrep automatically (user responsibility)
- Bundling semgrep as an MCP server in plugin.json
- Replacing security-sentinel
- Evaluating CodeRabbit (deferred -- issue #163 lists it as "consider")
- Custom semgrep rulesets shipped with the plugin

## Acceptance Criteria

- [x] `plugins/soleur/agents/engineering/review/semgrep-sast.md` created with proper frontmatter
- [x] `plugins/soleur/commands/soleur/review.md` updated with semgrep conditional agent block
- [x] Agent gracefully handles missing semgrep CLI (warns, continues)
- [x] Agent scans only changed files (not full repo)
- [x] Agent outputs findings inline (never writes to files)
- [x] README.md agent table includes semgrep-sast with role clarification
- [x] security-sentinel unchanged and still in always-run parallel list
- [x] Version bumped: plugin.json, CHANGELOG.md, README.md

## Test Scenarios

- Given semgrep is installed and PR has code changes, when `/soleur:review` runs, then semgrep-sast agent launches and reports findings inline
- Given semgrep is NOT installed, when `/soleur:review` runs, then a warning is logged and review continues without SAST
- Given semgrep finds zero issues, when agent completes, then it reports "0 findings" (not silent)
- Given semgrep CLI errors (bad config, crash), when agent runs, then it warns and review continues
- Given security-sentinel and semgrep both find an SQL injection, when review synthesizes, then both findings appear (no silent dedup)

## MVP

### 1. Create agent file

`plugins/soleur/agents/engineering/review/semgrep-sast.md`

```markdown
---
name: semgrep-sast
description: "Use this agent when you need deterministic static analysis..."
model: inherit
---

Agent prompt that:
1. Checks `which semgrep` -- if missing, return warning with install instructions
2. Gets list of changed files from git diff
3. Runs `semgrep --config=auto --json <files>`
4. Parses JSON output
5. Formats findings as structured report (severity, file, line, rule, description)
6. Returns findings inline -- never writes to files
```

### 2. Update review command

`plugins/soleur/commands/soleur/review.md`

Add to `<conditional_agents>` block after test-design-reviewer (agent #13):

```markdown
**If semgrep CLI is installed (`which semgrep` succeeds):**

14. Task semgrep-sast(PR content) - Deterministic SAST scanning for known vulnerability patterns

**When to run SAST agent:**
- `which semgrep` returns 0 (semgrep binary found in PATH)
- PR modifies source code files (not just markdown/config)

**What this agent checks:**
- `semgrep-sast`: Known vulnerability signatures (CWE patterns), hardcoded secrets,
  insecure function calls, taint analysis. Complements security-sentinel's architectural review.
```

### 3. Version bump

- `plugin.json`: 2.19.0 -> 2.20.0 (MINOR -- new agent)
- `CHANGELOG.md`: Added section with semgrep-sast
- `README.md`: Agent count 33 -> 34, add table row
- `plugin.json` description: Update agent count

## References

- security-sentinel: `plugins/soleur/agents/engineering/review/security-sentinel.md`
- Review command: `plugins/soleur/commands/soleur/review.md`
- Inline-only learning: `knowledge-base/learnings/2026-02-16-inline-only-output-for-security-agents.md`
- Landscape audit: `knowledge-base/learnings/2026-02-19-full-landscape-discovery-audit.md`
- Issue: #163
