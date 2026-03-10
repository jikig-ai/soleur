import { describe, test, expect } from "bun:test";
import { join } from "path";

const SCRIPT_PATH = join(
  import.meta.dirname,
  "..",
  "plugins",
  "soleur",
  "skills",
  "community",
  "scripts",
  "x-community.sh"
);

/**
 * Minimal env with no X API credentials.
 * Includes PATH so bash, jq, and openssl can be found.
 */
const NO_CREDS_ENV: Record<string, string> = {
  PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin",
  HOME: process.env.HOME ?? "/tmp",
};

/**
 * Env with fake X API credentials so the script passes the credential
 * check and reaches argument validation.
 */
const FAKE_CREDS_ENV: Record<string, string> = {
  ...NO_CREDS_ENV,
  X_API_KEY: "test",
  X_API_SECRET: "test",
  X_ACCESS_TOKEN: "test",
  X_ACCESS_TOKEN_SECRET: "test",
};

function decode(buf: Buffer | Uint8Array): string {
  return new TextDecoder().decode(buf);
}

// ---------------------------------------------------------------------------
// Credential validation
// ---------------------------------------------------------------------------

describe("x-community.sh fetch-mentions -- credential validation", () => {
  test("missing credentials exits 1 with descriptive error", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-mentions"], {
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("Missing X API credentials");
  });
});

// ---------------------------------------------------------------------------
// Argument validation (--max-results)
// ---------------------------------------------------------------------------

describe("x-community.sh fetch-mentions -- --max-results validation", () => {
  test("non-numeric --max-results exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results", "abc"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr.length).toBeGreaterThan(0);
  });

  test("--max-results too high (200) exits 1 with range error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results", "200"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr.length).toBeGreaterThan(0);
  });

  test("--max-results too low (2) exits 1 with range error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results", "2"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Argument validation (--since-id)
// ---------------------------------------------------------------------------

describe("x-community.sh fetch-mentions -- --since-id validation", () => {
  test("non-numeric --since-id exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--since-id", "abc"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Unknown flag
// ---------------------------------------------------------------------------

describe("x-community.sh fetch-mentions -- unknown flag", () => {
  test("unknown flag exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--unknown"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr.length).toBeGreaterThan(0);
  });
});
