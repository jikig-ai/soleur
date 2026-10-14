# Claude Design vs Pencil — Tooling Evaluation

**Date:** 2026-04-21
**Status:** Complete
**Branch:** feat-claude-design-evaluation
**Trigger:** Anthropic announced Claude Design (<https://www.anthropic.com/news/claude-design-anthropic-labs>). Founder asked whether to replace the Pencil MCP integration.

## What We're Building

Not building anything. This is a tooling-evaluation brainstorm to decide whether
Anthropic's new Claude Design product should replace our current Pencil MCP
integration for agent-driven design work.

**Decision:** Keep Pencil. Claude Design is not a viable replacement today.
Track as a re-evaluation trigger for when Anthropic ships an API or MCP surface.

## Why This Approach

### The two products solve different problems

Claude Design (research preview, announced 2026-04-21) is a **collaborative
web app** at `claude.ai/design` where humans work with Claude Opus 4.7 to
produce visual assets — slides, one-pagers, prototypes. It exports to Canva,
PDF, PPTX, HTML. It hands off to Claude Code as a "bundle" for implementation.

Pencil (integrated via `plugins/soleur/skills/pencil-setup/`) is an **MCP
server** exposing 18+ typed tools (`mcp__pencil__batch_design`,
`open_document`, `save`, `export_nodes`, `get_screenshot`,
`get_style_guide`, etc.) that our `ux-design-lead` agent calls
programmatically to produce `.pen` source files committed to git.

Different primitives for different users: Claude Design for humans in a
browser, Pencil for agents in a pipeline.

### Claude Design blockers for our use case

1. **No MCP / no CLI / no API.** The announcement describes web-only access
   and a Claude Code "bundle handoff" — there is no programmatic surface an
   agent can call to create, mutate, or save a design. Every Soleur workflow
   that touches design (`ux-design-lead` agent, `/soleur:frontend-design`,
   `/soleur:ux-audit`, `/soleur:feature-video`, Product/UX Gate in
   `wg-for-user-facing-pages-with-a-product-ux`) depends on this surface.
2. **Not headless.** It's a collaborative GUI. Driving it via Playwright MCP
   would reintroduce the fragility we eliminated when we moved Pencil to
   Tier 0 headless CLI in `feat-pencil-headless-cli` (2026-03-24). Session
   auth, DOM drift, no typed tool schemas.
3. **No committable source format.** Exports are PDF/PPTX/HTML/Canva. We
   commit `.pen` sources to `knowledge-base/project/specs/feat-*/designs/`
   so designs diff cleanly and survive founder review. Rasterised or
   binary-compressed exports break that loop.
4. **Access model.** Pro/Max/Team/Enterprise only, research preview,
   disabled by default for Enterprise. Our CI/CD agents run without
   interactive auth.

### Linux + headless answer to the founder's question

- **Linux support:** Yes via browser. Claude Design is web-based; any
  Chromium on Linux renders it. But "works in a browser" is not the same as
  "works for our agents."
- **Headless support:** No. There is no documented CLI, API, or MCP server
  for Claude Design as of 2026-04-21. Headless operation would require
  Playwright-driving `claude.ai/design`, which trades typed MCP tools for
  DOM automation.

### Why not a hybrid workflow now

A hybrid (Claude Design for founder-led visual ideation, Pencil for
agent-driven UX work) is technically workable but introduces a second
design-source-of-truth with no export path into `.pen`. The handoff "bundle"
Anthropic describes is designed for Claude Code implementation, not Pencil
re-import. Until there's a documented bridge, maintaining two parallel
design pipelines adds more overhead than it removes. Revisit when Anthropic
ships an API/MCP or a `.pen`-compatible export.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Replace Pencil with Claude Design? | No | No MCP/API/CLI; GUI-only; breaks every agent-driven design workflow |
| Add Claude Design as a parallel tool? | No (yet) | No integration bridge; doubles maintenance surface |
| Track for re-evaluation? | Yes | Anthropic's track record suggests API likely within 3-6 months |
| Re-evaluation triggers | (a) Claude Design MCP server announced, (b) Claude Design CLI/API announced, (c) `.pen`-compatible export or import shipped, (d) Founder workflow demand for human-led visual ideation | Any single trigger warrants a fresh brainstorm |

## Open Questions

1. Does Anthropic have a public roadmap signal for a Claude Design API?
   (Not in the announcement; watch changelog + Anthropic Labs blog.)
2. Should we use Claude Design ad-hoc for non-agent artefacts (investor
   slides, brand decks) where the committable-source requirement doesn't
   apply? — Low-priority; founder can decide per-artefact without any
   Soleur integration.

## Non-Goals

- Building a Claude Design ↔ Pencil bridge.
- Writing a Playwright MCP adapter for `claude.ai/design`.
- Removing, deprecating, or refactoring any existing Pencil integration.

## Next Actions

1. Tracking issue filed: #2699 (milestone: Post-MVP / Later).
2. No code changes. No spec needed beyond this brainstorm.
