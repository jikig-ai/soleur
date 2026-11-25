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
 *
 * Fixture-only branches (answered only when the request names a fixture id, so no other spec changes):
 * - HELD_E2E_USERS (#12714): the held-files Settings states.
 * - EGRESS_E2E_USERS (#12605): the Scope Grants web-egress states. The page's own reads are `/auth/v1/user`,
 *   `user_session_state`, `workspace_members` and `workspaces`. The tenant `web_egress` read goes through
 *   `getFreshTenantClient` in lib/supabase/tenant.ts: `mintFounderJwt` (admin getUserById, `runtime_mint_intent`,
 *   `generate_link`, `verify`), then `denyProbe` (`is_jti_denied`), then the `get_workspace_web_egress` RPC.
 * Every other request gets a 404 and one `[mock-supabase] unhandled` stderr line per actor, method and path.
 */
import http from "node:http";
import { TC_VERSION } from "../lib/legal/tc-version";
import { sanitizeForLog } from "../lib/log-sanitize";

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

/**
 * Mint a synthetic JWT-shaped string with a real `iat` claim. The
 * middleware's revocation gate (#4307) decodes the JWT payload to extract
 * `iat` and fail-CLOSES the session if it can't. A literal string token
 * (the prior shape) made every authenticated e2e route redirect to
 * `/login?revoked=session-error`. The signature is intentionally inert —
 * the edge decoder is `Unsafe` (no signature check); the test mock
 * trusts itself.
 */
function mintMockJwt(nowSeconds: number, user: MockUser = MOCK_USER, jti?: string): string {
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
    ...(jti === undefined ? {} : { jti }),
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
 * #12714 Settings held-files card (e2e/settings-kb-sync-held.e2e.ts). Synthesized fixtures
 * (cq-test-fixtures-synthesized-only): one user per card state, each answered ONLY for its own id, so no other spec
 * sees these rows (MOCK_USER and MOCK_FOUNDER keep the 404 defaults). Solo users own the workspace whose id is their
 * own; the two members belong to a team workspace through `user_session_state` + `workspace_members`.
 * `ownerRpc` is the `is_workspace_owner` answer; "error" is the V10 role-unknown case (a 500 from the RPC).
 */
const HELD_ORG_ID = "00000000-0000-4000-8000-00000000c0a0";
export const HELD_ORG_NAME = "Acme Team";
const HELD_TEAM_WS = "00000000-0000-4000-8000-0000000012b1";
const HELD_TEAM_WS_ZERO = "00000000-0000-4000-8000-0000000012b2";

interface HeldUserFixture {
  readonly id: string;
  /** null: solo (the workspace id is the user id). */
  readonly teamWorkspaceId: string | null;
  readonly ownerRpc: boolean | "error";
}

export const HELD_E2E_USERS = {
  ownerHeld: { id: "00000000-0000-4000-8000-0000000012a1", teamWorkspaceId: null, ownerRpc: true },
  ownerZero: { id: "00000000-0000-4000-8000-0000000012a2", teamWorkspaceId: null, ownerRpc: true },
  ownerNull: { id: "00000000-0000-4000-8000-0000000012a3", teamWorkspaceId: null, ownerRpc: true },
  ownerPullBlocked: { id: "00000000-0000-4000-8000-0000000012a4", teamWorkspaceId: null, ownerRpc: true },
  ownerCap: { id: "00000000-0000-4000-8000-0000000012a5", teamWorkspaceId: null, ownerRpc: true },
  roleUnknown: { id: "00000000-0000-4000-8000-0000000012a6", teamWorkspaceId: null, ownerRpc: "error" },
  memberHeld: { id: "00000000-0000-4000-8000-0000000012a7", teamWorkspaceId: HELD_TEAM_WS, ownerRpc: false },
  memberZero: { id: "00000000-0000-4000-8000-0000000012a8", teamWorkspaceId: HELD_TEAM_WS_ZERO, ownerRpc: false },
} as const satisfies Record<string, HeldUserFixture>;

/** `workspaces` rows by id: the repo columns, the held count (migration 187) and the pull-blocked reason (188). */
export const HELD_E2E_WORKSPACES: Readonly<Record<string, Readonly<Record<string, unknown>>>> = (() => {
  const row = (heldFiles: number | null, pullBlocked: string | null = null) => ({
    organization_id: HELD_ORG_ID,
    logo_path: null,
    repo_url: "https://github.com/acme/widgets",
    repo_status: "ready",
    repo_last_synced_at: "2026-11-16T09:00:00Z",
    github_installation_id: 4242,
    kb_sync_held_files: heldFiles,
    kb_sync_held_checked_at: "2026-11-16T09:00:00Z",
    kb_sync_pull_blocked: pullBlocked,
  });
  const u = HELD_E2E_USERS;
  return {
    [u.ownerHeld.id]: row(3),
    [u.ownerZero.id]: row(0),
    [u.ownerNull.id]: row(null),
    [u.ownerPullBlocked.id]: row(2, "untracked_collision"),
    [u.ownerCap.id]: row(10_000),
    [u.roleUnknown.id]: row(3),
    [HELD_TEAM_WS]: row(3),
    [HELD_TEAM_WS_ZERO]: row(0),
  };
})();

const HELD_USERS_BY_ID: ReadonlyMap<string, HeldUserFixture> = new Map(
  Object.values(HELD_E2E_USERS).map((u) => [u.id, u]),
);

/**
 * A signed-in session for a fixture user (held-files or egress); each spec builds its storage state from it.
 * `/auth/v1/token` refresh accepts held-files fixtures only. An egress fixture's session lasts 24 hours, well past
 * one test, and a refresh would get a 400 and sign the test out loudly rather than pass (ruling R5-r).
 */
export function heldSessionFor(userId: string) {
  const user: MockUser = { ...MOCK_USER, id: userId, email: `held-${userId.slice(-4)}@example.com` };
  return {
    access_token: mintMockJwt(MOCK_NOW_SECONDS, user),
    token_type: "bearer",
    expires_in: 86400,
    expires_at: MOCK_NOW_SECONDS + 86400,
    refresh_token: `held-refresh-${userId}`,
    user,
  };
}

/**
 * #12605 Scope Grants web-egress disclosures (e2e/nav-states-scope-grants-web-egress.e2e.ts). Synthesized fixtures
 * (cq-test-fixtures-synthesized-only), answered ONLY for these ids so no other spec sees them. Each is the Owner of a
 * solo workspace whose id is its own, with a null organization so the dialog renders its longest ("unknown") copy.
 * `jti` is the UUID the tenant mint requires in the minted token.
 */
export const EGRESS_E2E_USERS = {
  on: { id: "00000000-0000-4000-8000-0000000012c1", jti: "00000000-0000-4000-8000-0000000012d1" },
  off: { id: "00000000-0000-4000-8000-0000000012c2", jti: "00000000-0000-4000-8000-0000000012d2" },
} as const;

type EgressUserFixture = (typeof EGRESS_E2E_USERS)[keyof typeof EGRESS_E2E_USERS];

const EGRESS_E2E_WORKSPACES: Readonly<
  Record<string, { readonly organization_id: null; readonly name: string; readonly web_egress: boolean }>
> = {
  [EGRESS_E2E_USERS.on.id]: { organization_id: null, name: "Egress On Workspace", web_egress: true },
  [EGRESS_E2E_USERS.off.id]: { organization_id: null, name: "Egress Off Workspace", web_egress: false },
};

const EGRESS_FIXTURES: readonly EgressUserFixture[] = Object.values(EGRESS_E2E_USERS);
const EGRESS_USERS_BY_ID: ReadonlyMap<string, EgressUserFixture> = new Map(EGRESS_FIXTURES.map((u) => [u.id, u]));
const egressHashedToken = (id: string) => `egress-hashed-token-${id}`;

/** The `eq.` value of a PostgREST filter param, or null. */
function eqParam(url: URL, col: string): string | null {
  const v = url.searchParams.get(col);
  return v?.startsWith("eq.") ? v.slice(3) : null;
}

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
    // One stderr line per distinct actor, method and path: the mock runs in the Playwright runner, so it reaches the CI log.
    const unhandled = new Set<string>();
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

      function notFound() {
        if (res.headersSent) return;
        const actor = eqParam(url, "user_id") ?? bearerSub(req.headers.authorization ?? "") ?? "-";
        const key = `${actor} ${req.method} ${url.pathname}`;
        if (!unhandled.has(key)) {
          unhandled.add(key);
          // The key carries request-supplied text (query, bearer claim, path), so strip control characters first.
          process.stderr.write(`[mock-supabase] unhandled actor=${sanitizeForLog(key, 300)}\n`);
        }
        res.writeHead(404);
        res.end(JSON.stringify({ error: "Not found", path: url.pathname }));
      }

      /**
       * Run a handler on the parsed JSON body; a handler declines with `notFound()`. Always call it as
       * `return withJsonBody(...)`: without the synchronous return the catch-all writes first and the late write throws.
       */
      function withJsonBody(handler: (body: Record<string, unknown>) => void): void {
        void readBody(req)
          .then((raw) => {
            // A body that is not a JSON object is a request the mock does not answer.
            let body: unknown;
            try {
              body = JSON.parse(raw || "{}");
            } catch {
              return notFound();
            }
            if (body === null || typeof body !== "object" || Array.isArray(body)) return notFound();
            handler(body as Record<string, unknown>);
          })
          .catch((err: unknown) => {
            // A handler or stream failure is a defect in the mock, not a missing branch: log it and answer 500, so the
            // runner log does not point at an `unhandled` line for a branch that exists.
            process.stderr.write(
              `[mock-supabase] handler error ${req.method} ${sanitizeForLog(url.pathname, 200)}: ${sanitizeForLog(String(err), 300)}\n`,
            );
            if (res.destroyed) return;
            if (res.headersSent) {
              if (!res.writableEnded) res.end(); // writeHead ran before the throw; close the response so it cannot hang.
              return;
            }
            res.writeHead(500);
            res.end(JSON.stringify({ error: "mock handler error", path: url.pathname }));
          });
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
        const sub = bearerSub(auth);
        res.writeHead(200);
        res.end(
          JSON.stringify(
            sub === MOCK_FOUNDER.id
              ? MOCK_FOUNDER
              : sub !== null && (HELD_USERS_BY_ID.has(sub) || EGRESS_USERS_BY_ID.has(sub))
                ? heldSessionFor(sub).user
                : MOCK_USER,
          ),
        );
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
        // Any grant other than a refresh is not modelled: a 400, never a session.
        if (grantType !== "refresh_token") {
          res.writeHead(400);
          res.end(JSON.stringify({ error: "unsupported_grant_type", error_description: "Not modelled" }));
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
            const heldId =
              typeof refreshToken === "string" && refreshToken.startsWith("held-refresh-")
                ? refreshToken.slice("held-refresh-".length)
                : null;
            const session =
              heldId !== null && HELD_USERS_BY_ID.has(heldId)
                ? heldSessionFor(heldId)
                : [MOCK_FOUNDER_SESSION, MOCK_SESSION].find((x) => x.refresh_token === refreshToken);
            if (session === undefined) {
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

      // #12605: the tenant mint path (mintFounderJwt in lib/supabase/tenant.ts), for EGRESS_E2E_USERS only, so the page
      // reads `web_egress` through the real fail-closed resolver. Anything else reaches the 404 it always did.
      if (req.method === "GET" && url.pathname.startsWith("/auth/v1/admin/users/")) {
        const id = url.pathname.slice("/auth/v1/admin/users/".length);
        if (EGRESS_USERS_BY_ID.has(id)) {
          res.writeHead(200);
          res.end(JSON.stringify(heldSessionFor(id).user));
          return;
        }
      }
      if (req.method === "POST" && url.pathname === "/auth/v1/admin/generate_link") {
        return withJsonBody((body) => {
          const fixture = EGRESS_FIXTURES.find((u) => heldSessionFor(u.id).user.email === body.email);
          if (!fixture) return notFound();
          // auth-js reads hashed_token from the top level, alongside the user fields.
          res.writeHead(200);
          res.end(JSON.stringify({ ...heldSessionFor(fixture.id).user, hashed_token: egressHashedToken(fixture.id) }));
        });
      }
      if (req.method === "POST" && url.pathname === "/auth/v1/verify") {
        return withJsonBody((body) => {
          const fixture = EGRESS_FIXTURES.find((u) => egressHashedToken(u.id) === body.token_hash);
          if (!fixture) return notFound();
          const session = heldSessionFor(fixture.id);
          res.writeHead(200);
          res.end(
            JSON.stringify({
              ...session,
              access_token: mintMockJwt(Math.floor(Date.now() / 1000), session.user, fixture.jti),
            }),
          );
        });
      }

      // ---- PostgREST endpoints ----

      if (req.method === "POST" && url.pathname === "/rest/v1/runtime_mint_intent") {
        return withJsonBody((body) => {
          if (typeof body.user_id !== "string" || !EGRESS_USERS_BY_ID.has(body.user_id)) return notFound();
          res.writeHead(201);
          res.end();
        });
      }

      // #12714 held-files fixtures (HELD_E2E_USERS): answered only when the filter names a fixture id, else falls
      // through to the defaults below (which 404 these tables), so no other spec changes behaviour.
      if (url.pathname === "/rest/v1/user_session_state") {
        const egressFixture = EGRESS_USERS_BY_ID.get(eqParam(url, "user_id") ?? "");
        if (egressFixture) {
          // Mirrors the production read order; not load-bearing for these null-org fixtures (ruling R2-r). Without it the
          // 404 sends resolveCurrentWorkspaceId down its error fallback (reportSilentFallback, then userId), the same id,
          // and the egress card's pointer read throws to `collection: "unknown"`, which equals the null-org result. A
          // fixture with an organization_id would make this branch load-bearing.
          sendRows([{ current_workspace_id: egressFixture.id, current_organization_id: null }]);
          return;
        }
        const fixture = HELD_USERS_BY_ID.get(eqParam(url, "user_id") ?? "");
        if (fixture) {
          sendRows(
            fixture.teamWorkspaceId
              ? [{ current_workspace_id: fixture.teamWorkspaceId, current_organization_id: HELD_ORG_ID }]
              : [],
          );
          return;
        }
      }
      if (url.pathname === "/rest/v1/workspace_members") {
        const egressFixture = EGRESS_USERS_BY_ID.get(eqParam(url, "user_id") ?? "");
        if (egressFixture) {
          const ws = eqParam(url, "workspace_id");
          // Only the probe that names the fixture's own workspace gets a row; a read with no workspace_id filter gets none.
          sendRows(
            ws === egressFixture.id
              ? [{ user_id: egressFixture.id, workspace_id: egressFixture.id, role: "owner" }]
              : [],
          );
          return;
        }
        const fixture = HELD_USERS_BY_ID.get(eqParam(url, "user_id") ?? "");
        if (fixture) {
          // The membership probe (workspace_id + user_id): a member row only for the fixture's own team workspace.
          const ws = eqParam(url, "workspace_id");
          sendRows(
            fixture.teamWorkspaceId && ws === fixture.teamWorkspaceId
              ? [{ user_id: fixture.id, workspace_id: ws }]
              : [],
          );
          return;
        }
      }
      if (url.pathname === "/rest/v1/workspaces") {
        const id = eqParam(url, "id") ?? "";
        const row = HELD_E2E_WORKSPACES[id] ?? EGRESS_E2E_WORKSPACES[id];
        if (row) {
          sendRows([row]);
          return;
        }
      }
      if (url.pathname === "/rest/v1/organizations" && eqParam(url, "id") === HELD_ORG_ID) {
        sendRows([{ name: HELD_ORG_NAME, owner_user_id: null }]);
        return;
      }

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

      // #12714: the owner check the Settings identity resolver makes (supabase.rpc("is_workspace_owner")), answered
      // only for a held-files fixture user; "error" is the V10 role-unknown case.
      if (url.pathname === "/rest/v1/rpc/is_workspace_owner") {
        const fixture = HELD_USERS_BY_ID.get(bearerSub(req.headers.authorization ?? "") ?? "");
        if (fixture) {
          if (fixture.ownerRpc === "error") {
            res.writeHead(500);
            res.end(JSON.stringify({ code: "XX000", message: "e2e: owner check failed" }));
          } else {
            res.writeHead(200);
            res.end(JSON.stringify(fixture.ownerRpc));
          }
          return;
        }
      }

      // #12605: the post-mint deny probe (`denyProbe` in `getFreshTenantClient`), for the fixtures' own jti values only.
      if (req.method === "POST" && url.pathname === "/rest/v1/rpc/is_jti_denied") {
        return withJsonBody((body) => {
          if (!EGRESS_FIXTURES.some((u) => u.jti === body.p_jti)) return notFound();
          res.writeHead(200);
          res.end("false");
        });
      }

      // #12605: the row's `web_egress` for the caller's own workspace, else null, as the real RPC answers a non-member.
      if (req.method === "POST" && url.pathname === "/rest/v1/rpc/get_workspace_web_egress") {
        const fixture = EGRESS_USERS_BY_ID.get(bearerSub(req.headers.authorization ?? "") ?? "");
        if (fixture) {
          return withJsonBody((body) => {
            const webEgress =
              body.p_workspace_id === fixture.id ? (EGRESS_E2E_WORKSPACES[fixture.id]?.web_egress ?? null) : null;
            res.writeHead(200);
            res.end(JSON.stringify(webEgress));
          });
        }
      }

      // ---- Realtime (WebSocket upgrade attempt — reject gracefully) ----

      if (url.pathname.startsWith("/realtime/")) {
        res.writeHead(200);
        res.end(JSON.stringify({ message: "realtime not supported in mock" }));
        return;
      }

      // ---- Catch-all ----
      notFound();
    });

    server.on("error", reject);
    server.listen(port, () => resolve(server));
  });
}
