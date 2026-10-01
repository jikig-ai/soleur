# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-fix-leader-loop-prompt-caching-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Phase 2 draft superseded twice after measurement (Inngest serializer strips custom error name; message-tag protocol replaced by returned value).
- Deferral issue for timeout mislabel refused by filing hook (inline threshold) — folded into plan. Second filing became #8719.
- No Anthropic credential available; prompt sizes are char-based estimates.

### Decisions
- Caching per brief: no per-tool markers, one system-block marker, top-level automatic caching, 5m TTL (DC-1 records reviewer challenge to drop the system marker).
- Fold in timeout mislabel: classify inside the step, return deterministic failures; new reason `anthropic_request_rejected`.
- Tests extend existing leader-loop suite; class list from Object.keys(LEADER_PROMPTS); per-call request copies; manual mutation checks.
- Amend ADR-042 §I1 and §I5; no new ADR.
- Brand-survival threshold `aggregate pattern`; filed #8719 for missing Sentry alert rule.

### Components Invoked
- soleur:plan, claude-api, soleur:plan-review, soleur:deepen-plan, plus research/review agents.
