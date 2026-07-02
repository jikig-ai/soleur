import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BoardIssueInput } from "@/lib/workstream";

// The accessor's IO collaborators are ALL mocked — there are NO live network
// calls. We assert the empty-vs-throw contract and the mapping wiring.

const getCurrentRepoUrl = vi.fn();
const resolveInstallationId = vi.fn();
const resolveEffectiveInstallationId = vi.fn();
const listRepoIssues = vi.fn();
const fetchBoardStatusMap = vi.fn();
const reportSilentFallback = vi.fn();

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: (...a: unknown[]) => getCurrentRepoUrl(...a),
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: (...a: unknown[]) => resolveInstallationId(...a),
}));
vi.mock("@/server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: (...a: unknown[]) =>
    resolveEffectiveInstallationId(...a),
}));
vi.mock("@/server/github-read-tools", () => ({
  listRepoIssues: (...a: unknown[]) => listRepoIssues(...a),
  fetchBoardStatusMap: (...a: unknown[]) => fetchBoardStatusMap(...a),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { getWorkstreamIssues } from "@/server/workstream/get-workstream-issues";

function rawIssue(over: Partial<BoardIssueInput> = {}): BoardIssueInput {
  return {
    number: 5652,
    title: "Tighten the gap",
    body: "the body",
    assignees: ["harry"],
    labels: ["domain/engineering", "priority/p1-high", "in-progress"],
    state: "open",
    state_reason: null,
    created_at: "2026-06-20T09:00:00.000Z",
    updated_at: "2026-06-21T09:00:00.000Z",
    ...over,
  };
}

beforeEach(() => {
  getCurrentRepoUrl.mockResolvedValue("https://github.com/acme/widgets");
  resolveInstallationId.mockResolvedValue(123);
  resolveEffectiveInstallationId.mockResolvedValue(123);
  listRepoIssues.mockResolvedValue([]);
  fetchBoardStatusMap.mockResolvedValue(new Map());
});
afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

describe("getWorkstreamIssues", () => {
  it("returns [] (honest empty) when no repo is connected — no reader call", async () => {
    getCurrentRepoUrl.mockResolvedValue(null);
    const out = await getWorkstreamIssues("u1");
    expect(out).toEqual([]);
    expect(listRepoIssues).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns [] AND mirrors to Sentry when repo present but installation is null", async () => {
    resolveEffectiveInstallationId.mockResolvedValue(null);
    const out = await getWorkstreamIssues("u1");
    expect(out).toEqual([]);
    expect(listRepoIssues).not.toHaveBeenCalled();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "no-installation" }),
    );
  });

  it("maps the reader output via the pure mapper for a connected repo", async () => {
    listRepoIssues.mockResolvedValue([rawIssue()]);
    const out = await getWorkstreamIssues("u1");
    expect(listRepoIssues).toHaveBeenCalledWith(123, "acme", "widgets");
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({
      id: "5652",
      title: "Tighten the gap",
      description: "the body",
      status: "in_progress",
      priority: "high",
      assigneeRole: "cto",
      user: { name: "harry", initials: "HA" },
      live: true,
    });
  });

  it("propagates (throws) a GitHub reader error — never masquerades as empty", async () => {
    listRepoIssues.mockRejectedValue(new Error("GitHub API 403"));
    await expect(getWorkstreamIssues("u1")).rejects.toThrow("GitHub API 403");
  });

  it("prefers the canonical board Status over label derivation (Phase 2)", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]); // labels would derive in_progress
    fetchBoardStatusMap.mockResolvedValue(new Map([[5652, "Pending"]]));
    const out = await getWorkstreamIssues("u1");
    expect(fetchBoardStatusMap).toHaveBeenCalledWith(123, "acme", 2, "acme/widgets");
    expect(out[0].status).toBe("pending"); // board Status wins over the in-progress label
  });

  it("falls back to label derivation + mirrors to Sentry when the board read fails", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]);
    fetchBoardStatusMap.mockRejectedValue(new Error("GitHub API 403"));
    const out = await getWorkstreamIssues("u1");
    expect(out[0].status).toBe("in_progress"); // label fallback, never throws
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "board-status-read" }),
    );
  });

  it("skips the board read when the repo owner is not the configured board org", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "jikig-ai");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]);
    const out = await getWorkstreamIssues("u1");
    expect(fetchBoardStatusMap).not.toHaveBeenCalled();
    expect(out[0].status).toBe("in_progress"); // label derivation
  });
});
