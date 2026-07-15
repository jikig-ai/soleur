import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  createIssueRequest,
  patchIssueRequest,
  isRateLimited,
  isReadOnly,
} from "@/components/workstream/workstream-writes";

// The client write helpers POST/PATCH the write endpoints and throw a typed
// error carrying the HTTP status + code so the UI can branch (403 read-only,
// 429 slow-down) rather than treating every failure as a generic retry.

const fetchMock = vi.fn();

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

function res(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as unknown as Response;
}

describe("createIssueRequest", () => {
  it("returns the canonical issue on 200", async () => {
    fetchMock.mockResolvedValue(res(200, { issue: { id: "9", title: "x" } }));
    const issue = await createIssueRequest({ title: "x" });
    expect(issue.id).toBe("9");
    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/workstream/issues");
    expect(opts.method).toBe("POST");
  });

  it("throws a typed error with status+code on failure", async () => {
    fetchMock.mockResolvedValue(res(403, { error: "forbidden_readonly" }));
    await expect(createIssueRequest({ title: "x" })).rejects.toMatchObject({
      status: 403,
      code: "forbidden_readonly",
    });
  });
});

describe("patchIssueRequest", () => {
  it("PATCHes the numbered endpoint and returns the issue", async () => {
    fetchMock.mockResolvedValue(res(200, { issue: { id: "42", status: "blocked" } }));
    const issue = await patchIssueRequest(42, { status: "blocked" });
    expect(issue.status).toBe("blocked");
    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/workstream/issues/42");
    expect(opts.method).toBe("PATCH");
  });

  it("surfaces a 429 as a rate-limit error", async () => {
    fetchMock.mockResolvedValue(res(429, { error: "rate_limited" }));
    const err = await patchIssueRequest(1, { status: "ready" }).catch((e) => e);
    expect(isRateLimited(err)).toBe(true);
    expect(isReadOnly(err)).toBe(false);
  });

  it("classifies a 403 as read-only", async () => {
    fetchMock.mockResolvedValue(res(403, { error: "forbidden_readonly" }));
    const err = await patchIssueRequest(1, { status: "ready" }).catch((e) => e);
    expect(isReadOnly(err)).toBe(true);
  });
});
