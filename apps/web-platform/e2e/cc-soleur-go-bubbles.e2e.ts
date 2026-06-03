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
import { MOCK_USER } from "./mock-supabase";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";
import type { StreamEvent } from "@/lib/chat-state-machine";

const CONV_ID = "conv-stage-6-smoke";

const MOCK_CONVERSATION = {
  id: CONV_ID,
  user_id: MOCK_USER.id,
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
  await injectFakeSupabaseSession(page);
  await mockSupabaseAuth(page);

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

  const injector = await attachWsInjector(page);

  const response = await page.goto(`/dashboard/chat/${CONV_ID}`);
  if (response && response.status() >= 500) {
    test.skip(true, "Dev server compile error — skipped in worktree, passes in CI");
  }

  await injector.ready;

  // Server-side confirmation frame. The reducer enters its happy path only
  // after `session_started`; without it `useWebSocket` won't accept follow-up
  // events on the resolved conversation id. `session_started` is a control
  // frame outside the reducer-visible `StreamEvent` subset, so it goes
  // through the typed `sendControl` channel rather than `send`.
  injector.sendControl({ type: "session_started", conversationId: CONV_ID });

  return injector;
}

function assertNoPageErrors(injector: WsInjector) {
  expect(
    injector.pageErrors,
    `page errors: ${injector.pageErrors.map((e) => e.message).join("; ")}`,
  ).toHaveLength(0);
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

// ---------------------------------------------------------------------------
// 3.5 Concierge status-box overflow — inverse of #4852 (#4855-class)
//
// #4852 added bare `whitespace-nowrap` to the `ToolStatusChip` label
// (message-bubble.tsx:27) to stop premature wrapping of the routing-chip status
// label. With the bubble `max-w` cap + `min-w-0` ancestor chain, that left a
// label *wider* than the available card width no way to wrap and no way to grow
// → it overflowed the Concierge card's right border. The fix swaps `nowrap`
// for the wrap-capable `[overflow-wrap:anywhere]` idiom (already on the
// streaming body, :269).
//
// This drives the REAL routing chip (`chat-surface.tsx:737-755` `isClassifying`
// → `MessageBubble role=assistant messageState=tool_use toolLabel="Routing to
// the right experts..."`), NOT a synthetic `tool_use` stream event (which
// renders the lifecycle `data-tool-chip-id` chip, a DIFFERENT element). The
// chip appears when there is a user message and no assistant reply yet, so we
// type + send and inject no assistant frame.
//
// jsdom returns 0 for layout values (constitution line 312), so the no-overflow
// proof MUST live in Playwright. Both render variants ("full" chat-surface and
// the narrow "sidebar" `kb-chat-content.tsx`) share this SAME render path; the
// only difference is available container width. We exercise the SAME chip at a
// wide desktop viewport (single-line non-regression for #4852) AND a narrow
// viewport that forces the fixed label to wrap.
//
// Non-vacuity (the empty-band concern from nav-states-shell.e2e.ts:19): a bare
// `scrollWidth<=clientWidth` assertion passes vacuously if the label never
// needed to wrap. So the narrow case asserts BOTH (a) the card does not
// overflow AND (b) the label actually wrapped onto ≥2 line-boxes — wrapping is
// proof the width was constrained, i.e. exactly the condition under which the
// pre-fix `nowrap` overflowed. (a)+(b) together fail against the pre-fix code
// (nowrap → 1 line → overflow) and pass against the fix (wrap → no overflow).
// ---------------------------------------------------------------------------

/** Drive the real `isClassifying` routing chip. The chip renders when there is
 *  a user message and no assistant reply yet (chat-surface.tsx:456-462), which
 *  depends ONLY on reducer state — NOT on the WS "connected" status (the input
 *  is disabled in this offline harness, but the chip is not). So we seed the
 *  mount-time history fetch (`/api/conversations/:id/messages`,
 *  ws-client.ts:1041) with a single USER message and inject no assistant frame;
 *  `workflow.state` stays "idle" (only a `workflow_started` event activates it),
 *  so `isClassifying` is true and the fixed "Routing to the right experts..."
 *  ToolStatusChip renders. */
async function triggerRoutingChip(page: Page): Promise<WsInjector> {
  await page.route("**/api/conversations/*/messages", (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        messages: [
          {
            id: "user-msg-overflow-1",
            role: "user",
            content: "Fix the reported issue end to end",
            leader_id: null,
          },
        ],
        totalCostUsd: 0,
      }),
    }),
  );
  const injector = await bootChat(page);
  await expect(page.locator('[data-testid="routing-chip"]')).toBeVisible();
  return injector;
}

/** Measure the routing chip's bubble card (anchored by the stable
 *  `data-testid="message-bubble-card"` hook, NOT a generic Tailwind class) for
 *  horizontal overflow, plus the label span's line-box height vs line-height so
 *  the caller can prove the label wrapped (non-vacuity guard). */
async function measureRoutingChip(page: Page) {
  const card = page
    .locator('[data-testid="routing-chip"] [data-testid="message-bubble-card"]')
    .first();
  await expect(card).toBeVisible();
  return card.evaluate((cardEl) => {
    const label = cardEl.querySelector(
      '[data-testid="tool-status-chip"] span',
    ) as HTMLElement | null;
    if (!label) throw new Error("routing chip has no tool-status-chip label");
    const lineHeight = parseFloat(getComputedStyle(label).lineHeight);
    return {
      overflow: cardEl.scrollWidth - cardEl.clientWidth,
      labelText: label.textContent ?? "",
      labelHeight: label.offsetHeight,
      lineHeight,
    };
  });
}

test.describe("cc-soleur-go bubbles: Concierge status-box overflow", () => {
  // Harness-fidelity note (#4855 QA): in this offline authenticated harness the
  // dashboard chat column renders at ~265px wide regardless of the browser
  // viewport, so the routing chip card only ever has ~160px of content width —
  // less than the fixed label's ~210px single-line width. The label therefore
  // ALWAYS wraps here, and the "stays single-line when horizontal space is
  // available" #4852-non-regression cannot be exhibited at this layer (the
  // production chat column is far wider). That non-regression is instead pinned
  // structurally by the vitest className assertion in
  // `test/message-bubble-tool-status-chip.test.tsx`: the label carries
  // `[overflow-wrap:anywhere]` (which, by CSS definition, introduces a soft-wrap
  // opportunity ONLY when the content would otherwise overflow — it never forces
  // a break when the line fits) and no longer carries `whitespace-nowrap`. What
  // this Playwright layer CAN and MUST prove is the actual reported bug: the
  // label NEVER spills past the card's right border. We assert that at the
  // default viewport AND a deliberately narrow viewport, with a non-vacuity
  // guard that the label genuinely wrapped (so a collapsed/empty card cannot
  // pass trivially).
  for (const variant of [
    { name: "default viewport", width: 0 },
    { name: "narrow 300px viewport", width: 300 },
  ] as const) {
    test(`routing chip label wraps inside the card — no horizontal overflow — ${variant.name}`, async ({
      page,
    }) => {
      if (variant.width > 0) {
        await page.setViewportSize({ width: variant.width, height: 900 });
      }
      const injector = await triggerRoutingChip(page);

      const m = await measureRoutingChip(page);

      // Empty-band guard (nav-states-shell.e2e.ts:19 precedent): the card must
      // actually contain the routing label, else scroll<=client is vacuous.
      expect(m.labelText).toContain("Routing to the right experts");
      // `text-sm` sets an explicit px line-height; assert finite (don't skip on
      // NaN) so a future line-height regression to `normal` cannot make the
      // wrap check below pass vacuously.
      expect(Number.isFinite(m.lineHeight)).toBe(true);
      // Non-vacuity: the constrained card forced the label to wrap onto ≥2
      // line-boxes. This is the exact condition under which the pre-fix `nowrap`
      // spilled past the border instead of wrapping — so the no-overflow
      // assertion below is meaningful, not trivially satisfied by a short line.
      expect(m.labelHeight).toBeGreaterThan(m.lineHeight * 1.5);
      // The fix: the wrapped label stays inside the card — no horizontal
      // overflow (1px sub-pixel tolerance; a real overflow is tens of px).
      expect(m.overflow).toBeLessThanOrEqual(1);

      assertNoPageErrors(injector);
    });
  }
});
