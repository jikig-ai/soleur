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

export function buildAgentEnv(
  apiKey: string,
  serviceTokens?: Record<string, string>,
): Record<string, string> {
  const env: Record<string, string> = {
    ANTHROPIC_API_KEY: apiKey,
    ...AGENT_ENV_OVERRIDES,
  };

  // Inject third-party service tokens (env var names from PROVIDER_CONFIG)
  if (serviceTokens) {
    for (const [envVar, value] of Object.entries(serviceTokens)) {
      env[envVar] = value;
    }
  }

  for (const key of AGENT_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) {
      env[key] = value;
    }
  }

  return env;
}
