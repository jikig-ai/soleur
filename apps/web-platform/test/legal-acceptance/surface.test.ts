/**
 * #12197: the founder surface gate. The card is offered only to the configured founder, and the `approval-queue` flag is not
 * read (CTO ruling, 2026-11-10, superseding ruling B's flag AND founder). Fails closed: an unset or malformed
 * `LEGAL_ACCEPTANCE_FOUNDER_ID` disables the surface for everyone. Unset is silent (the kill switch); malformed reports once.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ reports: [] as unknown[][], flag: vi.fn(async () => false) }));
// The flag is mocked OFF on purpose: the surface must not depend on it (P1). The old flag AND founder would close every case here.
vi.mock("@/server/approval/flag", () => ({
  isApprovalQueueEnabled: h.flag,
}));
vi.mock("@/server/approval/ops", () => ({
  reportLegalOp: (...args: unknown[]) => {
    h.reports.push(args);
  },
}));

import { isLegalSurfaceEnabled, legalFounderId, resetSurfaceConfigReport } from "@/server/legal-acceptance/surface";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const OTHER = "00000000-0000-4000-8000-0000000000bb";

beforeEach(() => {
  h.reports.length = 0;
  resetSurfaceConfigReport();
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

describe("isLegalSurfaceEnabled (founder id only)", () => {
  it("flag off and the user is the founder: STILL enabled (the case the old flag AND founder would break)", async () => {
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(true);
    expect(await isLegalSurfaceEnabled(OTHER)).toBe(false);
    expect(h.reports).toEqual([]);
    expect(h.flag).not.toHaveBeenCalled();
  });

  it("the module source imports nothing from the approval flag (a flag read cannot come back through an import)", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const src = readFileSync(resolve(__dirname, "../../server/legal-acceptance/surface.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:])\/\/.*$/gm, "$1");
    const imports = src.match(/^import .* from "([^"]+)";$/gm) ?? [];
    expect(imports.map((l) => l.replace(/^.* from "([^"]+)";$/, "$1")).sort()).toEqual(["@/lib/is-uuid", "@/server/approval/ops"]);
    expect(src).not.toMatch(/isApprovalQueueEnabled|approval\/flag|getFlag|flagsmith/i);
  });

  it("another user: disabled, and no report", async () => {
    expect(await isLegalSurfaceEnabled(OTHER)).toBe(false);
    expect(h.reports).toEqual([]);
  });

  it("the comparison ignores the case of the user id", async () => {
    expect(await isLegalSurfaceEnabled(FOUNDER.toUpperCase())).toBe(true);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", FOUNDER.toUpperCase());
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(true);
  });
});

describe("the config report (CTO ruling F1, 2026-11-10: unset silent, malformed once)", () => {
  const CONFIG_REPORT = [
    "storeFailed",
    null,
    { tags: { stage: "config" }, extra: { step: "config", variables: ["LEGAL_ACCEPTANCE_FOUNDER_ID"] } },
  ];

  it("the id unset (empty): closed for everyone, and NO report (the kill switch is the dark state)", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    for (const u of [FOUNDER, OTHER, FOUNDER]) expect(await isLegalSurfaceEnabled(u)).toBe(false);
    expect(h.reports).toEqual([]);
  });

  it("the id unset (undefined): closed for everyone, and NO report", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", undefined as unknown as string);
    for (const u of [FOUNDER, OTHER, FOUNDER]) expect(await isLegalSurfaceEnabled(u)).toBe(false);
    expect(h.reports).toEqual([]);
  });

  it("the id MALFORMED: closed for everyone, and exactly ONE config report across repeated calls", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    for (const u of [FOUNDER, OTHER, FOUNDER]) expect(await isLegalSurfaceEnabled(u)).toBe(false);
    expect(h.reports).toEqual([CONFIG_REPORT]);
  });

  it("an unset call first does not use up the one report a later malformed value raises", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(false);
    expect(h.reports).toEqual([]);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    expect(await isLegalSurfaceEnabled(FOUNDER)).toBe(false);
    expect(h.reports).toEqual([CONFIG_REPORT]);
  });

  it("the report carries neither the user id nor the variable's value, and re-arms after the reset seam", async () => {
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    await isLegalSurfaceEnabled(FOUNDER);
    expect(JSON.stringify(h.reports)).not.toContain(FOUNDER);
    expect(JSON.stringify(h.reports)).not.toContain("not-a-uuid");
    resetSurfaceConfigReport();
    await isLegalSurfaceEnabled(FOUNDER);
    expect(h.reports.length).toBe(2);
  });
});
