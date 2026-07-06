import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { buildAgentEnv } from "../server/agent-env";

// Intentionally duplicated from agent-env.ts -- importing would defeat the
// security boundary test. Changes to the allowlist must be reflected here,
// forcing an explicit review of what the subprocess can see.
const SERVER_SECRETS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "BYOK_ENCRYPTION_KEY",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "STRIPE_PRICE_ID",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "PORT",
  "WORKSPACES_ROOT",
  "SOLEUR_PLUGIN_PATH",
  "CLAUDECODE",
  "RANDOM_NEW_SECRET",
] as const;

const EXPECTED_ALLOWLIST = [
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
] as const;

const EXPECTED_OVERRIDES: Record<string, string> = {
  DISABLE_AUTOUPDATER: "1",
  DISABLE_TELEMETRY: "1",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
};

describe("buildAgentEnv", () => {
  const savedEnv: Record<string, string | undefined> = {};
  const env = process.env as Record<string, string | undefined>;

  beforeEach(() => {
    // Save and set all allowlisted vars so tests are deterministic
    for (const key of EXPECTED_ALLOWLIST) {
      savedEnv[key] = env[key];
      env[key] = `test-${key.toLowerCase()}`;
    }
    // Inject server secrets into process.env
    for (const key of SERVER_SECRETS) {
      savedEnv[key] = env[key];
      env[key] = `secret-${key.toLowerCase()}`;
    }
  });

  afterEach(() => {
    // Restore original env
    for (const key of [...EXPECTED_ALLOWLIST, ...SERVER_SECRETS]) {
      if (savedEnv[key] === undefined) {
        delete env[key];
      } else {
        env[key] = savedEnv[key];
      }
    }
  });

  test("sets ANTHROPIC_API_KEY to the provided key", () => {
    const env = buildAgentEnv({ value: "sk-ant-test-key", scheme: "api_key" });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test-key");
  });

  test("forwards all allowlisted vars when present", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const key of EXPECTED_ALLOWLIST) {
      expect(env[key]).toBe(`test-${key.toLowerCase()}`);
    }
  });

  test("excludes all known server secrets", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const key of SERVER_SECRETS) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("always includes hardcoded overrides", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    for (const [key, value] of Object.entries(EXPECTED_OVERRIDES)) {
      expect(env[key]).toBe(value);
    }
  });

  test("exports opts.pluginPath as CLAUDE_PLUGIN_ROOT (#4826 plugin-shadow fix)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, undefined, {
      pluginPath: "/app/shared/plugins/soleur",
    });
    expect(env.CLAUDE_PLUGIN_ROOT).toBe("/app/shared/plugins/soleur");
  });

  test("omits CLAUDE_PLUGIN_ROOT when no pluginPath is supplied", () => {
    // Deliberately NOT copied from ambient process.env — it is a per-dispatch value.
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("CLAUDE_PLUGIN_ROOT");
  });

  test("omits allowlisted vars not present in process.env", () => {
    const mutableEnv = process.env as Record<string, string | undefined>;
    delete mutableEnv.LANG;
    delete mutableEnv.LC_ALL;
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("LANG");
    expect(env).not.toHaveProperty("LC_ALL");
  });

  test("total key count matches allowlist + overrides + ANTHROPIC_API_KEY", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const expectedCount =
      EXPECTED_ALLOWLIST.length +
      Object.keys(EXPECTED_OVERRIDES).length +
      1; // ANTHROPIC_API_KEY
    expect(Object.keys(env).length).toBe(expectedCount);
  });

  test("does not contain CLAUDECODE (prevents nested-session error)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("CLAUDECODE");
  });

  test("forwards proxy vars when present", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env.HTTPS_PROXY).toBe("test-https_proxy");
    expect(env.http_proxy).toBe("test-http_proxy");
  });

  test("contains only known keys (no process.env leakage)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env).not.toHaveProperty("RANDOM_NEW_SECRET");
  });

  test("injects service tokens when provided", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {
      CLOUDFLARE_API_TOKEN: "cf-token-123",
      STRIPE_SECRET_KEY: "sk_test_456",
    });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    expect(env.CLOUDFLARE_API_TOKEN).toBe("cf-token-123");
    expect(env.STRIPE_SECRET_KEY).toBe("sk_test_456");
  });

  test("works without service tokens (backward compatible)", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    expect(env).not.toHaveProperty("CLOUDFLARE_API_TOKEN");
  });

  test("service tokens do not leak server secrets", () => {
    const env = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {
      GITHUB_TOKEN: "ghp_test",
    });
    expect(env.GITHUB_TOKEN).toBe("ghp_test");
    for (const key of SERVER_SECRETS) {
      if (key === "STRIPE_SECRET_KEY") continue; // Not injected in this test
      expect(env).not.toHaveProperty(key);
    }
  });

  test("empty service tokens map does not affect output", () => {
    const envWithout = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
    const envWith = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" }, {});
    expect(Object.keys(envWith).length).toBe(Object.keys(envWithout).length);
  });

  // --- GH_TOKEN injection (Issue A — Concierge gh-auth, AC3) ---------------
  // The minted GitHub App installation token rides as `GH_TOKEN` (the var
  // `gh` prefers over `GITHUB_TOKEN`) via a dedicated typed `opts.ghToken`
  // param — NOT through the serviceTokens map (which keys to GITHUB_TOKEN
  // and is BYOK-clobberable). See agent-env.ts and cc-dispatcher.ts.
  describe("ghToken injection", () => {
    test("injects GH_TOKEN when opts.ghToken is set", () => {
      const env = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "ghs_minted_install_token" },
      );
      expect(env.GH_TOKEN).toBe("ghs_minted_install_token");
      // Auth-var switch untouched.
      expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test");
    });

    test("omits GH_TOKEN when opts.ghToken is absent or empty", () => {
      const envNoOpts = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
      expect(envNoOpts).not.toHaveProperty("GH_TOKEN");
      const envEmpty = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "" },
      );
      expect(envEmpty).not.toHaveProperty("GH_TOKEN");
      const envUndef = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        {},
      );
      expect(envUndef).not.toHaveProperty("GH_TOKEN");
    });

    test("GH_TOKEN (minted) and GITHUB_TOKEN (BYOK service token) coexist; gh prefers GH_TOKEN", () => {
      const env = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        { GITHUB_TOKEN: "ghp_byok_pat" },
        { ghToken: "ghs_minted_install_token" },
      );
      // Both present — the minted install token is the gh-preferred var,
      // and the BYOK PAT is left untouched under its own var.
      expect(env.GH_TOKEN).toBe("ghs_minted_install_token");
      expect(env.GITHUB_TOKEN).toBe("ghp_byok_pat");
    });

    test("GH_TOKEN is injected even though it is NOT in ALLOWED_SERVICE_ENV_VARS (bypasses the service-token loop)", () => {
      // Passing GH_TOKEN through the serviceTokens map would be dropped by the
      // allowlist; the opts param is the only path that lands it.
      const viaServiceTokens = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        { GH_TOKEN: "should_be_dropped" },
      );
      expect(viaServiceTokens).not.toHaveProperty("GH_TOKEN");
      const viaOpts = buildAgentEnv(
        { value: "sk-ant-test", scheme: "api_key" },
        undefined,
        { ghToken: "lands_via_opts" },
      );
      expect(viaOpts.GH_TOKEN).toBe("lands_via_opts");
    });
  });
});
