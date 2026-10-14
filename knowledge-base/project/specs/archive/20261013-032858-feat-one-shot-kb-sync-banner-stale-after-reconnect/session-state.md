# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-01-fix-kb-reconnect-banner-stale-after-reconnect-plan.md
- Status: complete

### Errors
None. CWD verified at start. Branch-safety check passed (feature branch, not main). All four deepen-plan mandatory gates passed inline (4.6 User-Brand Impact, 4.7 Observability 5-field schema, 4.8 PAT-shaped variable scan, 4.5 network-outage N/A). Subagent fan-out tooling unavailable in this environment; research/precedent-diff/verify-the-negative/live PR-issue checks run inline via Bash/grep.

### Decisions
- Root cause is server-side predicate signal divergence, not client wiring. Banner reads `repoNeedsReconnect(repo_status, users.github_installation_id)`, but real sync-capability is the workspace-scoped credential (`resolveInstallationId` → `resolve_workspace_installation_id` RPC, ADR-044). For org/workspace-shared installs `users.github_installation_id` is NULL by design → banner persists forever while sync resumes via the workspace credential.
- Fix adopts the existing canonical capability expression (`app/api/kb/sync/route.ts:101-106`). Adds async `resolveNeedsReconnect(repoStatus, userInstallationId, userId)` in `lib/repo-status.ts`, keeps `repoNeedsReconnect` pure, updates both derivation sites (`kb/tree/route.ts:39`, `settings/page.tsx:37`).
- Fail-toward-alarm + short-circuit: resolve RPC only in the `ready && user-column-null` branch (AC3, no extra round-trip on common path); null/error RPC keeps banner up so the #4706 silent-freeze still alarms (AC2 verify-the-negative).
- Placement de-risked: sole `.tsx` importer of `lib/repo-status` is the server component `settings/page.tsx` — no client importer, async resolver lands in `lib/repo-status.ts` with no client-bundle risk.
- Citations live-checked: #4712 CLOSED PR (banner origin, NULL-install workspaces), #4726 MERGED Sentry-only no-UI, #4728 OPEN issue / #4736 OPEN PR (orthogonal workspace_id discriminator, zero file overlap), #4706 MERGED PR. No open code-review issues touch edited files.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
