---
name: resolve-todo-parallel
description: "This skill should be used when resolving all pending CLI todos from the todos/ directory using parallel processing. It reads pending todos, plans resolution order with dependency analysis, and spawns parallel agents."
---

# Resolve CLI Todos in Parallel

> **Note:** The `/soleur:review` skill now creates GitHub issues directly for all new findings.
> This skill handles only legacy local `todos/*.md` files that predate the GitHub issue integration.

Resolve all TODO items from the /todos/*.md directory using parallel processing.

<decision_gate>
**API budget.** This skill spawns one `pr-comment-resolver` agent in parallel per unresolved TODO (N TODOs = N agents). Each agent runs an independent task with its own context window and token cost; parallel fan-out compresses wall-clock but not aggregate token consumption. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm the TODO count before allowing the fan-out. A pending backlog of 30 TODOs spawns 30 parallel agents.
</decision_gate>

## Workflow

### 1. Analyze

Get all unresolved TODOs from the /todos/\*.md directory.

### 2. Plan

Create a TodoWrite list of all unresolved items grouped by type. Look at dependencies that might occur and prioritize the ones needed by others. For example, if a name change is needed, wait to do the dependents. Output a mermaid flow diagram showing how the work can proceed. Can everything run in parallel? Does one item need to complete first before others can start? Structure the to-dos in the mermaid diagram flow-wise so the agent knows how to proceed in order.

### 3. Implement (PARALLEL)

Spawn a pr-comment-resolver agent for each unresolved item in parallel.

So if there are 3 items, spawn 3 pr-comment-resolver agents in parallel:

1. Task pr-comment-resolver(item1)
2. Task pr-comment-resolver(item2)
3. Task pr-comment-resolver(item3)

Always run all in parallel subagents/Tasks for each Todo item.

### 4. Commit & Resolve

- Commit changes
- Remove the TODO from the file, and mark it as resolved.
- Push to remote
