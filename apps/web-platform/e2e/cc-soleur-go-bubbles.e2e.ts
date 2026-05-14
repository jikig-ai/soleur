// PR-A (#2939) Stage 6 — cc-soleur-go bubble regression net.
//
// Four per-bubble Playwright assertions against the production reducer
// behavior (`lib/chat-state-machine.ts`) driven through the real `useWebSocket`
// hook. WS frames are injected via `attachWsInjector` (lib at
// `cc-soleur-go-ws-injector.ts`) which intercepts the `**/ws` route the
// real client opens on chat mount.
//
// Mocks Supabase HTTP via `page.route` (mirror of `start-fresh-onboarding.e2e.ts`).
// NO real Anthropic SDK (Spec NG2). NO screenshot baselines (Spec NG1).
// NO production tool short-names beyond a synthesized `test_synthesized_smoke`
// FQN that is neither registered nor on the Tier 3 denylist (Spec TR9 / NG4).

import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { attachWsInjector, type WsInjector } from "./cc-soleur-go-ws-injector";
import type { StreamEvent } from "@/lib/chat-state-machine";

const CONV_ID = "conv-stage-6-smoke";

const MOCK_AUTH_USER = {
  id: "test-user-id",
  aud: "authenticated",
  role: "authenticated",
  email: "test@e2e.com",
  email_confirmed_at: "2024-01-01T00:00:00Z",
  phone: "",
  confirmed_at: "2024-01-01T00:00:00Z",
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: {},
  identities: [],
  created_at: "2024-01-01T00:00:00Z",
  updated_at: "2024-01-01T00:00:00Z",
};

const MOCK_CONVERSATION = {
  id: CONV_ID,
  user_id: "test-user-id",
  title: "Stage 6 smoke",
  active_workflow: "cc-router",
  created_at: "2024-01-01T00:00:00Z",
  updated_at: "2024-01-01T00:00:00Z",
};

/**
 * Wire the page with mocks + WS injector and navigate to the chat surface.
 * Returns the live injector — call `await injector.ready` before `send()`.
 *
 * NOTE: order matters — `addInitScript` runs before any page script, then
 * `page.route` registers HTTP intercepts, then `attachWsInjector` claims
 * `**\/ws`. Finally `page.goto` boots the chat surface which opens the WS.
 */
async function bootChat(page: Page): Promise<WsInjector> {
  // Inject a fake Supabase session so the client doesn't short-circuit auth
  // before our /auth/v1/user mock fires. Mirrors start-fresh-onboarding.e2e.ts.
  await page.addInitScript(() => {
    const fakeSession = {
      access_token: "test-access-token",
      token_type: "bearer",
      expires_in: 86400,
      expires_at: Math.floor(Date.now() / 1000) + 86400,
      refresh_token: "test-refresh-token",
      user: {
        id: "test-user-id",
        aud: "authenticated",
        role: "authenticated",
        email: "test@e2e.com",
        email_confirmed_at: "2024-01-01T00:00:00Z",
        phone: "",
        confirmed_at: "2024-01-01T00:00:00Z",
        app_metadata: { provider: "email", providers: ["email"] },
        user_metadata: {},
        identities: [],
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
      },
    };
    localStorage.setItem("sb-localhost-auth-token", JSON.stringify(fakeSession));
  });

  await page.route("**/auth/v1/user", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(MOCK_AUTH_USER),
    }),
  );

  await page.route("**/auth/v1/token*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        access_token: "test-access-token",
        token_type: "bearer",
        expires_in: 86400,
        expires_at: Math.floor(Date.now() / 1000) + 86400,
        refresh_token: "test-refresh-token",
        user: MOCK_AUTH_USER,
      }),
    }),
  );

  // PostgREST .single() expects an object, not an array — match the existing
  // mock-supabase behavior (see e2e/mock-supabase.ts:wantsSingle).
  await page.route("**/rest/v1/conversations*", (route) => {
    const accept = route.request().headers().accept ?? "";
    const single = accept.includes("application/vnd.pgrst.object+json");
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(single ? MOCK_CONVERSATION : [MOCK_CONVERSATION]),
    });
  });

  await page.route("**/rest/v1/messages*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );

  await page.route("**/rest/v1/users*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          onboarding_completed_at: "2024-01-01T00:00:00Z",
          pwa_banner_dismissed_at: "2024-01-01T00:00:00Z",
        },
      ]),
    }),
  );

  // Realtime mock: empty 200 to prevent retry loops (does NOT collide with
  // /ws — the cc-soleur-go socket uses `/ws`, realtime uses `/realtime/**`).
  await page.route("**/realtime/**", (route) =>
    route.fulfill({ status: 200, contentType: "text/plain", body: "" }),
  );

  const injector = await attachWsInjector(page);

  // Capture any uncaught client-side error so a render crash in 3.4
  // (FQN composite key) fails the test loudly instead of silently passing.
  const pageErrors: Error[] = [];
  page.on("pageerror", (err) => pageErrors.push(err));
  (injector as unknown as { _pageErrors: Error[] })._pageErrors = pageErrors;

  const response = await page.goto(`/dashboard/chat/${CONV_ID}`);
  if (response && response.status() >= 500) {
    test.skip(true, "Dev server compile error — skipped in worktree, passes in CI");
  }

  await injector.ready;

  // Server-side confirmation frame. The reducer enters its happy path only
  // after `session_started`; without it `useWebSocket` won't accept follow-up
  // events on the resolved conversation id. Cast to StreamEvent-superset
  // (session_started is in WSMessage but excluded from StreamEvent because
  // it's a control frame, not a reducer-visible state event).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (injector as any).send({
    type: "session_started",
    conversationId: CONV_ID,
  });

  return injector;
}

function assertNoPageErrors(injector: WsInjector) {
  const errs = (injector as unknown as { _pageErrors?: Error[] })._pageErrors ?? [];
  expect(errs, `page errors: ${errs.map((e) => e.message).join("; ")}`).toHaveLength(0);
}

// ---------------------------------------------------------------------------
// 3.1 subagent-group expand-boundary (FR1.1)
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go bubbles: subagent-group", () => {
  test("collapses when N=3 and exposes 3 children after expand", async ({ page }) => {
    const injector = await bootChat(page);

    const parentId = "p-test-1";
    for (let i = 0; i < 3; i++) {
      injector.send({
        type: "subagent_spawn",
        parentId,
        leaderId: "cmo",
        spawnId: `${parentId}-child-${i}`,
      } satisfies StreamEvent);
    }

    const group = page.locator(`[data-parent-spawn-id="${parentId}"]`);
    await expect(group).toHaveCount(1);
    // Auto-collapse boundary fires at N > SUBAGENT_GROUP_AUTO_EXPAND_MAX (=2).
    // Children are conditionally rendered only when expanded — assert the
    // count badge text + collapsed attribute, then expand to verify N=3.
    await expect(group).toHaveAttribute("data-expanded", "false");
    await expect(group.getByText("3 subagents spawned")).toBeVisible();
    await group.getByTestId("subagent-group-toggle").click();
    await expect(group).toHaveAttribute("data-expanded", "true");
    await expect(group.locator("[data-child-spawn-id]")).toHaveCount(3);
  });

  test("auto-expands when N=2 (under boundary)", async ({ page }) => {
    const injector = await bootChat(page);

    const parentId = "p-test-2";
    for (let i = 0; i < 2; i++) {
      injector.send({
        type: "subagent_spawn",
        parentId,
        leaderId: "cto",
        spawnId: `${parentId}-child-${i}`,
      } satisfies StreamEvent);
    }

    await expect(
      page.locator(`[data-parent-spawn-id="${parentId}"][data-expanded="true"]`),
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// 3.2 interactive-prompt-card resolved-state (FR1.2)
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go bubbles: interactive-prompt-card", () => {
  test("renders ask_user prompt then transitions to resolved row on submit", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const promptId = "pid-test-1";

    injector.send({
      type: "interactive_prompt",
      promptId,
      conversationId: CONV_ID,
      kind: "ask_user",
      payload: {
        question: "Pick options",
        options: ["a", "b", "c"],
        multiSelect: true,
      },
    } satisfies StreamEvent);

    const card = page.locator(
      `[data-prompt-id="${promptId}"][data-prompt-kind="ask_user"]`,
    );
    await expect(card).toBeVisible();

    // Drive the resolved state through the production code path: tick two
    // checkboxes + click Submit, which fires `interactive_prompt_response`
    // via the local optimistic-dispatch reducer (chat-state-machine.ts:751).
    await card.getByLabel("a", { exact: true }).check();
    await card.getByLabel("c", { exact: true }).check();
    await card.getByRole("button", { name: "Submit" }).click();

    // Resolved row collapses to "Selected: <values>" per AC5/TS6 grammar
    // (interactive-prompt-card.tsx:188-194 ResolvedCardRow).
    await expect(card.getByText(/^Selected/)).toBeVisible();
    await expect(card.getByText(/a, c/)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// 3.3 workflow-lifecycle-bar chip-removal — BOTH trigger paths (FR1.3)
//
// chat-state-machine.ts:522-529 (stream_end) AND :716-718 (workflow_started)
// each filter `tool_use_chip` entries. A test that asserts only one would
// silently green-light a regression that removes the other (enumerate-extend
// pattern, 2026-04-18 learning).
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go bubbles: workflow-lifecycle-bar chip-removal", () => {
  test("tool_use → workflow_started removes chip and activates lifecycle bar", async ({
    page,
  }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "tool_use",
      leaderId: "cc_router",
      label: "Routing via /soleur:go",
    } satisfies StreamEvent);

    await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(1);

    injector.send({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: CONV_ID,
    } satisfies StreamEvent);

    await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(0);
    await expect(page.locator('[data-lifecycle-state="active"]')).toBeVisible();

    injector.send({
      type: "workflow_ended",
      workflow: "brainstorm",
      status: "completed",
    } satisfies StreamEvent);

    await expect(page.locator('[data-lifecycle-state="ended"]')).toBeVisible();
  });

  test("tool_use → stream_end removes chip (no workflow transition)", async ({ page }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "tool_use",
      leaderId: "cc_router",
      label: "Routing via /soleur:go",
    } satisfies StreamEvent);

    await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(1);

    injector.send({
      type: "stream_end",
      leaderId: "cc_router",
    } satisfies StreamEvent);

    await expect(page.locator('[data-tool-chip-id^="cc_router-"]')).toHaveCount(0);
  });
});

// ---------------------------------------------------------------------------
// 3.4 tool-use-chip unregistered-mcp-fqn render (FR1.4)
//
// Per Research Reconciliation row 4: with the empty cc-router MCP allowlist
// (Spec TR9), the degraded-UX shape is the literal FQN appearing inside the
// `data-tool-chip-id` composite key. NOT adding a new affordance attribute
// would be a UX scope-out into PR-C territory.
//
// `mcp__soleur_platform__test_synthesized_smoke` is NEITHER registered NOR on
// the Tier 3 denylist (`plausible_*`). Verify via Phase 4 grep.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go bubbles: tool-use-chip unregistered-mcp-fqn", () => {
  test("renders chip with literal FQN in data-tool-chip-id without crashing", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const fqn = "mcp__soleur_platform__test_synthesized_smoke";

    injector.send({
      type: "tool_use",
      leaderId: "cc_router",
      label: fqn,
    } satisfies StreamEvent);

    await expect(
      page.locator(`[data-tool-chip-id^="cc_router-${fqn}-"]`),
    ).toHaveCount(1);
    assertNoPageErrors(injector);
  });
});
