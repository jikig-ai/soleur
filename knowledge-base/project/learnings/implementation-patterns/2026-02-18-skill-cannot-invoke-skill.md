---
title: Skills cannot invoke other skills programmatically
category: implementation-patterns
module: soleur-plugin
severity: medium
tags: [skills, architecture, plugin-loader]
date: 2026-02-18
---

# Skills Cannot Invoke Other Skills Programmatically

## Problem

When designing the community skill with a `post` sub-command, the initial plan had it "delegate to discord-content skill." During plan review, this was identified as architecturally impossible -- skills are user-invoked entry points discovered by the plugin loader. There is no API for one skill to call another.

## Solution

Changed the `post` sub-command to inform the user to run `/soleur:discord-content <topic>` directly, rather than attempting programmatic invocation.

For cases where a skill needs functionality from another skill:
1. **Inform and redirect:** Tell the user to invoke the other skill directly
2. **Duplicate the logic:** Copy the essential behavior inline (if small enough)
3. **Extract to a shared script:** Move common logic to a script both skills can call via Bash
4. **Use an agent:** Agents CAN be spawned by skills via Task tool. If orchestration is needed, route through an agent.

## Key Insight

The Soleur architecture has a clear invocation hierarchy:
- **Users** invoke skills (via `/soleur:<name>`) and commands
- **Skills** can spawn agents (via Task tool) and run scripts (via Bash)
- **Agents** can spawn other agents (via Task tool) and run scripts
- **Skills cannot call other skills.** There is no inter-skill communication.

When designing multi-capability skills, prefer the agent + skill combo pattern: the skill handles routing and simple actions, the agent handles complex multi-step reasoning that might need capabilities from multiple domains.

## Tags

category: implementation-patterns
module: soleur-plugin
