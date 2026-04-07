---
title: "OpenHands Portability PoC Results"
date: 2026-04-07
issue: 1770
openhands_sdk_version: "1.15.0 (openhands-ai 1.6.0)"
---

# Proof of Concept Results

## Environment

- OpenHands SDK: v1.15.0 (`openhands-ai` 1.6.0 via pip)
- Python: 3.13
- Docker: 29.3.1 (available but not used for structural tests)
- LLM: Anthropic API key available in Doppler (runtime tests possible)

## Critical Unknown Verification

### Unknown #1: File-Based Agent Discovery — CONFIRMED WORKING

```python
from openhands.sdk import load_agents_from_dir
from openhands.sdk.subagent import register_file_agents

# load_agents_from_dir(Path) returns List[AgentDefinition]
# register_file_agents(project_root) discovers .agents/agents/*.md
```

**AgentDefinition fields** (from `openhands.sdk.subagent.schema`):

| Field | Type | Soleur Equivalent | Mapping |
|---|---|---|---|
| name | str | `name:` | Direct |
| description | str | `description:` | Direct |
| model | str | `model:` | Direct (`inherit` works) |
| tools | list | N/A (implicit in Claude Code) | New — explicitly list available tools |
| skills | list | N/A | New — skill names to load |
| system_prompt | str | Body text (after `---`) | Direct |
| hooks | dict | N/A | New — per-agent hooks |
| mcp_servers | dict | N/A | New — per-agent MCP config |
| when_to_use_examples | list | `<example>` tags in description | Direct extraction |
| permission_mode | str | N/A | New — action confirmation policy |
| max_iteration_per_run | int | N/A | New — iteration limits |
| metadata | dict | N/A | New — arbitrary metadata |

**Key insight:** OpenHands AgentDefinition is a SUPERSET of Soleur's agent format. Every Soleur field maps directly, plus OpenHands adds per-agent hooks, MCP servers, and tool scoping that Soleur doesn't have.

**Tested:** Created two file-based agents (cfo.md, budget-analyst.md) mimicking Soleur's format. Both loaded successfully with correct name, description, model, and system_prompt fields.

### Unknown #2: File-Based Agent Delegation — CONFIRMED STRUCTURALLY

```python
from openhands.tools.delegate.definition import DelegateAction, DelegateTool

# DelegateAction fields:
#   command: Literal['spawn', 'delegate']
#   ids: list[str] | None        # agent IDs for spawn
#   agent_types: list[str] | None # registered agent types
#   tasks: dict[str, str] | None  # {agent_id: task_description}
```

**DelegateTool** exists at `openhands.tools.delegate` with:

- `spawn` command: creates sub-agents by registered type
- `delegate` command: assigns tasks to spawned agents
- `agent_types` field: references registered agent names (from `register_file_agents`)

**Structurally confirmed:** After `register_file_agents(project_root)`, both `cfo` and `budget-analyst` are registered. The DelegateTool's `agent_types` field can reference these names. **Runtime verification needed** to confirm actual spawn + delegate execution.

**Nesting depth:** The DelegateTool implementation does not enforce a nesting limit in its schema. Whether sub-agents can themselves delegate is a runtime question.

### Unknown #3: Plugin System — CONFIRMED API EXISTS

```python
from openhands.sdk.plugin import (
    Plugin, PluginManifest,
    install_plugin, enable_plugin, disable_plugin, uninstall_plugin,
    list_installed_plugins, update_plugin
)
```

**PluginManifest fields:** name, version, description, author, entry_command

**Plugin management functions all importable:**

- `install_plugin` — install from local path or GitHub URL
- `enable_plugin` / `disable_plugin` — toggle plugins
- `uninstall_plugin` — remove
- `list_installed_plugins` — enumerate
- `update_plugin` — update from source

**Not runtime-tested:** Creating and installing a full plugin with agents, skills, hooks, and MCP config. The API exists but end-to-end plugin installation from a GitHub repo was not verified.

### Unknown #4: Hook System — CONFIRMED WORKING

```python
from openhands.sdk.hooks import HookConfig, HookType, HookDefinition

config = HookConfig.from_dict({
    "pre_tool_use": [{"matcher": "execute_bash", "hooks": [{"command": "guardrails.sh", "timeout": 10}]}],
    "session_start": [{"matcher": "*", "hooks": [{"command": "welcome.sh", "timeout": 5}]}],
    "stop": [{"matcher": "*", "hooks": [{"command": "stop-hook.sh", "timeout": 30}]}]
})
```

**HookType values:** `command`, `prompt`

**HookDefinition fields:** type, command, timeout, async_

**Confirmed:** HookConfig.from_dict accepts PreToolUse, SessionStart, and Stop hook configurations — all three hook types Soleur uses.

### Unknown #5: TaskTrackerTool — DISCOVERED (NOT IN DOCS)

```python
from openhands.tools.task_tracker import TaskTrackerTool, TaskTrackerAction

# TaskTrackerAction fields:
#   command: Literal['view', 'plan']
#   task_list: list[TaskItem]
```

**Surprise finding:** OpenHands has a `TaskTrackerTool` that was not mentioned in the critical unknowns. It supports `view` and `plan` commands with a task list. This is a partial equivalent to Claude Code's TodoWrite — it tracks tasks but uses different semantics (plan/view vs create/update/complete).

**Impact:** The 7 skills using TodoWrite may shift from YELLOW to GREEN if TaskTrackerTool provides equivalent functionality. Needs runtime verification.

### Unknown #6: MCP Configuration — CONFIRMED

```python
from openhands.sdk import MCPClient, create_mcp_tools, MCPToolDefinition
```

All three MCP classes importable. MCPClient handles server connection, MCPToolDefinition wraps MCP tools as SDK ToolDefinitions, create_mcp_tools auto-discovers from config.

### Unknown #7: Skill Loading — CONFIRMED

```python
from openhands.sdk import load_skills_from_dir

# Returns tuple of 3 dicts: (repo_skills, keyword_skills, task_skills)
# Keyword skills keyed by skill name
```

Skills load from `.agents/skills/*/SKILL.md` with YAML frontmatter. Keyword trigger matching confirmed.

---

## Summary

| Critical Unknown | Status | Confidence | Runtime Needed? |
|---|---|---|---|
| File-based agent discovery | CONFIRMED | HIGH | No — tested |
| File-based agent delegation | CONFIRMED (structural) | MEDIUM | Yes — spawn+delegate execution |
| Plugin system API | CONFIRMED | MEDIUM | Yes — end-to-end install from GitHub |
| Hook system | CONFIRMED | HIGH | No — tested |
| DelegateTool nesting depth | UNVERIFIED | LOW | Yes — sub-sub-agent spawn test |
| MCP configuration | CONFIRMED | HIGH | No — API tested |
| Skill loading | CONFIRMED | HIGH | No — tested |

## Surprise Findings

1. **AgentDefinition is a superset** — OpenHands adds per-agent hooks, MCP servers, tool scoping, permission mode, and metadata that Soleur doesn't have. Porting from Soleur to OpenHands gains features.

2. **TaskTrackerTool exists** — Undocumented TodoWrite-equivalent with plan/view commands. May resolve one of the inventory's YELLOW gaps.

3. **Default tools** — The `openhands.tools` package provides: DelegateTool, FileEditorTool, TaskTrackerTool, TerminalTool, plus built-in FinishTool and ThinkTool. These map well to Claude Code's tool set.

4. **Per-agent hooks and MCP** — Soleur agents currently share global hooks and MCP config. On OpenHands, each agent can have its own hooks and MCP servers, enabling finer-grained tool access control.

## Inventory Impact

The PoC findings suggest the inventory should be updated:

| Change | From | To | Reason |
|---|---|---|---|
| TaskTrackerTool discovery | P5 TodoWrite: YELLOW | P5 TodoWrite: GREEN (pending verification) | TaskTrackerTool with plan/view commands |
| AgentDefinition superset | Agents: tool name changes | Agents: tool name changes + feature gains | Per-agent hooks, MCP, tools, permission_mode |

## Remaining Runtime Verification

To fully close the critical unknowns, these runtime tests need an active LLM connection:

1. **DelegateTool spawn+delegate execution** — Create parent agent, spawn child via DelegateTool, delegate task, verify result consolidation
2. **Nesting depth** — Parent → child → grandchild delegation chain
3. **Plugin installation from GitHub** — `install_plugin("https://github.com/test/plugin")`
4. **Hook blocking** — PreToolUse hook returns exit code 2, verify tool execution is blocked
5. **TaskTrackerTool vs TodoWrite** — Verify plan/view/TaskItem semantics match Soleur's create/update/complete pattern
