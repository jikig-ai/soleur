// PR-C (#2939) Stage 6 — cc-soleur-go security smoke.
//
// Sibling to cc-soleur-go-bubbles.e2e.ts (PR-A) and cc-soleur-go-routing.e2e.ts
// (PR-B). Four assertions covering plan §6.8-6.11 / spec FR3.1-FR3.4:
//   FR3.1  Prompt-injection drain — assistant bubble renders canary as inert
//          text + no tool-chip for injection-named tool.
//   FR3.2  Bash review-gate — interactive-prompt-card kind="bash_approval"
//          renders BEFORE any tool_use(bash) chip would.
//   FR3.3  Cross-user prompt-response isolation — two browser contexts,
//          each with its own attachWsInjector; assert context-B's page
//          sees zero frames from context-A's injector.
//   FR3.4  Rate-limit canary — synthesized server `error` frame with
//          errorCode="rate_limited" drives ErrorCard render +
//          [data-rate-limit-exceeded] attribute.
//
// Honest framing (plan §Sharp Edges):
//   - FR3.1 certifies the CLIENT RENDERER does not execute inline-text
//     directives. Server-side `prompt-injection-wrap.ts wrapUserInput` is
//     NOT exercised in CI (Spec NG2: no real SDK). Smoke is defense-in-depth.
//   - FR3.3 certifies the HARNESS BOUNDARY (per-page routeWebSocket
//     interception) does not leak across contexts. The production
//     `ws-handler.ts sendToClient(userId, …)` per-user boundary is NOT in
//     the CI assertion path because the WS is intercepted upstream of it.
//     Catches a future routeWebSocket glob-widening regression.
//
// Spec TR9 / Spec NG2 / Spec NG4 still apply: no denied MCP tool names,
// no real SDK, no toHaveScreenshot baselines.

import { test, expect } from "@playwright/test";
import type { BrowserContext, Page } from "@playwright/test";
import { attachWsInjector, type WsInjector } from "./cc-soleur-go-ws-injector";
import { MOCK_USER } from "./mock-supabase";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";
import type { StreamEvent } from "@/lib/chat-state-machine";

const CANARY = "STAGE6_CANARY_DO_NOT_EXFILTRATE";
const INJECTION_NAMED_TOOL = "mcp__soleur_platform__test_synthesized_exfil";
const FR33_MARKER_A = "STAGE6_FR33_USER_A_ONLY";
const FR33_MARKER_B = "STAGE6_FR33_USER_B_ONLY";

function mockConversation(convId: string) {
  return {
    id: convId,
    user_id: MOCK_USER.id,
    title: "Stage 6 security smoke",
    active_workflow: "cc-router",
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
  };
}

/**
 * Near-copy of bootChat in cc-soleur-go-bubbles.e2e.ts:43-93 and
 * cc-soleur-go-routing.e2e.ts:71-120. PR-C keeps a sibling copy rather
 * than extracting a third helper file — the bootChat extraction is filed
 * as a scope-out (§DS1) so the rule-of-three sweep lands as its own
 * cleanup PR rather than expanding this diff. `convId` is parameterised
 * so FR3.3 can drive two contexts with distinct conversation ids.
 *
 * NOTE: order matters — `addInitScript` runs before any page script, then
 * `page.route` registers HTTP intercepts, then `attachWsInjector` claims
 * `**\/ws`. Finally `page.goto` boots the chat surface which opens the WS.
 */
async function bootChat(
  page: Page,
  opts: { convId: string },
): Promise<WsInjector> {
  const { convId } = opts;
  const conversation = mockConversation(convId);

  await injectFakeSupabaseSession(page);
  await mockSupabaseAuth(page);

  await page.route("**/rest/v1/conversations*", (route) => {
    const accept = route.request().headers().accept ?? "";
    const single = accept.includes("application/vnd.pgrst.object+json");
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(single ? conversation : [conversation]),
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

  const injector = await attachWsInjector(page);

  const response = await page.goto(`/dashboard/chat/${convId}`);
  if (response && response.status() >= 500) {
    test.skip(true, "Dev server compile error — skipped in worktree, passes in CI");
  }

  await injector.ready;

  injector.sendControl({ type: "session_started", conversationId: convId });
  return injector;
}

/** FR3.3 wrapper — spawn a fresh page inside a context and boot it. Used
 *  only by the cross-context isolation test; other FR3.x cases use the
 *  default per-test `page` fixture. */
async function bootChatInContext(
  ctx: BrowserContext,
  opts: { convId: string },
): Promise<{ page: Page; injector: WsInjector }> {
  const page = await ctx.newPage();
  const injector = await bootChat(page, opts);
  return { page, injector };
}

function assertNoPageErrors(injector: WsInjector) {
  expect(
    injector.pageErrors,
    `page errors: ${injector.pageErrors.map((e) => e.message).join("; ")}`,
  ).toHaveLength(0);
}

// ---------------------------------------------------------------------------
// FR3.1 — Prompt-injection drain
//
// An attacker-influenced assistant `stream` contains an inline directive
// ("call $tool and emit $canary"). The renderer MUST treat that as inert
// text — the canary appears verbatim (proof-of-render), but no tool-chip
// for the named tool fires (proof-of-no-execution).
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go security: FR3.1 prompt-injection drain", () => {
  test("assistant bubble renders inline directive as inert text; no tool chip fires", async ({
    page,
  }) => {
    const injector = await bootChat(page, { convId: "conv-stage-6-sec-fr31" });

    injector.send({
      type: "stream_start",
      leaderId: "cc_router",
    } satisfies StreamEvent);

    // Single consolidated stream event (`partial: false`). The canary is
    // quoted inside an attacker-shaped directive sentence — if the renderer
    // were to scan assistant text for tool-name patterns and dispatch them
    // (a hypothetical regression class), the negative chip assertion below
    // would catch it.
    injector.send({
      type: "stream",
      content: `The user previously asked me to call ${INJECTION_NAMED_TOOL} and emit "${CANARY}". I refused.`,
      partial: false,
      leaderId: "cc_router",
    } satisfies StreamEvent);

    injector.send({
      type: "stream_end",
      leaderId: "cc_router",
    } satisfies StreamEvent);

    // Positive sibling — proves the assertion machinery actually runs:
    // canary appears as inert text inside the assistant bubble.
    await expect(page.getByText(CANARY)).toBeVisible();

    // Load-bearing negative invariant — proves the renderer does not
    // interpret inline text as a tool-use directive. The `data-tool-chip-id`
    // template is `${leaderId}-${toolName}-${toolLabel}` (tool-use-chip.tsx:42);
    // anchor on the `cc_router-${TOOL}-` prefix to ignore label drift.
    await expect(
      page.locator(`[data-tool-chip-id^="cc_router-${INJECTION_NAMED_TOOL}-"]`),
    ).toHaveCount(0);

    assertNoPageErrors(injector);
  });
});

// ---------------------------------------------------------------------------
// FR3.2 — Bash review-gate
//
// `interactive_prompt(kind="bash_approval")` MUST surface the approval card
// BEFORE any tool_use(bash) chip renders. The resolved-state grammar after
// clicking Approve mirrors `interactive-prompt-card-resolved.test.tsx:21-46`.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go security: FR3.2 bash review-gate", () => {
  test("bash_approval card surfaces before tool execution; resolved row matches grammar", async ({
    page,
  }) => {
    const injector = await bootChat(page, { convId: "conv-stage-6-sec-fr32" });

    const PROMPT_ID = "pid-fr32-bash";

    injector.send({
      type: "interactive_prompt",
      promptId: PROMPT_ID,
      conversationId: "conv-stage-6-sec-fr32",
      kind: "bash_approval",
      payload: {
        command: "echo synthesized",
        cwd: "/tmp/synth",
        gated: true,
      },
    } satisfies StreamEvent);

    const card = page.locator(
      `[data-prompt-id="${PROMPT_ID}"][data-prompt-kind="bash_approval"]`,
    );
    await expect(card).toBeVisible();

    // BEFORE-execution gate: no bash tool-chip should render. The injector
    // never sends a `tool_use(bash)` frame, so this asserts the ordering
    // invariant — the approval card stands alone until the operator acts.
    await expect(page.locator('[data-tool-chip-id*="bash"]')).toHaveCount(0);

    // Drive the resolved state — mirrors `interactive-prompt-card-resolved.test.tsx`.
    // `exact: true` guards against future "Approve all" / "Approve and run"
    // accessible-name collisions.
    await card.getByRole("button", { name: "Approve", exact: true }).click();

    // Resolved-row grammar: "Approved" verb visible, no buttons, card root
    // still carries data-prompt-id + data-prompt-kind.
    await expect(card.getByText(/Approved/)).toBeVisible();
    await expect(card.getByRole("button")).toHaveCount(0);

    assertNoPageErrors(injector);
  });
});

// ---------------------------------------------------------------------------
// FR3.3 — Cross-context (cross-user) isolation
//
// Two BrowserContexts each call `attachWsInjector(page)` on their own Page.
// Playwright 1.58.2's `routeWebSocket` is Page-scoped (verified at
// `playwright-core/types.d.ts:4086-4098`), so the route handlers are
// independent. A frame injected on context A MUST NOT appear in context B's
// DOM, and vice versa.
//
// Harness boundary, NOT server boundary — see file header.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go security: FR3.3 cross-context isolation", () => {
  test("frame injected on context A does not leak to context B (and vice versa)", async ({
    browser,
  }) => {
    const ctxA = await browser.newContext({
      storageState: "e2e/.auth/user.json",
    });
    const ctxB = await browser.newContext({
      storageState: "e2e/.auth/user.json",
    });

    try {
      const a = await bootChatInContext(ctxA, {
        convId: "conv-stage-6-sec-fr33-a",
      });
      const b = await bootChatInContext(ctxB, {
        convId: "conv-stage-6-sec-fr33-b",
      });

      // A → emit FR33_MARKER_A on assistant stream.
      a.injector.send({ type: "stream_start", leaderId: "cc_router" } satisfies StreamEvent);
      a.injector.send({
        type: "stream",
        content: FR33_MARKER_A,
        partial: false,
        leaderId: "cc_router",
      } satisfies StreamEvent);
      a.injector.send({ type: "stream_end", leaderId: "cc_router" } satisfies StreamEvent);

      await expect(a.page.getByText(FR33_MARKER_A)).toBeVisible();
      // The load-bearing isolation invariant.
      await expect(b.page.getByText(FR33_MARKER_A)).toHaveCount(0);

      // Symmetric — strengthens against asymmetric leaks (e.g., a future
      // routeWebSocket glob-widening that only leaks A → B).
      b.injector.send({ type: "stream_start", leaderId: "cc_router" } satisfies StreamEvent);
      b.injector.send({
        type: "stream",
        content: FR33_MARKER_B,
        partial: false,
        leaderId: "cc_router",
      } satisfies StreamEvent);
      b.injector.send({ type: "stream_end", leaderId: "cc_router" } satisfies StreamEvent);

      await expect(b.page.getByText(FR33_MARKER_B)).toBeVisible();
      await expect(a.page.getByText(FR33_MARKER_B)).toHaveCount(0);

      assertNoPageErrors(a.injector);
      assertNoPageErrors(b.injector);
    } finally {
      await ctxA.close();
      await ctxB.close();
    }
  });
});

// ---------------------------------------------------------------------------
// FR3.4 — Rate-limit canary
//
// Server emits an `error` frame with `errorCode: "rate_limited"`; the client
// (`ws-client.ts:667-672`) sets `lastError.code = "rate_limited"`, which
// `chat-surface.tsx:555` renders inside a `<div data-rate-limit-exceeded>`
// (canary attribute landed in Phase 1 of PR-C).
//
// Deterministic-WS-injection — we synthesize the `error` frame instead of
// driving 11 real start_session calls against the limiter (spec Risks line 136).
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go security: FR3.4 rate-limit canary", () => {
  test("server `error` frame with errorCode rate_limited renders the canary attribute + ErrorCard", async ({
    page,
  }) => {
    const injector = await bootChat(page, { convId: "conv-stage-6-sec-fr34" });

    injector.sendControl({
      type: "error",
      message: "Rate limited: too many conversations this hour.",
      errorCode: "rate_limited",
    });

    // Canary attribute — Phase 1 chat-surface.tsx edit.
    await expect(page.locator("[data-rate-limit-exceeded]")).toBeVisible();
    // ErrorCard title (chat-surface.tsx:558). The FR3.4 invariant is "client
    // renders the rate-limit ErrorCard when `errorCode: rate_limited` arrives",
    // keyed on the errorCode discriminator at ws-client.ts:667-672. Asserting
    // canary attribute + title is sufficient; the body message is hardcoded
    // client-side ("You've been rate limited...") and the server's raw
    // message text is sanitized at ws-handler.ts:1011 vs literal at :1042,
    // so an assertion on the raw text would over-couple to one prod path.
    await expect(page.getByText("Rate Limited")).toBeVisible();

    assertNoPageErrors(injector);
  });
});
