# Codex web controlled rollout tasks

Plan: `knowledge-base/project/plans/2026-09-21-feat-codex-web-controlled-rollout-plan.md`

Progress: OpenAI API-key credentials now use authenticated Web settings and an
encrypted per-user resolver; runtime composition selects the persisted auth mode,
composes the approved App Server launcher through stdio and lifecycle, and fails
closed when managed authorization, transport configuration, or Codex egress
evidence is absent; persisted Codex bindings now derive the auth mode without
client input; neutral Codex events have a tested mapping to the existing WebSocket
protocol; a persisted-binding conversation dispatch bridge now persists events and
emits those frames. Direct websocket handler wiring, managed authorization,
qualification, legal disposition, and rollout remain open.

- [ ] Record current production/Flagsmith/CI/release/deploy baseline and related issues.
- [ ] Add failing real-path conversation and routine tests, including credential mode, immutable binding, events, approvals, cancellation, reconciliation, attachments, usage, failure and no fallback.
- [ ] Wire Codex transport and credential selection through real handlers and persistence; pass focused/full tests.
- [ ] Run security and GDPR gates, independent review and UI QA/wireframe if settings UI changes.
- [ ] Run bounded synthetic/redacted live qualification separately for API-key and managed ChatGPT modes; write actual results and blockers.
- [ ] Complete mode-specific vendor evidence and CLO decision packet without assuming approval.
- [ ] Verify/create default-off Flagsmith feature; enable only bounded internal cohort after applicable gates pass; verify deployed settings and execution.
- [ ] Open PR, review, merge and verify main CI, release build, workflow-run deploy, expected `/health` SHA and live app smoke.
- [ ] Report implemented/tested, live-qualified, CLO-approved, internally enabled, customer-enabled and deployed as distinct statuses.
