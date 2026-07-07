/**
 * Lightweight mock Supabase HTTP server for E2E tests.
 *
 * Handles the minimum set of Supabase API endpoints needed by the web platform:
 * - Auth: getUser, token refresh
 * - REST: users table (T&C check, workspace lookup, onboarding state), conversations
 *
 * All responses use a single test user ("test-user-id") with matching auth tokens.
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
function mintMockJwt(nowSeconds: number): string {
  const b64url = (obj: object) =>
    Buffer.from(JSON.stringify(obj))
      .toString("base64")
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  const header = b64url({ alg: "none", typ: "JWT" });
  const payload = b64url({
    sub: MOCK_USER.id,
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
        res.end(JSON.stringify(MOCK_USER));
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
        res.writeHead(200);
        res.end(JSON.stringify(MOCK_SESSION));
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
