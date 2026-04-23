---
module: apps/web-platform
date: 2026-04-23
problem_type: security_issue
component: client_render_pipeline
symptoms:
  - "Tokenize-scrub-restore scheme used a guessable ` PRESERVED_N ` placeholder; prose containing the literal could be rewritten or silently deleted"
  - "Client `\"use client\"` component imports `@/server/observability` transitively pulled `pino` into the browser bundle"
  - "Debounce default sentinel `0` combined with `vi.useFakeTimers({ now: 0 })` produced first-heartbeat `0 - 0 >= 5000` = false, starving the client watchdog"
  - "Broadening a canonical regex invalidated the negative-space RED tests (test still passed but no longer asserted the fallthrough)"
root_cause: predictable_placeholder_and_boundary_crossing_imports
severity: high
tags: [command-center, render-scrub, tokenize-restore, client-bundle, pino, observability, discriminated-union-widening, fake-timers]
related_issues: ["#2861", "#2860"]
synced_to: [work]
---

# Render-time scrub sentinels + client/server observability boundary (feat #2861)

## Problem

PR #2860 implemented five coupled Command Center changes: verb-based Bash labels, canonical sandbox-path scrub at both server (label pipeline) and client (assistant-text render), WS `tool_progress` heartbeat forwarding with client watchdog reset, and a two-stage retry lifecycle. Multi-agent review (security, architecture, code-quality, pattern-recognition, test-design) landed two P1s and several P2s that were all structurally in the same category: **"works against today's inputs, breaks silently when invariants shift."**

### Surfaced defects (P1)

1. **`formatAssistantText` placeholder collision.** The render-time scrub tokenized fences/URLs/inline-code into ` PRESERVED_<i> ` placeholders, scrubbed the remaining prose, and restored from `preserved[i]`. Two concrete failure modes:
   - **Prose collision:** assistant emitting the literal substring ` PRESERVED_0 ` had it spliced with a stashed segment (or, worse, `?? ""` silently deleted the literal).
   - **Out-of-range drop:** `preserved[99] ?? ""` swallowed any crafted sentinel index into a silent text deletion. This mechanism was also spoofable by an attacker referencing a stashed URL's restore slot from raw prose — bypassing both scrub and the `reportSilentFallback` leak-detection breadcrumb.
2. **Client bundle pulls `pino`.** `components/chat/message-bubble.tsx` (a `"use client"` file) and `lib/ws-client.ts` imported `reportSilentFallback` from `@/server/observability`. That module imports `@/server/logger`, which imports `pino`. `next.config.ts` lists `@anthropic-ai/claude-agent-sdk` and `ws` in `serverExternalPackages` but NOT pino — so pino bundles into the browser chunk. A pre-existing import pattern (`lib/ws-close-helper.ts`, `lib/stripe-price-tier-map.ts`) had been quietly bleeding pino into the browser for some time; FR3/FR4 widened the blast radius to the hottest render path.

### P2 backlog (also fixed)

- Sandbox-path regex required `[0-9a-fA-F]{6,}` for the workspace-ID slot; a provisioning change to a shorter-or-non-hex ID silently re-enables leaks. Broadened to `[A-Za-z0-9_-]{3,}`.
- `tool_progress` SDK payload cast with bare TS `as { tool_use_id: string; tool_name: string; elapsed_time_seconds: number }` — no runtime guard. Missing `tool_use_id` would poison the debounce map with `undefined` as the key, collapsing every subsequent heartbeat into one slot and starving real tools. Raw `tool_name` also bypassed the `buildToolLabel` allowlist that `tool_use` events go through.
- `KNOWN_WS_MESSAGE_TYPES` was a hand-maintained `Set<string>` with a "keep in sync with `WSMessage`" comment — no compile-time enforcement of the invariant.
- Narrowness invariant (`applyTimeout` is a no-op on already-`error` bubbles) was implied but not asserted.

## Solution

1. **Per-call random sentinel + throw on out-of-range:**

   ```ts
   const nonce = Math.floor(Math.random() * 0xffffffff)
     .toString(16)
     .padStart(8, "0");
   const placeholder = (i: number) => ` SOLEUR_PRES_${nonce}_${i} `;
   const restorePattern = new RegExp(` SOLEUR_PRES_${nonce}_(\\d+) `, "g");
   // ...
   work = work.replace(restorePattern, (_, idx) => {
     const n = Number(idx);
     const value = preserved[n];
     if (value === undefined) {
       throw new Error(
         `formatAssistantText: restore index ${n} out of range`,
       );
     }
     return value;
   });
   ```

   32 bits of entropy is enough to make collision astronomical without crypto cost; the throw converts "silently corrupt the render" to "fail loudly in dev/tests."

2. **Client-safe observability shim.** New `lib/client-observability.ts` exposes `reportSilentFallback` / `warnSilentFallback` with identical signatures to the server version, but pulls only `@sentry/nextjs` (which has a first-party browser build). `message-bubble.tsx` and `ws-client.ts` rewired. Server-side imports continue to route through `@/server/observability` for pino-backed structured logs.

3. **Runtime shape guard for SDK payload + label routing through `buildToolLabel`:** `tool_progress` branch now validates `toolUseId`, `toolName`, `elapsedSeconds` shape and reports `op: "tool-progress-shape"` on drift. `toolName` routes through `buildToolLabel(name, undefined, workspacePath)` so internal SDK tool names (Read/Bash/Grep) never leak over the heartbeat channel either — parity with the `tool_use` event flow.

4. **Compile-time exhaustiveness for `KNOWN_WS_MESSAGE_TYPES`:**

   ```ts
   type AllowedWSMessageType = WSMessage["type"] | ClosePreamble["type"];
   export const KNOWN_WS_MESSAGE_TYPES = new Set<AllowedWSMessageType>([...])
     satisfies ReadonlySet<AllowedWSMessageType>;

   type _Exhaustive = {
     _forward: Exclude<AllowedWSMessageType, SetToUnion<typeof KNOWN_WS_MESSAGE_TYPES>>;
     _backward: Exclude<SetToUnion<typeof KNOWN_WS_MESSAGE_TYPES>, AllowedWSMessageType>;
   };
   const _ExhaustivenessProof: { _forward: never; _backward: never } =
     null as unknown as _Exhaustive;
   ```

   TS2322 fails the build if either direction drifts. Runtime test additionally asserts the set is an exact match with the expected list (not a superset).

5. **Broadened sandbox alphabet + narrowness test + sub-3-char fallthrough test** close out the P2s.

## Key Insights

### Insight 1: Tokenize-scrub-restore schemes are not safe with human-readable sentinels

Any scheme that (a) replaces patterns with placeholders, (b) mutates the remainder, then (c) restores from an index requires the placeholder to be unguessable and the index to be authenticated. Otherwise the restore step is a substitution oracle. Pattern:

- **Unsafe default:** `PLACEHOLDER_0`, `__TOKEN_N__`, `%%REPLACEABLE_X%%`.
- **Safe default:** per-call random nonce (`SOLEUR_PRES_${8hexchars}_${i}`) plus throw-on-out-of-range. 32 bits of entropy is sufficient; reaching for `crypto.randomUUID()` is overkill for this threat model.

### Insight 2: `"use client"` imports transitively pull server modules into the browser

Next.js `serverExternalPackages` only marks packages as externals for the server chunk — they're still bundled into the client chunk if a client-reachable import path touches them. The only bulletproof check is `next build && grep -rl 'pino' .next/static/chunks`. A client-safe shim with identical signature is the lowest-friction fix; the alternative (splitting `reportSilentFallback` into dual exports in the same file) couples the two lifecycles.

### Insight 3: Debounce/throttle defaults must use "never fired" sentinels

Using `0` as the initial `lastSentAt` combined with `vi.useFakeTimers({ now: 0 })` produces `Date.now() - 0 >= 5000` = false on the first heartbeat. The fix is either (a) `undefined` + explicit first-fire branch, or (b) `-Infinity`. Never use `0` — it's valid wall-clock time.

### Insight 4: Broadening a regex requires updating negative-space tests in the same edit

Same class as `cq-raf-batching-sweep-test-helpers` and `cq-union-widening-grep-three-patterns`: when the production pattern widens, RED tests asserting "fallthrough fires on shape X" may silently pass for the wrong reason. In this session, broadening `[0-9a-fA-F]{6,}` → `[A-Za-z0-9_-]{3,}` made `/workspaces/not-a-uuid-shape/` now match — the fallthrough assertion needed a narrower shape (`/workspaces/ab/`, `/tmp/claude-abc/`). Sweep negative-space tests when broadening any gatekeeper.

### Insight 5: Discriminated union widening must update BOTH client reducer AND server handler exhaustive switches

`cq-union-widening-grep-three-patterns` enumerates three consumer patterns. Widening `WSMessage` with `tool_progress` surfaced a TS2322 in `server/ws-handler.ts` whose `default: const _exhaustive: never = msg` caught it at tsc time — the existing rule plus exhaustive-never-pattern is load-bearing here. Worth noting for future: when a WS message variant is server-to-client-only, still add a case (fall through to the "server-to-client only" error branch in `ws-handler.ts`) to preserve the TS never rail.

## Session Errors

1. **Phase 1 GREEN iteration: old `Bash tool` assertions became red when FR1 replaced the output format.** Recovery: updated 3 tests to match verb labels. **Prevention:** when a feature changes the output shape of a helper, grep for consumers in both code and tests in the same edit — the skill instruction for `cq-union-widening-grep-three-patterns` already says this for unions; it applies to any format change.

2. **Phase 1 idempotency test referenced old Bash verb output shape.** Recovery: rewrote using the Read tool (whose output preserves the path content). **Prevention:** idempotency tests must exercise a code path that is NOT replaced by the change under test, otherwise the test verifies behavior that no longer exists.

3. **Phase 2 forwarding test: `Date.now() - 0 >= 5000` false on first heartbeat.** Recovery: `undefined` sentinel + explicit first-fire branch. **Prevention:** debounce/throttle "not-yet-fired" sentinels must be `undefined` or `-Infinity`, never `0` — the pattern recurs with every test that uses `vi.useFakeTimers({ now: 0 })`.

4. **Phase 2 test: `vi.stubGlobal("Date", {...Date, now: ...})` clobbered `instanceof Date`.** Recovery: switched to `vi.setSystemTime()` inside the iterator. **Prevention:** never copy-spread JS globals (`Date`, `Map`, `Promise`) through `vi.stubGlobal` — they have internal slot semantics not expressible as plain-object properties. Use vitest's purpose-built helpers (`vi.useFakeTimers`, `vi.setSystemTime`).

5. **`ws-streaming-state.test.ts` broke when FR5 made `applyTimeout` two-stage.** Recovery: seeded `retrying: true` on existing fixtures. **Prevention:** when changing a state machine's transition semantics, grep for every test file importing the transition and schedule updates in the same edit (see Insight 4 — generalizes beyond regex).

6. **UI test asserted `container.textContent` doesn't contain "Working"**, not realizing MessageBubble renders a separate absolute-positioned "Working" status badge independent of the chip body. Recovery: dropped the assertion. **Prevention:** UI negative assertions should scope to `getByTestId` or `within(chip)` — container-level negation is a common vector for false passes when two components share a string.

7. **`ws-handler.ts` tsc error after WSMessage union widened.** Recovery: added `tool_progress` to the server-to-client-only case fall-through. **Prevention:** already covered by `cq-union-widening-grep-three-patterns` but emphasizes that cross-boundary unions (client reducer + server handler) need both exhaustive switches updated.

8. **Bash cwd drift: `cd apps/web-platform && …` from inside `apps/web-platform` produced nested path errors.** Recovery: absolute `cd` paths. **Prevention:** already mandated by `cq-for-local-verification-of-apps-doppler`. No new rule needed; muscle-memory drift.

9. **P1 found at review: `@/server/observability` in `"use client"` component pulls pino into browser.** Recovery: `lib/client-observability.ts` shim. **Prevention:** when editing a `"use client"` file (explicit or via consumer chain), the `@/server/*` import namespace is off-limits — build a thin shim in `lib/` with identical signatures. This is a new rule worth promoting (see below).

10. **P1 found at review: `formatAssistantText` placeholder collision.** Recovery: per-call random sentinel + throw-on-out-of-range. **Prevention:** see Insight 1. This is a new rule worth promoting (see below).

11. **Sandbox regex broadening invalidated RED-path tests.** Recovery: re-authored tests against still-narrow shapes. **Prevention:** see Insight 4. Already covered by `cq-raf-batching-sweep-test-helpers` as a class; worth adding a regex-specific instance.

## Proposed Workflow Changes

Per the "every session error must produce an AGENTS.md rule, skill instruction edit, or hook" rule (`wg-every-session-error-must-produce-either`), proposing:

### New AGENTS.md Code Quality rule — client-bundle boundary for `@/server/observability`

> When editing a `"use client"` component OR a `lib/` module that has client consumers, never import from `@/server/observability` (it transitively imports `pino`, which is not in `next.config.ts` `serverExternalPackages`). Use `@/lib/client-observability` instead, or add a thin shim with identical signature. Verify with `grep -rn "@/server" <new-file>` before committing.

### New AGENTS.md Code Quality rule — tokenize-scrub-restore schemes must use unguessable sentinels

> Any textual tokenize-scrub-restore pipeline (stash regex matches under placeholders, scrub the remainder, restore from array) MUST use a per-call random sentinel (≥24 bits of entropy) in the placeholder and throw (not silently return `""`) on out-of-range restore indices. Human-readable placeholders (`PLACEHOLDER_N`, `__TOKEN_N__`) are a substitution oracle — assistant-controlled prose containing the literal token splices in stashed content or deletes the literal.

### Existing rule reinforcement — `cq-union-widening-grep-three-patterns` generalization hint

Current rule mentions TS `.kind` / `.type` if-ladders. Worth appending a one-line clarification that cross-boundary exhaustive switches (`ws-client.ts` reducer AND `ws-handler.ts` server-to-client-only case fall-through) both need updating for WS message variants. Covered by existing rule; no new rule, just an in-session reminder.

## Tags

category: security_issue
module: apps/web-platform
