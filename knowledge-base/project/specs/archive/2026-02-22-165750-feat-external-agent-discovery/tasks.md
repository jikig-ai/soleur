# Tasks: External Agent Discovery

**Plan:** `knowledge-base/plans/2026-02-12-feat-external-agent-discovery-plan.md`
**Branch:** `feat-external-agent-discovery`

## Research Spike (Complete)

### 1. Check tessl.io APIs

- [x] Search tessl.io documentation for MCP HTTP endpoints
- [x] Search for REST API documentation
- [x] Test CLI: `npm i -g @tessl/cli && tessl skill search "code review"` (documented, not installed -- auth wall)
- [x] Document findings with sample responses

### 2. Check skills.sh and related registries

- [x] Check skills.sh for API/MCP endpoints
- [x] Check Anthropic's skills repo (github.com/anthropics/skills) for structured data
- [x] Check SkillsMP (skillsmp.com) for API access
- [x] Check MCP Market (mcpmarket.com) for API access
- [x] Document findings with sample responses

### 3. Write research document

- [x] Create `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`
- [x] For each registry: API type, endpoint URLs, authentication requirements, response schema, sample response
- [x] Summary: which registries are viable, which access methods work
- [x] Recommendation: proceed with implementation or park the feature

### 4. Updated research (2026-02-18)

- [x] Investigate MCP transport constraints from #116 audit
- [x] Discover unauthenticated registry APIs (api.claude-plugins.dev, claudepluginhub.com)
- [x] Verify SkillsMP auth requirements (all endpoints 401 without Bearer token)
- [x] Document `.mcp.json` supports stdio (Playwright proves this)
- [x] Update registry-research.md with new findings

## Phase 1: Implementation

### 1.0 Phase 0 loader test (prerequisite)

- [x] Create test agent with extra frontmatter fields (`stack`, `source`, `registry`, `installed`, `verified`)
- [x] Place in `plugins/soleur/agents/community/test-loader.md`
- [x] Verify plugin loader discovers it as `soleur:community:test-loader`
- [x] If loader rejects extra fields: move provenance to markdown comment blocks
- [x] Delete test agent after verification

### 1.1 Add `stack` field to existing agents

- [x] Add `stack: rails` to `plugins/soleur/agents/engineering/review/dhh-rails-reviewer.md` frontmatter
- [x] Add `stack: rails` to `plugins/soleur/agents/engineering/review/kieran-rails-reviewer.md` frontmatter
- [x] Verify both agents still load correctly after adding `stack` field

### 1.2 Create discovery agent

- [x] Create `plugins/soleur/agents/engineering/discovery/agent-finder.md`
  - [x] YAML frontmatter: name, description, model (inherit)
  - [x] Example block with context/user/assistant/commentary (constitution requirement)
  - [x] Stack gap detection instructions (Grep for `stack:` field in agent files)
  - [x] Registry query instructions (Bash curl to 3 endpoints, parallel)
  - [x] JSON response parsing and trust tier filtering
  - [x] Deduplication across registries (name + publisher key)
  - [x] Approval flow using AskUserQuestion (max 5 suggestions, skip all option)
  - [x] Installation logic (Write to agents/community/ or skills/community-<name>/)
  - [x] Frontmatter validation before install (YAML parse, required fields, size, no path traversal)
  - [x] Provenance frontmatter template (name, description, model, stack, source, registry, installed, verified)
  - [x] Graceful degradation (timeout, parse errors, 401/403 as permanent, all-fail skip)

### 1.3 Create community directory

- [x] Create `plugins/soleur/agents/community/.gitkeep`

### 1.4 Integrate discovery into /plan

- [x] Read `plugins/soleur/commands/soleur/plan.md`
- [x] Add Phase 1.5 "Discovery Check" between Phase 1 (Local Research) and Phase 1.5b (External Research)
  - [x] Stack detection via file-signature heuristics (7 stack signatures)
  - [x] Gap checking via Grep for `stack:` frontmatter in all agent files
  - [x] Conditional spawn of agent-finder when gap detected
  - [x] Handle agent-finder results (installed count, skipped count)
  - [x] Graceful fallthrough if no gap or discovery fails

### 1.5 Version bump and docs

- [x] Bump version in `plugins/soleur/plugin.json` (MINOR -- new agent + new behavior)
- [x] Add CHANGELOG.md entry
- [x] Update README.md (agent count, mention community discovery)

### 1.6 Review and ship

- [ ] Run code review on unstaged changes
- [ ] Run `/soleur:compound` to capture learnings
- [ ] Stage all artifacts (brainstorm, spec, plan, tasks, registry-research, code)
- [ ] Commit, push, create PR referencing #55
