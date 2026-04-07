import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "fs";
import path from "path";

// Mock fs.promises
vi.mock("fs", () => {
  const actual = vi.importActual<typeof import("fs")>("fs");
  return {
    ...actual,
    default: {
      ...actual,
      promises: {
        access: vi.fn(),
        mkdir: vi.fn(),
        writeFile: vi.fn(),
        stat: vi.fn(),
      },
    },
    promises: {
      access: vi.fn(),
      mkdir: vi.fn(),
      writeFile: vi.fn(),
      stat: vi.fn(),
    },
  };
});

const mockAccess = vi.mocked(fs.promises.access);
const mockMkdir = vi.mocked(fs.promises.mkdir);
const mockWriteFile = vi.mocked(fs.promises.writeFile);
const mockStat = vi.mocked(fs.promises.stat);

// Import the functions under test (exported from agent-runner.ts)
// We import lazily after mocks are set up
let tryCreateVision: (workspacePath: string, content: string) => Promise<void>;
let buildVisionEnhancementPrompt: (workspacePath: string) => Promise<string | null>;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();

  // Dynamic import after mocks are configured
  const mod = await import("@/server/vision-helpers");
  tryCreateVision = mod.tryCreateVision;
  buildVisionEnhancementPrompt = mod.buildVisionEnhancementPrompt;
});

describe("tryCreateVision", () => {
  const WORKSPACE = "/workspaces/user-123";

  it("creates vision.md with founder message when file does not exist", async () => {
    mockAccess.mockRejectedValueOnce(new Error("ENOENT"));
    mockMkdir.mockResolvedValueOnce(undefined);
    mockWriteFile.mockResolvedValueOnce(undefined);

    await tryCreateVision(WORKSPACE, "A platform that connects local farmers to restaurants");

    expect(mockMkdir).toHaveBeenCalledWith(
      path.join(WORKSPACE, "knowledge-base", "overview"),
      { recursive: true },
    );
    expect(mockWriteFile).toHaveBeenCalledWith(
      path.join(WORKSPACE, "knowledge-base", "overview", "vision.md"),
      "# Vision\n\nA platform that connects local farmers to restaurants\n",
      "utf-8",
    );
  });

  it("does not overwrite existing vision.md", async () => {
    mockAccess.mockResolvedValueOnce(undefined); // File exists

    await tryCreateVision(WORKSPACE, "Some new idea");

    expect(mockMkdir).not.toHaveBeenCalled();
    expect(mockWriteFile).not.toHaveBeenCalled();
  });

  it("handles mkdir/writeFile failures gracefully", async () => {
    mockAccess.mockRejectedValueOnce(new Error("ENOENT"));
    mockMkdir.mockRejectedValueOnce(new Error("EPERM"));

    // Should not throw — caller uses .catch()
    await expect(
      tryCreateVision(WORKSPACE, "test"),
    ).rejects.toThrow("EPERM");
  });
});

describe("buildVisionEnhancementPrompt", () => {
  const WORKSPACE = "/workspaces/user-123";

  it("returns enhancement prompt when vision.md is minimal (< 500 bytes)", async () => {
    mockStat.mockResolvedValueOnce({ size: 100 } as fs.Stats);

    const result = await buildVisionEnhancementPrompt(WORKSPACE);

    expect(result).toContain("vision document");
    expect(result).toContain("Mission");
    expect(result).toContain("Target Audience");
    expect(result).toContain("Value Proposition");
    expect(result).toContain("Key Differentiators");
  });

  it("returns null when vision.md is substantial (>= 500 bytes)", async () => {
    mockStat.mockResolvedValueOnce({ size: 1200 } as fs.Stats);

    const result = await buildVisionEnhancementPrompt(WORKSPACE);

    expect(result).toBeNull();
  });

  it("returns null when vision.md does not exist", async () => {
    mockStat.mockRejectedValueOnce(new Error("ENOENT"));

    const result = await buildVisionEnhancementPrompt(WORKSPACE);

    expect(result).toBeNull();
  });
});
