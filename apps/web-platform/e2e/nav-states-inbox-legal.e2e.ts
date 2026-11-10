// pyramid-justified: proves the founder legal row renders in the real Inbox
// (server gate in GET /api/inbox + client row + client-side navigation to the
// card page) end to end against the dev server; the unit suites stub each seam.
import { test, expect } from "@playwright/test";
import type { Page, Response } from "@playwright/test";

// Founder legal-acceptance Inbox row (#12197; CTO ruling F2, 2026-11-10; frame 23
// in knowledge-base/product/design/approvals/approval-request.pen).
//
// The `e2e-auth` webServer runs with LEGAL_ACCEPTANCE_FOUNDER_ID = MOCK_FOUNDER.id
// and FLAG_APPROVAL_QUEUE=0 (playwright.config.ts), so the founder block proves
// the surface gates on the founder id alone: flag off, founder configured, row
// visible, and the card page it leads to renders (the page gate ignores the flag
// too). The negative control signs in as MOCK_USER and must see no legal row.
//
// No browser-side Supabase stubs here: the shared helpers in
// helpers/supabase-mocks.ts answer with MOCK_USER / MOCK_SESSION, which would
// swap the founder's identity in the browser. The browser and the server both
// talk to the mock Supabase server, which picks the user by the bearer's `sub`.
//
// Literals are written out independently of the copy deck (lib/legal-acceptance-
// copy.ts, lib/legal-inbox-copy.ts) and the registry text
// (server/legal-acceptance/texts/founder-acceptance-record.md), so a wording or
// version change fails here instead of passing by construction.

const LEGAL_KEY = "founder-acceptance-record";
const ROW_TITLE = 'Acknowledge "How your decisions are recorded and kept"?';
const ROW_BADGE = "Needs your answer";
const ROW_META = "How your decisions are recorded and kept, version 2026-11-07";
// sha256 of the registry file's raw bytes (`sha256sum`): it must never reach the browser.
const TEXT_HASH = "10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287";
const ANY_SHA256 = /[0-9a-f]{64}/;

/** App API routes the dashboard chrome calls on mount; fulfilled so the shell renders without a backend. Never /api/inbox. */
async function stubShellRoutes(page: Page): Promise<void> {
  const stubs: [string, unknown][] = [
    ["**/api/admin/check", { isAdmin: false }],
    ["**/api/inbox/emails*", { items: [] }],
    ["**/api/workspace/active-repo*", {}],
    ["**/api/workspace/list-memberships*", { memberships: [] }],
    ["**/api/workspace/pending-invites*", { invites: [] }],
    ["**/api/dashboard/**", {}],
    ["**/api/byok/**", { hasKey: true, status: "ok" }],
    ["**/api/kb/**", { tree: [], entries: [] }],
  ];
  for (const [pattern, body] of stubs) {
    await page.route(pattern, (route) =>
      route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(body) }),
    );
  }
}

const isInboxList = (r: Response) =>
  r.request().method() === "GET" && new URL(r.url()).pathname === "/api/inbox";

/** Navigate, retrying the transient network aborts a cold dev-server compile produces. */
async function gotoInbox(page: Page): Promise<void> {
  let lastErr: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      await page.goto("/dashboard/inbox", { waitUntil: "domcontentloaded", timeout: 45_000 });
      return;
    } catch (err) {
      lastErr = err;
      if (!/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION|ERR_EMPTY_RESPONSE|ERR_NETWORK_CHANGED/.test(String(err))) throw err;
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
  }
  throw lastErr;
}

/** Open the Inbox and return the first GET /api/inbox response with its raw body. */
async function openInbox(page: Page): Promise<{ status: number; body: string }> {
  const inboxResponse = page.waitForResponse(isInboxList, { timeout: 90_000 });
  await gotoInbox(page);
  const res = await inboxResponse;
  return { status: res.status(), body: await res.text() };
}

test.describe("founder session", () => {
  test.use({ storageState: "e2e/.auth/founder.json", viewport: { width: 1440, height: 900 } });

  test("flag off, founder configured: the Inbox legal row is visible", async ({ page }) => {
    // Cold compile of /dashboard/inbox, /api/inbox and the card page on a loaded host.
    test.setTimeout(180_000);
    await stubShellRoutes(page);

    const inbox = await openInbox(page);
    expect(inbox.status).toBe(200);
    const items = (JSON.parse(inbox.body) as { items: { kind: string; legal?: { key: string; state: string } }[] }).items;
    expect(items.filter((i) => i.kind === "legal").map((i) => i.legal)).toEqual([
      expect.objectContaining({ key: LEGAL_KEY, state: "pending" }),
    ]);
    expect(inbox.body).not.toContain(TEXT_HASH);
    expect(inbox.body).not.toMatch(ANY_SHA256);

    const row = page.getByTestId("legal-inbox-row");
    await expect(row).toBeVisible({ timeout: 45_000 });
    await expect(row).toHaveCount(1);
    await expect(row).toHaveAttribute("data-state", "pending");
    await expect(row).toContainText(ROW_TITLE);
    await expect(row).toContainText(ROW_BADGE);
    await expect(row).toContainText(ROW_META);

    // The exact hash is in neither the row nor the whole document. The generic
    // 64-hex scan is scoped to the row (and the payload above): the dev page's
    // RSC payload and chunk URLs carry unrelated 64-hex strings.
    expect(await page.evaluate(() => document.documentElement.outerHTML)).not.toContain(TEXT_HASH);
    expect(await row.evaluate((el) => el.outerHTML)).not.toMatch(ANY_SHA256);

    // Design evidence for frame 23 (copied into knowledge-base/product/design/approvals/screenshots/).
    await page.evaluate(() => document.fonts.ready);
    await row.scrollIntoViewIfNeeded();
    await row.screenshot({ path: "test-results/inbox-legal-row-pending.png", animations: "disabled" });
    await page.screenshot({ path: "test-results/inbox-legal-row-pending-viewport.png", animations: "disabled" });

    // The row navigates only when its key is registry-shaped; role="button" is the marker.
    await expect(row).toHaveAttribute("role", "button");
    await page
      .getByRole("button", { name: /Acknowledge "How your decisions are recorded and kept"\?/ })
      .click();
    await page.waitForURL(/\/dashboard\/approvals\/legal\/founder-acceptance-record$/, {
      waitUntil: "commit",
      timeout: 60_000,
    });

    // router.push is a client-side navigation with no document status to read, so
    // the card's own marker is the not-found check.
    const card = page.getByTestId("legal-card");
    await expect(card).toBeVisible({ timeout: 60_000 });
    await expect(card).toHaveAttribute("data-state", "pending");
    await expect(card).toHaveAttribute("data-key", LEGAL_KEY);
  });
});

test.describe("non-founder session (negative control)", () => {
  test.use({ storageState: "e2e/.auth/user.json" });

  test("a signed-in user who is not the founder sees no legal row", async ({ page }) => {
    test.setTimeout(150_000);
    await stubShellRoutes(page);

    const inbox = await openInbox(page);
    expect(inbox.status).toBe(200);
    const items = (JSON.parse(inbox.body) as { items: { kind: string }[] }).items;
    expect(items.filter((i) => i.kind === "legal")).toEqual([]);

    // Absence is asserted only after the inbox has rendered its list state.
    await expect(page.getByText("You're all caught up.")).toBeVisible({ timeout: 45_000 });
    await expect(page.getByTestId("legal-inbox-row")).toHaveCount(0);
  });
});
