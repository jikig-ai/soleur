import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { buildAgentEnv } from "../server/agent-env";

const SERVER_SECRETS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "BYOK_ENCRYPTION_KEY",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "PORT",
  "WORKSPACES_ROOT",
  "SOLEUR_PLUGIN_PATH",
  "CLAUDECODE",
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
] as const;

const EXPECTED_OVERRIDES: Record<string, string> = {
  DISABLE_AUTOUPDATER: "1",
  DISABLE_TELEMETRY: "1",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
};

describe("buildAgentEnv", () => {
  const savedEnv: Record<string, string | undefined> = {};

  beforeEach(() => {
    // Save and set all allowlisted vars so tests are deterministic
    for (const key of EXPECTED_ALLOWLIST) {
      savedEnv[key] = process.env[key];
      process.env[key] = `test-${key.toLowerCase()}`;
    }
    // Inject server secrets into process.env
    for (const key of SERVER_SECRETS) {
      savedEnv[key] = process.env[key];
      process.env[key] = `secret-${key.toLowerCase()}`;
    }
  });

  afterEach(() => {
    // Restore original env
    for (const key of [...EXPECTED_ALLOWLIST, ...SERVER_SECRETS]) {
      if (savedEnv[key] === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = savedEnv[key];
      }
    }
  });

  test("sets ANTHROPIC_API_KEY to the provided key", () => {
    const env = buildAgentEnv("sk-ant-test-key");
    expect(env.ANTHROPIC_API_KEY).toBe("sk-ant-test-key");
  });

  test("forwards all allowlisted vars when present", () => {
    const env = buildAgentEnv("sk-ant-test");
    for (const key of EXPECTED_ALLOWLIST) {
      expect(env[key]).toBe(`test-${key.toLowerCase()}`);
    }
  });

  test("excludes all known server secrets", () => {
    const env = buildAgentEnv("sk-ant-test");
    for (const key of SERVER_SECRETS) {
      expect(env).not.toHaveProperty(key);
    }
  });

  test("always includes hardcoded overrides", () => {
    const env = buildAgentEnv("sk-ant-test");
    for (const [key, value] of Object.entries(EXPECTED_OVERRIDES)) {
      expect(env[key]).toBe(value);
    }
  });

  test("omits allowlisted vars not present in process.env", () => {
    delete process.env.LANG;
    delete process.env.LC_ALL;
    const env = buildAgentEnv("sk-ant-test");
    expect(env).not.toHaveProperty("LANG");
    expect(env).not.toHaveProperty("LC_ALL");
  });

  test("total key count matches allowlist + overrides + ANTHROPIC_API_KEY", () => {
    const env = buildAgentEnv("sk-ant-test");
    const expectedCount =
      EXPECTED_ALLOWLIST.length +
      Object.keys(EXPECTED_OVERRIDES).length +
      1; // ANTHROPIC_API_KEY
    expect(Object.keys(env).length).toBe(expectedCount);
  });

  test("does not contain CLAUDECODE (prevents nested-session error)", () => {
    process.env.CLAUDECODE = "1";
    const env = buildAgentEnv("sk-ant-test");
    expect(env).not.toHaveProperty("CLAUDECODE");
    delete process.env.CLAUDECODE;
  });

  test("forwards proxy vars when present", () => {
    process.env.HTTPS_PROXY = "http://proxy.corp:8080";
    const env = buildAgentEnv("sk-ant-test");
    expect(env.HTTPS_PROXY).toBe("http://proxy.corp:8080");
  });

  test("contains only known keys (no process.env leakage)", () => {
    process.env.RANDOM_NEW_SECRET = "should-not-leak";
    const env = buildAgentEnv("sk-ant-test");
    expect(env).not.toHaveProperty("RANDOM_NEW_SECRET");
    delete process.env.RANDOM_NEW_SECRET;
  });
});
