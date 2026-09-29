// #8978 Phase-0.4 — unit coverage for the perf probe's pure helpers.
// All fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";

import {
  safePath,
  classifyRequest,
  summarizeColdApi,
  countDuplicateGets,
  countExpectedRepeats,
  dupKeyFor,
  summarizeDuplicates,
  summarizeExpectedRepeats,
  durationsFromTiming,
  type NavSample,
  type RequestSample,
} from "../../scripts/live-verify/perf-probe";

describe("perf-probe durationsFromTiming — Playwright unit convention", () => {
  // PR #8984 review P1: timing()'s non-startTime fields are RELATIVE to
  // startTime (epoch ms) with -1 for unavailable — subtracting epoch from
  // relative zeroed the waterfall.
  it("treats responseStart/responseEnd as ms-since-request-start", () => {
    expect(
      durationsFromTiming({ responseStart: 421.7, responseEnd: 980.3 }),
    ).toEqual({ durationMs: 980.3, ttfbMs: 421.7 });
  });

  it("-1 fields mean unavailable → duration -1 / ttfb null", () => {
    expect(durationsFromTiming({ responseStart: -1, responseEnd: -1 })).toEqual(
      { durationMs: -1, ttfbMs: null },
    );
    expect(durationsFromTiming({ responseStart: 100, responseEnd: -1 })).toEqual(
      { durationMs: -1, ttfbMs: 100 },
    );
  });
});

describe("perf-probe safePath", () => {
  it("emits allowlisted paths verbatim", () => {
    expect(safePath("https://app.soleur.ai/dashboard")).toBe("/dashboard");
    expect(safePath("https://app.soleur.ai/api/workspace/active-repo?x=1")).toBe(
      "/api/workspace/active-repo",
    );
  });

  it("strips UUID tails inside api paths", () => {
    expect(
      safePath(
        "https://app.soleur.ai/api/chat/123e4567-e89b-42d3-a456-426614174000/history",
      ),
    ).toBe("/api/chat/<id>/history");
  });

  it("reduces non-allowlisted paths to their first segment (token-bearing shapes)", () => {
    expect(safePath("https://app.soleur.ai/shared/abcSECRETtoken")).toBe(
      "<reduced:/shared>",
    );
    expect(safePath("https://app.soleur.ai/invite/deadbeef")).toBe(
      "<reduced:/invite>",
    );
  });

  it("a single-segment unknown path emits NO segment — the segment IS the token", () => {
    expect(safePath("https://app.soleur.ai/SECRETTOKEN")).toBe("<reduced>");
  });

  it("dashboard chat UUID paths emit with <id> substitution", () => {
    expect(
      safePath(
        "https://app.soleur.ai/dashboard/chat/123e4567-e89b-42d3-a456-426614174000",
      ),
    ).toBe("/dashboard/chat/<id>");
  });

  it("handles unparsable input without throwing", () => {
    expect(safePath("not a url")).toBe("<unparsable>");
  });
});

describe("perf-probe classifyRequest", () => {
  it("document resource type wins", () => {
    expect(
      classifyRequest("https://app.soleur.ai/api/x", "document"),
    ).toBe("document");
  });
  it("non-document fetches to /api/* classify as api", () => {
    expect(
      classifyRequest("https://app.soleur.ai/api/dashboard/today", "fetch"),
    ).toBe("api");
  });
  it("static/other resources classify as other", () => {
    expect(classifyRequest("https://app.soleur.ai/logo.png", "image")).toBe(
      "other",
    );
  });
});

describe("perf-probe summarizeColdApi", () => {
  const sample = (apiDurs: number[], label = "cold-1"): NavSample => ({
    label,
    docTtfbMs: null,
    docServerTiming: null,
    fcpMs: null,
    lcpMs: null,
    cls: null,
    domContentLoadedMs: null,
    duplicates: [],
    expectedRepeats: [],
    requests: apiDurs.map((d) => ({
      path: "/api/dashboard/today",
      dupKey: "k-today",
      method: "GET",
      kind: "api" as const,
      status: 200,
      durationMs: d,
      ttfbMs: null,
      serverTiming: null,
    })),
  });

  it("aggregates per-path p50/p95 across samples", () => {
    const out = summarizeColdApi([
      sample([100, 200], "cold-1"),
      sample([300, 400], "cold-2"),
      sample([500], "cold-3"),
    ]);
    expect(out).toHaveLength(1);
    expect(out[0].path).toBe("/api/dashboard/today");
    expect(out[0].n).toBe(5);
    expect(out[0].p50).toBe(300);
    expect(out[0].p95).toBe(500);
  });

  it("excludes failed-timing entries (durationMs -1) and non-api kinds", () => {
    const s = sample([100], "cold-1");
    s.requests.push(
      {
        path: "/api/broken",
        dupKey: "k-broken",
        method: "GET",
        kind: "api",
        status: 500,
        durationMs: -1,
        ttfbMs: null,
        serverTiming: null,
      },
      {
        path: "/dashboard",
        dupKey: "k-doc",
        method: "GET",
        kind: "document",
        status: 200,
        durationMs: 900,
        ttfbMs: null,
        serverTiming: null,
      },
    );
    const out = summarizeColdApi([s]);
    expect(out).toHaveLength(1);
    expect(out[0].n).toBe(1);
  });

  it("returns [] when no api requests were captured", () => {
    expect(summarizeColdApi([sample([], "cold-1")])).toEqual([]);
  });
});

describe("perf-probe countDuplicateGets — same-mount census (#8985)", () => {
  const req = (
    path: string,
    method = "GET",
    kind: RequestSample["kind"] = "api",
    rawUrl?: string,
  ): RequestSample => ({
    path,
    dupKey: dupKeyFor(method, rawUrl ?? `https://app.soleur.ai${path}`),
    method,
    kind,
    status: 200,
    durationMs: 10,
    ttfbMs: null,
    serverTiming: null,
  });

  it("reports GET keys fetched >1 within one navigation, with the count", () => {
    const out = countDuplicateGets([
      req("/api/workspace/active-repo"),
      req("/api/workspace/active-repo"),
      req("/api/workspace/active-repo"),
      req("/api/dashboard/today"),
      req("/api/dashboard/today"),
      req("/api/inbox"),
    ]);
    expect(out).toEqual([
      { key: "GET /api/dashboard/today", count: 2 },
    ]);
    // /api/workspace/active-repo is a designed repeat (2s cloning poll) —
    // excluded from `duplicates` by EXPECTED_REPEAT_GET_PATHS but still
    // REPORTED on the informational channel (a regressed fan-out on the
    // headline path stays observable).
    expect(
      countExpectedRepeats([
        req("/api/workspace/active-repo"),
        req("/api/workspace/active-repo"),
        req("/api/workspace/active-repo"),
      ]),
    ).toEqual([{ key: "GET /api/workspace/active-repo", count: 3 }]);
  });

  it("skips non-GET methods — a POST+GET pair on one path is not a duplicate", () => {
    const out = countDuplicateGets([
      req("/api/x"),
      req("/api/x", "POST"),
      req("/api/x", "POST"),
    ]);
    expect(out).toEqual([]);
  });

  it("counts document GETs — a double document fetch is a duplicate too", () => {
    const out = countDuplicateGets([
      req("/dashboard", "GET", "document"),
      req("/dashboard", "GET", "document"),
    ]);
    expect(out).toEqual([{ key: "GET /dashboard", count: 2 }]);
  });

  it("returns [] when every GET fired once (the P1 met shape)", () => {
    expect(
      countDuplicateGets([req("/api/a"), req("/api/b"), req("/api/c")]),
    ).toEqual([]);
  });

  it("does NOT merge two distinct parameterized GETs the emit path collapses (#9180)", () => {
    // safePath collapses UUID tails to `<id>` — keyed on `path`, two LeaderLoopStatus
    // cost cards fetching different messageIds read as a false duplicate.
    const uuidA = "11111111-2222-3333-4444-555555555555";
    const uuidB = "66666666-7777-8888-9999-000000000000";
    const out = countDuplicateGets([
      req(
        "/api/dashboard/today/<id>/cost",
        "GET",
        "api",
        `https://app.soleur.ai/api/dashboard/today/${uuidA}/cost`,
      ),
      req(
        "/api/dashboard/today/<id>/cost",
        "GET",
        "api",
        `https://app.soleur.ai/api/dashboard/today/${uuidB}/cost`,
      ),
      // Control: the same URL twice still counts.
      req(
        "/api/dashboard/today/<id>/cost",
        "GET",
        "api",
        `https://app.soleur.ai/api/dashboard/today/${uuidA}/cost`,
      ),
    ]);
    expect(out).toEqual([{ key: "GET /api/dashboard/today/<id>/cost", count: 2 }]);
  });

  it("separates query-param-name variants; same-name repeats still count", () => {
    const out = countDuplicateGets([
      req("/api/inbox", "GET", "api", "https://app.soleur.ai/api/inbox?status=a"),
      req("/api/inbox", "GET", "api", "https://app.soleur.ai/api/inbox?status=b"),
      req("/api/inbox", "GET", "api", "https://app.soleur.ai/api/inbox?cursor=x"),
    ]);
    // Different query param NAMES are different request shapes — `status` (2) is
    // the real duplicate; `cursor` is distinct.
    expect(out).toEqual([{ key: "GET /api/inbox", count: 2 }]);
  });
});

describe("perf-probe summarizeDuplicates", () => {
  const sample = (
    label: string,
    dups: { key: string; count: number }[],
  ): NavSample => ({
    label,
    docTtfbMs: null,
    docServerTiming: null,
    fcpMs: null,
    lcpMs: null,
    cls: null,
    domContentLoadedMs: null,
    duplicates: dups,
    expectedRepeats: [],
    requests: [],
  });

  it("rolls per-sample duplicates into worst count + sample labels", () => {
    const out = summarizeDuplicates([
      sample("cold-1", [{ key: "GET /api/a", count: 2 }]),
      sample("cold-2", [{ key: "GET /api/a", count: 4 }]),
      sample("warm-sw", [{ key: "GET /api/b", count: 2 }]),
      sample("cold-3", []),
    ]);
    expect(out).toEqual([
      { key: "GET /api/a", max: 4, samples: ["cold-1", "cold-2"] },
      { key: "GET /api/b", max: 2, samples: ["warm-sw"] },
    ]);
  });

  it("returns [] when no sample carried duplicates", () => {
    expect(
      summarizeDuplicates([sample("cold-1", []), sample("warm-sw", [])]),
    ).toEqual([]);
  });
});
