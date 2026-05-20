import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";

// Smoke-renders /internal/github-app-init/page.tsx to static markup and
// asserts both branches behave as the plan §Phase 2 specifies:
//
//   - No callback params -> manifest-POST form with `name="manifest"` hidden
//     input containing the JSON-stringified manifest.
//   - Any callback param (code|installation_id|setup_action) -> informational
//     view with no <form ... action="https://github.com/..."> element.
//
// Replaces the dev-server curl smoke from plan Phase 2.4 — equivalent
// verification, survives in CI without booting Next.js.
//
// Ref #4115.

// APP_DOMAIN must be in the page's allowlist (app.soleur.ai or
// app.dev.soleur.ai). Using app.dev.soleur.ai for tests; the page throws
// otherwise as defense-in-depth against a Doppler config swap.
const APP_DOMAIN = "app.dev.soleur.ai";
const ADMIN_USER_ID = "test-admin-uuid";

// Mock next/navigation.redirect (server-only API). The mock throws a
// labeled Error so tests can assert WHICH redirect fired.
vi.mock("next/navigation", () => ({
  redirect: (target: string) => {
    throw new Error(`REDIRECT:${target}`);
  },
}));

// Mock the supabase server client used by the operator gate. Tests can
// override the returned user via `setMockUser` below.
let mockUser: { id: string } | null = { id: ADMIN_USER_ID };
function setMockUser(u: { id: string } | null): void {
  mockUser = u;
}
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: {
      getUser: async () => ({ data: { user: mockUser } }),
    },
  }),
}));

let savedAppDomain: string | undefined;
let savedAdminIds: string | undefined;

beforeEach(() => {
  savedAppDomain = process.env.APP_DOMAIN;
  savedAdminIds = process.env.ADMIN_USER_IDS;
  process.env.APP_DOMAIN = APP_DOMAIN;
  process.env.ADMIN_USER_IDS = ADMIN_USER_ID;
  setMockUser({ id: ADMIN_USER_ID });
});

afterEach(() => {
  if (savedAppDomain === undefined) {
    delete process.env.APP_DOMAIN;
  } else {
    process.env.APP_DOMAIN = savedAppDomain;
  }
  if (savedAdminIds === undefined) {
    delete process.env.ADMIN_USER_IDS;
  } else {
    process.env.ADMIN_USER_IDS = savedAdminIds;
  }
});

async function loadPage() {
  // Import fresh so process.env.APP_DOMAIN is read on each test.
  const mod = await import(
    "@/app/internal/github-app-init/page"
  );
  return mod.default;
}

describe("/internal/github-app-init page", () => {
  test("default mode renders manifest-POST form with hidden input", async () => {
    const Page = await loadPage();
    const html = renderToStaticMarkup(
      await Page({ searchParams: Promise.resolve({}) }),
    );
    expect(html).toContain('action="https://github.com/settings/apps/new"');
    expect(html).toContain('name="manifest"');
    // The hidden input value must contain the JSON-stringified manifest with
    // ${app_domain} substituted.
    expect(html).toContain(`https://${APP_DOMAIN}/internal/github-app-init`);
    expect(html).toContain(`https://${APP_DOMAIN}/api/webhooks/github`);
    expect(html).toContain(`https://${APP_DOMAIN}/dashboard/repos`);
    // Placeholder must NOT survive substitution into rendered output.
    expect(html).not.toContain("${app_domain}");
  });

  test.each([
    { code: "test-discard-me" },
    { installation_id: "42", setup_action: "install" },
    { code: "abc", state: "xyz" } as Record<string, string>,
  ])("callback param %o renders informational view (no POST form)", async (params) => {
    const Page = await loadPage();
    const html = renderToStaticMarkup(
      await Page({ searchParams: Promise.resolve(params) }),
    );
    expect(html).not.toContain('action="https://github.com/settings/apps/new"');
    expect(html).not.toContain('name="manifest"');
    expect(html).toContain("GitHub callback received");
  });

  test("default mode without APP_DOMAIN throws (fail-loud)", async () => {
    delete process.env.APP_DOMAIN;
    const Page = await loadPage();
    await expect(
      Page({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow(/APP_DOMAIN/);
  });

  test("APP_DOMAIN outside allowlist throws", async () => {
    process.env.APP_DOMAIN = "app.evil.example";
    const Page = await loadPage();
    await expect(
      Page({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow(/allowlist/);
  });

  test("unauthenticated visitor redirects to /login", async () => {
    setMockUser(null);
    const Page = await loadPage();
    await expect(
      Page({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/login");
  });

  test("non-admin authenticated visitor redirects to /dashboard", async () => {
    setMockUser({ id: "not-an-admin-uuid" });
    const Page = await loadPage();
    await expect(
      Page({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard");
  });
});
