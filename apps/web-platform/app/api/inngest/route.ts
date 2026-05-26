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
import { cronAgentNativeAudit } from "@/server/inngest/functions/cron-agent-native-audit";
import { cronBugFixer } from "@/server/inngest/functions/cron-bug-fixer";
import { cronCloudTaskHeartbeat } from "@/server/inngest/functions/cron-cloud-task-heartbeat";
import { cronCommunityMonitor } from "@/server/inngest/functions/cron-community-monitor";
import { cronCompetitiveAnalysis } from "@/server/inngest/functions/cron-competitive-analysis";
import { cronContentPublisher } from "@/server/inngest/functions/cron-content-publisher";
import { cronContentVendorDrift } from "@/server/inngest/functions/cron-content-vendor-drift";
import { cronCompoundPromote } from "@/server/inngest/functions/cron-compound-promote";
import { cronDailyTriage } from "@/server/inngest/functions/cron-daily-triage";
import { cronFollowThroughMonitor } from "@/server/inngest/functions/cron-follow-through-monitor";
import { cronGhPagesCertState } from "@/server/inngest/functions/cron-gh-pages-cert-state";
import { cronGithubAppDriftGuard } from "@/server/inngest/functions/cron-github-app-drift-guard";
import { cronLegalAudit } from "@/server/inngest/functions/cron-legal-audit";
import { cronLinkedinTokenCheck } from "@/server/inngest/functions/cron-linkedin-token-check";
import { cronMembershipHealth } from "@/server/inngest/functions/cron-membership-health";
import { cronNag4216Readiness } from "@/server/inngest/functions/cron-nag-4216-readiness";
import { cronUxAudit } from "@/server/inngest/functions/cron-ux-audit";
import { cronOauthProbe } from "@/server/inngest/functions/cron-oauth-probe";
import { cronPlausibleGoals } from "@/server/inngest/functions/cron-plausible-goals";
import { cronRoadmapReview } from "@/server/inngest/functions/cron-roadmap-review";
import { cronRulePrune } from "@/server/inngest/functions/cron-rule-prune";
import { cronRulesetBypassAudit } from "@/server/inngest/functions/cron-ruleset-bypass-audit";
import { cronSkillFreshness } from "@/server/inngest/functions/cron-skill-freshness";
import { cronStaleDeferredScopeOuts } from "@/server/inngest/functions/cron-stale-deferred-scope-outs";
import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";
import { eventCfTokenExpiryCheck } from "@/server/inngest/functions/event-cf-token-expiry-check";
import { eventShipMerge } from "@/server/inngest/functions/event-ship-merge";
import { githubOnEvent } from "@/server/inngest/functions/github-on-event";
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

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [
    agentOnSpawnRequested,
    cfoOnPaymentFailed,
    cronAgentNativeAudit,
    cronBugFixer,
    cronCloudTaskHeartbeat,
    cronCommunityMonitor,
    cronCompetitiveAnalysis,
    cronContentPublisher,
    cronContentVendorDrift,
    cronCompoundPromote,
    cronDailyTriage,
    cronFollowThroughMonitor,
    cronGhPagesCertState,
    cronGithubAppDriftGuard,
    cronLegalAudit,
    cronLinkedinTokenCheck,
    cronMembershipHealth,
    cronNag4216Readiness,
    cronOauthProbe,
    cronPlausibleGoals,
    cronRoadmapReview,
    cronRulePrune,
    cronRulesetBypassAudit,
    cronSkillFreshness,
    cronStaleDeferredScopeOuts,
    cronStrategyReview,
    cronUxAudit,
    eventCfTokenExpiryCheck,
    eventShipMerge,
    githubOnEvent,
    oneshotF2DeferGateReview,
    oneshotGdprGate50dEval,
    oneshotRecheck4217Calibration,
    workspaceReconcileOnPush,
  ],
  signingKey: SIGNING_KEY ?? "build-phase-placeholder",
});
