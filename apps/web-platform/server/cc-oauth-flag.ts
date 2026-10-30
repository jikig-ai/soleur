/**
 * Kill-switch for the operator Claude Code subscription-token credential
 * (plan §Phase 6.2). When unset/falsey the oauth read is never attempted — the
 * lease behaves exactly as the api_key-only path did, so the whole feature is
 * inert (AC8). Instant disable without a Flagsmith round-trip. Read at call
 * time so a deploy-time env flip takes effect on the next lease without a
 * process restart contract.
 *
 * Single source: `byok-lease.ts` (the lease) and `settings/page.tsx` (the
 * "in effect" UI derivation, #11524) both import this so the page can never
 * drift from the predicate the lease actually applies.
 */
export function isCcOauthEnabled(): boolean {
  const v = process.env.CC_OAUTH_ENABLED;
  return v === "1" || v === "true";
}
