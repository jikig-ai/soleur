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
import { chromium, type Browser } from "@playwright/test";

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

export interface Config {
  supabaseUrl: string;
  anonKey: string;
  password: string;
  expectedUid: string;
  expectedRef: string;
  productionUrl: string;
  dryRun: boolean;
}

function readConfig(): Config {
  const required = (name: string): string => {
    const v = process.env[name];
    if (!v || v.trim() === "") {
      throw new Error(`live-verify: required env ${name} is unset`);
    }
    return v.trim();
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
  };
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
    browser = await chromium.launch();
    const context = await browser.newContext();
    await context.addCookies(
      Array.from(jar.cookies.entries()).map(([name, c]) => ({
        name,
        value: c.value,
        domain: prodHost,
        path: "/",
        httpOnly: true,
        secure: true,
        sameSite: "Lax" as const,
      })),
    );
    const page = await context.newPage();

    if (cfg.dryRun) {
      // Read-only: load the dashboard, confirm authenticated render, create
      // NOTHING, write no artifact.
      await page.goto(`${cfg.productionUrl}/dashboard`, {
        waitUntil: "domcontentloaded",
      });
      await page.waitForSelector(RAIL, { timeout: 20_000 });
      return { kind: "PASS", detail: "dry-run: dashboard rendered, no mutation" };
    }

    // Start a fresh conversation and send ONE benign message — the only path
    // that materializes the conversations row the rail observes via realtime
    // (messages is not in the supabase_realtime publication; conversations is).
    await page.goto(`${cfg.productionUrl}/dashboard/chat/new`, {
      waitUntil: "domcontentloaded",
    });
    const input = page.getByRole("textbox").first();
    await input.waitFor({ state: "visible", timeout: 20_000 });
    await input.fill("live-verify rail check — automated, please ignore");
    await page.getByRole("button", { name: "Send message" }).click();

    // The app navigates to /dashboard/chat/<id> when the conversation
    // materializes. Bound the wait on that observable state (no fixed sleep).
    await page.waitForURL(/\/dashboard\/chat\/[0-9a-f-]{36}$/, {
      timeout: 30_000,
    });
    const convId = page.url().split("/").pop() ?? "";
    if (!/^[0-9a-f-]{36}$/.test(convId)) {
      return { kind: "FAIL", detail: "conversation id not resolvable from URL" };
    }

    // Stamp the crash-reaper marker immediately (own session, RLS).
    await supabase
      .from("conversations")
      .update({ session_id: `live-verify:${runId}` })
      .eq("id", convId)
      .eq("user_id", verified.uid);

    // THE assertion (#5391/#5436): the freshly-created conversation appears in
    // the Recent Conversations rail. Bounded wait on the rail row link.
    const railRow = page.locator(`${RAIL} a[href$="/dashboard/chat/${convId}"]`);
    let railOk = false;
    try {
      await railRow.waitFor({ state: "visible", timeout: 20_000 });
      railOk = true;
    } catch {
      railOk = false;
    }

    const result: Result = railOk
      ? { kind: "PASS", detail: "fresh conversation appeared in the rail" }
      : {
          kind: "FAIL",
          detail: `conversation ${convId} did NOT appear in the rail within budget (the #5391/#5436 class)`,
        };

    // Teardown as the synthetic user's own session (RLS), regardless of result.
    const teardown = await teardownConversation(supabase, cfg, verified, convId);
    if (teardown.kind === "CANT-RUN") return teardown;

    return result;
  } finally {
    if (browser) await browser.close();
  }
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
