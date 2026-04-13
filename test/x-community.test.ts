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

const CHECK_METRICS_ANOMALY_HELPER = join(
  import.meta.dirname,
  "helpers",
  "test-check-metrics-anomaly.sh"
);

// x-community.sh calls require_jq in main() before dispatching to any command,
// so ALL tests that invoke the script need this guard, not just direct jq calls.
const HAS_JQ =
  Bun.spawnSync(["jq", "--version"], {
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin" },
  }).exitCode === 0;

if (!HAS_JQ && process.env.CI) {
  throw new Error(
    "jq is required in CI but not found. Install it in the CI image."
  );
}

if (!HAS_JQ) {
  console.warn(
    "WARNING: jq is not installed. Skipping jq-dependent tests in x-community.test.ts. " +
      "Install jq for full test coverage: https://jqlang.github.io/jq/download/"
  );
}

const describeIfJq = HAS_JQ ? describe : describe.skip;

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

describeIfJq("x-community.sh fetch-mentions -- credential validation", () => {
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

describeIfJq("x-community.sh fetch-mentions -- --max-results validation", () => {
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

describeIfJq("x-community.sh fetch-mentions -- --since-id validation", () => {
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

describeIfJq("x-community.sh fetch-mentions -- unknown flag", () => {
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

describeIfJq("x-community.sh fetch-mentions -- jq transform", () => {
  const JQ_TRANSFORM = `
    ((.includes.users // []) | INDEX(.id)) as $users |
    {
      mentions: [
        .data[] |
        ($users[.author_id] // {}) as $user |
        {
          id: .id,
          text: .text,
          author_id: .author_id,
          author_username: ($user.username // "unknown"),
          author_name: ($user.name // "unknown"),
          author_profile_image_url: ($user.profile_image_url // null),
          author_followers_count: ($user.public_metrics.followers_count // 0),
          created_at: .created_at,
          conversation_id: .conversation_id,
          referenced_tweets: (.referenced_tweets // null)
        }
      ],
      meta: {
        newest_id: (.meta.newest_id // null),
        result_count: (.meta.result_count // 0)
      }
    }`;

  test("joins includes.users to data by author_id with enriched fields", () => {
    const input = JSON.stringify({
      data: [
        { id: "1", text: "hello @soleur", author_id: "100", created_at: "2026-03-10T00:00:00Z", conversation_id: "1" },
      ],
      includes: {
        users: [{
          id: "100", username: "alice", name: "Alice",
          profile_image_url: "https://pbs.twimg.com/profile_images/alice.jpg",
          public_metrics: { followers_count: 1234, following_count: 100, tweet_count: 500, listed_count: 10 },
        }],
      },
      meta: { newest_id: "1", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions).toHaveLength(1);
    expect(output.mentions[0].author_id).toBe("100");
    expect(output.mentions[0].author_username).toBe("alice");
    expect(output.mentions[0].author_name).toBe("Alice");
    expect(output.mentions[0].author_profile_image_url).toBe("https://pbs.twimg.com/profile_images/alice.jpg");
    expect(output.mentions[0].author_followers_count).toBe(1234);
    expect(output.mentions[0].referenced_tweets).toBeNull();
    expect(output.meta.newest_id).toBe("1");
  });

  test("preserves tweets when includes.users is missing (fallback to defaults)", () => {
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
    expect(output.mentions[0].author_profile_image_url).toBeNull();
    expect(output.mentions[0].author_followers_count).toBe(0);
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
    expect(output.mentions[0].author_profile_image_url).toBeNull();
    expect(output.mentions[0].author_followers_count).toBe(0);
  });

  test("outputs referenced_tweets with retweet type", () => {
    const input = JSON.stringify({
      data: [
        {
          id: "4", text: "RT @soleur: great post", author_id: "400",
          created_at: "2026-03-10T00:00:00Z", conversation_id: "4",
          referenced_tweets: [{ type: "retweeted", id: "999" }],
        },
      ],
      includes: { users: [{ id: "400", username: "bob", name: "Bob" }] },
      meta: { newest_id: "4", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].referenced_tweets).toHaveLength(1);
    expect(output.mentions[0].referenced_tweets[0].type).toBe("retweeted");
    expect(output.mentions[0].referenced_tweets[0].id).toBe("999");
  });

  test("outputs referenced_tweets with quoted type", () => {
    const input = JSON.stringify({
      data: [
        {
          id: "5", text: "Check this out @soleur", author_id: "500",
          created_at: "2026-03-10T00:00:00Z", conversation_id: "5",
          referenced_tweets: [{ type: "quoted", id: "888" }],
        },
      ],
      includes: { users: [{ id: "500", username: "carol", name: "Carol" }] },
      meta: { newest_id: "5", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].referenced_tweets).toHaveLength(1);
    expect(output.mentions[0].referenced_tweets[0].type).toBe("quoted");
  });

  test("outputs referenced_tweets with replied_to type", () => {
    const input = JSON.stringify({
      data: [
        {
          id: "9", text: "replying to @soleur thread", author_id: "900",
          created_at: "2026-03-10T00:00:00Z", conversation_id: "9",
          referenced_tweets: [{ type: "replied_to", id: "777" }],
        },
      ],
      includes: { users: [{ id: "900", username: "grace", name: "Grace" }] },
      meta: { newest_id: "9", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].referenced_tweets).toHaveLength(1);
    expect(output.mentions[0].referenced_tweets[0].type).toBe("replied_to");
    expect(output.mentions[0].referenced_tweets[0].id).toBe("777");
  });

  test("outputs null referenced_tweets when absent from API response", () => {
    const input = JSON.stringify({
      data: [
        { id: "6", text: "hey @soleur", author_id: "600", created_at: "2026-03-10T00:00:00Z", conversation_id: "6" },
      ],
      includes: { users: [{ id: "600", username: "dave", name: "Dave" }] },
      meta: { newest_id: "6", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].referenced_tweets).toBeNull();
  });

  test("missing public_metrics falls back to 0 followers", () => {
    const input = JSON.stringify({
      data: [
        { id: "7", text: "hello @soleur", author_id: "700", created_at: "2026-03-10T00:00:00Z", conversation_id: "7" },
      ],
      includes: {
        users: [{ id: "700", username: "eve", name: "Eve", profile_image_url: "https://pbs.twimg.com/eve.jpg" }],
      },
      meta: { newest_id: "7", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].author_followers_count).toBe(0);
    expect(output.mentions[0].author_profile_image_url).toBe("https://pbs.twimg.com/eve.jpg");
  });

  test("missing profile_image_url falls back to null", () => {
    const input = JSON.stringify({
      data: [
        { id: "8", text: "hi @soleur", author_id: "800", created_at: "2026-03-10T00:00:00Z", conversation_id: "8" },
      ],
      includes: {
        users: [{
          id: "800", username: "frank", name: "Frank",
          public_metrics: { followers_count: 50, following_count: 10, tweet_count: 100, listed_count: 1 },
        }],
      },
      meta: { newest_id: "8", result_count: 1 },
    });

    const result = Bun.spawnSync(["jq", JQ_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const output = JSON.parse(decode(result.stdout));
    expect(output.mentions[0].author_profile_image_url).toBeNull();
    expect(output.mentions[0].author_followers_count).toBe(50);
  });
});

// ---------------------------------------------------------------------------
// handle_response -- unified response handler
// ---------------------------------------------------------------------------

describeIfJq("x-community.sh handle_response -- 2xx", () => {
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

describeIfJq("x-community.sh handle_response -- 401", () => {
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

describeIfJq("x-community.sh handle_response -- 403", () => {
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

describeIfJq("x-community.sh handle_response -- default error", () => {
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
// fetch-user-timeline -- argument validation
// ---------------------------------------------------------------------------

describeIfJq("x-community.sh fetch-user-timeline -- argument validation", () => {
  test("missing user_id exits 1 with usage error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-user-timeline"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("requires a user_id argument");
  });

  test("non-numeric user_id exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-user-timeline", "abc"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("must be a positive integer");
  });

  test("non-numeric --max exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-user-timeline", "12345", "--max", "abc"],
      { env: FAKE_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("must be a positive integer");
  });

  test("unknown flag exits 1 with error", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-user-timeline", "12345", "--unknown"],
      { env: FAKE_CREDS_ENV }
    );
    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("Unknown option");
  });

  test("--max without value exits 1", () => {
    const result = Bun.spawnSync(
      ["bash", SCRIPT_PATH, "fetch-user-timeline", "12345", "--max"],
      { env: FAKE_CREDS_ENV }
    );
    expect(result.exitCode).not.toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Rename verification -- x_request must not exist
// No describeIfJq guard needed -- this test uses grep, not jq.
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

// ---------------------------------------------------------------------------
// _has_metrics_anomaly -- anomaly detection for public_metrics
// Shell boolean: 0 = true (anomaly exists), 1 = false (normal)
// ---------------------------------------------------------------------------

describeIfJq("x-community.sh _has_metrics_anomaly", () => {
  test("emits warning when followers=0 but tweets>0 and following>0", () => {
    const metrics = JSON.stringify({
      followers_count: 0,
      following_count: 18,
      tweet_count: 67,
      listed_count: 0,
    });

    const result = Bun.spawnSync(
      ["bash", CHECK_METRICS_ANOMALY_HELPER, metrics],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(0);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("Warning:");
    expect(stderr).toContain("0 followers");
    expect(decode(result.stdout)).toBe("");
  });

  test("emits degradation warning when all social metrics are zero except tweet_count", () => {
    const metrics = JSON.stringify({
      followers_count: 0,
      following_count: 0,
      tweet_count: 67,
      listed_count: 0,
    });

    const result = Bun.spawnSync(
      ["bash", CHECK_METRICS_ANOMALY_HELPER, metrics],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(0);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("Warning:");
    expect(stderr).toContain("API degradation");
  });

  test("no warning when followers > 0", () => {
    const metrics = JSON.stringify({
      followers_count: 5,
      following_count: 18,
      tweet_count: 67,
      listed_count: 1,
    });

    const result = Bun.spawnSync(
      ["bash", CHECK_METRICS_ANOMALY_HELPER, metrics],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toBe("");
  });

  test("no warning when all metrics are zero (genuinely new account)", () => {
    const metrics = JSON.stringify({
      followers_count: 0,
      following_count: 0,
      tweet_count: 0,
      listed_count: 0,
    });

    const result = Bun.spawnSync(
      ["bash", CHECK_METRICS_ANOMALY_HELPER, metrics],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toBe("");
  });

  test("no warning when only listed_count > 0 (listed_count excluded from detection)", () => {
    const metrics = JSON.stringify({
      followers_count: 0,
      following_count: 0,
      tweet_count: 0,
      listed_count: 3,
    });

    const result = Bun.spawnSync(
      ["bash", CHECK_METRICS_ANOMALY_HELPER, metrics],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toBe("");
  });
});
