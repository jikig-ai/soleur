---
title: Reasoning Narration — Live Status Line + Persisted Turn Summary
feature: feat-reasoning-chat-boxes
date: 2026-06-15
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gdpr_gate_required: true
issue: 5370
pr: 5363
brainstorm: knowledge-base/project/brainstorms/2026-06-15-reasoning-narration-brainstorm.md
spec: knowledge-base/project/specs/feat-reasoning-chat-boxes/spec.md
wireframes: knowledge-base/product/design/chat/reasoning-narration.pen
---

# ✨ Reasoning Narration — Live Status Line + Persisted Turn Summary

## Overview

Give non-technical Soleur users a real-time sense of *what the agent is doing* (a transient live
narration line) and a durable plain-language record of *what it did* (one persisted summary box per
substantive successful turn) — **without** exposing raw internal reasoning. The agent **emits the
user-facing text deliberately** via two MCP tools (`narrate` / `summarize`), so no internal monologue
ever reaches a persisted, user-visible record. The team-only "Debug stream" is untouched.

Both halves are kept (operator chose "a mix of 1 and 2" in brainstorm). Plan-review's simplicity lens
recommended deferring the live half entirely; **dissent recorded** — kept per operator decision, but
the live half is now a **single transient slot** (not the per-leader subsystem the first draft had),
which removes the bulk of the over-build the reviewers flagged.

| Frame | Lifecycle | Persisted? | Buffered (replay)? | Render |
|-------|-----------|-----------|--------------------|--------|
| `reasoning_narration` | transient | No | **No** (live-only, mirrors `debug_event`) | live line near "Working…" badge |
| `turn_summary` | durable | **Yes** (`messages` row) | **Yes** (4 lockstep edits) | emerald confirmed box |

## Architecture Decision

**Two MCP tools (not one `narrate({final})` fork — plan-review: one tool, one side-effect):**
- `narrate({ message })` → `reasoning_narration` frame (live-only).
- `summarize({ summary })` → persisted `turn_summary` (success path only).

**`liveNarration` is a single `string | null` slot in the ws-client `ChatState`** (NOT a per-leader
Map, NOT `ChatStateSnapshot`):
- *Reducer ownership* [spec-flow P0]: abort/timeout/disconnect are **ws-client actions**
  (`enter_stopping`/`clear_streams`/`timeout`/`connection_change`@`ws-client.ts:276`), never
  `StreamEvent`s — so teardown MUST live in the ws-client reducer (`ChatState`@`:219-256`), cleared on
  every lifecycle arm. The message reducer only *sets* it on a `reasoning_narration` event.
- *Single slot, not a Map* [Kieran P1-1, verified]: `narrate` registers only on the **interactive
  path** (`agent-runner.ts:55`→`conversations-tools.ts:59`), where cc-dispatcher emits with a fixed
  `CC_ROUTER_LEADER_ID`. The multi-leader concurrency that would justify per-leader keying lives in the
  **inngest leader-prompts path, which has zero MCP-tool registration** — so `narrate` is effectively
  single-leader on its surface. Worst case under any future multi-caller = the line flickers (not an
  incident). Per-leader keying, cross-leader de-dupe, and `leaderId`-on-frame are **deferred** until
  the tool is actually reachable from concurrent leaders.

**Write-scope control = the RLS tenant-client** [Kieran P1-2, verified]: `insert-turn-summary.ts`
mirrors `insert-draft-card.ts:65` — `getFreshTenantClient(founderId)` (RLS-scoped) + `user_id=founderId`.
`assertWriteScope` (`cc-dispatcher.ts:741`) is currently a **no-op forward-compat placeholder**
(`return true`); route through it for forward-compat + test-seam coverage, but it is NOT today's control.
The real cross-tenant defenses are: the RLS tenant-client, the system-prompt directive (forbid naming
any out-of-context entity), and `user-impact-reviewer` at PR time.

**Why FR5 holds:** `summarize` writes a row only on the success path AND `emitNarration()` drops the
call if the conversation is in an aborted/stopping server state. Aborted/errored turns never write.

**Why reuse `messages` (additive nullable `message_kind`):** mirrors migration 040; avoids the
NOT-NULL-insert-sweep foot-gun (learning 2026-06-04); inherits RLS; inherits DSAR export
(table-enumerated `select("*")` @`dsar-export.ts:588`) + Art-17 erasure (FK cascade
`001_initial_schema.sql:70` + `account-delete.ts:115`) — **conditional on `user_id=founderId`** so the
Art-15(4) author-redaction (`dsar-export.ts:619-622`, keyed on user_id NOT role) keeps `content` in the
export.

## Research Reconciliation — Spec vs. Codebase

No falsified spec assumptions. Gate-discovered deltas folded into phases:

| Claim | Reality | Plan response |
|-------|---------|---------------|
| migration adds a column freely | CI sentinel `dsar-message-redact-fields-sweep.test.ts` (`dsar-export.ts:363-371`) FAILS unless the new `messages` column is classified | Phase 1: `message_kind` → `MESSAGE_NON_REDACT_ALLOWLIST` (`:419`) |
| "reuse table → auto DSAR" | True (export table-enumerated, erasure FK-cascade) **iff** `user_id=founderId` | Phase 5 invariant + un-redacted-export test |
| Art-30 "new PA" | PA-2 already covers conversation runtime / `messages` | AMEND PA-2 (b)/(g); no new PA |
| assertWriteScope is the control | it is a `return true` placeholder (`:741`) | RLS tenant-client is the control; assertWriteScope = forward-compat seam |

## Open Code-Review Overlap
4 open issues touch planned files — all **Acknowledge** (distinct concerns): #3242 (tool_use raw-name),
#3374 (slot_reclaimed — same new-frame pattern; this PR documents it), #3243 (cc-dispatcher decomp — keep
`emitNarration()` extractable), #3280 (useWebSocket refactor — additive edits). All remain open.

## Resolved Open Questions
- **Trivial turns / agent-omits-`summarize` [spec-flow 2+5]:** summaries are **best-effort on
  substantive turns**, NOT guaranteed-every-turn (CPO anti-clutter). FR4 → "**at most one** per turn";
  **Frame 07 caption corrected** at /work (wireframe task, not an eng AC). No `summary-missing` Sentry op
  for v1 [simplicity: don't instrument a non-error]; if a fallback synthesizer is ever wanted, add the
  measurement then.
- **Multi-leader [spec-flow 3a/3b]:** N/A on the `narrate`/`summarize` surface (single-leader; Kieran
  P1-1). Single-summary-per-turn enforced by the orchestrator-only prompt + a test; server de-dupe
  deferred until multi-leader tool access exists.

## Implementation Phases (contract-before-consumer; atomic single-PR merge)

### Phase 0 — Preconditions (grep, no code)
- Read `conversations-tools.ts` (`tool()` shape + registration via `agent-runner.ts:55`); `tool-tiers.ts` `TOOL_TIER_MAP` (tier for `narrate`/`summarize`); `permission-callback.ts`; `cc-dispatcher.ts:741` `assertWriteScope` (confirm no-op) + `:1544/:1810` emit sites + `CC_ROUTER_LEADER_ID`.
- Read `ws-client.ts:219-293` (`ChatState` + actions, `onclose:1228`) — liveNarration teardown site.
- Read `dsar-export.ts:419` (`MESSAGE_NON_REDACT_ALLOWLIST`) + `dsar-export-allowlist.ts:13-17` (cross-doc gate); `insert-draft-card.ts:65-71` (tenant-client + `user_id`/`workspace_id` pin).
- Read `prompt-assembly.ts` + `constants.ts` (narration directive site).

### Phase 1 — DB contract + DSAR classification (migration 105)
- `105_turn_summary_message_kind.sql`: `ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_kind text`; add CHECK via a `DO $$ ... IF NOT EXISTS (SELECT FROM pg_constraint WHERE conname='messages_message_kind_chk') ... $$` idempotency guard (PG has no `ADD CONSTRAINT IF NOT EXISTS`) [Kieran P2-2]. `CHECK (message_kind IS NULL OR message_kind='turn_summary')`. No `CONCURRENTLY`. `.down.sql` drops both. Summary text reuses `content`.
- **[CRITICAL] `dsar-export.ts`: add `message_kind` to `MESSAGE_NON_REDACT_ALLOWLIST`** — else `dsar-message-redact-fields-sweep.test.ts` fails the build.
- Touching `dsar-export.ts` fires `legal-doc-cross-document-gate.yml` → 4 legal docs in lockstep (Phase 7).

### Phase 2 — Wire contract (types + zod)
- `lib/types.ts`: `{ type:"reasoning_narration"; conversationId:string; message:string }` (no seq, no leaderId v1); `{ type:"turn_summary"; conversationId:string; summary:string; seq?:number }`; `ChatTurnSummaryMessage` on `ChatMessage`; `liveNarration: string | null` on the **ws-client `ChatState`**.
- `lib/ws-zod-schemas.ts`: both schemas (turn_summary carries `replaySeqSchema`); register in `flatTypeSchema`. `_SchemaCovers`@`:642-649` fails tsc on drift.
- **Run `tsc --noEmit` — compiler enumerates every exhaustiveness rail** (learning 2026-05-07). No hand-listing.

### Phase 3 — Replay buffer (turn_summary ONLY)
- `stream-replay-buffer.ts` 4 lockstep edits for `turn_summary` (`:27-36`, `:47-55`, seq in Phase 2, replaySeqSchema in Phase 2). **`reasoning_narration` NOT added** (live-only; preserves #5290/#5240). **No `ws-handler.ts` edit needed** — `isBufferedFrame()`@`:615-621` auto-stamps buffered frames [Kieran P2-4].

### Phase 4 — Reducers
- **ws-client `ChatState` (`ws-client.ts`)** owns `liveNarration`: set on `reasoning_narration` dispatch; **clear (→null) on `clear_streams`, `enter_stopping`, `timeout`→error, `onclose`/`connection_change`** [spec-flow P0]. Single highest-leverage correctness fix.
- `chat-state-machine.ts`: `turn_summary` appends `ChatTurnSummaryMessage` (mirrors persisted-text append).

### Phase 5 — Emit + agent channel
- `narrate-tool.ts` (or extend `conversations-tools.ts`): `narrate({message})` + `summarize({summary})` on soleur_platform MCP server; register in `tool-tiers.ts` + `permission-callback.ts`.
- `cc-dispatcher.ts` — extractable `emitNarration()` (eases #3243): `narrate`→`reasoning_narration` frame. `summarize`→ **drop if conversation aborted/stopping** [spec-flow 1c]; redact at construction (`formatAssistantText` + `redactCommandForDisplay` + `debugRedactionProbeTrips`, drop-on-trip + Sentry mirror); `insertTurnSummary()`; emit buffered `turn_summary`.
- `insert-turn-summary.ts`: mirror `insert-draft-card.ts` — `getFreshTenantClient(founderId)`, **`user_id=founderId`** [legal HIGH], `role='assistant'`, `message_kind='turn_summary'`, redacted `content`.
- `prompt-assembly.ts` + `constants.ts`: directive — "call `narrate` with a short plain-language status at milestones; call `summarize` once with the outcome on successful completion. **Never name any entity, org, person, file path, skill name, or issue number outside the current user's own context**" [legal MEDIUM cross-tenant]. Multi-leader: only the orchestrator calls `summarize`.

### Phase 6 — Render + hydrate
- `chat-surface.tsx`: `case "turn_summary"` → `<TurnSummaryBubble>`; render `liveNarration` near the Working badge (wireframe 05); **reconnect placeholder** — `streamState==="streaming"` && `liveNarration===null` → "Still working…" [spec-flow 4] (cross-ref `reconnect-resume-states.pen`).
- `turn-summary-bubble.tsx` (NEW): emerald checkmark + `border-l` rail (wireframe 06); `formatAssistantText`.
- `ws-client.ts`: dispatch both frames; hydrate `message_kind='turn_summary'`→`ChatTurnSummaryMessage` (omission → silent fallthrough to a generic text bubble — name the regression [Kieran P2-3]); teardown on BOTH turn-boundary paths.
- `api-messages.ts`: add `message_kind` to history `.select(...)` (`:139-151` [Kieran P2-3]).
- Wireframe task: correct Frame 07 caption ("completed turns **may** leave a summary"); add reconnect-mid-turn frame (or cross-ref sibling .pen).

### Phase 7 — Compliance docs (lockstep)
- **Amend PA-2** in `article-30-register.md` (b)+(g); do NOT mint a new PA [legal HIGH]. Update privacy-policy, GDPR policy, Data Protection Disclosure, compliance-posture (cross-doc gate). Record **Art-22 negative determination**. Route through CLO-attestation.

### Phase 8 — Tests
- `turn-summary-emit.test.ts`: `summarize`→row w/ `user_id=founder` + buffered frame; planted secret→redacted/dropped (assert stored row); abort/error→0 rows; `summarize` after abort→0 rows; insert uses `getFreshTenantClient(founderId)` (tenant-scoped) and routes through `assertWriteScope` seam.
- `reasoning-narration-frame.test.ts`: NOT in `BufferedWSMessage`; ws-client reducer clears `liveNarration` on `clear_streams`/`enter_stopping`/`timeout`/`onclose` (one assertion each).
- `turn-summary-bubble.test.tsx` (in `test/components/`, vitest glob): emerald box + `formatAssistantText`.
- DSAR: `message_kind='turn_summary'` exports with **un-redacted `content`**; **conversation-row delete** (distinct from account-delete [Kieran P2-5]) cascades the row away.
- Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; tests `./node_modules/.bin/vitest run <path>`.

## Files to Create
- `apps/web-platform/supabase/migrations/105_turn_summary_message_kind.sql` + `.down.sql`
- `apps/web-platform/components/chat/turn-summary-bubble.tsx`
- `apps/web-platform/server/messages/insert-turn-summary.ts`
- `apps/web-platform/server/narrate-tool.ts` (or extend `conversations-tools.ts`)
- `apps/web-platform/test/server/turn-summary-emit.test.ts`
- `apps/web-platform/test/components/turn-summary-bubble.test.tsx`
- `apps/web-platform/test/server/reasoning-narration-frame.test.ts`

## Files to Edit
- `lib/types.ts`, `lib/ws-zod-schemas.ts`, `server/stream-replay-buffer.ts`
- `lib/chat-state-machine.ts`, `lib/ws-client.ts` (liveNarration ownership + hydrate + both-path teardown)
- `components/chat/chat-surface.tsx`, `server/cc-dispatcher.ts`, `server/api-messages.ts`
- `server/tool-tiers.ts`, `server/permission-callback.ts`
- `server/inngest/leader-prompts/prompt-assembly.ts` + `constants.ts`
- **`server/dsar-export.ts`** (`message_kind` → `MESSAGE_NON_REDACT_ALLOWLIST`) [CRITICAL]
- **4 legal docs + PA-2:** `article-30-register.md`, privacy-policy, GDPR policy, Data Protection Disclosure, compliance-posture

## User-Brand Impact
**If this lands broken, the user experiences:** a "✓ Done" summary on a failed turn (false completion),
a live line that never disappears, or jargon/another tenant's data in their permanent chat history.
**If this leaks, the user's data is exposed via:** an agent-authored summary persisted into their
exportable chat record naming internal routing, file paths, or another tenant's data.
**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true`. `user-impact-reviewer`
runs at PR review, **specifically tasked with the "another-tenant-data-in-prose" vector** — the real
controls are the RLS tenant-client + the prompt directive (the redaction probe scrubs paths/jargon, not
cross-tenant prose; `assertWriteScope` is a no-op placeholder today, not a control).

## Domain Review
**Domains relevant:** Product, Legal, Engineering (carry-forward).
### Legal (CLO) — reviewed; gdpr-gate run
Permitted-with-guardrails. CRITICAL: `message_kind`→allowlist (build-blocking). HIGH: `user_id=founderId`
(Art-15(4)); amend PA-2 not new PA. MEDIUM: 4-doc cross-document gate; Art-22 negative determination;
cross-tenant prose control via RLS tenant-client + prompt; conversation-delete cascade covers the row.
### Engineering (CTO) — reviewed (carry-forward)
Distinct persisted type; never promote `debug_event`. **Deepen-plan must resolve [Kieran P1-1]:** the
`narrate`/`summarize` emit channel — tool registration surface + `leaderId` source — and confirm the
single-leader assumption before Phase 5.
### Product/UX Gate
**Tier:** blocking (new component). **Decision:** reviewed. **Agents:** ux-design-lead (brainstorm 3.55),
spec-flow-analyzer (plan 2.5). **Skipped:** none. **Pencil available:** yes (`reasoning-narration.pen` 05-07).
spec-flow P0/P1 folded: ws-client liveNarration relocation, abort-race guard, reconnect placeholder. Frame 07
caption + reconnect frame are /work wireframe tasks.

## GDPR / Compliance (Phase 2.7 — gdpr-gate run)
Critical 1 / High 2 / Medium 3 — all folded. Central claim verified: messages-table reuse → DSAR export +
Art-17 erasure scope, conditional on `user_id=founderId`. Not legal advice; CLO-attestation at Phase 7.

## Observability
```yaml
liveness_signal:
  what: turn_summary insert + emit count per conversation
  cadence: per substantive successful turn
  alert_target: Sentry (op "reasoning-narration:summary-emit")
  configured_in: server/cc-dispatcher.ts emitNarration()
error_reporting:
  destination: Sentry via reportSilentFallback
  fail_loud: true — redaction-probe trip drops the frame AND mirrors to Sentry; never silently persist
failure_modes:
  - mode: summary redaction-probe trip
    detection: emitNarration catch + reportSilentFallback
    alert_route: Sentry op "reasoning-narration:redaction-drop"
  - mode: insert-turn-summary DB error
    detection: insertTurnSummary catch
    alert_route: Sentry op "reasoning-narration:summary-insert-fail"
logs:
  where: pino structured (NO raw message body; log {conversationId, kind})
  retention: existing app-log retention
discoverability_test:
  command: "doppler run -p soleur -c prd -- curl -s <sentry-issues-api>?query=op:reasoning-narration | jq '.[].title'"
  expected_output: zero open issues on a healthy deploy; drops visible without SSH
```
(Speculative `summary-missing` / `final-after-abort-dropped` ops cut per plan-review; covered by tests.)

## Acceptance Criteria
### Pre-merge (PR)
- [ ] `tsc --noEmit` passes (all rails widened for 2 frames + ChatMessage variant).
- [ ] `git grep -n "reasoning_narration" server/stream-replay-buffer.ts` returns 0; `turn_summary` in `BUFFERED_FRAME_TYPE_MAP`.
- [ ] **`message_kind` in `MESSAGE_NON_REDACT_ALLOWLIST`**; `dsar-message-redact-fields-sweep.test.ts` passes.
- [ ] ws-client reducer test: `liveNarration` cleared on `clear_streams`, `enter_stopping`, `timeout`→error, `onclose` (one assertion each).
- [ ] Emit test: `summarize`→row w/ `user_id=founder` + redacted `content` + buffered frame; planted secret→redacted/dropped (assert stored row); abort/error→0 rows; `summarize` after abort→0 rows.
- [ ] `insertTurnSummary` uses `getFreshTenantClient(founderId)` and routes through the `assertWriteScope` seam.
- [ ] DSAR test: `turn_summary` exports with **un-redacted `content`**; conversation-delete cascades it away.
- [ ] `turn-summary-bubble.test.tsx` under `test/components/`; emerald box + `formatAssistantText`.
- [ ] Migration 105 additive nullable, `ADD COLUMN IF NOT EXISTS` + DO-block constraint guard; `.down.sql`; no `CONCURRENTLY`.
- [ ] `debug_event` untouched: `git diff --stat` shows no edits to `server/debug-event.ts` / `components/chat/debug-stream-panel.tsx`.
- [ ] 4 legal docs + PA-2 amended in lockstep (cross-document gate green).
- [ ] PR body uses `Closes #5370`.
### Post-merge (operator)
- [ ] Migration 105 applied via `web-platform-release.yml#migrate` (auto on merge). Automation: feasible.
- [ ] Read-only DSAR export probe (Supabase MCP, DEV only) confirms a `turn_summary` row exports **with un-redacted content**.
- [ ] CLO-attestation on PA-2 + 4 legal-doc amendments (incl. Art-22 negative determination).

## Risks & Mitigations
- **Live line persists on abort/timeout/disconnect** → ws-client reducer ownership + per-arm tests (spec-flow P0).
- **False "Done" on aborted turn** → `summarize` dropped when conversation aborted/stopping (spec-flow 1c).
- **`message_kind` blocks merge** → allowlist classification (legal CRITICAL).
- **DSAR redacts user's own summary** → `user_id=founderId` + un-redacted-export test (legal HIGH).
- **Cross-tenant data in agent prose (durable breach)** → RLS tenant-client + prompt directive + user-impact-reviewer; redaction probe alone insufficient; `assertWriteScope` is NOT a control today (legal MEDIUM / Kieran P1-2).
- **`narrate`/`summarize` emit-channel + leaderId plumbing unestablished** → deepen-plan resolves before Phase 5 (Kieran P1-1).
- **Union widening misses a consumer** → `tsc` + `_SchemaCovers` + `BUFFERED_FRAME_TYPE_MAP` (learning 2026-05-07).
- **NOT-NULL insert sweep** → `message_kind` nullable/undefaulted (learning 2026-06-04).

## Sharp Edges
- `## User-Brand Impact` filled (deepen-plan Phase 4.6 gate).
- `reasoning_narration` and `turn_summary` have OPPOSITE buffer membership AND live in different reducers — do not "tidy" together.
- `liveNarration` teardown lives in the ws-client reducer, NOT the message reducer (abort/error/disconnect emit no `StreamEvent`).
- `assertWriteScope` is a `return true` placeholder; the RLS tenant-client is the actual write-scope control.
- Do not co-locate the component test; vitest `include:` only collects `test/**`.

## Next: deepen-plan
`single-user incident` + ultrathink → run `soleur:deepen-plan` after this. Focus: CTO precedent-check on the
`narrate`/`summarize` emit channel + leaderId source + tool registration surface [Kieran P1-1];
data-integrity-guardian on the additive migration + redact-before-persist + `user_id` invariant;
security-sentinel on persisted-PII + cross-tenant prose.
