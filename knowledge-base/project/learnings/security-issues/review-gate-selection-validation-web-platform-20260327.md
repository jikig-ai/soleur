---
title: Review gate selection validation against offered options
module: web-platform
date: 2026-03-27
problem_type: security_issue
component: authentication
symptoms:
  - "resolveReviewGate accepts arbitrary strings from WebSocket client"
  - "No server-side validation of selection against offered options"
  - "Potential prompt injection via review gate answer field"
root_cause: missing_validation
resolution_type: code_fix
severity: medium
tags: [review-gate, input-validation, defense-in-depth, websocket, prompt-injection]
synced_to: []
---

# Review Gate Selection Validation

## Problem

The `resolveReviewGate` function in `agent-runner.ts` accepted an arbitrary string from the WebSocket client as `selection` and passed it directly into `updatedInput.answer`. The options array was sent to the client but not stored server-side, so there was no way to validate the response.

A malicious authenticated client could send an oversized string, an empty string, or a prompt injection payload as a review gate response.

## Investigation

1. Identified the vulnerable code path: `review_gate_response` -> `resolveReviewGate` -> resolver -> `updatedInput.answer` -> SDK tool result
2. Audited all code paths where client-supplied strings reach the SDK (per security-fix-attack-surface-enumeration convention)
3. Confirmed `review_gate_response` was the only unvalidated channel -- user chat messages are the intended input channel, other paths are already validated

## Solution

Three-layer defense-in-depth:

**Layer 1 (transport):** Length guard in `ws-handler.ts` rejects `selection` exceeding `MAX_SELECTION_LENGTH` (256) before it reaches business logic. Throws into the existing catch block which runs `sanitizeErrorForClient`.

**Layer 2+3 (business logic):** `validateSelection` pure function in `review-gate.ts` checks both length and `options.includes(selection)`. Called by `resolveReviewGate` before resolving the promise.

```typescript
// review-gate.ts
export function validateSelection(
  options: string[],
  selection: string,
): void {
  if (selection.length > MAX_SELECTION_LENGTH) {
    throw new Error("Invalid review gate selection");
  }
  if (!options.includes(selection)) {
    throw new Error("Invalid review gate selection");
  }
}
```

**Options storage:** `ReviewGateEntry` interface bundles `resolve` callback with `options` array. Stored in `reviewGateResolvers` map at gate creation time.

**Options sanitization:** `toolInput.options` from the SDK is filtered with `typeof o === "string"` to prevent non-string elements from poisoning the allowlist.

**Retry semantics:** Invalid selection throws before `entry.resolve()` and `delete()`, so the gate remains pending for retry.

## Key Insight

When a data structure stores a callback (`resolve`) that will be called with user input, store the validation constraints alongside it. The `ReviewGateEntry` pattern (resolver + options) ensures validation data is always co-located with the resolution mechanism, making it impossible to resolve without validating.

## Prevention

- When adding new WebSocket message handlers that forward client input to internal systems, add input validation at both transport and business layers
- Use the same uniform error message for all rejection modes to prevent attackers from distinguishing failure causes (CWE-209 compliance)
- Store validation constraints at creation time, not at resolution time, to prevent TOCTOU gaps

## Related

- `knowledge-base/project/learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md` -- Review gate promise lifecycle (abort, timeout, cleanup)
- `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md` -- Error sanitization patterns
- `knowledge-base/project/learnings/2026-03-20-security-fix-attack-surface-enumeration.md` -- Attack surface enumeration convention

## Tags

category: security-issues
module: web-platform
