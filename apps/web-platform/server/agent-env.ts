import { PROVIDER_CONFIG } from "./providers";

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

export function buildAgentEnv(
  apiKey: string,
  serviceTokens?: Record<string, string>,
): Record<string, string> {
  const env: Record<string, string> = {
    ANTHROPIC_API_KEY: apiKey,
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

  return env;
}
