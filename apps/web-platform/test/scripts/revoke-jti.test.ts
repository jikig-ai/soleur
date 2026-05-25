import { describe, test, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

// Operator revoke-jti CLI tests — #3930.
//
// The CLI calls the `revoke_jti(uuid, uuid, text)` SECURITY DEFINER RPC
// (migration 068) via `createServiceClient()`. These tests cover argv
// validation (missing flags, malformed UUIDs) WITHOUT contacting the
// DB. Smoke against real dev Supabase is documented in the plan
// Phase 2.3 and executed inline at /work time (not as a vitest case
// because it would burn GoTrue rate-limit budget on every CI run).
//
// References:
// - Plan: knowledge-base/project/plans/2026-05-25-feat-jti-revoke-rls-3930-3932-plan.md §Phase 2.1
// - Sibling pattern: apps/web-platform/test/scripts/hash-user-id.test.ts

const SCRIPT_PATH = resolve(__dirname, "../../scripts/revoke-jti.ts");
const VALID_UUID_A = "11111111-2222-3333-4444-555555555555";
const VALID_UUID_B = "66666666-7777-8888-9999-aaaaaaaaaaaa";

function runScript(
  args: string[],
  env: Record<string, string | undefined> = {},
): { stdout: string; stderr: string; status: number } {
  const result = spawnSync("bun", [SCRIPT_PATH, ...args], {
    env: { ...process.env, ...env, PATH: process.env.PATH },
    encoding: "utf8",
    timeout: 10_000,
  });
  if (result.error) {
    throw new Error(
      `bun spawn failed (is bun on PATH?): ${result.error.message}`,
    );
  }
  return {
    stdout: result.stdout?.toString() ?? "",
    stderr: result.stderr?.toString() ?? "",
    status: result.status ?? -1,
  };
}

describe("scripts/revoke-jti — operator CLI argv validation", () => {
  test("missing --jti: exit 2 with ::error::missing required flag --jti", () => {
    const { stderr, status } = runScript([
      "--founder-id",
      VALID_UUID_A,
      "--reason",
      "test",
    ]);
    expect(status).toBe(2);
    expect(stderr).toContain("::error::missing required flag --jti");
  });

  test("missing --founder-id: exit 2 with ::error::missing required flag --founder-id", () => {
    const { stderr, status } = runScript([
      "--jti",
      VALID_UUID_A,
      "--reason",
      "test",
    ]);
    expect(status).toBe(2);
    expect(stderr).toContain("::error::missing required flag --founder-id");
  });

  test("missing --reason: exit 2 with ::error::missing required flag --reason", () => {
    const { stderr, status } = runScript([
      "--jti",
      VALID_UUID_A,
      "--founder-id",
      VALID_UUID_B,
    ]);
    expect(status).toBe(2);
    expect(stderr).toContain("::error::missing required flag --reason");
  });

  test("malformed --jti UUID: exit 2 before any DB write", () => {
    const { stderr, status } = runScript([
      "--jti",
      "not-a-uuid",
      "--founder-id",
      VALID_UUID_B,
      "--reason",
      "test",
      "--yes",
    ]);
    expect(status).toBe(2);
    expect(stderr).toMatch(/::error::--jti must be UUID/);
  });

  test("malformed --founder-id UUID: exit 2 before any DB write", () => {
    const { stderr, status } = runScript([
      "--jti",
      VALID_UUID_A,
      "--founder-id",
      "12345",
      "--reason",
      "test",
      "--yes",
    ]);
    expect(status).toBe(2);
    expect(stderr).toMatch(/::error::--founder-id must be UUID/);
  });

  // #4440 follow-up to #4418 — `--revoke-session` flag tests. These
  // assert argv parsing reaches the post-revoke session-termination
  // branch (which then needs SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
  // to call the GoTrue admin logout endpoint). The tests do NOT touch
  // a real DB — they sit at the same argv-validation tier as the
  // sibling cases above. Smoke against real dev Supabase is documented
  // in the plan and executed inline at /work time.

  test("--revoke-session flag is accepted by argv parser (no malformed-flag error)", () => {
    // Pair with a malformed jti so the parser still rejects at the
    // UUID-shape gate AFTER consuming the new flag — proves the flag
    // does NOT confuse the positional flag-value lookup. Same exit-2
    // semantic as the malformed-uuid tests above. If parseArgs treated
    // `--revoke-session` as a value-taking flag, this would surface
    // as a "missing required flag" failure instead.
    const { stderr, status } = runScript([
      "--jti",
      "not-a-uuid",
      "--founder-id",
      VALID_UUID_B,
      "--reason",
      "test",
      "--revoke-session",
      "--yes",
    ]);
    expect(status).toBe(2);
    expect(stderr).toMatch(/::error::--jti must be UUID/);
    // Ensure the parser did NOT swallow --reason's value as
    // --revoke-session's argument (regression guard).
    expect(stderr).not.toMatch(/::error::missing required flag --reason/);
  });

  test("absence of --revoke-session: parser still produces exit 2 on malformed jti (control case)", () => {
    const { stderr, status } = runScript([
      "--jti",
      "still-not-a-uuid",
      "--founder-id",
      VALID_UUID_B,
      "--reason",
      "test",
      "--yes",
    ]);
    expect(status).toBe(2);
    expect(stderr).toMatch(/::error::--jti must be UUID/);
  });
});
