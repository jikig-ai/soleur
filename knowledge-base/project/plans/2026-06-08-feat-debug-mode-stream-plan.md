---
title: "feat: Debug Mode — workspace-scoped harness instruction stream"
date: 2026-06-08
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gdpr_gate_required: true
closes: [5045]
brainstorm: knowledge-base/project/brainstorms/2026-06-08-debug-mode-stream-brainstorm.md
spec: knowledge-base/project/specs/feat-debug-mode-stream/spec.md
wireframe: knowledge-base/product/design/debug-mode/debug-mode-stream.pen
branch: feat-debug-mode-stream
pr: 5042
---

# feat: Debug Mode — Workspace-Scoped Harness Instruction Stream ✨

Internal-only Debug mode for the web-platform conversation surface. When toggled ON for a
workspace (visible only to the Soleur `dev` cohort), a **separate collapsed debug panel**
streams **redacted Claude Agent SDK harness events** (raw `tool_use` name + redacted
`tool_input`, assistant text, `result`/usage) so operators see live what the harness is
doing and accelerate harness improvement. Render-only, ephemeral, server-side gated.

A **scoped, gated exception to the #2138 "no raw tool inputs on the wire" invariant**,
exactly as `command_stream` already is.

> **Revised after 4-agent plan review** (DHH, Kieran, spec-flow, code-simplicity). See
> `## Plan Review Reconciliation` — four P0 structural corrections + two HIGH
> simplifications materially reshaped Phases 3/5/6/7 and shrank scope.

## Overview

Reuse three existing substrates verbatim:

1. **Per-workspace toggle** — `workspaces.bash_autonomous` (migration 097) + member/owner
   SECURITY-DEFINER RPCs + fail-closed `resolveBashAutonomous`. Clone to `workspaces.debug_mode`.
2. **Redacted emit from dispatcher callbacks** — `command_stream` is emitted from
   `cc-dispatcher.ts`'s `onToolResult` callback (`:2458`) through `redactCommandForDisplay`
   + a `probeRedactionFallthrough` Sentry tripwire. Debug mode emits from the **already-wired**
   `onText`/`onToolUse`/`onResult` callbacks (`:2358`/`:2370`/`:2632`).
3. **Eligibility flag** — Flagsmith RUNTIME_FLAGS (`lib/feature-flags/server.ts:40`) gated on
   the `dev` role cohort. Add a `debug-mode` availability flag.

## Plan Review Reconciliation

| # | Finding (reviewer) | Verified reality | Resolution |
|---|---|---|---|
| P0-1 | Tap seam misidentified as a `cc-dispatcher` loop (Kieran) | `cc-dispatcher.ts` has **0** `for await` loops; the SDK loop is `soleur-go-runner.ts:2158`. cc-dispatcher receives events via `DispatchEvents` callbacks and **already implements** `onText`/`onToolUse`/`onResult` | Emit `debug_event` from those **existing** cc-dispatcher callbacks. **No `soleur-go-runner.ts` edits, no new callbacks.** |
| P0-2 | Concierge path has no `reasoning`/`tool_progress` callback (Kieran) | `DispatchEvents` (`soleur-go-runner.ts:798`) = `onText`/`onToolUse`(raw input, all tools)/`onToolResult?`(Bash-only)/`onResult`. No thinking or progress seam | **Drop `tool_progress` kind from v1**; map "reasoning" → `onText`. Defer thinking-blocks + sub-agent transcripts (net-new plumbing). |
| P0-3 | `ClientSession.debugMode` not in scope at emit site (Kieran) | `DispatchSoleurGoArgs` carries no `ClientSession`; `bashAutonomousPosture` is resolved **inside** the dispatcher via `resolveBashAutonomous(userId)` (`:1270`/`:2283`) | Resolve `debugMode`+eligibility **per-dispatch** inside `dispatchSoleurGo`, mirroring bash. **Drops the ClientSession/handshake/refresh-timer design** — and **solves toggle propagation for free** (next turn resolves fresh). |
| P0-4 | `StreamEvent` allowlist silently swallows the frame (Kieran) | `chat-state-machine.ts:295` `StreamEvent = Extract<WSMessage, {type:"command_stream"} \| …>` is an **explicit allowlist**; `chat-surface.tsx:629` switches over `ChatMessage`, not WSMessage | Add `debug_event` to the `StreamEvent` Extract list + a reducer case in `chat-state-machine.ts`; THEN the render case. AC asserts `debug_event ∈ StreamEvent`. |
| HIGH-A | Dual-loop emit is speculative (DHH + simplicity) | `command_stream` emits from cc-dispatcher only, **never** `agent-runner.ts` (verified 0); legacy path is non-default (`pendingLeader`) | Emit from cc-dispatcher callbacks only. **Drop `agent-runner.ts`** from scope; defer legacy-path debug to a follow-up. |
| HIGH-B | Don't expand the shared redactor (simplicity) | `redactGithubSourcedText`/`redactCommandForDisplay` is shared with `message-bubble.tsx` + `command_stream` — hardening it has blast radius | **DROP-first**: call the existing redactor + probe in the emit helper and **drop the frame's input on probe trip** (don't expand the shared module). Keep the shared probe observational (P1, Kieran). |
| MED | Flatten typed payload (simplicity) vs keep (DHH) | DHH's "keep" rested on per-field redaction routing, which DROP-first removes | **Flatten** to `{ kind; label?; body }` — `body` is already redacted-or-dropped; exhaustiveness holds on the outer union. |
| P1 | Re-redact site is `message-bubble.tsx:258`, not chat-surface (Kieran) | confirmed | Re-redact in the new `debug-stream-panel.tsx`, importing from `@/lib/safety` (lib, not server). |
| P1 | `ws-known-types.ts` IS compile-enforced (Kieran) | `satisfies ReadonlySet` + bidirectional `_Exhaustive` (`:62`/`:77`) | Corrected; `StreamEvent` is the unguarded seam, not this set. |
| P2 | RPC param is `p_value` not `p_enabled` (Kieran) | `set-bash-autonomous.ts:41` uses `p_value` | Use `p_value`. |
| KEPT | Defer the in-UI toggle? (simplicity floated) | User explicitly asked to "toggle debug mode"; wireframe frame 04 has it | **Rejected** — toggle stays (core UX + user intent). |

## User-Brand Impact

**If this lands broken, the user experiences:** the debug panel shows nothing (fail-closed)
or, worst case, an un-redacted secret rendered into their conversation surface.

**If this leaks, the user's credentials/PII are exposed via:** (1) a redactor miss on a
`tool_input` reaching the panel; (2) a mis-targeted eligibility gate emitting to a non-Soleur
tenant; (3) any persistence path writing a `debug_event` to `messages`, logs, or Sentry.

**Brand-survival threshold:** `single-user incident`. CPO sign-off carried forward from
brainstorm Phase 0.1 triad. `user-impact-reviewer` runs at PR review.

## Implementation Phases (contract → consumer)

### Phase 1 — Clone the per-workspace toggle stack (contract: storage + authz + control)
- `supabase/migrations/101_workspace_debug_mode.sql` (+ `.down.sql`), cloning 097:
  `ALTER TABLE workspaces ADD COLUMN IF NOT EXISTS debug_mode boolean NOT NULL DEFAULT false`;
  `get_workspace_debug_mode(p_workspace_id uuid)` SECURITY DEFINER, member-checked, **`SET search_path = public, pg_temp`**, NULL→false for non-members;
  `set_workspace_debug_mode(p_workspace_id uuid, p_value boolean)` owner-only; **no UPDATE policy**; **no bulk write**. Re-verify `ls supabase/migrations | tail` at /work (101 is next now).
- `lib/feature-flags/server.ts` (`:40` RUNTIME_FLAGS): add `"debug-mode": "FLAG_DEBUG_MODE"` + `isDebugModeAvailable(identity)` (clone `isTeamWorkspaceInviteEnabled`, gate on `dev` role). `.env.example`: `FLAG_DEBUG_MODE`.
- `server/resolve-debug-mode.ts` (clone `resolve-bash-autonomous.ts`, fail-closed false, Sentry-mirror); `server/set-debug-mode.ts` (clone `set-bash-autonomous.ts`, `p_value`); `app/api/workspace/debug-mode/route.ts` (clone `bash-autonomous/route.ts`).

### Phase 2 — WS frame contract (`debug_event`)
- `lib/types.ts`: add `debug_event` to `WSMessage`: **flat** `{ type:"debug_event"; kind: "tool_use"|"reasoning"|"result"; label?: string; body: string }` (`body` is the already-redacted display string).
- `lib/ws-zod-schemas.ts`: add the `debug_event` schema (clone `:265`). Semantics = **delta/append** (one event per frame); turn end already signalled by `stream_end`/`session_ended`.
- `lib/ws-known-types.ts`: register `debug_event` (`:62` set is **compile-enforced** — TS2322 if omitted).
- `lib/chat-state-machine.ts`: **add `debug_event` to the `StreamEvent` Extract allowlist (`:301`)** AND a reducer case (clone the `command_stream` case at `:885`) mapping it to a `ChatMessage` debug variant. (Without this the `:never` rail stays green and the frame is silently dropped — P0-4.)

### Phase 3 — Server-side gated emit (the tap)
- `server/debug-event.ts` — pure, unit-testable `buildDebugEvent(kind, label, rawBody)`: routes `rawBody` through `redactCommandForDisplay`, calls `probeRedactionFallthrough` (widen its `field` type to include `"tool_input"|"reasoning"`); **on probe trip → DROP**: for `tool_use`, emit `{kind:"tool_use", label:toolName, body:"[input withheld: failed redaction probe]"}` (tool name is low-density, already a wire label per #2138) so a dropped input is **visible, not invisible** (spec-flow P1); for other kinds, return null (no frame). Otherwise return the redacted `debug_event`.
- `server/cc-dispatcher.ts`: resolve `debugPosture = resolveDebugMode(userId)` + `debugEligible = isDebugModeAvailable(identity)` per-dispatch (parallel to `resolveBashAutonomous` at `:1270`/`:2283`), captured as `let` bindings. In the existing `onText` (`:2358`) / `onToolUse` (`:2370`) / `onResult` (`:2632`) callbacks, when `debugPosture && debugEligible`, build the debug_event and `sendToClient` if non-null. Reuse the in-scope `COMMAND_STREAM_*_CAP_BYTES` (`:310`) — no new cap constants.
- **Ephemeral invariant**: `debug_event` is NEVER inserted into `messages` (the insert sinks at `cc-dispatcher.ts:2178/2351`, `ws-handler.ts:1429` are content-shaped, not WSMessage-by-type — confirmed), NEVER logged, NEVER Sentry-captured. A **standing CI grep gate** (write-boundary sentinel) asserts no persistence sink references `debug_event`.

### Phase 4 — Client render (consumer)
- `components/chat/debug-stream-panel.tsx` — separate collapsed drawer (per wireframe): collapsed/expanded/empty/streaming/"secrets redacted"/**dropped-or-capped ("N events withheld")**/**disconnected** states; "not saved" hint; **member (non-owner dev) read-only** view (no toggle); empty-vs-unavailable heuristic (toggle ON + 0 frames after a completed turn → "enabled; no events, or gate unavailable — check Sentry"). **Re-redact at render** via `redactCommandForDisplay` from `@/lib/safety` (dual-gate, mirroring `message-bubble.tsx:258`). Imports no `@/server/*`.
- `components/chat/chat-surface.tsx` (`:629` ChatMessage switch): add the debug ChatMessage render case (respect the `:never` rail).
- `components/settings/debug-mode-toggle.tsx` — clone `bash-autonomous-toggle.tsx`; visible only when `isDebugModeAvailable` (dev cohort); owner-write via the route.

### Phase 5 — Tests (deterministic; LLM out of the assertion path)
- `test/server/debug-event.test.ts` — three `describe` blocks: (a) **gate** — `buildDebugEvent`/emit produces nothing unless `debugPosture && debugEligible` (drive directly, not via `query()`); (b) **redaction + wire-bytes invariant** — planted Doppler value / signed URL / `sk-ant-` / generic token in a tool input → the **serialized `sendToClient` frame contains no secret substring** (assert the wire bytes, not "redactor called"); probe-trip drops the input and emits the `[input withheld]` placeholder. Fixtures synthesized only.; (c) **ephemeral** — no `messages` insert / logger / Sentry receives a `debug_event`.
- `test/components/debug-stream-panel.test.tsx` — render re-redaction (feed a frame whose `body` still contains a secret → rendered DOM is redacted); toggle hidden for non-`dev`; member read-only (no toggle) view.
- `tsc --noEmit` (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`): widens `WSMessage`, `StreamEvent`, `ws-known-types`, the two `:never` rails, and the ChatMessage render switch — compiler enumerates.

## Files to Create
- `apps/web-platform/supabase/migrations/101_workspace_debug_mode.sql` (+ `.down.sql`)
- `apps/web-platform/server/resolve-debug-mode.ts`
- `apps/web-platform/server/set-debug-mode.ts`
- `apps/web-platform/server/debug-event.ts`
- `apps/web-platform/app/api/workspace/debug-mode/route.ts`
- `apps/web-platform/components/chat/debug-stream-panel.tsx`
- `apps/web-platform/components/settings/debug-mode-toggle.tsx`
- `apps/web-platform/test/server/debug-event.test.ts`
- `apps/web-platform/test/components/debug-stream-panel.test.tsx`

## Files to Edit
- `apps/web-platform/lib/feature-flags/server.ts` — `debug-mode` RUNTIME_FLAG + `isDebugModeAvailable`
- `apps/web-platform/.env.example` — `FLAG_DEBUG_MODE`
- `apps/web-platform/lib/types.ts` — flat `debug_event` WSMessage variant
- `apps/web-platform/lib/ws-zod-schemas.ts` — `debug_event` zod schema
- `apps/web-platform/lib/ws-known-types.ts` — register `debug_event` (compile-enforced)
- `apps/web-platform/lib/chat-state-machine.ts` — `StreamEvent` Extract + reducer case (**the silent-drop seam**)
- `apps/web-platform/server/cc-dispatcher.ts` — per-dispatch gate resolve + emit from `onText`/`onToolUse`/`onResult`; widen `probeRedactionFallthrough` `field` type
- `apps/web-platform/components/chat/chat-surface.tsx` — debug ChatMessage render case
- (Re-grep every cited line number at /work — anchors drift; e.g. RUNTIME_FLAGS is `:40-46`.)

## Observability

```yaml
liveness_signal:
  what: debug_event frames emitted per turn when enabled (counter)
  cadence: per agent turn
  alert_target: none (operator-facing internal tool; absence is benign)
  configured_in: existing WS frame metrics
error_reporting:
  destination: Sentry (existing probeRedactionFallthrough tripwire + resolveDebugMode fail-closed mirror)
  fail_loud: redaction-probe trip drops the input (fail-closed) AND the existing Sentry tripwire fires
failure_modes:
  - mode: redactor misses a secret shape
    detection: probeRedactionFallthrough on suspected-secret survival → input dropped + Sentry
    alert_route: Sentry (existing redaction-fallthrough rule)
  - mode: emit fires for a non-dev / wrong workspace
    detection: per-dispatch debugPosture && debugEligible gate; resolveDebugMode fail-closes false
    alert_route: Sentry (resolveDebugMode failure mirror)
  - mode: debug_event reaches a persistence path
    detection: ephemeral unit test + standing CI grep (write-boundary sentinel)
    alert_route: CI (test/grep failure)
logs:
  where: none for debug payloads (ephemeral by design); resolveDebugMode fail-closed reasons mirror to Sentry
  retention: n/a
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/debug-event.test.ts"
  expected_output: "all tests pass; no ssh required"
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — Migration 101 adds `debug_mode` + member-read/owner-write SECURITY-DEFINER RPCs (`p_value`) with pinned `search_path`, no UPDATE policy, no bulk write; `.down.sql` reverses. **Behavioral check:** a `get_workspace_debug_mode` call as a non-member returns `false` (migration test), not a token-presence grep.
- [ ] AC2 — `debug-mode` ∈ `RUNTIME_FLAGS`; `isDebugModeAvailable` gates on `dev` role (unit test: non-`dev` identity → false).
- [ ] AC3 — `resolveDebugMode` fail-closes to `false` on RPC error/null (unit test); resolved **per-dispatch** inside `dispatchSoleurGo`, not from `ClientSession`.
- [ ] AC4 — **Wire-bytes invariant:** for a tool input carrying a planted Doppler value / signed URL / `sk-ant-` / generic token, the serialized `sendToClient` `debug_event` contains **no secret substring**; a probe-trip drops the input and emits the `[input withheld]` placeholder (tool name only). Fixtures synthesized only.
- [ ] AC5 — `debug_event` ∈ `WSMessage` (flat `{kind,label?,body}`), zod schema, `KNOWN_WS_MESSAGE_TYPES`, **AND `StreamEvent` (chat-state-machine)** with a reducer case; `tsc --noEmit` clean.
- [ ] AC6 — Emit produces nothing unless `debugPosture && debugEligible` (test drives `buildDebugEvent`/emit directly). A toggle flip takes effect on the **next** dispatch (per-dispatch resolution; note ≤1-turn mid-turn latency).
- [ ] AC7 — No persistence path (messages insert / logger / Sentry) receives a `debug_event` (ephemeral test) **AND** a standing CI grep asserts no persistence sink references `debug_event`.
- [ ] AC8 — Debug panel renders as a separate collapsed drawer (not inline), re-redacts at render, imports no `@/server/*`; has dropped/withheld + disconnected + member-read-only states; toggle hidden for non-`dev`.
- [ ] AC9 — `gdpr-gate` run on the diff; Critical findings (if any) acknowledged. `user-impact-reviewer` at PR review.

### Post-merge (operator/automatable)
- [ ] AC10 — Apply migration 101 via existing `web-platform-release.yml#migrate` (no SSH). Verify column via Supabase MCP read. **Order: migration before the Flagsmith flip.**
- [ ] AC11 — Create/flip the `debug-mode` Flagsmith segment for the `dev` cohort via `soleur:flag-set-role` (not a manual dashboard click).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm Phase 0.5 triad).

### Engineering (CTO)
**Status:** reviewed (carry-forward + 4-agent plan-review correction)
**Assessment:** Emit from cc-dispatcher's existing `onText`/`onToolUse`/`onResult` callbacks; per-dispatch gate resolution mirroring `bashAutonomousPosture`; DROP-first redaction without expanding the shared module; `StreamEvent` is the load-bearing exhaustiveness seam. Smaller than the original plan.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Rides registered PA-2 Conversation Data; founder-grade **only if ephemeral/render-only** (enforced by the standing CI grep + ephemeral test). Persistence ⇒ DPIA (Art. 35). Redact-at-source via DROP-first.

### Product/UX Gate
**Tier:** blocking (UI-surface override: `components/chat/*.tsx`, `components/settings/*.tsx`)
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55 — `.pen` committed), spec-flow-analyzer (this plan)
**Skipped specialists:** none
**Pencil available:** yes (`.pen` committed, referenced in spec FR1/FR2)

#### Findings
Wireframe (4 frames) with brand-critical callouts. spec-flow P0/P1s folded in: toggle propagation (solved via per-dispatch resolution), resolver-fail-closed-vs-idle heuristic, dropped-frame affordance, member read-only view, disconnect state, wire-bytes invariant AC.

## Infrastructure (IaC)

No new infrastructure provisioning. Only persistent change is Supabase migration 101 (column +
RPCs), applied by the existing `web-platform-release.yml#migrate` pipeline on merge. The
`debug-mode` Flagsmith flag is created via `flag-create`/`flag-set-role` (established pattern).
No new server, vendor, cron, DNS, secret, or systemd unit. Phase 2.8 → skip.

## Sharp Edges
- `## User-Brand Impact` is filled (deepen-plan Phase 4.6 gate).
- Migration `101` is next now; re-verify `ls supabase/migrations | tail` at /work (parallel PR could take it).
- **Per-dispatch gate resolution** means a mid-turn toggle-OFF keeps emitting until the turn ends (≤1 turn). Acceptable; documented in AC6. A toggle-ON takes effect next turn (no live-socket refresh needed — this is why the ClientSession/refresh-timer design was dropped).
- Redaction coverage is the dominant `single-user incident` risk — **DROP-first** (drop the input on probe trip), do NOT expand the shared `redactGithubSourcedText` (blast radius to `message-bubble.tsx` + `command_stream`). Sweep ALL sinks per `2026-06-04-redaction-fix-must-sweep-all-render-sinks`.
- `StreamEvent` (chat-state-machine) is the **unguarded** seam — `ws-known-types` is compile-enforced but `StreamEvent` is a hand-maintained Extract allowlist; forgetting it silently drops the frame while `tsc` stays green.
- Document the #2138-invariant exception inline at the emit site, as `command_stream` does.
- **DB column persists across cohort changes** (a removed-then-readded dev sees streaming re-enabled with no fresh consent). Acceptable for an internal tool; recorded as a decision, not an accident.

## Deferred (tracking)
- `tool_progress` kind + thinking-blocks + sub-agent internal transcripts (net-new `DispatchEvents` callbacks / SDK `system`-message handling) — Non-Goal for v1; file a follow-up if the uncurated stream proves insufficient.
- Legacy `agent-runner.ts` path debug emit (non-default `pendingLeader` sessions) — follow-up.
- Persisted/saved debug transcripts — separate plan + mandatory DPIA.
