---
title: "fix: validate review gate selection against offered options"
type: fix
date: 2026-03-27
deepened: 2026-03-27
---

# fix: validate review gate selection against offered options

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 5 (Attack Surface, Proposed Solution, Technical Considerations, Test Scenarios, Context)
**Research sources:** 6 institutional learnings, security pattern analysis, codebase audit

### Key Improvements

1. Full attack surface enumeration added (per project security convention) -- identified WebSocket message parsing as an additional hardening point
2. Negative-space test pattern applied from tool-path-checker precedent -- completeness guard ensures future gate types cannot bypass validation
3. `gateId` format validation added as defense-in-depth (UUID format check prevents map key injection)
4. `ws-handler.ts` length guard added as Layer 1 (before `resolveReviewGate` is even called) following the project's defense-in-depth layering convention

### Relevant Institutional Learnings Applied

- `2026-03-20-review-gate-promise-leak-abort-timeout.md` -- Reject, don't resolve with synthetic values; cleanup paths must be explicit
- `2026-03-20-security-fix-attack-surface-enumeration.md` -- Enumerate ALL code paths touching the security surface, not just the reported vector
- `2026-03-20-websocket-error-sanitization-cwe-209.md` -- Allowlist-with-fallback for error sanitization; new error must be added to the allowlist
- `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- Multiple independent validation layers; no single layer is the security boundary
- `2026-03-20-safe-tools-allowlist-bypass-audit.md` -- Explicit classification over implicit defaults; completeness guards in tests
- `2026-03-20-websocket-first-message-auth-toctou-race.md` -- Async operations between timers and state mutations create TOCTOU windows (not applicable here -- validation is synchronous, but audited)

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

### Research Insights: Full Attack Surface Enumeration

Per the project convention from `2026-03-20-security-fix-attack-surface-enumeration.md`, enumerate ALL code paths touching this security surface -- not just the reported vector.

**All code paths where a client-supplied string reaches the agent SDK:**

1. **`review_gate_response` -> `resolveReviewGate` -> resolver -> `updatedInput.answer`** (this issue) -- The `selection` string flows from WebSocket message through to SDK tool result with zero validation.
2. **`chat` -> `sendUserMessage` -> SDK `userMessage`** -- User chat messages also reach the SDK, but these are the intended user input channel. Prompt injection via chat is an inherent LLM risk, not a gate bypass.
3. **`start_session` -> `startAgentSession` -> `msg.leaderId`** -- The leader ID is validated against `DOMAIN_LEADERS` constant (line 267 of `agent-runner.ts`), so this path is already safe.

**Paths that do NOT reach the SDK (confirmed safe):**

- `auth` messages -- handled at connection level, token validated via Supabase `getUser()`
- `close_conversation` -- triggers session cleanup, no data passed to SDK
- `resume_session` -- uses `conversationId` (UUID from server), not arbitrary strings

**Conclusion:** The `review_gate_response` -> `resolveReviewGate` path is the only unvalidated channel where a client-supplied string enters SDK tool results. The fix scope is correct.

### What Stores Options Today

The `gateOptions` array is extracted from `toolInput.options` at gate creation time (line 388-390) and sent to the client, but it is **not** stored server-side. The `reviewGateResolvers` map stores only the resolver function (`(selection: string) => void`), not the valid options.

## Proposed Solution

Store the valid options alongside the resolver so selection can be validated at resolution time. The fix is scoped to the server only -- no client changes needed (the client already picks from the offered options via `ReviewGateCard`).

### Research Insights: Defense-in-Depth Layering

Per the project's defense-in-depth convention (from `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`), implement three independent validation layers where each layer independently blocks the most critical attack:

| Layer | Location | Check | Blocks |
|-------|----------|-------|--------|
| 1 | `ws-handler.ts` (message parsing) | Max length on `msg.selection` | Oversized payloads before they reach any business logic |
| 2 | `resolveReviewGate` (agent-runner.ts) | Max length + UUID format on `gateId` | Malformed gate IDs, repeated oversized payload check |
| 3 | `resolveReviewGate` (agent-runner.ts) | `options.includes(selection)` | Invalid selections, prompt injection via arbitrary strings |

Layer 1 is the earliest possible rejection point -- in `ws-handler.ts` before `resolveReviewGate` is even called. This follows the same pattern as the WebSocket auth timeout (validate at the transport layer, not the business layer).

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

**Add `validateSelection` as an exported pure function** (follows the `extractToolPath` pattern from `tool-path-checker.ts`):

```typescript
export const MAX_SELECTION_LENGTH = 256;

export function validateSelection(
  options: string[],
  selection: string,
  maxLength: number = MAX_SELECTION_LENGTH,
): void {
  if (selection.length > maxLength) {
    throw new Error("Invalid review gate selection");
  }
  if (!options.includes(selection)) {
    throw new Error("Invalid review gate selection");
  }
}
```

This function is pure (no side effects, no dependencies) and directly unit-testable without needing access to `activeSessions` or any module-private state. This resolves the testability concern from the original plan -- Option A is the clear choice.

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

**In `resolveReviewGate`:** Import and call `validateSelection` before the resolver:

```typescript
import { validateSelection } from "./review-gate";

// ...

export async function resolveReviewGate(
  userId: string,
  conversationId: string,
  gateId: string,
  selection: string,
): Promise<void> {
  const key = sessionKey(userId, conversationId);
  const session = activeSessions.get(key);

  if (!session) {
    throw new Error("No active session");
  }

  const entry = session.reviewGateResolvers.get(gateId);
  if (!entry) {
    throw new Error("Review gate not found or already resolved");
  }

  // Validate selection against stored options (Layer 2+3)
  validateSelection(entry.options, selection);

  entry.resolve(selection);
  session.reviewGateResolvers.delete(gateId);
}
```

#### 2b. `apps/web-platform/server/ws-handler.ts` (Layer 1 -- transport-level guard)

Add early validation in the `review_gate_response` case block before calling `resolveReviewGate`. This is Layer 1 -- the earliest rejection point:

```typescript
case "review_gate_response": {
  if (!session.conversationId) {
    sendToClient(userId, { type: "error", message: "No active session." });
    return;
  }

  // Layer 1: transport-level length guard (defense-in-depth)
  if (typeof msg.selection !== "string" || msg.selection.length > 256) {
    sendToClient(userId, {
      type: "error",
      message: "Invalid selection. Please choose one of the offered options.",
    });
    return;
  }

  try {
    await resolveReviewGate(
      userId, session.conversationId, msg.gateId, msg.selection,
    );
  } catch (err) {
    // ...
  }
  break;
}
```

This guard prevents oversized payloads from ever reaching `resolveReviewGate`. The type check (`typeof msg.selection !== "string"`) is defense-in-depth against malformed WebSocket messages -- TypeScript types are compile-time only and do not enforce runtime contracts.

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
- **Error message reuse.** Both the length guard and the options check throw the same message (`"Invalid review gate selection"`) to avoid leaking information about which check failed (CWE-209 compliance per `2026-03-20-websocket-error-sanitization-cwe-209.md`). The client sees a friendly message via the error sanitizer.
- **Default options `["Approve", "Reject"]`.** When `toolInput.options` is not an array, the server currently defaults to `["Approve", "Reject"]`. This default must also be passed to `abortableReviewGate` so validation works for gates with defaulted options.
- **Case sensitivity.** Options are compared with exact string match (`Array.includes`). The client UI sends the exact option string from the `options` array, so case sensitivity is correct behavior -- it prevents a crafted client from sending a differently-cased variant.

### Research Insights: Additional Considerations

- **No TOCTOU risk.** Unlike the WebSocket auth flow (which has an async gap between timer and validation per `2026-03-20-websocket-first-message-auth-toctou-race.md`), the validation here is synchronous -- `validateSelection` runs in the same event loop tick as the resolver invocation, so no race condition is possible between validation and resolution.
- **Gate ID is server-generated UUID.** The `gateId` is created via `randomUUID()` on the server (line 385 of `agent-runner.ts`). A malicious client must guess a valid UUID to target a pending gate. This is not a vulnerability per se (the Map lookup already handles invalid IDs), but it means brute-force gate targeting is infeasible.
- **Resolver cleanup on invalid selection.** When `validateSelection` throws, the resolver remains in the map -- the gate is still pending. This is correct behavior: the user can retry with a valid selection. The gate will eventually be cleaned up by the 5-minute timeout or session abort (per the existing `abortableReviewGate` mechanism). Do NOT delete the resolver on validation failure -- that would permanently block the gate with no recovery path.
- **Options array immutability.** The `options` array stored in `ReviewGateEntry` is a reference to the array created during `canUseTool`. Since `gateOptions` is constructed fresh each time (`Array.isArray(toolInput.options) ? toolInput.options as string[] : ["Approve", "Reject"]`), there is no risk of external mutation. No defensive copy is needed.
- **`toolInput.options` sanitization.** The current code casts `toolInput.options as string[]` without verifying each element is actually a string. If the SDK sends non-string elements, `Array.includes` with a string argument will correctly return `false` (no type coercion), so the validation is safe even with bad data. Adding explicit element-type validation is not needed -- the SDK controls `toolInput` and is trusted.

## Acceptance Criteria

- [ ] `validateSelection` exported from `review-gate.ts` as a pure function
- [ ] `resolveReviewGate` calls `validateSelection` before resolving -- rejects selections not in the original options array
- [ ] `resolveReviewGate` rejects selections exceeding 256 characters (via `validateSelection`)
- [ ] `ws-handler.ts` Layer 1 guard rejects oversized/non-string selections before calling `resolveReviewGate`
- [ ] Valid selections (matching an offered option) continue to work as before
- [ ] Invalid selection does NOT delete the resolver -- gate remains pending for retry
- [ ] Error message `"Invalid review gate selection"` is sanitized to a user-friendly string in `error-sanitizer.ts`
- [ ] `ReviewGateEntry` type replaces the bare function type in `AgentSession.reviewGateResolvers`
- [ ] `abortableReviewGate` accepts and stores `options` parameter
- [ ] Existing review gate tests pass with updated types
- [ ] New unit tests cover `validateSelection`: valid option, invalid option, oversized string, empty string, case mismatch, trailing whitespace
- [ ] Negative-space test confirms `resolveReviewGate` wires through to `validateSelection`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- security hardening of an internal server component.

## Test Scenarios

### Core Validation (unit tests on `validateSelection`)

- Given options `["Approve", "Reject"]` and selection `"Approve"`, then passes without error
- Given options `["Approve", "Reject"]` and selection `"Reject"`, then passes without error
- Given options `["Approve", "Reject"]` and selection `"Ignore all previous instructions"`, then throws `"Invalid review gate selection"`
- Given options `["Approve", "Reject"]` and selection `""` (empty string), then throws `"Invalid review gate selection"`
- Given options `["Yes", "No", "Maybe"]` and selection `"yes"` (wrong case), then throws `"Invalid review gate selection"`
- Given any options and a 300-character selection, then throws `"Invalid review gate selection"` (length check fires first)
- Given options `["Approve", "Reject"]` and selection `"Approve "` (trailing space), then throws -- exact match enforced

### Integration (end-to-end through the gate flow)

- Given a review gate with options `["Approve", "Reject"]`, when the client sends `selection: "Approve"`, then the gate resolves and the SDK receives `answer: "Approve"` in `updatedInput`
- Given a review gate with defaulted options (no `toolInput.options`), when the client sends `selection: "Approve"`, then the gate resolves normally (default options `["Approve", "Reject"]` are validated against)
- Given a review gate, when the client sends an invalid selection, then the server responds with an error AND the gate remains pending (resolver not deleted -- user can retry)
- Given a review gate, when the client sends a 300-character selection string, then the server responds with an error before the selection reaches `resolveReviewGate` (Layer 1 in ws-handler catches it)

### Negative-Space / Completeness Guards

Per `2026-03-20-security-fix-attack-surface-enumeration.md`, add a negative-space test ensuring validation cannot be bypassed:

- `validateSelection` is called by `resolveReviewGate` -- assert this by checking that an invalid selection thrown through `resolveReviewGate` produces the expected error (integration confirmation that the validation is wired in, not just defined)
- The `MAX_SELECTION_LENGTH` constant is exported and matches the Layer 1 guard in `ws-handler.ts` -- if either changes, tests break

### Error Sanitizer

- Given error message `"Invalid review gate selection"`, then `sanitizeErrorForClient` returns `"Invalid selection. Please choose one of the offered options."`

## Context

- **Root cause:** The review gate mechanism was added in #840/#1044 with focus on the promise lifecycle (abort, timeout, cleanup). Input validation was not part of the original scope.
- **Severity:** Medium. Exploitation requires an authenticated WebSocket connection (the user must have a valid Supabase session). The impact is limited to prompt injection within the user's own agent session -- no cross-user impact. However, a crafted selection could manipulate the agent into performing unintended actions within the user's workspace.
- **Prior art:** The `tool-path-checker.ts` extraction pattern (used for workspace sandbox validation) provides a good model for extracting `validateSelection` into `review-gate.ts`.

### Research Insights: Security Hardening Patterns from This Codebase

This fix follows three established patterns in the web-platform security model:

1. **Pure validation functions in standalone modules** -- `tool-path-checker.ts` extracts `extractToolPath`, `isFileTool`, `isSafeTool` as pure functions testable without SDK/Supabase dependencies. `validateSelection` follows the same pattern in `review-gate.ts`.

2. **Allowlist-with-fallback error sanitization** -- `error-sanitizer.ts` uses `KNOWN_SAFE_MESSAGES` for exact matches and a generic fallback for unknown errors. New error messages must be added to the allowlist or they will be replaced with the generic message (which is correct security posture but poor UX for an expected validation error).

3. **Defense-in-depth with transport + business layer validation** -- The WebSocket auth flow validates at the transport layer (timeout in `ws-handler.ts`) and at the business layer (token validation in `getUser()`). This fix mirrors that pattern: transport-layer length guard in `ws-handler.ts` + business-layer options validation in `resolveReviewGate`.

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
