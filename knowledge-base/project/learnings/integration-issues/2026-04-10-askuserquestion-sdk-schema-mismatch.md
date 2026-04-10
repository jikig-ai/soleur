---
module: WebPlatform
date: 2026-04-10
problem_type: integration_issue
component: service_object
symptoms:
  - "Review gate cards always show 'Agent needs your input' instead of the actual question"
  - "Clicking review gate buttons throws errors or has no visible effect"
  - "Review gate cards never disappear after responding"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [review-gate, askuserquestion, claude-agent-sdk, websocket, schema-mismatch]
---

# Learning: AskUserQuestion SDK Schema Mismatch

## Problem

The "Agent needs your Input" review gate UX had three bugs: no question
description shown, buttons not working, and cards never disappearing. All
three were caused by a single root cause.

## Root Cause

The server-side `canUseTool` callback in `agent-runner.ts` read
`toolInput.question` and `toolInput.options` (flat fields), but the Claude
Agent SDK v0.2.80 sends `toolInput.questions[0].question` and
`toolInput.questions[0].options` (nested array of `{ label, description }`
objects). The response format was also wrong: the code returned
`{ ...toolInput, answer: selection }` but the SDK expects
`{ questions, answers: { [questionText]: selection } }`.

Because the field names didn't match, the server always fell back to
`"Agent needs your input"` and `["Approve", "Reject"]`, silently
discarding the agent's actual question and options. The wrong response
format caused the SDK to error after the user responded.

## Solution

1. Extracted `extractReviewGateInput()` and `buildReviewGateResponse()`
   as pure functions in `review-gate.ts` for testability
2. `extractReviewGateInput` reads `toolInput.questions[0]` first, falls
   back to `toolInput.question`/`toolInput.options` for backward
   compatibility
3. `buildReviewGateResponse` returns the correct SDK format
   `{ questions, answers: { [q]: selection } }` for new schema
4. Extended `WSMessage` and `ChatMessage` types with `header`,
   `descriptions`, `gateId` (on errors), `resolved`, `selectedOption`,
   and `gateError` fields
5. `ReviewGateCard` now shows header tags, option descriptions, collapses
   after resolution, and displays errors inline with retry

## Key Insight

When integrating with an SDK's tool interception (`canUseTool`), always
verify the actual runtime schema against type definitions — don't assume
flat field names. The SDK's type definitions (`sdk-tools.d.ts`) were the
authoritative source, not the intuitive field names. Extract schema
parsing into testable pure functions so mismatches are caught by unit
tests, not by users.

## Session Errors

1. **`npx vitest` run from wrong directory** — Running vitest from the
   worktree root instead of `apps/web-platform/` caused a rolldown native
   binding error (missing `@rolldown/binding-linux-x64-gnu`). **Recovery:**
   Re-ran from `apps/web-platform/` directory. **Prevention:** Always
   `cd` to the app directory containing `vitest.config.ts` before running
   tests. The worktree root has no vitest config.

2. **`Write` tool on temp files without reading** — Attempted to use the
   Write tool on `/tmp/review-finding-*.md` files that hadn't been read.
   **Recovery:** Used `cat` via Bash tool instead. **Prevention:** For
   temp files that don't exist yet, use Bash `cat > file << 'EOF'`
   instead of the Write tool (which requires a prior Read).

3. **Wrong script path for ralph loop** — Tried
   `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` but it
   lives at `./plugins/soleur/scripts/setup-ralph-loop.sh`. **Recovery:**
   Corrected the path on second attempt. **Prevention:** The script is a
   repo-level utility, not skill-specific — check `plugins/soleur/scripts/`
   first.

## Tags

category: integration-issues
module: WebPlatform
