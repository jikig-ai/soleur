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
// Mirrors RAIL_WIDTH_KEY in hooks/use-rail-width.ts. Declared here (not imported)
// because addInitScript/page.evaluate run in the browser context where importing
// a "use client" hook module is awkward; keep the literal in lockstep with the hook.
const RAIL_WIDTH_KEY = "soleur:sidebar.kb.width";
const RAIL_MAX_ABS_PX = 480; // mirrors RAIL_MAX_ABS_PX in use-rail-width.ts

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

// POPULATED secondary-nav fixtures. The collapsed-overflow gate (AC3) must run
// against REAL content — an empty rail satisfies scrollWidth<=clientWidth
// vacuously (the false-GREEN this hardening closes: the KB tree was mocked
// `tree: []`, Settings/Chat collapsed were never visited).
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
  {
    id: "conv-third",
    user_id: "test-user-id",
    repo_url: "https://github.com/acme/repo",
    domain_leader: "cfo",
    session_id: null,
    status: "completed",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: "2026-04-26T10:00:00Z",
    created_at: "2026-04-26T09:00:00Z",
    archived_at: null,
  },
];

const SEEDED_MESSAGES = [
  {
    conversation_id: "conv-active",
    role: "user",
    content: "First seeded rail conversation title",
    leader_id: null,
    created_at: "2026-04-28T09:01:00Z",
  },
  {
    conversation_id: "conv-other",
    role: "user",
    content: "Second seeded rail conversation title",
    leader_id: null,
    created_at: "2026-04-27T09:01:00Z",
  },
  {
    conversation_id: "conv-third",
    role: "user",
    content: "Third seeded rail conversation title",
    leader_id: null,
    created_at: "2026-04-26T09:01:00Z",
  },
];

// A nested tree with a deliberately long folder + file name — the surface that
// truncates at the 224px default and that the widen handle (AC9) makes legible.
const SEEDED_KB_TREE = {
  tree: {
    name: "root",
    type: "directory",
    path: "",
    children: [
      // Top-level long file name — rendered immediately at depth 0 (no expand
      // needed), so it's the populated row the collapsed-overflow + widen
      // assertions target.
      {
        name: "an-extremely-long-document-filename-that-truncates-at-the-default-rail-width.md",
        type: "file",
        path: "an-extremely-long-document-filename-that-truncates-at-the-default-rail-width.md",
        extension: ".md",
      },
      {
        name: "knowledge-base",
        type: "directory",
        path: "knowledge-base",
        children: [
          {
            name: "a-deeply-nested-folder-name",
            type: "directory",
            path: "knowledge-base/a-deeply-nested-folder-name",
            children: [],
          },
        ],
      },
    ],
  },
  lastSync: null,
  needsReconnect: false,
};

/**
 * Wire the auth/session/realtime stubs (shared helper) PLUS the band's two app
 * API routes and the leaf routes the dashboard shell touches. Mirrors
 * start-fresh-conversations-rail.e2e.ts's setup, extended with /api/workspace/*.
 */
async function setupNavMocks(page: Page): Promise<void> {
  await injectFakeSupabaseSession(page);
  await mockSupabaseAuth(page);

  // layout.tsx reads users.subscription_status (browser-side) via .single();
  // the conversations rail scopes its list by users.repo_url (.single() → object
  // body, NOT array — see start-fresh-conversations-rail.e2e.ts on why).
  await page.route("**/rest/v1/users*", async (route) => {
    const select = new URL(route.request().url()).searchParams.get("select") ?? "";
    if (select.includes("repo_url")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ repo_url: "https://github.com/acme/repo" }),
      });
      return;
    }
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

  // Populated so the collapsed Chat case asserts overflow against REAL rows.
  await page.route("**/rest/v1/conversations*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(SEEDED_CONVERSATIONS),
    }),
  );
  await page.route("**/rest/v1/messages*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(SEEDED_MESSAGES),
    }),
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
  // POPULATED KB tree for the rail (registered AFTER the catch-all so Playwright,
  // which matches most-recently-added first, routes /api/kb/tree here). The rail
  // file tree reads `data.tree` from this endpoint (hooks/use-kb-layout-state).
  await page.route("**/api/kb/tree*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(SEEDED_KB_TREE),
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

// Secondary-nav content + stable wrappers (collapse fix).
const settingsRailNav = (page: Page) => page.getByTestId("settings-rail-nav");
const settingsNav = (page: Page) =>
  page.getByRole("navigation", { name: "Settings" });
const kbRailTree = (page: Page) => page.getByTestId("kb-rail-tree");
const kbLongFile = (page: Page) =>
  page.getByText(/an-extremely-long-document-filename/);
const conversationsRail = (page: Page) => page.getByTestId("conversations-rail");
const conversationRow = (page: Page) =>
  page.getByText(/First seeded rail conversation title/);
// Widenable KB rail (amendment).
const resizeHandle = (page: Page) => page.getByTestId("kb-rail-resize-handle");
const asideWidth = (page: Page) =>
  page.locator("aside").first().evaluate((el) => el.clientWidth);

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

  test("collapsed drilled (KB, POPULATED tree): no overflow, tree DOM-removed, chrome gone", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toBeVisible();
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
    await expect(wordmark(page)).toHaveCount(0); // Bug 1
    // AC2: the stable wrapper survives but the populated tree content is gone —
    // the file row must NOT be present (so it cannot clip at 56px).
    await expect(kbRailTree(page)).toBeAttached();
    await expect(kbLongFile(page)).toHaveCount(0);
    // AC3: the gate runs against POPULATED content (the false-GREEN this closes
    // was a `tree: []` empty rail).
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test("collapsed drilled (Settings, POPULATED): no overflow, sub-nav DOM-removed (AC2/AC3)", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/settings");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
    // AC5: identity still legible when collapsed+drilled.
    await expect(page.getByTestId("live-repo-dot")).toBeVisible();
    // AC2: wrapper present, the General/Billing/etc. links gone.
    await expect(settingsRailNav(page)).toBeAttached();
    await expect(settingsNav(page)).toHaveCount(0);
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test("collapsed drilled (Chat, POPULATED rows): no overflow, rows DOM-removed (AC2/AC3)", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/chat");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
    // AC2: the rich conversation rows are gone when collapsed.
    await expect(conversationRow(page)).toHaveCount(0);
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test("expanded drilled (all 3): secondary-nav content PRESENT (AC4 anti-vacuity)", async ({ page }) => {
    await setupNavMocks(page);

    await gotoOrSkip(page, "/dashboard/kb");
    await expect(kbLongFile(page)).toBeVisible({ timeout: 15_000 });

    await gotoOrSkip(page, "/dashboard/settings");
    await expect(settingsNav(page)).toBeVisible({ timeout: 15_000 });
    await expect(
      settingsNav(page).getByRole("link", { name: "General" }),
    ).toBeVisible();

    await gotoOrSkip(page, "/dashboard/chat");
    await expect(conversationsRail(page)).toBeVisible({ timeout: 15_000 });
    await expect(conversationRow(page)).toBeVisible({ timeout: 15_000 });
  });
});

test.describe("widenable KB rail — desktop", () => {
  test.use({ viewport: DESKTOP });

  test("drag widens the expanded KB rail and a truncated name becomes legible (AC9)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const before = await asideWidth(page);

    const handle = resizeHandle(page);
    const box = await handle.boundingBox();
    if (!box) throw new Error("resize handle has no bounding box");
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 140, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();

    const after = await asideWidth(page);
    expect(after).toBeGreaterThan(before);
  });

  test("width persists across reload (AC10)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });

    const handle = resizeHandle(page);
    const box = await handle.boundingBox();
    if (!box) throw new Error("resize handle has no bounding box");
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + 120, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();
    const widened = await asideWidth(page);

    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const restored = await asideWidth(page);
    expect(Math.abs(restored - widened)).toBeLessThanOrEqual(2);
  });

  test("collapse takes precedence over a widened width (AC12)", async ({ page }) => {
    await setupNavMocks(page);
    // Pre-seed a widened width, then collapse — the rail must still be 56px and
    // the handle gone; the stored width is preserved for re-expand.
    await page.addInitScript((key) => {
      localStorage.setItem(key, "400");
    }, RAIL_WIDTH_KEY);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(resizeHandle(page)).toHaveCount(0);
    const width = await asideWidth(page);
    expect(width).toBeLessThanOrEqual(64); // ~56px collapsed rail
    // Stored width is untouched (returns on expand).
    const stored = await page.evaluate(
      (key) => localStorage.getItem(key),
      RAIL_WIDTH_KEY,
    );
    expect(stored).toBe("400");
  });

  test("a stored over-range width is clamped on hydration, never swallowing content (AC11 wiring)", async ({ page }) => {
    await setupNavMocks(page);
    // Seed a corrupt/oversized stored width; the layout must apply the CLAMPED
    // value (≤ RAIL_MAX_ABS_PX), proving the hook's clamp-on-read reaches the
    // aside — the wiring the unit clamp test cannot cover.
    await page.addInitScript((key) => {
      localStorage.setItem(key, "9999");
    }, RAIL_WIDTH_KEY);
    await gotoOrSkip(page, "/dashboard/kb");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const width = await asideWidth(page);
    expect(width).toBeLessThanOrEqual(RAIL_MAX_ABS_PX);
    expect(width).toBeGreaterThanOrEqual(224);
  });

  test("re-expanding a collapsed-but-widened rail restores the stored width (AC12 round-trip)", async ({ page }) => {
    await setupNavMocks(page);
    await page.addInitScript((key) => {
      localStorage.setItem(key, "360");
    }, RAIL_WIDTH_KEY);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    // Expand via ⌘B; the widened width must return.
    await page.keyboard.press("Meta+b");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const width = await asideWidth(page);
    expect(Math.abs(width - 360)).toBeLessThanOrEqual(2);
  });

  test("resize handle is KB-only — absent on Settings and Chat (AC13)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/settings");
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    await expect(resizeHandle(page)).toHaveCount(0);

    await gotoOrSkip(page, "/dashboard/chat");
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    await expect(resizeHandle(page)).toHaveCount(0);
  });
});

test.describe("widenable KB rail — mobile", () => {
  test.use({ viewport: MOBILE });

  test("no resize handle on mobile; drawer width untouched (AC viewport)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");
    // The handle is `hidden md:block`; on mobile it must not be visible.
    await expect(resizeHandle(page)).toBeHidden();
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
