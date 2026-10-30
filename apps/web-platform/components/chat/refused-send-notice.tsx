/**
 * #11525 — visible, machine-readable feedback when a gate / prompt / disclosure
 * response was REFUSED (credential-blocked chat or socket not open): the frame
 * never left the client, the card stays actionable, and this line says why.
 */
export const REFUSED_SEND_MESSAGE = "Couldn't send. Reconnect, then choose again.";

export function RefusedSendNotice() {
  return (
    <p role="alert" className="mt-2 text-sm text-red-400">
      {REFUSED_SEND_MESSAGE}
    </p>
  );
}
