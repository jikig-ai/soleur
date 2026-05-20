import { describe, test, expect, beforeEach, afterEach } from "vitest";
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

const APP_DOMAIN = "app.test.example";

let savedEnv: string | undefined;

beforeEach(() => {
  savedEnv = process.env.APP_DOMAIN;
  process.env.APP_DOMAIN = APP_DOMAIN;
});

afterEach(() => {
  if (savedEnv === undefined) {
    delete process.env.APP_DOMAIN;
  } else {
    process.env.APP_DOMAIN = savedEnv;
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
});
