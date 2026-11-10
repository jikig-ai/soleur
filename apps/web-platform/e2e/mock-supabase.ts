/**
 * Lightweight mock Supabase HTTP server for E2E tests.
 *
 * Handles the minimum set of Supabase API endpoints needed by the web platform:
 * - Auth: getUser, token refresh
 * - REST: users table (T&C check, workspace lookup, onboarding state), conversations,
 *   and empty `[]` defaults for inbox_item, email_triage_items and legal_acceptance
 *   (an inbox visit renders an empty inbox instead of a 500)
 *
 * Two synthesized users, each with its own session:
 * - MOCK_USER ("test-user-id"): the default for every spec (`e2e/.auth/user.json`).
 * - MOCK_FOUNDER (a fixed UUID): the founder legal-acceptance surface's configured
 *   founder (`LEGAL_ACCEPTANCE_FOUNDER_ID` in playwright.config.ts mirrors its id;
 *   `e2e/.auth/founder.json`). `/auth/v1/user` picks the user by the bearer JWT's
 *   `sub` claim; `/auth/v1/token` refresh picks the session by `refresh_token`
 *   and answers 400 for an unknown one, so a silent identity swap fails loudly.
 */
import http from "node:http";
import { TC_VERSION } from "../lib/legal/tc-version";

export const MOCK_USER = {
  id: "test-user-id",
  aud: "authenticated",
  role: "authenticated",
  email: "test@e2e.com",
  email_confirmed_at: "2024-01-01T00:00:00Z",
  phone: "",
  confirmed_at: "2024-01-01T00:00:00Z",
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: {},
  identities: [],
  created_at: "2024-01-01T00:00:00Z",
  updated_at: "2024-01-01T00:00:00Z",
};

/**
 * Mint a synthetic JWT-shaped string with a real `iat` claim. The
 * middleware's revocation gate (#4307) decodes the JWT payload to extract
 * `iat` and fail-CLOSES the session if it can't. A literal string token
 * (the prior shape) made every authenticated e2e route redirect to
 * `/login?revoked=session-error`. The signature is intentionally inert —
 * the edge decoder is `Unsafe` (no signature check); the test mock
 * trusts itself.
 */
type MockUser = typeof MOCK_USER;

/**
 * The legal-acceptance founder (#12197). Synthesized fixture
 * (cq-test-fixtures-synthesized-only): a fixed example UUID on the reserved
 * example.com domain. Keep the id in lockstep with LEGAL_ACCEPTANCE_FOUNDER_ID
 * in the `e2e-auth` webServer env (playwright.config.ts).
 */
export const MOCK_FOUNDER: MockUser = {
  ...MOCK_USER,
  id: "00000000-0000-4000-8000-0000000000f0",
  email: "founder@example.com",
};

export function mintMockJwt(nowSeconds: number, user: MockUser = MOCK_USER): string {
  const b64url = (obj: object) =>
    Buffer.from(JSON.stringify(obj))
      .toString("base64")
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  const header = b64url({ alg: "none", typ: "JWT" });
  const payload = b64url({
    sub: user.id,
    aud: "authenticated",
    role: "authenticated",
    iat: nowSeconds,
    exp: nowSeconds + 86400,
  });
  return `${header}.${payload}.mock-signature`;
}

const MOCK_NOW_SECONDS = Math.floor(Date.now() / 1000);

export const MOCK_SESSION = {
  access_token: mintMockJwt(MOCK_NOW_SECONDS),
  token_type: "bearer",
  expires_in: 86400,
  expires_at: MOCK_NOW_SECONDS + 86400,
  refresh_token: "test-refresh-token",
  user: MOCK_USER,
};

export const MOCK_FOUNDER_SESSION = {
  access_token: mintMockJwt(MOCK_NOW_SECONDS, MOCK_FOUNDER),
  token_type: "bearer",
  expires_in: 86400,
  expires_at: MOCK_NOW_SECONDS + 86400,
  refresh_token: "test-founder-refresh-token",
  user: MOCK_FOUNDER,
};

/**
 * The `sub` claim of an unsigned bearer JWT, or null. Keyed on `sub`, never on
 * token-string equality: tokens embed Date.now() at module load, so a second
 * instance of this module (the config's import, a worker) mints other strings.
 */
function bearerSub(authorization: string): string | null {
  const payload = authorization.replace(/^Bearer\s+/, "").split(".")[1];
  if (!payload) return null;
  try {
    const json = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { sub?: unknown };
    return typeof json.sub === "string" ? json.sub : null;
  } catch {
    return null;
  }
}

/** Buffer a request body as text (the refresh grant carries its token in the JSON body). */
function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

/** Cookie name the Supabase SSR client uses for localhost URLs. */
export const AUTH_COOKIE_NAME = "sb-localhost-auth-token";

export function startMockSupabase(port: number): Promise<http.Server> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const url = new URL(req.url!, `http://localhost:${port}`);
      const accept = req.headers.accept ?? "";
      // PostgREST .single() sends this Accept header and expects an object, not an array
      const wantsSingle = accept.includes("application/vnd.pgrst.object+json");

      // CORS headers (Supabase client sends cross-origin requests)
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Headers", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
      res.setHeader("Content-Type", "application/json");

      if (req.method === "OPTIONS") {
        res.writeHead(200);
        res.end();
        return;
      }

      /** Respond with array or single object based on PostgREST Accept header. */
      function sendRows(rows: Record<string, unknown>[]) {
        res.writeHead(200);
        res.end(JSON.stringify(wantsSingle ? rows[0] ?? {} : rows));
      }

      // ---- Auth endpoints ----

      if (url.pathname === "/auth/v1/user") {
        // Only return a user if an Authorization header is present.
        // Without this check, unauthenticated pages (login, signup) get
        // unexpected "authenticated" responses from the client-side Supabase.
        const auth = req.headers.authorization ?? "";
        if (!auth.startsWith("Bearer ")) {
          res.writeHead(401);
          res.end(JSON.stringify({ error: "unauthorized", message: "No authorization header" }));
          return;
        }
        res.writeHead(200);
        res.end(JSON.stringify(bearerSub(auth) === MOCK_FOUNDER.id ? MOCK_FOUNDER : MOCK_USER));
        return;
      }

      if (url.pathname === "/auth/v1/token") {
        const grantType = url.searchParams.get("grant_type");
        // Code exchange (PKCE) should fail — the callback route expects this
        // for invalid codes. Only session refresh succeeds.
        if (grantType === "pkce") {
          res.writeHead(400);
          res.end(JSON.stringify({ error: "invalid_grant", error_description: "Invalid code" }));
          return;
        }
        // Session refresh: the session follows the refresh token in the body.
        // An unknown token is a 400, so a silent identity swap fails loudly.
        void readBody(req).then(
          (raw) => {
            let refreshToken: unknown;
            try {
              refreshToken = (JSON.parse(raw || "{}") as { refresh_token?: unknown }).refresh_token;
            } catch {
              refreshToken = undefined;
            }
            const session =
              refreshToken === MOCK_FOUNDER_SESSION.refresh_token
                ? MOCK_FOUNDER_SESSION
                : refreshToken === MOCK_SESSION.refresh_token
                  ? MOCK_SESSION
                  : null;
            if (session === null) {
              res.writeHead(400);
              res.end(JSON.stringify({ error: "invalid_grant", error_description: "Invalid Refresh Token" }));
              return;
            }
            res.writeHead(200);
            res.end(JSON.stringify(session));
          },
          () => {
            res.writeHead(400);
            res.end(JSON.stringify({ error: "invalid_request", error_description: "Unreadable body" }));
          },
        );
        return;
      }

      // ---- PostgREST endpoints ----

      if (url.pathname === "/rest/v1/users") {
        const select = url.searchParams.get("select") ?? "";

        if (select.includes("tc_accepted_version")) {
          // Import the canonical constant so this stays in sync when
          // TC_VERSION is bumped — middleware compares the user's stored
          // tc_accepted_version against TC_VERSION and redirects to
          // /accept-terms on mismatch, which breaks every authenticated
          // dashboard test. PR #3984 hit this when TC_VERSION moved
          // 1.0.0 -> 2.0.0 with the mock still hardcoded to 1.0.0.
          sendRows([{ tc_accepted_version: TC_VERSION }]);
          return;
        }

        if (select.includes("workspace_path")) {
          // KB tree API uses this to find the workspace directory.
          // For E2E tests the /api/kb/tree call is intercepted by page.route()
          // so this path is only hit if a test forgets to set up interception.
          sendRows([{
            workspace_path: "/tmp/soleur-e2e-nonexistent",
            workspace_status: "ready",
            repo_status: "connected",
          }]);
          return;
        }

        if (select.includes("onboarding_completed_at")) {
          sendRows([{
            onboarding_completed_at: "2024-01-01T00:00:00Z",
            pwa_banner_dismissed_at: "2024-01-01T00:00:00Z",
            // PR-G (#3947): useOnboarding widened its .select() to include
            // this column. Returning a non-null value keeps the runtime
            // explainer banner dismissed in tests, matching the existing
            // pwa-banner-dismissed convention above.
            runtime_explainer_dismissed_at: "2024-01-01T00:00:00Z",
          }]);
          return;
        }

        // Fallback for unrecognized select queries
        sendRows([{}]);
        return;
      }

      if (url.pathname === "/rest/v1/conversations") {
        res.writeHead(200);
        res.end(JSON.stringify([]));
        return;
      }

      if (url.pathname === "/rest/v1/messages") {
        res.writeHead(200);
        res.end(JSON.stringify([]));
        return;
      }

      // Empty defaults for the Inbox sources (GET /api/inbox) and the founder's
      // legal_acceptance rows (#12197): an inbox visit renders an empty inbox,
      // and a founder with no recorded decision sees every declared text pending.
      if (
        url.pathname === "/rest/v1/inbox_item" ||
        url.pathname === "/rest/v1/email_triage_items" ||
        url.pathname === "/rest/v1/legal_acceptance"
      ) {
        sendRows([]);
        return;
      }

      // ---- RPC endpoints ----

      // The conversation rail now reads via list_conversations_enriched (mig 125,
      // SECURITY INVOKER) instead of the direct conversations + messages queries.
      // Default to an empty rail (mirrors the /rest/v1/conversations → [] default
      // above); tests seeding a populated rail override this via page.route.
      if (url.pathname === "/rest/v1/rpc/list_conversations_enriched") {
        res.writeHead(200);
        res.end(JSON.stringify([]));
        return;
      }

      // #4307 revocation gate: middleware calls this on every authenticated
      // request and fail-CLOSES with 503 on any error. Return a not-revoked
      // row so the gate passes for the synthetic e2e user. The RPC's real
      // SECURITY DEFINER body lives in mig 067_workspace_member_revocation_lookup.
      if (url.pathname === "/rest/v1/rpc/check_my_revocation") {
        res.writeHead(200);
        res.end(
          JSON.stringify([
            { revoked: false, workspace_id: null, reason: null },
          ]),
        );
        return;
      }

      // ---- Realtime (WebSocket upgrade attempt — reject gracefully) ----

      if (url.pathname.startsWith("/realtime/")) {
        res.writeHead(200);
        res.end(JSON.stringify({ message: "realtime not supported in mock" }));
        return;
      }

      // ---- Catch-all ----
      res.writeHead(404);
      res.end(JSON.stringify({ error: "Not found", path: url.pathname }));
    });

    server.on("error", reject);
    server.listen(port, () => resolve(server));
  });
}
