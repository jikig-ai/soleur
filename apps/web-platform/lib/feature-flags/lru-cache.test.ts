import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { LRUCache } from "./lru-cache";

describe("LRUCache", () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: 1000 });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns cached value within TTL", () => {
    const cache = new LRUCache<string, number>(10, 5000);
    cache.set("a", 42);
    expect(cache.get("a")).toBe(42);
  });

  it("returns undefined after TTL expiry", () => {
    const cache = new LRUCache<string, number>(10, 5000);
    cache.set("a", 42);
    vi.advanceTimersByTime(5001);
    expect(cache.get("a")).toBeUndefined();
  });

  it("evicts LRU entry when at capacity", () => {
    const cache = new LRUCache<string, number>(3, 60000);
    cache.set("a", 1);
    cache.set("b", 2);
    cache.set("c", 3);
    cache.set("d", 4);
    expect(cache.get("a")).toBeUndefined();
    expect(cache.get("b")).toBe(2);
    expect(cache.get("c")).toBe(3);
    expect(cache.get("d")).toBe(4);
  });

  it("access refreshes recency (prevents eviction of recently-used)", () => {
    const cache = new LRUCache<string, number>(3, 60000);
    cache.set("a", 1);
    cache.set("b", 2);
    cache.set("c", 3);
    cache.get("a");
    cache.set("d", 4);
    expect(cache.get("a")).toBe(1);
    expect(cache.get("b")).toBeUndefined();
  });

  it("respects maxSize from constructor", () => {
    const cache = new LRUCache<string, number>(2, 60000);
    cache.set("x", 10);
    cache.set("y", 20);
    cache.set("z", 30);
    expect(cache.get("x")).toBeUndefined();
    expect(cache.get("y")).toBe(20);
    expect(cache.get("z")).toBe(30);
  });

  it("clear() removes all entries", () => {
    const cache = new LRUCache<string, number>(10, 60000);
    cache.set("a", 1);
    cache.set("b", 2);
    cache.clear();
    expect(cache.get("a")).toBeUndefined();
    expect(cache.get("b")).toBeUndefined();
  });
});
