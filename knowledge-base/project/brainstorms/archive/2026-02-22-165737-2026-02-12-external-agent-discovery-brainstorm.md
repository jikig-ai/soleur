# External Agent Discovery via Registry Integration

**Date:** 2026-02-12
**Updated:** 2026-02-18
**Status:** Active
**Issue:** #55
**Prior work:** Archived brainstorm from #46 in `knowledge-base/brainstorms/archive/`

## What We're Building

A gap-triggered discovery system that detects when the current project uses a stack not covered by built-in agents/skills, queries external registries for matching community artifacts, and installs approved ones -- all integrated into the `/plan` command as a pre-planning step.

[Updated 2026-02-18] Scope expanded from agents-only to **skills + agents**. Trigger changed from "any command" to specifically `/plan` (gap-triggered, not every invocation). Security model upgraded from "user consent only" to **source-gated with configurable allowlist**.

## Why This Approach

**Pre-plan check with gap-triggered suggestions** was chosen over explicit commands or always-on contextual suggestions because:

- **Natural workflow integration** -- `/plan` already analyzes the codebase. Discovery happens before planning, so newly installed agents/skills can influence the plan.
- **Non-intrusive** -- Only fires when a genuine gap is detected. Silent when existing agents cover the project's stack.
- **Constitution-aligned** -- Does not run unless the user invokes `/plan`. Not unsolicited automation.

**Rejected alternatives:**
- **Explicit `/find-skill` command (pull-based):** Users forget it exists. Doesn't surface naturally in workflow.
- **Always-on contextual suggestions:** Too aggressive. Interrupts active work in `/review` or `/work`.
- **Separate `/discover` phase in lifecycle:** Adds ceremony. Most users would skip it.

## Key Decisions

1. **Trigger: Pre-plan gap detection** -- During `/plan`, before planning starts, detect the project stack. If no built-in agents/skills cover it, query registries. Present suggestions. Install approved ones. Then plan with enriched capabilities. [Updated 2026-02-18]

2. **Scope: Skills + agents** -- Both community skills (SKILL.md) and agents (.md) are discoverable and installable. [Updated 2026-02-18]

3. **Data sources: Three registries + Anthropic repos** -- Query `api.claude-plugins.dev` (3,915 skills, unauthenticated REST), `claudepluginhub.com` (12,171 plugins, unauthenticated REST), and Anthropic's official repos via raw.githubusercontent.com (~70 artifacts, static JSON). Merge and deduplicate results. [Updated 2026-02-18]

4. **Security: Source-gated with configurable allowlist** -- Default allowlist includes Anthropic repos + verified publishers on registries. Users can extend the allowlist with trusted GitHub orgs/repos in settings. Only artifacts from trusted sources are suggested. [Updated 2026-02-18]

5. **Installation target: Plugin community directories** -- Agents install to `plugins/soleur/agents/community/`. Skills install to `plugins/soleur/skills/community-<name>/` (flat, prefix-based) until the loader is updated to recurse skills subdirectories. Once loader recursion is implemented, migrate to `plugins/soleur/skills/community/<name>/`. [Updated 2026-02-18]

6. **Loader prerequisite: Skills recursion** -- The plugin loader currently only discovers `skills/<name>/SKILL.md` (flat). A prerequisite PR must enable recursion into skills subdirectories so `skills/community/<name>/SKILL.md` works. [Updated 2026-02-18]

7. **Caching: Per-project, one-time check** -- Store discovery results per project (e.g., in `.soleur/` or a local cache file). Only re-check when the project's detected stack changes or user explicitly refreshes.

8. **Graceful degradation** -- Network failures warn and continue with local agents only. Registries being down never blocks a workflow.

9. **Conflict prevention** -- Only suggest external agents/skills for genuinely missing capabilities. If a local artifact covers the same category, the external one is not surfaced.

10. **Provenance tracking** -- Installed community artifacts include frontmatter: `source:`, `installed:`, `registry:`, `verified:`. Clearly labeled in `/help` output.

11. **Updates: Skip for v1** -- No auto-update mechanism. If an artifact is outdated, user deletes and reinstalls.

## Open Questions

- **Allowlist format** -- Where does the user configure trusted sources? `plugin.json` settings? `.claude/settings.json`? A dedicated config file?
- **Deduplication logic** -- When the same skill appears on multiple registries, which version wins? Prefer Anthropic > verified > highest star count?
- **Loader recursion scope** -- Should the loader recurse skills globally (breaking change?) or only within an explicit `community/` directory?
- **Cache invalidation** -- How often should discovery re-check? On every `/plan`? Only when `package.json`/`Gemfile`/etc. changes?

## Research Findings [Updated 2026-02-18]

### Registry API Viability

| Registry | Auth | Scale | API | Viable |
|----------|------|-------|-----|--------|
| api.claude-plugins.dev | None | 1,304 plugins / 3,915 skills | REST with search | YES |
| claudepluginhub.com | None | 12,171 plugins | REST with search | YES |
| Anthropic repos (raw GH) | None | ~70 artifacts | Static JSON | YES (catalog) |
| SkillsMP | API key required | 160K+ skills | REST + MCP | NO (auth wall) |
| skills.sh | None (nominally) | 55K+ skills | Flaky (500 errors) | NO |
| tessl.io | Browser login required | Unknown | No public API | NO |
| skillsdirectory.com | API key required | 36K+ skills | REST | NO |

### MCP Transport Findings

- `plugin.json` `mcpServers` supports HTTP only (no auth headers field)
- `.mcp.json` at plugin root supports BOTH stdio and HTTP (with headers + env var interpolation)
- Proven by Playwright (stdio), GitHub (HTTP with auth), Supabase (HTTP without auth)
- SkillsMP has a community MCP server supporting HTTP transport, but still needs API key server-side

### Integration Patterns Available

1. **Runtime MCP from skill** -- Already working (Context7 in deepen-plan)
2. **WebFetch from skill** -- Works for unauthenticated APIs only
3. **Bash CLI** -- `npx skills find <query>` works, no auth needed
4. **Static bundled index** -- Highest reliability, zero friction, goes stale
5. **User-configured MCP** -- For authenticated services, one-time setup

### Recommended Architecture: Layered

- Layer 1: Static bundled index (always available, zero friction)
- Layer 2: Bash CLI fallback (`npx skills find`) for live search
- Layer 3: Plugin-bundled MCP for unauthenticated registries
- Layer 4: User-configured MCP for authenticated services (opt-in)
