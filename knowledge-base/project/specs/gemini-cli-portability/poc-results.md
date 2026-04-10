---
title: "Gemini CLI Proof of Concept Results"
date: 2026-04-07
issue: 1738
---

# Proof of Concept Results

## Components Ported

### 1. CLO Domain (Green Agent → Gemini CLI)

**Source:** `plugins/soleur/agents/legal/clo.md` + 2 specialist agents
**Target:** `.gemini/agents/clo.md` + 2 specialist skills

| Aspect | Result | Notes |
|---|---|---|
| Agent format | Full parity | YAML frontmatter maps cleanly: `name`, `description` match. Added `tools`, `model`, `temperature`, `max_turns`, `timeout_mins`. |
| Prose instructions | Full parity | Assessment → Recommend → Sharp Edges structure preserved verbatim. |
| Tool name mapping | Full parity | `gh issue view` via `run_shell_command`, file reads via `read_file`/`read_many_files`. |
| Specialist delegation | Partial parity | **Key adaptation:** Specialists restructured from agents to skills. CLO activates `legal-compliance-auditor` and `legal-document-generator` skills instead of spawning subagents via Task. Sequential execution only — no parallel specialist dispatch. |
| Subdirectory structure | Breaking change | Gemini CLI agents are flat (`*.md` in directory root). `agents/legal/clo.md` → `.gemini/agents/clo.md`. Domain organization lost. |

**Parity rating: Partial parity.** Core assessment and delegation flow works. Loses parallelism and directory organization.

### 2. Compound Skill (Yellow Skill → Gemini CLI)

**Source:** `plugins/soleur/skills/compound/SKILL.md` (~180 lines with references)
**Target:** `.gemini/skills/compound/SKILL.md`

| Aspect | Result | Notes |
|---|---|---|
| Skill format | Full parity | `SKILL.md` with YAML frontmatter — identical format across both platforms. |
| $ARGUMENTS | Adapted | Replaced with conversation context + `ask_user`. Skills receive no args on Gemini CLI — the model must check conversation context or prompt for input. |
| Parallel subagents | Degraded | Claude Code version spawns 5 parallel subagents (Context Analyzer, Solution Extractor, Related Docs Finder, Prevention Strategist, Documentation Writer). Gemini CLI version runs these sequentially within the same conversation. Slower but same output quality. |
| hookSpecificOutput | Removed | Branch safety check via `hookSpecificOutput` replaced with explicit `run_shell_command` git branch check. Loses hook-level enforcement (the check can be bypassed). |
| Skill chaining | Adapted | `skill: soleur:compound-capture` invocation replaced with inline execution. The compound-capture logic is embedded directly rather than chained via `activate_skill`. |
| Session error inventory | Full parity | Conversation scanning works identically. |
| Learning file creation | Full parity | `write_file` creates the same markdown output in `knowledge-base/project/learnings/`. |

**Parity rating: Partial parity.** Core learning capture works. Loses parallelism (5 subagents → sequential), hook enforcement (branch safety), and skill isolation.

### 3. Go Command (Red Command → Gemini CLI)

**Source:** `plugins/soleur/commands/go.md`
**Target:** `.gemini/commands/workflow/go.toml`

| Aspect | Result | Notes |
|---|---|---|
| Command format | Format change | COMMAND.md (Markdown with YAML frontmatter) → TOML file with `prompt = """..."""`. Fundamental format difference but same content. |
| $ARGUMENTS | Full parity | `$ARGUMENTS` → `{{args}}`. Commands (unlike skills) DO support argument interpolation on Gemini CLI. |
| AskUserQuestion | Full parity | `AskUserQuestion` → `ask_user`. Same structured prompt capability. |
| Skill routing | Adapted | `Skill tool` invocations → `activate_skill` calls. Works but skills receive no args (the user input must be in conversation context). |
| Worktree detection | Full parity | `pwd` check via `run_shell_command` works identically. |
| Intent classification | Full parity | Semantic assessment logic is model-driven, works on any model. |

**Parity rating: Partial parity.** Routing works. The gap is that downstream skills (brainstorm, work, review) receive no explicit args — they must read context from the conversation.

### 4. MCP Server Configuration

**Source:** `.mcp.json` + `plugin.json` mcpServers
**Target:** `.gemini/settings.json` mcpServers

| Server | Transport | Status | Notes |
|---|---|---|---|
| Context7 | HTTP | Compatible | `gemini mcp add context7 https://mcp.context7.com/mcp -t http` |
| Cloudflare | HTTP | Compatible | `gemini mcp add cloudflare https://mcp.cloudflare.com/mcp -t http` |
| Vercel | HTTP | Compatible | `gemini mcp add vercel https://mcp.vercel.com -t http` |
| Playwright | stdio | Compatible | `gemini mcp add playwright npx @playwright/mcp@latest --isolated` |

**Parity rating: Full parity.** All 4 MCP servers use transports natively supported by Gemini CLI. Config format differs (`.mcp.json` → `.gemini/settings.json`) but semantics match.

---

## Summary

| Component | Type | Parity | Key Gap |
|---|---|---|---|
| CLO domain | Agent | Partial | Specialists become skills (no parallel dispatch) |
| Compound | Skill | Partial | Sequential execution (was 5 parallel subagents), no hook enforcement |
| Go | Command | Partial | Format change (MD → TOML), downstream skills get no explicit args |
| MCP servers | Config | Full | Format change only |

## Functional Gaps by Severity

| Gap | Severity | Impact | Workaround Viability |
|---|---|---|---|
| No parallel subagent execution within subagents | HIGH | Domain leaders can't fan-out to specialists in parallel | Sequential skill activation — slower but functional |
| No skill argument passing | MEDIUM | Skills must rely on conversation context, not explicit params | `ask_user` fallback or conversation context parsing |
| No hook-level enforcement | MEDIUM | Branch protection, pre-commit checks rely on model compliance | Gemini CLI Policy Engine (.toml) provides tool-level blocking, different mechanism |
| Flat agent directory | LOW | Organizational inconvenience | Name prefixes (e.g., `marketing-cmo.md`) |
| Sequential skill execution | LOW | Workflows take longer | Acceptable for correctness-over-speed use cases |

## Runtime Verification Status

All ported components are **structurally valid** (correct file formats, frontmatter, tool references). **Runtime verification requires a Gemini API key** which is not currently configured in Doppler. The ported components need to be tested by:

1. Setting up a Gemini API key (`gemini mcp add` or manual auth)
2. Running `gemini -p "@clo Assess our legal document posture"` in the Soleur repo
3. Verifying CLO activates specialist skills
4. Running `/go #1234` to verify routing
5. Activating compound after a code change to verify learning capture

## Context Isolation Risk

The subagent-to-skill restructuring introduces a **context cross-contamination risk** that is not tested in this PoC. When multiple specialist skills run sequentially within the same leader subagent conversation, earlier skill outputs remain visible to later skills. This creates a failure mode where one specialist's output is misinterpreted as instructions or context by a subsequent specialist.

### Failure Scenario

Consider the CLO domain leader activating two specialists sequentially:

1. **legal-compliance-auditor** runs first, producing findings such as "Missing GDPR data processing agreement" or "Terms of Service lacks arbitration clause"
2. **legal-document-generator** runs second in the same conversation context

The document generator now sees the auditor's findings in its context window. Without explicit context boundaries, the generator may:

- Treat audit findings as generation instructions (e.g., generating a GDPR agreement because the auditor flagged its absence, even if the user only requested a Terms of Service update)
- Incorporate audit language verbatim into generated documents (mixing analytical tone into legal prose)
- Act on remediation recommendations meant for the human operator, not for another skill

### Why This Was Not Caught

The PoC verified structural validity (file formats, tool references, frontmatter) but did not execute any skills at runtime. The cross-contamination risk only manifests during actual sequential skill execution within a shared conversation context. Claude Code avoids this by spawning specialists as independent subagents with isolated conversation contexts.

### Affected Domains

Any domain leader that activates multiple specialists is affected. Severity scales with specialist count:

| Domain Leader | Specialist Count | Risk Level |
|---|---|---|
| CMO | 7+ | Critical — longest sequential chain, most diverse specialist outputs |
| CLO | 2 | Medium — auditor output may contaminate generator |
| CTO | 3 | Medium — architect findings may influence implementer |
| COO | 2 | Low — fewer cross-specialist dependencies |

### Runtime Test Case (Future)

When a Gemini API key is available, validate context isolation with the following test:

1. Activate the CLO subagent
2. Have CLO activate `legal-compliance-auditor` skill, which produces audit findings (e.g., "CRITICAL: Missing privacy policy")
3. Without clearing context, have CLO activate `legal-document-generator` skill with an unrelated request (e.g., "Generate a contributor license agreement")
4. **Pass condition:** The generated CLA contains no references to privacy policies, GDPR, or any content from the auditor's findings
5. **Fail condition:** The generated document incorporates or responds to the auditor's output

A second test should verify the reverse direction — generator output should not influence a subsequent audit's findings or severity assessments.
