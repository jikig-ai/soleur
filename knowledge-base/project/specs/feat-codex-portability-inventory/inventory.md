# Codex Portability Inventory

**Date:** 2026-03-10
**Codex CLI version:** 0.113.0 (verified same day)
**Methodology:** Grep-based scan for 10 Claude Code-specific primitives across all component files (skills scan entire directory including references/, scripts/, assets/)
**Baseline:** [codex-baseline.md](./codex-baseline.md)

## Summary Statistics

| Classification | Count | Percentage | Description |
|---------------|-------|-----------|-------------|
| 🟢 Green | 58 | 47.5% | Ports to Codex as-is (modulo directory restructuring) |
| 🟡 Yellow | 9 | 7.4% | Needs adaptation — uses MEDIUM-risk primitives with partial equivalents |
| 🔴 Red | 53 | 43.4% | Requires rewrite — uses HIGH-risk primitives with no Codex equivalent |
| ⚪ N/A | 2 | 1.6% | Claude Code infrastructure only — no purpose on Codex |
| **Total** | **122** | **100%** | |

**By component type:**

| Type | Green | Yellow | Red | N/A | Total |
|------|-------|--------|-----|-----|-------|
| Agents | 42 (67.7%) | 3 (4.8%) | 17 (27.4%) | 0 | 62 |
| Skills | 16 (28.1%) | 6 (10.5%) | 33 (57.9%) | 2 (3.5%) | 57 |
| Commands | 0 | 0 | 3 (100%) | 0 | 3 |

**Key insight:** Agents are highly portable (67.7% green) because they are prose instructions with minimal orchestration. Skills are mostly non-portable (57.9% red) because they contain the workflow orchestration logic. All commands are red.

---

## Full Component Inventory

### 🟢 Green Agents (42)

These agents port to Codex's AGENTS.md / agent role format with zero content changes. Only directory restructuring needed (`.agents/` vs `plugins/soleur/agents/`).

| Agent | Domain |
|-------|--------|
| cto | engineering |
| ddd-architect | engineering |
| infra-security | engineering |
| terraform-architect | engineering |
| framework-docs-researcher | engineering |
| git-history-analyzer | engineering |
| learnings-researcher | engineering |
| repo-research-analyst | engineering |
| agent-native-reviewer | engineering |
| architecture-strategist | engineering |
| code-quality-analyst | engineering |
| code-simplicity-reviewer | engineering |
| data-integrity-guardian | engineering |
| data-migration-expert | engineering |
| deployment-verification-agent | engineering |
| dhh-rails-reviewer | engineering |
| kieran-rails-reviewer | engineering |
| legacy-code-expert | engineering |
| pattern-recognition-specialist | engineering |
| performance-oracle | engineering |
| security-sentinel | engineering |
| semgrep-sast | engineering |
| test-design-reviewer | engineering |
| pr-comment-resolver | engineering |
| budget-analyst | finance |
| financial-reporter | finance |
| revenue-analyst | finance |
| legal-document-generator | legal |
| analytics-analyst | marketing |
| conversion-optimizer | marketing |
| copywriter | marketing |
| paid-media-strategist | marketing |
| pricing-strategist | marketing |
| programmatic-seo-specialist | marketing |
| retention-strategist | marketing |
| seo-aeo-analyst | marketing |
| ops-advisor | operations |
| spec-flow-analyzer | product |
| deal-architect | sales |
| outbound-strategist | sales |
| pipeline-analyst | sales |
| ticket-triage | support |

### 🟡 Yellow Agents (3)

| Agent | Domain | Blocking Primitive | Codex Equivalent |
|-------|--------|--------------------|-----------------|
| fact-checker | marketing | WebSearch/WebFetch | `web_search` feature flag (partial) |
| growth-strategist | marketing | WebSearch/WebFetch | `web_search` feature flag (partial) |
| ops-research | operations | WebSearch/WebFetch | `web_search` feature flag (partial) |

### 🔴 Red Agents (17)

| Agent | Domain | Blocking Primitives | Primary Blocker |
|-------|--------|--------------------|-----------------|
| agent-finder | engineering | AskUserQuestion | No structured prompt tool |
| functional-discovery | engineering | AskUserQuestion | No structured prompt tool |
| best-practices-researcher | engineering | Skill tool | No skill-to-skill invocation |
| cfo | finance | Task/subagent | No programmatic agent spawning |
| clo | legal | Task/subagent | No programmatic agent spawning |
| legal-compliance-auditor | legal | Task/subagent, WebSearch | No programmatic agent spawning |
| brand-architect | marketing | AskUserQuestion | No structured prompt tool |
| cmo | marketing | Task/subagent | No programmatic agent spawning |
| coo | operations | Task/subagent | No programmatic agent spawning |
| ops-provisioner | operations | AskUserQuestion | No structured prompt tool |
| business-validator | product | AskUserQuestion, WebSearch | No structured prompt tool |
| competitive-intelligence | product | AskUserQuestion, Task, WebSearch | Multiple blockers |
| cpo | product | Task/subagent | No programmatic agent spawning |
| ux-design-lead | product | AskUserQuestion | No structured prompt tool |
| cro | sales | Task/subagent | No programmatic agent spawning |
| cco | support | Task/subagent | No programmatic agent spawning |
| community-manager | support | AskUserQuestion | No structured prompt tool |

**Pattern:** All 8 domain leader agents (C-suite: cfo, clo, cmo, coo, cpo, cro, cco, cto) are red except cto. Leaders are red because they spawn specialist agents via Task tool. cto is green because it provides assessment prose without orchestrating specialists.

---

### 🟢 Green Skills (16)

These skills port to Codex's `.agents/skills/` format with zero content changes.

| Skill | Description |
|-------|-------------|
| agent-browser | CLI browser automation via Bash |
| andrew-kane-gem-writer | Ruby gem writing patterns |
| archive-kb | Archive knowledge-base artifacts |
| changelog | Generate changelogs from PRs |
| deploy-docs | Eleventy docs deployment |
| dhh-rails-style | DHH Rails coding style |
| docs-site | Scaffold Eleventy docs site |
| every-style-editor | Copy editing style guide |
| frontend-design | Production frontend interfaces |
| gemini-imagegen | Gemini API image generation |
| git-worktree | Git worktree management (pure bash) |
| pencil-setup | Pencil MCP tool setup |
| rclone | Cloud storage file management |
| release-announce | GitHub Release creation |
| release-docs | Documentation metadata updates |
| user-story-writer | User story decomposition |

### 🟡 Yellow Skills (6)

| Skill | Blocking Primitives | Codex Equivalent | Complexity |
|-------|--------------------|--------------------|-----------|
| dspy-ruby | WebSearch/WebFetch | `web_search` (partial) | Trivial |
| feature-video | $ARGUMENTS | No documented equivalent | Trivial — remove or hardcode |
| file-todos | TodoWrite | None documented | Moderate — replace with file-based tracking |
| fix-issue | $ARGUMENTS | No documented equivalent | Trivial |
| test-fix-loop | $ARGUMENTS | No documented equivalent | Trivial |
| triage | TodoWrite | None documented | Moderate |

### 🔴 Red Skills (33)

| Skill | Blocking Primitives | Primary Blocker |
|-------|--------------------|-----------------|
| agent-native-architecture | Task, WebSearch | No programmatic agent spawning |
| agent-native-audit | Task, $ARGUMENTS | No programmatic agent spawning |
| atdd-developer | Task | No programmatic agent spawning |
| brainstorm | AskUser, Skill, Task, $ARGS | Multiple — core orchestration |
| brainstorm-techniques | Skill tool | No skill-to-skill invocation |
| community | AskUser, $ARGUMENTS | No structured prompt tool |
| competitive-analysis | AskUser, Task | Multiple blockers |
| compound | Skill, $ARGS, hookSpecificOutput | Hook protocol dependency |
| compound-capture | AskUser, Skill, $ARGS | Multiple blockers |
| content-writer | AskUser, Task | Multiple blockers |
| deepen-plan | AskUser, Skill, Task, $ARGS, MCP, WebSearch | Highest primitive density (6) |
| deploy | AskUserQuestion | No structured prompt tool |
| discord-content | AskUserQuestion | No structured prompt tool |
| growth | Task, WebSearch | No programmatic agent spawning |
| legal-audit | AskUser, Task | Multiple blockers |
| legal-generate | AskUser, Task | Multiple blockers |
| merge-pr | Skill tool | No skill-to-skill invocation |
| one-shot | Skill, Task, $ARGS | Core pipeline orchestrator |
| plan | AskUser, Skill, Task, $ARGS | Core pipeline orchestrator |
| plan-review | @agent- implicit subagent | No programmatic agent spawning |
| reproduce-bug | $ARGS, MCP tools | MCP tool references |
| resolve-parallel | Task, TodoWrite | No programmatic agent spawning |
| resolve-pr-parallel | Task, TodoWrite | No programmatic agent spawning |
| resolve-todo-parallel | Task, TodoWrite | No programmatic agent spawning |
| review | Skill, Task, $ARGS | Core pipeline orchestrator |
| schedule | AskUser, Skill, $ARGS, WebSearch | Multiple blockers |
| seo-aeo | Task | No programmatic agent spawning |
| ship | Skill, $ARGS, TodoWrite | Core pipeline orchestrator |
| social-distribute | AskUserQuestion | No structured prompt tool |
| spec-templates | Task | No programmatic agent spawning |
| test-browser | AskUser, $ARGS | No structured prompt tool |
| work | Skill, Task, $ARGS, TodoWrite, WebSearch | Core pipeline orchestrator |
| xcode-test | AskUser, Task | Multiple blockers |

### ⚪ N/A Skills (2)

| Skill | Reason |
|-------|--------|
| heal-skill | Repairs Claude Code skill structure — no purpose on Codex |
| skill-creator | Creates Claude Code plugin skills — no purpose on Codex |

### 🔴 Red Commands (3)

| Command | Blocking Primitives | Primary Blocker |
|---------|--------------------|-----------------|
| go | AskUser, Skill, $ARGS | Entry point router — core orchestration |
| help | Skill tool | Lists Claude Code plugin components |
| sync | AskUser, $ARGS | No structured prompt tool |

**Note:** Codex has no user-defined slash command mechanism. Commands would need to become skills on Codex.

---

## Gap Analysis by Primitive

### P1: AskUserQuestion (HIGH) — No Codex Equivalent

**Usage:** 29 files, ~54 references
**Affected components:** 9 agents, 16 skills, 2 commands (27 total)
**Codex equivalent:** None. Codex models can ask freeform questions but there is no structured multi-choice prompt tool with options, descriptions, and guaranteed response format.
**Impact:** Skills like brainstorm, plan, and ship use AskUserQuestion for routing decisions, approval gates, and domain leader selection. Without structured prompts, these become unreliable freeform interactions where the model must parse natural language responses.

### P2: Skill Tool / Inter-Skill Chaining (HIGH) — Partial Codex Equivalent

**Usage:** 20+ files, ~80 references
**Affected components:** 1 agent, 14 skills, 2 commands (17 total)
**Codex equivalent:** `$skill-name` mention invokes a skill, but there is no programmatic mid-execution invocation. Codex skills cannot call other skills from within their instruction text.
**Impact:** The core workflow pipeline (go → brainstorm → plan → work → review → compound → ship) depends on Skill tool chaining. The `one-shot` skill chains 9 skills sequentially. This pipeline cannot be reproduced on Codex without restructuring into a single monolithic skill or user-driven sequential invocation.

### P3: Task / Subagent Spawning (HIGH) — No Codex Equivalent

**Usage:** 30+ files, ~100+ references
**Affected components:** 9 agents, 19 skills (28 total)
**Codex equivalent:** None for programmatic spawning. Codex agents are spawned by the orchestrator only, not by other agents or skills. `max_depth=1` prevents agent nesting.
**Impact:** Domain leader agents (C-suite) spawn specialist agents. Skills like review (14 parallel agents), deepen-plan (10+ agents), and brainstorm (domain leader fan-out) depend on Task tool. This is the highest-impact gap — it breaks the entire multi-agent architecture.

### P4: $ARGUMENTS (MEDIUM) — No Documented Codex Equivalent

**Usage:** 22 files, ~30 references
**Affected components:** 18 skills, 2 commands (20 total)
**Codex equivalent:** `default_prompt` in `agents/openai.yaml` is the closest but serves a different purpose (wrapping prompt, not argument injection). No documented runtime argument substitution.
**Impact:** Skills use `$ARGUMENTS` to receive input from invoking skills or commands. Without this, skills lose their ability to be parameterized. Workaround: hardcode defaults or use file-based argument passing.

### P5: TodoWrite (MEDIUM) — No Documented Codex Equivalent

**Usage:** 7 files, ~14 references
**Affected components:** 6 skills
**Codex equivalent:** None documented. Codex may have internal task tracking but no exposed TodoWrite tool.
**Impact:** Used in work, ship, triage, file-todos, and the three resolve-* skills for in-session progress tracking. Workaround: use file-based checklists.

### P6: hookSpecificOutput (HIGH) — No Codex Equivalent

**Usage:** 2 files, 2 references
**Affected components:** 1 skill (compound)
**Codex equivalent:** None. No hook response protocol exists.
**Impact:** Minimal — only used in compound skill's defense-in-depth branch safety check and the welcome hook.

### P7: MCP Tool References (HIGH) — Partial Codex Equivalent

**Usage:** 2 skills (deepen-plan, reproduce-bug)
**Codex equivalent:** MCP is supported via `mcp_servers.*` config. If the same MCP servers are configured, tool names may work. But Playwright MCP tool names (`mcp__plugin_playwright_*`) are Claude Code-specific prefixes.
**Impact:** Low — only 2 skills affected. Solvable by configuring equivalent MCP servers on Codex.

### P8: WebSearch / WebFetch (MEDIUM) — Partial Codex Equivalent

**Usage:** 14 files, ~31 references
**Affected components:** 6 agents, 5 skills (11 total)
**Codex equivalent:** `web_search` feature flag (`disabled`, `cached`, `live`). Search exists but WebFetch (arbitrary URL fetching with AI processing) is unclear.
**Impact:** Moderate. Agents like fact-checker and growth-strategist use WebFetch for live research. May work with Codex's web search but behavior differs.

### P9: CLAUDE_PLUGIN_ROOT (MEDIUM) — No Codex Equivalent

**Usage:** 0 components (only in hooks, not agents/skills/commands)
**Impact:** None for the 122 components. Only affects hook scripts.

### P10: SessionStart / Stop Hooks (HIGH) — No Codex Equivalent

**Usage:** 0 components (only in hooks/hooks.json)
**Codex equivalent:** None. SessionStart is feature request #13014.
**Impact:** None for the 122 components. Affects the welcome hook and Ralph loop continuation.

---

## Inter-Component Dependencies

### Core Workflow Pipeline (all RED)

```
go ──→ brainstorm ──→ plan ──→ work ──→ review ──→ compound ──→ ship
  ├──→ one-shot (chains all above + deepen-plan, test-browser, feature-video)
  ├──→ review (standalone)
  └──→ work (standalone)
```

Every node in this pipeline is RED. Porting any individual node has limited standalone value because the entry points (go, one-shot) and the pipeline connections (Skill tool) are all non-portable.

### Domain Leader → Specialist Pattern

| Leader (RED) | Specialists (mostly GREEN) | Portable Specialists |
|-------------|---------------------------|---------------------|
| cmo | 11 marketing agents | 8 green, 1 yellow, 2 red |
| cfo | 3 finance agents | 3 green |
| clo | 2 legal agents | 1 green, 1 red |
| coo | 3 operations agents | 1 green, 1 yellow, 1 red |
| cpo | 4 product agents | 1 green, 3 red |
| cro | 3 sales agents | 3 green |
| cco | 2 support agents | 1 green, 1 red |

The specialist agents are highly portable (most are green), but their leaders (who orchestrate them via Task tool) are all red. On Codex, specialists would need to be invoked directly rather than through the leader hierarchy.

---

## CI/Infrastructure (Not Counted in 122)

These platform-locked components are outside the agent/skill/command taxonomy but contribute to Soleur's platform coupling:

| Component | Type | Blocking Primitive |
|-----------|------|--------------------|
| hooks/hooks.json | Plugin hook manifest | SessionStart, Stop events |
| hooks/welcome-hook.sh | SessionStart hook | hookSpecificOutput, CLAUDE_PLUGIN_ROOT |
| hooks/stop-hook.sh | Stop hook | Ralph loop protocol |
| .claude/hooks/guardrails.sh | PreToolUse hook | JSON stdin/stdout protocol |
| .claude/hooks/pre-merge-rebase.sh | PreToolUse hook | JSON stdin/stdout protocol |
| .claude/hooks/worktree-write-guard.sh | PreToolUse hook | JSON stdin/stdout protocol |
| .claude-plugin/plugin.json | Plugin manifest | Claude Code-specific format |
| .claude-plugin/marketplace.json | Distribution manifest | Claude Code marketplace |
| .claude/settings.json | Project settings | PreToolUse hook configuration |
| 12 GitHub Actions workflows | CI/CD | claude-code-action references |
