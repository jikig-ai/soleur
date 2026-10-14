# Codex Capability Baseline

**Last verified:** 2026-03-10
**Codex CLI version:** 0.113.0
**Sources:** developers.openai.com/codex/ (skills, multi-agent, config-reference, changelog)

## Skills

- Format: `SKILL.md` with YAML frontmatter (`name`, `description`)
- Optional: `scripts/`, `references/`, `assets/`, `agents/openai.yaml`
- Directory: `.agents/skills/` (scans CWD upward to root, then `$HOME/.agents/skills/`)
- Invocation: `/skills` command, `$skill-name` mention, or implicit (auto-trigger from description match)
- Optional metadata in `agents/openai.yaml`: `display_name`, `short_description`, icons, `brand_color`, `default_prompt`, `allow_implicit_invocation`, tool dependencies
- No documented argument passing mechanism (no equivalent to `$ARGUMENTS`)
- No skill-to-skill programmatic invocation (no equivalent to Claude Code's `Skill tool`)
- No interactive structured prompt tool (no equivalent to `AskUserQuestion`)

## Multi-Agent

- Defined as roles in `config.toml` under `[agents.<name>]`
- Built-in roles: `default`, `worker`, `explorer`, `monitor`
- Custom roles with: `description`, `config_file`, `model`, `model_reasoning_effort`, `sandbox_mode`, `developer_instructions`
- `max_threads` (default: 6), `max_depth` (default: 1)
- Agents CANNOT spawn other agents programmatically — only the orchestrator can
- CSV batch processing via `spawn_agents_on_csv` tool
- No equivalent to Claude Code's `Task` tool (fire prompt at named agent, get structured response)

## Hooks

- No PreToolUse hooks (no pre-execution interception)
- No SessionStart/Stop hooks (feature request: github.com/openai/codex/issues/13014)
- `notify` hook available (post-hoc notification only)
- `approval_policy` for permission management (coarser than hooks)
- No `hookSpecificOutput` protocol

## MCP Support

- Configured in `config.toml` under `mcp_servers.<id>.*`
- Supports stdio and HTTP servers
- Tool allowlists/denylists via `enabled_tools` / `disabled_tools`
- OAuth configuration with scopes
- Playwright/browser MCP tools: supported (if MCP server configured)

## Plugin System

- Launched v0.110.0 (March 5, 2026) — 5 days old
- Marketplace discovery available
- @plugin mentions (v0.112.0)
- Permission-request tool at runtime (v0.113.0)
- Supports skills, MCP entries, and app connectors

## Key Gaps (vs. Claude Code)

| Capability | Claude Code | Codex | Gap |
|-----------|------------|-------|-----|
| PreToolUse hooks | Shell scripts with JSON stdin/stdout | None | CRITICAL |
| AskUserQuestion | Structured multi-choice prompts | None | HIGH |
| Task/subagent spawning | Fire prompt at named agent, get response | Orchestrator-only spawning | HIGH |
| Skill-to-skill invocation | `Skill tool` programmatic chaining | `$skill-name` mention only | HIGH |
| $ARGUMENTS | Plugin runtime substitution | No documented equivalent | MEDIUM |
| TodoWrite | In-session task tracking | None documented | MEDIUM |
| SessionStart/Stop hooks | Plugin lifecycle events | Feature request only | HIGH |
| hookSpecificOutput | JSON protocol for hook responses | None | HIGH |
| CLAUDE_PLUGIN_ROOT | Plugin path variable | None documented | MEDIUM |
| WebSearch/WebFetch | Built-in tools | `web_search` feature flag | PARTIAL |

## Equivalence Mapping (10 Primitives)

| # | Primitive | Risk | Codex Equivalent | Mapping Confidence |
|---|-----------|------|-----------------|-------------------|
| 1 | AskUserQuestion | HIGH | None — model can ask freeform but no structured multi-choice tool | HIGH (confirmed absent) |
| 2 | Skill tool / inter-skill | HIGH | `$skill-name` mention (different semantics — no programmatic mid-execution invocation) | MEDIUM (mention exists but orchestration differs) |
| 3 | Task / subagent | HIGH | None — orchestrator spawns agents, not agents themselves; CSV batch ≠ Task | HIGH (confirmed absent) |
| 4 | $ARGUMENTS | MEDIUM | No documented equivalent; `default_prompt` in openai.yaml is closest but different | MEDIUM (may exist undocumented) |
| 5 | TodoWrite | MEDIUM | None documented | MEDIUM (may exist undocumented) |
| 6 | hookSpecificOutput | HIGH | None | HIGH (confirmed absent) |
| 7 | MCP tool refs | HIGH | MCP supported — same tool names if same MCP server configured | LOW (depends on server config, may work) |
| 8 | WebSearch / WebFetch | MEDIUM | `web_search` feature flag (partial — search exists, WebFetch unclear) | MEDIUM |
| 9 | CLAUDE_PLUGIN_ROOT | MEDIUM | None documented — plugin path resolution differs | MEDIUM |
| 10 | SessionStart / Stop | HIGH | None — feature request #13014 open | HIGH (confirmed absent) |
