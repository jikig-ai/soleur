import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";

// E2E Phase 5a for plan 2026-04-29-feat-command-center-conversation-nav.
//
// Asserts the user-visible behaviour of the chat-segment ConversationsRail:
//   1. Rail renders with seeded titles inside /dashboard/chat/<id>.
//   2. Active row carries aria-current="page" for the open conversation.
//   3. "View all in Command Center" footer link routes to /dashboard.
//   4. Sign-out completes (redirects to /login) without throwing.
//
// The zero-open-WS-after-signout assertion was REMOVED here. Mock-supabase
// rejects /realtime/* with HTTP 200 instead of upgrading the WebSocket, so
// no Realtime WS ever opens in this environment — `expect.poll(open === 0)`
// passes vacuously regardless of whether the rail's sign-out path runs.
// Carrying a structurally-dead assertion is worse than no assertion (false
// confidence). The load-bearing cross-tenant Realtime isolation + DELETE
// teardown guarantee lives entirely in Phase 5b
// (test/conversations-rail-cross-tenant.integration.test.ts), which
// targets a real Supabase project where WS upgrades succeed.

const SEEDED_CONVERSATIONS = [
  {
    id: "conv-active",
    user_id: "test-user-id",
    repo_url: "https://github.com/acme/repo",
    domain_leader: "cto",
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: "2026-04-28T10:00:00Z",
    created_at: "2026-04-28T09:00:00Z",
    archived_at: null,
  },
  {
    id: "conv-other",
    user_id: "test-user-id",
    repo_url: "https://github.com/acme/repo",
    domain_leader: "cmo",
    session_id: null,
    status: "waiting_for_user",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: "2026-04-27T10:00:00Z",
    created_at: "2026-04-27T09:00:00Z",
    archived_at: null,
  },
];

const SEEDED_MESSAGES = [
  {
    conversation_id: "conv-active",
    role: "user",
    content: "Active rail row title",
    leader_id: null,
    created_at: "2026-04-28T09:01:00Z",
  },
  {
    conversation_id: "conv-other",
    role: "user",
    content: "Other rail row title",
    leader_id: null,
    created_at: "2026-04-27T09:01:00Z",
  },
];

async function setupRailMocks(page: Page) {
  // Authenticated session in localStorage so the JS client doesn't
  // short-circuit auth.getUser() before page.route() fires.
  await page.addInitScript(() => {
    const fakeSession = {
      access_token: "test-access-token",
      token_type: "bearer",
      expires_in: 86400,
      expires_at: Math.floor(Date.now() / 1000) + 86400,
      refresh_token: "test-refresh-token",
      user: {
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
      },
    };
    localStorage.setItem(
      "sb-localhost-auth-token",
      JSON.stringify(fakeSession),
    );
  });

  await page.route("**/auth/v1/user", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
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
      }),
    });
  });

  await page.route("**/auth/v1/token*", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        access_token: "test-access-token",
        token_type: "bearer",
        expires_in: 86400,
        expires_at: Math.floor(Date.now() / 1000) + 86400,
        refresh_token: "test-refresh-token",
      }),
    });
  });

  // The hook reads users.repo_url to scope the conversation list.
  await page.route("**/rest/v1/users*", async (route) => {
    const url = new URL(route.request().url());
    const select = url.searchParams.get("select") ?? "";
    if (select.includes("repo_url")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify([
          { repo_url: "https://github.com/acme/repo" },
        ]),
      });
      return;
    }
    if (select.includes("subscription_status")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify([{ subscription_status: null }]),
      });
      return;
    }
    if (select.includes("onboarding_completed_at")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify([
          {
            onboarding_completed_at: "2024-01-01T00:00:00Z",
            pwa_banner_dismissed_at: "2024-01-01T00:00:00Z",
          },
        ]),
      });
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([{}]),
    });
  });

  await page.route("**/rest/v1/conversations*", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(SEEDED_CONVERSATIONS),
    });
  });

  await page.route("**/rest/v1/messages*", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(SEEDED_MESSAGES),
    });
  });

  await page.route("**/realtime/**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "text/plain",
      body: "",
    });
  });

  await page.route("**/api/admin/check", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ isAdmin: false }),
    });
  });
}

test.describe("ConversationsRail e2e (Phase 5a — mock-supabase)", () => {
  test("renders rail with active row + 'View all' link, then signs out cleanly", async ({
    page,
  }) => {
    await setupRailMocks(page);

    const response = await page.goto("/dashboard/chat/conv-active");
    if (response && response.status() >= 500) {
      test.skip(
        true,
        "Dev server CSS compilation error — skipped in worktree, passes in CI",
      );
    }
    const html = await page.content();
    if (
      html.includes('statusCode":500') ||
      html.includes("ERR_INVALID_URL_SCHEME")
    ) {
      test.skip(
        true,
        "Dev server CSS compilation error — skipped in worktree, passes in CI",
      );
    }

    // Rail row for the active conversation must mount and carry
    // aria-current="page" so screen readers announce the active thread.
    const activeRow = page.getByRole("link", {
      name: /Active rail row title/,
    });
    await expect(activeRow.first()).toBeVisible({ timeout: 15_000 });
    await expect(activeRow.first()).toHaveAttribute("aria-current", "page");

    // Sibling row must NOT be aria-current="page".
    const otherRow = page.getByRole("link", {
      name: /Other rail row title/,
    });
    await expect(otherRow.first()).toBeVisible();
    const otherAria = await otherRow.first().getAttribute("aria-current");
    expect(otherAria).toBeNull();

    // Footer "View all in Command Center" routes to /dashboard.
    await page
      .getByRole("link", { name: /view all in command center/i })
      .first()
      .click();
    await page.waitForURL("**/dashboard", { timeout: 10_000 });

    // Sign-out smoke check: the click must complete and the app must
    // redirect to /login. The try/finally in handleSignOut ensures
    // signOut() runs even if removeAllChannels rejects — the user-visible
    // contract is "click sign out → land on /login," and this assertion
    // gates that contract. WS-teardown semantics are exercised by the
    // Phase 5b integration test against a real Supabase WS endpoint.
    await page.getByRole("button", { name: /sign out/i }).click();
    await page.waitForURL("**/login", { timeout: 10_000 });
  });
});
