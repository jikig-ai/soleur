import { computeBodyHash } from "./hash";

export type FetchResult =
  | { status: "ok"; body: string; sha256: string }
  | { status: "404"; body: null; sha256: null }
  | { status: "fatal-4xx"; code: number }
  | { status: "5xx-after-retries"; code: number };

export interface FetchOptions {
  fetcher: (commentId: number) => Promise<{ status: number; body?: string }>;
  sleep?: (ms: number) => Promise<void>;
  maxAttempts?: number;
  baseBackoffMs?: number;
}

const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * Fetch a PR comment body with classification per plan Phase 2 step 3e:
 *   - 200          → ok with body + sha256
 *   - 404          → degraded (no retry; the action's cla.json + GraphQL audit
 *                    log corroborate per CLO sign-off)
 *   - 401/403/400  → fast-fail (config bug, not transient)
 *   - 5xx / 429    → exponential backoff up to maxAttempts (default 3)
 *
 * Tests inject `fetcher` and `sleep` to drive deterministically.
 */
export async function fetchCommentBody(
  commentId: number,
  opts: FetchOptions,
): Promise<FetchResult> {
  const sleep = opts.sleep ?? defaultSleep;
  const maxAttempts = opts.maxAttempts ?? 3;
  const base = opts.baseBackoffMs ?? 250;

  let lastCode = 0;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const r = await opts.fetcher(commentId);
    lastCode = r.status;

    if (r.status === 200) {
      const body = r.body ?? "";
      return { status: "ok", body, sha256: computeBodyHash(body) };
    }
    if (r.status === 404) {
      return { status: "404", body: null, sha256: null };
    }
    // 4xx ≠ 404 → fast-fail (Kieran F5).
    if (r.status >= 400 && r.status < 500 && r.status !== 429) {
      return { status: "fatal-4xx", code: r.status };
    }
    // 5xx or 429 → retry with exponential backoff if attempts remain.
    if (attempt < maxAttempts) {
      await sleep(base * 2 ** (attempt - 1));
    }
  }
  return { status: "5xx-after-retries", code: lastCode };
}
