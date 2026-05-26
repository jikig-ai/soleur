// Shared Supabase HTTP-route mocks for e2e tests on the `authenticated`
// Playwright project. Three call sites share the same auth + realtime
// short-circuit (PR-A: cc-soleur-go-bubbles, plus pre-existing start-fresh-
// onboarding and start-fresh-conversations-rail). Per-test data-layer routes
// (`/rest/v1/users*`, `/rest/v1/conversations*`, `/rest/v1/messages*`) stay
// inline in each spec — their response bodies legitimately diverge per
// test seam.
//
// Source of truth for fixture shapes: `e2e/mock-supabase.ts` (the server-side
// stand-in used when tests run against a real Playwright dev server).

import type { Page } from "@playwright/test";
import { MOCK_USER, MOCK_SESSION, AUTH_COOKIE_NAME } from "../mock-supabase";

/**
 * Seed `localStorage["sb-localhost-auth-token"]` with `MOCK_SESSION` BEFORE
 * any page script runs. Without this, the Supabase JS client reads no stored
 * session and short-circuits `auth.getUser()` before the HTTP `/auth/v1/user`
 * mock is hit — every downstream component then sees the unauthenticated
 * branch even though `page.route` is wired correctly.
 */
export async function injectFakeSupabaseSession(page: Page): Promise<void> {
  const json = JSON.stringify(MOCK_SESSION);
  await page.addInitScript(
    ({ json, cookieName }) => {
      localStorage.setItem(cookieName, json);
    },
    { json, cookieName: AUTH_COOKIE_NAME },
  );
}

/**
 * Intercept the always-identical auth + realtime routes:
 *   - `/auth/v1/user`         → MOCK_USER
 *   - `/auth/v1/token*`       → MOCK_SESSION
 *   - `/realtime/**`          → empty 200 (prevents WebSocket retry loops)
 *
 * The Realtime stub does NOT collide with cc-soleur-go's `/ws` interceptor —
 * Supabase Realtime uses `/realtime/**` and cc-soleur-go uses `/ws`. Verified
 * against `apps/web-platform/lib/ws-client.ts:496`.
 */
export async function mockSupabaseAuth(page: Page): Promise<void> {
  await page.route("**/auth/v1/user", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(MOCK_USER),
    }),
  );

  await page.route("**/auth/v1/token*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(MOCK_SESSION),
    }),
  );

  await page.route("**/realtime/**", (route) =>
    route.fulfill({ status: 200, contentType: "text/plain", body: "" }),
  );
}
