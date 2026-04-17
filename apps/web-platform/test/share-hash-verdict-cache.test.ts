import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";

import {
  shareHashVerdictCache,
  __resetShareHashVerdictCacheForTest,
} from "@/server/share-hash-verdict-cache";

const INO = 999;

describe("shareHashVerdictCache", () => {
  beforeEach(() => {
    __resetShareHashVerdictCacheForTest();
  });

  afterEach(() => {
    __resetShareHashVerdictCacheForTest();
    vi.useRealTimers();
  });

  it("returns null on miss", () => {
    expect(shareHashVerdictCache.get("token-a", INO, 1, 10)).toBeNull();
  });

  it("returns true after set with matching tuple", () => {
    shareHashVerdictCache.set("token-a", INO, 123, 50);
    expect(shareHashVerdictCache.get("token-a", INO, 123, 50)).toBe(true);
  });

  it("returns null when ino differs", () => {
    shareHashVerdictCache.set("token-a", INO, 123, 50);
    expect(shareHashVerdictCache.get("token-a", INO + 1, 123, 50)).toBeNull();
  });

  it("returns null when mtimeMs differs", () => {
    shareHashVerdictCache.set("token-a", INO, 123, 50);
    expect(shareHashVerdictCache.get("token-a", INO, 124, 50)).toBeNull();
  });

  it("returns null when size differs", () => {
    shareHashVerdictCache.set("token-a", INO, 123, 50);
    expect(shareHashVerdictCache.get("token-a", INO, 123, 51)).toBeNull();
  });

  it("returns null after TTL expires", () => {
    vi.useFakeTimers();
    const baseTime = new Date("2026-04-17T12:00:00Z").getTime();
    vi.setSystemTime(baseTime);
    shareHashVerdictCache.set("token-a", INO, 1, 10);
    expect(shareHashVerdictCache.get("token-a", INO, 1, 10)).toBe(true);
    vi.setSystemTime(baseTime + 60_001);
    expect(shareHashVerdictCache.get("token-a", INO, 1, 10)).toBeNull();
  });

  it("evicts oldest entry when MAX_ENTRIES exceeded", () => {
    const MAX_ENTRIES = 500;
    for (let i = 0; i < MAX_ENTRIES; i++) {
      shareHashVerdictCache.set(`token-${i}`, INO + i, i, i);
    }
    // All 500 entries should still be present.
    expect(shareHashVerdictCache.get("token-0", INO, 0, 0)).toBe(true);
    // Insert one more → oldest (token-0) evicted (we accessed it above
    // which refreshed LRU position; insert after that means token-1 is
    // now oldest).
    shareHashVerdictCache.set("token-new", INO + 9999, 9999, 9999);
    expect(shareHashVerdictCache.get("token-1", INO + 1, 1, 1)).toBeNull();
    expect(
      shareHashVerdictCache.get("token-new", INO + 9999, 9999, 9999),
    ).toBe(true);
  });

  it("tracks hit/miss stats", () => {
    shareHashVerdictCache.set("token-a", INO, 1, 10);
    shareHashVerdictCache.get("token-a", INO, 1, 10); // hit
    shareHashVerdictCache.get("token-b", INO, 1, 10); // miss
    shareHashVerdictCache.get("token-a", INO, 2, 10); // miss (mtime diff)
    const stats = shareHashVerdictCache.stats();
    expect(stats.hits).toBe(1);
    expect(stats.misses).toBe(2);
  });

  it("re-setting the same token updates tuple + TTL", () => {
    vi.useFakeTimers();
    const baseTime = new Date("2026-04-17T12:00:00Z").getTime();
    vi.setSystemTime(baseTime);
    shareHashVerdictCache.set("token-a", INO, 1, 10);
    vi.setSystemTime(baseTime + 59_000);
    shareHashVerdictCache.set("token-a", INO + 7, 2, 20);
    vi.setSystemTime(baseTime + 60_500);
    // Original tuple would be expired by now; new tuple should hit.
    expect(shareHashVerdictCache.get("token-a", INO, 1, 10)).toBeNull();
    expect(shareHashVerdictCache.get("token-a", INO + 7, 2, 20)).toBe(true);
  });

  it("same-size same-mtime but different ino is a miss (guards rename-swap)", () => {
    // The scenario security-sentinel F2 flagged: on filesystems with
    // coarse mtime, an attacker could swap a same-size file within the
    // same mtime-second. ino is the defense in depth.
    shareHashVerdictCache.set("token-a", 1000, 123_456, 2048);
    expect(
      shareHashVerdictCache.get("token-a", 2000, 123_456, 2048),
    ).toBeNull();
  });
});
