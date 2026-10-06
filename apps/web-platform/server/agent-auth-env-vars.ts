// The environment variables that carry the owner's Anthropic credential into an
// agent session. ONE source for both sides of the W1 boundary (#9601, ADR-272):
// `buildAgentEnv` injects exactly one of these per scheme, and
// `buildAgentSandboxConfig` denies exactly this set to sandboxed Bash, so a
// third auth variable cannot be added to one side only.
//
// Dependency-free on purpose: the sandbox config is imported lazily by the
// canary replay path and mocked wholesale by suites that stub `agent-env`, so
// it must not pull `agent-env`'s graph (providers, plugin-path) behind it.

/** Raw Anthropic API key (per-token billing). */
export const API_KEY_ENV_VAR = "ANTHROPIC_API_KEY" as const;

/** Claude Code subscription OAuth token. */
export const OAUTH_ENV_VAR = "CLAUDE_CODE_OAUTH_TOKEN" as const;

export const AGENT_AUTH_ENV_VARS = Object.freeze([
  API_KEY_ENV_VAR,
  OAUTH_ENV_VAR,
] as const);
