// feat-operator-inbox-delegation Phase 4 — thin wrapper around the Resend
// received-email GET (resend@6.12.3: `resend.emails.receiving.get(id)` →
// GET /emails/receiving/{id}; type shape GetReceivingEmailResponseSuccess
// in node_modules/resend/dist/index.d.mts).
//
// Deliberately its OWN module so pipeline tests mock the body fetch
// independently of the Anthropic SDK mock — never a shared global fetch
// mock (plan §Files to Create, email-on-received.test.ts contract).
//
// TR3 / parse-and-discard: the returned body exists only in the caller's
// frame (the fused fetch-sanitize-summarize step). Never log it here, and
// never embed response content in a thrown Error message.

import { Resend } from "resend";

export interface ReceivedEmailBody {
  text: string | null;
  html: string | null;
}

/**
 * Fetch the text/html body of a received (inbound) email by its Resend id.
 * Throws a retriable Error on missing key, API error, or empty response —
 * the caller's step retry budget (`retries: 1`) bounds re-runs.
 */
export async function fetchReceivedEmail(
  resendEmailId: string,
): Promise<ReceivedEmailBody> {
  // Least-privilege split (#5468): the inbound body fetch
  // (`resend.emails.receiving.get` → GET /emails/receiving/{id}) needs the
  // *receiving-read* permission. The shared send-scoped (restricted) Resend
  // key lacks it — reusing it here threw `restricted_api_key` and stranded
  // every non-probe email at a permanent NULL (Sentry WEB-PLATFORM-35). Read a
  // dedicated receiving-scoped key ONLY; deliberately NO fallback to the send
  // key — a prod fallback silently reproduces the exact bug behind a warn. Dev
  // sets RESEND_RECEIVING_API_KEY equal to the send key in .env.example.
  const key = process.env.RESEND_RECEIVING_API_KEY;
  if (!key) throw new Error("RESEND_RECEIVING_API_KEY must be set");
  const resend = new Resend(key);
  const { data, error } = await resend.emails.receiving.get(resendEmailId);
  if (error || !data) {
    // error.name only — never response/body fields (TR3 bans email content
    // in Error message strings, which Sentry would otherwise persist).
    throw new Error(
      `fetch-received-email failed: ${error?.name ?? "empty-response"}`,
    );
  }
  return { text: data.text, html: data.html };
}
