/**
 * #12197 (CTO ruling B, 2026-11-07): the founder surface gate. The `approval-queue` flag is global (identifier `role:prd`), so
 * the card is offered only to the configured founder. Fails closed: an unset or malformed `LEGAL_ACCEPTANCE_FOUNDER_ID`
 * disables the surface for everyone.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ flag: { value: true }, calls: [] as unknown[] }));
vi.mock("@/server/approval/flag", () => ({
  isApprovalQueueEnabled: async (id: unknown) => {
    h.calls.push(id);
    return h.flag.value;
  },
}));

import { isLegalSurfaceEnabled, legalFounderId } from "@/server/legal-acceptance/surface";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const OTHER = "00000000-0000-4000-8000-0000000000bb";

beforeEach(() => {
  h.flag.value = true;
  h.calls.length = 0;
  vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER);
});
afterEach(() => vi.unstubAllEnvs());

describe("legalFounderId", () => {
  it("is the configured UUID, lower-cased; null for unset, empty and malformed", () => {
    expect(legalFounderId()).toBe(FOUNDER);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER.toUpperCase());
    expect(legalFounderId()).toBe(FOUNDER);
    for (const bad of ["", "not-a-uuid", `${FOUNDER} `, "00000000-0000-4000-8000-0000000000a"]) {
      vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", bad);
      expect(legalFounderId(), JSON.stringify(bad)).toBeNull();
    }
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", undefined as unknown as string);
    expect(legalFounderId()).toBeNull();
  });
});

describe("isLegalSurfaceEnabled", () => {
  it("flag on and the user is the founder: enabled; the flag is read with no workspace", async () => {
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(true);
    expect(h.calls).toEqual([{ userId: FOUNDER, workspaceId: null }]);
  });

  it("flag on and another user: disabled (the case an OR instead of an AND would break)", async () => {
    expect(await isLegalSurfaceEnabled(OTHER)).toBe(false);
  });

  it("flag on, the variable unset or not a UUID: disabled for everyone, including the founder", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(false);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(false);
  });

  it("flag off and the variable equal: disabled", async () => {
    h.flag.value = false;
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(false);
  });

  it("flag off and another user: disabled", async () => {
    h.flag.value = false;
    expect(await isLegalSurfaceEnabled(OTHER)).toBe(false);
  });

  it("the comparison ignores the case of the user id", async () => {
    expect(await isLegalSurfaceEnabled(FOUNDER.toUpperCase())).toBe(true);
  });
});
