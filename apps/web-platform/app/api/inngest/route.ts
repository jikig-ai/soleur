// PR-F (#3244, #3940) Phase 2 — Inngest serve route.
//
// Mounts the Inngest substrate at /api/inngest. ADR-030 invariant I4:
// signature verification required at startup — `signingKey` is sourced
// from INNGEST_SIGNING_KEY and the SDK enforces HMAC validation on every
// inbound POST in cloud mode (INNGEST_DEV unset or =0).
//
// Phase 2 ships with `functions: []`. Phase 3 will fill `cfoOnPaymentFailed`.
// Once functions are registered, the signature gate (validateSignature in
// node_modules/inngest/components/InngestCommHandler.js:1465) runs BEFORE
// any function dispatches — preserving the "401 before dispatch" invariant
// asserted by test/server/inngest/signature-verify.test.ts.
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP method handlers
// are exported. RV6 (DHH/Simplicity): single-function-registry inlined;
// no separate functions/index.ts barrel module.

import { serve } from "inngest/next";
import { inngest } from "@/server/inngest/client";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
if (!SIGNING_KEY) {
  throw new Error("INNGEST_SIGNING_KEY missing at /api/inngest load");
}

export const { GET, POST, PUT } = serve({
  client: inngest,
  functions: [], // Phase 3 fills: cfoOnPaymentFailed.
  signingKey: SIGNING_KEY,
});
