import { readFileSync } from "node:fs";
import { resolve } from "node:path";
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
// "scheduler unreachable or unverifiable right now" outcome, so the caller (inngest-rearm-reminders.sh, which aborts on
// X-Soleur-Unavailable: backend-refused) must see a retryable 503 rather than a terminal-looking 502 and keep going past a lost
// arm. The send may have been persisted (a reset after the request left is ambiguous): the event id is the reminder id, so the
// re-arm is deduplicated. Error shapes are synthesized: TypeError("fetch failed") with the code on `cause`.
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
    "SELF_SIGNED_CERT_IN_CHAIN",
    "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
    "CERT_HAS_EXPIRED",
    "UND_ERR_SOCKET",
    "EHOSTUNREACH",
    "ENETUNREACH",
  ])("%s -> 503 + Retry-After + X-Soleur-Unavailable: backend-refused, mirrored to Sentry", async (code) => {
    mockSendInngestWithRetry.mockRejectedValueOnce(fetchFailedWith(code));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("120");
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("backend-refused");
    expect(mockReportSilentFallback.mock.calls[0][1].op).toBe("dispatch");
  });

  it.each(["ENOTFOUND", "EAI_AGAIN", "EPIPE", "ERR_TLSX", "ERR_TLS", "err_tls_cert", "UND_ERR_BODY_TIMEOUT", ""])(
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

  // One list, two consumers: the host canary's negative control (INNGEST_LINK_CANARY_NEG in ci-deploy.sh) accepts a fixed set of codes as
  // "certificate verification failed". Two directions are pinned, both derived from SOURCE: (1) the route answers every one of those
  // codes with the retryable 503 (below), and (2) the route's own retryable set is EXACTLY (the canary's codes that are not ERR_TLS_*,
  // which the route covers by prefix) + the listed transport codes + CERT_HAS_EXPIRED, so a code added to the route alone, or dropped
  // from either side, turns this red.
  const CI_DEPLOY = resolve(__dirname, "../../../../../apps/web-platform/infra/ci-deploy.sh");
  const canaryVerifyCodes = (): string[] => {
    const line = readFileSync(CI_DEPLOY, "utf8")
      .split("\n")
      .find((l) => l.startsWith("INNGEST_LINK_CANARY_NEG="));
    const m = line?.match(/\/\^\(([A-Z_|]+)\)\$\/\.test\(c\)/);
    return m ? m[1].split("|") : [];
  };
  it("derives a non-trivial verification-code list from the canary negative control (the parity test below is not vacuous)", () => {
    const codes = canaryVerifyCodes();
    expect(codes.length).toBeGreaterThanOrEqual(5);
    expect(codes).toContain("DEPTH_ZERO_SELF_SIGNED_CERT");
    expect(codes).toContain("ERR_TLS_CERT_ALTNAME_INVALID");
  });
  it("the route's retryable set equals the canary verification codes (minus the ERR_TLS_ prefix family) plus the transport codes", () => {
    const src = readFileSync(resolve(__dirname, "../../../app/api/internal/schedule-reminder/route.ts"), "utf8");
    const block = src.match(/const UNAVAILABLE_CAUSE_CODES = new Set\(\[([^\]]*)\]\)/)?.[1] ?? "";
    const routeCodes = [...block.matchAll(/"([A-Z0-9_]+)"/g)].map((m) => m[1]).sort();
    const TRANSPORT = ["ECONNREFUSED", "ETIMEDOUT", "ECONNRESET", "UND_ERR_CONNECT_TIMEOUT", "UND_ERR_SOCKET", "EHOSTUNREACH", "ENETUNREACH", "CERT_HAS_EXPIRED"];
    const expected = [...new Set([...canaryVerifyCodes().filter((c) => !c.startsWith("ERR_TLS_")), ...TRANSPORT])].sort();
    expect(routeCodes.length).toBeGreaterThanOrEqual(10);
    expect(routeCodes).toEqual(expected);
  });
  it.each(canaryVerifyCodes())("canary verification code %s -> the route answers the retryable 503", async (code) => {
    mockSendInngestWithRetry.mockRejectedValueOnce(fetchFailedWith(code));
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(res.headers.get("X-Soleur-Unavailable")).toBe("backend-refused");
  });

  it("a re-arm after an ambiguous reset carries the SAME event id (= reminder_id), so Inngest deduplicates a send that did persist", async () => {
    mockSendInngestWithRetry.mockImplementationOnce(async (fn: () => Promise<unknown>) => {
      await fn();
      throw fetchFailedWith("ECONNRESET");
    });
    const first = await POST(makeRequest(validBody()));
    expect(first.status).toBe(503);
    const second = await POST(makeRequest(validBody()));
    expect(second.status).toBe(202);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    const ids = mockInngestSend.mock.calls.map((c) => c[0].id);
    expect(ids).toEqual(["r-123", "r-123"]);
  });

  it("a successful send is untouched (202, no Retry-After)", async () => {
    mockSendInngestWithRetry.mockResolvedValueOnce(undefined);
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(202);
    expect(res.headers.get("Retry-After")).toBeNull();
  });
});
