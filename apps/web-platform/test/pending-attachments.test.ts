import { describe, it, expect, beforeEach, vi } from "vitest";
import { setPendingFiles, getPendingFiles, clearPendingFiles } from "@/lib/pending-attachments";

describe("pending-attachments", () => {
  beforeEach(() => {
    clearPendingFiles();
  });

  it("returns empty array when no files are set", () => {
    expect(getPendingFiles()).toEqual([]);
  });

  it("stores and retrieves files", () => {
    const file = new File(["test"], "test.png", { type: "image/png" });
    setPendingFiles([file]);
    const result = getPendingFiles();
    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("test.png");
  });

  it("replaces files on subsequent set (idempotent for double-submit)", () => {
    const file1 = new File(["a"], "a.png", { type: "image/png" });
    const file2 = new File(["b"], "b.png", { type: "image/png" });
    setPendingFiles([file1]);
    setPendingFiles([file2]);
    const result = getPendingFiles();
    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("b.png");
  });

  it("clears files", () => {
    setPendingFiles([new File(["x"], "x.png", { type: "image/png" })]);
    clearPendingFiles();
    expect(getPendingFiles()).toEqual([]);
  });

  it("discards files older than 5 minutes (staleness guard)", () => {
    const file = new File(["old"], "old.png", { type: "image/png" });
    setPendingFiles([file]);

    // Advance time past staleness window
    vi.useFakeTimers();
    vi.advanceTimersByTime(5 * 60 * 1000 + 1);

    expect(getPendingFiles()).toEqual([]);
    vi.useRealTimers();
  });

  it("returns files within staleness window", () => {
    const file = new File(["fresh"], "fresh.png", { type: "image/png" });
    setPendingFiles([file]);

    vi.useFakeTimers();
    vi.advanceTimersByTime(4 * 60 * 1000); // 4 minutes — within window

    const result = getPendingFiles();
    expect(result).toHaveLength(1);
    expect(result[0].name).toBe("fresh.png");
    vi.useRealTimers();
  });
});
