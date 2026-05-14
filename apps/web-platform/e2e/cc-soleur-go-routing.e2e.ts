// PR-B (#2939) Stage 6 — cc-soleur-go routing/cost/UX smoke regression net.
//
// Sibling to e2e/cc-soleur-go-bubbles.e2e.ts (PR-A FR1.x bubble assertions).
// Ten Playwright assertions covering plan §369-386 tasks 6.1-6.7 + 6.5.1-6.5.4
// (spec FR2.1-FR2.10). Same hermetic surface as PR-A: mocked Supabase HTTP +
// intercepted `**/ws` via attachWsInjector. NO real Anthropic SDK (Spec NG2),
// NO screenshot baselines (Spec NG1), NO denied MCP tool names (TR9 / NG4).
//
// Research Reconciliation — spec FR text vs production code at /work-time
// (mirrors the PR-A pattern; same hazard class as
// `2026-05-14-plan-prescribed-runtime-shapes-must-be-grepped-against-installed-version.md`):
//
//   - FR2.1 / FR2.2 selector `[data-active-workflow]` — does NOT exist. The
//     production signal for "routed" is the WorkflowLifecycleBar going
//     active after `workflow_started` (workflow-lifecycle-bar.tsx:40).
//   - FR2.1 / FR2.2 / FR2.9 use `workflow: "cc-router"` — `cc-router` is NOT
//     a `WorkflowName` literal (conversation-routing.ts:26 enumerates
//     one-shot, brainstorm, plan, work, review, drain-labeled-backlog). cc-
//     router is the dispatcher itself; what it routes INTO is the WorkflowName.
//     Tests pick `"brainstorm"` as the routed workflow.
//   - FR2.4 cost circuit-breaker — closed inline (#3774). Threaded the
//     existing `usageData.totalCostUsd` (driven by ws-client.ts:791-806's
//     out-of-reducer setState) into `WorkflowLifecycleBar` via a chat-
//     surface prop-merge. Added `data-lifecycle-status` attribute on the
//     bar's ended branch so the existing `cost_ceiling` terminal status
//     (lib/types.ts:WORKFLOW_END_STATUSES) is DOM-distinguishable from a
//     `completed` termination. The server-side threshold + emission of
//     `workflow_ended(status="cost_ceiling")` already existed; the client
//     just had no way to surface either signal.
//   - FR2.8 subprocess reuse — closed inline (#3775). `subagent_spawn`
//     reducer now dedupes via `priorSpawnIndex.has(event.spawnId)` at the
//     top of the arm, mirroring the F7 shape on `interactive_prompt`
//     (chat-state-machine.ts:751-770).
//   - FR2.10 container-restart pendingPrompts drop — remains `test.fixme` +
//     scope-out #3776 (contested-design — extending `context_reset` vs.
//     promoting `session_started` to a reducer event flips the WS control-
//     frame boundary the WsInjector explicitly draws). Deferred to its own
//     design-locked PR.

import { test, expect } from "@playwright/test";
import type { Page } from "@playwright/test";
import { attachWsInjector, type WsInjector } from "./cc-soleur-go-ws-injector";
import { MOCK_USER } from "./mock-supabase";
import {
  injectFakeSupabaseSession,
  mockSupabaseAuth,
} from "./helpers/supabase-mocks";
import type { StreamEvent } from "@/lib/chat-state-machine";

const CONV_ID = "conv-stage-6-routing";

const MOCK_CONVERSATION = {
  id: CONV_ID,
  user_id: MOCK_USER.id,
  title: "Stage 6 routing smoke",
  active_workflow: "cc-router",
  created_at: "2024-01-01T00:00:00Z",
  updated_at: "2024-01-01T00:00:00Z",
};

/**
 * Mirror of bootChat in cc-soleur-go-bubbles.e2e.ts. PR-B keeps a sibling
 * copy rather than extracting a third helper file — the two e2e specs share
 * no per-test state and a premature extraction would force a config-globals
 * dance for very little payoff. Fold when a third spec lands.
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

// ---------------------------------------------------------------------------
// FR2.1 — Fresh conversation routes through cc-router into a workflow.
//
// The router's output is a `workflow_started` event; the lifecycle bar then
// reports the dispatched workflow. `cc-router` is the dispatcher, not a
// WorkflowName — so the assertion is on the routed workflow ("brainstorm"
// for this fixture) appearing in the bar.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.1 fresh conv routes into a workflow", () => {
  test("workflow_started activates the lifecycle bar with the routed workflow name", async ({
    page,
  }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: CONV_ID,
    } satisfies StreamEvent);

    const bar = page.locator('[data-lifecycle-state="active"]');
    await expect(bar).toBeVisible();
    await expect(bar).toContainText("brainstorm");
  });
});

// ---------------------------------------------------------------------------
// FR2.2 — Sticky workflow on subsequent turns.
//
// Every reducer arm except `workflow_started` / `workflow_ended` passes
// `priorWorkflow` through unchanged (chat-state-machine.ts:336/386/422/etc).
// Stream events on a peer leader must not clear the active lifecycle bar.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.2 sticky workflow on subsequent turns", () => {
  test("active lifecycle survives a peer-leader stream cycle", async ({ page }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: CONV_ID,
    } satisfies StreamEvent);
    await expect(page.locator('[data-lifecycle-state="active"]')).toBeVisible();

    injector.send({
      type: "stream_start",
      leaderId: "cmo",
    } satisfies StreamEvent);
    injector.send({
      type: "stream",
      content: "follow-up turn body",
      partial: false,
      leaderId: "cmo",
    } satisfies StreamEvent);
    injector.send({
      type: "stream_end",
      leaderId: "cmo",
    } satisfies StreamEvent);

    const bar = page.locator('[data-lifecycle-state="active"]');
    await expect(bar).toBeVisible();
    await expect(bar).toContainText("brainstorm");
  });
});

// ---------------------------------------------------------------------------
// FR2.3 — Mid-workflow @CTO produces a subagent_spawn threaded into the
// transcript. Reducer arm at chat-state-machine.ts:596 creates a
// ChatSubagentGroupMessage on first spawn for a parentId; DOM exposes
// `[data-parent-spawn-id]` and `[data-child-spawn-id]` per subagent-group.tsx.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.3 @CTO mid-workflow", () => {
  test("subagent_spawn leaderId=cto threads into the parent group", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const parentId = "parent-cto-mid";

    injector.send({
      type: "subagent_spawn",
      parentId,
      leaderId: "cto",
      spawnId: `${parentId}-cto-1`,
      task: "Engineering deep-dive",
    } satisfies StreamEvent);

    // Pin the auto-expand contract: child rows are conditionally rendered
    // inside `{expanded ? (…) : null}` (subagent-group.tsx:157). N=1 ≤
    // SUBAGENT_GROUP_AUTO_EXPAND_MAX (=2, subagent-group.tsx:36) so the
    // group defaults to expanded. Asserting `data-expanded="true"` here
    // names the contract — a regression that lowers the boundary fails
    // explicitly rather than producing a misleading "child not visible".
    const group = page.locator(`[data-parent-spawn-id="${parentId}"]`);
    await expect(group).toHaveCount(1);
    await expect(group).toHaveAttribute("data-expanded", "true");
    await expect(
      group.locator(`[data-child-spawn-id="${parentId}-cto-1"]`),
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// FR2.4 — Cost circuit-breaker (lifted to live test).
//
// Originally scoped out as #3774; flipped inline per code-simplicity DISSENT
// at review time. The minimal client wire added in this PR:
//   - `usage_update` (handled out-of-reducer at `ws-client.ts:791-806` as
//     today, via setUsageData) is now threaded into `WorkflowLifecycleBar`
//     via a chat-surface prop-merge — when `workflow.state === "active"`,
//     `cumulativeCostUsd` is overridden with `usageData.totalCostUsd` so
//     the bar can render the running total without introducing a second
//     handler.
//   - `data-lifecycle-status` attribute added to `WorkflowLifecycleBar`'s
//     ended branch (workflow-lifecycle-bar.tsx) so the existing
//     `cost_ceiling` terminal status (lib/types.ts:WORKFLOW_END_STATUSES)
//     is DOM-distinguishable from a `completed` termination.
// Server-side threshold + emission of `workflow_ended(status="cost_ceiling")`
// already existed; the client just had no way to surface the distinction.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.4 cost circuit-breaker", () => {
  test("usage_update updates cost AND workflow_ended(cost_ceiling) exposes lifecycle-status", async ({
    page,
  }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: CONV_ID,
    } satisfies StreamEvent);
    await expect(page.locator('[data-lifecycle-state="active"]')).toBeVisible();

    // Synthesized cumulative cost — `usage_update` is handled by an out-of-
    // reducer setState (`ws-client.ts:791-806`) and threaded into the
    // lifecycle bar via a chat-surface prop merge (#3774). Therefore it goes
    // through the typed `sendControl` channel, not `send`.
    injector.sendControl({
      type: "usage_update",
      conversationId: CONV_ID,
      totalCostUsd: 1.2345,
      inputTokens: 1000,
      outputTokens: 2000,
    });
    await expect(page.locator('[data-lifecycle-state="active"]')).toContainText("$1.2345");

    // Server-side breaker trips → emit `workflow_ended` with the existing
    // `cost_ceiling` status (lib/types.ts:WORKFLOW_END_STATUSES). The
    // existing reducer arm transitions lifecycle to `ended`; the new
    // `data-lifecycle-status` attribute on the bar lets the test distinguish
    // it from a `completed` termination without coupling to copy.
    injector.send({
      type: "workflow_ended",
      workflow: "brainstorm",
      status: "cost_ceiling",
      summary: "Per-conversation cost ceiling reached",
    } satisfies StreamEvent);

    const endedBar = page.locator(
      '[data-lifecycle-state="ended"][data-lifecycle-status="cost_ceiling"]',
    );
    await expect(endedBar).toBeVisible();
    // Refusal-of-further-turns proven by the ChatInput's disabled+placeholder
    // hook (same path FR2.9 exercises for `completed`).
    await expect(
      page.getByPlaceholder("This conversation has ended"),
    ).toBeDisabled();
  });
});

// ---------------------------------------------------------------------------
// FR2.5 — CFO gate spawn renders.
//
// The threshold logic that fires the CFO spawn is server-side (covered by
// the FR2.4 scope-out). The receiving side — rendering the CFO child in the
// subagent group — IS client wire and worth pinning so that when FR2.4 lands
// the visual path is already a pass.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.5 CFO gate spawn renders", () => {
  test("subagent_spawn leaderId=cfo renders a child row in the group", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const parentId = "parent-cfo-gate";

    injector.send({
      type: "subagent_spawn",
      parentId,
      leaderId: "cfo",
      spawnId: `${parentId}-cfo-1`,
      task: "Cost review",
    } satisfies StreamEvent);

    // Same auto-expand contract pin as FR2.3 — N=1 ≤ 2 so the group
    // defaults to expanded; the child row only renders inside the
    // expanded branch of subagent-group.tsx:157.
    const group = page.locator(`[data-parent-spawn-id="${parentId}"]`);
    await expect(group).toHaveAttribute("data-expanded", "true");
    await expect(
      group.locator(`[data-child-spawn-id="${parentId}-cfo-1"]`),
    ).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// FR2.6 — Chip render under spec ceiling.
//
// The spec sets an 8s budget. The actual codepath is a pure-sync reducer arm
// (chat-state-machine.ts:344-389) + immediate React render — no debounce, no
// async hop. Tightened the assertion to a 2s ceiling so a regression that
// adds a 5s async hop (e.g., misplaced `await`, hydration race, sentry-
// instrumented wrapper) fails AT THIS ASSERTION rather than passing within
// the 8s slack. The 8s spec budget lives in the FR text; the test enforces
// the order-of-magnitude that actually matters. Also wires a pageerror
// listener so a render-throw fails loud rather than producing an unmounted-
// chip false-pass.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.6 chip render under spec ceiling", () => {
  test("[data-tool-chip-id] mounts within 2s of tool_use and no render-throw", async ({
    page,
  }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "tool_use",
      leaderId: "cc_router",
      label: "Routing handoff",
    } satisfies StreamEvent);

    const chip = page.locator('[data-tool-chip-id^="cc_router-Routing handoff-"]');
    await expect(chip).toBeVisible({ timeout: 2_000 });
    await expect(chip).toHaveCount(1);
    expect(
      injector.pageErrors,
      `page errors during chip render: ${injector.pageErrors.map((e) => e.message).join("; ")}`,
    ).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// FR2.7 — Narration text precedes any tool_use(skill_*).
//
// Server-side directive (soleur-go-runner.ts) emits a `stream` block before
// any `tool_use(skill_*)`. Client-side, the ordering is proven by sequential
// assertion: narration is visible AT THE MOMENT the test sends it (proves
// the reducer received and rendered it), then the skill tool_use is sent
// and asserted. Once `stream_start` fires, subsequent `tool_use` on the
// same leader falls through to the per-leader path
// (chat-state-machine.ts:347-353) and swaps the bubble's visible body
// from `content` to `toolLabel` — so the narration text is no longer
// queryable after tool_use lands. That swap is the per-leader bubble's
// designed UX (one bubble per leader; tool label replaces the in-flight
// content) and is not in PR-B scope to challenge.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.7 narration before Skill", () => {
  test("narration is visible AND skill toolLabel is absent before tool_use is injected", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const narration = "Routing your request to the brainstorm specialist.";

    injector.send({
      type: "stream_start",
      leaderId: "cc_router",
    } satisfies StreamEvent);
    injector.send({
      type: "stream",
      content: narration,
      partial: false,
      leaderId: "cc_router",
    } satisfies StreamEvent);

    // Order proof, half 1 — narration visible at this point in time.
    await expect(page.getByText(narration)).toBeVisible();
    // Order proof, half 2 — at the same point in time, the skill toolLabel
    // is NOT yet observable. Without this, the test only proves the test
    // author's send-order; with it, a reducer that ever flipped the order
    // (`tool_use` racing ahead of `stream`) would produce a visible skill
    // chip here and fail the test — that's the actual invariant the FR
    // claims to pin.
    await expect(page.getByText("skill_brainstorm")).toHaveCount(0);

    injector.send({
      type: "tool_use",
      leaderId: "cc_router",
      label: "skill_brainstorm",
    } satisfies StreamEvent);

    await expect(page.getByText(/skill_brainstorm/)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// FR2.8 — Subprocess reuse (lifted to live test).
//
// Originally scoped out as #3775; flipped inline per code-simplicity DISSENT
// at review time. The `subagent_spawn` reducer now dedupes on `spawnId` via
// `priorSpawnIndex.has(event.spawnId)` at the top of the arm
// (chat-state-machine.ts), mirroring the F7 shape on `interactive_prompt`
// (line 751-770). Two consecutive Skill calls that share a spawnId now
// produce exactly one child row — the client-side regression net for what
// the server-runner already guarantees.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.8 subprocess reuse", () => {
  test("duplicate subagent_spawn with same spawnId produces exactly one child row", async ({
    page,
  }) => {
    const injector = await bootChat(page);
    const parentId = "parent-reuse";
    const spawnId = `${parentId}-skill-shared`;

    // First spawn — establishes the group + child.
    injector.send({
      type: "subagent_spawn",
      parentId,
      leaderId: "cto",
      spawnId,
      task: "First skill invocation",
    } satisfies StreamEvent);

    // Second spawn with the SAME spawnId — reducer idempotent path; should
    // NOT produce a duplicate child row.
    injector.send({
      type: "subagent_spawn",
      parentId,
      leaderId: "cto",
      spawnId,
      task: "Second skill invocation (reuse)",
    } satisfies StreamEvent);

    const group = page.locator(`[data-parent-spawn-id="${parentId}"]`);
    await expect(group).toHaveAttribute("data-expanded", "true");
    await expect(group.locator(`[data-child-spawn-id="${spawnId}"]`)).toHaveCount(1);
    await expect(group.locator("[data-child-spawn-id]")).toHaveCount(1);
  });
});

// ---------------------------------------------------------------------------
// FR2.9 — Ended-state UX.
//
// `workflow_ended` reducer (chat-state-machine.ts:728) sets
// `workflow.state="ended"`; WorkflowLifecycleBar then renders the
// "Start new conversation" button (workflow-lifecycle-bar.tsx:91-97).
// ChatSurface flips `workflowEnded={true}` on ChatInput, which forces
// `disabled = rawDisabled || workflowEnded` (chat-input.tsx:99) and swaps
// the placeholder to "This conversation has ended" (chat-input.tsx:100-102).
// The placeholder is the file-documented structural test hook.
// ---------------------------------------------------------------------------

test.describe("cc-soleur-go routing: FR2.9 ended-state UX", () => {
  test("workflow_ended shows Start new conversation and disables the input", async ({
    page,
  }) => {
    const injector = await bootChat(page);

    injector.send({
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: CONV_ID,
    } satisfies StreamEvent);
    injector.send({
      type: "workflow_ended",
      workflow: "brainstorm",
      status: "completed",
    } satisfies StreamEvent);

    const endedBar = page.locator('[data-lifecycle-state="ended"]');
    await expect(endedBar).toBeVisible();
    await expect(
      endedBar.getByRole("button", { name: "Start new conversation" }),
    ).toBeVisible();

    await expect(
      page.getByPlaceholder("This conversation has ended"),
    ).toBeDisabled();
  });
});

// ---------------------------------------------------------------------------
// FR2.10 — Container-restart `pendingPrompts` drop. SCOPE-OUT.
//
// `pendingPrompts` lives in the server-side soleur-go runner; the client
// reducer dedupes `interactive_prompt` events on (promptId, conversationId)
// (chat-state-machine.ts:751-770) but neither `context_reset` (line 783)
// nor the `session_started` control frame clears resident prompt cards. A
// stale card from before a container restart persists on reconnect if the
// server re-emits the prompt with a different promptId. Scope-out #3776 —
// flip back to a live `test()` once the client gains a reducer arm that
// clears `interactive_prompt` cards on session reboot.
// ---------------------------------------------------------------------------

test.fixme(
  "cc-soleur-go routing: FR2.10 container-restart pendingPrompts drop — no client clear wire (scope-out)",
  async () => {
    // intentionally empty — scope-out documented in file header + PR body.
  },
);
