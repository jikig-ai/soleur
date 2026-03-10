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

const HANDLE_RESPONSE_HELPER = join(
  import.meta.dirname,
  "helpers",
  "test-handle-response.sh"
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
    expect(stderr).toContain("must be a numeric value");
  });

  test("--max-results too high (200) exits 1 with range error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results", "200"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("between 5 and 100");
  });

  test("--max-results too low (2) exits 1 with range error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results", "2"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("between 5 and 100");
  });

  test("--max-results without value exits 1", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--max-results"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("--max-results");
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
    expect(stderr).toContain("must be a numeric value");
  });

  test("--since-id without value exits 1", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-mentions", "--since-id"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("--since-id");
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
    expect(stderr).toContain("Unknown option");
  });
});

// ---------------------------------------------------------------------------
// jq transform (unit test using jq directly)
// ---------------------------------------------------------------------------

describe("x-community.sh fetch-mentions -- jq transform", () => {
  const JQ_TRANSFORM = `
    ((.includes.users // []) | INDEX(.id)) as $users |
    {
      mentions: [
        .data[] |
        ($users[.author_id] // {}) as $user |
        {
          id: .id,
          text: .text,
          author_username: ($user.username // "unknown"),
          author_name: ($user.name // "unknown"),
          created_at: .created_at,
          conversation_id: .conversation_id
        }
      ],
      meta: {
        newest_id: (.meta.newest_id // null),
        result_count: (.meta.result_count // 0)
      }
    }`;

  test("joins includes.users to data by author_id", () => {
    const input = JSON.stringify({
      data: [
        { id: "1", text: "hello @soleur", author_id: "100", created_at: "2026-03-10T00:00:00Z", conversation_id: "1" },
      ],
      includes: { users: [{ id: "100", username: "alice", name: "Alice" }] },
      meta: { newest_id: "1", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions).toHaveLength(1);
    expect(output.mentions[0].author_username).toBe("alice");
    expect(output.mentions[0].author_name).toBe("Alice");
    expect(output.meta.newest_id).toBe("1");
  });

  test("preserves tweets when includes.users is missing", () => {
    const input = JSON.stringify({
      data: [
        { id: "2", text: "hey @soleur", author_id: "200", created_at: "2026-03-10T00:00:00Z", conversation_id: "2" },
      ],
      meta: { newest_id: "2", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions).toHaveLength(1);
    expect(output.mentions[0].author_username).toBe("unknown");
    expect(output.mentions[0].author_name).toBe("unknown");
  });

  test("preserves tweets when author_id has no match in includes.users", () => {
    const input = JSON.stringify({
      data: [
        { id: "3", text: "question @soleur", author_id: "300", created_at: "2026-03-10T00:00:00Z", conversation_id: "3" },
      ],
      includes: { users: [{ id: "999", username: "other", name: "Other" }] },
      meta: { newest_id: "3", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions).toHaveLength(1);
    expect(output.mentions[0].author_username).toBe("unknown");
  });
});

// ---------------------------------------------------------------------------
// handle_response -- unified response handler
// ---------------------------------------------------------------------------

describe("x-community.sh handle_response -- 2xx", () => {
  test("2xx with valid JSON echoes body to stdout", () => {
    const body = JSON.stringify({ data: { id: "1" } });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "200", body, "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(0);
    expect(decode(result.stderr)).toBe("");
    const output = JSON.parse(decode(result.stdout));
    expect(output.data.id).toBe("1");
  });

  test("2xx with malformed JSON exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "200", "not-json{", "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("malformed JSON");
    expect(stderr).toContain("/2/tweets");
  });
});

describe("x-community.sh handle_response -- 401", () => {
  test("401 exits 1 with credential instructions", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "401", "{}", "/2/users/me", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("401 Unauthorized");
    expect(stderr).toContain("/2/users/me");
    expect(stderr).toContain("Regenerate your Access Token");
  });
});

describe("x-community.sh handle_response -- 403", () => {
  test("403 with reason client-not-enrolled gives paid API guidance", () => {
    const body = JSON.stringify({ reason: "client-not-enrolled" });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "403", body, "/2/tweets/search", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("403 Forbidden");
    expect(stderr).toContain("paid API access");
    expect(stderr).toContain("purchase credits");
  });

  test("403 with reason official-client-forbidden gives permissions guidance", () => {
    const body = JSON.stringify({ reason: "official-client-forbidden" });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "403", body, "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("403 Forbidden");
    expect(stderr).toContain("lack the required permissions");
    expect(stderr).not.toContain("suspended");
  });

  test("403 with no reason gives generic message", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "403", "{}", "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("403 Forbidden");
    expect(stderr).toContain("permissions or your account may be suspended");
  });
});

describe("x-community.sh handle_response -- default error", () => {
  test("500 exits 1 with parsed detail", () => {
    const body = JSON.stringify({ detail: "Internal server error" });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "500", body, "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("HTTP 500");
    expect(stderr).toContain("Internal server error");
    expect(stderr).toContain("/2/tweets");
  });

  test("500 with title instead of detail uses title", () => {
    const body = JSON.stringify({ title: "Service Unavailable" });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "500", body, "/2/tweets", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("Service Unavailable");
  });
});

// ---------------------------------------------------------------------------
// Rename verification -- x_request must not exist
// ---------------------------------------------------------------------------

describe("x-community.sh -- rename verification", () => {
  test("x_request is fully renamed to post_request", () => {
    const result = Bun.spawnSync(
      ["grep", "-c", "x_request", SCRIPT_PATH],
      { env: NO_CREDS_ENV }
    );

    // grep -c returns the count; 0 matches means exit code 1
    expect(result.exitCode).toBe(1);
  });
});
