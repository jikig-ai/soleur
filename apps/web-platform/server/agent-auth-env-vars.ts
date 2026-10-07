// The environment variables that carry the owner's Anthropic credential into an
// agent session (#9601, ADR-272). `buildAgentEnv` injects exactly one of these
// per scheme, and `buildAgentSandboxConfig` denies exactly this set to sandboxed
// Bash. Both read the names from here, and
// `test/agent-sandbox-credential-deny.test.ts` derives the injected set from
// `buildAgentEnv`'s output and requires it to equal this one, so a third auth
// variable added on the injection side fails that test rather than going unseen.
//
// Dependency-free on purpose. The canary capture path imports the sandbox config
// lazily, and importing it must not pull `agent-env`'s graph (providers,
// plugin-path) behind it, so the names live in a module with no imports.

/** Raw Anthropic API key (per-token billing). */
export const API_KEY_ENV_VAR = "ANTHROPIC_API_KEY" as const;

/** Claude Code subscription OAuth token. */
export const OAUTH_ENV_VAR = "CLAUDE_CODE_OAUTH_TOKEN" as const;

export const AGENT_AUTH_ENV_VARS = Object.freeze([
  API_KEY_ENV_VAR,
  OAUTH_ENV_VAR,
] as const);
