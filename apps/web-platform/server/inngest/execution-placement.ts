// Client-free execution-placement leaf (#7230, ADR-033 amendment 2026-09-28).
//
// Every function app/api/inngest/route.ts serves EXECUTES on the one step-executing host (web-1):
// the Inngest server calls steps at the registered serve URL (https://app.soleur.ai/api/inngest),
// which Cloudflare routes to web-1 only. `--sdk-url` on the dedicated Inngest host is the
// registration poll, not the step path. This leaf records where each function COULD run, so the
// ADR-143 Phase-3 flip (placement-aware execution, #9137) has a checked answer.
//
// Classify a function by the FIRST rule that matches:
//   volume-bound  it reads WORKSPACES_ROOT or reaches server/workspace.ts / server/workspace-resolver.ts
//                 (user workspaces): only the host holding the ADR-119 sole-copy LUKS workspaces
//                 volume (web-1 today).
//   host-affine   it spawns Claude or any child process, clones under CRON_WORKSPACE_ROOT, or takes
//                 the ADR-078 deploy lease: exactly one app host, sticky per run (a Claude spawn's
//                 single-flight is process-local, ADR-243 §2).
//   portable      none of the above: any host holding the prd secrets.
//
// Keyed by Inngest function id (`createFunction({ id })`), one row per served function. An
// `onFailure` handler is registered by the SDK as `<id>-failure` and inherits its parent's class;
// it has no row. test/server/inngest/execution-placement.test.ts enforces two things here: the rows
// are exactly the served set (Guard 1), and a `portable` row reaches no host-local dependency
// (Guard 2). The host-affine / volume-bound split is DECLARED and reviewed, not guarded, until the
// placement-aware registry of #9137 consumes it. Never widen the guard's allowlist to make a row
// pass; re-class the row instead.
//
// This module imports NOTHING (the suite asserts it), and no runtime module imports it today.
// Keep workflow file names out of the reason strings: Guard 3 scans every string under
// server/inngest/ for the names of Inngest's external verifiers.

/** The placement classes, in rule order. */
export const EXECUTION_PLACEMENTS = ["volume-bound", "host-affine", "portable"] as const;

export type ExecutionPlacement = (typeof EXECUTION_PLACEMENTS)[number];

export const EXECUTION_PLACEMENT: Readonly<Record<string, { placement: ExecutionPlacement; reason: string }>> = {
  "agent-on-spawn-requested": {
    placement: "volume-bound",
    reason: "reaches server/workspace-resolver.ts (WORKSPACES_ROOT): runs an agent against a user workspace",
  },
  "agent-on-spawn-settle": {
    placement: "volume-bound",
    reason: "reaches server/workspace-resolver.ts (WORKSPACES_ROOT) through the shared agent-on-spawn-requested module",
  },
  "cfo-on-payment-failed": {
    placement: "volume-bound",
    reason: "conservative pin: reaches server/workspace-resolver.ts only through byok-resolver.ts resolveCurrentWorkspaceId (a Supabase lookup, no filesystem access); moving that helper to a filesystem-free module unpins it (#9137)",
  },
  "cron-action-required-sla": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-actions-queue-health-dispatch": {
    placement: "portable",
    reason: "host-free: mints an actions:write-scoped App token and POSTs a workflow_dispatch; deliberately runner-independent so it fires while the GHA queue it measures is starved (#9273)",
  },
  "cron-merge-queue-stall-dispatch": {
    placement: "portable",
    reason: "host-free: mints an actions:write-scoped App token and POSTs a workflow_dispatch; the probe itself runs on a GitHub-hosted runner (#9482)",
  },
  "sla-issue-process": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-agent-native-audit": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-anthropic-cost-report": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-anthropic-credit-probe": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-architecture-diagram-sync": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-bot-pr-reaper": {
    placement: "portable",
    reason: "host-free: mints a repo-scoped App token and drives pulls/update-branch + check-runs + issues REST calls (needs prd secrets only)",
  },
  "cron-bug-fixer": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-campaign-calendar": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-cloud-task-heartbeat": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-community-monitor": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-competitive-analysis": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-content-generator": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-content-publisher": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-compound-promote": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-content-vendor-drift": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-daily-triage": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-dev-migration-drift": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-machinery-drain": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-domain-model-drift": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-email-ingress-probe": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-expenses-verify-by": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-follow-through-monitor": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-gh-pages-cert-reissue": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-github-app-drift-guard": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-github-cidr-refresh": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-growth-audit": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-growth-execution": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-inngest-config-drift": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-inngest-cron-watchdog": {
    placement: "portable",
    reason: "host-free, but calls the Inngest host's private API (10.0.1.40:8288): any web host on the private network, not any host with the secrets",
  },
  "cron-kb-template-health": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-legal-audit": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-linkedin-token-check": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-main-health-monitor": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-membership-health": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-nag-4216-readiness": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-oauth-probe": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-plausible-goals": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-review-reminder": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-roadmap-review": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-rule-prune": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-ruleset-bypass-audit": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-sentry-alert-drift": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-seo-aeo-audit": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-skill-freshness": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-stale-deferred-scope-outs": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-strategy-review": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-supabase-advisor-scan": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-supabase-disk-io": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-supabase-watchdog-dispatch": {
    placement: "portable",
    reason: "host-free: mints an actions:write-scoped App token and POSTs a workflow_dispatch; deliberately DB-independent so it survives the Postgres hang it dispatches against (#9168)",
  },
  "cron-terraform-drift": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-ux-audit": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "cron-weekly-analytics": {
    placement: "host-affine",
    reason: "ephemeral clone on CRON_WORKSPACE_ROOT (resolveCronWorkspaceRoot / setupEphemeralWorkspace)",
  },
  "cron-weekly-release-digest": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "cron-workspace-gc": {
    placement: "volume-bound",
    reason: "sweeps the /workspaces user-data volume directly (resolveCronWorkspaceRoot); it is also the GC for every host-affine clone root, so it must run wherever they run (#9137)",
  },
  "cron-workspace-sync-health": {
    placement: "volume-bound",
    reason: "user-workspace git health via server/session-sync.ts (child_process) and server/workspace-resolver.ts (WORKSPACES_ROOT)",
  },
  "email-on-received": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "event-cf-token-expiry-check": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "event-scheduled-reminder": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "event-ship-merge": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "github-on-event": {
    placement: "volume-bound",
    reason: "conservative pin: reaches server/workspace-resolver.ts only through byok-resolver.ts resolveCurrentWorkspaceId (a Supabase lookup, no filesystem access); moving that helper to a filesystem-free module unpins it (#9137)",
  },
  "oneshot-4650-monitor-close": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "oneshot-heartbeat-recovery-verify": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "oneshot-f2-defer-gate-review": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "oneshot-gdpr-gate-50d-eval": {
    placement: "portable",
    reason: "host-free: no host-local marker in its import closure (needs prd secrets only)",
  },
  "oneshot-recheck-4217-calibration": {
    placement: "host-affine",
    reason: "spawnClaudeEval in an ephemeral clone (process-local single-flight, ADR-243 §2)",
  },
  "workspace-reconcile-on-push": {
    placement: "volume-bound",
    reason: "reconciles user workspaces via server/session-sync.ts (child_process) and server/workspace-resolver.ts (WORKSPACES_ROOT)",
  },
};
