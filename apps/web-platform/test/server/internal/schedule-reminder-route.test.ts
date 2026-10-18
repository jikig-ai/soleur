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
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("cutover-quiesce");
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
    expect(res.headers.get("Retry-After")).toBeNull();
    expect(mockReportSilentFallback.mock.calls[0][1].op).toBe("dispatch");
  });
});

// Cutover window (#6921 FR16): op=quiesce-web stops the scheduler the app sends
// to, so inngest.send's fetch is REFUSED until the INNGEST_BASE_URL repoint
// redeploys. Error shape captured against a closed loopback port with the
// pinned SDK (inngest 3.54.2, 2026-09-14): TypeError "fetch failed" whose
// `cause` is an Error with code ECONNREFUSED — not a top-level code.
function refusedFetchError(): TypeError {
  const cause = Object.assign(new Error("connect ECONNREFUSED 127.0.0.1:8288"), {
    code: "ECONNREFUSED",
    errno: -111,
  });
  return new TypeError("fetch failed", { cause });
}

describe("POST /api/internal/schedule-reminder — backend refusing connections", () => {
  it("503 + Retry-After (retry later) when the send is refused, still mirrored to Sentry", async () => {
    mockSendInngestWithRetry.mockRejectedValueOnce(refusedFetchError());
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("120");
    // Distinct from the INNGEST_CUTOVER_QUIESCE 503 so inngest-rearm-reminders.sh does not
    // send the operator to clear a flag that is not set.
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("backend-refused");
    expect(mockReportSilentFallback.mock.calls[0][1].op).toBe("dispatch");
  });

  it("stays 502 for a fetch failure whose cause is NOT a refusal (e.g. DNS)", async () => {
    const cause = Object.assign(new Error("getaddrinfo ENOTFOUND x"), { code: "ENOTFOUND" });
    mockSendInngestWithRetry.mockRejectedValueOnce(new TypeError("fetch failed", { cause }));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(502);
    expect(res.headers.get("Retry-After")).toBeNull();
  });

  it("503 (not 502) when the cause code is ECONNRESET, whatever the message says (#10136: a reset is retryable too)", async () => {
    const cause = Object.assign(new Error("read ECONNRESET (after ECONNREFUSED)"), { code: "ECONNRESET" });
    mockSendInngestWithRetry.mockRejectedValueOnce(new TypeError("fetch failed", { cause }));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("120");
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("backend-refused");
  });

  it("stays 502 for a non-TypeError whose cause carries code ECONNREFUSED", async () => {
    const err = Object.assign(new Error("wrapped"), { cause: { code: "ECONNREFUSED" } });
    mockSendInngestWithRetry.mockRejectedValueOnce(err);
    expect((await POST(makeRequest(validBody()))).status).toBe(502);
  });

  it("stays 502 for a non-TypeError carrying ECONNREFUSED text only in its message", async () => {
    mockSendInngestWithRetry.mockRejectedValueOnce(new Error("upstream said ECONNREFUSED"));
    expect((await POST(makeRequest(validBody()))).status).toBe(502);
  });
});

// #10136 (CTO G4): the verified-TLS link adds failure modes the refusal branch did not cover. Each of these is a
// "scheduler unreachable or unverifiable right now, nothing persisted" outcome, so the caller (inngest-rearm-reminders.sh,
// which aborts on X-Soleur-Unavailable: backend-refused) must see a retryable 503 rather than a terminal-looking 502 and
// keep going past a lost arm. Error shapes are synthesized: TypeError("fetch failed") with the code on `cause`.
function fetchFailedWith(code: string, message = `synthetic ${code}`): TypeError {
  return new TypeError("fetch failed", { cause: Object.assign(new Error(message), { code }) });
}

describe("POST /api/internal/schedule-reminder — timeout and TLS-verification causes are retryable (503)", () => {
  it.each([
    "ECONNREFUSED",
    "ETIMEDOUT",
    "ECONNRESET",
    "UND_ERR_CONNECT_TIMEOUT",
    "ERR_TLS_CERT_ALTNAME_INVALID",
    "ERR_TLS_HANDSHAKE_TIMEOUT",
    "ERR_TLS_INVALID_PROTOCOL_VERSION",
    "DEPTH_ZERO_SELF_SIGNED_CERT",
    "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  ])("%s -> 503 + Retry-After + X-Soleur-Unavailable: backend-refused, mirrored to Sentry", async (code) => {
    mockSendInngestWithRetry.mockRejectedValueOnce(fetchFailedWith(code));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("120");
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("backend-refused");
    expect(mockReportSilentFallback.mock.calls[0][1].op).toBe("dispatch");
  });

  it.each(["ENOTFOUND", "EAI_AGAIN", "EPIPE", "ERR_TLSX", "ERR_TLS", "err_tls_cert", "CERT_HAS_EXPIRED", ""])(
    "%s stays 502 (only the listed causes are retryable; ERR_TLS_ needs its underscore and exact case)",
    async (code) => {
      mockSendInngestWithRetry.mockRejectedValueOnce(fetchFailedWith(code));
      const res = await POST(makeRequest(validBody()));
      expect(res.status).toBe(502);
      expect(res.headers.get("Retry-After")).toBeNull();
      expect(res.headers.get("X-Soleur-Unavailable")).toBeNull();
    },
  );

  it("stays 502 for a retryable code on something that is not a TypeError, or with no object cause", async () => {
    mockSendInngestWithRetry.mockRejectedValueOnce(Object.assign(new Error("wrapped"), { cause: { code: "ETIMEDOUT" } }));
    expect((await POST(makeRequest(validBody()))).status).toBe(502);
    mockSendInngestWithRetry.mockRejectedValueOnce(new TypeError("fetch failed: ETIMEDOUT"));
    expect((await POST(makeRequest(validBody()))).status).toBe(502);
    mockSendInngestWithRetry.mockRejectedValueOnce(new TypeError("fetch failed", { cause: "ETIMEDOUT" }));
    expect((await POST(makeRequest(validBody()))).status).toBe(502);
  });

  it("a successful send is untouched (202, no Retry-After)", async () => {
    mockSendInngestWithRetry.mockResolvedValueOnce(undefined);
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(202);
    expect(res.headers.get("Retry-After")).toBeNull();
  });
});
