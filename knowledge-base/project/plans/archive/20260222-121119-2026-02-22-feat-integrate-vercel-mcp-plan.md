---
title: "feat: Integrate Vercel MCP"
type: feat
date: 2026-02-22
---

# feat: Integrate Vercel MCP

Add the Vercel MCP server to Soleur's plugin.json, giving all agents access to Vercel platform tools (deployments, projects, logs, domains, documentation). Same integration pattern as Context7.

## Acceptance Criteria

- [x] `plugin.json` contains `vercel` entry in `mcpServers` with `type: http` and `url: https://mcp.vercel.com`
- [x] `plugin.json` description updated: MCP Servers count 1 -> 2
- [x] README.md MCP Servers table has Vercel row; subsection documents tools
- [x] README.md Known Issues section includes Vercel MCP workaround (same pattern as Context7)
- [x] CHANGELOG.md has `### Added` entry under new version
- [x] MINOR version bump across plugin.json, CHANGELOG.md, README.md, root README badge, bug_report.yml (verified main at 2.31.6, bumped to 2.32.0)
- [ ] Post-implementation: call one authenticated Vercel MCP tool to verify OAuth flow works

## Test Scenarios

- Given plugin.json has vercel MCP entry, when Claude Code loads the plugin, then `mcp__vercel__*` tools appear in the tool list
- Given a non-Vercel user, when an agent calls `search_documentation`, then it works without OAuth
- Given the README MCP Servers section, when a user reads it, then they can find Vercel MCP capabilities and manual setup instructions

## Context

- **Issue:** #258 | **Brainstorm:** `knowledge-base/brainstorms/2026-02-22-vercel-mcp-brainstorm.md` | **Spec:** `knowledge-base/specs/feat-vercel-mcp/spec.md`
- **Prior art:** MCP audit #116 ([learning](knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md)) -- header auth can't bundle, but Vercel uses OAuth (Claude Code native)

## MVP

### plugins/soleur/.claude-plugin/plugin.json

Add `vercel` entry to `mcpServers`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    },
    "vercel": {
      "type": "http",
      "url": "https://mcp.vercel.com"
    }
  }
}
```

Update `description` field: change "1" MCP server reference to "2".

### plugins/soleur/README.md

**MCP Servers table** -- add Vercel row:

```markdown
| Server | Description |
|--------|-------------|
| `context7` | Framework documentation lookup via Context7 |
| `vercel` | Vercel platform access (deployments, projects, logs, domains) via OAuth |
```

**Vercel subsection** -- add after Context7 subsection:

```markdown
### Vercel

**Tools provided:**

- `search_documentation` - Search Vercel and Next.js documentation (no auth required)
- `list_teams`, `list_projects`, `get_project` - Project management
- `list_deployments`, `get_deployment`, `get_deployment_build_logs`, `get_runtime_logs` - Deployment monitoring
- `check_domain_availability_and_price`, `buy_domain` - Domain management
- `get_access_to_vercel_url`, `web_fetch_vercel_url` - URL access
- `use_vercel_cli`, `deploy_to_vercel` - CLI and deployment

Requires OAuth authentication for most tools (Claude Code handles this automatically on first use). Documentation search works without authentication.
```

**Known Issues section** -- add Vercel MCP entry alongside Context7:

```markdown
### MCP Servers Not Auto-Loading

**Issue:** The bundled MCP servers (Context7, Vercel) may not load automatically when the plugin is installed.

**Workaround:** Manually add them to your project's `.claude/settings.json`:

{
  "mcpServers": {
    "context7": { ... },
    "vercel": {
      "type": "http",
      "url": "https://mcp.vercel.com"
    }
  }
}
```

**Component counts table** -- update MCP Servers count from 1 to 2.

### plugins/soleur/CHANGELOG.md

```markdown
## [2.32.0] - 2026-02-22

### Added

- Vercel MCP server integration -- full platform access (deployments, projects, logs, domains, documentation) via OAuth
```

## References

- [Vercel MCP docs](https://vercel.com/docs/agent-resources/vercel-mcp) | [Tools reference](https://vercel.com/docs/agent-resources/vercel-mcp/tools)
- Context7 pattern: `plugins/soleur/.claude-plugin/plugin.json` lines 21-26
