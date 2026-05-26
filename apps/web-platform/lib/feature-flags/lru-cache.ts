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
    if (Date.now() - entry.at >= this.ttlMs) {
      this.map.delete(key);
      return undefined;
    }
    entry.at = Date.now();
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
