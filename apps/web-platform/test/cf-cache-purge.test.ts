import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { purgeSharedToken } from "@/server/cf-cache-purge";
import * as observability from "@/server/observability";

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env.CF_API_TOKEN_PURGE = "test-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.CF_ZONE_ID = "test-zone-1234567890abcdef";
  vi.spyOn(observability, "reportSilentFallback").mockImplementation(() => {});
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
  vi.restoreAllMocks();
  vi.useRealTimers();
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

describe("purgeSharedToken", () => {
  it("posts a single files-array to the CF zone purge endpoint and returns ok on success", async () => {
    const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
      expect(init?.method).toBe("POST");
      expect(url).toBe(
        "https://api.cloudflare.com/client/v4/zones/test-zone-1234567890abcdef/purge_cache",
      );
      const headers = init?.headers as Record<string, string>;
      expect(headers.Authorization).toBe(
        "Bearer test-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      );
      expect(headers["Content-Type"]).toBe("application/json");
      expect(JSON.parse(init?.body as string)).toEqual({
        files: ["https://app.soleur.ai/api/shared/abc123def456"],
      });
      return jsonResponse({ success: true, errors: [] });
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await purgeSharedToken("abc123def456");

    expect(result).toEqual({ ok: true });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(observability.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns cf-api error on a non-JSON body (HTML 5xx from CF edge)", async () => {
    const fetchMock = vi.fn(
      async () =>
        new Response("<html><body>503 Service Unavailable</body></html>", {
          status: 503,
          headers: { "content-type": "text/html" },
        }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await purgeSharedToken("abc123def4567890");

    expect(result).toEqual({ ok: false, error: "cf-api" });
    const callArgs = (
      observability.reportSilentFallback as ReturnType<typeof vi.fn>
    ).mock.calls[0];
    const reportedErr = callArgs[0] as Error;
    expect(reportedErr.message).toContain("status=503");
    expect(reportedErr.message).toContain("success=undefined");
    const opts = callArgs[1] as Record<string, unknown>;
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.status).toBe(503);
  });

  it("returns cf-api error and reports to Sentry on a 403 auth failure", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse(
        {
          success: false,
          errors: [{ code: 10000, message: "Authentication error" }],
        },
        403,
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await purgeSharedToken("abc123def4567890");

    expect(result).toEqual({ ok: false, error: "cf-api" });
    expect(observability.reportSilentFallback).toHaveBeenCalledTimes(1);
    const callArgs = (observability.reportSilentFallback as ReturnType<typeof vi.fn>)
      .mock.calls[0];
    const opts = callArgs[1] as Record<string, unknown>;
    expect(opts.feature).toBe("kb-share");
    expect(opts.op).toBe("revoke-purge");
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.status).toBe(403);
    expect(extra.tokenPrefix).toBe("abc123de");
  });

  it("returns missing-config when CF_API_TOKEN_PURGE is unset", async () => {
    delete process.env.CF_API_TOKEN_PURGE;
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const result = await purgeSharedToken("abc123def456");

    expect(result).toEqual({ ok: false, error: "missing-config" });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(observability.reportSilentFallback).toHaveBeenCalledTimes(1);
    const opts = (observability.reportSilentFallback as ReturnType<typeof vi.fn>)
      .mock.calls[0][1] as Record<string, unknown>;
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.hasToken).toBe(false);
    expect(extra.hasZone).toBe(true);
  });

  it("returns missing-config when CF_ZONE_ID is unset", async () => {
    delete process.env.CF_ZONE_ID;
    vi.stubGlobal("fetch", vi.fn());

    const result = await purgeSharedToken("abc123def456");

    expect(result).toEqual({ ok: false, error: "missing-config" });
    const opts = (observability.reportSilentFallback as ReturnType<typeof vi.fn>)
      .mock.calls[0][1] as Record<string, unknown>;
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.hasZone).toBe(false);
  });

  it("returns timeout when fetch is aborted by the 5s AbortController", async () => {
    // Install fake timers BEFORE invoking the SUT so the helper's internal
    // setTimeout(controller.abort, 5000) is intercepted by vi.
    vi.useFakeTimers();
    const fetchMock = vi.fn((_url: string, init?: RequestInit) => {
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const promise = purgeSharedToken("abc123def4567890");
    await vi.advanceTimersByTimeAsync(5001);
    const result = await promise;

    expect(result).toEqual({ ok: false, error: "timeout" });
    const opts = (observability.reportSilentFallback as ReturnType<typeof vi.fn>)
      .mock.calls[0][1] as Record<string, unknown>;
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.reason).toBe("timeout");
  });

  it("returns network error when fetch throws", async () => {
    const fetchMock = vi.fn(async () => {
      throw new TypeError("fetch failed");
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await purgeSharedToken("abc123def4567890");

    expect(result).toEqual({ ok: false, error: "network" });
    const opts = (observability.reportSilentFallback as ReturnType<typeof vi.fn>)
      .mock.calls[0][1] as Record<string, unknown>;
    const extra = opts.extra as Record<string, unknown>;
    expect(extra.reason).toBe("network");
  });
});
