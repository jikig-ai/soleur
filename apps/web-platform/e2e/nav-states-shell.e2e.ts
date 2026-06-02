import { test, expect } from "@playwright/test";
import type { Page, Response } from "@playwright/test";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";

// Headless visual-regression gate for the single nav rail (ADR-049, #4834).
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

/**
 * Navigate. A 5xx is the local worktree's CSS-compile quirk — skip THERE only.
 * In CI a 5xx means the shell this gate guards is actually broken, so it must
 * FAIL, never skip to a green exit (a skipped test exits 0 = brand-survival
 * false-GREEN — the exact hole this gate exists to close).
 */
async function gotoOrSkip(page: Page, path: string): Promise<void> {
  // The authenticated dev server's first navigation can ERR_ABORTED / refuse
  // connection during cold compile. Retry transient NETWORK aborts a few times
  // (deterministic, not reliant on CI `retries`). A 5xx is NOT retried here — it
  // flows to the CI-fail / local-skip branch below. A persistent abort still throws.
  let res: Response | null = null;
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      res = await page.goto(path, { waitUntil: "domcontentloaded", timeout: 30_000 });
      lastErr = undefined;
      break;
    } catch (err) {
      lastErr = err;
      if (
        !/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION|ERR_NETWORK_CHANGED|ERR_EMPTY_RESPONSE/.test(
          String(err),
        )
      ) {
        throw err;
      }
      // Page-independent backoff — page.waitForTimeout throws if a degraded
      // server already tore the context down, masking the real abort.
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }
  if (lastErr) throw lastErr;
  const html = await page.content();
  const is5xx =
    (res !== null && res.status() >= 500) ||
    html.includes('statusCode":500') ||
    html.includes("ERR_INVALID_URL_SCHEME");
  if (is5xx) {
    if (process.env.CI) {
      throw new Error(
        `Dashboard route ${path} returned 5xx in CI — the visual gate must fail, not skip.`,
      );
    }
    test.skip(true, "Dev server 5xx (CSS compile) — local worktree only; fails in CI");
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

    // Identity CONTENT (not just band box) is visible. Generous timeout — the
    // org/repo come from async app-route fetches that lag a cold route compile.
    await expect(railBand(page)).toBeVisible({ timeout: 15_000 });
    await expect(orgIdentity(page)).toContainText("Soleur Workspace", { timeout: 15_000 });
    await expect(repoBadge(page)).toContainText("acme/repo", { timeout: 15_000 });
  });

  test("drilled (expanded): top-level chrome is GONE; band + section + slot remain (Bug 1)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    // The drilled rail swaps to the secondary slot + section title.
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    await expect(railBand(page)).toBeVisible({ timeout: 15_000 });
    await expect(railBand(page)).toContainText("Knowledge Base", { timeout: 15_000 }); // section title in band
    await expect(orgIdentity(page)).toContainText("Soleur Workspace", { timeout: 15_000 }); // identity survives drill

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

    // Identity never unmounts on collapse (ADR-047) — band still present, in its
    // icon-only form (positive invariant: the icon marker IS rendered).
    await expect(railBand(page)).toBeVisible();
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
    await expect(page.getByTestId("live-repo-dot")).toBeVisible();

    // Bug 2 invariant: the rail must NOT overflow horizontally, and the verbose
    // "Working on:" repo label must be ABSENT from the rail (icon-only form). Use
    // toHaveCount(0) at the rail-variant scope — NOT toBeHidden() on the (empty)
    // rail band, which would pass vacuously on a zero-match locator.
    const overflow = await aside.evaluate(
      (el) => el.scrollWidth - el.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);
    await expect(
      page.locator('[data-variant="rail"]').getByText("Working on:", { exact: false }),
    ).toHaveCount(0);
  });

  test("collapsed drilled: icon-only, no overflow, chrome gone", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toBeVisible();
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
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
    await expect(mobileBand).toContainText("Soleur Workspace", { timeout: 15_000 });
  });
});
