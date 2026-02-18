# Registry Research: External Agent/Skill Discovery APIs

**Date:** 2026-02-12
**Updated:** 2026-02-18
**Issue:** #55
**Purpose:** Determine which registries expose usable APIs for programmatic agent/skill discovery

## Executive Summary

The ecosystem has matured significantly since the original #46 brainstorm. Eleven registries were evaluated across two research rounds.

**Round 1 (2026-02-12):** Nine registries evaluated. SkillsMP identified as the best API but requires auth. Recommendation: park implementation.

**Round 2 (2026-02-18):** Two new unauthenticated registries discovered (`api.claude-plugins.dev`, `claudepluginhub.com`). MCP transport constraints from #116 audit confirmed SkillsMP can't be bundled without auth headers. `.mcp.json` supports stdio transport (Playwright proves this). Recommendation revised: viable unauthenticated paths exist.

**Current recommendation:** Use `api.claude-plugins.dev` and `claudepluginhub.com` as primary data sources (both unauthenticated REST), Anthropic repos as curated secondary source. SkillsMP available as opt-in via user-configured MCP.

## Registry Evaluations

### Tier 1: Viable for Unauthenticated Programmatic Discovery

#### api.claude-plugins.dev [Added 2026-02-18]

| Property | Value |
|----------|-------|
| Type | REST API (Val Town backend, Cloudflare/Render hosted) |
| Scale | 1,304 plugins / 3,915 skills |
| API | `GET /api/search?q={query}&limit={n}&offset={n}` (plugins), `GET /api/skills/search?q={query}&limit={n}&offset={n}` (skills) |
| Auth | **None required** |
| Rate limits | 1,000 requests per 30 seconds |
| Format | JSON with pagination (`total`, `limit`, `offset`) |
| Response fields | `id`, `name`, `namespace`, `gitUrl`, `description`, `version`, `author`, `keywords`, `skills`, `category`, `stars`, `verified`, `downloads`, `metadata` (homepage, repository, license, commands, agents, mcpServers), `createdAt`, `updatedAt` |
| Other endpoints | `/api/resolve/:owner/:marketplace/:plugin`, `/api/plugins/:owner/:marketplace/:plugin/stats`, `/api/skills/:owner/:repo/:skillName`, `/api/sitemap/plugins`, `/api/sitemap/skills` |
| Verdict | **Best unauthenticated API.** Rich metadata, generous rate limits, both plugin and skill search. |

#### claudepluginhub.com [Updated 2026-02-18]

| Property | Value |
|----------|-------|
| Type | Website + REST API (Vercel/Next.js) |
| Scale | 12,171 plugins / 3,066 marketplaces |
| API | `GET /api/plugins?q={query}&page={n}` (search+list), `GET /api/marketplaces` (marketplace list) |
| Auth | **None required** |
| Format | JSON with pagination (`currentPage`, `totalPages`, `total`). Default page size: 36. |
| Response fields | `id`, `slug`, `name`, `description`, `repositoryUrl`, `starCount`, `installCount`, `activeSparks`, `lastCommitDate`, `currentVersion` (nested: `version`, `commandCount`, `agentCount`, `skillCount`, `hasHooksDetail`, `hasMcpDetail`, `hasLspDetail`) |
| Auto-scan | Scans GitHub every 30 minutes |
| Verdict | **Largest unauthenticated dataset.** 12K+ plugins. Good metadata including component counts. |

#### Anthropic Skills Repo (github.com/anthropics/skills)

| Property | Value |
|----------|-------|
| Type | GitHub repository (also a Claude Code plugin marketplace) |
| Scale | ~50 curated skills |
| API | `raw.githubusercontent.com/anthropics/skills/main/.claude-plugin/marketplace.json` |
| Auth | None required |
| Format | JSON (marketplace.json: 2 bundles, 16 skills total) |
| Verdict | **Official, reliable, small.** Good for "recommended" skills. Not large enough for general discovery. |

#### Anthropic Official Plugins (github.com/anthropics/claude-plugins-official)

| Property | Value |
|----------|-------|
| Type | GitHub repository (curated plugin marketplace) |
| Scale | 53 plugins |
| API | `raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json` |
| Auth | None required |
| Format | JSON (marketplace.json: 53 plugins with full schema) |
| Verdict | **Official plugin directory.** Structured JSON index with `$schema` reference. Highest trust. |

### Tier 2: Viable with Auth (Opt-in Only)

#### SkillsMP (skillsmp.com)

| Property | Value |
|----------|-------|
| Type | Website + REST API + MCP server |
| Scale | 160,000+ skills |
| API | `GET /api/v1/skills/search?q={query}` (keyword), `POST /api/v1/skills/ai-search` (semantic) |
| Auth | **API key required** (Bearer token: `sk_live_...`). All endpoints return 401 without it. No free tier found. |
| MCP servers | 3 community implementations: [anilcancakir/skillsmp-mcp-server](https://github.com/anilcancakir/skillsmp-mcp-server) (HTTP+stdio, 5 tools), [boyonglin/skillsmp-mcp-lite](https://github.com/boyonglin/skillsmp-mcp-lite) (stdio only, 3 tools), [adarc8/skills-master-mcp](https://github.com/adarc8/skills-master-mcp) (HTTP+stdio, no API key -- uses proxy backend) |
| Bundling constraint | Cannot bundle in `plugin.json` `mcpServers` (no `headers` field for auth). Can bundle via `.mcp.json` as stdio with `${SKILLSMP_API_KEY}` env var. User must configure API key. |
| Verdict | **Best API overall but auth-walled.** Available as opt-in via user-configured MCP server. Not viable as default data source. [Updated 2026-02-18] |

### Tier 3: Usable with Significant Friction

#### tessl.io

| Property | Value |
|----------|-------|
| Type | Website + CLI + MCP server (stdio only) |
| Scale | Unknown (registry at tessl.io/registry) |
| API | **No public REST API.** No HTTP MCP endpoint. |
| Auth | **Required for all paths.** WorkOS browser-based login. No API key mechanism. |
| Verdict | **Auth wall blocks automated use.** No headless/non-interactive path. |

#### skills.sh (Vercel) [Updated 2026-02-18]

| Property | Value |
|----------|-------|
| Type | Website + CLI (`npx skills`) |
| Scale | 55,000+ skills |
| API | `GET /api/search?q={query}` exists but **unreliable** -- returns 500 errors and timeouts on most queries. |
| Auth | None required |
| CLI | `npx skills find [query]` works reliably. No `--json` flag. |
| Verdict | **API exists but flaky.** CLI works but requires text parsing. Not reliable enough for programmatic use. |

#### Skills Directory (skillsdirectory.com) [Updated 2026-02-18]

| Property | Value |
|----------|-------|
| Type | Website + CLI + REST API |
| Scale | 36,109+ skills |
| API | `GET /api/v1/skills`, `GET /api/v1/skills/search` (Pro+ only) |
| Auth | **API key required** (`sk_live_...`). Free tier: 100 req/day. Pro: $29/mo. |
| Verdict | **Auth-walled with paid tiers.** Not viable for bundled use. |

#### claude-plugins.dev [Updated 2026-02-18]

| Property | Value |
|----------|-------|
| Type | Website (Astro frontend) + REST API (Val Town backend) |
| Scale | 63,000+ skills (website claim), ~3,915 (API reality) |
| API | Same backend as `api.claude-plugins.dev` -- already covered in Tier 1 |
| Verdict | **Duplicate of api.claude-plugins.dev.** The website and CLI use the same Val Town API. |

### Tier 4: Not Viable

#### MCP Market (mcpmarket.com)

| Property | Value |
|----------|-------|
| Type | Website (editorial directory) |
| API | None found |
| Verdict | **No API.** Website scraping only. |

#### awesome-claude-skills (GitHub)

| Property | Value |
|----------|-------|
| Type | Curated markdown list |
| API | GitHub API for README |
| Verdict | **Not structured data.** Useful as human curation signal only. |

## Integration Path Comparison [Updated 2026-02-18]

| Path | Registry | Effort | Auth | Reliability | Recommendation |
|------|----------|--------|------|-------------|----------------|
| REST (WebFetch) | api.claude-plugins.dev | Low | None | High | **Primary** |
| REST (WebFetch) | claudepluginhub.com | Low | None | High | **Primary** |
| Static JSON (WebFetch) | Anthropic repos | Low | None | High | **Secondary (curated)** |
| User MCP (opt-in) | SkillsMP | Medium | User API key | High | **Opt-in enrichment** |
| CLI subprocess | skills.sh | Medium | None | Medium | Fallback only |
| REST (WebFetch) | skills.sh API | Low | None | **Low (500 errors)** | Not recommended |
| CLI subprocess | tessl.io | Medium | Browser login | Low | Not recommended |

## MCP Transport Constraints [Added 2026-02-18]

Findings from #116 audit (PR #125):

- `plugin.json` `mcpServers`: Only `"type": "http"` supported. **No `headers` field** for auth tokens.
- `.mcp.json` at plugin root: Supports stdio (`command`/`args`), HTTP (`type: "http"`, `url`, `headers`), and SSE. **Does support auth headers** via `${ENV_VAR}` interpolation.
- Proven patterns: Playwright uses stdio via `.mcp.json`. GitHub MCP uses HTTP with `Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}` via `.mcp.json`. Supabase uses unauthenticated HTTP.
- Implication: SkillsMP MCP server could be bundled via `.mcp.json` as stdio, but user must set `SKILLSMP_API_KEY` env var. Not viable as a default (silent failure if env var missing).

## Key Findings

1. **Two new unauthenticated registries are viable.** `api.claude-plugins.dev` (3,915 skills, generous rate limits) and `claudepluginhub.com` (12,171 plugins) both have working REST APIs with no auth. These were not found in the original research. [Added 2026-02-18]

2. **SkillsMP is auth-walled at every endpoint.** All endpoints return 401 without `Bearer sk_live_xxx`. No free tier. Demoted from "Primary" to "Opt-in enrichment." [Updated 2026-02-18]

3. **Anthropic's official repos** remain the most reliable curated source. Static JSON via raw.githubusercontent.com, 53 plugins + 16 skills.

4. **`.mcp.json` supports stdio transport.** The original constraint ("stdio can't be bundled") was wrong. Playwright proves stdio bundling works. This opens up SkillsMP as an opt-in via user-configured MCP. [Added 2026-02-18]

5. **skills.sh API exists but is unreliable.** Returns 500 errors on most queries. CLI works but requires text parsing. [Updated 2026-02-18]

6. **tessl.io remains blocked.** No public API, auth-walled CLI, closed-source binary. No change from original assessment.

7. **The ecosystem is less fragmented than it appeared.** `claude-plugins.dev` and its CLI share the same Val Town backend as `api.claude-plugins.dev`. Several registries are wrappers around the same data.

## Recommendation [Updated 2026-02-18]

**Viable paths now exist.** The original "park implementation" recommendation is revised. Two unauthenticated registries provide sufficient data for gap-triggered discovery.

Recommended data source stack:
1. `api.claude-plugins.dev` -- Primary search (skills + plugins, rich metadata, 1000 req/30s)
2. `claudepluginhub.com` -- Secondary/enrichment (largest dataset at 12K+ plugins)
3. Anthropic repos -- Curated catalog via raw GitHub (highest trust, no search)
4. SkillsMP -- Opt-in enrichment via user-configured MCP (best API but requires API key)

Implementation should still wait for user demand, but the technical blockers are resolved.

## Sources

- [tessl.io docs](https://docs.tessl.io) | [tessl.io registry](https://tessl.io/registry) | [MCP tools reference](https://docs.tessl.io/reference/mcp-tools)
- [skills.sh](https://skills.sh/) | [skills.sh docs](https://skills.sh/docs) | [vercel-labs/skills](https://github.com/vercel-labs/skills)
- [anthropics/skills](https://github.com/anthropics/skills) | [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [SkillsMP](https://skillsmp.com/) | [SkillsMP API docs](https://skillsmp.com/docs/api) | [MCP server](https://github.com/anilcancakir/skillsmp-mcp-server)
- [api.claude-plugins.dev](https://api.claude-plugins.dev) | [claude-plugins.dev](https://claude-plugins.dev/) | [ClaudePluginHub](https://www.claudepluginhub.com/)
- [Skills Directory](https://www.skillsdirectory.com/) | [MCP Market](https://mcpmarket.com/)
- [awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills)
- [skills-master-mcp](https://github.com/adarc8/skills-master-mcp) (SkillsMP proxy backend)
- MCP integration audit: #116, PR #125
