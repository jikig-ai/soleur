/**
 * GAP F (ADR-067 staleTimes amendment): detect a session-revocation bounce in a
 * client-side `fetch` response so the caller can HARD-navigate to /login —
 * `window.location.assign("/login")` is the only wipe of the App Router Router
 * Cache, and a Router-Cache hit otherwise bypasses middleware's revocation gate.
 *
 * Two shapes must BOTH be caught:
 *  - a direct `401` from the route handler, AND
 *  - the #4307 middleware revocation gate's `302 → /login`. `fetch` transparently
 *    FOLLOWS the 302 to the /login HTML (final `status` is 200 with
 *    `res.redirected === true`), so a `status === 401`-only guard silently never
 *    fires for the revocation path.
 *
 * The pathname check is EXACT (`=== "/login"`) so a response that was redirected
 * somewhere else (canonicalization, `/dashboard`) does not false-positive. A
 * malformed `res.url` (empty in some environments) is treated as "not a bounce".
 *
 * Single-sourced here (was duplicated across three SWR fetch sites) so the
 * security-sensitive dual-detection cannot drift — one site being "fixed" back
 * to `status === 401`-only would silently reopen the revocation window.
 */
export function isRevocationBounce(res: Response): boolean {
  if (res.status === 401) return true;
  if (!res.redirected) return false;
  try {
    return new URL(res.url).pathname === "/login";
  } catch {
    return false;
  }
}
