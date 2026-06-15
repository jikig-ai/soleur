---
date: 2026-06-15
topic: reasoning-narration-in-chat
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Reasoning narration in chat

## What We're Building

Give non-technical Soleur users a real-time sense of *what the agent is doing*, and a
durable plain-language record of *what it did* — **without** exposing the agent's raw
internal reasoning.

Two surfaces:

1. **Live narration (transient).** An agent-emitted, plain-language status line ("Looking
   into the navigation issue…", "Fixing it now…") shown live near the existing
   "Soleur Concierge / Working…" badge and tool-use chips. Updates in place as the turn
   progresses; **torn down when the turn ends** (success, abort, or error). Never persisted.
2. **Persisted turn summary (durable).** One plain-language summary box left in the main
   chat thread after each turn ("✓ Fixed the side panel — it now stays where you left it").
   A **new persisted message variant**, visually distinct (emerald checkmark + left-accent
   rail), surviving reload.

The **debug stream stays untouched** — team-only, dev-cohort-gated, ephemeral, live-only.

## Why This Approach

The operator's literal ask was "promote each `Reasoning` debug event into a confirmed box in
the main chat." The CPO/CLO/CTO triad converged that the literal mechanism is simultaneously
the most expensive to build, the heaviest legally, and the *weakest* UX — while the stated
*goal* ("users get a sense of what's happening") is best served by translated narration.

The decisive design choice: **the agent emits the user-facing narration deliberately**, as a
first-class output separate from its internal monologue. This means **no raw reasoning text
ever leaves the server**, which dissolves the central legal risk (promoting dev-calibrated
redacted content into a persisted user-visible record) instead of merely mitigating it.

Raw reasoning ("Issue #4826 … `fix/feat` intent → routing to `soleur:one-shot`") is the agent
talking to itself in operator jargon — noise for a non-technical user, full of hedging and
dead-ends. A confirmed box implies "this is true"; reasoning is neither confirmed nor finished.

## Key Decisions

| Decision | Choice | Source |
|----------|--------|--------|
| Surface shape | Live transient narration **+** persisted per-turn summary (mix of options 1 & 2) | Operator |
| Text source | **Agent emits deliberate user-facing narration**, separate from internal reasoning; no raw monologue persisted | Operator |
| Narration cadence | Milestone-paced (agent decides) — avoids per-event flooding | CTO |
| Live line lifecycle | Transient; torn down on turn-end regardless of outcome; never written to history | UX / CPO |
| Summary lifecycle | Persisted; one per turn; survives reload | Operator |
| Summary on abort/error | **Must NOT render the "Done" checkmark** — those turns keep their existing honest markers (`[stopped by user]`, "Agent stopped responding…") | UX (brand-critical) |
| Architecture | **Distinct new persisted message type**; do NOT reuse/promote `debug_event` | CTO |
| Debug stream | Untouched — team-only, ephemeral, live-only | CTO |
| Plain-language enforcement | Reuse existing `formatAssistantText` scrub (strips paths/jargon) on both surfaces | UX |
| Redaction-before-persist | Defense-in-depth on the summary, even though agent-authored | CLO / CTO |
| Visual design | `knowledge-base/product/design/chat/reasoning-narration.pen` (frames 05–07) | ux-design-lead |

## Open Questions

- **Summary generation trigger & content.** Summary emitted at `stream_end`/`workflow_ended`.
  Is it agent-authored at turn-end, or assembled from the milestone narration lines? (Leaning
  agent-authored for tone control.)
- **Cadence guardrails.** Even agent-paced, should there be a soft cap on live-line updates
  per turn to bound render churn? (CTO flagged frequency.)
- **Live narration vs existing chips.** Does the live line replace, or sit alongside, the
  existing `tool_use_chip` rendering? (Wireframe 05 places it above the chip.)
- **Multi-leader turns.** `/soleur:go` spawns multiple domain leaders — one narration line and
  one summary for the whole turn, or per-leader? (Default: one per turn, whole-turn summary.)
- **Empty/trivial turns.** Does a turn that does nothing user-visible still leave a summary box,
  or suppress it to avoid clutter?

## User-Brand Impact

- **Artifact:** the agent-emitted reasoning-narration line + the persisted turn-summary message
  variant in the web-platform chat surface.
- **Vector:** an agent-authored narration/summary line could leak internal routing detail, file
  paths, or (worst case) another tenant's data into a user's permanent, exportable chat record;
  or a "Done" summary could render on a turn that actually failed, asserting a false outcome.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(triad spawned per `USER_BRAND_CRITICAL=true`: Product, Legal, Engineering).

### Product (CPO)

**Summary:** Do not persist raw reasoning verbatim — it's operator jargon, hedged, and a
confirmed box implies a certainty reasoning doesn't have. The goal is *trust/progress narration*,
not transparency of internals. Recommended transient translated narration + a single optional
persisted summary, extending existing surfaces (`Working…` badge, `WorkflowLifecycleBar`,
tool-use chips) rather than a new verbatim box.

### Legal (CLO)

**Summary:** PERMITTED-WITH-GUARDRAILS. The legal weight attaches only to the *persisted*
surface: it becomes DSAR-exportable/erasable personal data (Art. 15/17), inherits a retention
clock, and any cross-tenant leak becomes a durable breach (Art. 33, 72h). The agent-emits-it
choice removes the dev-redaction-posture-inversion risk entirely. Remaining guardrails: confirm
DSAR export+erasure covers the new summary rows; defense-in-depth redaction-before-persist;
update Privacy Policy + Data Protection Disclosure + GDPR processing register; route doc
amendments through CLO-attestation.

### Engineering (CTO)

**Summary:** Build the user-facing path as a **distinct persisted message type** (sibling of the
existing persisted text message), never by promoting `debug_event`. Reusing `debug_event` would
break the `#5240` leader-liveness heartbeat and `#5290` reconnect-replay (both depend on
compiler-enforced live-only debug frames via `BUFFERED_FRAME_TYPE_MAP`). Medium build: new
migration + history-hydrate (`api-messages.ts`) + new buffered WS frame (4 lockstep edits in
`stream-replay-buffer.ts`) + `ChatMessage` variant & reducer case + render case in the MAIN map
+ Zod schema + redact-before-persist. Union-widening grep gates apply
(`cq-union-widening-grep-three-patterns`, `hr-type-widening-cross-consumer-grep`).

## Capability Gaps

None. Engineering, data-integrity (migration review), and gdpr-gate capabilities all exist in
the current domain (CTO confirmed via repo grep of the persistence + replay-buffer paths).

## Notes

- `#4826` in the original request is a **contextual citation** (the example reasoning event
  happened to be about restoring nav-rail position from #4826) — it is NOT the work target for
  this feature. Scrubbed to date-anchored prose to avoid one-shot's closed-issue collision gate.
