/**
 * CI/CD MCP Tool Tests (Phase 2, #1927)
 *
 * Tests the github_read_ci_status and github_read_workflow_logs tool handlers.
 * These are unit tests for the tool handler functions themselves — the MCP
 * server registration and canUseTool gating are tested in agent-runner-tools
 * and canusertool-tiered-gating test files.
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
  readCiStatus,
  readWorkflowLogs,
} from "../server/ci-tools";

describe("readCiStatus", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  let nextInstallationId = 7000;
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

  test("returns workflow runs with status, SHA, branch, URL, and name", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        total_count: 2,
        workflow_runs: [
          {
            id: 100,
            name: "CI",
            head_branch: "main",
            head_sha: "abc123",
            status: "completed",
            conclusion: "success",
            html_url: "https://github.com/alice/my-repo/actions/runs/100",
            workflow_id: 10,
            created_at: "2026-04-10T10:00:00Z",
          },
          {
            id: 101,
            name: "Deploy",
            head_branch: "feat-x",
            head_sha: "def456",
            status: "in_progress",
            conclusion: null,
            html_url: "https://github.com/alice/my-repo/actions/runs/101",
            workflow_id: 20,
            created_at: "2026-04-10T11:00:00Z",
          },
        ],
      }),
    });

    const result = await readCiStatus(installationId, "alice", "my-repo");

    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({
      id: 100,
      name: "CI",
      branch: "main",
      sha: "abc123",
      status: "completed",
      conclusion: "success",
      url: "https://github.com/alice/my-repo/actions/runs/100",
      workflowId: 10,
    });
    expect(result[1]).toEqual({
      id: 101,
      name: "Deploy",
      branch: "feat-x",
      sha: "def456",
      status: "in_progress",
      conclusion: null,
      url: "https://github.com/alice/my-repo/actions/runs/101",
      workflowId: 20,
    });
  });

  test("returns empty array when no workflows exist", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ total_count: 0, workflow_runs: [] }),
    });

    const result = await readCiStatus(installationId, "alice", "my-repo");
    expect(result).toEqual([]);
  });

  test("filters by branch when specified", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ total_count: 0, workflow_runs: [] }),
    });

    await readCiStatus(installationId, "alice", "my-repo", { branch: "feat-x" });

    const getCall = mockFetch.mock.calls[1];
    expect(getCall[0]).toContain("branch=feat-x");
  });
});

describe("readWorkflowLogs", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  let nextInstallationId = 6000;
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

  function mockRunResponse(headSha: string = "abc123") {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ head_sha: headSha, conclusion: "failure" }),
    });
  }

  test("returns annotations when available", async () => {
    const installationId = uniqueInstallationId();
    // Token for run fetch (to get head_sha)
    mockTokenResponse();
    mockRunResponse();
    // Check runs request (token cached)
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        total_count: 1,
        check_runs: [
          {
            id: 500,
            name: "build",
            conclusion: "failure",
            output: {
              annotations_count: 2,
            },
          },
        ],
      }),
    });
    // Annotations request
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => [
        {
          path: "src/app.ts",
          start_line: 10,
          end_line: 10,
          annotation_level: "failure",
          message: "Type error: Property 'x' does not exist",
        },
        {
          path: "src/utils.ts",
          start_line: 25,
          end_line: 25,
          annotation_level: "warning",
          message: "Unused variable 'tmp'",
        },
      ],
    });

    const result = await readWorkflowLogs(
      installationId, "alice", "my-repo", 100,
    );

    expect(result.conclusion).toBe("failure");
    expect(result.annotations).toHaveLength(2);
    expect(result.annotations[0]).toEqual({
      path: "src/app.ts",
      line: 10,
      level: "failure",
      message: "Type error: Property 'x' does not exist",
    });
  });

  test("falls back to last 100 lines of failed step when no annotations", async () => {
    const installationId = uniqueInstallationId();
    // Token for run fetch + check runs request
    mockTokenResponse();
    mockRunResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        total_count: 1,
        check_runs: [
          {
            id: 500,
            name: "test",
            conclusion: "failure",
            output: { annotations_count: 0 },
          },
        ],
      }),
    });
    // Jobs request for fallback log lines
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        total_count: 1,
        jobs: [
          {
            id: 600,
            name: "test",
            conclusion: "failure",
            steps: [
              { name: "Run tests", conclusion: "failure", number: 3 },
              { name: "Checkout", conclusion: "success", number: 1 },
            ],
          },
        ],
      }),
    });
    // Job logs request
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      text: async () => "line1\nline2\nline3\nError: test failed\n",
    });

    const result = await readWorkflowLogs(
      installationId, "alice", "my-repo", 100,
    );

    expect(result.conclusion).toBe("failure");
    expect(result.annotations).toHaveLength(0);
    expect(result.fallbackLog).toBeDefined();
    expect(result.fallbackLog!.jobName).toBe("test");
    expect(result.fallbackLog!.stepName).toBe("Run tests");
    expect(result.fallbackLog!.lines).toContain("Error: test failed");
  });

  test("returns empty result when run has no check runs", async () => {
    const installationId = uniqueInstallationId();
    mockTokenResponse();
    mockRunResponse();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ total_count: 0, check_runs: [] }),
    });

    const result = await readWorkflowLogs(
      installationId, "alice", "my-repo", 100,
    );

    expect(result.conclusion).toBeNull();
    expect(result.annotations).toEqual([]);
  });
});
