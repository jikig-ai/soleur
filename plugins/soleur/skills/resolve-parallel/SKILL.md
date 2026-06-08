---
name: resolve-parallel
description: "This skill should be used when resolving all TODO comments in the codebase using parallel processing. It analyzes dependencies, creates a resolution plan with a mermaid flow diagram, and spawns parallel resolver agents."
---

> **Dynamic-workflow alternative (opt-in).** A [`Workflow`-tool](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code) port of this skill lives at [`workflows/resolve-parallel.workflow.js`](./workflows/resolve-parallel.workflow.js) — deterministic fan-out, journaled resume, schema-validated output. Run it with `Workflow({ scriptPath: "plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js", args: ... })`. The prose skill below stays the default; the two coexist during calibration. See [`knowledge-base/project/specs/feat-review-workflow-prototype/spec.md`](../../../../knowledge-base/project/specs/feat-review-workflow-prototype/spec.md).

# Resolve TODO Comments in Parallel

Resolve all TODO comments using parallel processing.

## Workflow

### 1. Analyze

Gather the TODO items from the codebase.

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
- Push to remote
