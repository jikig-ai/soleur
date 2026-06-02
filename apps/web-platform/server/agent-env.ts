import { PROVIDER_CONFIG } from "./providers";

/**
 * The auth scheme an agent run is funded by. `api_key` feeds the raw
 * Anthropic `ANTHROPIC_API_KEY`; `oauth_token` feeds the Claude Code
 * subscription `CLAUDE_CODE_OAUTH_TOKEN`. The scheme is the discriminator
 * that selects the mutually-exclusive env var in `buildAgentEnv`.
 */
export type AgentAuthScheme = "api_key" | "oauth_token";

/**
 * A resolved agent credential. Carried as a single object (not two scalar
 * args) end-to-end from the lease to `buildAgentEnv` so a forgotten
 * `scheme` is a TYPE error, not a silent default to `api_key` (which would
 * inject the wrong env var — the both-keys/wrong-key trap, plan §Phase 3).
 */
export interface AgentCredential {
  /** Plaintext secret value. */
  value: string;
  /** Which auth env var `value` feeds. */
  scheme: AgentAuthScheme;
}

// ---------------------------------------------------------------------------
// Agent subprocess environment isolation (CWE-526)
//
// The Claude Agent SDK subprocess must NOT inherit server secrets like
// SUPABASE_SERVICE_ROLE_KEY or BYOK_ENCRYPTION_KEY. Node.js child_process.spawn
// replaces process.env entirely when options.env is set, so omitting a var from
// the allowlist is equivalent to blocking it.
// ---------------------------------------------------------------------------

const AGENT_ENV_ALLOWLIST = Object.freeze([
  "HOME",
  "PATH",
  "NODE_ENV",
  "LANG",
  "LC_ALL",
  "TERM",
  "USER",
  "SHELL",
  "TMPDIR",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "NO_PROXY",
  "http_proxy",
  "https_proxy",
  "no_proxy",
] as const);

const AGENT_ENV_OVERRIDES = Object.freeze({
  DISABLE_AUTOUPDATER: "1",
  DISABLE_TELEMETRY: "1",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
} as const);

// Defense-in-depth: only env var names from PROVIDER_CONFIG are allowed
// as service token keys. Prevents injection of LD_PRELOAD, NODE_OPTIONS, etc.
const ALLOWED_SERVICE_ENV_VARS = new Set(
  Object.values(PROVIDER_CONFIG).map((c) => c.envVar),
);

// The two mutually-exclusive auth env vars. The CLI subprocess authenticates
// with `CLAUDE_CODE_OAUTH_TOKEN` (subscription) XOR `ANTHROPIC_API_KEY` (per-
// token API). Injecting BOTH is the silent-API-billing trap (FR2): the SDK
// prefers one but the operator believes they are on the subscription.
const API_KEY_ENV_VAR = "ANTHROPIC_API_KEY";
const OAUTH_ENV_VAR = "CLAUDE_CODE_OAUTH_TOKEN";

export function buildAgentEnv(
  credential: AgentCredential,
  serviceTokens?: Record<string, string>,
): Record<string, string> {
  const env: Record<string, string> = {
    // Telemetry-suppression overrides ride OUTSIDE the auth branch: a
    // subscription token must NOT phone home to the operator's personal
    // Claude account. These names are not in ALLOWED_SERVICE_ENV_VARS, so
    // the service-token loop below cannot clobber them.
    ...AGENT_ENV_OVERRIDES,
  };

  // Copy allowlisted system vars from process.env first
  for (const key of AGENT_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) {
      env[key] = value;
    }
  }

  // Inject third-party service tokens AFTER the allowlist loop.
  // Service tokens take precedence over ambient process.env values,
  // and the env var names are validated against ALLOWED_SERVICE_ENV_VARS
  // to prevent injection of dangerous vars like LD_PRELOAD or NODE_OPTIONS.
  if (serviceTokens) {
    for (const [envVar, value] of Object.entries(serviceTokens)) {
      if (ALLOWED_SERVICE_ENV_VARS.has(envVar)) {
        env[envVar] = value;
      }
    }
  }

  // Auth var LAST and mutually exclusive: the credential branch is
  // authoritative over any ambient/service value, and the NON-selected auth
  // var is explicitly removed so exactly one is ever present (both-keys
  // trap). The exhaustive `: never` rail makes a future scheme a TS build
  // break here rather than a silent fall-through to the wrong var.
  switch (credential.scheme) {
    case "api_key":
      delete env[OAUTH_ENV_VAR];
      env[API_KEY_ENV_VAR] = credential.value;
      break;
    case "oauth_token":
      delete env[API_KEY_ENV_VAR];
      env[OAUTH_ENV_VAR] = credential.value;
      break;
    default: {
      const _exhaustive: never = credential.scheme;
      throw new Error(`buildAgentEnv: unhandled auth scheme ${_exhaustive}`);
    }
  }

  return env;
}
