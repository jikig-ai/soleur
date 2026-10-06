// #7122 — shared test support: a VALID one-line community draft.
//
// The flow / heartbeat / dedup / collector-status suites model the agent's final
// message with this helper instead of an issue the agent filed itself. It is
// built from the production metrics table, so a key added there appears here.

import {
  COMMUNITY_METRICS,
  COMMUNITY_PLATFORMS,
  type CommunityPlatform,
} from "@/server/inngest/functions/_cron-community-publication";

export type DraftOverrides = {
  periodDays?: unknown;
  platforms?: Partial<Record<CommunityPlatform, Record<string, unknown>>>;
  topics?: unknown;
  /** Extra top-level keys, merged last (used by rejection rows). */
  extra?: Record<string, unknown>;
};

export function validDraftObject(overrides: DraftOverrides = {}): Record<string, unknown> {
  const platforms: Record<string, unknown> = {};
  for (const p of COMMUNITY_PLATFORMS) {
    const metrics: Record<string, number> = {};
    for (const key of Object.keys(COMMUNITY_METRICS[p])) metrics[key] = 3;
    platforms[p] = { status: "collected", metrics, ...(overrides.platforms?.[p] ?? {}) };
  }
  return {
    periodDays: overrides.periodDays ?? 1,
    platforms,
    topics: overrides.topics ?? [
      { category: "infrastructure", count: 2 },
      { category: "other", count: 1 },
    ],
    ...(overrides.extra ?? {}),
  };
}

/** One line of compact JSON, exactly what the prompt asks the agent to emit. */
export function validDraftFinalMessage(overrides: DraftOverrides = {}): string {
  return JSON.stringify(validDraftObject(overrides));
}
