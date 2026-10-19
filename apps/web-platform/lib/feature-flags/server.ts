// Runtime feature flags (ADR-038 v2). Two kinds:
//   ENV (sync, build/deploy-time) for DCE-friendly flags like dev-signin.
//   RUNTIME (async, identity-aware) via Flagsmith with per-role segmentation.
// Env-var fallback mirrors the prd-segment Flagsmith state — see ADR §"Fallback semantics".

import { Flagsmith } from "flagsmith-nodejs";
import { mirrorWarnWithDebounce } from "@/server/observability";
import { LRUCache } from "./lru-cache";

const DEFAULT_FLAGSMITH_API_URL = "https://edge.api.flagsmith.com/api/v1/";
const REQUEST_TIMEOUT_SECONDS = 0.2; // 200ms ceiling — never block request path on Flagsmith.
const CACHE_TTL_MS = 30_000;

// INVARIANT (enforced by soleur:flag-set-role in PR #2): every FLAG_* env var
// below mirrors the flag's prd-segment Flagsmith state. Editing one side
// without the other breaks the env-var-fallback fidelity story in ADR §"Fallback semantics".
//
// dev-signin stays ENV by design. It pairs with the DCE tripwire
// `apps/web-platform/scripts/assert-dev-signin-eliminated.sh` which fails the
// prd build if "dev-signin", isDevSignInEnabled, or dev-sign-in-panel tokens
// leak into client bundles. Sync getFlag() + `process.env.NODE_ENV !== "development"`
// literals are what SWC/Terser need to eliminate the panel.
//
// team-workspace-invite and byok-delegations are RUNTIME_FLAGS under Flagsmith
// with per-org targeting via per-feature `<flag>-orgs` segments (ADR-043
// §"Per-feature segment scoping"): each org-targetable flag gets its own segment
// whose `EQUAL orgId` conditions are the sole per-org gate for that flag. byok runs
// on `byok-delegations-orgs`; team-workspace-invite runs on `team-workspace-invite-orgs`
// (migrated off the legacy shared `org-targeted` segment, which was retired 2026-05-29
// per #4617). Which segment carries the override is transparent to getRuntimeFlag here.
// FLAG_* env vars remain as the Flagsmith outage fallback (env-fallback mirror).
//
// New flags: if the call-site needs DCE elimination → ENV. Otherwise → RUNTIME.
// See ADR-038 + ADR-043.
const ENV_FLAGS = {
  "dev-signin": "FLAG_DEV_SIGNIN",
} as const;

const RUNTIME_FLAGS = {
  "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
  "team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE",
  "byok-delegations": "FLAG_BYOK_DELEGATIONS",
  // Gates the interactive LikeC4 C4-model visualizer in the KB viewer
  // (replaces static Mermaid C4 rendering). Per-user rollout via role/segment.
  "c4-visualizer": "FLAG_C4_VISUALIZER",
  // feat-debug-mode-stream — availability flag for the workspace debug
  // stream panel. Read ONLY through `isDebugModeAvailable`. Open to ALL
  // roles during beta (the P0-8 `dev`-cohort hard-gate was retired so users
  // can send harness logs for debugging); this flag remains the kill
  // switch. Note the env fallback `FLAG_DEBUG_MODE=1` is role-blind — on a
  // Flagsmith outage it opens the stream to everyone; emission still also
  // requires the owner-set per-workspace `debug_mode` toggle.
  "debug-mode": "FLAG_DEBUG_MODE",
  // feat-c4-viewer-remove-code-panel-gate-edit — gates ONLY the user-direct
  // C4 edit surface (PUT /api/kb/c4 + the Code panel UI). Default OFF for all
  // roles; user editing is removed pending substrate fixes, re-enabled later by
  // flipping the Flagsmith flag. Does NOT gate view (c4-visualizer) or the
  // Concierge edit tool (also c4-visualizer). Fail-closed: FLAG_C4_EDIT=0 mirror.
  "c4-edit": "FLAG_C4_EDIT",
  // feat-web-app-shortcuts — gates the ⌘K command palette + ? help overlay
  // command layer (apps/web-platform/components/command-palette). Default OFF
  // for all roles; dev-cohort rollout via Flagsmith. Fail-closed: FLAG_COMMAND_PALETTE=0 mirror.
  "command-palette": "FLAG_COMMAND_PALETTE",
  // feat-support-interface — gates the floating support launcher + slide-over
  // support chat (apps/web-platform/components/support). Currently ON for all prd.
  // Whether a sent message gets a LIVE Concierge reply or the canned interface-
  // preview reply is gated SEPARATELY by `support-live` below. Fail-closed:
  // FLAG_SUPPORT=0 mirror.
  support: "FLAG_SUPPORT",
  // feat-wire-concierge-support-chat (ADR-113) — gates the LIVE Concierge backend
  // for the support chat (SSE via POST /api/support, support-scoped skills). Default
  // OFF for all roles: while OFF the bubble shows the canned interface-preview reply
  // (no network). Flip ON only AFTER the Phase-4 product-help corpus + search-root
  // restriction are validated against a deployed env (else the read-only support
  // agent could grep the internal knowledge base). Fail-closed: FLAG_SUPPORT_LIVE=0 mirror.
  "support-live": "FLAG_SUPPORT_LIVE",
  // feat-guided-tour — gates the onboarding tour: spotlight overlay + TourProvider
  // (apps/web-platform/components/tour) and the "Take a tour" launch points. Default
  // OFF for all roles until rollout. Fail-closed: FLAG_GUIDED_TOUR=0 mirror (the
  // env fallback is role-blind, so keep it 0 until the Flagsmith feature is created).
  "guided-tour": "FLAG_GUIDED_TOUR",
  // feat-pluggable-web-agent-engines — gates Codex rollout independently of
  // registry capability, authorization, and qualification checks. Keep the
  // env mirror default-off because it is role-blind during a Flagsmith outage.
  "codex-engine": "FLAG_CODEX_ENGINE",
  // #4671 / ADR-287 — heuristic injection scan + annotation of WebFetch results
  // (apps/web-platform/server/untrusted-content.ts). Annotate-only; prd default OFF
  // until the observe window. Read ONLY through `isUntrustedContentClassifyEnabled`.
  // Fail-closed: FLAG_UNTRUSTED_CONTENT_CLASSIFY=0 mirror.
  "untrusted-content-classify": "FLAG_UNTRUSTED_CONTENT_CLASSIFY",
  // #4671 / ADR-287 — subordinate to the flag above: ALSO rewrites a flagged WebFetch
  // result into the data-only envelope (`updatedToolOutput`). prd default OFF; enabling
  // it is a separate, operator-visible flip after >=7 days of prd telemetry.
  // Fail-closed: FLAG_UNTRUSTED_CONTENT_WRAP=0 mirror.
  "untrusted-content-wrap": "FLAG_UNTRUSTED_CONTENT_WRAP",
  // #9545 / ADR-288 — egress audit rollup collection (the Vector -> app ingest route,
  // apps/web-platform/server/egress-audit-ingest.ts). Dark by default and evaluated PER
  // ORG after the ingest route has authenticated the batch: environment default OFF
  // (kill switch), a Jikigai-owned canary org enabled by a per-org segment override (ruling
  // A); external orgs stay OFF until PR2 ships. Read ONLY through the ingest module.
  // Fail-closed: FLAG_EGRESS_AUDIT_COLLECTION=0 mirror.
  "egress-audit-collection": "FLAG_EGRESS_AUDIT_COLLECTION",
  // #10455 (a) / ADR-075 addendum 2026-10-19 — selects the AF_UNIX-deny seccomp artifact for NO-EGRESS
  // agent sessions (egress sessions always stay on the base artifact). Default OFF = today's posture.
  // Read ONLY through `isAgentSandboxUnixDenyEnabled` (via server/resolve-sandbox-unix-deny.ts, which
  // resolves any error or timeout to OFF). The flag is global (anonymous identity; the anonymous identity
  // resolves to the prd segment, so a dev-only flip does nothing). Turning it ON is a
  // production write that waits for a green deploy SDK Bash smoke (tracker #10548). Fail-closed:
  // FLAG_AGENT_SANDBOX_UNIX_DENY=0 mirror.
  "agent-sandbox-unix-deny": "FLAG_AGENT_SANDBOX_UNIX_DENY",
} as const;

export type EnvFlagName = keyof typeof ENV_FLAGS;
export type RuntimeFlagName = keyof typeof RUNTIME_FLAGS;
export type FlagName = EnvFlagName | RuntimeFlagName;

export type Role = "prd" | "dev";

export type Identity = {
  userId: string | null;
  role: Role;
  orgId: string | null;
  // Additive fields for the dashboard chrome server-render (Phase 6,
  // perf-dashboard-section-load-latency): email comes free from
  // userData.user.email; subscriptionStatus rides the widened users select.
  // ANON_IDENTITY keeps literal null for both (no widening of the anon shape).
  email: string | null;
  subscriptionStatus: string | null;
};

export const ANON_IDENTITY: Identity = {
  userId: null,
  role: "prd",
  orgId: null,
  email: null,
  subscriptionStatus: null,
};

function envIsOn(name: string): boolean {
  return process.env[name] === "1";
}

// Sync. Kept separate from getRuntimeFlag because dev-signin's call sites
// rely on `process.env.NODE_ENV !== "development"` literals for DCE in
// production bundles (see components/auth/dev-sign-in-panel.tsx). Routing
// through async Flagsmith would weaken that.
export function getFlag(name: EnvFlagName): boolean {
  return envIsOn(ENV_FLAGS[name]);
}

let _client: Flagsmith | null = null;
function client(): Flagsmith | null {
  if (_client) return _client;
  const key = process.env.FLAGSMITH_ENVIRONMENT_KEY;
  if (!key) return null;
  _client = new Flagsmith({
    environmentKey: key,
    apiUrl: process.env.FLAGSMITH_API_URL ?? DEFAULT_FLAGSMITH_API_URL,
    enableLocalEvaluation: false,
    requestTimeoutSeconds: REQUEST_TIMEOUT_SECONDS,
  });
  return _client;
}

type RuntimeSnapshot = Record<RuntimeFlagName, boolean>;

const CACHE_MAX_ENTRIES = parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || "1000");
let _roleCache = new LRUCache<string, RuntimeSnapshot>(CACHE_MAX_ENTRIES, CACHE_TTL_MS);

function runtimeEnvFallback(): RuntimeSnapshot {
  const out = {} as RuntimeSnapshot;
  for (const [name, envVar] of Object.entries(RUNTIME_FLAGS) as [RuntimeFlagName, string][]) {
    out[name] = envIsOn(envVar);
  }
  return out;
}

async function fetchRuntimeFlagsFromFlagsmith(
  role: Role,
  orgId: string | null,
): Promise<RuntimeSnapshot | null> {
  const c = client();
  if (!c) return null;
  try {
    const identifier = orgId ? `org:${orgId}:${role}` : `role:${role}`;
    const traits: Record<string, string> = { role, ...(orgId ? { orgId } : {}) };
    const flags = await c.getIdentityFlags(identifier, traits, true);
    const out = {} as RuntimeSnapshot;
    for (const name of Object.keys(RUNTIME_FLAGS) as RuntimeFlagName[]) {
      out[name] = flags.isFeatureEnabled(name);
    }
    return out;
  } catch (err) {
    // The page degrades gracefully via runtimeEnvFallback() below — this is a
    // recovered path, not a user-facing failure. Report at WARNING level and
    // debounce per-segment so a Flagsmith edge slowdown cannot burst Sentry.
    // (The error-level, undebounced burst fired `auth-callback-no-code-burst`,
    // whose filters were empty 2026-05-17..06-02 so it matched every issue
    // (#4781); Sentry ID
    // ac2d712121d94ad9ab154a16f6178fa7 / #4571.) Dedup key is the snapshot
    // cache key shape (role:orgId), never a userId — in-process, never emitted.
    mirrorWarnWithDebounce(
      err,
      {
        feature: "feature-flags",
        op: "flagsmith.getIdentityFlags",
        extra: { role, orgId },
      },
      `${role}:${orgId ?? "__anon__"}`,
      "flagsmith:getidentityflags-timeout",
    );
    return null;
  }
}

async function getRuntimeSnapshot(role: Role, orgId: string | null): Promise<RuntimeSnapshot> {
  const cacheKey = `${role}:${orgId ?? "__anon__"}`;
  const hit = _roleCache.get(cacheKey);
  if (hit) return hit;
  const flags = (await fetchRuntimeFlagsFromFlagsmith(role, orgId)) ?? runtimeEnvFallback();
  _roleCache.set(cacheKey, flags);
  return flags;
}

export async function getRuntimeFlag(
  name: RuntimeFlagName,
  identity: Identity,
): Promise<boolean> {
  return (await getRuntimeSnapshot(identity.role, identity.orgId))[name];
}

export async function getFeatureFlags(
  identity: Identity,
): Promise<Record<FlagName, boolean>> {
  const runtime = await getRuntimeSnapshot(identity.role, identity.orgId);
  const envFlags = {} as Record<EnvFlagName, boolean>;
  for (const [name, envVar] of Object.entries(ENV_FLAGS) as [EnvFlagName, string][]) {
    envFlags[name] = envIsOn(envVar);
  }
  return { ...envFlags, ...runtime };
}

export async function isTeamWorkspaceInviteEnabled(orgId: string, identity: Identity): Promise<boolean> {
  if (!orgId) return false;
  return getRuntimeFlag("team-workspace-invite", identity);
}

export async function isByokDelegationsEnabled(orgId: string | null | undefined, identity: Identity): Promise<boolean> {
  if (!orgId) return false;
  return getRuntimeFlag("byok-delegations", identity);
}

/**
 * Engine rollout mapping. A null entry means the reviewed engine is always
 * available once registry capability checks pass; a runtime flag keeps an
 * engine dark until its qualification and cohort gates are complete. Engines
 * are deliberately fail-closed until they are registered here.
 */
const ENGINE_ROLLOUT_FLAGS: Readonly<Record<string, RuntimeFlagName | null>> = {
  "claude-code": null,
  codex: "codex-engine",
};

export async function isEngineRolloutEnabled(
  engineId: string,
  orgId: string | null | undefined,
  identity: Identity,
): Promise<boolean> {
  const rolloutFlag = ENGINE_ROLLOUT_FLAGS[engineId];
  if (rolloutFlag === undefined) return false;
  if (rolloutFlag === null) return true;
  if (!orgId || identity.orgId !== orgId) return false;
  return getRuntimeFlag(rolloutFlag, identity);
}

/**
 * feat-pluggable-web-agent-engines — internal Codex rollout gate.
 *
 * A workspace is required so anonymous or unbound requests cannot enter the
 * rollout cohort. Dispatch still must resolve the persisted binding through
 * the engine registry; this flag only controls cohort exposure.
 */
export async function isCodexEngineEnabled(
  orgId: string | null | undefined,
  identity: Identity,
): Promise<boolean> {
  return isEngineRolloutEnabled("codex", orgId, identity);
}

/**
 * feat-debug-mode-stream — availability of the harness instruction stream for
 * `identity`. Open to ALL roles during beta so users can capture and send
 * harness logs for debugging; the `debug-mode` flag is the sole cohort gate
 * and remains the kill switch.
 *
 * The original P0-8 `role !== "dev"` hard-gate is retired: the stream stays a
 * scoped exception to the #2138 raw-tool-input invariant, but every frame is
 * redacted/probe-gated at the emit boundary (server/debug-event.ts) and
 * emission additionally requires the owner-set per-workspace `debug_mode`
 * toggle — neither control is role-dependent. The Flagsmith identity still
 * carries the real role so the flag can be re-segmented if beta needs a
 * partial rollback.
 */
export async function isDebugModeAvailable(identity: Identity): Promise<boolean> {
  return getRuntimeFlag("debug-mode", identity);
}

/** #4671 / ADR-287 — classify + annotate WebFetch results. Resolve with the session's REAL identity. */
export async function isUntrustedContentClassifyEnabled(identity: Identity): Promise<boolean> {
  return getRuntimeFlag("untrusted-content-classify", identity);
}

/** #4671 / ADR-287 — rewrite flagged WebFetch results into the data-only envelope. Subordinate to classify. */
export async function isUntrustedContentWrapEnabled(identity: Identity): Promise<boolean> {
  return getRuntimeFlag("untrusted-content-wrap", identity);
}

/** #10455 (a) — AF_UNIX-deny seccomp artifact for no-egress sessions. Global flag: resolve with the anonymous identity. */
export async function isAgentSandboxUnixDenyEnabled(identity: Identity = ANON_IDENTITY): Promise<boolean> {
  return getRuntimeFlag("agent-sandbox-unix-deny", identity);
}

export function __resetFeatureFlagsForTests(): void {
  _client = null;
  const maxEntries = parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || "1000");
  _roleCache = new LRUCache<string, RuntimeSnapshot>(maxEntries, CACHE_TTL_MS);
}
