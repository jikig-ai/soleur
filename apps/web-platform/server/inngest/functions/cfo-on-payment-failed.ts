// PR-F (#3244, #3940) Phase 3 — CFO function on finance.payment_failed.
//
// ADR-030 load-bearing invariants:
//   I1 — runWithByokLease opens INSIDE each step.run that calls the SDK
//        (R1 — ALS context is lost across Inngest step boundaries; opening
//        the lease in the function body would silently fall back to a
//        global default key).
//   I2 — getFreshTenantClient is called INSIDE each tenant-touching step
//        (JWT freshness; never cached across boundaries).
//   I3 — verify-stripe-state is SINGLE-PASS — verify lives in the function
//        body, NOT a step.run whose checkpointed result is consumed by
//        downstream steps. Any Inngest retry path re-enters from the top
//        and re-verifies (RV17 / Kieran P1.2). Stale-after-verify on a
//        6h-deadlettered retry is the failure mode this closes.
//   I4 — signature-verify required at startup (enforced by route.ts).
//   I5 — "drafts everywhere, sends nowhere" — DB CHECK constraint
//        messages_external_tier_status_check (migration 046) plus this
//        function only ever writes status='draft' for external_* tiers.
//
// RV2 — schema-gate is a NON-throwing step.run that early-returns
//   {deadletter: true}. Schema-version mismatches are deterministic;
//   throwing under `retries: 1` would waste a BYOK turn.
// RV3 — PaymentFailedPayload inlined; reintroduce as discriminated union
//   when v=2 ships (per learning 2026-04-18-schema-version-must-be-
//   asserted-at-consumer-boundary).
// RV4 — TIER constant inlined; ACTION_CLASS_DEFAULTS lifts to a map when
//   PR-G's 2nd consumer arrives (follow-up #3947).
// RV16 — persist-draft does NOT open runWithByokLease; lease is for SDK
//   calls and INSERT under tenant client is sufficient.
//
// Phase 3 ships the substrate; the Anthropic SDK call and per-turn
// cost-writer cap-check are STUBBED inside the draft step pending PR-G
// cohort onboarding (#3947).

import { inngest } from "@/server/inngest/client";
import { getStripe } from "@/lib/stripe";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { runWithByokLease } from "@/server/byok-lease";
import { reportSilentFallback } from "@/server/observability";
import {
  MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL,
  MESSAGE_STATUS_DRAFT,
} from "@/lib/messages/tiers";

interface PaymentFailedPayload {
  founderId: string;
  invoiceId: string;
  customerEmailHash: string;
  amount: number;
  currency: string;
  failureCode: string;
}

const TIER = "draft_one_click" as const;
const SUPPORTED_V = "1";

const MAX_TURN_DURATION_MS = parseInt(
  process.env.MAX_TURN_DURATION_MS ?? "90000",
  10,
);

const VERIFY_TIMEOUT_MS = 2000;

interface HandlerArgs {
  event: {
    v?: string;
    data: { founderId: string; payload: PaymentFailedPayload };
  };
  step: {
    run<T>(name: string, cb: () => Promise<T>): Promise<T>;
  };
  logger: {
    warn: (...args: unknown[]) => void;
    info: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

export async function cfoHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<
  | { deadlettered: true; reason: string }
  | { drafted: false; reason: string }
  | { drafted: true }
> {
  // RV2: schema-gate as NON-throwing step.run. Deterministic failure mode;
  // no retry budget consumed.
  const v = event.v ?? "0";
  const gate = await step.run("schema-gate", async () => {
    if (v !== SUPPORTED_V) {
      return { deadletter: true as const, reason: `schema_v=${v}` };
    }
    return { deadletter: false as const, reason: "" };
  });
  if (gate.deadletter) {
    logger.warn({ v, reason: gate.reason }, "Schema-gate deadletter");
    return { deadlettered: true, reason: gate.reason };
  }

  const founderId = event.data.founderId;
  const payload = event.data.payload;

  // Review P2-4 (data-integrity-guardian): defense-in-depth parity check.
  // Signature-verify gates the dispatch at the route layer; this guard
  // catches the case where a signed envelope carries a mismatched
  // payload.founderId (impossible from the Stripe webhook bridge, but
  // possible if a future producer mis-assembles the envelope or a
  // schema-version migration drifts the shape).
  if (payload.founderId !== founderId) {
    logger.warn(
      { founderId, payloadFounderId: payload.founderId },
      "envelope founderId mismatch — deadlettering (defense-in-depth)",
    );
    return { deadlettered: true, reason: "envelope-mismatch" };
  }

  // I3 (RV17): single-pass verify. NOT a step.run — Inngest's step
  // memoization would otherwise serve a stale checkpoint on a 6h
  // retry. Any retry re-enters from the top and re-runs this verify.
  const stripe = getStripe();
  let verifyState: string | undefined;
  const verifyResult = await Promise.race<
    { ok: true; state: string } | { ok: false; reason: string }
  >([
    stripe.charges
      .retrieve(payload.invoiceId)
      .then((c: { status: string }) => ({ ok: true as const, state: c.status }))
      .catch((err: unknown) => ({
        ok: false as const,
        reason: `verify-error:${(err as Error)?.message ?? "unknown"}`,
      })),
    new Promise<{ ok: false; reason: string }>((res) =>
      setTimeout(
        () => res({ ok: false as const, reason: "verify-timeout-2s" }),
        VERIFY_TIMEOUT_MS,
      ),
    ),
  ]);

  if (!verifyResult.ok) {
    logger.warn(
      { founderId, reason: verifyResult.reason },
      "Stripe verify failed — aborting (no draft)",
    );
    reportSilentFallback(new Error(verifyResult.reason), {
      feature: "trust-tier-verify",
      op: "stripe.charges.retrieve",
      message: "Stripe verify failed before CFO draft",
      extra: { founderId, invoiceId: payload.invoiceId },
    });
    return { drafted: false, reason: verifyResult.reason };
  }

  verifyState = verifyResult.state;
  if (verifyState !== "failed") {
    // Live state moved (typically to "succeeded") between webhook and verify.
    // Do NOT draft. Existing draft archival + re-queue logic lands in PR-G.
    logger.warn(
      { founderId, verifyState },
      "Stripe state drifted — aborting (no draft)",
    );
    return { drafted: false, reason: `state=${verifyState}` };
  }

  // I1: lease opens INSIDE the SDK-calling step.run. ALS context is local
  // to the step boundary; opening outside would silently escape on replay.
  // byok-audit-writer-sweep: out-of-scope — Phase 3 stub holds the lease
  // open for the structural test surface (R1 / I1: lease MUST open inside
  // each SDK-calling step). The actual Anthropic SDK call + per-turn
  // recordByokUseAndCheckCap + persistTurnCost wire in PR-G (#3947) when
  // cohort onboarding lands. Until then there is no real token cost to
  // record; the stub returns tokenCount=0 / unitCostCents=0 deterministically.
  const _draft = await step.run("draft-customer-response", async () => {
    return runWithByokLease(founderId, async (_lease) => {
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), MAX_TURN_DURATION_MS);
      try {
        // STUB: in PR-G this becomes the leader prompt loop. The signal
        // hook is wired here so the lease/timeout shape is fixed.
        void ac.signal;
        return {
          body: "<draft text — wired in PR-G>",
          tokenCount: 0,
          unitCostCents: 0,
        };
      } finally {
        clearTimeout(timer);
      }
    });
  });

  // I2: getFreshTenantClient called inside the persist step (per-step JWT
  // freshness). RV16: NO runWithByokLease here — this is a tenant-client
  // INSERT, not an SDK call.
  await step.run("persist-draft", async () => {
    const tenant = await getFreshTenantClient(founderId);
    await tenant.from("messages").insert({
      user_id: founderId,
      tier: MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL, // I5 + migration 046 CHECK enforces status=draft.
      status: MESSAGE_STATUS_DRAFT,
      source: "stripe",
      owning_domain: "cfo",
      draft_preview: "<draft text — wired in PR-G>",
      urgency: "medium",
      trust_tier: TIER,
    });
  });

  return { drafted: true };
}

export const cfoOnPaymentFailed = inngest.createFunction(
  {
    id: "cfo-on-payment-failed",
    concurrency: [
      // CEL key per Inngest docs (/websites/inngest 2026-05-17).
      // Function name namespaces by event; no colon-suffix needed.
      { scope: "fn", key: "event.data.founderId", limit: 1 },
      { scope: "account", key: '"agent-runtime"', limit: 50 },
    ],
    retries: 1, // RV2: transient SDK/network only.
  },
  { event: "finance.payment_failed" },
  cfoHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
