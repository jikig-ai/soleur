// PR-H+1 (#4098) — per-Octokit-call audit writer.
//
// recordGithubApiCall is the bridge between Octokit's afterResponse hook
// and the record_github_token_use SECURITY DEFINER RPC. Per AC8: failure
// is non-blocking and Sentry-mirrored (cq-silent-fallback-must-mirror-to-sentry).

import { describe, it, expect, vi, beforeEach } from "vitest";

const { rpcMock, captureExceptionMock } = vi.hoisted(() => ({
  rpcMock: vi.fn(),
  captureExceptionMock: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: rpcMock }),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: captureExceptionMock,
}));

import {
  recordGithubApiCall,
  extractEndpoint,
  extractRepoFullName,
} from "@/server/github/audit-writer";

beforeEach(() => {
  rpcMock.mockReset();
  captureExceptionMock.mockReset();
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

  it("is non-blocking when the RPC returns an error (AC8 / cq-silent-fallback-must-mirror-to-sentry)", async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: "supabase: connection refused" },
    });

    await expect(recordGithubApiCall(ARGS)).resolves.toBeUndefined();

    expect(captureExceptionMock).toHaveBeenCalledTimes(1);
    const [thrown, options] = captureExceptionMock.mock.calls[0];
    expect((thrown as { message: string }).message).toMatch(/connection refused/);
    expect(options).toEqual({
      tags: {
        surface: "github-audit-writer",
        endpoint: ARGS.endpoint,
      },
    });
  });

  it("is non-blocking when the RPC throws", async () => {
    rpcMock.mockImplementationOnce(() => {
      throw new Error("network down");
    });

    await expect(recordGithubApiCall(ARGS)).resolves.toBeUndefined();
    expect(captureExceptionMock).toHaveBeenCalledTimes(1);
    expect(
      (captureExceptionMock.mock.calls[0][0] as { message: string }).message,
    ).toMatch(/network down/);
  });

  it("does NOT page Sentry on the success path", async () => {
    await recordGithubApiCall(ARGS);
    expect(captureExceptionMock).not.toHaveBeenCalled();
  });
});
