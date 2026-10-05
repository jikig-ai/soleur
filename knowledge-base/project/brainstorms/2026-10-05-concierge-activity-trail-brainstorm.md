---
name: concierge-activity-trail
description: Brainstorm for the Concierge chat working-status surface — one consolidated box, plain-language in-turn activity trail, collapse into turn summary.
type: brainstorm
date: 2026-10-05
status: decided
lane: cross-domain
draft_pr: "#9514"
prior_art: "specs/feat-reasoning-chat-boxes (shipped, #5363); archive/20260423 command-center-activity-ux (shipped, #2860)"
---

# Concierge Working-Status Consolidation + Activity Trail — Brainstorm

## What We're Building

Three operator-reported defects on the Concierge session chat's in-turn status
surface (`apps/web-platform`):

1. **Duplicated "working" signal.** A boxed "Soleur Concierge / Working…" badge
   and a standalone "Still working…" line render simultaneously; after navigating
   away and back, a *second* "Working…" box appears — three indicators for one
   state.
2. **Generic status text.** The box says only "Working…" while richer context
   (reasoning first-line, plain-language tool descriptions) exists but never
   reaches the chat surface.
3. **No in-turn history.** Status text overwrites in place; the operator cannot
   see what steps happened during a turn.

**Inciting defect found during research (Phase 1.1, verified on `main`):**
`KNOWN_WS_MESSAGE_TYPES` (`apps/web-platform/lib/ws-known-types.ts`) is missing
11 wire types the union defines — including `reasoning_narration`,
`turn_summary`, `command_stream`, `stream_replay`, `autonomous_disclosure`,
`resume_stream`, `abort_turn`, `membership_revoked`, `revocation_notice`,
`autonomous_posture`, `autonomous_disclosure_response`. `ws-client.ts` drops
any non-allowlisted frame *before* Zod parse (`op: "ws-unknown-event"`), so
**narration can never reach `liveNarration` — the "Still working…" fallback is
permanent**, replay frames are dropped, and command blocks/autonomous cards
never render. The `_Exhaustive` compile-time proof is vacuous
(`new Set<AllowedWSMessageType>([...])` types elements as the full union, so
both `Exclude`s are always `never`), and the guard test pins the stale list —
drift is structurally invisible. This is the root cause of complaint 2 and a
contributor to complaints 1 and 3.

## Why This Approach

- **Fix the drift first, redesign second** (operator choice): the allowlist
  repair is a small prod hotfix that makes narration/turn-summary/command-
  stream frames actually arrive; the UX consolidation then builds on working
  frames. Two PRs keep the hotfix fast.
- **Session-only trail** (operator choice): entries accumulate inside the
  working box during the turn and fold away into the persisted `turn_summary`
  at turn end. Zero new persistence surface — reuses buffered `tool_use` /
  `tool_progress` / `reasoning_narration` frames; no migration, no DSAR/Art.30
  expansion, no `messages` schema change (CTO Option C; CLO's hard constraints
  are moot when nothing new persists).
- **Plain-language steps only** (operator choice): `buildToolLabel` verb labels
  + `narrate()` emissions — never raw commands, tool names, paths, skill names,
  or issue numbers (spec #5370 non-goal; CLO HC-2; CMO copy contract).
- **Collapse into summary** (operator choice): trail is torn down at turn end;
  the `TurnSummaryBubble` stays the durable record — preserves spec #5370's
  FR3/no-flood decisions while fixing the overwrite complaint.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Delivery shape | Two PRs: PR1 hotfix (`ws-known-types` sync + non-vacuous exhaustiveness + guard test), PR2 UX consolidation | Operator choice; hotfix unblocks narration immediately and is independently shippable |
| Indicator merge | Single working box; delete the standalone `live-narration` slot (`chat-surface.tsx`), render narration inside the active `MessageBubble` | Two renderers of one signal; keep `awaitingUserInput` suppression, `aria-live`, and the reconnect fallback inside the box |
| Duplicate box after navigation | Diagnose during work — likely the routing chip (`isClassifying` `MessageBubble`) plus an active/stale `tool_use` bubble; consolidate to one visible status box | Second screenshot shows two identical "Working…" boxes + the standalone line |
| Activity trail model | Session-only, in-box, appended per `tool_use`/`reasoning_narration` event on the tip bubble (reuse `toolsUsed`-style append on `ChatTextMessage`, `commandBlocks` precedent); update-in-place on `tool_progress` | Operator choice; CTO Option C — zero wire/persistence/DSAR changes, replay-safe within grace |
| Trail contents | Plain-language verb labels + narrate() lines; dedup consecutive identical; cap ~5 visible (older collapse to "…and N more steps"); latest highlighted, older dimmed | Operator choice; CMO noise guidance; `TOOL_USE_CHIP_CAP_PER_LEADER = 5` precedent |
| Trail end | Torn down on every turn-end path (same arms as `liveNarration` teardown); `turn_summary` remains the durable record | Operator choice; preserves spec #5370 FR3 + no-flood non-goal |
| Detail ceiling | No raw commands/paths/tool names/reasoning monologue — `debug_event` stays team-only; narrate contract unchanged | CLO HC-1/HC-2; spec #5370 non-goals; #2138 disclosure posture |
| `tool_progress` display | Show elapsed seconds on long-running steps ("Running command… · 45s") — in-place update, not a new entry | `tool_progress` already carries `toolName` + `elapsedSeconds`; heartbeat ≠ trail entry (render-churn risk) |
| Debug stream panel | Untouched — stays team-only, ephemeral | spec #5370 invariant |
| Visual design | `knowledge-base/product/design/app-ui/concierge-activity-trail.pen` (+ 4 state PNGs in `screenshots/`) — approved by operator 2026-10-05; taste-profile recorded (`app-ui`, `single-status-box-fading-trail`) | `wg-ui-feature-requires-pen-wireframe` |
| Productize candidate | Vacuous-proof audit — the `_Exhaustive` pattern that can never fail is a recurring defect class (`cq-assert-anchor-not-bare-token` cousins); a sweep for self-consistent-but-vacuous TS guards could be a future lint | Deferred item; filed as follow-up issue |

## Non-Goals

- Persisting the activity trail to `messages` (operator chose session-only;
  CTO Option B remains the documented fallback if durability is later required).
- Raw reasoning/commands/paths/tool names user-facing; `debug_event` reuse.
- Changing the debug-mode flag, debug panel, or its redaction posture.
- `narrate`/`summarize` tool contract changes (cadence prompting may follow —
  parked as an implementation question).
- The "N leaders responding" footer, usage/cost footer, and turn-summary card
  design (only its relationship to the collapsing trail).

## Open Questions

1. **Root cause of the double box after navigation** — is it the routing chip
   plus an active bubble, or a stale transitional bubble surviving rehydrate?
   (Plan/work-phase diagnosis; `hr` — investigated, not parked.)
2. **`tool_use` lacks `toolUseId`** — correlating a `tool_progress` heartbeat
   to its step needs a small wire widening; confirm shape at plan time.
3. **`mapBashVerb` fallback rate** — how often does the label degrade to
   "Working…"? Check the `tool-label-fallback` Sentry rate at plan time;
   may justify allowlist tightening as trail quality work.
4. **Multi-leader `/soleur:go` turns** — flat trail vs per-leader grouping;
   default flat (matches the single-slot `liveNarration` simplification).

## User-Brand Impact

- **Artifact:** the Concierge session chat's in-turn working-status surface
  (the `MessageBubble` working box + activity trail).
- **Vector:** worst case, a stuck or silently-failing session presents a generic
  or duplicated "Working…" while its real status is dropped client-side —
  hiding failure and eroding trust in the product's core surface.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** The three complaints map to three mechanisms; two are cheaper than
they look — `toolsUsed` already accumulates labels per turn, and the
`tool_use_chip` cap-5 pattern is the trail precedent. Recommended default:
single status surface, bounded live trail (latest + ≤5 dimmed), torn down at
turn end; keep the ✓ turn summary as the durable record. Warned that
"Working…" dominance may be an emission-cadence problem (`mapBashVerb`
fallbacks / narrate cadence), measurable via Sentry fallback rate.

### Legal

**Summary:** Ephemeral trail = no new legal surface; hard constraints apply
only if persistence is later chosen (no raw reasoning/commands/tool names;
privacy-policy "never stored" line must be amended *before* any persisted
variant ships; gdpr-gate mandatory; prefer `messages` over a new table).
Session-only trail inherits none of that.

### Engineering

**Summary:** All three asks feasible without new agent emissions — `tool_use.label`,
`tool_progress.toolName`, and `reasoning_narration` are already on the wire.
Option C (ephemeral client transcript) recommended: zero buffer lockstep edits,
no union widening, replay-safe; reject per-event persistence (N× writes, DSAR
growth, id-dedup hazard). Preserve the #5240 live-only `debug_event` invariant
and every `liveNarration` teardown arm.

### Marketing

**Summary:** The chat is the product promise made visible — a legible trail is
trust scaffolding and screenshot-able proof. Copy contract: verb-first gerund +
business-object noun ("Checking your open change requests…"), never
`soleur:*`/paths/`#NNNN`/git jargon; dedup noise ("Searching code… × 12" reads
as flailing); "Working…" stays the honest fallback.

## Session Findings (not errors)

- **Verified live defect:** `KNOWN_WS_MESSAGE_TYPES` missing 11 union members on
  `main`; drop confirmed at `ws-client.ts` `ws-unknown-event` guard; vacuous
  `_Exhaustive` proof confirmed by inspection. Filed inside this feature's PR1
  (not deferred — it blocks complaint 2).
- `ws-known-types-guard.test.ts` pins the stale list self-consistently — the
  test passes while the allowlist is wrong; PR1 must make the guard derive from
  the union, not a hand-maintained list.
