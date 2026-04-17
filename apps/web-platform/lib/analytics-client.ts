// Thin client for emitting analytics goals to /api/analytics/track, which
// forwards to Plausible. Fail-soft: analytics must never break user flows.
// See plan 5.1 + 5.2 for server route + provisioning.

/**
 * Emit an analytics goal to the server forwarder (Plausible).
 *
 * **Caller contract — `path` prop:** when `props.path` is set, callers MUST
 * pass a NORMALIZED path — dynamic segments replaced with stable placeholders
 * (Next.js-style):
 *
 * - `/users/[uid]/settings` — NOT `/users/alice@example.com/settings`
 * - `/kb/docs/[slug]` — NOT `/kb/docs/550e8400-e29b-41d4-a716-446655440000`
 * - `/billing/customer/[id]/invoices` — NOT `/billing/customer/123456/invoices`
 *
 * Why: the dashboard groups pageviews by `path`; un-normalized paths produce
 * a long tail of one-off rows and leak PII (emails, UUIDs, customer IDs) into
 * Plausible. The server has a defense-in-depth scrubber
 * (`app/api/analytics/track/sanitize.ts`) that replaces matched tokens with
 * fixed sentinels (`[email]`, `[uuid]`, `[id]`) — but the scrubber is a
 * safety net, not the happy path. Normalize at the call site.
 *
 * Fail-soft: never throws, never blocks the caller.
 *
 * @param goal   Plausible goal name (≤120 chars).
 * @param props  Optional props; only the `path` key is forwarded today
 *               (allowlist in `app/api/analytics/track/sanitize.ts`).
 */
export async function track(
  goal: string,
  props?: Record<string, unknown>,
): Promise<void> {
  if (typeof window === "undefined") return;
  try {
    await fetch("/api/analytics/track", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ goal, props }),
      keepalive: true,
    });
  } catch {
    // fail-soft
  }
}
