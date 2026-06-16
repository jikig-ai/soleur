import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Capture the inherited value so afterEach restores it — INNGEST_MANUAL_TRIGGER_SECRET
// is security-relevant; never leak a stub/delete to a sibling file in the worker.
const ORIG_SECRET = process.env.INNGEST_MANUAL_TRIGGER_SECRET;

const { mockSendInngestWithRetry, mockReportSilentFallback, mockInngestSend } =
  vi.hoisted(() => ({
    mockSendInngestWithRetry: vi.fn(),
    mockReportSilentFallback: vi.fn(),
    mockInngestSend: vi.fn(),
  }));

vi.mock("@/server/inngest/send-with-retry", () => ({
  sendInngestWithRetry: mockSendInngestWithRetry,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

// The route dynamically imports the client inside POST; mock it so the import
// resolves without firing the client's load-time fail-closed throw.
vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

import { POST } from "@/app/api/internal/trigger-cron/route";

const SECRET = "trigger-cron-test-secret";
const ALLOWED_EVENT = "cron/workspace-sync-health.manual-trigger";

function makeRequest(
  body: object | string,
  opts: { authorization?: string | null } = {},
): Request {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const headers = new Headers({ "content-type": "application/json" });
  // Default: a valid Bearer. Pass `authorization: null` to omit.
  const auth =
    "authorization" in opts ? opts.authorization : `Bearer ${SECRET}`;
  if (auth !== null && auth !== undefined) headers.set("authorization", auth);
  return new Request("https://soleur.ai/api/internal/trigger-cron", {
    method: "POST",
    headers,
    body: raw,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.INNGEST_MANUAL_TRIGGER_SECRET = SECRET;
  // Default: sendInngestWithRetry invokes the thunk (so inngest.send fires and
  // the envelope can be asserted), and resolves.
  mockSendInngestWithRetry.mockImplementation(async (fn: () => Promise<unknown>) => {
    await fn();
  });
  mockInngestSend.mockResolvedValue({ ids: ["evt_1"] });
});

afterEach(() => {
  if (ORIG_SECRET === undefined) delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  else process.env.INNGEST_MANUAL_TRIGGER_SECRET = ORIG_SECRET;
});

describe("POST /api/internal/trigger-cron — auth / fail-closed", () => {
  it("returns 503 (fail-closed) when the secret is unset (no dispatch)", async () => {
    delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
    const res = await POST(makeRequest({ event: ALLOWED_EVENT }));
    expect(res.status).toBe(503);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 401 on missing Bearer (no dispatch)", async () => {
    const res = await POST(
      makeRequest({ event: ALLOWED_EVENT }, { authorization: null }),
    );
    expect(res.status).toBe(401);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 401 on wrong Bearer (no dispatch)", async () => {
    const res = await POST(
      makeRequest({ event: ALLOWED_EVENT }, { authorization: "Bearer nope" }),
    );
    expect(res.status).toBe(401);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 401 on a wrong-length Bearer (length-guard before timingSafeEqual)", async () => {
    const res = await POST(
      makeRequest(
        { event: ALLOWED_EVENT },
        { authorization: `Bearer ${SECRET}-extra` },
      ),
    );
    expect(res.status).toBe(401);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 401 on a CORRECT-length but wrong-bytes Bearer (positive control: timingSafeEqual is the deciding gate, not just the length-guard)", async () => {
    const wrongSameLength = "x".repeat(SECRET.length);
    expect(wrongSameLength.length).toBe(SECRET.length); // guard: same length
    const res = await POST(
      makeRequest(
        { event: ALLOWED_EVENT },
        { authorization: `Bearer ${wrongSameLength}` },
      ),
    );
    expect(res.status).toBe(401);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });
});

describe("POST /api/internal/trigger-cron — dispatch", () => {
  it("dispatches an allowlisted event → 202 and calls sendInngestWithRetry once", async () => {
    const res = await POST(makeRequest({ event: ALLOWED_EVENT }));
    expect(res.status).toBe(202);
    const json = await res.json();
    expect(json).toMatchObject({ dispatched: ALLOWED_EVENT, trigger: "manual-api" });

    expect(mockSendInngestWithRetry).toHaveBeenCalledTimes(1);
    // arg #2 is the context object.
    expect(mockSendInngestWithRetry.mock.calls[0][1]).toEqual({
      feature: "trigger-cron",
    });
    // The thunk (arg #1) wrapped inngest.send with the manual-api envelope.
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const envelope = mockInngestSend.mock.calls[0][0];
    expect(envelope).toMatchObject({
      name: ALLOWED_EVENT,
      data: { trigger: "manual-api" },
    });
    expect(typeof envelope.data.at).toBe("string");
    expect(() => new Date(envelope.data.at as string).toISOString()).not.toThrow();
  });

  it("returns 400 on a non-allowlisted event (no dispatch)", async () => {
    for (const evt of [
      "cron/cf-token-expiry-check.manual-trigger",
      "evil",
      "cron/bug-fixer.run",
    ]) {
      mockSendInngestWithRetry.mockClear();
      const res = await POST(makeRequest({ event: evt }));
      expect(res.status).toBe(400);
      expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
    }
  });

  it("returns 400 on malformed JSON (valid secret + auth)", async () => {
    const res = await POST(makeRequest("{not json"));
    expect(res.status).toBe(400);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 413 on an oversized body (memory-amp DoS guard, no dispatch)", async () => {
    const huge = JSON.stringify({ event: ALLOWED_EVENT, pad: "a".repeat(70 * 1024) });
    const res = await POST(makeRequest(huge));
    expect(res.status).toBe(413);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });

  it("returns 502 + reportSilentFallback when sendInngestWithRetry throws", async () => {
    const err = new Error("inngest loopback down");
    mockSendInngestWithRetry.mockRejectedValueOnce(err);
    const res = await POST(makeRequest({ event: ALLOWED_EVENT }));
    expect(res.status).toBe(502);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(err, {
      feature: "trigger-cron",
      op: "dispatch",
      extra: { event: ALLOWED_EVENT },
    });
  });
});

describe("POST /api/internal/trigger-cron — optional event data pass-through (#4742)", () => {
  // AC-A1: an allowlisted event with a `data` object forwards the per-cron
  // fields verbatim alongside the route-controlled audit keys.
  it("forwards body.data fields (issue_number) while stamping trigger + fresh at (AC-A1)", async () => {
    const res = await POST(
      makeRequest({ event: ALLOWED_EVENT, data: { issue_number: 4383 } }),
    );
    expect(res.status).toBe(202);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const envelope = mockInngestSend.mock.calls[0][0];
    expect(envelope.name).toBe(ALLOWED_EVENT);
    expect(envelope.data.issue_number).toBe(4383);
    expect(envelope.data.trigger).toBe("manual-api");
    expect(typeof envelope.data.at).toBe("string");
    expect(() => new Date(envelope.data.at as string).toISOString()).not.toThrow();
  });

  // AC-A2: route keys are spread LAST so a caller cannot forge a payload that
  // mimics a scheduled (non-manual) fire — the audit-poison guard. The
  // non-colliding `issue_number` key makes this test SELF-gating: it fails both
  // the "callerData never merged" mutant (issue_number absent) AND the
  // "route keys spread first" mutant (trigger === "spoofed"), so it does not
  // depend on AC-A1 to have discriminating power.
  it("never lets body.data override trigger/at (route keys win — audit-poison guard) (AC-A2)", async () => {
    const res = await POST(
      makeRequest({
        event: ALLOWED_EVENT,
        data: { issue_number: 99, trigger: "spoofed", at: "1999-01-01T00:00:00.000Z" },
      }),
    );
    expect(res.status).toBe(202);
    const envelope = mockInngestSend.mock.calls[0][0];
    // non-colliding caller key survives (proves the merge happened) ...
    expect(envelope.data.issue_number).toBe(99);
    // ... while colliding route keys still win (proves spread order).
    expect(envelope.data.trigger).toBe("manual-api");
    expect(envelope.data.at).not.toBe("1999-01-01T00:00:00.000Z");
    // fresh ISO timestamp, not the spoofed value
    expect(() => new Date(envelope.data.at as string).toISOString()).not.toThrow();
  });

  // AC-A3: with NO `data` key, the envelope carries EXACTLY the route-controlled
  // keys. As of #5345 the secret route dispatches through the runRoutine
  // chokepoint, so the envelope also carries the system-tier attribution keys
  // (actor_class/actor_id/delegating_principal) — additive + ignored by
  // consuming crons, required by the run-log middleware for WORM attribution.
  const SYSTEM_ENVELOPE_KEYS = [
    "actor_class",
    "actor_id",
    "at",
    "delegating_principal",
    "trigger",
  ];
  it("dispatches the system-tier envelope when data is absent (exact keys) (AC-A3)", async () => {
    const res = await POST(makeRequest({ event: ALLOWED_EVENT }));
    expect(res.status).toBe(202);
    const envelope = mockInngestSend.mock.calls[0][0];
    expect(Object.keys(envelope.data).sort()).toEqual(SYSTEM_ENVELOPE_KEYS);
    expect(envelope.data.trigger).toBe("manual-api");
    expect(envelope.data.actor_class).toBe("system");
  });

  // AC-A3 (null variant): explicit `data: null` is treated as no-data, same as absent.
  it("treats explicit data:null as no-data (system-tier envelope) (AC-A3)", async () => {
    const res = await POST(makeRequest({ event: ALLOWED_EVENT, data: null }));
    expect(res.status).toBe(202);
    const envelope = mockInngestSend.mock.calls[0][0];
    expect(Object.keys(envelope.data).sort()).toEqual(SYSTEM_ENVELOPE_KEYS);
  });

  // AC-A4: a present-but-non-plain-object `data` is rejected 400 before dispatch.
  it("returns 400 on non-plain-object data (number / string / array), no dispatch (AC-A4)", async () => {
    for (const bad of [42, "x", ["a"], true] as const) {
      mockInngestSend.mockClear();
      mockSendInngestWithRetry.mockClear();
      const label = `data=${JSON.stringify(bad)}`;
      const res = await POST(
        makeRequest({ event: ALLOWED_EVENT, data: bad as unknown as object }),
      );
      expect(res.status, label).toBe(400);
      expect(mockSendInngestWithRetry, label).not.toHaveBeenCalled();
      expect(mockInngestSend, label).not.toHaveBeenCalled();
    }
  });

  // AC-A5: the existing 64 KiB 413-before-parse guard still covers the widened
  // body when the bulk lives in `data`.
  it("returns 413 on oversized data padding (before parse, no dispatch) (AC-A5)", async () => {
    const huge = JSON.stringify({
      event: ALLOWED_EVENT,
      data: { pad: "a".repeat(70 * 1024) },
    });
    const res = await POST(makeRequest(huge));
    expect(res.status).toBe(413);
    expect(mockSendInngestWithRetry).not.toHaveBeenCalled();
  });
});
