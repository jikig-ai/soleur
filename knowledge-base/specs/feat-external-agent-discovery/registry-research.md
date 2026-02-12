# Registry Research: External Agent/Skill Discovery APIs

**Date:** 2026-02-12
**Issue:** #55
**Purpose:** Determine which registries expose usable APIs for programmatic agent/skill discovery

## Executive Summary

The ecosystem has matured significantly since the original #46 brainstorm. Nine registries were evaluated. **SkillsMP is the only registry with a documented, public REST API with semantic search.** Anthropic's official repos provide reliable structured data via GitHub API. tessl.io has no public API (auth-walled CLI only). skills.sh has no API (CLI only).

**Recommendation:** If/when demand emerges, start with SkillsMP's REST API (best documented, semantic search, existing MCP servers) and Anthropic's GitHub repos (official, structured, no auth). tessl.io and skills.sh require CLI subprocess invocation with significant friction.

## Registry Evaluations

### Tier 1: Viable for Programmatic Discovery

#### SkillsMP (skillsmp.com)

| Property | Value |
|----------|-------|
| Type | Website + REST API + MCP server |
| Scale | 160,000+ skills |
| API | `GET /api/v1/skills/search?q={query}` (keyword), `POST /api/v1/skills/ai-search` (semantic) |
| Auth | API key required (Bearer token: `sk_live_...`) |
| Format | JSON with pagination (`page`, `limit` up to 100, `sort_by`: stars/recent) |
| MCP servers | 2 community implementations: [anilcancakir/skillsmp-mcp-server](https://github.com/anilcancakir/skillsmp-mcp-server) (5 tools), [boyonglin/skillsmp-mcp-lite](https://github.com/boyonglin/skillsmp-mcp-lite) (3 tools) |
| MCP tools | `search_skills`, `ai_search_skills`, `read_skill`, `list_repo_skills`, `install_skill` |
| Verdict | **Best API in ecosystem.** REST + semantic search + existing MCP servers. API key is the only friction. |

#### Anthropic Skills Repo (github.com/anthropics/skills)

| Property | Value |
|----------|-------|
| Type | GitHub repository (also a Claude Code plugin marketplace) |
| Scale | ~50 curated skills |
| API | GitHub Contents/Search API |
| Auth | None required (60 req/hr), optional token (5000 req/hr) |
| Format | YAML frontmatter + Markdown (SKILL.md files), JSON (marketplace.json) |
| Verdict | **Official, reliable, small.** Good for "recommended" skills. Not large enough for general discovery. |

#### Anthropic Official Plugins (github.com/anthropics/claude-plugins-official)

| Property | Value |
|----------|-------|
| Type | GitHub repository (curated plugin marketplace) |
| Scale | 50+ plugins (containing skills, commands, agents, MCP servers) |
| API | GitHub API, static `marketplace.json` fetchable via raw URL |
| Auth | None required |
| Format | JSON (marketplace.json with schema), individual plugin.json manifests |
| Verdict | **Official plugin directory.** Structured JSON index. Good complement to skills repo. |

### Tier 2: Usable with Friction

#### tessl.io

| Property | Value |
|----------|-------|
| Type | Website + CLI + MCP server (stdio only) |
| Scale | Unknown (registry at tessl.io/registry) |
| API | **No public REST API.** No HTTP MCP endpoint. |
| CLI | `tessl skill search [query]` via `npm i -g @tessl/cli` (v0.62.1) |
| MCP | stdio-only server via `tessl mcp start` -- 6 tools including `search` |
| Auth | **Required for all paths.** WorkOS browser-based login. No API key mechanism. |
| Format | CLI output format undocumented. MCP returns structured data via protocol. |
| Registry metadata | Name, description, version, rating (0-100%), install command, status, last updated |
| Verdict | **Auth wall blocks automated use.** No headless/non-interactive path. Closed-source CLI. Would need user to pre-authenticate. |

#### skills.sh (Vercel)

| Property | Value |
|----------|-------|
| Type | Website + CLI (`npx skills`) |
| Scale | 55,000+ skills |
| API | **No REST API.** CLI only: `npx skills find [query]` |
| Auth | None required |
| Format | Text output (no `--json` flag documented) |
| Source | Open source: [vercel-labs/skills](https://github.com/vercel-labs/skills) |
| Verdict | **Large index, no API.** CLI subprocess invocation is possible but fragile (text parsing). Open source means internal API could be reverse-engineered. |

#### ClaudePluginHub (claudepluginhub.com)

| Property | Value |
|----------|-------|
| Type | Website + per-plugin JSON API |
| Scale | 11,050 plugins / 36,410 skills |
| API | `GET /api/plugins/[id]/marketplace.json` (per-plugin, not bulk search) |
| Auth | None |
| Format | JSON (marketplace.json) |
| Verdict | **No bulk search API.** Useful for enriching results from other registries. Auto-scans GitHub every 30 minutes. |

#### claude-plugins.dev

| Property | Value |
|----------|-------|
| Type | Website + CLI (`skills-installer search`) |
| Scale | 63,000+ skills |
| API | CLI search only, no REST API |
| Auth | None |
| Verdict | **CLI only, no API.** Runs on Val Town backend. |

#### Skills Directory (skillsdirectory.com)

| Property | Value |
|----------|-------|
| Type | Website + CLI (`openskills`) |
| Scale | 36,000+ skills |
| API | Partially documented "Registry API" (endpoints not confirmed) |
| Auth | Unknown |
| Verdict | **Unconfirmed API.** URL-based search exists but REST endpoints not verified. |

### Tier 3: Not Viable

#### MCP Market (mcpmarket.com)

| Property | Value |
|----------|-------|
| Type | Website (editorial directory) |
| API | None found |
| Verdict | **No API.** Aggregates from other registries. Website scraping only. |

#### awesome-claude-skills (GitHub)

| Property | Value |
|----------|-------|
| Type | Curated markdown list |
| API | GitHub API for README |
| Verdict | **Not structured data.** Useful as human curation signal only. |

## Integration Path Comparison

| Path | Registry | Effort | Auth | Reliability | Recommendation |
|------|----------|--------|------|-------------|----------------|
| REST API | SkillsMP | Low | API key | High (documented API) | **Primary** |
| GitHub API | Anthropic repos | Low | Optional | High (official) | **Secondary** |
| MCP server | SkillsMP (community) | Medium | API key | Medium (community-maintained) | Alternative to REST |
| CLI subprocess | tessl.io | Medium | Browser login | Low (auth wall, closed source) | Defer |
| CLI subprocess | skills.sh | Medium | None | Medium (text parsing) | Defer |
| CLI subprocess | claude-plugins.dev | Medium | None | Medium (text parsing) | Defer |

## Key Findings

1. **SkillsMP is the clear winner** for programmatic discovery. Documented REST API, semantic search, pagination, 160K+ skills, existing MCP server implementations to reference. API key is the only barrier.

2. **Anthropic's official repos** are the most reliable secondary source. Structured JSON, no auth needed, official curation. Small scale but high quality.

3. **tessl.io is harder than expected.** No public API, auth-walled CLI, closed-source binary. The MCP server is stdio-only (not HTTP). Automated/headless integration is blocked by the WorkOS browser login requirement.

4. **skills.sh has no API** despite being the second-largest index (55K skills). Open source CLI could be reverse-engineered, but no documented programmatic interface exists.

5. **The ecosystem is fragmented.** Nine registries were found, but only one (SkillsMP) has a real API. Most are CLIs or websites without programmatic access.

6. **Quality signals vary.** tessl.io has percentage-based evaluation scores. SkillsMP has star counts. Anthropic's repos are curated. No universal quality metric exists.

## Recommendation

**Park implementation.** The reviewers were right -- no user demand exists. But the research reveals that viable APIs do exist (SkillsMP, GitHub) if/when demand materializes.

When demand arrives, the minimal integration path is:
1. SkillsMP REST API for broad discovery (requires API key)
2. Anthropic GitHub repos for curated/official skills (no auth)
3. Skip tessl.io and skills.sh until they expose public APIs

This research should be re-evaluated in 3-6 months as the ecosystem is evolving rapidly.

## Sources

- [tessl.io docs](https://docs.tessl.io) | [tessl.io registry](https://tessl.io/registry) | [MCP tools reference](https://docs.tessl.io/reference/mcp-tools)
- [skills.sh](https://skills.sh/) | [skills.sh docs](https://skills.sh/docs) | [vercel-labs/skills](https://github.com/vercel-labs/skills)
- [anthropics/skills](https://github.com/anthropics/skills) | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [SkillsMP](https://skillsmp.com/) | [SkillsMP API docs](https://skillsmp.com/docs/api) | [MCP server](https://github.com/anilcancakir/skillsmp-mcp-server)
- [MCP Market](https://mcpmarket.com/) | [Skills Directory](https://www.skillsdirectory.com/)
- [ClaudePluginHub](https://www.claudepluginhub.com/) | [claude-plugins.dev](https://claude-plugins.dev/)
- [awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills)
