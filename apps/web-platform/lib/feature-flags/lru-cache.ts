export class LRUCache<K, V> {
  private map = new Map<K, { value: V; at: number }>();
  private readonly maxSize: number;
  private readonly ttlMs: number;

  constructor(maxSize: number, ttlMs: number) {
    this.maxSize = maxSize;
    this.ttlMs = ttlMs;
  }

  get(key: K): V | undefined {
    const entry = this.map.get(key);
    if (!entry) return undefined;
    // Expiry is anchored at WRITE time and is never extended by reads — an
    // entry hit continuously still dies at write+ttlMs (absolute bounded
    // staleness, not a sliding window; without this, a security-verdict
    // consumer's "≤ TTL" bound stretches to token lifetime under traffic).
    // The delete/set below only reorders the Map for LRU recency.
    if (Date.now() - entry.at >= this.ttlMs) {
      this.map.delete(key);
      return undefined;
    }
    this.map.delete(key);
    this.map.set(key, entry);
    return entry.value;
  }

  set(key: K, value: V): void {
    this.map.delete(key);
    if (this.map.size >= this.maxSize) {
      const oldest = this.map.keys().next().value!;
      this.map.delete(oldest);
    }
    this.map.set(key, { value, at: Date.now() });
  }

  clear(): void {
    this.map.clear();
  }
}
