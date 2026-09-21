# Codex web controlled rollout tasks

Plan: `knowledge-base/project/plans/2026-09-21-feat-codex-web-controlled-rollout-plan.md`

- [ ] Record current production/Flagsmith/CI/release/deploy baseline and related issues.
- [ ] Add failing real-path conversation and routine tests, including credential mode, immutable binding, events, approvals, cancellation, reconciliation, attachments, usage, failure and no fallback.
- [ ] Wire Codex transport and credential selection through real handlers and persistence; pass focused/full tests.
- [ ] Run security and GDPR gates, independent review and UI QA/wireframe if settings UI changes.
- [ ] Run bounded synthetic/redacted live qualification separately for API-key and managed ChatGPT modes; write actual results and blockers.
- [ ] Complete mode-specific vendor evidence and CLO decision packet without assuming approval.
- [ ] Verify/create default-off Flagsmith feature; enable only bounded internal cohort after applicable gates pass; verify deployed settings and execution.
- [ ] Open PR, review, merge and verify main CI, release build, workflow-run deploy, expected `/health` SHA and live app smoke.
- [ ] Report implemented/tested, live-qualified, CLO-approved, internally enabled, customer-enabled and deployed as distinct statuses.
