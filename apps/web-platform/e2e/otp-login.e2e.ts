// pyramid-justified: intercepts `**/auth/v1/otp*` via page.route and drives
// the real rendered OTP form (banners, inputs, submit) — needs a real
// browser.
import { test, expect, type Page } from "@playwright/test";
import { EMAIL_OTP_LENGTH } from "../lib/auth/constants";
import { SIGNUP_REASON_NO_ACCOUNT } from "../lib/auth/error-messages";

/**
 * The /signup "no account" banner. The nav-pending island also renders
 * role="status" while the /login -> /signup navigation settles, so an
 * unfiltered getByRole("status") hits two elements and toContainText fails at
 * once with a strict-mode violation instead of polling (#9170). Select the
 * banner by its text instead.
 */
const noAccountBanner = (page: Page) =>
  page.getByRole("status").filter({ hasText: /no Soleur account found/i });

// ---------- OTP Login Flow Tests ----------
// These test the email OTP sign-in flow end-to-end.

/** Intercept the Supabase OTP request and return success so the OTP input renders. */
async function navigateToOtpStep(
  page: import("@playwright/test").Page,
  path: "/login" | "/signup",
) {
  await page.route("**/auth/v1/otp*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "{}" }),
  );
  await page.goto(path);
  const html = await page.content();
  if (html.includes('statusCode":500')) {
    test.skip(true, "Dev server CSS compilation error — skipped in worktree");
  }

  const emailInput = page.getByRole("textbox", { name: /you@example.com/i });
  await emailInput.waitFor({ timeout: 10_000 });
  await emailInput.fill("test@example.com");

  if (path === "/signup") {
    await page.getByRole("checkbox").check();
  }

  const sendButton = page.getByRole("button", {
    name: path === "/login" ? /send sign-in code/i : /send verification code/i,
  });
  await sendButton.click();

  await page.getByText(/sent a.*digit code/i).waitFor({ timeout: 5_000 });
}

test.describe("OTP login form", () => {
  test("login page renders email input and send code button", async ({
    page,
  }) => {
    await page.goto("/login");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error — skipped in worktree, passes in CI",
    );

    await expect(
      page.getByRole("textbox", { name: /you@example.com/i }),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.getByRole("button", { name: /send sign-in code/i }),
    ).toBeVisible();
  });

  test("login page shows sign-in code text instead of magic link", async ({
    page,
  }) => {
    await page.goto("/login");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );

    await expect(
      page.getByText("Enter your email to receive a sign-in code"),
    ).toBeVisible();
  });

  test("signup page renders email input and send verification code button", async ({
    page,
  }) => {
    await page.goto("/signup");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );

    await expect(
      page.getByRole("textbox", { name: /you@example.com/i }),
    ).toBeVisible({ timeout: 10_000 });
    await expect(
      page.getByRole("button", { name: /send verification code/i }),
    ).toBeVisible();
  });
});

test.describe("OTP callback error handling", () => {
  test("/login?error=auth_failed shows error message", async ({ page }) => {
    await page.goto("/login?error=auth_failed");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );

    await expect(
      page.getByText("Sign-in failed. If you have an existing account, try signing in with email instead."),
    ).toBeVisible({ timeout: 10_000 });
  });

});

// Request-only /callback redirect cases live at the unit layer:
// test/app/auth/callback-route-branches.test.ts covers bare-?code and
// invalid-code exchange failures with branch-precision assertions.

test.describe("Login no-account redirect", () => {
  test("submitting unknown email on /login redirects to /signup with prefill + banner", async ({
    page,
  }) => {
    // Mock Supabase OTP endpoint to return otp_disabled.
    // Verified shape against `node_modules/@supabase/auth-js/src/lib/fetch.ts:65-69` —
    // client reads `data.code` first, falls back to `data.error_code`. Status is 400
    // per `errors.ts:47` AuthApiError constructor convention.
    await page.route("**/auth/v1/otp*", (route) =>
      route.fulfill({
        status: 400,
        contentType: "application/json",
        body: JSON.stringify({
          code: "otp_disabled",
          error_code: "otp_disabled",
          msg: "Signups not allowed for otp",
          message: "Signups not allowed for otp",
        }),
      }),
    );

    await page.goto("/login");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );

    const email = "no-account@example.com";
    await page
      .getByRole("textbox", { name: /you@example.com/i })
      .fill(email);
    await page.getByRole("button", { name: /send sign-in code/i }).click();

    // Expect navigation to /signup with email + reason params
    await page.waitForURL(
      new RegExp(`/signup\\?.*reason=${SIGNUP_REASON_NO_ACCOUNT}`),
      { timeout: 5_000 },
    );
    expect(page.url()).toContain(`email=${encodeURIComponent(email)}`);

    // Email is prefilled
    const emailInput = page.getByRole("textbox", {
      name: /you@example.com/i,
    });
    await expect(emailInput).toHaveValue(email);

    // Deterministic stand-in for the nav-pending island: a second
    // role="status" element that is NOT the banner. An unfiltered locator
    // would hit both and fail strict mode, which is the #9170 flake.
    await page.evaluate(() => {
      const decoy = document.createElement("div");
      decoy.setAttribute("role", "status");
      decoy.textContent = "Loading";
      document.body.appendChild(decoy);
    });

    // Banner is visible
    await expect(noAccountBanner(page)).toContainText(
      /no Soleur account found/i,
    );
    await expect(noAccountBanner(page)).toContainText(email);

    // Banner dismisses on edit (derived from `email !== initialEmail`)
    await emailInput.fill(`${email}-edit`);
    await expect(noAccountBanner(page)).toHaveCount(0);
  });

  test("/signup with unknown reason value does NOT show the banner", async ({
    page,
  }) => {
    await page.goto(
      `/signup?email=${encodeURIComponent("foo@example.com")}&reason=other_value`,
    );
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );
    await expect(page.getByRole("status")).toHaveCount(0);
  });

  test("/signup with reason=no_account but no email param does NOT show the banner", async ({
    page,
  }) => {
    await page.goto(`/signup?reason=${SIGNUP_REASON_NO_ACCOUNT}`);
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );
    await expect(page.getByRole("status")).toHaveCount(0);
  });

  test("/signup with no query params shows no banner (baseline)", async ({
    page,
  }) => {
    await page.goto("/signup");
    const html = await page.content();
    test.skip(
      html.includes('statusCode":500'),
      "Dev server CSS compilation error",
    );
    await expect(page.getByRole("status")).toHaveCount(0);
  });
});

test.describe("OTP input validation", () => {
  test("OTP input maxLength matches EMAIL_OTP_LENGTH on login", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/login");
    const otpInput = page.locator('input[autocomplete="one-time-code"]');
    await expect(otpInput).toHaveAttribute(
      "maxlength",
      String(EMAIL_OTP_LENGTH),
    );
  });

  test("OTP input maxLength matches EMAIL_OTP_LENGTH on signup", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/signup");
    const otpInput = page.locator('input[autocomplete="one-time-code"]');
    await expect(otpInput).toHaveAttribute(
      "maxlength",
      String(EMAIL_OTP_LENGTH),
    );
  });

  test("submit button is disabled until OTP has correct length", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/login");
    const otpInput = page.locator('input[autocomplete="one-time-code"]');
    const submitButton = page.getByRole("button", { name: /sign in/i });

    // Partial code — button should be disabled
    await otpInput.fill("123");
    await expect(submitButton).toBeDisabled();

    // Full code — button should be enabled
    await otpInput.fill("1".repeat(EMAIL_OTP_LENGTH));
    await expect(submitButton).toBeEnabled();
  });

  test("instructional text shows correct digit count on login", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/login");
    await expect(
      page.getByText(`We sent a ${EMAIL_OTP_LENGTH}-digit code to`),
    ).toBeVisible();
  });

  test("instructional text shows correct digit count on signup", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/signup");
    await expect(
      page.getByText(`We sent a ${EMAIL_OTP_LENGTH}-digit code to`),
    ).toBeVisible();
  });

  test("OTP input truncates over-length code to EMAIL_OTP_LENGTH digits", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/login");
    const otpInput = page.locator('input[autocomplete="one-time-code"]');

    // Fill a code longer than EMAIL_OTP_LENGTH — maxLength should truncate
    const overLengthCode = "1".repeat(EMAIL_OTP_LENGTH + 2);
    await otpInput.fill(overLengthCode);
    const value = await otpInput.inputValue();
    expect(value.length).toBe(EMAIL_OTP_LENGTH);
  });

  test("OTP input accepts exactly EMAIL_OTP_LENGTH digits", async ({
    page,
  }) => {
    await navigateToOtpStep(page, "/login");
    const otpInput = page.locator('input[autocomplete="one-time-code"]');

    await otpInput.fill("1".repeat(EMAIL_OTP_LENGTH));
    const value = await otpInput.inputValue();
    expect(value.length).toBe(EMAIL_OTP_LENGTH);
  });
});
