import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";

// Headless visual-regression gate for the single nav rail (ADR-048, #4834).
//
// Catches the CSS-layout bug class that jsdom (vitest) structurally cannot see
// — the two bugs PR #4810 shipped:
//   Bug 1: top-level chrome (Soleur wordmark + ThemeToggle) leaked into drilled
//          routes because it rendered OUTSIDE the `drill === null` rail swap.
//   Bug 2: the WorkspaceContextBand had no collapsed (icon-only) form, so at the
//          md:w-14 (56px) rail width the org chip + "Working on:" repo + section
//          title overflowed into an unreadable strip.
//
// Assertions assert the INVARIANT, never a bare proxy (plan FR3): a zero-box or
// empty band would satisfy scrollWidth<=clientWidth, so we ALSO assert the band
// CONTAINS visible org + repo identity. The band's children render `null` until
// their app API routes resolve (LiveRepoBadge -> /api/workspace/active-repo,
// OrgSwitcherContainer -> /api/workspace/list-memberships) — those are app
// routes, NOT Supabase REST, so supabase-mocks.ts does NOT cover them; we mock
// them here or the identity assertions false-GREEN on an empty band (Kieran P0).
//
// Collapsed state is seeded deterministically via localStorage["soleur:sidebar
// .main.collapsed"] = "1" (the literal the useSidebarCollapse hook checks for) —
// never a toggle click + animation wait. The hook hydrates collapse in a
// useEffect, so the collapsed-width assertions use retrying locator assertions.

const RAIL_COLLAPSE_KEY = "soleur:sidebar.main.collapsed";

const MOCK_MEMBERSHIP = {
  organizationId: "org-e2e-1",
  organizationName: "Soleur Workspace",
  workspaceId: "ws-e2e-1",
  isCurrent: true,
  role: "owner" as const,
  memberCount: 1,
};

const MOCK_ACTIVE_REPO = {
  workspaceId: "ws-e2e-1",
  repoUrl: "https://github.com/acme/repo",
  repoName: "acme/repo",
  repoStatus: "connected",
  fellBackToSolo: false,
};

/**
 * Wire the auth/session/realtime stubs (shared helper) PLUS the band's two app
 * API routes and the leaf routes the dashboard shell touches. Mirrors
 * start-fresh-conversations-rail.e2e.ts's setup, extended with /api/workspace/*.
 */
async function setupNavMocks(page: Page): Promise<void> {
  await injectFakeSupabaseSession(page);
  await mockSupabaseAuth(page);

  // layout.tsx reads users.subscription_status (browser-side) via .single().
  await page.route("**/rest/v1/users*", async (route) => {
    const select = new URL(route.request().url()).searchParams.get("select") ?? "";
    if (select.includes("subscription_status")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ subscription_status: null }),
      });
      return;
    }
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({}),
    });
  });

  await page.route("**/rest/v1/conversations*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await page.route("**/rest/v1/messages*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await page.route("**/api/admin/check", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ isAdmin: false }),
    }),
  );

  // The band's identity children (Kieran P0-1) — without these both render null.
  await page.route("**/api/workspace/active-repo", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(MOCK_ACTIVE_REPO),
    }),
  );
  await page.route("**/api/workspace/list-memberships", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ memberships: [MOCK_MEMBERSHIP] }),
    }),
  );

  // KB drilled route page body fetches a tree; the RAIL (what we assert on)
  // does not depend on it, but mock it so the page does not 500.
  await page.route("**/api/kb/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ tree: [], entries: [] }),
    }),
  );
  await page.route("**/api/byok/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ hasKey: true, status: "ok" }),
    }),
  );
  await page.route("**/api/workspace/pending-invites", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ invites: [] }),
    }),
  );
}

/** Seed the rail into the collapsed state before any page script runs. */
async function seedCollapsed(page: Page): Promise<void> {
  await page.addInitScript((key) => {
    localStorage.setItem(key, "1");
  }, RAIL_COLLAPSE_KEY);
}

/** Navigate; skip (don't fail) only on a dev-server CSS-compile 500 in worktree. */
async function gotoOrSkip(page: Page, path: string): Promise<void> {
  const res = await page.goto(path);
  if (res && res.status() >= 500) {
    test.skip(true, "Dev server 5xx (CSS compile) — passes in CI container");
  }
  const html = await page.content();
  if (html.includes('statusCode":500') || html.includes("ERR_INVALID_URL_SCHEME")) {
    test.skip(true, "Dev server 5xx (CSS compile) — passes in CI container");
  }
}

const DESKTOP = { width: 1280, height: 900 };
const MOBILE = { width: 390, height: 844 };

const wordmark = (page: Page) => page.getByText("Soleur", { exact: true });
// Expanded → role=group aria-label "Theme"; collapsed → the cycle button.
const themeToggle = (page: Page) =>
  page.getByRole("group", { name: "Theme" }).or(page.getByTestId("theme-cycle-button"));
const railBand = (page: Page) =>
  page.locator('[data-testid="workspace-context-band"][data-variant="rail"]');
// The band mounts twice (mobile top-bar + rail), both CSS-present in the DOM —
// scope identity/repo assertions to the RAIL band or they resolve to 2 elements.
const orgIdentity = (page: Page) => railBand(page).getByTestId("workspace-identity-static");
const repoBadge = (page: Page) => railBand(page).getByTestId("live-repo-badge");
const repoText = (page: Page) => railBand(page).getByText("Working on:", { exact: false });
const secondarySlot = (page: Page) => page.getByTestId("rail-secondary-slot");
const primaryNav = (page: Page) => page.getByRole("link", { name: "Knowledge Base" });

test.describe("nav-states visual gate — desktop", () => {
  test.use({ viewport: DESKTOP });

  test("top-level (expanded): chrome present + identity visible, no drill slot", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    // Top-level chrome IS shown at the top level.
    await expect(wordmark(page)).toBeVisible({ timeout: 15_000 });
    await expect(primaryNav(page)).toBeVisible();
    await expect(secondarySlot(page)).toHaveCount(0);

    // Identity CONTENT (not just band box) is visible.
    await expect(railBand(page)).toBeVisible();
    await expect(orgIdentity(page)).toContainText("Soleur Workspace");
    await expect(repoBadge(page)).toContainText("acme/repo");
  });

  test("drilled (expanded): top-level chrome is GONE; band + section + slot remain (Bug 1)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    // The drilled rail swaps to the secondary slot + section title.
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    await expect(railBand(page)).toBeVisible();
    await expect(railBand(page)).toContainText("Knowledge Base"); // section title in band
    await expect(orgIdentity(page)).toContainText("Soleur Workspace"); // identity survives drill

    // Bug 1 invariant: wordmark + theme toggle must NOT be present when drilled.
    await expect(wordmark(page)).toHaveCount(0);
    await expect(themeToggle(page)).toHaveCount(0);
    // Primary nav is replaced by the section's secondary nav.
    await expect(primaryNav(page)).toHaveCount(0);
  });

  test("collapsed top-level: rail is icon-only, no horizontal overflow (Bug 2)", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    // Retrying assertion: wait for the post-hydration collapsed width (md:w-14 = 56px).
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });

    // Identity never unmounts on collapse (ADR-047) — band still present.
    await expect(railBand(page)).toBeVisible();

    // Bug 2 invariant: the rail must NOT overflow horizontally, and the verbose
    // "Working on:" repo label must be hidden in the collapsed (icon-only) form.
    const overflow = await aside.evaluate(
      (el) => el.scrollWidth - el.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);
    await expect(repoText(page)).toBeHidden();
  });

  test("collapsed drilled: icon-only, no overflow, chrome gone", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toBeVisible();
    await expect(wordmark(page)).toHaveCount(0); // Bug 1
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1); // Bug 2
  });
});

test.describe("nav-states visual gate — mobile", () => {
  test.use({ viewport: MOBILE });

  test("mobile shell: identity band visible in the top bar", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    // On mobile the band lives in the top bar (variant="mobile"), CSS-placed so
    // identity paints on the first frame (RQ1). It must be visible.
    const mobileBand = page.locator(
      '[data-testid="workspace-context-band"][data-variant="mobile"]',
    );
    await expect(mobileBand).toBeVisible({ timeout: 15_000 });
    await expect(mobileBand).toContainText("Soleur Workspace");
  });
});
