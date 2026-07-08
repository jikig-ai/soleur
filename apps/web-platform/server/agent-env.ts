import { PROVIDER_CONFIG } from "./providers";
import { assertTrustedPluginPath } from "./plugin-path";

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

/**
 * Optional env extras that are NOT service tokens and NOT auth vars.
 *
 * `ghToken` is the freshly-minted GitHub App **installation** token for the
 * agent's connected repo. It is injected as `GH_TOKEN` — the var `gh` prefers
 * over `GITHUB_TOKEN` — so the Concierge agent's `gh` calls authenticate
 * without an interactive `gh auth login` (Issue A). It rides this dedicated
 * param rather than the `serviceTokens` map for three reasons: (1) the map is
 * keyed to `PROVIDER_CONFIG.envVar` which is `GITHUB_TOKEN` (the lower-
 * precedence var), (2) a user's BYOK GitHub PAT row would clobber it, and
 * (3) `GH_TOKEN` is intentionally NOT in `ALLOWED_SERVICE_ENV_VARS`, so the
 * service-token loop cannot carry it. Per `hr-github-app-auth-not-pat` the
 * value is a short-lived App installation token, never a PAT — and it is
 * NEVER logged.
 */
export interface BuildAgentEnvOptions {
  ghToken?: string;
  /**
   * Absolute path to the in-sandbox GIT_ASKPASS helper script. Written by
   * the server under the agent's own `workspacePath` (the only verified
   * sandbox-readable `allowWrite` dir) so a bwrap `git` subprocess can
   * read+exec it. `GH_TOKEN` authenticates the `gh` CLI; raw `git`
   * push/fetch/pull needs THIS separate askpass path. Paired with
   * `gitInstallationToken` — both-or-nothing (a half-wired askpass is a
   * silent auth failure).
   */
  gitAskpassScriptPath?: string;
  /**
   * The freshly-minted GitHub App **installation** token the askpass
   * script reads at runtime from `GIT_INSTALLATION_TOKEN`. It is delivered
   * via env ONLY — never interpolated into the askpass script body, never
   * embedded in a `.git/config` remote URL, NEVER logged. Per
   * `hr-github-app-auth-not-pat` this is an App installation token, never a
   * PAT. Same token value as `ghToken` at the cc call site (one is for
   * `gh`, the other for raw `git`); carried as a distinct field so the
   * both-present guard is explicit.
   */
  gitInstallationToken?: string;
  /**
   * The platform-deployed plugin root (`getPluginPath()` →
   * `/app/shared/plugins/soleur` in prod), injected as `CLAUDE_PLUGIN_ROOT`.
   * The deployed skills' `bash ${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…`
   * shell-outs read this var so they execute the platform-controlled script,
   * NOT the connected repo's committed (untrusted) `./plugins/soleur/` copy
   * (the connected-repo-shadow delivery fix — plan §Phase 2). It rides this
   * dedicated per-dispatch param rather than `AGENT_ENV_ALLOWLIST` on purpose:
   * the allowlist copies AMBIENT `process.env` (a whole-process constant),
   * whereas this is a per-dispatch value threaded from
   * `agent-runner-query-options.ts`. Keeping it out of the allowlist also
   * prevents an ambient `process.env.CLAUDE_PLUGIN_ROOT` from leaking into the
   * agent env.
   *
   * FAIL-CLOSED (#6223): in a production env this is a dispatch precondition —
   * absent/empty throws, and a present value is validated via
   * `assertTrustedPluginPath` before injection (see the injection site below).
   * The earlier "graceful CLI degradation / empty is a no-op" rationale was
   * fictional: `buildAgentEnv` is server-only with exactly one caller; the
   * CLI/worktree surface runs the plugin directly, never through this function.
   * Omission is tolerated ONLY under the VITEST/NODE_ENV=test bypass.
   */
  pluginPath?: string;
}

export function buildAgentEnv(
  credential: AgentCredential,
  serviceTokens?: Record<string, string>,
  opts?: BuildAgentEnvOptions,
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

  // GitHub App installation token (Issue A). Injected as GH_TOKEN OUTSIDE
  // the service-token loop and OUTSIDE the auth switch — it is neither a
  // PROVIDER_CONFIG service var nor an Anthropic auth var. Empty/undefined
  // is a no-op (graceful degradation when no repo is connected). Never log.
  if (opts?.ghToken) {
    env.GH_TOKEN = opts.ghToken;
  }

  // In-sandbox raw-git credential path (plan item 1). `GH_TOKEN` authenticates
  // the `gh` CLI but NOT `git push`/`fetch`/`pull`. These six vars are the
  // credential-relevant subset of the server-side `gitWithInstallationAuth`
  // env block in `git-auth.ts` — same names + values, no novel credential
  // path. We intentionally omit that block's seventh var `GIT_TERMINAL_PROGRESS`
  // (a cosmetic progress-meter toggle, irrelevant to a non-interactive sandbox
  // subprocess) and cannot replicate its argv-level `HELPER_RESET`
  // (`-c credential.helper=`) because the agent builds its own `git` argv;
  // `GIT_CONFIG_NOSYSTEM`+`GIT_CONFIG_GLOBAL=/dev/null` neutralize system/global
  // helpers, and the connected repo is freshly cloned with no repo-local
  // `credential.helper`, so `GIT_ASKPASS` is authoritative. The token rides
  // `GIT_INSTALLATION_TOKEN` (env) and is `printf`'d by the fixed askpass
  // script; it is NEVER interpolated into the script body or a remote URL, and
  // is NEVER logged (`hr-github-app-auth-not-pat`). BOTH-OR-NOTHING: a
  // half-wired askpass (path without token, or token without path) is a silent
  // auth failure, so inject the set only when both inputs are present (empty
  // string counts as absent — graceful-degradation parity with `GH_TOKEN`).
  if (opts?.gitAskpassScriptPath && opts?.gitInstallationToken) {
    env.GIT_ASKPASS = opts.gitAskpassScriptPath;
    env.GIT_USERNAME = "x-access-token";
    env.GIT_INSTALLATION_TOKEN = opts.gitInstallationToken;
    env.GIT_TERMINAL_PROMPT = "0";
    env.GIT_CONFIG_NOSYSTEM = "1";
    env.GIT_CONFIG_GLOBAL = "/dev/null";
  }

  // Deployed plugin root for the agent's `bash` shell-outs (Slice B / #6223).
  // Injected OUTSIDE the allowlist loop and the auth switch — it is a
  // per-dispatch platform path (getPluginPath()), NOT an ambient process.env
  // value, so it is deliberately absent from AGENT_ENV_ALLOWLIST. The deployed
  // skills expand `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` to run the
  // platform-controlled worktree-manager.sh, never the untrusted connected-repo
  // copy.
  //
  // FAIL-CLOSED (#6223, ADR-093): the injection is the per-dispatch boundary at
  // which the export invariant is pinned. A dispatch whose env OMITS
  // CLAUDE_PLUGIN_ROOT would let the `:-./plugins/soleur` fallback resolve the
  // connected repo's UNTRUSTED committed copy — silently re-opening the hole
  // ADR-093 closes (neutered redact-sentinel.sh; trigger.sh secret exfil). So:
  //   - present → validate via assertTrustedPluginPath (rejects non-/app/ in
  //     prod; returns the value unchanged) then set. This is a SECOND, distinct
  //     call from the `:197` guard in agent-runner-query-options.ts — that one
  //     protects the SDK `plugins:[{path}]` binding sink; THIS one protects the
  //     exported CLAUDE_PLUGIN_ROOT bash-env sink. Both are deliberate; do not
  //     collapse (see ADR-093 amendment + the plan's Alternatives table).
  //   - absent/empty in a PRODUCTION env → THROW (fail closed). Enforcement
  //     travels WITH the value-injection point, so any future buildAgentEnv
  //     caller that bypasses buildAgentQueryOptions is still covered.
  //   - absent/empty in a test env → omit (fixture ergonomics for the many
  //     no-pluginPath unit tests). The VITEST/NODE_ENV=test bypass predicate is
  //     the canonical one in plugin-path.ts (getPluginPath /
  //     assertTrustedPluginPath) — kept identical here so the copies cannot drift.
  if (opts?.pluginPath) {
    env.CLAUDE_PLUGIN_ROOT = assertTrustedPluginPath(opts.pluginPath);
  } else if (!(process.env.VITEST || process.env.NODE_ENV === "test")) {
    throw new Error(
      "[plugin-path] CLAUDE_PLUGIN_ROOT export required for agent dispatch — pluginPath was empty/undefined",
    );
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
