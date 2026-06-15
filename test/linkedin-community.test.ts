import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "path";

const SCRIPT_PATH = join(
  import.meta.dirname,
  "..",
  "plugins",
  "soleur",
  "skills",
  "community",
  "scripts",
  "linkedin-community.sh"
);

const HANDLE_RESPONSE_HELPER = join(
  import.meta.dirname,
  "helpers",
  "test-handle-response-linkedin.sh"
);

// linkedin-community.sh calls require_jq in main() before dispatching to any
// command, so ALL tests that invoke the script need this guard.
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
    "WARNING: jq is not installed. Skipping jq-dependent tests in linkedin-community.test.ts. " +
      "Install jq for full test coverage: https://jqlang.github.io/jq/download/"
  );
}

const describeIfJq = HAS_JQ ? describe : describe.skip;

/**
 * Minimal env with NO LinkedIn credentials of any kind.
 */
const NO_CREDS_ENV: Record<string, string> = {
  PATH: process.env.PATH ?? "/usr/bin:/bin:/usr/local/bin",
  HOME: process.env.HOME ?? "/tmp",
};

/**
 * Env with a PERSONAL token but NO org creds. Used to prove the fetch
 * commands never silently fall back to the personal token (silent-failure
 * CRITICAL-2): org-cred-missing must exit 1 with no network call.
 */
const PERSONAL_ONLY_ENV: Record<string, string> = {
  ...NO_CREDS_ENV,
  LINKEDIN_ACCESS_TOKEN: "personal",
};

/**
 * Env with only the org token but NOT the org id — require_org_credentials
 * must still exit 1 and name the missing LINKEDIN_ORG_ID.
 */
const ORG_TOKEN_ONLY_ENV: Record<string, string> = {
  ...NO_CREDS_ENV,
  LINKEDIN_ORG_ACCESS_TOKEN: "test",
};

/**
 * Synthetic org creds (fixture hygiene — NOT the real org id 129094054).
 */
const FAKE_ORG_CREDS_ENV: Record<string, string> = {
  ...NO_CREDS_ENV,
  LINKEDIN_ORG_ACCESS_TOKEN: "test",
  LINKEDIN_ORG_ID: "12345",
};

function decode(buf: Buffer | Uint8Array): string {
  return new TextDecoder().decode(buf);
}

// ---------------------------------------------------------------------------
// Source-parity drift guard.
// Several tests below copy the script's jq transform/guard programs as local
// string constants so they can exercise the EXACT shape over fixtures. That
// copy can silently drift if someone edits the script's jq without touching
// the test. Read the script source and assert each copied program is present
// (ignoring pure indentation differences) so a future script-side jq edit
// breaks the test instead of drifting. Mirrors cron-community-monitor.test.ts's
// SUT_SOURCE / .toContain pattern.
// ---------------------------------------------------------------------------

const SUT_SOURCE = readFileSync(SCRIPT_PATH, "utf8");

// Collapse all runs of whitespace to a single space and trim, so the assertion
// tracks the jq program's CONTENT (fields, fallbacks, predicate) rather than
// its indentation — which legitimately differs between the script body and the
// test literal.
function normalizeWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

// ---------------------------------------------------------------------------
// Credential validation (require_org_credentials)
// ---------------------------------------------------------------------------

describeIfJq("linkedin-community.sh fetch-metrics -- org credential validation", () => {
  test("no org creds exits 1 and names both missing vars", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-metrics"], {
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("LINKEDIN_ORG_ACCESS_TOKEN");
    expect(stderr).toContain("LINKEDIN_ORG_ID");
  });

  test("only org token (no org id) exits 1 and names LINKEDIN_ORG_ID", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-metrics"], {
      env: ORG_TOKEN_ONLY_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("LINKEDIN_ORG_ID");
  });
});

describeIfJq("linkedin-community.sh fetch-activity -- org credential validation", () => {
  test("no org creds exits 1 and names both missing vars", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-activity"], {
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("LINKEDIN_ORG_ACCESS_TOKEN");
    expect(stderr).toContain("LINKEDIN_ORG_ID");
  });
});

// ---------------------------------------------------------------------------
// Silent-fallback negative test (silent-failure CRITICAL-2)
// org creds absent BUT personal token present -> still exit 1, no fall-through.
// ---------------------------------------------------------------------------

describeIfJq("linkedin-community.sh -- never falls back to the personal token", () => {
  test("fetch-metrics: personal token present, org creds absent -> exit 1, no 401/expired", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-metrics"], {
      env: PERSONAL_ONLY_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    // Proves we never reached the network / personal-token path:
    expect(stderr).not.toContain("401");
    expect(stderr).not.toContain("expired");
    // Proves we failed at the org-cred check:
    expect(stderr).toContain("LINKEDIN_ORG");
  });

  test("fetch-activity: personal token present, org creds absent -> exit 1, no 401/expired", () => {
    const result = Bun.spawnSync(["bash", SCRIPT_PATH, "fetch-activity"], {
      env: PERSONAL_ONLY_ENV,
    });

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).not.toContain("401");
    expect(stderr).not.toContain("expired");
    expect(stderr).toContain("LINKEDIN_ORG");
  });
});

// ---------------------------------------------------------------------------
// No-MDP / no-Marketing-API regression (Acceptance Criteria)
// ---------------------------------------------------------------------------

describe("linkedin-community.sh -- Marketing API / MDP premise removed", () => {
  test("script no longer mentions 'Marketing API' or 'MDP partner'", () => {
    const marketing = Bun.spawnSync(["grep", "-c", "Marketing API", SCRIPT_PATH], {
      env: NO_CREDS_ENV,
    });
    // grep -c exits 1 when count is 0
    expect(marketing.exitCode).toBe(1);

    const mdp = Bun.spawnSync(["grep", "-c", "MDP partner", SCRIPT_PATH], {
      env: NO_CREDS_ENV,
    });
    expect(mdp.exitCode).toBe(1);
  });

  test("endpoint strings use %3A-encoded org URN + the aggregate endpoints", () => {
    for (const needle of [
      "urn%3Ali%3Aorganization%3A",
      "organizationalEntityShareStatistics",
      "networkSizes",
      "COMPANY_FOLLOWED_BY_MEMBER",
      "X-RestLi-Method: FINDER",
    ]) {
      const r = Bun.spawnSync(["grep", "-c", needle, SCRIPT_PATH], {
        env: NO_CREDS_ENV,
      });
      expect(r.exitCode).toBe(0);
    }
  });

  test("demographic-facet endpoint is NOT present (organizationalEntityFollowerStatistics cut)", () => {
    const r = Bun.spawnSync(
      ["grep", "-c", "organizationalEntityFollowerStatistics", SCRIPT_PATH],
      { env: NO_CREDS_ENV }
    );
    // count 0 -> exit 1
    expect(r.exitCode).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// fetch-metrics jq compose -- share statistics shape + missing-field fallbacks
// The transform mirrors cmd_fetch_metrics's `jq -n` compose; fed share-stats
// + networkSizes fixtures via --argjson so the test exercises the SAME shape.
// ---------------------------------------------------------------------------

// share_statistics extraction from organizationalEntityShareStatistics
// .elements[0].totalShareStatistics, with per-field `// 0` defaults.
const SHARE_STATS_TRANSFORM = `
  .elements[0].totalShareStatistics as $s |
  {
    impressions: ($s.impressionCount // 0),
    unique_impressions: ($s.uniqueImpressionsCount // 0),
    clicks: ($s.clickCount // 0),
    likes: ($s.likeCount // 0),
    comments: ($s.commentCount // 0),
    shares: ($s.shareCount // 0),
    engagement: ($s.engagement // 0)
  }`;

describeIfJq("linkedin-community.sh fetch-metrics -- share-stats jq transform", () => {
  test("maps totalShareStatistics fields into the digest shape", () => {
    const input = JSON.stringify({
      paging: { count: 10, start: 0, total: 1 },
      elements: [
        {
          totalShareStatistics: {
            impressionCount: 1200,
            uniqueImpressionsCount: 980,
            clickCount: 34,
            likeCount: 12,
            commentCount: 3,
            shareCount: 2,
            engagement: 0.045,
          },
        },
      ],
    });

    const result = Bun.spawnSync(["jq", SHARE_STATS_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.impressions).toBe(1200);
    expect(out.unique_impressions).toBe(980);
    expect(out.clicks).toBe(34);
    expect(out.likes).toBe(12);
    expect(out.comments).toBe(3);
    expect(out.shares).toBe(2);
    expect(out.engagement).toBeCloseTo(0.045);
  });

  test("missing optional sub-fields fall back to 0", () => {
    const input = JSON.stringify({
      elements: [{ totalShareStatistics: { impressionCount: 5 } }],
    });

    const result = Bun.spawnSync(["jq", SHARE_STATS_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.impressions).toBe(5);
    expect(out.likes).toBe(0);
    expect(out.engagement).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Shape-validation guard (silent-failure HIGH-1): an empty .elements 200 must
// NOT render as fake zeros. The implementation asserts
// `.elements[0].totalShareStatistics` is a non-null object before composing;
// this exercises the SAME predicate the script uses.
// ---------------------------------------------------------------------------

const SHARE_STATS_SHAPE_GUARD = `(.elements[0].totalShareStatistics | type) == "object"`;

describeIfJq("linkedin-community.sh fetch-metrics -- empty-elements shape guard", () => {
  test("empty .elements fails the shape guard (no fake zeros)", () => {
    const input = JSON.stringify({ paging: { total: 0 }, elements: [] });
    const result = Bun.spawnSync(["jq", "-e", SHARE_STATS_SHAPE_GUARD], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });
    // jq -e exits 1 when the result is false/null
    expect(result.exitCode).toBe(1);
  });

  test("well-shaped .elements passes the shape guard", () => {
    const input = JSON.stringify({
      elements: [{ totalShareStatistics: { impressionCount: 1 } }],
    });
    const result = Bun.spawnSync(["jq", "-e", SHARE_STATS_SHAPE_GUARD], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });
    expect(result.exitCode).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// fetch-activity jq compose -- posts author-finder shape + fallbacks
// Mirrors cmd_fetch_activity's transform over the Posts author-finder body.
// ---------------------------------------------------------------------------

const POSTS_TRANSFORM = `
  {
    posts: [
      .elements[] | {
        id: .id,
        commentary: (.commentary // null),
        published_at: (.publishedAt // .createdAt // null),
        lifecycle_state: (.lifecycleState // null)
      }
    ]
  }`;

// Shape guard cmd_fetch_activity runs BEFORE the `.elements[]` iteration: a
// missing/null `.elements` would crash jq ("Cannot iterate over null", exit 5)
// under set -e. A present-but-empty array must still pass.
const POSTS_SHAPE_GUARD = `(.elements | type) == "array"`;

describeIfJq("linkedin-community.sh fetch-activity -- posts jq transform", () => {
  test("maps post metadata only (no commenter/liker identities)", () => {
    const input = JSON.stringify({
      paging: { count: 10, start: 0 },
      elements: [
        {
          id: "urn:li:share:111",
          author: "urn:li:organization:12345",
          commentary: "We shipped a thing.",
          publishedAt: 1700000000000,
          createdAt: 1699999999000,
          lifecycleState: "PUBLISHED",
        },
        {
          id: "urn:li:share:222",
          author: "urn:li:organization:12345",
          commentary: "Second post.",
          createdAt: 1699999000000,
          lifecycleState: "PUBLISHED",
        },
      ],
    });

    const result = Bun.spawnSync(["jq", POSTS_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.posts).toHaveLength(2);
    expect(out.posts[0].id).toBe("urn:li:share:111");
    expect(out.posts[0].commentary).toBe("We shipped a thing.");
    expect(out.posts[0].published_at).toBe(1700000000000);
    expect(out.posts[0].lifecycle_state).toBe("PUBLISHED");
    // No author/commenter/liker identity fields leak into the digest shape.
    expect(out.posts[0].author).toBeUndefined();
    // publishedAt absent -> falls back to createdAt.
    expect(out.posts[1].published_at).toBe(1699999000000);
  });

  test("missing fields fall back without dropping the post (INDEX-style preservation)", () => {
    const input = JSON.stringify({
      elements: [{ id: "urn:li:share:333" }],
    });

    const result = Bun.spawnSync(["jq", POSTS_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });

    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.posts).toHaveLength(1);
    expect(out.posts[0].id).toBe("urn:li:share:333");
    expect(out.posts[0].commentary).toBeNull();
    expect(out.posts[0].published_at).toBeNull();
    expect(out.posts[0].lifecycle_state).toBeNull();
  });

  test("empty .elements yields an empty posts array (not an error)", () => {
    const input = JSON.stringify({ paging: { total: 0 }, elements: [] });
    const result = Bun.spawnSync(["jq", POSTS_TRANSFORM], {
      stdin: new Response(input),
      env: NO_CREDS_ENV,
    });
    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.posts).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// handle_response -- LinkedIn's ACTUAL handler shape (NOT x-community's)
// LinkedIn handle_response has NO 403-reason branching: a single generic
// message. The exit-2 rate-limit path lives in get_request (depth guard),
// NOT handle_response.
// ---------------------------------------------------------------------------

describeIfJq("linkedin-community.sh handle_response -- 2xx", () => {
  test("2xx with valid JSON echoes body to stdout", () => {
    const body = JSON.stringify({ elements: [] });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "handle_response", "200", body, "/rest/x", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(0);
    expect(decode(result.stderr)).toBe("");
    expect(JSON.parse(decode(result.stdout)).elements).toEqual([]);
  });

  test("2xx with malformed JSON exits 1", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "handle_response", "200", "not-json{", "/rest/x", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("malformed JSON");
  });
});

describeIfJq("linkedin-community.sh handle_response -- 401/403", () => {
  test("401 exits 1 with token-expiry guidance", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "handle_response", "401", "{}", "/rest/x", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    expect(decode(result.stderr)).toContain("401 Unauthorized");
  });

  test("403 exits 1 with a generic message (NO reason branching)", () => {
    const body = JSON.stringify({ reason: "client-not-enrolled", message: "no access" });
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "handle_response", "403", body, "/rest/x", "0", "echo", "noop"],
      { env: NO_CREDS_ENV }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("403 Forbidden");
    // LinkedIn surfaces .message generically; it does NOT branch on `reason`.
    expect(stderr).toContain("no access");
    expect(stderr).not.toContain("paid API access");
  });
});

describeIfJq("linkedin-community.sh get_request -- rate-limit exhaustion (exit 2, no network)", () => {
  test("depth>=3 short-circuits to exit 2 before any curl", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "get_request", "/rest/x", "3"],
      { env: FAKE_ORG_CREDS_ENV }
    );

    expect(result.exitCode).toBe(2);
    expect(decode(result.stderr)).toContain("rate limit exceeded");
  });
});

// ---------------------------------------------------------------------------
// Source-parity drift guard: the jq programs copied into this test file as
// local constants MUST still exist (content-equivalent) in the script. If a
// future edit changes the script's jq without updating the copy, these break
// — so the fixture-driven shape/transform tests above can never silently test
// a stale program. Mirrors cron-community-monitor.test.ts's SUT_SOURCE checks.
// ---------------------------------------------------------------------------

describe("linkedin-community.sh -- copied jq programs match the script source", () => {
  const normalizedSource = normalizeWhitespace(SUT_SOURCE);

  for (const [label, program] of [
    ["SHARE_STATS_TRANSFORM", SHARE_STATS_TRANSFORM],
    ["SHARE_STATS_SHAPE_GUARD", SHARE_STATS_SHAPE_GUARD],
    ["POSTS_TRANSFORM", POSTS_TRANSFORM],
    ["POSTS_SHAPE_GUARD", POSTS_SHAPE_GUARD],
  ] as const) {
    test(`${label} is present verbatim (modulo indentation) in the script`, () => {
      expect(normalizedSource).toContain(normalizeWhitespace(program));
    });
  }
});

// ---------------------------------------------------------------------------
// cmd_fetch_activity shape guard (behavioral): runs the REAL command body with
// get_request stubbed from a fixture so no network call is made. A posts body
// missing `.elements` must exit 1 with the actionable message (jq would
// otherwise crash with "Cannot iterate over null"); a present-but-empty
// `elements: []` must succeed -> {"posts": []}.
// ---------------------------------------------------------------------------

describeIfJq("linkedin-community.sh cmd_fetch_activity -- elements shape guard", () => {
  test("missing .elements (e.g. {}) exits 1 with the actionable message", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "cmd_fetch_activity"],
      {
        env: {
          ...FAKE_ORG_CREDS_ENV,
          GET_REQUEST_POSTS_BODY: "{}",
        },
      }
    );

    expect(result.exitCode).toBe(1);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("posts author-finder returned no usable elements array");
    expect(stderr).toContain("12345");
    // Crucially NOT the raw jq crash that the guard prevents.
    expect(stderr).not.toContain("Cannot iterate over null");
  });

  test("present-but-empty elements:[] succeeds -> {\"posts\": []}", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "cmd_fetch_activity"],
      {
        env: {
          ...FAKE_ORG_CREDS_ENV,
          GET_REQUEST_POSTS_BODY: JSON.stringify({ elements: [] }),
        },
      }
    );

    expect(result.exitCode).toBe(0);
    const out = JSON.parse(decode(result.stdout));
    expect(out.posts).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// cmd_fetch_metrics firstDegreeSize numeric guard (behavioral): a non-numeric
// follower size must degrade total_followers to null (with a stderr warning)
// rather than abort the emit under set -e — the same degrade path as a failed
// networkSizes fetch.
// ---------------------------------------------------------------------------

describeIfJq("linkedin-community.sh cmd_fetch_metrics -- firstDegreeSize numeric guard", () => {
  test("non-numeric firstDegreeSize degrades total_followers to null (no abort)", () => {
    const result = Bun.spawnSync(
      ["bash", HANDLE_RESPONSE_HELPER, "cmd_fetch_metrics"],
      {
        env: {
          ...FAKE_ORG_CREDS_ENV,
          GET_REQUEST_SHARE_BODY: JSON.stringify({
            elements: [{ totalShareStatistics: { impressionCount: 5 } }],
          }),
          GET_REQUEST_NETWORK_BODY: JSON.stringify({ firstDegreeSize: "abc" }),
        },
      }
    );

    expect(result.exitCode).toBe(0);
    const stderr = decode(result.stderr);
    expect(stderr).toContain("non-numeric firstDegreeSize");
    const out = JSON.parse(decode(result.stdout));
    expect(out.total_followers).toBeNull();
    // The (more important) share-stats result still emits.
    expect(out.share_statistics.impressions).toBe(5);
  });
});
