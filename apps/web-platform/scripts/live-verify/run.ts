// scripts/live-verify/run.ts
//
// Autonomous post-deploy live-verification harness (#5452). Drives the DEPLOYED
// app under a dedicated synthetic prod Supabase principal to catch the
// realtime/server-commit-timing bug class that mock e2e structurally cannot
// (the #5391→#5421→#5436 broken-fix cycle: a freshly-started conversation that
// never appears in the Recent Conversations rail).
//
// Runner: bun (`bun run scripts/live-verify/run.ts [--dry-run]`). NOT bare node.
// Driver: chromium bundled in @playwright/test (AC1 — no extra Playwright
// driver package; the bundled browser is used directly).
//
// Binding invariants (ADR live-verify):
//   I-allowlist            exactly one synthetic principal; gate asserts
//                          ref(anon JWT) BEFORE sign-in, UID+email AFTER sign-in,
//                          all BEFORE the browser launch (the sole launch call
//                          site is inside driveAndVerify, which takes the verified
//                          principal as a typed argument — a future refactor
//                          cannot bypass a boolean).
//   I-action-send-free     the harness writes no `messages`/`action_sends` row in
//                          code (the one message is sent through the browser UI);
//                          the synthetic principal holds ZERO scope_grants so the
//                          agent Send route 403s before write-action-send.ts can
//                          ever create a WORM `action_sends` row. Teardown asserts
//                          the principal has 0 action_sends before deleting.
//                          (Supersedes the plan's original I-message-free, which
//                          the CTO ruling 2026-06-17 found structurally vacuous:
//                          `conversations` rows are materialized only on the first
//                          message — ws-handler.ts:2164 — so a strictly
//                          message-free run produces no row and never exercises
//                          the rail-realtime path it exists to verify.)
//   I-service-role-free    the gate-run path NEVER references the service role
//                          (AC2b); teardown runs as the synthetic user's OWN
//                          session via RLS.
//   I-teardown             delete-by-conversation-id with user_id=<UID> predicate
//                          (CASCADE removes messages + chat_attachments); never
//                          delete-by-user-id. session_id = "live-verify:<run-id>"
//                          stamps a queryable marker so a crashed run is reaped.
//   I-ephemerality         session + raw captures are destroyed at end of run;
//                          only a redacted RESULT summary is emitted.

import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { chromium, type Browser, type LaunchOptions } from "@playwright/test";

import { redact } from "./redact";

// ---------------------------------------------------------------------------
// Constants + config
// ---------------------------------------------------------------------------

// The one allowlisted synthetic email. A committed literal: no real end-user
// owns it, so it is the strongest single anchor of the allowlist gate.
export const EXPECTED_EMAIL = "live-verify@soleur.ai";

// Issue tracking the CANT-TEARDOWN escalation (data-integrity invariant breach).
const TEARDOWN_ESCALATION_ISSUE = "#5463";

const CANONICAL_HOST_RE = /^[a-z0-9]{20}\.supabase\.co$/;
const PROD_ALLOWED_HOSTS = new Set<string>(["api.soleur.ai"]);

export type Result =
  | { kind: "PASS"; detail: string }
  | { kind: "FAIL"; detail: string }
  | { kind: "CANT-RUN"; reason: string };

// The two fields of a server `{type:"error"}` WS frame the harness classifies
// on. Deliberately NOT the raw payload — adjacent frames (the auth frame) carry
// a token, so only these two scalars ever leave parseWsErrorFrame
// (I-ephemerality).
export type WsErrorFrame = { errorCode?: string; message?: string };

// The drive-phase decision seam. CANT-RUN / FAIL are terminal; PROCEED means the
// session was accepted and a row persisted, so the caller runs the rail
// assertion (the only place a PASS or the rail-race-class FAIL is decided).
export type DriveDecision =
  | { kind: "CANT-RUN"; reason: string }
  | { kind: "FAIL"; detail: string }
  | { kind: "PROCEED"; convId: string };

export interface Config {
  supabaseUrl: string;
  anonKey: string;
  password: string;
  expectedUid: string;
  expectedRef: string;
  productionUrl: string;
  dryRun: boolean;
  // Optional runner-portability overrides (#5485). Unset on ubuntu-latest CI,
  // where the bundled @playwright/test chromium installs cleanly. Set on a host
  // whose OS the bundled chromium does not support (the launch otherwise fails
  // with "Executable doesn't exist") to point the harness at a system browser.
  browserChannel?: string;
  browserPath?: string;
}

function readConfig(): Config {
  const required = (name: string): string => {
    const v = process.env[name];
    if (!v || v.trim() === "") {
      throw new Error(`live-verify: required env ${name} is unset`);
    }
    return v.trim();
  };
  const optional = (name: string): string | undefined => {
    const v = process.env[name];
    return v && v.trim() !== "" ? v.trim() : undefined;
  };
  const productionUrl =
    process.env.PRODUCTION_URL?.trim() ||
    process.env.DEPLOY_URL?.trim() ||
    "";
  if (!productionUrl) {
    throw new Error("live-verify: PRODUCTION_URL (or DEPLOY_URL) is unset");
  }
  return {
    supabaseUrl: required("NEXT_PUBLIC_SUPABASE_URL"),
    anonKey: required("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    password: required("LIVE_VERIFY_USER_PASSWORD"),
    expectedUid: required("LIVE_VERIFY_EXPECTED_UID"),
    expectedRef: required("LIVE_VERIFY_EXPECTED_REF"),
    productionUrl,
    dryRun: process.argv.includes("--dry-run"),
    browserChannel: optional("LIVE_VERIFY_BROWSER_CHANNEL"),
    browserPath: optional("LIVE_VERIFY_BROWSER_PATH"),
  };
}

/**
 * Build the Playwright launch options from the optional runner-portability
 * overrides (#5485). Returns `{}` when neither is set so the call is
 * byte-identical to the historical `chromium.launch()` (no `channel` key) and
 * ubuntu-latest CI keeps using the bundled chromium. An explicit
 * `executablePath` wins over `channel` (a concrete binary is the stronger
 * signal). Empty strings are treated as unset.
 */
export function buildLaunchOptions(opts: {
  channel?: string;
  executablePath?: string;
}): LaunchOptions {
  // Harden the system-browser override path (#5485 — a local runner whose OS the
  // bundled chromium can't run) against the Wayland GPU crash that drops every
  // page context mid-run as "Target page, context or browser has been closed".
  //   --disable-gpu        load-bearing here: kills the Vulkan/SwiftShader GPU
  //                        path that crashes this HEADLESS harness on Wayland.
  //   --ozone-platform=x11 inert while headless (no window); kept as cheap
  //                        insurance for running the override path HEADED for
  //                        local debugging, and for parity with the proven
  //                        headed MCP-browser fix (fdc4a0895).
  // Both are no-ops on a native-X11 host. The no-override (CI bundled-chromium)
  // path returns `{}` byte-identical, so ubuntu-latest — which has no X server
  // for --ozone-platform=x11 — is unaffected. See knowledge-base/project/
  // learnings/workflow-patterns/2026-06-17-playwright-mcp-wayland-vulkan-launch-crash.md.
  const WAYLAND_STABILIZATION_ARGS = ["--ozone-platform=x11", "--disable-gpu"];
  if (opts.executablePath) {
    return { executablePath: opts.executablePath, args: WAYLAND_STABILIZATION_ARGS };
  }
  if (opts.channel) {
    return { channel: opts.channel, args: WAYLAND_STABILIZATION_ARGS };
  }
  return {};
}

// The shape Playwright's `context.addCookies` accepts for the injected session.
type InjectedCookie = {
  name: string;
  value: string;
  domain: string;
  path: string;
  httpOnly: boolean;
  secure: boolean;
  sameSite: "Lax";
};

/**
 * Map the minted SSR cookie jar to the per-cookie shape the deployed app reads.
 * Every jar entry is re-injected 1:1 (chunk-suffix names preserved); the cookie
 * is scoped to the APP host (the driven origin, e.g. `app.soleur.ai`), never
 * the supabase host.
 *
 * `httpOnly: false` is load-bearing (#5485). The deployed client-guarded routes
 * (e.g. `/dashboard/chat/new`) hydrate their session via the @supabase/ssr
 * BROWSER client, which reads the auth-token cookie from `document.cookie` —
 * a path `httpOnly` blocks. Injecting `httpOnly: true` made the client-side
 * guard win a hydration race and bounce to `/login` ~20% of runs (measured
 * live, 5-iteration repro); `httpOnly: false` was 5/5 clean and matches the two
 * proven-working cookie-injection references in the repo
 * (`plugins/soleur/skills/ux-audit/scripts/bot-signin.ts`,
 * `apps/web-platform/e2e/global-setup.ts`). Do NOT flip it back without a fresh
 * live repro. The shape is locked by a characterization test.
 */
export function buildInjectedCookies(
  entries: Iterable<[string, { value: string }]>,
  appHost: string,
): InjectedCookie[] {
  return Array.from(entries).map(([name, c]) => ({
    name,
    value: c.value,
    domain: appHost,
    path: "/",
    httpOnly: false,
    secure: true,
    sameSite: "Lax" as const,
  }));
}

// ---------------------------------------------------------------------------
// Project bind (I-allowlist, before sign-in)
// ---------------------------------------------------------------------------

/** Derive the project ref from a Supabase JWT's `ref` claim (base64url middle). */
export function refFromJwt(token: string): string {
  const segments = token.split(".");
  if (segments.length !== 3) {
    throw new Error("anon key is not a 3-segment JWT");
  }
  const middle = segments[1];
  if (!middle || !/^[A-Za-z0-9_-]+$/.test(middle)) {
    throw new Error("anon key payload segment is not base64url");
  }
  const base64 = middle.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(
    base64.length + ((4 - (base64.length % 4)) % 4),
    "=",
  );
  const json = Buffer.from(padded, "base64").toString("utf8");
  const payload = JSON.parse(json) as { ref?: string };
  if (!payload.ref) throw new Error("anon key JWT carries no ref claim");
  return payload.ref;
}

export function assertUrlHostAllowed(rawUrl: string): void {
  const host = new URL(rawUrl).hostname;
  if (!PROD_ALLOWED_HOSTS.has(host) && !CANONICAL_HOST_RE.test(host)) {
    throw new Error(
      `NEXT_PUBLIC_SUPABASE_URL host ${host} is neither the prod custom domain nor the canonical 20-char shape`,
    );
  }
}

/** Hard-fail BEFORE sign-in if the configured project is not the expected one. */
export function bindProject(cfg: Config): void {
  assertUrlHostAllowed(cfg.supabaseUrl);
  const ref = refFromJwt(cfg.anonKey);
  if (ref !== cfg.expectedRef) {
    throw new Error(
      `project-bind: anon-key ref "${ref}" != LIVE_VERIFY_EXPECTED_REF "${cfg.expectedRef}" — refusing to sign in to the wrong project`,
    );
  }
}

// ---------------------------------------------------------------------------
// Mint (server-side, in-memory cookie jar — port of dev-signin/route.ts)
// ---------------------------------------------------------------------------

interface Jar {
  cookies: Map<string, { value: string; options: CookieOptions }>;
}

function makeJar(): Jar {
  return { cookies: new Map() };
}

/**
 * Sign in as the synthetic principal, capturing the auth cookies the Supabase
 * SSR client writes into an in-memory jar. Prod cookies are `secure:true`
 * (NOT dev-signin's `secure:false`).
 */
async function mintSession(
  cfg: Config,
  jar: Jar,
): Promise<ReturnType<typeof createServerClient>> {
  const supabase = createServerClient(cfg.supabaseUrl, cfg.anonKey, {
    cookieOptions: { sameSite: "lax", secure: true, path: "/" },
    cookies: {
      getAll() {
        return Array.from(jar.cookies.entries()).map(([name, c]) => ({
          name,
          value: c.value,
        }));
      },
      setAll(
        toSet: { name: string; value: string; options: CookieOptions }[],
      ) {
        for (const { name, value, options } of toSet) {
          jar.cookies.set(name, { value, options });
        }
      },
    },
  });

  const { error } = await supabase.auth.signInWithPassword({
    email: EXPECTED_EMAIL,
    password: cfg.password,
  });
  if (error) {
    // Never echo error.message — it can embed credentials. Surface only name.
    throw new Error(`signInWithPassword failed: ${error.name}`);
  }
  return supabase;
}

// ---------------------------------------------------------------------------
// Allowlist code-gate (FR2 / AC2 — after sign-in, before launch)
// ---------------------------------------------------------------------------

// Branded type: only `verifyPrincipal` produces it, and `driveAndVerify`
// requires it — so the browser launch is unreachable without passing the gate.
export type VerifiedPrincipal = {
  readonly __brand: "verified-live-verify-principal";
  readonly uid: string;
};

export async function verifyPrincipal(
  supabase: ReturnType<typeof createServerClient>,
  cfg: Config,
): Promise<VerifiedPrincipal> {
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    throw new Error(`getUser failed after sign-in: ${error?.name ?? "no user"}`);
  }
  const { id, email } = data.user;
  if (id !== cfg.expectedUid) {
    throw new Error(
      `allowlist gate: session UID "${id}" != LIVE_VERIFY_EXPECTED_UID — aborting before launch`,
    );
  }
  if (email !== EXPECTED_EMAIL) {
    throw new Error(
      `allowlist gate: session email "${email ?? ""}" != "${EXPECTED_EMAIL}" — aborting before launch`,
    );
  }
  return { __brand: "verified-live-verify-principal", uid: id };
}

// ---------------------------------------------------------------------------
// Drive the deployed app (the ONLY browser-launch call site)
// ---------------------------------------------------------------------------

const RAIL = '[data-testid="conversations-rail"]';
// The authenticated app-shell route that renders the rail for the synthetic
// principal (NOT /dashboard, which is the rail-less onboarding command-center
// for an org-less user). Used by both the dry-run auth proof and the gate path.
const CHAT_NEW_PATH = "/dashboard/chat/new";

/**
 * Launch chromium, inject the verified session cookies against the deployed
 * origin, and verify the rail behaviour. Requires a VerifiedPrincipal — the
 * type system makes this the single reachable launch path.
 */
async function driveAndVerify(
  verified: VerifiedPrincipal,
  supabase: ReturnType<typeof createServerClient>,
  cfg: Config,
  jar: Jar,
): Promise<Result> {
  const prodHost = new URL(cfg.productionUrl).hostname;
  const runId = crypto.randomUUID();

  let browser: Browser | null = null;
  try {
    // Launch the bundled chromium by default; honor the optional runner-
    // portability override (#5485) on hosts whose OS the bundled browser does
    // not support. Fail LOUD (CANT-RUN:browser-launch:<error.name>) rather than
    // a silent fallback, so a runner-environment problem is a distinct,
    // diagnosable result and never masquerades as a rail regression.
    try {
      browser = await chromium.launch(
        buildLaunchOptions({
          channel: cfg.browserChannel,
          executablePath: cfg.browserPath,
        }),
      );
    } catch (err) {
      return {
        kind: "CANT-RUN",
        reason: `browser-launch:${(err as Error).name}`,
      };
    }
    const context = await browser.newContext();
    await context.addCookies(buildInjectedCookies(jar.cookies.entries(), prodHost));
    const page = await context.newPage();

    // Capture the latest server-side `{type:"error"}` frame on the APP WS so a
    // send REJECTION (rate limit / no active session) classifies as CANT-RUN, not
    // a false rail FAIL. Registered BEFORE the first goto on purpose: the client
    // fires `start_session` from a React effect on WS-connect during hydration —
    // the rate_limited reply lands before the Send click, so a listener attached
    // later would miss it. Match ONLY the app WS path "/ws" (not the Supabase
    // realtime socket /realtime/v1/websocket). Only the parsed {errorCode,message}
    // is retained; raw frame payloads (the auth frame carries a token) never leak.
    let latestWsError: WsErrorFrame | null = null;
    let sessionStarted = false;
    page.on("websocket", (ws) => {
      let pathname: string;
      try {
        pathname = new URL(ws.url()).pathname;
      } catch {
        return;
      }
      if (pathname !== "/ws") return;
      ws.on("framereceived", ({ payload }) => {
        const text = payload.toString();
        const parsed = parseWsErrorFrame(text);
        if (parsed) latestWsError = parsed;
        // `session_started` is the server's acceptance of `start_session`; the
        // Send gate below waits for it so the chat never races ahead of the
        // established session (the #5463 session-rejected class).
        if (isSessionStartedFrame(text)) sessionStarted = true;
      });
    });

    if (cfg.dryRun) {
      // Read-only auth proof: load the chat-composer route and confirm the
      // authenticated app shell renders (the conversations rail), creating
      // NOTHING and writing no artifact. NOTE: /dashboard/chat/new — NOT
      // /dashboard. For the synthetic principal (no organization yet)
      // /dashboard renders the onboarding command-center, which has no rail;
      // /dashboard/chat/new renders the authenticated shell WITH the rail and
      // only materializes a conversation on message *send* (#5485). The
      // non-dry-run gate path below already uses /dashboard/chat/new.
      await page.goto(`${cfg.productionUrl}${CHAT_NEW_PATH}`, {
        waitUntil: "domcontentloaded",
      });
      await page.waitForSelector(RAIL, { timeout: 20_000 });
      return {
        kind: "PASS",
        detail: "dry-run: authenticated app shell rendered, no mutation",
      };
    }

    // Capture a high-water mark BEFORE the send so the materialization poll
    // below only ever matches a FRESH row, never a leftover from a prior run.
    const sinceIso = new Date().toISOString();

    // Start a fresh conversation and send ONE benign message.
    await page.goto(`${cfg.productionUrl}${CHAT_NEW_PATH}`, {
      waitUntil: "domcontentloaded",
    });
    const input = page.getByRole("textbox").first();
    await input.waitFor({ state: "visible", timeout: 20_000 });
    await input.fill("live-verify rail check — automated, please ignore");

    // Gate the Send on start_session ACCEPTANCE, not merely WS-connect. The Send
    // button enables on `status === "connected"` (chat-surface.tsx) — strictly
    // weaker than session acceptance — so clicking the instant it enables can race
    // ahead of the server's `session_started` reply and land the chat with no
    // active session ("Send start_session first" → session-rejected, the #5463
    // class observed on the first real CI run). The client auto-fires start_session
    // on WS-connect during hydration, so we poll the frame-listener flags here:
    //   - `session_started` seen      → session established, safe to Send
    //   - rate-limited / rejected     → bail with the precise reason BEFORE sending
    //   - neither within budget       → distinct `session-not-acked` CANT-RUN
    // (so a never-acked session is diagnosable, not misattributed downstream).
    const ackDeadline = Date.now() + 20_000;
    while (!sessionStarted) {
      const rejection = sendRejectionReason(latestWsError);
      if (rejection) {
        return { kind: "CANT-RUN", reason: rejection };
      }
      if (Date.now() >= ackDeadline) {
        // latestWsError is mutated only inside the framereceived closure, which
        // TS's control-flow analysis cannot model — it narrows the variable to
        // `null` here (so `?.field` errors on the `never` non-null branch). The
        // assertion re-states the true declared type; the closure does set it.
        const lastErr = latestWsError as WsErrorFrame | null;
        const hint = lastErr?.errorCode ?? lastErr?.message;
        return {
          kind: "CANT-RUN",
          reason: hint ? `session-not-acked:${hint}` : "session-not-acked",
        };
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }

    // The Send button is disabled until the WS reaches status === "connected"
    // (chat-surface.tsx: `disabled={status !== "connected"}`); clicking a
    // disabled Send is a silent no-op (handleSend early-returns when not
    // connected). Playwright's click auto-waits for the button to be enabled,
    // so a never-connect surfaces as a click timeout we convert into a clear
    // CANT-RUN rather than a downstream "no conversation" false-FAIL.
    try {
      await page
        .getByRole("button", { name: "Send message" })
        .click({ timeout: 35_000 });
    } catch {
      return {
        kind: "CANT-RUN",
        reason: "send-button-never-enabled:ws-not-connected",
      };
    }

    // Materialization signal #1 (authoritative, browser-independent): the
    // conversations row persists. The deployed app no longer NAVIGATES to
    // /dashboard/chat/<id> on a fresh send — it materializes the conversation
    // IN PLACE by dispatching CONVERSATION_CREATED_EVENT so the rail refetches
    // (the #5391/#5436 rail-race fix replaced the URL navigation). The old
    // waitForURL(/dashboard/chat/<uuid>/) assertion therefore could NEVER match
    // against the current app — poll the persisted row instead and derive the
    // id from it (not from the URL).
    const polledId = await pollFreshConversationId(
      supabase,
      verified,
      sinceIso,
      30_000,
      // Abort the poll the moment a server-side send rejection is captured, so a
      // rate_limited / session-rejected error WINS over the 30s no-row timeout
      // (otherwise an environmental rejection would wait out the budget and
      // false-FAIL as a rail regression). Checked at the top of every 1s tick.
      () => sendRejectionReason(latestWsError) !== null,
    );

    // A captured rate_limited / session-rejected WS error → CANT-RUN (surfaced,
    // non-blocking); no row + no error → the genuine FAIL; row present → PROCEED
    // to the rail assertion. Return the CANT-RUN/FAIL terminals BEFORE
    // teardownConversation — no row was created, so a teardown call here would
    // mask the real reason with CANT-TEARDOWN-empty-predicate.
    const decision = classifyDriveResult({ convId: polledId, wsError: latestWsError });
    if (decision.kind === "CANT-RUN") return decision;
    if (decision.kind === "FAIL") return decision;
    const convId = decision.convId;

    // Stamp the crash-reaper marker immediately (own session, RLS).
    await supabase
      .from("conversations")
      .update({ session_id: `live-verify:${runId}` })
      .eq("id", convId)
      .eq("user_id", verified.uid);

    // Materialization signal #2 — THE assertion (#5391/#5436): the freshly
    // persisted conversation appears in the Recent Conversations rail.
    const railRow = page.locator(`${RAIL} a[href$="/dashboard/chat/${convId}"]`);
    let railOk = false;
    try {
      await railRow.waitFor({ state: "visible", timeout: 20_000 });
      railOk = true;
    } catch {
      railOk = false;
    }

    const result: Result = railOk
      ? {
          kind: "PASS",
          detail: "fresh conversation persisted and appeared in the rail",
        }
      : {
          kind: "FAIL",
          detail: `conversation ${convId} persisted but did NOT appear in the rail within budget (the #5391/#5436 class)`,
        };

    // Teardown as the synthetic user's own session (RLS), regardless of result.
    const teardown = await teardownConversation(supabase, cfg, verified, convId);
    if (teardown.kind === "CANT-RUN") return teardown;

    return result;
  } finally {
    if (browser) await browser.close();
  }
}

/**
 * Parse a server WS frame, returning ONLY `{errorCode, message}` for a
 * `{type:"error"}` frame and `null` for anything else (non-JSON, non-object,
 * non-error). Pure + side-effect-free so it is unit-testable without a browser.
 * The raw payload is never returned — adjacent frames (the auth frame) carry a
 * token, so only these two scalars are allowed to escape (I-ephemerality).
 */
export function parseWsErrorFrame(payload: string): WsErrorFrame | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return null;
  }
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    (parsed as { type?: unknown }).type !== "error"
  ) {
    return null;
  }
  const { errorCode, message } = parsed as { errorCode?: unknown; message?: unknown };
  return {
    errorCode: typeof errorCode === "string" ? errorCode : undefined,
    message: typeof message === "string" ? message : undefined,
  };
}

/**
 * True ONLY for a `{type:"session_started"}` frame — the server's acceptance of
 * `start_session` (ws-handler.ts emits it with a conversationId + capabilities).
 * The drive loop waits for this before clicking Send, because the Send button
 * enables on the weaker `status === "connected"` (chat-surface.tsx) and a click
 * can otherwise race ahead of session acceptance. Pure + side-effect-free for unit
 * tests; only the `type` discriminant is read, so no payload field escapes.
 */
export function isSessionStartedFrame(payload: string): boolean {
  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch {
    return false;
  }
  return (
    typeof parsed === "object" &&
    parsed !== null &&
    (parsed as { type?: unknown }).type === "session_started"
  );
}

// The genuine no-persist FAIL detail (session accepted but no row materialized —
// the rail-race regression class). A single source so the wording stays in sync
// with the ADR-064 prose that describes it.
export const RAIL_FAIL_DETAIL =
  "send did not persist a conversation within budget (workspace-binding / WS-auth)";

/**
 * Map a captured WS error to its send-rejection CANT-RUN reason, or null when the
 * frame is NOT a send rejection. The two rejection classes:
 *   - errorCode === "rate_limited"                → "rate-limited"
 *   - message includes "Send start_session first" → "session-rejected"
 * The session-rejected match is the NARROW "Send start_session first" hint, NOT a
 * bare "No active session" substring — three ws-handler sites emit that prefix for
 * established-session drops (a genuine FAIL class) that the broad match would mask.
 * Shared by classifyDriveResult AND the poll abort predicate so the rate-limit
 * race-win does not depend on classifyDriveResult's internal branch ordering.
 */
export function sendRejectionReason(
  wsError: WsErrorFrame | null,
): "rate-limited" | "session-rejected" | null {
  if (wsError?.errorCode === "rate_limited") return "rate-limited";
  if (wsError?.message?.includes("Send start_session first")) return "session-rejected";
  return null;
}

/**
 * Decide the drive-phase outcome from the poll result + the latest captured WS
 * error. Precedence (pure, unit-testable):
 *   1. a send rejection (rate-limited / session-rejected) → CANT-RUN — checked
 *      first so it wins even when a stale row id is present
 *   2. a persisted row id → PROCEED (caller runs the rail assertion)
 *   3. otherwise → FAIL (the genuine no-persist case)
 */
export function classifyDriveResult(input: {
  convId: string | null;
  wsError: WsErrorFrame | null;
}): DriveDecision {
  const { convId, wsError } = input;
  const rejection = sendRejectionReason(wsError);
  if (rejection) {
    return { kind: "CANT-RUN", reason: rejection };
  }
  if (convId) {
    return { kind: "PROCEED", convId };
  }
  return { kind: "FAIL", detail: RAIL_FAIL_DETAIL };
}

/**
 * Poll the conversations table for a row created by the synthetic principal
 * AFTER `sinceIso` (the pre-send high-water mark). The deployed app materializes
 * a fresh conversation IN PLACE (CONVERSATION_CREATED_EVENT → rail refetch), not
 * via a URL navigation, so the persisted row — not the URL — is the authoritative
 * "the send actually worked" signal. Returns the conversation id (uuid) or null
 * on timeout. Uses the synthetic user's own session (RLS); never a broad scan.
 *
 * `shouldAbort` (optional) is checked at the top of every tick; when it returns
 * true the poll returns null immediately so the caller can classify on a captured
 * WS error rather than waiting out the full timeout (the rate-limit race-win).
 */
export async function pollFreshConversationId(
  supabase: ReturnType<typeof createServerClient>,
  verified: VerifiedPrincipal,
  sinceIso: string,
  timeoutMs: number,
  shouldAbort?: () => boolean,
): Promise<string | null> {
  const deadline = Date.now() + timeoutMs;
  do {
    if (shouldAbort?.()) return null;
    const { data } = await supabase
      .from("conversations")
      .select("id")
      .eq("user_id", verified.uid)
      .gt("created_at", sinceIso)
      .order("created_at", { ascending: false })
      .limit(1);
    const id = data?.[0]?.id;
    if (typeof id === "string" && /^[0-9a-f-]{36}$/.test(id)) return id;
    if (Date.now() >= deadline) break;
    await new Promise((r) => setTimeout(r, 1_000));
  } while (Date.now() < deadline);
  return null;
}

// ---------------------------------------------------------------------------
// Teardown (I-teardown / I-action-send-free, synthetic user's own session)
// ---------------------------------------------------------------------------

export async function teardownConversation(
  supabase: ReturnType<typeof createServerClient>,
  cfg: Config,
  verified: VerifiedPrincipal,
  convId: string,
): Promise<Result> {
  if (!verified.uid || !convId) {
    // Never run a delete with an empty predicate (would risk a null-filter
    // match). Surface as CANT-RUN rather than a silent skip.
    return { kind: "CANT-RUN", reason: "CANT-TEARDOWN-empty-predicate" };
  }

  // I-action-send-free: the synthetic principal must hold ZERO action_sends.
  // (By construction it has no scope_grants, so the Send route 403s before any
  // action_sends write.) A non-zero count is an invariant breach — escalate,
  // never reap-next-run, never force-delete (the WORM no-delete trigger would
  // abort the transaction and wedge the row).
  const { count, error: countErr } = await supabase
    .from("action_sends")
    .select("id", { count: "exact", head: true })
    .eq("user_id", verified.uid);
  if (countErr) {
    return { kind: "CANT-RUN", reason: "CANT-TEARDOWN-action-sends-unreadable" };
  }
  if ((count ?? 0) > 0) {
    return {
      kind: "CANT-RUN",
      reason: `CANT-TEARDOWN-has-action-sends+${TEARDOWN_ESCALATION_ISSUE}`,
    };
  }

  // Archive first → fires the migration-036 slot-release trigger
  // (user_concurrency_slots has no FK, so a bare delete would leak the slot).
  await supabase
    .from("conversations")
    .update({ archived_at: new Date().toISOString() })
    .eq("id", convId)
    .eq("user_id", verified.uid);

  // Delete by conversation id WITH the allowlisted UID predicate. messages and
  // chat_attachments CASCADE (mig 001:70 / 019:22); we asserted 0 action_sends.
  const { error: delErr } = await supabase
    .from("conversations")
    .delete()
    .eq("id", convId)
    .eq("user_id", verified.uid);
  if (delErr) {
    return {
      kind: "CANT-RUN",
      reason: `CANT-TEARDOWN-delete-failed+${TEARDOWN_ESCALATION_ISSUE}`,
    };
  }
  return { kind: "PASS", detail: "teardown complete" };
}

/**
 * Start-of-run reaper: delete any orphan conversations from a crashed prior run
 * (own session, RLS). conversations has no title column, so the queryable
 * marker is session_id LIKE 'live-verify:%'.
 */
async function reapOrphans(
  supabase: ReturnType<typeof createServerClient>,
  verified: VerifiedPrincipal,
): Promise<void> {
  await supabase
    .from("conversations")
    .delete()
    .eq("user_id", verified.uid)
    .like("session_id", "live-verify:%");
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

function emit(result: Result): void {
  const line =
    result.kind === "CANT-RUN"
      ? `RESULT: CANT-RUN:${result.reason}`
      : `RESULT: ${result.kind} — ${redact(result.detail)}`;
  // Single structured line (FR6). redact() scrubs any captured value that
  // reached the detail string.
  console.log(line);
}

async function main(): Promise<void> {
  let cfg: Config;
  try {
    cfg = readConfig();
  } catch (err) {
    emit({ kind: "CANT-RUN", reason: `CONFIG:${(err as Error).message}` });
    process.exitCode = 1;
    return;
  }

  const jar = makeJar();
  try {
    bindProject(cfg); // hard-fail before sign-in
    const supabase = await mintSession(cfg, jar);
    const verified = await verifyPrincipal(supabase, cfg); // before launch

    if (!cfg.dryRun) {
      await reapOrphans(supabase, verified);
    }

    const result = await driveAndVerify(verified, supabase, cfg, jar);

    // I-ephemerality: destroy the session before exit (also on dry-run).
    await supabase.auth.signOut().catch(() => undefined);

    emit(result);
    if (result.kind === "FAIL") process.exitCode = 1;
  } catch (err) {
    // Any pre-launch gate failure (project-bind, mint, allowlist) lands here as
    // CANT-RUN — the harness never reached a verifiable state. redact the
    // message defensively in case a captured value leaked into it.
    emit({ kind: "CANT-RUN", reason: redact((err as Error).message) });
    process.exitCode = 1;
  } finally {
    jar.cookies.clear();
  }
}

// Run only when invoked directly (`bun run …`), NOT when imported by the unit
// tests. `import.meta.main` is true under bun's entrypoint and undefined under
// vitest's node loader, so the gate functions stay importable without firing
// main() (which would launch a browser at import time).
if ((import.meta as { main?: boolean }).main) {
  void main();
}
