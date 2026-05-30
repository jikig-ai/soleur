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
