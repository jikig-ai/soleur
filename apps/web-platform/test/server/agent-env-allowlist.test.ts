/**
 * Drift-guard: server-only env vars introduced by feat-team-workspace-multi-user
 * (Phase 4 feature flag + allowlist) MUST NEVER reach the agent subprocess.
 *
 * `buildAgentEnv` constructs the subprocess env from a frozen allowlist
 * (`AGENT_ENV_ALLOWLIST` in server/agent-env.ts). Per learning
 * 2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526,
 * any future widening of the allowlist that includes
 *   - FLAG_TEAM_WORKSPACE_INVITE
 *   - TEAM_WORKSPACE_ALLOWLIST_ORG_IDS
 * is a CWE-526 regression. This test runs `buildAgentEnv` with both vars
 * populated in process.env and asserts neither leaks into the returned env
 * object, which is what `child_process.spawn({env})` consumes.
 */

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { buildAgentEnv } from "@/server/agent-env";

const KEYS_TO_VERIFY = [
  "FLAG_TEAM_WORKSPACE_INVITE",
  "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS",
] as const;

// Capture originals so we restore exactly (not unconditionally delete) — the
// test process may inherit these in dev/CI configs and other tests in this
// file shouldn't see drift.
const originals: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const key of KEYS_TO_VERIFY) {
    originals[key] = process.env[key];
    process.env[key] = "should-never-reach-agent";
  }
});

afterEach(() => {
  for (const key of KEYS_TO_VERIFY) {
    if (originals[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = originals[key];
    }
  }
});

describe("buildAgentEnv: feat-team-workspace-multi-user env var isolation (CWE-526)", () => {
  it("does NOT include FLAG_TEAM_WORKSPACE_INVITE in the subprocess env", () => {
    const env = buildAgentEnv("test-api-key");
    expect(env).not.toHaveProperty("FLAG_TEAM_WORKSPACE_INVITE");
  });

  it("does NOT include TEAM_WORKSPACE_ALLOWLIST_ORG_IDS in the subprocess env", () => {
    const env = buildAgentEnv("test-api-key");
    expect(env).not.toHaveProperty("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS");
  });

  it("still includes the canonical agent runtime contract (ANTHROPIC_API_KEY + overrides)", () => {
    const env = buildAgentEnv("test-api-key");
    expect(env.ANTHROPIC_API_KEY).toBe("test-api-key");
    expect(env.DISABLE_AUTOUPDATER).toBe("1");
    expect(env.DISABLE_TELEMETRY).toBe("1");
  });
});
