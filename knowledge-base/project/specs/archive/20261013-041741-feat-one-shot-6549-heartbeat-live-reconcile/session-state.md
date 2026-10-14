# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-feat-heartbeat-live-reconcile-drift-workflow-plan.md
- Status: complete

### Errors
None. (Two Better Stack Uptime API doc URLs 404'd during deepen; exact-contract check deferred to /work Phase 0.1, corroborated by in-repo heartbeat-manifest.ts:148 evidence that /api/v2/heartbeats returns `paused`.)

### Decisions
- Reconcile matches on the `.tf` `name =` attribute; excluding any heartbeat with a `count =` meta-arg keeps the two paid-tier-gated webhook heartbeats (item 1) out of scope, while git_data_prd (no count gate, absent live) triggers condition (b) — surfacing #6548's ask on first run.
- Auth (v1): reuse existing BETTERSTACK_API_TOKEN via `doppler secrets get --plain` (not a tf-var, gates no apply). Read-only least-privilege token filed as a fast-follow, not a merge blocker.
- Tri-state flake tolerance: transient 5xx/timeout → retry ≤3 backoff → exit 0 (UNREACHABLE, no page); confirmed mismatch → exit 2 + deduped GitHub issue + email + SOLEUR_* marker; auth/config error → exit 1. New sentry_cron_monitor.scheduled_heartbeat_reconcile gives the job its own liveness signal.
- ADR-117 amended (not superseded); ADR-122 is the new-ADR fallback.
- Deepen correction: sentry-monitor-iac-parity.test.ts needs no change (one-way code→IaC); pinned full sentry_cron_monitor attribute set against provider jianyuan/sentry 0.15.0-beta2.

### Components Invoked
- Skill soleur:plan, Skill soleur:deepen-plan, Agent learnings-researcher

### Scope guardrails
- #6549 left OPEN (item-2 box + PR ref only, item 1 untouched)
- #6548 left OPEN (referenced as context; git-data disposition deferred to first run)

## Work Phase (2026-07-17)
- MANIFEST had grown to 7 rows (workspaces_luks / #6604 landed after the plan's 4-row view); reconcile logic is generic over all rows, verified against real infra discovery (7 blocks, webhook rows count-gated).
- Plan Phase 4.2 correction: the plan only anticipated `sentry-monitor-iac-parity.test.ts` (tolerates GHA-fired). MISSED `function-registry-count.test.ts` (c2), which required adding `scheduled-heartbeat-reconcile` to `NON_INNGEST_MONITORS`. Done.
- Security review (background) flagged SSRF/credential-exfil: `pagination.next` from the response body was followed with the Bearer token attached. Fixed inline — pinned pagination to `uptime.betterstack.com` over HTTPS; added regression test asserting the token is never sent off-host.
- **Live dry-run (read-only, prd_terraform token):** registry_prd/inngest_prd/registry_disk_prd all live `up`/unpaused (registry armed by #6540 → no false (a) flag). `git_data_prd` absent-live → condition (b) (CONFIRMS #6548 ask #1: missing from the live provider). `workspaces_luks` ALSO absent-live (its uptime-alerts.tf monitor not yet applied to Better Stack — a legitimate second first-run finding, disposition belongs to #6604).
- D1 read-only-token fast-follow filed: #6635.
