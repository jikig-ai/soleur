---
title: Task subagents inherit prompt text only — no image content blocks
date: 2026-05-12
category: best-practices
module: claude-code-sdk
tags: [task-tool, subagents, multimodal, prompt-contract, linear-fetch]
source_session: Phase 0 verification for feat-linear-issue-image-context
related_pr: "#3631"
related_issue: "#3635"
---

# Task subagents inherit prompt text only — no image content blocks

## Context

The `/soleur:linear-fetch` skill design (PR #3631) needed to verify a load-bearing assumption: when a parent conversation has image content blocks (from an MCP tool like `mcp__linear-server__extract_images` or from a `Read` of a PNG file), do those image blocks transfer to a `Task` subagent invoked from that parent?

The answer determines whether `/soleur:one-shot` Step 0a (Linear preflight) should fetch images in the parent, the subagent, or both. The plan committed to: parent fetches once, subagent receives only the `persist_safe_summary` text via `$ARGUMENTS` substitution in the prompt template. This learning is the verification.

## Verification

**The Task tool's prompt parameter is `string`-typed.**

From the Claude Code harness tool schema (the canonical contract the SDK enforces at the tool boundary):

```json
{
  "name": "Agent",
  "parameters": {
    "properties": {
      "prompt": {
        "description": "The task for the agent to perform",
        "type": "string"
      },
      "description": { "type": "string" },
      "subagent_type": { "type": "string" },
      ...
    },
    "required": ["description", "prompt"]
  }
}
```

There is no `images`, `content`, `content_blocks`, or `attachments` parameter. The interface accepts a single string. Anything the parent has in its own conversation — image content blocks from MCP tools, file content from `Read` calls, prior tool results — is NOT forwarded to the subagent unless it is encoded into the `prompt` string the parent constructs.

This is by design. Subagents are isolation boundaries: each subagent starts with its own message history (one user message containing the prompt string), runs to completion, returns a final assistant message, and is discarded. The parent's accumulated context does not bleed across.

## Consequence for `/soleur:linear-fetch` wiring

- The parent (`/soleur:one-shot` runner, `/soleur:brainstorm` runner) is the ONLY place image content blocks live after `extract_images` returns.
- When the parent spawns a Task subagent (one-shot's plan-and-deepen subagent at Steps 1–2; brainstorm's domain-leader subagents at Phase 0.5), the subagent receives a text prompt only. Embedding `persist_safe_summary` in that prompt is the correct mechanism.
- The plan's Research Reconciliation row for FR9 ("single fetch in the parent at Step 0a; subagent prompt substitutes `$ARGUMENTS` with `persist_safe_summary`; no second fetch") is the correct architecture given this contract.
- The plan's Research Reconciliation row for FR10 (brainstorm Phase 0.4 placement; leader prompts get persist-safe-summary text only; the brainstorm parent conversation retains the images) is correct for the same reason.

## Consequence for future multimodal skills

Any future skill that needs image context inside a Task subagent must:

1. Fetch the image at the boundary closest to where it is consumed (i.e., inside the subagent, not in the parent), OR
2. Encode the image content into the prompt text as a path the subagent can `Read` itself (i.e., write the image to a temp file in the parent, pass the path in the prompt string, have the subagent `Read` it).

Option 2 is the only way to "share" image content across the Task boundary, and it requires a filesystem hop the `/soleur:linear-fetch` design explicitly rejects (TR5: no filesystem writes for image data). For Linear-image use cases, the design accepts that subagents work with the persist-safe text and that the parent retains the visual context.

## Why this matters

A misread of this contract would have produced one of two failures:

- **Naive overshare:** fetch in the parent, expect subagent to "see" the images. Subagent plans the implementation blind — same failure mode as today, except now the redaction has fired and the persist-safe summary is the only signal. The skill ships with no behavioral difference for the load-bearing one-shot path.
- **Naive overfetch:** fetch in both parent AND subagent. Doubles the MCP round-trip cost, doubles the chance of token-expired races, doubles the surface area for a redaction bug to leak a URL into a subagent's prompt log.

The plan's choice (single parent fetch, text-only subagent) avoids both. This learning documents the contract that makes it correct.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-12-feat-linear-issue-image-context-plan.md` (Research Reconciliation FR9/FR10)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-linear-issue-image-context-brainstorm.md` (Capability Gap #3 — first multimodal-MCP-passthrough skill)
- Spec: `knowledge-base/project/specs/feat-linear-issue-image-context/spec.md` (FR9, FR10, R6 in Risks)
