// pyramid-justified: each test measures real Chromium layout at 390x844 for the Scope Grants web-egress disclosures,
// rendered from the page's own server reads (the Owner membership and the fail-closed tenant `web_egress` read). The
// unit suites stub those reads and jsdom cannot measure layout.
import { test, expect } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";
import { AUTH_COOKIE_NAME, EGRESS_E2E_USERS, heldSessionFor } from "./mock-supabase";
import { GH_DISCLOSURE, PUSH_DISCLOSURE } from "../lib/web-egress-disclosure";

const PHONE = { width: 390, height: 844 } as const;
const PAGE_PATH = "/dashboard/settings/scope-grants";

/** Playwright storage state carrying a fixture user's mock session (same cookie shape as global-setup.ts). */
function storageFor(userId: string) {
  return {
    cookies: [
      {
        name: AUTH_COOKIE_NAME,
        value: JSON.stringify(heldSessionFor(userId)),
        domain: "localhost",
        path: "/",
        expires: Math.floor(Date.now() / 1000) + 86400,
        httpOnly: false,
        secure: false,
        sameSite: "Lax" as const,
      },
    ],
    origins: [],
  };
}

/** App API routes the dashboard chrome calls on mount; fulfilled so the shell renders without a backend. */
async function stubShellRoutes(page: Page): Promise<void> {
  const stubs: [string, unknown][] = [
    ["**/api/admin/check", { isAdmin: false }],
    ["**/api/inbox**", { items: [] }],
    ["**/api/workspace/active-repo*", {}],
    ["**/api/workspace/list-memberships*", { memberships: [] }],
    ["**/api/workspace/pending-invites*", { invites: [] }],
    ["**/api/byok/**", { hasKey: true, status: "ok" }],
    ["**/api/kb/**", { tree: [], entries: [] }],
  ];
  for (const [pattern, body] of stubs) {
    await page.route(pattern, (route) =>
      route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) }),
    );
  }
}

/** Navigate to the page, retrying the transient network aborts a cold dev-server compile produces. */
async function gotoScopeGrants(page: Page): Promise<void> {
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await page.goto(PAGE_PATH, { waitUntil: "domcontentloaded", timeout: 90_000 });
      expect(res?.status(), "Scope Grants document status").toBeLessThan(400);
      return;
    } catch (err) {
      lastErr = err;
      if (!/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION|ERR_EMPTY_RESPONSE|ERR_NETWORK_CHANGED|ERR_NETWORK_IO_SUSPENDED/.test(String(err))) throw err;
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }
  throw lastErr;
}

/** The dev-tools badge floats over content on the dev server only. */
async function hideDevOverlay(page: Page): Promise<void> {
  await page.addStyleTag({ content: "nextjs-portal { display: none !important; }" });
}

/** Render count of each disclosure. Sees a disclosure added in another tag or outside the section. */
async function expectDisclosureCount(page: Page, n: number): Promise<void> {
  await expect(page.getByText(PUSH_DISCLOSURE, { exact: true })).toHaveCount(n);
  await expect(page.getByText(GH_DISCLOSURE, { exact: true })).toHaveCount(n);
}

// The shell's overflow-x-hidden makes the document check unable to fail, so each surface is also measured.
// Range rects include text nodes, which element rects miss.
async function expectFitsPhone(page: Page, surface: Locator): Promise<void> {
  await expect(surface).toBeVisible(); // Fail fast: expect defaults to 5 s, and Locator.evaluate below has no such bound.
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(PHONE.width);
  const m = await surface.evaluate((el) => {
    const range = document.createRange();
    range.selectNodeContents(el);
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    return {
      count: rects.length,
      left: Math.min(...rects.map((r) => r.left)),
      right: Math.max(...rects.map((r) => r.right)),
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    };
  });
  expect(m.count).toBeGreaterThan(0);
  expect(m.left).toBeGreaterThanOrEqual(0);
  expect(m.right).toBeLessThanOrEqual(PHONE.width);
  expect(m.scrollWidth).toBeLessThanOrEqual(m.clientWidth);
}

/** Each disclosure is exactly one paragraph the user can see. `getByText` alone also counts hidden elements. */
async function expectOwnVisibleParagraphs(surface: Locator): Promise<void> {
  const visible = await surface
    .locator("p")
    .evaluateAll((ps) =>
      ps
        .filter((p) => p.checkVisibility({ opacityProperty: true, visibilityProperty: true }))
        .map((p) => p.textContent?.trim() ?? ""),
    );
  expect(visible.filter((text) => text === PUSH_DISCLOSURE)).toHaveLength(1);
  expect(visible.filter((text) => text === GH_DISCLOSURE)).toHaveLength(1);
}

async function expectSurface(page: Page, surface: Locator): Promise<void> {
  await expectFitsPhone(page, surface);
  await expectOwnVisibleParagraphs(surface);
}

function surfaces(page: Page) {
  const section = page.locator("#agent-web-access");
  const push = section.locator("p", { hasText: PUSH_DISCLOSURE });
  return {
    toggle: section.getByRole("switch"),
    dialog: section.getByRole("alertdialog"),
    onBlock: push.first().locator("xpath=.."),
    callout: push.last().locator("xpath=.."),
  };
}

function collectPageErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("pageerror", (err) => errors.push(err.message));
  return errors;
}

async function expectNoRenderFailure(page: Page, pageErrors: string[]): Promise<void> {
  await expect(page.getByRole("heading", { name: "Something went wrong" })).toHaveCount(0);
  expect(pageErrors).toEqual([]);
}

test.describe("Scope Grants web-egress disclosures at 390x844", () => {
  test.use({ viewport: PHONE });

  test.describe("web access on", () => {
    test.use({ storageState: storageFor(EGRESS_E2E_USERS.on.id) });

    test("the ON block and callout fit, with each disclosure in its own paragraph", async ({ page }) => {
      test.setTimeout(180_000);
      const pageErrors = collectPageErrors(page);
      await stubShellRoutes(page);
      await gotoScopeGrants(page);
      const { toggle, onBlock, callout } = surfaces(page);

      await expect(toggle).toBeVisible({ timeout: 90_000 }); // Cold compile, as in settings-kb-sync-held.e2e.ts.
      await expect(
        toggle,
        "web_egress read fell closed to OFF. Check [mock-supabase] unhandled lines for this fixture's actor id and for actor=-, then compare the mock's egress branches with mintFounderJwt in lib/supabase/tenant.ts.",
      ).toHaveAttribute("aria-checked", "true");
      await expect(toggle).toBeEnabled();
      await expectDisclosureCount(page, 2);
      await hideDevOverlay(page);
      await expect
        .poll(() => toggle.evaluate((el) => Object.keys(el).some((k) => k.startsWith("__reactProps$"))), {
          timeout: 45_000,
        })
        .toBe(true);

      await expectSurface(page, onBlock);
      await expectSurface(page, callout);
      await expectNoRenderFailure(page, pageErrors);
    });
  });

  test.describe("web access off", () => {
    test.use({ storageState: storageFor(EGRESS_E2E_USERS.off.id) });

    test("the enable dialog and callout fit, and the confirm button is reachable", async ({ page }) => {
      test.setTimeout(180_000);
      const pageErrors = collectPageErrors(page);
      await stubShellRoutes(page);
      await gotoScopeGrants(page);
      const { toggle, dialog, callout } = surfaces(page);

      await expect(toggle).toBeVisible({ timeout: 90_000 }); // Cold compile, as in settings-kb-sync-held.e2e.ts.
      await expect(toggle).toHaveAttribute("aria-checked", "false");
      await expect(toggle).toBeEnabled();
      await expectDisclosureCount(page, 1);
      await hideDevOverlay(page);

      // A click before hydration is a silent no-op, so retry until the dialog opens.
      await expect(async () => {
        if (!(await dialog.isVisible())) await toggle.click();
        await expect(dialog).toBeVisible({ timeout: 2_000 });
      }).toPass({ timeout: 45_000 });
      await expectDisclosureCount(page, 2);

      await expectSurface(page, dialog);
      await expectSurface(page, callout);

      const confirm = dialog.getByRole("button", { name: "I understand — turn it on" });
      await expect(confirm).toBeVisible();
      await confirm.scrollIntoViewIfNeeded({ timeout: 10_000 });
      await expect(confirm).toBeInViewport({ ratio: 1 });
      // A trial click proves nothing covers the button and fires no handler. This spec never confirms the dialog.
      await confirm.click({ trial: true, timeout: 10_000 });
      await expectNoRenderFailure(page, pageErrors);
    });
  });
});
