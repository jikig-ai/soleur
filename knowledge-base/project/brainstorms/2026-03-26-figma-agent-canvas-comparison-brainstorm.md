# Figma Agent Canvas vs Pencil.dev Headless — Comparison & Strategy

**Date:** 2026-03-26
**Status:** Complete
**Participants:** Founder, CPO, CTO (pending)

## Context

On March 24, 2026, Figma announced that their canvas is open to AI agents via a new MCP server. This gives coding agents (Claude Code, Cursor, Codex, Copilot, etc.) direct write access to Figma design files — creating components, applying variables, building with design systems. They also introduced "skills" — markdown files that teach agents how to behave on the canvas.

Soleur implemented equivalent capability using Pencil.dev's headless CLI via a custom MCP adapter (shipped March 24-25, 2026). This brainstorm investigates the overlap, differences, and strategic implications.

## What We're Building

A multi-backend design abstraction using a **thin skills layer** pattern:

- Two design skills (`pencil-design` and `figma-design`) encapsulating tool-specific MCP instructions
- The `ux-design-lead` agent detects available MCP tool namespaces and imports the appropriate skill
- Pencil remains the default for local/headless/CI scenarios; Figma is the option for teams already in the Figma ecosystem
- **Deferred to Phase 3** (roadmap item 3.4: API + MCP service integrations)

## Why This Approach

### Figma's Offering vs Ours — Not Equivalent, But Adjacent

| Dimension | Figma MCP (`use_figma`) | Soleur Pencil.dev Integration |
|-----------|------------------------|-------------------------------|
| Architecture | Remote MCP server (cloud-hosted, `mcp.figma.com/mcp`) | Custom MCP adapter over local REPL (stdio) |
| Tool surface | ~16 tools, single `use_figma` for writes (Figma routes internally) | 14+ granular tools (`batch_design`, `get_screenshot`, `snapshot_layout`, etc.) |
| Design model | Cloud-collaborative, design-system-first, team-oriented | Local-first, headless (no GUI required), solo-operator-oriented |
| Skills/Instructions | Markdown files teaching agents canvas behavior | Equivalent: ux-design-lead agent with brand-guide integration |
| Ecosystem | Massive (millions of users, design systems, plugins, Dev Mode) | Niche (Pencil.dev is early-stage) |
| Cost | Free during beta, then usage-based paid | Free (Pencil Desktop + CLI) |
| Offline/local | No — requires Figma cloud or desktop app | Yes — .pen files are local, git-trackable |
| Headless | Remote mode needs no local app but requires cloud | True headless CLI, no GUI or cloud needed |
| Rate limits | Starter: 6 calls/month; Paid: REST API Tier 1 | None (local execution) |
| Auth | OAuth (Figma account) | PENCIL_CLI_KEY env var |

### Strategic Read

1. **Validation, not threat.** Figma entering this space proves the "agents write to design tools via MCP" pattern we already built. Market education happens for free.

2. **Ecosystem gravity matters, but not yet.** Figma has orders-of-magnitude more users. But Soleur has 0 beta users — premature optimization for Figma ecosystem access before we have users would be a distraction.

3. **Pencil's headless capability is a hard dependency.** Server-side agents (Phase 1 cloud platform) need a design tool that works without a GUI or cloud connection. Pencil's Tier 0 headless CLI satisfies this. Figma does not.

4. **Figma fits the existing architecture.** The roadmap (item 3.4) already calls MCP "a first-class integration tier." Figma publishing an MCP server means it gets near-zero-config integration by design.

### Positioning

"Agent-native design with any canvas. Unlimited local with Pencil, cloud-collaborative with Figma."

- Design-tool agnostic — Soleur works with YOUR design tool
- Lead with local-first, no-rate-limit, true-headless advantages
- Offer Figma as the cloud/team option for users already in that ecosystem
- Position WITH Figma, not against it

## Key Decisions

1. **Approach: Thin Skills Layer (Approach B)** — Create `pencil-design` and `figma-design` skills that encapsulate tool-specific instructions. The ux-design-lead agent imports the right skill based on which MCP tools are detected. Cleaner separation than conditional agent instructions. Mirrors Figma's own "skills" concept.

2. **Agent-level routing** — No new middleware or adapter abstraction. The ux-design-lead agent detects `mcp__pencil__*` or `mcp__figma__*` tool namespaces and loads the appropriate design skill. If both available, user config or one-time question decides.

3. **Defer to Phase 3** — Figma integration is not blocking Phase 1 work. Add to Phase 3 item 3.4 (API + MCP service integrations) alongside Cloudflare, Stripe, Plausible.

4. **Pencil stays default** — Pencil.dev's local-first, headless, no-rate-limit properties align with Soleur's architecture and current phase (solo founder, server-side agents). Figma becomes an additive option.

## Open Questions

- **Figma MCP stability:** The API is in beta. Tool surface may change. Defer investment until it stabilizes?
- **Figma .pen file format:** Can Figma export to a local-trackable format? Or are Figma files always cloud-only?
- **Design system bridge:** If a user has design tokens in Figma, can they be imported into Pencil (or vice versa)?
- **Figma rate limits post-beta:** Usage-based pricing could make high-frequency agent workflows expensive. What are the projected costs?
- **Pencil.dev's roadmap:** Does Pencil plan to add cloud/collaboration features that close the gap with Figma?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Figma's offering is not equivalent — different architecture (cloud vs. local), different trade-offs. Both give agents design tool access via MCP. Validates the pattern Soleur already implements. Figma MCP fits the existing 3-tier roadmap architecture. Recommends adding Figma as Option B alongside Pencil, deferred to Phase 3 item 3.4. Pencil retains unique headless capability needed for server-side agents. Position WITH Figma, not against it.

### Engineering (CTO)

**Summary:** Assessment pending at time of brainstorm capture. Key architectural questions flagged: MCP server architectures differ (remote HTTP vs. adapter-over-REPL), latency/reliability trade-offs need benchmarking, Figma could be added as an additional backend alongside Pencil with moderate effort, beta API dependency carries risk.

## Figma MCP Technical Reference

### Available Tools (from developer docs)

**Read/Context:**

- `get_design_context` — Extracts structured design data
- `get_variable_defs` — Variables, styles, colors, spacing, typography
- `get_screenshot` — Visual reference capture
- `get_metadata` — XML representation with layer IDs
- `search_design_system` — Find components, variables, styles across libraries

**Write/Generation:**

- `use_figma` — General-purpose create/edit (remote only)
- `generate_figma_design` — Convert web pages to Figma designs (remote only)
- `generate_diagram` — FigJam diagrams from Mermaid syntax
- `create_new_file` — Create blank Figma files
- `create_design_system_rules` — Generate instruction files

**Code Connect:**

- `get_code_connect_map` — Figma node ID to code component mappings
- `get_code_connect_suggestions` — Detect mapping opportunities
- `send_code_connect_mappings` — Finalize component mappings

**Utility:**

- `whoami` — Authenticated user identity

### Architecture

- Remote: `https://mcp.figma.com/mcp` (Streamable HTTP)
- Desktop: Local server (for org/enterprise)
- Auth: OAuth flow
- Rate limits: Starter/View/Collab = 6 calls/month; Dev/Full seats = REST API Tier 1

### Skills Framework

- Markdown files defining agent canvas behavior
- 9 launch skills: component libraries, design generation, accessibility specs, workflow coordination, design token integration
- Self-healing loops: agents compare, refine, update designs based on real structure
- Anyone can write skills — no plugin development or code required

## Sources

- [Figma Blog: Agents, Meet the Figma Canvas](https://www.figma.com/blog/the-figma-canvas-is-now-open-to-agents/)
- [Figma Help: Get Started with the Figma MCP Server](https://help.figma.com/hc/en-us/articles/39216419318551-Get-started-with-the-Figma-MCP-server)
- [Figma Developer Docs: MCP Server](https://developers.figma.com/docs/figma-mcp-server/)
- [Figma MCP Server Guide (GitHub)](https://github.com/figma/mcp-server-guide)
- [Muzli: What It Means for Designers](https://muz.li/blog/figma-just-opened-the-canvas-to-ai-agents-heres-what-it-means-for-designers/)
- [AlternativeTo: Figma Opens Direct AI Agent Design](https://alternativeto.net/news/2026/3/figma-opens-direct-ai-agent-design-on-canvas-introduces-skills-for-guided-workflows/)
