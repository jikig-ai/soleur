# Learning: a consent/approval gate that shares an untagged resolver registry with another gate type is bypassable by the sibling's response frame

## Problem

The Concierge first-run consent **soft-gate** (hold a Bash command until the workspace owner acks a disclosure) was implemented by reusing the existing review-gate hold primitive: the held command awaited `abortableReviewGate(...)`, registered in the shared `_ccBashGates` registry keyed only by `userId:conversationId:gateId`. The owner-checked consent write (`set_workspace_autonomous_ack`) lived ONLY in the `autonomous_disclosure_response` WS handler.

Because the registry entry carried **no discriminator** of gate type, `resolveCcBashGate(gateId, selection)` resolved whatever matched the key. A `review_gate_response` frame carrying the held **disclosure** gate's id + `"Got it"` released the held command **without** ever calling `setAutonomousAck` — so the command executed, no consent timestamp was written, and the disclosure banner never had to be shown. A client could auto-answer every disclosure with a `review_gate_response` and silently auto-run all held commands. The DB ack RPC was correctly owner-gated — but the **command release was decoupled from the ack write**, and the two were separable through the shared registry. tsc + the unit suite (which mocked `abortableReviewGate` and never drove the ws-handler release) were green; only multi-agent review caught it.

## Solution

Two layers:
1. **Tag the gate.** Add `kind: "review" | "autonomous_disclosure"` to the registry record; `resolveCcBashGate` takes an `expectedKind` and refuses (`if (record.kind !== expectedKind) return false`) to resolve a mismatched gate. Each response handler passes its own kind, so a cross-frame response cannot release the sibling gate.
2. **Make the side effect load-bearing at the enforcement point (defense-in-depth).** The disclosure-hold path re-verifies the persisted ack (`verifyAutonomousAck()`) AFTER the gate resolves "proceed" and BEFORE `allow()`; a release that didn't persist consent re-holds instead of allowing.

## Key Insight

When you reuse a generic hold/resolve primitive for a NEW gate type that carries a **type-specific side effect** (a consent write, an audit row, a payment capture), the shared resolver registry becomes a confused-deputy surface: the response frame for gate type A can resolve a held gate of type B, skipping B's side effect. The auth on the side-effect RPC does NOT protect you — the attacker doesn't call the RPC, they release the command through the *other* gate's frame. **Bind the release to the side effect:** discriminate gates by kind and reject cross-kind resolution, AND re-assert the invariant (the side effect actually happened) at the point of consequence, not just trust the response-frame type.

Related fail-open in the same feature (worth its own reflex): `autonomousAckAtMs = Date.parse(ackStr)` then a downstream `=== null` check — `NaN == null` is `false`, so an unparseable timestamp was treated as "acked" and failed **open**. Any string→number coercion feeding a fail-closed gate needs `Number.isFinite(x) ? x : null`. A fail-closed contract enforced at the RPC/resolver layer is lost the moment a later coercion silently produces `NaN`/`undefined`.

## Prevention

- **Review-spawn prompt for any new approval/consent/hold gate:** instruct the security + architecture agents to enumerate EVERY response frame that can resolve the shared registry and confirm each cannot release a gate whose type-specific side effect it doesn't perform. Drive the *cross-frame* path in a test (the same-frame test passes vacuously).
- Tag shared resolver registries by kind; reject cross-kind resolution.
- Re-verify the type-specific invariant at the enforcement boundary (e.g. re-read the consent row before `allow()`), don't trust the response-frame type.
- Guard every coercion that feeds a fail-closed gate with `Number.isFinite`/explicit null — a `NaN`/`undefined` that compares falsely against your `== null` sentinel converts fail-closed into fail-open.

## Session Errors

- **Consent-gate bypass via untagged shared gate registry** (P1). Recovery: kind-tagged gates + `expectedKind` refusal + `verifyAutonomousAck` re-check. Prevention: this learning; route-to-definition bullet added to review defect-classes.
- **`Date.parse` NaN fail-open** (P2): unparseable ack treated as acked. Recovery: `Number.isFinite` guard → null/HOLD. Prevention: coercion-into-fail-closed-gate reflex above.
- **Stale frozen in-session snapshot** (P1): `autonomousAckAt` resolved once at cold-start, never updated after the ack, so every subsequent command re-held. Recovery: mutable per-conversation ack-posture cell flipped on ack. Prevention: long-lived dep closures over mutable state need a write-back path, not a frozen snapshot.
- **Chip posture client-heuristic while a schema comment claimed a non-existent server `posture` field** (P1). Recovery: implement the real server→client posture frame; feed the chip from it. Prevention: a comment asserting "the server pushes X" is not evidence X exists — grep for the field.
- **Existing-workspace opt-out shipped as dead code** (P3): the banner arm + handler existed but the server emit was never wired. Recovery: wired the `!autonomous && ack==null && owner` emit. Prevention: a UI affordance with no reachable server emit is dead — trace the producer.
- (Forwarded) Pencil `save` wrote to the bare root; Task tool unavailable in the planning subagent env — both handled, known/environmental.

## Tags
category: security-issues
module: apps/web-platform/server/cc-dispatcher.ts, server/permission-callback.ts, server/ws-handler.ts
related: [[2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path]]
