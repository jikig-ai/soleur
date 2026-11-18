// host-roster.ts — the pure parse of SOLEUR_HOST_ROSTER (#12910).
//
// The roster maps each web host's `var.web_hosts` key (`web-1`, `web-2`, the
// value resolveHostId() returns once verified) to that host's private-net
// address. session-router.ts dials it; host-identity.ts reads it to verify the
// host's own key against its own private IP (CTO ruling T1).
//
// A leaf: no imports, read at call time (never cached at module load), never
// throws. Empty, unset or invalid gives `{}`, so a peer is never resolvable and
// a stray remote holder yields `owner-unresolved` rather than a wrong dial.

export function loadHostRoster(
  env: NodeJS.ProcessEnv = process.env,
): Record<string, string> {
  const raw = env.SOLEUR_HOST_ROSTER?.trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof v === "string" && v.length > 0) out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}
