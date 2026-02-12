---
name: resolve-todo-parallel
description: This skill should be used when resolving all pending CLI todos from the /todos/ directory using parallel processing. It reads pending todos, plans resolution order with dependency analysis, and spawns parallel agents. Triggers on "resolve CLI todos", "fix pending todos", "parallel todo resolution", "clean up todos directory".
---

# Resolve CLI Todos in Parallel

Resolve all TODO items from the /todos/*.md directory using parallel processing.

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
