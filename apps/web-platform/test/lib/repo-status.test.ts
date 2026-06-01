import { describe, it, expect } from "vitest";
import { repoNeedsReconnect } from "@/lib/repo-status";

describe("repoNeedsReconnect", () => {
  it("is true for ready + null installation id", () => {
    expect(repoNeedsReconnect("ready", null)).toBe(true);
  });

  it("is true for ready + undefined installation id", () => {
    expect(repoNeedsReconnect("ready", undefined)).toBe(true);
  });

  it("is false for ready + numeric installation id", () => {
    expect(repoNeedsReconnect("ready", 12345)).toBe(false);
  });

  it("is false for ready + bigint installation id", () => {
    expect(repoNeedsReconnect("ready", 12345n)).toBe(false);
  });

  it("is false for non-ready statuses regardless of installation id", () => {
    expect(repoNeedsReconnect("not_connected", null)).toBe(false);
    expect(repoNeedsReconnect("not_connected", 1)).toBe(false);
    expect(repoNeedsReconnect("error", null)).toBe(false);
    expect(repoNeedsReconnect("error", 1)).toBe(false);
    expect(repoNeedsReconnect("cloning", null)).toBe(false);
    expect(repoNeedsReconnect("cloning", 1)).toBe(false);
  });

  it("is false for null repoStatus", () => {
    expect(repoNeedsReconnect(null, null)).toBe(false);
  });
});
