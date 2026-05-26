import { describe, test, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { createHmac } from "node:crypto";
import { resolve } from "node:path";

// Operator hash-user-id CLI tests — #3711.
//
// The CLI imports `hashUserId` from `apps/web-platform/server/observability.ts`
// (single source of truth — same HMAC + pepper primitive used by pino
// formatters.log() rename hook + reportSilentFallback helpers). The script
// runs operator-locally under `doppler run -p soleur -c prd -- npm run -w
// apps/web-platform hash-user-id <uuid>`. These tests exercise the script
// via Bun child-process so the runtime contract matches production
// invocation exactly.
//
// References:
// - Plan: knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md
// - Sibling pattern: apps/web-platform/scripts/verify-stripe-prices.ts

const SCRIPT_PATH = resolve(__dirname, "../../scripts/hash-user-id.ts");
const FIXTURE_UUID = "11111111-2222-3333-4444-555555555555";
const FIXTURE_PEPPER = "test-pepper";

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

describe("scripts/hash-user-id — operator CLI", () => {
  test("happy path: emits 64-hex hash matching reference HMAC", () => {
    // nosemgrep: javascript.lang.security.audit.hardcoded-hmac-key.hardcoded-hmac-key -- FIXTURE_PEPPER is a synthesized test fixture, not a real key
    const expected = createHmac("sha256", FIXTURE_PEPPER)
      .update(FIXTURE_UUID)
      .digest("hex");
    expect(expected).toHaveLength(64);

    const { stdout, stderr, status } = runScript([FIXTURE_UUID], {
      SENTRY_USERID_PEPPER: FIXTURE_PEPPER,
    });

    expect(status).toBe(0);
    expect(stderr).toBe("");
    expect(stdout.trim()).toBe(expected);
    expect(stdout.trim()).toMatch(/^[0-9a-f]{64}$/);
  });

  test("no argv: exits non-zero with `usage:` stderr message", () => {
    const { stdout, stderr, status } = runScript([], {
      SENTRY_USERID_PEPPER: FIXTURE_PEPPER,
    });

    expect(status).not.toBe(0);
    expect(stdout).toBe("");
    expect(stderr).toMatch(/usage:/i);
  });

  test("no pepper: exits non-zero with `pepper not set` stderr message", () => {
    const { stdout, stderr, status } = runScript([FIXTURE_UUID], {
      SENTRY_USERID_PEPPER: undefined,
    });

    expect(status).not.toBe(0);
    expect(stdout).toBe("");
    expect(stderr).toMatch(/pepper not set/i);
    // Distinct from the runtime sentinel `"pepper_unset"` so log-grep
    // operators don't confuse a CLI fail with a runtime fail-closed event.
    expect(stderr).not.toContain("pepper_unset\n");
  });

  test("deterministic: same uuid + pepper produces same hash", () => {
    const run1 = runScript([FIXTURE_UUID], {
      SENTRY_USERID_PEPPER: FIXTURE_PEPPER,
    });
    const run2 = runScript([FIXTURE_UUID], {
      SENTRY_USERID_PEPPER: FIXTURE_PEPPER,
    });
    expect(run1.stdout.trim()).toBe(run2.stdout.trim());
  });

  test("output is exactly 64 hex chars (sharp-edge sanity guard catches contract drift)", () => {
    const { stdout } = runScript([FIXTURE_UUID], {
      SENTRY_USERID_PEPPER: FIXTURE_PEPPER,
    });
    expect(stdout.trim()).toHaveLength(64);
  });
});
