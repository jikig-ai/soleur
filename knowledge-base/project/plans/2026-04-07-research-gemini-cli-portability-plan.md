---
title: "research: investigate Gemini CLI as alternative harness for platform risk mitigation"
type: feat
date: 2026-04-07
issue: 1738
---

# Gemini CLI Portability Investigation

## Problem Statement

Anthropic has restricted Claude Code subscription access for OpenClaw users, creating material platform risk for Soleur. If similar restrictions expand, users on Max plans could lose access, making Soleur unusable without an API key. A prior Codex CLI portability scan (#513) found 43.4% of components non-portable due to 4 missing primitives. Gemini CLI has since emerged as architecturally closer to Claude Code, with equivalents for all 4 blocking primitives. This research validates whether Gemini CLI is a viable second harness.

## Prior Art

The Codex portability scan (`knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`) classified 122 components:

- **47.5% green** (58 -- portable as-is, mostly agents as prose)
- **7.4% yellow** (9 -- need adaptation)
- **43.4% red** (53 -- require rewrite, mostly skills with orchestration)
- **1.6% N/A** (2)

Top blockers: Task/subagent spawning (28 components), Skill tool chaining (17), AskUserQuestion (27), $ARGUMENTS interpolation (20).

Key insight from methodology learning: "The domain knowledge (agent prose, frameworks, reference docs) is portable; the wiring (tool calls, inter-skill chaining, hook protocols) is not."

## Primitive Mapping (Research Findings)

| Claude Code Primitive | Gemini CLI Equivalent | Parity |
|---|---|---|
| Agent tool (subagent spawning) | `.gemini/agents/*.md` with auto-delegation or `@agent` forcing | Partial -- single-level only, no subagent-to-subagent calls |
| Skill tool (skill chaining) | `activate_skill` + `.gemini/skills/*/SKILL.md` | Unknown -- depth of chaining unverified |
| AskUserQuestion | `ask_user` | Direct equivalent |
| TodoWrite / TaskCreate | `write_todos` | Equivalent for tracking, NOT for parallel subagent spawning |
| Read / Write / Edit | `read_file` / `write_file` / `replace` | Direct equivalents |
| Bash | `run_shell_command` | Direct equivalent |
| Glob / Grep | `glob` / `grep_search` | Direct equivalents |
| WebSearch / WebFetch | `google_web_search` / `web_fetch` | Direct equivalents |
| EnterPlanMode / ExitPlanMode | `enter_plan_mode` / `exit_plan_mode` | Direct equivalents |
| CLAUDE.md / AGENTS.md | GEMINI.md (project + user level) | Close match |
| settings.json hooks | `settings.json` hooks (10 lifecycle events) | Superset -- more granular |
| settings.json permissions | Policy Engine (.toml, 5-tier priority) | Superset -- more granular |
| plugin.json (manifest) | `gemini-extension.json` | Different format, same concept |
| MCP servers (.mcp.json) | `mcpServers` in extension manifest or agent frontmatter | Direct equivalent |
| $ARGUMENTS | `{{args}}` in commands; unclear in skills | Partial -- commands only? |
| save_memory (CC memory) | `save_memory` (writes to GEMINI.md) | Different target, similar concept |

## Critical Architectural Risk

**Subagent depth limitation (HIGH risk).** Gemini CLI subagents cannot call other subagents. Soleur has confirmed 3-level chains: skill (brainstorm/work/plan) -> domain leader (cmo, cpo) -> specialist (brand-architect, copywriter). The CMO alone delegates to 7+ specialists via Task. This is the core orchestration pattern for all 8 domain leaders.

**Mitigation options:**

1. **Flatten hierarchy** -- inline specialist instructions into leaders. Loses parallelism, bloats context.
2. **Simulate depth via skill chaining** -- leaders invoke specialist skills instead of agents. Fragile, depends on `activate_skill` depth.
3. **Accept reduced functionality** -- Gemini port runs a subset of capabilities (green + yellow components only).

## Acceptance Criteria

- [ ] Portability inventory for Gemini CLI (comparable to Codex inventory)
- [ ] At least 3 components ported and tested on Gemini CLI
- [ ] Written recommendation on whether to invest in dual-harness support

## Implementation Plan

### Phase 1: Capability Mapping (research-only)

#### 1.1 Install and Verify Gemini CLI

- [ ] Install Gemini CLI via npm (`npm install -g @google/gemini-cli` or official channel)
- [ ] Verify subscription access works (Gemini API key or Google account)
- [ ] Document installation prerequisites and auth method

#### 1.2 Empirically Verify Critical Unknowns (gate for remaining Phase 1)

These questions cannot be answered from documentation alone. If any fundamental constraint fails (skill chaining depth, agent nesting), skip the full portability scan -- the architecture is not viable.

- [ ] Does `activate_skill` support skill A invoking skill B invoking skill C? (skill chaining depth)
- [ ] Does `.gemini/agents/` support subdirectory nesting? (Soleur has `agents/marketing/`, `agents/engineering/design/`)
- [ ] What is the agent description token budget? (Soleur has 62 agents -- cumulative description load)
- [ ] Does `{{args}}` interpolation work in SKILL.md files or only in command TOML files?
- [ ] Can MCP servers from `.mcp.json` be used unmodified via `mcpServers` in extension manifest?

#### 1.3 Run Portability Scan (only if 1.2 passes)

Reuse the Codex scan methodology (`knowledge-base/project/learnings/2026-03-10-codex-portability-scan-methodology.md`):

- [ ] Adapt the 10-primitive grep scan for Gemini CLI's tool names
- [ ] Scan all 122 components against Gemini CLI primitives
- [ ] Classify each component: green (portable as-is), yellow (needs adaptation), red (requires rewrite)
- [ ] Use worst-primitive-wins logic per component

#### 1.4 Document Gaps

- [ ] Create `knowledge-base/project/specs/gemini-cli-portability/inventory.md` with full component classification
- [ ] Document: what Gemini CLI can do that Soleur requires, what it cannot

### Phase 2: Proof of Concept

#### 2.1 Select Representative Components

Port 3 components spanning the portability spectrum:

| Component | Type | Codex Status | Why Selected |
|---|---|---|---|
| CLO (legal domain leader) | Agent | Green | Smallest domain hierarchy (2 specialists). Tests subagent depth constraint. |
| `soleur:compound` | Skill (yellow) | Yellow | Uses AskUserQuestion, file I/O, git commands. Tests skill adaptation. |
| `soleur:go` | Command (red) | Red | Entry point routing via Skill tool. Tests skill chaining and argument passing. |

#### 2.2 Port Components

- [ ] Create `.gemini/agents/clo.md` from `plugins/soleur/agents/legal/clo.md`
- [ ] Create `.gemini/agents/legal-document-generator.md` and `legal-compliance-auditor.md`
- [ ] Create `.gemini/skills/compound/SKILL.md` from `plugins/soleur/skills/compound/SKILL.md`
- [ ] Create `.gemini/commands/go.toml` or equivalent from `plugins/soleur/commands/go/COMMAND.md`
- [ ] Adapt each to use Gemini CLI tool names (`read_file`, `ask_user`, etc.)

#### 2.3 Test End-to-End

- [ ] Test CLO assessment: invoke `@clo` and verify it delegates to legal specialists
- [ ] Test compound skill: invoke and verify it captures learnings to files
- [ ] Test go routing: invoke and verify it routes to correct downstream skill
- [ ] Document quality/capability differences vs Claude Code execution
- [ ] Verify whether MCP servers (Context7, Cloudflare, Vercel) work unmodified

#### 2.4 Document Results

- [ ] Create `knowledge-base/project/specs/gemini-cli-portability/poc-results.md`
- [ ] Include: what worked, what failed, what required workarounds
- [ ] Rate each ported component: full parity / partial parity / non-functional

### Phase 3: Recommendation

Based on Phase 1-2 findings, write the decision document:

- [ ] Create `knowledge-base/project/specs/gemini-cli-portability/recommendation.md`
- [ ] Include: go/no-go for Gemini CLI as viable second harness
- [ ] If go: create a follow-up issue for abstraction assessment (gated on Phase 2 success)

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rated subagent depth as HIGH risk -- Gemini CLI's single-level nesting breaks Soleur's 3-level domain-leader-to-specialist hierarchy. Recommended Option C (minimal PoC with CLO domain first) to validate flattening feasibility before committing to abstraction layer or separate ports. Component count (62 agents) and description token budget also flagged as unknowns requiring empirical verification.

## Test Scenarios

Research tasks do not have automated tests. Verification is empirical:

- Given Gemini CLI is installed, when running the portability scan, then all 122 components are classified
- Given the CLO agent is ported, when invoking `@clo`, then it delegates to legal-document-generator or legal-compliance-auditor
- Given the compound skill is ported, when invoking it after a code change, then it writes a learning file
- Given the go command is ported, when invoking it, then it routes to the correct downstream skill

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Full abstraction layer first | Single codebase, clean separation | High upfront cost, may not be feasible due to subagent depth constraint | Deferred -- validate feasibility first |
| Port all components at once | Complete parity immediately | Massive effort (122 components), premature if constraints block core patterns | Rejected -- PoC first |
| Defer entirely | Zero effort | Platform risk remains unmitigated, no data for future decisions | Rejected -- need data |
| Multi-runtime SDK (#1215 BYOM) | Model-agnostic, most flexible | Different scope -- BYOM is about model providers, not CLI harnesses | Orthogonal -- separate track |

## References

- Codex portability inventory: #513, `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
- Codex scan methodology: `knowledge-base/project/learnings/2026-03-10-codex-portability-scan-methodology.md`
- Platform risk learning: `knowledge-base/project/learnings/2026-02-25-platform-risk-cowork-plugins.md`
- BYOM guide: #1215
- Gemini CLI repo: [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)
- Gemini CLI extensions: [geminicli.com/docs/extensions/](https://geminicli.com/docs/extensions/)
- Gemini CLI subagents: [geminicli.com/docs/core/subagents/](https://geminicli.com/docs/core/subagents/)
- Gemini CLI hooks: [geminicli.com/docs/hooks/](https://geminicli.com/docs/hooks/)
- Gemini CLI policy engine: [geminicli.com/docs/reference/policy-engine/](https://geminicli.com/docs/reference/policy-engine/)
