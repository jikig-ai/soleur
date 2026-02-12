# Tasks: External Agent Discovery

**Plan:** `knowledge-base/plans/2026-02-12-feat-external-agent-discovery-plan.md`
**Branch:** `feat-external-agent-discovery`

## Research Spike

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
