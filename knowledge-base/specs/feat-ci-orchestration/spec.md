# Feature: Multi-Agent CI Orchestration

## Problem Statement

The competitive-intelligence agent produces a standalone report. Downstream artifacts -- battlecards (deal-architect), comparison pages (programmatic-seo-specialist), pricing matrices (pricing-strategist), content gap analysis (growth-strategist) -- are not automatically refreshed when the competitive landscape changes. This requires manual invocation of each specialist separately.

## Goals

- Automate cascading updates from CI report to 4 downstream specialist agents
- Ensure each specialist run is independent (one failing doesn't block others)
- Produce a consolidated cascade summary appended to the CI report
- Follow established fan-out patterns (Task tool parallel dispatch)

## Non-Goals

- Normalized data contract between CI agent and specialists (deferred; YAGNI)
- Smart detection of which specialists need to run (always-run for v1)
- Cross-specialist consistency auditing (add if inconsistency emerges)
- Interactive cascade mode (no second opt-in; always automatic)
- New agents or skills (orchestration added to existing CI agent body)

## Functional Requirements

### FR1: Cascade Phase

After writing the base CI report to `knowledge-base/overview/competitive-intelligence.md`, the competitive-intelligence agent enters a Phase 2: Cascade that spawns all 4 specialist agents in parallel via Task tool.

### FR2: Independent Specialist Execution

Each specialist runs in isolation. A failure in one does not prevent others from completing. The CI agent handles partial failures gracefully (logs failure, continues collecting results).

### FR3: Consolidated Cascade Results

After all specialists complete (or fail), the CI agent appends a `## Cascade Results` section to `competitive-intelligence.md` summarizing: which specialists ran, what each produced/updated, any failures, and what needs manual attention.

### FR4: File-Based Data Flow

Each specialist reads the CI report from disk (`knowledge-base/overview/competitive-intelligence.md`). No prompt injection of report contents. Each specialist writes to its own output location.

## Technical Requirements

### TR1: Fan-Out Pattern Compliance

Follow the established fan-out pattern from `/soleur:work`: max 5 parallel agents, lead-coordinated results, subagents do NOT commit. The CI agent collects all output before any commits.

### TR2: Cross-Domain Acknowledgment

The CI agent (Product domain) explicitly documents that it spawns Marketing agents (growth-strategist, pricing-strategist, programmatic-seo-specialist) and a Sales agent (deal-architect), crossing domain boundaries for speed and directness.

### TR3: Autonomous Specialist Mode

Each specialist must run autonomously when invoked as a Task subagent (no AskUserQuestion, no interactive gates). If a specialist currently has interactive patterns, the Task prompt must instruct it to operate in non-interactive mode.

### TR4: Agent Description Token Budget

No new agents are created. The competitive-intelligence agent description (YAML frontmatter) stays unchanged. Phase 2 instructions go in the agent body only.
