---
title: "Gemini CLI Portability Investigation"
issue: 1738
branch: gemini-cli-portability
date: 2026-04-07
---

# Tasks

## Phase 1: Capability Mapping

### 1.1 Install and Verify Gemini CLI

- [ ] Install Gemini CLI
- [ ] Verify authentication and subscription access
- [ ] Document installation prerequisites

### 1.2 Verify Critical Unknowns (gate for remaining Phase 1)

- [ ] Test `activate_skill` chaining depth (skill A -> skill B -> skill C)
- [ ] Test `.gemini/agents/` subdirectory nesting support
- [ ] Measure agent description token budget with 62 agents
- [ ] Test `{{args}}` interpolation in SKILL.md files
- [ ] Test MCP server compatibility (`.mcp.json` -> `mcpServers`)

### 1.3 Run Portability Scan (only if 1.2 passes)

- [ ] Adapt the Codex 10-primitive grep scan for Gemini CLI tool names
- [ ] Scan all 122 components (62 agents, 63 skills, 3 commands)
- [ ] Classify each: green / yellow / red using worst-primitive-wins logic

### 1.4 Document Gaps

- [ ] Create `inventory.md` with full component classification
- [ ] Document capability gaps

## Phase 2: Proof of Concept

### 2.1 Port CLO Domain (Green Agent)

- [ ] Create `.gemini/agents/clo.md` from `plugins/soleur/agents/legal/clo.md`
- [ ] Create `.gemini/agents/legal-document-generator.md`
- [ ] Create `.gemini/agents/legal-compliance-auditor.md`
- [ ] Test: invoke `@clo`, verify delegation to specialists

### 2.2 Port Compound Skill (Yellow Skill)

- [ ] Create `.gemini/skills/compound/SKILL.md` adapted for Gemini CLI tools
- [ ] Test: invoke compound, verify it writes a learning file

### 2.3 Port Go Command (Red Command)

- [ ] Create `.gemini/commands/go.toml` (or equivalent) for routing
- [ ] Test: invoke, verify downstream skill routing

### 2.4 MCP Compatibility

- [ ] Test Context7 MCP server on Gemini CLI
- [ ] Test Cloudflare MCP server on Gemini CLI
- [ ] Document any configuration changes needed

### 2.5 Document PoC Results

- [ ] Create `poc-results.md` with per-component parity ratings
- [ ] Document quality/capability differences

## Phase 3: Recommendation

### 3.1 Write Recommendation

- [ ] Create `recommendation.md` with go/no-go decision
- [ ] If go: create follow-up issue for abstraction assessment
