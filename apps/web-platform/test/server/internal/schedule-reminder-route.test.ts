import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// INNGEST_MANUAL_TRIGGER_SECRET is security-relevant — capture + restore so a
// stub/delete never leaks to a sibling file in the same worker.
const ORIG_SECRET = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
// INNGEST_CUTOVER_QUIESCE (#5450) — capture + force-OFF per test so an inherited
// Doppler/CI value cannot flip the quiesce gate (vitest unstub can't clear a
// process-inherited env var).
const ORIG_QUIESCE = process.env.INNGEST_CUTOVER_QUIESCE;

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
vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

import { POST } from "@/app/api/internal/schedule-reminder/route";

const SECRET = "schedule-reminder-test-secret";
const FIRE_AT = "2026-06-04T09:45:00Z";

function validBody() {
  return {
    reminder_id: "r-123",
    fire_at: FIRE_AT,
    actor: "platform",
    action: { type: "issue-comment", issue: 2714, body: "hi" },
  };
}

function makeRequest(
  body: object | string,
  opts: { authorization?: string | null } = {},
): Request {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const headers = new Headers({ "content-type": "application/json" });
  const auth = "authorization" in opts ? opts.authorization : `Bearer ${SECRET}`;
  if (auth !== null && auth !== undefined) headers.set("authorization", auth);
  return new Request("https://soleur.ai/api/internal/schedule-reminder", {
    method: "POST",
    headers,
    body: raw,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.INNGEST_MANUAL_TRIGGER_SECRET = SECRET;
  delete process.env.INNGEST_CUTOVER_QUIESCE;
  mockSendInngestWithRetry.mockImplementation(async (fn: () => Promise<unknown>) => {
    await fn();
  });
  mockInngestSend.mockResolvedValue({ ids: ["evt_1"] });
});

afterEach(() => {
  if (ORIG_SECRET === undefined) delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  else process.env.INNGEST_MANUAL_TRIGGER_SECRET = ORIG_SECRET;
  if (ORIG_QUIESCE === undefined) delete process.env.INNGEST_CUTOVER_QUIESCE;
  else process.env.INNGEST_CUTOVER_QUIESCE = ORIG_QUIESCE;
});

describe("POST /api/internal/schedule-reminder — cutover quiesce (#5450)", () => {
  it("503 + Retry-After and does NOT arm when INNGEST_CUTOVER_QUIESCE=1", async () => {
    process.env.INNGEST_CUTOVER_QUIESCE = "1";
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("120");
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it('also quiesces on the literal "true"', async () => {
    process.env.INNGEST_CUTOVER_QUIESCE = "true";
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("arms normally (202) when the flag is unset — proves the gate is the cause, not a broken happy path", async () => {
    // beforeEach already deletes INNGEST_CUTOVER_QUIESCE.
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(202);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });
});

describe("POST /api/internal/schedule-reminder — auth", () => {
  it("503 when secret unset", async () => {
    delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
    const res = await POST(makeRequest(validBody(), { authorization: null }));
    expect(res.status).toBe(503);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("401 on missing / wrong Bearer", async () => {
    expect((await POST(makeRequest(validBody(), { authorization: null }))).status).toBe(401);
    expect((await POST(makeRequest(validBody(), { authorization: "Bearer nope" }))).status).toBe(401);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});

describe("POST /api/internal/schedule-reminder — validation", () => {
  it("202 + emits reminder.scheduled with id + future ts on a valid request", async () => {
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ scheduled: "r-123", fire_at: FIRE_AT });
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const envelope = mockInngestSend.mock.calls[0][0];
    expect(envelope).toMatchObject({
      name: "reminder.scheduled",
      id: "r-123",
      ts: Date.parse(FIRE_AT),
    });
    expect(envelope.data.action).toEqual({ type: "issue-comment", issue: 2714, body: "hi" });
  });

  it("400 on non-allowlisted action", async () => {
    const res = await POST(makeRequest({ ...validBody(), action: { type: "label", issue: 1 } }));
    expect(res.status).toBe(400);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("400 on invalid fire_at", async () => {
    const res = await POST(makeRequest({ ...validBody(), fire_at: "not-a-date" }));
    expect(res.status).toBe(400);
  });

  it("400 on actor !== platform", async () => {
    const res = await POST(makeRequest({ ...validBody(), actor: "user" }));
    expect(res.status).toBe(400);
  });

  it("400 on missing reminder_id", async () => {
    const res = await POST(makeRequest({ ...validBody(), reminder_id: "" }));
    expect(res.status).toBe(400);
  });

  it("413 on oversize body, 400 on malformed JSON", async () => {
    const big = JSON.stringify(validBody()) + " ".repeat(64 * 1024);
    expect((await POST(makeRequest(big))).status).toBe(413);
    expect((await POST(makeRequest("{not json"))).status).toBe(400);
  });

  it("502 when dispatch fails", async () => {
    mockSendInngestWithRetry.mockRejectedValueOnce(new Error("inngest down"));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(502);
    expect(mockReportSilentFallback.mock.calls[0][1].op).toBe("dispatch");
  });
});
