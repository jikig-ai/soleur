import { describe, it, expect, vi, beforeEach } from "vitest";

// Phase 5 (#4625): resolveGranteeAcceptanceStatus must surface the
// canonical server-owned version (so the UI can detect a stale acceptance)
// and the withdrawn state (a withdrawal post-dating the latest acceptance).

const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

import { resolveGranteeAcceptanceStatus } from "@/server/byok-delegation-ui-resolver";
import { BYOK_SIDE_LETTER_VERSION } from "@/server/byok-side-letter";

// Build a chainable query stub whose terminal `.maybeSingle()` resolves to
// the given row. Supports .select().eq().eq()[.order().limit()].maybeSingle()
function chain(row: unknown) {
  const obj: Record<string, unknown> = {};
  for (const m of ["select", "eq", "order", "limit"]) {
    obj[m] = vi.fn(() => obj);
  }
  obj.maybeSingle = vi.fn(async () => ({ data: row, error: null }));
  return obj;
}

function primeTables(opts: {
  acceptance: { accepted_at: string; side_letter_version: string } | null;
  withdrawal: { withdrawn_at: string } | null;
}) {
  mockFrom.mockImplementation((table: string) => {
    if (table === "byok_delegation_acceptances") return chain(opts.acceptance);
    if (table === "byok_delegation_withdrawals") return chain(opts.withdrawal);
    throw new Error(`unexpected from(${table})`);
  });
}

beforeEach(() => vi.clearAllMocks());

describe("resolveGranteeAcceptanceStatus (Phase 5)", () => {
  it("returns currentVersion = server constant and not-accepted when no row", async () => {
    primeTables({ acceptance: null, withdrawal: null });
    const s = await resolveGranteeAcceptanceStatus("u1", "d1");
    expect(s.accepted).toBe(false);
    expect(s.currentVersion).toBe(BYOK_SIDE_LETTER_VERSION);
    expect(s.withdrawn).toBe(false);
  });

  it("accepted, no withdrawal → withdrawn false", async () => {
    primeTables({
      acceptance: { accepted_at: "2026-05-20T00:00:00Z", side_letter_version: "1.0.0" },
      withdrawal: null,
    });
    const s = await resolveGranteeAcceptanceStatus("u1", "d1");
    expect(s.accepted).toBe(true);
    expect(s.sideLetterVersion).toBe("1.0.0");
    expect(s.withdrawn).toBe(false);
  });

  it("withdrawal newer than acceptance → withdrawn true", async () => {
    primeTables({
      acceptance: { accepted_at: "2026-05-20T00:00:00Z", side_letter_version: "1.0.0" },
      withdrawal: { withdrawn_at: "2026-05-21T00:00:00Z" },
    });
    const s = await resolveGranteeAcceptanceStatus("u1", "d1");
    expect(s.withdrawn).toBe(true);
  });

  it("re-acceptance newer than withdrawal → withdrawn false (non-terminal)", async () => {
    primeTables({
      acceptance: { accepted_at: "2026-05-22T00:00:00Z", side_letter_version: "1.0.0" },
      withdrawal: { withdrawn_at: "2026-05-21T00:00:00Z" },
    });
    const s = await resolveGranteeAcceptanceStatus("u1", "d1");
    expect(s.withdrawn).toBe(false);
  });
});
