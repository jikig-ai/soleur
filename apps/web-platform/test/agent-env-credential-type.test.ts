import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { buildAgentEnv, type AgentCredential } from "../server/agent-env";

// feat-operator-cc-oauth Phase 3 — mutually-exclusive auth env injection.
//
// The both-keys trap (FR2): a run must inject EXACTLY ONE of
// ANTHROPIC_API_KEY / CLAUDE_CODE_OAUTH_TOKEN, never both — else a
// subscription run silently bills the API account. This property test
// asserts the invariant across BOTH schemes, plus that the 3
// telemetry-suppression overrides ride OUTSIDE the auth branch (a
// subscription token must not phone home to the operator's account) and
// cannot be clobbered by the service-token loop.

const API_KEY_VAR = "ANTHROPIC_API_KEY";
const OAUTH_VAR = "CLAUDE_CODE_OAUTH_TOKEN";

const TELEMETRY_OVERRIDES = [
  "DISABLE_AUTOUPDATER",
  "DISABLE_TELEMETRY",
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
] as const;

const SCHEMES: AgentCredential["scheme"][] = ["api_key", "oauth_token"];

describe("buildAgentEnv — mutually-exclusive auth scheme", () => {
  const env = process.env as Record<string, string | undefined>;
  let savedHome: string | undefined;

  beforeEach(() => {
    savedHome = env.HOME;
    env.HOME = "/home/test";
  });
  afterEach(() => {
    if (savedHome === undefined) delete env.HOME;
    else env.HOME = savedHome;
  });

  test("api_key scheme sets ONLY ANTHROPIC_API_KEY", () => {
    const result = buildAgentEnv({ value: "sk-ant-key", scheme: "api_key" });
    expect(result[API_KEY_VAR]).toBe("sk-ant-key");
    expect(result).not.toHaveProperty(OAUTH_VAR);
  });

  test("oauth_token scheme sets ONLY CLAUDE_CODE_OAUTH_TOKEN", () => {
    const result = buildAgentEnv({ value: "sk-ant-oat", scheme: "oauth_token" });
    expect(result[OAUTH_VAR]).toBe("sk-ant-oat");
    expect(result).not.toHaveProperty(API_KEY_VAR);
  });

  test("property: exactly one auth var across both schemes", () => {
    for (const scheme of SCHEMES) {
      const result = buildAgentEnv({ value: `v-${scheme}`, scheme });
      const authVarsPresent = [API_KEY_VAR, OAUTH_VAR].filter((v) =>
        Object.prototype.hasOwnProperty.call(result, v),
      );
      expect(authVarsPresent).toHaveLength(1);
    }
  });

  test("AC2b: both schemes carry all 3 telemetry overrides", () => {
    for (const scheme of SCHEMES) {
      const result = buildAgentEnv({ value: "v", scheme });
      for (const key of TELEMETRY_OVERRIDES) {
        expect(result[key]).toBe("1");
      }
    }
  });

  test("AC2b: service-token loop cannot clobber the telemetry overrides", () => {
    for (const scheme of SCHEMES) {
      // DISABLE_* are not provider envVars, so the service-token loop must
      // never override them even when an attacker-shaped map names them.
      const result = buildAgentEnv(
        { value: "v", scheme },
        {
          DISABLE_TELEMETRY: "0",
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "0",
          DISABLE_AUTOUPDATER: "0",
        },
      );
      for (const key of TELEMETRY_OVERRIDES) {
        expect(result[key]).toBe("1");
      }
    }
  });

  test("oauth run: a stray ANTHROPIC_API_KEY service token cannot re-introduce the API key", () => {
    // Defense-in-depth: even if a service-token map carried the api_key var
    // (it never does — getUserServiceTokens skips 'anthropic'), the auth
    // branch is authoritative and the non-selected var is removed.
    const result = buildAgentEnv(
      { value: "sk-ant-oat", scheme: "oauth_token" },
      { ANTHROPIC_API_KEY: "sk-ant-leaked" },
    );
    expect(result[OAUTH_VAR]).toBe("sk-ant-oat");
    expect(result).not.toHaveProperty(API_KEY_VAR);
  });
});
