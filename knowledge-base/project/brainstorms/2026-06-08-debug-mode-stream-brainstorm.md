---
title: Debug Mode — Workspace-Scoped Harness Instruction Stream
date: 2026-06-08
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
gdpr_gate_required: true
tags: [debug-mode, observability, feature-flag, websocket, redaction, internal-tooling]
related_issues: [5045]
related_efforts: ["#3603 cc-soleur-go transcript hardening"]
---

# Debug Mode — Workspace-Scoped Harness Instruction Stream

## What We're Building

A **Debug mode** for the web-platform conversation surface, available only to the
**Soleur org** (internal-staff `dev` cohort) and toggled per-workspace. When ON, the
conversation surface streams the **uncurated Claude Agent SDK message stream** — raw
`tool_use` name + (redacted) `tool_input`, full assistant reasoning text,
`tool_progress` heartbeats, and `result`/usage — into a **separate collapsed debug
panel** (never inline with user-facing messages). The goal is to let operators see
live what the harness is doing in the backend while dogfooding, to accelerate
harness improvement.

This is **internal tooling**, not a customer-roadmap feature. It accelerates the
Phase-4 dogfooding/harness-improvement loop that founder recruitment depends on.

## Why This Approach

The exact mechanism already exists in miniature. `command_stream` streams *real,
redacted* Bash command text to the conversation UI today, gated by a per-workspace,
membership-checked, fail-closed toggle (`workspaces.bash_autonomous`, migration 097 +
`resolve-bash-autonomous.ts`). Debug mode is a **generalization of that pattern** to
all tool-uses + assistant reasoning. We reuse three battle-tested precedents instead
of inventing:

1. **Frame contract** — the `command_stream` WS frame (`lib/types.ts:296-312`) and its
   redaction-gated emit in `cc-dispatcher.ts:2417-2456` are the literal template.
2. **Per-workspace toggle** — the `workspaces.bash_autonomous` column + member/owner
   SECURITY-DEFINER RPCs + fail-closed resolver (migration 097) is the template for a
   new `workspaces.debug_mode` column.
3. **Redaction pipeline** — `redactCommandForDisplay` + `probeRedactionFallthrough` +
   sandbox-path scrub, applied at the emit boundary and re-applied at render (dual-gate).

Debug mode is a **scoped, gated exception to the #2138 invariant** ("raw tool
names/inputs never reach the wire") — exactly as `command_stream` already is. Outside
the debug toggle, the invariant is unchanged.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Build now vs defer | **Build now** | Operator: accelerates Phase-4 dogfooding; no zero-cost out-of-band path exists (web harness drops the SDK stream in-process). |
| Surface | **Separate collapsed debug panel/drawer**, never inline | CPO: inline interleave pollutes the conversation that is itself the product under validation. |
| Scope of stream (v1) | **Uncurated SDK stream**: raw tool_use + redacted input + full assistant text + tool_progress + result | YAGNI; reuses existing loop + frame pattern. |
| Eligibility gate | **Soleur-org / `dev` cohort** via a Flagsmith availability flag (`debug-mode`) | Operator chose "anyone in the Soleur org." No "Soleur Workspace" constant exists; `dev` role is the internal-staff signal. |
| Per-workspace control | **`workspaces.debug_mode` column** + member/owner SECURITY-DEFINER RPCs, fail-closed resolver, cached on `ClientSession` at handshake | Per-workspace targeting does not exist in Flagsmith; bash_autonomous is the precedent. No per-message DB query. |
| Emission enforcement | **Server-side at emit**; flipped client flag can never unlock the stream | CLO + CTO: flag-state alone is single-control. |
| Content policy | **Everything except secrets** | Operator-only workspace; seeing orchestration IS the value. Proprietary-orchestration exposure is a non-issue within one's own org. |
| Persistence | **Ephemeral / render-only** — never written to `messages`, logs, or Sentry | CLO: persistence ⇒ new high-risk sink ⇒ DPIA. Write-boundary sentinel sweep enumerates debug-event types as never-persist. |
| Redaction site | **Event-construction site**, swept across every sink; before stream AND before any (future) persistence | Closest precedent (`2026-06-04-redaction-fix-must-sweep-all-render-sinks`): a token leaked because redaction was added only on the new path. |
| Redaction hardening | Extend `redactCommandForDisplay` beyond command-shaped tokens to **interpolated Doppler values, signed URLs, arbitrary token shapes in prose**; content-level, case-insensitive, Unicode-separator-aware; per-call random sentinels if tokenizing | CTO/learnings: redaction-coverage gap is the dominant brand risk. |
| WS protocol | New `debug_event` frame: declare cumulative-vs-delta semantics, emit terminal event, register in `KNOWN_WS_MESSAGE_TYPES`; client panel imports no `@/server/*` (pino bundle trap) | Learnings #3, #8. |
| Visual design | `.pen` wireframe (debug panel states + settings toggle): `knowledge-base/product/design/debug-mode/debug-mode-stream.pen` | wg-ui-feature-requires-pen-wireframe. |

### Deferred to follow-up (Non-Goals for v1)

- **True system-reminders + sub-agent internal transcripts** — not captured anywhere
  in the web harness today; would require net-new SDK `system`-message handling and
  sub-agent stream plumbing. (This is the gap between "uncurated SDK stream" and
  literal CLI-terminal parity.)
- **Persisted / saved debug transcripts** — separate plan + mandatory DPIA.
- **Customer-facing debug mode** — out of scope; this is internal tooling.

## Open Questions

1. **Soleur-org identity** — gate on the `dev`-role cohort (existing internal signal)
   vs. a new `debug-mode-orgs` Flagsmith segment pinned to a Soleur org id (no
   constant exists yet)? Lean: `dev` cohort for availability; revisit if a non-`dev`
   Soleur teammate needs it. (CTO Open Q1.)
2. **Redaction coverage proof** — does the hardened redactor actually cover
   interpolated Doppler values + signed URLs in prompt *text* (not just command
   strings)? Must be proven with fixtures before ship; `probeRedactionFallthrough`
   must fail-closed (drop frame on suspected-secret match), not best-effort.
3. **Toggle ownership** — workspace owner sets `debug_mode`, members read? Or per-user
   client toggle gated by server-side eligibility? (bash_autonomous = owner-write,
   member-read.)
4. **Stream volume / cost caps** — full uncurated stream is high-bandwidth; mirror
   `COMMAND_STREAM_*_CAP_BYTES` caps and log truncation.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). (Marketing, Operations,
Sales, Finance, Support not relevant — internal operator tooling.)

### Engineering (CTO)

**Summary:** The streaming channel, the SDK-iterator tap seam (`cc-dispatcher.ts` /
`agent-runner.ts:1842`), and the redaction primitive all exist; the two structural
items are (a) per-workspace gating (no Flagsmith grain — use a `workspaces.debug_mode`
column) and (b) hardening redaction beyond command-shaped tokens, which is the
dominant brand risk. Smallest viable: new `debug_event` zod frame emitted server-side
through a hardened redactor, ephemeral, rendered in a collapsed panel.

### Product (CPO)

**Summary:** This is internal tooling, not a customer feature, and was not on the
Phase-4 roadmap — but the "just read logs" alternative does not exist for the web
surface (the harness drops its stream in-process), so it is not gold-plating relative
to a free option. Must be a separate panel, never inline, to avoid polluting the
conversation surface under validation. Spec as internal tooling; reuse the existing
4.9 monitoring slot rather than adding a customer roadmap row.

### Legal (CLO)

**Summary:** No new processing *purpose* (rides on registered PA-2 Conversation Data),
but it widens the *content* flowing into that sink to include secrets and harness
internals — so the posture turns entirely on render-only vs persisted. Founder-grade
**only if ephemeral/render-only**; any persistence to DB/logs/Sentry crosses into a
new high-risk surface requiring a DPIA (Art. 35). Required guardrails: ephemeral-only
(write-boundary sentinel sweep), server-side workspace/cohort assertion at emit (not
flag-state alone) + alarm on mismatch, secret-redaction at source.

## User-Brand Impact

- **Artifact:** the live conversation surface (web-platform), backed by the SDK
  `query()` loop in `cc-dispatcher.ts` / `agent-runner.ts`.
- **Vector:** (1) secrets/PII interpolated into harness instructions rendered into the
  stream; (2) cross-tenant exposure if the eligibility gate mis-targets a non-Soleur
  org/workspace; (3) trust breach from exposing proprietary orchestration outside the
  operator cohort.
- **Threshold:** `single-user incident`. A single leaked Doppler value or a single
  mis-flipped gate to a customer tenant is the brand-survival event.
- **Controls (fail-closed):** ephemeral-only; server-side emission gate (cohort +
  workspace assertion, not client flag); hardened redaction at the construction site
  swept across all sinks, with `probeRedactionFallthrough` dropping frames on
  suspected-secret match; membership enforced in app code (the runner uses the
  service client which bypasses RLS).

## Capability Gaps

None that block. Process gates that MUST run (evidence cited):
- **`soleur:gdpr-gate`** on this surface before ship — `hr-gdpr-gate-on-regulated-data-surfaces`;
  sibling umbrella #3603 already GDPR-gates this exact conversation-persistence path.
- **`user-impact-reviewer`** at PR review — `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors`
  shows it repeatedly catches leak/tamper vectors plan-time review + unit tests miss.
- **Security review of the redaction-filter expansion** — the allowlist is
  command-shaped today (`lib/safety/redaction-allowlist.ts:212`); broadening it to
  prose is a new security boundary.

## Related Prior Art (load-bearing)

- `feat-concierge-stream-commands` / `command_stream` frame — the architecture in miniature.
- migration `097_workspace_bash_autonomous.sql` + `server/resolve-bash-autonomous.ts` — per-workspace toggle template.
- `lib/safety/redaction-allowlist.ts` (`redactCommandForDisplay`, `probeRedactionFallthrough`) — redaction route.
- `2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path.md` — sweep-all-sinks failure mode.
- `2026-04-13-websocket-cumulative-vs-delta-streaming-fix.md` — WS frame semantics.
- `#3603` cc-soleur-go transcript hardening — sibling effort; debug mode inherits its USER_BRAND_CRITICAL + GDPR obligations if persisted.
- #2138/#2115/#3235 — the "no raw tool inputs on the wire" invariant debug mode scopes an exception to.
