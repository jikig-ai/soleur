// feat-skip-api-key-onboarding (#4642). Framework-free decision shared by the
// two redirect gates (app/(auth)/callback/route.ts, app/api/accept-terms/
// route.ts) so the "show the /setup-key onboarding step?" rule lives in one
// unit-tested place. Routing/UX only — chat-time key enforcement is separate.

export interface SetupKeyGateInput {
  /** Own VALID anthropic key OR an active, accepted BYOK delegation. */
  hasEffectiveKey: boolean;
  /** `users.setup_key_skipped_at` — non-null once the user chose "Set up later". */
  setupKeySkippedAt: string | null;
}

/**
 * The onboarding api-key step (redirect to /setup-key) is shown ONLY when the
 * user has no effective key AND has not skipped. Effective-key OR an explicit
 * skip both let the user past the gate; chat-time enforcement still blocks any
 * paid call until a usable key exists.
 */
export function shouldRouteToSetupKey({
  hasEffectiveKey,
  setupKeySkippedAt,
}: SetupKeyGateInput): boolean {
  return !hasEffectiveKey && setupKeySkippedAt == null;
}

/**
 * feat-invite-accept-membership-byok (#4715). True when a validated post-auth
 * next-hop targets workspace-invite acceptance (`/invite/<token>`). The two
 * redirect gates use it to let an invite target OUTRANK the /setup-key
 * onboarding step, so a keyless invitee accepts membership instead of stalling
 * at a key-purchase funnel they can't complete.
 *
 * `nextHop` is always `safeReturnTo`-validated upstream (same-origin, allowlist
 * prefix `/invite/`), so this only ever sees a benign relative path — the
 * `startsWith("/invite/")` check requires the trailing slash, so prefix-adjacent
 * paths like `/invited-users` never match.
 */
export function isInviteReturnTarget(nextHop: string | null): nextHop is string {
  return nextHop?.startsWith("/invite/") ?? false;
}
