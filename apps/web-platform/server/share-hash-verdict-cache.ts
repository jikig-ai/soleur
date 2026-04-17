// In-process verdict cache for /api/shared/[token] content-hash gate.
//
// Keyed on share token; the stored entry carries (ino, mtimeMs, size) so
// file mutations silently invalidate — a subsequent request with a
// different tuple is treated as a miss. Including `ino` on top of
// `mtimeMs + size` defends against same-second same-size swaps on
// filesystems with coarse mtime resolution (NFS, overlayfs on older
// kernels) that would otherwise let a malicious rename slip past the
// verdict gate.
//
// Per-worker, self-healing: each Next.js worker has its own Map. Cross-
// worker cache-miss just means one extra hash per worker per file per
// 60 s window — acceptable for share traffic volume. Do NOT promote to a
// shared Redis layer without measuring hit rate first; the correctness
// story depends on the per-request validateBinaryFile fstat rebuilding
// the tuple on every view.
//
// Lives in a sibling module — NOT in route.ts — to stay inside the
// Next.js App Router route-file export allowlist (cq-nextjs-route-files-
// http-only-exports). PR #2401 shipped a hotfix for exactly this class of
// bug after the analytics-track route file leaked a non-HTTP singleton.

const TTL_MS = 60_000;
const MAX_ENTRIES = 500;

interface Entry {
  ino: number;
  mtimeMs: number;
  size: number;
  expiresAt: number;
}

const cache = new Map<string, Entry>();

interface Stats {
  hits: number;
  misses: number;
  evictions: number;
  expirations: number;
}
const stats: Stats = { hits: 0, misses: 0, evictions: 0, expirations: 0 };

export const shareHashVerdictCache = {
  /**
   * Returns true if (token, ino, mtimeMs, size) has a fresh "verified"
   * entry. Returns null on miss (absent, expired, or tuple mismatch —
   * each counts as a cache miss for the purposes of forcing a re-hash).
   */
  get(token: string, ino: number, mtimeMs: number, size: number): true | null {
    const entry = cache.get(token);
    if (!entry) {
      stats.misses += 1;
      return null;
    }
    if (entry.expiresAt <= Date.now()) {
      cache.delete(token);
      stats.expirations += 1;
      stats.misses += 1;
      return null;
    }
    if (
      entry.ino !== ino ||
      entry.mtimeMs !== mtimeMs ||
      entry.size !== size
    ) {
      // File swapped or mutated since verification — treat as miss;
      // caller will re-hash and overwrite via set().
      stats.misses += 1;
      return null;
    }
    // Refresh LRU position (Map preserves insertion order).
    cache.delete(token);
    cache.set(token, entry);
    stats.hits += 1;
    return true;
  },

  set(token: string, ino: number, mtimeMs: number, size: number): void {
    if (cache.size >= MAX_ENTRIES && !cache.has(token)) {
      const oldest = cache.keys().next().value;
      if (oldest !== undefined) {
        cache.delete(oldest);
        stats.evictions += 1;
      }
    }
    cache.set(token, {
      ino,
      mtimeMs,
      size,
      expiresAt: Date.now() + TTL_MS,
    });
  },

  stats(): Readonly<Stats> {
    return { ...stats };
  },
};

/**
 * Test-only helper. Must never be imported from a route.ts file — keep
 * the route-file export surface limited to HTTP method handlers +
 * Next.js config exports per cq-nextjs-route-files-http-only-exports.
 */
export function __resetShareHashVerdictCacheForTest(): void {
  cache.clear();
  stats.hits = 0;
  stats.misses = 0;
  stats.evictions = 0;
  stats.expirations = 0;
}
