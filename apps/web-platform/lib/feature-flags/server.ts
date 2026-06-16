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
  // feat-debug-mode-stream — availability flag for the internal dev-cohort
  // harness instruction stream. Read ONLY through `isDebugModeAvailable`,
  // which hard-gates `role === "dev"` BEFORE this flag so the role-blind
  // env-fallback cannot open the stream to `prd` on a Flagsmith outage.
  "debug-mode": "FLAG_DEBUG_MODE",
  // feat-c4-viewer-remove-code-panel-gate-edit — gates ONLY the user-direct
  // C4 edit surface (PUT /api/kb/c4 + the Code panel UI). Default OFF for all
  // roles; user editing is removed pending substrate fixes, re-enabled later by
  // flipping the Flagsmith flag. Does NOT gate view (c4-visualizer) or the
  // Concierge edit tool (also c4-visualizer). Fail-closed: FLAG_C4_EDIT=0 mirror.
  "c4-edit": "FLAG_C4_EDIT",
} as const;

export type EnvFlagName = keyof typeof ENV_FLAGS;
export type RuntimeFlagName = keyof typeof RUNTIME_FLAGS;
export type FlagName = EnvFlagName | RuntimeFlagName;

export type Role = "prd" | "dev";

export type Identity = {
  userId: string | null;
  role: Role;
  orgId: string | null;
};

export const ANON_IDENTITY: Identity = { userId: null, role: "prd", orgId: null };

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
    // (The error-level, undebounced burst is what tripped the unrelated
    // alert rule `auth-callback-no-code-burst`; Sentry ID
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
 * feat-debug-mode-stream (P0-8) — availability of the internal harness
 * instruction stream for `identity`.
 *
 * INTENTIONALLY NOT cloned from `isTeamWorkspaceInviteEnabled`: that helper is
 * fail-OPEN on a Flagsmith outage (the env-fallback `FLAG_*` is role-blind, so
 * a `prd` identity would resolve `true` from `FLAG_DEBUG_MODE=1`). The debug
 * stream is a scoped exception to the #2138 raw-tool-input invariant and must
 * stay dev-cohort-only, so the `role !== "dev"` hard-gate runs BEFORE the flag
 * is ever consulted — a Flagsmith outage can only ever make this MORE
 * restrictive, never open the stream to `prd`.
 */
export async function isDebugModeAvailable(identity: Identity): Promise<boolean> {
  if (identity.role !== "dev") return false;
  return getRuntimeFlag("debug-mode", identity);
}

export function __resetFeatureFlagsForTests(): void {
  _client = null;
  const maxEntries = parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || "1000");
  _roleCache = new LRUCache<string, RuntimeSnapshot>(maxEntries, CACHE_TTL_MS);
}
