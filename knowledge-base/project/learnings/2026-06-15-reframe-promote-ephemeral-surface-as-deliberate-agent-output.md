# Learning: Reframe "promote the ephemeral internal artifact" as "emit a deliberate user-facing output"

## Problem

The operator asked to "make each `Reasoning` debug-stream event a confirmed box in the
main chat" so users get a sense of what's happening. Taken literally, this promotes a
**team-only, dev-cohort-gated, ephemeral, dev-redaction-calibrated** artifact (`debug_event`
kind `reasoning`) into a **persisted, all-user-visible** surface (the main chat). The
literal mechanism is the costliest build, the heaviest legally, and the *weakest* UX.

## Solution

The CPO/CLO/CTO triad reframed the **mechanism** while preserving the **goal**:

- **Decisive move:** have the agent *emit a deliberate, plain-language user-facing
  narration string* as a first-class output — distinct from its internal reasoning monologue.
- This **dissolves** the central legal risk (CLO: promoting dev-calibrated redacted content
  into a persisted user record — DSAR/retention/cross-tenant-breach posture inversion)
  rather than merely mitigating it: no raw internal text ever leaves the server.
- It also keeps the ephemeral path's **load-bearing invariants intact** (CTO): the
  `debug_event` family is compiler-enforced live-only via `BUFFERED_FRAME_TYPE_MAP`, and the
  `#5240` leader-liveness heartbeat + `#5290` reconnect-replay both depend on that. The
  user-facing path is a **distinct new persisted message type**, never a promotion of
  `debug_event`.

Final shape: transient agent-emitted narration line during a turn + one persisted
plain-language summary box per turn. Brainstorm: `2026-06-15-reasoning-narration-brainstorm.md`.
Spec: `specs/feat-reasoning-chat-boxes/spec.md`. Issue #5370. Draft PR #5363.

## Key Insight

When a request is phrased as "surface/promote the existing internal artifact X to users,"
check whether X is a *team-only / ephemeral / dev-calibrated* surface. If so, the strongest
design is usually **not** to widen X's audience+lifetime (which inverts its threat model and
often collides with invariants other features rely on), but to have the agent **emit a
separate, deliberate, audience-appropriate output**. Promoting the raw artifact mitigates
risk; emitting a purpose-built output *dissolves* it. The triad's job is to reframe the
**mechanism**, never the user's **goal**.

Corollary (verified here, reusable): a single upstream signal (the SDK reasoning string in
`cc-dispatcher.ts`) can fan out to two emitters with **opposite lifecycle contracts**
(ephemeral/dev-only vs. durable/all-user) — keep them as siblings, never couple them.

## Session Errors

1. **ux-design-lead wrote `.pen` artifacts to the bare-repo path before correcting into the
   worktree.** Recovery: the agent moved every artifact into the worktree and removed strays
   before reporting. Prevention: already owned by the ux-design-lead path convention; the
   bare-repo-vs-worktree CWD trap recurs for any worktree-spawned agent that resolves output
   paths — spawn prompts should state the worktree root explicitly (this one did, and the
   agent still slipped once then self-corrected). One-off; no rule change warranted.

## Tags
category: workflow-patterns
module: brainstorm / chat-surface
