---
title: "feat(chat): consolidated working-status box + in-turn activity trail (incl. ws boundary repair)"
type: feat
date: 2026-10-05
slug: feat-chat-working-status-trail
branch: feat-concierge-activity-trail
issue: 9515
closes: [9515]
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat(chat): consolidated working-status box + in-turn activity trail

## Overview

Two-PR delivery for issue #9515, from brainstorm 2026-10-05 (all operator
decisions locked). PR1 repairs a verified live defect: the
`KNOWN_WS_MESSAGE_TYPES` allowlist on `main` is missing 11
`WSMessage`/`ClosePreamble` union members, and `ws-client.ts` drops
non-allowlisted frames before Zod parse — so `reasoning_narration` never
reaches `liveNarration`, `turn_summary`'s live frame dies, `command_stream`
blocks never render, `stream_replay` gap-recovery never runs, and
`autonomous_disclosure`, `autonomous_posture` (the Auto-run chip's server
truth) and `revocation_notice` (the discriminated toast) silently die — 7 of
the 11 are actually dropped server→client frames (`membership_revoked` is
intercepted pre-allowlist, belt-and-suspenders). PR1 **deletes**
`isKnownWSMessageType` + `ws-known-types.ts` entirely: `parseWSMessage`'s zod
union already admits every legitimate frame and already breadcrumbs unknown
types via `ws-zod-parse-failure` — the allowlist is one call site that is a
strict subset of the parse that runs anyway (DHH panel finding; dissolves the
derivation ceremony and the entire drift class). PR2 consolidates the
in-turn status surface into one box carrying a session-only, plain-language
activity trail that collapses into the persisted `turn_summary` at turn end —
and fixes the orphaned "Working" box that duplicates the indicator after
navigation/reconnect.

## Problem Statement / Motivation

Operator report (3 defects + 1 follow-up): duplicated "Working…" badge +
"Still working…" line; generic status text while richer context exists in the
team-only Debug stream; status messages overwrite so no in-turn history; and
a second "Working…" box appears after navigating away and back.

Research found the complaint is partly a telemetry bug wearing a UX costume:
the rich content in the Debug stream (`debug_event` — allowlisted) cannot
reach the status surface because the user-facing frame family is dropped at
the boundary. Sentry confirms both sides: only 6 `command-center silent
fallback` events since Aug (few narration frames exist to drop — narrate
cadence is low), while `Unknown Bash verb` fires ~489×/14d (the label
fallback that manufactures "Working…").

## Proposed Solution

**PR1 — WS boundary repair (hotfix, lands first).** Delete
`isKnownWSMessageType` and `ws-known-types.ts` (~91 lines, 1 call site, 1
consumer test). `ws-client.ts:833` drops the pre-check; `parseWSMessage`'s
discriminated union is the single admission authority — a frame whose `type`
matches no schema variant already fails parse, and the existing failure path
reports `reportSilentFallback`. Preserve ops distinction in that path:
discriminator-miss (`type` matched no variant) → `op: ws-unknown-event`;
shape-miss (right type, bad payload) → `op: ws-zod-parse-failure`. Replace
`ws-known-types-guard.test.ts` with a boundary test: bogus type →
`ws-unknown-event` breadcrumb; valid `reasoning_narration` frame →
`set_live_narration`. A `soleur:incident` PIR for the ~4-month silent
frame-drop is part of this PR (CPO sign-off condition; PIR names all 7
actually-dropped paths incl. `autonomous_posture` + `revocation_notice`).

**PR2 — consolidation.** Single status box = the active `MessageBubble`:
delete the standalone `live-narration` slot; render the live status line +
bounded activity trail inside the bubble.

- **Trail model (simplified per panels):** `liveNarration` stays the
  current-step slot, torn down by its existing 5 arms — unchanged.
  `activity[]` holds **dimmed priors only**, stored on the tip
  `ChatTextMessage` (in `chat-state-machine.ts`, NOT `lib/types.ts` — the
  type is unexported there). When a new `tool_use`/`reasoning_narration`
  arrives, the previous live entry is pushed into `activity[]` (consecutive-
  dedup at push, stored cap `MAX_ACTIVITY_ENTRIES` mirroring
  `MAX_COMMAND_BLOCKS`). At bubble creation, `activity[]` is seeded from the
  pruned `tool_use_chip` labels (the pre-bubble steps the user already saw —
  no new `ChatState` queue; pre-bubble narration overwrites `liveNarration`
  as today, which seeds the bubble when it forms).
- **Teardown is free — no `stripTrail`.** Trail rendering is gated on the
  bubble being in a live-ish state (transitional or `interrupted`); on
  terminalization the trail stops rendering and the Done card stands alone.
  This deletes the 5-site teardown machinery entirely (simplicity panel).
- **Interrupted (flag, not state):** on `clear_streams`, a shared
  `sweepTransitional` helper sweeps `thinking`/`tool_use`/`streaming` bubbles
  to `state: undefined` + `interrupted: true` (+ strips `retrying` /
  `livenessRearms` — an orphan that timed out once otherwise pins the "No
  response yet" chip forever). `interrupted` renders a neutral chip (no
  Working pill, no ✓-complete lie, no amber border) and keeps its trail
  visible — a mid-turn flap preserves the history the buffered replay can't
  fully rebuild. A resuming `stream`/`tool_use` REBINDS to the interrupted
  bubble for that leader (`findInterruptedBubble(leader)` — the flag
  distinguishes it from hydrated rows, which also carry `state: undefined`) —
  clears the flag, resumes state, trail continues in place: one box per
  leader, seamless resume (operator decision at the review gate —
  overrode the panel's no-rebind lean; the `interrupted` marker remains
  honest DURING the gap). The rebind check precedes every transitional
  entry path — chip branch, `tool_use`, `tool_progress`, `stream`,
  `command_stream`, `stream_start` — or a replayed frame spawns a sibling
  box next to the interrupted one (the duplicate in a new costume). Same helper terminalizes `enter_stopping`, which today leaves
  the badge pinned post-abort. No `MessageState` union widening —
  `interrupted?: boolean` mirrors the `retrying` precedent.
- **`activeStreams` re-keyed by message id** (`Map<leaderId, messageId>` +
  `findIndex` at read sites, ~10 sites — `subagent_complete` id-scan is the
  precedent). Remap-on-prepend fixes 1 of ~6 index-invalidating sites; every
  chip-removal `filter` shifts absolute indices mid-turn with no navigation
  (verified cross-leader corruption: chip for leader A pruned while leader
  B's bubble is live shifts B's stored index → B's content stamps onto the
  wrong row). Also: add the missing `type === "text"` guard on the `tool_use`
  arm (stream/command_stream have it; the same unguarded-stamp class exists
  in `stream_end` + the gate sweeps — enumerate all); collapse `spawnIndex`
  to `Set<spawnId>` (`messageIdx`/`childIdx` are write-only vestiges).
  Committed decision (advisor+arch+kieran+CTO); DHH's bail-out noted only if
  the test-fixture sweep balloons — ~150 `activeStreams` constructions across
  ≥7 test files is the real cost (est. changed lines ~800-1000).
- **Elapsed:** `startedAt` stamped once on each trail/chip entry; the live
  line computes `Date.now() - startedAt` at render inside an `aria-hidden`
  node (own 1s tick — `tool_progress` stays watchdog-only; per the
  "no message mutation on the hot path" memo invariant, `tool_progress`
  writes nothing into `messages[]`). Seeded chip entries carry the chip's
  creation timestamp.
- **"Used:" chips deduplicate against the trail** — `toolsUsed` accumulation
  is folded into `activity[]` (one accumulator; the done-state chip row reads
  the dedup'd trail) rather than accumulating the same stream twice.
- **Copy:** full `session_ended.reason` → copy map (all ~10 snake_case
  enums — `idle_timeout`, `runner_runaway`, `cost_ceiling`, `session_revoked`
  … — currently echo raw onto the trust surface) + generic fallback that
  never echoes the token; `user_aborted` → "Stopped — send a new message to
  continue." Overflow copy respects singular ("…and 1 more step").
- **`mapBashVerb` widening (separable fast-follow inside PR2):** driven by
  the actual `Unknown Bash verb` distribution (Sentry 124542794) + CMO copy
  contract (verb-first gerund + business noun). Includes: git-subcommand
  allowlist → business-noun labels (raw subcommand echo violates the
  contract today: `git rev-parse` → "Checking git rev-parse"); normalize the
  U+2026-vs-ASCII "Working…" mismatch that breaks consecutive-dedup; a label
  shape test (leading gerund + banned tokens `soleur:`, `#`, `/`, backtick);
  re-look `doppler` → "Fetching secrets" (prefer "Fetching configuration" on
  a trust surface).

## Technical Considerations

- **No `WSMessage`/`ChatMessage`/`MessageState` union widening** —
  `activity[]`/`interrupted` are plain optional fields; `activeStreams`
  re-keying is internal.
- **Live-only invariants preserved** — `debug_event`/`reasoning_narration`
  stay out of `BufferedWSMessage` (#5240, #5290).
- **Orphan-box root cause (detective, high confidence):** `clear_streams`
  (dispatched on every `connect()`) empties `activeStreams` but never
  terminalizes `messages[].state` — a `tool_use`/`streaming` bubble keeps
  rendering "Working" forever (watchdog can't fire without an `activeStreams`
  entry) while the resumed stream opens a second bubble. StrictMode
  double-mount and mid-turn socket flaps both trigger it.
- **Import safety (CTO-verified):** `ws-known-types` deletion removes an
  import edge; no cycle risk (`ws-zod-schemas` → `{zod, types}` only).
- **PR1 activation surface:** unblocking `stream_replay` newly enables the
  `unrecoverable`+refetch flow (never run in prod) and a turn_summary
  synthetic-id/DB-id double-render edge — both named in rollout observations.
- **Zod boundary:** zod union error distinguishes discriminator-miss from
  shape-miss (variant `type` literal) — the op split is ~10 lines in the
  existing failure handler.
- **Tests:** RTL/vitest — boundary test (bogus → breadcrumb; narration →
  action), trail append/dedup/cap/seed, render-gate on terminalization,
  interrupted render, sweep at clear_streams + enter_stopping, suppression +
  aria-live, label shape test, memo-stability on non-tip messages.

## User-Brand Impact

- **If this lands broken, the user experiences:** the `/chat` Concierge
  working-status box showing wrong, duplicated, or permanently-stuck
  "Working…" during a real turn — the product's core trust surface lying
  about whether work is happening.
- **If this leaks, the user's workflow is exposed via:** none — trail content
  is session-only (never persisted, never exported); plain-language labels
  only.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the status surface is the product's
  "work is happening" promise — a lie there is a single-user trust incident.

## Observability

```yaml
liveness_signal:
  what: "ws-unknown-event Sentry breadcrumb count post-merge == 0 for the newly-admitted types; 'Unknown Bash verb' rate trend down after mapBashVerb widening"
  cadence: per deploy window; 7-day post-PR1 narration-cadence observation (feeds NARRATION_PROMPT_DIRECTIVE tuning decision)
  alert_target: sentry:project web-platform
  configured_in: sentry
error_reporting:
  destination: "Sentry reportSilentFallback (op: ws-unknown-event / ws-zod-parse-failure) + vitest"
  fail_loud: "unknown-type frames breadcrumb via the parse boundary; _SchemaCovers compile rail + boundary test cover admission"
failure_modes:
  - mode: "schema drifts from union (new frame without schema)"
    detection: "_SchemaCovers type rail fails tsc; boundary test"
    alert_route: ci
  - mode: "trail renders on a terminalized bubble (never collapses)"
    detection: "render-gate reducer/render tests; QA screenshot"
    alert_route: ci
  - mode: "orphan Working box persists post-reconnect"
    detection: "sweep tests + manual navigate-away-return QA"
    alert_route: ci
  - mode: "PR1 activates a path with no prod history (stream_replay unrecoverable, turn_summary double-render, autonomous_posture chip)"
    detection: "7-day rollout observation on Sentry + session chat smoke"
    alert_route: sentry
logs:
  where: "Sentry breadcrumbs (ws-unknown-event, tool-label-fallback), pino stdout"
  retention: sentry default
discoverability_test:
  command: "grep -c reasoning_narration apps/web-platform/lib/ws-zod-schemas.ts"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — WS frame admission (schema-is-authority)

**Property.** Every frame valid per `wsMessageSchema` reaches the reducer;
every frame whose `type` matches no schema variant reports
`ws-unknown-event` before dispatch.

**Assembly.** The zod discriminated union itself — members enter via
`ws-zod-schemas.ts` variants, coverage proved bidirectionally by the
existing `_SchemaCovers` type rail (union ↔ schema). Population is DERIVED
from the parse authority; there is no second literal to drift.

**Mutation matrix.**
  | Mutation | Expected |
  |---|---|
  | Add `WSMessage` variant without a schema | tsc RED (`_SchemaCovers`) |
  | Add a schema variant without a union member | tsc RED (`_SchemaCovers`) |
  | Remove the op split (all misses → one op) | vitest RED (bogus-type → `ws-unknown-event` asserted) |
  | Restore a pre-parse `type` allowlist check | vitest RED (boundary test asserts parse handles admission) |
  | Dispatch a bogus-`type` frame | `ws-unknown-event` breadcrumb (must-PASS for the report, must-REJECT for dispatch) |
  | Dispatch a valid `reasoning_narration` frame | `set_live_narration` (precondition-satisfying row: admitted AND routed) |
**Anchor.** Schema ↔ union are two artifacts in the same diff discipline;
`_SchemaCovers` is a compile-time rail — weakening requires editing both
schema and union, which tsc flags.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the UX is not great on the still working as we have the working also in the box above. We should find a way to merge them and keep only the box" | FR2 single status surface / PR2 | mapped |
| 2 | "working is pretty generic. We should try to mimic the experience of all AI Harness provider and provide more information on what is happening such as the first sentence in the debug stream" | FR3 plain-language trail / PR2 | mapped |
| 3 | "sometimes the messages do appear in the Working box but they get overwritten by Working so there is no history in the chat really" | FR3 activity trail (session-only) | mapped |
| 4 | "sometimes we get two Working boxes (I changed screen and came back)" | interrupted-sweep + id-keyed activeStreams / PR2 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| PR1 ws boundary repair | — | inferred — prerequisite defect; operator approved "Fix first, then redesign" |
| Session-only trail | "Session-only trail" (AskUserQuestion selection) | asked |
| Plain-language steps | "Plain-language steps" (AskUserQuestion selection) | asked |
| Collapse into summary | "Collapse into summary" (AskUserQuestion selection) | asked |
| mapBashVerb widening | — | inferred — 489 `Unknown Bash verb` events/14d; without it the trail reads "Working…" (separable fast-follow) |
| session_ended copy map | — | inferred — same trust-surface jargon class the operator flagged ("Working" generic); CMO P1: all ~10 reasons echo raw today |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (lib + components + server + test)
- Planned files: ~14 | Estimated changed lines: ~900 (id-rekey test sweep is ~half)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — two PRs (PR1 boundary repair, PR2 UX
  consolidation) per operator decision; delivery split, not scope split

## Acceptance Criteria

- [ ] **PR1:** `isKnownWSMessageType` + `ws-known-types.ts` deleted;
  `parseWSMessage` is the sole admission authority; discriminator-miss frames
  report `op: ws-unknown-event`, shape-miss `op: ws-zod-parse-failure`.
- [ ] **PR1:** boundary test replaces `ws-known-types-guard.test.ts` — bogus
  type → `ws-unknown-event` breadcrumb + no dispatch; valid
  `reasoning_narration` → `set_live_narration`.
- [x] ~~**PR1:** `soleur:incident` PIR filed + linked before merge~~ — SKIPPED
  by operator decision 2026-10-05 (draft was written + sentinel-cleared;
  operator chose not to commit it. Draft preserved at /tmp/pir-draft.md).
- [ ] **PR2:** exactly one in-turn status surface — standalone
  `live-narration` slot deleted; no second "Working" box after
  navigate-away-and-return (transitional bubbles sweep to
  `interrupted` flag on `clear_streams`/`enter_stopping` via one
  `sweepTransitional` helper; resuming frames rebind via
  `findInterruptedBubble` checked ahead of all transitional entry paths;
  `activeStreams` re-keyed by message id).
- [ ] **PR2:** the box shows current step (`liveNarration`) + dimmed priors
  (`activity[]`, consecutive-dedup, ≤5 visible + "…and N more steps" singular-
  aware, stored cap); seeded from pruned chip labels; trail renders only on
  live-ish bubbles (free teardown) and survives on `interrupted` cards;
  `awaitingUserInput` suppression (badge+live-line only, trail visible,
  border neutral, newest row normal weight) + `aria-live` preserved, elapsed
  in `aria-hidden`; `--text-muted` ≥4.5:1 for dimmed rows (no .pen opacity
  literals).
- [ ] **PR2:** `session_ended` renders via a complete reason→copy map with a
  non-echoing fallback; `user_aborted` → "Stopped — send a new message to
  continue." `turn_summary` remains the only durable record.
- [ ] `mapBashVerb` widening covers the top verbs in Sentry 124542794 under
  the copy contract + shape test (or records irreducible-noise rationale);
  git-subcommand allowlist; ellipsis normalized to U+2026.
- [ ] Each PR body names its rollback (revert).

## Test Scenarios

- Given a frame with a bogus `type`, when the boundary runs, then
  `ws-unknown-event` reports and nothing dispatches; given a valid
  `reasoning_narration` frame, then `set_live_narration` fires (regression:
  previously dropped).
- Given `tool_use` A, `tool_use` A, `tool_use` B, when rendered, then the
  trail shows A once + B; given 7 distinct steps, then 5 shown + "…and 2
  more steps"; given 1 hidden, then "…and 1 more step".
- Given chips before any `ChatTextMessage`, when the first `stream` creates
  the bubble, then `activity[]` is seeded from the pruned chip labels.
- Given a `tool_use` bubble when `clear_streams` fires (reconnect), then the
  bubble sweeps to `interrupted` (neutral chip, trail visible, no Working
  pill) and a resuming `stream` opens a FRESH box — never two Working boxes,
  never an abandoned done-shell.
- Given `enter_stopping`, when the bubble renders, then the Working badge is
  cleared (swept) and later `tool_use` frames do not re-append.
- Given `awaitingUserInput` (unresolved review_gate), when frames arrive,
  then badge+live-line are suppressed and the trail stays visible.
- Given `tool_progress` heartbeats, when they arrive, then `messages[]` is
  not mutated (memo stability asserted on non-tip messages); elapsed ticks
  render-side.
- **Browser (soleur:qa):** `/chat` send a message → one box, trail grows
  with plain-language steps → navigate away + return mid-turn → one Working
  box (+ possible honest Interrupted card) → turn ends → trail gone, Done
  card present.

## Success Metrics

- `ws-unknown-event` events for the newly-admitted types: trend to 0
  post-merge (7-day observation window).
- `command-center silent fallback` events: rises initially (narration now
  arrives where it was silently dropped — expected).
- `Unknown Bash verb` rate: measurably lower after the scoped widening.
- Zero duplicate-indicator reports on the session chat surface.

## Dependencies & Risks

- **Id-rekey test-fixture sweep** (~150 `activeStreams` constructions in ≥7
  test files) — the estimate's biggest risk; DHH bail-out: 3-line
  `+= unique.length` remap in `filter_prepend` if the re-key balloons.
- **PR1 activates never-run paths** — `stream_replay` unrecoverable+refetch,
  `autonomous_posture` chip, `revocation_notice` toast, live `turn_summary`
  synthetic-id vs refetched DB-id double-render edge. Mitigation: rollout
  observation register + PR1 smoke test on session chat.
- **Narration flood post-PR1** — dedup + cap bound it; cadence observed in
  the 7-day window before tuning `NARRATION_PROMPT_DIRECTIVE`.
- **Multi-leader flat trail** — accepted residual (single-leader cc today);
  attribution is a follow-up, not scope.

## Open Code-Review Overlap

3 open `code-review` issues touch planned files (checked 2026-10-05):

- **#3280** (reducer-driven history-fetch) — **acknowledge + coordinate.** Our
  id-keying survives any `messages[]` reorder; may be subsumed if #3280 lands
  first. Note in PR body.
- **#3374** (`slot_reclaimed` frame) — **acknowledge.** Post-PR1, a new frame
  needs only a schema + union entry; admission is automatic — the drift class
  is gone, not re-gated.
- **#3242** (raw tool `name` for agent consumers) — **acknowledge.**
  Different need; we avoid widening `tool_use` entirely.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `tool_progress` needs `toolUseId` widening (TR4) | cc forwards `tool_progress` since #5214; messages-mutation on hot path violates memo invariant | No widening — `startedAt` + render-side elapsed |
| Narration frames carry labels users should see | Dropped pre-Zod AND `narrate` cadence low (6 events since Aug) | PR1 unblocks the channel; floor comes from `tool_use.label` + measured `mapBashVerb` widening |
| Debug stream content can feed the trail | `debug_event.body` is jargon + spec #5370 non-goal | Sources = `tool_use.label` + `reasoning_narration` only |
| `activity[]`/types on `lib/types.ts` | `ChatTextMessage` lives (unexported) in `chat-state-machine.ts:101` | Fields added there; `lib/types.ts` only for any exported `ActivityEntry` type |

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing

### Engineering

**Status:** reviewed
**Assessment:** All asks feasible without new agent emissions. Session-only
trail (Option C) — zero buffer/schema/DSAR changes. Preserve #5240/#5290
live-only invariants. (CTO, brainstorm carry-forward + named-panel recheck:
no import-cycle risk, id-keying endorsed, split boundary correct.)

### Legal

**Status:** reviewed
**Assessment:** Ephemeral trail has no new legal surface; persistence (if
ever) requires privacy-policy amendment first + gdpr-gate. (CLO, carry-forward.)

### Marketing

**Status:** reviewed
**Assessment:** Copy contract — verb-first gerund + business noun; dedup;
"Working…" stays honest fallback. (CMO carry-forward + named-panel: full
reason→copy map, subcommand allowlist, ellipsis normalization, label shape
test, actionable "Stopped" copy — all folded into scope.)

### Product/UX Gate

**Tier:** blocking (new `components/chat/activity-trail.tsx`)
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** none — `.pen` committed + operator-approved 2026-10-05
(`knowledge-base/product/design/app-ui/concierge-activity-trail.pen`)
**Pencil available:** yes

#### Findings

- **spec-flow-analyzer:** 7 gaps found → folded in as Spec-Flow Revisions
  (below); recheck confirmed all resolved + added NG1-NG5 (resolved in this
  revision: interrupted-as-flag not state, chip-seed dissolves
  pendingNarration, render-gate dissolves stripTrail, elapsed render tick +
  chip timestamps, teardown-arm conditionality absorbed by render-gate).
- **CPO (Phase 2.6):** APPROVED, `single-user incident` confirmed; 3
  conditions embedded (PIR→AC, mapBashVerb+CMO-contract→AC, navigate-away QA
  + 7-day observation window). Recheck: CONFIRM sign-off.
- **ux-design-lead (named panel):** interrupted gets a neutral-chip spec
  (no Working pill / no ✓ / no amber border); trail survives on interrupted;
  elapsed `aria-hidden`; dimming via `--text-muted` ≥4.5:1 not .pen opacity;
  parked-gate: neutral border + newest row normal weight; PR1/PR2 ship
  adjacently.

## Spec-Flow Revisions

1. **Pre-bubble seeding:** chip labels persist as the trail's seed — on
   bubble creation, `activity[]` initializes from pruned `tool_use_chip`
   labels.
2. **Interrupted, not done-shell:** swept bubbles → `interrupted` flag
   (trail preserved); resumed stream REBINDS to the interrupted bubble
   (operator choice — seamless one-box resume; rebind finder precedes all
   transitional entry paths incl. the chip branch).
3. **Parked-gate scope:** suppress badge + live-line only; trail stays.
4. **Stopping:** `enter_stopping` runs `sweepTransitional` too.
5. **Abort copy:** full reason→copy map (CMO P1), not `user_aborted` alone.
6. **Replay degradation:** labels-only replayed trail — accepted, honest.
7. **Multi-leader host:** newest `activeStreams` tip; attribution residual.

## Research Insights

- **Premise Validation:** #9515 open; #9516 machinery (vacuous-guard class —
  still useful for the sweep even though this instance dissolves by
  deletion); spec #5363 merged; #2860 shipped; #5214 CLOSED (`tool_progress`
  forwarded on cc). No stale premises.
- **Property List:** (a) narration reaches client; (b) drift fails loudly;
  (c) one status surface; (d) visible in-turn step history; (e) honest
  teardown. **Cut List:** persisted trail; new wire/union variants; raw
  reasoning surface; `isKnownWSMessageType` replacement machinery (deleted
  per DHH — parse IS the allowlist); `pendingNarration` queue (dissolved);
  `stripTrail` (dissolved by render-gate); `MessageState` widening
  (`interrupted` flag instead).
- **Sentry measurements (live, 2026-10-05):** `Unknown Bash verb`
  (124542794) = 489/14d; `command-center silent fallback` = 6 since 08-06.
- **Verified claims (Kieran):** 11 missing members enumerated; 5
  `liveNarration` teardown arms; vacuous `_Exhaustive`; `membership_revoked`
  intercepted pre-allowlist (not actually dropped); `autonomous_posture` +
  `revocation_notice` dead handlers.
- **Working precedents:** `commandBlocks`/`toolsUsed`/`tool_use_chip`
  append+cap patterns; `_SchemaCovers` + `BUFFERED_FRAME_TYPE_MAP`
  non-vacuous proofs; `subagent_complete` id-scan; `retrying` flag;
  `findRecoverableErrorBubble`.
- **Learnings applied:** reducer-slice lifecycle audit (2026-04-27);
  bubble-lifecycle invariants (2026-04-23); ephemeral-vs-persisted
  (2026-06-15); enumerate reducer arms by grep (2026-05-13);
  resume-on-view ≠ activity (2026-09-30); make silent failure loud
  (2026-07-01); delete-over-fix (#2720/ADR-176 class).

## Files to Edit

- `apps/web-platform/lib/ws-client.ts` — drop allowlist pre-check; op split
  in parse-failure path; `session_ended` copy map (PR1 + PR2)
- `apps/web-platform/lib/chat-state-machine.ts` — `activity[]`/`interrupted`
  on `ChatTextMessage`; chip-seed; push-prev-on-new-entry; dedup+cap;
  `sweepTransitional`; id-keyed `activeStreams`; `type==="text"` guards;
  `spawnIndex`→`Set<spawnId>` (PR2)
- `apps/web-platform/components/chat/message-bubble.tsx` — live line + trail
  render inside box; `interrupted` chip; parked-gate render (PR2)
- `apps/web-platform/components/chat/chat-surface.tsx` — delete standalone
  slot; suppression fold (PR2)
- `apps/web-platform/server/tool-labels.ts` — `mapBashVerb` widening +
  subcommand allowlist + ellipsis normalize (PR2, measured)

## Files to Create

- `apps/web-platform/components/chat/activity-trail.tsx` — trail render
- `apps/web-platform/test/activity-trail.test.tsx` — render/dedup/cap/dim/aria
- `apps/web-platform/test/chat-state-machine-activity.test.ts` — append,
  seed, sweep, render-gate, id-key, memo stability
- `apps/web-platform/test/ws-boundary.test.ts` — bogus→breadcrumb; narration→
  action (PR1; replaces ws-known-types-guard.test.ts which is deleted)

## Files to Delete

- `apps/web-platform/lib/ws-known-types.ts` (PR1)
- `apps/web-platform/test/ws-known-types-guard.test.ts` (PR1)

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Rebuild allowlist (Record-literal or schema-derived Set) | Rejected — DHH: strict subset of `parseWSMessage` which runs anyway; deletes the drift class instead of re-gating it |
| Persisted trail (`message_kind='activity'`) | Rejected by operator — session-only |
| Rebind resuming stream to interrupted bubble | **Chosen** — operator decision (seamless one-box resume); finder precedes all transitional entry paths; `interrupted` flag disambiguates from hydrated rows |
| `interrupted` as `MessageState` member | Rejected — boolean flag (retrying precedent); skips union-widening consumer audit |
| `stripTrail` at 5 teardown sites | Rejected — render-gate on live-ish state; teardown is free |
| `pendingNarration` queue | Rejected — `liveNarration` is the pre-bubble slot; chips seed the trail |
| Reuse `debug_event` feed | Rejected — team-only, jargon, non-goal |
| `tool_use` `toolUseId` widening | Unneeded — latest-entry heuristic + `startedAt` |

## Post-Review Notes (2026-10-05)

Panel: DHH + Kieran + code-simplicity + arch-strategist + spec-flow (eng) and
ux-design-lead + CPO + CTO + CMO (named). All mechanical findings applied
inline above. Taste-class call resolved by operator: **rebind** — seamless resume into
one box (was no-rebind pending the review gate; updated inline).
