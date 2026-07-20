// TR9 PR-3 (#4211) — cron-oauth-probe handler unit tests.
//
// Covers AC17: happy path, per-failure-mode `?status=error` mapping,
// fork-PR fallback (SENTRY_INGEST_DOMAIN empty), issue-filing branch via
// mocked Octokit. All fetches stubbed — no real network calls.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  mirrorWarnWithDebounce: vi.fn(),
  reportSilentFallback: reportSilentFallbackSpy,
}));

// Octokit mock used by handleTrackingIssue. Tracked across calls; reset
// in beforeEach.
const octokitRequestSpy = vi.fn();
vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: vi.fn(async () => ({ request: octokitRequestSpy })),
}));

// Mock for the canonical resolver `resolveSupabaseRef` (the handler now
// imports from @/lib/supabase/resolve-ref instead of inlining a node:dns
// call). The spy returns the canonical happy-path ref; per-test overrides
// drive the drift scenario.
const resolveSupabaseRefSpy = vi.fn(
  async (_url: string): Promise<string | null> => "ifsccnjhymdmidffkzhl",
);
vi.mock("@/lib/supabase/resolve-ref", () => ({
  resolveSupabaseRef: resolveSupabaseRefSpy,
}));

// --- Helpers ---------------------------------------------------------------

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

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Healthy response factories. Each probe step has a distinct expected
// shape; the per-URL responder below routes by URL substring.
const healthyLoginResponse = () =>
  new Response("", { status: 200 });

const healthyRedirect302 = (location: string) =>
  new Response("", { status: 302, headers: { location } });

const healthyGithubAuthorizePage = () =>
  new Response(
    '<html><body><form action="/session" method="post"><input name="authenticity_token" value="abc" /></form></body></html>',
    { status: 200 },
  );

const healthySettings = () =>
  new Response(JSON.stringify({ external: { google: true, github: true } }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });

const healthyCallbackPassthrough = () =>
  new Response("", {
    status: 302,
    headers: { location: "https://app.soleur.ai/login?error=oauth_cancelled" },
  });

// Defaults: route fetch by URL substring to a healthy response. Order is
// load-bearing — the github authorize URL contains the substring "/login"
// (`github.com/login/oauth/authorize`), so the github branch MUST precede
// the generic `/login` branch.
function defaultFetch(input: RequestInfo | URL): Promise<Response> {
  const url = typeof input === "string" ? input : (input as URL).toString();
  if (url.startsWith("https://github.com/login/oauth/authorize"))
    return Promise.resolve(healthyGithubAuthorizePage());
  if (url.includes("/auth/v1/authorize?provider=google"))
    return Promise.resolve(healthyRedirect302("https://accounts.google.com/o/oauth2/auth?..."));
  if (url.includes("/auth/v1/authorize?provider=github"))
    return Promise.resolve(
      healthyRedirect302("https://github.com/login/oauth/authorize?client_id=abc"),
    );
  if (url.includes("/callback?error=access_denied"))
    return Promise.resolve(healthyCallbackPassthrough());
  if (url.includes("/auth/v1/settings"))
    return Promise.resolve(healthySettings());
  if (url.endsWith("/login")) return Promise.resolve(healthyLoginResponse());
  // Host-based routing — CodeQL js/incomplete-url-substring-sanitization
  // (high severity) flags `.includes("api.resend.com")` because
  // `attacker.api.resend.com.evil` would match. Parse the host instead.
  let host = "";
  try { host = new URL(url).host; } catch { /* malformed URL — fall through */ }
  if (host === "api.resend.com") return Promise.resolve(new Response("{}", { status: 200 }));
  if (host.endsWith(".sentry.io") && url.includes("/api/")) return Promise.resolve(new Response("", { status: 202 }));
  return Promise.resolve(new Response("", { status: 200 }));
}

const ORIGINAL_ENV = {
  SENTRY_INGEST_DOMAIN: process.env.SENTRY_INGEST_DOMAIN,
  SENTRY_PROJECT_ID: process.env.SENTRY_PROJECT_ID,
  SENTRY_PUBLIC_KEY: process.env.SENTRY_PUBLIC_KEY,
  APP_HOST: process.env.APP_HOST,
  API_HOST: process.env.API_HOST,
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY,
  OAUTH_PROBE_GITHUB_CLIENT_ID: process.env.OAUTH_PROBE_GITHUB_CLIENT_ID,
  SUPABASE_PROJECT_REF: process.env.SUPABASE_PROJECT_REF,
  GITHUB_APP_ID: process.env.GITHUB_APP_ID,
  GITHUB_APP_PRIVATE_KEY: process.env.GITHUB_APP_PRIVATE_KEY,
  RESEND_API_KEY: process.env.RESEND_API_KEY,
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

beforeEach(() => {
  vi.resetModules();
  reportSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  // search → no existing tracking issue by default
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route === "GET /search/issues") return { data: { items: [] } };
    return { data: {} };
  });
  resolveSupabaseRefSpy.mockReset();
  resolveSupabaseRefSpy.mockResolvedValue("ifsccnjhymdmidffkzhl");
  logger.info.mockReset();
  logger.warn.mockReset();
  logger.error.mockReset();
  vi.stubGlobal("fetch", vi.fn(defaultFetch));
  process.env.SENTRY_INGEST_DOMAIN = "ingest.sentry.io";
  process.env.SENTRY_PROJECT_ID = "999";
  process.env.SENTRY_PUBLIC_KEY = "abc123def4567890abc123def4567890";
  process.env.APP_HOST = "app.soleur.ai";
  process.env.API_HOST = "api.soleur.ai";
  process.env.SUPABASE_ANON_KEY = "eyJhbGciOi.dummy.anon";
  process.env.OAUTH_PROBE_GITHUB_CLIENT_ID = "Iv23li9p88M5ZxYv1b7V";
  process.env.SUPABASE_PROJECT_REF = "ifsccnjhymdmidffkzhl";
  process.env.GITHUB_APP_ID = "12345";
  process.env.GITHUB_APP_PRIVATE_KEY = "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----";
  process.env.RESEND_API_KEY = "re_test_key";
  process.env.INNGEST_SIGNING_KEY = "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  process.env.INNGEST_DEV = "1";
});

afterEach(() => {
  vi.unstubAllGlobals();
  (Object.keys(ORIGINAL_ENV) as Array<keyof typeof ORIGINAL_ENV>).forEach(restoreEnv);
});

async function importHandler() {
  const mod = await import("@/server/inngest/functions/cron-oauth-probe");
  return mod;
}

// Search for the heartbeat POST inside the recorded fetch calls.
function findHeartbeatStatus(fetchSpy: ReturnType<typeof vi.fn>): "ok" | "error" | null {
  for (const call of fetchSpy.mock.calls) {
    const url = call[0];
    if (typeof url !== "string") continue;
    let host = "";
    try { host = new URL(url).host; } catch { /* skip malformed */ }
    if (host.endsWith(".sentry.io") && url.includes("/cron/scheduled-oauth-probe/")) {
      if (url.endsWith("?status=ok")) return "ok";
      if (url.endsWith("?status=error")) return "error";
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("cronOauthProbeHandler — happy path", () => {
  it("emits ?status=ok heartbeat when every probe passes", async () => {
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("ok");
    // No tracking issue created on green.
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(0);
    // Notify-ops-email skipped on green.
    const resendCalls = fetchSpy.mock.calls.filter(
      ([url]) => {
        if (typeof url !== "string") return false;
        try { return new URL(url).host === "api.resend.com"; } catch { return false; }
      },
    );
    expect(resendCalls.length).toBe(0);
  });

  it("step ordering: probe → issue-handling → sentry-heartbeat (no notify on green)", async () => {
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    await cronOauthProbeHandler({ step, logger });
    const names = step.calls.map((c) => c.name);
    expect(names).toEqual(["probe", "issue-handling", "sentry-heartbeat"]);
  });
});

describe("cronOauthProbeHandler — failure modes", () => {
  function stubFetchSequence(handler: (url: string) => Response | null) {
    const fallback = vi.fn(defaultFetch);
    vi.stubGlobal(
      "fetch",
      vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
        const url = typeof input === "string" ? input : (input as URL).toString();
        const override = handler(url);
        if (override) return Promise.resolve(override);
        return fallback(input);
      }),
    );
  }

  it("login_unreachable → ?status=error and tracking issue created", async () => {
    stubFetchSequence((url) =>
      url === "https://app.soleur.ai/login"
        ? new Response("server down", { status: 503 })
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("login_unreachable");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
    const issueCreates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(issueCreates.length).toBe(1);
    expect(issueCreates[0]![1]).toMatchObject({
      title: "[ci/auth-broken] Synthetic OAuth probe failed",
      labels: ["ci/auth-broken", "priority/p1-high"],
    });
    // Notify-ops-email fires on failure.
    const resendCalls = fetchSpy.mock.calls.filter(
      ([u]) => {
        if (typeof u !== "string") return false;
        try { return new URL(u).host === "api.resend.com"; } catch { return false; }
      },
    );
    expect(resendCalls.length).toBe(1);
  });

  it("network_error on /login → ?status=error", async () => {
    stubFetchSequence((url) => {
      if (url === "https://app.soleur.ai/login")
        throw new Error("ECONNREFUSED");
      return null;
    });
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("network_error");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
  });

  it("google_authorize → ?status=error when 302 lands on wrong host", async () => {
    stubFetchSequence((url) =>
      url.includes("/auth/v1/authorize?provider=google")
        ? new Response("", {
            status: 302,
            headers: { location: "https://attacker.example.com/oauth" },
          })
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("google_authorize");
  });

  it("github_authorize → ?status=error when 302 lands on wrong host", async () => {
    stubFetchSequence((url) =>
      url.includes("/auth/v1/authorize?provider=github")
        ? new Response("", {
            status: 302,
            headers: { location: "https://malicious.example.com/oauth" },
          })
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("github_authorize");
  });

  it("github_oauth_<label>_unregistered → ?status=error on redirect_uri rejection", async () => {
    stubFetchSequence((url) =>
      url.startsWith("https://github.com/login/oauth/authorize")
        ? new Response(
            "<html><body>The redirect_uri is not associated with this application.</body></html>",
            { status: 200 },
          )
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("github_oauth_github_resolve_unregistered");
  });

  it("github_app_suspended → ?status=error on suspended sentinel", async () => {
    stubFetchSequence((url) =>
      url.startsWith("https://github.com/login/oauth/authorize")
        ? new Response(
            "<html><body><h1>Application suspended</h1></body></html>",
            { status: 200 },
          )
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("github_app_suspended");
  });

  it("supabase_project_ref_drift → ?status=error when CNAME ref differs from env", async () => {
    resolveSupabaseRefSpy.mockResolvedValue("differentref99999999");
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("supabase_project_ref_drift");
  });

  it("settings_provider_disabled → ?status=error when google not enabled", async () => {
    stubFetchSequence((url) =>
      url.includes("/auth/v1/settings")
        ? new Response(JSON.stringify({ external: { google: false, github: true } }), {
            status: 200,
            headers: { "content-type": "application/json" },
          })
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("settings_provider_disabled");
  });

  it("callback_error_passthrough → ?status=error when redirect target wrong", async () => {
    stubFetchSequence((url) =>
      url.includes("/callback?error=access_denied")
        ? new Response("", {
            status: 302,
            headers: { location: "https://app.soleur.ai/login?error=auth_failed" },
          })
        : null,
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("callback_error_passthrough");
  });
});

describe("cronOauthProbeHandler — fork-PR fallback", () => {
  it("logs warning + does not throw when SENTRY_INGEST_DOMAIN is empty", async () => {
    delete process.env.SENTRY_INGEST_DOMAIN;
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    await expect(
      cronOauthProbeHandler({ step, logger }),
    ).resolves.toBeDefined();
    expect(logger.info).toHaveBeenCalled();
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe(null);
  });
});

describe("cronOauthProbeHandler — issue-filing branch", () => {
  it("comments on existing tracking issue instead of creating a new one", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 4242 }] } };
      return { data: {} };
    });
    // Trigger a failure (login_unreachable).
    vi.stubGlobal(
      "fetch",
      vi.fn((input: RequestInfo | URL) => {
        const url = typeof input === "string" ? input : (input as URL).toString();
        if (url === "https://app.soleur.ai/login")
          return Promise.resolve(new Response("down", { status: 503 }));
        return defaultFetch(input);
      }),
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    await cronOauthProbeHandler({ step, logger });
    const comments = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    const creates = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "POST /repos/{owner}/{repo}/issues",
    );
    expect(comments.length).toBe(1);
    expect(comments[0]![1]).toMatchObject({ issue_number: 4242 });
    expect(creates.length).toBe(0);
  });

  it("403 on POST /issues → reportSilentFallback op=issue_write_403 (#4189)", async () => {
    // Same blind spot as the drift-guard: createProbeOctokit() is
    // installation-scoped and 403s on issue writes when the App lacks
    // issues:write. The catch must discriminate the 403 so the operator can
    // alert-route on the missing grant.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") return { data: { items: [] } };
      if (route === "POST /repos/{owner}/{repo}/issues") {
        const err = new Error(
          "Resource not accessible by integration",
        ) as Error & { status?: number };
        err.status = 403;
        throw err;
      }
      return { data: {} };
    });
    // Trigger a failure (login_unreachable) so the issue-filing path runs.
    vi.stubGlobal(
      "fetch",
      vi.fn((input: RequestInfo | URL) => {
        const url = typeof input === "string" ? input : (input as URL).toString();
        if (url === "https://app.soleur.ai/login")
          return Promise.resolve(new Response("down", { status: 503 }));
        return defaultFetch(input);
      }),
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    const out = await cronOauthProbeHandler({ step, logger });
    expect(out.failureMode).toBe("login_unreachable");
    const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
    expect(findHeartbeatStatus(fetchSpy)).toBe("error");
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "issue_write_403",
    );
    expect(call).toBeDefined();
    expect((call![1] as { message: string }).message).toBe(
      "GitHub tracking-issue file/comment/close failed",
    );
  });

  it("non-403 issue-write error preserves op=handleTrackingIssue", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues") return { data: { items: [] } };
      if (route === "POST /repos/{owner}/{repo}/issues") {
        const err = new Error("Server error") as Error & { status?: number };
        err.status = 500;
        throw err;
      }
      return { data: {} };
    });
    vi.stubGlobal(
      "fetch",
      vi.fn((input: RequestInfo | URL) => {
        const url = typeof input === "string" ? input : (input as URL).toString();
        if (url === "https://app.soleur.ai/login")
          return Promise.resolve(new Response("down", { status: 503 }));
        return defaultFetch(input);
      }),
    );
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    await cronOauthProbeHandler({ step, logger });
    const call = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string })?.op === "handleTrackingIssue",
    );
    expect(call).toBeDefined();
  });

  it("closes the stale tracking issue on probe-green recovery", async () => {
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /search/issues")
        return { data: { items: [{ number: 7777 }] } };
      return { data: {} };
    });
    const { cronOauthProbeHandler } = await importHandler();
    const step = makeStep();
    await cronOauthProbeHandler({ step, logger });
    const patches = octokitRequestSpy.mock.calls.filter(
      ([route]) => route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(patches.length).toBe(1);
    expect(patches[0]![1]).toMatchObject({ issue_number: 7777, state: "closed" });
  });

  it("buildIssueBody includes the required callback URL block on _unregistered failures", async () => {
    const { __TESTING__ } = await importHandler();
    const body = __TESTING__.buildIssueBody({
      failureMode: "github_oauth_supabase_custom_unregistered",
      failureDetail: "test detail",
      detectedAtIso: "2026-05-21T12:00:00.000Z",
      runUrl: "https://example/run/1",
      runbookUrl: "https://example/runbook",
    });
    expect(body).toContain("Required GitHub App callback URLs");
    expect(body).toContain("https://app.soleur.ai/api/auth/github-resolve/callback");
    expect(body).toContain("https://api.soleur.ai/auth/v1/callback");
    expect(body).toContain("https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback");
  });

  it("buildIssueBody omits the callback URL block on non-callback failures", async () => {
    const { __TESTING__ } = await importHandler();
    const body = __TESTING__.buildIssueBody({
      failureMode: "settings_provider_disabled",
      failureDetail: "external.google=false",
      detectedAtIso: "2026-05-21T12:00:00.000Z",
      runUrl: "https://example/run/1",
      runbookUrl: "https://example/runbook",
    });
    expect(body).not.toContain("Required GitHub App callback URLs");
  });
});

describe("cronOauthProbeHandler — registration", () => {
  it("function id is cron-oauth-probe", async () => {
    const mod = await importHandler();
    // Inngest InngestFunction wraps id in `.id()` method on the returned
    // object; access via the (untyped) opts surface.
    const fn = mod.cronOauthProbe as unknown as { id: () => string; opts: { id: string } };
    const id = typeof fn.id === "function" ? fn.id() : fn.opts.id;
    expect(id).toContain("cron-oauth-probe");
  });
});
