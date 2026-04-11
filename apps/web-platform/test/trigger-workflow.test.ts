/**
 * Workflow Trigger Tool Tests (Phase 3, #1928)
 *
 * Tests the github_trigger_workflow handler function:
 * - Dispatches workflow_dispatch event via GitHub API
 * - Rate limiting (max 10 per session)
 * - Returns new run ID after dispatch
 */
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

import {
  triggerWorkflow,
  createRateLimiter,
} from "../server/trigger-workflow";

describe("triggerWorkflow", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  let nextInstallationId = 5000;
  function uniqueInstallationId() {
    return nextInstallationId++;
  }

  function mockTokenResponse() {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_test_token",
        expires_at: new Date(Date.now() + 3_600_000).toISOString(),
      }),
    });
  }

  function mockDispatchAndRunsResponse(runId: number = 200) {
    // Dispatch returns 204 No Content
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 204,
      text: async () => "",
      json: async () => null,
    });
    // Token for listing runs (may reuse cached)
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        total_count: 1,
        workflow_runs: [
          {
            id: runId,
            name: "CI",
            head_branch: "main",
            head_sha: "abc123",
            status: "queued",
            conclusion: null,
            html_url: `https://github.com/alice/my-repo/actions/runs/${runId}`,
            workflow_id: 42,
            created_at: new Date().toISOString(),
          },
        ],
      }),
    });
  }

  test("dispatches workflow and returns new run ID", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockDispatchAndRunsResponse(200);

    const limiter = createRateLimiter();
    const result = await triggerWorkflow(
      installationId, "alice", "my-repo", 42, "main", limiter,
    );

    expect(result.runId).toBe(200);
    expect(result.status).toBe("queued");

    // Verify dispatch API call
    const dispatchCall = mockFetch.mock.calls[1];
    expect(dispatchCall[0]).toBe(
      "https://api.github.com/repos/alice/my-repo/actions/workflows/42/dispatches",
    );
    expect(JSON.parse(dispatchCall[1].body)).toEqual({ ref: "main" });
  });

  test("passes optional inputs to workflow_dispatch", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockDispatchAndRunsResponse();

    const limiter = createRateLimiter();
    await triggerWorkflow(
      installationId, "alice", "my-repo", 42, "main", limiter,
      { deploy_env: "staging" },
    );

    const dispatchCall = mockFetch.mock.calls[1];
    expect(JSON.parse(dispatchCall[1].body)).toEqual({
      ref: "main",
      inputs: { deploy_env: "staging" },
    });
  });
});

describe("rate limiter", () => {
  test("allows up to 10 triggers", () => {
    const limiter = createRateLimiter();
    for (let i = 0; i < 10; i++) {
      expect(limiter.check()).toBe(true);
      limiter.increment();
    }
  });

  test("blocks the 11th trigger", () => {
    const limiter = createRateLimiter();
    for (let i = 0; i < 10; i++) {
      limiter.increment();
    }
    expect(limiter.check()).toBe(false);
  });

  test("remaining() returns correct count", () => {
    const limiter = createRateLimiter();
    expect(limiter.remaining()).toBe(10);
    limiter.increment();
    limiter.increment();
    expect(limiter.remaining()).toBe(8);
  });
});
