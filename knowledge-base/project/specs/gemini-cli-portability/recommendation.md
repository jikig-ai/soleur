---
title: "Gemini CLI Portability Recommendation"
date: 2026-04-07
issue: 1738
---

# Recommendation: Gemini CLI as Alternative Harness

## Decision: CONDITIONAL GO

Gemini CLI is a viable second harness for Soleur with significant caveats. Invest in a **minimal Gemini CLI extension** when platform risk materializes (Anthropic restricts Max plan access or API agent usage), not preemptively.

## Evidence Summary

| Metric | Codex CLI (2026-03-10) | Gemini CLI (2026-04-07) |
|---|---|---|
| GREEN (ports as-is) | 47.5% (58/122) | 54.3% (70/129) |
| YELLOW (needs adaptation) | 7.4% (9/122) | 45.0% (58/129) |
| RED (requires rewrite) | 43.4% (53/122) | 0.8% (1/129) |
| Blockers with no equivalent | 4 (Task, Skill, AskUser, Args) | 1 (hookSpecificOutput) |
| MCP compatibility | Partial (stdio only) | Full (stdio + HTTP) |
| Subagent support | None | Yes (single-level) |
| Skill chaining | None | Yes (context injection) |

Gemini CLI is architecturally 50x closer to Claude Code than Codex CLI was. The RED percentage dropped from 43.4% to 0.8%.

## Critical Constraint

**Single-level subagent nesting.** Gemini CLI subagents cannot spawn other subagents. This breaks Soleur's core pattern: domain leader (agent) → specialist (agent). The workaround — restructuring specialists as skills activated within the leader subagent — is functional but loses:

1. **Parallel execution** — Claude Code fans out to 7+ specialists simultaneously; Gemini CLI runs them sequentially
2. **Context isolation** — specialists share the leader's conversation context, risking cross-contamination
3. **Independent tool scoping** — specialists can't have different tool access than their parent

For 6 of 8 domain leaders (those with 2-3 specialists), this is acceptable. For the CMO (7+ specialists), it degrades significantly — a single CMO session would need to sequentially load marketing strategist, copywriter, SEO analyst, etc. instructions into the same context window.

## What to Build (when triggered)

### Minimum Viable Gemini Extension

A `gemini-extension.json` bundling:

1. **51 GREEN agents** as `.gemini/agents/*.md` — direct port, tool name changes only
2. **12 YELLOW agents** (domain leaders) — specialists restructured as skills
3. **18 GREEN skills** as `.gemini/skills/*/SKILL.md` — direct port
4. **MCP servers** — Context7, Cloudflare, Vercel, Playwright via `mcpServers`
5. **GEMINI.md** context file — adapted from CLAUDE.md/AGENTS.md
6. **Policy rules** — adapted from settings.json hooks

### What NOT to build

- An abstraction layer that compiles to both formats — premature and not justified by the current constraint (single-level nesting makes semantic parity impossible)
- The 44 YELLOW skills — most are workflow orchestrators (brainstorm, plan, work, review, ship) that require argument passing and skill chaining. Port only the 5 core pipeline skills and accept degraded functionality.
- A separate port maintained in parallel — maintenance cost exceeds risk mitigation value at current scale

## Trigger for Investment

Invest in the Gemini CLI extension when ANY of:

1. Anthropic restricts Max plan access for Claude Code CLI usage
2. Anthropic imposes API rate limits that make agent harness usage impractical
3. A competitor ships a multi-harness plugin system that Soleur needs to match
4. Gemini CLI adds multi-level subagent support (eliminates the critical constraint)

## Estimated Effort

| Scope | Effort | Outcome |
|---|---|---|
| GREEN agents only (51) | 1-2 days | Basic agent library, no workflows |
| GREEN agents + core skills (18) | 3-4 days | Agent library + simple skills |
| Full extension (agents + 5 core pipeline skills) | 1-2 weeks | Degraded but functional workflow pipeline |
| Dual-harness abstraction layer | 4+ weeks | Full parity — not recommended |

## Follow-up Issues

If proceeding to build:

1. Create issue: "feat: build Gemini CLI extension with GREEN agents and core skills"
2. Create issue: "feat: restructure domain leaders for single-level subagent constraint"
3. Monitor: google-gemini/gemini-cli for multi-level subagent support (would change the equation)

## References

- Portability inventory: `knowledge-base/project/specs/gemini-cli-portability/inventory.md`
- Critical unknowns verification: `knowledge-base/project/specs/gemini-cli-portability/critical-unknowns.md`
- PoC results: `knowledge-base/project/specs/gemini-cli-portability/poc-results.md`
- Codex portability inventory: `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
- Platform risk learning: `knowledge-base/project/learnings/2026-02-25-platform-risk-cowork-plugins.md`
