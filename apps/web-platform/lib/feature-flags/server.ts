// Runtime feature flags (ADR-038 v2). Two kinds:
//   ENV (sync, build/deploy-time) for DCE-friendly flags like dev-signin.
//   RUNTIME (async, identity-aware) via Flagsmith with per-role segmentation.
// Env-var fallback mirrors the prd-segment Flagsmith state — see ADR §"Fallback semantics".

import { Flagsmith } from "flagsmith-nodejs";
import { reportSilentFallback } from "@/server/observability";

const DEFAULT_FLAGSMITH_API_URL = "https://edge.api.flagsmith.com/api/v1/";
const REQUEST_TIMEOUT_SECONDS = 0.2; // 200ms ceiling — never block request path on Flagsmith.
const CACHE_TTL_MS = 30_000;

// INVARIANT (enforced by soleur:flag-set-role in PR #2): every FLAG_* env var
// below mirrors the flag's prd-segment Flagsmith state. Editing one side
// without the other breaks the env-var-fallback fidelity story in ADR §"Fallback semantics".
const ENV_FLAGS = {
  "dev-signin": "FLAG_DEV_SIGNIN",
  "team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE",
} as const;

const RUNTIME_FLAGS = {
  "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
} as const;

export type EnvFlagName = keyof typeof ENV_FLAGS;
export type RuntimeFlagName = keyof typeof RUNTIME_FLAGS;
export type FlagName = EnvFlagName | RuntimeFlagName;

export type Role = "prd" | "dev";

export type Identity = {
  userId: string | null;
  role: Role;
};

export const ANON_IDENTITY: Identity = { userId: null, role: "prd" };

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
// Max 2 entries by Role enum — no bounded eviction needed.
// V1 ignores per-identity Flagsmith overrides by design; every flag flows
// through a segment. The Flagsmith identifier is `role:<role>` so identity-
// level overrides on real UUIDs cannot bleed into this bucket.
const _roleCache = new Map<Role, { at: number; flags: RuntimeSnapshot }>();

function runtimeEnvFallback(): RuntimeSnapshot {
  const out = {} as RuntimeSnapshot;
  for (const [name, envVar] of Object.entries(RUNTIME_FLAGS) as [RuntimeFlagName, string][]) {
    out[name] = envIsOn(envVar);
  }
  return out;
}

async function fetchRuntimeFlagsFromFlagsmith(
  role: Role,
): Promise<RuntimeSnapshot | null> {
  const c = client();
  if (!c) return null;
  try {
    const flags = await c.getIdentityFlags(`role:${role}`, { role });
    const out = {} as RuntimeSnapshot;
    for (const name of Object.keys(RUNTIME_FLAGS) as RuntimeFlagName[]) {
      out[name] = flags.isFeatureEnabled(name);
    }
    return out;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "feature-flags",
      op: "flagsmith.getIdentityFlags",
      extra: { role },
    });
    return null;
  }
}

async function getRuntimeSnapshot(role: Role): Promise<RuntimeSnapshot> {
  const now = Date.now();
  const hit = _roleCache.get(role);
  if (hit && now - hit.at < CACHE_TTL_MS) return hit.flags;
  const flags = (await fetchRuntimeFlagsFromFlagsmith(role)) ?? runtimeEnvFallback();
  _roleCache.set(role, { at: now, flags });
  return flags;
}

export async function getRuntimeFlag(
  name: RuntimeFlagName,
  identity: Identity,
): Promise<boolean> {
  return (await getRuntimeSnapshot(identity.role))[name];
}

export async function getFeatureFlags(
  identity: Identity,
): Promise<Record<FlagName, boolean>> {
  const runtime = await getRuntimeSnapshot(identity.role);
  const envFlags = {} as Record<EnvFlagName, boolean>;
  for (const [name, envVar] of Object.entries(ENV_FLAGS) as [EnvFlagName, string][]) {
    envFlags[name] = envIsOn(envVar);
  }
  return { ...envFlags, ...runtime };
}

// Cache keyed on the raw env-var string. Production sees `process.env`
// fixed at boot, so the cache hits on every subsequent call. Tests that
// mutate `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` re-parse without needing a
// test-only reset hook.
let cachedAllowlist: { raw: string; set: ReadonlySet<string> } | null = null;

export function getTeamWorkspaceAllowlist(): ReadonlySet<string> {
  const raw = process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS ?? "";
  if (cachedAllowlist && cachedAllowlist.raw === raw) return cachedAllowlist.set;
  const set = new Set(
    raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );
  cachedAllowlist = { raw, set };
  return set;
}

/**
 * Two-key gate per AC-F: `FLAG_TEAM_WORKSPACE_INVITE=1` AND `orgId`
 * present in `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`. Both must hold.
 */
export function isTeamWorkspaceInviteEnabled(orgId: string): boolean {
  if (!getFlag("team-workspace-invite")) return false;
  if (!orgId) return false;
  return getTeamWorkspaceAllowlist().has(orgId);
}

export function __resetFeatureFlagsForTests(): void {
  _client = null;
  _roleCache.clear();
  cachedAllowlist = null;
}
