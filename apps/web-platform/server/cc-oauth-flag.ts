/**
 * Kill-switch for the operator Claude Code subscription-token credential
 * (plan §Phase 6.2). When unset/falsey the oauth read is never attempted — the
 * lease behaves exactly as the api_key-only path did, so the whole feature is
 * inert (AC8). Instant disable without a Flagsmith round-trip. Read at call
 * time so a deploy-time env flip takes effect on the next lease without a
 * process restart contract.
 *
 * Single source for the KILL-SWITCH predicate only: `byok-lease.ts`,
 * `app/api/keys/route.ts` (POST) and `settings/page.tsx` all import this so
 * none can parse the env var differently. It is NOT the whole "in effect"
 * rule: the lease additionally applies the owner-only fence, and the page
 * composes `isCcOauthEnabled() && is_valid` itself (#11524).
 */
export function isCcOauthEnabled(): boolean {
  const v = process.env.CC_OAUTH_ENABLED;
  return v === "1" || v === "true";
}
