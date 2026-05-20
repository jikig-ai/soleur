// PR-H+1 (#4098) — per-Octokit-call audit writer.
//
// recordGithubApiCall is the bridge between Octokit's afterResponse hook
// and the record_github_token_use SECURITY DEFINER RPC. Per AC8: failure
// is non-blocking and mirrors via reportSilentFallback to Sentry
// (cq-silent-fallback-must-mirror-to-sentry). reportSilentFallback's own
// internal try/catch wrapping guarantees a Sentry SDK throw cannot
// escape into the Octokit hook chain.

import { describe, it, expect, vi, beforeEach } from "vitest";

const { rpcMock, reportSilentFallbackMock } = vi.hoisted(() => ({
  rpcMock: vi.fn(),
  reportSilentFallbackMock: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: () => ({ rpc: rpcMock }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

import {
  recordGithubApiCall,
  extractEndpoint,
  extractRepoFullName,
} from "@/server/github/audit-writer";

beforeEach(() => {
  rpcMock.mockReset();
  reportSilentFallbackMock.mockReset();
  rpcMock.mockResolvedValue({ data: "fake-id", error: null });
});

describe("extractRepoFullName", () => {
  it("parses owner/repo from a /repos/<owner>/<repo>/... path", () => {
    expect(extractRepoFullName("/repos/jikig-ai/soleur/pulls/4098")).toBe(
      "jikig-ai/soleur",
    );
  });

  it("parses owner/repo from an absolute api.github.com URL", () => {
    expect(
      extractRepoFullName("https://api.github.com/repos/jikig-ai/soleur"),
    ).toBe("jikig-ai/soleur");
  });

  it("strips query strings from bare paths (cardinality + PII guard)", () => {
    expect(extractRepoFullName("/repos/jikig-ai/soleur?per_page=100")).toBe(
      "jikig-ai/soleur",
    );
  });

  it("returns null for non-repo endpoints", () => {
    expect(extractRepoFullName("/app")).toBeNull();
    expect(extractRepoFullName("/installation/repositories")).toBeNull();
    expect(extractRepoFullName("/user")).toBeNull();
  });

  it("returns null for malformed input", () => {
    expect(extractRepoFullName("")).toBeNull();
    expect(extractRepoFullName("///")).toBeNull();
  });
});

describe("extractEndpoint", () => {
  it("strips the host and returns the pathname", () => {
    expect(
      extractEndpoint("https://api.github.com/repos/jikig-ai/soleur/pulls"),
    ).toBe("/repos/jikig-ai/soleur/pulls");
  });

  it("returns the path unchanged when no host is present", () => {
    expect(extractEndpoint("/repos/jikig-ai/soleur")).toBe(
      "/repos/jikig-ai/soleur",
    );
  });

  it("drops query strings (parameters are not load-bearing for audit shape)", () => {
    expect(
      extractEndpoint("/repos/jikig-ai/soleur/issues?per_page=100&page=1"),
    ).toBe("/repos/jikig-ai/soleur/issues");
  });

  it("returns the <unknown> sentinel on empty input (length-≥-1 CHECK guard)", () => {
    expect(extractEndpoint("")).toBe("<unknown>");
  });

  it("caps the pathname at 256 chars (length-≤-256 CHECK guard)", () => {
    const longSegment = "a".repeat(300);
    const result = extractEndpoint(`/repos/${longSegment}`);
    expect(result.length).toBe(256);
    expect(result.startsWith("/repos/aaaa")).toBe(true);
  });
});

describe("recordGithubApiCall", () => {
  const ARGS = {
    founderId: "11111111-1111-1111-1111-111111111111",
    installationId: 42,
    repoFullName: "jikig-ai/soleur",
    endpoint: "/repos/jikig-ai/soleur/pulls/4098",
    responseStatus: 200,
  } as const;

  it("calls record_github_token_use RPC with the canonical p_* parameter shape", async () => {
    await recordGithubApiCall(ARGS);

    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock).toHaveBeenCalledWith("record_github_token_use", {
      p_founder_id: ARGS.founderId,
      p_installation_id: ARGS.installationId,
      p_repo_full_name: ARGS.repoFullName,
      p_endpoint: ARGS.endpoint,
      p_response_status: ARGS.responseStatus,
    });
  });

  it("forwards a null repo_full_name when the call site has no repo context", async () => {
    await recordGithubApiCall({ ...ARGS, repoFullName: null });

    expect(rpcMock).toHaveBeenCalledWith(
      "record_github_token_use",
      expect.objectContaining({ p_repo_full_name: null }),
    );
  });

  it("forwards a null response_status for network-error hook paths", async () => {
    await recordGithubApiCall({ ...ARGS, responseStatus: null });

    expect(rpcMock).toHaveBeenCalledWith(
      "record_github_token_use",
      expect.objectContaining({ p_response_status: null }),
    );
  });

  it("is non-blocking when the RPC returns an error and mirrors via reportSilentFallback (AC8 + cq-silent-fallback-must-mirror-to-sentry)", async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: "supabase: connection refused" },
    });

    await expect(recordGithubApiCall(ARGS)).resolves.toBeUndefined();

    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
    const [thrown, options] = reportSilentFallbackMock.mock.calls[0];
    expect((thrown as { message: string }).message).toMatch(
      /connection refused/,
    );
    expect(options).toMatchObject({
      feature: "github-audit",
      op: "record",
      extra: {
        installationId: ARGS.installationId,
        repoFullName: ARGS.repoFullName,
        endpoint: ARGS.endpoint,
        responseStatus: ARGS.responseStatus,
      },
    });
    // Sentry tag-cardinality guard — endpoint templated for the indexed tag.
    expect(options.extra.endpointTemplate).toBe(
      "/repos/:owner/:repo/pulls/:n",
    );
  });

  it("is non-blocking when the RPC throws", async () => {
    rpcMock.mockImplementationOnce(() => {
      throw new Error("network down");
    });

    await expect(recordGithubApiCall(ARGS)).resolves.toBeUndefined();
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
    expect(
      (reportSilentFallbackMock.mock.calls[0][0] as { message: string })
        .message,
    ).toMatch(/network down/);
  });

  it("does NOT page Sentry on the success path", async () => {
    await recordGithubApiCall(ARGS);
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });
});
