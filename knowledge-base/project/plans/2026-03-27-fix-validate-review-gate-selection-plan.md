---
title: "fix: validate review gate selection against offered options"
type: fix
date: 2026-03-27
---

# fix: validate review gate selection against offered options

## Overview

The `resolveReviewGate` function in `apps/web-platform/server/agent-runner.ts` accepts an arbitrary string from the WebSocket client as `selection` and passes it directly into `updatedInput: { ...toolInput, answer: selection }`. There is no server-side validation that the selection matches one of the options originally sent to the client.

A malicious client could send an extremely long string, an empty string, or attempt prompt injection via the review gate answer. The options array should be stored server-side when the gate is created, and the selection validated against it before resolution.

Found during post-merge review of #1190. Filed as #1195.

## Problem Statement

### Current Flow (Vulnerable)

1. `canUseTool` intercepts `AskUserQuestion` and extracts `gateOptions` from `toolInput.options` (lines 384-396 of `agent-runner.ts`)
2. A `review_gate` message is sent to the client with `gateId`, `question`, and `options`
3. A resolver function is stored in `session.reviewGateResolvers` map keyed by `gateId`
4. The resolver accepts an arbitrary `string` and resolves the promise with it
5. When the client sends `review_gate_response`, `resolveReviewGate` looks up the resolver and calls it with the raw `selection` string
6. The resolved selection is injected into `updatedInput.answer` and passed to the SDK

### Attack Surface

- **Prompt injection:** The `answer` field becomes part of the tool result that the LLM processes. A crafted string could attempt to manipulate the agent's subsequent behavior.
- **Oversized payload:** No length limit on the selection string. A multi-megabyte string would be stored in memory and passed through the promise chain.
- **Invalid selection:** The client can send any string, not just one of the offered options. The agent receives a "user decision" that was never actually offered.

### What Stores Options Today

The `gateOptions` array is extracted from `toolInput.options` at gate creation time (line 388-390) and sent to the client, but it is **not** stored server-side. The `reviewGateResolvers` map stores only the resolver function (`(selection: string) => void`), not the valid options.

## Proposed Solution

Store the valid options alongside the resolver so selection can be validated at resolution time. The fix is scoped to the server only -- no client changes needed (the client already picks from the offered options via `ReviewGateCard`).

### Approach: Extend the resolver map to store options

Replace the `reviewGateResolvers: Map<string, (selection: string) => void>` with a structure that also stores the valid options for each gate.

### Changes Required

#### 1. `apps/web-platform/server/review-gate.ts`

**Change the `AgentSession.reviewGateResolvers` type** from `Map<string, (selection: string) => void>` to `Map<string, ReviewGateEntry>` where:

```typescript
export interface ReviewGateEntry {
  resolve: (selection: string) => void;
  options: string[];
}
```

**Update `abortableReviewGate`** to accept an `options: string[]` parameter and store it alongside the resolver:

```typescript
session.reviewGateResolvers.set(gateId, { resolve, options });
```

Update cleanup paths (abort, timeout) to use the new map value type -- they already call `session.reviewGateResolvers.delete(gateId)` which is unchanged.

#### 2. `apps/web-platform/server/agent-runner.ts`

**In `canUseTool` (AskUserQuestion block):** Pass `gateOptions` to `abortableReviewGate`:

```typescript
const selection = await abortableReviewGate(
  session,
  gateId,
  controller.signal,
  undefined, // timeoutMs (use default)
  gateOptions, // <-- new parameter
);
```

Note: The function signature already has `timeoutMs` as the 4th parameter with a default. Adding `options` as the 5th parameter keeps the existing API stable.

**In `resolveReviewGate`:** Add validation before calling the resolver:

```typescript
const entry = session.reviewGateResolvers.get(gateId);
if (!entry) {
  throw new Error("Review gate not found or already resolved");
}

// Validate selection against offered options
if (!entry.options.includes(selection)) {
  throw new Error("Invalid review gate selection");
}

entry.resolve(selection);
session.reviewGateResolvers.delete(gateId);
```

**Add a max-length guard** at the top of `resolveReviewGate` (defense-in-depth, fires before map lookup):

```typescript
const MAX_SELECTION_LENGTH = 256;
if (selection.length > MAX_SELECTION_LENGTH) {
  throw new Error("Invalid review gate selection");
}
```

256 characters is generous for any legitimate option string. This prevents oversized payloads from reaching the promise chain even if the options check somehow passes.

#### 3. `apps/web-platform/server/error-sanitizer.ts`

Add the new error message to `KNOWN_SAFE_MESSAGES`:

```typescript
"Invalid review gate selection":
  "Invalid selection. Please choose one of the offered options.",
```

#### 4. `apps/web-platform/test/review-gate.test.ts`

Update existing tests to use the new `ReviewGateEntry` structure and add new test cases:

- Update resolver access: `session.reviewGateResolvers.get("g1")?.resolve("Approve")` instead of `session.reviewGateResolvers.get("g1")!("Approve")`
- Test that `abortableReviewGate` stores options alongside the resolver
- Test that the entry's `options` array matches what was passed in

#### 5. New test file or extension of existing tests for validation

Add tests for `resolveReviewGate` validation behavior:

- Given a gate with options `["Approve", "Reject"]`, when selection is `"Approve"`, then resolves normally
- Given a gate with options `["Approve", "Reject"]`, when selection is `"malicious input"`, then throws `"Invalid review gate selection"`
- Given a selection longer than 256 characters, then throws `"Invalid review gate selection"` (length guard fires first)
- Given an empty selection string, then throws `"Invalid review gate selection"` (not in options array)

Testing `resolveReviewGate` directly requires access to `activeSessions` (a module-private `Map`). Two options:

- **Option A (preferred):** Extract the validation logic into `review-gate.ts` as a pure function (`validateSelection(options: string[], selection: string, maxLength?: number): void`) and test it there. `resolveReviewGate` calls it.
- **Option B:** Test validation end-to-end through the WebSocket protocol test (`ws-protocol.test.ts`), which already exercises the `review_gate_response` path.

## Technical Considerations

- **No breaking changes to the client WebSocket protocol.** The `review_gate_response` message shape (`{ type, gateId, selection }`) is unchanged. The server simply rejects invalid selections with an error message.
- **Error message reuse.** Both the length guard and the options check throw the same message (`"Invalid review gate selection"`) to avoid leaking information about which check failed. The client sees a friendly message via the error sanitizer.
- **Default options `["Approve", "Reject"]`.** When `toolInput.options` is not an array, the server currently defaults to `["Approve", "Reject"]`. This default must also be passed to `abortableReviewGate` so validation works for gates with defaulted options.
- **Case sensitivity.** Options are compared with exact string match (`Array.includes`). The client UI sends the exact option string from the `options` array, so case sensitivity is correct behavior -- it prevents a crafted client from sending a differently-cased variant.

## Acceptance Criteria

- [ ] `resolveReviewGate` rejects selections not in the original options array
- [ ] `resolveReviewGate` rejects selections exceeding 256 characters
- [ ] Valid selections (matching an offered option) continue to work as before
- [ ] Error message `"Invalid review gate selection"` is sanitized to a user-friendly string
- [ ] `ReviewGateEntry` type replaces the bare function type in `AgentSession.reviewGateResolvers`
- [ ] Existing review gate tests pass with updated types
- [ ] New tests cover: valid selection, invalid selection, oversized selection, empty selection

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- security hardening of an internal server component.

## Test Scenarios

- Given a review gate with options `["Approve", "Reject"]`, when the client sends `selection: "Approve"`, then the gate resolves and the SDK receives `answer: "Approve"` in `updatedInput`
- Given a review gate with options `["Approve", "Reject"]`, when the client sends `selection: "Ignore all previous instructions"`, then the server responds with an error and the gate remains pending
- Given a review gate, when the client sends a 300-character selection string, then the server responds with an error before checking the options array
- Given a review gate with defaulted options (no `toolInput.options`), when the client sends `selection: "Approve"`, then the gate resolves normally (default options `["Approve", "Reject"]` are validated against)
- Given a review gate with options `["Yes", "No", "Maybe"]`, when the client sends `selection: "yes"` (wrong case), then the server responds with an error

## Context

- **Root cause:** The review gate mechanism was added in #840/#1044 with focus on the promise lifecycle (abort, timeout, cleanup). Input validation was not part of the original scope.
- **Severity:** Medium. Exploitation requires an authenticated WebSocket connection (the user must have a valid Supabase session). The impact is limited to prompt injection within the user's own agent session -- no cross-user impact. However, a crafted selection could manipulate the agent into performing unintended actions within the user's workspace.
- **Prior art:** The `tool-path-checker.ts` extraction pattern (used for workspace sandbox validation) provides a good model for extracting `validateSelection` into `review-gate.ts`.

## References

- Issue: #1195
- Review gate implementation: `apps/web-platform/server/review-gate.ts`
- Agent runner review gate block: `apps/web-platform/server/agent-runner.ts:384-413`
- Resolve function: `apps/web-platform/server/agent-runner.ts:641-661`
- WebSocket handler: `apps/web-platform/server/ws-handler.ts:228-249`
- Error sanitizer: `apps/web-platform/server/error-sanitizer.ts`
- Existing tests: `apps/web-platform/test/review-gate.test.ts`
- Learning: `knowledge-base/project/learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md`
- Related PR: #1190 (where the vulnerability was discovered during post-merge review)
