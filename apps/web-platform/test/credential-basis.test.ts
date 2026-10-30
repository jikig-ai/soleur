import { describe, it, expect } from "vitest";
import {
  describeCredentialBasis,
  REVOKE_SENTENCE,
} from "@/lib/credential-basis";

const KEY_USE = "your Anthropic API key";
const NOTHING = "nothing set up - chat is paused until you add an API key";

describe("describeCredentialBasis (single source for the status line and the confirm dialog)", () => {
  it("returns null when no oauth row is stored", () => {
    expect(
      describeCredentialBasis({
        hasOauthToken: false,
        oauthInEffect: false,
        hasApiKey: true,
      }),
    ).toBeNull();
    // oauthInEffect cannot be true without a row; the row is authoritative.
    expect(
      describeCredentialBasis({
        hasOauthToken: false,
        oauthInEffect: true,
        hasApiKey: false,
      }),
    ).toBeNull();
  });

  it("variant A: in effect, API key also stored", () => {
    const b = describeCredentialBasis({
      hasOauthToken: true,
      oauthInEffect: true,
      hasApiKey: true,
    })!;
    expect(b.variant).toBe("A");
    expect(b.conversationsUse).toBe("Claude subscription (API key also saved)");
    expect(b.dialogBody).toBe(
      "Conversations will use your Anthropic API key, and its usage charges apply. Conversations already open keep using the token until they end. Removing it here does not revoke it with Anthropic - revoke it in your Claude account if it may be exposed.",
    );
    expect(b.notice).toBe(
      "Subscription token removed. New conversations will use your API key.",
    );
    expect(b.offerAddApiKey).toBe(false);
  });

  it("variant B: in effect, no API key", () => {
    const b = describeCredentialBasis({
      hasOauthToken: true,
      oauthInEffect: true,
      hasApiKey: false,
    })!;
    expect(b.variant).toBe("B");
    expect(b.conversationsUse).toBe("Claude subscription");
    expect(b.dialogBody).toBe(
      `You will have no sign-in for Claude until you add an API key, and chat will stop working. ${REVOKE_SENTENCE}`,
    );
    expect(b.notice).toBe(
      "Subscription token removed. Add an API key to keep using chat.",
    );
    expect(b.offerAddApiKey).toBe(true);
  });

  it.each([true, false])(
    "variant C: not in effect (hasApiKey=%s) makes no billing claim and never offers Add an API key first",
    (hasApiKey) => {
      const b = describeCredentialBasis({
        hasOauthToken: true,
        oauthInEffect: false,
        hasApiKey,
      })!;
      expect(b.variant).toBe("C");
      expect(b.conversationsUse).toBe(hasApiKey ? KEY_USE : NOTHING);
      expect(b.dialogBody).toBe(
        `Soleur is not using this token for conversations. Removing deletes the saved copy. ${REVOKE_SENTENCE}`,
      );
      expect(b.notice).toBe("Subscription token removed.");
      expect(b.offerAddApiKey).toBe(false);
    },
  );

  it("REVOKE_SENTENCE never claims Soleur revokes the token", () => {
    expect(REVOKE_SENTENCE).toBe(
      "Removing it here does not revoke it with Anthropic - revoke it in your Claude account if it may be exposed.",
    );
  });
});
