import { describe, it, expect, vi, beforeEach } from "vitest";
import { makeRecordingEvents as makeEvents } from "./helpers/soleur-go-fixtures";

// #11599 — Guard 2 row 2 (soleur-go-runner queryFactory): a credential-lease refusal that the lease already reported
// (oauth_unusable, auth_mode_unresolved, auth_mode_unavailable) adds no second error-tracker event from the factory
// catch; the error is re-thrown so the dispatcher routes the honest client message. A real fetch_failed is still
// mirrored, and a non-lease error proves the spy is live.
const { mockReportSilentFallback } = vi.hoisted(() => ({ mockReportSilentFallback: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

import { createSoleurGoRunner } from "@/server/soleur-go-runner";
import { ByokLeaseError } from "@/server/byok-lease";

const factoryMirrors = () =>
  mockReportSilentFallback.mock.calls.filter(([, ctx]) => (ctx as { op?: string })?.op === "queryFactory");

async function dispatchRejectedBy(err: unknown) {
  const runner = createSoleurGoRunner({
    queryFactory: () => {
      throw err;
    },
  });
  await expect(
    runner.dispatch({
      persona: "command_center",
      conversationId: "conv-lease-refusal",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events: makeEvents(),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    }),
  ).rejects.toBe(err);
}

describe("soleur-go-runner queryFactory catch — lease refusals", () => {
  beforeEach(() => mockReportSilentFallback.mockClear());

  it.each(["oauth_unusable", "auth_mode_unresolved", "auth_mode_unavailable"] as const)(
    "%s: re-thrown with no factory mirror",
    async (cause) => {
      await dispatchRejectedBy(new ByokLeaseError(cause, "refused"));
      expect(factoryMirrors()).toHaveLength(0);
    },
  );

  it("positive control (the spy is live): a non-lease error IS mirrored", async () => {
    await dispatchRejectedBy(new Error("boom"));
    expect(factoryMirrors()).toHaveLength(1);
  });

  it("a real fetch_failed is still mirrored", async () => {
    await dispatchRejectedBy(new ByokLeaseError("fetch_failed", "boom"));
    expect(factoryMirrors()).toHaveLength(1);
  });
});
