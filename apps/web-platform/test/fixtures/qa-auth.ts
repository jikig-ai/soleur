/**
 * Playwright auth fixture for QA testing.
 *
 * Authenticates as the QA test user via password sign-in and injects
 * the session cookie into the browser context. Requires the QA user
 * to be seeded first via `scripts/seed-qa-user.sh`.
 *
 * Usage in a Playwright test:
 *   import { authenticateQaUser } from "./fixtures/qa-auth";
 *
 *   test("chat page renders", async ({ page }) => {
 *     await authenticateQaUser(page);
 *     await page.goto("http://localhost:3000/dashboard");
 *   });
 */
import type { Page } from "@playwright/test";

const QA_EMAIL = "qa-test@example.com";
const QA_PASSWORD = "qa-test-local-2026";

/**
 * Sign in the QA test user and set the session cookie on the page's
 * browser context. After calling this, the page can navigate to any
 * authenticated route.
 */
export async function authenticateQaUser(
  page: Page,
  options?: { port?: number },
): Promise<{ userId: string; conversationUrl?: string }> {
  const port = options?.port ?? 3000;
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !anonKey) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY must be set. " +
        "Run with: doppler run -p soleur -c dev -- npx playwright test",
    );
  }

  // Sign in via password to get session tokens
  const response = await fetch(
    `${supabaseUrl}/auth/v1/token?grant_type=password`,
    {
      method: "POST",
      headers: {
        apikey: anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email: QA_EMAIL, password: QA_PASSWORD }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `QA auth failed (${response.status}): ${body}. ` +
        "Did you run scripts/seed-qa-user.sh first?",
    );
  }

  const session = await response.json();
  const userId: string = session.user?.id;

  // Extract project ref from Supabase URL for the cookie name
  const projectRef = new URL(supabaseUrl).hostname.split(".")[0];
  const cookieName = `sb-${projectRef}-auth-token`;

  // Inject session cookie into the browser context
  const context = page.context();
  await context.addCookies([
    {
      name: cookieName,
      value: JSON.stringify(session),
      domain: "localhost",
      path: "/",
      httpOnly: false,
      secure: false,
      sameSite: "Lax",
    },
  ]);

  // Also set in localStorage for client-side Supabase reads
  await page.goto(`http://localhost:${port}/login`);
  await page.evaluate(
    ([key, val]) => localStorage.setItem(key, val),
    [cookieName, JSON.stringify(session)],
  );

  return { userId };
}
