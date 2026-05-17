---
name: resolve-pr-parallel
description: "This skill should be used when resolving all PR comments using parallel processing. It fetches unresolved comments, spawns parallel resolver agents, and verifies all threads are resolved."
---

# Resolve PR Comments in Parallel

Resolve all PR comments using parallel processing.

Claude Code automatically detects and understands git context:

- Current branch detection
- Associated PR context
- All PR comments and review threads
- Can work with any PR by specifying the PR number, or ask it.

<decision_gate>
**API budget.** This skill spawns one `pr-comment-resolver` agent in parallel per unresolved PR comment (N comments = N agents). Each agent runs an independent task with its own context window and token cost; parallel fan-out compresses wall-clock but not aggregate token consumption. Soleur does not bill or proxy these calls — Anthropic does, against the key in your session. The Soleur LICENSE (BSL 1.1) disclaims warranty for runtime cost; you operate this loop against your own budget.

Confirm the unresolved-comment count before allowing the fan-out. A PR with 40 unresolved threads spawns 40 parallel agents.
</decision_gate>

## Workflow

### 1. Analyze

Get all unresolved comments for the PR:

```bash
gh pr status
bin/get-pr-comments PR_NUMBER
```

### 2. Plan

Create a TodoWrite list of all unresolved items grouped by type.

### 3. Implement (PARALLEL)

Spawn a pr-comment-resolver agent for each unresolved item in parallel.

So if there are 3 comments, spawn 3 pr-comment-resolver agents in parallel:

1. Task pr-comment-resolver(comment1)
2. Task pr-comment-resolver(comment2)
3. Task pr-comment-resolver(comment3)

Always run all in parallel subagents/Tasks for each Todo item.

### 4. Commit & Resolve

- Commit changes
- Run bin/resolve-pr-thread THREAD_ID_1
- Push to remote

Last, check bin/get-pr-comments PR_NUMBER again to see if all comments are resolved. They should be; if not, repeat the process from step 1.
