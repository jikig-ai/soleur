# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-09-chore-decouple-zot-claim-from-ci-deploy-and-hmac-key-off-argv-plan.md
- Status: complete

### Errors
None blocking. Planner skipped research agents and plan-review panel (inline research only).

### Decisions
- Item 2: remove the version claim from ci-deploy.sh, point at provenance sidecar; add check 11.
- Item 3: HMAC key via environment to python3 -I snippet (no openssl option reads key from stdin/fd).
- Kill-switch marker lines on every commit body and the squash body.

### Components Invoked
soleur:plan, soleur:deepen-plan
