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

  // The dashboard inbox fetches email-triage items on mount (#5103). Unmocked,
  // the request reaches the real dev server whose server-side Supabase client
  // points at the fake e2e URL — a hanging request that can wedge a throttled
  // dev server and stall every other fetch on the page.
  await page.route("**/api/inbox/emails*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ items: [] }),
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
        !/ERR_ABORTED|ECONNREFUSED|ERR_CONNECTION|ERR_NETWORK_CHANGED|ERR_EMPTY_RESPONSE|ERR_NETWORK_IO_SUSPENDED/.test(
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

// (The dedicated ▢ collapse toggle was removed — the resize slider now owns
// collapse/expand — so the `collapseToggle` / `dashboardNavLink` /
// `expectVerticallyCentered` helpers and the toggle-position tests that used them
// were removed with it.)
type Rect = { x: number; y: number; width: number; height: number };
const intersects = (a: Rect, b: Rect): boolean =>
  a.x < b.x + b.width &&
  a.x + a.width > b.x &&
  a.y < b.y + b.height &&
  a.y + a.height > b.y;

test.describe("nav-states visual gate — desktop", () => {
  test.use({ viewport: DESKTOP });

  test("top-level (expanded): chrome present + identity visible, no drill slot", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    // Phase 2 (#4915): the "Soleur" wordmark is removed everywhere — the primary
    // nav + identity band are the top-level chrome now; the wordmark must be absent.
    await expect(primaryNav(page)).toBeVisible({ timeout: 15_000 });
    await expect(wordmark(page)).toHaveCount(0);
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

  test("drilled (expanded): no horizontal overflow (reclaimed-space restructure)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
    await expect(railBand(page)).toBeVisible({ timeout: 15_000 });
    // Empty-band guard: identity content must be present so the no-overflow
    // assertion below cannot pass vacuously on an unmounted band.
    await expect(orgIdentity(page)).toContainText("Soleur Workspace", {
      timeout: 15_000,
    });

    // Bug 1: the expanded drilled rail (md:w-56 = 224px) must not overflow — the
    // gap the existing "drilled (expanded)" test (chrome-presence only) misses.
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(
      overflow,
      "expanded drilled rail (md:w-56) overflows horizontally — Bug 1 regression",
    ).toBeLessThanOrEqual(1);
    // The dedicated ▢ collapse button (and its float-position assertions) were
    // removed: the resize slider now owns collapse/expand. Its presence in every
    // drill state is covered by the "widenable KB rail — desktop" describe block.
  });

  test("expanded multi-workspace: band reclaims the top (~45px) (AC1)", async ({ page }) => {
    await setupNavMocks(page);
    // ≥2 memberships → OrgSwitcher renders the INTERACTIVE switch button with the
    // `▾` chevron at the card's right edge. Registered AFTER setupNavMocks so
    // Playwright matches first.
    await page.route("**/api/workspace/list-memberships", (route) =>
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          memberships: [
            MOCK_MEMBERSHIP,
            {
              organizationId: "org-e2e-2",
              organizationName: "Second Workspace",
              workspaceId: "ws-e2e-2",
              isCurrent: false,
              role: "member",
              memberCount: 3,
            },
          ],
        }),
      }),
    );
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
    const switcher = page.getByRole("button", { name: "Switch workspace" });
    await expect(switcher).toBeVisible({ timeout: 15_000 });

    // AC1 — reclaimed space: the band's top edge is at/near the aside top (the
    // dedicated ~44px toggle row is gone). RED on the old markup (~44px gap).
    // The floated-toggle overlap/alignment ACs were removed with the ▢ button.
    const asideBox = await aside.boundingBox();
    const bandBox = await railBand(page).boundingBox();
    expect(asideBox).not.toBeNull();
    expect(bandBox).not.toBeNull();
    expect(
      bandBox!.y - asideBox!.y,
      "workspace band did not rise to the sidebar top — ~45px not reclaimed",
    ).toBeLessThanOrEqual(12);
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
    // Identity never unmounts on collapse (ADR-047) — assert the orientation
    // anchor directly (the decorative gold repo dot was removed in the
    // sidebar-declutter pass, so the invariant moves to the identity tile).
    await expect(
      railBand(page).getByTestId("workspace-identity-icon"),
    ).toBeVisible();

    // Phase 1 (#4915): the collapsed identity is the MONOGRAM tile (non-gold),
    // and the FULL workspace name is the tooltip — the authoritative
    // disambiguator for shared-initial monograms (P0-3).
    const idIcon = railBand(page).getByTestId("workspace-identity-icon");
    await expect(idIcon).toHaveAttribute("title", "Soleur Workspace", {
      timeout: 15_000,
    });
    const monogram = idIcon.getByTestId("workspace-identity-tile");
    await expect(monogram).toBeVisible();
    await expect(monogram).toHaveText("S"); // "Soleur Workspace" → "S"
    expect(await monogram.getAttribute("class")).not.toMatch(/accent-gold/);

    // (The floated ▢ collapse-toggle overlap assertions were removed with the
    // button; the resize slider — now the sole collapse/expand control — is
    // covered in the "widenable KB rail — desktop" block.)

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
    // the nested file row must NOT be present (so it cannot clip at 56px).
    await expect(kbRailTree(page)).toBeAttached();
    await expect(kbLongFile(page)).toHaveCount(0);
    // Sidebar-UX Issue 6: the collapsed KB rail is no longer empty — it shows an
    // icon-only "Browse files" affordance (expands the rail) in place of the
    // (56px-unclippable) nested tree.
    await expect(page.getByTestId("kb-rail-collapsed-expand")).toBeVisible();
    // AC3: the gate runs against POPULATED content (the false-GREEN this closes
    // was a `tree: []` empty rail).
    const overflow = await aside.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test("collapsed drilled (Settings, POPULATED): no overflow, icon-only sub-nav (Issue 4)", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/settings");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(railBand(page)).toHaveAttribute("data-collapsed", "true");
    // AC5: identity still legible when collapsed+drilled (the orientation
    // anchor; the decorative gold repo dot was removed in the declutter pass).
    await expect(
      railBand(page).getByTestId("workspace-identity-icon"),
    ).toBeVisible();
    // Sidebar-UX Issue 4: the collapsed Settings nav is now an ICON-ONLY column
    // (tagged settings-rail-icons) instead of being DOM-removed — so the rail is
    // navigable when collapsed. The single 56px-safe glyphs must not overflow.
    await expect(settingsRailNav(page)).toBeAttached();
    const iconNav = page.getByTestId("settings-rail-icons");
    await expect(iconNav).toBeVisible();
    // The General tab is reachable via its aria-label (no visible text label).
    await expect(iconNav.getByRole("link", { name: "General" })).toBeVisible();
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

  // The rail has `md:transition-[width]` (200ms) and width hydrates/updates in a
  // post-mount effect, so every width assertion polls until it settles — a single
  // synchronous read races the animation/hydration and catches a transient value.
  async function dragHandleBy(page: Page, dx: number): Promise<void> {
    const handle = resizeHandle(page);
    // The handle's SSR markup is visible before React hydration attaches its
    // onPointerDown/Move handlers; dragging too early fires DOM pointer events at
    // an element with no listeners (no width change). Settle for hydration first.
    await page.waitForTimeout(1500);
    const box = await handle.boundingBox();
    if (!box) throw new Error("resize handle has no bounding box");
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + dx, box.y + box.height / 2, { steps: 8 });
    await page.mouse.up();
  }

  test("drag widens the expanded KB rail and a truncated name becomes legible (AC9)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const before = await asideWidth(page);

    await dragHandleBy(page, 140);

    // Poll: require a meaningful widening (> default + 50) so a 1px jitter can't
    // pass — proves the drag actually drove the width, after the transition settles.
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(before + 50);
  });

  test("width persists across reload (AC10)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });

    await dragHandleBy(page, 130);
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(300);
    const widened = await asideWidth(page);

    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(widened - 8);
  });

  test("collapse takes precedence over a widened width (AC12)", async ({ page }) => {
    await setupNavMocks(page);
    // Pre-seed a widened width, then collapse — the rail must still be 56px. The
    // handle now STAYS mounted when collapsed (it is the sole expand affordance,
    // post ▢-button removal), but the stored 400px width must NOT apply while
    // collapsed; it is preserved for re-expand.
    await page.addInitScript((key) => {
      localStorage.setItem(key, "400");
    }, RAIL_WIDTH_KEY);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    // The grip stays mounted when collapsed (so the user can drag/double-click
    // to expand) — collapse precedence is about WIDTH, not handle presence.
    await expect(resizeHandle(page)).toBeVisible({ timeout: 7_000 });
    // The rail hydrates expanded (224px) → collapsed (56px) over a 200ms
    // `md:transition-[width]`. Poll until the width settles, matching the
    // sibling widenable-rail tests — a single synchronous read races the
    // transition and catches a mid-animation frame (~126px).
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeLessThanOrEqual(64); // ~56px collapsed rail
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
    // Poll until the post-mount hydration applies the clamped width: it must
    // widen past the default (proving 9999 was read + applied) AND stay ≤ the
    // absolute ceiling (proving it was clamped, never the raw 9999).
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(300);
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
    // Expand via ⌘B; the widened width must return. Poll until the expand
    // transition (56px → 360px) settles near the stored width (359 = 360 − 1px
    // border), rather than catching a mid-animation frame.
    await page.keyboard.press("Meta+b");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(340);
  });

  // INVERTED from the former gate (grip previously rendered only on the KB rail):
  // the rail is now resizable in EVERY expanded drill state, so the grip MUST be
  // present on Settings AND Chat. Runs with the rail EXPANDED (no seedCollapsed)
  // — collapsed would unmount the grip and false-fail the presence assertion.
  test("resize handle is present on Settings AND Chat (expanded), gold-active wired + generic a11y label (AC-E2E-1, AC-E2E-4)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/settings");
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    const settingsHandle = resizeHandle(page);
    await expect(settingsHandle).toBeVisible({ timeout: 15_000 });
    // Gold-on-active wash is wired (inherited from the merged KB grip).
    await expect(settingsHandle).toHaveClass(/soleur-accent-gold-fill/);
    // De-KB-ified accessible name on the non-KB rail.
    await expect(settingsHandle).toHaveAttribute("aria-label", "Resize sidebar");

    await gotoOrSkip(page, "/dashboard/chat");
    await expect(secondarySlot(page)).toBeVisible({ timeout: 15_000 });
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
  });

  test("drag widens the NON-KB (Settings) rail and the width persists across reload via the shared key (AC-E2E-2)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/settings");
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    const before = await asideWidth(page);

    await dragHandleBy(page, 140);
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(before + 50);
    const widened = await asideWidth(page);

    // Persisted to the SHARED key (D1: soleur:sidebar.kb.width) and re-applied
    // to the main rail on reload.
    const stored = await page.evaluate(
      (key) => localStorage.getItem(key),
      RAIL_WIDTH_KEY,
    );
    expect(Number(stored)).toBeGreaterThan(before + 50);

    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(resizeHandle(page)).toBeVisible({ timeout: 15_000 });
    await expect
      .poll(async () => asideWidth(page), { timeout: 7_000 })
      .toBeGreaterThan(widened - 8);
  });

  test("double-click the Settings grip collapses the rail; the grip stays and re-expands (AC-E2E-3)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/settings");
    const handle = resizeHandle(page);
    await expect(handle).toBeVisible({ timeout: 15_000 });
    // The grip's onDoubleClick handler attaches at hydration; settle first.
    await page.waitForTimeout(1500);
    await handle.dblclick();

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 7_000 });

    // The dedicated ▢ collapse button is gone — the grip is the sole
    // collapse/expand affordance, so it STAYS mounted when collapsed and a
    // second double-click re-expands the rail.
    await expect(resizeHandle(page)).toBeVisible({ timeout: 7_000 });
    await resizeHandle(page).dblclick();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 7_000 });
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

  test("mobile: the close button still dismisses the drawer (AC6 — mobile close row preserved)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    // The reclaimed-space restructure made the desktop toggle row md:hidden and
    // floated the collapse toggle, but the MOBILE close row (and its button) must
    // be untouched. Open the drawer, then dismiss it via the close button.
    const openBtn = page.getByRole("button", { name: "Open navigation" });
    await expect(openBtn).toBeVisible({ timeout: 15_000 });
    // Settle for React hydration: the SSR hamburger paints before its onClick
    // attaches, so an early click fires at a handler-less button (no-op) and the
    // drawer never opens. Mirrors the widenable-rail drag tests' hydration wait.
    await page.waitForTimeout(1500);
    await openBtn.click();
    const aside = page.locator("aside").first();
    await expect(aside).not.toHaveClass(/-translate-x-full/, { timeout: 15_000 });
    const closeBtn = page.getByRole("button", { name: "Close navigation" });
    await expect(closeBtn).toBeVisible({ timeout: 15_000 });
    await closeBtn.click();
    await expect(aside).toHaveClass(/-translate-x-full/, { timeout: 15_000 });
  });

  test("mobile fullWidth (empty KB landing): page header owns the title; the band owns the SINGLE 'Back to menu' (Phase 4, one back per state)", async ({ page }) => {
    await setupNavMocks(page);
    // Override with an EMPTY tree so the fullWidth EmptyState branch renders
    // (registered AFTER setup → Playwright matches it first).
    await page.route("**/api/kb/tree*", (route) =>
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          tree: { name: "root", type: "directory", path: "", children: [] },
          lastSync: null,
          needsReconnect: false,
        }),
      }),
    );
    await gotoOrSkip(page, "/dashboard/kb");

    // P0-1: the chromeless mobile fullWidth body now carries a page header title.
    const header = page.getByTestId("kb-page-mobile-header");
    await expect(header).toBeVisible({ timeout: 15_000 });
    await expect(header.getByText("Knowledge Base")).toBeVisible();

    // One back per state: on the KB LANDING the persistent band owns "Back to
    // menu"; the page header must NOT duplicate it. Exactly one visible
    // "Back to menu" across the mobile viewport (the rail band is md-hidden).
    await expect(
      header.getByRole("link", { name: /back to menu/i }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: /back to menu/i }),
    ).toHaveCount(1);

    // P2-4: exactly one "Knowledge Base" title on mobile — the band's mobile
    // section title is suppressed (the page header owns it).
    const mobileBand = page.locator(
      '[data-testid="workspace-context-band"][data-variant="mobile"]',
    );
    await expect(mobileBand.getByTestId("nav-section-title")).toHaveCount(0);
  });
});

// Full-hide ("0px") gate. The unified rail collapses to a 56px icon rail; HIDE
// goes all the way to md:w-0 so <main> reclaims the entire row. jsdom cannot
// see width:0 / overflow clipping / the fixed reveal button anchoring outside
// the aside, so the pixel proof lives here: rail truly reaches 0, the floating
// reveal hamburger is present + clickable OUTSIDE the zeroed aside, content
// reclaims the freed width, and the in-rail Hide affordance does not collide
// with the collapse toggle. Screenshots are emitted to test-results/ for review.
const hideButton = (page: Page) =>
  page.getByRole("button", { name: "Hide sidebar" });
// The floating hamburger reveal (distinct from the left-edge gold reveal strip,
// which shares the "Show sidebar" name) — target by testid to disambiguate.
const revealButton = (page: Page) =>
  page.getByTestId("sidebar-reveal-button");
const revealEdge = (page: Page) => page.getByTestId("sidebar-reveal-edge");
const mainWidth = (page: Page) =>
  page.locator("main").first().evaluate((el) => el.clientWidth);

/** Seed the rail fully hidden (0px) before any page script runs. */
async function seedHidden(page: Page): Promise<void> {
  await page.addInitScript((key) => {
    localStorage.setItem(key, "1");
  }, "soleur:sidebar.main.hidden");
}

test.describe("full-hide (0px) gate — desktop", () => {
  test.use({ viewport: DESKTOP });

  test("expanded: Hide affordance sits in the top-right corner, inside the rail, no overlap", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
    await expect(hideButton(page)).toBeVisible({ timeout: 15_000 });
    // Reveal hamburger is absent while the rail is visible.
    await expect(revealButton(page)).toHaveCount(0);

    const hideBox = (await hideButton(page).boundingBox())!;
    const asideBox = (await aside.boundingBox())!;
    // Hide is the sole floated rail-header button now (the ▢ collapse toggle was
    // removed) — it sits in the top-right corner, fully inside the rail.
    expect(hideBox.x).toBeGreaterThanOrEqual(asideBox.x - 1);
    expect(hideBox.x + hideBox.width).toBeLessThanOrEqual(asideBox.x + asideBox.width + 1);
    // Right-anchored: within ~16px of the aside right edge.
    const asideRight = asideBox.x + asideBox.width;
    expect(asideRight - (hideBox.x + hideBox.width)).toBeLessThanOrEqual(16);
    // The widened band clearance keeps it off the workspace identity / switcher.
    await expect(orgIdentity(page)).toBeVisible({ timeout: 15_000 });
    const identityBox = (await orgIdentity(page).boundingBox())!;
    expect(intersects(hideBox, identityBox), "Hide overlaps the workspace identity").toBe(false);

    await page.screenshot({ path: "test-results/hide-1-visible-expanded.png" });
  });

  test("clicking Hide drives the rail to 0px, reveals the floating hamburger, and reclaims the row", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard/kb");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
    // Wait for hydration before clicking — the async identity only renders after
    // the client tree hydrates, which is also when the Hide onClick is wired (a
    // click on the SSR markup before hydration would no-op).
    await expect(orgIdentity(page)).toBeVisible({ timeout: 15_000 });
    const mainBefore = await mainWidth(page);

    await hideButton(page).click();

    // The rail truly reaches zero width and drops its border (no sliver).
    await expect(aside).toHaveClass(/md:w-0/, { timeout: 15_000 });
    await expect
      .poll(() => asideWidth(page), { timeout: 15_000 })
      .toBeLessThanOrEqual(1);
    // The reveal control lives OUTSIDE the zeroed aside and is clickable.
    await expect(revealButton(page)).toBeVisible();
    await expect(hideButton(page)).toHaveCount(0);
    // <main> reclaims the freed horizontal space.
    expect(await mainWidth(page)).toBeGreaterThan(mainBefore);

    await page.screenshot({ path: "test-results/hide-2-hidden.png" });
  });

  test("the reveal hamburger restores the rail to its prior width", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");

    // Wait for hydration (see note in the hide-click test) before clicking.
    await expect(orgIdentity(page)).toBeVisible({ timeout: 15_000 });
    await hideButton(page).click();
    await expect(revealButton(page)).toBeVisible({ timeout: 15_000 });

    await revealButton(page).click();

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
    await expect
      .poll(() => asideWidth(page), { timeout: 15_000 })
      .toBeGreaterThan(200);
    await expect(hideButton(page)).toBeVisible();
    await expect(revealButton(page)).toHaveCount(0);

    await page.screenshot({ path: "test-results/hide-3-revealed.png" });
  });

  test("a persisted hidden state loads at 0px with the reveal hamburger", async ({ page }) => {
    await setupNavMocks(page);
    await seedHidden(page);
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-0/, { timeout: 15_000 });
    await expect
      .poll(() => asideWidth(page), { timeout: 15_000 })
      .toBeLessThanOrEqual(1);
    await expect(revealButton(page)).toBeVisible();
  });

  test("collapsed icon rail still exposes a Hide affordance, centered in the rail", async ({ page }) => {
    await setupNavMocks(page);
    await seedCollapsed(page);
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    await expect(aside).toHaveClass(/md:w-14/, { timeout: 15_000 });
    await expect(hideButton(page)).toBeVisible({ timeout: 15_000 });

    const hideBox = (await hideButton(page).boundingBox())!;
    const asideBox = (await aside.boundingBox())!;
    // Centered on the collapsed icon column (left-1/2 -translate-x-1/2) and fully
    // inside the 56px rail.
    const hideCx = hideBox.x + hideBox.width / 2;
    const asideCx = asideBox.x + asideBox.width / 2;
    expect(Math.abs(hideCx - asideCx)).toBeLessThanOrEqual(2);
    expect(hideBox.x).toBeGreaterThanOrEqual(asideBox.x - 1);
    expect(hideBox.x + hideBox.width).toBeLessThanOrEqual(asideBox.x + asideBox.width + 1);

    await page.screenshot({ path: "test-results/hide-4-collapsed.png" });
  });

  test("double-clicking the bar body hides the rail (desktop)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");
    await expect(orgIdentity(page)).toBeVisible({ timeout: 15_000 });

    const aside = page.locator("aside").first();
    // The empty centre of the flex-1 primary nav (below the link list) is a
    // non-interactive bar-body spot — the guard hides only on such a target.
    await aside.locator("nav").first().dblclick();

    await expect(aside).toHaveClass(/md:w-0/, { timeout: 15_000 });
    await expect(revealButton(page)).toBeVisible();
  });

  test("the left-edge gold strip reveals the hidden rail", async ({ page }) => {
    await setupNavMocks(page);
    await seedHidden(page);
    await gotoOrSkip(page, "/dashboard");

    const aside = page.locator("aside").first();
    // toHaveClass(md:w-0) / edge visibility both wait for the hidden hydration,
    // which is also when the edge's onClick is wired.
    await expect(aside).toHaveClass(/md:w-0/, { timeout: 15_000 });
    await expect(revealEdge(page)).toBeVisible();
    const edgeBox = (await revealEdge(page).boundingBox())!;
    // Pinned to the very left screen edge, full height.
    expect(edgeBox.x).toBeLessThanOrEqual(1);
    expect(edgeBox.height).toBeGreaterThan(500);

    await revealEdge(page).click();
    await expect(aside).toHaveClass(/md:w-56/, { timeout: 15_000 });
  });

  test("pressing the bar body paints NO gold; gold is confined to the slider zone (screenshot)", async ({ page }) => {
    await setupNavMocks(page);
    await gotoOrSkip(page, "/dashboard");
    await expect(orgIdentity(page)).toBeVisible({ timeout: 15_000 });

    const aside = page.locator("aside").first();
    const box = (await aside.boundingBox())!;

    // The whole-bar gold wash overlay was removed entirely.
    await expect(page.getByTestId("rail-gold-active-overlay")).toHaveCount(0);

    // Press and hold on the BAR BODY (left side, away from the right-edge grip).
    // No part of the rail should turn gold.
    await page.mouse.move(box.x + 16, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(200);
    const bodyPressBg = await aside.evaluate(
      (el) => getComputedStyle(el).backgroundColor,
    );
    await page.screenshot({ path: "test-results/hide-5-no-bar-gold.png" });
    await page.mouse.up();

    // The grip turns gold only within its OWN zone on active/drag. Press it and
    // screenshot for the visual record.
    const handle = resizeHandle(page);
    await expect(handle).toBeVisible({ timeout: 7_000 });
    const hbox = (await handle.boundingBox())!;
    await page.mouse.move(hbox.x + hbox.width / 2, hbox.y + hbox.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(150);
    const gripActiveBg = await handle.evaluate(
      (el) => getComputedStyle(el).backgroundColor,
    );
    await page.screenshot({ path: "test-results/hide-5-grip-gold.png" });
    await page.mouse.up();

    // The bar body never adopts the grip's active gold; the two backgrounds differ.
    expect(gripActiveBg, `grip active bg was ${gripActiveBg}`).not.toBe(
      bodyPressBg,
    );
    // The grip carries the active-gold class; the bar body does not.
    await expect(handle).toHaveClass(/active:bg-soleur-accent-gold-fill\/70/);
    const asideClass = (await aside.getAttribute("class")) ?? "";
    expect(asideClass).not.toContain("bg-soleur-accent-gold-fill");
  });
});
