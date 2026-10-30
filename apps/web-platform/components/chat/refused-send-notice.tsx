/**
 * #11525 — visible, machine-readable feedback when a gate / prompt / disclosure
 * response was REFUSED (credential-blocked chat or socket not open): the frame
 * never left the client, the card stays actionable, and this line says why.
 *
 * Two reasons, two remedies:
 *  - "connection": the socket was not open; reconnecting is enough and the card
 *    is still live, so "choose again" is right.
 *  - "credential": the run that raised the question died with the key failure,
 *    so the card is probably dead; the remedy is fix the credential, Reconnect,
 *    then re-send the user's message (not "choose again" on a dead gate).
 */
export const REFUSED_SEND_MESSAGE = "Couldn't send. Reconnect, then choose again.";

export function credentialRefusedMessage(noun: "token" | "key"): string {
  return `Couldn't send. Update your ${noun} in Settings, select Reconnect, then send your message again.`;
}

export type RefusalContext =
  | { reason: "connection" }
  | { reason: "credential"; noun: "token" | "key" };

export const CONNECTION_REFUSAL: RefusalContext = { reason: "connection" };

export function RefusedSendNotice({ refusal = CONNECTION_REFUSAL }: { refusal?: RefusalContext }) {
  return (
    <p role="alert" className="mt-2 text-sm text-red-400">
      {refusal.reason === "credential"
        ? credentialRefusedMessage(refusal.noun)
        : REFUSED_SEND_MESSAGE}
    </p>
  );
}
