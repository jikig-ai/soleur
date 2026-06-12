# Learning: mirroring a monolithic precedent across a two-layer seam — emit raw, debounce/label at the transport boundary

## Problem

#5214: the Concierge (cc / `soleur-go`) chat surface did not forward SDK
`tool_progress` heartbeats to the client, so the 45s client stuck-watchdog
(`STUCK_TIMEOUT_MS`) was not heartbeat-fed during a long single tool. On a
>90s tool the client timed out twice and flipped the chat bubble to a terminal
`error` state, then rendered the real answer in a new bubble below the orphaned
error bubble.

The issue prescribed a **one-line fix**: "add a `tool_progress` WS forward in
`cc-dispatcher.ts` (~line 2107) alongside the existing stream/tool_use forwards."
That premise was wrong in two ways, and taking it literally would have shipped a
no-op (a `sendToClient` line with nothing to call).

## Solution

Two traces falsified the issue's premise before any code was written:

1. **`cc-dispatcher.ts` does not iterate SDK messages itself.** It wires
   `DispatchEvents` callbacks (`onText`/`onToolUse`/…) into an `events` object
   (~line 2448) that it hands to the runner. The line-2107 anchor pointed into a
   helper region, not the forward site.
2. **The runner (`soleur-go-runner.ts`) owned the SDK loop and swallowed
   `tool_progress`.** Its `tool_progress` branch was a *pure re-arm* of the idle
   watchdog that read no fields and emitted no event. So nothing existed for the
   dispatcher to forward.

The real fix was **two-layer**, mirroring the legacy `agent-runner.ts:1889-1948`
forward but split across the runner/dispatcher seam:

- **Runner layer:** add an optional `onToolProgress?` to `DispatchEvents` and
  EMIT it (shape-guarded) from the `tool_progress` branch, after the existing
  `armRunaway` re-arm. The runner emits the **RAW** SDK fields at **SDK cadence
  (un-debounced)**.
- **Dispatcher layer:** wire `events.onToolProgress` → `sendToClient(...)`,
  applying the **5s per-`toolUseId` debounce** and routing the raw `toolName`
  through `buildToolLabel` (shared `buildToolProgressWSMessage`, #2138 invariant).

Everything downstream (the `tool_progress` WS variant, zod schema, ws-client
passthrough, and the `chat-state-machine.ts:490` consumer) already existed for
the agent-runner surface and was reused unchanged.

## Key Insight

**When you mirror a monolithic precedent (one inline block doing N things) into
a codebase that has an architectural seam the precedent lacks, do NOT copy the
monolith — split the responsibilities across the seam.** `agent-runner.ts`
inlines emit + debounce + label in one closure because it has no runner/dispatcher
seam. The cc path does: the runner is **surface-agnostic** (it must work for any
consumer), so transport policy — cadence (debounce) and wire formatting (label
routing, #2138) — belongs in the **dispatcher** (the socket consumer), not the
producer. The architecture review independently rated this split a *better*
factoring than the precedent: baking 5s/labeling into the runner would be the
leak, because a future non-WS consumer (test harness, audit sink) wants different
cadence. Put the cadence contract in JSDoc on the emitting callback so a second
consumer can't forget to debounce.

Corollary (reinforces an existing rule class): **an issue's prescribed fix
location/mechanism is a hypothesis, not the work-list.** Grep the literal
producer and walk the delegation chain (`cc-dispatcher` → `soleur-go-runner`
`consumeStream`) to the exact determining condition before coding. The "~line
2107" anchor and "one-line forward" framing were both falsified by a 2-file
trace. See `2026-06-01-symptom-root-cause-trace-the-actual-redirect-not-the-plan-hypothesis.md`.

## Session Errors

1. **Pre-write hook blocked on the literal `doppler secrets set` in the plan's
   Phase 2.8 negative-detection prose** (the list asserting infra patterns are
   absent). — Recovery: added `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`
   and rephrased. — Prevention: the `iac-routing-ack` opt-out is the designed
   escape hatch for negative-detection prose that names infra tokens only to
   assert their absence; already covered, no new rule.
2. **Listed a non-existent test file (`test/tool-labels.test.ts`) in a vitest
   regression invocation** — the runner reported "4 passed" for a 5-file list. —
   Recovery: `ls` confirmed there is no dedicated tool-labels test (the new
   `buildToolProgressWSMessage` helper is covered by the forwarding test's
   WS-shape assertion). — Prevention: glob/verify a test path exists before
   citing it in a runner command; a silently-absent file inflates the expected
   suite count.

## Tags
category: best-practices
module: apps/web-platform/server (cc-dispatcher, soleur-go-runner, tool-labels)
