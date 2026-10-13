## Summary

The Concierge per-conversation cost cap kills the conversation instead of
pausing it. Observed in production: at ~$4.28 of spend a managed session hit
`cost_ceiling` → terminal `session_ended` → *"This conversation reached the
per-workflow cost cap. Start a new conversation to continue."* Input is disabled,
context is lost, and the advised new conversation re-trips the same cap on the
same long-running task.

Two changes, scoped by credential type:

1. **Managed sessions** (user pays Soleur, not Anthropic directly): stop
   enforcing the per-conversation cap. Optional telemetry-only soft threshold
   for runaway visibility.
2. **BYOK sessions** (user's own Anthropic key): keep the cap but make it
   **resumable** — an in-chat interactive prompt offers preset raises
   ("raise to $5 / $10 / $25"), the per-conversation cap override persists, and
   `cost_ceiling` leaves `TERMINAL_WORKFLOW_END_STATUSES`.

User-Impact: Concierge chat page — a paying user's conversation is destroyed mid-task by a guardrail that exists to protect Soleur, not them.
Fix-Size: 300 lines / 10 files

## Acceptance criteria

- Managed-session conversations never terminate on the per-conversation cap.
- BYOK cap-hit renders an in-chat raise affordance; accepting bumps the cap and
  the conversation continues with context intact.
- The raised cap survives reload/reconnect (persisted per conversation).
- Declining keeps the cap and the conversation; the next agent send re-prompts.
- All `WorkflowEndStatus`/`session_ended` copy and parity tests updated.

## Artifacts

- Brainstorm: `knowledge-base/project/brainstorms/2026-10-05-cc-cap-raise-resume-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-cap-raise-resume/spec.md`
- Branch: `feat-cc-cap-raise-resume`
- Draft PR: #9560
