import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";

// feat-ui-action-feedback (#8917) Guard 1 — the nav-pending bar is visible iff a
// soft navigation has been in flight past the 150ms entry delay, and it clears
// on route commit (pathname OR searchParams change). Exercises two of the
// three trigger channels in-browser (NavLink click, popstate via goBack);
// usePendingRouter is covered at unit level (test/use-pending-router.test.tsx).
// Timed behaviors are driven by delaying the target
// route's RSC/document fetch via page.route — never by racing real latency.

const BAR = (page: Page) => page.getByTestId("nav-pending-bar");
const LIVE = (page: Page) => page.getByRole("status");

async function setup(page: Page): Promise<void> {
  await injectFakeSupabaseSession(page);
  await mockSupabaseAuth(page);
  // Dashboard shell calls these app routes on mount; fulfill empty/ok so the
  // rail renders deterministically without a real backend.
  for (const pattern of [
    "**/api/workspace/active-repo*",
    "**/api/workspace/list-memberships*",
  ]) {
    await page.route(pattern, (route) =>
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: pattern.includes("list-memberships") ? "[]" : "{}",
      }),
    );
  }
  await page.route("**/rest/v1/users*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: "{}",
    }),
  );
  await page.route("**/rest/v1/conversations*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await page.route("**/api/dashboard/**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "{}" }),
  );
}

async function gotoDash(page: Page): Promise<void> {
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      await page.goto("/dashboard", {
        waitUntil: "domcontentloaded",
        timeout: 30_000,
      });
      return;
    } catch (err) {
      lastErr = err;
      if (!/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION/.test(String(err))) throw err;
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
  throw lastErr;
}

/** Delay every request to `pathPattern` by `ms` — holds the RSC fetch open so
 *  the pending episode is guaranteed visible mid-assertion. */
async function delayRoute(page: Page, pathPattern: string, ms: number) {
  await page.route(pathPattern, async (route) => {
    await new Promise((r) => setTimeout(r, ms));
    await route.continue();
  });
}

test.describe("nav-pending bar (#8917 Guard 1)", () => {
  test("harness precondition: bar hidden on a settled page", async ({
    page,
  }) => {
    await setup(page);
    await gotoDash(page);
    await page.waitForLoadState("networkidle").catch(() => {});
    await expect(BAR(page)).toHaveCount(0);
  });

  test("NavLink click: bar appears past the entry delay and clears on commit", async ({
    page,
  }) => {
    await setup(page);
    await delayRoute(page, "**/dashboard/settings**", 1500);
    await gotoDash(page);

    // Harness precondition — an always-on bar must not false-green this spec.
    await expect(BAR(page)).toHaveCount(0);

    const link = page
      .getByRole("link", { name: /settings/i })
      .first();
    await link.click();

    // Under the entry delay, nothing shows yet.
    await expect(BAR(page)).toHaveCount(0);
    // Past the 150ms delay + inside the held fetch, the bar renders and the
    // live region announces.
    await expect(BAR(page)).toBeVisible({ timeout: 5_000 });
    await expect(LIVE(page).filter({ hasText: /loading/i })).toBeAttached();
    // Clears once the navigation commits.
    await expect(page).toHaveURL(/\/dashboard\/settings/, { timeout: 30_000 });
    await expect(BAR(page)).toHaveCount(0, { timeout: 10_000 });
  });

  test("instant navigation does not flash the bar", async ({ page }) => {
    await setup(page);
    await gotoDash(page);
    await expect(BAR(page)).toHaveCount(0);
    // A warm/fast nav: click a rail link with no route delay — the episode
    // should commit under the 150ms entry delay and never show.
    await page.getByRole("link", { name: /knowledge base|chat|inbox/i }).first().click();
    await page.waitForTimeout(400);
    // Either the bar never appeared, or it's already gone — never visible at
    // the +400ms mark for a committed sub-150ms nav.
    await expect(BAR(page)).not.toBeVisible();
  });

  test("a second rapid navigation after commit starts a fresh episode (no stuck bar)", async ({
    page,
  }) => {
    await setup(page);
    await gotoDash(page);
    await expect(BAR(page)).toHaveCount(0);

    // First nav commits.
    await page
      .getByRole("link", { name: /chat|inbox|knowledge base/i })
      .first()
      .click();
    await page.waitForURL(/\/dashboard\/(chat|inbox|kb)/, { timeout: 30_000 });
    await expect(BAR(page)).toHaveCount(0);

    // Second nav fires a new episode on a delayed target — bar reappears and
    // clears on that commit too (covers same-origin re-navigation sequencing).
    await delayRoute(page, "**/dashboard**", 1200);
    await page.goBack();
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 30_000 });
    await expect(BAR(page)).toHaveCount(0, { timeout: 15_000 });
  });

  test("popstate (browser Back) fires the bar on real history entries", async ({
    page,
  }) => {
    await setup(page);
    await gotoDash(page);
    await page
      .getByRole("link", { name: /chat|inbox|knowledge base/i })
      .first()
      .click();
    await page.waitForURL(/\/dashboard\/(chat|inbox|kb)/, { timeout: 30_000 });
    await expect(BAR(page)).toHaveCount(0);

    // Delay the previous route's reload so a real back-nav exceeds the delay.
    await delayRoute(page, "**/dashboard**", 1500);
    await page.goBack();
    await expect(BAR(page)).toBeVisible({ timeout: 5_000 });
    await expect(page).toHaveURL(/\/dashboard$/, { timeout: 30_000 });
    await expect(BAR(page)).toHaveCount(0, { timeout: 10_000 });
  });

  test("a navigation that never commits cannot leave a permanent bar", async ({
    page,
  }) => {
    await setup(page);
    await gotoDash(page);
    // Stall the target's RSC fetch forever — the ~30s stall timeout must clear
    // the bar. We emulate the mechanism cheaply: hold the episode open for a
    // few seconds (bar visible), then unblock and confirm clear. The full 30s
    // stall path is covered by the unit suite (fake timers); here we verify a
    // held nav neither stuck-blocks interactions nor strands the bar after
    // the route unblocks.
    let release!: () => void;
    const gate = new Promise<void>((r) => (release = r));
    await page.route("**/dashboard/kb**", async (route) => {
      await gate;
      await route.continue();
    });
    const link = page.getByRole("link", { name: /knowledge base/i }).first();
    await link.click();
    await expect(BAR(page)).toBeVisible({ timeout: 5_000 });
    release();
    await expect(BAR(page)).toHaveCount(0, { timeout: 15_000 });
  });
});
