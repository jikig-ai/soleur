# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-26-fix-inngest-github-installation-token-401-plan.md
- Status: complete

### Errors
None

### Decisions
- Classified as `ops-only-prod-write` with `brand_survival_threshold: none` — error affects only operator-internal Inngest cron functions, not founder-facing surfaces
- Added hypothesis H7 (transient GitHub token replication delay) after deepen-pass discovered `@octokit/auth-app@8.2.0` has built-in 401-retry logic the hand-rolled `createAppJwt()` path lacks
- Corrected initial PEM-handling divergence hypothesis: both paths use identical `replace(/\\n/g, '\n')` normalization
- Added Phase 2.4 (retry-on-401 with fresh JWT) as hardening measure
- Diagnostic-first structure (Phase 0 read-only triage) before any code changes

### Components Invoked
- `soleur:plan` — created initial plan with 6 hypotheses, 3-phase structure
- `soleur:deepen-plan` — enhanced with `@octokit/auth-app` source analysis, added H7 + Phase 2.4
