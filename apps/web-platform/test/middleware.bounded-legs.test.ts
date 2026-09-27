// middleware.bounded-legs.test.ts — #8978 residual cold tiers: every remote
// Supabase leg on the authenticated path carries a bounded wait, and each
// bound lands on a PRE-EXISTING verdict arm (Guard Contract Guard 1).
// Mock shapes mirror middleware.test.ts; abortSignal is honoured the way
// postgrest-js does — the builder's abort resolves as an error OBJECT
// ({hint: "Request was aborted (timeout or manual cancellation)"}), never a
// rejection.
import { readFileSync } from "fs";
import { resolve } from "path";
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";

const {
  mockGetUser,
  mockGetSession,
  mockRpc,
  mockFrom,
  mockReportEdgeSilentFallback,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
  mockReportEdgeSilentFallback: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
    rpc: (...args: unknown[]) => {
      const r = mockRpc(...args) as
        | { abortSignal?: unknown }
        | Promise<unknown>;
      return r &&
        typeof (r as { abortSignal?: unknown }).abortSignal === "function"
        ? r
        : { abortSignal: () => r };
    },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: mockReportEdgeSilentFallback,
}));

import { middleware } from "@/middleware";
import { TC_VERSION } from "@/lib/legal/tc-version";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";

// postgrest-js's settled abort shape (PostgrestBuilder then-catch, the
// !shouldThrowOnError arm): an abort resolves to an error OBJECT.
const ABORT_ERROR_RESULT = {
  data: null,
  error: {
    message: "TimeoutError: The operation timed out.",
    details: "",
    hint: "Request was aborted (timeout or manual cancellation)",
    code: "",
  },
  count: null,
  status: 0,
  statusText: "",
};

let credSeq = 0;
function freshCreds() {
  credSeq += 1;
  return {
    userId: `00000000-0000-0000-0000-${String(credSeq).padStart(12, "0")}`,
    iat: 1_700_000_000 + credSeq * 60,
  };
}

function makeJwt(iatSeconds: number, sub: string): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  return `${b64({ alg: "ES256", typ: "JWT" })}.${b64({ iat: iatSeconds, sub, aud: "authenticated" })}.sig`;
}

function makeAuthRequest(pathname: string): NextRequest {
  return new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai" },
  });
}

function seedAuth(userId: string, iat: number) {
  mockGetUser.mockResolvedValue({
    data: { user: { id: userId, email: `${userId}@example.com` } },
    error: null,
  });
  mockGetSession.mockResolvedValue({
    data: {
      session: { access_token: makeJwt(iat, userId), user: { id: userId } },
    },
    error: null,
  });
}

function seedTcOk() {
  const single = vi.fn().mockResolvedValue({
    data: { tc_accepted_version: TC_VERSION, subscription_status: "active" },
    error: null,
  });
  const eq = vi
    .fn()
    .mockReturnValue({ single, abortSignal: vi.fn(() => ({ single })) });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
  return { single };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", SUPABASE_ANON_KEY);
  vi.stubEnv("SOLEUR_MW_RPC_TIMEOUT_MS", "60");
  vi.stubEnv("SOLEUR_MW_AUTH_TIMEOUT_MS", "60");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("bounded Supabase legs (Guard 1)", () => {
  test("must-PASS: a fast healthy RPC resolves normally and caches the positive verdict", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcOk();

    const res = await middleware(makeAuthRequest("/dashboard"));
    // Pass-through contract directly: no redirect AT ALL — `not.toBe(302)`
    // would still pass a wrong 307 bounce (the only 302 is the revoked one).
    expect(res.headers.get("location")).toBeNull();
    // Second request: verdict cache hit preempts the RPC entirely.
    await middleware(makeAuthRequest("/dashboard"));
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });

  test("a stalled revocation RPC lands in grace — never writes the verdict cache, proceeds, reports op=rpc_timeout", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    // Never-resolving until the armed AbortSignal fires — resolves with
    // postgrest's abort-shaped error object (no rejection, matching the
    // installed postgrest-js !shouldThrowOnError then-catch).
    mockRpc.mockReturnValue({
      abortSignal: (signal: AbortSignal) =>
        new Promise((res) =>
          signal.addEventListener("abort", () => res(ABORT_ERROR_RESULT)),
        ),
    });
    seedTcOk();

    const res = await middleware(makeAuthRequest("/dashboard"));
    expect(res.headers.get("location")).toBeNull();

    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "revocation_gate.rpc_timeout",
    );
    expect(calls.length).toBe(1);

    // No verdict was cached — a second request issues a SECOND RPC.
    await middleware(makeAuthRequest("/dashboard"));
    expect(mockRpc).toHaveBeenCalledTimes(2);
  });

  test("a stalled T&C users select lands on the fail-closed arm → /accept-terms?error=db_unavailable", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    const abortSingle = (signal: AbortSignal) => ({
      single: vi.fn(
        () =>
          new Promise((res) =>
            signal.addEventListener("abort", () => res(ABORT_ERROR_RESULT)),
          ),
      ),
    });
    const eq = vi
      .fn()
      .mockReturnValue({ abortSignal: vi.fn((s: AbortSignal) => abortSingle(s)) });
    const select = vi.fn().mockReturnValue({ eq });
    mockFrom.mockReturnValue({ select });

    const res = await middleware(makeAuthRequest("/dashboard"));
    // redirectWithCookies → NextResponse.redirect default (307); the
    // load-bearing assertion is the destination, not the status code.
    expect(res.headers.get("location") ?? "").toContain(
      "/accept-terms?error=db_unavailable",
    );
  });

  test("a stalled getUser() lands on the !user arm → /login redirect + mw_auth.timeout report", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockGetUser.mockReturnValue(new Promise(() => {})); // never resolves
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcOk();

    const res = await middleware(makeAuthRequest("/dashboard"));
    expect(res.headers.get("location") ?? "").toContain("/login");
    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "mw_auth.timeout",
    );
    expect(calls.length).toBe(1);
  });

  test("dedup: 6 concurrent cold misses on the same (sub,iat) issue exactly ONE RPC", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    let resolveRpc!: (v: unknown) => void;
    const gate = new Promise<unknown>((res) => {
      resolveRpc = res;
    });
    mockRpc.mockReturnValue({
      abortSignal: () => gate,
    });
    seedTcOk();

    const pending = Promise.all(
      Array.from({ length: 6 }, () => middleware(makeAuthRequest("/dashboard"))),
    );
    // Let every request reach the revocation-miss join before the RPC settles.
    await vi.waitFor(() => {
      expect(mockRpc).toHaveBeenCalled();
    });
    resolveRpc({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    const results = await pending;

    for (const res of results)
      expect(res.headers.get("location")).toBeNull();
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });

  test("dedup joiner bound: a never-settling shared promise resolves grace with op=dedup_joiner_timeout", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    // The leader's abortSignal returns a promise that NEVER resolves —
    // not even on abort — the worst case the joiner bound exists for.
    mockRpc.mockReturnValue({
      abortSignal: () => new Promise(() => {}),
    });
    seedTcOk();

    // The LEADER still waits on the shared promise — only joiners carry
    // the independent bound — so its middleware call stays pending (the
    // documented leader-side residual: the leader's own bound is the
    // postgrest abort, which this mock deliberately ignores).
    const leader = middleware(makeAuthRequest("/dashboard"));
    void leader;
    const results = await Promise.all([
      middleware(makeAuthRequest("/dashboard")),
      middleware(makeAuthRequest("/dashboard")),
    ]);
    for (const res of results)
      expect(res.headers.get("location")).toBeNull();
    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) =>
        (c[1] as { op?: string }).op ===
        "revocation_gate.dedup_joiner_timeout",
    );
    expect(calls.length).toBe(2);
  });

  test("a stalled getSession() is bounded — revocation skipped, request proceeds, op=session_get.timeout", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockGetSession.mockReturnValue(new Promise(() => {})); // never resolves
    seedTcOk();

    const res = await middleware(makeAuthRequest("/dashboard"));
    expect(res.headers.get("location")).toBeNull();
    // getUser() still verifies — the session leg timing out must not
    // bounce the request.
    expect(mockGetUser).toHaveBeenCalledTimes(1);
    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "session_get.timeout",
    );
    expect(calls.length).toBe(1);
  });

  test("grace strikes escalate: a sustained outage fails closed past the strike limit", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    // Every RPC resolves a transient error — the sustained-outage shape the
    // strike counter exists for (grace is never verdict-cached, so each
    // request re-issues: RPCs == requests).
    mockRpc.mockReturnValue({
      abortSignal: () =>
        Promise.resolve({
          data: null,
          error: { message: "boom", hint: "", code: "500", details: "" },
        }),
    });
    seedTcOk();

    // The first MW_GRACE_STRIKE_LIMIT-1 landings all proceed (fail-open
    // preserved within the window).
    for (let i = 0; i < 19; i++) {
      const r = await middleware(makeAuthRequest("/dashboard"));
      expect(r.headers.get("location")).toBeNull();
    }
    // The 20th escalates — /login with the session PRESERVED (deny now,
    // not clearSession: credentials are not destroyed during an outage).
    const res = await middleware(makeAuthRequest("/dashboard"));
    expect(res.headers.get("location") ?? "").toContain("/login");
    expect(res.headers.get("location") ?? "").toContain(
      "revocation_unavailable",
    );
    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) =>
        (c[1] as { op?: string }).op ===
        "revocation_gate.grace_window_exceeded",
    );
    expect(calls.length).toBe(1);
  });

  test("dedup entry is removed on settle — a post-settle cache-cold request issues a fresh RPC", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    // Grace outcome (error result) → no verdict-cache write, so the next
    // request re-misses. If the in-flight entry were NOT removed on settle,
    // the second request would join a settled promise and issue no RPC.
    mockRpc.mockReturnValue({
      abortSignal: () =>
        Promise.resolve({
          data: null,
          error: { message: "boom", hint: "", code: "500", details: "" },
        }),
    });
    seedTcOk();

    await middleware(makeAuthRequest("/dashboard"));
    await middleware(makeAuthRequest("/dashboard"));
    expect(mockRpc).toHaveBeenCalledTimes(2);
    // Non-abort-shaped errors report transient_grace — the arm the abort
    // detector must NOT conflate with its own timeout op.
    const calls = mockReportEdgeSilentFallback.mock.calls.filter(
      (c) =>
        (c[1] as { op?: string }).op === "revocation_gate.transient_grace",
    );
    expect(calls.length).toBe(2);
  });
});

describe("Guard 1 row 4 — bounded-call-site census (source-level)", () => {
  // The census pins the COMPLETE remote-Supabase call-site set on the
  // /dashboard request path; an added unbounded call fails here.
  const mwSrc = readFileSync(resolve(__dirname, "../middleware.ts"), "utf-8");
  const idSrc = readFileSync(
    resolve(__dirname, "../lib/feature-flags/identity.ts"),
    "utf-8",
  );

  function boundedCallSites(src: string): { total: number; bounded: number } {
    // Strip line comments so a `.rpc(`/`.from(` mentioned in prose cannot
    // satisfy the census (cq-assert-anchor-not-bare-token — a body-grep must
    // anchor on a call form a comment cannot produce).
    const code = src
      .split("\n")
      .map((l) => l.replace(/\/\/.*$/, ""))
      .join("\n");
    // Each `.rpc(`/`.from(` opens a remote call; the chain must reach
    // `.abortSignal(` before its terminal (`.single(` / `.maybeSingle(` /
    // the statement's `;`). Whitespace-tolerant: supabase-rooted calls are
    // routinely split across lines (`supabase\n  .rpc(...)`).
    let total = 0;
    let bounded = 0;
    for (const m of code.matchAll(/\.(?:rpc|from)\(\s*["'`]/g)) {
      total += 1;
      const rest = code.slice(m.index!, m.index! + 900);
      const abortIdx = rest.indexOf(".abortSignal(");
      const terminalIdx = rest.search(/\.single\(|\.maybeSingle\(|;/);
      if (abortIdx !== -1 && (terminalIdx === -1 || abortIdx < terminalIdx)) {
        bounded += 1;
      }
    }
    return { total, bounded };
  }

  test("middleware.ts: every supabase.rpc/.from call on the auth path is bounded; getUser is raced", () => {
    const { total, bounded } = boundedCallSites(mwSrc);
    // Exact set today: rpc("check_my_revocation") + the T&C users select.
    expect(total).toBe(2);
    expect(bounded).toBe(2);
    // mw-auth's bound is a Promise.race (gotrue exposes no abortSignal).
    expect(mwSrc).toContain("Promise.race(");
    expect(mwSrc).toContain("mwAuthTimeoutMs()");
  });

  test("identity.ts: both resolveIdentity selects are bounded", () => {
    const { total, bounded } = boundedCallSites(idSrc);
    expect(total).toBe(2);
    expect(bounded).toBe(2);
    expect(idSrc).toContain("identitySelectTimeoutMs()");
  });
});
