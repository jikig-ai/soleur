// Thin client for emitting analytics goals to /api/analytics/track, which
// forwards to Plausible. Fail-soft: analytics must never break user flows.
// See plan 5.1 + 5.2 for server route + provisioning.

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
