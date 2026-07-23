// PR-F (#3244, #3940) Phase 2 — Inngest serve route.
//
// Mounts the Inngest substrate at /api/inngest. ADR-030 invariant I4:
// signature verification required at startup — `signingKey` is sourced
// from INNGEST_SIGNING_KEY and the SDK enforces HMAC validation on every
// inbound POST in cloud mode (INNGEST_DEV unset or =0).
//
// Phase 2 ships with `functions: []`. Phase 3 will fill `cfoOnPaymentFailed`.
// Once functions are registered, the signature gate (validateSignature in
// node_modules/inngest/components/InngestCommHandler.js:1465) runs BEFORE
// any function dispatches — preserving the "401 before dispatch" invariant
// asserted by test/server/inngest/signature-verify.test.ts.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP method handlers
// are exported. RV6 (DHH/Simplicity): single-function-registry inlined;
// no separate functions/index.ts barrel module.

import { serve } from "inngest/next";
import { inngest } from "@/server/inngest/client";
import { agentOnSpawnRequested } from "@/server/inngest/functions/agent-on-spawn-requested";
import { cfoOnPaymentFailed } from "@/server/inngest/functions/cfo-on-payment-failed";
import { cronActionRequiredSla } from "@/server/inngest/functions/cron-action-required-sla";
import { cronAgentNativeAudit } from "@/server/inngest/functions/cron-agent-native-audit";
import { slaIssueProcess } from "@/server/inngest/functions/sla-issue-process";
import { cronAnthropicCostReport } from "@/server/inngest/functions/cron-anthropic-cost-report";
import { cronAnthropicCreditProbe } from "@/server/inngest/functions/cron-anthropic-credit-probe";
import { cronArchitectureDiagramSync } from "@/server/inngest/functions/cron-architecture-diagram-sync";
import { cronBugFixer } from "@/server/inngest/functions/cron-bug-fixer";
import { cronCampaignCalendar } from "@/server/inngest/functions/cron-campaign-calendar";
import { cronCloudTaskHeartbeat } from "@/server/inngest/functions/cron-cloud-task-heartbeat";
import { cronCommunityMonitor } from "@/server/inngest/functions/cron-community-monitor";
import { cronCompetitiveAnalysis } from "@/server/inngest/functions/cron-competitive-analysis";
import { cronCompoundPromote } from "@/server/inngest/functions/cron-compound-promote";
import { cronContentGenerator } from "@/server/inngest/functions/cron-content-generator";
import { cronContentPublisher } from "@/server/inngest/functions/cron-content-publisher";
import { cronContentVendorDrift } from "@/server/inngest/functions/cron-content-vendor-drift";
import { cronDailyTriage } from "@/server/inngest/functions/cron-daily-triage";
import { cronDevMigrationDrift } from "@/server/inngest/functions/cron-dev-migration-drift";
import { cronDomainModelDrift } from "@/server/inngest/functions/cron-domain-model-drift";
import { cronEmailIngressProbe } from "@/server/inngest/functions/cron-email-ingress-probe";
import { cronExpensesVerifyBy } from "@/server/inngest/functions/cron-expenses-verify-by";
import { cronFollowThroughMonitor } from "@/server/inngest/functions/cron-follow-through-monitor";
import { cronGhPagesCertReissue } from "@/server/inngest/functions/cron-gh-pages-cert-reissue";
import { cronGhPagesCertState } from "@/server/inngest/functions/cron-gh-pages-cert-state";
import { cronGhcrTokenMinter } from "@/server/inngest/functions/cron-ghcr-token-minter";
import { cronGithubAppDriftGuard } from "@/server/inngest/functions/cron-github-app-drift-guard";
import { cronGithubCidrRefresh } from "@/server/inngest/functions/cron-github-cidr-refresh";
import { cronGrowthAudit } from "@/server/inngest/functions/cron-growth-audit";
import { cronGrowthExecution } from "@/server/inngest/functions/cron-growth-execution";
import { cronInngestConfigDrift } from "@/server/inngest/functions/cron-inngest-config-drift";
import { cronInngestCronWatchdog } from "@/server/inngest/functions/cron-inngest-cron-watchdog";
import { cronKbTemplateHealth } from "@/server/inngest/functions/cron-kb-template-health";
import { cronLegalAudit } from "@/server/inngest/functions/cron-legal-audit";
import { cronLinkedinTokenCheck } from "@/server/inngest/functions/cron-linkedin-token-check";
import { cronMainHealthMonitor } from "@/server/inngest/functions/cron-main-health-monitor";
import { cronMembershipHealth } from "@/server/inngest/functions/cron-membership-health";
import { cronNag4216Readiness } from "@/server/inngest/functions/cron-nag-4216-readiness";
import { cronOauthProbe } from "@/server/inngest/functions/cron-oauth-probe";
import { cronPlausibleGoals } from "@/server/inngest/functions/cron-plausible-goals";
import { cronReviewReminder } from "@/server/inngest/functions/cron-review-reminder";
import { cronRoadmapReview } from "@/server/inngest/functions/cron-roadmap-review";
import { cronRulePrune } from "@/server/inngest/functions/cron-rule-prune";
import { cronRulesetBypassAudit } from "@/server/inngest/functions/cron-ruleset-bypass-audit";
import { cronSeoAeoAudit } from "@/server/inngest/functions/cron-seo-aeo-audit";
import { cronSkillFreshness } from "@/server/inngest/functions/cron-skill-freshness";
import { cronStaleDeferredScopeOuts } from "@/server/inngest/functions/cron-stale-deferred-scope-outs";
import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";
import { cronSupabaseAdvisorScan } from "@/server/inngest/functions/cron-supabase-advisor-scan";
import { cronSupabaseDiskIo } from "@/server/inngest/functions/cron-supabase-disk-io";
import { cronTerraformDrift } from "@/server/inngest/functions/cron-terraform-drift";
import { cronUxAudit } from "@/server/inngest/functions/cron-ux-audit";
import { cronWeeklyAnalytics } from "@/server/inngest/functions/cron-weekly-analytics";
import { cronWeeklyReleaseDigest } from "@/server/inngest/functions/cron-weekly-release-digest";
import { cronWorkspaceGc } from "@/server/inngest/functions/cron-workspace-gc";
import { cronWorkspaceSyncHealth } from "@/server/inngest/functions/cron-workspace-sync-health";
import { emailOnReceived } from "@/server/inngest/functions/email-on-received";
import { eventCfTokenExpiryCheck } from "@/server/inngest/functions/event-cf-token-expiry-check";
import { eventScheduledReminder } from "@/server/inngest/functions/event-scheduled-reminder";
import { eventShipMerge } from "@/server/inngest/functions/event-ship-merge";
import { githubOnEvent } from "@/server/inngest/functions/github-on-event";
import { oneshot4650MonitorClose } from "@/server/inngest/functions/oneshot-4650-monitor-close";
import { oneshotHeartbeatRecoveryVerify } from "@/server/inngest/functions/oneshot-heartbeat-recovery-verify";
import { oneshotF2DeferGateReview } from "@/server/inngest/functions/oneshot-f2-defer-gate-review";
import { oneshotGdprGate50dEval } from "@/server/inngest/functions/oneshot-gdpr-gate-50d-eval";
import { oneshotRecheck4217Calibration } from "@/server/inngest/functions/oneshot-recheck-4217-calibration";
import { workspaceReconcileOnPush } from "@/server/inngest/functions/workspace-reconcile-on-push";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
// next build page-data collection loads this module without runtime env.
// Skip the throw during build; runtime process restart on Hetzner re-fires
// the validation against Doppler-injected env. Mirrors the bypass in
// server/inngest/client.ts.
const IS_BUILD_PHASE = process.env.NEXT_PHASE === "phase-production-build";
if (!IS_BUILD_PHASE && !SIGNING_KEY) {
  throw new Error("INNGEST_SIGNING_KEY missing at /api/inngest load");
}

// #5159: pin the serve URL the SDK reports to the self-hosted inngest-server at
// registration. Without this, the SDK infers the host from the inbound request's
// Host/proto — so the loopback re-register PUT (http://127.0.0.1:3000, fired by
// ci-deploy.sh's verify_inngest_health after an inngest-server restart) registers
// `http://127.0.0.1:3000/api/inngest`, which the server accepts (HTTP 200) but
// NEVER plans crons for. Only the public-host registration re-plans crons —
// confirmed live on 2026-06-11: a manual `PUT https://app.soleur.ai/api/inngest`
// returns `modified:true` and crons fire, while the loopback PUT returns 200 with
// `inngest_crons:{}` (surfaced by #5178's deploy-status diagnostic). Pinning
// serveHost makes EVERY registration path — container boot, the server's
// --poll-interval sync, AND the in-loop loopback PUT — report the canonical public
// URL, so a standalone inngest restart self-recovers (the #5160 design intent that
// the loopback PUT alone could not achieve).
//
// HARDCODED, not env-derived: #5182 read this from `process.env.NEXT_PUBLIC_APP_URL`
// and was a silent no-op — Next.js statically inlines `process.env.NEXT_PUBLIC_*` at
// BUILD time, and NEXT_PUBLIC_APP_URL is not a Docker build ARG, so it inlined as
// `undefined` (the post-deploy AC15 re-dispatch still showed inngest_register_http
// =200 + inngest_crons:{}). The canonical server origin is therefore a hardcoded
// constant, matching the security-motivated convention in server/cf-cache-purge.ts
// (`const APP_ORIGIN = "https://app.soleur.ai"` — reading the origin from a header
// /env is a spoofing risk). Gated on NODE_ENV (reliably "production" in the prod
// container per Dockerfile `ENV NODE_ENV=production`, and NOT NEXT_PUBLIC_-inlined)
// so dev/build (the inngest dev server) infers the host from the request instead.
const SERVE_HOST =
  process.env.NODE_ENV === "production" ? "https://app.soleur.ai" : undefined;

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [
    agentOnSpawnRequested,
    cfoOnPaymentFailed,
    cronActionRequiredSla,
    slaIssueProcess,
    cronAgentNativeAudit,
    cronAnthropicCostReport,
    cronAnthropicCreditProbe,
    cronArchitectureDiagramSync,
    cronBugFixer,
    cronCampaignCalendar,
    cronCloudTaskHeartbeat,
    cronCommunityMonitor,
    cronCompetitiveAnalysis,
    cronContentGenerator,
    cronContentPublisher,
    cronCompoundPromote,
    cronContentVendorDrift,
    cronDailyTriage,
    cronDevMigrationDrift,
    cronDomainModelDrift,
    cronEmailIngressProbe,
    cronExpensesVerifyBy,
    cronFollowThroughMonitor,
    cronGhPagesCertReissue,
    cronGhPagesCertState,
    cronGhcrTokenMinter,
    cronGithubAppDriftGuard,
    cronGithubCidrRefresh,
    cronGrowthAudit,
    cronGrowthExecution,
    cronInngestConfigDrift,
    cronInngestCronWatchdog,
    cronKbTemplateHealth,
    cronLegalAudit,
    cronLinkedinTokenCheck,
    cronMainHealthMonitor,
    cronMembershipHealth,
    cronNag4216Readiness,
    cronOauthProbe,
    cronPlausibleGoals,
    cronReviewReminder,
    cronRoadmapReview,
    cronRulePrune,
    cronRulesetBypassAudit,
    cronSeoAeoAudit,
    cronSkillFreshness,
    cronStaleDeferredScopeOuts,
    cronStrategyReview,
    cronSupabaseAdvisorScan,
    cronSupabaseDiskIo,
    cronTerraformDrift,
    cronUxAudit,
    cronWeeklyAnalytics,
    cronWeeklyReleaseDigest,
    cronWorkspaceGc,
    cronWorkspaceSyncHealth,
    emailOnReceived,
    eventCfTokenExpiryCheck,
    eventScheduledReminder,
    eventShipMerge,
    githubOnEvent,
    oneshot4650MonitorClose,
    oneshotHeartbeatRecoveryVerify,
    oneshotF2DeferGateReview,
    oneshotGdprGate50dEval,
    oneshotRecheck4217Calibration,
    workspaceReconcileOnPush,
  ],
  signingKey: SIGNING_KEY ?? "build-phase-placeholder",
  // #5159 (see SERVE_HOST note above): pin the registered serve URL to the
  // canonical public origin so a loopback re-register PUT plans crons. Omitted
  // when NEXT_PUBLIC_APP_URL is unset (dev/build) → SDK infers from the request.
  ...(SERVE_HOST ? { serveHost: SERVE_HOST, servePath: "/api/inngest" } : {}),
});
