import { describe, test, expect } from "vitest";
import { buildAgentEnv } from "../server/agent-env";

// Item 1a (plan §Phase 1) — in-sandbox git GIT_ASKPASS credentialing.
//
// `buildAgentEnv` already injects `GH_TOKEN` (for the `gh` CLI). Raw `git`
// push/fetch/pull in the sandbox needs a SEPARATE credential path: a
// GIT_ASKPASS helper script + the installation token on
// `GIT_INSTALLATION_TOKEN`. This mirrors the server-side
// `gitWithInstallationAuth` env block in `git-auth.ts` (the canonical
// precedent) verbatim — no novel credential path.
//
// These six are the credential-relevant subset of `gitWithInstallationAuth`'s
// env block (same names + values); that block's cosmetic `GIT_TERMINAL_PROGRESS`
// is intentionally omitted for the non-interactive sandbox subprocess.
//
// Security invariants pinned here (brand-survival single-user-incident):
//   - both-or-nothing: a half-wired askpass (path without token, or vice
//     versa) is a silent auth failure — inject NEITHER unless BOTH present.
//   - the token appears in NO env key other than GIT_INSTALLATION_TOKEN.
//   - graceful-degradation parity with `GH_TOKEN`: absent inputs → no vars.

const CRED = { value: "sk-ant-test", scheme: "api_key" as const };
const ASKPASS_PATH = "/workspaces/ws-uuid/.askpass-abc123.sh";
const INSTALL_TOKEN = "ghs_install_token_value_abcdefghij";

const EXPECTED_GIT_ASKPASS_VARS = {
  GIT_ASKPASS: ASKPASS_PATH,
  GIT_USERNAME: "x-access-token",
  GIT_INSTALLATION_TOKEN: INSTALL_TOKEN,
  GIT_TERMINAL_PROMPT: "0",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
} as const;

describe("buildAgentEnv — in-sandbox git GIT_ASKPASS injection (item 1a)", () => {
  test("injects all six GIT_* vars when BOTH askpass inputs are present", () => {
    const env = buildAgentEnv(CRED, undefined, {
      gitAskpassScriptPath: ASKPASS_PATH,
      gitInstallationToken: INSTALL_TOKEN,
    });
    for (const [key, value] of Object.entries(EXPECTED_GIT_ASKPASS_VARS)) {
      expect(env[key]).toBe(value);
    }
    // Auth-var switch untouched.
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
  });

  test("injects NONE of the GIT_* askpass vars when both inputs are absent", () => {
    const env = buildAgentEnv(CRED);
    for (const key of Object.keys(EXPECTED_GIT_ASKPASS_VARS)) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("both-or-nothing: only gitAskpassScriptPath present → inject NONE", () => {
    const env = buildAgentEnv(CRED, undefined, {
      gitAskpassScriptPath: ASKPASS_PATH,
    });
    for (const key of Object.keys(EXPECTED_GIT_ASKPASS_VARS)) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("both-or-nothing: only gitInstallationToken present → inject NONE", () => {
    const env = buildAgentEnv(CRED, undefined, {
      gitInstallationToken: INSTALL_TOKEN,
    });
    for (const key of Object.keys(EXPECTED_GIT_ASKPASS_VARS)) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("both-or-nothing: empty-string token is treated as absent", () => {
    const env = buildAgentEnv(CRED, undefined, {
      gitAskpassScriptPath: ASKPASS_PATH,
      gitInstallationToken: "",
    });
    for (const key of Object.keys(EXPECTED_GIT_ASKPASS_VARS)) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("the installation token appears in NO env key other than GIT_INSTALLATION_TOKEN", () => {
    const env = buildAgentEnv(CRED, undefined, {
      gitAskpassScriptPath: ASKPASS_PATH,
      gitInstallationToken: INSTALL_TOKEN,
    });
    const keysCarryingToken = Object.entries(env)
      .filter(([, v]) => v === INSTALL_TOKEN)
      .map(([k]) => k);
    expect(keysCarryingToken).toEqual(["GIT_INSTALLATION_TOKEN"]);
  });

  test("askpass token is distinct from GH_TOKEN; both ride their own dedicated key", () => {
    const env = buildAgentEnv(CRED, undefined, {
      ghToken: "ghs_gh_cli_token_value",
      gitAskpassScriptPath: ASKPASS_PATH,
      gitInstallationToken: INSTALL_TOKEN,
    });
    expect(env.GH_TOKEN).toBe("ghs_gh_cli_token_value");
    expect(env.GIT_INSTALLATION_TOKEN).toBe(INSTALL_TOKEN);
    // The installation token must not have been duplicated into GH_TOKEN.
    expect(env.GH_TOKEN).not.toBe(INSTALL_TOKEN);
  });
});
