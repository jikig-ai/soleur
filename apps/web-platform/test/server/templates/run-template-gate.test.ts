/**
 * #10543 (CTO Q3) — runTemplateGate forwards `excludeActionSendId` to isTemplateAuthorized as the 5th
 * argument, and forwards nothing when the caller passes none. Both route test files mock runTemplateGate and
 * the predicate tests call isTemplateAuthorized directly, so this is the only test that sees the seam: dropping
 * the forwarded argument would deny a replay of the send that hit max_sends with template_quota_exhausted.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockIsTemplateAuthorized } = vi.hoisted(() => ({
  mockIsTemplateAuthorized: vi.fn(),
}));

vi.mock("@/server/templates/is-template-authorized", async (importOriginal) => {
  const actual =
    await importOriginal<
      typeof import("@/server/templates/is-template-authorized")
    >();
  return { ...actual, isTemplateAuthorized: mockIsTemplateAuthorized };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

import { runTemplateGate } from "@/server/templates/run-template-gate";

const BASE = {
  supabase: {} as never,
  founderId: "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
  founderIdHash: "founder-hash-stub",
  templateHash: "t".repeat(64),
  grantId: "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb",
  actionClass: "engineering.pr_review_pending",
  messageId: "11111111-1111-4111-aaaa-111111111111",
};

beforeEach(() => {
  vi.clearAllMocks();
  mockIsTemplateAuthorized.mockResolvedValue({ status: "authorized" });
});

describe("runTemplateGate → isTemplateAuthorized argument forwarding", () => {
  it("forwards excludeActionSendId as the 5th argument on a replay", async () => {
    const res = await runTemplateGate({
      ...BASE,
      excludeActionSendId: "44444444-4444-4444-aaaa-444444444444",
    });

    expect(res).toEqual({ kind: "allow" });
    expect(mockIsTemplateAuthorized).toHaveBeenCalledTimes(1);
    expect(mockIsTemplateAuthorized.mock.calls[0].slice(1)).toEqual([
      BASE.founderId,
      BASE.templateHash,
      BASE.grantId,
      "44444444-4444-4444-aaaa-444444444444",
    ]);
  });

  it("[guard] a fresh send forwards no exclusion (5th argument undefined)", async () => {
    await runTemplateGate(BASE);

    expect(mockIsTemplateAuthorized).toHaveBeenCalledTimes(1);
    expect(mockIsTemplateAuthorized.mock.calls[0][4]).toBeUndefined();
  });
});
