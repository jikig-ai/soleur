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
import {
  chromium,
  type Browser,
  type LaunchOptions,
  type Page,
} from "@playwright/test";

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

export function readConfig(): Config {
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

export interface Jar {
  cookies: Map<string, { value: string; options: CookieOptions }>;
}

export function makeJar(): Jar {
  return { cookies: new Map() };
}

/**
 * Sign in as the synthetic principal, capturing the auth cookies the Supabase
 * SSR client writes into an in-memory jar. Prod cookies are `secure:true`
 * (NOT dev-signin's `secure:false`).
 */
export async function mintSession(
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

/**
 * The composer's ARIA role — used by BOTH the wait and the diagnostic that
 * explains the wait's failure. They must never re-derive it independently: a
 * diagnostic counting a different role than the wait queried would report the
 * opposite of the truth, and only on the failure path where nobody is looking.
 */
export const COMPOSER_ROLE = "textbox" as const;

/** Per-field ceiling for the renderer round trips in waitFailureState. */
const FIELD_TIMEOUT_MS = 3_000;

/** Paths this harness can legitimately be on; anything else is reduced. */
const EXPECTED_PATHS =
  /^\/(?:dashboard(?:\/chat(?:\/new|\/[0-9a-f-]{36})?)?|login|accept-terms)$/;

/**
 * Strip the characters a log/JSON viewer treats as line breaks.
 * `JSON.stringify` escapes only C0, `"` and `\` — U+2028/U+2029 (and DEL) pass
 * through literally, so a crafted title could render as a second line and forge
 * a `RESULT:` verdict in an operator's eye. Written as escapes, never literals
 * (`cq-regex-unicode-separators-escape-only`).
 */
function scrubLine(v: string): string {
  // Codepoint test rather than a regex literal: a character class spanning
  // \x00-\x1f is exactly what eslint's `no-control-regex` exists to flag, and
  // that rule carries a ratchet in this repo which only moves DOWN. Same
  // semantics, no control characters in source, and the separators stay
  // numeric escapes (cq-regex-unicode-separators-escape-only).
  let out = "";
  for (const ch of v) {
    const c = ch.codePointAt(0) ?? 0;
    const breaksALine = c < 0x20 || c === 0x7f || c === 0x2028 || c === 0x2029;
    out += breaksALine ? " " : ch;
  }
  return out;
}

/**
 * Race a probe against a timeout, returning `fallback` on throw or expiry.
 * Shared by waitFailureState's `safe()` and the rail-assert diagnostics —
 * a diagnostic probe must never throw AND never stall the verdict
 * (BOUNDED, not merely guarded — see the comment inside waitFailureState).
 */
const bounded = async <T>(
  fn: () => Promise<T>,
  fallback: T,
  timeoutMs: number = FIELD_TIMEOUT_MS,
): Promise<T> => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      fn(),
      new Promise<T>((resolve) => {
        timer = setTimeout(() => resolve(fallback), timeoutMs);
      }),
    ]);
  } catch {
    return fallback;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
};

/**
 * The name field of a captured error — the only part safe to emit
 * (`.message` can embed origin URLs). Same extraction waitFailureState
 * performs inline on `cause`.
 */
function errorName(err: unknown): string {
  return err && typeof err === "object" && "name" in err
    ? scrubLine(String((err as { name: unknown }).name)).slice(0, 40)
    : "<none>";
}

/** The page-death classes: the page can no longer reach a verdict at all.
 * `execution context was destroyed` is deliberately ABSENT — it is the
 * RETRIABLE navigation race (documented below in waitFailureState's catch),
 * not death: a stray navigation during a poll tick would otherwise convert
 * a reachable verdict into CANT-RUN. `crashed` covers Playwright's real
 * crash strings — "Page crashed", "Navigation failed because page
 * crashed!", "Target crashed <logs>" — which are the same death class the
 * #5485 Wayland-GPU crash history produced. */
const CLOSED_TARGET_RE =
  /target.{0,30}closed|has been closed|crashed/i;

function isClosedTargetError(err: unknown): boolean {
  const name =
    err && typeof err === "object" && "name" in err
      ? String((err as { name: unknown }).name)
      : "";
  const message = err instanceof Error ? err.message : "";
  return CLOSED_TARGET_RE.test(`${name} ${message}`);
}

/**
 * Failure-time page state for a visibility wait that timed out (#7969).
 * Background and the three hypotheses it separates: issue #7969, PR #8092.
 *
 * Two invariants constrain every future edit here:
 *
 * 1. NEVER THROWS. This runs only on the already-failing path, so an exception
 *    would replace a diagnosable timeout with an undiagnosable one. Every field
 *    goes through safe() and degrades to a sentinel (`<unreadable>`, `-1`) —
 *    never to a value a healthy page could also produce.
 * 2. The URL is cut to its PATH, and that is the ONLY control on the query
 *    string: redact.ts's rules cover access_token/refresh_token/provider_token/
 *    apikey, and NOT `code=`, which is what Supabase PKCE puts there. Widening
 *    this back to a full URL leaks that grant into a public CI log.
 */
export async function waitFailureState(
  page: Page,
  nav: { status(): number; url?(): string } | null,
  what: "composer" | "rail",
  cause?: unknown,
): Promise<string> {
  // BOUNDED, not merely guarded (#8092 review). page.title() and
  // Locator.count() accept no timeout and evaluate in the RENDERER — and a
  // wedged renderer is one of the hypotheses this helper exists to separate.
  // Unbounded, a hang here would blow the job's timeout-minutes, emit NO
  // RESULT: line at all, and the workflow escalates that absence to BLOCK=1 —
  // turning a non-blocking CANT-RUN into a blocking release failure carrying
  // LESS information than the timeout it replaced. So: never throws AND always
  // returns.
  const safe = <T>(fn: () => Promise<T>, fallback: T): Promise<T> =>
    bounded(fn, fallback, FIELD_TIMEOUT_MS);
  // ALLOWLIST, not raw emit (#8092 review). Cutting the URL to its pathname
  // strips the query and the fragment — where Supabase PKCE puts `?code=` and
  // the implicit flow puts `#access_token=` — but a pathname can ITSELF be a
  // credential: this app serves /shared/<token>, /api/kb/share/<token>,
  // /invite/<token> and /api/account/export/<jobId>, none of which any
  // redact.ts rule matches. The harness cannot reach those today only because
  // middleware.ts passes literal redirect targets and the nav target is a
  // constant — three files away, pinned by nothing here. So emit only the paths
  // this harness can legitimately be on, and reduce anything else to its first
  // segment, which is enough to diagnose and cannot carry a token.
  const path = await safe(async () => {
    const raw = new URL(page.url()).pathname;
    if (EXPECTED_PATHS.test(raw)) return raw;
    return `<unexpected:/${raw.split("/")[1] ?? ""}>`;
  }, "<unreadable>");
  // IN safe(), despite Response.status() being a sync accessor: on a CLOSED
  // target every accessor throws ("Target page, context or browser has been
  // closed"), and a wedged page that just blew a 20s wait is exactly where a
  // context teardown races this. Measured consequence of leaving it out — the
  // throw escapes driveAndVerify and SKIPS `supabase.auth.signOut()` below, so
  // the synthetic PRODUCTION principal's session is never destroyed.
  const status = nav
    ? await safe(async () => String(nav.status()), "<unreadable>")
    : "<no-response>";
  // OVERLOADED, deliberately recorded: playwright's Frame.queryCount swallows a
  // RETRIABLE error ("Execution context was destroyed, most likely because of a
  // navigation") and returns 0. So `textboxes=0` means "no elements" OR "the
  // query hit a mid-navigation page" — and mid-navigation is itself one of the
  // hypotheses. The `-1` sentinel is unreachable for that class; `visible` below
  // is what disambiguates a real zero from a late paint.
  const textboxes = await safe(() => page.getByRole(COMPOSER_ROLE).count(), -1);
  // redact BEFORE the cut: redact()'s rules need WHOLE tokens (the JWT
  // three-segment shape, the email TLD), so truncating first can leave an
  // unmatched fragment of a secret.
  const title = redact(await safe(() => page.title(), "<unreadable>")).slice(0, 60);
  const rail = await safe(() => page.locator(RAIL).count(), -1);
  // `http` describes the document goto() fetched; `path` is read at FAILURE
  // time, after any client-side push. Emitting the nav path too is what makes
  // `http=200 path=/login` decidable between "the server served /login" and
  // "the server served the chat route, then the client pushed to /login" —
  // which is exactly the bounce hypothesis this helper exists to settle.
  const navPath = nav?.url
    ? ((): string => {
        try {
          return new URL(nav.url!()).pathname;
        } catch {
          return "<unreadable>";
        }
      })()
    : "<none>";
  // Re-probe visibility AT REPORT TIME. The wait sampled at T+0..20s; this
  // samples at ~T+20.05s. `textboxes=1 visible=false` is drift (present but
  // hidden); `textboxes=1 visible=true` means it painted just after the wait
  // expired, i.e. slow first paint — the hypothesis the original message could
  // not separate at all.
  const visible = await safe(
    () => page.getByRole(COMPOSER_ROLE).first().isVisible(),
    // a distinct sentinel: "we could not tell", never a boolean a healthy page
    // could also produce
    "<unreadable>" as boolean | string,
  );
  // `.name` ONLY — `.message` embeds the origin URL. This separates a genuine
  // timeout from TargetClosedError / "Execution context was destroyed", which
  // the bare catch previously discarded entirely.
  const errName = cause !== undefined ? errorName(cause) : "<none>";
  return (
    `${what}-not-visible path=${path} http=${status} nav=${navPath} ` +
    `err=${errName} textboxes=${textboxes} visible=${visible} rail=${rail} ` +
    `title=${JSON.stringify(scrubLine(title))}`
  );
}

/**
 * Await a visibility condition, or return a CANT-RUN carrying the page state.
 *
 * WHY THIS IS A FUNCTION AND NOT TWO INLINE try/catch BLOCKS (#7969 review):
 * the inline form made the PR's own central change unpinned — reverting either
 * call site to a bare `await …waitFor(…)` left the whole suite GREEN, because
 * `waitFailureState` was unit-tested in isolation and nothing asserted it was
 * ever CALLED. The endpoints were covered and the wire was not. Routing both
 * waits through one exported seam makes the wire itself drivable from a test,
 * and `no-bare-visibility-wait.test.ts` asserts no bare form comes back.
 *
 * Returns `null` when the wait succeeds, so callers read as
 * `const bad = await …; if (bad) return bad;`.
 */
export async function awaitVisibleOrDiagnose(
  wait: () => Promise<unknown>,
  page: Page,
  nav: { status(): number; url?(): string } | null,
  what: "composer" | "rail",
): Promise<{ kind: "CANT-RUN"; reason: string } | null> {
  try {
    await wait();
    return null;
  } catch (err) {
    return {
      kind: "CANT-RUN",
      reason: await waitFailureState(page, nav, what, err),
    };
  }
}

// ---------------------------------------------------------------------------
// Rail verdict seam (#9581): observe -> scope probe -> one reload -> observe
// ---------------------------------------------------------------------------

/**
 * Per-window observe budget. The app's own delivery arms have a designed
 * bound of ~9.6s (the CONVERSATION_CREATED_EVENT retry ladder) plus refetch
 * latency, so ~45s gives them ~4x headroom before any recovery draw — enough
 * that a miss means the arms failed, not that the window was tight.
 */
const RAIL_OBSERVE_MS = 45_000;

/** Poll cadence for `railRow.isVisible()` inside each observe window. */
const RAIL_POLL_MS = 1_500;

/**
 * ONE named total ceiling enclosing the verdict path — both observe windows,
 * the scope probes, and the reload. It preserves the role the old 20s
 * `waitFor` timeout played — bounding FAIL-detection latency and job time —
 * at the value the observe+recover shape needs: worst case is
 * observe 45s + one in-flight read overrun 5s + probes 2×10s + the
 * lastDirect read 5s + reload backstop 35s + observe 45s + a final
 * overrun 5s ≈ 160s, so the ceiling also guarantees phase B a full
 * observe window. Diagnostics that run after the verdict (railRowState,
 * waitFailureState) sit outside it, each under their own bounded()
 * per-field timeouts. Far inside the job's 15-minute budget either way.
 */
export const RAIL_ASSERT_TOTAL_BUDGET_MS = 165_000;

/**
 * Per-probe ceiling for the active-repo + RPC scope probes, under the same
 * bounded() discipline as waitFailureState: a diagnostic must never stall
 * the verdict or outlive the total ceiling.
 */
const RAIL_SCOPE_PROBE_MS = 10_000;

/**
 * `page.reload`'s timeout is MANDATORY, not optional: the installed .d.ts
 * documents a default of `0` — NO timeout — so an unpinned reload can
 * outwait RAIL_ASSERT_TOTAL_BUDGET_MS. A thrown reload (e.g. nav timeout)
 * is captured as `reload_err`, never a verdict.
 */
const RAIL_RELOAD_TIMEOUT_MS = 30_000;

/**
 * Per-tick ceiling on `railRow.isVisible()`. The call accepts no timeout and
 * still requires a renderer round-trip — on a wedged-but-not-closed renderer
 * (the very hypothesis bounded() exists for) an unbounded read would stall
 * the poll loop past the deadline, emit NO `RESULT:` line at all, and let
 * the workflow escalate that absence to `BLOCK=1` with zero diagnostics —
 * worse than the FAIL it replaced. A timed-out read is a missed tick, not a
 * verdict; `!sawCleanRead` still lands an honest CANT-RUN when the wedge
 * never releases a single read.
 */
const RAIL_READ_TIMEOUT_MS = 5_000;

/**
 * The rail check's three verdicts. `railVerdictToResult` maps them onto the
 * Result union — keeping the wire prefixes (`RESULT: PASS —` /
 * `RESULT: FAIL —` / `RESULT: CANT-RUN:`) the workflow classifier parses.
 */
export type RailVerdict =
  | {
      kind: "appeared";
      via: "direct" | "reload";
      elapsedMs: number;
      checks: number;
      reloadErr?: string;
    }
  | {
      kind: "absent";
      checks: number;
      readErrs: number;
      reloads: number;
      elapsedMs: number;
      railState: string;
      rpcRow: string;
      activeRepo: string;
      reloadErr?: string;
      budgetMs: number;
    }
  | { kind: "unverifiable"; reason: string };

/**
 * Which of the rail's three mutually exclusive render branches was showing
 * (conversations-rail.tsx): the error branch, the empty-state branch, or the
 * rows map — plus `rail-absent` when the wrapper testid itself is gone and
 * `unreadable` when the reads could not be taken. NEVER THROWS: every count
 * goes through bounded() and degrades to a sentinel, the same discipline
 * waitFailureState holds.
 */
export async function railRowState(page: Page): Promise<string> {
  const errCount = await bounded(
    () => page.locator('[data-testid="conversations-rail-error"]').count(),
    -1,
  );
  if (errCount > 0) return "error";
  const emptyCount = await bounded(
    () => page.locator('[data-testid="conversations-rail-empty"]').count(),
    -1,
  );
  if (emptyCount > 0) return "empty";
  const railCount = await bounded(() => page.locator(RAIL).count(), -1);
  if (railCount === 0) return "rail-absent";
  const rows = await bounded(
    () =>
      // `:not(/new)` excludes the persistent "+ New" NavLink (and the empty
      // branch's CTA), which matches the plain prefix and would overcount
      // conversation rows by one.
      page.locator(`${RAIL} a[href^="/dashboard/chat/"]:not([href$="/new"])`).count(),
    -1,
  );
  if (railCount === -1 || errCount === -1 || emptyCount === -1 || rows === -1) {
    return "unreadable";
  }
  // `rows:0` cannot distinguish "rendered list missing the row" from
  // "loading never settled" (the rail's ternary renders the rows-map branch
  // with zero anchors while `loading` stays true) — a DOM-only read cannot
  // tell them apart; `rpc_row=`/`active_repo=` disambiguate one level down.
  return `rows:${rows}`;
}

/** A PostgREST error's most useful compact tag: `code` when present, else name. */
function rpcErrorTag(error: unknown): string {
  const e = error as { code?: unknown; name?: unknown } | null;
  const tag =
    typeof e?.code === "string" && e.code
      ? e.code
      : typeof e?.name === "string" && e.name
        ? e.name
        : "error";
  return scrubLine(tag).slice(0, 40);
}

/**
 * Probe whether the fresh row is in the rail's OWN scoped data source —
 * `list_conversations_enriched` called with the same inputs the rail's SWR
 * fetch resolves (`{workspaceId, repoUrl}` from
 * `GET /api/workspace/active-repo`, read through the injected cookie jar).
 * This is the data-vs-render discriminator: `rpc_row=no` means the row is
 * committed but OUT of the rail's scope (a real regression — fail fast, no
 * reload); `rpc_row=yes` + DOM-absent means the render path is broken.
 * Every read is bounded; a failed read degrades to `unreadable:<reason>`,
 * never a throw.
 */
async function probeRailScope(
  page: Page,
  supabase: ReturnType<typeof createServerClient>,
  convId: string,
  productionUrl: string,
  probeMs: number,
): Promise<{
  activeRepo: string;
  scopeNull: "repo" | "workspace" | null;
  rpcRow: string;
}> {
  const scope = await bounded(
    async (): Promise<
      | { ok: true; workspaceId: string | null; repoUrl: string | null }
      | { ok: false; status?: number }
    > => {
      const res = await page.request.get(
        `${productionUrl}/api/workspace/active-repo`,
      );
      if (!res.ok()) return { ok: false, status: res.status() };
      const body = (await res.json()) as {
        workspaceId?: unknown;
        repoUrl?: unknown;
      } | null;
      // A 200 with a non-object body is a malformed read — treat it like
      // any other probe failure, or a bare `null` would resolve to
      // `n/a:repo-null` and fail-fast on a misparse.
      if (body === null || typeof body !== "object") return { ok: false };
      return {
        ok: true,
        workspaceId: typeof body?.workspaceId === "string" ? body.workspaceId : null,
        repoUrl: typeof body?.repoUrl === "string" ? body.repoUrl : null,
      };
    },
    { ok: false },
    probeMs,
  );
  if (!scope.ok) {
    return {
      activeRepo: "unreadable",
      scopeNull: null,
      rpcRow: `unreadable:active-repo${scope.status !== undefined ? `:${scope.status}` : ""}`,
    };
  }
  // A repo-less rail scope cannot list the row no matter how many times we
  // reload — report it and let the caller fail fast. `n/a:` (not
  // `unreadable:`): the probe succeeded; the RPC was not run because the
  // scope itself is empty.
  if (scope.repoUrl === null) {
    return { activeRepo: "resolved", scopeNull: "repo", rpcRow: "n/a:repo-null" };
  }
  if (scope.workspaceId === null) {
    return {
      activeRepo: "resolved",
      scopeNull: "workspace",
      rpcRow: "n/a:workspace-null",
    };
  }
  const rpcRow = await bounded(
    async () => {
      const { data, error } = await supabase.rpc("list_conversations_enriched", {
        p_repo_url: scope.repoUrl,
        p_workspace_id: scope.workspaceId,
        p_archive: "active",
        p_status: null,
        p_domain: null,
        // These args mirror the rail's own fetch byte-for-byte
        // (use-conversations.ts's list_conversations_enriched call, with
        // p_limit = RAIL_LIMIT in conversations-rail.tsx — pinned by the
        // live-verify suite so a rail-limit change drifts red, not silent).
        p_limit: 15,
      });
      if (error) return `unreadable:${rpcErrorTag(error)}`;
      // A successful-but-non-array payload is a malformed read, not an empty
      // set — `no` would fail-fast on a misparse.
      if (!Array.isArray(data)) return "unreadable:shape";
      return data.some(
        (r) =>
          r !== null &&
          typeof r === "object" &&
          (r as { id?: unknown }).id === convId,
      )
        ? "yes"
        : "no";
    },
    "unreadable:rpc",
    probeMs,
  );
  return { activeRepo: "resolved", scopeNull: null, rpcRow };
}

export interface RailAssertDeps {
  railRow: { isVisible(): Promise<boolean> };
  page: Page;
  nav: { status(): number; url?(): string } | null;
  supabase: ReturnType<typeof createServerClient>;
  convId: string;
  productionUrl: string;
  /** Test-only budget overrides; prod reads the named constants. */
  budget?: {
    observeMs?: number;
    pollMs?: number;
    readMs?: number;
    totalMs?: number;
    probeMs?: number;
    reloadMs?: number;
  };
}

/**
 * THE rail assertion (#9581). Replaces the single-shot
 * `railRow.waitFor({timeout: 20_000})` — which read any rail-listing lag
 * over 20s as a release-blocking FAIL — with a bounded observe -> scope
 * probe -> one reload -> observe loop under ONE total ceiling:
 *
 *   Phase A OBSERVE: poll `railRow.isVisible()` (point-in-time, lazy
 *     locator — survives the reload; deliberately NOT waitFor, which would
 *     re-enter the no-bare-visibility-wait territory and can throw across
 *     navigation) every ~1.5s for ~45s.
 *   SCOPE PROBE: is the row in `list_conversations_enriched` under the
 *     rail's own scope inputs? `no` (or a null repoUrl) FAILs fast —
 *     scope-broken is a regression, not lag, and must not burn the reload.
 *   Phase B RECOVER: exactly one `page.reload` (which re-runs the mount-time
 *     fetch — a real path, not a cooperative event re-dispatch), then a
 *     second observe window to the total ceiling.
 *
 * Verdict honesty: an isVisible() throw on a live page is a missed tick;
 * the target-closed class (page death) is `unverifiable` -> CANT-RUN —
 * consistent with awaitVisibleOrDiagnose, and honest about what was
 * verified (nothing). A row that never appears still yields `absent` ->
 * FAIL -> BLOCK=1; recovery is measured via `via=`/`elapsed=`, never silent.
 */
export async function assertRailRowVisible(
  deps: RailAssertDeps,
): Promise<RailVerdict> {
  const observeMs = deps.budget?.observeMs ?? RAIL_OBSERVE_MS;
  const pollMs = deps.budget?.pollMs ?? RAIL_POLL_MS;
  const readMs = deps.budget?.readMs ?? RAIL_READ_TIMEOUT_MS;
  const totalMs = deps.budget?.totalMs ?? RAIL_ASSERT_TOTAL_BUDGET_MS;
  const probeMs = deps.budget?.probeMs ?? RAIL_SCOPE_PROBE_MS;
  const reloadMs = deps.budget?.reloadMs ?? RAIL_RELOAD_TIMEOUT_MS;

  const started = Date.now();
  const totalDeadline = started + totalMs;
  let checks = 0;
  let readErrs = 0;
  let reloads = 0;
  let reloadErr: string | undefined;
  let sawCleanRead = false;
  let cleanReadPostReload = false;
  let unreadableCause: unknown;

  const sleep = (ms: number) =>
    new Promise<void>((r) => setTimeout(r, Math.max(0, ms)));

  const readOnce = async (): Promise<"visible" | "hidden" | "dead"> => {
    checks++;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      // A manual race — NOT bounded(): bounded's catch-all resolves the
      // fallback on a page-death throw too, which would make the "dead"
      // classification below unreachable and a crashed browser read as
      // absent -> FAIL -> BLOCK=1. Timeout yields the null sentinel (a
      // missed tick); a rejection propagates to the catch and classifies.
      const v = await Promise.race([
        deps.railRow.isVisible(),
        new Promise<null>((resolve) => {
          timer = setTimeout(() => resolve(null), readMs);
        }),
      ]);
      if (v === null) {
        readErrs++;
        return "hidden";
      }
      sawCleanRead = true;
      if (reloads > 0) cleanReadPostReload = true;
      return v ? "visible" : "hidden";
    } catch (err) {
      if (isClosedTargetError(err)) {
        unreadableCause = err;
        return "dead";
      }
      // A non-fatal throw is a missed tick, not a verdict — keep polling.
      // If we NEVER achieve a clean read the verdict degrades to
      // unverifiable below rather than a false rail-regression FAIL.
      readErrs++;
      unreadableCause ??= err;
      return "hidden";
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  };

  // The navigation response diagnostics read: the original goto until a
  // reload produces a fresher one (post-reload CANT-RUN should describe the
  // reload's navigation, not the pre-send one).
  let navAfter = deps.nav;

  const unverifiable = async (): Promise<RailVerdict> => ({
    kind: "unverifiable",
    reason:
      `rail-check:${await waitFailureState(deps.page, navAfter, "rail", unreadableCause)}` +
      ` reads=${checks} read_errors=${readErrs}` +
      (reloadErr !== undefined ? ` reload_err=${reloadErr}` : ""),
  });

  const pollWindow = async (
    deadlineMs: number,
    via: "direct" | "reload",
  ): Promise<RailVerdict | null> => {
    while (Date.now() < deadlineMs) {
      const r = await readOnce();
      if (r === "visible") {
        return { kind: "appeared", via, elapsedMs: Date.now() - started, checks };
      }
      if (r === "dead") return unverifiable();
      await sleep(Math.min(pollMs, deadlineMs - Date.now()));
    }
    return null;
  };

  // Phase A — OBSERVE.
  const phaseA = await pollWindow(
    Math.min(started + observeMs, totalDeadline),
    "direct",
  );
  if (phaseA) return phaseA;

  // The scope probe runs BEFORE the reload draw: `rpc_row=no` (row committed
  // but outside the rail's scoped list) or a null repoUrl is a genuine
  // regression a reload cannot repair — fail fast, do not burn the draw.
  const scope = await probeRailScope(
    deps.page,
    deps.supabase,
    deps.convId,
    deps.productionUrl,
    probeMs,
  );
  const absentVerdict = async (): Promise<RailVerdict> => ({
    kind: "absent",
    checks,
    readErrs,
    reloads,
    elapsedMs: Date.now() - started,
    railState: await railRowState(deps.page),
    rpcRow: scope.rpcRow,
    activeRepo: scope.activeRepo,
    reloadErr,
    budgetMs: totalMs,
  });

  if (scope.scopeNull !== null || scope.rpcRow === "no") {
    return absentVerdict();
  }

  // One last direct-arm read before spending the reload: the app's own
  // delivery arms may have landed the row DURING the scope probe. Crediting
  // that arrival to `via=reload` would over-count the very signal
  // (own-arms-miss) the measurement exists to track.
  const lastDirect = await readOnce();
  if (lastDirect === "visible") {
    return { kind: "appeared", via: "direct", elapsedMs: Date.now() - started, checks };
  }
  if (lastDirect === "dead") return unverifiable();

  // Phase B — RECOVER: exactly one reload (the mount-time fetch is a real
  // path no event wiring can fake; a second reload would repeat the same
  // draw), then a SECOND full observe window. Phase B gets its own deadline
  // (start + observeMs, capped at the ceiling), not the ceiling itself —
  // otherwise probe/reload latency could starve the recovery window to a
  // few seconds and reintroduce the flake this fixes. Note: the reload also
  // re-runs mount effects (a second start_session on the 10/user/hr
  // limiter) — another reason the draw is one, not N.
  if (Date.now() < totalDeadline) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      // A manual race — NOT bounded(), for the same reason as readOnce:
      // bounded would swallow a page-death throw into the fallback and kill
      // the dead classification. Playwright's timeout: reloadMs bounds the
      // NAVIGATION; the outer race (reloadMs + 5s) is the backstop for a
      // wedged driver/CDP transport where even the timeout can't fire.
      const reNav = await Promise.race([
        deps.page.reload({ waitUntil: "domcontentloaded", timeout: reloadMs }),
        new Promise<"__wedge__">((resolve) => {
          timer = setTimeout(() => resolve("__wedge__"), reloadMs + 5_000);
        }),
      ]);
      reloads++;
      if (reNav === "__wedge__") reloadErr = "reload-unbounded-wedge";
      else if (reNav) navAfter = reNav;
    } catch (err) {
      if (isClosedTargetError(err)) {
        unreadableCause = err;
        return unverifiable();
      }
      reloadErr = errorName(err);
      reloads++;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }

  const phaseB = await pollWindow(
    Math.min(Date.now() + observeMs, totalDeadline),
    "reload",
  );
  if (phaseB) {
    // A reload that threw but was followed by the row appearing is still a
    // reload-arm PASS — annotate it rather than reporting a clean draw.
    if (phaseB.kind === "appeared" && reloadErr !== undefined) {
      phaseB.reloadErr = reloadErr;
    }
    return phaseB;
  }

  if (!sawCleanRead) {
    // isVisible() never once evaluated — the page is wedged in a way the
    // closed-target classifier does not recognise. CANT-RUN is the honest
    // verdict; a rail-regression FAIL would assert something we never saw.
    return unverifiable();
  }

  if (reloads > 0 && !cleanReadPostReload) {
    // The recovery draw ran but NOT ONE post-reload read settled — the
    // transport wedged or died (in ways the dead-classifier did not match)
    // after the reload. `absent` would assert "did not appear" on reads
    // that never executed, in the window that counted; CANT-RUN is honest.
    return unverifiable();
  }

  return absentVerdict();
}

/**
 * Map a rail verdict onto the Result union. Pure — the wire prefixes are
 * authored here and here alone, so the workflow's `case "${RESULT_LINE}"`
 * classifier (`RESULT: PASS*` -> info, `RESULT: FAIL*` -> BLOCK=1,
 * `RESULT: CANT-RUN*` -> warning) needs zero YAML changes.
 */
export function railVerdictToResult(verdict: RailVerdict, convId: string): Result {
  switch (verdict.kind) {
    case "appeared": {
      const reloadNote = verdict.reloadErr
        ? ` reload_err=${verdict.reloadErr}`
        : "";
      return {
        kind: "PASS",
        detail:
          `fresh conversation persisted and appeared in the rail ` +
          `(via=${verdict.via} elapsed=${Math.round(verdict.elapsedMs / 1000)}s ` +
          `checks=${verdict.checks}${reloadNote})`,
      };
    }
    case "unverifiable":
      return { kind: "CANT-RUN", reason: verdict.reason };
    case "absent": {
      const reloadNote = verdict.reloadErr ? ` reload_err=${verdict.reloadErr}` : "";
      return {
        kind: "FAIL",
        detail:
          `conversation ${convId} persisted but did NOT appear in the rail ` +
          `(elapsed=${Math.round(verdict.elapsedMs / 1000)}s ` +
          `budget=${Math.round(verdict.budgetMs / 1000)}s ` +
          `checks=${verdict.checks} read_errors=${verdict.readErrs} ` +
          `reloads=${verdict.reloads} rail_state=${verdict.railState} ` +
          `rpc_row=${verdict.rpcRow} ` +
          `active_repo=${verdict.activeRepo}${reloadNote}) ` +
          `(the #5391/#5436 class, #9581)`,
      };
    }
  }
}

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
      const dryNav = await page.goto(`${cfg.productionUrl}${CHAT_NEW_PATH}`, {
        waitUntil: "domcontentloaded",
      });
      // #7969: same blindness as the composer wait, same remedy.
      const railFailed = await awaitVisibleOrDiagnose(
        () => page.waitForSelector(RAIL, { timeout: 20_000 }),
        page,
        dryNav,
        "rail",
      );
      if (railFailed) return railFailed;
      return {
        kind: "PASS",
        detail: "dry-run: authenticated app shell rendered, no mutation",
      };
    }

    // Capture a high-water mark BEFORE the send so the materialization poll
    // below only ever matches a FRESH row, never a leftover from a prior run.
    const sinceIso = new Date().toISOString();

    // Start a fresh conversation and send ONE benign message.
    const nav = await page.goto(`${cfg.productionUrl}${CHAT_NEW_PATH}`, {
      waitUntil: "domcontentloaded",
    });
    const input = page.getByRole(COMPOSER_ROLE).first();
    // #7969: report WHAT WAS ON THE PAGE, not merely that a locator timed out.
    const composerFailed = await awaitVisibleOrDiagnose(
      () => input.waitFor({ state: "visible", timeout: 20_000 }),
      page,
      nav,
      "composer",
    );
    if (composerFailed) return composerFailed;
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
    // (the deterministic fresh-conversation fix — #5449 — replaced the URL
    // navigation with in-place materialization). The old
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
    // #9581: bounded observe -> scope probe -> one reload -> observe under
    // RAIL_ASSERT_TOTAL_BUDGET_MS, never the single-shot 20s waitFor that
    // read ordinary rail-listing lag as a blocking FAIL. FAIL stays loud: a
    // row absent from the rail's own scoped data (rpc_row=no) or absent
    // after the recovery draw still FAILs -> BLOCK=1.
    const railRow = page.locator(`${RAIL} a[href$="/dashboard/chat/${convId}"]`);
    const verdict = await assertRailRowVisible({
      railRow,
      page,
      nav,
      supabase,
      convId,
      productionUrl: cfg.productionUrl,
    });
    const result: Result = railVerdictToResult(verdict, convId);

    // Teardown as the synthetic user's own session (RLS), regardless of result.
    const teardown = await teardownConversation(supabase, cfg, verified, convId);
    if (teardown.kind === "CANT-RUN") {
      // A rail FAIL must not be downgraded to non-blocking CANT-RUN — the
      // regression signal outranks the teardown breach, so the teardown
      // reason rides inside the FAIL detail instead (#9581 review). For
      // PASS the breach IS the result (nothing blocked, operator alerted);
      // for a rail CANT-RUN the two diagnostics compose rather than the
      // rail one being dropped.
      const teardownTag = `teardown=${scrubLine(teardown.reason).slice(0, 120)}`;
      if (result.kind === "FAIL") {
        return { kind: "FAIL", detail: `${result.detail} ${teardownTag}` };
      }
      if (result.kind === "CANT-RUN") {
        return { kind: "CANT-RUN", reason: `${result.reason} ${teardownTag}` };
      }
      return teardown;
    }

    return result;
  } finally {
    // Guarded: on a wedged transport (the same class the reload's
    // __wedge__ backstop exists for) an unbounded close() would either
    // hang past the RESULT line — no-line → BLOCK=1 with zero diagnostics —
    // or throw a verdict away into main's CANT-RUN catch. Best-effort,
    // bounded.
    if (browser) {
      await Promise.race([
        browser.close().catch(() => undefined),
        new Promise<void>((r) => setTimeout(r, 10_000)),
      ]);
    }
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

/** The RESULT line builder, exported so the redaction can be tested as a COMPOSITION. */
export function emitLine(result: Result): string {
  return result.kind === "CANT-RUN"
    ? `RESULT: CANT-RUN:${redact(result.reason)}`
    : `RESULT: ${result.kind} — ${redact(result.detail)}`;
}

function emit(result: Result): void {
  // Delegates to emitLine: the wire format lives in exactly ONE place —
  // the exported, test-pinned builder. An inline copy here would let the
  // shipped string drift from the asserted one while the suite stays green
  // (the endpoints-covered-wire-not class). redact() inside emitLine scrubs
  // any captured value that reached EITHER string; the CANT-RUN branch was
  // previously unredacted while its sibling was — an asymmetry that was
  // latent while reasons were fixed tokens, and becomes load-bearing now
  // that waitFailureState() puts live page state into a reason (#7969).
  console.log(emitLine(result));
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
