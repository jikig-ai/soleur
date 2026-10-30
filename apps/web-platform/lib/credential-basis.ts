/**
 * Billing-basis description for a stored subscription token (#11524).
 *
 * The Settings status line (`Conversations use: …`) and the remove-token
 * confirm dialog (variant A/B/C) BOTH render from this one function so they
 * cannot disagree: the billing basis must be verifiable before the
 * destructive flow (CPO condition; decision-challenges.md item 29).
 *
 * Pure and client-safe (no `@/server/*` import): the page computes
 * `oauthInEffect` server-side from `isCcOauthEnabled() && is_valid` and passes
 * it down as a prop.
 */

export interface CredentialBasisInput {
  /** An `anthropic_oauth` row is stored (any validity, any operator status). */
  hasOauthToken: boolean;
  /** The lease would use it: kill-switch on AND `is_valid`. */
  oauthInEffect: boolean;
  /** A valid `anthropic` API-key row is stored. */
  hasApiKey: boolean;
}

export type CredentialBasisVariant = "A" | "B" | "C";

export interface CredentialBasis {
  variant: CredentialBasisVariant;
  /** Text after `Conversations use: ` in the Settings status block. */
  conversationsUse: string;
  /** Confirm-dialog body (title and buttons are constant). */
  dialogBody: string;
  /** Post-removal notice, chosen from the props the user confirmed against. */
  notice: string;
}

/** Never claims Soleur revokes the token at Anthropic (CLO condition). */
export const REVOKE_SENTENCE =
  "Removing it here does not revoke it with Anthropic - revoke it in your Claude account if it may be exposed.";

const NOTHING_SET_UP =
  "nothing set up - chat is paused until you add an API key";

export function describeCredentialBasis({
  hasOauthToken,
  oauthInEffect,
  hasApiKey,
}: CredentialBasisInput): CredentialBasis | null {
  if (!hasOauthToken) return null;

  if (oauthInEffect && hasApiKey) {
    return {
      variant: "A",
      conversationsUse: "Claude subscription (API key also saved)",
      dialogBody: `Conversations will use your Anthropic API key, and its usage charges apply. Conversations already open may keep using the token until they end. ${REVOKE_SENTENCE}`,
      notice:
        "Subscription token removed. New conversations will use your API key.",
    };
  }

  if (oauthInEffect) {
    return {
      variant: "B",
      conversationsUse: "Claude subscription",
      dialogBody: `You will have no sign-in for Claude until you add an API key, and chat will stop working. Conversations already open may keep using the token until they end. ${REVOKE_SENTENCE}`,
      notice: "Subscription token removed. Add an API key to keep using chat.",
    };
  }

  // Not in effect (kill-switch off or token invalid): no billing claim, and no
  // "open conversations keep using it" claim either - nothing uses this token.
  // (A/B soften that claim to "may": verified only for the cc-soleur-go Query
  // captured at cold start, unverified for the legacy runner's per-turn path.)
  return {
    variant: "C",
    conversationsUse: hasApiKey ? "your Anthropic API key" : NOTHING_SET_UP,
    dialogBody: `Soleur is not using this token for conversations. Removing deletes the saved copy. ${REVOKE_SENTENCE}`,
    notice: "Subscription token removed.",
  };
}
