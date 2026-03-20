---
title: "feat: MCP integration audit"
type: feat
date: 2026-02-18
---

# MCP Integration Audit

## Overview

Issue #116 asked: "can we investigate adding MCP Tools when it's possible for smoother integration?" This plan covers the audit findings and a minimal agent improvement.

The audit of all 28 agents and 37 skills found that **Cloudflare REST API is the only high-value MCP opportunity**. However, Cloudflare's official MCP servers don't cover DNS record management (the core gap), and they require OAuth which can't be auto-bundled in plugin.json. MCP integration is not viable for the current use cases.

## Problem Statement

PR #108 (GitHub Pages + Cloudflare wiring) exposed an "agent autonomy gap." The brainstorm identified Cloudflare as the top MCP candidate. But research shows:

1. Cloudflare's official MCP servers cover analytics/observability/builds -- NOT DNS record CRUD or zone settings management
2. All Cloudflare MCP servers require OAuth authentication -- plugin.json only supports unauthenticated HTTP
3. The `mcp-remote` bridge converts remote servers to stdio transport -- still can't be bundled
4. Building a custom MCP server would require hosting infrastructure for marginal benefit

## Non-Goals

- Building a custom Cloudflare MCP server
- Bundling Cloudflare's OAuth-required MCP servers
- Rewriting the infra-security agent (separate issue if needed)

## Proposed Solution

### Phase 1: Document Audit Findings

Commit the brainstorm and spec that document the full audit results. This is the primary deliverable for issue #116.

**Files:**
- `knowledge-base/brainstorms/2026-02-18-mcp-audit-brainstorm.md` (already written)
- `knowledge-base/specs/feat-mcp-audit/spec.md` (update with research findings)

### Phase 2: Minimal Agent Pointer

Add one line to the infra-security agent's GitHub Pages wire recipe referencing the detailed learning document. This avoids duplicating knowledge while ensuring the agent knows where to find the 10-step sequence.

**Change to `plugins/soleur/agents/engineering/infra/infra-security.md`:**

Add after the existing wire recipe's "Post-wiring verification" paragraph:

```markdown
**Detailed workflow:** For the complete 10-step autonomous sequence including cert provisioning, DNS proxy toggling, and common blockers, see `knowledge-base/learnings/integration-issues/2026-02-16-github-pages-cloudflare-wiring-workflow.md`.
```

## Acceptance Criteria

- [x] Audit findings documented in brainstorm and spec
- [x] Spec updated with Cloudflare MCP server research findings (OAuth limitation, no DNS CRUD)
- [x] Infra-security agent has one-line pointer to the GitHub Pages wiring learning
- [ ] Issue #116 closable with conclusion: MCP integration not viable for current use cases

## Version Bump

PATCH bump (agent prompt change touches plugin files). Files: `plugin.json`, `CHANGELOG.md`, `README.md`.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-18-mcp-audit-brainstorm.md`
- GitHub Pages learning: `knowledge-base/learnings/integration-issues/2026-02-16-github-pages-cloudflare-wiring-workflow.md`
- Cloudflare MCP servers: https://github.com/cloudflare/mcp-server-cloudflare
- Cloudflare MCP docs: https://developers.cloudflare.com/agents/model-context-protocol/mcp-servers-for-cloudflare/
- Issue: #116
- Related PR: #108
