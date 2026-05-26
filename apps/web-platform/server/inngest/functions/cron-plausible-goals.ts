// TR9 Phase-2 — Monthly idempotent provisioning of Plausible Analytics
// conversion goals. Lists existing goals, compares against a canonical
// set, creates any missing goals.
//
// Migrated from .github/workflows/scheduled-plausible-goals.yml (deleted
// in the same PR per TR9 I-13 hygiene). Pure TS port — no agent spawn,
// no ephemeral workspace. All IO via Plausible REST API (fetch).
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — No long-running subprocess; fetch timeout bounds wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-plausible-goals";

const PLAUSIBLE_BASE_URL = "https://plausible.io";

// Fetch timeout for individual Plausible API calls (10 seconds).
const PLAUSIBLE_FETCH_TIMEOUT_MS = 10_000;

// =============================================================================
// Canonical goals — ported from scripts/provision-plausible-goals.sh
// =============================================================================

export interface PlausibleGoal {
  goal_type: "event" | "page";
  /** event_name for event goals, page_path for page goals */
  value: string;
}

export const CANONICAL_GOALS: readonly PlausibleGoal[] = [
  { goal_type: "event", value: "Newsletter Signup" },
  { goal_type: "event", value: "Waitlist Signup" },
  { goal_type: "page", value: "/pages/getting-started.html" },
  { goal_type: "page", value: "/blog/*" },
  { goal_type: "event", value: "Outbound Link: Click" },
  // kb-chat-sidebar (#2345) — selection -> quoted-chat flow.
  { goal_type: "event", value: "kb.chat.opened" },
  { goal_type: "event", value: "kb.chat.selection_sent" },
  { goal_type: "event", value: "kb.chat.thread_resumed" },
] as const;

// =============================================================================
// Helpers — Plausible API
// =============================================================================

interface PlausibleApiGoal {
  id: number;
  display_name: string;
  goal_type: string;
  event_name?: string;
  page_path?: string;
}

async function plausibleRequest(
  method: "GET" | "PUT",
  endpoint: string,
  apiKey: string,
  body?: unknown,
): Promise<unknown> {
  const url = `${PLAUSIBLE_BASE_URL}${endpoint}`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${apiKey}`,
  };
  const init: RequestInit = {
    method,
    headers,
    signal: AbortSignal.timeout(PLAUSIBLE_FETCH_TIMEOUT_MS),
  };
  if (method === "PUT" && body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }

  const resp = await fetch(url, init);

  if (resp.status === 401 || resp.status === 402) {
    // Plan limitation — skip gracefully (matches shell script behaviour)
    return null;
  }

  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(
      `Plausible API error (HTTP ${resp.status}): ${text.slice(0, 200)}`,
    );
  }

  return resp.json();
}

async function listExistingGoals(
  apiKey: string,
  siteId: string,
): Promise<PlausibleApiGoal[]> {
  const result = await plausibleRequest(
    "GET",
    `/api/v1/sites/goals?site_id=${encodeURIComponent(siteId)}`,
    apiKey,
  );
  if (result === null) return []; // plan limitation
  const data = result as { goals?: PlausibleApiGoal[] };
  return data.goals ?? [];
}

function goalExists(
  existing: PlausibleApiGoal[],
  goal: PlausibleGoal,
): boolean {
  return existing.some((e) => {
    if (goal.goal_type === "event") {
      return e.goal_type === "event" && e.event_name === goal.value;
    }
    return e.goal_type === "page" && e.page_path === goal.value;
  });
}

async function provisionGoal(
  apiKey: string,
  siteId: string,
  goal: PlausibleGoal,
): Promise<void> {
  const body =
    goal.goal_type === "event"
      ? { site_id: siteId, goal_type: "event", event_name: goal.value }
      : { site_id: siteId, goal_type: "page", page_path: goal.value };

  await plausibleRequest("PUT", "/api/v1/sites/goals", apiKey, body);
}

// =============================================================================
// Handler
// =============================================================================

export async function cronPlausibleGoalsHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  created: number;
  skipped: number;
  existingCount: number;
}> {
  // --- Step 1: provision goals ---
  const result = await step.run("provision-plausible-goals", async () => {
    const apiKey = process.env.PLAUSIBLE_API_KEY;
    const siteId = process.env.PLAUSIBLE_SITE_ID;

    if (!apiKey || !siteId) {
      logger.info(
        { fn: "cron-plausible-goals" },
        "PLAUSIBLE_API_KEY or PLAUSIBLE_SITE_ID not set — skipping",
      );
      return { created: 0, skipped: CANONICAL_GOALS.length, existingCount: 0 };
    }

    // Preflight: check API plan access
    const existing = await listExistingGoals(apiKey, siteId);

    let created = 0;
    let skipped = 0;

    for (const goal of CANONICAL_GOALS) {
      if (goalExists(existing, goal)) {
        skipped++;
        continue;
      }

      try {
        await provisionGoal(apiKey, siteId, goal);
        logger.info(
          {
            fn: "cron-plausible-goals",
            goalType: goal.goal_type,
            value: goal.value,
          },
          "Goal provisioned",
        );
        created++;
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-plausible-goals",
          op: "provision-goal",
          message: `Failed to provision goal: ${goal.goal_type}/${goal.value}`,
          extra: {
            fn: "cron-plausible-goals",
            goalType: goal.goal_type,
            value: goal.value,
          },
        });
        // Continue provisioning remaining goals
      }
    }

    return { created, skipped, existingCount: existing.length };
  });

  // --- Step 2: Sentry heartbeat ---
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: true,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-plausible-goals",
      logger,
    });
  });

  return { ok: true, ...result };
}

// =============================================================================
// Registration
// =============================================================================

export const cronPlausibleGoals = inngest.createFunction(
  {
    id: "cron-plausible-goals",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 7 1 * *" },
    { event: "cron/plausible-goals.manual-trigger" },
  ],
  cronPlausibleGoalsHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
