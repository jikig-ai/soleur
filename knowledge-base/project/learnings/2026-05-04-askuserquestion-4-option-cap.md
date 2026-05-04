---
title: AskUserQuestion caps `options` at 4 and auto-appends "Other"
date: 2026-05-04
category: integration-issues
component: brainstorm-skill
related_skills:
  - plugins/soleur/skills/brainstorm/SKILL.md
related_session: feat-harness-eval-stale-rules
---

# AskUserQuestion caps `options` at 4 and auto-appends "Other"

## Problem

During the `feat-harness-eval-stale-rules` brainstorm session, the Phase 0.1 user-impact framing call to `AskUserQuestion` failed with:

```
InputValidationError: [{ "origin": "array", "code": "too_big", "maximum": 4, "inclusive": true, "path": ["questions", 0, "options"], "message": "Too big: expected array to have <=4 items" }]
```

The brainstorm skill's Phase 0.1 instruction listed 7 example presets ("User data exposure", "Credential leak / auth bypass", "Billing surprise / payment error", "Data loss / corruption", "Trust breach / cross-tenant read", "No direct user impact", "Other"). The agent passed all 7 verbatim.

## Root cause

Two compounding issues:

1. **Schema cap.** The AskUserQuestion tool's JSONSchema declares `options.maxItems: 4`. The skill's prose listed 7 presets without flagging the cap.
2. **"Other" is auto-appended.** Per the tool description: "Users will always be able to select 'Other' to provide custom text input." Including "Other" in the operator's options list duplicates the runtime's auto-add — and worse, it consumes one of the 4 slots that should be a real preset.

The skill instruction's "(e.g., ... 'Other')" example was misleading on both counts.

## Solution

Edited `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.1 Step 1 to explicitly:

- Call out `maxItems: 4`.
- Note that "Other" is auto-appended by the runtime — do NOT include it in your options list.
- Instruct the agent to pick 3 presets most likely to fit the current feature and let auto-"Other" carry the long tail.

## Key insight

Skills that prescribe specific tool calls must reference the tool's schema constraints inline. "Pick 3 from this menu of 6, plus auto-Other" is a precise instruction; "(e.g., A, B, C, D, E, F, Other)" is not. Tool-call schema gaps in skill prose surface as runtime validation errors, not as static lint failures — so they only get caught after wasting a tool round-trip.

## Session Errors

- **AskUserQuestion called with 5 options on first attempt** — Recovery: collapsed to 3 options + auto-"Other". Prevention: the skill edit above now warns about `maxItems: 4` and the auto-"Other" duplication.

## Prevention strategies

- When writing skill instructions that prescribe tool calls, scan the tool's JSONSchema (visible in the LLM's tool list at runtime) for `maxItems`, `minItems`, `enum`, `pattern`, `maxLength` constraints. Mirror them inline.
- For AskUserQuestion specifically, the constraints worth flagging in any skill that uses it: `options.minItems: 2`, `options.maxItems: 4`, "Other" is auto-appended, `multiSelect: false` is the default, `header` is shown as a chip and is capped at 12 chars per the description.
