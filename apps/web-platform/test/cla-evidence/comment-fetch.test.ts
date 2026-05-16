// RED-first per cq-write-failing-tests-before. Phase 2.
// TS4: 5xx/429 retry with exponential backoff (max 3 attempts).
// TS5:  404 → degraded record (no retry, status="404", body null).
// TS5b: 4xx≠404 → fast-fail (status="fatal-4xx", code), no retry.
import { describe, it, expect, vi } from "vitest";
import { fetchCommentBody } from "@/scripts/cla-evidence/comment-fetch";

// A scripted fetcher that returns the next response on each call. The helper
// must drive retries by calling the fetcher up to 3 times, sleeping in between
// (using the injected sleep stub so tests don't actually wait).
function scriptedFetcher(responses: Array<{ status: number; body?: string }>) {
  let i = 0;
  return vi.fn(async () => {
    const r = responses[Math.min(i, responses.length - 1)];
    i++;
    return r;
  });
}

describe("fetchCommentBody", () => {
  it("returns ok with body and SHA-256 on 200", async () => {
    const fetcher = scriptedFetcher([{ status: 200, body: "I have read the CLA Document and I hereby sign the CLA" }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("ok");
    if (r.status !== "ok") throw new Error("unreachable");
    expect(r.body).toBe("I have read the CLA Document and I hereby sign the CLA");
    expect(r.sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("retries 5xx up to 3 attempts with exponential backoff (TS4)", async () => {
    const fetcher = scriptedFetcher([
      { status: 502 },
      { status: 502 },
      { status: 200, body: "OK" },
    ]);
    const sleep = vi.fn<(ms: number) => Promise<void>>(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("ok");
    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(sleep).toHaveBeenCalledTimes(2);
    // Exponential backoff: 1st sleep < 2nd sleep
    const delays = sleep.mock.calls.map((c) => c[0]);
    expect(delays[1]).toBeGreaterThan(delays[0]);
  });

  it("retries 429 the same way as 5xx", async () => {
    const fetcher = scriptedFetcher([{ status: 429 }, { status: 200, body: "OK" }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("ok");
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("hard-fails after 3 consecutive 5xx attempts", async () => {
    const fetcher = scriptedFetcher([{ status: 503 }, { status: 503 }, { status: 503 }, { status: 503 }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("5xx-after-retries");
    if (r.status !== "5xx-after-retries") throw new Error("unreachable");
    expect(r.code).toBe(503);
    expect(fetcher).toHaveBeenCalledTimes(3);
  });

  it("returns degraded { status: '404', body: null } on 404 without retry (TS5)", async () => {
    const fetcher = scriptedFetcher([{ status: 404 }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("404");
    if (r.status !== "404") throw new Error("unreachable");
    expect(r.body).toBeNull();
    expect(r.sha256).toBeNull();
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("fast-fails on 401 with no retry (TS5b)", async () => {
    const fetcher = scriptedFetcher([{ status: 401 }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("fatal-4xx");
    if (r.status !== "fatal-4xx") throw new Error("unreachable");
    expect(r.code).toBe(401);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(sleep).not.toHaveBeenCalled();
  });

  it("fast-fails on 403 with no retry", async () => {
    const fetcher = scriptedFetcher([{ status: 403 }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("fatal-4xx");
    if (r.status !== "fatal-4xx") throw new Error("unreachable");
    expect(r.code).toBe(403);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("fast-fails on 400 with no retry", async () => {
    const fetcher = scriptedFetcher([{ status: 400 }]);
    const sleep = vi.fn(async () => {});
    const r = await fetchCommentBody(12345, { fetcher, sleep });
    expect(r.status).toBe("fatal-4xx");
    if (r.status !== "fatal-4xx") throw new Error("unreachable");
    expect(r.code).toBe(400);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
});
