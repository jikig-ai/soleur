import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

// PR-F (#3244, #3940) Phase 3 — CFO function on finance.payment_failed.
//
// Mocks BYOK lease, tenant client, Stripe SDK, and observability. Tests
// drive `cfoHandler` directly with a mock `step` (each step.run callback
// runs eagerly) so the Inngest runtime is not required for unit coverage.
// The full Inngest dev-mode round-trip is covered by the integration tier
// per plan §Test Strategy (TENANT_INTEGRATION_TEST=1).
//
// Source-read negative-space tests guard the load-bearing structural
// invariants from ADR-030 that the mock-based tests cannot prove:
//   I3 — verify-external-state is single-pass (verify must NOT be a
//        step.run-checkpointed result that subsequent steps consume).
//   I1 — runWithByokLease opens INSIDE each SDK-calling step.run.

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

// --- Module mocks (hoisted by vitest) ----------------------------------------

const retrieveSpy = vi.fn();
const getStripeSpy = vi.fn(() => ({
  charges: { retrieve: retrieveSpy },
}));
vi.mock("@/lib/stripe", () => ({
  getStripe: getStripeSpy,
}));

const insertSpy = vi.fn(async () => ({ data: null, error: null }));
const getFreshTenantClientSpy = vi.fn(async () => ({
  from: () => ({ insert: insertSpy }),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: getFreshTenantClientSpy,
}));

const runWithByokLeaseSpy = vi.fn(
  async <T,>(_userId: string, fn: (lease: unknown) => Promise<T>) => {
    return fn({ getApiKey: () => "fake-api-key" });
  },
);
vi.mock("@/server/byok-lease", () => ({
  runWithByokLease: runWithByokLeaseSpy,
}));

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

function makeEvent(v: string, founderId = "founder-123") {
  return {
    v,
    data: {
      founderId,
      payload: {
        founderId,
        invoiceId: "in_test_001",
        customerEmailHash: "abc123",
        amount: 4200,
        currency: "usd",
        failureCode: "card_declined",
      },
    },
  };
}

beforeEach(() => {
  vi.resetModules();
  retrieveSpy.mockReset();
  getStripeSpy.mockClear();
  insertSpy.mockReset();
  insertSpy.mockResolvedValue({ data: null, error: null });
  getFreshTenantClientSpy.mockClear();
  runWithByokLeaseSpy.mockClear();
  reportSilentFallbackSpy.mockReset();
  logger.warn.mockReset();
  logger.info.mockReset();
  logger.error.mockReset();
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cfo-on-payment-failed");
  return mod.cfoHandler;
}

describe("cfo-on-payment-failed — schema-gate (RV2)", () => {
  it("deadletters and early-returns when event.v is unsupported (v=2)", async () => {
    const handler = await importHandler();
    const step = makeStep();
    const result = (await handler({
      event: makeEvent("2"),
      step,
      logger,
    })) as { deadlettered?: boolean; drafted?: boolean };

    expect(result.deadlettered).toBe(true);
    expect(retrieveSpy).not.toHaveBeenCalled();
    expect(runWithByokLeaseSpy).not.toHaveBeenCalled();
    expect(insertSpy).not.toHaveBeenCalled();
    // Schema-gate executed AS a step.run (not a throw — RV2).
    expect(step.calls.some((c) => c.name === "schema-gate")).toBe(true);
  });

  it("deadletters when event.v is unset (v=0)", async () => {
    const handler = await importHandler();
    const step = makeStep();
    const result = (await handler({
      event: { data: makeEvent("1").data }, // v omitted
      step,
      logger,
    })) as { deadlettered?: boolean };

    expect(result.deadlettered).toBe(true);
    expect(retrieveSpy).not.toHaveBeenCalled();
  });

  it("proceeds when event.v is the supported version (v=1)", async () => {
    retrieveSpy.mockResolvedValue({ status: "failed" });
    const handler = await importHandler();
    const step = makeStep();
    const result = (await handler({
      event: makeEvent("1"),
      step,
      logger,
    })) as { drafted?: boolean };

    expect(retrieveSpy).toHaveBeenCalledTimes(1);
    expect(result.drafted).toBe(true);
  });
});

describe("cfo-on-payment-failed — verify-stripe-state (RV17)", () => {
  it("does NOT draft when live Stripe state is 'succeeded' (state drift after webhook)", async () => {
    retrieveSpy.mockResolvedValue({ status: "succeeded" });
    const handler = await importHandler();
    const step = makeStep();
    const result = (await handler({
      event: makeEvent("1"),
      step,
      logger,
    })) as { drafted?: boolean; reason?: string };

    expect(result.drafted).toBe(false);
    expect(result.reason).toMatch(/state=succeeded|verify/);
    expect(runWithByokLeaseSpy).not.toHaveBeenCalled();
    expect(insertSpy).not.toHaveBeenCalled();
  });

  it("does NOT draft + mirrors reportSilentFallback when stripe.charges.retrieve times out (>2s)", async () => {
    vi.useFakeTimers();
    try {
      retrieveSpy.mockImplementation(() => new Promise(() => {})); // never resolves
      const handler = await importHandler();
      const step = makeStep();
      const promise = handler({ event: makeEvent("1"), step, logger });
      // Advance past the 2s verify timeout.
      await vi.advanceTimersByTimeAsync(2100);
      const result = (await promise) as { drafted?: boolean; reason?: string };

      expect(result.drafted).toBe(false);
      expect(result.reason).toMatch(/timeout/);
      expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
      const ctx = reportSilentFallbackSpy.mock.calls[0][1] as {
        feature: string;
        op?: string;
      };
      expect(ctx.feature).toBe("trust-tier-verify");
      expect(runWithByokLeaseSpy).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("cfo-on-payment-failed — draft + persist (R1, RV16)", () => {
  it("opens runWithByokLease for the draft step and persists with tier=external_brand_critical/status=draft", async () => {
    retrieveSpy.mockResolvedValue({ status: "failed" });
    const handler = await importHandler();
    const step = makeStep();
    await handler({ event: makeEvent("1"), step, logger });

    expect(runWithByokLeaseSpy).toHaveBeenCalledTimes(1);
    expect(runWithByokLeaseSpy.mock.calls[0][0]).toBe("founder-123");

    // persist-draft fired with the CHECK-constraint-compatible shape.
    expect(insertSpy).toHaveBeenCalledTimes(1);
    const row = (insertSpy.mock.calls[0] as unknown[])[0] as {
      tier: string;
      status: string;
      user_id: string;
      trust_tier: string;
    };
    expect(row.tier).toBe("external_brand_critical");
    expect(row.status).toBe("draft");
    expect(row.user_id).toBe("founder-123");
    expect(row.trust_tier).toBe("draft_one_click");
  });
});

describe("cfo-on-payment-failed — structural invariants (source-grep)", () => {
  // These are negative-space regression guards for ADR-030 invariants that
  // mock-based tests cannot prove. If a refactor inadvertently restructures
  // the function to a shape that violates the invariant, these gates fail
  // BEFORE the runtime regression hits production.

  const srcPath = resolve(
    __dirname,
    "../../../server/inngest/functions/cfo-on-payment-failed.ts",
  );

  it("I3 — stripe.charges.retrieve is NOT wrapped in any step.run (single-pass invariant)", () => {
    // Review P2-9 (pattern-recognition + test-design): tightened from a
    // name-string regex (which false-positive-tripped on legitimate
    // step names like "verify-deadletter") to a structural check against
    // the actual SDK call. The invariant is "verify is not checkpointed";
    // the concrete API surface that MUST stay un-checkpointed is
    // stripe.charges.retrieve. If a future change wraps that call in
    // step.run, Inngest's step memoization will serve a stale result on
    // a 6h-deadlettered retry.
    const src = readFileSync(srcPath, "utf8");
    // Pattern: step.run(<name>, <cb>) where the callback body contains
    // stripe.charges.retrieve. Match on the SDK token directly so step
    // names are irrelevant.
    const stripeIdx = src.search(/stripe\.charges\s*\.\s*retrieve\s*\(/);
    expect(stripeIdx, "stripe.charges.retrieve must be present").toBeGreaterThan(-1);
    // Find every step.run( opener and check none of their callback
    // bodies contains the SDK token. Cheapest bound: between each
    // step.run opener and its closing "});", the SDK token must not
    // appear.
    const stepRunBlocks = [...src.matchAll(/step\.run\(\s*["'`][^"'`]+["'`][\s\S]*?\n\s{2,4}\}\s*\)\s*;/g)];
    for (const block of stepRunBlocks) {
      expect(
        block[0],
        `step.run block must not wrap stripe.charges.retrieve (I3 single-pass): ${block[0].slice(0, 80)}…`,
      ).not.toMatch(/stripe\.charges\s*\.\s*retrieve\s*\(/);
    }
  });

  it("I1 — runWithByokLease is called from inside a step.run callback (per-step lease)", () => {
    const src = readFileSync(srcPath, "utf8");
    // Both tokens must be present, and runWithByokLease must NOT appear at
    // top-level (outside any step.run). We approximate "inside a step.run"
    // by requiring that the FIRST step.run( occurs BEFORE the FIRST
    // runWithByokLease( in source order. This is sufficient for the single
    // SDK-calling step shipped by PR-F; PR-G adds a positional gate when a
    // 2nd SDK step lands.
    const stepRunIdx = src.search(/step\.run\(/);
    const leaseIdx = src.search(/runWithByokLease\(/);
    expect(stepRunIdx).toBeGreaterThan(-1);
    expect(leaseIdx).toBeGreaterThan(-1);
    expect(leaseIdx).toBeGreaterThan(stepRunIdx);
  });

  it("RV16 — persist-draft step does NOT open runWithByokLease (lease is for SDK-calling steps only)", () => {
    const src = readFileSync(srcPath, "utf8");
    // Find the persist-draft step.run block and verify runWithByokLease is
    // absent inside it. Source-level grep over the lexical block.
    const persistMatch = src.match(
      /step\.run\(\s*["'`]persist-draft["'`][\s\S]*?\n\s{2,4}\}\s*\)\s*;/,
    );
    expect(persistMatch).not.toBeNull();
    expect(persistMatch![0]).not.toMatch(/runWithByokLease/);
  });
});
