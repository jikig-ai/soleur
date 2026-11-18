// pyramid-justified: proves the Settings Project card renders the held-files notice from the server's own reads (the
// service select of `workspaces.kb_sync_held_files`, the `is_workspace_owner` RPC, the publish-route predicate) end to
// end on the dev server, and that the 375 px layout does not scroll sideways; the unit suites stub each seam and jsdom
// cannot measure layout.
import fs from "node:fs";
import path from "node:path";
import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { AUTH_COOKIE_NAME, HELD_E2E_USERS, HELD_ORG_NAME, heldSessionFor } from "./mock-supabase";
import {
  disconnectHeldBody,
  disconnectHeldWarning,
  heldMemberNoRoute,
  heldOwnerNoRoute,
  heldRoleUnknown,
} from "../lib/kb-sync-held-copy";

// #12714 Settings held-commits card (task 11.5; wireframe knowledge-base/product/design/settings/kb-sync-held-commits.pen).
//
// Each card state is its own synthesized user in e2e/mock-supabase.ts (HELD_E2E_USERS), so the server-side reads are
// answered per user and no other spec sees the rows. The `e2e-auth` server pins FLAG_APPROVAL_QUEUE=0 with Flagsmith
// unconfigured (playwright.config.ts), so the publish-route predicate answers "unavailable" (flag off) for every user
// here: the route-available and transient strings cannot be reached in this harness and stay covered by
// test/project-setup-card.test.tsx and test/kb-sync-held-copy.test.ts. Expected copy is imported from
// lib/kb-sync-held-copy.ts (the CPO's V6-V11 strings), never retyped.
//
// Screenshots go to HELD_E2E_SHOT_DIR when set (for the PR), else under test-results/.

const SHOT_DIR = process.env.HELD_E2E_SHOT_DIR ?? path.resolve("test-results/settings-kb-sync-held");
const VIEWPORTS = {
  desktop: { width: 1280, height: 800 },
  "375": { width: 375, height: 812 },
} as const;
const REPO_NAME = "acme/widgets";

/** Playwright storage state carrying a held-files fixture user's mock session (same cookie shape as global-setup.ts). */
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
  // The Agent engine section above the Project card: answered as unavailable so it renders its own error state (an
  // empty `{}` body would crash it into the page error boundary).
  await page.route("**/api/dashboard/settings/agent-engine", (route) =>
    route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "e2e" }) }),
  );
}

/** Navigate to Settings, retrying the transient network aborts a cold dev-server compile produces. */
async function gotoSettings(page: Page): Promise<void> {
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const res = await page.goto("/dashboard/settings", { waitUntil: "domcontentloaded", timeout: 90_000 });
      expect(res?.status(), "Settings document status").toBeLessThan(400);
      return;
    } catch (err) {
      lastErr = err;
      if (!/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION|ERR_EMPTY_RESPONSE|ERR_NETWORK_CHANGED|ERR_NETWORK_IO_SUSPENDED/.test(String(err))) throw err;
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }
  throw lastErr;
}

const projectSection = (page: Page) =>
  page.locator("section").filter({ has: page.getByRole("heading", { level: 2, name: "Project" }) });
const heldNotice = (page: Page) => page.getByTestId("kb-sync-held-notice");

async function expectNoHorizontalScroll(page: Page): Promise<void> {
  const { scrollWidth, innerWidth } = await page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    innerWidth: window.innerWidth,
  }));
  expect(scrollWidth, `document scrollWidth ${scrollWidth} > innerWidth ${innerWidth}`).toBeLessThanOrEqual(innerWidth);
}

async function shoot(page: Page, name: string): Promise<void> {
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  await page.evaluate(() => document.fonts.ready);
  // The Next dev-tools badge (dev server only) floats over the card at 375 px; hidden for the picture only.
  await page.addStyleTag({ content: "nextjs-portal { display: none !important; }" });
  const section = projectSection(page);
  await section.evaluate((el) => el.scrollIntoView({ block: "start" }));
  await section.screenshot({ path: path.join(SHOT_DIR, `${name}.png`), animations: "disabled" });
  await page.screenshot({ path: path.join(SHOT_DIR, `${name}-viewport.png`), animations: "disabled" });
}

/** Open the owner's Disconnect dialog; retries the click until hydration has attached the handler. */
async function openDisconnect(page: Page): Promise<void> {
  const heading = page.getByRole("heading", { name: "Disconnect repository" });
  const button = projectSection(page).getByRole("button", { name: "Disconnect", exact: true });
  await expect(async () => {
    if (!(await heading.isVisible())) await button.click();
    await expect(heading).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 45_000 });
}

interface HeldCase {
  /** Screenshot stem. */
  readonly name: string;
  readonly userId: string;
  readonly audience: "owner" | "member" | "unknown";
  /** The notice text, or null when no notice renders. */
  readonly notice: string | null;
  /** Owner cases only: the Disconnect dialog's warning paragraph (null: none) and its own paragraph. */
  readonly disconnect?: { readonly warning: string | null; readonly body: { before: string; after: string } };
}

const u = HELD_E2E_USERS;
const CASES: readonly HeldCase[] = [
  {
    name: "owner-held",
    userId: u.ownerHeld.id,
    audience: "owner",
    notice: heldOwnerNoRoute(3),
    disconnect: { warning: disconnectHeldWarning(3, "unavailable"), body: disconnectHeldBody(3) },
  },
  {
    name: "owner-zero",
    userId: u.ownerZero.id,
    audience: "owner",
    notice: null,
    disconnect: { warning: null, body: disconnectHeldBody(0) },
  },
  {
    name: "owner-null",
    userId: u.ownerNull.id,
    audience: "owner",
    notice: null,
    disconnect: { warning: null, body: disconnectHeldBody(null) },
  },
  {
    // kb_sync_pull_blocked = 'untracked_collision' (migration 188): Settings does not read it, so the card is the
    // held-count notice alone (an Owner line for a stuck merge is the D30 follow-up, task 11.6).
    name: "pull-blocked",
    userId: u.ownerPullBlocked.id,
    audience: "owner",
    notice: heldOwnerNoRoute(2),
    disconnect: { warning: disconnectHeldWarning(2, "unavailable"), body: disconnectHeldBody(2) },
  },
  {
    // V9: the stored clamp renders as "10,000 or more".
    name: "owner-cap",
    userId: u.ownerCap.id,
    audience: "owner",
    notice: heldOwnerNoRoute(10_000),
  },
  { name: "member-held", userId: u.memberHeld.id, audience: "member", notice: heldMemberNoRoute(3) },
  { name: "member-zero", userId: u.memberZero.id, audience: "member", notice: null },
  // V10: the is_workspace_owner RPC failed, so neither the Owner nor the member steps are shown.
  { name: "role-unknown", userId: u.roleUnknown.id, audience: "unknown", notice: heldRoleUnknown(3) },
];

for (const c of CASES) {
  test.describe(`Settings held-files card: ${c.name}`, () => {
    test.use({ storageState: storageFor(c.userId) });

    for (const [vpName, viewport] of Object.entries(VIEWPORTS)) {
      test(`${vpName}`, async ({ page }) => {
        // A cold compile of /dashboard/settings on a loaded host.
        test.setTimeout(180_000);
        await page.setViewportSize(viewport);
        const pageErrors: string[] = [];
        page.on("pageerror", (err) => pageErrors.push(err.message));
        await stubShellRoutes(page);
        await gotoSettings(page);

        const section = projectSection(page);
        // The connected repo line is the anchor every state renders; the notice (if any) is in the same server render.
        await expect(section.getByText(REPO_NAME, { exact: true })).toBeVisible({ timeout: 90_000 });
        await expect(section.getByText("Connected", { exact: true })).toBeVisible();

        if (c.notice === null) {
          await expect(heldNotice(page)).toHaveCount(0);
        } else {
          await expect(heldNotice(page)).toHaveText(c.notice);
          await expect(heldNotice(page)).toHaveAttribute("role", "note");
        }

        if (c.audience === "owner") {
          await expect(section.getByRole("button", { name: "Disconnect", exact: true })).toBeVisible();
        } else {
          // Member and role-unknown read the read-only summary: no connection controls (ADR-044 FR3).
          await expect(section.getByText(`managed by ${HELD_ORG_NAME}`, { exact: true })).toBeVisible();
          await expect(section.getByRole("button", { name: "Disconnect", exact: true })).toHaveCount(0);
        }

        if (vpName === "375") await expectNoHorizontalScroll(page);
        await shoot(page, `${c.name}-${vpName}`);

        if (c.disconnect) {
          await openDisconnect(page);
          const warning = page.getByTestId("disconnect-held-warning");
          if (c.disconnect.warning === null) {
            await expect(warning).toHaveCount(0);
          } else {
            await expect(warning).toHaveText(c.disconnect.warning);
          }
          await expect(section.getByText(`${c.disconnect.body.before}${REPO_NAME}${c.disconnect.body.after}`, { exact: true })).toBeVisible();
          if (vpName === "375") await expectNoHorizontalScroll(page);
          await shoot(page, `${c.name}-disconnect-${vpName}`);
        }
        // The card stayed mounted: no render error replaced the page (the dashboard error boundary), no uncaught error.
        await expect(page.getByRole("heading", { name: "Something went wrong" })).toHaveCount(0);
        expect(pageErrors).toEqual([]);
      });
    }
  });
}
