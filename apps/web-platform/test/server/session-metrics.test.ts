import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Shared mutable references so each test can swap the mock behavior.
const mockSessions = new Map<string, unknown>();
const mockFs = {
  readdirSync: vi.fn<(path: string) => string[]>(),
  statSync: vi.fn<(path: string) => { isDirectory: () => boolean }>(),
};

vi.mock("../../server/ws-handler", () => ({
  sessions: mockSessions,
}));

vi.mock("fs", () => ({
  readdirSync: (...args: [string]) => mockFs.readdirSync(...args),
  statSync: (...args: [string]) => mockFs.statSync(...args),
}));

describe("getActiveSessionCount", () => {
  beforeEach(() => {
    mockSessions.clear();
  });

  afterEach(() => {
    mockSessions.clear();
  });

  it("returns the current sessions.size", async () => {
    mockSessions.set("user-1", {});
    mockSessions.set("user-2", {});
    mockSessions.set("user-3", {});

    const { getActiveSessionCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveSessionCount()).toBe(3);
  });

  it("returns 0 when no sessions are active", async () => {
    const { getActiveSessionCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveSessionCount()).toBe(0);
  });
});

describe("getActiveWorkspaceCount", () => {
  beforeEach(() => {
    mockFs.readdirSync.mockReset();
    mockFs.statSync.mockReset();
    mockFs.statSync.mockReturnValue({ isDirectory: () => true });
  });

  it("counts non-orphaned workspace directories", async () => {
    mockFs.readdirSync.mockReturnValue([
      "abc-uuid",
      "def-uuid",
      ".orphaned-1712345678",
    ]);

    const { getActiveWorkspaceCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveWorkspaceCount()).toBe(2);
  });

  it("excludes entries that are not directories", async () => {
    mockFs.readdirSync.mockReturnValue(["abc-uuid", "README.md"]);
    mockFs.statSync.mockImplementation((p: string) => ({
      isDirectory: () => !p.endsWith("README.md"),
    }));

    const { getActiveWorkspaceCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveWorkspaceCount()).toBe(1);
  });

  it("returns 0 when readdir throws (ENOENT, permission denied, etc.)", async () => {
    mockFs.readdirSync.mockImplementation(() => {
      throw new Error("ENOENT: /workspaces does not exist");
    });

    const { getActiveWorkspaceCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveWorkspaceCount()).toBe(0);
  });

  it("returns 0 when /workspaces is empty", async () => {
    mockFs.readdirSync.mockReturnValue([]);

    const { getActiveWorkspaceCount } = await import(
      "../../server/session-metrics"
    );
    expect(getActiveWorkspaceCount()).toBe(0);
  });
});
