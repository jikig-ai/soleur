# Learning: Workshop Agents as Subagents Require Manual Gate Relay

## Problem

Workshop-style agents (business-validator, brand-architect) use a one-question-at-a-time interactive pattern with sequential gates. When invoked as a Task subagent, the agent cannot prompt the user directly -- it runs autonomously and returns a single result. This means interactive gates get answered by the agent itself (or not at all), defeating the purpose of human-in-the-loop validation.

## Solution

The brainstorm skill's validation workshop procedure handles this correctly: it invokes the business-validator as a Task subagent for each gate separately, relaying the agent's question to the user via AskUserQuestion, then passing the user's answer back in a new Task invocation with accumulated context.

Pattern:
1. Invoke agent with context -> agent returns gate question
2. Relay question to user via AskUserQuestion
3. Invoke agent again with prior gate results + user answer -> agent returns next gate question
4. Repeat until all gates complete
5. Final invocation writes the report

This relay pattern preserves human judgment at each gate while leveraging the agent's domain expertise for question formulation and assessment.

## Key Insight

Interactive workshop agents and autonomous Task subagents are fundamentally different execution models. Workshop agents assume they control the conversation loop; Task subagents assume they run to completion. When combining them, the orchestrator (brainstorm skill) must act as a relay -- decomposing the workshop into per-gate subagent calls with user interaction between each one. This is more verbose but preserves the workshop's core property: human decisions at every gate.

## Tags
category: integration-issues
module: agents/product, skills/brainstorm
