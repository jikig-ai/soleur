// #8978 Phase-0.4 — unit coverage for the perf probe's pure helpers.
// All fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";

import {
  safePath,
  classifyRequest,
  summarizeColdApi,
  type NavSample,
} from "../../scripts/live-verify/perf-probe";

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
    domContentLoadedMs: null,
    requests: apiDurs.map((d) => ({
      path: "/api/dashboard/today",
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
        kind: "api",
        status: 500,
        durationMs: -1,
        ttfbMs: null,
        serverTiming: null,
      },
      {
        path: "/dashboard",
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
