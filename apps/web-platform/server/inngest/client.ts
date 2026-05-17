// PR-F (#3244, #3940) Phase 2 — Inngest client.
//
// Fail-closed at module load on missing/empty INNGEST_SIGNING_KEY or
// INNGEST_EVENT_KEY, and on malformed INNGEST_BASE_URL when set. The
// signing key gates inbound POST verification at /api/inngest; the event
// key signs outbound `inngest.send` envelopes from the Stripe webhook.
// Both are load-bearing for ADR-030 invariant I4 (signature-verify required
// at startup). A silent default would expose the runtime trigger surface
// to forged events.
//
// INNGEST_BASE_URL is optional. Self-hosted Hetzner deploys set it to
// http://127.0.0.1:8288 per ADR-030; Inngest Cloud deploys (rejected,
// see ADR-030) would omit it.

import { Inngest } from "inngest";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
const EVENT_KEY = process.env.INNGEST_EVENT_KEY;
const BASE_URL = process.env.INNGEST_BASE_URL;

if (!SIGNING_KEY) {
  throw new Error("INNGEST_SIGNING_KEY missing at startup");
}
if (!EVENT_KEY) {
  throw new Error("INNGEST_EVENT_KEY missing at startup");
}
if (BASE_URL) {
  try {
    new URL(BASE_URL);
  } catch {
    throw new Error(`INNGEST_BASE_URL malformed: ${BASE_URL}`);
  }
}

export const inngest = new Inngest({
  id: "soleur-runtime",
  eventKey: EVENT_KEY,
  ...(BASE_URL ? { baseUrl: BASE_URL } : {}),
});
