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
        mkdir: vi.fn(),
        writeFile: vi.fn(),
        stat: vi.fn(),
      },
    },
    promises: {
      mkdir: vi.fn(),
      writeFile: vi.fn(),
      stat: vi.fn(),
    },
  };
});

const mockMkdir = vi.mocked(fs.promises.mkdir);
const mockWriteFile = vi.mocked(fs.promises.writeFile);
const mockStat = vi.mocked(fs.promises.stat);

let tryCreateVision: (workspacePath: string, content: string) => Promise<void>;
let buildVisionEnhancementPrompt: (workspacePath: string) => Promise<string | null>;

beforeEach(async () => {
  vi.clearAllMocks();
  vi.resetModules();

  const mod = await import("@/server/vision-helpers");
  tryCreateVision = mod.tryCreateVision;
  buildVisionEnhancementPrompt = mod.buildVisionEnhancementPrompt;
});

describe("tryCreateVision", () => {
  const WORKSPACE = "/workspaces/user-123";

  it("creates vision.md with founder message when file does not exist", async () => {
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
      { encoding: "utf-8", flag: "wx" },
    );
  });

  it("does not overwrite existing vision.md (EEXIST from wx flag)", async () => {
    mockMkdir.mockResolvedValueOnce(undefined);
    const eexist = new Error("EEXIST") as NodeJS.ErrnoException;
    eexist.code = "EEXIST";
    mockWriteFile.mockRejectedValueOnce(eexist);

    // Should silently return — no throw
    await tryCreateVision(WORKSPACE, "Some new idea");

    expect(mockWriteFile).toHaveBeenCalled();
    // No error thrown — EEXIST is handled
  });

  it("truncates content exceeding 5000 characters", async () => {
    mockMkdir.mockResolvedValueOnce(undefined);
    mockWriteFile.mockResolvedValueOnce(undefined);

    const longContent = "x".repeat(10000);
    await tryCreateVision(WORKSPACE, longContent);

    const written = mockWriteFile.mock.calls[0][1] as string;
    // "# Vision\n\n" (10 chars) + 5000 chars + "\n" (1 char) = 5011
    expect(written.length).toBe(5011);
  });

  it("re-throws non-EEXIST errors from writeFile", async () => {
    mockMkdir.mockResolvedValueOnce(undefined);
    mockWriteFile.mockRejectedValueOnce(new Error("EPERM"));

    await expect(tryCreateVision(WORKSPACE, "A valid startup idea")).rejects.toThrow("EPERM");
  });

  it("rejects slash commands like /soleur:sync --headless", async () => {
    await tryCreateVision(WORKSPACE, "/soleur:sync --headless");
    expect(mockWriteFile).not.toHaveBeenCalled();
  });

  it("rejects content shorter than 10 characters", async () => {
    await tryCreateVision(WORKSPACE, "@cpo");
    expect(mockWriteFile).not.toHaveBeenCalled();
  });

  it("rejects malformed sync output (### Vision /soleur:sync)", async () => {
    await tryCreateVision(WORKSPACE, "### Vision /soleur:sync --headless");
    expect(mockWriteFile).not.toHaveBeenCalled();
  });

  it("accepts mention with content (user message with leader prefix)", async () => {
    mockMkdir.mockResolvedValueOnce(undefined);
    mockWriteFile.mockResolvedValueOnce(undefined);

    await tryCreateVision(WORKSPACE, "@cpo I'm building a marketplace for designers");
    expect(mockWriteFile).toHaveBeenCalled();
  });

  it("rejects bare leader mention without content", async () => {
    await tryCreateVision(WORKSPACE, "@cto");
    expect(mockWriteFile).not.toHaveBeenCalled();
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

  it("uses relative path (agent runs with cwd: workspacePath)", async () => {
    mockStat.mockResolvedValueOnce({ size: 100 } as fs.Stats);

    const result = await buildVisionEnhancementPrompt(WORKSPACE);

    // Must use relative path — the agent runs with cwd: workspacePath,
    // so relative paths resolve correctly and avoid leaking absolute paths.
    expect(result).toContain("knowledge-base/overview/vision.md");
    expect(result).not.toContain(WORKSPACE);
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
