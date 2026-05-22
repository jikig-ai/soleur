// Runtime feature flags — identity-aware (ADR-038 v2).
//
// Two flag kinds:
//   1. ENV flags (sync)     — build/deploy-time toggles read from
//      process.env at request time. Used for dev-only surfaces gated by
//      NODE_ENV literals the bundler can DCE in production (`dev-signin`).
//      Never go through Flagsmith.
//   2. RUNTIME flags (async, identity-aware) — resolved via Flagsmith with
//      per-role segmentation. The current Identity { userId, role } is
//      passed at every call site (`role-prd` or `role-dev` segment in
//      Flagsmith). Cache key = role (only two entries). 30s TTL.
//
// Operational interface:
//   - Operator never opens flagsmith.com. Soleur skills (soleur:flag-create,
//     soleur:flag-set-role, soleur:user-set-role) mutate Flagsmith via its
//     management API.
//   - Each FLAG_* env var mirrors the flag's prd-segment state. Outage →
//     everyone falls back to that value (matches "prd everyone" semantics;
//     never dark-launches a dev-only feature to prd).

import { Flagsmith } from "flagsmith-nodejs";

const ENV_FLAGS = {
  "dev-signin": "FLAG_DEV_SIGNIN",
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

// Anonymous users + any request without a Supabase session resolve through
// the prd role. `null` userId is the signal to Flagsmith that this is an
// untracked identity (the SDK still requires *some* string identifier; we
// pass `anon` so per-segment rules fire on the role trait alone).
export const ANON_IDENTITY: Identity = { userId: null, role: "prd" };

export function getFlag(name: EnvFlagName): boolean {
  return process.env[ENV_FLAGS[name]] === "1";
}

let _client: Flagsmith | null = null;
function client(): Flagsmith | null {
  if (_client) return _client;
  const key = process.env.FLAGSMITH_ENVIRONMENT_KEY;
  if (!key) return null;
  _client = new Flagsmith({
    environmentKey: key,
    apiUrl: process.env.FLAGSMITH_API_URL ?? "https://edge.api.flagsmith.com/api/v1/",
    enableLocalEvaluation: false,
    requestTimeoutSeconds: 0.2,
  });
  return _client;
}

const CACHE_TTL_MS = 30_000;
type RuntimeSnapshot = Record<RuntimeFlagName, boolean>;
const _cache = new Map<Role, { at: number; flags: RuntimeSnapshot }>();

function runtimeEnvFallback(): RuntimeSnapshot {
  const out = {} as RuntimeSnapshot;
  for (const [name, envVar] of Object.entries(RUNTIME_FLAGS) as [RuntimeFlagName, string][]) {
    out[name] = process.env[envVar] === "1";
  }
  return out;
}

async function fetchRuntimeFlagsFromFlagsmith(
  identity: Identity,
): Promise<RuntimeSnapshot | null> {
  const c = client();
  if (!c) return null;
  try {
    const flags = await c.getIdentityFlags(
      identity.userId ?? "anon",
      { role: identity.role },
    );
    const out = {} as RuntimeSnapshot;
    for (const name of Object.keys(RUNTIME_FLAGS) as RuntimeFlagName[]) {
      out[name] = flags.isFeatureEnabled(name);
    }
    return out;
  } catch {
    return null;
  }
}

async function getRuntimeSnapshot(identity: Identity): Promise<RuntimeSnapshot> {
  const now = Date.now();
  const hit = _cache.get(identity.role);
  if (hit && now - hit.at < CACHE_TTL_MS) return hit.flags;
  const flags = (await fetchRuntimeFlagsFromFlagsmith(identity)) ?? runtimeEnvFallback();
  _cache.set(identity.role, { at: now, flags });
  return flags;
}

export async function getRuntimeFlag(
  name: RuntimeFlagName,
  identity: Identity,
): Promise<boolean> {
  return (await getRuntimeSnapshot(identity))[name];
}

export async function getFeatureFlags(
  identity: Identity,
): Promise<Record<FlagName, boolean>> {
  const runtime = await getRuntimeSnapshot(identity);
  const envFlags = {} as Record<EnvFlagName, boolean>;
  for (const [name, envVar] of Object.entries(ENV_FLAGS) as [EnvFlagName, string][]) {
    envFlags[name] = process.env[envVar] === "1";
  }
  return { ...envFlags, ...runtime };
}

// Test-only: drop client + cache between tests so process.env mutations
// and per-role cache assertions are independent across cases.
export function __resetForTests(): void {
  _client = null;
  _cache.clear();
}
