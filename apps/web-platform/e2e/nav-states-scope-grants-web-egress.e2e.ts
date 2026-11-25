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
async function expectFitsPhone(page: Page, name: string, surface: Locator): Promise<void> {
  await expect(surface, `${name} is visible`).toBeVisible(); // Fail fast: Locator.evaluate below has no 5 s bound.
  // Measure after web fonts settle and a frame has painted, so a late font swap cannot reflow the text afterwards.
  await page.evaluate(() => document.fonts.ready.then(() => new Promise((resolve) => requestAnimationFrame(resolve))));
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
    "document scrollWidth",
  ).toBeLessThanOrEqual(PHONE.width);
  const m = await surface.evaluate((el) => {
    const range = document.createRange();
    range.selectNodeContents(el);
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    // The card's box, not the viewport, so text escaping the card's padding fails too (ruling R3).
    const card = el.closest("#agent-web-access")!.getBoundingClientRect();
    return {
      count: rects.length,
      left: Math.min(...rects.map((r) => r.left)),
      right: Math.max(...rects.map((r) => r.right)),
      cardLeft: card.left,
      cardRight: card.right,
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth,
    };
  });
  expect(m.count, `${name} has rendered text`).toBeGreaterThan(0);
  expect(m.cardLeft, "card left edge").toBeGreaterThanOrEqual(0);
  expect(m.cardRight, "card right edge").toBeLessThanOrEqual(PHONE.width);
  expect(m.left, `${name} text left edge`).toBeGreaterThanOrEqual(m.cardLeft);
  expect(m.right, `${name} text right edge`).toBeLessThanOrEqual(m.cardRight);
  expect(m.scrollWidth, `${name} scrollWidth`).toBeLessThanOrEqual(m.clientWidth);
}

/** The switch opens the enable dialog, so it must sit inside the card where a phone user can tap it (ruling R3). */
async function expectSwitchInCard(toggle: Locator): Promise<void> {
  const m = await toggle.evaluate((el) => {
    const box = el.getBoundingClientRect();
    const card = el.closest("#agent-web-access")!.getBoundingClientRect();
    return { left: box.left, right: box.right, width: box.width, cardLeft: card.left, cardRight: card.right };
  });
  expect(m.width, "switch width").toBeGreaterThan(0);
  expect(m.left, "switch left edge").toBeGreaterThanOrEqual(m.cardLeft);
  expect(m.right, "switch right edge").toBeLessThanOrEqual(m.cardRight);
}

/**
 * Each disclosure is exactly one paragraph the user can see. `getByText` alone also counts hidden elements, and
 * `checkVisibility` alone passes a zero-height paragraph and one whose text sits in a hidden child (ruling R1).
 */
async function expectOwnVisibleParagraphs(name: string, surface: Locator): Promise<void> {
  const visible = await surface.locator("p").evaluateAll((ps) =>
    ps
      .filter((p) => {
        if (!p.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false;
        if (p.getBoundingClientRect().height <= 0) return false;
        const range = document.createRange();
        range.selectNodeContents(p);
        return [...range.getClientRects()].some((r) => r.width > 0 && r.height > 0);
      })
      .map((p) => p.textContent?.trim() ?? ""),
  );
  expect(visible.filter((text) => text === PUSH_DISCLOSURE), `${name}: push disclosure paragraphs`).toHaveLength(1);
  expect(visible.filter((text) => text === GH_DISCLOSURE), `${name}: GitHub disclosure paragraphs`).toHaveLength(1);
}

async function expectSurface(page: Page, name: string, surface: Locator): Promise<void> {
  await expectFitsPhone(page, name, surface);
  await expectOwnVisibleParagraphs(name, surface);
}

// Each surface is anchored on text only it carries, so a missing surface fails instead of resolving to another.
function surfaces(page: Page) {
  const section = page.locator("#agent-web-access");
  return {
    toggle: section.getByRole("switch"),
    dialog: section.getByRole("alertdialog"),
    onBlock: section.locator("p", { hasText: "On. Applies to sessions started after enabling" }).locator("xpath=.."),
    callout: section.locator(":scope > div", { hasText: "Widens the security boundary." }),
    crash: page.getByRole("heading", { name: "Something went wrong" }),
  };
}

/** Wait for the toggle or the error boundary, so a crashed render fails at once rather than after the cold-compile wait. */
async function expectToggleRendered(toggle: Locator, crash: Locator): Promise<void> {
  await expect(toggle.or(crash)).toBeVisible({ timeout: 90_000 }); // Cold compile, as in settings-kb-sync-held.e2e.ts.
  await expect(crash, "the page rendered its error boundary").toHaveCount(0);
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
  // Mobile emulation honours the meta viewport and touch input, as a phone does (ruling R4).
  test.use({ viewport: PHONE, isMobile: true, hasTouch: true });

  test.describe("web access on", () => {
    test.use({ storageState: storageFor(EGRESS_E2E_USERS.on.id) });

    test("the ON block and callout fit, with each disclosure in its own paragraph", async ({ page }) => {
      test.setTimeout(180_000);
      const pageErrors = collectPageErrors(page);
      await stubShellRoutes(page);
      await gotoScopeGrants(page);
      const { toggle, onBlock, callout, crash } = surfaces(page);

      await expectToggleRendered(toggle, crash);
      await expect(
        toggle,
        `The tenant web_egress read fell closed to OFF. Find the "[mock-supabase] unhandled actor=${EGRESS_E2E_USERS.on.id}" and "actor=-" lines in the runner log, then compare the mock's #12605 branches with mintFounderJwt in lib/supabase/tenant.ts.`,
      ).toHaveAttribute("aria-checked", "true");
      await expect(toggle).toBeEnabled();
      await expectDisclosureCount(page, 2);
      await hideDevOverlay(page);
      await expect
        .poll(() => toggle.evaluate((el) => Object.keys(el).some((k) => k.startsWith("__reactProps$"))), {
          timeout: 45_000,
        })
        .toBe(true);

      await expectSwitchInCard(toggle);
      await expectSurface(page, "ON block", onBlock);
      await expectSurface(page, "risk callout", callout);
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
      const { toggle, dialog, callout, crash } = surfaces(page);

      await expectToggleRendered(toggle, crash);
      await expect(toggle).toHaveAttribute("aria-checked", "false");
      await expect(toggle).toBeEnabled();
      await expectDisclosureCount(page, 1);
      await hideDevOverlay(page);
      await expectSwitchInCard(toggle);

      // A click before hydration is a silent no-op, so retry until the dialog opens.
      await expect(async () => {
        if (!(await dialog.isVisible())) await toggle.click();
        await expect(dialog).toBeVisible({ timeout: 2_000 });
      }).toPass({ timeout: 45_000 });
      await expectDisclosureCount(page, 2);
      // Both fixtures carry a null organization_id, so the longest "unknown" recording notice must render (ruling F4).
      // RECORDING_NOTICE_UNKNOWN in web-egress-toggle.tsx is not exported, so its opening sentence anchors it.
      await expect(dialog.getByText("We couldn't check whether recording is on for this workspace.")).toBeVisible();

      await expectSurface(page, "enable dialog", dialog);
      await expectSurface(page, "risk callout", callout);

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
